import Foundation
import CryptoKit

/// PrefixPool (Route B, SIMIGO17_PREFIX_POOL gate) — content-addressed
/// shared store of Execution State prefix representations for the daily
/// small-model path.
///
/// Principle (E-line): logical states consume physical representations by
/// CONTENT, not by identity. A new session admits the longest stored
/// prefix whose content provably equals its own prompt prefix, and pays
/// only the delta — instead of cold-recomputing the whole context.
///
/// Layering: this type is ZERO-MLX. Artifacts are opaque handles; the
/// KV snapshot adapter (ChatSession.saveCache/loadCache wiring) lives in
/// B-2. The pool never interprets artifact payloads.
///
/// P-I1 (bind correctness, the I-L3 lesson): a stored entry's boundary
/// hash is a CLAIM about content. Admission recomputes the chain hash
/// over the caller's actual tokens and admits only on equality — a hit
/// cannot mis-describe the prefix. The loud-failure half (artifact load
/// must fail, never silently continue, when the snapshot's internal
/// token count disagrees with the entry) is enforced by the B-2 adapter.
public struct PrefixPoolNamespace: Equatable, Hashable, Sendable {
    public let modelID: String
    public let kvFingerprint: String

    public init(modelID: String, kvFingerprint: String) {
        self.modelID = modelID
        self.kvFingerprint = kvFingerprint
    }
}

/// Message-sequence encoding for the daily (ChatSession) path. The pool
/// hashes an Int stream; the product's natural content unit is the
/// conversation message. Encoding: two Ints per message (low/high halves
/// of an FNV-1a fold over "role\u{1f}content" UTF-8) — 1:1, deterministic
/// across restarts, order-sensitive, so a covered boundary commits to the
/// exact message prefix.
///
/// Why messages, not tokenizer ids: on the ChatSession path the rendered
/// token stream does not exist before generation (the engine tokenizes
/// internally). Message-level equality is sound for pool hits — identical
/// message prefixes render to identical token prefixes under the same
/// tokenizer + template, so a hit's KV snapshot IS the exact prefix of
/// what would otherwise be recomputed. Template-affecting config (e.g.
/// thinking flag) must ride in the namespace, not here.
public enum PrefixMessageChain {
    /// Preserve all 256 bits; length-prefix each field so separators in user
    /// content cannot make distinct (role, content) pairs ambiguous.
    public static func messageHash(role: String, content: String) -> [Int] {
        var data = Data("simigo-prefix-message-v1".utf8)
        appendField(role, to: &data)
        appendField(content, to: &data)
        let bytes = Array(SHA256.hash(data: data))
        return stride(from: 0, to: bytes.count, by: 8).map { offset in
            var word: UInt64 = 0
            for byte in bytes[offset..<(offset + 8)] {
                word = (word << 8) | UInt64(byte)
            }
            return Int(truncatingIfNeeded: word)
        }
    }

    private static func appendField(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(contentsOf: bytes)
    }

    /// Four Int elements per message carry the entire SHA-256 commitment.
    public static func stream(_ messages: [(role: String, content: String)]) -> [Int] {
        messages.flatMap { messageHash(role: $0.role, content: $0.content) }
    }
}

/// Opaque handle to the representation artifact (KV snapshot). Zero-MLX:
/// the pool counts tokens and orders recency; what the artifact points
/// at is the adapter's business.
public protocol PrefixArtifactHandle: Sendable {
    /// Physical artifact size when the adapter can provide it. Unknown sizes
    /// are exempt from the byte budget; disk artifacts always report one.
    var physicalByteCount: Int? { get }
    /// Stable identity for one physical artifact generation. Nil is suitable
    /// for in-memory or opaque handles without independently deletable files.
    var replacementIdentity: String? { get }
}

public extension PrefixArtifactHandle {
    var physicalByteCount: Int? { nil }
    var replacementIdentity: String? { nil }
}

/// Legacy 64-bit rolling hash retained only as a quick candidate/index value.
public enum PrefixContentDomain: String, Codable, Equatable, Hashable, Sendable {
    case tokenIDs
    case messageSequence
}

/// Rolling hash chain over token ids — order-sensitive candidate identity.
/// chain(L) commits to the ENTIRE prefix tokens[0..<L]: equality at
/// length L is equality of content and order.
public enum PrefixChain {
    public static let seed: UInt64 = 0xcbf29ce484222325

