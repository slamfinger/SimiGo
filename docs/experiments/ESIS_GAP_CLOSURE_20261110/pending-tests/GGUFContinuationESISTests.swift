import Foundation
import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

/// Model-free regression for the GGUF continuation path (I2–I5).
///
/// It drives the REAL product store and the REAL GGUF settlement adapter — no
/// weights, no generation — to prove the properties the product claims:
///
/// 1. A settled continuation creates a child Execution State whose model
///    identity is the producer that generated it, and a settlement whose
///    declared parent settlement is a REAL `dependency_edges` row.
/// 2. Invalidating the parent closes the child through that edge, so it is not
///    decorative.
/// 3. The GGUF result contract is task-specific: an echo of the recovered value
///    or a result produced for a different task is refused and writes nothing.
/// 4. The parent settlement is re-validated inside the child settlement
///    transaction; a settlement that was valid at admission but invalid at
///    settlement time cannot commit.
/// 5. `/v1/models` states each runtime's actual wiring instead of claiming a
///    capability the runtime does not have.
///
/// Isolation: requires the injected isolated roots, otherwise XCTSkip.
final class GGUFContinuationESISTests: XCTestCase {

    private var isolationRoot: URL!
    private var modelPath: String!
    private var gguf: GGUFModelIdentity!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through the isolated xctestrun "
                + "(SIMIGO_HOME / SIMIGO_STATE_GRAPH_STORE) so no real state is written")
        }
        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SimiGoGGUFContinuation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        modelPath = dir.appendingPathComponent("model.gguf").path
        try Data("GGUF-stand-in-weights-for-continuation-tests".utf8)
            .write(to: URL(fileURLWithPath: modelPath))
        gguf = try GGUFModelIdentity.resolve(path: modelPath)
    }

    override func tearDown() {
        if let modelPath {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: modelPath).deletingLastPathComponent())
        }
        super.tearDown()
    }

    // MARK: - Staging helpers (the production settlement authority)

    /// Stage a parent ES whose settled reference-contract value is `value`.
    @MainActor
    private func stagedParent(
        _ store: ExecutionStateGraphStore,
        value: String
    ) throws -> (state: ExecutionStateRecord, settlementID: String) {
        let parent = try store.continueState(try store.create(), input: value)
        try store.settleProducerResult(
            generatedText: "RESULT=\(value)",
            boundToState: parent,
            producerIdentity: gguf.producer)
        let esis = try XCTUnwrap(store.esis)
        let settlementID = try XCTUnwrap(esis.latestSettlementID(forStateID: parent.id))
        return (parent, settlementID)
    }

    private func ggufResult(_ value: String, task: String = GGUFContinuationContract.version) -> String {
        "TASK=\(task)\nANSWER=\(value)"
    }

    /// Drive the REAL GGUF settlement adapter with the bindings the REAL
    /// pre-generation admission verified.
    @MainActor
    private func settleGGUF(
        store: ExecutionStateGraphStore,
        parent: ExecutionStateRecord,
        admitted: SimiGoISAdmission.Admitted,
        child: String,
        generatedText: String,
        parentSettlementID: String? = nil
    ) throws -> ContinuationSettlementOutcome {
        try settleForGGUFContinuation(
            store: store,
            request: ContinuationSettlementRequest(
                generatedText: generatedText,
                parentESStateID: parent.id,
                childESStateID: child,
                verifiedBindings: admitted.verifiedBindings,
                parentSettlementID: parentSettlementID ?? admitted.settlementID),
            identity: gguf)
    }

    @MainActor
    private func assertNothingWasWritten(
        _ store: ExecutionStateGraphStore,
        child: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNil(store.state(child), "no child ES may be projected on refusal", file: file, line: line)
        let esis = try XCTUnwrap(store.esis, file: file, line: line)
        XCTAssertNil(
            try esis.latestSettlementID(forStateID: child),
            "no settlement may exist for a refused child", file: file, line: line)
        XCTAssertFalse(
            try esis.readGraph().states.contains { $0.id == child },
            "no child ES row may be persisted on refusal", file: file, line: line)
    }

    // MARK: - 1. Real dependency edge + producer identity

    @MainActor
    func testSettlementRecordsRealDependencyAndChildUsesProducerIdentity() throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "41")
        let admitted = try store.admitContinuation(
            stateID: staged.state.id, consumer: gguf.producer)
        XCTAssertEqual(admitted.recoveredValue, "41")
        XCTAssertEqual(admitted.settlementID, staged.settlementID)

        let child = "es-gguf-child-\(UUID().uuidString.lowercased())"
        let outcome = try settleGGUF(
            store: store, parent: staged.state, admitted: admitted, child: child,
            generatedText: ggufResult("42"))

        XCTAssertEqual(outcome.childESStateID, child)
        XCTAssertTrue(outcome.identityBindingPublished)

        let esis = try XCTUnwrap(store.esis)
        XCTAssertEqual(try esis.settlementValidity(outcome.settlementID), "valid")
        XCTAssertEqual(
            try esis.upstreamDependencyClosure(ofSettlement: outcome.settlementID),
            [staged.settlementID],
            "the child settlement must cite the parent settlement admission verified")

        let childRow = try XCTUnwrap(
            try esis.readGraph().states.first { $0.id == child })
        XCTAssertEqual(childRow.parentID, staged.state.id)
        XCTAssertEqual(childRow.position, staged.state.position + 1)
        XCTAssertEqual(childRow.lifecycle, "active")
        XCTAssertEqual(childRow.nextInput, "42",
                       "the child must round-trip the value it settled")
        XCTAssertEqual(childRow.modelIdentity, gguf.producer.model,
                       "the child ES names the producer that generated it")
        XCTAssertNotEqual(childRow.modelIdentity, staged.state.modelIdentity,
                          "the child identity is not copied from the parent state")

        // Chainability: the returned child id admits on its own, and it admits
        // THROUGH the IS value, not through any field echoed by the client.
        let next = try store.admitContinuation(stateID: child, consumer: gguf.producer)
        XCTAssertEqual(next.recoveredValue, "42")
        XCTAssertEqual(next.settlementID, outcome.settlementID)

        // The parent keeps exactly the settlement admission read: the
        // continuation did not re-settle it.
        XCTAssertEqual(try esis.latestSettlementID(forStateID: staged.state.id), staged.settlementID)
    }

    // MARK: - 2. The edge is real: parent invalidation closes the child

    @MainActor
    func testParentInvalidationClosesChildThroughDependencyClosure() throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "7")
        let admitted = try store.admitContinuation(
            stateID: staged.state.id, consumer: gguf.producer)
        let child = "es-gguf-child-\(UUID().uuidString.lowercased())"
        let outcome = try settleGGUF(
            store: store, parent: staged.state, admitted: admitted, child: child,
            generatedText: ggufResult("8"))

        let esis = try XCTUnwrap(store.esis)
        let invalidated = try esis.invalidateSettlement(staged.settlementID)
        XCTAssertTrue(
            invalidated.contains(outcome.settlementID),
            "a child citing its parent settlement must be closed out with it")
        XCTAssertEqual(try esis.settlementValidity(outcome.settlementID), "invalid")

        XCTAssertThrowsError(
            try store.admitContinuation(stateID: child, consumer: gguf.producer)
        ) { error in
            guard case SimiGoISAdmission.Refusal.invalidated(let id) = error else {
                return XCTFail("expected an invalidation refusal, got \(error)")
            }
            XCTAssertEqual(id, outcome.settlementID)
        }
    }

    // MARK: - 3. Task-specific contract: echo and wrong task are refused

    @MainActor
    func testEchoOfRecoveredValueIsRefusedAndWritesNothing() throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "41")
        let admitted = try store.admitContinuation(
            stateID: staged.state.id, consumer: gguf.producer)
        let child = "es-gguf-echo-\(UUID().uuidString.lowercased())"

        XCTAssertThrowsError(try settleGGUF(
            store: store, parent: staged.state, admitted: admitted, child: child,
            generatedText: ggufResult("41")
        )) { error in
            let terminal = continuationSettlementTerminal(for: error)
            XCTAssertEqual(terminal.status, 422)
            XCTAssertEqual(terminal.errorKind, "NATIVE_RESULT_CONTRACT_REJECTED")
        }
        try assertNothingWasWritten(store, child: child)
    }

    @MainActor
    func testWrongTaskTagIsRefusedAndWritesNothing() throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "41")
        let admitted = try store.admitContinuation(
            stateID: staged.state.id, consumer: gguf.producer)
        let child = "es-gguf-wrong-task-\(UUID().uuidString.lowercased())"

        XCTAssertThrowsError(try settleGGUF(
            store: store, parent: staged.state, admitted: admitted, child: child,
            generatedText: ggufResult("42", task: "gguf-continuation/v2")
        )) { error in
            let terminal = continuationSettlementTerminal(for: error)
            XCTAssertEqual(terminal.status, 422)
            XCTAssertEqual(terminal.errorKind, "NATIVE_RESULT_CONTRACT_REJECTED")
        }
        try assertNothingWasWritten(store, child: child)
    }

    // MARK: - 4. Parent settlement is re-validated inside the child transaction

    @MainActor
    func testMissingAdmittedParentSettlementIsRefusedBeforeWrite() throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "5")
        let admitted = try store.admitContinuation(
            stateID: staged.state.id, consumer: gguf.producer)
        let child = "es-gguf-no-parent-\(UUID().uuidString.lowercased())"

        XCTAssertThrowsError(try settleGGUF(
            store: store, parent: staged.state, admitted: admitted, child: child,
            generatedText: ggufResult("6"), parentSettlementID: ""
        )) { error in
            XCTAssertEqual(
                continuationSettlementTerminal(for: error).errorKind,
                "SETTLEMENT_ENGINE_ERROR",
                "a settlement without its admitted parent is an engine fault, not a business refusal")
        }
        try assertNothingWasWritten(store, child: child)
    }

    @MainActor
    func testParentInvalidatedAfterAdmissionCannotCommitChild() throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "9")
        let admitted = try store.admitContinuation(
            stateID: staged.state.id, consumer: gguf.producer)

        // Valid when admission read it, invalid by the time settlement runs.
        let esis = try XCTUnwrap(store.esis)
        _ = try esis.invalidateSettlement(admitted.settlementID)
        XCTAssertEqual(try esis.settlementValidity(admitted.settlementID), "invalid")

        let child = "es-gguf-stale-parent-\(UUID().uuidString.lowercased())"
        XCTAssertThrowsError(try settleGGUF(
            store: store, parent: staged.state, admitted: admitted, child: child,
            generatedText: ggufResult("10")
        )) { error in
            XCTAssertEqual(
                continuationSettlementTerminal(for: error).errorKind,
                "SETTLEMENT_ENGINE_ERROR")
        }
        try assertNothingWasWritten(store, child: child)
    }

    // MARK: - 5. Capability declaration states the runtime's actual wiring

    func testBootstrapDeclaresRuntimeDifferences() throws {
        let none = HTTPServer.simigoBootstrapDocument(
            health: true, observedAt: Date(),
            declaration: .init(esContinuation: false, kvRepresentation: false))
        let ggufDoc = HTTPServer.simigoBootstrapDocument(
            health: true, observedAt: Date(),
            declaration: .init(esContinuation: true, kvRepresentation: false))
        let mlxDoc = HTTPServer.simigoBootstrapDocument(
            health: true, observedAt: Date(),
            declaration: .init(esContinuation: true, kvRepresentation: true))

        func capabilities(_ doc: [String: Any]) -> [String: Any] {
            doc["capabilities"] as? [String: Any] ?? [:]
        }
        func esState(_ doc: [String: Any]) -> String? {
            (capabilities(doc)["es"] as? [String: Any])?["state"] as? String
        }
        func kv(_ doc: [String: Any]) -> [String: Any] {
            capabilities(doc)["memory_kv_cache"] as? [String: Any] ?? [:]
        }
        func carrierKV(_ doc: [String: Any]) -> [String: Any] {
            ((doc["carrier"] as? [String: Any])?["kv_cache"] as? [String: Any]) ?? [:]
        }

        XCTAssertEqual(esState(none), "not_wired_on_this_runtime")
        XCTAssertEqual(esState(ggufDoc), "supported")

        // GGUF records no IS-authorized prefix representation: it must say so
        // instead of inheriting the MLX claim.
        XCTAssertEqual(kv(ggufDoc)["state"] as? String, "not_supported_on_this_runtime")
        XCTAssertEqual(kv(ggufDoc)["authority"] as? String, "none")
        XCTAssertEqual(carrierKV(ggufDoc)["mode"] as? String, "memory")
        XCTAssertEqual(carrierKV(ggufDoc)["disk_persistence"] as? Bool, false)

        XCTAssertEqual(kv(mlxDoc)["state"] as? String, "supported")
        XCTAssertEqual(kv(mlxDoc)["authority"] as? String, "is_authorized_bindings")
        // Even the runtime that records bindings never claims the ENGINE's
        // cache is an IS-persistent representation (Phase 1 boundary).
        XCTAssertEqual(
            kv(mlxDoc)["persistent_representation_claimed"] as? Bool, false)
        XCTAssertEqual(
            (capabilities(mlxDoc)["is"] as? [String: Any])?["state"] as? String,
            "supported")
    }
}

