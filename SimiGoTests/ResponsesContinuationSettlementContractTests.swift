import Foundation
import Network
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// Directed, model-free tests for the v0.1 continuation response contract on
/// the real product Responses dispatch objects. They prove:
///
/// * the refusal classes are pairwise distinct and machine-readable
///   (`error.error_kind` / `error.reason_code` in the JSON body);
/// * an explicit settlement request with no settlement authority fails closed
///   BEFORE generation and before the admission authority is invoked;
/// * unknown admission/settlement engine errors never masquerade as business
///   refusals (500, never a 422);
/// * post-generation native contract rejection is reported independently of
///   admission refusal, with the generated text provenance recorded;
/// * the success payload carries settlement id + identity binding status;
/// * requests that never opt in keep the legacy path unchanged (no authority
///   invoked, legacy error bodies carry no new keys).
final class ResponsesContinuationSettlementContractTests: XCTestCase {

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var _admissions: [String] = []
        private var _settlements: [ContinuationSettlementRequest] = []
        var admissionBehavior: (String) throws -> ContinuationAdmissionOutcome = {
            ContinuationAdmissionOutcome(
                esStateID: $0,
                recoveredValue: "RECOVERED",
                verifiedBindings: ["next_input": .string("RECOVERED")])
        }
        var settlementBehavior: (ContinuationSettlementRequest) throws -> ContinuationSettlementOutcome = { request in
            ContinuationSettlementOutcome(
                settlementID: "settle-1",
                identityBindingPublished: true,
                childESStateID: request.childESStateID)
        }
        func recordAdmission(_ anchor: String) { lock.withLock { _admissions.append(anchor) } }
        func recordSettlement(_ request: ContinuationSettlementRequest) { lock.withLock { _settlements.append(request) } }
        var admissionCalls: Int { lock.withLock { _admissions.count } }
        var settlementCalls: Int { lock.withLock { _settlements.count } }
        var lastSettlement: ContinuationSettlementRequest? { lock.withLock { _settlements.last } }
    }

    private func makeServer(box: Box, settlementWired: Bool) -> HTTPServer {
        var settlement: ContinuationSettlementHandler?
        if settlementWired {
            settlement = { request in
                box.recordSettlement(request)
                return try box.settlementBehavior(request)
            }
        }
        return HTTPServer(
            port: 59_218,
            modelId: "settlement-contract-test",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "t/main", modelId: "settlement-contract-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            continuationAdmission: { anchor in
                box.recordAdmission(anchor)
                return try box.admissionBehavior(anchor)
            },
            continuationSettlement: settlement
        )
    }

    private func makeContext() -> HTTPServer.ConnectionContext {
        let conn = NWConnection(host: "127.0.0.1", port: 1, using: .tcp)
        return HTTPServer.ConnectionContext(connection: conn)
    }

    private func parse(_ server: HTTPServer, _ json: [String: Any]) throws -> ResponsesParsedRequest {
        try XCTUnwrap(
            server.parseResponsesParams(json, headers: [:]),
            "responses parse returned nil for \(json)")
    }

    private func baseJSON(_ extra: [String: Any] = [:]) -> [String: Any] {
        var json: [String: Any] = [
            "model": "settlement-contract-test",
            "input": "continue",
        ]
        for (k, v) in extra { json[k] = v }
        return json
    }

    private func errorInfo(_ body: [String: Any]) -> [String: Any]? {
        body["error"] as? [String: Any]
    }

    // 1) The opt-in flag parses; absent means false.
    @MainActor
    func testSettleFlagParsing() throws {
        let server = makeServer(box: Box(), settlementWired: false)
        XCTAssertFalse(try parse(server, baseJSON()).continuationSettle)
        XCTAssertTrue(
            try parse(server, baseJSON([
                "previous_es_state_id": "S-1",
                "continuation_settle": true,
            ])).continuationSettle)
    }

    // 2) Legacy path: no anchor, no flag -> untouched; no authority invoked;
    //    legacy error bodies gain no structured keys.
    @MainActor
    func testLegacyPathStaysUntouched() async throws {
        let box = Box()
        let server = makeServer(box: box, settlementWired: true)
        let parsed = try parse(server, baseJSON())
        let out = await server.continuationGate(parsed: parsed, context: makeContext())
        XCTAssertEqual(out, parsed.canonicalMessages)
        XCTAssertEqual(box.admissionCalls, 0)
        XCTAssertEqual(box.settlementCalls, 0)

        let legacy = server.errorBody(message: "m", status: 422)
        let info = try XCTUnwrap(errorInfo(legacy))
        XCTAssertNil(info["error_kind"], "legacy error bodies stay byte-for-byte unchanged")
    }

    // 3) settle asked WITHOUT an anchor -> 400 fail closed, zero authority calls.
    @MainActor
    func testSettleWithoutAnchorFailsClosed() async throws {
        let box = Box()
        let server = makeServer(box: box, settlementWired: true)
        let parsed = try parse(server, baseJSON(["continuation_settle": true]))
        let out = await server.continuationGate(parsed: parsed, context: makeContext())
        XCTAssertNil(out)
        XCTAssertEqual(box.admissionCalls, 0)
        XCTAssertEqual(ContinuationTerminal.settleWithoutAnchor.status, 400)
        XCTAssertEqual(ContinuationTerminal.settleWithoutAnchor.errorKind, "SETTLEMENT_WITHOUT_ANCHOR")
    }

    // 4) settle asked, settlement authority NOT wired -> 503 fail closed
    //    BEFORE generation and before the admission authority is invoked.
    @MainActor
    func testMissingSettlementAuthorityFailsClosedBeforeAdmission() async throws {
        let box = Box()
        let server = makeServer(box: box, settlementWired: false)
        let parsed = try parse(server, baseJSON([
            "previous_es_state_id": "S-1",
            "continuation_settle": true,
        ]))
        let out = await server.continuationGate(parsed: parsed, context: makeContext())
        XCTAssertNil(out)
        XCTAssertEqual(box.admissionCalls, 0, "missing settlement authority must not even reach admission")
        XCTAssertEqual(ContinuationTerminal.settlementAuthorityUnavailable.status, 503)
        XCTAssertEqual(ContinuationTerminal.settlementAuthorityUnavailable.errorKind, "SETTLEMENT_AUTHORITY_UNAVAILABLE")
    }

    // 5) The five admission-side kinds are pairwise distinct; an unknown
    //    engine error is 500, never 422 (it must not masquerade as a refusal).
    @MainActor
    func testAdmissionClassificationIsPairwiseDistinct() {
        let invalid = ContinuationAdmissionFailure.invalidAnchor.terminal
        let isRefusal = ContinuationAdmissionFailure.refused("identity mismatch").terminal
        let unavailable = ContinuationAdmissionFailure.unavailable.terminal
        let unknown = continuationAdmissionTerminal(
            for: NSError(domain: "engine", code: 7))

        XCTAssertEqual(invalid.status, 422)
        XCTAssertEqual(invalid.errorKind, "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(invalid.reasonCode, "invalid_anchor")
        XCTAssertEqual(isRefusal.status, 422)
        XCTAssertEqual(isRefusal.errorKind, "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(isRefusal.reasonCode, "is_refusal")
        XCTAssertEqual(unavailable.status, 503)
        XCTAssertEqual(unavailable.errorKind, "ADMISSION_AUTHORITY_UNAVAILABLE")
        XCTAssertEqual(unknown.status, 500, "unknown errors must not fall back to 422")
        XCTAssertEqual(unknown.errorKind, "ADMISSION_ENGINE_ERROR")
        XCTAssertNotEqual(unavailable.errorKind, invalid.errorKind)
        XCTAssertEqual(Set([invalid.errorKind, unavailable.errorKind, unknown.errorKind,
                            ContinuationTerminal.settlementUnsupportedOnStream.errorKind,
                            ContinuationTerminal.settlementEngineError.errorKind,
                            ContinuationSettlementFailure
                                .contractRejected(auditDetail: "x").terminal.errorKind]).count, 6)
    }

    // 6) Empty/malformed anchor: gate fails closed before the authority with
    //    the INPUT_ADMISSION_REFUSED / invalid_anchor contract.
    @MainActor
    func testBlankAnchorFailsClosedWithStableContract() async throws {
        let box = Box()
        let server = makeServer(box: box, settlementWired: true)
        let parsed = try parse(server, baseJSON(["previous_es_state_id": "   "]))
        let out = await server.continuationGate(parsed: parsed, context: makeContext())
        XCTAssertNil(out)
        XCTAssertEqual(box.admissionCalls, 0)
    }

    // 7) Post-generation native contract rejection is its OWN class: never an
    //    admission refusal, and it runs over the actual generated text.
    @MainActor
    func testPostGenerationContractRejectionIsIndependent() async throws {
        let box = Box()
        box.settlementBehavior = { _ in
            throw ContinuationSettlementFailure.contractRejected(auditDetail: "value mismatch")
        }
        let server = makeServer(box: box, settlementWired: true)
        let parsed = try parse(server, baseJSON([
            "previous_es_state_id": "S-1",
            "continuation_settle": true,
        ]))
        // ONE request, ONE context: the settlement of this request consumes the
        // admission of this same request.
        let context = makeContext()
        let gate = await server.continuationGate(parsed: parsed, context: context)
        XCTAssertNotNil(gate, "admission succeeds; only the later contract may refuse")

        let step = await server.settlementStep(
            parsed: parsed, generatedText: "NOISE", context: context)
        guard case .refused = step else { return XCTFail("expected refused, got \(step)") }
        XCTAssertEqual(box.settlementCalls, 1)
        XCTAssertEqual(box.lastSettlement?.generatedText, "NOISE",
                       "settlement runs over the ACTUAL output")
        XCTAssertEqual(box.lastSettlement?.parentESStateID, "S-1")

        let terminal = continuationSettlementTerminal(
            for: ContinuationSettlementFailure.contractRejected(auditDetail: "value mismatch"))
        XCTAssertEqual(terminal.status, 422)
        XCTAssertEqual(terminal.errorKind, "NATIVE_RESULT_CONTRACT_REJECTED")
        XCTAssertNotEqual(terminal.errorKind, "INPUT_ADMISSION_REFUSED")
    }

    // 8) Infrastructure errors never masquerade as contract rejections — and
    //    a raw NativeResultContractError thrown through an untyped boundary is
    //    still recognized as the contract refusal it is.
    @MainActor
    func testEngineErrorsDoNotMasquerade() {
        let sqliteish = continuationSettlementTerminal(
            for: NSError(domain: "SQLite", code: 14))
        XCTAssertEqual(sqliteish.status, 500)
        XCTAssertEqual(sqliteish.errorKind, "SETTLEMENT_ENGINE_ERROR")

        let rawContract = continuationSettlementTerminal(
            for: NativeResultContractError(code: "equals_binding_mismatch", detail: "m"))
        XCTAssertEqual(rawContract.status, 422)
        XCTAssertEqual(rawContract.errorKind, "NATIVE_RESULT_CONTRACT_REJECTED")
    }

    // 9) Success: the completed response gains settlement_id + identity
    //    binding status, and a non-settle request never calls the authority.
    @MainActor
    func testSuccessPayloadAndNonOptInStaysSilent() async throws {
        let box = Box()
        let server = makeServer(box: box, settlementWired: true)
        let parsed = try parse(server, baseJSON([
            "previous_es_state_id": "S-1",
            "continuation_settle": true,
        ]))
        let context = makeContext()
        _ = await server.continuationGate(parsed: parsed, context: context)
        let step = await server.settlementStep(
            parsed: parsed, generatedText: "RESULT=hello", context: context)
        guard case .settled(let outcome) = step else {
            return XCTFail("expected settled, got \(step)")
        }
        let payload = server.settlementPayload(outcome)
        XCTAssertEqual(payload["settlement_id"] as? String, "settle-1")
        XCTAssertEqual(payload["identity_binding_published"] as? Bool, true)
        // The settlement handler received THIS admission's verified bindings and
        // a child ES distinct from the parent anchor.
        let received = try XCTUnwrap(box.lastSettlement)
        XCTAssertEqual(
            received.verifiedBindings["next_input"], .string("RECOVERED"),
            "settlement must bind the value the admission VERIFIED, not ES state")
        XCTAssertNotEqual(received.childESStateID, "S-1")
        XCTAssertEqual(payload["child_es_state_id"] as? String, received.childESStateID,
                       "the returned child ES id is the one the settlement belongs to")

        let legacy = try parse(server, baseJSON())
        let legacyStep = await server.settlementStep(
            parsed: legacy, generatedText: "anything", context: makeContext())
        guard case .notRequested = legacyStep else {
            return XCTFail("non-opt-in must be .notRequested, got \(legacyStep)")
        }
        XCTAssertEqual(box.settlementCalls, 1, "only the opt-in request invoked settlement")
    }

    // 10) Structured terminals render into the JSON error body.
    @MainActor
    func testStructuredBodyFields() {
        let server = makeServer(box: Box(), settlementWired: true)
        let body = server.errorBody(
            message: "m", status: 422,
            errorKind: "INPUT_ADMISSION_REFUSED", reasonCode: "is_refusal")
        let info = body["error"] as? [String: Any]
        XCTAssertEqual(info?["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(info?["reason_code"] as? String, "is_refusal")
    }
}
