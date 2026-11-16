import Foundation
import XCTest
import SimiGo2Experimental

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
    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    private func directory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-prefix-safety-\\(name)-\\(UUID().uuidString)")
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
        let (store, artifact, validSidecar) = try await exportFixture(root: root)
        _ = store
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

    func testRescanRejectsSnapshotReplacedAfterSidecarCommit() async throws {
        let root = try directory("snapshot-replaced")
        let (_, artifact, _) = try await exportFixture(root: root)
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
