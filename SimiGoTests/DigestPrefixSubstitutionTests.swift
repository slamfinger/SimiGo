import Foundation
import SQLite3
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// Spike A contract anchors: digest-chain substitution of settled history at the
/// rendering layer (flag `SIMIGO_DIGEST_PREFIX_SUBSTITUTION`, product default ON
/// since owner 2026-11-23; tests arm an explicit OFF baseline in setUp).
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
    private var requestAdmission: RequestAdmissionScheduler?

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
        private var _digestGenerate = 0
        private var _digestMessages: [JSONValue] = []
        private var _holdNextGeneration = false
        private var _generationHeld = false
        private var _heldContinuation: CheckedContinuation<Void, Never>?
        nonisolated(unsafe) var text = "DIGEST-SPIKE-SETTLED-ANSWER"
        nonisolated(unsafe) var completion: GenerationCompletion = .complete
        /// Warm-digest lane output. Default is NOT digest format, so the
        /// existing anchors keep exercising the fail-open fallback path;
        /// warm-success tests arm a producing value.
        nonisolated(unsafe) var digestText = "DIGEST-SPIKE-SETTLED-ANSWER"
        nonisolated(unsafe) var digestDelay: TimeInterval = 0
        func bump(_ messages: [JSONValue]) {
            lock.withLock { _generate += 1; _messages = messages }
        }
        func bumpDigest(_ messages: [JSONValue]) {
            lock.withLock { _digestGenerate += 1; _digestMessages = messages }
        }
        var generate: Int { lock.withLock { _generate } }
        var messages: [JSONValue] { lock.withLock { _messages } }
        var digestGenerate: Int { lock.withLock { _digestGenerate } }
        var digestMessages: [JSONValue] { lock.withLock { _digestMessages } }
        func holdNextGeneration() { lock.withLock { _holdNextGeneration = true } }
        var generationHeld: Bool { lock.withLock { _generationHeld } }
        func holdGeneration() async {
            let shouldHold = lock.withLock { () -> Bool in
                guard _holdNextGeneration else { return false }
                _holdNextGeneration = false
                return true
            }
            guard shouldHold else { return }
            await withCheckedContinuation { continuation in
                lock.withLock {
                    _heldContinuation = continuation
                    _generationHeld = true
                }
            }
        }
        func releaseHeldGeneration() {
            lock.withLock {
                _heldContinuation?.resume()
                _heldContinuation = nil
                _generationHeld = false
            }
        }
    }

    private final class DiagnosticCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        func append(_ line: String) {
            lock.withLock { storage.append(line) }
        }
        var lines: [String] { lock.withLock { storage } }
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
        // Explicit OFF baseline for tests (product default is ON since owner
        // 2026-11-23 ruling); ON-arm tests setenv "1" below. Decouples the
        // test baseline from the product default so both stay testable.
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "0", 1)
        unsetenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS")
        MessageSignatureDiagnostics.sink = nil
        unsetenv("SIMIGO_DIGEST_COMPACTION_KEEP")
        unsetenv("SIMIGO_DIGEST_COMPACTION_BUDGET_CHARS")
        unsetenv("SIMIGO_DIGEST_COMPACTION_TRIGGER_TURNS")
        unsetenv("SIMIGO_DIGEST_COMPACTION_TRIGGER_CHARS")
        DigestStubURLProtocol.responder = { _ in (503, "digest-stub-unarmed") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DigestStubURLProtocol.self]
        TurnDigestScheduler.completeSession = URLSession(configuration: config)
    }

    override func tearDown() async throws {
        MessageSignatureDiagnostics.sink = nil
        requestAdmission = nil
        unsetenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS")
        unsetenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION")
        unsetenv("SIMIGO_DIGEST_COMPACTION_KEEP")
        unsetenv("SIMIGO_DIGEST_COMPACTION_BUDGET_CHARS")
        unsetenv("SIMIGO_DIGEST_COMPACTION_TRIGGER_TURNS")
        unsetenv("SIMIGO_DIGEST_COMPACTION_TRIGGER_CHARS")
        // Clear the flags FIRST: a drain still in flight holds activeKey/working
        // for a queue that is already empty, so the idle wait below would
        // otherwise block on it.
        TurnDigestScheduler.resetQueueForTesting()
        let drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(drained, "digest drain must release its worker ownership")
        HTTPServer.warmDigestTimeoutForTesting = nil
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
            generateHandler: { _, _, sessionId, _, messages, _, _, onChunk, _, _ in
                // The warm-digest lane is a separate engine session: count it
                // separately so chat-generation anchors stay exact, and never
                // let its prompt overwrite the captured chat rendering.
                if sessionId == "simigo-turn-digest" {
                    stub.bumpDigest(messages)
                    if stub.digestDelay > 0 {
                        try? await Task.sleep(
                            nanoseconds: UInt64(stub.digestDelay * 1_000_000_000))
                    }
                    onChunk(stub.digestText)
                    return GenerationResult(
                        text: stub.digestText, usage: nil, completion: .complete)
                }
                stub.bump(messages)
                await stub.holdGeneration()
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
            },
            requestAdmission: requestAdmission
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
        session: String, messages: [[String: Any]], tools: [[String: Any]]? = nil
    ) async throws -> (status: Int, body: [String: Any]) {
        var body: [String: Any] = [
            "model": "digest-prefix-http-test",
            "messages": messages,
            "session_id": session,
            "stream": false,
        ]
        if let tools { body["tools"] = tools }
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
        // UPSERT: a folded reuse turn may already have inherited a digest
        // zero-call (fix A); seeding overrides it rather than colliding.
        try executeDatabaseSQL("""
        INSERT INTO turn_digests(session_id, turn_index, digest, keywords, model, created_at)
        VALUES('\(session)', \(turn), '\(text)', 'kw', 'test', '816900000.0')
        ON CONFLICT(session_id, turn_index) DO UPDATE SET
            digest=excluded.digest, keywords=excluded.keywords,
            model=excluded.model, created_at=excluded.created_at;
        """)
    }

    private func renderedTexts(_ messages: [JSONValue]) -> [String] {
        messages.map { $0.object?["content"]?.messageText ?? "" }
    }

    /// The warm digest runs AFTER the response bytes reach the client (the
    /// handler holds the permit until it finishes), so a dispatch returning
    /// does not mean the warm write landed. Poll instead of racing it.
    private func waitUntil(
        _ what: String, timeout: TimeInterval = 5,
        _ predicate: () throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try predicate() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("timed out waiting for \(what)")
    }

    private func diagnosticPayloads(_ lines: [String]) -> [[String: Any]] {
        lines.compactMap { line in
            guard line.hasPrefix("[MSG_SIG] ") else { return nil }
            let json = String(line.dropFirst("[MSG_SIG] ".count))
            return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
        }
    }

    func testMessageSignatureDiagnosticsOffEmitsNothing() async throws {
        let collector = DiagnosticCollector()
        MessageSignatureDiagnostics.sink = { collector.append($0) }
        unsetenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS")
        let session = "msg-sig-off-\(UUID().uuidString)"
        try await withServer {
            let response = try await self.dispatch(
                session: session, messages: [self.system, self.user("Q-MSG-SIG-OFF")])
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(self.renderedTexts(self.stub.messages).count, 2)
        }
        XCTAssertTrue(collector.lines.isEmpty)
    }

    func testMessageSignatureDiagnosticsHTTPStagesArePrivateAndCorrelated() async throws {
        let collector = DiagnosticCollector()
        MessageSignatureDiagnostics.sink = { collector.append($0) }
        setenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS", "1", 1)
        let session = "msg-sig-http-\(UUID().uuidString)"
        let tools: [[String: Any]] = [[
            "type": "function",
            "function": [
                "name": "private_tool",
                "description": "PRIVATE-TOOL-SCHEMA",
                "parameters": [
                    "type": "object",
                    "properties": ["token": ["type": "string", "description": "PRIVATE-TOOL-ARG"]],
                ],
            ],
        ]]
        try await withServer {
            let response = try await self.dispatch(
                session: session,
                messages: [
                    self.system,
                    self.user("PRIVATE-OLD-QUESTION"),
                    [
                        "role": "assistant",
                        "content": "PRIVATE-ASSISTANT",
                        "tool_calls": [[
                            "id": "call-private",
                            "type": "function",
                            "function": ["name": "private_tool", "arguments": "{\"token\":\"PRIVATE-TOOL-ARG\"}"],
                        ]],
                    ],
                    ["role": "tool", "tool_call_id": "call-private", "content": "PRIVATE-TOOL-RESULT"],
                    self.user("PRIVATE-CURRENT-QUESTION"),
                ],
                tools: tools)
            XCTAssertEqual(response.status, 200)
        }
        let payloads = diagnosticPayloads(collector.lines)
        XCTAssertEqual(payloads.compactMap { $0["stage"] as? String }, [
            "B0", "B1", "B2", "B3", "B4", "B5", "B6",
        ])
        let requestIDs = Set(payloads.compactMap { $0["request_id"] as? String })
        XCTAssertEqual(requestIDs.count, 1)
        let sessionFingerprints = Set(payloads.compactMap { $0["session_fingerprint"] as? String })
        XCTAssertEqual(sessionFingerprints.count, 1)
        XCTAssertEqual(sessionFingerprints.first?.count, 12)
        let logged = collector.lines.joined(separator: "\n")
        for marker in [
            "PRIVATE-OLD-QUESTION", "PRIVATE-ASSISTANT", "PRIVATE-TOOL-RESULT",
            "PRIVATE-CURRENT-QUESTION", "PRIVATE-TOOL-SCHEMA", "PRIVATE-TOOL-ARG", "call-private",
        ] {
            XCTAssertFalse(logged.contains(marker), "diagnostic leaked \(marker)")
        }
        let b0 = try XCTUnwrap(payloads.first)
        XCTAssertEqual((b0["tool_schema_sha256"] as? String)?.count, 64)
        let b0Messages = b0["messages"] as? [[String: Any]] ?? []
        let assistantSignature = try XCTUnwrap(b0Messages.first { $0["role"] as? String == "assistant" })
        XCTAssertEqual((assistantSignature["tool_identity_sha256"] as? String)?.count, 64)
        let b3 = try XCTUnwrap(payloads.first { $0["stage"] as? String == "B3" })
        XCTAssertEqual(b3["applied"] as? Bool, false)
        let b4 = try XCTUnwrap(payloads.first { $0["stage"] as? String == "B4" })
        XCTAssertEqual(b4["missing"] as? Bool, nil)
    }

    func testMessageSignatureDiagnosticsStabilityNormalizationAndMetrics() async throws {
        XCTAssertFalse(MessageSignatureDiagnostics.isCurrentChatRequest("req-outside"))
        await MessageSignatureDiagnostics.$chatRequestID.withValue("req-scoped") {
            XCTAssertTrue(MessageSignatureDiagnostics.isCurrentChatRequest("req-scoped"))
            XCTAssertFalse(MessageSignatureDiagnostics.isCurrentChatRequest("req-other"))
        }
        XCTAssertFalse(MessageSignatureDiagnostics.isCurrentChatRequest("req-scoped"))
        let collector = DiagnosticCollector()
        MessageSignatureDiagnostics.sink = { collector.append($0) }
        setenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS", "1", 1)
        let messages: [JSONValue] = [
            .object(["role": .string("user"), "content": .array([
                .object(["type": .string("text"), "text": .string("PRIVATE-MULTIPART")])
            ])]),
            .object(["role": .string("assistant"), "content": .string("PRIVATE-ANSWER")]),
        ]
        MessageSignatureDiagnostics.record(
            stage: "B0", requestID: "req-stable", messages: messages)
        MessageSignatureDiagnostics.record(
            stage: "B0", requestID: "req-stable", messages: messages)
        var changed = messages
        changed[1] = .object(["role": .string("assistant"), "content": .string("PRIVATE-CHANGED")])
        MessageSignatureDiagnostics.record(
            stage: "B1", requestID: "req-stable", messages: changed, previousMessages: messages)
        MessageSignatureDiagnostics.recordNormalized(
            requestID: "req-stable", sessionID: "session-private",
            messages: [.init(role: "user", content: "PRIVATE-MULTIPART", hasTool: false)],
            previousMessages: [messages[0]], fields: ["route": "cold_rebuild"])
        MessageSignatureDiagnostics.recordMetrics(
            requestID: "req-stable", sessionID: "session-private",
            promptTokens: 123, cacheHitTokens: 45, generationTokens: 6,
            cacheTokensBefore: 40, cacheEfficiency: 0.36, reuseMode: "rebuild",
            ttftSeconds: 1.2, promptSeconds: 0.8, deltaMessages: 1,
            reused: false, completion: "complete", forkCommonTokens: 12,
            forkLedgerTokens: 20, route: "trim_fork", kvStrategy: "affine4")
        MessageSignatureDiagnostics.recordMissing(
            stage: "B6", requestID: "req-reuse", sessionID: "session-private",
            reason: "answer_reuse", previousStage: "B5")

        let payloads = diagnosticPayloads(collector.lines)
        let first = try XCTUnwrap(payloads.first)
        let second = try XCTUnwrap(payloads.dropFirst().first)
        XCTAssertEqual(
            first["message_sequence_sha256"] as? String,
            second["message_sequence_sha256"] as? String)
        let b1 = try XCTUnwrap(payloads.first { $0["stage"] as? String == "B1" })
        XCTAssertEqual(b1["first_difference_index"] as? Int, 1)
        let b5 = try XCTUnwrap(payloads.first { $0["stage"] as? String == "B5" })
        XCTAssertTrue(b5["first_content_difference_index"] is NSNull)
        let b6 = try XCTUnwrap(payloads.first {
            $0["stage"] as? String == "B6" && $0["request_id"] as? String == "req-stable"
        })
        XCTAssertEqual(b6["cache_hit_tokens"] as? Int, 45)
        XCTAssertEqual(b6["route"] as? String, "trim_fork")
        let missing = try XCTUnwrap(payloads.first { $0["request_id"] as? String == "req-reuse" })
        XCTAssertEqual(missing["missing"] as? Bool, true)
        let logged = collector.lines.joined(separator: "\n")
        for marker in ["PRIVATE-MULTIPART", "PRIVATE-ANSWER", "PRIVATE-CHANGED", "session-private"] {
            XCTAssertFalse(logged.contains(marker), "diagnostic leaked \(marker)")
        }
    }

    func testMessageSignatureDiagnosticsNormalizedSourceDetectsToolMutation() throws {
        let collector = DiagnosticCollector()
        MessageSignatureDiagnostics.sink = { collector.append($0) }
        setenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS", "1", 1)
        func source(_ arguments: String) -> JSONValue {
            .object([
                "role": .string("assistant"),
                "content": .string("PRIVATE-TOOL-NARRATION"),
                "tool_calls": .array([.object([
                    "id": .string("PRIVATE-CALL-ID"),
                    "function": .object([
                        "name": .string("private_tool"),
                        "arguments": .string(arguments),
                    ]),
                ])]),
            ])
        }
        let original = source("{\"token\":\"PRIVATE-ARG-A\"}")
        let mutated = source("{\"token\":\"PRIVATE-ARG-B\"}")
        let originalIncoming = NativeMLX.makeChatMessages([original])
        let echo = NativeMLX.normalizeToolEcho([mutated], against: [original])
        XCTAssertEqual(echo.replacedCalls, 1)
        XCTAssertEqual(echo.messages, [original])
        let normalizedIncoming = NativeMLX.makeChatMessages(echo.messages)
        let normalized = NativeMLX.diagnosticNormalizedMessages(
            sourceMessages: [original], incoming: originalIncoming)
        let mutatedNormalized = NativeMLX.diagnosticNormalizedMessages(
            sourceMessages: [mutated], incoming: normalizedIncoming)
        XCTAssertEqual(normalized.first?.content, mutatedNormalized.first?.content)
        XCTAssertEqual(normalized.first?.hasTool, mutatedNormalized.first?.hasTool)
        MessageSignatureDiagnostics.recordNormalized(
            requestID: "req-tool-a", sessionID: "session-private",
            messages: normalized, previousMessages: [original])
        MessageSignatureDiagnostics.recordNormalized(
            requestID: "req-tool-b", sessionID: "session-private",
            messages: mutatedNormalized, previousMessages: [original])
        let payloads = diagnosticPayloads(collector.lines)
        let first = try XCTUnwrap(payloads.first)
        let second = try XCTUnwrap(payloads.dropFirst().first)
        XCTAssertTrue(first["first_content_difference_index"] is NSNull)
        XCTAssertTrue(second["first_content_difference_index"] is NSNull)
        XCTAssertEqual(second["first_source_difference_index"] as? Int, 0)
        let firstMessage = try XCTUnwrap((first["messages"] as? [[String: Any]])?.first)
        let secondMessage = try XCTUnwrap((second["messages"] as? [[String: Any]])?.first)
        XCTAssertEqual(secondMessage["changed"] as? Bool, true)
        XCTAssertNotEqual(
            firstMessage["source_structure_sha256"] as? String,
            secondMessage["source_structure_sha256"] as? String)
        XCTAssertNotEqual(
            first["message_sequence_sha256"] as? String,
            second["message_sequence_sha256"] as? String)
        let logged = collector.lines.joined(separator: "\n")
        for marker in ["PRIVATE-ARG-A", "PRIVATE-ARG-B", "PRIVATE-CALL-ID", "PRIVATE-TOOL-NARRATION"] {
            XCTAssertFalse(logged.contains(marker), "diagnostic leaked \(marker)")
        }
    }

    func testMessageSignatureDiagnosticsEarlyExitUsesCanonicalSessionFingerprint() async throws {
        let collector = DiagnosticCollector()
        MessageSignatureDiagnostics.sink = { collector.append($0) }
        setenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS", "1", 1)
        let canonicalSession = "canonical-early-exit-session"
        let engineSession = "codex-thread:" + String(repeating: "x", count: 116)
        await MessageSignatureDiagnostics.scoped(
            requestID: "req-canonical-exit", sessionID: canonicalSession
        ) {
            MessageSignatureDiagnostics.recordMissing(
                stage: "B5", requestID: "req-canonical-exit", sessionID: engineSession,
                reason: "generation_exited_before_incoming", previousStage: "B4")
            MessageSignatureDiagnostics.recordMetrics(
                requestID: "req-canonical-exit", sessionID: engineSession,
                promptTokens: nil, cacheHitTokens: nil, generationTokens: nil,
                cacheTokensBefore: nil, cacheEfficiency: nil, reuseMode: nil,
                ttftSeconds: nil, promptSeconds: nil, deltaMessages: 0,
                reused: false, completion: "unconfirmed", forkCommonTokens: nil,
                forkLedgerTokens: nil, route: "cold_rebuild", kvStrategy: nil)
        }
        let payloads = diagnosticPayloads(collector.lines).filter {
            $0["request_id"] as? String == "req-canonical-exit"
        }
        let expected = try XCTUnwrap(MessageSignatureDiagnostics.fingerprint(canonicalSession))
        XCTAssertEqual(expected.count, 12)
        XCTAssertFalse(payloads.isEmpty)
        for payload in payloads {
            XCTAssertEqual(payload["session_fingerprint"] as? String, expected)
        }
        let logged = collector.lines.joined(separator: "\n")
        XCTAssertFalse(logged.contains(canonicalSession))
        XCTAssertFalse(logged.contains(engineSession))
    }

    func testMessageSignatureDiagnosticsEarlyExitRecordsMissingStages() async throws {
        let collector = DiagnosticCollector()
        MessageSignatureDiagnostics.sink = { collector.append($0) }
        setenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS", "1", 1)
        try await withServer {
            let payload = try JSONSerialization.data(withJSONObject: [
                "model": "digest-prefix-http-test", "messages": [], "stream": false,
            ])
            let result = try await LOCALBAuthorizedE2E.send(
                host: host, port: port, method: "POST",
                path: "/v1/chat/completions",
                contentType: "application/json", body: payload)
            XCTAssertEqual(result.1.statusCode, 400)
        }
        let payloads = diagnosticPayloads(collector.lines)
        XCTAssertEqual(payloads.compactMap { $0["stage"] as? String }, [
            "B0", "B1", "B2", "B3", "B4", "B5", "B6",
        ])
        XCTAssertEqual(Set(payloads.compactMap { $0["session_fingerprint"] as? String }).count, 1)
        for payload in payloads.dropFirst() {
            XCTAssertEqual(payload["missing"] as? Bool, true)
            XCTAssertEqual(payload["reason"] as? String, "invalid_chat_payload")
        }
        XCTAssertEqual(self.stub.generate, 0)
    }

    func testMessageSignatureDiagnosticsReuseMarksMissingEngineStages() async throws {
        let collector = DiagnosticCollector()
        MessageSignatureDiagnostics.sink = { collector.append($0) }
        setenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS", "1", 1)
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        stub.digestText = "摘要：诊断复用轮。\n关键词：诊断 复用"
        let session = "msg-sig-reuse-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(
                session: session, messages: [self.system, self.user("Q-MSG-SIG-REUSE")])
            let firstLineCount = collector.lines.count
            let second = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q-MSG-SIG-REUSE"),
                self.assistant(self.stub.text), self.user("Q-MSG-SIG-REUSE"),
            ])
            XCTAssertEqual(second.status, 200)
            XCTAssertEqual(self.stub.generate, 1, "the repeat must reuse without a model call")
            let allPayloads = diagnosticPayloads(Array(collector.lines.dropFirst(firstLineCount)))
            let secondRequestID = try XCTUnwrap(allPayloads.first { $0["stage"] as? String == "B0" }?["request_id"] as? String)
            let payloads = allPayloads.filter { $0["request_id"] as? String == secondRequestID }
            XCTAssertEqual(payloads.compactMap { $0["stage"] as? String }, [
                "B0", "B1", "B2", "B3", "B4", "B5", "B6",
            ])
            for stage in ["B4", "B5", "B6"] {
                let payload = try XCTUnwrap(payloads.first { $0["stage"] as? String == stage })
                XCTAssertEqual(payload["missing"] as? Bool, true)
                XCTAssertEqual(payload["reason"] as? String, "answer_reuse")
            }
        }
    }

    func testMessageSignatureDiagnosticsPostAdmissionReuseKeepsSingleB4() async throws {
        let collector = DiagnosticCollector()
        MessageSignatureDiagnostics.sink = { collector.append($0) }
        setenv("SIMIGO_MESSAGE_SIGNATURE_DIAGNOSTICS", "1", 1)
        let admission = RequestAdmissionScheduler(limit: 1)
        requestAdmission = admission
        stub.holdNextGeneration()
        let session = "msg-sig-post-admission-\(UUID().uuidString)"
        try await withServer {
            async let firstResponse = self.dispatch(
                session: session, messages: [self.system, self.user("Q-MSG-SIG-POST-ADMISSION")])
            try await self.waitUntil("first generation to hold") {
                self.stub.generationHeld
            }
            let secondLineStart = collector.lines.count
            async let secondResponse = self.dispatch(
                session: session, messages: [self.system, self.user("Q-MSG-SIG-POST-ADMISSION")])
            try await self.waitUntil("repeat to enter the admission queue") {
                admission.waitingRequestIDs().count == 1
            }
            self.stub.releaseHeldGeneration()
            let first = try await firstResponse
            let second = try await secondResponse
            XCTAssertEqual(first.status, 200)
            XCTAssertEqual(second.status, 200)
            XCTAssertEqual(
                (second.body["simigo"] as? [String: Any])?["answer_reuse"] as? Bool, true)
            XCTAssertEqual(self.stub.generate, 1)

            let allPayloads = diagnosticPayloads(Array(collector.lines.dropFirst(secondLineStart)))
            let secondRequestID = try XCTUnwrap(allPayloads.first { $0["stage"] as? String == "B0" }?["request_id"] as? String)
            let payloads = allPayloads.filter { $0["request_id"] as? String == secondRequestID }
            let stages = payloads.compactMap { $0["stage"] as? String }
            XCTAssertEqual(stages, ["B0", "B1", "B2", "B3", "B4", "B5", "B6"])
            XCTAssertEqual(Set(stages).count, stages.count)
            let b4 = try XCTUnwrap(payloads.first { $0["stage"] as? String == "B4" })
            XCTAssertNil(b4["missing"] as? Bool)
            for stage in ["B5", "B6"] {
                let payload = try XCTUnwrap(payloads.first { $0["stage"] as? String == stage })
                XCTAssertEqual(payload["missing"] as? Bool, true)
                XCTAssertEqual(payload["reason"] as? String, "answer_reuse")
            }
        }
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

    /// Product default (owner 2026-11-23): with the flag UNSET, substitution is
    /// ON — settled history renders as the digest chain without any env arming.
    /// Guards the default-ON correction against accidental reversion to OFF.
    func testSubstitutionDefaultOnWhenEnvUnset() async throws {
        unsetenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION")
        let session = "default-on-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-DEF")])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-DEFAULT-TEXT")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-DEF"), self.assistant("A1-DEF"), self.user("Q2-DEF"),
            ])
            let rendered = self.stub.messages
            XCTAssertEqual(rendered.count, 3)
            XCTAssertEqual(rendered[0].object?["content"]?.messageText, "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertEqual(
                rendered[1].object?["content"]?.messageText,
                "[Earlier turn t1 digest] DIGEST-DEFAULT-TEXT")
            XCTAssertTrue(
                (rendered[2].object?["content"]?.messageText ?? "").hasPrefix("Q2-DEF"))
            XCTAssertFalse(self.renderedTexts(rendered).contains { $0 == "A1-DEF" })
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

    /// Bounded fail-open (h100 E2): two settled turns, only turn 1 digested.
    /// The covered prefix renders as the chain; the lagging turn stays raw
    /// (with its frozen block); the frontier is intact. Cost is O(lag), not
    /// the O(depth) full-text re-render that hit the ctx wall at ~40 turns.
    func testPartialCoverageSubstitutesPrefixKeepsRawTail() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "partial-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-P")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-P"), self.assistant("A1-P"), self.user("Q2-P"),
            ])
            // Turn 2's digest is lagging; only turn 1 is covered.
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-P-ONE")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-P"), self.assistant("A1-P"),
                self.user("Q2-P"), self.assistant("A2-P"), self.user("Q3-P"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 5)
            XCTAssertEqual(rendered[0], "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertEqual(rendered[1], "[Earlier turn t1 digest] DIGEST-P-ONE")
            XCTAssertTrue(rendered[2].hasPrefix("Q2-P"), "lagging turn stays raw")
            XCTAssertEqual(rendered[3], "A2-P")
            XCTAssertTrue(rendered[4].hasPrefix("Q3-P"), "frontier intact")
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t2") })
        }
    }

    /// One-turn settle lag (exp-2 2026-11-23): the immediately previous turn's
    /// ledger row has not landed yet (settle serializes behind the next turn's
    /// inference), so ledger.highest == pastGenuine - 1. The gate must still
    /// substitute the covered prefix and keep the lagging turn raw — a strict
    /// equality gate rendered RAW here and locked the session into a permanent
    /// one-behind RAW loop once a fork bloated the KV.
    func testLedgerOneTurnLagStillSubstitutesPrefix() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "lag1-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-L")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-L"), self.assistant("A1-L"), self.user("Q2-L"),
            ])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-L-ONE")
            // Turn 2's settlement is still in flight: its ledger row is absent.
            try self.executeDatabaseSQL("""
            DELETE FROM chat_turn_ledger WHERE session_id='\(session)' AND turn_index=2;
            """)
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-L"), self.assistant("A1-L"),
                self.user("Q2-L"), self.assistant("A2-L"), self.user("Q3-L"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 5)
            XCTAssertEqual(rendered[1], "[Earlier turn t1 digest] DIGEST-L-ONE")
            XCTAssertTrue(rendered[2].hasPrefix("Q2-L"), "lagging turn stays raw")
            XCTAssertEqual(rendered[3], "A2-L")
            XCTAssertTrue(rendered[4].hasPrefix("Q3-L"), "frontier intact")
        }
    }

    /// Identity anchoring (owner 2026-11-23): a digest row alone never
    /// authorizes substitution. Turns 2/3 lose their ledger anchors while
    /// their digests linger in render-side memory: the anchored prefix (t1)
    /// still substitutes, the unanchored turns stay RAW — no data loss, no
    /// digest mapped onto a question the ledger cannot vouch for. Replaces
    /// the positional two-turn-lag fallback: under anchoring the lagging
    /// turns are simply unanchored, and the bounded fail-open keeps them
    /// verbatim. The memory preload is the artificial part (production
    /// digests never outrun the ledger); it exercises the covered<=anchored
    /// cap directly.
    func testUnanchoredTurnsStayRawEvenWhenDigestsExist() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "lag2-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-T")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-T"), self.assistant("A1-T"), self.user("Q2-T"),
            ])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-T"), self.assistant("A1-T"),
                self.user("Q2-T"), self.assistant("A2-T"), self.user("Q3-T"),
            ])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-T-ONE")
            // Turns 2 and 3 lose their ledger anchors; their digests persist.
            try self.executeDatabaseSQL("""
            DELETE FROM chat_turn_ledger WHERE session_id='\(session)' AND turn_index>=2;
            """)
            ISContextLedger.shared.rememberDigest(
                scope: session, turnIndex: 2, digest: "DIGEST-T-TWO")
            ISContextLedger.shared.rememberDigest(
                scope: session, turnIndex: 3, digest: "DIGEST-T-THREE")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-T"), self.assistant("A1-T"),
                self.user("Q2-T"), self.assistant("A2-T"),
                self.user("Q3-T"), self.assistant("A3-T"), self.user("Q4-T"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 7)
            XCTAssertEqual(rendered[1], "[Earlier turn t1 digest] DIGEST-T-ONE")
            XCTAssertTrue(rendered[2].hasPrefix("Q2-T"), "unanchored turn stays raw")
            XCTAssertEqual(rendered[3], "A2-T")
            XCTAssertTrue(rendered[4].hasPrefix("Q3-T"), "unanchored turn stays raw")
            XCTAssertEqual(rendered[5], "A3-T")
            XCTAssertTrue(rendered[6].hasPrefix("Q4-T"), "frontier intact")
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t2") })
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t3") })
        }
    }

    /// Real-client recheck root cause (002e68, 21 turns zero substitution):
    /// the client injects noise user messages whose stripped text is non-empty
    /// but matches no settled question. Position counting inflated the genuine
    /// count and wedged the gate shut. Identity anchoring must ignore the noise
    /// for counting, substitute the anchored chain, and keep the frontier.
    /// Noise inside a substituted segment rides along with its turn (whole-turn
    /// substitution, owner Q2); noise after the last substituted turn stays raw.
    func testNoiseUserMessagesDoNotWedgeTheGate() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "noise-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-N")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-N"), self.assistant("A1-N"),
                self.user("CLIENT-NOISE-ONE"), self.user("Q2-N"),
            ])
            // Phase 1: only t1 digested — bounded fail-open with noise present.
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-N-ONE")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-N"), self.assistant("A1-N"),
                self.user("CLIENT-NOISE-ONE"), self.user("Q2-N"), self.assistant("A2-N"),
                self.user("CLIENT-NOISE-TWO"), self.user("Q3-N"),
            ])
            let partial = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(partial.count, 7)
            XCTAssertEqual(partial[1], "[Earlier turn t1 digest] DIGEST-N-ONE")
            XCTAssertEqual(partial[2], "CLIENT-NOISE-ONE", "noise after the substituted prefix stays raw")
            XCTAssertTrue(partial[3].hasPrefix("Q2-N"), "lagging turn stays raw")
            XCTAssertEqual(partial[4], "A2-N")
            XCTAssertEqual(partial[5], "CLIENT-NOISE-TWO", "tail noise verbatim")
            XCTAssertTrue(partial[6].hasPrefix("Q3-N"), "frontier intact")
            // Phase 2: coverage completes — the full anchored chain renders
            // despite two noise messages the positional gate counted as turns.
            // The previous dispatch settled t3 (Q3-N); cover it too.
            try self.seedDigest(session: session, turn: 2, text: "DIGEST-N-TWO")
            try self.seedDigest(session: session, turn: 3, text: "DIGEST-N-THREE")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-N"), self.assistant("A1-N"),
                self.user("CLIENT-NOISE-ONE"), self.user("Q2-N"), self.assistant("A2-N"),
                self.user("CLIENT-NOISE-TWO"), self.user("Q3-N"), self.assistant("A3-N"),
                self.user("Q4-N"),
            ])
            let full = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(full.count, 5)
            XCTAssertEqual(full[0], "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertEqual(full[1], "[Earlier turn t1 digest] DIGEST-N-ONE")
            XCTAssertEqual(full[2], "[Earlier turn t2 digest] DIGEST-N-TWO")
            XCTAssertEqual(full[3], "[Earlier turn t3 digest] DIGEST-N-THREE")
            XCTAssertTrue(full[4].hasPrefix("Q4-N"), "frontier intact")
            XCTAssertFalse(full.contains { $0.contains("CLIENT-NOISE") },
                           "mid-chain noise rides along with its substituted turn")
        }
    }

    /// Real zcode session 174f54 (2026-11-23): a retried question is served by
    /// ES zero-call reuse (`IS_REUSE model_calls=0`), committing a SECOND ledger
    /// turn with identical question AND answer, while the client's deduped
    /// history shows the question only once. The gate must fold the consecutive
    /// identical-Q+A run into one effective anchor and substitute, not wedge
    /// shut forever on anchor_count/anchor_mismatch.
    func testReusedDuplicateTurnFoldsAndSubstitutes() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "reuse-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-R")])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-R-ONE")
            // Same question again as the frontier: ES reuse, no generation.
            let second = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-R"), self.assistant(self.stub.text), self.user("Q1-R"),
            ])
            XCTAssertEqual(second.status, 200)
            XCTAssertEqual(self.stub.generate, 1, "the repeat must reuse, not generate")
            let ledger = try self.queryRows("""
            SELECT turn_index FROM chat_turn_ledger
            WHERE session_id='\(session)' ORDER BY turn_index;
            """)
            XCTAssertEqual(ledger, [["1"], ["2"]], "reuse commits a second ledger turn")
            try self.seedDigest(session: session, turn: 2, text: "DIGEST-R-TWO")
            // Client deduped the retry: Q1 appears ONCE. Before the fold fix
            // this wedged the gate (anchored=1, ledger=2, no visible lag).
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-R"), self.assistant(self.stub.text), self.user("Q2-R"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 3)
            XCTAssertEqual(rendered[0], "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertEqual(rendered[1], "[Earlier turn t1 digest] DIGEST-R-ONE")
            XCTAssertTrue(rendered[2].hasPrefix("Q2-R"), "frontier intact")
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t2") },
                           "the folded reuse turn renders no separate digest")
        }
    }

    /// A legit repeat the client shows TWICE (identical Q+A via reuse): once a
    /// second distinct turn anchors past both copies, the whole segment folds
    /// to ONE digest — no duplicate digest, no wedge, no raw Q1 left behind.
    func testRepeatedQuestionShownTwiceFoldsToOneDigest() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "reuse2-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-D")])
            // Identical repeat -> ES reuse commits t2 (same Q+A).
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-D"), self.assistant(self.stub.text), self.user("Q1-D"),
            ])
            XCTAssertEqual(self.stub.generate, 1, "second identical question reuses")
            // A distinct turn so the anchored prefix extends past BOTH Q1 copies.
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-D"), self.assistant(self.stub.text),
                self.user("Q1-D"), self.assistant(self.stub.text), self.user("Q2-D"),
            ])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-D-ONE")
            try self.seedDigest(session: session, turn: 2, text: "DIGEST-D-TWO")
            try self.seedDigest(session: session, turn: 3, text: "DIGEST-D-THREE")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-D"), self.assistant(self.stub.text),
                self.user("Q1-D"), self.assistant(self.stub.text),
                self.user("Q2-D"), self.assistant(self.stub.text), self.user("Q3-D"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 4)
            XCTAssertEqual(rendered[0], "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertEqual(rendered[1], "[Earlier turn t1 digest] DIGEST-D-ONE")
            XCTAssertEqual(rendered[2], "[Earlier turn t3 digest] DIGEST-D-THREE")
            XCTAssertTrue(rendered[3].hasPrefix("Q3-D"), "frontier intact")
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t2") },
                           "the folded reuse turn renders no separate digest")
            XCTAssertFalse(rendered.contains { $0.hasPrefix("Q1-D") },
                           "both occurrences of the folded question substitute away")
        }
    }

    /// A repeat with a DIFFERENT answer is NOT provably the same round: it stays
    /// a distinct run. The earliest anchors and substitutes; the later occurrence
    /// is unanchored and stays RAW (no information loss, no digest mis-mapped).
    func testRepeatWithDifferentAnswerStaysRaw() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "reuse3-\(UUID().uuidString)"
        let originalAnswer = self.stub.text
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-X")])
            // Force a fresh, DIFFERENT answer for the repeat (reuse off).
            setenv("SIMIGO_IS_ANSWER_REUSE", "0", 1)
            self.stub.text = "DIFFERENT-ANSWER-X"
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-X"), self.assistant(originalAnswer), self.user("Q1-X"),
            ])
            setenv("SIMIGO_IS_ANSWER_REUSE", "1", 1)
            self.stub.text = originalAnswer
            XCTAssertEqual(self.stub.generate, 2, "different answer must generate")
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-X-ONE")
            try self.seedDigest(session: session, turn: 2, text: "DIGEST-X-TWO")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-X"), self.assistant(originalAnswer),
                self.user("Q1-X"), self.assistant("A2-X"), self.user("Q2-X"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 5)
            XCTAssertEqual(rendered[1], "[Earlier turn t1 digest] DIGEST-X-ONE")
            XCTAssertTrue(rendered[2].hasPrefix("Q1-X"), "the different-answer repeat stays raw")
            XCTAssertEqual(rendered[3], "A2-X")
            XCTAssertTrue(rendered[4].hasPrefix("Q2-X"), "frontier intact")
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t2") },
                           "a non-identical repeat is never folded into the head digest")
        }
    }

    /// Deduped different-answer retry (qoder, real session c0d32c 2026-11-24):
    /// the client shows the retried question ONCE carrying the LATEST answer.
    /// The consecutive same-question runs collapse into the latest head, so the
    /// single display substitutes the latest answer's digest and the gate no
    /// longer wedges shut (gate=0 anchor_mismatch on every request before fix).
    func testDedupedDifferentAnswerRetryFoldsToLatest() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "dedup-\(UUID().uuidString)"
        let originalAnswer = self.stub.text
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-Y")])
            // Different-answer retry (reuse off): commits t2, same question.
            setenv("SIMIGO_IS_ANSWER_REUSE", "0", 1)
            self.stub.text = "DIFFERENT-ANSWER-Y"
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-Y"), self.assistant(originalAnswer), self.user("Q1-Y"),
            ])
            setenv("SIMIGO_IS_ANSWER_REUSE", "1", 1)
            self.stub.text = originalAnswer
            XCTAssertEqual(self.stub.generate, 2, "different answer must generate")
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-Y-ONE")
            try self.seedDigest(session: session, turn: 2, text: "DIGEST-Y-TWO")
            // Client DEDUPS the retry: Q1-Y shown ONCE; a distinct frontier turn
            // extends the anchored prefix past the collapsed retry.
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-Y"), self.assistant("DIFFERENT-ANSWER-Y"), self.user("Q2-Y"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 3)
            XCTAssertEqual(rendered[0], "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertEqual(rendered[1], "[Earlier turn t2 digest] DIGEST-Y-TWO",
                           "the deduped retry substitutes the LATEST answer's digest")
            XCTAssertTrue(rendered[2].hasPrefix("Q2-Y"), "frontier intact")
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t1") },
                           "the superseded earliest run renders no separate digest")
        }
    }

    /// Unsettled head (owner Q1: 首算保持不替换): a briefing/task message that
    /// never settles has no ledger anchor. Substitution must start at the first
    /// ANCHORED turn, keeping the head's original text instead of deleting it
    /// with the trunk-to-chain slice.
    func testUnsettledHeadTurnKeepsOriginalText() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "head-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("TASK-BRIEFING-NEVER-SETTLES"), self.user("Q1-H"),
            ])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-H-ONE")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("TASK-BRIEFING-NEVER-SETTLES"),
                self.user("Q1-H"), self.assistant("A1-H"), self.user("Q2-H"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 4)
            XCTAssertEqual(rendered[0], "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertEqual(rendered[1], "TASK-BRIEFING-NEVER-SETTLES", "head stays raw")
            XCTAssertEqual(rendered[2], "[Earlier turn t1 digest] DIGEST-H-ONE")
            XCTAssertTrue(rendered[3].hasPrefix("Q2-H"), "frontier intact")
        }
    }

    /// Whole-turn substitution (owner Q2: 工具会话整轮替换，工具不是结论):
    /// assistant tool_calls legs and tool results inside a settled turn are
    /// deleted with the turn segment; the digest chain carries the conclusion.
    func testToolLegsSubstituteWithTheirWholeTurn() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "tool-\(UUID().uuidString)"
        let toolCall: [String: Any] = [
            "role": "assistant", "content": "",
            "tool_calls": [[
                "id": "call_1", "type": "function",
                "function": ["name": "noop", "arguments": "{}"],
            ]],
        ]
        let toolResult: [String: Any] = [
            "role": "tool", "tool_call_id": "call_1", "content": "TOOL-OUTPUT-DETAIL",
        ]
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-W")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-W"), toolCall, toolResult,
                self.assistant("A1-W"), self.user("Q2-W"),
            ])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-W-ONE")
            try self.seedDigest(session: session, turn: 2, text: "DIGEST-W-TWO")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-W"), toolCall, toolResult,
                self.assistant("A1-W"), self.user("Q2-W"), self.assistant("A2-W"),
                self.user("Q3-W"),
            ])
            let rendered = self.stub.messages
            XCTAssertEqual(rendered.count, 4)
            XCTAssertEqual(rendered[1].object?["content"]?.messageText,
                           "[Earlier turn t1 digest] DIGEST-W-ONE")
            XCTAssertEqual(rendered[2].object?["content"]?.messageText,
                           "[Earlier turn t2 digest] DIGEST-W-TWO")
            XCTAssertTrue((rendered[3].object?["content"]?.messageText ?? "").hasPrefix("Q3-W"))
            XCTAssertFalse(rendered.contains { $0.object?["role"]?.string == "tool" },
                           "tool results ride along with their substituted turn")
            XCTAssertFalse(self.renderedTexts(rendered).contains { $0.contains("TOOL-OUTPUT-DETAIL") })
        }
    }

    /// Contiguity: a digest for turn 2 with turn 1 missing cannot be substituted
    /// (the chain must be a contiguous prefix) — covered==0, full fail-open.
    func testNonContiguousCoverageFallsBackToOriginal() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "noncontig-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-NC")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-NC"), self.assistant("A1-NC"), self.user("Q2-NC"),
            ])
            try self.seedDigest(session: session, turn: 2, text: "DIGEST-NC-TWO")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-NC"), self.assistant("A1-NC"),
                self.user("Q2-NC"), self.assistant("A2-NC"), self.user("Q3-NC"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 6)
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn") })
        }
    }

    /// Convergence: once the lagging digest lands, the next render is the full
    /// chain again — byte-identical to complete-coverage substitution.
    func testPartialConvergesToFullChainWhenCoverageCompletes() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        let session = "converge-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-C")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-C"), self.assistant("A1-C"), self.user("Q2-C"),
            ])
            try self.seedDigest(session: session, turn: 1, text: "DIGEST-C-ONE")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-C"), self.assistant("A1-C"),
                self.user("Q2-C"), self.assistant("A2-C"), self.user("Q3-C"),
            ])
            XCTAssertEqual(self.renderedTexts(self.stub.messages).count, 5, "partial first")
            // The previous dispatch settled t3; coverage completes for every
            // settled turn. The frontier must ADVANCE (Q4): a byte-identical
            // re-dispatch hits demand-keyed answer reuse and never generates,
            // so the stub would still hold the partial render.
            try self.seedDigest(session: session, turn: 2, text: "DIGEST-C-TWO")
            try self.seedDigest(session: session, turn: 3, text: "DIGEST-C-THREE")
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-C"), self.assistant("A1-C"),
                self.user("Q2-C"), self.assistant("A2-C"),
                self.user("Q3-C"), self.assistant("A3-C"), self.user("Q4-C"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.count, 5, "full chain once coverage completes")
            XCTAssertEqual(rendered[1], "[Earlier turn t1 digest] DIGEST-C-ONE")
            XCTAssertEqual(rendered[2], "[Earlier turn t2 digest] DIGEST-C-TWO")
            XCTAssertEqual(rendered[3], "[Earlier turn t3 digest] DIGEST-C-THREE")
            XCTAssertTrue(rendered[4].hasPrefix("Q4-C"))
        }
    }

    /// Form ② compactor pure function: bounded by char budget, deterministic,
    /// short input untouched. The decoupled producer swap point.
    func testCompactionBriefIsBoundedAndDeterministic() {
        let digests = (1...20).map {
            (turnIndex: $0, digest: String(repeating: "x", count: 100))
        }
        let a = DigestPrefixCompaction.brief(digests, budgetChars: 500)
        let b = DigestPrefixCompaction.brief(digests, budgetChars: 500)
        XCTAssertEqual(a, b, "deterministic")
        XCTAssertLessThanOrEqual(a.count, 501, "budget + ellipsis")
        XCTAssertTrue(a.hasSuffix("…"))
        XCTAssertEqual(
            DigestPrefixCompaction.brief([(1, "short")], budgetChars: 500),
            "t1: short", "short input untouched")
    }

    /// KEY-ANCHORED brief (owner 2026-11-23): when truncation would drop later
    /// digests, the verbatim fact tokens from ALL turns survive in the anchor
    /// (the old prefix-only cap dropped late-turn keys ⇒ perf-full normal 7/29).
    /// Narrative prose is the lossy part; precise codes/values are preserved.
    func testCompactionBriefPreservesLateTurnFacts() {
        let digests = [
            (turnIndex: 1, digest: String(repeating: "叙", count: 200)),
            (turnIndex: 2, digest: "结构混凝土强度等级 C45、沥青摊铺温度 155℃、路基压实度 98%"),
            (turnIndex: 3, digest: String(repeating: "叙", count: 200)),
            (turnIndex: 4, digest: "质保金预留比例 5.5%、缺陷责任期 850天、项目编号 X-9942、监理通知单 JL-3105"),
        ]
        let brief = DigestPrefixCompaction.brief(digests, budgetChars: 300)
        XCTAssertTrue(brief.hasPrefix("事实锚点"), "anchor leads when truncating")
        for key in ["C45", "155℃", "98%", "5.5%", "850", "X-9942", "JL-3105"] {
            XCTAssertTrue(brief.contains(key), "late-turn fact \(key) must survive truncation")
        }
        XCTAssertLessThanOrEqual(brief.count, 301, "prefix bound holds (budget + ellipsis)")
        XCTAssertEqual(brief, DigestPrefixCompaction.brief(digests, budgetChars: 300),
                       "deterministic")
        // No facts ⇒ anchor empty ⇒ behaves as the old narrative prefix cap.
        let prose = DigestPrefixCompaction.brief(
            (1...10).map { (turnIndex: $0, digest: String(repeating: "x", count: 100)) },
            budgetChars: 200)
        XCTAssertFalse(prose.hasPrefix("事实锚点"), "no fact tokens ⇒ no anchor line")
        XCTAssertTrue(prose.hasSuffix("…"))
    }

    func testCompactionBriefKeepsRelationsAtomicAndDeduplicated() {
        let facts = "30 min、4–20 mA、2.40 MPa、WT-IF-004 版本 3、版本2、EN-DOC-003、C45"
        let digests = [
            (turnIndex: 1, digest: String(repeating: "叙", count: 2000)),
            (turnIndex: 2, digest: facts + "；4–20 mA 再次出现"),
        ]
        let brief = DigestPrefixCompaction.brief(digests, budgetChars: 500)
        XCTAssertTrue(brief.hasPrefix("事实锚点（逐字保留）：\(facts)\n"))
        XCTAssertEqual(brief.components(separatedBy: "4–20 mA").count - 1, 1)
    }

    func testCompactionBriefGeneralizesEngineeringUnits() {
        let facts = "0.5 mm、12 min、8 mA、2.35 m、90 d、25 m³/h、70 km/h、3 kW、10 kg/m³、4 m/s、5 kWh、50 Hz、20 ℃、30%、850天"
        let digests = [
            (turnIndex: 1, digest: String(repeating: "叙", count: 2000)),
            (turnIndex: 2, digest: facts),
        ]
        let brief = DigestPrefixCompaction.brief(digests, budgetChars: 700)
        XCTAssertTrue(brief.hasPrefix("事实锚点（逐字保留）：\(facts)\n"))
    }

    func testCompactionBriefPreservesRangeSeparatorsVerbatim() {
        let facts = "1–2 m、3—4 MPa、5~6 kW、7～8 d、9至10 mA、11到12 m³/h"
        let digests = [
            (turnIndex: 1, digest: String(repeating: "叙", count: 2000)),
            (turnIndex: 2, digest: facts),
        ]
        let brief = DigestPrefixCompaction.brief(digests, budgetChars: 500)
        XCTAssertTrue(brief.hasPrefix("事实锚点（逐字保留）：\(facts)\n"))
    }

    /// Form ② TRIGGER policy pure function: the brief is the cold-rebuild point,
    /// so the boundary advances at checkpoints (turn/char, first to hit), NOT
    /// every turn. Between checkpoints B is stable (append-only raw => engine
    /// reuse); at a checkpoint B jumps (one bounded cold rebuild, amortized).
    func testCompactionBoundaryIsCheckpointedNotPerTurn() {
        // Turn checkpoint every 2 eligible turns.
        XCTAssertEqual(
            DigestPrefixCompaction.boundary(rawTurnChars: [100, 100], triggerChars: 0, triggerTurns: 2), 2)
        XCTAssertEqual(
            DigestPrefixCompaction.boundary(rawTurnChars: [100, 100, 100], triggerChars: 0, triggerTurns: 2),
            2, "stable between checkpoints => append-only reuse")
        XCTAssertEqual(
            DigestPrefixCompaction.boundary(rawTurnChars: [100, 100, 100, 100], triggerChars: 0, triggerTurns: 2),
            4, "jumps at the checkpoint => one cold rebuild")
        XCTAssertEqual(
            DigestPrefixCompaction.boundary(rawTurnChars: [100, 100, 100, 100, 100], triggerChars: 0, triggerTurns: 2), 4)
        // Char checkpoint (token proxy), every 2000 chars.
        XCTAssertEqual(
            DigestPrefixCompaction.boundary(rawTurnChars: [1000, 1000, 1000], triggerChars: 2000, triggerTurns: 0), 2)
        // First-to-hit: a big turn crosses the char budget before the turn cap.
        XCTAssertEqual(
            DigestPrefixCompaction.boundary(rawTurnChars: [3000], triggerChars: 2000, triggerTurns: 8), 1)
        // Both disabled => never compact; empty => 0.
        XCTAssertEqual(
            DigestPrefixCompaction.boundary(rawTurnChars: [100, 100], triggerChars: 0, triggerTurns: 0), 0)
        XCTAssertEqual(
            DigestPrefixCompaction.boundary(rawTurnChars: [], triggerChars: 2000, triggerTurns: 2), 0)
    }

    /// Before the first checkpoint the rendering stays the ORIGINAL append-only
    /// raw history (OFF-arm shape) so the engine reuses its prefix — compaction
    /// is triggered, not per-turn. keep=2, turn checkpoint=8, 4 settled turns =>
    /// eligible=2 < 8 => no checkpoint => no brief/digest substitution.
    func testCompactionBeforeCheckpointKeepsAppendOnlyRaw() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        setenv("SIMIGO_DIGEST_COMPACTION_KEEP", "2", 1)
        setenv("SIMIGO_DIGEST_COMPACTION_TRIGGER_TURNS", "8", 1)
        setenv("SIMIGO_DIGEST_COMPACTION_TRIGGER_CHARS", "0", 1)
        let session = "compact-pre-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-K")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-K"), self.assistant("A1-K"), self.user("Q2-K"),
            ])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-K"), self.assistant("A1-K"),
                self.user("Q2-K"), self.assistant("A2-K"), self.user("Q3-K"),
            ])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-K"), self.assistant("A1-K"),
                self.user("Q2-K"), self.assistant("A2-K"),
                self.user("Q3-K"), self.assistant("A3-K"), self.user("Q4-K"),
            ])
            for t in 1...4 {
                try self.seedDigest(session: session, turn: t, text: "DIGEST-K-\(t)")
            }
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-K"), self.assistant("A1-K"),
                self.user("Q2-K"), self.assistant("A2-K"),
                self.user("Q3-K"), self.assistant("A3-K"),
                self.user("Q4-K"), self.assistant("A4-K"), self.user("Q5-K"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered.first, "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertTrue(rendered.last?.hasPrefix("Q5-K") == true)
            XCTAssertFalse(rendered.contains { $0.contains("[Compacted") }, "no checkpoint yet")
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn") }, "append-only raw")
        }
    }

    /// At a checkpoint the rendering collapses the older covered digests into ONE
    /// bounded brief, keeps the most recent `keep` digests full, and leaves the
    /// post-boundary turns RAW (append-only tail) + frontier intact. keep=1,
    /// turn checkpoint=2, 4 settled turns => eligible=3, boundary=2, split=1 =>
    /// brief(t1) + digest(t2) + raw(t3,t4) + frontier. Model-agnostic.
    func testCompactionAtCheckpointRendersBoundedPrefix() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        setenv("SIMIGO_DIGEST_COMPACTION_KEEP", "1", 1)
        setenv("SIMIGO_DIGEST_COMPACTION_TRIGGER_TURNS", "2", 1)
        setenv("SIMIGO_DIGEST_COMPACTION_TRIGGER_CHARS", "0", 1)
        setenv("SIMIGO_DIGEST_COMPACTION_BUDGET_CHARS", "4000", 1)
        let session = "compact-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-K")])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-K"), self.assistant("A1-K"), self.user("Q2-K"),
            ])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-K"), self.assistant("A1-K"),
                self.user("Q2-K"), self.assistant("A2-K"), self.user("Q3-K"),
            ])
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-K"), self.assistant("A1-K"),
                self.user("Q2-K"), self.assistant("A2-K"),
                self.user("Q3-K"), self.assistant("A3-K"), self.user("Q4-K"),
            ])
            for t in 1...4 {
                try self.seedDigest(session: session, turn: t, text: "DIGEST-K-\(t)")
            }
            _ = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-K"), self.assistant("A1-K"),
                self.user("Q2-K"), self.assistant("A2-K"),
                self.user("Q3-K"), self.assistant("A3-K"),
                self.user("Q4-K"), self.assistant("A4-K"), self.user("Q5-K"),
            ])
            let rendered = self.renderedTexts(self.stub.messages)
            XCTAssertEqual(rendered[0], "DIGEST-SPIKE-TRUNK-SYSTEM")
            XCTAssertTrue(rendered[1].hasPrefix("[Compacted turns t1..t1 brief]"))
            XCTAssertTrue(rendered[1].contains("DIGEST-K-1"))
            XCTAssertEqual(rendered[2], "[Earlier turn t2 digest] DIGEST-K-2")
            XCTAssertTrue(rendered.contains { $0.hasPrefix("Q3-K") }, "post-boundary turn stays raw")
            XCTAssertTrue(rendered.contains { $0.hasPrefix("Q4-K") })
            XCTAssertTrue(rendered.last?.hasPrefix("Q5-K") == true)
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t1 digest]") }, "t1 compacted")
            XCTAssertFalse(rendered.contains { $0.contains("[Earlier turn t3 digest]") }, "t3 raw, not compacted")
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

    // MARK: - Q2 warm digest (settle-time write + instant substitution)

    /// Warm path: the digest is produced from the in-memory Q+A while the
    /// engine is still warm, written before the handler returns (no drain
    /// wait, no seeded rows), and the very next turn substitutes it.
    func testWarmDigestWritesAtSettleAndSubstitutesNextTurn() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        stub.digestText = "摘要：暖摘要在结算时落库。\n关键词：暖摘要 结算 落库 替换"
        let session = "warm-\(UUID().uuidString)"
        try await withServer {
            let first = try await self.dispatch(
                session: session, messages: [self.system, self.user("Q1-WARM")])
            XCTAssertEqual(first.status, 200)
            // Written at settle, before the permit releases — no drain, no
            // seeded rows. Poll: the response outruns the warm write by ms.
            try await self.waitUntil("the warm digest row") {
                try self.queryRows("""
                SELECT digest FROM turn_digests
                WHERE session_id='\(session)' AND turn_index=1;
                """) == [["暖摘要在结算时落库。"]]
            }
            XCTAssertEqual(self.stub.digestGenerate, 1, "one warm digest call for the settled turn")
            XCTAssertEqual(self.stub.generate, 1, "the chat generation count is unchanged")
            // The prompt carries the in-memory question and answer, not an IS re-read.
            let prompt = self.renderedTexts(self.stub.digestMessages).joined()
            XCTAssertTrue(prompt.contains("Q1-WARM"), "the warm prompt must carry the question")
            XCTAssertTrue(prompt.contains(self.stub.text), "the warm prompt must carry the answer")

            let second = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-WARM"), self.assistant(self.stub.text),
                self.user("Q2-WARM"),
            ])
            XCTAssertEqual(second.status, 200)
            XCTAssertTrue(
                self.renderedTexts(self.stub.messages).contains(
                    "[Earlier turn t1 digest] 暖摘要在结算时落库。"),
                "the next turn must substitute the warm-written digest with no raw-tail lag")
        }
    }

    /// Fail-open: a warm production that cannot parse writes NO row; the
    /// ledger turn exists and the queued fallback owns the turn.
    func testWarmDigestBadFormatFallsBackToQueue() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        // Default stub.digestText is a single line: not digest format.
        let session = "warmfb-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(
                session: session, messages: [self.system, self.user("Q1-WFB")])
            try await self.waitUntil("the warm attempt") { self.stub.digestGenerate == 1 }
            let rows = try self.queryRows("""
            SELECT digest FROM turn_digests
            WHERE session_id='\(session)' AND turn_index=1;
            """)
            XCTAssertTrue(rows.isEmpty, "bad format must not write; the queued fallback owns the turn")
            let ledger = try self.queryRows("""
            SELECT turn_index FROM chat_turn_ledger WHERE session_id='\(session)';
            """)
            XCTAssertEqual(ledger, [["1"]], "the durable gap ledger can still recover the turn")
        }
    }

    /// Bounded: a warm production that exceeds the timeout is cancelled, the
    /// late result is discarded, and the fallback queue owns the turn.
    func testWarmDigestTimeoutFallsBack() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        stub.digestText = "摘要：迟到但格式正确的摘要。\n关键词：超时 兜底 有界"
        stub.digestDelay = 0.5
        HTTPServer.warmDigestTimeoutForTesting = 0.05
        let session = "warmto-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(
                session: session, messages: [self.system, self.user("Q1-WTO")])
            try await self.waitUntil("the warm attempt") { self.stub.digestGenerate == 1 }
            let rows = try self.queryRows("""
            SELECT digest FROM turn_digests
            WHERE session_id='\(session)' AND turn_index=1;
            """)
            XCTAssertTrue(rows.isEmpty, "the timeout must win; the late digest must not be written")
        }
    }

    /// Fix 1: the rendering gate freezes before admission, so a fast feed can
    /// freeze turn N+1's render before turn N's warm write lands (covered =
    /// anchored-1). The post-admission refresh re-runs the gate once the permit
    /// is held (warm write landed by then) so GENERATION uses covered==anchored,
    /// not a lagging raw tail. A warm delay widens the race window; the assertion
    /// holds whether prepare or refresh supplied the coverage.
    func testPostAdmissionRefreshCoversLaggingTurn() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        stub.digestText = "摘要：准入后刷新补上滞后轮。\n关键词：刷新 准入 滞后 覆盖"
        stub.digestDelay = 0.4
        let session = "refresh-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(
                session: session, messages: [self.system, self.user("Q1-RF")])
            // Immediately dispatch turn 2: its prepare may freeze before turn 1's
            // warm write lands; the refresh after admission must still substitute.
            let second = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-RF"), self.assistant(self.stub.text),
                self.user("Q2-RF"),
            ])
            XCTAssertEqual(second.status, 200)
            XCTAssertTrue(
                self.renderedTexts(self.stub.messages).contains(
                    "[Earlier turn t1 digest] 准入后刷新补上滞后轮。"),
                "generation must use refreshed coverage, not a lagging raw tail")
        }
    }

    // MARK: - Fix A: folded reuse turn zero-call digest copy (build21)

    /// Backward ordering: the source digest already exists when the reuse turn
    /// settles. The folded turn inherits it verbatim at settle time — coverage
    /// lands immediately, no second digest generation, no async-drain lag.
    func testFoldedReuseTurnCopiesDigestZeroCall() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        stub.digestText = "摘要：复用轮零调用复制。\n关键词：复用 复制 零调用"
        let session = "copy-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-C")])
            try await self.waitUntil("turn 1 warm digest") {
                try self.queryRows("""
                SELECT digest FROM turn_digests WHERE session_id='\(session)' AND turn_index=1;
                """) == [["复用轮零调用复制。"]]
            }
            XCTAssertEqual(self.stub.digestGenerate, 1)
            // Identical repeat → ES reuse commits folded turn 2 (no generation).
            let second = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-C"), self.assistant(self.stub.text), self.user("Q1-C"),
            ])
            XCTAssertEqual(second.status, 200)
            XCTAssertEqual(self.stub.generate, 1, "the repeat reuses, not generates")
            let copied = try self.queryRows("""
            SELECT digest FROM turn_digests WHERE session_id='\(session)' AND turn_index=2;
            """)
            XCTAssertEqual(copied, [["复用轮零调用复制。"]],
                           "the folded reuse turn inherits turn 1's digest at settle time")
            XCTAssertEqual(self.stub.digestGenerate, 1,
                           "the copy is zero-call: no second digest generation")
            let src = try self.queryRows("""
            SELECT COUNT(*) FROM turn_digest_sources WHERE session_id='\(session)' AND turn_index=2;
            """)
            XCTAssertEqual(src, [["1"]], "the source receipt is copied too")
        }
    }

    /// Forward ordering — the real build20 race: the reuse turn settles BEFORE
    /// the source turn's warm digest lands. When that digest is written it
    /// propagates to the already-committed folded sibling zero-call, instead of
    /// the sibling waiting minutes for the async drain (no_coverage cold window).
    func testFoldedReuseTurnCopiedForwardWhenSourceDigestLandsLate() async throws {
        setenv("SIMIGO_DIGEST_PREFIX_SUBSTITUTION", "1", 1)
        stub.digestText = "摘要：迟到源摘要前向传播。\n关键词：前向 传播 复用"
        stub.digestDelay = 0.6
        let session = "copyfwd-\(UUID().uuidString)"
        try await withServer {
            _ = try await self.dispatch(session: session, messages: [self.system, self.user("Q1-F")])
            // Reuse turn 2 settles while turn 1's warm digest is still delayed.
            let second = try await self.dispatch(session: session, messages: [
                self.system, self.user("Q1-F"), self.assistant(self.stub.text), self.user("Q1-F"),
            ])
            XCTAssertEqual(second.status, 200)
            XCTAssertEqual(self.stub.generate, 1, "the repeat reuses, not generates")
            // Once turn 1's digest lands, turn 2 is filled forward (no 2nd gen).
            try await self.waitUntil("forward fold fill") {
                try self.queryRows("""
                SELECT digest FROM turn_digests WHERE session_id='\(session)' AND turn_index=2;
                """) == [["迟到源摘要前向传播。"]]
            }
            XCTAssertEqual(self.stub.digestGenerate, 1, "forward fill is zero-call")
        }
    }
}
