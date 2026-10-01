import Foundation

public struct StateSequenceCase: Codable, Hashable, Sendable {
    public let id: String
    public let states: [ExecutionStateLabel]

    public init(id: String, states: [ExecutionStateLabel]) {
        self.id = id
        self.states = states
    }
}

public enum StateSequenceCatalog {
    public static let cases: [StateSequenceCase] = [
        StateSequenceCase(
            id: "BASELINE_ABA",
            states: [.stateA, .stateB, .stateAB, .stateA, .stateAll]
        ),
        StateSequenceCase(
            id: "LOCALITY_A",
            states: [.stateA, .stateA, .stateA, .stateA, .stateA]
        ),
        StateSequenceCase(
            id: "ALTERNATE_AB",
            states: [.stateA, .stateB, .stateA, .stateB, .stateA]
        ),
        StateSequenceCase(
            id: "CYCLE_ABC",
            states: [.stateA, .stateB, .stateC, .stateA, .stateB, .stateC]
        ),
        StateSequenceCase(
            id: "ALTERNATE_A_AB",
            states: [.stateA, .stateAB, .stateA, .stateAB, .stateA]
        ),
        StateSequenceCase(
            id: "FULL_PARTIAL",
            states: [.stateAll, .stateA, .stateAll, .stateA, .stateAll]
        )
    ]

    public static func named(_ id: String) throws -> StateSequenceCase {
        guard let value = cases.first(where: { $0.id == id }) else {
            throw LayerResidencyError.unknownSequence(id)
        }
        return value
    }
}

public struct StateSequenceSweepReport: Codable, Hashable, Sendable {
    public let sequences: [StateSequenceCase]
    public let benchmarks: [MLXGroupResidencyBenchmarkReport]
}

public enum StateSequenceSweep {
    public static func run(
        modelDirectory: URL,
        sequenceIDs: [String]
    ) async throws -> StateSequenceSweepReport {
        let selected = try sequenceIDs.map(StateSequenceCatalog.named)
        var benchmarks: [MLXGroupResidencyBenchmarkReport] = []
        benchmarks.reserveCapacity(selected.count)

        for sequence in selected {
            benchmarks.append(
                try await MLXGroupResidencyBenchmark.run(
                    modelDirectory: modelDirectory,
                    states: sequence.states
                )
            )
        }

        return StateSequenceSweepReport(
            sequences: selected,
            benchmarks: benchmarks
        )
    }
}
