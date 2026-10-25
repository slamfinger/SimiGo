import Foundation
import SimiGoRuntimeContract

/// The Controller/Materializer boundary is the `ResidencyMaterializer`
/// contract (SimiGoRuntimeContract target). This file MUST stay free of
/// MLX imports: the Controller depends on the Runtime Contract, and MLX
/// enters only behind the concrete Backend implementation (L4-A).
public enum ResidencyControllerError: Error, Equatable, Sendable {
    /// Resident state is DIRTY: plans are refused until recovery (R3.6).
    case dirty
    /// An admission is already in flight; the serialized mutation stream
    /// (R3.18) rejects overlapping mutations. The host retries.
    case admissionInFlight
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
    /// Non-nil when the admission holds a residency window (R3.20): the
    /// required set stays protected from eviction until the host closes the
    /// window via `closeResidencyWindow(_:)`.
    public let requestID: UUID?
}

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

/// The runtime residency controller: the single writer of resident state
/// (R2.1/R3.4). Owns plan admission, per-group transfer commit, the
/// transfer log, DIRTY semantics, reconciliation, and cancellation.
///
/// Commit protocol per group: the materializer executes the real effect
/// first; only on success does the controller commit the transfer through
/// the state machine (log + bookkeeping). Failures reduce to
/// loadFailed/evictFailed events — eviction failure enters DIRTY (R3.13).
///
/// Serialization (R3.18): admissions and pressure responses serialize
/// through an async FIFO lock — admission order is preserved and an
/// admission runs to completion or failure as a whole (R2.2) across the
/// materializer's await points. The synchronous reconciliation/recovery
/// operations reject with `.admissionInFlight` while an admission is
/// suspended rather than observing intermediate state.
public final class ResidencyController: @unchecked Sendable {
    public let inventory: LayerInventory
    private let planner: ExecutionResidencyPlanner
    private let materializer: any ResidencyMaterializer
    private let machine: ResidencyStateMachine
    private let initialBookkeeping: ResidencyBookkeeping
    /// R3.18: FIFO async serialization for materializer-driving mutations.
    private let admissionLock = AsyncLock()
    /// Guards the synchronous operations (reconcile/recover) and the
    /// in-flight flag against the admission path.
    private let stateLock = NSLock()
    private var admissionInFlight = false
    /// R3.20: open residency windows for concurrently admitted requests.
    /// A windowed request's required set is protected from eviction for the
    /// whole execution window; the host closes the window when its execution
    /// finishes.
    private var residencyWindows: [UUID: Set<String>] = [:]

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
    ///
    /// With `holdsResidencyWindow: true` (R3.20) the admission opens a
    /// residency window: its required set is unioned into every subsequent
    /// admission's effective required set (and protected from pressure
    /// eviction) until the host closes the window via
    /// `closeResidencyWindow(_:)` with the returned requestID.
    @discardableResult
    public func admit(
        requiredGroupIDs: Set<String>,
        budget: ResidencyBudgetPolicy,
        holdsResidencyWindow: Bool = false,
        cancellationToken: ResidencyCancellationToken = .none
    ) async throws -> ResidencyAdmissionOutcome {
        await admissionLock.lock()
        defer { admissionLock.unlock() }

        stateLock.withLock { admissionInFlight = true }
        defer {
            stateLock.withLock { admissionInFlight = false }
        }

        let admission = machine.reduce(.planAdmission(requiredGroupIDs: requiredGroupIDs))
        guard admission.effect == .admissionAccepted else {
            throw ResidencyControllerError.dirty
        }

        // Effective required set = this request's set unioned with every
        // open residency window (R3.20: jointly resident).
        let windowRequired = residencyWindows.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        let effectiveRequired = requiredGroupIDs.union(windowRequired)

        let plan = try planner.plan(
            currentResidentGroupIDs: residentGroupIDs,
            requiredGroupIDs: effectiveRequired,
            demandHints: [],
            budget: budget,
            recommendedBytes: inventory.totalByteCount
        )

        guard plan.fitsBudget else {
            throw ResidencyControllerError.requiredOverflow(plan)
        }

        var cancelled = false
        var requestID: UUID?

        if holdsResidencyWindow {
            let id = UUID()
            residencyWindows[id] = requiredGroupIDs
            requestID = id
        }

        for groupID in plan.loadGroupIDs.sorted() {
            if cancellationToken.isCancelled {
                cancelled = true
                break
            }
            do {
                try await materializer.materialize(groupID: groupID)
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
                try await materializer.release(groupID: groupID)
            } catch {
                machine.reduce(.evictFailed(groupID: groupID, reason: String(describing: error)))
                throw ResidencyControllerError.evictFailed(groupID: groupID)
            }
            machine.reduce(.evictCommitted(groupID: groupID))
        }

        return ResidencyAdmissionOutcome(plan: plan, cancelled: cancelled, requestID: requestID)
    }

