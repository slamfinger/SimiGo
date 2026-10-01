import Foundation

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
    public static func messageHash(role: String, content: String) -> UInt64 {
        var h = PrefixChain.seed
        for byte in (role + "\u{1f}" + content).utf8 {
            h = PrefixChain.fold(h, Int(byte))
        }
        return h
    }

    /// Two stream elements per message — tokenCount / 2 = message count.
    public static func stream(_ messages: [(role: String, content: String)]) -> [Int] {
        messages.flatMap { message -> [Int] in
            let h = messageHash(role: message.role, content: message.content)
            return [Int(truncatingIfNeeded: h), Int(truncatingIfNeeded: h >> 32)]
        }
    }
}

/// Opaque handle to the representation artifact (KV snapshot). Zero-MLX:
/// the pool counts tokens and orders recency; what the artifact points
/// at is the adapter's business.
public protocol PrefixArtifactHandle: Sendable {
    /// Physical artifact size when the adapter can provide it. Unknown sizes
    /// are exempt from the byte budget; disk artifacts always report one.
    var physicalByteCount: Int? { get }
}

public extension PrefixArtifactHandle {
    var physicalByteCount: Int? { nil }
}

/// Rolling hash chain over token ids — order-sensitive content identity.
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
}

public struct PrefixPoolEntry: Equatable, Sendable {
    public let namespace: PrefixPoolNamespace
    public let tokenCount: Int
    /// Chain hash over the full prefix — the entry's content claim.
    public let boundaryHash: UInt64
    public let artifact: any PrefixArtifactHandle

    public static func == (l: PrefixPoolEntry, r: PrefixPoolEntry) -> Bool {
        l.namespace == r.namespace && l.tokenCount == r.tokenCount
            && l.boundaryHash == r.boundaryHash
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
    private var lastUse: [UInt64: UInt] = [:]
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
    public private(set) var stats = PrefixPoolStats()

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
        namespace: PrefixPoolNamespace, promptTokens: [Int]
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
            guard actual == entry.boundaryHash else { continue }
            if best == nil || entry.tokenCount > best!.tokenCount {
                best = entry
            }
        }
        guard let hit = best else {
            stats.misses += 1
            return nil
        }
        tick += 1
        lastUse[hit.boundaryHash] = tick
        stats.hits += 1
        return PrefixAdmission(entry: hit, coveredTokens: hit.tokenCount)
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
        artifact: any PrefixArtifactHandle
    ) -> PrefixPoolEntry {
        precondition(!prefix.isEmpty)
        lock.lock()
        defer { lock.unlock() }
        let hash = PrefixChain.hash(prefix)
        let entry = PrefixPoolEntry(
            namespace: namespace, tokenCount: prefix.count,
            boundaryHash: hash, artifact: artifact)
        if let index = entries.firstIndex(where: { $0 == entry }) {
            entries[index] = entry
            stats.artifactReplacements += 1
        } else {
            entries.append(entry)
            stats.exports += 1
        }
        tick += 1
        lastUse[hash] = tick
        evictLocked()
        return entry
    }

    /// Drop one entry explicitly (e.g. its artifact load failed loudly in
    /// the adapter — the pool must not hand it out again).
    @discardableResult
    public func remove(_ entry: PrefixPoolEntry) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0 == entry }) else {
            return false
        }
        entries.remove(at: index)
        lastUse[entry.boundaryHash] = nil
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
        artifact: any PrefixArtifactHandle
    ) -> PrefixPoolEntry {
        precondition(tokenCount > 0)
        lock.lock()
        defer { lock.unlock() }
        let entry = PrefixPoolEntry(
            namespace: namespace, tokenCount: tokenCount,
            boundaryHash: boundaryHash, artifact: artifact)
        if let index = entries.firstIndex(where: { $0 == entry }) {
            entries[index] = entry
            stats.artifactReplacements += 1
        } else {
            entries.append(entry)
            stats.exports += 1
        }
        tick += 1
        lastUse[entry.boundaryHash] = tick
        evictLocked()
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
            by: { (lastUse[$0.boundaryHash] ?? 0) < (lastUse[$1.boundaryHash] ?? 0) }
        ) {
            entries.removeAll { $0 == victim }
            lastUse[victim.boundaryHash] = nil
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
