import XCTest
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
    /// `SimiGoSettlementAuthority` -> authoritative SQLite IS commit), and that it
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
}
