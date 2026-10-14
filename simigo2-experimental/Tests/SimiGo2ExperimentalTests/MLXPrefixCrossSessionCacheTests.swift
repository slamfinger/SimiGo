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

        runtime.install()
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
        runtime.install()
        defer { runtime.uninstall() }
        let hook = try XCTUnwrap(ChatSession.crossSessionPrefixLookup)
        XCTAssertNil(hook([11, 22, 33]))

        let observations = runtime.observations
        XCTAssertEqual(observations.calls, 1)
        XCTAssertEqual(observations.hits, 0)
        XCTAssertNil(observations.lastMatchedTokenCount)
    }

    func testUninstallRemovesHostHook() async throws {
        runtime.install()
        XCTAssertNotNil(ChatSession.crossSessionPrefixLookup)
        runtime.uninstall()
        XCTAssertNil(ChatSession.crossSessionPrefixLookup)
    }
}
