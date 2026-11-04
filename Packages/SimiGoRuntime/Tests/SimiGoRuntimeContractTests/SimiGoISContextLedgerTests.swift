import XCTest
@testable import SimiGoRuntimeContract

/// Regression cover for the prefix-stable Information-Space injection
/// (2026-10-27 root cause: a per-turn fresh block mutated a mid-chain user
/// message that the engine had already committed, so every turn of a real agent
/// tool loop paid a full cold prefill).
nonisolated final class SimiGoISContextLedgerTests: XCTestCase {

    private static func resolution(demand: String = "demand-1") -> SimiGoInformationLoop.Resolution {
        SimiGoInformationLoop.Resolution(
            demandID: demand, stateID: nil, reused: false, hits: [],
            inputDigest: demand, resultSHA256: "sha", retrievalSettlementID: "ret-1",
            itemIDs: ["file:a"], staleItemIDs: [])
    }

    func testFirstRenderIsTheCandidateVerbatim() {
        let ledger = SimiGoISContextLedger()
        let snapshot = ledger.stabilize(
            scope: "s", userText: "hello", block: "[Information Space] A",
            resolution: Self.resolution())
        XCTAssertEqual(snapshot.block, "[Information Space] A")
        XCTAssertFalse(snapshot.isReplay)
        XCTAssertFalse(snapshot.candidateChanged)
    }

    func testDriftingCandidateReplaysTheFrozenBytes() {
        let ledger = SimiGoISContextLedger()
        let first = ledger.stabilize(
            scope: "s", userText: "hello", block: "BLOCK-ONE",
            resolution: Self.resolution(demand: "demand-1"))
        // The same user turn, one turn later: retrieval now wants a different
        // block (this is exactly the measured drift). The render must not change.
        let second = ledger.stabilize(
            scope: "s", userText: "hello", block: "BLOCK-TWO",
            resolution: Self.resolution(demand: "demand-2"))
        XCTAssertEqual(second.block, first.block)
        XCTAssertTrue(second.isReplay)
        XCTAssertTrue(second.candidateChanged)
        // Settlement must claim the retrieval the prompt was actually built from.
        XCTAssertEqual(second.resolution.demandID, "demand-1")
    }

    func testStableCandidateReportsNoChange() {
        let ledger = SimiGoISContextLedger()
        ledger.stabilize(
            scope: "s", userText: "hello", block: "SAME",
            resolution: Self.resolution())
        let again = ledger.stabilize(
            scope: "s", userText: "hello", block: "SAME",
            resolution: Self.resolution())
        XCTAssertTrue(again.isReplay)
        XCTAssertFalse(again.candidateChanged)
    }

    func testEmptyFirstRenderIsFrozenAsEmpty() throws {
        let ledger = SimiGoISContextLedger()
        let cold = ledger.stabilize(
            scope: "s", userText: "hello", block: "",
            resolution: Self.resolution())
        XCTAssertEqual(cold.block, "")
        // A question committed without context never gets one afterwards: the
        // engine already holds it raw, so appending now would break the prefix.
        let later = ledger.stabilize(
            scope: "s", userText: "hello", block: "BLOCK",
            resolution: Self.resolution())
        XCTAssertEqual(later.block, "")
        let replay = try XCTUnwrap(ledger.frozenBlock(scope: "s", userText: "hello"))
        XCTAssertEqual(replay, "")
    }

    func testScopesAndUserTurnsNeverShareASnapshot() {
        let ledger = SimiGoISContextLedger()
        ledger.stabilize(
            scope: "alpha", userText: "q1", block: "A1",
            resolution: Self.resolution())
        ledger.stabilize(
            scope: "alpha", userText: "q2", block: "A2",
            resolution: Self.resolution())
        ledger.stabilize(
            scope: "beta", userText: "q1", block: "B1",
            resolution: Self.resolution())
        XCTAssertEqual(ledger.frozenBlock(scope: "alpha", userText: "q1"), "A1")
        XCTAssertEqual(ledger.frozenBlock(scope: "alpha", userText: "q2"), "A2")
        XCTAssertEqual(ledger.frozenBlock(scope: "beta", userText: "q1"), "B1")
        XCTAssertNil(ledger.frozenBlock(scope: "beta", userText: "q2"))
        XCTAssertEqual(ledger.count, 3)
    }

    func testCapacityEvictsOldestFirst() {
        let ledger = SimiGoISContextLedger()
        let capacity = SimiGoISContextLedger.capacity
        for index in 0..<capacity {
            ledger.stabilize(
                scope: "s", userText: "q\(index)", block: "b\(index)",
                resolution: Self.resolution())
        }
        XCTAssertEqual(ledger.count, capacity)
        ledger.stabilize(
            scope: "s", userText: "extra", block: "newest",
            resolution: Self.resolution())
        XCTAssertEqual(ledger.count, capacity)
        XCTAssertNil(ledger.frozenBlock(scope: "s", userText: "q0"))
        XCTAssertEqual(ledger.frozenBlock(scope: "s", userText: "q1"), "b1")
        XCTAssertEqual(ledger.frozenBlock(scope: "s", userText: "extra"), "newest")
    }

    /// The property the engine gate depends on: rendering the same chain twice
    /// with the same ledger produces byte-identical user turns.
    func testReplayKeepsACommittedChainByteStable() {
        let ledger = SimiGoISContextLedger()
        func render(question: String, freshBlock: String) -> String {
            let snapshot = ledger.stabilize(
                scope: "s", userText: question, block: freshBlock,
                resolution: Self.resolution())
            return question + "\n\n" + snapshot.block
        }
        let turnOne = render(question: "what is X", freshBlock: "BLOCK-1")
        let turnTwo = render(question: "what is X", freshBlock: "BLOCK-2")
        XCTAssertEqual(turnOne, turnTwo)
    }
}
