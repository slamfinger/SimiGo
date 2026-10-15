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
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookupWithContext)
        let matched = try XCTUnwrap(
            hook.lookup(tokens + [97, 98, 99], callerContext(directory: nil)))
        XCTAssertEqual(matched.matchedTokenCount, tokens.count)

        let observations = runtime.observations
        XCTAssertEqual(observations.calls, 1)
        XCTAssertEqual(observations.hits, 1)
        XCTAssertEqual(observations.lastMatchedTokenCount, tokens.count)
    }

    func testHookMissDoesNotAdmitForeignPrefix() async throws {
        try runtime.install()
        defer { runtime.uninstall() }
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookupWithContext)
        XCTAssertNil(hook.lookup([11, 22, 33], callerContext(directory: nil)))

        let observations = runtime.observations
        XCTAssertEqual(observations.calls, 1)
        XCTAssertEqual(observations.hits, 0)
        XCTAssertNil(observations.lastMatchedTokenCount)
    }

    func testUninstallRemovesHostHook() throws {
        try runtime.install()
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookupWithContext)
        XCTAssertEqual(runtime.uninstall(), true)
        XCTAssertNil(ChatSession.crossSessionPrefixLookupWithContext)
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
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookupWithContext)
        _ = hook.lookup([1, 2, 3], callerContext(directory: nil))
        XCTAssertEqual(runtime.observations.calls, 1)
        runtime.uninstall()
        XCTAssertNil(ChatSession.crossSessionPrefixLookupWithContext)
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
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookupWithContext)
        XCTAssertNotNil(hook.lookup(Array(0..<10), callerContext(directory: nil)))
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
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookupWithContext)

        // The displaced owner cannot clear the new owner's hook.
        XCTAssertEqual(runtime.uninstall(), false)
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookupWithContext)
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
        let contentIdentity = MLXPrefixCrossSessionCache.contentIdentity(
            modelDirectory: modelDirectory)
        XCTAssertEqual(
            adopted.store.root,
            MLXPrefixCrossSessionCache.hostRoot(
                base: base,
                namespace: MLXPrefixCrossSessionCache.namespace(
                    modelID: "Qwen3-Coder-30B",
                    contentIdentity: contentIdentity)))
        // The adopted namespace carries the content digest, not the bare
        // daily fingerprint.
        XCTAssertTrue(adopted.namespace.kvFingerprint.hasPrefix(
            MLXPrefixCrossSessionCache.dailyKVFingerprint + "-"))
        XCTAssertGreaterThan(
            adopted.namespace.kvFingerprint.count,
            MLXPrefixCrossSessionCache.dailyKVFingerprint.count + 32)
    }
}

// MARK: - Content identity isolation (GUI promotion acceptance, item 2)

extension MLXPrefixCrossSessionCacheTests {
    @discardableResult
    private func makeModelDirectory(
        name: String, tokenizerBody: String, weightsBody: String
    ) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("identity-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(tokenizerBody.utf8).write(to: directory.appendingPathComponent("tokenizer.json"))
        try? Data(weightsBody.utf8).write(to: directory.appendingPathComponent("model.safetensors"))
        return directory
    }

    /// THE same-name-different-model hole: directory NAME is not identity.
    /// Two directories with identical names but different content must get
    /// different content identities, different namespaces, and — at the
    /// pool level — must never adopt each other's snapshots.
    func testContentIdentitySeparatesSameNameDifferentContent() async throws {
        let dirA = makeModelDirectory(
            name: "same-model", tokenizerBody: "tokenizer-A", weightsBody: "weights-A")
        let dirB = makeModelDirectory(
            name: "same-model", tokenizerBody: "tokenizer-B", weightsBody: "weights-B")
        defer {
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
        }

        let identityA = MLXPrefixCrossSessionCache.contentIdentity(modelDirectory: dirA)
        let identityB = MLXPrefixCrossSessionCache.contentIdentity(modelDirectory: dirB)
        XCTAssertNotEqual(identityA, identityB)

        let namespaceA = MLXPrefixCrossSessionCache.namespace(
            modelDirectory: dirA, contentIdentity: identityA)
        let namespaceB = MLXPrefixCrossSessionCache.namespace(
            modelDirectory: dirB, contentIdentity: identityB)
        XCTAssertNotEqual(namespaceA, namespaceB)
        XCTAssertNotEqual(
            MLXPrefixCrossSessionCache.hostRoot(base: root!, namespace: namespaceA),
            MLXPrefixCrossSessionCache.hostRoot(base: root!, namespace: namespaceB))

        // Pool-level isolation: an entry admitted under namespace A must be
        // invisible to namespace B even inside ONE shared pool.
        let tokens = Array(0..<16)
        _ = try await runtime.store.export(namespace: namespaceA, tokens: tokens) { url in
            try writeSyntheticSnapshot(to: url)
        }
        XCTAssertNotNil(runtime.store.pool.admit(namespace: namespaceA, promptTokens: tokens + [1]))
        XCTAssertNil(runtime.store.pool.admit(namespace: namespaceB, promptTokens: tokens + [1]))
    }

