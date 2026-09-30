import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import SimiGoRuntimeContract
import Tokenizers

/// L4-B: INV-3 real byte reconciliation. The single question this probe
/// answers: does the Controller's resident bookkeeping match the REAL MLX
/// runtime's memory observation,
///
///     |idleBytes − (residentBookkeepingBytes + C_model)| ≤ ε
///
/// across the seven registered paths (load committed, release committed,
/// load failure, release failure → DIRTY, recovery, multi-group continuous
/// transfers, pressure response). NOT a performance test: no latency,
/// throughput, or improvement claims.
///
/// C_model is the per-model-class accounting constant from the residency
/// observability audit (Qwen3-Coder = 0; Nail = the audited −851.1 MiB
/// offset from the un-loaded vision tower). When not supplied, the probe
/// calibrates C_model from the first reconciliation sample and verifies its
/// constancy across every subsequent transition.
public struct L4BTransitionRecord: Codable, Sendable {
    public let label: String
    public let path: String
    public let transferLogCount: Int
    public let bookkeepingBytes: Int64
    public let cModelBytes: Int64
    public let predictedIdleBytes: Int64
    public let observedIdleBytes: Int64
    public let deviationBytes: Int64
    public let withinEpsilon: Bool
    public let controllerState: String
}

public struct L4ReconciliationReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let epsilonBytes: Int64
    public let cModelBytesSupplied: Bool
    public let cModelBytesUsed: Int64
    public let transitions: [L4BTransitionRecord]
    public let overallPass: Bool
}

enum L4BFault: Error {
    case injectedLoadFailure(groupID: String)
    case injectedReleaseFailure(groupID: String)
}

/// Contract-level fault injector wrapping the REAL backend: an injected
/// throw happens BEFORE delegation, so the real MLX state remains consistent
/// with what the controller's bookkeeping will record.
final class FaultInjectingResidencyMaterializer: ResidencyMaterializer, @unchecked Sendable {
    let base: any ResidencyMaterializer
    var failLoadsOf: Set<String> = []
    var failReleasesOf: Set<String> = []

    init(base: any ResidencyMaterializer) {
        self.base = base
    }

    func materialize(groupID: String) async throws {
        if failLoadsOf.contains(groupID) {
            throw L4BFault.injectedLoadFailure(groupID: groupID)
        }
        try await base.materialize(groupID: groupID)
    }

    func release(groupID: String) async throws {
        if failReleasesOf.contains(groupID) {
            throw L4BFault.injectedReleaseFailure(groupID: groupID)
        }
        try await base.release(groupID: groupID)
    }
}

public enum L4ReconciliationProbe {
    public static let protocolVersion = "G1.9-L4B.RECONCILIATION.V1"

