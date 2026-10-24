import Foundation
import Network
import XCTest
import SQLite3
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// Second-step, model-free HTTP INTEGRATION proof for the ES/IS continuation +
/// settlement contract. Unlike the stub-driven gate tests
/// (`ResponsesContinuationSettlementContractTests`, which hard-code a fake
/// `settle-1`) and the adapter tests (which drive the settlement closure
/// directly), every assertion here goes through the SAME real product dispatch
/// a live client hits:
///
///   real signed HTTPS POST /v1/responses (LOCALB TLS + V2 proof)
///     -> HTTPServer.route (protected-route gate)
///     -> handleResponsesNonStreaming / handleResponsesStreaming
///     -> continuationGate -> the REAL admission authority
///        (`SimiGoProducerIdentity.recoverForContinuation`, exactly the closure
///        NativeMLX wires at the HTTPServer construction site)
///     -> generateHandler  (a TEXT stand-in, no model load — this is the ONLY
///        substituted component)
///     -> settlementStep  -> the REAL settlement adapter
///        (`makeNativeMLXContinuationSettlementHandler` -> native gate +
///        authoritative SQLite atomic commit + identity-binding publication)
///     -> completed response / structured error terminal
///
/// Because admission + settlement + the authoritative SQLite are the real
/// product code, this proves what the stub tests cannot: that the `settlement_id`
/// the HTTP response reports is the SAME id the authoritative store committed in
/// this request's atomic transaction, and that a lower-layer write failure fails
/// closed end-to-end with no partial commit.
///
/// NO REAL MODEL IS STARTED and NO REAL USER STATE IS WRITTEN: the runtime never
/// loads weights (the snapshot is a disk directory whose identity is re-derived
/// without a load), and the whole class XCTSkips unless the three isolated roots
/// (`SIMIGO_HOME`, `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`) are injected,
/// so the authoritative store the server opens is inside the isolation root.
///
/// The LOCALB transport identity + registry + client pairing come from the
/// test-only `LOCALBAuthorizedE2E` fixture, which is independent of the model and
/// leaves production defaults untouched.
final class ResponsesContinuationHTTPIntegrationTests: XCTestCase {

    // A single listener port reused across the sequential tests of this class.
    private let port = 59_357

    private var isolationRoot: URL!
    private var modelPath: String!
    private var host: LOCALBAuthorizedE2E.Host!

    // MARK: - Generation stand-in + authority-call counters

    /// Records how many times each stage actually ran, and holds the fixed text
    /// the "generation" emits (so settlement runs over a deterministic value).
    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        private var _admission = 0
        private var _settlement = 0
        nonisolated(unsafe) var text: String = ""

