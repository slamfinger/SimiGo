import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class DurableExecutionStateStoreTests: XCTestCase {
    private var root: URL!
    private var store: DurableExecutionStateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-state-\(UUID().uuidString)")
        store = DurableExecutionStateStore(directory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func handle(
        _ raw: String, parent: String? = nil, position: Int64,
        lifecycle: ExecutionBranchLifecycle
    ) -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID(raw),
            lineage: ExecutionLineage(
                root: ExecutionID(parent ?? raw), parent: parent.map(ExecutionID.init)),
            position: ExecutionPosition(position),
            continuation: ExecutionContinuation(
                nextInput: "next-\(raw)", continuationID: "cont-\(raw)"),
            lifecycle: lifecycle)
    }

    func testEmptyStoreLoadsEmptyState() throws {
        let loaded = try store.load()
        XCTAssertTrue(loaded.handles.isEmpty)
        XCTAssertTrue(loaded.lifecycleRecords.isEmpty)
    }

    func testAtomicSnapshotRoundTripsSemanticStateAndAudit() throws {
        let parent = handle("P", position: 2, lifecycle: .active)
        let child = handle("C", parent: "P", position: 2, lifecycle: .active)
        let records = [
            ExecutionContinuityCoordinator.LifecycleRecord(
                sequence: 1, operation: .created, executionID: parent.id,
                relatedID: nil, resultLifecycle: .attached,
                resultPosition: ExecutionPosition(0),
                resultContinuation: parent.continuation),
            ExecutionContinuityCoordinator.LifecycleRecord(
                sequence: 2, operation: .forked, executionID: child.id,
                relatedID: parent.id, resultLifecycle: .active,
                resultPosition: ExecutionPosition(2),
                resultContinuation: child.continuation),
        ]

        try store.replace(handles: [parent, child], lifecycleRecords: records)
        let loaded = try store.load()
        XCTAssertEqual(Set(loaded.handles), Set([parent, child]))
        XCTAssertEqual(loaded.lifecycleRecords, records)

        let restarted = DurableExecutionStateStore(directory: root)
        XCTAssertEqual(try restarted.load(), loaded)
    }

    func testCorruptSnapshotFailsClosed() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{not-state".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            guard case DurableExecutionStateStore.StoreError.malformedState = error else {
                return XCTFail("unexpected store error: \(error)")
            }
        }
    }

    func testCoordinatorRestoresHandlesAndContinuesAuditSequence() async throws {
        let backend = MLXExecutionStateBackend()
        let first = try ExecutionContinuityCoordinator(backend: backend, identityAllocator: nil, stateStore: store)
        let parent = try await first.create(
            id: ExecutionID("P"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "seed", continuationID: "cont-0"))
        _ = try await first.continueExecution(
            parent,
            continuation: ExecutionContinuation(nextInput: "next", continuationID: "cont-1"))
        XCTAssertEqual(first.recordCount, 2)

        let restarted = try ExecutionContinuityCoordinator(
            backend: MLXExecutionStateBackend(),
            identityAllocator: nil,
            stateStore: store)
        let restored = try XCTUnwrap(restarted.handle(ExecutionID("P")))
        XCTAssertEqual(restored.position, ExecutionPosition(1))
        XCTAssertEqual(restored.lifecycle, .active)
        XCTAssertEqual(restarted.recordCount, 2)

        let advanced = try await restarted.continueExecution(
            restored,
            continuation: ExecutionContinuation(nextInput: "next-2", continuationID: "cont-2"))
        XCTAssertEqual(advanced.position, ExecutionPosition(2))
        XCTAssertEqual(restarted.recordCount, 3)
        XCTAssertEqual(restarted.recordsSnapshot.last?.sequence, 3)
    }

    func testDurableCommitFailureDoesNotAdvanceAuditOrReportSuccess() throws {
        // Seed a valid readable snapshot, then inject a commit-time payload
        // sync failure so the transition reaches the durable boundary but
        // cannot publish.
        try store.replace(handles: [], lifecycleRecords: [])
        DurableFileWriter.debugFailingDirectorySyncPhases = ["payload"]
        defer { DurableFileWriter.debugFailingDirectorySyncPhases = [] }

        let coordinator = try ExecutionContinuityCoordinator(
            backend: MLXExecutionStateBackend(),
            identityAllocator: nil,
            stateStore: store)
        let expectation = expectation(description: "durable commit failure")
        Task {
            do {
                _ = try await coordinator.create(
                    id: ExecutionID("A"),
                    position: ExecutionPosition(0),
                    continuation: ExecutionContinuation(nextInput: "", continuationID: ""))
                XCTFail("durable commit failure must propagate")
            } catch let error as ExecutionContinuityCoordinator.CoordinatorError {
                XCTAssertEqual(error, .durableStateCommitFailed(ExecutionID("A")))
            } catch {
                XCTFail("unexpected error: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertNil(coordinator.handle(ExecutionID("A")))
        XCTAssertEqual(coordinator.recordCount, 0)
    }
}