    /// Determinism: identical content (copied directory) must produce the
    /// identical identity and namespace — the property that makes snapshots
    /// re-adoptable across restarts and switches.
    func testContentIdentityDeterministicForIdenticalContent() throws {
        let parentA = FileManager.default.temporaryDirectory
            .appendingPathComponent("identity-parent-A-(UUID().uuidString)", isDirectory: true)
        let parentB = FileManager.default.temporaryDirectory
            .appendingPathComponent("identity-parent-B-(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: parentA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: parentB, withIntermediateDirectories: true)
        // Same basename, different parents: the NAME is identical by construction.
        let dirA = parentA.appendingPathComponent("stable-model", isDirectory: true)
        let dirB = parentB.appendingPathComponent("stable-model", isDirectory: true)
        try? FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try? Data("tok".utf8).write(to: dirA.appendingPathComponent("tokenizer.json"))
        try? Data("weights".utf8).write(to: dirA.appendingPathComponent("model.safetensors"))
        try? Data("tok".utf8).write(to: dirB.appendingPathComponent("tokenizer.json"))
        try? Data("weights".utf8).write(to: dirB.appendingPathComponent("model.safetensors"))
        defer {
            try? FileManager.default.removeItem(at: parentA)
            try? FileManager.default.removeItem(at: parentB)
        }
        let identityA = MLXPrefixCrossSessionCache.contentIdentity(modelDirectory: dirA)
        let identityB = MLXPrefixCrossSessionCache.contentIdentity(modelDirectory: dirB)
        XCTAssertEqual(identityA, identityB)
        XCTAssertEqual(
            MLXPrefixCrossSessionCache.namespace(
                modelDirectory: dirA, contentIdentity: identityA),
            MLXPrefixCrossSessionCache.namespace(
                modelDirectory: dirB, contentIdentity: identityB))
    }

    /// Acceptance item 3: a corrupted artifact must fail closed — the hook
    /// returns nil (cold fallback), the observation records a miss, and no
    /// partial adoption happens.
    func testCorruptedArtifactFailsClosedWithoutPartialAdoption() async throws {
        let tokens = Array(0..<24)
        let entry = try await runtime.store.export(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            tokens: tokens
        ) { url in
            try writeSyntheticSnapshot(to: url)
        }
        let artifact = try XCTUnwrap(entry.artifact as? DiskPrefixArtifact)
        let handle = try FileHandle(forWritingTo: artifact.snapshotURL)
        try handle.seek(toOffset: 64)
        try handle.write(contentsOf: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        try handle.close()

        try runtime.install()
        defer { runtime.uninstall() }
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookupWithContext)
        XCTAssertNil(hook.lookup(tokens + [97, 98, 99], callerContext(directory: nil)))
        let observations = runtime.observations
        XCTAssertEqual(observations.calls, 1)
        XCTAssertEqual(observations.hits, 0)
    }
}

// MARK: - Ownership churn under concurrency (acceptance item 4)

extension MLXPrefixCrossSessionCacheTests {
    /// Repeated model switches and concurrent install/uninstall must keep
    /// the single-owner invariant: after the churn, the global hook is nil
    /// exactly when no cache claims ownership, and a live hook routes to
    /// the recorded owner and nobody else.
    func testConcurrentOwnershipChurnPreservesSingleOwnerInvariant() async throws {
        let factories: [(MLXPrefixCrossSessionCache, String)] = (0..<6).map { index in
            let store = PrefixSnapshotStore(
                root: root!.appendingPathComponent("churn-\(index)"),
                pool: ExecutionStatePrefixPool(tokenBudget: 100_000))
            return (MLXPrefixCrossSessionCache(
                store: store,
                namespace: PrefixPoolNamespace(modelID: "m\(index)", kvFingerprint: "fp")),
                    "m\(index)")
        }
        let participants = factories.map { $0.0 }
        await withTaskGroup(of: Void.self) { group in
            for (index, cache) in participants.enumerated() {
                group.addTask { @Sendable in
                    for step in 0..<30 {
                        switch (step + index) % 3 {
                        case 0:
                            try? cache.install()
                        case 1:
                            try? cache.install(forceTakeover: true)
                        default:
                            cache.uninstall()
                        }
                        await Task.yield()
                    }
                }
            }
        }
        for cache in participants {
            cache.uninstall()
        }

        let hook = ChatSession.crossSessionPrefixLookupWithContext
        let active = MLXPrefixCrossSessionCache.activeInstance
        XCTAssertEqual(hook == nil, active == nil)
        if let hook, let active {
            let before = active.observations.calls
            _ = hook.lookup([1, 2, 3, 4, 5], callerContext(directory: nil))
            XCTAssertEqual(active.observations.calls, before + 1)
        }
    }
}

extension MLXPrefixCrossSessionCacheTests {
    /// Restart / switch-back re-adoption contract: a freshly constructed
    /// cache on a durable root has an EMPTY pool until it is rescanned — the
    /// host performs that rescan at activation (fail-closed on a corrupt
    /// root). Without it, a model switched back or a restarted host
    /// cold-misses everything.
    func testFreshCacheOnDurableRootReAdoptsAfterRescan() async throws {
        let tokens = Array(0..<24)
        let durableRoot = root!.appendingPathComponent("durable-\(UUID().uuidString)")
        let seedingStore = PrefixSnapshotStore(
            root: durableRoot, pool: ExecutionStatePrefixPool(tokenBudget: 100_000))
        let entry = try await seedingStore.export(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            tokens: tokens
        ) { url in
            try writeSyntheticSnapshot(to: url)
        }
        XCTAssertNotNil((entry.artifact as? DiskPrefixArtifact)?.generation)

        // A fresh cache over the same durable root: pool starts empty.
        let restarted = MLXPrefixCrossSessionCache(
            store: PrefixSnapshotStore(
                root: durableRoot,
                pool: ExecutionStatePrefixPool(tokenBudget: 100_000)),
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"))
        let admittedBefore = restarted.store.pool.admit(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            promptTokens: tokens + [1])
        XCTAssertNil(admittedBefore, "pool must be empty before rescan")

        // Activation duty: rescan populates the pool from disk; quarantine
        // tombstones stay honored by rescan itself.
        _ = try restarted.store.rescan()
        let admittedAfter = restarted.store.pool.admit(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            promptTokens: tokens + [1])
        XCTAssertEqual(admittedAfter?.coveredTokens, tokens.count)
    }
}

// MARK: - Admission guard (F4 caller-identity closure, cache layer)

extension MLXPrefixCrossSessionCacheTests {
    /// The admission guard binds the hook to the host generation that
    /// installed it: a refused call returns nil (cold path) AND records an
    /// observed miss — refusals are visible in observations, not silent.
    func testAdmissionGuardRefusalReturnsColdAndRecordsMiss() async throws {
        let tokens = Array(0..<24)
        _ = try await runtime.store.export(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            tokens: tokens
        ) { url in
            try writeSyntheticSnapshot(to: url)
        }

        let admitted = ActorIsolated(false)
        try runtime.install(admissionGuard: { admitted.value })
        defer { runtime.uninstall() }
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookupWithContext)

