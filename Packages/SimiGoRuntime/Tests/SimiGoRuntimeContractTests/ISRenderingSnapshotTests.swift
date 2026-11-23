import XCTest
@testable import SimiGoRuntimeContract

/// ADR_IS_RENDERING_SNAPSHOT_PERSISTENCE_20261122: frozen rendering snapshots
/// survive a process restart (a NEW ledger instance over the same durable
/// store), keyed by occurrence, fail-open on missing/corrupt rows. The driver
/// evidence is bind T4: after a real restart the ledger was empty, historical
/// injection blocks vanished, and the rendered chain forked (refHash ec4d1a8b
/// ≠ 70d784bf) so poolBind silently missed despite valid authorization.
nonisolated final class ISRenderingSnapshotTests: XCTestCase {

    private func openStore() throws -> (URL, ESISDatabase) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-render-\(UUID().uuidString).sqlite3")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        // No runMigrations(): the table's idempotent DDL must be
        // migration-order independent (same contract as turn_digest_sources).
        return (url, try ESISDatabase(url: url))
    }

    private func resolution(demand: String) -> InformationLoop.Resolution {
        InformationLoop.Resolution(
            demandID: demand, stateID: nil, reused: false, hits: [],
            inputDigest: demand, resultSHA256: "sha", retrievalSettlementID: "ret-1",
            itemIDs: ["file:a"], staleItemIDs: [])
    }

    func testFrozenBytesWarmLoadVerbatimAcrossLedgerInstances() throws {
        let (_, db) = try openStore()
        let before = ISContextLedger()
        before.installRenderStore(db)
        _ = before.stabilize(
            scope: "s", userText: "q", index: 0, block: "BLOCK-1",
            resolution: resolution(demand: "d1"))

        // "Restart": a fresh ledger over the same durable store. Today's
        // candidate drifted, but the committed bytes must replay verbatim.
        let after = ISContextLedger()
        after.installRenderStore(db)
        let snapshot = after.stabilize(
            scope: "s", userText: "q", index: 0, block: "BLOCK-2",
            resolution: resolution(demand: "d2"))
        XCTAssertEqual(snapshot.block, "BLOCK-1")
        XCTAssertTrue(snapshot.isReplay)
        XCTAssertTrue(snapshot.candidateChanged)
        XCTAssertEqual(snapshot.resolution.demandID, "d1",
                       "settlement must claim the retrieval the prompt was built from")
        XCTAssertEqual(after.frozenBlock(scope: "s", userText: "q", index: 0), "BLOCK-1")
    }

    /// The T4 replay path: historical user turns are reconstructed through
    /// frozenBlock alone (HTTPServerChat's contextFreezing loop), no stabilize.
    func testFrozenBlockWarmLoadsHistoryWithoutStabilize() throws {
        let (_, db) = try openStore()
        let before = ISContextLedger()
        before.installRenderStore(db)
        _ = before.stabilize(
            scope: "s", userText: "q0", index: 0, block: "A",
            resolution: resolution(demand: "d0"))
        _ = before.stabilize(
            scope: "s", userText: "q2", index: 2, block: "B",
            resolution: resolution(demand: "d2"))

        let after = ISContextLedger()
        after.installRenderStore(db)
        XCTAssertEqual(after.frozenBlock(scope: "s", userText: "q0", index: 0), "A")
        XCTAssertEqual(after.frozenBlock(scope: "s", userText: "q2", index: 2), "B")
        XCTAssertNil(after.frozenBlock(scope: "s", userText: "q1", index: 1),
                     "an index that was never injected stays un-augmented")
    }

    func testOccurrenceKeysIsolateAcrossRestart() throws {
        let (_, db) = try openStore()
        let before = ISContextLedger()
        before.installRenderStore(db)
        _ = before.stabilize(
            scope: "s", userText: "same", index: 0, block: "A",
            resolution: resolution(demand: "d0"))
        _ = before.stabilize(
            scope: "s", userText: "same", index: 6, block: "B",
            resolution: resolution(demand: "d6"))
        _ = before.stabilize(
            scope: "s", userText: "q1", index: 2, block: "X",
            resolution: resolution(demand: "dx"))

        let after = ISContextLedger()
        after.installRenderStore(db)
        XCTAssertEqual(after.frozenBlock(scope: "s", userText: "same", index: 0), "A")
        XCTAssertEqual(after.frozenBlock(scope: "s", userText: "same", index: 6), "B")
        XCTAssertNil(after.frozenBlock(scope: "s", userText: "same", index: 1))
        // Same index, different text = a NEW occurrence, never a replay of q1.
        let fresh = after.stabilize(
            scope: "s", userText: "q2", index: 2, block: "Y",
            resolution: resolution(demand: "dy"))
        XCTAssertEqual(fresh.block, "Y")
        XCTAssertFalse(fresh.isReplay)
        XCTAssertEqual(after.frozenBlock(scope: "s", userText: "q1", index: 2), "X",
                       "the old occurrence's durable row is untouched")
    }

    func testRefreshOverwritesTheDurableRow() throws {
        let (_, db) = try openStore()
        let before = ISContextLedger()
        before.installRenderStore(db)
        _ = before.stabilize(
            scope: "s", userText: "q", index: 0, block: "OLD",
            resolution: resolution(demand: "d-old"))
        _ = before.refresh(
            scope: "s", userText: "q", index: 0, block: "NEW",
            resolution: resolution(demand: "d-new"))

        let after = ISContextLedger()
        after.installRenderStore(db)
        let snapshot = after.stabilize(
            scope: "s", userText: "q", index: 0, block: "OTHER",
            resolution: resolution(demand: "d-other"))
        XCTAssertEqual(snapshot.block, "NEW")
        XCTAssertEqual(snapshot.resolution.demandID, "d-new")
    }

    func testMissingRowFailsOpenToFreshRender() throws {
        let (_, db) = try openStore()
        let ledger = ISContextLedger()
        ledger.installRenderStore(db)
        XCTAssertNil(ledger.frozenBlock(scope: "s", userText: "q", index: 0))
        let snapshot = ledger.stabilize(
            scope: "s", userText: "q", index: 0, block: "FRESH",
            resolution: resolution(demand: "d1"))
        XCTAssertEqual(snapshot.block, "FRESH")
        XCTAssertFalse(snapshot.isReplay)
    }

    func testCorruptResolutionJSONFailsOpenAndSelfHeals() throws {
        let (_, db) = try openStore()
        let before = ISContextLedger()
        before.installRenderStore(db)
        _ = before.stabilize(
            scope: "s", userText: "q", index: 0, block: "BLOCK-1",
            resolution: resolution(demand: "d1"))
        // Corrupt the durable row's declaration behind the ledger's back.
        try db.saveRenderSnapshot(
            scope: "s", index: 0,
            userTextSHA256: NativeSHA256.hexDigest(Data("q".utf8)),
            block: "BLOCK-1", resolutionJSON: "{not-json")

        let after = ISContextLedger()
        after.installRenderStore(db)
        let snapshot = after.stabilize(
            scope: "s", userText: "q", index: 0, block: "FRESH",
            resolution: resolution(demand: "d2"))
        XCTAssertEqual(snapshot.block, "FRESH", "undecodable row = miss, not wrong bytes")
        XCTAssertFalse(snapshot.isReplay)
        // The fresh freeze wrote through over the corrupt row: a third ledger
        // replays it again.
        let third = ISContextLedger()
        third.installRenderStore(db)
        XCTAssertEqual(third.frozenBlock(scope: "s", userText: "q", index: 0), "FRESH")
    }

    func testRowBudgetEvictsOldestFIFO() throws {
        let (_, db) = try openStore()
        let budget = ESISDatabase.renderSnapshotRowBudget
        let before = ISContextLedger()
        before.installRenderStore(db)
        for index in 0..<(budget + 8) {
            _ = before.stabilize(
                scope: "s", userText: "q\(index)", index: index, block: "b\(index)",
                resolution: resolution(demand: "d\(index)"))
        }
        let after = ISContextLedger()
        after.installRenderStore(db)
        XCTAssertNil(after.frozenBlock(scope: "s", userText: "q0", index: 0),
                     "evicted occurrence falls back to a cold rebuild")
        XCTAssertEqual(
            after.frozenBlock(scope: "s", userText: "q\(budget + 7)", index: budget + 7),
            "b\(budget + 7)")
    }

    /// The product-default posture: no store installed = pure memory, nothing
    /// durable. (The env gate itself lives app-side in HTTPServerChat.)
    func testNoStoreKeepsPureMemoryBehavior() throws {
        let (_, db) = try openStore()
        let ledger = ISContextLedger()
        _ = ledger.stabilize(
            scope: "s", userText: "q", index: 0, block: "MEM",
            resolution: resolution(demand: "d1"))
        let restarted = ISContextLedger()
        restarted.installRenderStore(db)
        XCTAssertNil(restarted.frozenBlock(scope: "s", userText: "q", index: 0),
                     "without a store nothing was written")

        // Installing then removing the store stops further writes.
        let toggled = ISContextLedger()
        toggled.installRenderStore(db)
        _ = toggled.stabilize(
            scope: "s", userText: "kept", index: 1, block: "KEPT",
            resolution: resolution(demand: "dk"))
        toggled.installRenderStore(nil)
        _ = toggled.stabilize(
            scope: "s", userText: "dropped", index: 2, block: "DROPPED",
            resolution: resolution(demand: "dd"))
        let reader = ISContextLedger()
        reader.installRenderStore(db)
        XCTAssertEqual(reader.frozenBlock(scope: "s", userText: "kept", index: 1), "KEPT")
        XCTAssertNil(reader.frozenBlock(scope: "s", userText: "dropped", index: 2))
    }
}
