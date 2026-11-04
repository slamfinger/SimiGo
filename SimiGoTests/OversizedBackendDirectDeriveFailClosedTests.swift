import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// Slice (Registered gap G-1, ported from Lab): a DIRECT backend derive must
/// fail closed on a parent/child logical-position mismatch, exactly like the
/// coordinator-driven fork path, instead of relying on the coordinator to mask
/// it. Before the fix the product's `OversizedSegmentedStateBackend`
/// `deriveRepresentation(from:for:)` bound the child unconditionally, so a
/// direct caller holding a stale/mismatched handle silently armed a binding at
/// the wrong position while every sibling read path already rejected it.
///
/// Model-free: pure backend + contract value types — no engine, no model, no
/// disk.
final class OversizedBackendDirectDeriveFailClosedTests: XCTestCase {
    private func parent(id: ExecutionID, position: Int64) -> ExecutionRepresentation {
        ExecutionRepresentation(
            executionID: id, position: ExecutionPosition(position),
            payload: OversizedPrefixPayload(tokenPrefix: [1, 2, 3]))
    }

    private func child(parentID: ExecutionID, position: Int64) -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID("C"),
            lineage: ExecutionLineage(root: parentID, parent: parentID),
            position: ExecutionPosition(position),
            continuation: ExecutionContinuation(nextInput: "child", continuationID: "child-cont"),
            lifecycle: .active)
    }

    func testDirectChildDeriveRejectsParentChildPositionMismatch() async throws {
        let backend = OversizedSegmentedStateBackend(releaseAll: {})
        let parentID = ExecutionID("P")
        // Parent bound at position 0; child handle demands position 1 -> mismatch.
        let parent = parent(id: parentID, position: 0)
        let child = child(parentID: parentID, position: 1)

        do {
            _ = try await backend.deriveRepresentation(from: parent, for: child)
            XCTFail("direct derive must reject a parent/child position mismatch")
        } catch {
            // Reflection rather than typed match: SimiGoTests double-links
            // SimiGoRuntimeContract (directly AND via SimiGo2Experimental), so
            // `error as? ExecutionStateBackendError` can return nil across the
            // framework boundary even when the value is that case.
            let reflected = String(reflecting: error)
            XCTAssertTrue(reflected.contains("representationPositionMismatch"),
                          "expected representationPositionMismatch, got \(reflected)")
            XCTAssertTrue(reflected.contains("\"C\""),
                          "error must name the child execution, got \(reflected)")
        }

        // Fail-closed means NO side effect: the child was never armed.
        XCTAssertNil(try? backend.boundPrefix(for: child),
                     "a rejected derive must not bind the child")
    }

    /// Control: a position-matched derive still succeeds and binds the child,
    /// so the guard does not over-reject existing derive behavior.
    func testPositionMatchedDeriveStillSucceedsAndBinds() async throws {
        let backend = OversizedSegmentedStateBackend(releaseAll: {})
        let parentID = ExecutionID("P")
        let parent = parent(id: parentID, position: 0)
        let child = child(parentID: parentID, position: 0)   // same position

        let derived = try await backend.deriveRepresentation(from: parent, for: child)
        XCTAssertEqual(derived.executionID, ExecutionID("C"))
        XCTAssertEqual(derived.position, ExecutionPosition(0))
        let bound = try backend.boundPrefix(for: child)
        XCTAssertEqual(bound.prefix, [1, 2, 3])
        XCTAssertEqual(bound.position, ExecutionPosition(0))
    }
}
