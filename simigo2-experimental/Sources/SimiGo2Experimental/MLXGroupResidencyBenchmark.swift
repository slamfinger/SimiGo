import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXNN
import Tokenizers

public struct MLXRuntimeMemorySample: Codable, Hashable, Sendable {
  public let activeBytes: Int64
  public let cacheBytes: Int64
  public let peakBytes: Int64

  init(snapshot: Memory.Snapshot) {
    activeBytes = Int64(snapshot.activeMemory)
    cacheBytes = Int64(snapshot.cacheMemory)
    peakBytes = Int64(snapshot.peakMemory)
  }
}

public struct MLXPolicyRuntimeTransition: Codable, Hashable, Sendable {
  public let executionState: ExecutionStateLabel
  public let output: String
  public let readyActiveBytes: Int64
  public let generatedActiveBytes: Int64
  public let idleActiveBytes: Int64
  public let generationMilliseconds: Double
  public let reloadedGroupIDs: [String]
  public let reloadedBytes: Int64
  public let reloadMilliseconds: Double
  public let releasedGroupIDs: [String]
  public let releasedBytes: Int64
  public let releaseMilliseconds: Double
}

public struct MLXPolicyRuntimeReport: Codable, Hashable, Sendable {
  public let policy: String
  public let transitions: [MLXPolicyRuntimeTransition]
  public let outputs: [String]
  public let totalGenerationMilliseconds: Double
  public let totalReloadMilliseconds: Double
  public let totalReleaseMilliseconds: Double
  public let cumulativeReloadedBytes: Int64
  public let cumulativeReleasedBytes: Int64
}

public struct MLXGroupResidencyBenchmarkReport: Codable, Hashable, Sendable {
  public let states: [ExecutionStateLabel]
  public let allResident: MLXPolicyRuntimeReport
  public let naiveOnDemand: MLXPolicyRuntimeReport
  public let stateDriven: MLXPolicyRuntimeReport
  public let outputIdentityPass: Bool
  public let idleReductionObserved: Bool
  public let idleReductionBytes: Int64
  public let reloadReductionVsNaiveBytes: Int64
  public let reloadReductionVsNaiveObserved: Bool
  public let benchmarkPass: Bool
}

