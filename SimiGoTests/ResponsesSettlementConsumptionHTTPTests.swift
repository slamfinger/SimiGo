import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// Stage B end-to-end proof at the REAL product HTTP entry: `/v1/responses`
/// with the typed `settlement_consumption` opt-in must return the settled value
/// with ZERO generation calls, while the same endpoint without the field keeps
/// its ordinary semantics.
///
/// Every assertion goes through the real dispatch:
///
///   signed HTTPS POST /v1/responses
///     -> HTTPServer.route -> handleResponsesNonStreaming
///     -> settlementConsumptionStep -> the REAL adapter
///        (`makeNativeMLXSettlementConsumptionHandler` ->
///         `SimiGoProducerIdentity.consumeSettlement` ->
///         `ExecutionStateGraphStore.consumeSettlement` ->
///         `SimiGoSettlementConsumption.consume`, one BEGIN IMMEDIATE)
///     -> completed 200 / typed refusal
///
/// The only substituted component is generation (a counter, never a model).
/// The consuming identity is the runtime's own model-path-derived identity, so
/// the source settlement is staged with that same identity.
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class ResponsesSettlementConsumptionHTTPTests: XCTestCase {

    private let port = 59_358

    private var isolationRoot: URL!
    private var modelPath: String!
    private var host: LOCALBAuthorizedE2E.Host!
    private var workRoot: URL!

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        nonisolated(unsafe) var text = ""
        func bump() { lock.withLock { _generate += 1 } }
        var generate: Int { lock.withLock { _generate } }
    }

    private struct Outcome {
        let status: Int
        let body: [String: Any]
        let raw: Data
        let generate: Int
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
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoConsumptionModelFree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"consumption-http-model-free-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoConsumptionRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        try Data("alpha beta gamma".utf8)
            .write(to: workRoot.appendingPathComponent("notes.md"))

        host = try LOCALBAuthorizedE2E.makeHost()
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        if let workRoot { try? FileManager.default.removeItem(at: workRoot) }
        host = nil
        super.tearDown()
    }

    // MARK: - Staging a consumable settled unit in the authoritative store

    @MainActor
    private func stageConsumableSource(
        value: String,
        query: String,
        rootID: String = "work"
    ) throws -> String {
        let store = ExecutionStateGraphStore()
        let db = try XCTUnwrap(store.esis)
        let producer = SimiGoProducerIdentity.identity(fromPath: modelPath)
        _ = try db.settleWorkRootContents(rootID: rootID, rootURL: workRoot)

        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: value,
            contractJSON: SimiGoInformationLoop.chatResultContractJSON,
            verifiedBindings: [:])
        let stateID = "es-source-" + UUID().uuidString.lowercased()
        try db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: producer.model,
            position: 1, continuationID: UUID().uuidString,
            anchor: settled.payloadDigest, lifecycle: "active", createdAt: Date())
        let settlementID = try db.recordNativeSettlement(settled, stateID: stateID)
        try db.recordIdentityBindings(settlementID: settlementID, identity: producer)
        _ = try db.declareSettlementReuseContract(
            settlementID: settlementID,
            contractID: SimiGoSettlementConsumption.Contract.contractID,
            demandClass: SimiGoSettlementConsumption.Contract.demandClass,
            contractVersion: SimiGoSettlementConsumption.Contract.version,
            query: query,
            rootIDs: [rootID])
        return settlementID
    }

    private func consumptionBody(
        settlementID: String,
        query: String = "alpha facts",
        rootIDs: [String] = ["work"],
        allowRecompute: Bool = false,
        contractID: String = SimiGoSettlementConsumption.Contract.contractID,
        demandClass: String = SimiGoSettlementConsumption.Contract.demandClass,
        version: String = SimiGoSettlementConsumption.Contract.version,
        extract: String = SimiGoSettlementConsumption.Contract.defaultExtractField,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var json: [String: Any] = [
            "model": "http-consumption-test",
            "input": "consume",
            "settlement_consumption": [
                "source_settlement_id": settlementID,
                "contract": [
                    "id": contractID,
                    "demand_class": demandClass,
                    "version": version,
                    "extract": extract,
                ],
                "query": query,
                "root_ids": rootIDs,
                "allow_recompute": allowRecompute,
            ],
        ]
        for (k, v) in extra { json[k] = v }
        return json
    }

    // MARK: - Server + one real authorized request

    @MainActor
    private func dispatch(
        body: [String: Any],
        emit text: String = "RESULT=generated",
        wireConsumption: Bool = true
    ) async throws -> Outcome {
        let stub = Stub()
        stub.text = text
        var consumption: SettlementConsumptionHandler?
        if wireConsumption {
            let mp = modelPath!
            let inner = makeNativeMLXSettlementConsumptionHandler(modelPath: mp)
            consumption = { entry in
                try await inner(entry)
            }
        }
        let server = HTTPServer(
            port: port,
            modelId: "http-consumption-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _ in
                stub.bump()
                onChunk(stub.text)
                return GenerationResult(text: stub.text, usage: nil)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "http-consumption-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            settlementConsumption: consumption
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer { server.stop() }

        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
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
        let sent = try XCTUnwrap(
            httpResponse,
            "authorized request never reached the server: \(String(describing: lastError))")
        let data = responseData ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return Outcome(status: sent.statusCode, body: json, raw: data, generate: stub.generate)
    }

    private func errorInfo(_ o: Outcome) -> [String: Any]? {
        o.body["error"] as? [String: Any]
    }

    private func outputText(_ o: Outcome) -> String? {
        guard let output = o.body["output"] as? [[String: Any]],
              let content = output.first?["content"] as? [[String: Any]]
        else { return nil }
        return content.first?["text"] as? String
    }

    // MARK: - 1) Explicit consumption: settled value, zero generation

    @MainActor
    func testExplicitConsumptionServesSettledValueWithZeroGeneration() async throws {
        let value = "CONSUMED-8801"
        let source = try stageConsumableSource(value: value, query: "alpha facts")
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)

        let o = try await dispatch(
            body: consumptionBody(
                settlementID: source,
                extra: ["settlement_consumption": [
                    "source_settlement_id": source,
                    "contract": [
                        "id": SimiGoSettlementConsumption.Contract.contractID,
                        "demand_class": SimiGoSettlementConsumption.Contract.demandClass,
                        "version": SimiGoSettlementConsumption.Contract.version,
                        "extract": SimiGoSettlementConsumption.Contract.defaultExtractField,
                    ],
                    "query": "alpha facts",
                    "root_ids": ["work"],
                    "identity": [
                        "model_identity": identity.model,
                        "tokenizer_identity": identity.tokenizer,
                    ],
                ]]))

        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(o.generate, 0, "consumption must not call the model")
        XCTAssertEqual(outputText(o), value, "the served text is the settled value")

        let payload = try XCTUnwrap(o.body["settlement_consumption"] as? [String: Any])
        XCTAssertEqual(payload["outcome"] as? String, "consumed")
        XCTAssertEqual(payload["model_calls"] as? Int, 0)
        XCTAssertEqual(payload["source_settlement_id"] as? String, source)
        XCTAssertEqual(payload["derived_settlement"] as? Bool, true)
        XCTAssertEqual(o.body["store"] as? Bool, false,
                       "a consumed unit is not stored as generated response history")

        let consumerES = try XCTUnwrap(payload["consumer_es_state_id"] as? String)
        let consumerSettlement = try XCTUnwrap(payload["consumer_settlement_id"] as? String)
        XCTAssertNotEqual(consumerES, consumerSettlement)

        // The consumer settlement exists in the authoritative store, is marked
        // derived, binds the consumer namespace (never a producer claim), and
        // carries no KV representation.
        let store = ExecutionStateGraphStore()
        let db = try XCTUnwrap(store.esis)
        let receipts = try db.readSettlementReceipts()
        XCTAssertTrue(receipts.contains { $0.id.uuidString == consumerSettlement && $0.stateID == consumerES })
        let rows = try db.settlementConsumptions(consumerStateID: consumerES)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.modelCalls, 0)
        XCTAssertEqual(rows.first?.sourceSettlementID, source)
        let bindings = try db.settlementBindings(settlementID: consumerSettlement)
        XCTAssertNotNil(bindings[SimiGoSettlementIdentityBinding.consumerModelKey])
        XCTAssertNil(bindings[SimiGoSettlementIdentityBinding.modelKey])
        XCTAssertTrue(bindings.keys.allSatisfy { !$0.hasPrefix("kv.") })

        // Chainable: the derived settlement admits as a continuation anchor.
        let chained = try store.admitContinuation(stateID: consumerES, consumer: identity)
        XCTAssertEqual(chained.recoveredValue, value)
    }

    // MARK: - 2) Absent field: ordinary generation unchanged

    @MainActor
    func testAbsentFieldKeepsOrdinaryGeneration() async throws {
        let o = try await dispatch(body: [
            "model": "http-consumption-test",
            "input": "hello",
        ])
        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(o.generate, 1, "no opt-in means the ordinary path runs")
        XCTAssertNil(o.body["settlement_consumption"])
    }

    // MARK: - 3) Refusals never generate, never fall back

    @MainActor
    func testMalformedAndUnknownSourceAreRefusedWithoutGeneration() async throws {
        let malformed = try await dispatch(body: [
            "model": "http-consumption-test",
            "input": "consume",
            "settlement_consumption": ["query": "alpha facts"],
        ])
        XCTAssertEqual(malformed.status, 422, String(decoding: malformed.raw, as: UTF8.self))
        XCTAssertEqual(errorInfo(malformed)?["reason_code"] as? String, "invalid_entry")
        XCTAssertEqual(malformed.generate, 0)
        XCTAssertFalse(String(decoding: malformed.raw, as: UTF8.self).contains("CONSUMED-"))

        let unknown = try await dispatch(body: consumptionBody(settlementID: "no-such-settlement"))
        XCTAssertEqual(unknown.status, 422, String(decoding: unknown.raw, as: UTF8.self))
        XCTAssertEqual(errorInfo(unknown)?["reason_code"] as? String, "contract_undeclared")
        XCTAssertEqual(unknown.generate, 0)
    }

    @MainActor
    func testIdentityAssertionMismatchIsRefused() async throws {
        let source = try stageConsumableSource(value: "IDENTITY-8822", query: "alpha facts")
        var body = consumptionBody(settlementID: source)
        body["settlement_consumption"] = [
            "source_settlement_id": source,
            "contract": [
                "id": SimiGoSettlementConsumption.Contract.contractID,
                "demand_class": SimiGoSettlementConsumption.Contract.demandClass,
                "version": SimiGoSettlementConsumption.Contract.version,
                "extract": SimiGoSettlementConsumption.Contract.defaultExtractField,
            ],
            "query": "alpha facts",
            "root_ids": ["work"],
            "identity": [
                "model_identity": "not-this-model",
                "tokenizer_identity": "not-this-tokenizer",
            ],
        ]
        let o = try await dispatch(body: body)
        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(errorInfo(o)?["reason_code"] as? String, "identity_mismatch")
        XCTAssertEqual(o.generate, 0)
    }

    // MARK: - 3b) Native admission denials are business refusals (422)

    /// Row counts the refusal path must leave untouched. A refusal is a read-only
    /// verdict: no consumption row, no derived settlement, no consumer state.
    private struct Ledger: Equatable {
        let settlements: Int
        let states: Int
        let consumptions: Int
        let edges: Int
    }

    @MainActor
    private func ledger() throws -> Ledger {
        let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
        return Ledger(
            settlements: try db.count("settlements"),
            states: try db.count("execution_states"),
            consumptions: try db.count("settlement_consumptions"),
            edges: try db.count("dependency_edges"))
    }

    @MainActor
    func testInvalidatedSourceIsRefusedAsSourceNotValid() async throws {
        let source = try stageConsumableSource(value: "INVALIDATED-8877", query: "alpha facts")
        let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
        let invalidated = try db.invalidateSettlement(source)
        XCTAssertTrue(invalidated.contains(source), "the source itself must be invalid")
        XCTAssertEqual(try db.settlementValidity(source), "invalid")

        let before = try ledger()
        let o = try await dispatch(body: consumptionBody(settlementID: source))

        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        let info = try XCTUnwrap(errorInfo(o))
        XCTAssertEqual(info["error_kind"] as? String, "SETTLEMENT_CONSUMPTION_REFUSED")
        XCTAssertEqual(info["reason_code"] as? String, "source_not_valid")
        XCTAssertEqual(o.generate, 0, "a refused admission performs no model work")
        XCTAssertNil(o.body["settlement_consumption"])
        XCTAssertEqual(try ledger(), before,
                       "refusal must not write a consumption row or derived settlement")
    }

    @MainActor
    func testUpstreamDependencyInvalidIsRefusedAsDependencyInvalid() async throws {
        let dependency = try stageConsumableSource(value: "DEPENDENCY-8888", query: "beta facts")
        let source = try stageConsumableSource(value: "DEPENDENT-8899", query: "alpha facts")
        let db = try XCTUnwrap(ExecutionStateGraphStore().esis)

        // The dependency is invalidated BEFORE the edge is recorded, so the
        // source's own validity row stays "valid": admission has to refuse on
        // the upstream closure, not on the named source.
        try db.invalidateSettlement(dependency)
        try db.addDependency(fromSettlement: source, toSettlement: dependency)
        XCTAssertEqual(try db.settlementValidity(source), "valid")
        XCTAssertTrue(
            try db.upstreamDependencyClosure(ofSettlement: source).contains(dependency),
            "the invalid dependency must be in the upstream closure")

        let before = try ledger()
        let o = try await dispatch(body: consumptionBody(settlementID: source))

        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        let info = try XCTUnwrap(errorInfo(o))
        XCTAssertEqual(info["error_kind"] as? String, "SETTLEMENT_CONSUMPTION_REFUSED")
        XCTAssertEqual(info["reason_code"] as? String, "dependency_invalid")
        XCTAssertEqual(o.generate, 0, "a refused admission performs no model work")
        XCTAssertNil(o.body["settlement_consumption"])
        XCTAssertEqual(try ledger(), before,
                       "refusal must not write a consumption row or derived settlement")
    }

    @MainActor
    func testChangedDemandRefusesWithoutExplicitRecompute() async throws {
        let source = try stageConsumableSource(value: "CHANGED-8833", query: "alpha facts")
        let o = try await dispatch(
            body: consumptionBody(settlementID: source, query: "beta facts"))
        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(errorInfo(o)?["reason_code"] as? String, "canonical_input_mismatch")
        XCTAssertEqual(o.generate, 0, "an unpermitted mismatch is a refusal, not a fallback")
    }

    @MainActor
    func testExplicitRecomputeRunsGenerationAndReportsReason() async throws {
        let source = try stageConsumableSource(value: "RECOMPUTE-8844", query: "alpha facts")
        let o = try await dispatch(
            body: consumptionBody(
                settlementID: source, query: "beta facts", allowRecompute: true),
            emit: "FRESH-GENERATION")
        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(o.generate, 1, "explicit recompute runs the normal generation path")
        XCTAssertEqual(outputText(o), "FRESH-GENERATION")
        let payload = try XCTUnwrap(o.body["settlement_consumption"] as? [String: Any])
        XCTAssertEqual(payload["outcome"] as? String, "recompute")
        XCTAssertFalse((payload["reason"] as? String ?? "").isEmpty,
                       "a recompute must name why reuse did not apply")
        XCTAssertNil(payload["consumption_id"])
    }

    // MARK: - 4) Streaming path refuses before any SSE head

    @MainActor
    func testStreamingConsumptionIsRefusedBeforeSse() async throws {
        let source = try stageConsumableSource(value: "STREAM-8855", query: "alpha facts")
        var body = consumptionBody(settlementID: source)
        body["stream"] = true
        let o = try await dispatch(body: body)
        XCTAssertEqual(o.status, 501, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(
            errorInfo(o)?["error_kind"] as? String,
            "SETTLEMENT_CONSUMPTION_UNSUPPORTED_ON_STREAM")
        XCTAssertEqual(o.generate, 0)
    }

    // MARK: - 5) Unwired authority fails closed

    @MainActor
    func testUnwiredConsumptionAuthorityRefuses() async throws {
        let source = try stageConsumableSource(value: "UNWIRED-8866", query: "alpha facts")
        let o = try await dispatch(
            body: consumptionBody(settlementID: source),
            wireConsumption: false)
        XCTAssertEqual(o.status, 503, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(
            errorInfo(o)?["error_kind"] as? String,
            "SETTLEMENT_CONSUMPTION_AUTHORITY_UNAVAILABLE")
        XCTAssertEqual(o.generate, 0)
    }
}
