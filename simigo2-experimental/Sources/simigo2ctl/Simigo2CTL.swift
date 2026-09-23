import Foundation
import SimiGo2Experimental

struct OutputError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
struct Simigo2CTL {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data(("error: \(error.localizedDescription)\n").utf8))
            exit(1)
        }
    }

    static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            throw OutputError(message: "usage: simigo2ctl <inventory|simulate|benchmark> MODEL_DIRECTORY [options]")
        }

        let rest = Array(arguments.dropFirst())
        guard let modelDirectoryIndex = rest.firstIndex(where: { !$0.hasPrefix("--") }) else {
            throw OutputError(message: "missing MODEL_DIRECTORY")
        }

        let modelDirectory = URL(
            fileURLWithPath: rest[modelDirectoryIndex],
            isDirectory: true
        ).standardizedFileURL

        switch command {
        case "inventory":
            let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(modelDirectory: modelDirectory)
            print(try toJSON(InventoryOutput(inventory: inventory)))

        case "simulate":
            let states = try parseStates(from: rest)
            let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(modelDirectory: modelDirectory)
            let policy = Qwen3CoderStatePolicy(inventory: inventory)
            var engine = LayerResidencyEngine(inventory: inventory, policy: policy)

            var reports: [TransitionReport] = []
            for state in states {
                reports.append(try engine.transition(to: state))
            }

            let output = SimulationOutput(
                modelDirectory: modelDirectory.path,
                states: states,
                reports: reports,
                peakResidentBytes: engine.peakResidentBytes,
                cumulativeLoadedBytes: engine.cumulativeLoadedBytes,
                cumulativeEvictedBytes: engine.cumulativeEvictedBytes
            )
            print(try toJSON(output))

        case "benchmark":
            let states = try parseStates(from: rest)
            let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(modelDirectory: modelDirectory)
            let reports = try ResidencyBenchmark.run(
                kinds: ResidencyPolicyKind.allCases,
                inventory: inventory,
                states: states
            )
            let output = BenchmarkOutput(
                modelDirectory: modelDirectory.path,
                states: states,
                reports: reports
            )
            print(try toJSON(output))

        default:
            throw OutputError(message: "unknown command: \(command)")
        }
    }

    static func parseStates(from arguments: [String]) throws -> [ExecutionStateLabel] {
        guard let statesIndex = arguments.firstIndex(of: "--states"),
              statesIndex + 1 < arguments.count else {
            throw OutputError(message: "missing --states STATE_A,STATE_B,...")
        }

        return try arguments[statesIndex + 1]
            .split(separator: ",")
            .map { try ExecutionStateLabel(parsing: String($0)) }
    }

    static func toJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

struct InventoryOutput: Encodable {
    let groups: [LayerGroup]
    let tensorCount: Int
    let totalBytes: Int64

    init(inventory: LayerInventory) {
        groups = inventory.groups
        tensorCount = inventory.tensors.count
        totalBytes = inventory.totalByteCount
    }
}

struct SimulationOutput: Encodable {
    let modelDirectory: String
    let states: [ExecutionStateLabel]
    let reports: [TransitionReport]
    let peakResidentBytes: Int64
    let cumulativeLoadedBytes: Int64
    let cumulativeEvictedBytes: Int64
}

struct BenchmarkOutput: Encodable {
    let modelDirectory: String
    let states: [ExecutionStateLabel]
    let reports: [PolicyBenchmarkReport]
}