        func bumpGenerate() { lock.withLock { _generate += 1 } }
        func bumpAdmission() { lock.withLock { _admission += 1 } }
        func bumpSettlement() { lock.withLock { _settlement += 1 } }
        var generate: Int { lock.withLock { _generate } }
        var admission: Int { lock.withLock { _admission } }
        var settlement: Int { lock.withLock { _settlement } }
    }

    private struct Outcome {
        let status: Int
        let body: [String: Any]
        let raw: Data
        let generate: Int
        let admission: Int
        let settlement: Int
    }

    // MARK: - Setup / teardown

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "(SIMIGO_HOME / SIMIGO_CACHE_ROOT / SIMIGO_STATE_GRAPH_STORE) so no real "
                + "model or user state is touched")
        }
        isolationRoot = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        // Guard the claim: the authority the server opens must live inside the isolation root.
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root: \(SimiGoPaths.databaseURL.path)")
        XCTAssertTrue(
            ExecutionStateGraphStore.defaultStoreURL().path.hasPrefix(
                (graphStore as NSString).standardizingPath),
            "reference graph resolves outside the isolated state-graph root")

        // Model-free snapshot DIRECTORY (never a weight load): identity is pure
        // disk re-derivation, so this is a legitimate stand-in for the runtime's
        // own model path on both the admission and settlement sides.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoHTTPIntegrationModelFree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"http-integration-model-free-stand-in"}"#.utf8).write(
            to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        // Real transport identity + registry + paired client (test-only fixture,
        // independent of the model).
        host = try LOCALBAuthorizedE2E.makeHost()
    }

    override func tearDown() {
        if let modelPath {
            try? FileManager.default.removeItem(atPath: modelPath)
        }
        host = nil
        super.tearDown()
    }

    // MARK: - Real-store helpers

    /// Stage a live, SETTLED, identity-matched ES anchor in the product's
    /// authoritative store — exactly the precondition a real continuation needs:
    /// admission reads this settlement's value back under the SAME model snapshot
    /// the runtime would present as consumer. Returns the state id to send as
    /// `previous_es_state_id`.
    @MainActor
    private func stageSettledAnchor(value: String) throws -> String {
        let store = ExecutionStateGraphStore()
        let producer = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let root = try store.create()
        try store.continueState(root, input: value)
        let state = try XCTUnwrap(store.state(root.id))
        _ = try store.settleProducerResult(
            generatedText: "RESULT=\(value)",
            boundToState: state,
            producerIdentity: producer
        )
        return state.id
    }

    @MainActor
    private func freshStore() -> ExecutionStateGraphStore { ExecutionStateGraphStore() }

    @MainActor
    private func totalSettlements() throws -> Int {
        try XCTUnwrap(freshStore().esis).readSettlementReceipts().count
    }

    @MainActor
    private func totalBindings() throws -> Int {
        try XCTUnwrap(freshStore().esis).count("settlement_bindings")
    }

    @MainActor
    private func projectionReceiptCount(stateID: String) -> Int {
        (freshStore().document.settlements ?? []).filter { $0.stateID == stateID }.count
    }

    /// Narrowly scoped SQL against the isolated DB, used ONLY to inject a real
    /// lower-layer write fault exactly when a producer identity binding is written.
    private func executeIsolatedSQLite(_ sql: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open(SimiGoPaths.databaseURL.path, &handle)
        guard openRC == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw NSError(
                domain: "ResponsesContinuationHTTPIntegrationTests.SQLite",
                code: Int(openRC),
                userInfo: [NSLocalizedDescriptionKey: "could not open isolated test database"])
        }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &message)
        if rc != SQLITE_OK {
            let detail = message.map { String(cString: $0) } ?? "SQLite error \(rc)"
            if let message { sqlite3_free(message) }
            throw NSError(
                domain: "ResponsesContinuationHTTPIntegrationTests.SQLite",
                code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: detail])
        }
        if let message { sqlite3_free(message) }
    }

    // MARK: - Server construction (real product wiring, text-only generation)

    private func makeServer(
        stub: Stub,
        wireAdmission: Bool,
        wireSettlement: Bool,
        faultAdmissionRawError: Bool
    ) -> HTTPServer {
        let mp = modelPath!
        var admission: ContinuationAdmissionHandler?
        if faultAdmissionRawError {
            // A raw, NON-typed error straight from the handler, proving the ROUTE
            // maps an unknown admission-stage error to 500 (never a 422 business
            // refusal). `testAdmissionInternalFaultThroughRealClosureIs500` below
            // proves the REAL production closure now preserves that distinction
            // rather than swallowing internal faults into a 422.
            admission = { _ in
                stub.bumpAdmission()
                throw NSError(
                    domain: "ResponsesContinuationHTTPIntegrationTests.EngineFault",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "injected admission engine fault"])
            }
        } else if wireAdmission {
            // The REAL admission authority, mirroring the NativeMLX wiring.
            admission = { esStateID in
                stub.bumpAdmission()
                let value = try await MainActor.run {
                    try SimiGoProducerIdentity.recoverForContinuation(
                        stateID: esStateID, modelPath: mp)
                }
                return ContinuationAdmissionOutcome(esStateID: esStateID, recoveredValue: value)
            }
        }

        var settlement: ContinuationSettlementHandler?
        if wireSettlement {
            // The REAL production settlement adapter.
            let inner = makeNativeMLXContinuationSettlementHandler(modelPath: mp)
            settlement = { text, anchor in
                stub.bumpSettlement()
                return try await inner(text, anchor)
            }
        }

        return HTTPServer(
            port: port,
            modelId: "http-integration-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _ in
                // The ONLY substituted component: a text stand-in, no model.
                stub.bumpGenerate()
                onChunk(stub.text)
                return GenerationResult(text: stub.text, usage: nil)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "t/main", modelId: "http-integration-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            continuationAdmission: admission,
            continuationSettlement: settlement
        )
    }

    /// Start a real LOCALB-TLS server on the product route, send ONE authorized
    /// request over a real socket, and stop the server. Returns the actual HTTP
    /// status + decoded body + the stage counters.
    @MainActor
    private func dispatch(
        body: [String: Any],
        emit text: String,
        wireAdmission: Bool = true,
        wireSettlement: Bool = true,
        faultAdmissionRawError: Bool = false
    ) async throws -> Outcome {
        let stub = Stub()
        stub.text = text
        let server = makeServer(
            stub: stub,
            wireAdmission: wireAdmission,
            wireSettlement: wireSettlement,
            faultAdmissionRawError: faultAdmissionRawError)
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)  // let the listener reach ready
        defer { server.stop() }

        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        // A bounded retry absorbs the listener-ready race on a real socket.
        for _ in 0..<3 {
            do {
                let result = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST",
                    path: "/v1/responses",
                    contentType: "application/json", body: payload)
                responseData = result.0
                httpResponse = result.1
                break
            } catch let error as URLError
            where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let sent = try XCTUnwrap(httpResponse, "authorized request never reached the server: \(String(describing: lastError))")
        let data = responseData ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return Outcome(
            status: sent.statusCode,
            body: json,
            raw: data,
            generate: stub.generate,
            admission: stub.admission,
            settlement: stub.settlement)
    }

    private func baseJSON(_ extra: [String: Any] = [:]) -> [String: Any] {
        var json: [String: Any] = [
            "model": "http-integration-test",
            "input": "continue",
        ]
        for (k, v) in extra { json[k] = v }
        return json
    }

    private func errorInfo(_ o: Outcome) -> [String: Any]? { o.body["error"] as? [String: Any] }
    private func errorKind(_ o: Outcome) -> String? { errorInfo(o)?["error_kind"] as? String }
    private func reasonCode(_ o: Outcome) -> String? { errorInfo(o)?["reason_code"] as? String }
    private func settlementPayload(_ o: Outcome) -> [String: Any]? {
        o.body["continuation_settlement"] as? [String: Any]
    }

    // MARK: - 1) Valid continuation settles over the real HTTP entry

    @MainActor
    func testValidContinuationSettlesAndReportsAuthoritativeID() async throws {
        let value = "HTTP-SETTLE-7101"
        let anchor = try stageSettledAnchor(value: value)
        let own = SimiGoProducerIdentity.identity(fromPath: modelPath)

        // The real settlement will run over the ACTUAL generated text, so the
        // stand-in must satisfy the declared result contract for this anchor.
        let o = try await dispatch(
            body: baseJSON([
                "previous_es_state_id": anchor,
                "continuation_settle": true,
            ]),
            emit: "RESULT=\(value)")

        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(o.admission, 1, "real admission invoked once")
        XCTAssertEqual(o.generate, 1, "generation ran exactly once")
        XCTAssertEqual(o.settlement, 1, "real settlement invoked once")

        let payload = try XCTUnwrap(settlementPayload(o), "200 must carry a settlement payload")
        XCTAssertEqual(payload["identity_binding_published"] as? Bool, true)
        let responseID = try XCTUnwrap(payload["settlement_id"] as? String)
        XCTAssertFalse(responseID.isEmpty)

        // THE decisive claim: the id the HTTP response reports is a settlement
        // the AUTHORITATIVE store actually committed in this request's atomic
        // transaction, published WITH the re-derived producer identity binding.
        let bindings = try XCTUnwrap(freshStore().esis)
            .settlementBindings(settlementID: responseID)
        XCTAssertEqual(bindings[SimiGoSettlementIdentityBinding.modelKey],
                       SimiGoSettlementIdentityBinding.digest(own.model),
                       "the reported settlement_id must exist in the DB bound to THIS runtime identity")
        XCTAssertEqual(bindings[SimiGoSettlementIdentityBinding.tokenizerKey],
                       SimiGoSettlementIdentityBinding.digest(own.tokenizer))

        // The in-memory receipt projection and the authoritative settlement row
        // agree with the reported id.
        XCTAssertEqual(projectionReceiptCount(stateID: anchor), 2,
                       "staged settlement + this request's settlement both project")
        let rows = try XCTUnwrap(freshStore().esis).readSettlementReceipts()
        XCTAssertTrue(rows.contains { $0.id.uuidString == responseID },
                      "the authoritative store must contain a settlement row with the reported id")
    }

    // MARK: - 2) Legacy request keeps the original contract untouched

    @MainActor
    func testLegacyRequestKeepsOriginalContract() async throws {
        let o = try await dispatch(body: baseJSON(), emit: "just a normal answer")

        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        XCTAssertNotNil(o.body["output"], "legacy Responses shape preserved")
        // No new continuation keys leak into a non-opt-in response.
        XCTAssertNil(o.body["continuation_settlement"],
                     "a request that never opts in must gain no settlement payload")
        XCTAssertNil(errorInfo(o))
        // No authority touched; ordinary generation still runs exactly once.
        XCTAssertEqual(o.admission, 0)
        XCTAssertEqual(o.settlement, 0)
        XCTAssertEqual(o.generate, 1)
    }

    // MARK: - 3) Settlement asked WITHOUT an anchor -> 400, no generation

    @MainActor
    func testSettlementWithoutAnchorFailsClosed400() async throws {
        let o = try await dispatch(
            body: baseJSON(["continuation_settle": true]),
            emit: "RESULT=unused")

        XCTAssertEqual(o.status, 400)
        XCTAssertEqual(errorKind(o), "SETTLEMENT_WITHOUT_ANCHOR")
        XCTAssertEqual(o.generate, 0, "must fail closed before generation")
        XCTAssertEqual(o.admission, 0)
        XCTAssertEqual(o.settlement, 0)
    }

    // MARK: - 4) Settlement authority NOT wired -> 503 before admission and generation

    @MainActor
    func testMissingSettlementAuthorityFailsClosed503BeforeAdmission() async throws {
        let anchor = try stageSettledAnchor(value: "HTTP-NOSTL-7104")
        let o = try await dispatch(
            body: baseJSON([
                "previous_es_state_id": anchor,
                "continuation_settle": true,
            ]),
            emit: "RESULT=HTTP-NOSTL-7104",
            wireSettlement: false)

        XCTAssertEqual(o.status, 503)
        XCTAssertEqual(errorKind(o), "SETTLEMENT_AUTHORITY_UNAVAILABLE")
        XCTAssertEqual(o.admission, 0, "missing settlement authority must not even reach admission")
        XCTAssertEqual(o.generate, 0)
    }

    // MARK: - 5) Admission authority NOT wired -> 503, no generation

    @MainActor
    func testMissingAdmissionAuthorityFailsClosed503() async throws {
        let anchor = try stageSettledAnchor(value: "HTTP-NOADM-7105")
        let o = try await dispatch(
            body: baseJSON(["previous_es_state_id": anchor]),
            emit: "anything",
            wireAdmission: false)

        XCTAssertEqual(o.status, 503)
        XCTAssertEqual(errorKind(o), "ADMISSION_AUTHORITY_UNAVAILABLE")
        XCTAssertEqual(o.generate, 0, "an unwired continuation must fail closed, never fall back")
    }

    // MARK: - 6) Real admission refuses an un-settleable anchor -> 422, no generation

    @MainActor
    func testAdmissionRefusalIs422NotSilentFallback() async throws {
        // A phantom anchor: real recoverForContinuation -> admitContinuation
        // refuses (no settled, identity-verifiable IS record) as a typed refusal.
        let ghost = "es-state-no-such-anchor-\(UUID().uuidString)"
        let o = try await dispatch(
            body: baseJSON([
                "previous_es_state_id": ghost,
                "continuation_settle": true,
            ]),
            emit: "RESULT=ghost")

        XCTAssertEqual(o.status, 422)
        XCTAssertEqual(errorKind(o), "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(o.generate, 0, "a real admission refusal is terminal, not a fallback to generation")
        XCTAssertEqual(o.settlement, 0)
    }

    // MARK: - 7) Blank anchor -> 422 invalid_anchor BEFORE the authority

    @MainActor
    func testBlankAnchorFailsClosed422InvalidAnchor() async throws {
        let o = try await dispatch(
            body: baseJSON(["previous_es_state_id": "   "]),
            emit: "anything")

        XCTAssertEqual(o.status, 422)
        XCTAssertEqual(errorKind(o), "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(reasonCode(o), "invalid_anchor")
        XCTAssertEqual(o.admission, 0, "blank anchor must fail closed before the authority")
        XCTAssertEqual(o.generate, 0)
    }

    // MARK: - 8) Admission engine fault (raw, non-typed) -> 500, never 422

    @MainActor
    func testAdmissionEngineFaultMapsTo500() async throws {
        let anchor = try stageSettledAnchor(value: "HTTP-ADMF-7108")
        let o = try await dispatch(
            body: baseJSON(["previous_es_state_id": anchor, "continuation_settle": true]),
            emit: "RESULT=HTTP-ADMF-7108",
            faultAdmissionRawError: true)

        XCTAssertEqual(o.status, 500, "an unknown admission error must not masquerade as a refusal")
        XCTAssertEqual(errorKind(o), "ADMISSION_ENGINE_ERROR")
        XCTAssertNotEqual(errorKind(o), "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(o.generate, 0)
    }

    // MARK: - 9) Native result-contract rejection -> 422, no settlement written

    @MainActor
    func testNativeContractRejectionIs422AndWritesNothing() async throws {
        let anchor = try stageSettledAnchor(value: "HTTP-CONTRACT-7109")
        let settlementsBefore = try totalSettlements()
        let bindingsBefore = try totalBindings()

        // Admission recovers the anchor's value; generation returns text that
        // VIOLATES the declared contract, so only the later settlement refuses.
        let o = try await dispatch(
            body: baseJSON([
                "previous_es_state_id": anchor,
                "continuation_settle": true,
            ]),
            emit: "NOISE-OFF-CONTRACT")

        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(errorKind(o), "NATIVE_RESULT_CONTRACT_REJECTED")
        XCTAssertNotEqual(errorKind(o), "INPUT_ADMISSION_REFUSED",
                          "post-generation contract rejection is its own class")
        XCTAssertNil(settlementPayload(o), "a refused contract never yields a settlement payload")
        XCTAssertEqual(o.generate, 1, "generation ran; only the later contract refused")
        XCTAssertEqual(o.settlement, 1, "the real settlement authority ran once and refused")
        // The native gate throws BEFORE any store write: nothing was committed.
        XCTAssertEqual(try totalSettlements(), settlementsBefore,
                       "a contract rejection must add no settlement row")
        XCTAssertEqual(try totalBindings(), bindingsBefore,
                       "a contract rejection must add no identity binding row")
    }

    // MARK: - 10) Settlement / identity-binding write failure -> 500, no partial commit

    @MainActor
    func testSettlementWriteFailureIs500WithNoPartialCommit() async throws {
        let value = "HTTP-ATOMIC-7110"
        let anchor = try stageSettledAnchor(value: value)
        let settlementsBefore = try totalSettlements()
        let bindingsBefore = try totalBindings()
        let projectionBefore = projectionReceiptCount(stateID: anchor)

        let trigger = "fail_http_identity_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        try executeIsolatedSQLite("""
        CREATE TRIGGER \(trigger)
        BEFORE INSERT ON settlement_bindings
        WHEN NEW.name = 'producer.model_identity'
        BEGIN
            SELECT RAISE(ABORT, 'injected producer identity write failure');
        END;
        """)
        defer { try? executeIsolatedSQLite("DROP TRIGGER IF EXISTS \(trigger)") }

        let o = try await dispatch(
            body: baseJSON([
                "previous_es_state_id": anchor,
                "continuation_settle": true,
            ]),
            emit: "RESULT=\(value)")

        XCTAssertEqual(o.status, 500, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(errorKind(o), "SETTLEMENT_ENGINE_ERROR")
        XCTAssertNil(settlementPayload(o), "a failed settlement must never return a success payload")
        XCTAssertEqual(o.generate, 1, "generation happened; only the authoritative write failed")

        // Nothing partial survived: settlement rows, binding rows and the in-memory
        // projection are all unchanged from before the request.
        XCTAssertEqual(try totalSettlements(), settlementsBefore,
                       "settlement insert must roll back when the identity insert fails")
        XCTAssertEqual(try totalBindings(), bindingsBefore,
                       "identity + constraint bindings must all roll back")
        XCTAssertEqual(projectionReceiptCount(stateID: anchor), projectionBefore,
                       "the graph projection must not gain a receipt before commit")
    }

    // MARK: - 11) Stream + settle -> HTTP 501 at the TRANSPORT level (fix A)

    /// Contract fix A regression: a streaming Responses request that asks for
    /// post-generation settlement must be refused with HTTP 501 on the STATUS
    /// LINE — before the SSE `200` header is committed — never as a `200` that
    /// carries a mid-stream `501`. It refuses before generation, before the
    /// admission authority, and never produces a settlement.
    @MainActor
    func testStreamWithSettleIsRejected501BeforeSSEHeaders() async throws {
        let value = "HTTP-STREAM-7111"
        let anchor = try stageSettledAnchor(value: value)

        let o = try await dispatch(
            body: baseJSON([
                "model": "http-integration-test",
                "input": "continue",
                "stream": true,
                "previous_es_state_id": anchor,
                "continuation_settle": true,
            ]),
            emit: "RESULT=\(value)")

        // The decisive transport-level claim: the STATUS LINE is 501, not 200.
        XCTAssertEqual(o.status, 501, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(errorKind(o), "SETTLEMENT_UNSUPPORTED_ON_STREAM")
        // A structured JSON error terminal — NOT a committed SSE body.
        XCTAssertNotNil(errorInfo(o), "501 must carry the structured error object")
        XCTAssertNil(o.body["output"], "no completed response body on the rejected stream")
        XCTAssertNil(settlementPayload(o),
                     "stream + settle must never silently produce a settlement")
        // Fail-closed ordering: rejected before the authority and before generation.
        XCTAssertEqual(o.admission, 0, "the unsupported combination is refused before admission")
        XCTAssertEqual(o.generate, 0, "settle-on-stream refuses before generation")
        XCTAssertEqual(o.settlement, 0, "the settlement authority must not run on the stream path")
    }

    // MARK: - 12) Real admission closure internal fault -> 500, never 422 (fix B)

    /// Contract fix B regression, driven through the SAME closure NativeMLX wires
    /// (not a stub). When the authoritative store itself faults — SQLite cannot
    /// open its database file, so `ensureESIS()` fails, `admitContinuation` throws
    /// `ExecutionGraphError.storeUnavailable`, a NON-`SimiGoISAdmission.Refusal`
    /// error — the real `recoverForContinuation` must surface it so the route
    /// returns 500 ADMISSION_ENGINE_ERROR. The pre-fix behaviour swallowed it into
    /// a 422 INPUT_ADMISSION_REFUSED. Contrast test 8 (route mapping via an
    /// injected stub) and test 6 (a genuine semantic refusal still 422).
    @MainActor
    func testAdmissionInternalFaultThroughRealClosureIs500() async throws {
        let dbURL = SimiGoPaths.databaseURL
        // Make the authority genuinely UNOPENABLE. A short garbage file is NOT
        // enough: an existing WAL/SHM pair lets SQLite rebuild a valid image and
        // admission then returns a legitimate empty-store refusal (422). Occupy
        // the database path with a DIRECTORY (after clearing every sidecar) so
        // `sqlite3_open_v2` fails with SQLITE_CANTOPEN regardless of WAL state.
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + suffix)
        }
        try FileManager.default.createDirectory(at: dbURL, withIntermediateDirectories: true)
        // Restore isolation for sibling tests: drop the directory + sidecars so
        // the next store open recreates a clean database (an absent path yields a
        // valid empty store — i.e. a 422 noSettlement, the neighbour distinction).
        defer {
            for suffix in ["", "-wal", "-shm", "-journal"] {
                try? FileManager.default.removeItem(atPath: dbURL.path + suffix)
            }
        }

        let o = try await dispatch(
            body: baseJSON([
                "previous_es_state_id": "es-anchor-irrelevant",
                "continuation_settle": true,
            ]),
            emit: "RESULT=never-generated")

        XCTAssertEqual(o.status, 500, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(errorKind(o), "ADMISSION_ENGINE_ERROR",
                       "a real store fault must not masquerade as a 422 business refusal")
        XCTAssertNotEqual(errorKind(o), "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(o.generate, 0, "an admission fault must fail closed before generation")
        XCTAssertEqual(o.settlement, 0)
    }
}