/// Real-runtime benchmark for group residency between complete generations.
/// Every complete Transformer generation requires all decoder-layer groups; the
/// execution-state policy therefore controls idle retention, not semantic layer
/// skipping.
public enum MLXGroupResidencyBenchmark {
  public static func run(
    modelDirectory: URL,
    states: [ExecutionStateLabel],
    prompt: String = "Return exactly one word: ping",
    maxTokens: Int = 24
  ) async throws -> MLXGroupResidencyBenchmarkReport {
    let inventory = try SafetensorsInventoryReader.readModelGroups(
      modelDirectory: modelDirectory
    )
    let policy = ContiguousLayerStatePolicy(inventory: inventory)
    let planner = ExecutionResidencyPlanner(inventory: inventory)
    let optionalGroupIDs = Set(
      inventory.groups.filter { !$0.alwaysResident }.map(\.id)
    )
    let coreGroupIDs = Set(
      inventory.groups.filter(\.alwaysResident).map(\.id)
    )

    let container = try await LLMModelFactory.shared.loadContainer(
      from: modelDirectory,
      using: #huggingFaceTokenizerLoader()
    )
    func generate() async throws -> String {
      try await ChatTemplateGeneration.generate(
        container: container,
        modelDirectory: modelDirectory,
        prompt: prompt,
        maxTokens: maxTokens
      )
    }

    func allResidentPass() async throws -> MLXPolicyRuntimeReport {
      var transitions: [MLXPolicyRuntimeTransition] = []

      for state in states {
        let readyMemory = Memory.snapshot()
        let start = ContinuousClock.now
        let output = try await generate()
        let generationMs = milliseconds(start: start)
        Memory.clearCache()
        let generatedMemory = Memory.snapshot()

        transitions.append(
          transition(
            state: state,
            output: output,
            readyMemory: readyMemory,
            generatedMemory: generatedMemory,
            idleMemory: generatedMemory,
            generationMilliseconds: generationMs,
            reloaded: emptyTransfer(),
            released: emptyTransfer()
          )
        )
      }

      return report(policy: "ALL_RESIDENT", transitions: transitions)
    }

    func stateDrivenPass() async throws -> MLXPolicyRuntimeReport {
      var transitions: [MLXPolicyRuntimeTransition] = []
      var resident = coreGroupIDs

      let allGroupBytes = inventory.totalByteCount
      let executionRequired = coreGroupIDs.union(optionalGroupIDs)

      for state in states {
        let loadPlan = try planner.plan(
          currentResidentGroupIDs: resident,
          requiredGroupIDs: executionRequired,
          demandHints: [],
          budget: ResidencyBudgetPolicy(fixedBytes: allGroupBytes),
          recommendedBytes: allGroupBytes
        )
        let missing = loadPlan.loadGroupIDs.intersection(optionalGroupIDs)
        let reload = try await loadGroups(
          container: container,
          inventory: inventory,
          groupIDs: missing
        )
        resident.formUnion(missing)
        Memory.clearCache()
        let readyMemory = Memory.snapshot()

        let start = ContinuousClock.now
        let output = try await generate()
        let generationMs = milliseconds(start: start)
        Memory.clearCache()
        let generatedMemory = Memory.snapshot()
        let retentionRequired = policy.desiredGroupIDs(for: state)
        let retentionBytes = inventory.groups
          .filter { retentionRequired.contains($0.id) }
          .reduce(Int64(0)) { $0 + $1.byteCount }
        let retentionPlan = try planner.plan(
          currentResidentGroupIDs: resident,
          requiredGroupIDs: retentionRequired,
          demandHints: [],
          budget: ResidencyBudgetPolicy(fixedBytes: retentionBytes),
          recommendedBytes: allGroupBytes
        )
        let releaseIDs = retentionPlan.evictGroupIDs.intersection(optionalGroupIDs)
        let release = try await releaseGroups(
          container: container,
          inventory: inventory,
          groupIDs: releaseIDs
        )
        resident.subtract(releaseIDs)
        Memory.clearCache()
        try? await Task.sleep(for: .milliseconds(25))
        let idleMemory = Memory.snapshot()

        transitions.append(
          transition(
            state: state,
            output: output,
            readyMemory: readyMemory,
            generatedMemory: generatedMemory,
            idleMemory: idleMemory,
            generationMilliseconds: generationMs,
            reloaded: reload,
            released: release
          )
        )
      }

      return report(policy: "EXECUTION_STATE_PLANNER", transitions: transitions)
    }

    func naiveOnDemandPass() async throws -> MLXPolicyRuntimeReport {
      var transitions: [MLXPolicyRuntimeTransition] = []
      var resident = optionalGroupIDs

      for state in states {
        let missing = optionalGroupIDs.subtracting(resident)
        let reload = try await loadGroups(
          container: container,
          inventory: inventory,
          groupIDs: missing
        )
        resident = optionalGroupIDs
        Memory.clearCache()
        let readyMemory = Memory.snapshot()

        let start = ContinuousClock.now
        let output = try await generate()
        let generationMs = milliseconds(start: start)
        Memory.clearCache()
        let generatedMemory = Memory.snapshot()

        let release = try await releaseGroups(
          container: container,
          inventory: inventory,
          groupIDs: optionalGroupIDs
        )
        resident = []
        Memory.clearCache()
        try? await Task.sleep(for: .milliseconds(25))
        let idleMemory = Memory.snapshot()

        transitions.append(
          transition(
            state: state,
            output: output,
            readyMemory: readyMemory,
            generatedMemory: generatedMemory,
            idleMemory: idleMemory,
            generationMilliseconds: generationMs,
            reloaded: reload,
            released: release
          )
        )
      }

      return report(policy: "NAIVE_ON_DEMAND", transitions: transitions)
    }

    let baseline = try await allResidentPass()
    let naiveRun = try await naiveOnDemandPass()
    let stateRun = try await stateDrivenPass()
    let outputsEqual =
      baseline.outputs == stateRun.outputs && baseline.outputs == naiveRun.outputs
    let idleReductionBytes = zip(baseline.transitions, stateRun.transitions)
      .map { $0.0.idleActiveBytes - $0.1.idleActiveBytes }
      .max() ?? 0
    let idleReductionObserved = idleReductionBytes > 0
    let reloadReductionVsNaiveBytes =
      naiveRun.cumulativeReloadedBytes - stateRun.cumulativeReloadedBytes
    let reloadReductionVsNaiveObserved = reloadReductionVsNaiveBytes > 0
    let benchmarkPass =
      outputsEqual && idleReductionObserved && reloadReductionVsNaiveObserved

    return MLXGroupResidencyBenchmarkReport(
      states: states,
      allResident: baseline,
      naiveOnDemand: naiveRun,
      stateDriven: stateRun,
      outputIdentityPass: outputsEqual,
      idleReductionObserved: idleReductionObserved,
      idleReductionBytes: idleReductionBytes,
      reloadReductionVsNaiveBytes: reloadReductionVsNaiveBytes,
      reloadReductionVsNaiveObserved: reloadReductionVsNaiveObserved,
      benchmarkPass: benchmarkPass
    )
  }