    public static func run(
        modelDirectory: URL,
        cModelBytes: Int64? = nil,
        epsilonBytes: Int64 = 5 * 1024 * 1024
    ) async throws -> L4ReconciliationReport {
        let inventory = try SafetensorsInventoryReader.readModelGroups(
            modelDirectory: modelDirectory
        )
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        let modelType = await container.perform { (context: ModelContext) -> String in
            String(describing: type(of: context.model))
        }

        let backend = MLXResidencyBackend(container: container, inventory: inventory)
        let faulted = FaultInjectingResidencyMaterializer(base: backend)

        let allGroups = Set(inventory.groups.map(\.id))
        // The backend loads the FULL model, so the controller's initial
        // bookkeeping MUST be the full set — it starts consistent with the
        // real runtime state.
        let controller = ResidencyController(
            inventory: inventory,
            materializer: faulted,
            initialResidentGroupIDs: allGroups
        )

        let coreIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        let optionalIDs = inventory.groups
            .filter { !$0.alwaysResident }
            .sorted { $0.layerRangeDescription < $1.layerRangeDescription }
            .map(\.id)
        guard optionalIDs.count == 3 else {
            throw L4BError.unexpectedOptionalGroupCount(optionalIDs.count)
        }
        let g0 = optionalIDs[0], g1 = optionalIDs[1], g2 = optionalIDs[2]
        let coreBytes = inventory.groups
            .filter(\.alwaysResident)
            .reduce(Int64(0)) { $0 + $1.byteCount }

        var records: [L4BTransitionRecord] = []
        var calibratedCModel: Int64?

        func record(label: String, path: String) async throws {
            // Validated transition hygiene: purge transient caches, allow
            // the backend to settle, then observe passively.
            backend.purgeTransientCaches()
            try? await Task.sleep(for: .milliseconds(25))
            let observation = try backend.memoryObservation()

            let bookkeepingBytes = controller.residentBytes
            let cModel: Int64
            if let supplied = cModelBytes {
                cModel = supplied
            } else if let calibrated = calibratedCModel {
                cModel = calibrated
            } else {
                cModel = observation.activeBytes - bookkeepingBytes
                calibratedCModel = cModel
            }

            let predicted = bookkeepingBytes + cModel
            let deviation = observation.activeBytes - predicted
            let within = abs(deviation) <= epsilonBytes

            records.append(
                L4BTransitionRecord(
                    label: label,
                    path: path,
                    transferLogCount: controller.transferLog.count,
                    bookkeepingBytes: bookkeepingBytes,
                    cModelBytes: cModel,
                    predictedIdleBytes: predicted,
                    observedIdleBytes: observation.activeBytes,
                    deviationBytes: deviation,
                    withinEpsilon: within,
                    controllerState: controller.state == .clean ? "CLEAN" : "DIRTY"
                )
            )
        }

        // T0 — calibration sample on the untouched full-load state.
        try await record(label: "T0_START_CALIBRATION", path: "CALIBRATION")

        // T1 — pressure response: shrink to the core floor (all three
        // optional groups released, each a committed transfer).
        _ = try await controller.respondToMemoryPressure(targetBytes: coreBytes)
        try await record(label: "T1_PRESSURE_RELEASE_ALL", path: "PRESSURE_RESPONSE+RELEASE_COMMITTED")

        // T2 — load committed: one optional group materialized.
        _ = try await controller.admit(
            requiredGroupIDs: coreIDs.union([g0]),
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        try await record(label: "T2_LOAD_COMMITTED", path: "LOAD_COMMITTED")

        // T3 — multi-group continuous transfer: adds a second group.
        _ = try await controller.admit(
            requiredGroupIDs: coreIDs.union([g0, g1]),
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        try await record(label: "T3_MULTI_GROUP_CONTINUOUS", path: "MULTI_GROUP_CONTINUOUS+LOAD_COMMITTED")

        // T4 — release committed: shrink back to the middle group.
        _ = try await controller.admit(
            requiredGroupIDs: coreIDs.union([g1]),
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        try await record(label: "T4_RELEASE_COMMITTED", path: "RELEASE_COMMITTED")

        // T5 — load failure: the injected load failure leaves bookkeeping
        // and the REAL backend state consistent (g2 not materialized). The
        // controller surfaces the injected fault as .loadFailed.
        faulted.failLoadsOf = [g2]
        do {
            _ = try await controller.admit(
                requiredGroupIDs: coreIDs.union([g0, g1, g2]),
                budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
            )
            throw L4BError.expectedLoadFailure
        } catch let error as ResidencyControllerError {
            guard case .loadFailed(groupID: g2) = error else {
                throw L4BError.expectedLoadFailure
            }
        }
        try await record(label: "T5_LOAD_FAILURE", path: "LOAD_FAILURE")

        // T6 — release failure → DIRTY: the group stays resident in the REAL
        // state and in the bookkeeping.
        faulted.failLoadsOf = []
        faulted.failReleasesOf = [g0]
        do {
            _ = try await controller.admit(
                requiredGroupIDs: coreIDs.union([g2]),
                budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
            )
            throw L4BError.expectedReleaseFailure
        } catch let error as ResidencyControllerError {
            guard case .evictFailed(groupID: g0) = error else {
                throw L4BError.expectedReleaseFailure
            }
        }
        try await record(label: "T6_RELEASE_FAILURE_DIRTY", path: "RELEASE_FAILURE+DIRTY")
        guard controller.state == .dirty else {
            throw L4BError.expectedReleaseFailure
        }

        // T7 — recovery: bookkeeping rebuilt from the transfer log; the
        // real state already matched it.
        try controller.recover()
        try await record(label: "T7_RECOVERY", path: "RECOVERY")

        // T8 — full residency restored after recovery.
        faulted.failLoadsOf = []
        faulted.failReleasesOf = []
        _ = try await controller.admit(
            requiredGroupIDs: allGroups,
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        try await record(label: "T8_FULL_AFTER_RECOVERY", path: "LOAD_COMMITTED+RECOVERY")

        // T9 — pressure response with the recovery-verified state.
        _ = try await controller.respondToMemoryPressure(targetBytes: coreBytes)
        try await record(label: "T9_PRESSURE_RESPONSE", path: "PRESSURE_RESPONSE")

        let overallPass = records.allSatisfy(\.withinEpsilon)
            && records.allSatisfy { $0.controllerState == "CLEAN" || $0.label == "T6_RELEASE_FAILURE_DIRTY" }

        return L4ReconciliationReport(
            status: overallPass ? "PASS" : "FAIL",
            boundary:
                "REAL_RUNTIME_RECONCILIATION / RESOURCE_STATE_CORRECTNESS / NOT_A_PERFORMANCE_TEST / NOT_DEMAND / NOT_PREDICTION",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: modelType,
            epsilonBytes: epsilonBytes,
            cModelBytesSupplied: cModelBytes != nil,
            cModelBytesUsed: calibratedCModel ?? (cModelBytes ?? 0),
            transitions: records,
            overallPass: overallPass
        )
    }

    public enum L4BError: Error, Equatable {
        case unexpectedOptionalGroupCount(Int)
        case expectedLoadFailure
        case expectedReleaseFailure
    }
}
