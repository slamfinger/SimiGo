import Foundation
import MLX
import MLXLMCommon
import XCTest

@testable import SimiGo2Experimental

/// KV-quant × disk-pool parity (2026-11-22, kv-kv window).
///
/// Locks the corrected conclusion: the production messageSequence disk path
/// (export → rescan → admit → load) is representation-generic. `QuantizedKVCache`
/// is registered in `KVCacheTypeRegistry` and is trimmable, so a quantized prefix
/// survives a simulated restart (a brand-new store on the same root) and restores
/// as `QuantizedKVCache` with its offset intact — no new product code is required
/// for quantized disk-pool reuse. The quantized-specific exclusions live elsewhere
/// (token-domain B-6 base gate, memory-pool capture, the test-only
/// `truncatedSnapshot` helper), not on this path.
///
/// Scope: two quantized full-attn layers, no carried `LMOutput.State`. Quantization
/// only touches full-attn layers; a hybrid model's state layers (MambaCache/
/// ArraysCache) are representation-independent and their round-trip is already
/// exercised by the fp16 bind experiment. Model-free: synthetic KV, real store
/// machinery (sidecar v4 + namespace dir + rescan + admission + load).
final class QuantizedKVPoolRoundTripTests: XCTestCase {
    func testQuantizedPrefixSurvivesRestartRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qpool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ns = PrefixPoolNamespace(
            modelID: "ornith-test", kvFingerprint: "affine4|think:0|physical:test")
        let history: [(role: String, content: String)] = [
            (role: "user", content: "alpha"), (role: "assistant", content: "beta"),
            (role: "user", content: "gamma"), (role: "assistant", content: "delta"),
        ]
        let chain = PrefixMessageChain.stream(history)
        let tokenCount = 64

        func makeCache() -> QuantizedKVCache {
            let cache = QuantizedKVCache(groupSize: 64, bits: 4, mode: .affine)
            let keys = MLXArray.zeros([1, 2, tokenCount, 256], dtype: .float16)
            let values = MLXArray.zeros([1, 2, tokenCount, 256], dtype: .float16)
            _ = cache.updateQuantized(keys: keys, values: values)
            return cache
        }
        let cache: [any KVCache] = [makeCache(), makeCache()]

        // Export through the real store (write closure = savePromptCache, the
        // same serialization ChatSession.saveCache uses).
        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100_000))
        let entry = try await store.export(
            namespace: ns, tokens: chain, domain: .messageSequence
        ) { url in
            try savePromptCache(url: url, cache: cache, metadata: ["modelID": ns.modelID])
        }
        XCTAssertEqual(entry.tokenCount, chain.count)

        // Simulated restart: fresh store on the same root, claims re-registered
        // from sidecars only (the token array is not reconstructable from hash).
        let restarted = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 100_000))
        XCTAssertGreaterThan(try restarted.rescan(), 0)
        let admission = try XCTUnwrap(
            restarted.pool.admit(namespace: ns, promptTokens: chain, domain: .messageSequence),
            "quantized namespace must admit its own restarted boundary")
        let snapshot = try await restarted.load(admission)

        // Restored as quantized (not downcast to fp16), offset intact, trimmable
        // via the same protocol trim the engine narrow path uses.
        XCTAssertEqual(snapshot.cache.count, 2)
        for layer in snapshot.cache {
            let quantized = try XCTUnwrap(
                layer as? QuantizedKVCache,
                "registry must restore QuantizedKVCache across the disk round-trip")
            XCTAssertEqual(quantized.bits, 4)
            XCTAssertEqual(quantized.offset, tokenCount)
            XCTAssertTrue(quantized.isTrimmable)
            XCTAssertEqual(quantized.trim(16), 16)
            XCTAssertEqual(quantized.offset, tokenCount - 16)
        }
    }
}
