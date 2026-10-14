import XCTest
import MLXLMCommon
import MLX
import Foundation
import Crypto
@testable import SimiGo2Experimental

private let f3ns = PrefixPoolNamespace(modelID: "qwen3-8b", kvFingerprint: "fp-mlc4")

private enum MaterializationProbeError: Error, CustomStringConvertible {
    case timedOutWaitingForFirstWorkCall
    case timedOutWaitingForJoin(String)

    var description: String {
        switch self {
        case .timedOutWaitingForFirstWorkCall:
            return "Timed out waiting for the first materialization work call"
        case .timedOutWaitingForJoin(let key):
            return "Timed out waiting for single-flight join for key: \(key)"
        }
    }
}

/// Starts both racing materializations only after both have reached the
/// startup point. This reduces task-creation skew; it is not a coordinator
/// internal wait-queue barrier.
private actor MaterializationStartBarrier {
    private let participantCount: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func wait() async {
        arrivals += 1
        if arrivals == participantCount {
            let ready = waiters
            waiters.removeAll()
            ready.forEach { $0.resume() }
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }
}

/// Replaces a fixed sleep with a controllable work boundary so assertions can
/// observe the single admitted closure before and after it is released.
private actor MaterializationWorkGate {
    private var callContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0
    private var released = false

    func enterWork() async {
        callCount += 1
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if released {
                continuation.resume()
            } else {
                callContinuations.append(continuation)
            }
        }
    }

    func waitForFirstCall(timeoutNanoseconds: UInt64 = 5_000_000_000) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while callCount == 0 {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw MaterializationProbeError.timedOutWaitingForFirstWorkCall
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func release() {
        released = true
        let ready = callContinuations
        callContinuations.removeAll()
        ready.forEach { $0.resume() }
    }
}

private actor MaterializationJoinProbe {
    private var joinedKeys: [String] = []

    func record(_ key: String) {
        joinedKeys.append(key)
    }

    func waitForJoin(_ key: String, timeoutNanoseconds: UInt64 = 5_000_000_000) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !joinedKeys.contains(key) {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw MaterializationProbeError.timedOutWaitingForJoin(key)
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    var joinCount: Int { joinedKeys.count }
}

private func f3tokens(_ count: Int, seed: Int = 0) -> [Int] {
    (0..<count).map { ($0 * 31 + seed * 7) % 50_000 + 3 }
}

private func storeDeleteFailure(_ failures: [Error]) -> PrefixSnapshotStoreError? {
    failures.first as? PrefixSnapshotStoreError
}

private func waitForMaterializationPreparation(
    _ registry: PhysicalUseRegistry,
    key: String,
    timeoutNanoseconds: UInt64 = 5_000_000_000
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !(registry.isPreparingGeneration(key) && registry.inFlightLeaseCount(key) > 0) {
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw MaterializationProbeError.timedOutWaitingForFirstWorkCall
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

private final class URLBox: @unchecked Sendable {
    var value: URL?
}

private func f3writeSnapshot(to url: URL) throws {
    let layer = KVCacheSimple()
    layer.update(
        keys: MLXArray.zeros([1, 2, 8, 4]),
        values: MLXArray.zeros([1, 2, 8, 4]))
    try savePromptCache(url: url, cache: [layer])
}

private func f3writeSynthetic(to url: URL) async throws -> Void {
    try f3writeSnapshot(to: url)
}

/// F3 Coordinator Skeleton battery (IMPLEMENTATION_PLANNING first cut,
/// zero-MLX synthetic artifacts). Success criterion: prove the
/// Representation physical-lifecycle infrastructure does NOT break the
/// closed Execution/Binding/PrefixPool semantic lines.
///
/// T1 materialize × eviction — artifact must not be deleted while a Work
///    holds it; eviction eligibility restored after release.
/// T2 materialize × materialize — one MaterializationWork per Ref key;
///    joiners reuse the same result; no second underlying load.
/// T3 materialize × restart/rescan — P2 eviction persistence intact;
///    restart never resurrects deleted artifacts; in-flight protection
///    is transient (never masquerades as persistent state).
final class MaterializationCoordinatorTests: XCTestCase {
    func testEvictionDuringMaterializeIsDeferred() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("f3-t1-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = ExecutionStatePrefixPool(tokenBudget: 600)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        let coordinator = MaterializationCoordinator<String>(physicalUse: store.physicalUse)

        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(512, seed: 1), write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let artifactPath = (entry.artifact as! DiskPrefixArtifact).snapshotURL.path

        // The work itself triggers the eviction of its own artifact
        // (budget 600: exporting B evicts LRU A) and observes protection.
        final class Flag: @unchecked Sendable {
            private let l = NSLock()
            private var v = false
            func set() { l.lock(); v = true; l.unlock() }
            var value: Bool { l.lock(); defer { l.unlock() }; return v }
        }
        let flag = Flag()
        let seed2 = f3tokens(512, seed: 2)
        let value = try await coordinator.materialize(key: artifactPath) {
            _ = try await store.export(
                namespace: f3ns, tokens: seed2, write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
            flag.set()
            return "done"
        }
        XCTAssertEqual(value, "done")
        XCTAssertTrue(
            flag.value,
            "in-flight artifact must survive a concurrent eviction request")
        // After release: deferred deletion fires — eviction eligibility
        // fully restored.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: artifactPath),
            "deferred delete must fire once the physical use is released")
        XCTAssertEqual(store.pool.stats.evictions, 1)
    }

    func testConcurrentMaterializeRunsSingleFlight() async throws {
        let registry = PhysicalUseRegistry(onDelete: { _, _ in })
        let coordinator = MaterializationCoordinator<Int>(physicalUse: registry)
        let startBarrier = MaterializationStartBarrier(participantCount: 2)
        let workGate = MaterializationWorkGate()
        let joinProbe = MaterializationJoinProbe()
        coordinator.setJoinObserver { [joinProbe] key in
            await joinProbe.record(key)
        }
        final class Counter: @unchecked Sendable {
            private let l = NSLock()
            private var v = 0
            func bump() { l.lock(); v += 1; l.unlock() }
            var value: Int { l.lock(); defer { l.unlock() }; return v }
        }
        let loads = Counter()

        enum MaterializeOutcome {
            case success(Int)
            case failure(Error)
        }

        let tasks = (0..<2).map { _ in
            Task { () -> MaterializeOutcome in
                await startBarrier.wait()
                do {
                    let value = try await coordinator.materialize(key: "ref-X") {
                        loads.bump()
                        await workGate.enterWork()
                        return 42
                    }
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            }
        }

        do {
            try await workGate.waitForFirstCall()
            try await joinProbe.waitForJoin("ref-X")
        } catch {
            // A failed observation must not strand the underlying work at the
            // gate or leak racing tasks past the end of this test.
            await workGate.release()
            for task in tasks {
                _ = await task.value
            }
            throw error
        }
        let callsBeforeRelease = await workGate.callCount
        XCTAssertEqual(callsBeforeRelease, 1, "exactly one underlying work may start before release")
        let joinsBeforeRelease = await joinProbe.joinCount
        XCTAssertEqual(joinsBeforeRelease, 1, "the second caller must reuse the in-flight work before release")

        await workGate.release()
        var outcomes: [MaterializeOutcome] = []
        for task in tasks {
            outcomes.append(await task.value)
        }
        let callsAfterRelease = await workGate.callCount
        let joinsAfterRelease = await joinProbe.joinCount

        let failures = outcomes.compactMap {
            if case .failure(let error) = $0 { return error }
            return nil
        }
        XCTAssertTrue(failures.isEmpty, "no materialization caller should fail")
        XCTAssertEqual(outcomes.compactMap {
            if case .success(let value) = $0 { return value }
            return nil
        }, [42, 42], "both callers share the single work's result")
        XCTAssertEqual(callsAfterRelease, 1, "no duplicate underlying work may start after release")
        XCTAssertEqual(joinsAfterRelease, 1, "only one single-flight join should be observed")
        // WHICH caller creates the work is nondeterministic — the
        // contract is: same result for both, exactly ONE underlying load.
        XCTAssertEqual(loads.value, 1, "single-flight: one work, shared result")
        XCTAssertEqual(registry.physicalUseCount("ref-X"), 0, "protection released")
    }

    func testProtectionIsTransientAndP2SemanticsSurvive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("f3-t3-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = ExecutionStatePrefixPool(tokenBudget: 10_000)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        let coordinator = MaterializationCoordinator<String>(physicalUse: store.physicalUse)

        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 4), write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let artifact = entry.artifact as! DiskPrefixArtifact
        let sidecarBefore = try Data(contentsOf: artifact.metadataURL)

        // A completed materialization writes NO persistent protection
        // state: sidecar bytes identical before/after.
        _ = try await coordinator.materialize(key: artifact.snapshotURL.path) { "ok" }
        let sidecarAfter = try Data(contentsOf: artifact.metadataURL)
        XCTAssertEqual(sidecarBefore, sidecarAfter, "transient protection leaves no trace")

        // Evict (no in-flight use → immediate delete), then
        // restart-rescan must not resurrect.
        try store.remove(entry)
        let fresh = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        XCTAssertEqual(try fresh.rescan(), 0, "removed artifact stays gone")
        XCTAssertNil(
            fresh.pool.admit(namespace: f3ns, promptTokens: f3tokens(256, seed: 4)))
    }

    /// Rescan must register the disk generation before pool eviction can
    /// request cleanup; otherwise a budget-evicted rescan artifact looks
    /// stale and is left behind as an orphan.
    func testRescanRegistersGenerationBeforeSelfEvictionCleanup() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rescan-self-evict-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let tokens = f3tokens(256, seed: 5)
        let entry = try await source.export(namespace: f3ns, tokens: tokens) { url in
            try "payload".write(to: url, atomically: true, encoding: .utf8)
        }
        let artifact = entry.artifact as! DiskPrefixArtifact
        let deleted = DeletedGenerations()
        let fresh = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 1),
            artifactIOLock: NSLock(),
            deleteArtifact: { key, generation in
                deleted.record(generation)
                try FileManager.default.removeItem(atPath: key)
                let metadataURL = URL(fileURLWithPath: key)
                    .deletingPathExtension()
                    .appendingPathExtension("json")
                try FileManager.default.removeItem(at: metadataURL)
            }
        )

        XCTAssertEqual(try fresh.rescan(), 1)

        XCTAssertEqual(deleted.generations, [artifact.generation])
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.metadataURL.path))
        XCTAssertNil(fresh.pool.admit(namespace: f3ns, promptTokens: tokens))
    }

    /// Rescan scans outside the artifact I/O lock, so a deletion can finish
    /// after the sidecar is read. The publication must revalidate the exact
    /// generation under that lock before registering a pool entry.
    func testRescanSkipsArtifactDeletedAfterScan() async throws {
        final class ScanGate: @unchecked Sendable {
            private let entered = DispatchSemaphore(value: 0)
            private let leave = DispatchSemaphore(value: 0)

            func enter() {
                entered.signal()
                _ = leave.wait(timeout: .now() + 5)
            }

            func waitForEnter() -> Bool {
                entered.wait(timeout: .now() + 5) == .success
            }

            func release() { leave.signal() }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rescan-vanished-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let tokens = f3tokens(256, seed: 6)
        let entry = try await source.export(namespace: f3ns, tokens: tokens) { url in
            try "payload".write(to: url, atomically: true, encoding: .utf8)
        }
        let artifact = entry.artifact as! DiskPrefixArtifact

        let gate = ScanGate()
        let fresh = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { _, _ in },
            willBeginRescanGeneration: { gate.enter() }
        )
        // Make the scanned generation current without pool-registering it, so
        // the deterministic hook pauses exactly before conditional publication.
        fresh.physicalUse.beginGeneration(
            artifact.snapshotURL.path, generation: artifact.generation) {}

        let rescan = Task.detached { try fresh.rescan() }
        guard gate.waitForEnter() else {
            gate.release()
            _ = try await rescan.value
            return XCTFail("rescan never reached conditional publication")
        }

        try FileManager.default.removeItem(at: artifact.snapshotURL)
        try FileManager.default.removeItem(at: artifact.metadataURL)
        gate.release()

        let registeredCount = try await rescan.value
        XCTAssertEqual(registeredCount, 0)
        XCTAssertNil(fresh.pool.admit(namespace: f3ns, promptTokens: tokens))
    }

    /// A legacy sidecar may have a nil generation, but a missing sidecar is
    /// still unknown state; rescan must not treat `nil == nil` as a match.
    func testRescanSkipsLegacyArtifactWhenSidecarDisappears() async throws {
        final class ScanGate: @unchecked Sendable {
            private let entered = DispatchSemaphore(value: 0)
            private let leave = DispatchSemaphore(value: 0)

            func enter() {
                entered.signal()
                _ = leave.wait(timeout: .now() + 5)
            }

            func waitForEnter() -> Bool {
                entered.wait(timeout: .now() + 5) == .success
            }

            func release() { leave.signal() }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rescan-legacy-vanished-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let tokens = f3tokens(256, seed: 7)
        let entry = try await source.export(namespace: f3ns, tokens: tokens) { url in
            try "payload".write(to: url, atomically: true, encoding: .utf8)
        }
        let artifact = entry.artifact as! DiskPrefixArtifact
        let sidecar = try JSONDecoder().decode(
            PrefixSnapshotSidecar.self,
            from: Data(contentsOf: artifact.metadataURL)
        )
        var legacySidecar = sidecar
        legacySidecar.generation = nil
        try JSONEncoder().encode(legacySidecar).write(
            to: artifact.metadataURL, options: .atomic)

        let gate = ScanGate()
        let fresh = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { _, _ in },
            willBeginRescanGeneration: { gate.enter() }
        )
        fresh.physicalUse.beginGeneration(
            artifact.snapshotURL.path, generation: nil) {}

        let rescan = Task.detached { try fresh.rescan() }
        guard gate.waitForEnter() else {
            gate.release()
            _ = try await rescan.value
            return XCTFail("rescan never reached conditional publication")
        }

        try FileManager.default.removeItem(at: artifact.metadataURL)
        gate.release()

        let registeredCount = try await rescan.value
        XCTAssertEqual(registeredCount, 0)
        XCTAssertNil(fresh.pool.admit(namespace: f3ns, promptTokens: tokens))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))
    }

    /// The eviction sink is part of a store/pool reference cycle unless it
    /// captures the store weakly.
    func testStoreDoesNotRetainItselfThroughEvictionSink() async throws {
        weak var weakStore: PrefixSnapshotStore?
        var retainedPool: ExecutionStatePrefixPool?

        autoreleasepool {
            let pool = ExecutionStatePrefixPool(tokenBudget: 10_000)
            let store = PrefixSnapshotStore(
                root: FileManager.default.temporaryDirectory
                    .appendingPathComponent("store-lifetime-\(UUID().uuidString)"),
                pool: pool
            )
            weakStore = store
            retainedPool = pool
        }

        XCTAssertNotNil(retainedPool)
        XCTAssertNil(weakStore, "eviction sink must not retain its store")
    }

    // MARK: - Delete decision/execution window

    /// A duplicate request for the generation already deleting must dedupe;
    /// cleanup must reopen admission and return a generation-bound lease.
    func testDeleteExecutionRejectsLeaseUntilCallbackCompletes() async throws {
        let key = "delete-execution"
        let gate = DeleteExecutionGate()
        let registry = PhysicalUseRegistry(onDelete: { _, _ in
            gate.enterDelete()
        })

        let deletion = Task.detached {
            registry.requestDelete(key, generation: nil)
        }
        try await gate.waitForDeleteStart()
        XCTAssertNil(registry.acquire(key), "no lease may be admitted during delete execution")

        // The request targets the generation already deleting: it dedupes.
        registry.requestDelete(key, generation: nil)
        gate.finishDelete()
        await deletion.value
        XCTAssertEqual(gate.startCount, 1, "same-generation delete requests dedupe")
        XCTAssertNotNil(
            registry.acquire(key),
            "cleanup must admit a later recreation of the same path")
        registry.release(registry.acquire(key)!)
    }

    /// The pending-to-executing transition must use the same deletion state:
    /// the release of the final lease closes admission before `onDelete`
    /// starts, and cleanup reopens it afterward.
    func testDeferredDeleteExecutionRejectsLeaseUntilCallbackCompletes() async throws {
        let key = "deferred-delete-execution"
        let gate = DeleteExecutionGate()
        let registry = PhysicalUseRegistry(onDelete: { _, _ in
            gate.enterDelete()
        })

        let lease = registry.acquire(key)!
        registry.requestDelete(key, generation: nil)
        let releaser = Task.detached {
            registry.release(lease)
        }

        try await gate.waitForDeleteStart()
        XCTAssertNil(registry.acquire(key), "pending deletion must close admission on execution")

        gate.finishDelete()
        await releaser.value
        XCTAssertNotNil(registry.acquire(key), "cleanup must reopen admission for path reuse")
        registry.release(registry.acquire(key)!)
    }

    /// A lease is an ownership token. Releasing it twice must not consume a
    /// different holder's count or end another in-flight physical use.
    func testDuplicateReleaseCannotEndForeignLease() async throws {
        let key = "duplicate-release"
        let deleted = DeletedGenerations()
        let registry = PhysicalUseRegistry(onDelete: { _, generation in
            deleted.record(generation)
        })
        let first = registry.acquire(key)
        let second = registry.acquire(key)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)

        XCTAssertNil(registry.requestDelete(key, generation: nil))
        registry.release(first!)
        registry.release(first!)

        XCTAssertEqual(registry.physicalUseCount(key), 1, "second lease remains protected")
        XCTAssertNil(registry.acquire(key), "pending delete remains admission-gated")

        registry.release(second!)
        XCTAssertEqual(registry.physicalUseCount(key), 0)
        XCTAssertEqual(deleted.generations, [nil])
    }

    /// A queued request for a live replacement executes independently after
    /// the old generation; a duplicate old-generation request does not run.
    func testReplacementGenerationDeleteRunsAfterOldGeneration() async throws {
        let key = "generation-queue"
        let gate = DeleteExecutionGate()
        let deleted = DeletedGenerations()
        let registry = PhysicalUseRegistry(onDelete: { _, generation in
            deleted.record(generation)
            gate.enterDelete()
        })
        let old = UUID()
        let replacement = UUID()

        registry.beginGeneration(key, generation: old) {}
        let deletion = Task.detached {
            registry.requestDelete(key, generation: old)
        }
        try await gate.waitForDeleteStart()
        registry.requestDelete(key, generation: old)

        registry.beginGeneration(key, generation: replacement) {}
        registry.requestDelete(key, generation: replacement)
        XCTAssertNil(registry.acquire(key), "replacement publication remains delete-gated")

        gate.finishDelete()
        try await gate.waitForDeleteStart(minimumStartCount: 2)
        XCTAssertNil(registry.acquire(key), "new-generation delete must stay admission-gated")
        gate.finishDelete()
        await deletion.value

        XCTAssertEqual(deleted.generations, [old, replacement])
        XCTAssertEqual(gate.startCount, 2, "same-generation deletes dedupe")
        let lease = registry.acquire(key)
        XCTAssertNotNil(lease)
        XCTAssertEqual(lease?.generation, replacement)
        registry.release(lease!)
    }

    /// A scan that started before a live replacement must not publish its old
    /// sidecar after the replacement commits.
    func testStaleRescanCannotReplaceReplacementGeneration() async throws {
        let key = "stale-rescan"
        let old = UUID()
        let replacement = UUID()
        let registry = PhysicalUseRegistry(onDelete: { _, _ in })
        registry.beginGeneration(key, generation: replacement) {}

        let staleScan = try registry.beginGenerationIfCurrentOrUnregistered(
            key, generation: old, publish: {
                XCTFail("stale rescan must not publish")
            }
        )

        XCTAssertFalse(staleScan)
        let lease = registry.acquire(key)
        XCTAssertEqual(lease?.generation, replacement)
        registry.release(lease!)
    }

    /// A rescan must not race an executing delete for the same generation:
    /// otherwise it can pool-register an artifact whose files are being removed.
    func testConditionalRescanRejectsExecutingDelete() async throws {
        let key = "rescan-during-delete"
        let generation = UUID()
        let gate = DeleteExecutionGate()
        let registry = PhysicalUseRegistry(onDelete: { _, _ in
            gate.enterDelete()
        })
        registry.beginGeneration(key, generation: generation) {}

        let lease = registry.acquire(key)
        XCTAssertNotNil(lease)
        XCTAssertNil(registry.requestDelete(key, generation: generation))

        let releaser = Task.detached {
            registry.release(lease!)
        }
        try await gate.waitForDeleteStart()

        let rescan = try registry.beginGenerationIfCurrentOrUnregistered(
            key, generation: generation, publish: {
                XCTFail("rescan must not publish during delete execution")
            }
        )

        XCTAssertFalse(rescan)
        gate.finishDelete()
        await releaser.value
    }

    /// A pending delete has already closed admission for its generation.
    /// Rescan must not reintroduce that generation between lease release and
    /// delete-callback execution.
    func testConditionalRescanRejectsPendingDelete() async throws {
        let key = "rescan-pending-delete"
        let generation = UUID()
        let gate = DeleteExecutionGate()
        let registry = PhysicalUseRegistry(onDelete: { _, _ in
            gate.enterDelete()
        })
        registry.beginGeneration(key, generation: generation) {}
        let lease = registry.acquire(key)
        XCTAssertNotNil(lease)
        XCTAssertNil(registry.requestDelete(key, generation: generation))

        let rescan = try registry.beginGenerationIfCurrentOrUnregistered(
            key, generation: generation, publish: {
                XCTFail("pending delete must block rescan publication")
            }
        )

        XCTAssertFalse(rescan)
        XCTAssertEqual(gate.startCount, 0)

        let releaser = Task.detached {
            registry.release(lease!)
        }
        try await gate.waitForDeleteStart()
        gate.finishDelete()
        await releaser.value
    }

    /// A failed delete callback cannot leave admission permanently closed.
    func testFailedDeleteCallbackRestoresAdmission() async throws {
        let key = "failed-delete"
        let registry = PhysicalUseRegistry(onDelete: { _, _ in
            struct DeleteFailure: Error {}
            throw DeleteFailure()
        })

        let failure = registry.requestDelete(key, generation: nil)
        XCTAssertNotNil(failure)
        XCTAssertEqual(registry.physicalUseCount(key), 0)

        let lease = registry.acquire(key)
        XCTAssertNotNil(lease, "callback failure must not permanently close admission")
        registry.release(lease!)
        XCTAssertEqual(registry.takeDeleteFailures(key).count, 1)
    }

    /// A delete request that arrives while a replacement is preparing is not
    /// stale. If publication fails and restores the old generation, that
    /// deferred request must still delete it.
    func testDeleteDuringFailedPublicationSurvivesRollback() async throws {
        let key = "delete-during-failed-publication"
        let old = UUID()
        let replacement = UUID()
        let publicationStarted = DispatchSemaphore(value: 0)
        let releasePublication = DispatchSemaphore(value: 0)
        let deleted = DeletedGenerations()
        let registry = PhysicalUseRegistry(onDelete: { _, generation in
            deleted.record(generation)
        })
        registry.beginGeneration(key, generation: old) {}

        let publication = Task.detached {
            try registry.beginGeneration(key, generation: replacement) {
                publicationStarted.signal()
                _ = releasePublication.wait(timeout: .now() + 5)
                throw RollbackFault()
            }
        }

        guard publicationStarted.wait(timeout: .now() + 5) == .success else {
            releasePublication.signal()
            _ = try? await publication.value
            return XCTFail("replacement publication never reached its gate")
        }

        XCTAssertNil(registry.requestDelete(key, generation: old))
        releasePublication.signal()
        do {
            try await publication.value
            XCTFail("injected publication failure must propagate")
        } catch {}

        XCTAssertEqual(deleted.generations, [old])
        let lease = registry.acquire(key)
        XCTAssertEqual(lease?.generation, old)
        registry.release(lease!)
    }

    /// Store-level sidecar generation validation prevents a stale eviction
    /// request from deleting a replacement at the same path.
    func testStaleGenerationDeleteCannotRemoveReplacementArtifact() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("generation-delete-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let oldEntry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 8), write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let oldArtifact = oldEntry.artifact as! DiskPrefixArtifact
        let newEntry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 8), write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let newArtifact = newEntry.artifact as! DiskPrefixArtifact

        XCTAssertEqual(oldArtifact.snapshotURL.path, newArtifact.snapshotURL.path)
        XCTAssertNotEqual(oldArtifact.generation, newArtifact.generation)

        store.physicalUse.requestDelete(
            newArtifact.snapshotURL.path, generation: oldArtifact.generation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newArtifact.snapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newArtifact.metadataURL.path))

        store.physicalUse.requestDelete(
            newArtifact.snapshotURL.path, generation: newArtifact.generation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newArtifact.snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newArtifact.metadataURL.path))
    }

    func testExplicitRemoveOfStaleEntryCannotAffectReplacement() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("explicit-stale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let oldEntry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 9), write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let newEntry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 9), write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let newArtifact = newEntry.artifact as! DiskPrefixArtifact

        try store.remove(oldEntry)
        let admitted = store.pool.admit(
            namespace: f3ns, promptTokens: f3tokens(256, seed: 9))
        let admittedArtifact = admitted?.entry.artifact as? DiskPrefixArtifact
        XCTAssertEqual(admittedArtifact?.generation, newArtifact.generation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newArtifact.snapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newArtifact.metadataURL.path))

        try store.remove(newEntry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newArtifact.snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newArtifact.metadataURL.path))
        XCTAssertNil(store.pool.admit(namespace: f3ns, promptTokens: f3tokens(256, seed: 9)))
    }

    func testDeleteFailuresAreReportedAndExplicitRetryCanSucceed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        final class DeletionPlan: @unchecked Sendable {
            private let l = NSLock()
            private var stages = ["sidecar", "snapshot", "metadata", "success"]
            var next: String {
                l.lock()
                defer { l.unlock() }
                if stages.isEmpty { return "success" }
                return stages.removeFirst()
            }
        }
        let plan = DeletionPlan()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { key, generation in
                let snapshotURL = URL(fileURLWithPath: key)
                let metadataURL = snapshotURL.deletingPathExtension()
                    .appendingPathExtension("json")
                switch plan.next {
                case "sidecar":
                    throw PrefixSnapshotStoreError.artifactGenerationMismatch(
                        expected: generation, actual: UUID())
                case "snapshot":
                    throw PrefixSnapshotStoreError.artifactDeletionFailed(
                        path: snapshotURL.path, underlyingDescription: "injected")
                case "metadata":
                    try FileManager.default.removeItem(at: snapshotURL)
                    throw PrefixSnapshotStoreError.artifactDeletionFailed(
                        path: metadataURL.path, underlyingDescription: "injected")
                default:
                    if FileManager.default.fileExists(atPath: snapshotURL.path) {
                        try FileManager.default.removeItem(at: snapshotURL)
                    }
                    if FileManager.default.fileExists(atPath: metadataURL.path) {
                        try FileManager.default.removeItem(at: metadataURL)
                    }
                }
            }
        )
        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 10), write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let artifact = entry.artifact as! DiskPrefixArtifact

        store.physicalUse.requestDelete(
            artifact.snapshotURL.path, generation: artifact.generation)
        let firstFailures = store.physicalUse.takeDeleteFailures(artifact.snapshotURL.path)
        guard let failure = storeDeleteFailure(firstFailures),
            case .artifactGenerationMismatch = failure else {
            return XCTFail("expected sidecar-validation failure")
        }
        XCTAssertEqual(firstFailures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))

        store.physicalUse.requestDelete(
            artifact.snapshotURL.path, generation: artifact.generation)
        let secondFailures = store.physicalUse.takeDeleteFailures(artifact.snapshotURL.path)
        guard let failure = storeDeleteFailure(secondFailures),
            case .artifactDeletionFailed(let snapshotPath, _) = failure else {
            return XCTFail("expected snapshot-deletion failure")
        }
        XCTAssertEqual(snapshotPath, artifact.snapshotURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))

        store.physicalUse.requestDelete(
            artifact.snapshotURL.path, generation: artifact.generation)
        let thirdFailures = store.physicalUse.takeDeleteFailures(artifact.snapshotURL.path)
        guard let failure = storeDeleteFailure(thirdFailures),
            case .artifactDeletionFailed(let metadataPath, _) = failure else {
            return XCTFail("expected metadata-deletion failure")
        }
        XCTAssertEqual(metadataPath, artifact.metadataURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))

        var finalFailures: [Error] = []
        for _ in 0..<3 {
            store.physicalUse.requestDelete(
                artifact.snapshotURL.path, generation: artifact.generation)
            finalFailures = store.physicalUse.takeDeleteFailures(artifact.snapshotURL.path)
            if finalFailures.isEmpty,
                !FileManager.default.fileExists(atPath: artifact.metadataURL.path) {
                break
            }
        }
        XCTAssertTrue(finalFailures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.metadataURL.path))
        XCTAssertNotNil(store.physicalUse.acquire(artifact.snapshotURL.path))
    }

    func testRemoveSurfacesImmediateDeleteFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remove-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { key, _ in
                throw PrefixSnapshotStoreError.artifactDeletionFailed(
                    path: key,
                    underlyingDescription: "injected immediate failure")
            }
        )
        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 14),
            write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let artifact = entry.artifact as! DiskPrefixArtifact

        do {
            try store.remove(entry)
            XCTFail("explicit remove must surface an immediate deletion failure")
        } catch let error as PrefixSnapshotStoreError {
            XCTAssertEqual(
                error,
                .artifactDeletionFailed(
                    path: artifact.snapshotURL.path,
                    underlyingDescription: "injected immediate failure"))
        }
        XCTAssertEqual(store.physicalUse.takeDeleteFailures(artifact.snapshotURL.path).count, 1)
        XCTAssertNil(store.pool.admit(namespace: f3ns, promptTokens: f3tokens(256, seed: 14)))
    }

    /// A failed explicit remove leaves the artifact behind for retry. The
    /// pool entry is already gone, so retry must not silently skip deletion.
    func testRemoveRetryAfterFailureDeletesArtifact() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remove-retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let shouldFail = PublicationFault()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { key, _ in
                guard shouldFail.isEnabled else {
                    try FileManager.default.removeItem(atPath: key)
                    let metadataURL = URL(fileURLWithPath: key)
                        .deletingPathExtension()
                        .appendingPathExtension("json")
                    try FileManager.default.removeItem(at: metadataURL)
                    return
                }
                throw PrefixSnapshotStoreError.artifactDeletionFailed(
                    path: key,
                    underlyingDescription: "injected remove failure")
            }
        )
        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 22),
            write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let artifact = entry.artifact as! DiskPrefixArtifact

        shouldFail.enable()
        do {
            try store.remove(entry)
            XCTFail("first remove must surface the injected failure")
        } catch {}

        XCTAssertEqual(store.physicalUse.takeDeleteFailures(
            artifact.snapshotURL.path).count, 1)
        XCTAssertNil(store.pool.admit(
            namespace: f3ns, promptTokens: f3tokens(256, seed: 22)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.metadataURL.path))

        shouldFail.disable()
        try store.remove(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.metadataURL.path))
        XCTAssertTrue(store.physicalUse.takeDeleteFailures(
            artifact.snapshotURL.path).isEmpty)
    }

    func testRemoveDoesNotSurfaceStaleDeleteFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remove-stale-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        final class DeletionPlan: @unchecked Sendable {
            private let l = NSLock()
            private var failFirst = true
            var next: Error? {
                l.lock()
                defer { l.unlock() }
                if failFirst {
                    failFirst = false
                    return PrefixSnapshotStoreError.artifactDeletionFailed(
                        path: "injected", underlyingDescription: "stale")
                }
                return nil
            }
        }
        let plan = DeletionPlan()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { key, _ in
                if let failure = plan.next { throw failure }
            }
        )
        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 15),
            write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let artifact = entry.artifact as! DiskPrefixArtifact

        store.physicalUse.requestDelete(
            artifact.snapshotURL.path, generation: artifact.generation)
        XCTAssertEqual(store.physicalUse.takeDeleteFailures(artifact.snapshotURL.path).count, 1)

        try store.remove(entry)
        XCTAssertTrue(store.physicalUse.takeDeleteFailures(artifact.snapshotURL.path).isEmpty)
        XCTAssertNil(store.pool.admit(namespace: f3ns, promptTokens: f3tokens(256, seed: 15)))
    }

    /// Successful deletion is idempotent: a repeated explicit remove of the
    /// same generation must not turn a missing artifact into a new failure.
    func testRepeatedSuccessfulRemoveIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remove-idempotent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 23),
            write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let artifact = entry.artifact as! DiskPrefixArtifact

        try store.remove(entry)
        try store.remove(entry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.metadataURL.path))
        XCTAssertNil(store.pool.admit(
            namespace: f3ns, promptTokens: f3tokens(256, seed: 23)))
        XCTAssertTrue(store.physicalUse.takeDeleteFailures(
            artifact.snapshotURL.path).isEmpty)
    }

    /// Pool budget accounting must use the published artifact's byte count,
    /// not race the I/O lock and stat a snapshot during replacement/removal.
    func testArtifactByteCountRemainsStableAfterDiskMutation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-bytes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(256, seed: 24),
            write: { url in
                try Data(repeating: 97, count: 1_234).write(to: url)
            }
        )
        let artifact = entry.artifact as! DiskPrefixArtifact
        let publishedByteCount = try XCTUnwrap(artifact.physicalByteCount)

        try Data("x".utf8).write(to: artifact.snapshotURL)
        try FileManager.default.removeItem(at: artifact.metadataURL)

        XCTAssertEqual(artifact.physicalByteCount, publishedByteCount)
        XCTAssertEqual(store.pool.totalPhysicalBytes, publishedByteCount)
    }

    /// Byte count is accounting metadata, not artifact identity. Exact pool
    /// removal must still match after a legacy and published handle disagree
    /// about how the size was obtained.
    func testDiskArtifactEqualityIgnoresByteCount() {
        let snapshotURL = URL(fileURLWithPath: "/tmp/feature.safetensors")
        let metadataURL = URL(fileURLWithPath: "/tmp/feature.json")
        let generation = UUID()
        let dynamic = DiskPrefixArtifact(
            snapshotURL: snapshotURL, metadataURL: metadataURL, generation: generation)
        let published = DiskPrefixArtifact(
            snapshotURL: snapshotURL, metadataURL: metadataURL,
            generation: generation, publishedPhysicalByteCount: 1_234)

        XCTAssertEqual(dynamic, published)
        XCTAssertNotEqual(
            dynamic,
            DiskPrefixArtifact(
                snapshotURL: snapshotURL, metadataURL: metadataURL, generation: UUID())
        )
    }

    /// Unknown legacy artifact sizes must stay unknown. Reporting missing
    /// files as zero would let the byte budget treat them as free.
    func testLegacyArtifactByteCountIsNilWhenDiskStateUnknown() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-byte-count-\(UUID().uuidString)")
        let snapshotURL = root.appendingPathComponent("artifact.safetensors")
        let metadataURL = root.appendingPathComponent("artifact.json")
        let artifact = DiskPrefixArtifact(
            snapshotURL: snapshotURL, metadataURL: metadataURL, generation: nil)

        XCTAssertNil(artifact.physicalByteCount)

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? Data("snapshot".utf8).write(to: snapshotURL)
        XCTAssertNil(artifact.physicalByteCount, "missing sidecar has unknown size")

        try? Data("sidecar".utf8).write(to: metadataURL)
        XCTAssertEqual(artifact.physicalByteCount, 15)
    }

    func testDeleteRequestDuringLeaseClosesAdmissionUntilRelease() async throws {
        let key = "delete-during-lease"
        let registry = PhysicalUseRegistry(onDelete: { _, _ in })
        let lease = registry.acquire(key)
        XCTAssertNotNil(lease)

        XCTAssertNil(registry.requestDelete(key, generation: nil))
        XCTAssertNil(registry.acquire(key), "pending delete must close admission")

        registry.release(lease!)
        let restored = registry.acquire(key)
        XCTAssertNotNil(restored, "successful deferred delete must restore admission")
        registry.release(restored!)
    }

    func testDeferredDeleteFailureIsRecordedAndRestoresAdmission() async throws {
        let key = "deferred-delete-failure"
        struct InjectedDeferredFailure: Error {}
        let registry = PhysicalUseRegistry(onDelete: { _, _ in
            throw InjectedDeferredFailure()
        })
        let lease = registry.acquire(key)
        XCTAssertNotNil(lease)
        XCTAssertNil(registry.requestDelete(key, generation: nil))

        let releaser = Task.detached {
            registry.release(lease!)
        }
        await releaser.value

        let failures = registry.takeDeleteFailures(key)
        XCTAssertTrue(failures.first is InjectedDeferredFailure)
        XCTAssertEqual(registry.physicalUseCount(key), 0)
        let restored = registry.acquire(key)
        XCTAssertNotNil(restored, "failed deferred delete must restore admission")
        registry.release(restored!)
    }

    func testReplacementWaitsForExistingLeaseBeforePublishing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("replacement-lease-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let tokens = f3tokens(256, seed: 16)
        let oldEntry = try await store.export(namespace: f3ns, tokens: tokens) { url in
            try "old".write(to: url, atomically: true, encoding: .utf8)
        }
        let oldArtifact = oldEntry.artifact as! DiskPrefixArtifact
        let oldLease = store.physicalUse.acquire(oldArtifact.snapshotURL.path)
        XCTAssertNotNil(oldLease)

        let replacement = Task.detached {
            try await store.export(namespace: f3ns, tokens: tokens) { url in
                try "new".write(to: url, atomically: true, encoding: .utf8)
            }
        }
        try await waitForMaterializationPreparation(
            store.physicalUse, key: oldArtifact.snapshotURL.path)

        XCTAssertEqual(
            try String(contentsOf: oldArtifact.snapshotURL, encoding: .utf8), "old")
        XCTAssertNil(store.physicalUse.acquire(oldArtifact.snapshotURL.path))

        store.physicalUse.release(oldLease!)
        let replacementEntry = try await replacement.value
        XCTAssertEqual(
            try String(contentsOf: oldArtifact.snapshotURL, encoding: .utf8), "new")
        let newLease = store.physicalUse.acquire(oldArtifact.snapshotURL.path)
        let replacementArtifact = replacementEntry.artifact as! DiskPrefixArtifact
        XCTAssertEqual(newLease?.generation, replacementArtifact.generation)
        XCTAssertNotEqual(newLease?.generation, oldArtifact.generation)
        store.physicalUse.release(newLease!)
    }

    func testLoadRejectsStaleAdmissionAfterReplacement() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-load-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let tokens = f3tokens(256, seed: 17)
        let oldEntry = try await store.export(namespace: f3ns, tokens: tokens) { url in
            try "old".write(to: url, atomically: true, encoding: .utf8)
        }
        let oldAdmission = store.pool.admit(namespace: f3ns, promptTokens: tokens)
        let newEntry = try await store.export(namespace: f3ns, tokens: tokens) { url in
            try "new".write(to: url, atomically: true, encoding: .utf8)
        }
        let oldArtifact = oldEntry.artifact as! DiskPrefixArtifact
        let newArtifact = newEntry.artifact as! DiskPrefixArtifact
        XCTAssertNotEqual(oldArtifact.generation, newArtifact.generation)

        do {
            _ = try await store.load(oldAdmission!)
            XCTFail("stale admission must not load replacement generation")
        } catch let error as PrefixSnapshotStoreError {
            XCTAssertEqual(
                error,
                .artifactGenerationMismatch(
                    expected: oldArtifact.generation,
                    actual: newArtifact.generation))
        }
        let tokensForAdmission = tokens + [1_000_003]
        XCTAssertNotNil(store.pool.admit(
            namespace: f3ns, promptTokens: tokensForAdmission))
    }

    /// Load self-healing must also retire the failed artifact; otherwise a
    /// restart rescan repeatedly resurrects an unreadable representation.
    func testLoadFailureRetiresUnreadableArtifactFromRescan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("load-retire-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let tokens = f3tokens(256, seed: 19)
        let entry = try await store.export(namespace: f3ns, tokens: tokens) { url in
            try "not-a-safetensors-payload".write(
                to: url, atomically: true, encoding: .utf8)
        }
        let artifact = entry.artifact as! DiskPrefixArtifact

        XCTAssertEqual(try store.rescan(), 1)
        let admission = try XCTUnwrap(
            store.pool.admit(namespace: f3ns, promptTokens: tokens))
        do {
            _ = try await store.load(admission)
            XCTFail("invalid snapshot must fail loudly")
        } catch {}

        XCTAssertNil(store.pool.admit(namespace: f3ns, promptTokens: tokens))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.metadataURL.path))
        XCTAssertEqual(
            try store.rescan(), 0, "a failed load must not be resurrected")
        XCTAssertTrue(store.physicalUse.takeDeleteFailures(
            artifact.snapshotURL.path).isEmpty)
    }

    /// Direct artifact reads are physical operations: the store must expose
    /// them through the same transient lease boundary as export/delete.
    func testLoadHoldsPhysicalUseLeaseDuringArtifactRead() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("load-lease-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let artifactIOLock = NSLock()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: artifactIOLock,
            deleteArtifact: { _, _ in }
        )
        let tokens = f3tokens(256, seed: 20)
        let entry = try await store.export(
            namespace: f3ns, tokens: tokens, write: f3writeSynthetic)
        let artifact = entry.artifact as! DiskPrefixArtifact
        let admission = try XCTUnwrap(
            store.pool.admit(namespace: f3ns, promptTokens: tokens))

        artifactIOLock.lock()
        let load = Task { try await store.load(admission) }
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while store.physicalUse.physicalUseCount(artifact.snapshotURL.path) < 1 {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                artifactIOLock.unlock()
                _ = try? await load.value
                return XCTFail("load must acquire a physical-use lease before I/O")
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(store.physicalUse.physicalUseCount(
            artifact.snapshotURL.path), 1)
        artifactIOLock.unlock()
        _ = try await load.value
        XCTAssertEqual(store.physicalUse.physicalUseCount(
            artifact.snapshotURL.path), 0)
    }

    /// Lease rejection is transient unavailability, not artifact corruption:
    /// it must not trigger self-healing removal of a healthy pool entry.
    func testLoadLeaseRejectionDoesNotRetireHealthyArtifact() async throws {
        let key = "load-lease-rejection"
        let gate = DeleteExecutionGate()
        let store = PrefixSnapshotStore(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("load-reject-\(UUID().uuidString)"),
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { _, _ in gate.enterDelete() }
        )
        defer { gate.finishDelete() }
        let tokens = f3tokens(256, seed: 21)
        let entry = try await store.export(namespace: f3ns, tokens: tokens) { url in
            try "payload".write(to: url, atomically: true, encoding: .utf8)
        }
        let artifact = entry.artifact as! DiskPrefixArtifact
        let admission = try XCTUnwrap(
            store.pool.admit(namespace: f3ns, promptTokens: tokens))

        let deletion = Task.detached {
            _ = store.physicalUse.requestDelete(
                artifact.snapshotURL.path, generation: artifact.generation)
        }
        try await gate.waitForDeleteStart()
        do {
            _ = try await store.load(admission)
            XCTFail("load during delete execution must fail closed")
        } catch let error as PrefixSnapshotStoreError {
            XCTAssertEqual(
                error, .physicalUseUnavailable(path: artifact.snapshotURL.path))
        }
        XCTAssertEqual(store.physicalUse.physicalUseCount(
            artifact.snapshotURL.path), 0)
        gate.finishDelete()
        await deletion.value
        XCTAssertNotNil(store.pool.admit(namespace: f3ns, promptTokens: tokens))
    }

    /// Disk publication and pool generation switch are one admission epoch:
    /// an old entry can still be admitted while the replacement is being
    /// committed, but physical use remains closed until the pool switches.
    func testPoolCommitStaysInsideGenerationPublication() async throws {
        final class CommitGate: @unchecked Sendable {
            private let lock = NSLock()
            private let entered = DispatchSemaphore(value: 0)
            private let leave = DispatchSemaphore(value: 0)
            private var enabled = false

            func enable() {
                lock.lock()
                enabled = true
                lock.unlock()
            }

            func enterIfEnabled() {
                lock.lock()
                let shouldEnter = enabled
                lock.unlock()
                guard shouldEnter else { return }
                entered.signal()
                _ = leave.wait(timeout: .now() + 5)
            }

            func waitForEnter() -> Bool {
                entered.wait(timeout: .now() + 5) == .success
            }

            func release() { leave.signal() }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pool-commit-window-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let commitGate = CommitGate()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { _, _ in },
            willCommitPoolEntry: { commitGate.enterIfEnabled() }
        )
        let tokens = f3tokens(256, seed: 18)
        let oldEntry = try await store.export(namespace: f3ns, tokens: tokens) { url in
            try "old".write(to: url, atomically: true, encoding: .utf8)
        }
        let oldArtifact = oldEntry.artifact as! DiskPrefixArtifact

        commitGate.enable()
        let replacement = Task {
            try await store.export(namespace: f3ns, tokens: tokens) { url in
                try "new".write(to: url, atomically: true, encoding: .utf8)
            }
        }

        guard commitGate.waitForEnter() else {
            commitGate.release()
            _ = try await replacement.value
            return XCTFail("replacement never reached its pool commit window")
        }

        XCTAssertTrue(
            store.physicalUse.isPreparingGeneration(oldArtifact.snapshotURL.path))
        XCTAssertNil(store.physicalUse.acquire(oldArtifact.snapshotURL.path))
        XCTAssertNotNil(store.pool.admit(namespace: f3ns, promptTokens: tokens))
        commitGate.release()

        let newEntry = try await replacement.value
        let newArtifact = newEntry.artifact as! DiskPrefixArtifact
        XCTAssertNotEqual(oldArtifact.generation, newArtifact.generation)
        let lease = store.physicalUse.acquire(newArtifact.snapshotURL.path)
        XCTAssertEqual(lease?.generation, newArtifact.generation)
        store.physicalUse.release(lease!)
    }

    func testConcurrentSamePathExportsKeepRegistryAndDiskBound() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("concurrent-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        let tokens = f3tokens(256, seed: 11)
        let gateA = MaterializationWorkGate()
        let gateB = MaterializationWorkGate()

        let taskA = Task {
            try await store.export(namespace: f3ns, tokens: tokens) { url in
                await gateA.enterWork()
                try "A".write(to: url, atomically: true, encoding: .utf8)
            }
        }
        try await gateA.waitForFirstCall()
        let taskB = Task {
            try await store.export(namespace: f3ns, tokens: tokens) { url in
                await gateB.enterWork()
                try "B".write(to: url, atomically: true, encoding: .utf8)
            }
        }
        try await gateB.waitForFirstCall()

        await gateB.release()
        _ = try await taskB.get()
        await gateA.release()
        let finalEntry = try await taskA.get()
        let finalArtifact = finalEntry.artifact as! DiskPrefixArtifact

        let snapshotData = try Data(contentsOf: finalArtifact.snapshotURL)
        XCTAssertEqual(String(data: snapshotData, encoding: .utf8), "A")
        let sidecarData = try Data(contentsOf: finalArtifact.metadataURL)
        let sidecar = try JSONDecoder().decode(PrefixSnapshotSidecar.self, from: sidecarData)
        XCTAssertEqual(sidecar.generation, finalArtifact.generation)
        let lease = store.physicalUse.acquire(finalArtifact.snapshotURL.path)
        XCTAssertEqual(lease?.generation, finalArtifact.generation)
        store.physicalUse.release(lease!)
    }

    func testSidecarPublishFailureRestoresOldSnapshotPair() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("publish-rollback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let publishFault = PublicationFault()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { _, _ in },
            willPublishSidecar: { metadataURL in
                guard publishFault.isEnabled else { return }
                try FileManager.default.createDirectory(
                    at: metadataURL, withIntermediateDirectories: true)
                try Data("blocked".utf8).write(
                    to: metadataURL.appendingPathComponent("blocked"))
            }
        )
        let tokens = f3tokens(256, seed: 12)
        let oldEntry: PrefixPoolEntry
        do {
            oldEntry = try await store.export(namespace: f3ns, tokens: tokens) { url in
                try "old".write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            XCTFail("old export failed: \(error)")
            throw error
        }
        publishFault.enable()
        let oldArtifact = oldEntry.artifact as! DiskPrefixArtifact

        do {
            _ = try await store.export(namespace: f3ns, tokens: tokens) { url in
                try "new".write(to: url, atomically: true, encoding: .utf8)
            }
            XCTFail("sidecar publication failure must propagate")
        } catch {}

        XCTAssertTrue(FileManager.default.fileExists(atPath: oldArtifact.snapshotURL.path))
        let sidecarData = try Data(contentsOf: oldArtifact.metadataURL)
        let sidecar = try JSONDecoder().decode(PrefixSnapshotSidecar.self, from: sidecarData)
        XCTAssertEqual(sidecar.generation, oldArtifact.generation)
        XCTAssertEqual(try String(contentsOf: oldArtifact.snapshotURL, encoding: .utf8), "old")
        let lease = store.physicalUse.acquire(oldArtifact.snapshotURL.path)
        XCTAssertEqual(lease?.generation ?? nil, oldArtifact.generation)
        store.physicalUse.release(lease!)
        XCTAssertTrue(store.physicalUse.takePublicationFailures(
            oldArtifact.snapshotURL.path).isEmpty)
    }

    func testRollbackFailureQuarantinesGenerationAndBlocksLaterUse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("publish-rollback-failure-\(UUID().uuidString)")
        let publishFault = PublicationFault()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { _, _ in },
            willPublishSidecar: { metadataURL in
                guard publishFault.isEnabled else { return }
                // Replace the destination with a directory so sidecar publish
                // fails after the new snapshot has moved into place.
                try FileManager.default.createDirectory(
                    at: metadataURL, withIntermediateDirectories: true)
                try Data("blocked".utf8).write(
                    to: metadataURL.appendingPathComponent("blocked"))
            },
            willRollback: {
                throw RollbackFault()
            }
        )
        let tokens = f3tokens(256, seed: 13)
        let oldEntry = try await store.export(namespace: f3ns, tokens: tokens) { url in
            try "old".write(to: url, atomically: true, encoding: .utf8)
        }
        publishFault.enable()
        let oldArtifact = oldEntry.artifact as! DiskPrefixArtifact
        let namespaceDirectory = oldArtifact.snapshotURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: namespaceDirectory.path)
        }

        enum ExportOutcome {
            case success
            case failure(Error)
        }
        let outcome: ExportOutcome = await withCheckedContinuation { continuation in
            Task.detached {
                do {
                    _ = try await store.export(namespace: f3ns, tokens: tokens) { url in
                        try "new".write(to: url, atomically: true, encoding: .utf8)
                    }
                    continuation.resume(returning: .success)
                } catch {

                    continuation.resume(returning: .failure(error))
                }
            }
        }
        guard case .failure(let exportError) = outcome else {
            XCTFail("rollback failure must propagate as publication quarantine")
            return
        }
        XCTAssertNotNil(exportError)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: namespaceDirectory.path)

        let key = oldArtifact.snapshotURL.path
        XCTAssertTrue(store.physicalUse.isGenerationInvalidated(key))
        let failures = store.physicalUse.takePublicationFailures(key)
        guard failures.first is PhysicalUseRegistry.PublicationQuarantinedError else {
            return XCTFail("expected quarantined-publication failure")
        }
        XCTAssertEqual(failures.count, 1, "one rollback failure must produce one quarantine record")
        XCTAssertTrue(store.physicalUse.takePublicationFailures(key).isEmpty)
        XCTAssertNil(store.physicalUse.acquire(key))
        XCTAssertNil(store.physicalUse.acquire(key))

        let entries = try FileManager.default.contentsOfDirectory(
            at: namespaceDirectory, includingPropertiesForKeys: nil)
        let backupSnapshot = entries.first {
            $0.lastPathComponent.hasPrefix(".backup-") &&
                $0.pathExtension == "safetensors"
        }
        let backupMetadata = entries.first {
            $0.lastPathComponent.hasPrefix(".backup-") &&
                $0.pathExtension == "metadata"
        }
        let quarantine = entries.first {
            $0.lastPathComponent.hasPrefix(".quarantine-")
        }
        XCTAssertNotNil(backupSnapshot)
        XCTAssertNotNil(backupMetadata)
        XCTAssertNil(quarantine, "rollback must fail before quarantining either file")
        XCTAssertEqual(
            try String(contentsOf: backupSnapshot!, encoding: .utf8), "old")
        let backupSidecar = try JSONDecoder().decode(
            PrefixSnapshotSidecar.self,
            from: Data(contentsOf: backupMetadata!))
        XCTAssertEqual(backupSidecar.generation, oldArtifact.generation)

        XCTAssertEqual(
            try String(contentsOf: oldArtifact.snapshotURL, encoding: .utf8), "new")
        let finalMetadataAttributes = try FileManager.default.attributesOfItem(
            atPath: oldArtifact.metadataURL.path)
        XCTAssertEqual(
            finalMetadataAttributes[.type] as? FileAttributeType, .typeDirectory)

        let admission = store.pool.admit(namespace: f3ns, promptTokens: tokens)
        XCTAssertNotNil(admission)
        XCTAssertTrue(store.physicalUse.isGenerationInvalidated(key))
        XCTAssertNil(store.physicalUse.acquire(key))

        let quarantined = try store.quarantinedArtifacts()
        XCTAssertEqual(quarantined.map(\.artifactPath), [key])
        XCTAssertNotNil(quarantined.first?.generation)

        let fresh = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        XCTAssertEqual(try fresh.rescan(), 0, "durable quarantine must survive restart")
        XCTAssertEqual(try fresh.quarantinedArtifacts().count, 1)

        try fresh.clearQuarantine(forArtifactAt: key)
        XCTAssertTrue(try fresh.quarantinedArtifacts().isEmpty)

        // Explicit dismissal clears the durable tombstone; a real repair also
        // restores the backup pair that rollback failed to reinstall.
        try FileManager.default.removeItem(at: oldArtifact.metadataURL)
        try FileManager.default.removeItem(at: oldArtifact.snapshotURL)
        try FileManager.default.moveItem(
            at: backupMetadata!, to: oldArtifact.metadataURL)
        try FileManager.default.moveItem(
            at: backupSnapshot!, to: oldArtifact.snapshotURL)

        XCTAssertEqual(try fresh.rescan(), 1, "explicit dismissal allows recovery")
        XCTAssertNotNil(fresh.pool.admit(namespace: f3ns, promptTokens: tokens))
    }

    /// A failed first publication must not leave an unregistered candidate
    /// at the formal path where restart rescan can resurrect it.
    func testFreshPublishFailureQuarantinesUnregisteredArtifact() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("publish-fresh-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let publishFault = PublicationFault()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            artifactIOLock: NSLock(),
            deleteArtifact: { _, _ in },
            willPublishSidecar: { metadataURL in
                guard publishFault.isEnabled else { return }
                try FileManager.default.createDirectory(
                    at: metadataURL, withIntermediateDirectories: true)
            }
        )
        let tokens = f3tokens(256, seed: 14)
        publishFault.enable()

        do {
            _ = try await store.export(namespace: f3ns, tokens: tokens) { url in
                try "new".write(to: url, atomically: true, encoding: .utf8)
            }
            XCTFail("sidecar publication failure must propagate")
        } catch {}

        XCTAssertEqual(try store.rescan(), 0)
        let namespaceDirectory = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey]
            ).first { $0.hasDirectoryPath })
        let quarantines = try FileManager.default.contentsOfDirectory(
            at: namespaceDirectory, includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".quarantine-") }
        XCTAssertEqual(quarantines.count, 2)
        XCTAssertTrue(quarantines.contains {
            (try? String(contentsOf: $0, encoding: .utf8)) == "new"
        })
    }

    /// Coordinator maps a rejected startup lease to a thrown result without
    /// publishing or starting a work task.
    func testMaterializeRejectsWorkDuringDeleteExecution() async throws {
        let key = "materialize-vs-delete"
        let gate = DeleteExecutionGate()
        let workCounter = MaterializationWorkCounter()
        let registry = PhysicalUseRegistry(onDelete: { _, _ in
            gate.enterDelete()
        })
        let coordinator = MaterializationCoordinator<String>(physicalUse: registry)
        coordinator.setLeaseRejectionObserver { key in
            gate.rejectAdmission()
        }

        let deletion = Task.detached {
            registry.requestDelete(key, generation: nil)
        }
        try await gate.waitForDeleteStart()

        let denied = Task.detached {
            try await coordinator.materialize(key: key) {
                workCounter.record()
                return "stale"
            }
        }
        try await gate.waitForRejection()
        XCTAssertNil(registry.acquire(key))

        gate.finishDelete()
        await deletion.value
        do {
            _ = try await denied.value
            XCTFail("materialization must be rejected while delete is executing")
        } catch let error as MaterializationCoordinatorError {
            XCTAssertEqual(error, .physicalUseUnavailable(key))
        }
        XCTAssertEqual(workCounter.count, 0, "rejected startup must not run work")
        XCTAssertFalse(coordinator.isInFlight(key), "rejected startup must not publish work")

        let value = try await coordinator.materialize(key: key) {
            workCounter.record()
            return "fresh"
        }
        XCTAssertEqual(value, "fresh")
        XCTAssertEqual(workCounter.count, 1)
        XCTAssertEqual(registry.physicalUseCount(key), 0)
    }

    // MARK: - D-I4 startup window (lease acquired before task publication)

    /// Deterministic startup-window regression: the physical-use lease is
    /// held (count == 1) at the moment the single-flight task is published —
    /// BEFORE any work runs — so an eviction-side requestDelete in that
    /// window is DEFERRED, the artifact survives, and the deferred deletion
    /// fires only after the work releases the lease.
    func testStartupWindowLeaseHeldBeforeWorkStartsAndDeferredDeleteHonored() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("f3-di4-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = ExecutionStatePrefixPool(tokenBudget: 600)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        let coordinator = MaterializationCoordinator<String>(physicalUse: store.physicalUse)

        let entry = try await store.export(
            namespace: f3ns, tokens: f3tokens(512, seed: 1), write: { try "payload".write(to: $0, atomically: true, encoding: .utf8) })
        let artifact = entry.artifact as! DiskPrefixArtifact
        let artifactPath = artifact.snapshotURL.path

        final class StartupObservation: @unchecked Sendable {
            private let l = NSLock()
            private(set) var observed = false
            private(set) var countAtObservation: Int = -1
            private(set) var artifactExisted = false
            private(set) var deferredRequested = false
            func observe(count: Int, artifactExisted: Bool, requestDeferredDelete: () -> Void) {
                l.lock()
                observed = true
                countAtObservation = count
                self.artifactExisted = artifactExisted
                l.unlock()
                if count > 0 {
                    requestDeferredDelete()
                    l.lock()
                    deferredRequested = true
                    l.unlock()
                }
            }
        }
        let observation = StartupObservation()
        coordinator.setStartupObserver { key in
            let count = store.physicalUse.physicalUseCount(key)
            let existed = FileManager.default.fileExists(atPath: key)
            // Deterministic startup-window interleave: while the lease is
            // already held but the work has not started, eviction requests
            // deletion — the registry must defer (artifact untouched).
            observation.observe(
                count: count, artifactExisted: existed,
                requestDeferredDelete: {
                    store.physicalUse.requestDelete(key, generation: artifact.generation)
                })
        }

        let value = try await coordinator.materialize(key: artifactPath) { "done" }
        XCTAssertEqual(value, "done")

        // Startup-window observations: lease held BEFORE work started.
        XCTAssertTrue(observation.observed, "startup seam must fire")
        XCTAssertEqual(observation.countAtObservation, 1,
                       "physical-use count must already be 1 before the work starts")
        XCTAssertTrue(observation.artifactExisted,
                      "artifact must survive a delete request in the startup window")
        XCTAssertTrue(observation.deferredRequested,
                      "the delete request must have been deferred, not dropped")

        // Work ended → release → the deferred deletion fires.
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactPath),
                       "deferred delete must fire after the work releases the lease")
        XCTAssertEqual(store.physicalUse.physicalUseCount(artifactPath), 0)
    }

    /// Failure path: the lease is released even when the work throws, so a
    /// deferred delete fires and no physical-use count leaks.
    func testStartupWindowLeaseReleasedOnWorkFailure() async throws {
        let registry = PhysicalUseRegistry(onDelete: { _, _ in })
        let coordinator = MaterializationCoordinator<String>(physicalUse: registry)

        final class Observation: @unchecked Sendable {
            private let l = NSLock()
            private(set) var countAtObservation: Int = -1
            func observe(count: Int) { l.lock(); countAtObservation = count; l.unlock() }
        }
        let observation = Observation()
        coordinator.setStartupObserver { key in
            observation.observe(count: registry.physicalUseCount(key))
        }

        struct WorkFailure: Error {}
        do {
            _ = try await coordinator.materialize(key: "ref-fail") { throw WorkFailure() }
            XCTFail("work failure must propagate")
        } catch {}

        XCTAssertEqual(observation.countAtObservation, 1,
                       "lease held before the failing work started")
        XCTAssertEqual(registry.physicalUseCount("ref-fail"), 0,
                       "lease must be released on the work-failure path")
    }

    /// Startup-window join semantics: a second caller for the same key joins
    /// the already-protected work — the lease is neither double-acquired nor
    /// released early, and both callers share the single result.
    func testStartupWindowJoinSharesProtectedWork() async throws {
        let registry = PhysicalUseRegistry(onDelete: { _, _ in })
        let coordinator = MaterializationCoordinator<String>(physicalUse: registry)
        let workGate = MaterializationWorkGate()

        let startup = ObservationCounter()
        coordinator.setStartupObserver { key in
            startup.observe(count: registry.physicalUseCount(key))
        }

        async let v1: String = coordinator.materialize(key: "ref-join") {
            await workGate.enterWork()
            return "shared"
        }
        async let v2: String = coordinator.materialize(key: "ref-join") {
            await workGate.enterWork()
            return "shared"
        }
        try await workGate.waitForFirstCall()
        let joined = await workGate.callCount
        XCTAssertEqual(joined, 1, "single-flight: one work")
        await workGate.release()
        let results = try await [v1, v2]
        XCTAssertEqual(results, ["shared", "shared"])
        XCTAssertEqual(startup.maxCountAtObservation, 1,
                       "the lease is acquired exactly once, before publication")
        XCTAssertEqual(registry.physicalUseCount("ref-join"), 0)
    }

    /// The startup observer must run after the lease/task are published but
    /// before user work can start; otherwise the "startup window" depends on
    /// scheduler luck.
    func testStartupObserverRunsBeforeWorkStarts() async throws {
        final class StartupPhases: @unchecked Sendable {
            private let l = NSLock()
            private var observerEnteredValue = false
            private var workStartedValue = false
            private let observerEnteredSemaphore = DispatchSemaphore(value: 0)
            private let releaseObserverSemaphore = DispatchSemaphore(value: 0)

            func markObserverEnteredAndWait() {
                l.lock()
                observerEnteredValue = true
                l.unlock()
                observerEnteredSemaphore.signal()
                _ = releaseObserverSemaphore.wait(timeout: .now() + 5)
            }

            func markWorkStarted() {
                l.lock()
                workStartedValue = true
                l.unlock()
            }

            var observerEntered: Bool {
                l.lock(); defer { l.unlock() }
                return observerEnteredValue
            }

            var workStarted: Bool {
                l.lock(); defer { l.unlock() }
                return workStartedValue
            }

            func waitForObserverEntered() -> Bool {
                observerEnteredSemaphore.wait(timeout: .now() + 5) == .success
            }

            func releaseObserver() { releaseObserverSemaphore.signal() }
        }

        let phases = StartupPhases()
        let registry = PhysicalUseRegistry(onDelete: { _, _ in })
        let coordinator = MaterializationCoordinator<String>(physicalUse: registry)
        coordinator.setStartupObserver { _ in
            phases.markObserverEnteredAndWait()
        }

        let materialization = Task.detached {
            try await coordinator.materialize(key: "startup-order") {
                phases.markWorkStarted()
                return "done"
            }
        }

        guard phases.waitForObserverEntered() else {
            phases.releaseObserver()
            _ = try? await materialization.value
            return XCTFail("startup observer never ran")
        }

        XCTAssertFalse(phases.workStarted, "work must wait for startup publication")
        phases.releaseObserver()
        let value = try await materialization.value
        XCTAssertEqual(value, "done")
        XCTAssertTrue(phases.workStarted)
    }
}

