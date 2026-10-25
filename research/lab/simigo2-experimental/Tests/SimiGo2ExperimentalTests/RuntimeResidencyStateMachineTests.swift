import XCTest
@testable import SimiGo2Experimental

final class RuntimeResidencyStateMachineTests: XCTestCase {
    private let initial = ResidencyBookkeeping(residentGroupIDs: ["CORE"])

    func testCleanAcceptsAdmission() {
        let machine = ResidencyStateMachine(initialBookkeeping: initial)
        let result = machine.reduce(.planAdmission(requiredGroupIDs: ["CORE", "A"]))

        XCTAssertEqual(result.state, .clean)
        XCTAssertEqual(result.effect, .admissionAccepted)
    }

    func testDirtyRejectsAdmission() {
        let machine = ResidencyStateMachine(initialBookkeeping: initial)
        _ = machine.reduce(.evictFailed(groupID: "A", reason: "io"))
        let result = machine.reduce(.planAdmission(requiredGroupIDs: ["CORE", "A"]))

        XCTAssertEqual(result.state, .dirty)
        XCTAssertEqual(result.effect, .admissionRejectedDirty)
    }

    func testEvictFailureIsOnlyTransitionToDirtyFromClean() {
        let machine = ResidencyStateMachine(initialBookkeeping: initial)
        let result = machine.reduce(.evictFailed(groupID: "A", reason: "io"))

        XCTAssertEqual(result.state, .dirty)
        XCTAssertEqual(result.effect, .enteredDirty)
    }

    func testAuditMismatchEntersDirty() {
        let machine = ResidencyStateMachine(initialBookkeeping: initial)
        let result = machine.reduce(.auditMismatch(expectedBytes: 100, observedBytes: 200))

        XCTAssertEqual(result.state, .dirty)
        XCTAssertEqual(result.effect, .enteredDirty)
    }

    func testLoadFailureDoesNotCreateDirty() {
        let machine = ResidencyStateMachine(initialBookkeeping: initial)
        let result = machine.reduce(.loadFailed(groupID: "A", reason: "io"))

        XCTAssertEqual(result.state, .clean)
        XCTAssertEqual(result.effect, .transferRejected)
    }

    func testCancellationDoesNotCreateDirty() {
        let machine = ResidencyStateMachine(initialBookkeeping: initial)
        let result = machine.reduce(.cancelled(operationID: "op-1"))

        XCTAssertEqual(result.state, .clean)
        XCTAssertEqual(result.effect, .cancelled)
    }

    func testRecoverIsTheOnlyExitFromDirty() {
        let machine = ResidencyStateMachine(initialBookkeeping: initial)
        _ = machine.reduce(.evictFailed(groupID: "A", reason: "io"))

        let rejected = machine.reduce(.auditMatched)
        XCTAssertEqual(rejected.state, .dirty)
        XCTAssertEqual(rejected.effect, .recoverRequired)

        let recovered = machine.reduce(.recover)
        XCTAssertEqual(recovered.state, .clean)
        XCTAssertEqual(recovered.effect, .recovered)

        // Recovery replays from the ORIGINAL initial state: the initially
        // resident CORE group must survive (INV-1 uses the same initial).
        XCTAssertEqual(machine.bookkeeping, initial)
    }

    func testTransferLogReplayMatchesBookkeeping() {
        var bookkeeping = initial
        let log = ResidencyTransferLog()

        bookkeeping = log.appendAndApply(
            .load(groupID: "A"),
            to: bookkeeping
        )
        bookkeeping = log.appendAndApply(
            .evict(groupID: "CORE"),
            to: bookkeeping
        )

        XCTAssertEqual(bookkeeping, log.replay(initial: initial))
    }

    func testReplayIsDefinedForEveryTransferPrefix() {
        let log = ResidencyTransferLog([
            .load(groupID: "A"),
            .load(groupID: "B"),
            .evict(groupID: "A")
        ])

        var expected = initial
        for index in 0..<log.count {
            expected = log.prefix(index + 1).replay(initial: initial)
            XCTAssertEqual(expected, log.replay(initial: initial, through: index))
        }
    }
}
