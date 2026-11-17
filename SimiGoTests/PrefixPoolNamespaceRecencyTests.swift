import Foundation
import Darwin
import XCTest
@testable import SimiGo2Experimental
import SimiGoRuntimeContract

@testable import SimiGo

/// Slice 7 regression: prefix-pool LRU recency must be scoped per
/// (namespace, boundaryHash), not by the bare boundaryHash.
///
/// `boundaryHash` is derived purely from the token prefix, and a pool entry's
/// `==` also folds in the namespace — so the SAME token prefix living under two
/// different model/KV namespaces produces two distinct live entries that SHARE
/// one boundaryHash. Before the fix the recency map was keyed by that bare
/// hash, so admitting one namespace silently refreshed the OTHER namespace's
/// recency slot; eviction then read a collided recency and could drop the entry
/// that was just used while keeping a stale same-hash sibling. The fix keys
/// recency by (namespace, boundaryHash), so each namespace tracks its own LRU.
///
/// Model-free: pure token-budget LRU — a default `physicalByteCount == nil`
/// handle keeps physical accounting out of the picture, so only the token
/// budget drives eviction. No artifact bytes, no model, no disk.
final class PrefixPoolNamespaceRecencyTests: XCTestCase {
    /// Minimal handle relying on the protocol default `physicalByteCount == nil`.
    private struct Marker: PrefixArtifactHandle {}

    private let tokenPrefix = [11, 22, 33]   // shared content -> shared boundaryHash
    private let otherPrefix = [44, 55, 66]    // distinct content

    private let nsA = PrefixPoolNamespace(modelID: "m1", kvFingerprint: "kv1")
    private let nsB = PrefixPoolNamespace(modelID: "m2", kvFingerprint: "kv2")
    private let nsC = PrefixPoolNamespace(modelID: "m3", kvFingerprint: "kv3")