    @inlinable
    public static func fold(_ previous: UInt64, _ token: Int) -> UInt64 {
        var h = previous &* 0x100000001b3 &+ UInt64(truncatingIfNeeded: token)
        h ^= h >> 29
        h &*= 0xbf58476d1ce4e5b9
        h ^= h >> 32
        return h
    }

    /// Cumulative hashes: result[i] = chain over tokens[0...i].
    public static func cumulative(_ tokens: [Int]) -> [UInt64] {
        var h = seed
        return tokens.map { h = fold(h, $0); return h }
    }

    public static func hash(_ tokens: [Int]) -> UInt64 {
        var h = seed
        for t in tokens { h = fold(h, t) }
        return h
    }

    /// Collision-resistant commitment; the old UInt64 is not authorization.
    public static func contentDigest(
        _ tokens: [Int], domain: PrefixContentDomain
    ) -> String {
        var data = Data("simigo-prefix-content-v1".utf8)
        data.append(0)
        data.append(contentsOf: domain.rawValue.utf8)
        data.append(0)
        var count = UInt64(tokens.count).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for token in tokens {
            var encoded = UInt64(bitPattern: Int64(token)).bigEndian
            withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct PrefixPoolEntry: Equatable, Sendable {
    public let namespace: PrefixPoolNamespace
    public let tokenCount: Int
    /// Chain hash over the full prefix — the entry's content claim.
    public let boundaryHash: UInt64
    public let contentDomain: PrefixContentDomain
    public let contentDigest: String
    public let artifact: any PrefixArtifactHandle
    /// Distinguishes successive registrations with identical semantic content.
    /// A delayed failure from an old admission may remove only its own registration.
    let registrationID = UUID()

    public static func == (l: PrefixPoolEntry, r: PrefixPoolEntry) -> Bool {
        l.namespace == r.namespace && l.tokenCount == r.tokenCount
            && l.boundaryHash == r.boundaryHash
            && l.contentDomain == r.contentDomain && l.contentDigest == r.contentDigest
    }
}

public struct PrefixAdmission: Equatable, Sendable {
    public let entry: PrefixPoolEntry
    /// Prompt tokens covered by the admitted representation (delta is
    /// the caller's remaining work: promptTokens[covered...]).
    public let coveredTokens: Int
}

public struct PrefixPoolStats: Equatable, Sendable {
    public var hits = 0
    public var misses = 0
    public var exports = 0
    public var evictions = 0
    public var artifactReplacements = 0
    public init() {}
}

public final class ExecutionStatePrefixPool: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [PrefixPoolEntry] = []
    /// Monotonic recency counter (deterministic; no wall clock).
    /// Recency is scoped per (namespace, boundaryHash): the same token prefix
    /// can be live under two different model/KV namespaces, whose LRU recency
    /// must not collide on a shared slot (a hit in one namespace would keep
    /// the other namespace's identically-hashed entry from ever being evicted,
    /// or evict the wrong one).
    private struct RecencyKey: Hashable {
        let namespace: PrefixPoolNamespace
        let contentDomain: PrefixContentDomain
        let contentDigest: String
    }

    private func recencyKey(for entry: PrefixPoolEntry) -> RecencyKey {
        RecencyKey(
            namespace: entry.namespace, contentDomain: entry.contentDomain,
            contentDigest: entry.contentDigest)
    }

    private var lastUse: [RecencyKey: UInt] = [:]
    private var tick: UInt = 0
    private let tokenBudget: Int
    private let physicalByteBudget: Int?
    /// Eviction persistence (SIMIGO17 P2 closure): invoked for every
    /// evicted entry AFTER the lock is released. The disk-backed store
    /// installs this at construction to delete the artifact — an evicted
    /// representation must neither be re-admitted in this process NOR
    /// resurrected by a restart rescan (eviction is a budget decision
    /// and outlives the process). The callback must not re-enter the
    /// pool.
    public var onEvict: ((PrefixPoolEntry) -> Void)?
    /// Called outside the pool lock when same-content registration replaces
    /// a different physical artifact generation.
    public var onReplace: ((PrefixPoolEntry) -> Void)?
    public private(set) var stats = PrefixPoolStats()

    /// Read-only bounds used by restart recovery to reject artifacts that the
    /// pool would immediately evict or that exceed its configured disk budget.
    public var configuredTokenBudget: Int { tokenBudget }
    public var configuredPhysicalByteBudget: Int? { physicalByteBudget }

    public init(tokenBudget: Int, physicalByteBudget: Int? = nil) {
        precondition(tokenBudget > 0)
        precondition(physicalByteBudget.map { $0 > 0 } ?? true)
        self.tokenBudget = tokenBudget
        self.physicalByteBudget = physicalByteBudget
    }

    // MARK: - Admission (bind)

    /// Longest namespace entry whose content claim provably equals the
    /// incoming prompt's prefix. Chain-hash mismatch is a normal miss
    /// (the entry may serve another prompt) — the entry is NOT removed
    /// here; load-time corruption is the adapter's loud failure (P-I1).
    public func admit(
        namespace: PrefixPoolNamespace, promptTokens: [Int],
        domain: PrefixContentDomain = .tokenIDs
    ) -> PrefixAdmission? {
        lock.lock()
        defer { lock.unlock() }
        guard !entries.isEmpty else {
            stats.misses += 1
            return nil
        }
        let cumulative = PrefixChain.cumulative(promptTokens)
        var best: PrefixPoolEntry?
        for entry in entries where entry.namespace == namespace {
            guard entry.tokenCount <= promptTokens.count else { continue }
            let actual = cumulative[entry.tokenCount - 1]
            guard actual == entry.boundaryHash,
                  entry.contentDomain == domain,
                  PrefixChain.contentDigest(
                    Array(promptTokens[..<entry.tokenCount]), domain: domain
                  ) == entry.contentDigest
            else { continue }
            if best == nil || entry.tokenCount > best!.tokenCount {
                best = entry
            }
        }
        guard let hit = best else {
            stats.misses += 1
            return nil
        }
        tick += 1
        lastUse[recencyKey(for: hit)] = tick
        stats.hits += 1
        return PrefixAdmission(entry: hit, coveredTokens: hit.tokenCount)
    }

    /// Read whether an exact content boundary is still resident in this pool.
    /// This is intentionally observational: it does not update LRU recency or
    /// hit/miss statistics, so callers can validate cached membership without
    /// changing the eviction policy.
    public func contains(
        namespace: PrefixPoolNamespace,
        tokenCount: Int,
        boundaryHash: UInt64,
        domain: PrefixContentDomain = .tokenIDs,
        contentDigest: String? = nil
    ) -> Bool {
        guard tokenCount > 0 else { return false }
        lock.lock()
        defer { lock.unlock() }
        return entries.contains {
            $0.namespace == namespace
                && $0.tokenCount == tokenCount
                && $0.boundaryHash == boundaryHash
                && $0.contentDomain == domain
                && (contentDigest == nil || $0.contentDigest == contentDigest)
        }
    }

    /// Run a non-reentrant side effect while the exact registration is protected
    /// by the pool lock. PrefixSnapshotStore uses this to acquire a physical-use
    /// lease atomically with checking that an admission has not been replaced.
    @discardableResult
    func performIfCurrent(_ entry: PrefixPoolEntry, _ action: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard entries.contains(where: {
            $0 == entry && $0.registrationID == entry.registrationID
        }) else {
            return false
        }
        action()
        return true
    }

    // MARK: - Export (derive/commit)

    /// Register a boundary representation (turn commit). A re-export of
    /// the same content replaces the artifact and refreshes recency; a
    /// different prefix of the same length is a distinct entry (both are
    /// valid content claims). Enforces the token budget (LRU eviction)
    /// before returning.
    @discardableResult
    public func export(
        namespace: PrefixPoolNamespace,
        tokens prefix: [Int],
        domain: PrefixContentDomain = .tokenIDs,
        artifact: any PrefixArtifactHandle
    ) -> PrefixPoolEntry {
        precondition(!prefix.isEmpty)
        lock.lock()
        let hash = PrefixChain.hash(prefix)
        let contentDigest = PrefixChain.contentDigest(prefix, domain: domain)
        let entry = PrefixPoolEntry(
            namespace: namespace, tokenCount: prefix.count,
            boundaryHash: hash, contentDomain: domain,
            contentDigest: contentDigest, artifact: artifact)
        var replaced: PrefixPoolEntry?
        if let index = entries.firstIndex(where: { $0 == entry }) {
            let previous = entries[index]
            if let previousIdentity = previous.artifact.replacementIdentity,
               previousIdentity != artifact.replacementIdentity {
                replaced = previous
            }
            entries[index] = entry
            stats.artifactReplacements += 1
        } else {
            entries.append(entry)
            stats.exports += 1
        }
        tick += 1
        lastUse[recencyKey(for: entry)] = tick
        evictLocked()
        let replace = onReplace
        lock.unlock()
        if let replaced { replace?(replaced) }
        return entry
    }

    /// Drop one entry explicitly (e.g. its artifact load failed loudly in
    /// the adapter — the pool must not hand it out again).
    @discardableResult
    public func remove(_ entry: PrefixPoolEntry) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: {
            $0 == entry && $0.registrationID == entry.registrationID
        }) else {
            return false
        }
        entries.remove(at: index)
        lastUse[recencyKey(for: entry)] = nil
        return true
    }

