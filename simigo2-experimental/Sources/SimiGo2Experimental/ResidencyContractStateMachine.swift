import Foundation

/// Minimal pure state and event model for Runtime Residency contract verification.
///
/// This is a verification skeleton only. It does not execute materialization,
/// touch MLX, own runtime concurrency, or implement a controller.
public struct ResidencyBookkeeping: Equatable, Sendable {
    public private(set) var residentGroupIDs: Set<String>

    public init(residentGroupIDs: Set<String> = []) {
        self.residentGroupIDs = residentGroupIDs
    }

    public mutating func apply(_ transfer: ResidencyTransfer) {
        switch transfer {
        case .load(let groupID):
            residentGroupIDs.insert(groupID)
        case .evict(let groupID):
            residentGroupIDs.remove(groupID)
        }
    }
}

public enum ResidencyTransfer: Equatable, Sendable {
    case load(groupID: String)
    case evict(groupID: String)
}

/// Append-only transfer audit trail. Replay is the authoritative verification
/// operation for INV-1; it is deliberately independent of a future controller.
public final class ResidencyTransferLog: @unchecked Sendable {
    private var entries: [ResidencyTransfer]

    public init(_ entries: [ResidencyTransfer] = []) {
        self.entries = entries
    }

    public var count: Int { entries.count }

    public func append(_ transfer: ResidencyTransfer) {
        entries.append(transfer)
    }

    @discardableResult
    public func appendAndApply(
        _ transfer: ResidencyTransfer,
        to bookkeeping: ResidencyBookkeeping
    ) -> ResidencyBookkeeping {
        append(transfer)
        var next = bookkeeping
        next.apply(transfer)
        return next
    }

    public func prefix(_ count: Int) -> ResidencyTransferLog {
        ResidencyTransferLog(Array(entries.prefix(count)))
    }

    public func replay(
        initial: ResidencyBookkeeping,
        through index: Int? = nil
    ) -> ResidencyBookkeeping {
        var result = initial
        let end = index.map { min($0 + 1, entries.count) } ?? entries.count
        guard end > 0 else { return result }

        for transfer in entries.prefix(end) {
            result.apply(transfer)
        }
        return result
    }
}

public enum ResidencyControllerState: Equatable, Sendable {
    case clean
    case dirty
}

public enum ResidencyStateMachineEvent: Equatable, Sendable {
    case planAdmission(requiredGroupIDs: Set<String>)
    case loadCommitted(groupID: String)
    case loadFailed(groupID: String, reason: String)
    case evictCommitted(groupID: String)
    case evictFailed(groupID: String, reason: String)
    case auditMatched
    case auditMismatch(expectedBytes: Int64, observedBytes: Int64)
    case recover
    case cancelled(operationID: String)
}

public enum ResidencyStateMachineEffect: Equatable, Sendable {
    case admissionAccepted
    case admissionRejectedDirty
    case enteredDirty
    case transferCommitted
    case transferRejected
    case auditAccepted
    case recoverRequired
    case recovered
    case cancelled
}

public struct ResidencyStateMachineResult: Equatable, Sendable {
    public let state: ResidencyControllerState
    public let effect: ResidencyStateMachineEffect

    public init(
        state: ResidencyControllerState,
        effect: ResidencyStateMachineEffect
    ) {
        self.state = state
        self.effect = effect
    }
}

/// Deterministic state-machine skeleton for L2 verification.
///
/// Invariants represented here:
/// - DIRTY is entered only by eviction failure or audit mismatch.
/// - DIRTY rejects plan admission.
/// - DIRTY can leave only through explicit recovery.
/// - ordinary load failure/cancellation do not silently poison bookkeeping.
///
/// Transfer execution remains outside this type.
public final class ResidencyStateMachine: @unchecked Sendable {
    public private(set) var state: ResidencyControllerState = .clean
    public private(set) var bookkeeping: ResidencyBookkeeping
    public let transferLog: ResidencyTransferLog
    private let initialBookkeeping: ResidencyBookkeeping

    public init(
        initialBookkeeping: ResidencyBookkeeping = ResidencyBookkeeping(),
        transferLog: ResidencyTransferLog = ResidencyTransferLog()
    ) {
        self.initialBookkeeping = initialBookkeeping
        self.bookkeeping = initialBookkeeping
        self.transferLog = transferLog
        self.bookkeeping = transferLog.replay(initial: initialBookkeeping)
    }

    @discardableResult
    public func reduce(
        _ event: ResidencyStateMachineEvent
    ) -> ResidencyStateMachineResult {
        switch event {
        case .planAdmission:
            guard state == .clean else {
                return .init(state: state, effect: .admissionRejectedDirty)
            }
            return .init(state: state, effect: .admissionAccepted)

        case .loadCommitted(let groupID):
            guard state == .clean else {
                return .init(state: state, effect: .transferRejected)
            }
            let transfer = ResidencyTransfer.load(groupID: groupID)
            bookkeeping = transferLog.appendAndApply(transfer, to: bookkeeping)
            return .init(state: state, effect: .transferCommitted)

        case .evictCommitted(let groupID):
            guard state == .clean else {
                return .init(state: state, effect: .transferRejected)
            }
            let transfer = ResidencyTransfer.evict(groupID: groupID)
            bookkeeping = transferLog.appendAndApply(transfer, to: bookkeeping)
            return .init(state: state, effect: .transferCommitted)

        case .loadFailed:
            return .init(state: state, effect: .transferRejected)

        case .evictFailed:
            if state == .clean {
                state = .dirty
                return .init(state: state, effect: .enteredDirty)
            }
            return .init(state: state, effect: .enteredDirty)

        case .auditMatched:
            guard state == .clean else {
                return .init(state: state, effect: .recoverRequired)
            }
            return .init(state: state, effect: .auditAccepted)

        case .auditMismatch:
            state = .dirty
            return .init(state: state, effect: .enteredDirty)

        case .recover:
            guard state == .dirty else {
                return .init(state: state, effect: .recoverRequired)
            }
            state = .clean
            bookkeeping = transferLog.replay(initial: initialBookkeeping)
            return .init(state: state, effect: .recovered)

        case .cancelled:
            return .init(state: state, effect: .cancelled)
        }
    }
}