        // Guard refuses: cold path, miss recorded.
        XCTAssertNil(hook.lookup(tokens + [97, 98, 99], callerContext(directory: nil)))
        XCTAssertEqual(runtime.observations.calls, 1)
        XCTAssertEqual(runtime.observations.hits, 0)

        // Guard admits: verified hit flows normally.
        await admitted.setValue(true)
        let matched = try XCTUnwrap(
            hook.lookup(tokens + [97, 98, 99], callerContext(directory: nil)))
        XCTAssertEqual(matched.matchedTokenCount, tokens.count)
        XCTAssertEqual(runtime.observations.hits, 1)
    }
}

import MLX

/// Minimal lock-guarded bool the guard closure can capture.
final class ActorIsolated: @unchecked Sendable {
    private let lock = NSLock()
    private var underlying: Bool
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return underlying
    }

    init(_ initial: Bool) { underlying = initial }

    func setValue(_ newValue: Bool) {
        lock.lock()
        underlying = newValue
        lock.unlock()
    }
}

// MARK: - Canonical prefill profile (F1 adjudication)

extension MLXPrefixCrossSessionCacheTests {
    /// The profile binds the namespace: same content, different canonical
    /// profile → different namespace → old artifacts unreachable (isolated,
    /// never silently reused across an execution-protocol change).
    func testCanonicalProfileBindsNamespaceAndInvalidatesAcrossChange() {
        let identity = MLXPrefixCrossSessionCache.MLXModelContentIdentity(
            weightsDigest: "w", tokenizerDigest: "t")
        let stride256 = CanonicalPrefillProfile(stride: 256)
        let stride512 = CanonicalPrefillProfile(stride: 512)
        let v2 = CanonicalPrefillProfile(version: "canonical-remainder-v2", stride: 256)

        let base = MLXPrefixCrossSessionCache.namespace(
            modelID: "m", contentIdentity: identity, profile: stride256)
        XCTAssertNotEqual(
            base,
            MLXPrefixCrossSessionCache.namespace(
                modelID: "m", contentIdentity: identity, profile: stride512))
        XCTAssertNotEqual(
            base,
            MLXPrefixCrossSessionCache.namespace(
                modelID: "m", contentIdentity: identity, profile: v2))
        XCTAssertTrue(base.kvFingerprint.contains(stride256.fingerprint))
        // Different content still separates under the same profile.
        let otherContent = MLXPrefixCrossSessionCache.MLXModelContentIdentity(
            weightsDigest: "w2", tokenizerDigest: "t")
        XCTAssertNotEqual(
            base,
            MLXPrefixCrossSessionCache.namespace(
                modelID: "m", contentIdentity: otherContent, profile: stride256))
    }

