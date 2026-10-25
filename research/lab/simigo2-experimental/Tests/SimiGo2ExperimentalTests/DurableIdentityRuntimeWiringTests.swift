import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

private final class FlakyForkBackend: ExecutionStateBackend, @unchecked Sendable {
    private var representations: [ExecutionID: ExecutionRepresentation] = [:]
    private var deriveCalls = 0

    func captureRepresentation(for state: ExecutionStateHandle) async throws -> ExecutionRepresentation {
        guard let representation = representations[state.id] else {
            throw ExecutionStateBackendError.noBoundRepresentation(state.id)
        }
        return representation
    }

    func deriveRepresentation(
        from parent: ExecutionRepresentation,
        for child: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation {
        deriveCalls += 1
        if deriveCalls == 1 {
            throw ExecutionStateBackendError.foreignRepresentationPayload(child.id)
        }
        let childRepresentation = ExecutionRepresentation(
            executionID: child.id,
            position: child.position,
            payload: parent.payload
        )
        representations[child.id] = childRepresentation
        return childRepresentation
    }

    func restoreRepresentation(_ representation: ExecutionRepresentation) async throws {
        representations[representation.executionID] = representation
    }

    func releaseRepresentation(_ representation: ExecutionRepresentation) async throws {
        representations.removeValue(forKey: representation.executionID)
    }
}

final class DurableIdentityRuntimeWiringTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-identity-runtime-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCreateAndForkReserveExecutionIDsDurably() async throws {
        let allocator = try DurableExecutionIdentityAllocator(directory: root)
        let backend = MLXExecutionStateBackend()
        let coordinator = ExecutionContinuityCoordinator(
            backend: backend, identityAllocator: allocator)
        let parent = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "seed", continuationID: "seed"))
        try await coordinator.bindRepresentation(
            executionID: parent.id,
            position: ExecutionPosition(0),
            payload: MLXPrefixPayload(tokenPrefix: [1, 2, 3]))

        let child = try await coordinator.fork(ExecutionForkRequest(
            parent: parent,
            childID: ExecutionID("B"),
            childPosition: ExecutionPosition(0),
            childContinuation: ExecutionContinuation(nextInput: "seed", continuationID: "seed")))

        XCTAssertTrue(allocator.hasReserved(parent.id))
        XCTAssertTrue(allocator.hasReserved(child.id))

        let restarted = try DurableExecutionIdentityAllocator(directory: root)
        XCTAssertTrue(restarted.hasReserved(parent.id))
        XCTAssertTrue(restarted.hasReserved(child.id))
        XCTAssertEqual(
            restarted.reservation(forToken: "create:\(parent.id.rawValue)"), parent.id)
        XCTAssertEqual(
            restarted.reservation(forToken: "fork:A:B"), child.id)
    }

    func testFailedForkKeepsDurableChildReservationForRetry() async throws {
        let allocator = try DurableExecutionIdentityAllocator(directory: root)
        let coordinator = ExecutionContinuityCoordinator(
            backend: FlakyForkBackend(), identityAllocator: allocator)
        let parent = try await coordinator.create(
            id: ExecutionID("P"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "seed", continuationID: "seed"))
        try await coordinator.bindRepresentation(
            executionID: parent.id,
            position: ExecutionPosition(0),
            payload: MLXPrefixPayload(tokenPrefix: [1, 2, 3]))

        let request = ExecutionForkRequest(
            parent: parent,
            childID: ExecutionID("C"),
            childPosition: ExecutionPosition(0),
            childContinuation: ExecutionContinuation(nextInput: "seed", continuationID: "seed"))
        do {
            _ = try await coordinator.fork(request)
            XCTFail("injected fork failure must propagate")
        } catch {}

        XCTAssertEqual(
            allocator.reservation(forToken: "fork:P:C"), request.childID)
        let child = try await coordinator.fork(request)
        XCTAssertEqual(child.id, request.childID)
        XCTAssertTrue(allocator.hasReserved(child.id))
    }

    func testEngineWiresIdentityDirectoryAndFailsClosedOnCorruption() async throws {
        let modelRoot = root.appendingPathComponent("model")
        let identityRoot = root.appendingPathComponent("identity")
        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        try Data("tokenizer-v1".utf8).write(to: modelRoot.appendingPathComponent("tokenizer.json"))

        let engine = OversizedSegmentedEngine(
            modelDirectory: modelRoot,
            identityDirectory: identityRoot)
        engine.debugReleaseAllOverride = {}
        let state = try await engine.debugEnsureSession(prefix: [1, 2, 3])

        let restarted = try DurableExecutionIdentityAllocator(directory: identityRoot)
        XCTAssertEqual(restarted.hasReserved(state.id), true)

        try Data("{torn\n".utf8).write(
            to: identityRoot.appendingPathComponent("execution-ids.jsonl"))
        let corruptEngine = OversizedSegmentedEngine(
            modelDirectory: modelRoot,
            identityDirectory: root.appendingPathComponent("identity-next"))
        corruptEngine.debugReleaseAllOverride = {}

        let corruptAllocatorRoot = identityRoot
        XCTAssertThrowsError(try DurableExecutionIdentityAllocator(directory: corruptAllocatorRoot)) {
            error in
            guard case .ledgerCorrupt = error as? ExecutionIdentityAllocatorError else {
                return XCTFail("unexpected engine allocator error: \(error)")
            }
        }
    }
}
