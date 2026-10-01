import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXNN
import Tokenizers

public struct MLXParameterSwapReport: Codable, Hashable, Sendable {
  public let targetParameterKey: String
  public let prompt: String
  public let baselineOutput: String
  public let perturbedOutput: String
  public let restoredOutput: String
  public let restoredParameterMatchesBaseline: Bool
  public let baselineEqualsRestored: Bool
  public let perturbedDiffers: Bool
  public let swapAndRestorePass: Bool
  public let targetWasLoadBearing: Bool
}

public enum MLXParameterSwapGate {
  public static func run(
    modelDirectory: URL,
    prompt: String = "Return exactly one word: ping",
    maxTokens: Int = 24
  ) async throws -> MLXParameterSwapReport {
    let container = try await LLMModelFactory.shared.loadContainer(
      from: modelDirectory,
      using: #huggingFaceTokenizerLoader()
    )

    let targetKey = try await container.perform { context -> String in
      let matches = context.model.parameters().flattened().map(\.0).filter { key in
        key.hasSuffix(".mlp.switch_mlp.gate_proj.weight")
      }
      guard let key = matches.sorted().first else {
        throw LayerResidencyError.unknownLayerGroup("mlp.switch_mlp.gate_proj.weight")
      }
      return key
    }

    let originalBox = try await container.perform { context -> UnsafeSendableBox<MLXArray> in
      let parameter = context.model.parameters().flattened().first { $0.0 == targetKey }
      guard let array = parameter?.1 else {
        throw LayerResidencyError.unknownLayerGroup(targetKey)
      }
      eval(array)
      return UnsafeSendableBox(value: array)
    }
    let original = originalBox.value

    // Module update mutates the MLXArray wrapper in place, so snapshot before perturbing.
    let snapshot = original + 0
    eval(snapshot)
    let replacement = MLXArray.zeros(original.shape, dtype: original.dtype)
    let replacementParameters = ModuleParameters.unflattened([targetKey: replacement])
    let baselineFingerprint = Self.fingerprint(original)

    func apply(_ parameters: ModuleParameters) async throws {
      _ = try await container.perform(nonSendable: parameters) { context, parameters in
        let model = UnsafeSendableBox(value: context.model)
      try model.value.update(parameters: parameters, verify: [])
      }
    }

    func generate() async throws -> String {
      let session = ChatSession(
        container,
        speculativeDecoding: nil,
        generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0)
      )
      return try await session.respond(to: prompt)
    }

    let baseline = try await generate()
    try await apply(replacementParameters)
    let perturbed = try await generate()

    let restoreParameters = ModuleParameters.unflattened([targetKey: snapshot])
    try await apply(restoreParameters)
    let restored = try await generate()

    let baselineEqualsRestored = baseline == restored
    let perturbedDiffers = perturbed != baseline
    let restoredParameterMatchesBaseline = try await container.perform { context in
      let parameter = context.model.parameters().flattened().first { $0.0 == targetKey }
      guard let array = parameter?.1 else {
        throw LayerResidencyError.unknownLayerGroup(targetKey)
      }
      return Self.fingerprint(array) == baselineFingerprint
    }
    let swapAndRestorePass = baselineEqualsRestored && restoredParameterMatchesBaseline

    return MLXParameterSwapReport(
      targetParameterKey: targetKey,
      prompt: prompt,
      baselineOutput: baseline,
      perturbedOutput: perturbed,
      restoredOutput: restored,
      restoredParameterMatchesBaseline: restoredParameterMatchesBaseline,
      baselineEqualsRestored: baselineEqualsRestored,
      perturbedDiffers: perturbedDiffers,
      swapAndRestorePass: swapAndRestorePass,
      targetWasLoadBearing: perturbedDiffers
    )
  }

  private static func fingerprint(_ array: MLXArray) -> String {
    eval(array)
    return "\(array.dtype);\(array.shape);\(array.sum().item(Float.self));\(array.min().item(Float.self));\(array.max().item(Float.self))"
  }
}
