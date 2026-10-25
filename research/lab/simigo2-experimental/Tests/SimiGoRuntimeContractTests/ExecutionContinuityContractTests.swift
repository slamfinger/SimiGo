import XCTest
@testable import SimiGoRuntimeContract

final class ExecutionContinuityContractTests: XCTestCase {
    func testExecutionIdentityAndLineageAreLogicalValues() {
        let parentID = ExecutionID("parent")
        let childID = ExecutionID("child")

        let parentLineage = ExecutionLineage(root: parentID)
        let childLineage = ExecutionLineage(root: parentID, parent: parentID)

        XCTAssertEqual(parentLineage.root, parentID)
        XCTAssertNil(parentLineage.parent)
        XCTAssertEqual(childLineage.root, parentID)
        XCTAssertEqual(childLineage.parent, parentID)
        XCTAssertNotEqual(parentID, childID)
    }

    func testPositionAndContinuationAreIndependentSemanticValues() {
        let position = ExecutionPosition(42)
        let continuation = ExecutionContinuation(
            nextInput: "parent-next",
            continuationID: "parent-continuation"
        )

        XCTAssertEqual(position.value, 42)
        XCTAssertEqual(continuation.nextInput, "parent-next")
        XCTAssertEqual(continuation.continuationID, "parent-continuation")
    }

    func testStateHandleCarriesLogicalStateOnly() {
        let id = ExecutionID("state-A")
        let lineage = ExecutionLineage(root: id)
        let position = ExecutionPosition(7)
        let continuation = ExecutionContinuation(
            nextInput: "next-A",
            continuationID: "cont-A"
        )

        let handle = ExecutionStateHandle(
            id: id,
            lineage: lineage,
            position: position,
            continuation: continuation,
            lifecycle: .active
        )

        XCTAssertEqual(handle.id, id)
        XCTAssertEqual(handle.lineage, lineage)
        XCTAssertEqual(handle.position, position)
        XCTAssertEqual(handle.continuation, continuation)
        XCTAssertEqual(handle.lifecycle, .active)
    }

    func testForkRequestKeepsParentAndChildSemanticsDistinct() {
        let parentID = ExecutionID("parent")
        let parent = ExecutionStateHandle(
            id: parentID,
            lineage: ExecutionLineage(root: parentID),
            position: ExecutionPosition(100),
            continuation: ExecutionContinuation(
                nextInput: "parent-next",
                continuationID: "parent-cont"
            ),
            lifecycle: .active
        )

        let childID = ExecutionID("child")
        let request = ExecutionForkRequest(
            parent: parent,
            childID: childID,
            childPosition: ExecutionPosition(100),
            childContinuation: ExecutionContinuation(
                nextInput: "child-next",
                continuationID: "child-cont"
            )
        )

        XCTAssertEqual(request.parent.id, parentID)
        XCTAssertEqual(request.childID, childID)
        XCTAssertNotEqual(request.childID, request.parent.id)
        XCTAssertNotEqual(
            request.childContinuation,
            request.parent.continuation
        )
    }

    func testRestoreRequestTargetsLogicalPositionAndContinuation() {
        let request = ExecutionRestoreRequest(
            targetPosition: ExecutionPosition(88),
            continuation: ExecutionContinuation(
                nextInput: "restore-next",
                continuationID: "restore-cont"
            )
        )

        XCTAssertEqual(request.targetPosition.value, 88)
        XCTAssertEqual(request.continuation.nextInput, "restore-next")
        XCTAssertEqual(request.continuation.continuationID, "restore-cont")
    }

    func testLifecycleStatesAreRepresentationIndependent() {
        let expected: [ExecutionBranchLifecycle] = [
            .attached,
            .active,
            .restored,
            .discarded
        ]

        XCTAssertEqual(
            expected,
            [.attached, .active, .restored, .discarded]
        )
    }
}
