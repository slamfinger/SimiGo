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
      throw OutputError(
        message:
          "usage: simigo2ctl <inventory|simulate|benchmark|budget-sweep|trace-replay|materialize|mlx-gate1|mlx-gate2|mlx-gate3|mlx-gate4|mlx-gate5|mlx-sequence-sweep|rep-audit|instrument-audit|group-trace-audit|g19a-pilot|g19-collect|l4b-reconcile|l4c-identity|e5-scenario|o2-baseline|o3-skeleton|o3c-streaming|module-paths> MODEL_DIRECTORY [options]"
      )
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
      let inventory = try SafetensorsInventoryReader.readModelGroups(
        modelDirectory: modelDirectory)
      print(try toJSON(InventoryOutput(inventory: inventory)))

    case "simulate":
      let states = try parseStates(from: rest)
      let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(
        modelDirectory: modelDirectory)
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

    case "materialize":
      let states = try parseStates(from: rest)
      let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(
        modelDirectory: modelDirectory)
      let policy = Qwen3CoderStatePolicy(inventory: inventory)
      let experiment = ExecutionStateMaterializationExperiment(
        modelDirectory: modelDirectory,
        inventory: inventory,
        policy: policy
      )
      let report = try experiment.run(states: states)
      print(try toJSON(report))

    case "benchmark":
      let states = try parseStates(from: rest)
      let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(
        modelDirectory: modelDirectory)
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

    case "budget-sweep":
      let sequenceIDs = optionalOption("--sequences", rest).map {
        $0.split(separator: ",").map(String.init)
      }
      let budgetPercents = try parseBudgetPercents(from: rest)
      let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(
        modelDirectory: modelDirectory
      )
      let report = try PlannerBudgetSweep.run(
        inventory: inventory,
        sequenceIDs: sequenceIDs,
        budgetPercents: budgetPercents
      )
      print(try toJSON(report))

    case "trace-replay":
      let traceIDOption = optionalOption("--traces", rest)
      let traces: [WorkloadTrace]?
      if let traceIDOption {
        traces = try traceIDOption.split(separator: ",").map {
          try WorkloadTraceCatalog.named(String($0))
        }
      } else {
        traces = nil
      }
      let budgetPercents = try parseBudgetPercents(from: rest)
      let inventory = try SafetensorsInventoryReader.readModelGroups(
        modelDirectory: modelDirectory
      )
      let report = try WorkloadTraceReplay.run(
        inventory: inventory,
        traces: traces,
        budgetPercents: budgetPercents,
        policy: ContiguousLayerStatePolicy(inventory: inventory)
      )
      print(try toJSON(report))

    case "mlx-gate1":
      guard let groupIndex = rest.firstIndex(of: "--group"),
        groupIndex + 1 < rest.count
      else {
        throw OutputError(message: "missing --group GROUP_ID")
      }
      let groupID = rest[groupIndex + 1]
      let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(
        modelDirectory: modelDirectory)
      let report = try await MLXGroupGate.materialize(
        modelDirectory: modelDirectory,
        inventory: inventory,
        groupID: groupID
      )
      print(try toJSON(report))
    case "mlx-gate2":
      guard let groupIndex = rest.firstIndex(of: "--group"),
        groupIndex + 1 < rest.count
      else {
        throw OutputError(message: "missing --group GROUP_ID")
      }
      let groupID = rest[groupIndex + 1]
      let inventory = try SafetensorsInventoryReader.readQwen3CoderGroups(
        modelDirectory: modelDirectory)
      let report = try await MLXGroupLifecycleExperiment.run(
        modelDirectory: modelDirectory,
        inventory: inventory,
        groupID: groupID
      )
      print(try toJSON(report))
    case "mlx-gate3":
      let prompt = "Return exactly one word: ping"
      let report = try await MLXParameterSwapGate.run(
        modelDirectory: modelDirectory,
        prompt: prompt,
        maxTokens: 24
      )
      print(try toJSON(report))
    case "mlx-gate4":
      let prompt = optionalOption("--prompt", rest) ?? "Return exactly one word: ping"
      let state = try ExecutionStateLabel(parsing: try optionValue("--state", rest))
      let report = try await MLXGroupInferenceGate.run(
        modelDirectory: modelDirectory,
        state: state,
        prompt: prompt)
      print(try toJSON(report))
    case "mlx-gate5":
      let states = try parseStates(from: rest)
      let report = try await MLXGroupResidencyBenchmark.run(
        modelDirectory: modelDirectory,
        states: states
      )
      print(try toJSON(report))
    case "mlx-sequence-sweep":
      let sequenceIDs = try parseSequenceIDs(from: rest)
      let report = try await StateSequenceSweep.run(
        modelDirectory: modelDirectory,
        sequenceIDs: sequenceIDs
      )
      print(try toJSON(report))
    case "rep-audit":
      let report = try await RepresentationCaptureAudit.audit(modelDirectory: modelDirectory)
      print(try toJSON(report))
    case "instrument-audit":
      let prompt = optionalOption("--prompt", rest) ?? "Return exactly one word: ping"
      let report = try await InstrumentationIdentityProbe.run(
        modelDirectory: modelDirectory,
        prompt: prompt,
        layerIndices: try parseLayerIndices(from: rest)
      )
      print(try toJSON(report))
    case "group-trace-audit":
      let prompt = optionalOption("--prompt", rest) ?? "Return exactly one word: ping"
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 8
      let report = try await GroupExecutionTraceProbe.run(
        modelDirectory: modelDirectory,
        prompt: prompt,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    case "g19a-pilot":
      let repetitions = optionalOption("--repetitions", rest).flatMap(Int.init)
        ?? ExecutionTracePilot.defaultRepetitions
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 24
      let report = try await ExecutionTracePilot.run(
        modelDirectory: modelDirectory,
        repetitions: repetitions,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    case "module-paths":
      let filter = optionalOption("--filter", rest) ?? "down_proj"
      let report = try await GroupExecutionTraceProbe.leafModulePathAudit(
        modelDirectory: modelDirectory,
        filterSubstring: filter
      )
      print(try toJSON(report))
    case "g19-collect":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 16
      let report = try await MeasuredTraceCollection.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    case "l4b-reconcile":
      let cModelBytes = optionalOption("--c-model-bytes", rest).flatMap(Int64.init)
      let epsilonBytes = (optionalOption("--epsilon-mib", rest).flatMap(Int64.init) ?? 5) * 1024 * 1024
      let report = try await L4ReconciliationProbe.run(
        modelDirectory: modelDirectory,
        cModelBytes: cModelBytes,
        epsilonBytes: epsilonBytes
      )
      print(try toJSON(report))
    case "l4c-identity":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 24
      let report = try await L4IdentityProbe.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    case "e5-scenario":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 12
      let report = try await E5ExecutionStateScenario.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    case "o2-baseline":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 48
      let generations = optionalOption("--generations", rest).flatMap(Int.init) ?? 10
      let report = try await O2BaselineProbe.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens,
        generations: generations
      )
      print(try toJSON(report))
    case "o3-skeleton":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 16
      let report = try await O3SkeletonProbe.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    case "o3c-streaming":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 2
      let report = try await O3CStreamingV2.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    case "o3c-streaming-v2":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 1
      let report = try await O3CStreamingV2.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    case "o3c-segmentwise":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 1
      let report = try await O3CSegmentWiseProbe.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens
      )
      print(try toJSON(report))
    default:
      throw OutputError(message: "unknown command: \(command)")
    }
  }

  static func parseSequenceIDs(from arguments: [String]) throws -> [String] {
    guard let index = arguments.firstIndex(of: "--sequences"), index + 1 < arguments.count else {
      throw OutputError(message: "missing --sequences ID,ID,...")
    }
    return arguments[index + 1].split(separator: ",").map(String.init)
  }

  static func parseBudgetPercents(from arguments: [String]) throws -> [Double] {
    guard let index = arguments.firstIndex(of: "--budgets") else {
      return PlannerBudgetSweep.defaultBudgetPercents
    }
    guard index + 1 < arguments.count else {
      throw OutputError(message: "missing --budgets PERCENT,PERCENT,...")
    }

    return try arguments[index + 1]
      .split(separator: ",")
      .map { raw in
        guard let value = Double(raw), value > 0, value.isFinite else {
          throw OutputError(message: "invalid budget percent: \(raw)")
        }
        return value
      }
  }

  static func parseStates(from arguments: [String]) throws -> [ExecutionStateLabel] {
    guard let statesIndex = arguments.firstIndex(of: "--states"),
      statesIndex + 1 < arguments.count
    else {
      throw OutputError(message: "missing --states STATE_A,STATE_B,...")
    }

    return try arguments[statesIndex + 1]
      .split(separator: ",")
      .map { try ExecutionStateLabel(parsing: String($0)) }
  }

  static func parseLayerIndices(from arguments: [String]) throws -> [Int] {
    guard let index = arguments.firstIndex(of: "--layers"),
      index + 1 < arguments.count
    else {
      throw OutputError(message: "missing --layers INDEX,INDEX,...")
    }

    return try arguments[index + 1]
      .split(separator: ",")
      .map { raw in
        guard let value = Int(raw) else {
          throw OutputError(message: "invalid layer index: \(raw)")
        }
        return value
      }
  }

  static func optionValue(_ name: String, _ arguments: [String]) throws -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
      throw OutputError(message: "missing \(name) VALUE")
    }
    return arguments[index + 1]
  }

  static func optionalOption(_ name: String, _ arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
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
