import Foundation
import SQLite3
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// Spike A contract anchors: digest-chain substitution of settled history at the
/// rendering layer (flag `SIMIGO_DIGEST_PREFIX_SUBSTITUTION`, default OFF).
///
/// Every assertion goes through the real dispatch:
///
///   signed HTTPS POST /v1/chat/completions
///     -> prepareInformationTurn (real ES demand + IS resolve + substitution)
///     -> generateHandler (a counter that captures the rendered messages)
///     -> settleInformationTurn (real settlement + flag-gated digest scheduling)
///
/// Anchors: default-OFF zero change · substitution correctness (ordered chain,
/// trunk/frontier intact) · fail-open gates (missing digest, ledger mismatch) ·
/// determinism · truth rows immutable · convergence (demand-keyed reuse survives
/// a substituted prefix) · live-turn ledger scheduling · live digest production
/// end-to-end through the real scheduler and its source verification.
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class DigestPrefixSubstitutionTests: XCTestCase {

    private let port = 59_383

    private var isolationRoot: URL!
    private var modelPath: String!
    private var host: LOCALBAuthorizedE2E.Host!
    private var stub: Stub!

    /// Intercepts the digest scheduler's model transport. Installed for the
    /// whole class and NEVER restored to .shared: a drain task that outlives a
    /// test must not be able to reach the real engine at 127.0.0.1:8000. After
    /// the last test the responder is a refusing guard, so any waking drain
    /// fails transiently against the stub instead of touching real state.
    private final class DigestStubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var responder: ((URLRequest) -> (Int, String))?
        override class func canInit(with request: URLRequest) -> Bool { responder != nil }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let responder = Self.responder, let url = request.url else { return }
            let (status, body) = responder(request)
            let http = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        private var _messages: [JSONValue] = []
        nonisolated(unsafe) var text = "DIGEST-SPIKE-SETTLED-ANSWER"
        nonisolated(unsafe) var completion: GenerationCompletion = .complete
        func bump(_ messages: [JSONValue]) {
            lock.withLock { _generate += 1; _messages = messages }
        }
        var generate: Int { lock.withLock { _generate } }
        var messages: [JSONValue] { lock.withLock { _messages } }
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "so no real model or user state is touched")
        }
        isolationRoot = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            ManagedPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoDigestPrefix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"digest-prefix-http-model-free-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        host = try LOCALBAuthorizedE2E.makeHost()
        stub = Stub()
        // No real engine contact, ever: the stub session refuses every digest
        // request unless a test arms a producing responder. A refused job fails
        // transiently and stays in the queue (observable), and the drain exits
        // instead of parking — a drain parked in waitForIdle captures the quiet
        // period at entry and would hold the single generation permit forever.
        TurnDigestScheduler.idleQuietPeriodForTesting = 0
        TurnDigestScheduler.admissionLivenessForTesting = { (active: 0, waiting: 0) }
        unsetenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION")
        DigestStubURLProtocol.responder = { _ in (503, "digest-stub-unarmed") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DigestStubURLProtocol.self]
        TurnDigestScheduler.completeSession = URLSession(configuration: config)
    }

    override func tearDown() async throws {
        unsetenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION")
        // Clear the flags FIRST: a drain still in flight holds activeKey/working
        // for a queue that is already empty, so the idle wait below would
        // otherwise block on it.
        TurnDigestScheduler.resetQueueForTesting()
        let drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(drained, "digest drain must release its worker ownership")
        // Keep liveness busy so any drain still inside waitForIdle parks instead
        // of waking into a request once the quiet period is restored. The stub
        // session stays installed with a refusing responder: restoring .shared
        // here would let a drain that is between waitForIdle and its request
        // reach the real engine at 127.0.0.1:8000.
        TurnDigestScheduler.admissionLivenessForTesting = { (active: 1, waiting: 0) }
        TurnDigestScheduler.idleQuietPeriodForTesting = nil
        DigestStubURLProtocol.responder = { _ in (503, "digest-stub-teardown-guard") }
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        stub = nil
        host = nil
        try await super.tearDown()
    }

    // MARK: - Server + real authorized request

    @MainActor
    private func withServer(_ run: () async throws -> Void) async throws {
        let stub = self.stub!
        let identity = ProducerIdentity.identity(fromPath: modelPath)
        let server = HTTPServer(
            port: port,
            modelId: "digest-prefix-http-test",
            generateHandler: { _, _, _, _, messages, _, _, onChunk, _, _ in
                stub.bump(messages)
                onChunk(stub.text)
                return GenerationResult(text: stub.text, usage: nil, completion: stub.completion)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "digest-prefix-http-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _, _ in
                BranchDeletionOutcome(
                    deletedBranch: "", hadLiveSession: false,
                    hadCheckpointFile: false, generation: 1,
                    remainingLiveBranches: [], remainingCheckpointBranches: [])
            },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            informationTurnProducer: {
                InformationTurnProducer(
                    modelIdentity: identity.model, identity: identity)
            }
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer { server.stop() }
        try await run()
    }

    private func executeDatabaseSQL(_ sql: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open_v2(
            ManagedPaths.databaseURL.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard openRC == SQLITE_OK, let handle else {
            throw NSError(domain: "DigestPrefixSubstitutionTests", code: Int(openRC))
        }
        defer { sqlite3_close_v2(handle) }
        // The live app and the digest drain write concurrently; the product's
        // own connections wait on locks (busy_timeout=5000), so must these.
        sqlite3_busy_timeout(handle, 5000)
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        guard rc == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(error)
            throw NSError(domain: "DigestPrefixSubstitutionTests", code: Int(rc),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func queryRows(_ sql: String) throws -> [[String]] {
        var handle: OpaquePointer?
        let openRC = sqlite3_open_v2(
            ManagedPaths.databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard openRC == SQLITE_OK, let handle else {
            throw NSError(domain: "DigestPrefixSubstitutionTests", code: Int(openRC))
        }
        defer { sqlite3_close_v2(handle) }
        sqlite3_busy_timeout(handle, 5000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "DigestPrefixSubstitutionTests", code: -1)
        }
        defer { sqlite3_finalize(stmt) }
        var rows: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String] = []
            for i in 0..<sqlite3_column_count(stmt) {
                row.append(sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "NULL")
            }
            rows.append(row)
        }
        return rows
    }

    @MainActor
    private func dispatch(
        session: String, messages: [[String: Any]]
    ) async throws -> (status: Int, body: [String: Any]) {
        let body: [String: Any] = [
            "model": "digest-prefix-http-test",
            "messages": messages,
            "session_id": session,
            "stream": false,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let result = try await LOCALBAuthorizedE2E.send(
            host: host, port: port, method: "POST",
            path: "/v1/chat/completions",
            contentType: "application/json", body: payload)
        let object = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any] ?? [:]
        return (result.1.statusCode, object)
    }

    private func user(_ text: String) -> [String: Any] {
        ["role": "user", "content": text]
    }

    private func assistant(_ text: String) -> [String: Any] {
        ["role": "assistant", "content": text]
    }

    private let system: [String: Any] = [
        "role": "system", "content": "DIGEST-SPIKE-TRUNK-SYSTEM",
    ]

    private static func modelBody(_ content: String) -> String {
        let object: [String: Any] = [
            "choices": [["message": ["role": "assistant", "content": content]]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    private func seedDigest(session: String, turn: Int, text: String) throws {
        try executeDatabaseSQL("""
        INSERT INTO turn_digests(session_id, turn_index, digest, keywords, model, created_at)
        VALUES('\(session)', \(turn), '\(text)', 'kw', 'test', '816900000.0');
        """)
    }

    private func renderedTexts(_ messages: [JSONValue]) -> [String] {
        messages.map { $0.object?["content"]?.messageText ?? "" }
    }

    // MARK: - Anchors

    /// Default OFF: the rendered history keeps the original turn text and the
    /// live settlement writes no ledger row — zero behavior change.
    func testFlagOffKeepsOriginalHistoryAndLedger() async throws {
        let session = "off-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-OFF")])
            let history: [[String: Any]] = [
                self.system, self.user("Q1-OFF"), self.assistant("A1-OFF"), self.user("Q2-OFF"),
            ]
            _ = try await self.dispatch(session: session, messages: history)
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 4)
            XCTAssertEqual(rendered[0], "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertTrue(rendered[1].hasPrefix("Q1-OFF"))
            XCTAssertEqual(rendered[2], "A1-OFF")
            XCTAssertTrue(rendered[3].hasPrefix("Q2-OFF"))
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn") })
            let ledger = try self.queryRows(
                "SELECT COUNT(*) FROM chat_turn_ledger WHERE session_id='\(session)';")
            XCTAssertEqual(ledger, [["0"]])
        }
    }

    /// ON: settled history renders as the ordered digest chain; trunk and
    /// frontier stay; the live settlement recorded ledger turn 1 and queued it.
    func testFlagOnSubstitutesSettledHistory() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "on-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-ON")])
            let ledger = try self.queryRows("""
            SELECT turn_index, request_id FROM chat_turn_ledger
            WHERE session_id='\(session)' ORDER BY turn_index;
            """)
            XCTAssertEqual(ledger.count, 1)
            XCTAssertEqual(ledger[0][0], "1")
            XCTAssertTrue(ledger[0][1].hasPrefix("live-"))
            XCTAssertGreaterThanOrEqual(TurnDigestScheduler.pendingDepth, 1)

            try self.seedDigest(session: session, turn: 1, text: "DIGEST-ONE-TEXT")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-ON"), self.assistant("A1-ON"), self.user("Q2-ON"),
            ])
            let rendered = self.stub.messages
            XCTAssertEqual(rendered.count, 3)
            XCTAssertEqual(rendered[0].object?["content"]?.messageText, "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertEqual(rendered[1].object?["role"]?.string, "user")
            XCTAssertEqual(
                rendered[1].object?["content"]?.messageText,
                "[Earlier turn t1 digest] DIGEST-ONE-TEXT")
            XCTAssertTrue(
                (rendered[2].object?["content"]?.messageText ?? "").hasPrefix("Q2-ON"))
            XCTAssertFalse(self.renderedTexts(rendered).contains { $0 == "A1-ON" })
        }
    }

    /// ON but the ledger turn has no digest yet: fail open to the original text.
    func testMissingDigestFallsBackToOriginal() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "gap-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-GAP")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-GAP"), self.assistant("A1-GAP"), self.user("Q2-GAP"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 4)
            XCTAssertTrue(rendered[1].hasPrefix("Q1-GAP"))
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn") })
        }
    }

    /// ON but the ledger knows more turns than the client history carries:
    /// the mapping is unverifiable, so the original rendering stands.
    func testLedgerHistoryMismatchFallsBack() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "mismatch-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-MM")])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-MM-ONE")
            try self.executeDatabaseSQL("""
            INSERT INTO chat_turn_ledger(session_id, turn_index, request_id, seen_at)
            VALUES('\(session)', 2, 'external-2', '816900000.0');
            """)
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-MM"), self.assistant("A1-MM"), self.user("Q2-MM"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 4)
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn") })
        }
    }

    /// Same stored state + same request shape renders byte-identical twice.
    /// `.capped` keeps the requests from settling, so the gate inputs do not move.
    func testSubstitutedRenderingIsDeterministic() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "det-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-DET")])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-DET-ONE")
            self.stub.completion = .capped
            let history: [[String: Any]] = [
                self.system, self.user("Q1-DET"), self.assistant("A1-DET"), self.user("Q2-DET"),
            ]
            _ = try await self.dispatch(session: session, messages: history)
            let first = self.stub.messages
            _ = try await self.dispatch(session: session, messages: history)
            let second = self.stub.messages
            XCTAssertEqual(first, second)
            XCTAssertTrue(self.renderedTexts(first).contains { $0.contains("[Earlier turn t1 digest]") })
        }
    }

    /// Rendering never rewrites existing truth rows: chat_messages / is_objects
    /// rows present before the request are byte-identical after it, and the
    /// digest/ledger tables are untouched by a non-settling substituted request.
    func testSubstitutionDoesNotMutateExistingTruthRows() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "truth-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-TRUTH")])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-TRUTH-ONE")
            let cutoff = try self.queryRows("SELECT COALESCE(MAX(id),0) FROM chat_messages;")[0][0]
            let objectCutoff = try self.queryRows("SELECT COALESCE(MAX(created_order),0) FROM is_objects;")[0][0]
            let messagesBefore = try self.queryRows("""
            SELECT id, session_id, role, content, content_object_id, turn_state
            FROM chat_messages WHERE id <= \(cutoff) ORDER BY id;
            """)
            let objectsBefore = try self.queryRows("""
            SELECT object_id, byte_size, length(content) FROM is_objects
            WHERE created_order <= \(objectCutoff) ORDER BY created_order;
            """)
            let digestsBefore = try self.queryRows(
                "SELECT session_id, turn_index, digest FROM turn_digests ORDER BY session_id, turn_index;")
            let ledgerBefore = try self.queryRows(
                "SELECT session_id, turn_index, request_id FROM chat_turn_ledger ORDER BY session_id, turn_index;")

            self.stub.completion = .capped
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-TRUTH"), self.assistant("A1-TRUTH"), self.user("Q2-TRUTH"),
            ])
            XCTAssertTrue(self.renderedTexts(self.stub.messages).contains { $0.contains("[Earlier turn") })

            XCTAssertEqual(try self.queryRows("""
            SELECT id, session_id, role, content, content_object_id, turn_state
            FROM chat_messages WHERE id <= \(cutoff) ORDER BY id;
            """), messagesBefore)
            XCTAssertEqual(try self.queryRows("""
            SELECT object_id, byte_size, length(content) FROM is_objects
            WHERE created_order <= \(objectCutoff) ORDER BY created_order;
            """), objectsBefore)
            XCTAssertEqual(try self.queryRows(
                "SELECT session_id, turn_index, digest FROM turn_digests ORDER BY session_id, turn_index;"),
                digestsBefore)
            XCTAssertEqual(try self.queryRows(
                "SELECT session_id, turn_index, request_id FROM chat_turn_ledger ORDER BY session_id, turn_index;"),
                ledgerBefore)
        }
    }

    /// Convergence: an answer settled under a substituted prefix stays reusable
    /// by a later request whose rendering fell back to the original history —
    /// the demand key never saw the rendering at all.
    func testConvergencePreservedUnderSubstitution() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "conv-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-CONV")])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-CONV-ONE")
            let second = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-CONV"), self.assistant("A1-CONV"), self.user("Q2-CONV"),
            ])
            XCTAssertEqual(second.status, 200)
            XCTAssertTrue(self.renderedTexts(self.stub.messages).contains { $0.contains("[Earlier turn") })
            XCTAssertEqual(self.stub.generate, 2)

            let third = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-CONV"), self.assistant("A1-CONV"),
                self.user("Q2-CONV"), self.assistant(self.stub.text), self.user("Q2-CONV"),
            ])
            XCTAssertEqual(third.status, 200)
            XCTAssertEqual(self.stub.generate, 2, "the repeated demand must reuse, not generate")
            let choices = third.body["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            XCTAssertEqual(message?["content"] as? String, self.stub.text)
        }
    }

    /// The live hook records one contiguous ledger turn per settled genuine
    /// question — not per request, not per tool-loop leg.
    func testLiveSettlementsRecordContiguousLedgerTurns() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "ledger-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-L")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-L"), self.assistant("A1-L"), self.user("Q2-L"),
            ])
            let ledger = try self.queryRows("""
            SELECT turn_index FROM chat_turn_ledger
            WHERE session_id='\(session)' ORDER BY turn_index;
            """)
            XCTAssertEqual(ledger, [["1"], ["2"]])
        }
    }

    /// End-to-end production: a settled live turn is digested by the REAL
    /// scheduler (only the model transport is stubbed), the write passes the
    /// ledger source verification — which requires the user and assistant chat
    /// rows to be paired by the ledger's request_id — and the next request
    /// renders that produced digest. No raw-SQL digest seeding anywhere: this
    /// is the anchor that catches a live write path the seeded anchors cannot.
    func testLiveDigestProductionWritesThroughScheduler() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "e2e-\(UUID().uuidString)"
        // Arm the stub: from here the real drain produces digests.
        DigestStubURLProtocol.responder = { _ in
            (200, Self.modelBody("摘要：LIVE-PRODUCED-DIGEST\n关键词：活轮 摘要"))
        }
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-E2E")])
            // The fix under test: both chat rows carry the ledger request_id.
            let pairs = try self.queryRows("""
            SELECT request_id, COUNT(*) FROM chat_messages
            WHERE session_id='\(session)' AND request_id IS NOT NULL
            GROUP BY request_id;
            """)
            XCTAssertEqual(pairs.count, 1, "one request_id pairs the turn's two rows")
            XCTAssertEqual(pairs[0][1], "2")
            XCTAssertTrue(pairs[0][0].hasPrefix("live-"))

            var produced: [[String]] = []
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                produced = try self.queryRows("""
                SELECT digest FROM turn_digests
                WHERE session_id='\(session)' AND turn_index=1;
                """)
                if !produced.isEmpty { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertEqual(produced, [["LIVE-PRODUCED-DIGEST"]],
                           "the scheduler must write through source verification, not be refused by unpaired rows")

            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-E2E"), self.assistant("A1-E2E"), self.user("Q2-E2E"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertTrue(rendered.contains("[Earlier turn t1 digest] LIVE-PRODUCED-DIGEST"),
                          "the produced digest must render without any seeded rows")
            // Let the drain finish turn 2 before teardown so no job is in
            // flight when the class-level guards go up.
            let drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
            XCTAssertTrue(drained, "the live drain must go idle before teardown")
        }
    }
}
