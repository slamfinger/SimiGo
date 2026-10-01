import XCTest
@testable import SimiGo

final class ExecutionStateGraphTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoStateGraphTests-\(UUID().uuidString)")
            .appendingPathComponent("graph.json")
    }

    @MainActor
    func testCreateContinueForkKeepsParentClosureUntouched() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL)
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
        let store = ExecutionStateGraphStore(storeURL: storeURL)
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
        let first = ExecutionStateGraphStore(storeURL: storeURL)
        let root = try first.create()
        try first.continueState(root, input: "durable")
        try first.save(try XCTUnwrap(first.state(root.id)))

        let second = ExecutionStateGraphStore(storeURL: storeURL)
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
        let store = ExecutionStateGraphStore(storeURL: storeURL)
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
}