    /// Precondition for the collision: the same prefix under two namespaces is
    /// two distinct live entries — the setup the eviction test relies on.
    func testSamePrefixUnderTwoNamespacesAreDistinctLiveEntries() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 100)
        _ = pool.export(namespace: nsA, tokens: tokenPrefix, artifact: Marker())
        _ = pool.export(namespace: nsB, tokens: tokenPrefix, artifact: Marker())
        XCTAssertNotNil(pool.admit(namespace: nsA, promptTokens: tokenPrefix))
        XCTAssertNotNil(pool.admit(namespace: nsB, promptTokens: tokenPrefix))
    }

    /// The regression: nsA is admitted again (most-recently-used among the two
    /// same-hash siblings), then an over-budget export must evict the
    /// NEVER-re-used nsB — not the freshly used nsA. Under the old shared-slot
    /// keying both siblings read the same recency and the wrong one is dropped.
    func testLruEvictsStaleNamespaceSiblingNotRecentlyAdmitted() {
        // tokenBudget 6 = exactly two 3-token entries; the third export evicts.
        let pool = ExecutionStatePrefixPool(tokenBudget: 6)
        _ = pool.export(namespace: nsA, tokens: tokenPrefix, artifact: Marker())  // recency 1
        _ = pool.export(namespace: nsB, tokens: tokenPrefix, artifact: Marker())  // recency 2
        _ = pool.admit(namespace: nsA, promptTokens: tokenPrefix)                 // recency 3 (A used again)

        // A third 3-token entry pushes total to 9 > 6 -> exactly one victim.
        _ = pool.export(namespace: nsC, tokens: otherPrefix, artifact: Marker())

        // Correct (per-namespace recency): B is the stale LRU sibling -> evicted.
        XCTAssertNotNil(pool.admit(namespace: nsA, promptTokens: tokenPrefix),
                        "recently admitted nsA must NOT be evicted by a namespace sibling's recency")
        XCTAssertNil(pool.admit(namespace: nsB, promptTokens: tokenPrefix),
                     "the stale nsB sibling is the true LRU victim")
        XCTAssertNotNil(pool.admit(namespace: nsC, promptTokens: otherPrefix),
                        "the just-exported nsC is the most recent and must survive")
    }

    /// The adapter's export dedup check must follow authoritative pool residency.
    /// An observational contains() must not refresh LRU recency or mutate stats:
    /// otherwise checking whether a boundary is still present could change the
    /// very eviction decision it is trying to observe.
    func testContainsTracksEvictionWithoutChangingRecencyOrStats() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 6)
        let prefixA = [1, 2, 3]
        let prefixB = [4, 5, 6]
        let prefixC = [7, 8, 9]

        _ = pool.export(namespace: nsA, tokens: prefixA, artifact: Marker())
        _ = pool.export(namespace: nsB, tokens: prefixB, artifact: Marker())
        let statsBeforeQuery = pool.stats

        XCTAssertTrue(pool.contains(
            namespace: nsA, tokenCount: prefixA.count,
            boundaryHash: PrefixChain.hash(prefixA)))
        XCTAssertTrue(pool.contains(
            namespace: nsB, tokenCount: prefixB.count,
            boundaryHash: PrefixChain.hash(prefixB)))
        XCTAssertEqual(pool.stats, statsBeforeQuery,
                       "membership queries must not alter pool statistics")

        // The read-only checks above must not make A more recent than B.
        _ = pool.export(namespace: nsC, tokens: prefixC, artifact: Marker())
        XCTAssertFalse(pool.contains(
            namespace: nsA, tokenCount: prefixA.count,
            boundaryHash: PrefixChain.hash(prefixA)),
            "an evicted boundary must no longer suppress a later export")
        XCTAssertTrue(pool.contains(
            namespace: nsB, tokenCount: prefixB.count,
            boundaryHash: PrefixChain.hash(prefixB)))
        XCTAssertTrue(pool.contains(
            namespace: nsC, tokenCount: prefixC.count,
            boundaryHash: PrefixChain.hash(prefixC)))

        // Re-registering the same content makes it visible again.
        _ = pool.export(namespace: nsA, tokens: prefixA, artifact: Marker())
        XCTAssertTrue(pool.contains(
            namespace: nsA, tokenCount: prefixA.count,
            boundaryHash: PrefixChain.hash(prefixA)))
    }

    func testAdmissionRequiresStrongContentDigestBeyondLegacyHash() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 100)
        let tokens = [11, 22, 33, 44]
        _ = pool.register(
            namespace: nsA, tokenCount: tokens.count,
            boundaryHash: PrefixChain.hash(tokens),
            contentDomain: .tokenIDs,
            contentDigest: String(repeating: "0", count: 64),
            artifact: Marker())
        XCTAssertNil(
            pool.admit(namespace: nsA, promptTokens: tokens),
            "matching a legacy UInt64 claim is not sufficient for a cache hit")
    }
    /// Control: ordinary single-lineage LRU still evicts the least-recently-used
    /// entry, so per-namespace keys do not disable normal eviction.
    func testSingleNamespaceLruEvictionStillWorks() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 6)
        _ = pool.export(namespace: nsA, tokens: tokenPrefix, artifact: Marker())  // recency 1
        _ = pool.export(namespace: nsB, tokens: otherPrefix, artifact: Marker())  // recency 2
        _ = pool.admit(namespace: nsB, promptTokens: otherPrefix)                 // recency 3 (B used again)
        _ = pool.export(namespace: nsC, tokens: [77, 88, 99], artifact: Marker()) // total 9 > 6 -> evict A

        XCTAssertNil(pool.admit(namespace: nsA, promptTokens: tokenPrefix),
                     "normal LRU still evicts the least-recently-used entry")
        XCTAssertNotNil(pool.admit(namespace: nsB, promptTokens: otherPrefix),
                        "the re-used nsB must survive")
    }
}


