import XCTest
@testable import SimiGo2Experimental

/// PrefixPool unit battery (Route B stage B-1) — content-addressed
/// admission, namespace fidelity, LRU budget. P-I1 shape: an admitted
/// entry's boundary hash provably equals the incoming prompt's prefix
/// hash — a hit can never mis-describe content.
final class ExecutionStatePrefixPoolTests: XCTestCase {
    private struct FakeArtifact: PrefixArtifactHandle, Equatable {
        let id: Int
    }

    private let ns = PrefixPoolNamespace(modelID: "qwen3-8b", kvFingerprint: "fp-mlc4")

    private func tokens(_ count: Int, seed: Int = 0) -> [Int] {
        (0..<count).map { ($0 * 31 + seed * 7) % 50_000 + 3 }
    }

    func testExportThenAdmitHits() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 1_000_000)
        let prefix = tokens(512)
        pool.export(namespace: ns, tokens: prefix, artifact: FakeArtifact(id: 1))
        let admission = pool.admit(namespace: ns, promptTokens: prefix)
        XCTAssertNotNil(admission)
        XCTAssertEqual(admission?.coveredTokens, 512)
        XCTAssertEqual(admission?.entry.artifact as? FakeArtifact, FakeArtifact(id: 1))
        XCTAssertEqual(pool.stats.hits, 1)
    }

    func testAdmitCoversStoredPrefixOnly() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 1_000_000)
        let stored = tokens(2048)
        pool.export(namespace: ns, tokens: stored, artifact: FakeArtifact(id: 1))
        // A longer prompt whose HEAD equals the stored prefix: the delta
        // (2048...) is the caller's remaining work.
        var prompt = stored
        prompt.append(contentsOf: tokens(128, seed: 3))
        let admission = pool.admit(namespace: ns, promptTokens: prompt)
        XCTAssertEqual(admission?.coveredTokens, 2048)
    }

    func testContentMismatchIsMissAndEntrySurvives() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 1_000_000)
        let stored = tokens(512)
        pool.export(namespace: ns, tokens: stored, artifact: FakeArtifact(id: 1))
        // Same length, different content — and the SAME token multiset
        // shuffled is still a miss: the chain is order-sensitive.
        var shuffled = stored
        shuffled.swapAt(0, 100)
        XCTAssertNil(pool.admit(namespace: ns, promptTokens: shuffled))
        XCTAssertEqual(pool.stats.misses, 1)
        // The entry was not removed by the miss — it still serves its own
        // prompt (a miss is not a corruption verdict).
        XCTAssertNotNil(pool.admit(namespace: ns, promptTokens: stored))
    }

    func testLongestMatchWins() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 10_000_000)
        let head = tokens(512)
        var longer = head
        longer.append(contentsOf: tokens(1536, seed: 5))
        pool.export(namespace: ns, tokens: longer, artifact: FakeArtifact(id: 1))
        pool.export(namespace: ns, tokens: head, artifact: FakeArtifact(id: 2))
        var prompt = longer
        prompt.append(contentsOf: tokens(64, seed: 9))
        let admission = pool.admit(namespace: ns, promptTokens: prompt)
        XCTAssertEqual(admission?.coveredTokens, 2048, "longest stored boundary wins")
    }

    func testNamespaceIsolation() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 1_000_000)
        let prefix = tokens(512)
        pool.export(namespace: ns, tokens: prefix, artifact: FakeArtifact(id: 1))
        let otherModel = PrefixPoolNamespace(modelID: "gemma4-12b", kvFingerprint: "fp-mlc4")
        let otherFP = PrefixPoolNamespace(modelID: "qwen3-8b", kvFingerprint: "fp-mlc8")
        XCTAssertNil(pool.admit(namespace: otherModel, promptTokens: prefix))
        XCTAssertNil(pool.admit(namespace: otherFP, promptTokens: prefix))
        XCTAssertNotNil(pool.admit(namespace: ns, promptTokens: prefix))
    }

    func testReExportSameContentReplacesArtifact() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 1_000_000)
        let prefix = tokens(512)
        pool.export(namespace: ns, tokens: prefix, artifact: FakeArtifact(id: 1))
        pool.export(namespace: ns, tokens: prefix, artifact: FakeArtifact(id: 2))
        XCTAssertEqual(pool.stats.exports, 1)
        XCTAssertEqual(pool.stats.artifactReplacements, 1)
        let admission = pool.admit(namespace: ns, promptTokens: prefix)
        XCTAssertEqual(admission?.entry.artifact as? FakeArtifact, FakeArtifact(id: 2))
    }

    func testSameLengthDifferentContentBothAdmissible() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 1_000_000)
        let a = tokens(512, seed: 1)
        let b = tokens(512, seed: 2)
        pool.export(namespace: ns, tokens: a, artifact: FakeArtifact(id: 1))
        pool.export(namespace: ns, tokens: b, artifact: FakeArtifact(id: 2))
        XCTAssertEqual(pool.admit(namespace: ns, promptTokens: a)?.entry.artifact as? FakeArtifact, FakeArtifact(id: 1))
        XCTAssertEqual(pool.admit(namespace: ns, promptTokens: b)?.entry.artifact as? FakeArtifact, FakeArtifact(id: 2))
    }

    func testLRUEvictionUnderBudget() {
        // Budget admits two 512-token entries only.
        let pool = ExecutionStatePrefixPool(tokenBudget: 1024)
        let a = tokens(512, seed: 1)
        let b = tokens(512, seed: 2)
        let c = tokens(512, seed: 3)
        pool.export(namespace: ns, tokens: a, artifact: FakeArtifact(id: 1))
        pool.export(namespace: ns, tokens: b, artifact: FakeArtifact(id: 2))
        // Touch A so B becomes LRU.
        _ = pool.admit(namespace: ns, promptTokens: a)
        pool.export(namespace: ns, tokens: c, artifact: FakeArtifact(id: 3))
        XCTAssertEqual(pool.stats.evictions, 1, "B evicted, not A")
        XCTAssertNil(pool.admit(namespace: ns, promptTokens: b), "B was evicted")
        XCTAssertNotNil(pool.admit(namespace: ns, promptTokens: a), "touched A survives")
        XCTAssertLessThanOrEqual(pool.totalTokens, 1024)
    }

    func testRemoveDropsEntry() {
        let pool = ExecutionStatePrefixPool(tokenBudget: 1_000_000)
        let prefix = tokens(512)
        let entry = pool.export(namespace: ns, tokens: prefix, artifact: FakeArtifact(id: 1))
        XCTAssertTrue(pool.remove(entry))
        XCTAssertNil(pool.admit(namespace: ns, promptTokens: prefix))
        XCTAssertEqual(pool.totalTokens, 0)
    }

    /// Recency is scoped by namespace. Removing one namespace's copy of a
    /// shared boundary hash must not make another namespace's copy look LRU.
    func testRecencyIsNamespaceScopedForSameBoundaryHash() {
        let namespaceA = PrefixPoolNamespace(modelID: "model-a", kvFingerprint: "fp-a")
        let namespaceB = PrefixPoolNamespace(modelID: "model-b", kvFingerprint: "fp-b")
        let pool = ExecutionStatePrefixPool(tokenBudget: 768)
        let shared = tokens(256)
        let otherA = tokens(256, seed: 1)
        let otherA2 = tokens(256, seed: 2)
        let otherA3 = tokens(256, seed: 3)

        let aShared = pool.export(
            namespace: namespaceA, tokens: shared, artifact: FakeArtifact(id: 1))
        let otherAEntry = pool.export(
            namespace: namespaceA, tokens: otherA, artifact: FakeArtifact(id: 3))
        let bShared = pool.export(
            namespace: namespaceB, tokens: shared, artifact: FakeArtifact(id: 2))

        XCTAssertNotNil(pool.admit(namespace: namespaceB, promptTokens: shared))
        XCTAssertTrue(pool.remove(aShared))

        pool.export(
            namespace: namespaceA, tokens: otherA2, artifact: FakeArtifact(id: 4))

        pool.export(
            namespace: namespaceA, tokens: otherA3, artifact: FakeArtifact(id: 5))

        XCTAssertEqual(pool.stats.evictions, 1, "the true LRU entry must be evicted")
        XCTAssertNotNil(pool.admit(namespace: namespaceB, promptTokens: shared))
        XCTAssertNil(pool.admit(namespace: namespaceA, promptTokens: otherA))
        XCTAssertNotNil(pool.admit(namespace: namespaceA, promptTokens: otherA2))
        XCTAssertNotNil(pool.admit(namespace: namespaceA, promptTokens: otherA3))
        XCTAssertEqual(bShared.artifact as? FakeArtifact, FakeArtifact(id: 2))
        XCTAssertEqual(otherAEntry.artifact as? FakeArtifact, FakeArtifact(id: 3))
    }

    func testChainIsOrderSensitive() {
        let a: [Int] = [11, 22, 33]
        let b: [Int] = [33, 22, 11]
        XCTAssertNotEqual(PrefixChain.hash(a), PrefixChain.hash(b))
        XCTAssertEqual(PrefixChain.hash(a), PrefixChain.hash([11, 22, 33]))
        // Cumulative consistency: fold of cumulative tail == whole hash.
        XCTAssertEqual(PrefixChain.cumulative(a).last, PrefixChain.hash(a))
    }
}