  private static func transition(
    state: ExecutionStateLabel,
    output: String,
    readyMemory: Memory.Snapshot,
    generatedMemory: Memory.Snapshot,
    idleMemory: Memory.Snapshot,
    generationMilliseconds: Double,
    reloaded: GroupTransfer,
    released: GroupTransfer
  ) -> MLXPolicyRuntimeTransition {
    MLXPolicyRuntimeTransition(
      executionState: state,
      output: output,
      readyActiveBytes: Int64(readyMemory.activeMemory),
      generatedActiveBytes: Int64(generatedMemory.activeMemory),
      idleActiveBytes: Int64(idleMemory.activeMemory),
      generationMilliseconds: generationMilliseconds,
      reloadedGroupIDs: reloaded.groupIDs.sorted(),
      reloadedBytes: reloaded.bytes,
      reloadMilliseconds: reloaded.milliseconds,
      releasedGroupIDs: released.groupIDs.sorted(),
      releasedBytes: released.bytes,
      releaseMilliseconds: released.milliseconds
    )
  }

  private static func emptyTransfer() -> GroupTransfer {
    GroupTransfer(groupIDs: [], bytes: 0, milliseconds: 0)
  }

  private static func report(
    policy: String,
    transitions: [MLXPolicyRuntimeTransition]
  ) -> MLXPolicyRuntimeReport {
    MLXPolicyRuntimeReport(
      policy: policy,
      transitions: transitions,
      outputs: transitions.map(\.output),
      totalGenerationMilliseconds: transitions.reduce(0) { $0 + $1.generationMilliseconds },
      totalReloadMilliseconds: transitions.reduce(0) { $0 + $1.reloadMilliseconds },
      totalReleaseMilliseconds: transitions.reduce(0) { $0 + $1.releaseMilliseconds },
      cumulativeReloadedBytes: transitions.reduce(0) { $0 + $1.reloadedBytes },
      cumulativeReleasedBytes: transitions.reduce(0) { $0 + $1.releasedBytes }
    )
  }

  static func loadGroups(
    container: ModelContainer,
    inventory: LayerInventory,
    groupIDs: Set<String>
  ) async throws -> GroupTransfer {
    guard !groupIDs.isEmpty else { return emptyTransfer() }
    let names = tensorNames(inventory: inventory, groupIDs: groupIDs)
    let bytes = groupBytes(inventory: inventory, groupIDs: groupIDs)
    FileHandle.standardError.write(
      Data("RELEASE groupIDs=\(groupIDs.sorted()) namesCount=\(names.count) bytes=\(bytes)\n".utf8))
    let files = Set(
      inventory.tensors
        .filter { names.contains($0.id) }
        .map(\.fileURL)
    )

    var arrays: [String: MLXArray] = [:]
    let start = ContinuousClock.now
    for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let (all, _) = try MLX.loadArraysAndMetadata(
        url: file,
        stream: .cpu
      )
      for (name, array) in all where names.contains(name) {
        arrays[name] = array
      }
    }
    eval(Array(arrays.values))

