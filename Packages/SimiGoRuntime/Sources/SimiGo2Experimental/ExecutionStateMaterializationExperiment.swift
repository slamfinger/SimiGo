import Foundation

public struct ExecutionStateMaterializationExperiment: Sendable {
    public let modelDirectory: URL
    public let inventory: LayerInventory
    public let policy: any LayerResidencyPolicy
    public let materializer: SafetensorsGroupMaterializer

    public init(modelDirectory: URL, inventory: LayerInventory, policy: any LayerResidencyPolicy) {
        self.modelDirectory = modelDirectory
        self.inventory = inventory
        self.policy = policy
        self.materializer = SafetensorsGroupMaterializer(modelDirectory: modelDirectory, inventory: inventory)
    }

    public func run(states: [ExecutionStateLabel]) throws -> MaterializationExperimentReport {
        var engine = LayerResidencyEngine(inventory: inventory, policy: policy)
        var reports: [StateMaterializationReport] = []

        for state in states {
            let desired = policy.desiredGroupIDs(for: state)
            let newlyLoaded = desired.subtracting(engine.residentGroupIDs)
            let groupReports = try materializer.materialize(groups: newlyLoaded)
            _ = try engine.transition(to: state)

            let loadedBytes = groupReports.reduce(Int64(0)) { $0 + $1.byteCount }
            let elapsedMilliseconds = groupReports.reduce(0) { $0 + $1.elapsedMilliseconds }

            reports.append(
                StateMaterializationReport(
                    executionState: state,
                    loadedGroupIDs: newlyLoaded,
                    evictedGroupIDs: [],
                    residentGroupIDs: engine.residentGroupIDs,
                    reports: groupReports,
                    loadedBytes: loadedBytes,
                    elapsedMilliseconds: elapsedMilliseconds,
                    throughputMiBsPerSecond: throughput(bytes: loadedBytes, milliseconds: elapsedMilliseconds)
                )
            )
        }

        let loadedBytes = reports.reduce(Int64(0)) { $0 + $1.loadedBytes }
        let elapsedMilliseconds = reports.reduce(0) { $0 + $1.elapsedMilliseconds }

        return MaterializationExperimentReport(
            modelDirectory: modelDirectory.path,
            states: states,
            reports: reports,
            loadedBytes: loadedBytes,
            elapsedMilliseconds: elapsedMilliseconds,
            averageThroughputMiBsPerSecond: throughput(bytes: loadedBytes, milliseconds: elapsedMilliseconds)
        )
    }

    private func throughput(bytes: Int64, milliseconds: Double) -> Double {
        guard milliseconds > 0 else { return 0 }
        return (Double(bytes) / (1024 * 1024)) / (milliseconds / 1000)
    }
}