    /// The canonical plan's stability points: boundaries only at positive
    /// stride multiples, and the floor function maps any request down to
    /// one.
    func testCanonicalProfileStableBoundaries() {
        let profile = CanonicalPrefillProfile(stride: 256)
        XCTAssertTrue(profile.isStableBoundary(256))
        XCTAssertTrue(profile.isStableBoundary(1024))
        XCTAssertFalse(profile.isStableBoundary(0))
        XCTAssertFalse(profile.isStableBoundary(100))
        XCTAssertEqual(profile.stableBoundary(atOrBelow: 900), 768)
        XCTAssertEqual(profile.stableBoundary(atOrBelow: 256), 256)
        XCTAssertEqual(profile.stableBoundary(atOrBelow: 100), 0)
    }
}

// MARK: - Caller-identity directory binding (FORK-HOOK-CALLER-IDENTITY-01)

extension MLXPrefixCrossSessionCacheTests {
    func callerContext(
        directory: URL?
    ) -> ChatSession.CrossSessionCallerContext {
        ChatSession.CrossSessionCallerContext(modelDirectory: directory)
    }

    /// The cache admits only callers whose model origin matches the
    /// directory it was activated with: a foreign directory and a nil
    /// origin are both refused (recorded miss, cold path), the matching
    /// directory adopts.
    func testCallerDirectoryBindingRefusesForeignAndNilOrigins() async throws {
        let tokens = Array(0..<24)
        _ = try await runtime.store.export(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            tokens: tokens
        ) { url in
            try writeSyntheticSnapshot(to: url)
        }
        let home = URL(fileURLWithPath: "/models/home", isDirectory: true)
        let foreign = URL(fileURLWithPath: "/models/foreign", isDirectory: true)
        try runtime.install(allowedModelDirectory: home)
        defer { runtime.uninstall() }
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookupWithContext)

        // Foreign origin: refused, miss recorded.
        XCTAssertNil(hook.lookup(tokens + [97, 98, 99], callerContext(directory: foreign)))
        XCTAssertEqual(runtime.observations.calls, 1)
        XCTAssertEqual(runtime.observations.hits, 0)

        // Nil origin (unresolved hub id): refused.
        XCTAssertNil(hook.lookup(tokens + [97, 98, 99], callerContext(directory: nil)))
        XCTAssertEqual(runtime.observations.calls, 2)

        // Matching origin: verified adoption.
        let matched = try XCTUnwrap(
            hook.lookup(tokens + [97, 98, 99], callerContext(directory: home)))
        XCTAssertEqual(matched.matchedTokenCount, tokens.count)
        XCTAssertEqual(runtime.observations.hits, 1)
    }

    /// Complete release means the CONTEXT slot is clear; a foreign LEGACY
    /// owner is not this cache's to clear and must not be clobbered.
    func testUninstallReleasesContextSlotWithoutTouchingForeignLegacy() throws {
        try runtime.install()
        let foreignLegacy: (@Sendable ([Int]) -> (cache: PromptCacheSnapshot, matchedTokenCount: Int)?) = { _ in nil }
        ChatSession.crossSessionPrefixLookup = foreignLegacy
        defer { ChatSession.crossSessionPrefixLookup = nil }

        XCTAssertEqual(runtime.uninstall(), true)
        XCTAssertNil(ChatSession.crossSessionPrefixLookupWithContext)
        XCTAssertTrue(runtime.ownsNoHookSlot)
        // The foreign legacy owner survives untouched.
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookup)
    }
}