    // MARK: - Residency windows

    /// Closes a residency window (R3.20): the request's execution finished.
    /// Its groups become eviction candidates at the NEXT admission or
    /// pressure event — closing alone performs no transfers.
    public func closeResidencyWindow(_ requestID: UUID) {
        stateLock.lock()
        defer { stateLock.unlock() }
        residencyWindows.removeValue(forKey: requestID)
    }

    /// Closes every open residency window.
    public func closeAllResidencyWindows() {
        stateLock.lock()
        defer { stateLock.unlock() }
        residencyWindows.removeAll()
    }

    public var activeResidencyWindowCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return residencyWindows.count
    }

    // MARK: - Reconciliation and recovery

    /// Byte reconciliation (R3.5/INV-3): compares the observed runtime idle
    /// bytes against residentBytes + C_model within ε. A mismatch enters
    /// DIRTY; a match in DIRTY still requires explicit recovery. Refused
    /// while an admission is in flight (R3.18).
    @discardableResult
    public func reconcile(
        observedIdleBytes: Int64,
        cModelBytes: Int64 = 0,
        epsilonBytes: Int64
    ) throws -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        if admissionInFlight {
            throw ResidencyControllerError.admissionInFlight
        }

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
    /// rebuilt from the transfer log over the initial state (R3.6). Refused
    /// while an admission is in flight (R3.18).
    public func recover() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        if admissionInFlight {
            throw ResidencyControllerError.admissionInFlight
        }
        machine.reduce(.recover)
    }

    // MARK: - Memory pressure

    /// Contractual response to an external memory-pressure event
    /// (R3.21–R3.23): proactively shrink residency by evicting resident
    /// non-core groups largest-byte-first (registered default victim order;
    /// ties broken by group ID) until `residentBytes + cModelBytes` is at or
    /// below `targetBytes`, or only core groups remain (the floor — core is
    /// never evicted). Every eviction is a committed, logged transfer; a
    /// release failure enters DIRTY. Never speculatively re-materializes
    /// anything afterwards (R3.24). Refused while DIRTY (R3.6). Groups
    /// required by open residency windows are not victims (R3.22).
    ///
    /// Serializes through the same FIFO lock as admissions, so pressure
    /// never overlaps an in-flight admission.
    @discardableResult
    public func respondToMemoryPressure(
        targetBytes: Int64,
        cModelBytes: Int64 = 0
    ) async throws -> [String] {
        await admissionLock.lock()
        defer { admissionLock.unlock() }

        guard machine.state == .clean else {
            throw ResidencyControllerError.dirty
        }

        let byteLookup = Dictionary(uniqueKeysWithValues: inventory.groups.map { ($0.id, $0.byteCount) })
        let coreIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        // R3.22: groups required by an open residency window are not
        // pressure-eviction victims.
        let windowRequired = residencyWindows.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        var evicted: [String] = []

        func residentBytesNow() -> Int64 {
            residentGroupIDs.reduce(Int64(0)) { $0 + (byteLookup[$1] ?? 0) }
        }

        while residentBytesNow() + cModelBytes > targetBytes {
            let candidates = residentGroupIDs
                .subtracting(coreIDs)
                .subtracting(windowRequired)
                .map { (id: $0, bytes: byteLookup[$0] ?? 0) }
                .sorted { left, right in
                    if left.bytes != right.bytes { return left.bytes > right.bytes }
                    return left.id < right.id
                }

            guard let victim = candidates.first else {
                break // core floor reached
            }

            do {
                try await materializer.release(groupID: victim.id)
            } catch {
                machine.reduce(.evictFailed(groupID: victim.id, reason: String(describing: error)))
                throw ResidencyControllerError.evictFailed(groupID: victim.id)
            }
            machine.reduce(.evictCommitted(groupID: victim.id))
            evicted.append(victim.id)
        }

        return evicted
    }
}
