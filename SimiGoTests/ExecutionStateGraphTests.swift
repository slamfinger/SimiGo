import XCTest
import SQLite3
import SimiGoRuntimeContract
@testable import SimiGo

final class ExecutionStateGraphTests: XCTestCase {
    private var storeURL: URL!
    private var dbURL: URL!

    override func setUp() {
        super.setUp()
        // Hermetic: BOTH the JSON storeURL and the authoritative SQLite dbURL are
        // scoped to a fresh per-test temp directory, so multiple store instances in
        // a run never collide on the shared global authority (the store rebuilds its
        // document from SQLite, not JSON, since the ES/IS integration).
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoStateGraphTests-\(UUID().uuidString)")
        storeURL = base.appendingPathComponent("graph.json")
        dbURL = base.appendingPathComponent("estates.sqlite3")
    }

    func testLegacyGraphLoaderDistinguishesMissingFromUnreadable() throws {
        XCTAssertNil(
            try BootstrapRunner.loadLegacyGraph(at: storeURL),
            "a genuinely absent legacy graph is optional")

        let directoryURL = storeURL.appendingPathExtension("directory")
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        XCTAssertThrowsError(
            try BootstrapRunner.loadLegacyGraph(at: directoryURL),
            "an existing but unreadable path must not be treated as an absent graph")

        // ENOTDIR is an obstruction, not absence: a regular-file parent means
        // the configured legacy path cannot be inspected and must fail closed.
        // Keep the blocker as a sibling inside the still-existing temp directory;
        // do not replace the directory that the previous case just exercised.
        let blockedParent = storeURL.deletingLastPathComponent()
            .appendingPathComponent("not-a-directory")
        try Data("not a directory".utf8).write(to: blockedParent)
        defer { try? FileManager.default.removeItem(at: blockedParent) }
        XCTAssertThrowsError(
            try BootstrapRunner.loadLegacyGraph(
                at: blockedParent.appendingPathComponent("graph.json")),
            "a non-directory parent must not be treated as a missing legacy graph")
    }

    func testBootstrapPreflightFailureReplacesStaleSuccessReport() throws {
        let base = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true)

        let blockedParent = base.appendingPathComponent("not-a-directory-report-test")
        try Data("not a directory".utf8).write(to: blockedParent)
        defer { try? FileManager.default.removeItem(at: blockedParent) }

        let reportURL = base.appendingPathComponent("bootstrap-report.json")
        let staleReport = Data("""
        {
          "startedAt": "stale",
          "finishedAt": "stale",
          "schemaVersion": 1,
          "steps": [],
          "modelsDiscovered": 99,
          "workFilesIndexed": 99,
          "legacyMigrated": true,
          "issueCount": 0
        }
        """.utf8)
        try staleReport.write(to: reportURL)

        let result = BootstrapRunner.launchIfNeeded(
            storeURL: blockedParent.appendingPathComponent("graph.json"),
            dbURL: dbURL,
            launchedAt: Date(timeIntervalSince1970: 1_800_000_000),
            reportURL: reportURL)

