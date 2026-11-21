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
/// user text, and a process restart legitimately costs one rebuild because
/// persisted KV must never be a continuity requirement.
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
    /// Insertion order, oldest first, keyed by (scope, message index).
    private var order: [SlotKey] = []
    private var frozen: [String: [Int: Frozen]] = [:]

    public init() {}

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
        insert(
            Frozen(block: block, resolution: resolution, text: userText),
            scope: scope, index: index)
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
        insert(
            Frozen(block: block, resolution: resolution, text: userText),
            scope: scope, index: index)
        return Snapshot(
            block: block, resolution: resolution, isReplay: false, candidateChanged: false)
    }

    /// The block committed for THIS occurrence, or nil when this exact
    /// (scope, index, text) was never rendered — then the message must be sent
    /// unmodified. Same text at another index is a different occurrence.
    public func frozenBlock(scope: String, userText: String, index: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let held = frozen[scope]?[index], held.text == userText else { return nil }
        return held.block
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
}