    /// Remove only the entry whose artifact handle equals ``artifact``, in
    /// addition to matching its semantic content. Content equality alone is
    /// unsafe once a same-content re-export can replace the artifact: a loader
    /// still holding the OLD artifact must not evict the NEW entry that
    /// replaced it. Returns true only when a content- AND artifact-matched
    /// entry was found and dropped.
    @discardableResult
    public func remove<Artifact: Equatable & Sendable>(
        _ entry: PrefixPoolEntry, artifact: Artifact
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { candidate in
            candidate == entry
                && candidate.registrationID == entry.registrationID
                && (candidate.artifact as? Artifact) == artifact
        }) else {
            return false
        }
        entries.remove(at: index)
        lastUse[recencyKey(for: entry)] = nil
        return true
    }

    /// Register an entry from a PRECOMPUTED content claim (restart rescan:
    /// only the chain hash survives on disk, the token array does not).
    /// P-I1 is unaffected — registration is a claim, admission still
    /// recomputes the chain over the caller's live tokens before any hit,
    /// so a corrupt claim can only ever miss, never mis-bind.
    @discardableResult
    public func register(
        namespace: PrefixPoolNamespace,
        tokenCount: Int,
        boundaryHash: UInt64,
        contentDomain: PrefixContentDomain,
        contentDigest: String,
        artifact: any PrefixArtifactHandle
    ) -> PrefixPoolEntry {
        precondition(tokenCount > 0)
        lock.lock()
        let entry = PrefixPoolEntry(
            namespace: namespace, tokenCount: tokenCount,
            boundaryHash: boundaryHash, contentDomain: contentDomain,
            contentDigest: contentDigest, artifact: artifact)
        var replaced: PrefixPoolEntry?
        if let index = entries.firstIndex(where: { $0 == entry }) {
            let previous = entries[index]
            if let previousIdentity = previous.artifact.replacementIdentity,
               previousIdentity != artifact.replacementIdentity {
                replaced = previous
            }
            entries[index] = entry
            stats.artifactReplacements += 1
        } else {
            entries.append(entry)
            stats.exports += 1
        }
        tick += 1
        lastUse[recencyKey(for: entry)] = tick
        evictLocked()
        let replace = onReplace
        lock.unlock()
        if let replaced { replace?(replaced) }
        return entry
    }

    // MARK: - Budget

    public var totalTokens: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.reduce(0) { $0 + $1.tokenCount }
    }

    /// Nil means at least one artifact cannot report its physical cost.
    public var totalPhysicalBytes: Int? {
        lock.lock()
        defer { lock.unlock() }
        return entries.reduce(0) { total, entry in
            total.flatMap { sum in entry.artifact.physicalByteCount.map { sum + $0 } }
        }
    }

    /// LRU eviction until within budget. Called automatically on export;
    /// public for pressure hooks.
    public func evictToBudget() {
        lock.lock()
        defer { lock.unlock() }
        evictLocked()
    }

    private func evictLocked() {
        var total = entries.reduce(0) { $0 + $1.tokenCount }
        var totalBytes = entries.reduce(0) { total, entry in
            total + (entry.artifact.physicalByteCount ?? 0)
        }
        var evicted: [PrefixPoolEntry] = []
        var overByteBudget = physicalByteBudget.map { totalBytes > $0 } ?? false
        while (total > tokenBudget || overByteBudget), let victim = entries.min(
            by: { (lastUse[recencyKey(for: $0)] ?? 0)
                < (lastUse[recencyKey(for: $1)] ?? 0) }
        ) {
            entries.removeAll { $0 == victim }
            lastUse[recencyKey(for: victim)] = nil
            total -= victim.tokenCount
            totalBytes -= victim.artifact.physicalByteCount ?? 0
            overByteBudget = physicalByteBudget.map { totalBytes > $0 } ?? false
            stats.evictions += 1
            evicted.append(victim)
        }
        // P2: deliver eviction notifications OUTSIDE the pool lock (the
        // disk-backed store deletes artifacts there; it must never
        // re-enter the pool from inside this lock).
        if let onEvict, !evicted.isEmpty {
            lock.unlock()
            for victim in evicted { onEvict(victim) }
            lock.lock()
        }
    }
}
