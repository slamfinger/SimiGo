import XCTest
@testable import SimiGoRuntimeContract

/// Regression cover for the prefix-stable Information-Space injection
/// (2026-10-27 root cause: a per-turn fresh block mutated a mid-chain user
/// message that the engine had already committed, so every turn of a real agent
/// tool loop paid a full cold prefill).
///
/// 2026-11-21: the ledger is occurrence-aware. The old key was
/// `(scope, userText)`, so a block frozen for one occurrence of a repeated
/// system-reminder was replayed into another occurrence the engine had stored
/// raw: `prefixMismatch index=6 stored=86B incoming=3972B`, 35k/62k prompts
/// cold-prefilled. The tests below pin the occurrence boundary.
nonisolated final class ISContextLedgerTests: XCTestCase {

    private static func resolution(demand: String = "demand-1") -> InformationLoop.Resolution {
        InformationLoop.Resolution(
            demandID: demand, stateID: nil, reused: false, hits: [],
            inputDigest: demand, resultSHA256: "sha", retrievalSettlementID: "ret-1",
            itemIDs: ["file:a"], staleItemIDs: [])
    }

    func testFirstRenderIsTheCandidateVerbatim() {
        let ledger = ISContextLedger()
        let snapshot = ledger.stabilize(
            scope: "s", userText: "hello", index: 0, block: "[Information Space] A",
            resolution: Self.resolution())
        XCTAssertEqual(snapshot.block, "[Information Space] A")
        XCTAssertFalse(snapshot.isReplay)
        XCTAssertFalse(snapshot.candidateChanged)
    }

    func testDriftingCandidateReplaysTheFrozenBytes() {
        let ledger = ISContextLedger()
        let first = ledger.stabilize(
            scope: "s", userText: "hello", index: 0, block: "BLOCK-ONE",
            resolution: Self.resolution(demand: "demand-1"))
        // The same user turn, one turn later: retrieval now wants a different
        // block (this is exactly the measured drift). The render must not change.
        let second = ledger.stabilize(
            scope: "s", userText: "hello", index: 0, block: "BLOCK-TWO",
            resolution: Self.resolution(demand: "demand-2"))
        XCTAssertEqual(second.block, first.block)
        XCTAssertTrue(second.isReplay)
        XCTAssertTrue(second.candidateChanged)
        // Settlement must claim the retrieval the prompt was actually built from.
        XCTAssertEqual(second.resolution.demandID, "demand-1")
    }

    func testStableCandidateReportsNoChange() {
        let ledger = ISContextLedger()
        _ = ledger.stabilize(
            scope: "s", userText: "hello", index: 0, block: "SAME",
            resolution: Self.resolution())
        let again = ledger.stabilize(
            scope: "s", userText: "hello", index: 0, block: "SAME",
            resolution: Self.resolution())
        XCTAssertTrue(again.isReplay)
        XCTAssertFalse(again.candidateChanged)
    }

    func testEmptyFirstRenderIsFrozenAsEmpty() throws {
        let ledger = ISContextLedger()
        let cold = ledger.stabilize(
            scope: "s", userText: "hello", index: 0, block: "",
            resolution: Self.resolution())
        XCTAssertEqual(cold.block, "")
        // A question committed without context never gets one afterwards: the
        // engine already holds it raw, so appending now would break the prefix.
        let later = ledger.stabilize(
            scope: "s", userText: "hello", index: 0, block: "BLOCK",
            resolution: Self.resolution())
        XCTAssertEqual(later.block, "")
        let replay = try XCTUnwrap(
            ledger.frozenBlock(scope: "s", userText: "hello", index: 0))
        XCTAssertEqual(replay, "")
    }

    func testScopesAndUserTurnsNeverShareASnapshot() {
        let ledger = ISContextLedger()
        _ = ledger.stabilize(
            scope: "alpha", userText: "q1", index: 0, block: "A1",
            resolution: Self.resolution())
        _ = ledger.stabilize(
            scope: "alpha", userText: "q2", index: 1, block: "A2",
            resolution: Self.resolution())
        _ = ledger.stabilize(
            scope: "beta", userText: "q1", index: 0, block: "B1",
            resolution: Self.resolution())
        XCTAssertEqual(ledger.frozenBlock(scope: "alpha", userText: "q1", index: 0), "A1")
        XCTAssertEqual(ledger.frozenBlock(scope: "alpha", userText: "q2", index: 1), "A2")
        XCTAssertEqual(ledger.frozenBlock(scope: "beta", userText: "q1", index: 0), "B1")
        XCTAssertNil(ledger.frozenBlock(scope: "beta", userText: "q2", index: 1))
        XCTAssertEqual(ledger.count, 3)
    }

    /// The 2026-11-21 failure: the same system-reminder text at index 6 was
    /// never injected, but a block frozen for another occurrence was replayed
    /// there. Each index is its own occurrence; an uninjected index stays nil.
    func testSameTextAtDifferentIndicesIsItsOwnOccurrence() {
        let ledger = ISContextLedger()
        let first = ledger.stabilize(
            scope: "s", userText: "same", index: 0, block: "BLOCK-0",
            resolution: Self.resolution())
        XCTAssertEqual(first.block, "BLOCK-0")
        XCTAssertFalse(first.isReplay)

        let other = ledger.stabilize(
            scope: "s", userText: "same", index: 6, block: "BLOCK-6",
            resolution: Self.resolution())
        XCTAssertEqual(other.block, "BLOCK-6")
        XCTAssertFalse(other.isReplay, "a different index is a different occurrence")
        XCTAssertEqual(
            ledger.frozenBlock(scope: "s", userText: "same", index: 0), "BLOCK-0")
        XCTAssertEqual(
            ledger.frozenBlock(scope: "s", userText: "same", index: 6), "BLOCK-6")
        XCTAssertNil(
            ledger.frozenBlock(scope: "s", userText: "same", index: 1),
            "an index that was never injected must not get another occurrence's block")
    }

    func testSameIndexWithDifferentTextStartsANewOccurrence() {
        let ledger = ISContextLedger()
        _ = ledger.stabilize(
            scope: "s", userText: "q1", index: 2, block: "BLOCK-1",
            resolution: Self.resolution())
        let second = ledger.stabilize(
            scope: "s", userText: "q2", index: 2, block: "BLOCK-2",
            resolution: Self.resolution())
        XCTAssertEqual(second.block, "BLOCK-2")
        XCTAssertFalse(second.isReplay)
        XCTAssertNil(ledger.frozenBlock(scope: "s", userText: "q1", index: 2))
        XCTAssertEqual(ledger.frozenBlock(scope: "s", userText: "q2", index: 2), "BLOCK-2")
    }

    func testRefreshReplacesOnlyTheTargetOccurrence() {
        let ledger = ISContextLedger()
        _ = ledger.stabilize(
            scope: "s", userText: "same", index: 0, block: "A",
            resolution: Self.resolution(demand: "demand-0"))
        _ = ledger.stabilize(
            scope: "s", userText: "same", index: 6, block: "B",
            resolution: Self.resolution(demand: "demand-6"))
        let refreshed = ledger.refresh(
            scope: "s", userText: "same", index: 6, block: "C",
            resolution: Self.resolution(demand: "demand-new"))
        XCTAssertEqual(refreshed.block, "C")
        XCTAssertEqual(ledger.frozenBlock(scope: "s", userText: "same", index: 0), "A")
        XCTAssertEqual(ledger.frozenBlock(scope: "s", userText: "same", index: 6), "C")
    }

    func testCapacityEvictsOldestFirst() {
        let ledger = ISContextLedger()
        let capacity = ISContextLedger.capacity
        for index in 0..<capacity {
            _ = ledger.stabilize(
                scope: "s", userText: "q\(index)", index: index, block: "b\(index)",
                resolution: Self.resolution())
        }
        XCTAssertEqual(ledger.count, capacity)
        _ = ledger.stabilize(
            scope: "s", userText: "extra", index: capacity, block: "newest",
            resolution: Self.resolution())
        XCTAssertEqual(ledger.count, capacity)
        XCTAssertNil(ledger.frozenBlock(scope: "s", userText: "q0", index: 0))
        XCTAssertEqual(ledger.frozenBlock(scope: "s", userText: "q1", index: 1), "b1")
        XCTAssertEqual(
            ledger.frozenBlock(scope: "s", userText: "extra", index: capacity), "newest")
    }

    /// The property the engine gate depends on: rendering the same chain twice
    /// with the same ledger produces byte-identical user turns.
    func testReplayKeepsACommittedChainByteStable() {
        let ledger = ISContextLedger()
        func render(question: String, freshBlock: String) -> String {
            let snapshot = ledger.stabilize(
                scope: "s", userText: question, index: 0, block: freshBlock,
                resolution: Self.resolution())
            return question + "\n\n" + snapshot.block
        }
        let turnOne = render(question: "what is X", freshBlock: "BLOCK-1")
        let turnTwo = render(question: "what is X", freshBlock: "BLOCK-2")
        XCTAssertEqual(turnOne, turnTwo)
    }

    /// Refresh-on-divergence: when the frozen context no longer matches what
    /// the space holds, the turn renders and settles from ONE fresh snapshot —
    /// so the replacement answer's declared demand is the demand it actually
    /// saw, and the next exact repeat is served from it (no regen loop).
    func testRefreshReplacesFrozenSnapshotAndStopsReportingDivergence() {
        let ledger = ISContextLedger()
        let stale = ledger.stabilize(
            scope: "s", userText: "where is the vault", index: 0, block: "BLOCK-OLD",
            resolution: Self.resolution(demand: "demand-old"))
        XCTAssertTrue(stale.isReplay == false)

        let drifted = ledger.stabilize(
            scope: "s", userText: "where is the vault", index: 0, block: "BLOCK-NEW",
            resolution: Self.resolution(demand: "demand-new"))
        XCTAssertTrue(drifted.candidateChanged, "divergence must be reported first")

        let refreshed = ledger.refresh(
            scope: "s", userText: "where is the vault", index: 0, block: "BLOCK-NEW",
            resolution: Self.resolution(demand: "demand-new"))
        XCTAssertEqual(refreshed.block, "BLOCK-NEW")
        XCTAssertEqual(refreshed.resolution.demandID, "demand-new")
        XCTAssertFalse(refreshed.candidateChanged)

        let settled = ledger.stabilize(
            scope: "s", userText: "where is the vault", index: 0, block: "BLOCK-NEW",
            resolution: Self.resolution(demand: "demand-new"))
        XCTAssertFalse(settled.candidateChanged, "post-refresh repeats are stable")
        XCTAssertEqual(
            ledger.frozenBlock(scope: "s", userText: "where is the vault", index: 0),
            "BLOCK-NEW")
    }

    // MARK: - Settled digest chain (render-side memory feed)

    func testDigestChainRemembersAndReturnsPerTurn() {
        let ledger = ISContextLedger()
        ledger.rememberDigest(scope: "s", turnIndex: 1, digest: "d1")
        ledger.rememberDigest(scope: "s", turnIndex: 2, digest: "d2")
        XCTAssertEqual(ledger.digestChain(scope: "s"), [1: "d1", 2: "d2"])
        XCTAssertTrue(ledger.digestChain(scope: "other").isEmpty)
    }

    func testDigestRewriteIsLastWriteWins() {
        let ledger = ISContextLedger()
        ledger.rememberDigest(scope: "s", turnIndex: 1, digest: "old")
        ledger.rememberDigest(scope: "s", turnIndex: 1, digest: "new")
        XCTAssertEqual(ledger.digestChain(scope: "s"), [1: "new"])
    }

    func testDigestChainPartialCoverageIsObservable() {
        // The feed substitutes only when memory covers 1...N contiguously; a
        // gap must be visible so the caller fails open to the IS read.
        let ledger = ISContextLedger()
        ledger.rememberDigest(scope: "s", turnIndex: 1, digest: "d1")
        ledger.rememberDigest(scope: "s", turnIndex: 3, digest: "d3")
        let chain = ledger.digestChain(scope: "s")
        XCTAssertNil(chain[2], "the missing turn must not be fabricated")
        XCTAssertFalse((1...3).allSatisfy { chain[$0] != nil })
    }

    func testDigestSessionFifoEvictsOldestScope() {
        let ledger = ISContextLedger()
        for i in 0..<ISContextLedger.digestSessionCapacity {
            ledger.rememberDigest(scope: "s\(i)", turnIndex: 1, digest: "d")
        }
        XCTAssertFalse(ledger.digestChain(scope: "s0").isEmpty)
        // One more session pushes out the oldest (s0); memory fails open, the
        // durable IS row is untouched.
        ledger.rememberDigest(
            scope: "s\(ISContextLedger.digestSessionCapacity)", turnIndex: 1, digest: "d")
        XCTAssertTrue(ledger.digestChain(scope: "s0").isEmpty)
        XCTAssertFalse(
            ledger.digestChain(scope: "s\(ISContextLedger.digestSessionCapacity)").isEmpty)
    }
}
