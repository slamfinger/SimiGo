import Foundation
import SimiGoRuntimeContract

/// Token Ledger (review-approved gate) — append-only record of confirmed
/// token-prefix facts per Execution State.
///
/// Ownership: conceptually the Execution State representation layer (the
/// prefix IS the physical representation; the ledger is its token-level
/// view); the CURRENT implementation owner is the OversizedSegmentedEngine
/// (engine-side representation audit structure — sinking it into the
/// backend abstraction is deferred until that abstraction stabilizes).
/// Positions remain Coordinator-owned. Boundaries: NOT a KV record, NOT
/// usage, NOT a position source, NOT a transcript.
///
/// Invariants:
///   I-L1 committed-only — entries exist only for committed transitions
///        (bootstrap + successful turns); failed turns append nothing
///   I-L2 strictly increasing prefixLength within a segment (a restore
///        marker resets the growth point; the superseded tail is retained
///        and flagged)
///   I-L3 entry prefixLength == backend bound-prefix length at that
///        position — ENFORCED at append: every entry is cross-checked
///        against the backend's own binding record through the authority
///        closure; a mismatch (wrong length, missing binding, or binding
///        at another position) throws divergence-class and the entry is
///        never recorded
public struct OversizedTokenLedgerEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bootstrap
        case turn
        case restoreMarker
    }

    public let executionID: ExecutionID
    public let position: Int
    public let kind: Kind
    public let prefixLength: Int
    public let superseded: Bool

    init(
        executionID: ExecutionID,
        position: Int,
        kind: Kind,
        prefixLength: Int,
        superseded: Bool = false
    ) {
        self.executionID = executionID
        self.position = position
        self.kind = kind
        self.prefixLength = prefixLength
        self.superseded = superseded
    }
}

public final class OversizedTokenLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [OversizedTokenLedgerEntry] = []
    /// Last committed position per execution — drives I-L2 validation.
    private var lastCommittedPosition: [ExecutionID: Int] = [:]
    /// I-L3 authority — the backend's own binding record, queried per
    /// append. Required (never optional): a ledger that can skip the
    /// cross-check is the gap this gate exists to close.
    private let boundPrefixLength: (ExecutionID, Int) throws -> Int

    public init(
        boundPrefixLength: @escaping (ExecutionID, Int) throws -> Int
    ) {
        self.boundPrefixLength = boundPrefixLength
    }

    /// Append a committed entry. Validates per-execution ordering: turn and
    /// bootstrap entries must move strictly forward from the current growth
    /// point; a restore marker records the rollback/resume point and may move
    /// the growth point to any coordinator-valid position — rewind OR forward
    /// resume of a previously superseded position. Every entry is first
    /// cross-checked against the backend's binding record (I-L3); a mismatch
    /// throws and the entry is never recorded. Position ordering defense in
    /// depth: the coordinator already gates restore targets on representation
    /// existence, so the ledger bound is the furthest-ever committed
    /// position (I-L2).
    public func append(_ entry: OversizedTokenLedgerEntry) throws {
        lock.lock()
        defer { lock.unlock() }

        let backendLength: Int
        do {
            backendLength = try boundPrefixLength(entry.executionID, entry.position)
        } catch {
            throw OversizedEngineError.residencyDivergence(
                "token ledger: I-L3 no backend binding at position \(entry.position) "
                    + "for \(entry.executionID) (\(error))")
        }
        guard entry.prefixLength == backendLength else {
            throw OversizedEngineError.residencyDivergence(
                "token ledger: I-L3 prefix mismatch at position \(entry.position) for "
                    + "\(entry.executionID) (entry claims \(entry.prefixLength), "
                    + "backend bound \(backendLength))")
        }

        if entry.kind == .restoreMarker {
            let furthest = entries
                .filter { $0.executionID == entry.executionID }
                .max(by: { $0.position < $1.position })?.position
            if let furthest {
                guard entry.position <= furthest else {
                    throw OversizedEngineError.residencyDivergence(
                        "token ledger: restore marker beyond committed history for "
                            + "\(entry.executionID) (\(entry.position) > \(furthest))"
                    )
                }
            }
        } else if let growth = lastCommittedPosition[entry.executionID] {
            guard entry.position > growth else {
                throw OversizedEngineError.residencyDivergence(
                    "token ledger: non-increasing position for \(entry.executionID) "
                        + "(\(growth) -> \(entry.position))"
                )
            }
        }
        lastCommittedPosition[entry.executionID] = entry.position
        entries.append(entry)
    }

    /// Flag entries beyond `position` for `executionID` as superseded
    /// (retained for audit; excluded from the active chain).
    public func markSuperseded(beyond position: Int, executionID: ExecutionID) {
        lock.lock()
        defer { lock.unlock() }
        for index in entries.indices where entries[index].executionID == executionID {
            if entries[index].position > position, !entries[index].superseded {
                entries[index] = OversizedTokenLedgerEntry(
                    executionID: entries[index].executionID,
                    position: entries[index].position,
                    kind: entries[index].kind,
                    prefixLength: entries[index].prefixLength,
                    superseded: true
                )
            }
        }
    }

    public func allEntries() -> [OversizedTokenLedgerEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func entries(for executionID: ExecutionID) -> [OversizedTokenLedgerEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.executionID == executionID }
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}