/// Counting observation sink for the D-I4 startup seam.
final class ObservationCounter: @unchecked Sendable {
    private let l = NSLock()
    private var values: [Int] = []
    func observe(count: Int) { l.lock(); values.append(count); l.unlock() }
    var maxCountAtObservation: Int { l.lock(); defer { l.unlock() }; return values.max() ?? -1 }
}

/// Deterministic boundary around the registry's out-of-lock delete callback.
private final class DeleteExecutionGate: @unchecked Sendable {
    private let l = NSLock()
    private var startCountValue = 0
    private var rejected = false
    private let finish = DispatchSemaphore(value: 0)

    func enterDelete() {
        l.lock()
        startCountValue += 1
        l.unlock()
        finish.wait()
    }

    func waitForDeleteStart(
        minimumStartCount: Int = 1,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while currentStartCount < minimumStartCount {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw MaterializationProbeError.timedOutWaitingForFirstWorkCall
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func finishDelete() {
        finish.signal()
    }

    var startCount: Int { currentStartCount }

    func rejectAdmission() {
        l.lock()
        rejected = true
        l.unlock()
    }

    func waitForRejection(timeoutNanoseconds: UInt64 = 5_000_000_000) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !isRejected {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw MaterializationProbeError.timedOutWaitingForFirstWorkCall
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private var isRejected: Bool {
        l.lock()
        defer { l.unlock() }
        return rejected
    }

    private var currentStartCount: Int {
        l.lock()
        defer { l.unlock() }
        return startCountValue
    }
}

private final class DeletedGenerations: @unchecked Sendable {
    private let l = NSLock()
    private var values: [UUID?] = []
    func record(_ generation: UUID?) {
        l.lock()
        values.append(generation)
        l.unlock()
    }
    var generations: [UUID?] {
        l.lock()
        defer { l.unlock() }
        return values
    }
}

private final class MaterializationWorkCounter: @unchecked Sendable {
    private let l = NSLock()
    private(set) var count = 0

    func record() {
        l.lock()
        count += 1
        l.unlock()
    }
}

private struct RollbackFault: Error {}

private final class PublicationFault: @unchecked Sendable {
    private let l = NSLock()
    private var enabled = false
    func enable() { l.lock(); enabled = true; l.unlock() }
    func disable() { l.lock(); enabled = false; l.unlock() }
    var isEnabled: Bool { l.lock(); defer { l.unlock() }; return enabled }
}
