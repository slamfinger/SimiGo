import MLX
import MLXLMCommon
import XCTest
@testable import SimiGo2Experimental

final class MLXPrefixCrossSessionCacheTests: XCTestCase {
    private var root: URL!
    private var runtime: MLXPrefixCrossSessionCache!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prefix-cross-session-\(UUID().uuidString)")
        let pool = ExecutionStatePrefixPool(tokenBudget: 100_000)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        runtime = MLXPrefixCrossSessionCache(
            store: store,
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"))
    }

    override func tearDownWithError() throws {
        runtime.uninstall()
        try? FileManager.default.removeItem(at: root)
    }

    private func writeSyntheticSnapshot(to url: URL) throws {
        let layer = KVCacheSimple()
        layer.update(
            keys: MLXArray.zeros([1, 2, 8, 4]),
            values: MLXArray.zeros([1, 2, 8, 4]))
        try savePromptCache(url: url, cache: [layer])
    }

    func testInstalledHookReturnsVerifiedPrefixSnapshot() async throws {
        let tokens = Array(0..<24)
        let entry = try await runtime.store.export(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            tokens: tokens
        ) { url in
            try writeSyntheticSnapshot(to: url)
        }
        XCTAssertNotNil((entry.artifact as? DiskPrefixArtifact)?.generation)

        try runtime.install()
        defer { runtime.uninstall() }
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookup)
        let matched = try XCTUnwrap(hook(tokens + [97, 98, 99]))
        XCTAssertEqual(matched.matchedTokenCount, tokens.count)

        let observations = runtime.observations
        XCTAssertEqual(observations.calls, 1)
        XCTAssertEqual(observations.hits, 1)
        XCTAssertEqual(observations.lastMatchedTokenCount, tokens.count)
    }

    func testHookMissDoesNotAdmitForeignPrefix() async throws {
        try runtime.install()
        defer { runtime.uninstall() }
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookup)
        XCTAssertNil(hook([11, 22, 33]))

        let observations = runtime.observations
        XCTAssertEqual(observations.calls, 1)
        XCTAssertEqual(observations.hits, 0)
        XCTAssertNil(observations.lastMatchedTokenCount)
    }

    func testUninstallRemovesHostHook() throws {
        try runtime.install()
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookup)
        XCTAssertEqual(runtime.uninstall(), true)
        XCTAssertNil(ChatSession.crossSessionPrefixLookup)
        XCTAssertFalse(runtime.isInstalled)
        XCTAssertNil(MLXPrefixCrossSessionCache.activeInstance)
    }

    /// A long-lived host installing twice must be a no-op, not a second
    /// owner: the hook stays assigned exactly once.
    func testInstallIsIdempotentForSameInstance() throws {
        try runtime.install()
        try runtime.install()
        XCTAssertTrue(runtime.isInstalled)
        XCTAssertIdentical(MLXPrefixCrossSessionCache.activeInstance, runtime)
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookup)
        _ = hook([1, 2, 3])
        XCTAssertEqual(runtime.observations.calls, 1)
        runtime.uninstall()
        XCTAssertNil(ChatSession.crossSessionPrefixLookup)
    }

    /// While another cache owns the hook, a second host's install must fail
    /// closed — the incumbent's hook identity and observations stay intact.
    func testInstallFailsClosedWhileAnotherCacheOwnsHook() async throws {
        try runtime.install()
        defer { runtime.uninstall() }

        let otherRoot = root!.deletingLastPathComponent()
            .appendingPathComponent("prefix-cross-session-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let other = MLXPrefixCrossSessionCache(
            store: PrefixSnapshotStore(
                root: otherRoot,
                pool: ExecutionStatePrefixPool(tokenBudget: 100_000)),
            namespace: PrefixPoolNamespace(modelID: "other-model", kvFingerprint: "fp-other"))

        XCTAssertThrowsError(try other.install()) { error in
            XCTAssertEqual(
                error as? MLXPrefixCrossSessionCache.OwnershipError,
                .hookOwnedByOther)
        }
        XCTAssertFalse(other.isInstalled)
        XCTAssertIdentical(MLXPrefixCrossSessionCache.activeInstance, runtime)

        // The incumbent still owns the hook: a miss still routes to IT.
        try await runtime.store.export(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            tokens: Array(0..<8)
        ) { url in
            try writeSyntheticSnapshot(to: url)
        }
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookup)
        XCTAssertNotNil(hook(Array(0..<10)))
        XCTAssertEqual(runtime.observations.calls, 1)
    }

    /// The deliberate model-switch path: takeover transfers the hook, and
    /// the displaced owner's uninstall becomes a visible no-op that cannot
    /// steal or clear the new owner's hook.
    func testForceTakeoverTransfersOwnershipAndNeutralizesForeignUninstall() throws {
        try runtime.install()
        XCTAssertTrue(runtime.uninstall())

        let otherRoot = root!.deletingLastPathComponent()
            .appendingPathComponent("prefix-cross-session-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let other = MLXPrefixCrossSessionCache(
            store: PrefixSnapshotStore(
                root: otherRoot,
                pool: ExecutionStatePrefixPool(tokenBudget: 100_000)),
            namespace: PrefixPoolNamespace(modelID: "other-model", kvFingerprint: "fp-other"))

        try other.install(forceTakeover: true)
        XCTAssertTrue(other.isInstalled)
        XCTAssertIdentical(MLXPrefixCrossSessionCache.activeInstance, other)
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookup)

        // The displaced owner cannot clear the new owner's hook.
        XCTAssertEqual(runtime.uninstall(), false)
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookup)
        XCTAssertTrue(other.isInstalled)

        XCTAssertEqual(other.uninstall(), true)
        XCTAssertNil(ChatSession.crossSessionPrefixLookup)
        XCTAssertNil(MLXPrefixCrossSessionCache.activeInstance)
    }

    /// Long-lived host root convention: deterministic, path-safe, and the
    /// convenience adoption path lands the store under it.
    func testHostRootConventionIsDeterministicAndSanitized() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("host-cache-base-\(UUID().uuidString)")
        let namespace = PrefixPoolNamespace(modelID: "org/Model:32B", kvFingerprint: "chat-cross-session-v1")
        let first = MLXPrefixCrossSessionCache.hostRoot(base: base, namespace: namespace)
        let second = MLXPrefixCrossSessionCache.hostRoot(base: base, namespace: namespace)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "org-Model-32B-chat-cross-session-v1")

        let modelDirectory = URL(fileURLWithPath: "/models/Qwen3-Coder-30B")
        let adopted = MLXPrefixCrossSessionCache(modelDirectory: modelDirectory, base: base)
        XCTAssertEqual(
            adopted.store.root,
            MLXPrefixCrossSessionCache.hostRoot(
                base: base,
                namespace: PrefixPoolNamespace(
                    modelID: "Qwen3-Coder-30B",
                    kvFingerprint: MLXPrefixCrossSessionCache.dailyKVFingerprint)))
    }
}
