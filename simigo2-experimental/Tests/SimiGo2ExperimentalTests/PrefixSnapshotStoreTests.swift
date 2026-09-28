import XCTest
import MLXLMCommon
import MLX
@testable import SimiGo2Experimental

/// B-2 battery — the KV artifact adapter, exercised WITHOUT a model:
/// synthetic KVCacheSimple snapshots (real savePromptCache /
/// loadPromptCacheSnapshot file round-trip) plus tampered/missing
/// artifacts for the loud-failure surfaces. P-I1 full chain shape:
/// prompt → entry (pool admission) → artifact (sidecar reconciliation),
/// every link verified, failure = entry removed + throw.
final class PrefixSnapshotStoreTests: XCTestCase {
    private let ns = PrefixPoolNamespace(modelID: "qwen3-8b", kvFingerprint: "fp-mlc4")
    private var root: URL!
    private var store: PrefixSnapshotStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prefix-pool-\(UUID().uuidString)")
        store = PrefixSnapshotStore(root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000_000))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func tokens(_ count: Int, seed: Int = 0) -> [Int] {
        (0..<count).map { ($0 * 31 + seed * 7) % 50_000 + 3 }
    }

    /// A real snapshot file with synthetic cache content — the same
    /// serializer the production path uses, no model required.
    private func writeSyntheticSnapshot(to url: URL, tokenCount: Int = 8) throws {
        let layer = KVCacheSimple()
        layer.update(
            keys: MLXArray.zeros([1, 2, tokenCount, 4]),
            values: MLXArray.zeros([1, 2, tokenCount, 4]))
        try savePromptCache(url: url, cache: [layer])
    }

    func testExportRegistersEntryAndWritesSidecar() async throws {
        let prefix = tokens(512)
        let entry = try await store.export(
            namespace: ns, tokens: prefix
        ) { url in
            try writeSyntheticSnapshot(to: url, tokenCount: 8)
        }
        let admission = pool_admit(prefix)
        XCTAssertEqual(admission?.entry, entry)
        let artifact = entry.artifact as! DiskPrefixArtifact
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.snapshotURL.path))
        let sidecar = try JSONDecoder().decode(
            PrefixSnapshotSidecar.self, from: Data(contentsOf: artifact.metadataURL))
        XCTAssertEqual(sidecar.tokenCount, 512)
        XCTAssertEqual(sidecar.chainHash, PrefixChain.hash(prefix))
        XCTAssertEqual(sidecar.modelID, ns.modelID)
    }

    func testLoadRoundTripsSyntheticSnapshot() async throws {
        let prefix = tokens(256)
        _ = try await store.export(namespace: ns, tokens: prefix) { url in
            try writeSyntheticSnapshot(to: url, tokenCount: 8)
        }
        let admission = pool_admit(prefix)
        let snapshot = try await store.load(admission!)
        XCTAssertEqual(snapshot.cache.count, 1, "one synthetic layer survives the file round-trip")
        XCTAssertEqual(snapshot.cache[0].state.count, 2, "keys + values restored")
    }

    func testTamperedTokenCountThrowsAndSelfHeals() async throws {
        let prefix = tokens(512)
        let entry = try await store.export(namespace: ns, tokens: prefix) { url in
            try writeSyntheticSnapshot(to: url)
        }
        // Tamper: the sidecar now claims a different prefix length.
        let artifact = entry.artifact as! DiskPrefixArtifact
        var sidecar = try JSONDecoder().decode(
            PrefixSnapshotSidecar.self, from: Data(contentsOf: artifact.metadataURL))
        sidecar.tokenCount += 64
        try JSONEncoder().encode(sidecar).write(to: artifact.metadataURL)

        let admission = pool_admit(prefix)
        do {
            _ = try await store.load(admission!)
            XCTFail("expected load to throw")
        } catch let error as PrefixSnapshotStoreError {
            guard case .metadataMismatch = error else {
                return XCTFail("expected metadataMismatch, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
        // Self-healing: the untrustworthy entry is gone from the pool.
        XCTAssertNil(pool_admit(prefix))
    }

    func testTamperedChainHashThrows() async throws {
        let prefix = tokens(512)
        let entry = try await store.export(namespace: ns, tokens: prefix) { url in
            try writeSyntheticSnapshot(to: url)
        }
        let artifact = entry.artifact as! DiskPrefixArtifact
        var sidecar = try JSONDecoder().decode(
            PrefixSnapshotSidecar.self, from: Data(contentsOf: artifact.metadataURL))
        sidecar.chainHash &+= 1
        try JSONEncoder().encode(sidecar).write(to: artifact.metadataURL)
        let admission = pool_admit(prefix)
        do {
            _ = try await store.load(admission!)
            XCTFail("expected load to throw")
        } catch is PrefixSnapshotStoreError {} catch {
            XCTFail("unexpected error type: \(error)")
        }
        XCTAssertNil(pool_admit(prefix))
    }

    func testMissingSnapshotThrowsAndSelfHeals() async throws {
        let prefix = tokens(512)
        let entry = try await store.export(namespace: ns, tokens: prefix) { url in
            try writeSyntheticSnapshot(to: url)
        }
        let artifact = entry.artifact as! DiskPrefixArtifact
        try FileManager.default.removeItem(at: artifact.snapshotURL)
        let admission = pool_admit(prefix)
        do {
            _ = try await store.load(admission!)
            XCTFail("expected load to throw")
        } catch let error as PrefixSnapshotStoreError {
            guard case .artifactUnreadable = error else {
                return XCTFail("expected artifactUnreadable, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
        XCTAssertNil(pool_admit(prefix))
    }

    func testFailingExporterLeavesPoolUntouched() async throws {
        let prefix = tokens(512)
        do {
            _ = try await store.export(namespace: ns, tokens: prefix) { _ in
                throw NSError(domain: "test", code: 1)
            }
            XCTFail("expected export to throw")
        } catch {}
        XCTAssertEqual(store.pool.totalTokens, 0, "failed export registers nothing")
        XCTAssertNil(pool_admit(prefix))
    }

    func testNamespacesSeparatedOnDisk() async throws {
        let prefix = tokens(512)
        let other = PrefixPoolNamespace(modelID: "gemma4-12b", kvFingerprint: "fp-mlc8")
        _ = try await store.export(namespace: ns, tokens: prefix) { url in
            try writeSyntheticSnapshot(to: url)
        }
        _ = try await store.export(namespace: other, tokens: prefix) { url in
            try writeSyntheticSnapshot(to: url)
        }
        let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
        XCTAssertEqual(contents.count, 2, "one directory per namespace")
    }

    // The store takes the pool as a constructor dependency; admit through
    // it so assertions exercise the exact production admission path.
    private func pool_admit(_ tokens: [Int]) -> PrefixAdmission? {
        store.pool.admit(namespace: ns, promptTokens: tokens)
    }
}

/// P2 — eviction persistence: an evicted representation must neither be
/// re-admitted in-process NOR resurrected by a restart rescan (its disk
/// artifact is deleted at eviction time).
final class PrefixPoolEvictionPersistenceTests: XCTestCase {
    private let ns = PrefixPoolNamespace(modelID: "qwen3-8b", kvFingerprint: "fp-mlc4")

    private func tokens(_ count: Int, seed: Int = 0) -> [Int] {
        (0..<count).map { ($0 * 31 + seed * 7) % 50_000 + 3 }
    }

    private func writeSnapshot(to url: URL) throws {
        let layer = KVCacheSimple()
        layer.update(
            keys: MLXArray.zeros([1, 2, 8, 4]),
            values: MLXArray.zeros([1, 2, 8, 4]))
        try savePromptCache(url: url, cache: [layer])
    }

    func testEvictionDeletesArtifactAndBlocksResurrection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prefix-p2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = ExecutionStatePrefixPool(tokenBudget: 1100)
        let store = PrefixSnapshotStore(root: root, pool: pool)

        let a = tokens(512, seed: 1)
        let b = tokens(512, seed: 2)
        let c = tokens(512, seed: 3)
        _ = try await store.export(namespace: ns, tokens: a) { url in
            try writeSnapshot(to: url)
        }
        let entryB = try await store.export(namespace: ns, tokens: b) { url in
            try writeSnapshot(to: url)
        }
        // Touch A so B is the LRU victim when C arrives.
        _ = pool.admit(namespace: ns, promptTokens: a)
        let artifactB = entryB.artifact as! DiskPrefixArtifact
        _ = try await store.export(namespace: ns, tokens: c) { url in
            try writeSnapshot(to: url)
        }
        XCTAssertEqual(pool.stats.evictions, 1, "B evicted")

        // B's artifact files are GONE from disk (eviction = deletion).
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: artifactB.snapshotURL.path),
            "evicted artifact must not linger to resurrect on rescan")

        // Restart rescan must NOT resurrect B.
        let fresh = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        XCTAssertEqual(try fresh.rescan(), 2, "only A and C re-register")
        XCTAssertNil(fresh.pool.admit(namespace: ns, promptTokens: b))
        XCTAssertNotNil(fresh.pool.admit(namespace: ns, promptTokens: a))
    }
}

/// P2 continuity — same-boundary re-export across persistent pool runs
/// must REPLACE the artifact (real-device finding 2026-09-28: moveItem
/// to an existing destination threw 516, leaving the pool entry stale).
final class PrefixSnapshotReexportTests: XCTestCase {
    private func f3tokens(_ count: Int, seed: Int = 0) -> [Int] {
        (0..<count).map { ($0 * 31 + seed * 7) % 50_000 + 3 }
    }

    private let ns = PrefixPoolNamespace(modelID: "qwen3-8b", kvFingerprint: "fp-mlc4")

    func testSameBoundaryReExportSucceeds() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("f3-reexport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = ExecutionStatePrefixPool(tokenBudget: 10_000)
        let store = PrefixSnapshotStore(root: root, pool: pool)

        let write: (URL) async throws -> Void = { url in
            let layer = KVCacheSimple()
            layer.update(
                keys: MLXArray.zeros([1, 2, 8, 4]),
                values: MLXArray.zeros([1, 2, 8, 4]))
            try savePromptCache(url: url, cache: [layer])
        }
        let first = try await store.export(
            namespace: ns, tokens: f3tokens(512, seed: 1), write: write)
        let second = try await store.export(
            namespace: ns, tokens: f3tokens(512, seed: 1), write: write)
        XCTAssertEqual(first, second, "same content = same boundary")
        XCTAssertEqual(store.pool.stats.exports, 1)
        XCTAssertEqual(store.pool.stats.artifactReplacements, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: (second.artifact as! DiskPrefixArtifact).snapshotURL.path))
    }
}
