import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// C entry proof at the REAL product HTTP dispatch: `/v1/responses` with a
/// typed `recompute_policy` must either reach the injected managed authority or
/// be refused before any model work. Requests without a C-scope field must keep
/// the pre-C path byte-identical.
///
/// The only substituted component is the managed authority itself (a closure,
/// never the model); every assertion runs through the signed dispatch:
///
///   signed HTTPS POST /v1/responses
///     -> handleResponsesNonStreaming / handleResponsesStreaming
///     -> managedContinuationPreflight -> managedContinuationStep -> terminal
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class ResponsesManagedContinuationHTTPTests: XCTestCase {

    private let port = 59_359

    private var host: LOCALBAuthorizedE2E.Host!

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
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
        host = try LOCALBAuthorizedE2E.makeHost()
    }

    override func tearDown() {
        host = nil
        super.tearDown()
    }

    // MARK: - Server + one real authorized request

    @MainActor
    private func dispatch(
        body: [String: Any],
        managed: ManagedContinuationHandler? = nil,
        emit text: String = "RESULT=generated"
    ) async throws -> Outcome {
        let stub = Stub()
        let server = HTTPServer(
            port: port,
            modelId: "http-managed-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _ in
                stub.bump()
                onChunk(text)
                return GenerationResult(text: text, usage: nil)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "http-managed-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            managedContinuation: managed
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

    /// The body prints an absent reason code as JSON null; either form means no
    /// code was exposed.
    private func assertNoReasonCode(
        _ info: [String: Any], _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let value = info["reason_code"]
        XCTAssertTrue(
            value == nil || value is NSNull, message,
            file: file, line: line)
    }

    private func managedBody(
        anchor: String? = "es-anchor-http",
        policy: Any = "never",
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var json: [String: Any] = [
            "model": "http-managed-test",
            "input": "continue",
        ]
        if let anchor { json["previous_es_state_id"] = anchor }
        json[SimiGoRecomputePolicy.requestKey] = policy
        for (k, v) in extra { json[k] = v }
        return json
    }

    private func committedResult(reused: Bool = false) -> ManagedContinuationResult {
        ManagedContinuationResult(
            content: "MANAGED-9001",
            toolCalls: [],
            usage: nil,
            executionID: "exec-http-1",
            childESStateID: "es-child-http-1",
            settlementID: "settle-http-1",
            declaredSnapshotID: "obj-declared-http-1",
            finalSnapshotID: "obj-final-http-1",
            fingerprint: "fp-http-1",
            modelCalls: reused ? 0 : 1,
            settlementsWritten: reused ? 0 : 1,
            replayable: true,
            recomputed: false,
            reusedExecution: reused)
    }

    // MARK: - 1) Validation order and public 400 allowlist

    @MainActor
    func testPolicyWithoutAnchorIsARequestFormatError() async throws {
        let o = try await dispatch(body: managedBody(anchor: nil))
        XCTAssertEqual(o.status, 400, String(decoding: o.raw, as: UTF8.self))
        let info = try XCTUnwrap(errorInfo(o))
        XCTAssertEqual(info["error_kind"] as? String, "INVALID_REQUEST_ENTRY")
        XCTAssertEqual(info["reason_code"] as? String, "recompute_policy_invalid")
        XCTAssertEqual(o.generate, 0, "a request-format error never reaches the model")
    }

    @MainActor
    func testUnsupportedPolicyValueIsReportedBeforeTheConflict() async throws {
        let o = try await dispatch(body: managedBody(
            policy: "sometimes",
            extra: ["settlement_consumption": ["source_settlement_id": "s-1", "query": "q"]]))
        XCTAssertEqual(o.status, 400, String(decoding: o.raw, as: UTF8.self))
        let info = try XCTUnwrap(errorInfo(o))
        XCTAssertEqual(info["reason_code"] as? String, "recompute_policy_invalid",
                       "value legality is decided before mutual exclusion")
        XCTAssertEqual(o.generate, 0)
    }

    @MainActor
    func testPolicyWithSettlementConsumptionConflicts() async throws {
        let o = try await dispatch(body: managedBody(
            extra: ["settlement_consumption": ["source_settlement_id": "s-1", "query": "q"]]))
        XCTAssertEqual(o.status, 400, String(decoding: o.raw, as: UTF8.self))
        let info = try XCTUnwrap(errorInfo(o))
        XCTAssertEqual(info["error_kind"] as? String, "INVALID_REQUEST_ENTRY")
        XCTAssertEqual(info["reason_code"] as? String, "recompute_policy_conflict")
        XCTAssertEqual(o.generate, 0)
    }

    @MainActor
    func testCScopeFieldWithoutPolicyIsRefused() async throws {
        var body: [String: Any] = ["model": "http-managed-test", "input": "continue"]
        body["idempotency_key"] = "caller-key-1"
        let o = try await dispatch(body: body)
        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        let info = try XCTUnwrap(errorInfo(o))
        XCTAssertEqual(info["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
        assertNoReasonCode(info, "shape refusals carry no public code")
        XCTAssertEqual(o.generate, 0, "an ignored C-scope field is refused, never dropped")
    }

    // MARK: - 2) Fail closed without an authority

    @MainActor
    func testUnwiredManagedAuthorityFailsClosed() async throws {
        let o = try await dispatch(body: managedBody())
        XCTAssertEqual(o.status, 503, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(
            errorInfo(o)?["error_kind"] as? String,
            "ADMISSION_AUTHORITY_UNAVAILABLE")
        XCTAssertEqual(o.generate, 0)
    }

    // MARK: - 3) Streaming refuses before the SSE head

    @MainActor
    func testStreamingManagedRequestIsRefusedBeforeSse() async throws {
        var body = managedBody()
        body["stream"] = true
        let o = try await dispatch(body: body, managed: { _ in
            XCTFail("a streaming C request must never reach the managed authority")
            return ManagedContinuationResult(
                content: "", toolCalls: [], usage: nil,
                executionID: "", childESStateID: "", settlementID: "",
                declaredSnapshotID: "", finalSnapshotID: "", fingerprint: "",
                modelCalls: 0, settlementsWritten: 0, replayable: nil,
                recomputed: false, reusedExecution: false)
        })
        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(
            errorInfo(o)?["error_kind"] as? String,
            "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(o.generate, 0)
        XCTAssertNil(o.body["managed_continuation"])
    }

    // MARK: - 4) A committed execution returns its receipt

    @MainActor
    func testCommittedManagedExecutionReturnsItsReceipt() async throws {
        let result = committedResult()
        let o = try await dispatch(
            body: managedBody(policy: "allow_safe_recompute"),
            managed: { request in
                XCTAssertEqual(request.anchorESStateID, "es-anchor-http")
                XCTAssertEqual(request.policy, .allowSafeRecompute)
                return result
            })
        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(o.generate, 0, "the managed pipeline owns the model call")
        let payload = try XCTUnwrap(o.body["managed_continuation"] as? [String: Any])
        XCTAssertEqual(payload["outcome"] as? String, "committed")
        XCTAssertEqual(payload["execution_id"] as? String, "exec-http-1")
        XCTAssertEqual(payload["es_state_id"] as? String, "es-child-http-1")
        XCTAssertEqual(payload["parent_es_state_id"] as? String, "es-anchor-http")
        XCTAssertEqual(payload["settlement_id"] as? String, "settle-http-1")
        XCTAssertEqual(payload["declared_snapshot_id"] as? String, "obj-declared-http-1")
        XCTAssertEqual(payload["final_snapshot_id"] as? String, "obj-final-http-1")
        XCTAssertEqual(payload["idempotency_fingerprint"] as? String, "fp-http-1")
        XCTAssertEqual(payload["model_calls"] as? Int, 1)
        XCTAssertEqual(payload["settlements_written"] as? Int, 1)
        XCTAssertEqual(payload["replayable"] as? Bool, true)
        XCTAssertEqual(payload["recompute_policy"] as? String, "allow_safe_recompute")
        XCTAssertEqual(o.body["store"] as? Bool, true)
    }

    @MainActor
    func testReplayIsNotStoredAsANewTurn() async throws {
        let o = try await dispatch(
            body: managedBody(),
            managed: { _ in self.committedResult(reused: true) })
        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        let payload = try XCTUnwrap(o.body["managed_continuation"] as? [String: Any])
        XCTAssertEqual(payload["outcome"] as? String, "replayed")
        XCTAssertEqual(payload["reused_execution"] as? Bool, true)
        XCTAssertEqual(o.body["store"] as? Bool, false,
                       "a replay produced no new turn")
    }

    // MARK: - 5) Only allowlisted codes leave the process

    @MainActor
    func testInternalRefusalCauseIsNotExposed() async throws {
        let o = try await dispatch(
            body: managedBody(),
            managed: { _ in
                throw ManagedContinuationFailure.refused(
                    SimiGoManagedRefusal.Refusal(
                        cause: .snapshotUsedUndeclared, origin: .snapshot, phase: .p2))
            })
        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        let info = try XCTUnwrap(errorInfo(o))
        XCTAssertEqual(info["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
        assertNoReasonCode(info, "an internal cause has no public code")
        let text = String(decoding: o.raw, as: UTF8.self)
        XCTAssertFalse(text.contains("snapshot_used_undeclared"),
                       "internal refusal causes never reach the response body")
        XCTAssertFalse(text.contains("P2"), "internal stage markers never reach the body")
        XCTAssertEqual(o.generate, 0)
    }

    @MainActor
    func testAllowlistedRefusalCodeIsExposed() async throws {
        let o = try await dispatch(
            body: managedBody(),
            managed: { _ in
                throw ManagedContinuationFailure.refused(
                    SimiGoManagedRefusal.Refusal(
                        cause: .idempotencyConflict, origin: .idempotency, phase: .p2))
            })
        XCTAssertEqual(o.status, 422, String(decoding: o.raw, as: UTF8.self))
        let info = try XCTUnwrap(errorInfo(o))
        XCTAssertEqual(info["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(info["reason_code"] as? String, "idempotency_conflict")
    }

    // MARK: - 6) Absent field: ordinary generation unchanged

    @MainActor
    func testAbsentCScopeFieldsKeepOrdinaryGeneration() async throws {
        let o = try await dispatch(body: [
            "model": "http-managed-test",
            "input": "hello",
        ])
        XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
        XCTAssertEqual(o.generate, 1)
        XCTAssertNil(o.body["managed_continuation"])
    }
}
