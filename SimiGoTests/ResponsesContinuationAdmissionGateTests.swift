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
        var behavior: (String) throws -> ContinuationAdmissionOutcome = { _ in
            throw ContinuationAdmissionFailure.unavailable
        }
        func record(_ anchor: String) {
            lock.withLock { _calls += 1; _anchors.append(anchor) }
        }
        var calls: Int { lock.withLock { _calls } }
        var anchors: [String] { lock.withLock { _anchors } }
    }

    private func makeServer(admission: ContinuationAdmissionHandler?) -> HTTPServer {
        HTTPServer(
            port: 59_217,
            modelId: "admission-gate-test",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "t/main", modelId: "admission-gate-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
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
        let server = makeServer(admission: { anchor in
            box.record(anchor); return try box.behavior(anchor)
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
                recoveredValue: "RECOVERED-\(anchor)",
                verifiedBindings: ["next_input": .string("RECOVERED-\(anchor)")])
        }
        let server = makeServer(admission: { anchor in
            box.record(anchor); return try box.behavior(anchor)
        })
        let parsed = try parse(server, [
            "model": "admission-gate-test",
            "input": "continue",
            "previous_es_state_id": "S-42",
        ])
        XCTAssertTrue(parsed.esStateIDPresent)

        let gateOut = await server.continuationGate(parsed: parsed, context: makeContext())
        let out = try XCTUnwrap(gateOut)

        XCTAssertEqual(box.calls, 1)
        XCTAssertEqual(box.anchors, ["S-42"])
        XCTAssertEqual(out.count, parsed.canonicalMessages.count + 1)
        XCTAssertEqual(lastContent(out), "RECOVERED-S-42")
    }

    // 3) Field PRESENT + native refusal -> gate returns nil (generate not reached).
    @MainActor
    func testPresentAnchorRefusedBeforeGeneration() async throws {
        let box = Box()
        box.behavior = { anchor in
            box.record(anchor)
            throw ContinuationAdmissionFailure.refused("identity mismatch")
        }
        let server = makeServer(admission: { anchor in
            box.record(anchor); return try box.behavior(anchor)
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
        let server = makeServer(admission: { anchor in
            box.record(anchor)
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
        let server = makeServer(admission: { anchor in
            box.record(anchor); return try box.behavior(anchor)
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
                esStateID: "", recoveredValue: "", verifiedBindings: [:])
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

    // 6) Field PRESENT but NO authority wired -> fail closed (503 path), never generate.
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
}
