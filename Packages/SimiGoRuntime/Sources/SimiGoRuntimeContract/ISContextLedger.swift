import Foundation

/// Render-side memory of the Information-Space context this server has already
/// committed to an execution scope.
///
/// The engine reuses its KV prefix only while every message it previously
/// rendered stays byte-identical. An injected block mutates a message in the
/// MIDDLE of the client's chain: inside a tool loop the trailing user turn is the
/// same message on every request, and the assistant/tool lines after it are
/// already committed. Re-retrieving a fresh block therefore breaks the prefix
/// once per turn and pays a full cold prefill (measured 2026-10-27, installed
/// build 30, real agent traffic: 19/19 reuse misses, a 56 KB user turn diverging
/// at offset 52303 inside `[Information Space]`, 42–108 s per turn).
///
/// This ledger makes injection a deterministic function of the *occurrence*
/// (scope, message index, user text): the first render freezes that occurrence's
/// block, every later render of the SAME occurrence replays those exact bytes,
/// and a turn first rendered without context never gets one afterwards — that
/// is what the engine already committed. A repeat of the same text at a
/// different index is a different occurrence and gets its own snapshot; replaying
/// one occurrence's block into another was the 2026-11-21 prefix break
/// (`prefixMismatch index=6 stored=86B incoming=3972B`) that forced 35k/62k
/// prompts to cold-prefill. Retrieval still refreshes on every NEW question.
/// The frozen resolution travels into settlement too, so a settled turn always
/// declares the retrieval its prompt was actually built from, never a fresher
/// one it never saw.
///
/// Authoritative rows are untouched: the stored chat line keeps the un-augmented
/// user text. Without a durable store a process restart legitimately costs one
/// rebuild; with one installed (disk-pool research mode, ADR 2026-11-22) the
/// frozen bytes warm-load per occurrence, so the rendered chain survives the
/// restart. Persisted KV must never be a continuity requirement either way.

/// Durable backing for frozen rendering snapshots
/// (ADR_IS_RENDERING_SNAPSHOT_PERSISTENCE_20261122). The ledger stays a warm
/// cache: every first freeze writes through, every memory miss warm-loads.
/// Implemented app-side by ESISDatabase; no store installed = the original
/// pure-memory behavior. Calls are made under the ledger's lock; a thrown
/// error is treated as a miss (fail-open), never as wrong content.
public protocol ISRenderingSnapshotStore {
    func saveRenderSnapshot(
        scope: String, index: Int, userTextSHA256: String,
        block: String, resolutionJSON: String) throws
    func loadRenderSnapshot(
        scope: String, index: Int, userTextSHA256: String)
        throws -> (block: String, resolutionJSON: String)?
}