        XCTAssertNil(result, "a failed legacy graph preflight must stop bootstrap")
        let report = try JSONDecoder().decode(
            BootstrapReport.self, from: Data(contentsOf: reportURL))
        XCTAssertFalse(report.ok)
        XCTAssertEqual(report.issueCount, 1)
        XCTAssertGreaterThanOrEqual(report.schemaVersion, 0)
        XCTAssertEqual(report.steps.map(\.id), ["load-legacy-graph"])
        XCTAssertEqual(report.steps.first?.status, .failed)
        XCTAssertEqual(report.modelsDiscovered, 0)
        XCTAssertEqual(report.workFilesIndexed, 0)
        XCTAssertFalse(report.legacyMigrated)
    }

    @MainActor
    func testCreateContinueForkKeepsParentClosureUntouched() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.continueState(root, input: "shared")
        let parent = try XCTUnwrap(store.state(root.id))

        let child = try store.fork(parent)
        try store.continueState(child, input: "branch")

        let unchangedParent = try XCTUnwrap(store.state(parent.id))
        let changedChild = try XCTUnwrap(store.state(child.id))
        XCTAssertEqual(unchangedParent.position, 1)
        XCTAssertEqual(unchangedParent.prefix, ["shared"])
        XCTAssertEqual(changedChild.position, 2)
        XCTAssertEqual(changedChild.prefix, ["shared", "branch"])
        XCTAssertEqual(changedChild.parentID, parent.id)
    }

    @MainActor
    func testForkRejectsStaleSnapshotAfterParentDiscard() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.continueState(root, input: "shared")
        let staleParent = try XCTUnwrap(store.state(root.id))
        XCTAssertEqual(staleParent.lifecycle, .active)

        // Keep the pre-discard snapshot, then change the authoritative graph.
        try store.discard(staleParent)
        XCTAssertEqual(staleParent.lifecycle, .active,
                       "the caller's value remains stale by construction")
        XCTAssertEqual(store.state(root.id)?.lifecycle, .discarded)

        XCTAssertThrowsError(
            try store.fork(staleParent),
            "fork must consult the current graph, not the stale active snapshot")
        XCTAssertTrue(store.children(of: root.id).isEmpty,
                      "a discarded parent must not acquire a new child")

        // Reopen from SQLite to prove the refused fork did not persist a child.
        let reopened = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.state(root.id)?.lifecycle, .discarded)
        XCTAssertTrue(reopened.children(of: root.id).isEmpty)
    }

    @MainActor
    func testSaveRestoreFailsClosedOnTamperedCheckpoint() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.continueState(root, input: "valid")
        let checkpoint = try store.save(try XCTUnwrap(store.state(root.id)))

        try store.continueState(try XCTUnwrap(store.state(root.id)), input: "after-save")
        var tampered = checkpoint
        tampered = ExecutionCheckpoint(
            id: checkpoint.id,
            stateID: checkpoint.stateID,
            modelIdentity: checkpoint.modelIdentity,
            position: checkpoint.position,
            continuationID: checkpoint.continuationID,
            nextInput: checkpoint.nextInput,
            anchor: checkpoint.anchor,
            prefix: ["tampered"],
            createdAt: checkpoint.createdAt,
            checksum: checkpoint.checksum
        )

        XCTAssertThrowsError(try store.restore(try XCTUnwrap(store.state(root.id)), checkpoint: tampered))
        let restored = try store.restore(try XCTUnwrap(store.state(root.id)), checkpoint: checkpoint)
        XCTAssertEqual(restored.prefix, ["valid"])
        XCTAssertEqual(restored.lifecycle, .restored)
    }

    @MainActor
    func testDurableGraphPersistsAcrossStoreInstances() throws {
        let first = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try first.create()
        try first.continueState(root, input: "durable")
        try first.save(try XCTUnwrap(first.state(root.id)))

        let second = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        XCTAssertEqual(second.document, first.document)

        XCTAssertNil(second.loadError)
        let restored = try second.restore(
            try XCTUnwrap(second.state(root.id)),
            checkpoint: try XCTUnwrap(second.checkpoints.first)
        )
        XCTAssertEqual(restored.prefix, ["durable"])
    }

    @MainActor
    func testDiscardRemovesGhostContinuationAndReleaseKeepsLogicalState() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.save(root)
        let saved = try XCTUnwrap(store.state(root.id))
        let ghost = ExecutionCheckpoint(
            id: UUID(),
            stateID: root.id,
            modelIdentity: "reference-model",
            position: 0,
            continuationID: "invalid",
            nextInput: "",
            anchor: ExecutionStateGraphStore.anchor([]),
            prefix: [],
            createdAt: Date(),
            checksum: "invalid"
        )

        try store.discard(saved)
        XCTAssertNil(store.checkpoints(for: root.id).first)
        XCTAssertEqual(store.state(root.id)?.lifecycle, .discarded)
        XCTAssertThrowsError(try store.restore(try XCTUnwrap(store.state(root.id)), checkpoint: ghost))

        let releasable = try store.create()
        try store.save(releasable)
        try store.release(try XCTUnwrap(store.state(releasable.id)))
        XCTAssertTrue(store.checkpoints(for: releasable.id).isEmpty)
        XCTAssertEqual(store.state(releasable.id)?.lifecycle, .active)
    }

    /// Integration proof that the native settlement gate is wired into the app's
    /// real production call chain (UI Settle action -> `settleProducerResult` ->
    /// `SettlementAuthority` -> authoritative SQLite IS commit), and that it
    /// stays fail-closed. A temp `dbURL` keeps the run off the global store.
    @MainActor
    func testSettleProducerResultCommitsThroughNativeGateAndFailsClosed() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoSettleTests-\(UUID().uuidString)")
            .appendingPathComponent("estates.sqlite3")
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.continueState(root, input: "shared")
        let state = try XCTUnwrap(store.state(root.id))

        // Fail-closed: a producer result that does not commit to the IS next-input
        // is refused by the native gate and nothing is settled.
        XCTAssertThrowsError(try store.settleProducerResult(generatedText: "RESULT=tampered", boundToState: state)) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "PRODUCER_RESULT_BINDING_MISMATCH")
        }
        XCTAssertNil(store.document.settlements?.first(where: { $0.stateID == state.id }))

        // Authorized: the validated payload commits to the graph and to SQLite IS.
        let settled = try store.settleProducerResult(generatedText: "RESULT=shared", boundToState: state)
        XCTAssertEqual(settled.trace.validationStatus, "VALID")
        XCTAssertEqual(store.document.settlements?.filter { $0.stateID == state.id }.count, 1)

        let db = try XCTUnwrap(store.esis)
        let receipts = try db.readSettlementReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.payloadDigest, settled.payloadDigest)
        XCTAssertEqual(receipts.first?.stateID, state.id)
    }

    /// A failed authoritative SQLite graph write must not be reported as a
    /// successful JSON-only mutation. The trigger makes the failure deterministic
    /// without relying on timing, filesystem permissions, or a busy timeout.
    @MainActor
    func testSQLiteWriteFailureIsPropagatedWithoutPublishingJSONFallback() throws {
        // Create the valid schema first, then add a trigger that rejects the
        // graph insert performed by writeGraph.
        do {
            let database = try ESISDatabase(url: dbURL)
            try database.runMigrations()
        }

        var rawDatabase: OpaquePointer?
        let openResult = sqlite3_open_v2(
            dbURL.path, &rawDatabase, SQLITE_OPEN_READWRITE, nil)
        guard openResult == SQLITE_OK, let rawDatabase else {
            XCTFail("could not open test database for trigger setup (SQLite code \(openResult))")
            if let rawDatabase { _ = sqlite3_close_v2(rawDatabase) }
            return
        }

        let triggerSQL = """
        CREATE TRIGGER reject_execution_state_insert
        BEFORE INSERT ON execution_states
        BEGIN
            SELECT RAISE(ABORT, 'forced graph persistence failure');
        END;
        """
        let triggerResult = sqlite3_exec(rawDatabase, triggerSQL, nil, nil, nil)
        let triggerError = String(cString: sqlite3_errmsg(rawDatabase))
        let closeResult = sqlite3_close_v2(rawDatabase)
        XCTAssertEqual(triggerResult, SQLITE_OK, triggerError)
        XCTAssertEqual(closeResult, SQLITE_OK)
        guard triggerResult == SQLITE_OK else { return }

        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        XCTAssertNil(store.loadError)

        XCTAssertThrowsError(try store.create())
        XCTAssertTrue(store.states.isEmpty)
        XCTAssertNotNil(store.persistError)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.path),
            "legacy JSON is read-only and must not become a substitute authority")

        let reopened = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        XCTAssertNil(reopened.loadError)
        XCTAssertTrue(
            reopened.states.isEmpty,
            "a fresh store must see the unchanged authoritative SQLite graph")
    }

}