    let parameters = ModuleParameters.unflattened(arrays)
    _ = try await container.perform(nonSendable: parameters) { context, parameters in
      let model = UnsafeSendableBox(value: context.model)
      try model.value.update(parameters: parameters, verify: [])
    }
    arrays.removeAll()
    Memory.clearCache()

    return GroupTransfer(
      groupIDs: groupIDs,
      bytes: bytes,
      milliseconds: elapsed(start: start)
    )
  }

  static func releaseGroups(
    container: ModelContainer,
    inventory: LayerInventory,
    groupIDs: Set<String>
  ) async throws -> GroupTransfer {
    guard !groupIDs.isEmpty else { return emptyTransfer() }
    let names = tensorNames(inventory: inventory, groupIDs: groupIDs)
    let bytes = groupBytes(inventory: inventory, groupIDs: groupIDs)
    let start = ContinuousClock.now

    try await container.perform { context in
      let selected = context.model.parameters().flattened().filter {
        names.contains($0.0)
      }
      FileHandle.standardError.write(
        Data("RELEASE selected \(selected.count) of \(names.count) names\n".utf8))
      let placeholders = selected.reduce(into: [:]) { result, item in
        result[item.0] = MLXArray.zeros([0], dtype: item.1.dtype)
      }
      try context.model.update(
        parameters: ModuleParameters.unflattened(placeholders),
        verify: []
      )
    }
    Memory.clearCache()

    return GroupTransfer(
      groupIDs: groupIDs,
      bytes: bytes,
      milliseconds: elapsed(start: start)
    )
  }

  private static func tensorNames(
    inventory: LayerInventory,
    groupIDs: Set<String>
  ) -> Set<String> {
    Set(
      inventory.tensors
        .filter { tensor in
          inventory.groups.contains { group in
            groupIDs.contains(group.id) && groupContains(tensor: tensor, group: group.id)
          }
        }
        .map(\.id)
    )
  }

  private static func groupBytes(
    inventory: LayerInventory,
    groupIDs: Set<String>
  ) -> Int64 {
    inventory.groups
      .filter { groupIDs.contains($0.id) }
      .reduce(0) { $0 + $1.byteCount }
  }

  private static func groupContains(tensor: TensorEntry, group: String) -> Bool {
    switch group {
    case "CORE_NON_SWITCH": return !tensor.isSwitchMLP
    case let dense where group.hasPrefix("DENSE_MLP_"):
      let parts = dense.dropFirst("DENSE_MLP_L".count).split(separator: "_")
      guard parts.count == 2, let lower = Int(parts[0]), let upper = Int(parts[1]),
            let layer = tensor.decoderLayer else { return false }
      return tensor.isDenseMLP && layer >= lower && layer <= upper
    case "SWITCH_MLP_L00_15": return tensor.isSwitchMLP && (tensor.decoderLayer ?? -1) <= 15
    case "SWITCH_MLP_L16_31":
      let layer = tensor.decoderLayer ?? -1
      return tensor.isSwitchMLP && layer >= 16 && layer <= 31
    case "SWITCH_MLP_L32_47": return tensor.isSwitchMLP && (tensor.decoderLayer ?? -1) >= 32
    default: return false
    }
  }

  private static func elapsed(start: ContinuousClock.Instant) -> Double {
    milliseconds(start: start)
  }

  private static func milliseconds(start: ContinuousClock.Instant) -> Double {
    let interval = ContinuousClock.now - start
    let (seconds, attoseconds) = interval.components
    return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
  }
}

struct GroupTransfer {
  let groupIDs: Set<String>
  let bytes: Int64
  let milliseconds: Double
}
