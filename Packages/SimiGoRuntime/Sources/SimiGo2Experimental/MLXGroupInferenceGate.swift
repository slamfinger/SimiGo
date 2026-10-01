import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXNN
import Tokenizers

public struct MLXGroupInferenceReport: Codable, Hashable, Sendable {
  public let executionState: ExecutionStateLabel
  public let groupID: String
  public let prompt: String
  public let baselineOutput: String
  public let restoredOutput: String
  public let outputEquals: Bool
  public let groupTensorCount: Int
  public let groupByteCount: Int64
  public let releasedTensorCount: Int
  public let rematerializedTensorCount: Int
  public let releaseMilliseconds: Double
  public let rematerializeMilliseconds: Double
  public let baselineGenerateMilliseconds: Double
  public let restoredGenerateMilliseconds: Double
  public let memoryAfterBaseline: MLXLifecycleMemorySample
  public let memoryAfterRelease: MLXLifecycleMemorySample
  public let memoryAfterRematerialize: MLXLifecycleMemorySample
  public let memoryAfterRestoredGenerate: MLXLifecycleMemorySample
  public let groupInferenceResidencyPass: Bool
}

/// Minimal whole-group runtime gate: execution state selects one optional group,
/// which is released from a real model, rematerialized from Safetensors, and used
/// for inference again.
public enum MLXGroupInferenceGate {
  public static func run(
    modelDirectory: URL,
    state: ExecutionStateLabel,
    prompt: String = "Return exactly one word: ping",
    maxTokens: Int = 24
  ) async throws -> MLXGroupInferenceReport {
    let inventory = try SafetensorsInventoryReader.readModelGroups(
      modelDirectory: modelDirectory
    )
    let policy = ContiguousLayerStatePolicy(inventory: inventory)
    let optionalGroupIDs = policy
      .desiredGroupIDs(for: state)
      .subtracting(policy.alwaysResidentGroupIDs)
      .sorted()
    guard let groupID = optionalGroupIDs.first, let group = inventory.group(withID: groupID) else {
      throw LayerResidencyError.unknownLayerGroup("optional group for \(state.rawValue)")
    }

    let groupTensorNames = Set(
      inventory.tensors
        .filter { tensor in Self.groupContains(tensor: tensor, group: groupID) }
        .map(\.id)
    )
    let files = Set(
      inventory.tensors.compactMap { tensor -> URL? in
        guard groupTensorNames.contains(tensor.id) else { return nil }
        return modelDirectory.appendingPathComponent(tensor.file)
      }
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
    func sample() -> MLXLifecycleMemorySample {
      MLXLifecycleMemorySample(snapshot: Memory.snapshot())
    }
    func milliseconds(_ interval: ContinuousClock.Duration) -> Double {
      let (seconds, attoseconds) = interval.components
      return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }

    let baselineClock = ContinuousClock()
    let baselineStart = baselineClock.now
    let baselineOutput = try await generate()
    let baselineGenerateMilliseconds = milliseconds(baselineClock.now - baselineStart)
    Memory.clearCache()
    let memoryAfterBaseline = sample()

    let releaseStart = baselineClock.now
    let releasedTensorCount = try await container.perform { context -> Int in
      let selected = context.model.parameters().flattened().filter {
        groupTensorNames.contains($0.0)
      }
      let placeholders = selected.reduce(into: [:]) { result, item in
        result[item.0] = MLXArray.zeros([0], dtype: item.1.dtype)
      }
      try context.model.update(
        parameters: ModuleParameters.unflattened(placeholders),
        verify: []
      )
      return selected.count
    }
    Memory.clearCache()
    let releaseMilliseconds = milliseconds(baselineClock.now - releaseStart)
    let memoryAfterRelease = sample()

    var rematerialized: [String: MLXArray] = [:]
    let rematerializeStart = baselineClock.now
    for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let (all, _) = try MLX.loadArraysAndMetadata(url: file, stream: .cpu)
      for (name, array) in all where groupTensorNames.contains(name) {
        rematerialized[name] = array
      }
    }
    eval(Array(rematerialized.values))
    let rematerializedTensorCount = rematerialized.count

    let parameters = ModuleParameters.unflattened(rematerialized)
    _ = try await container.perform(nonSendable: parameters) { context, parameters in
      let model = UnsafeSendableBox(value: context.model)
      try model.value.update(parameters: parameters, verify: [])
    }
    rematerialized.removeAll()
    Memory.clearCache()
    let rematerializeMilliseconds = milliseconds(baselineClock.now - rematerializeStart)
    let memoryAfterRematerialize = sample()

    let restoredStart = baselineClock.now
    let restoredOutput = try await generate()
    let restoredGenerateMilliseconds = milliseconds(baselineClock.now - restoredStart)
    Memory.clearCache()
    let memoryAfterRestoredGenerate = sample()

    let outputEquals = baselineOutput == restoredOutput
    let groupInferenceResidencyPass =
      releasedTensorCount == group.tensorCount
      && rematerializedTensorCount == group.tensorCount
      && outputEquals
      && memoryAfterRelease.activeBytes < memoryAfterBaseline.activeBytes
      && memoryAfterRematerialize.activeBytes
        >= memoryAfterRelease.activeBytes + (group.byteCount * 9 / 10)

    return MLXGroupInferenceReport(
      executionState: state,
      groupID: groupID,
      prompt: prompt,
      baselineOutput: baselineOutput,
      restoredOutput: restoredOutput,
      outputEquals: outputEquals,
      groupTensorCount: group.tensorCount,
      groupByteCount: group.byteCount,
      releasedTensorCount: releasedTensorCount,
      rematerializedTensorCount: rematerializedTensorCount,
      releaseMilliseconds: releaseMilliseconds,
      rematerializeMilliseconds: rematerializeMilliseconds,
      baselineGenerateMilliseconds: baselineGenerateMilliseconds,
      restoredGenerateMilliseconds: restoredGenerateMilliseconds,
      memoryAfterBaseline: memoryAfterBaseline,
      memoryAfterRelease: memoryAfterRelease,
      memoryAfterRematerialize: memoryAfterRematerialize,
      memoryAfterRestoredGenerate: memoryAfterRestoredGenerate,
      groupInferenceResidencyPass: groupInferenceResidencyPass
    )
  }

  private static func groupContains(tensor: TensorEntry, group: String) -> Bool {
    switch group {
    case "CORE_NON_SWITCH":
      return group.hasPrefix("DENSE_MLP") ? !tensor.isDenseMLP : !tensor.isSwitchMLP
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
}