// MARK: - FCI-OWN-01: foreign CONTEXT-slot ownership conflicts

extension MLXPrefixCrossSessionCacheTests {
    private func foreignLookup(
        forwardingTo original: ChatSession.CrossSessionPrefixLookup? = nil
    ) -> ChatSession.CrossSessionPrefixLookup {
        ChatSession.CrossSessionPrefixLookup(
            owner: ChatSession.CrossSessionPrefixLookup.OwnerToken(),
            lookup: { tokens, caller in
                original?.lookup(tokens, caller)
            })
    }

    /// A foreign context hook installed directly on the static (outside
    /// our registry) must make a plain install REFUSE — the internal
    /// `active` registry being empty is not authority to overwrite.
    func testForeignContextSlotOwnerBlocksPlainInstall() throws {
        ChatSession.crossSessionPrefixLookupWithContext = foreignLookup()
        defer { ChatSession.crossSessionPrefixLookupWithContext = nil }

        XCTAssertThrowsError(try runtime.install()) { error in
            XCTAssertEqual(
                error as? MLXPrefixCrossSessionCache.OwnershipError,
                .hookOwnedByOther)
        }
        XCTAssertFalse(runtime.isInstalled)
        XCTAssertNil(MLXPrefixCrossSessionCache.activeInstance)
        // The foreign hook is untouched.
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookupWithContext)

        // An explicit takeover may replace it (deliberate model-switch).
        try runtime.install(forceTakeover: true)
        XCTAssertTrue(runtime.isInstalled)
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookupWithContext)
        runtime.uninstall()
        XCTAssertNil(ChatSession.crossSessionPrefixLookupWithContext)
    }

    /// If an external party REPLACED the context slot while this cache was
    /// active, uninstall must NOT clear the replacement: it reports the
    /// inconsistency and returns false, leaving the foreign hook intact.
    func testUninstallDoesNotClearExternallyReplacedContextSlot() throws {
        try runtime.install()
        XCTAssertTrue(runtime.isInstalled)

        ChatSession.crossSessionPrefixLookupWithContext = foreignLookup()

        XCTAssertEqual(runtime.uninstall(), false)
        XCTAssertTrue(runtime.ownershipInconsistencyDetected)
        XCTAssertNil(MLXPrefixCrossSessionCache.activeInstance)
        // The external replacement SURVIVES the uninstall.
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookupWithContext)
        ChatSession.crossSessionPrefixLookupWithContext = nil
    }
}

extension MLXPrefixCrossSessionCacheTests {
    /// FCI-OWN-02 core counterexample: a WRAPPER that forwards every call
    /// (including any probe) to our installed hook. Reachability holds —
    /// the forwarded calls still work — but the wrapper's owner token is
    /// foreign, so it is NOT us: plain reinstall refuses, and uninstall
    /// preserves the wrapper instead of clearing it.
    func testForwardingWrapperIsNotTheOwnerDespiteReachability() async throws {
        let tokens = Array(0..<24)
        _ = try await runtime.store.export(
            namespace: PrefixPoolNamespace(modelID: "test-model", kvFingerprint: "fp-cross"),
            tokens: tokens
        ) { url in
            try writeSyntheticSnapshot(to: url)
        }
        try runtime.install(
            allowedModelDirectory: URL(fileURLWithPath: "/models/home", isDirectory: true))
        XCTAssertTrue(runtime.isInstalled)

        // External party wraps OUR lookup and installs the wrapper with
        // ITS OWN owner token.
        let original = ChatSession.crossSessionPrefixLookupWithContext!
        let wrapper = foreignLookup(forwardingTo: original)
        ChatSession.crossSessionPrefixLookupWithContext = wrapper

        // Same-instance reinstall must NOT fast-return on the registry:
        // the slot no longer carries our token → plain install refuses.
        XCTAssertThrowsError(try runtime.install()) { error in
            XCTAssertEqual(
                error as? MLXPrefixCrossSessionCache.OwnershipError,
                .hookOwnedByOther)
        }

        // The wrapper remains fully functional (reachability intact)…
        let home = ChatSession.CrossSessionCallerContext(
            modelDirectory: URL(fileURLWithPath: "/models/home", isDirectory: true))
        let matched = wrapper.lookup(tokens + [1], home)
        XCTAssertEqual(matched?.matchedTokenCount, tokens.count)

        // …but uninstall treats it as a foreign owner: preserved, not
        // cleared, inconsistency reported.
        XCTAssertEqual(runtime.uninstall(), false)
        XCTAssertTrue(runtime.ownershipInconsistencyDetected)
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookupWithContext)
        // And the wrapper STILL answers after our uninstall.
        XCTAssertNotNil(wrapper.lookup(tokens + [1], home))
        ChatSession.crossSessionPrefixLookupWithContext = nil
    }

    /// The idempotent fast path verifies the CURRENT slot: with the slot
    /// intact and still ours, re-install succeeds and keeps behavior.
    func testIdempotentReinstallVerifiesSlotOwnership() throws {
        try runtime.install()
        try runtime.install()
        XCTAssertTrue(runtime.isInstalled)
        XCTAssertTrue(runtime.uninstall())
        XCTAssertNil(ChatSession.crossSessionPrefixLookupWithContext)
    }
}

