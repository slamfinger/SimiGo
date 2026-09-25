import Foundation
import SimiGoRuntimeContract

/// The Controller/Materializer boundary is the `ResidencyMaterializer`
/// contract (SimiGoRuntimeContract target). This file MUST stay free of
/// MLX imports: the Controller depends on the Runtime Contract, and MLX
/// enters only behind the concrete Backend implementation (B3).

/// Cooperative cancellation checked at group boundaries (R3.15: a group is
/// either fully transferred or not started; cancellation never splits one).
public struct ResidencyCancellationToken: Sendable {
    private let check: (@Sendable () -> Bool)?

    public static let none = ResidencyCancellationToken { false }

    public init(check: @escaping @Sendable () -> Bool) {
        self.check = check
    }

    public var isCancelled: Bool { check?() ?? false }
}

public enum ResidencyControllerError: Error, Equatable, Sendable {
    /// Resident state is DIRTY: plans are refused until recovery (R3.6).
    case dirty
    /// The required set does not fit the budget. Failed before any transfer
    /// (R3.11); the reported plan carries the overflow details.
    case requiredOverflow(ResidencyPlan)
    case loadFailed(groupID: String)
    case evictFailed(groupID: String)
}

public struct ResidencyAdmissionOutcome: Equatable, Sendable {
    public let plan: ResidencyPlan
    /// True when the cancellation token fired before every planned group
    /// completed; committed groups remain resident (R3.15–R3.16).
    public let cancelled: Bool
}

/// The runtime residency controller: the single writer of resident state
/// (R2.1/R3.4). Owns plan admission, per-group transfer commit, the
/// transfer log, DIRTY semantics, reconciliation, and cancellation.
///
/// Commit protocol per group: the materializer executes the real effect
/// first; only on success does the controller commit the transfer through
/// the state machine (log + bookkeeping). Failures reduce to
/// loadFailed/evictFailed events — eviction failure enters DIRTY (R3.13).
///
/// Single-writer note (R3.18): all mutations serialize through the
/// controller; the host MUST drive it from one serialized context (actor or
/// queue wrapper is a hosting decision).
public final class ResidencyController: @unchecked Sendable {
    public let inventory: LayerInventory
    private let planner: ExecutionResidencyPlanner
    private let materializer: any ResidencyMaterializer
    private let machine: ResidencyStateMachine
    private let initialBookkeeping: ResidencyBookkeeping

    public init(
        inventory: LayerInventory,
        materializer: any ResidencyMaterializer,
        initialResidentGroupIDs: Set<String>? = nil
    ) {
        self.inventory = inventory
        self.planner = ExecutionResidencyPlanner(inventory: inventory)
        self.materializer = materializer
        let core = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        let initial = ResidencyBookkeeping(
            residentGroupIDs: initialResidentGroupIDs ?? core
        )
        self.initialBookkeeping = initial
        self.machine = ResidencyStateMachine(initialBookkeeping: initial)
    }

    // MARK: - Observed state

    public var state: ResidencyControllerState { machine.state }

    public var residentGroupIDs: Set<String> { machine.bookkeeping.residentGroupIDs }

    public var residentBytes: Int64 {
        let lookup = Dictionary(uniqueKeysWithValues: inventory.groups.map { ($0.id, $0.byteCount) })
        return residentGroupIDs.reduce(Int64(0)) { $0 + (lookup[$1] ?? 0) }
    }

    public var transferLog: ResidencyTransferLog { machine.transferLog }

    /// INV-1 audit: replay the transfer log over the initial state. MUST
    /// equal `residentGroupIDs` at any point.
    public func auditReplay() -> ResidencyBookkeeping {
        machine.transferLog.replay(initial: initialBookkeeping)
    }

    // MARK: - Admission

    /// Plans against the current resident state and executes the plan.
    /// Hints are intentionally absent (R1.4): the controller never supplies
    /// ordering signals. Required-set overflow fails fast before any
    /// transfer (R3.11).
    @discardableResult
    public func admit(
        requiredGroupIDs: Set<String>,
        budget: ResidencyBudgetPolicy,
        cancellationToken: ResidencyCancellationToken = .none
    ) throws -> ResidencyAdmissionOutcome {
        let admission = machine.reduce(.planAdmission(requiredGroupIDs: requiredGroupIDs))
        guard admission.effect == .admissionAccepted else {
            throw ResidencyControllerError.dirty
        }

        let plan = try planner.plan(
            currentResidentGroupIDs: residentGroupIDs,
            requiredGroupIDs: requiredGroupIDs,
            demandHints: [],
            budget: budget,
            recommendedBytes: inventory.totalByteCount
        )

        guard plan.fitsBudget else {
            throw ResidencyControllerError.requiredOverflow(plan)
        }

        var cancelled = false

        for groupID in plan.loadGroupIDs.sorted() {
            if cancellationToken.isCancelled {
                cancelled = true
                break
            }
            do {
                try materializer.materialize(groupID: groupID)
            } catch {
                machine.reduce(.loadFailed(groupID: groupID, reason: String(describing: error)))
                throw ResidencyControllerError.loadFailed(groupID: groupID)
            }
            machine.reduce(.loadCommitted(groupID: groupID))
        }

        for groupID in plan.evictGroupIDs.sorted() {
            if cancellationToken.isCancelled {
                cancelled = true
                break
            }
            do {
                try materializer.release(groupID: groupID)
            } catch {
                machine.reduce(.evictFailed(groupID: groupID, reason: String(describing: error)))
                throw ResidencyControllerError.evictFailed(groupID: groupID)
            }
            machine.reduce(.evictCommitted(groupID: groupID))
        }

        return ResidencyAdmissionOutcome(plan: plan, cancelled: cancelled)
    }

    // MARK: - Reconciliation and recovery

    /// Byte reconciliation (R3.5/INV-3): compares the observed runtime idle
    /// bytes against residentBytes + C_model within ε. A mismatch enters
    /// DIRTY; a match in DIRTY still requires explicit recovery.
    @discardableResult
    public func reconcile(
        observedIdleBytes: Int64,
        cModelBytes: Int64 = 0,
        epsilonBytes: Int64
    ) -> Bool {
        let expected = residentBytes + cModelBytes
        let deviation = abs(observedIdleBytes - expected)
        if deviation <= epsilonBytes {
            machine.reduce(.auditMatched)
            return true
        }
        machine.reduce(.auditMismatch(expectedBytes: expected, observedBytes: observedIdleBytes))
        return false
    }

    /// Exits DIRTY. The host MUST have restored consistency (re-snapshot or
    /// full re-materialization pass) before calling; the bookkeeping is
    /// rebuilt from the transfer log over the initial state (R3.6).
    public func recover() {
        machine.reduce(.recover)
    }
}
