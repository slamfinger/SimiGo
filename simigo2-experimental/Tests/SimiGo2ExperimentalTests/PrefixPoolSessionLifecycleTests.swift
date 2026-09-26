import XCTest
import MLXLMCommon
import MLX
@testable import SimiGo2Experimental

/// B-3 lifecycle battery — the full session lifecycle against the real
/// store and pool (synthetic KV snapshots, no model):
///
///   session A: cold start (miss) → generate → commit → export L_A
///   session B: different key, SAME document prefix + extra → admits
///              L_A (delta only) → extends → commit → export L_B
///   RESTART:   fresh pool + store on the same root → rescan →
///              session C admits L_B without any new computation
///
/// This is the integration seam the product routing (B-4) calls into:
/// admit → load → extend → commit-export, plus restart-warm survival.
final class PrefixPoolSessionLifecycleTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prefix-lifecycle-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let ns = PrefixPoolNamespace(modelID: "qwen3-8b", kvFingerprint: "fp-mlc4")

    /// A conversation's processed token sequence: 6.2K shared document
    /// head (the measured cold-prefill class) optionally + session tail.
    private func sharedDocument() -> [Int] {
        (0..<6200).map { ($0 * 17 + 5) % 50_000 + 3 }
    }

    private func makeStore() -> PrefixSnapshotStore {
        PrefixSnapshotStore(root: root, pool: ExecutionStatePrefixPool(tokenBudget: 1_000_000))
    }

    private func commitTurn(
        _ store: PrefixSnapshotStore, processedTokens: [Int], artifactId: Int
    ) async throws -> PrefixPoolEntry {
        try await store.export(
            namespace: ns, tokens: processedTokens
        ) { url in
            // The production exporter is session.saveCache(to:); the
            // synthetic stand-in produces a real snapshot file.
            let layer = KVCacheSimple()
            layer.update(
                keys: MLXArray.zeros([1, 2, 8, 4]),
                values: MLXArray.zeros([1, 2, 8, 4]))
            try savePromptCache(url: url, cache: [layer])
            _ = artifactId
        }
    }

    func testColdStartThenCrossSessionShareThenRestartWarm() async throws {
        let document = sharedDocument()

        // --- Session A: cold start (the 47.6s class) ---
        let storeA = makeStore()
        XCTAssertNil(
            storeA.pool.admit(namespace: ns, promptTokens: document),
            "empty world: cold start")
        let entryA = try await commitTurn(storeA, processedTokens: document, artifactId: 1)

        // --- Session B: different conversation, same document head ---
        var promptB = document
        promptB.append(contentsOf: (0..<300).map { ($0 * 7 + 1) % 40_000 + 3 })
        // Same live store first…
        let admissionB = storeA.pool.admit(namespace: ns, promptTokens: promptB)
        XCTAssertEqual(admissionB?.coveredTokens, 6200, "session B pays only its own tail")
        _ = try await storeA.load(admissionB!)
        _ = entryA

        // …and through a SECOND store instance over the same disk (a
        // second process / reopened app before restart is simulated):
        let storeB = makeStore()
        XCTAssertNil(storeB.pool.admit(namespace: ns, promptTokens: promptB))
        let rescanned = try storeB.rescan()
        XCTAssertEqual(rescanned, 1, "one boundary on disk")
        let admissionB2 = storeB.pool.admit(namespace: ns, promptTokens: promptB)
        XCTAssertEqual(admissionB2?.coveredTokens, 6200, "disk re-registration admits")
        let snapshotB2 = try await storeB.load(admissionB2!)
        XCTAssertEqual(snapshotB2.cache.count, 1)

        // Session B commits its extended turn — a new, longer boundary.
        _ = try await commitTurn(storeB, processedTokens: promptB, artifactId: 2)

        // --- RESTART: fresh everything, only the disk survives ---
        let storeC = makeStore()
        XCTAssertEqual(try storeC.rescan(), 2, "both boundaries re-registered")
        // A new session continuing B's conversation is warm immediately:
        var promptC = promptB
        promptC.append(contentsOf: (0..<120).map { ($0 * 11 + 3) % 30_000 + 3 })
        let admissionC = storeC.pool.admit(namespace: ns, promptTokens: promptC)
        XCTAssertEqual(
            admissionC?.coveredTokens, promptB.count,
            "longest boundary (B's commit) wins after restart")
        _ = try await storeC.load(admissionC!)

        // A session with a DIVERGENT document never false-hits:
        let divergent = sharedDocument().map { $0 == 5 ? 6 : $0 }
        XCTAssertLessThan(
            storeC.pool.admit(namespace: ns, promptTokens: divergent)?.coveredTokens ?? 0,
            6200, "one-token divergence at position 0 breaks the chain at position 0")
    }

    func testRescanSkipsVanishedSnapshots() async throws {
        let store = makeStore()
        let entry = try await commitTurn(store, processedTokens: sharedDocument(), artifactId: 1)
        let artifact = entry.artifact as! DiskPrefixArtifact
        try FileManager.default.removeItem(at: artifact.snapshotURL)

        let fresh = makeStore()
        XCTAssertEqual(try fresh.rescan(), 0, "vanished snapshot is not re-registered")
        XCTAssertNil(fresh.pool.admit(namespace: ns, promptTokens: sharedDocument()))
    }

    func testRescanSurvivesGarbageSidecar() async throws {
        let store = makeStore()
        _ = try await commitTurn(store, processedTokens: sharedDocument(), artifactId: 1)
        // Drop a corrupt sidecar into the namespace directory.
        let namespaceDir = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ).first { $0.hasDirectoryPath }!
        try Data("not json".utf8).write(
            to: namespaceDir.appendingPathComponent("garbage.json"))

        let fresh = makeStore()
        XCTAssertEqual(try fresh.rescan(), 1, "garbage sidecar skipped, real entry kept")
    }

    func testBudgetEvictionAppliesAcrossRescan() async throws {
        // Tiny budget on the RECEIVING pool: rescan must respect it.
        let store = makeStore()
        let document = sharedDocument()
        _ = try await commitTurn(store, processedTokens: document, artifactId: 1)
        var longer = document
        longer.append(contentsOf: (0..<200).map { $0 % 20_000 + 3 })
        _ = try await commitTurn(store, processedTokens: longer, artifactId: 2)

        let fresh = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 6500))
        let registered = try fresh.rescan()
        XCTAssertEqual(registered, 2, "both claims registered")
        XCTAssertLessThanOrEqual(fresh.pool.totalTokens, 6500, "budget enforced after rescan")
    }
}
