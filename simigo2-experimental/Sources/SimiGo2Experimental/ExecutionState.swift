import Foundation

/// Externally observable execution labels used by the first deterministic MVP.
/// These are workload labels, not claims about model-internal semantics.
public enum ExecutionStateLabel: String, Codable, CaseIterable, Sendable {
    case stateA = "STATE_A"
    case stateB = "STATE_B"
    case stateC = "STATE_C"
    case stateAB = "STATE_AB"
    case stateBC = "STATE_BC"
    case stateAll = "STATE_ALL"

    public init(parsing value: String) throws {
        let normalized = value.uppercased()
        guard let label = ExecutionStateLabel(rawValue: normalized) else {
            throw LayerResidencyError.unknownExecutionState(normalized)
        }
        self = label
    }
}

public enum LayerResidencyError: Error, LocalizedError, Sendable {
    case unknownExecutionState(String)
    case missingModelIndexOfFile(String)
    case invalidSafetensorsHeader(String)
    case invalidTensorEntry(String)
    case unknownLayerGroup(String)
    case unknownSequence(String)
    case unknownWorkloadTrace(String)
    case shortTensorRead(String, expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .unknownExecutionState(let value):
            return "Unknown execution state: \(value)"
        case .missingModelIndexOfFile(let path):
            return "Missing model.safetensors.index.json at \(path)"
        case .invalidSafetensorsHeader(let path):
            return "Invalid Safetensors header in \(path)"
        case .invalidTensorEntry(let name):
            return "Invalid Safetensors tensor entry: \(name)"
        case .unknownLayerGroup(let id):
            return "Unknown layer group: \(id)"
        case .unknownSequence(let id):
            return "Unknown state sequence: \(id)"
        case .unknownWorkloadTrace(let id):
            return "Unknown workload trace: \(id)"
        case .shortTensorRead(let name, let expected, let actual):
            return "Short tensor read for \(name): expected \(expected), got \(actual)"
        }
    }
}