nonisolated public final class ISContextLedger: @unchecked Sendable {

    public static let shared = ISContextLedger()

    /// FIFO bound. A snapshot that leaves the ledger stops being replayed, which
    /// costs that one turn a prefill; it never renders wrong content.
    static let capacity = 512

    /// A rendered turn: the exact bytes injected plus the retrieval they came
    /// from, so the settlement can claim the same sources the model saw.
    public struct Snapshot: Sendable {
        public let block: String
        public let resolution: InformationLoop.Resolution
        /// This render replayed a snapshot frozen by an earlier turn.
        public let isReplay: Bool
        /// Today's retrieval would have injected something different, so the
        /// rendered context is stale by design in order to keep the prefix.
        public let candidateChanged: Bool

        public init(
            block: String, resolution: InformationLoop.Resolution,
            isReplay: Bool, candidateChanged: Bool
        ) {
            self.block = block
            self.resolution = resolution
            self.isReplay = isReplay
            self.candidateChanged = candidateChanged
        }
    }

    private struct Frozen {
        let block: String
        let resolution: InformationLoop.Resolution
        /// The text this occurrence was rendered with. An index reused with a
        /// different text is a new occurrence, never a replay.
        let text: String
    }

    private struct SlotKey: Equatable {
        let scope: String
        let index: Int
    }

    private let lock = NSLock()
    /// Durable rendering-snapshot backend, injected only in disk-pool research
    /// mode. Guarded by `lock` like the rest of the ledger state.
    private var store: ISRenderingSnapshotStore?
    /// Insertion order, oldest first, keyed by (scope, message index).
    private var order: [SlotKey] = []
    private var frozen: [String: [Int: Frozen]] = [:]

    public init() {}

    /// Install (or remove) the durable backend. The app injects it once when
    /// `RuntimeTuning.prefixPoolEnabled`; the product default installs nothing.
    public func installRenderStore(_ store: ISRenderingSnapshotStore?) {
        lock.lock()
        defer { lock.unlock() }
        self.store = store
    }

    /// Freeze this turn's retrieval on first sight, or return what was frozen
    /// then. The empty block is a legitimate snapshot: a question first rendered
    /// without context must keep being rendered without context.
    @discardableResult
    public func stabilize(
        scope: String,
        userText: String,
        index: Int,
        block: String,
        resolution: InformationLoop.Resolution
    ) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        if let held = frozen[scope]?[index], held.text == userText {
            return Snapshot(
                block: held.block, resolution: held.resolution,
                isReplay: true, candidateChanged: held.block != block)
        }
        if let warm = warmLoad(scope: scope, userText: userText, index: index) {
            return Snapshot(
                block: warm.block, resolution: warm.resolution,
                isReplay: true, candidateChanged: warm.block != block)
        }
        let value = Frozen(block: block, resolution: resolution, text: userText)
        insert(value, scope: scope, index: index)
        writeThrough(value, scope: scope, index: index)
        return Snapshot(
            block: block, resolution: resolution, isReplay: false, candidateChanged: false)
    }

    /// Replace the frozen snapshot for this occurrence (scope, index, userText) with today's
    /// retrieval. Call this when `stabilize` reported `candidateChanged` and the
    /// turn must answer from current information: the rendered block, the
    /// settlement's declared retrieval and the reuse gate all read one fresh
    /// snapshot afterwards, so an exact repeat is served from the replacement
    /// answer instead of regenerating against the stale one forever.
    /// This re-pays one cold prefill for that turn — the bounded cost of
    /// answering from what is actually in the space, versus replaying bytes the
    /// space no longer backs.
    @discardableResult
    public func refresh(
        scope: String,
        userText: String,
        index: Int,
        block: String,
        resolution: InformationLoop.Resolution
    ) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let value = Frozen(block: block, resolution: resolution, text: userText)
        insert(value, scope: scope, index: index)
        writeThrough(value, scope: scope, index: index)
        return Snapshot(
            block: block, resolution: resolution, isReplay: false, candidateChanged: false)
    }

    /// The block committed for THIS occurrence, or nil when this exact
    /// (scope, index, text) was never rendered — then the message must be sent
    /// unmodified. Same text at another index is a different occurrence.
    public func frozenBlock(scope: String, userText: String, index: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let held = frozen[scope]?[index], held.text == userText { return held.block }
        return warmLoad(scope: scope, userText: userText, index: index)?.block
    }

    /// Test seam: how many (scope, index) snapshots are held.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frozen.values.reduce(0) { $0 + $1.count }
    }

    private func insert(
        _ value: Frozen, scope: String, index: Int
    ) {
        let key = SlotKey(scope: scope, index: index)
        if frozen[scope]?[index] != nil {
            // Replacing one occurrence: move it to the newest position without
            // evicting an unrelated slot.
            order.removeAll { $0 == key }
        } else if order.count >= Self.capacity, let oldest = order.first {
            frozen[oldest.scope]?.removeValue(forKey: oldest.index)
            if frozen[oldest.scope]?.isEmpty == true {
                frozen.removeValue(forKey: oldest.scope)
            }
            order.removeFirst()
        }
        frozen[scope, default: [:]][index] = value
        order.append(key)
    }

    /// Caller holds `lock`. The durable row for THIS occurrence, decoded and
    /// re-inserted into memory, or nil (no store / no row / corrupt row).
    /// Fail-open: any failure falls back to a fresh render, never wrong bytes.
    private func warmLoad(scope: String, userText: String, index: Int) -> Frozen? {
        guard let store else { return nil }
        let sha = NativeSHA256.hexDigest(Data(userText.utf8))
        guard let row = try? store.loadRenderSnapshot(
                scope: scope, index: index, userTextSHA256: sha),
            let resolution = try? JSONDecoder().decode(
                InformationLoop.Resolution.self, from: Data(row.resolutionJSON.utf8))
        else { return nil }
        let held = Frozen(block: row.block, resolution: resolution, text: userText)
        insert(held, scope: scope, index: index)
        return held
    }

    /// Caller holds `lock`. Persist the just-frozen bytes verbatim. Errors are
    /// swallowed: the durable row is an optimization, the memory slot already
    /// holds the truth for this process.
    private func writeThrough(_ value: Frozen, scope: String, index: Int) {
        guard let store,
            let json = try? JSONEncoder().encode(value.resolution),
            let text = String(data: json, encoding: .utf8)
        else { return }
        try? store.saveRenderSnapshot(
            scope: scope, index: index,
            userTextSHA256: NativeSHA256.hexDigest(Data(value.text.utf8)),
            block: value.block, resolutionJSON: text)
    }

    // MARK: - Settled digest chain (render-side memory, fail-open to IS)

    /// FIFO bound on sessions held. A session that leaves stops being fed from
    /// memory and costs one IS read to rebuild; it never renders wrong content.
    /// ponytail: FIFO by session first-seen (same shape as the frozen-block
    /// ledger); per-session LRU if a long-lived session ever churns out.
    static let digestSessionCapacity = 64

    private var digestOrder: [String] = []
    private var digestChains: [String: [Int: String]] = [:]

    /// Remember a settled turn's digest. Last write wins, matching the durable
    /// overwrite semantics (a re-digest of the same turn replaces the row).
    /// Called by the formation funnel after the row lands, so memory is always
    /// a subset of the durable digest rows.
    public func rememberDigest(scope: String, turnIndex: Int, digest: String) {
        lock.lock()
        defer { lock.unlock() }
        if digestChains[scope] == nil {
            if digestOrder.count >= Self.digestSessionCapacity, let oldest = digestOrder.first {
                digestChains.removeValue(forKey: oldest)
                digestOrder.removeFirst()
            }
            digestOrder.append(scope)
        }
        digestChains[scope, default: [:]][turnIndex] = digest
    }

    /// The digests held for this scope (turnIndex → digest), empty when none.
    /// The caller validates coverage/contiguity against the durable ledger
    /// before substituting; a gap fails open to the IS read.
    public func digestChain(scope: String) -> [Int: String] {
        lock.lock()
        defer { lock.unlock() }
        return digestChains[scope] ?? [:]
    }
}