// MARK: - FCI-OWN-03/04/05 (third ownership review round)

extension MLXPrefixCrossSessionCacheTests {
    /// OWN-03: the token is UNREADABLE — a wrapper cannot even construct
    /// the same-token forwarding struct the review described. The struct
    /// answers isOwned(by:) ONLY to the party already holding the exact
    /// token; anyone else's wrapper (foreign token) is not us. This test
    /// pins that semantics from the outside.
    func testSameTokenWrapperIsUnconstructibleAndForeignWrappersAreNotOurs() throws {
        try runtime.install()
        let ourToken = ChatSession.CrossSessionPrefixLookup.OwnerToken()
        // A struct we build with a DIFFERENT token is not owned by our
        // token — even though its lookup forwards to the live slot.
        let original = ChatSession.crossSessionPrefixLookupWithContext!
        let wrapper = foreignLookup(forwardingTo: original)
        XCTAssertFalse(wrapper.isOwned(by: ourToken))
        // The slot IS owned by the cache's own (inaccessible) token —
        // provable only through behavior: uninstall clears it cleanly.
        XCTAssertTrue(runtime.uninstall())
        XCTAssertNil(ChatSession.crossSessionPrefixLookupWithContext)
    }

    /// OWN-04: another instance remains registered as active while the
    /// static slot was externally CLEARED — a plain install must still be
    /// refused; the registry is an independent authority, not a slot
    /// shadow. Only an explicit takeover displaces a live instance.
    func testRegistryActiveInstanceBlocksPlainInstallEvenWithEmptySlot() throws {
        try runtime.install()

        // External party clears the static slot directly.
        ChatSession.crossSessionPrefixLookupWithContext = nil
        defer { /* slot already nil */ }

        let otherRoot = root!.deletingLastPathComponent()
            .appendingPathComponent("prefix-cross-session-own04-\(UUID().uuidString)")
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

        // Explicit takeover displaces the live instance.
        try other.install(forceTakeover: true)
        XCTAssertTrue(other.isInstalled)
        // The displaced instance's uninstall is a visible no-op.
        XCTAssertEqual(runtime.uninstall(), false)
        XCTAssertTrue(other.uninstall())
        XCTAssertNil(ChatSession.crossSessionPrefixLookupWithContext)
    }

    /// OWN-05: ownsNoHookSlot means NO context hook remains. While a
    /// preserved external wrapper still occupies the slot it is FALSE;
    /// only after the slot is actually cleared does it become TRUE.
    func testOwnsNoHookSlotFalseWhileExternalWrapperRemains() throws {
        try runtime.install()
        let original = ChatSession.crossSessionPrefixLookupWithContext!
        ChatSession.crossSessionPrefixLookupWithContext =
            foreignLookup(forwardingTo: original)

        XCTAssertEqual(runtime.uninstall(), false)
        XCTAssertTrue(runtime.ownershipInconsistencyDetected)
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookupWithContext)
        XCTAssertFalse(runtime.ownsNoHookSlot)

        ChatSession.crossSessionPrefixLookupWithContext = nil
        XCTAssertTrue(runtime.ownsNoHookSlot)
    }
}
