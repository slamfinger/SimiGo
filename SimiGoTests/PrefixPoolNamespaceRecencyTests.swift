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
