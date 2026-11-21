import Foundation
import Network
import XCTest

@testable import SimiGo

/// Directed tests for the NEW, opt-in ES/IS continuation admission gate on the
/// real product Responses dispatch path. They drive the SAME product functions
/// the live HTTP server runs before it would call `generateHandler`:
/// `parseResponsesParams(...)` then `continuationGate(parsed:context:)`.
///
/// Contract proven here (per the opt-in design):
/// * Absent `previous_es_state_id` -> the original `canonicalMessages` are
///   returned untouched and the admission authority is NOT invoked: existing
///   ordinary Responses / chat semantics are byte-for-byte unchanged.
/// * Present + verified -> the authority IS invoked and the recovered IS value
///   is appended as the generation input.
/// * Present + refused / empty / malformed / no authority -> the gate returns
///   `nil`, which the handlers consume as `guard let … else { return }` BEFORE
///   `generateHandler`, so generation count is zero. Nothing falls back to an
///   ordinary generation.
///
/// Model-free and hermetic: the admission authority is a spy, no store/DB, Keychain,
/// GUI, or real user state is touched. The real-model positive path is verified
/// separately by the live server.
final class ResponsesContinuationAdmissionGateTests: XCTestCase {

    /// Counters shared with the @Sendable admission spy.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        private var _anchors: [String] = []
        private var _riskAcceptanceChoices: [Bool] = []
        var behavior: (String) throws -> ContinuationAdmissionOutcome = { _ in
            throw ContinuationAdmissionFailure.unavailable
        }
        func record(_ anchor: String, acceptInvalidatedDependency: Bool? = nil) {
            lock.withLock {
                _calls += 1
                _anchors.append(anchor)
                if let acceptInvalidatedDependency {
                    _riskAcceptanceChoices.append(acceptInvalidatedDependency)
                }
            }
        }
        var calls: Int { lock.withLock { _calls } }
        var anchors: [String] { lock.withLock { _anchors } }
        var riskAcceptanceChoices: [Bool] { lock.withLock { _riskAcceptanceChoices } }
    }

    private func makeServer(admission: ContinuationAdmissionHandler?) -> HTTPServer {
        HTTPServer(
            port: 59_217,
            modelId: "admission-gate-test",
            generateHandler: { _, _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "t/main", modelId: "admission-gate-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _, _ in
                BranchDeletionOutcome(
                    deletedBranch: "", hadLiveSession: false,
                    hadCheckpointFile: false, generation: 1,
                    remainingLiveBranches: [],
                    remainingCheckpointBranches: [])
            },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            continuationAdmission: admission
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

    /// Last message content of the returned continuation, if any.
    private func lastContent(_ messages: [JSONValue]) -> String? {
        guard let last = messages.last, let obj = last.object,
              case .string(let c)? = obj["content"] else { return nil }
        return c
    }

    // 1) Field ABSENT -> original canonicalMessages, authority never called.
    @MainActor
    func testAbsentAnchorPreservesOriginalDispatchAndSkipsAdmission() async throws {
        let box = Box()
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor, acceptInvalidatedDependency: acceptInvalidatedDependency)
            return try box.behavior(anchor)
        })
        let parsed = try parse(server, ["model": "admission-gate-test", "input": "just chat"])
        XCTAssertFalse(parsed.esStateIDPresent)

        let out = await server.continuationGate(parsed: parsed, context: makeContext())

        XCTAssertEqual(out, parsed.canonicalMessages, "absent anchor must not alter input")
        XCTAssertEqual(box.calls, 0, "authority must not be invoked without an anchor")
    }

    // 2) Field PRESENT + verified -> authority invoked, recovered value appended.
    @MainActor
    func testPresentValidAnchorInvokesAuthorityAndAppendsRecoveredValue() async throws {
        let box = Box()
        box.behavior = { anchor in
            ContinuationAdmissionOutcome(
                esStateID: anchor,
                settlementID: "settlement-\(anchor)",
                recoveredValue: "RECOVERED-\(anchor)",
                verifiedBindings: ["next_input": .string("RECOVERED-\(anchor)")])
        }
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor, acceptInvalidatedDependency: acceptInvalidatedDependency)
            return try box.behavior(anchor)
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-42",
            "accept_invalidated_dependency": true,
        ])
        XCTAssertTrue(parsed.esStateIDPresent)

        let gateOut = await server.continuationGate(parsed: parsed, context: makeContext())
        let out = try XCTUnwrap(gateOut)

        XCTAssertEqual(box.calls, 1)
        XCTAssertEqual(box.anchors, ["S-42"])
        XCTAssertEqual(box.riskAcceptanceChoices, [true])
        XCTAssertEqual(out.count, parsed.canonicalMessages.count + 1)
        XCTAssertEqual(lastContent(out), "RECOVERED-S-42")
    }

    @MainActor
    func testRiskAcceptanceDefaultsToFalseForContinuation() async throws {
        let box = Box()
        box.behavior = { anchor in
            ContinuationAdmissionOutcome(
                esStateID: anchor,
                settlementID: "settlement-\(anchor)",
                recoveredValue: "RECOVERED-\(anchor)",
                verifiedBindings: ["next_input": .string("RECOVERED-\(anchor)")])
        }
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor, acceptInvalidatedDependency: acceptInvalidatedDependency)
            return try box.behavior(anchor)
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-default-risk",
        ])

        _ = await server.continuationGate(parsed: parsed, context: makeContext())

        XCTAssertEqual(box.riskAcceptanceChoices, [false],
                       "omission must keep continuation admission fail-closed")
    }

    @MainActor
    func testRiskAcceptanceFlagMustBeAJSONBoolean() throws {
        let server = makeServer(admission: nil)
        let valid = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-valid-risk",
            "accept_invalidated_dependency": true,
        ])
        XCTAssertTrue(valid.acceptInvalidatedDependency)
        XCTAssertNil(valid.requestShapeError)

        let numeric = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-invalid-risk",
            "accept_invalidated_dependency": NSNumber(value: 1),
        ])
        XCTAssertEqual(numeric.requestShapeError, .invalidRiskAcceptance)

        let misplaced = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "accept_invalidated_dependency": true,
        ])
        XCTAssertEqual(misplaced.requestShapeError, .riskAcceptanceWithoutAnchor)
    }

    // 3) Field PRESENT + native refusal -> gate returns nil (generate not reached).
    @MainActor
    func testPresentAnchorRefusedBeforeGeneration() async throws {
        let box = Box()
        box.behavior = { anchor in
            box.record(anchor)
            throw ContinuationAdmissionFailure.refused("identity mismatch")
        }
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor, acceptInvalidatedDependency: acceptInvalidatedDependency)
            return try box.behavior(anchor)
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-7",
        ])

        let out = await server.continuationGate(parsed: parsed, context: makeContext())

        XCTAssertNil(out, "a refused continuation must return nil before generateHandler")
    }

    // 3b) Double-count guard: a refusal that throws from the handler is still nil
    // and the handler was reached exactly once.
    @MainActor
    func testRefusalInvokesAuthorityExactlyOnce() async throws {
        let box = Box()
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor, acceptInvalidatedDependency: acceptInvalidatedDependency)
            throw ContinuationAdmissionFailure.refused("no valid settlement")
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-9",
        ])

        _ = await server.continuationGate(parsed: parsed, context: makeContext())

        XCTAssertEqual(box.calls, 1)
        XCTAssertEqual(box.anchors, ["S-9"])
    }

    // 4) Field PRESENT but EMPTY -> fail closed BEFORE invoking the authority.
    @MainActor
    func testEmptyAnchorFailsClosedWithoutInvokingAuthority() async throws {
        let box = Box()
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor, acceptInvalidatedDependency: acceptInvalidatedDependency)
            return try box.behavior(anchor)
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "   ",
        ])
        XCTAssertTrue(parsed.esStateIDPresent, "presence must be tracked separately from validity")

        let out = await server.continuationGate(parsed: parsed, context: makeContext())

        XCTAssertNil(out)
        XCTAssertEqual(box.calls, 0, "blank anchor must fail closed before the authority")
    }

    // 5) Field PRESENT but MALFORMED (non-string) -> fail closed, authority untouched.
    @MainActor
    func testMalformedAnchorFailsClosed() async throws {
        let server = makeServer(admission: { _ in
            XCTFail("authority must not run for a malformed anchor")
            return ContinuationAdmissionOutcome(
                esStateID: "", settlementID: "", recoveredValue: "", verifiedBindings: [:])
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": 12345,   // not a string
        ])
        XCTAssertTrue(parsed.esStateIDPresent)
        XCTAssertNil(parsed.esStateID)

        let out = await server.continuationGate(parsed: parsed, context: makeContext())
        XCTAssertNil(out)
    }

    // 7) Task cancellation before gate entry must also skip the authority.
    @MainActor
    func testCancelledTaskSkipsAdmissionBeforeGateEntry() async throws {
        let box = Box()
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor)
            return try box.behavior(anchor)
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-task-cancelled",
        ])
        let context = makeContext()

        let out = await Task { @MainActor in
            withUnsafeCurrentTask { task in task?.cancel() }
            return await server.continuationGate(parsed: parsed, context: context)
        }.value

        XCTAssertNil(out, "a cancelled request task must stop before admission")
        XCTAssertEqual(box.calls, 0, "a cancelled request task must not invoke the authority")
        XCTAssertNil(context.continuationBinding)
    }

    // 8) A request already closed before gate entry must not invoke admission.
    @MainActor
    func testClosedRequestSkipsAdmissionBeforeGateEntry() async throws {
        let box = Box()
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor)
            return try box.behavior(anchor)
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-closed",
        ])
        let context = makeContext()
        _ = context.markClosed()

        let out = await server.continuationGate(parsed: parsed, context: context)

        XCTAssertNil(out, "a closed request must stop before admission")
        XCTAssertEqual(box.calls, 0, "a closed request must not invoke the authority")
        XCTAssertNil(context.continuationBinding)
    }

    // 9) Cancellation while the asynchronous authority is suspended must not
    // publish the child binding (and therefore must not register its KV grant).
    @MainActor
    func testCancellationDuringAdmissionDoesNotInstallContinuationBinding() async throws {
        let box = Box()
        box.behavior = { anchor in
            ContinuationAdmissionOutcome(
                esStateID: anchor,
                settlementID: "settlement-\(anchor)",
                recoveredValue: "RECOVERED-\(anchor)",
                verifiedBindings: ["next_input": .string("RECOVERED-\(anchor)")])
        }
        let server = makeServer(admission: { anchor, acceptInvalidatedDependency in
            box.record(anchor, acceptInvalidatedDependency: acceptInvalidatedDependency)
            await Task.yield()
            withUnsafeCurrentTask { task in task?.cancel() }
            return try box.behavior(anchor)
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-cancelled-during-admission",
        ])
        let context = makeContext()

        let out = await server.continuationGate(parsed: parsed, context: context)

        XCTAssertNil(out, "cancelled admission must not continue to generation")
        XCTAssertEqual(box.calls, 1, "the already-started authority is allowed to finish")
        XCTAssertNil(
            context.continuationBinding,
            "cancellation after the await must be observed before installing the child binding")
    }

    // 10) Field PRESENT but NO authority wired -> fail closed (503 path), never generate.
    @MainActor
    func testPresentAnchorWithNoAuthorityFailsClosed() async throws {
        let server = makeServer(admission: nil)
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-1",
        ])

        let out = await server.continuationGate(parsed: parsed, context: makeContext())
        XCTAssertNil(out, "an unwired continuation must fail closed, not fall back to generation")
    }

    func testSettlementConsumptionRiskAcceptanceIsStrictAndDefaultsFalse() throws {
        let base: [String: Any] = [
            "source_settlement_id": "settlement-1",
            "query": "exact repeat",
            "contract": [
                "id": "simigo.settlement-consumption",
                "demand_class": "exact-repeat",
                "version": "v1",
                "extract": "content",
            ],
        ]

        XCTAssertFalse(try SettlementConsumptionEntry.parse(base)
            .acceptInvalidatedDependency,
            "omission must preserve the fail-closed default")

        var accepted = base
        accepted["accept_invalidated_dependency"] = true
        XCTAssertTrue(try SettlementConsumptionEntry.parse(accepted)
            .acceptInvalidatedDependency)

        var numeric = base
        numeric["accept_invalidated_dependency"] = NSNumber(value: 1)
        XCTAssertThrowsError(try SettlementConsumptionEntry.parse(numeric),
                             "numeric 1 is not a JSON boolean")

        var text = base
        text["accept_invalidated_dependency"] = "true"
        XCTAssertThrowsError(try SettlementConsumptionEntry.parse(text),
                             "string booleans must be refused")
    }

}