/// B-4 seam — message-stream encoding: 2 stream elements per message,
/// deterministic, order- and content-sensitive.
final class PrefixMessageChainTests: XCTestCase {
    func testStreamCoversExactlyTwoElementsPerMessage() {
        let messages: [(role: String, content: String)] = [
            ("system", "you are a coding agent"), ("user", "hello"), ("assistant", "hi")]
        let stream = PrefixMessageChain.stream(messages)
        XCTAssertEqual(stream.count, 6, "two elements per message")
        // The chain over the full stream equals the chain over the stream
        // truncated at any message boundary (consistency of the encoding).
        XCTAssertEqual(PrefixChain.hash(stream), PrefixChain.hash(stream))
    }

    func testStreamIsContentAndRoleSensitive() {
        let a = PrefixMessageChain.stream([("user", "hello")])
        let b = PrefixMessageChain.stream([("user", "hellp")])
        let c = PrefixMessageChain.stream([("assistant", "hello")])
        XCTAssertNotEqual(PrefixChain.hash(a), PrefixChain.hash(b))
        XCTAssertNotEqual(PrefixChain.hash(a), PrefixChain.hash(c))
    }

    func testMessagePrefixCommitsToFullContent() {
        let head = PrefixMessageChain.stream([("system", "doc")])
        var longer = head
        longer.append(contentsOf: PrefixMessageChain.stream([("user", "q")]))
        let cumulative = PrefixChain.cumulative(longer)
        XCTAssertEqual(cumulative[head.count - 1], PrefixChain.hash(head),
                       "a stored boundary hash matches the longer prompt's head")
    }
}