/// I4 at the REAL HTTP entry (plaintext loopback, model-free generation stub).
///
/// A committed continuation must publish `simigo.es_state_id` and
/// `simigo.settlement_id` naming the SAME settlement record, and an admission
/// refusal must still happen BEFORE any generation call.
final class GGUFContinuationAnchorHTTPTests: XCTestCase {

    private var isolationRoot: URL!
    private var modelPath: String!
    private var gguf: GGUFModelIdentity!
    private var host: LOCALBAuthorizedE2E.Host!

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        private var _admit = 0
        nonisolated(unsafe) var text = ""
        func bump() { lock.withLock { _generate += 1 } }
        func bumpAdmit() { lock.withLock { _admit += 1 } }
        var generate: Int { lock.withLock { _generate } }
        var admit: Int { lock.withLock { _admit } }
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through the isolated xctestrun "
                + "(SIMIGO_HOME / SIMIGO_STATE_GRAPH_STORE) so no real state is written")
        }
        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SimiGoGGUFAnchor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        modelPath = dir.appendingPathComponent("model.gguf").path
        try Data("GGUF-stand-in-weights-for-anchor-tests".utf8)
            .write(to: URL(fileURLWithPath: modelPath))
        gguf = try GGUFModelIdentity.resolve(path: modelPath)
        host = try LOCALBAuthorizedE2E.makeHost()
    }

    override func tearDown() {
        if let modelPath {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: modelPath).deletingLastPathComponent())
        }
        host = nil
        super.tearDown()
    }

    @MainActor
    private func stagedParent(
        _ store: ExecutionStateGraphStore,
        value: String
    ) throws -> (state: ExecutionStateRecord, settlementID: String) {
        let parent = try store.continueState(try store.create(), input: value)
        try store.settleProducerResult(
            generatedText: "RESULT=\(value)",
            boundToState: parent,
            producerIdentity: gguf.producer)
        let esis = try XCTUnwrap(store.esis)
        let settlementID = try XCTUnwrap(esis.latestSettlementID(forStateID: parent.id))
        return (parent, settlementID)
    }

    @MainActor
    private func withServer(
        port: Int,
        stub: Stub,
        wireAdmission: Bool = true,
        wireSettlement: Bool = true,
        _ run: () async throws -> Void
    ) async throws {
        // The same wiring ManagedGGUFRuntime installs: ONE resolved identity
        // feeds admission, settlement and the information-turn producer.
        let identity = gguf!
        let server = HTTPServer(
            port: port,
            modelId: "gguf-continuation-anchor-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _, _ in
                stub.bump()
                onChunk(stub.text)
                return GenerationResult(
                    text: stub.text, usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target, _ in
                SessionCacheMetadata(
                    storageKey: "t/\(target)",
                    modelId: "gguf-continuation-anchor-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _, _ in
                BranchDeletionOutcome(
                    deletedBranch: "", hadLiveSession: false,
                    hadCheckpointFile: false,
                    remainingLiveBranches: [],
                    remainingCheckpointBranches: [])
            },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            continuationAdmission: wireAdmission ? { esStateID in
                stub.bumpAdmit()
                let admitted = try await MainActor.run {
                    try SimiGoProducerIdentity.recoverForContinuation(
                        stateID: esStateID, consumer: identity.producer)
                }
                return ContinuationAdmissionOutcome(
                    esStateID: esStateID,
                    recoveredValue: admitted.recoveredValue,
                    verifiedBindings: admitted.verifiedBindings,
                    kvBindings: [:],
                    parentSettlementID: admitted.settlementID)
            } : nil,
            continuationSettlement: wireSettlement ? makeGGUFContinuationSettlementHandler(
                identity: identity) : nil,
            informationTurnProducer: {
                InformationTurnProducer(
                    modelIdentity: identity.modelIdentity,
                    identity: identity.producer)
            })
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer { server.stop() }
        try await run()
    }

    private func send(
        port: Int,
        body: [String: Any]
    ) async throws -> (status: Int, body: [String: Any], raw: Data) {
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        for _ in 0..<3 {
            do {
                let (data, response) = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST",
                    path: "/v1/responses",
                    contentType: "application/json", body: payload)
                let json = (try? JSONSerialization.jsonObject(with: data))
                    as? [String: Any] ?? [:]
                return (response.statusCode, json, data)
            } catch let error as URLError
            where error.code == .cannotConnectToHost
                || error.code == .networkConnectionLost {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func continuationBody(
        session: String, parentID: String
    ) -> [String: Any] {
        [
            "model": "gguf-continuation-anchor-test",
            "input": "continue the settled value",
            "session_id": session,
            "stream": false,
            "previous_es_state_id": parentID,
            "continuation_settle": true,
        ]
    }

    @MainActor
    func testCommittedContinuationPublishesMatchingAnchors() async throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "41")
        let stub = Stub()
        stub.text = "TASK=\(GGUFContinuationContract.version)\nANSWER=42"

        try await withServer(port: 59_383, stub: stub) {
            let sent = try await send(
                port: 59_383,
                body: continuationBody(
                    session: "anchor-\(UUID().uuidString)",
                    parentID: staged.state.id))
            XCTAssertEqual(sent.status, 200, String(decoding: sent.raw, as: UTF8.self))
            XCTAssertEqual(stub.generate, 1)

            let settlement = try XCTUnwrap(
                sent.body["continuation_settlement"] as? [String: Any])
            let child = try XCTUnwrap(
                settlement["child_es_state_id"] as? String)
            let settlementID = try XCTUnwrap(
                settlement["settlement_id"] as? String)
            let simigo = try XCTUnwrap(
                sent.body["simigo"] as? [String: Any],
                "a committed settlement must publish its ES/IS anchor")
            XCTAssertEqual(
                simigo["es_state_id"] as? String, child,
                "the anchor ES is the child the settlement belongs to")
            XCTAssertEqual(
                simigo["settlement_id"] as? String, settlementID,
                "both ids name the same committed settlement")

            let esis = try XCTUnwrap(store.esis)
            XCTAssertEqual(try esis.settlementValidity(settlementID), "valid")
            // The turn's own retrieval demand is a second, legitimate upstream
            // dependency; the parent settlement must be among them.
            XCTAssertTrue(
                try esis.upstreamDependencyClosure(ofSettlement: settlementID)
                    .contains(staged.settlementID),
                "the HTTP continuation records the real dependency edge")
            XCTAssertEqual(
                try esis.latestSettlementID(forStateID: child), settlementID)
            XCTAssertEqual(
                try esis.latestSettlementID(forStateID: staged.state.id),
                staged.settlementID,
                "the parent is not re-settled by the continuation")
        }
    }

    // MARK: - E1 negative controls: every refusal precedes generation

    /// The six admission-stage outcomes of the v0.1 continuation contract,
    /// driven through the REAL HTTP entry with the REAL GGUF identity wiring.
    /// Each one must terminate the request before the generate handler runs and
    /// before anything is written.
    @MainActor
    private func snapshot(
        _ store: ExecutionStateGraphStore
    ) throws -> (states: Int, settlements: Int) {
        let esis = try XCTUnwrap(store.esis)
        return (try esis.readGraph().states.count,
                try esis.readSettlementReceipts().count)
    }

    @MainActor
    private func assertRefusedBeforeAnyWork(
        store: ExecutionStateGraphStore,
        before: (states: Int, settlements: Int),
        stub: Stub,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            stub.generate, 0,
            "the refusal must happen before any model generation", file: file, line: line)
        let after = try snapshot(store)
        XCTAssertEqual(
            after.states, before.states,
            "a refused continuation writes no ES row", file: file, line: line)
        XCTAssertEqual(
            after.settlements, before.settlements,
            "a refused continuation writes no settlement", file: file, line: line)
    }

    @MainActor
    func testN1SettleWithoutAnchorRefusedBeforeGeneration() async throws {
        let store = ExecutionStateGraphStore()
        let before = try snapshot(store)
        let stub = Stub()
        try await withServer(port: 59_385, stub: stub) {
            let sent = try await send(port: 59_385, body: [
                "model": "gguf-continuation-anchor-test",
                "input": "continue",
                "session_id": "n1-\(UUID().uuidString)",
                "stream": false,
                "continuation_settle": true,
            ])
            XCTAssertEqual(sent.status, 400, String(decoding: sent.raw, as: UTF8.self))
            let error = try XCTUnwrap(sent.body["error"] as? [String: Any])
            XCTAssertEqual(error["error_kind"] as? String, "SETTLEMENT_WITHOUT_ANCHOR")
            XCTAssertEqual(stub.admit, 0, "no anchor means no authority may be consulted")
            try assertRefusedBeforeAnyWork(store: store, before: before, stub: stub)
        }
    }

    @MainActor
    func testN2BlankAnchorRefusedBeforeAuthority() async throws {
        let store = ExecutionStateGraphStore()
        let before = try snapshot(store)
        let stub = Stub()
        try await withServer(port: 59_386, stub: stub) {
            let sent = try await send(port: 59_386, body: [
                "model": "gguf-continuation-anchor-test",
                "input": "continue",
                "session_id": "n2-\(UUID().uuidString)",
                "stream": false,
                "previous_es_state_id": "   ",
            ])
            XCTAssertEqual(sent.status, 422, String(decoding: sent.raw, as: UTF8.self))
            let error = try XCTUnwrap(sent.body["error"] as? [String: Any])
            XCTAssertEqual(error["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
            XCTAssertEqual(error["reason_code"] as? String, "invalid_anchor")
            XCTAssertEqual(stub.admit, 0, "a blank anchor never reaches the authority")
            try assertRefusedBeforeAnyWork(store: store, before: before, stub: stub)
        }
    }

    @MainActor
    func testN3MissingSettlementAuthorityRefusedBeforeAdmission() async throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "11")
        let before = try snapshot(store)
        let stub = Stub()
        try await withServer(port: 59_387, stub: stub, wireSettlement: false) {
            let sent = try await send(
                port: 59_387,
                body: continuationBody(
                    session: "n3-\(UUID().uuidString)", parentID: staged.state.id))
            XCTAssertEqual(sent.status, 503, String(decoding: sent.raw, as: UTF8.self))
            let error = try XCTUnwrap(sent.body["error"] as? [String: Any])
            XCTAssertEqual(error["error_kind"] as? String, "SETTLEMENT_AUTHORITY_UNAVAILABLE")
            XCTAssertEqual(stub.admit, 0, "settlement authority is checked before admission")
            try assertRefusedBeforeAnyWork(store: store, before: before, stub: stub)
        }
    }

    @MainActor
    func testN4MissingAdmissionAuthorityRefusedBeforeGeneration() async throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "12")
        let before = try snapshot(store)
        let stub = Stub()
        try await withServer(port: 59_388, stub: stub, wireAdmission: false) {
            let sent = try await send(port: 59_388, body: [
                "model": "gguf-continuation-anchor-test",
                "input": "continue",
                "session_id": "n4-\(UUID().uuidString)",
                "stream": false,
                "previous_es_state_id": staged.state.id,
            ])
            XCTAssertEqual(sent.status, 503, String(decoding: sent.raw, as: UTF8.self))
            let error = try XCTUnwrap(sent.body["error"] as? [String: Any])
            XCTAssertEqual(error["error_kind"] as? String, "ADMISSION_AUTHORITY_UNAVAILABLE")
            try assertRefusedBeforeAnyWork(store: store, before: before, stub: stub)
        }
    }

    @MainActor
    func testN5UnknownAnchorIsRefusedBeforeGeneration() async throws {
        let store = ExecutionStateGraphStore()
        let before = try snapshot(store)
        let stub = Stub()
        try await withServer(port: 59_389, stub: stub) {
            let sent = try await send(port: 59_389, body: continuationBody(
                session: "n5-\(UUID().uuidString)",
                parentID: "es-no-such-anchor-\(UUID().uuidString)"))
            XCTAssertEqual(sent.status, 422, String(decoding: sent.raw, as: UTF8.self))
            let error = try XCTUnwrap(sent.body["error"] as? [String: Any])
            XCTAssertEqual(error["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
            XCTAssertEqual(error["reason_code"] as? String, "is_refusal")
            XCTAssertEqual(stub.admit, 1, "the real IS authority ran and refused")
            try assertRefusedBeforeAnyWork(store: store, before: before, stub: stub)
        }
    }

    @MainActor
    func testN6ForeignProducerIdentityIsRefusedBeforeGeneration() async throws {
        let store = ExecutionStateGraphStore()
        // A settled parent written by the reference path: its settlement carries
        // NO producer identity binding. Absence is not a wildcard, so the GGUF
        // consumer must refuse it rather than continue another producer's state.
        let foreign = try store.continueState(try store.create(), input: "7")
        try store.settleProducerResult(
            generatedText: "RESULT=7", boundToState: foreign)
        let before = try snapshot(store)
        let stub = Stub()
        try await withServer(port: 59_390, stub: stub) {
            let sent = try await send(port: 59_390, body: continuationBody(
                session: "n6-\(UUID().uuidString)", parentID: foreign.id))
            XCTAssertEqual(sent.status, 422, String(decoding: sent.raw, as: UTF8.self))
            let error = try XCTUnwrap(sent.body["error"] as? [String: Any])
            XCTAssertEqual(error["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
            XCTAssertEqual(error["reason_code"] as? String, "is_refusal")
            XCTAssertEqual(stub.admit, 1, "the real identity check ran and refused")
            try assertRefusedBeforeAnyWork(store: store, before: before, stub: stub)
        }
    }

    @MainActor
    func testInvalidatedParentIsRefusedBeforeGeneration() async throws {
        let store = ExecutionStateGraphStore()
        let staged = try stagedParent(store, value: "100")
        let esis = try XCTUnwrap(store.esis)
        _ = try esis.invalidateSettlement(staged.settlementID)
        let settlementsBefore = try esis.readSettlementReceipts().count

        let stub = Stub()
        stub.text = "TASK=\(GGUFContinuationContract.version)\nANSWER=101"
        try await withServer(port: 59_384, stub: stub) {
            let sent = try await send(
                port: 59_384,
                body: continuationBody(
                    session: "refused-\(UUID().uuidString)",
                    parentID: staged.state.id))
            XCTAssertEqual(sent.status, 422, String(decoding: sent.raw, as: UTF8.self))
            let error = try XCTUnwrap(sent.body["error"] as? [String: Any])
            XCTAssertEqual(error["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
            XCTAssertEqual(
                stub.generate, 0,
                "the refusal happens before any model generation")
            XCTAssertEqual(
                try esis.readSettlementReceipts().count, settlementsBefore,
                "a refused continuation writes no settlement")
        }
    }
}
