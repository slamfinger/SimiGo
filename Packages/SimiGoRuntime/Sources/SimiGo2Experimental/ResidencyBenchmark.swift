import Foundation

public struct PolicyBenchmarkReport: Codable, Hashable, Sendable {
    public let policy: ResidencyPolicyKind
    public let states: [ExecutionStateLabel]
    public let cumulativeLoadedBytes: Int64
    public let cumulativeEvictedBytes: Int64
    public let peakResidentBytes: Int64
    public let transitionCount: Int
    public let controlDecisionCount: Int
}

public enum ResidencyBenchmark {
    public static func run(
        kinds: [ResidencyPolicyKind],
        inventory: LayerInventory,
        states: [ExecutionStateLabel],
        llamaOptions: LlamaCppControlOptions = .default
    ) throws -> [PolicyBenchmarkReport] {
        try kinds.map { kind in
            let policy = AnyLayerResidencyPolicy(
                kind: kind,
                inventory: inventory,
                llamaOptions: llamaOptions
            )
            var engine = LayerResidencyEngine(inventory: inventory, policy: policy)

            for state in states {
                _ = try engine.transition(to: state)
            }

            return PolicyBenchmarkReport(
                policy: kind,
                states: states,
                cumulativeLoadedBytes: engine.cumulativeLoadedBytes,
                cumulativeEvictedBytes: engine.cumulativeEvictedBytes,
                peakResidentBytes: engine.peakResidentBytes,
                transitionCount: states.count,
                controlDecisionCount: engine.events.count
            )
        }
    }
}
