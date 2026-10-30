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
/// This ledger makes injection a deterministic function of (scope, user text):
/// the first render freezes the block, every later render replays those exact
/// bytes, and a turn first rendered without context never gets one afterwards —
/// that is what the engine already committed. Retrieval still refreshes on every
/// NEW question. The frozen resolution travels into settlement too, so a settled
/// turn always declares the retrieval its prompt was actually built from, never
/// a fresher one it never saw.
///
/// Authoritative rows are untouched: the stored chat line keeps the un-augmented
/// user text, and a process restart legitimately costs one rebuild because
/// persisted KV must never be a continuity requirement.
nonisolated public final class SimiGoISContextLedger: @unchecked Sendable {

    public static let shared = SimiGoISContextLedger()

    /// FIFO bound. A snapshot that leaves the ledger stops being replayed, which
    /// costs that one turn a prefill; it never renders wrong content.
    static let capacity = 512

    /// A rendered turn: the exact bytes injected plus the retrieval they came
    /// from, so the settlement can claim the same sources the model saw.
    public struct Snapshot: Sendable {
        public let block: String
        public let resolution: SimiGoInformationLoop.Resolution
        /// This render replayed a snapshot frozen by an earlier turn.
        public let isReplay: Bool
        /// Today's retrieval would have injected something different, so the
        /// rendered context is stale by design in order to keep the prefix.
        public let candidateChanged: Bool

        public init(
            block: String, resolution: SimiGoInformationLoop.Resolution,
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
        let resolution: SimiGoInformationLoop.Resolution
    }

    private let lock = NSLock()
    /// Insertion order, oldest first, as "<scope>\u{1}<userText>".
    private var order: [String] = []
    private var frozen: [String: [String: Frozen]] = [:]

    public init() {}

    /// Freeze this turn's retrieval on first sight, or return what was frozen
    /// then. The empty block is a legitimate snapshot: a question first rendered
    /// without context must keep being rendered without context.
    @discardableResult
    public func stabilize(
        scope: String,
        userText: String,
        block: String,
        resolution: SimiGoInformationLoop.Resolution
    ) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        if let held = frozen[scope]?[userText] {
            return Snapshot(
                block: held.block, resolution: held.resolution,
                isReplay: true, candidateChanged: held.block != block)
        }
        insert(Frozen(block: block, resolution: resolution), scope: scope, userText: userText)
        return Snapshot(
            block: block, resolution: resolution, isReplay: false, candidateChanged: false)
    }

    /// The block committed when this user turn was first rendered in `scope`, or
    /// nil when it never was — then the message must be sent unmodified.
    public func frozenBlock(scope: String, userText: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return frozen[scope]?[userText]?.block
    }

    /// Test seam: how many (scope, userText) snapshots are held.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frozen.values.reduce(0) { $0 + $1.count }
    }

    private func insert(
        _ value: Frozen, scope: String, userText: String
    ) {
        if order.count >= Self.capacity, let oldest = order.first {
            let split = oldest.split(
                separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
            if split.count == 2 {
                frozen[String(split[0])]?.removeValue(forKey: String(split[1]))
                if frozen[String(split[0])]?.isEmpty == true {
                    frozen.removeValue(forKey: String(split[0]))
                }
            }
            order.removeFirst()
        }
        frozen[scope, default: [:]][userText] = value
        order.append("\(scope)\u{1}\(userText)")
    }
}
