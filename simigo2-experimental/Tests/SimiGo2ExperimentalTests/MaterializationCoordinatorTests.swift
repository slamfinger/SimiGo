import XCTest
import MLXLMCommon
import MLX
import Foundation
@testable import SimiGo2Experimental

private let f3ns = PrefixPoolNamespace(modelID: "qwen3-8b", kvFingerprint: "fp-mlc4")

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
    private var observationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0
    private var released = false

    func enterWork() async {
        callCount += 1
        let observers = observationWaiters
        observationWaiters.removeAll()
        observers.forEach { $0.resume() }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if released {
                continuation.resume()
            } else {
                callContinuations.append(continuation)
            }
        }
    }

    func waitForFirstCall() async {
        if callCount > 0 { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            observationWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let ready = callContinuations
        callContinuations.removeAll()
        ready.forEach { $0.resume() }
        observationWaiters.forEach { $0.resume() }
        observationWaiters.removeAll()
    }
}

private func f3tokens(_ count: Int, seed: Int = 0) -> [Int] {
    (0..<count).map { ($0 * 31 + seed * 7) % 50_000 + 3 }
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
            namespace: f3ns, tokens: f3tokens(512, seed: 1), write: f3writeSynthetic(to:))
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
                namespace: f3ns, tokens: seed2, write: f3writeSynthetic(to:))
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
        let registry = PhysicalUseRegistry(onDelete: { _ in })
        let coordinator = MaterializationCoordinator<Int>(physicalUse: registry)
        let startBarrier = MaterializationStartBarrier(participantCount: 2)
        let workGate = MaterializationWorkGate()
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

        await workGate.waitForFirstCall()
        let callsBeforeRelease = await workGate.callCount
        XCTAssertEqual(callsBeforeRelease, 1, "exactly one underlying work may start before release")

        await workGate.release()
        var outcomes: [MaterializeOutcome] = []
        for task in tasks {
            outcomes.append(await task.value)
        }
        let callsAfterRelease = await workGate.callCount

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
            namespace: f3ns, tokens: f3tokens(256, seed: 4), write: f3writeSynthetic(to:))
        let artifact = entry.artifact as! DiskPrefixArtifact
        let sidecarBefore = try Data(contentsOf: artifact.metadataURL)

        // A completed materialization writes NO persistent protection
        // state: sidecar bytes identical before/after.
        _ = try await coordinator.materialize(key: artifact.snapshotURL.path) { "ok" }
        let sidecarAfter = try Data(contentsOf: artifact.metadataURL)
        XCTAssertEqual(sidecarBefore, sidecarAfter, "transient protection leaves no trace")

        // Evict (no in-flight use → immediate delete), then
        // restart-rescan must not resurrect.
        store.remove(entry)
        let fresh = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        XCTAssertEqual(try fresh.rescan(), 0, "removed artifact stays gone")
        XCTAssertNil(
            fresh.pool.admit(namespace: f3ns, promptTokens: f3tokens(256, seed: 4)))
    }
}
