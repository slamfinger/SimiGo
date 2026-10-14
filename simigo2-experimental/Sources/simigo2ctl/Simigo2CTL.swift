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
          "usage: simigo2ctl <inventory|simulate|benchmark|budget-sweep|trace-replay|materialize|mlx-gate1|mlx-gate2|mlx-gate3|mlx-gate4|mlx-gate5|mlx-sequence-sweep|rep-audit|instrument-audit|group-trace-audit|g19a-pilot|g19-collect|l4b-reconcile|l4c-identity|e5-scenario|o2-baseline|o3-skeleton|o3c-streaming|o6-cancel-ab|llama-execstate-ab|llama-execstate-fork-restore|llama-execstate-cancel|llama-branch-session|llama-branch-session-nested|llama-branch-session-cancel|llama-branch-session-long|llama-branch-session-memory-pressure|mlx-branch-session|mlx-branch-session-nested|mlx-branch-session-long|mlx-branch-session-cancel|mlx-branch-session-memory-pressure|ui-branch-session-matrix|ui-nested-branch-matrix|ui-cancellation-matrix|ui-memory-pressure-matrix|cross-backend-token-record|cross-backend-token-compare|cross-backend-logit-record|cross-backend-logit-compare|cross-backend-margin-record|cross-backend-margin-compare|named-source-profile-evaluate|mlx-execstate-cost|mlx-execstate-scale|mlx-release-cost|mlx-release-recovery|mlx-prefix-cache-probe|mlx-segment-phase|mlx-fixed-prefix-phase|module-paths|representation-consistency-boundary|llama-representation-consistency> MODEL_DIRECTORY [options]"
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
      let repetitions =
        optionalOption("--repetitions", rest).flatMap(Int.init)
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
      let epsilonBytes =
        (optionalOption("--epsilon-mib", rest).flatMap(Int64.init) ?? 5) * 1024 * 1024
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
    case "llama-representation-consistency":
      let serverURL =
        optionalOption("--server-url", rest)
        .flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:18080")!
      let predictionTokens = optionalOption("--prediction-tokens", rest).flatMap(Int.init) ?? 12
      let repetitions = optionalOption("--repetitions", rest).flatMap(Int.init) ?? 3
      let seedText =
        optionalOption("--seed-text", rest)
        ?? "The project directory ReferenceFiles contains project management documents."
      let nextInput = optionalOption("--next-input", rest) ?? "What folder did I create?"
      let report = try await LLAMARepresentationConsistencyExperiment.run(
        serverURL: serverURL,
        seedText: seedText,
        nextInput: nextInput,
        predictionTokens: predictionTokens,
        repetitions: repetitions
      )
      print(try toJSON(report))

    case "representation-consistency-boundary":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 16
      let c2Repetitions = optionalOption("--c2-repetitions", rest).flatMap(Int.init) ?? 3
      let report = try await RepresentationConsistencyBoundaryExperiment.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens,
        c2Repetitions: c2Repetitions
      )
      print(try toJSON(report))

    case "cross-backend-token-record":
      let maxTokens = optionalOption("--max-tokens", rest).flatMap(Int.init) ?? 12
      let record = try await CrossBackendTokenProbe.runRecord(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens
      )
      let output = try optionValue("--output", rest)
      let json = try toJSON(record)
      try json.write(toFile: output, atomically: true, encoding: .utf8)
      print(json)
    case "cross-backend-token-compare":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let recordPath = try optionValue("--record", rest)
      let report = try await CrossBackendTokenProbe.runCompare(
        modelDirectory: modelDirectory,
        recordPath: recordPath,
        host: host,
        port: port,
        seed: seed
      )
      print(try toJSON(report))
    case "cross-backend-logit-record":
      let topK = optionalOption("--top-k", rest).flatMap(Int.init) ?? 16
      let record = try await CrossBackendLogitProbe.runRecord(
        modelDirectory: modelDirectory,
        sourceComparePath: try optionValue("--compare", rest),
        topK: topK
      )
      let output = try optionValue("--output", rest)
      let json = try toJSON(record)
      try json.write(toFile: output, atomically: true, encoding: .utf8)
      print(json)
    case "cross-backend-logit-compare":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let topK = optionalOption("--top-k", rest).flatMap(Int.init) ?? 16
      let report = try await CrossBackendLogitProbe.runCompare(
        modelDirectory: modelDirectory,
        recordPath: try optionValue("--record", rest),
        host: host,
        port: port,
        topK: topK
      )
      print(try toJSON(report))
    case "cross-backend-margin-record":
      let topK = optionalOption("--top-k", rest).flatMap(Int.init) ?? 16
      let scope = optionalOption("--scope", rest) ?? "all"
      guard let marginScope = CrossBackendMarginProbe.Scope(rawValue: scope) else {
        throw OutputError(message: "invalid --scope: \(scope)")
      }
      let record = try await CrossBackendMarginProbe.runRecord(
        modelDirectory: modelDirectory,
        sourceComparePath: try optionValue("--compare", rest),
        scope: marginScope,
        topK: topK
      )
      let output = try optionValue("--output", rest)
      let json = try toJSON(record)
      try json.write(toFile: output, atomically: true, encoding: .utf8)
      print(json)
    case "cross-backend-margin-compare":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let topK = optionalOption("--top-k", rest).flatMap(Int.init) ?? 16
      let scope = optionalOption("--scope", rest) ?? "all"
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      guard let marginScope = CrossBackendMarginProbe.Scope(rawValue: scope) else {
        throw OutputError(message: "invalid --scope: \(scope)")
      }
      let report = try await CrossBackendMarginProbe.runCompare(
        modelDirectory: modelDirectory,
        recordPath: try optionValue("--record", rest),
        host: host,
        port: port,
        scope: marginScope,
        topK: topK,
        seed: seed
      )
      print(try toJSON(report))
    case "named-source-profile-evaluate":
      let comparePaths = zip(rest, rest.dropFirst())
        .filter { flag, _ in flag == "--compare" }
        .map { $1 }
      guard comparePaths.count >= 2 else {
        throw OutputError(message: "missing two --compare PATH arguments")
      }
      let evidence = try comparePaths.enumerated().map { index, path in
        let defaultSeed = path.contains("seed43") ? 43 : (index == 0 ? 42 : 43)
        return try NamedSourceConformanceProfile.seedEvidence(
          fromCompareData: Data(contentsOf: URL(fileURLWithPath: path)),
          defaultSeed: defaultSeed
        )
      }
      let evaluation = NamedSourceConformanceProfile.evaluate(evidence: evidence)
      print(try toJSON(evaluation))
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
      let passes = optionalOption("--passes", rest).flatMap(Int.init) ?? 1
      let report = try await O3CSegmentWiseProbe.run(
        modelDirectory: modelDirectory,
        maxTokens: maxTokens,
        streamingPasses: passes
      )
      print(try toJSON(report))
    case "o4-gen-compare":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 8
      let passes = optionalOption("--passes", rest).flatMap(Int.init) ?? 2
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 10
      let report = try await O4GenerationProbe.run(
        modelDirectory: modelDirectory,
        maxNewTokens: tokens,
        passes: passes,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "o4-oversized-gen":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 8
      let passes = optionalOption("--passes", rest).flatMap(Int.init) ?? 2
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 16
      let promptRepeat = optionalOption("--prompt-repeat", rest).flatMap(Int.init) ?? 1
      let prompt =
        optionalOption("--prompt", rest) ?? "Write a Python function that merges two sorted lists."
      let prefetch = rest.contains("--prefetch")
      let report = try await O4OversizedGenerationProbe.run(
        modelDirectory: modelDirectory,
        prompt: prompt,
        promptRepeat: promptRepeat,
        maxNewTokens: tokens,
        passes: passes,
        segmentSize: segmentSize,
        prefetch: prefetch
      )
      print(try toJSON(report))
    case "o6-execstate":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 4
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await O6ExecutionStateScenario.run(
        modelDirectory: modelDirectory,
        maxTokens: tokens,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "o6-cancel-ab":
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 3
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 4
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await O6CancellationAB.run(
        modelDirectory: modelDirectory,
        cycles: cycles,
        maxTokens: tokens,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "llama-execstate-ab":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let samples = optionalOption("--samples", rest).flatMap(Int.init) ?? 30
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 8
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let report = try await LLAMAServerExecutionStateAB.run(
        host: host,
        port: port,
        samples: samples,
        predictionTokens: tokens,
        seed: seed
      )
      print(try toJSON(report))
    case "llama-execstate-fork-restore":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let samples = optionalOption("--samples", rest).flatMap(Int.init) ?? 30
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 8
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let report = try await LLAMAServerExecutionStateForkRestore.run(
        host: host,
        port: port,
        samples: samples,
        predictionTokens: tokens,
        seed: seed
      )
      print(try toJSON(report))
    case "llama-execstate-cancel":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 20
      let cancelDelay = optionalOption("--cancel-delay-ms", rest).flatMap(Int.init) ?? 100
      let predictionTokens = optionalOption("--prediction-tokens", rest).flatMap(Int.init) ?? 256
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let report = try await LLAMAServerExecutionStateCancellation.run(
        host: host,
        port: port,
        cycles: cycles,
        cancelDelayMs: cancelDelay,
        predictionTokens: predictionTokens,
        seed: seed
      )
      print(try toJSON(report))
    case "llama-branch-session":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 8
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let report = try await UIBranchSessions.run(
        host: host,
        port: port,
        predictionTokens: tokens,
        seed: seed
      )
      print(try toJSON(report))
    case "llama-branch-session-nested":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 2
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let report = try await UIBranchSessions.runNestedLLAMA(
        host: host,
        port: port,
        predictionTokens: tokens,
        cycles: cycles,
        seed: seed
      )
      print(try toJSON(report))
    case "llama-branch-session-cancel":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let cancelDelay = optionalOption("--cancel-delay-ms", rest).flatMap(Int.init) ?? 100
      let predictionTokens = optionalOption("--prediction-tokens", rest).flatMap(Int.init) ?? 2
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let report = try await UIBranchSessions.runCancellationLLAMA(
        host: host,
        port: port,
        predictionTokens: predictionTokens,
        cancelDelayMs: cancelDelay,
        cycles: cycles,
        seed: seed
      )
      print(try toJSON(report))
    case "llama-branch-session-long":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let turns = optionalOption("--turns", rest).flatMap(Int.init) ?? 6
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 4
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let report = try await UIBranchSessions.runLongRunningLLAMA(
        host: host,
        port: port,
        turns: turns,
        predictionTokens: tokens,
        seed: seed
      )
      print(try toJSON(report))
    case "llama-branch-session-memory-pressure":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let tokens = optionalOption("--prediction-tokens", rest).flatMap(Int.init) ?? 1
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let report = try await UIBranchSessions.runMemoryPressureLLAMA(
        host: host,
        port: port,
        predictionTokens: tokens,
        cycles: cycles,
        seed: seed
      )
      print(try toJSON(report))
    case "mlx-branch-session":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 2
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runOversizedMLX(
        modelDirectory: modelDirectory,
        maxTokens: tokens,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-branch-session-nested":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 2
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runNestedOversizedMLX(
        modelDirectory: modelDirectory,
        maxTokens: tokens,
        cycles: cycles,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-branch-session-cancel":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 4
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runCancellationOversizedMLX(
        modelDirectory: modelDirectory,
        maxTokens: tokens,
        cycles: cycles,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-branch-session-long":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 1
      let turns = optionalOption("--turns", rest).flatMap(Int.init) ?? 6
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runLongRunningOversizedMLX(
        modelDirectory: modelDirectory,
        turnInputs: Array(
          [
            "Summarize the first implementation step.",
            "List one edge case and how to handle it.",
            "Add a focused unit test for that edge case.",
            "Describe the expected result in one sentence.",
            "Review the result and identify one improvement.",
            "Finalize the implementation with a short TODO.",
          ].prefix(turns)
        ),
        maxTokens: tokens,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-branch-session-memory-pressure":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 1
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runMemoryPressureOversizedMLX(
        modelDirectory: modelDirectory,
        maxTokens: tokens,
        cycles: cycles,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "ui-branch-session-matrix":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 2
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runCrossBackendMatrix(
        modelDirectory: modelDirectory,
        host: host,
        port: port,
        predictionTokens: tokens,
        seed: seed,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "ui-nested-branch-matrix":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 2
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runNestedCrossBackendMatrix(
        modelDirectory: modelDirectory,
        host: host,
        port: port,
        predictionTokens: tokens,
        cycles: cycles,
        seed: seed,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "ui-cancellation-matrix":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 2
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let cancelDelay = optionalOption("--cancel-delay-ms", rest).flatMap(Int.init) ?? 100
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runCancellationCrossBackendMatrix(
        modelDirectory: modelDirectory,
        host: host,
        port: port,
        recoveryTokens: tokens,
        cycles: cycles,
        cancelDelayMs: cancelDelay,
        seed: seed,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "ui-memory-pressure-matrix":
      let host = optionalOption("--host", rest) ?? "127.0.0.1"
      let port = optionalOption("--port", rest).flatMap(Int.init) ?? 18080
      let tokens = optionalOption("--prediction-tokens", rest).flatMap(Int.init) ?? 1
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 2
      let seed = optionalOption("--seed", rest).flatMap(Int.init) ?? 42
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await UIBranchSessions.runMemoryPressureCrossBackendMatrix(
        modelDirectory: modelDirectory,
        host: host,
        port: port,
        predictionTokens: tokens,
        cycles: cycles,
        seed: seed,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-execstate-cost":
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 2
      let paired = optionalOption("--paired-cycles", rest).flatMap(Int.init) ?? 3
      let lifecycle = optionalOption("--lifecycle-cycles", rest).flatMap(Int.init) ?? 2
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await MLXExecutionStateCostProfile.run(
        modelDirectory: modelDirectory,
        maxTokens: tokens,
        pairedCycles: paired,
        lifecycleCycles: lifecycle,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-execstate-scale":
      let lengths = optionalOption("--lengths", rest)?.split(separator: ",").compactMap { Int($0) }
      let pairs = optionalOption("--pairs-per-length", rest).flatMap(Int.init) ?? 2
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 1
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await MLXExecutionStateCostProfile.runScaleSweep(
        modelDirectory: modelDirectory,
        tokenLengths: lengths ?? [8, 64, 256],
        pairsPerLength: pairs,
        maxTokens: tokens,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-release-cost":
      let lengths = optionalOption("--lengths", rest)?.split(separator: ",").compactMap { Int($0) }
      let samples = optionalOption("--samples-per-length", rest).flatMap(Int.init) ?? 10
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await MLXExecutionStateCostProfile.runReleaseCostProfile(
        modelDirectory: modelDirectory,
        tokenLengths: lengths ?? [8, 64, 256],
        samplesPerLength: samples,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-prefix-cache-probe":
      let prompt = optionalOption("--prompt", rest)
        ?? "Summarize the tradeoff between durable write-ahead logs and atomic rename publication."
      let prefixTokens = optionalOption("--prefix-tokens", rest).flatMap(Int.init) ?? 16
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 8
      let root = optionalOption("--root", rest).map {
        URL(fileURLWithPath: $0, isDirectory: true)
      } ?? FileManager.default.temporaryDirectory.appendingPathComponent(
        "simigo-prefix-cache-\(UUID().uuidString)", isDirectory: true)
      let report = try await MLXPrefixCrossSessionCache.persistenceProbe(
        modelDirectory: modelDirectory,
        root: root,
        prompt: prompt,
        prefixTokenCount: prefixTokens,
        maxTokens: tokens
      )
      print(try toJSON(report))

    case "mlx-release-recovery":
      let length = optionalOption("--prefix-length", rest).flatMap(Int.init) ?? 64
      let tokens = optionalOption("--tokens", rest).flatMap(Int.init) ?? 2
      let cycles = optionalOption("--cycles", rest).flatMap(Int.init) ?? 4
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await MLXExecutionStateCostProfile.runReleaseRecoveryProfile(
        modelDirectory: modelDirectory,
        prefixTokenLength: length,
        maxTokens: tokens,
        cycles: cycles,
        segmentSize: segmentSize
      )
      print(try toJSON(report))
    case "mlx-segment-phase":
      let prefixLength = optionalOption("--prefix-length", rest).flatMap(Int.init) ?? 64
      let samples = optionalOption("--samples", rest).flatMap(Int.init) ?? 1
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await O6SegmentPhaseProfiler.run(
        modelDirectory: modelDirectory,
        prefixTokenLength: prefixLength,
        segmentSize: segmentSize,
        measuredSamples: samples
      )
      print(try toJSON(report))
    case "mlx-fixed-prefix-phase":
      let ids =
        optionalOption("--prefix-token-ids", rest)?.split(separator: ",").compactMap { Int($0) }
        ?? Array(1000...1063)
      let lengths =
        optionalOption("--prefix-lengths", rest)?.split(separator: ",").compactMap { Int($0) } ?? [
          8, 64,
        ]
      let samples = optionalOption("--samples-per-size", rest).flatMap(Int.init) ?? 3
      let segmentSize = optionalOption("--segment-size", rest).flatMap(Int.init) ?? 8
      let report = try await O6FixedPrefixPhaseStudy.run(
        modelDirectory: modelDirectory,
        prefixTokenIDs: ids,
        prefixTokenLengths: lengths,
        segmentSize: segmentSize,
        measuredSamplesPerSize: samples
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