/// Restart-rescan and artifact-boundary regressions. These tests use tiny
/// placeholder files: every rejection happens before MLX attempts to decode
/// a snapshot, so no model weights or GPU are required.
final class PrefixSnapshotStoreRestartSafetyTests: XCTestCase {
    private struct OpaqueArtifact: PrefixArtifactHandle {}

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    private func directory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-prefix-safety-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        scratch.append(url)
        return url
    }

    private func exportFixture(
        root: URL, namespace: PrefixPoolNamespace = .init(modelID: "model", kvFingerprint: "kv")
    ) async throws -> (PrefixSnapshotStore, DiskPrefixArtifact, Data) {
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        let entry = try await store.export(namespace: namespace, tokens: [1, 2, 3]) { url in
            try Data("snapshot".utf8).write(to: url)
        }
        let artifact = try XCTUnwrap(entry.artifact as? DiskPrefixArtifact)
        return (store, artifact, try Data(contentsOf: artifact.metadataURL))
    }

    func testRescanSkipsZeroAndNegativeTokenCounts() async throws {
        let root = try directory("bad-count")
        let (_, artifact, validSidecar) = try await exportFixture(root: root)

        // Positive control: a current v3 sidecar must be recoverable before
        // malformed token counts are introduced.
        let validPool = ExecutionStatePrefixPool(tokenBudget: 100)
        let validRestore = PrefixSnapshotStore(root: root, pool: validPool)
        XCTAssertEqual(try validRestore.rescan(), 1)

        for invalidCount in [0, -1] {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: validSidecar) as? [String: Any])
            var changed = object
            changed["tokenCount"] = invalidCount
            try JSONSerialization.data(withJSONObject: changed)
                .write(to: artifact.metadataURL, options: .atomic)

            let restoredPool = ExecutionStatePrefixPool(tokenBudget: 100)
            let restored = PrefixSnapshotStore(root: root, pool: restoredPool)
            XCTAssertEqual(try restored.rescan(), 0)
            XCTAssertNil(restoredPool.admit(
                namespace: PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv"),
                promptTokens: [1, 2, 3]))
        }
    }

    func testRescanSkipsUnsupportedSidecarVersion() async throws {
        let root = try directory("unsupported-version")
        let (_, artifact, validSidecar) = try await exportFixture(root: root)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validSidecar) as? [String: Any])
        object["version"] = 4
        try JSONSerialization.data(withJSONObject: object)
            .write(to: artifact.metadataURL, options: .atomic)

        let restored = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try restored.rescan(), 0)
    }

    func testRescanRejectsSnapshotReplacedAfterSidecarCommit() async throws {
        let root = try directory("snapshot-replaced")
        let (_, artifact, _) = try await exportFixture(root: root)
        let validRestore = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try validRestore.rescan(), 1,
                       "the intact v2 sidecar and snapshot must be recoverable")

        // Same length, different inode and ctime: metadata alone must not be
        // allowed to vouch for the replacement KV bytes.
        try Data("tampered".utf8).write(to: artifact.snapshotURL, options: .atomic)

        let restored = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try restored.rescan(), 0)
    }

    func testRescanSkipsSymlinkedSidecarSnapshotAndNamespaceDirectory() async throws {
        let root = try directory("symlink-root")
        let outside = try directory("outside")
        let (_, artifact, validSidecar) = try await exportFixture(root: root)
        let fm = FileManager.default

        let validRestore = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try validRestore.rescan(), 1,
                       "the intact v2 artifact is the positive control")

        let externalSidecar = outside.appendingPathComponent("external.json")
        try validSidecar.write(to: externalSidecar)
        try fm.removeItem(at: artifact.metadataURL)
        try fm.createSymbolicLink(at: artifact.metadataURL, withDestinationURL: externalSidecar)
        let sidecarStore = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try sidecarStore.rescan(), 0)

        try fm.removeItem(at: artifact.metadataURL)
        try validSidecar.write(to: artifact.metadataURL)
        let externalSnapshot = outside.appendingPathComponent("external.safetensors")
        try Data("snapshot".utf8).write(to: externalSnapshot)
        try fm.removeItem(at: artifact.snapshotURL)
        try fm.createSymbolicLink(at: artifact.snapshotURL, withDestinationURL: externalSnapshot)
        let snapshotStore = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try snapshotStore.rescan(), 0)

        let namespaceDirectory = artifact.snapshotURL.deletingLastPathComponent()
        try fm.removeItem(at: namespaceDirectory)
        let outsideNamespace = outside.appendingPathComponent("namespace", isDirectory: true)
        try fm.createDirectory(at: outsideNamespace, withIntermediateDirectories: true)
        let baseName = artifact.snapshotURL.deletingPathExtension().lastPathComponent
        try validSidecar.write(
            to: outsideNamespace.appendingPathComponent(baseName + ".json"))
        try Data("snapshot".utf8).write(
            to: outsideNamespace.appendingPathComponent(baseName + ".safetensors"))
        try fm.createSymbolicLink(at: namespaceDirectory, withDestinationURL: outsideNamespace)

        let namespaceStore = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try namespaceStore.rescan(), 0)
        do {
            _ = try await namespaceStore.export(
                namespace: PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv"),
                tokens: [1, 2, 3]) { url in
                    try Data("new".utf8).write(to: url)
                }
            XCTFail("export must not write through a namespace-directory symlink")
        } catch is PrefixSnapshotStoreError {
            // Expected fail-closed path.
        }
    }

    func testRescanRejectsSidecarNamespaceTampering() async throws {
        let root = try directory("namespace-tamper")
        let (_, artifact, validSidecar) = try await exportFixture(root: root)
        let validRestore = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try validRestore.rescan(), 1,
                       "the intact v2 artifact is the positive control")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validSidecar) as? [String: Any])
        object["modelID"] = "different-model"
        try JSONSerialization.data(withJSONObject: object)
            .write(to: artifact.metadataURL, options: .atomic)

        let restored = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        XCTAssertEqual(try restored.rescan(), 0,
                       "sidecar claims must agree with the hashed namespace directory")
    }



    func testExportRejectsEmptyAndOverBudgetTokenBoundariesBeforeWriting() async throws {
        let root = try directory("invalid-export-boundary")
        let pool = ExecutionStatePrefixPool(tokenBudget: 2)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        var writes = 0

        for tokens in [[], [1, 2, 3]] {
            do {
                _ = try await store.export(
                    namespace: PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv"),
                    tokens: tokens) { url in
                        writes += 1
                        try Data("must-not-write".utf8).write(to: url)
                    }
                XCTFail("invalid token boundary must be rejected")
            } catch is PrefixSnapshotStoreError {
                // Expected fail-closed path.
            }
        }
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(pool.totalTokens, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            atPath: root.path).isEmpty)
    }

    func testExportAndRescanRefuseRootReplacedBySymlink() async throws {
        let root = try directory("root-replaced")
        let outside = try directory("root-outside")
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100))
        let backup = root.deletingLastPathComponent()
            .appendingPathComponent("simigo-prefix-safety-root-backup-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: root, to: backup)
        scratch.append(backup)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)

        do {
            _ = try await store.export(
                namespace: PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv"),
                tokens: [1, 2, 3]) { url in
                    try Data("must-not-escape".utf8).write(to: url)
                }
            XCTFail("export must refuse a root replaced by a symlink")
        } catch is PrefixSnapshotStoreError {
            // Expected fail-closed path.
        }
        XCTAssertThrowsError(try store.rescan())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            atPath: outside.path).isEmpty,
            "root replacement must not create files in the symlink target")
    }

    func testDiskSnapshotsStaySeparatedByPhysicalIdentityAcrossRescan() async throws {
        let root = try directory("physical-identity")
        let modelA = SettlementIdentityBinding.Identity(
            model: "weights-digest-A", tokenizer: "tokenizer-digest-1")
        let modelB = SettlementIdentityBinding.Identity(
            model: "weights-digest-B", tokenizer: "tokenizer-digest-1")
        let namespaceA = try XCTUnwrap(NativeMLXPrefixPool.namespace(
            modelID: "same-repository-name", kvFingerprint: "same-kv-layout",
            thinkingDisabled: false, engineIdentity: modelA))
        let namespaceB = try XCTUnwrap(NativeMLXPrefixPool.namespace(
            modelID: "same-repository-name", kvFingerprint: "same-kv-layout",
            thinkingDisabled: false, engineIdentity: modelB))
        XCTAssertNotEqual(namespaceA, namespaceB)

        let promptTokens = [11, 22, 33, 44]
        let originalPool = ExecutionStatePrefixPool(
            tokenBudget: 1024, physicalByteBudget: 1_048_576)
        let originalStore = PrefixSnapshotStore(root: root, pool: originalPool)
        let entryA = try await originalStore.export(
            namespace: namespaceA, tokens: promptTokens
        ) { url in
            try Data("physical-kv-snapshot-A".utf8).write(to: url)
        }
        let entryB = try await originalStore.export(
            namespace: namespaceB, tokens: promptTokens
        ) { url in
            try Data("physical-kv-snapshot-B".utf8).write(to: url)
        }
        let artifactA = try XCTUnwrap(entryA.artifact as? DiskPrefixArtifact)
        let artifactB = try XCTUnwrap(entryB.artifact as? DiskPrefixArtifact)
        XCTAssertNotEqual(artifactA.snapshotURL, artifactB.snapshotURL)

        // A fresh pool recovers both physical identities from their own sidecars.
        let restartedPool = ExecutionStatePrefixPool(
            tokenBudget: 1024, physicalByteBudget: 1_048_576)
        let restartedStore = PrefixSnapshotStore(root: root, pool: restartedPool)
        XCTAssertEqual(try restartedStore.rescan(), 2)

        let admittedA = try XCTUnwrap(
            restartedPool.admit(namespace: namespaceA, promptTokens: promptTokens))
        let admittedB = try XCTUnwrap(
            restartedPool.admit(namespace: namespaceB, promptTokens: promptTokens))
        // macOS may spell the same temporary-directory target as /var or
        // /private/var. Compare resolved paths, not their pre-resolution URL
        // spellings, while still asserting that each identity restores its own file.
        XCTAssertEqual(
            (admittedA.entry.artifact as? DiskPrefixArtifact)?
                .snapshotURL.resolvingSymlinksInPath().standardizedFileURL,
            artifactA.snapshotURL.resolvingSymlinksInPath().standardizedFileURL)
        XCTAssertEqual(
            (admittedB.entry.artifact as? DiskPrefixArtifact)?
                .snapshotURL.resolvingSymlinksInPath().standardizedFileURL,
            artifactB.snapshotURL.resolvingSymlinksInPath().standardizedFileURL)

        // Keep the path in namespace B but cross-wire its sidecar claim to A.
        // Path validation passes; the sidecar's own namespace claim must fail.
        var sidecarB = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: artifactB.metadataURL)) as? [String: Any])
        sidecarB["kvFingerprint"] = namespaceA.kvFingerprint
        try JSONSerialization.data(withJSONObject: sidecarB)
            .write(to: artifactB.metadataURL, options: .atomic)
        let crossModel = try XCTUnwrap(
            restartedPool.admit(namespace: namespaceB, promptTokens: promptTokens))
        XCTAssertThrowsError(try restartedStore.loadSync(crossModel)) { error in
            XCTAssertEqual(
                error as? PrefixSnapshotStoreError,
                .namespaceMismatch(expected: namespaceB, snapshot: namespaceA))
        }
    }

    func testCrossWiredArtifactHandleCannotDeleteAnotherNamespaceSnapshot() async throws {
        let root = try directory("cross-wired-artifact")
        let modelA = SettlementIdentityBinding.Identity(
            model: "weights-digest-A", tokenizer: "tokenizer-digest-1")
        let modelB = SettlementIdentityBinding.Identity(
            model: "weights-digest-B", tokenizer: "tokenizer-digest-1")
        let namespaceA = try XCTUnwrap(NativeMLXPrefixPool.namespace(
            modelID: "same-repository-name", kvFingerprint: "same-kv-layout",
            thinkingDisabled: false, engineIdentity: modelA))
        let namespaceB = try XCTUnwrap(NativeMLXPrefixPool.namespace(
            modelID: "same-repository-name", kvFingerprint: "same-kv-layout",
            thinkingDisabled: false, engineIdentity: modelB))
        let promptTokens = [11, 22, 33, 44]

        let originalPool = ExecutionStatePrefixPool(
            tokenBudget: 1024, physicalByteBudget: 1_048_576)
        let originalStore = PrefixSnapshotStore(root: root, pool: originalPool)
        let entryA = try await originalStore.export(
            namespace: namespaceA, tokens: promptTokens
        ) { url in
            try Data("physical-kv-snapshot-A".utf8).write(to: url)
        }
        _ = try await originalStore.export(
            namespace: namespaceB, tokens: promptTokens
        ) { url in
            try Data("physical-kv-snapshot-B".utf8).write(to: url)
        }
        let artifactA = try XCTUnwrap(entryA.artifact as? DiskPrefixArtifact)

        // Restart first, then simulate an incorrect in-memory registration:
        // B's pool entry is given A's artifact handle, while A still owns it.
        let restartedPool = ExecutionStatePrefixPool(
            tokenBudget: 1024, physicalByteBudget: 1_048_576)
        let restartedStore = PrefixSnapshotStore(root: root, pool: restartedPool)
        XCTAssertEqual(try restartedStore.rescan(), 2)
        _ = restartedPool.register(
            namespace: namespaceB,
            tokenCount: entryA.tokenCount,
            boundaryHash: entryA.boundaryHash,
            contentDomain: entryA.contentDomain,
            contentDigest: entryA.contentDigest,
            artifact: artifactA)

        let crossWired = try XCTUnwrap(
            restartedPool.admit(namespace: namespaceB, promptTokens: promptTokens))
        XCTAssertThrowsError(try restartedStore.loadSync(crossWired)) { error in
            XCTAssertEqual(
                error as? PrefixSnapshotStoreError,
                .artifactUnreadable("artifact path is outside the pool root or is a symlink"))
        }

        // Failed B cleanup must remove only B's bad pool entry. It must never
        // unlink the snapshot or sidecar still owned by namespace A.
        XCTAssertNil(
            restartedPool.admit(namespace: namespaceB, promptTokens: promptTokens),
            "the rejected cross-wired B entry must be removed from the pool")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactA.snapshotURL.path),
                      "rejecting B's foreign handle must preserve A's snapshot")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactA.metadataURL.path),
                      "rejecting B's foreign handle must preserve A's sidecar")
        let admittedA = try XCTUnwrap(
            restartedPool.admit(namespace: namespaceA, promptTokens: promptTokens))
        // Rescan re-derives URLs through the resolved root (/private/var), so
        // compare resolved paths rather than pre-resolution spellings.
        XCTAssertEqual(
            (admittedA.entry.artifact as? DiskPrefixArtifact)?
                .snapshotURL.resolvingSymlinksInPath().standardizedFileURL,
            artifactA.snapshotURL.resolvingSymlinksInPath().standardizedFileURL,
            "namespace A must retain its original artifact registration")
    }

    func testSameContentReexportRetiresOnlyTheSupersededGeneration() async throws {
        let root = try directory("same-content-reexport")
        let namespace = PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv")
        let pool = ExecutionStatePrefixPool(tokenBudget: 100)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        let promptTokens = [1, 2, 3]

        let oldEntry = try await store.export(namespace: namespace, tokens: promptTokens) { url in
            try Data("old-generation".utf8).write(to: url)
        }
        let oldArtifact = try XCTUnwrap(oldEntry.artifact as? DiskPrefixArtifact)
        let staleAdmission = try XCTUnwrap(
            pool.admit(namespace: namespace, promptTokens: promptTokens))

        let newEntry = try await store.export(namespace: namespace, tokens: promptTokens) { url in
            try Data("new-generation".utf8).write(to: url)
        }
        let newArtifact = try XCTUnwrap(newEntry.artifact as? DiskPrefixArtifact)

        XCTAssertNotEqual(oldArtifact.generationID, newArtifact.generationID)
        XCTAssertNotEqual(oldArtifact.snapshotURL, newArtifact.snapshotURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldArtifact.snapshotURL.path),
                       "replacing a content entry retires its old snapshot generation")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldArtifact.metadataURL.path),
                       "replacing a content entry retires its old sidecar generation")

        // A delayed failure from the old admission must not remove the new
        // content-identical entry or its independently published files.
        XCTAssertThrowsError(try store.loadSync(staleAdmission))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newArtifact.snapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newArtifact.metadataURL.path))
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: newArtifact.snapshotURL), as: UTF8.self),
            "new-generation")
        let current = try XCTUnwrap(pool.admit(namespace: namespace, promptTokens: promptTokens))
        XCTAssertEqual(
            (current.entry.artifact as? DiskPrefixArtifact)?.generationID,
            newArtifact.generationID)
    }

    func testReexportDefersOldSnapshotDeletionUntilPhysicalUseEnds() async throws {
        let root = try directory("physical-use-reexport")
        let namespace = PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv")
        let pool = ExecutionStatePrefixPool(tokenBudget: 100)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        let promptTokens = [21, 22, 23]

        let oldEntry = try await store.export(namespace: namespace, tokens: promptTokens) { url in
            try Data("old-generation".utf8).write(to: url)
        }
        let oldArtifact = try XCTUnwrap(oldEntry.artifact as? DiskPrefixArtifact)
        let admission = try XCTUnwrap(
            pool.admit(namespace: namespace, promptTokens: promptTokens))

        let entered = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        let loader = Task.detached {
            try store.withPhysicalArtifactUse(admission: admission) { _ in
                entered.signal()
                proceed.wait()
                return FileManager.default.fileExists(atPath: oldArtifact.snapshotURL.path)
            }
        }

        guard entered.wait(timeout: .now() + 5) == .success else {
            proceed.signal()
            _ = try await loader.value
            XCTFail("physical-use lease should be acquired before the loader blocks")
            return
        }

        let newEntry = try await store.export(namespace: namespace, tokens: promptTokens) { url in
            try Data("new-generation".utf8).write(to: url)
        }
        let newArtifact = try XCTUnwrap(newEntry.artifact as? DiskPrefixArtifact)
        let oldExistsWhileLeased = FileManager.default.fileExists(atPath: oldArtifact.snapshotURL.path)

        proceed.signal()
        let oldExistsInsideOperation = try await loader.value

        XCTAssertTrue(oldExistsWhileLeased,
                      "re-export must defer deleting an artifact held by a physical-use lease")
        XCTAssertTrue(oldExistsInsideOperation,
                      "the old file must remain readable until the protected operation ends")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldArtifact.snapshotURL.path),
                       "the retired generation should be deleted after the final lease releases")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newArtifact.snapshotURL.path),
                      "the new generation must remain available")
    }

    func testExplicitRemoveDefersDeletionUntilPhysicalUseEnds() async throws {
        let root = try directory("physical-use-explicit-remove")
        let namespace = PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv")
        let pool = ExecutionStatePrefixPool(tokenBudget: 100)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        let promptTokens = [31, 32, 33]

        let entry = try await store.export(namespace: namespace, tokens: promptTokens) { url in
            try Data("live-snapshot".utf8).write(to: url)
        }
        let artifact = try XCTUnwrap(entry.artifact as? DiskPrefixArtifact)
        let admission = try XCTUnwrap(
            pool.admit(namespace: namespace, promptTokens: promptTokens))

        let entered = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        let loader = Task.detached {
            try store.withPhysicalArtifactUse(admission: admission) { _ in
                entered.signal()
                proceed.wait()
                return FileManager.default.fileExists(atPath: artifact.snapshotURL.path)
            }
        }

        guard entered.wait(timeout: .now() + 5) == .success else {
            proceed.signal()
            _ = try await loader.value
            XCTFail("physical-use lease should be acquired before explicit removal")
            return
        }

        store.remove(entry)
        let existsWhileLeased = FileManager.default.fileExists(atPath: artifact.snapshotURL.path)
        proceed.signal()
        let existedInsideOperation = try await loader.value

        XCTAssertTrue(existsWhileLeased,
                      "explicit remove must defer deletion while a physical-use lease is active")
        XCTAssertTrue(existedInsideOperation,
                      "the active operation must retain access to its snapshot")
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.snapshotURL.path),
                       "explicit remove should delete the retired file after lease release")
        XCTAssertNil(pool.admit(namespace: namespace, promptTokens: promptTokens))
    }

    func testRescanRejectsLegacyV2SnapshotLayoutWithoutStrongDigest() async throws {
        let root = try directory("legacy-v2")
        let (_, artifact, validSidecar) = try await exportFixture(root: root)
        var sidecar = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validSidecar) as? [String: Any])
        sidecar["version"] = 2
        sidecar.removeValue(forKey: "generationID")

        let directory = artifact.snapshotURL.deletingLastPathComponent()
        let legacyBase = "\(String(PrefixChain.hash([1, 2, 3]), radix: 16))-3"
        let legacySnapshot = directory.appendingPathComponent(legacyBase + ".safetensors")
        let legacyMetadata = directory.appendingPathComponent(legacyBase + ".json")
        try FileManager.default.moveItem(at: artifact.snapshotURL, to: legacySnapshot)
        try FileManager.default.moveItem(at: artifact.metadataURL, to: legacyMetadata)

        // The v2 sidecar pins inode + mtime + ctime. Renaming the file can
        // update ctime, so rebuild the identity from the file at its final
        // legacy path instead of carrying the pre-rename v3 identity forward.
        var snapshotInfo = stat()
        let statResult = legacySnapshot.path.withCString {
            Darwin.lstat($0, &snapshotInfo)
        }
        XCTAssertEqual(statResult, 0, "legacy snapshot must exist for identity capture")
        sidecar["snapshotIdentity"] = [
            "device": UInt64(snapshotInfo.st_dev),
            "inode": UInt64(snapshotInfo.st_ino),
            "byteCount": Int64(snapshotInfo.st_size),
            "modifiedSeconds": Int64(snapshotInfo.st_mtimespec.tv_sec),
            "modifiedNanoseconds": Int64(snapshotInfo.st_mtimespec.tv_nsec),
            "changedSeconds": Int64(snapshotInfo.st_ctimespec.tv_sec),
            "changedNanoseconds": Int64(snapshotInfo.st_ctimespec.tv_nsec)
        ]
        try JSONSerialization.data(withJSONObject: sidecar)
            .write(to: legacyMetadata, options: .atomic)

        let restoredPool = ExecutionStatePrefixPool(tokenBudget: 100)
        let restored = PrefixSnapshotStore(root: root, pool: restoredPool)
        XCTAssertEqual(try restored.rescan(), 0,
                       "legacy sidecars lack a strong content commitment and cannot be re-admitted")
        XCTAssertNil(restoredPool.admit(
            namespace: PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv"),
            promptTokens: [1, 2, 3]))
    }

    func testForeignArtifactFailureRemovesOnlyItsOwnRegistration() async throws {
        let root = try directory("foreign-artifact")
        let pool = ExecutionStatePrefixPool(tokenBudget: 100)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        let namespace = PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv")
        let tokens = [7, 8, 9]

        _ = pool.export(namespace: namespace, tokens: tokens, artifact: OpaqueArtifact())
        let staleAdmission = try XCTUnwrap(pool.admit(namespace: namespace, promptTokens: tokens))
        _ = pool.export(namespace: namespace, tokens: tokens, artifact: OpaqueArtifact())

        do {
            _ = try await store.load(staleAdmission)
            XCTFail("an opaque foreign artifact must fail closed")
        } catch is PrefixSnapshotStoreError {
            // Expected; this stale failure must remove only its own registration.
        }
        XCTAssertNotNil(
            pool.admit(namespace: namespace, promptTokens: tokens),
            "a delayed foreign-handle failure must not remove the replacement registration")

        let currentTokens = [10, 11, 12]
        _ = pool.export(
            namespace: namespace, tokens: currentTokens, artifact: OpaqueArtifact())
        let currentAdmission = try XCTUnwrap(
            pool.admit(namespace: namespace, promptTokens: currentTokens))
        XCTAssertThrowsError(try store.loadSync(currentAdmission))
        XCTAssertNil(
            pool.admit(namespace: namespace, promptTokens: currentTokens),
            "a currently invalid foreign-handle registration must be cleaned up")
    }

    func testLoadRemovesModifiedSnapshotAfterFailClosed() async throws {
        let root = try directory("load-tamper")
        let (store, artifact, _) = try await exportFixture(root: root)
        try Data("tampered".utf8).write(to: artifact.snapshotURL, options: .atomic)
        let admission = try XCTUnwrap(store.pool.admit(
            namespace: PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv"),
            promptTokens: [1, 2, 3]))

        do {
            _ = try await store.load(admission)
            XCTFail("modified snapshot must not be restored")
        } catch is PrefixSnapshotStoreError {
            // Expected fail-closed path; the corrupt in-root artifact is removed.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.metadataURL.path))
    }

    func testRemoveNeverDeletesArtifactOutsidePoolRoot() throws {
        let root = try directory("remove-root")
        let outside = try directory("remove-outside")
        let snapshot = outside.appendingPathComponent("external.safetensors")
        let metadata = outside.appendingPathComponent("external.json")
        try Data("snapshot".utf8).write(to: snapshot)
        try Data("metadata".utf8).write(to: metadata)

        let namespace = PrefixPoolNamespace(modelID: "model", kvFingerprint: "kv")
        let pool = ExecutionStatePrefixPool(tokenBudget: 100)
        let store = PrefixSnapshotStore(root: root, pool: pool)
        let entry = pool.export(
            namespace: namespace, tokens: [1, 2, 3],
            artifact: DiskPrefixArtifact(snapshotURL: snapshot, metadataURL: metadata))
        store.remove(entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadata.path))
    }
}
