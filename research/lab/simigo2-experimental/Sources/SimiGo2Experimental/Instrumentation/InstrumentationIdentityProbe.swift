import Foundation
import Crypto
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import Tokenizers

public enum InstrumentationIdentityCaptureKind: String, Codable, Sendable {
    case observationValue
    case outputLogits
}

public struct InstrumentationCaptureValue: Codable, Equatable, Sendable {
    public let kind: InstrumentationIdentityCaptureKind
    public let shape: [Int]
    public let dtype: String
    public let checksum: String

    init(kind: InstrumentationIdentityCaptureKind, array: MLXArray) {
        self.kind = kind
        self.shape = array.shape
        self.dtype = String(describing: array.dtype)
        self.checksum = InstrumentationIdentityProbe.sha256Base64(array)
    }
}

public struct InstrumentationProbeModule: Codable, Equatable, Sendable {
    public let path: String
    public let originalType: String
    public let replacementType: String
    public let quantized: Bool
}

public struct InstrumentationComparison: Codable, Equatable, Sendable {
    public let baseline: InstrumentationCaptureValue
    public let instrumented: InstrumentationCaptureValue
    public let maxAbsoluteDifference: Float
    public let exactlyEqual: Bool
}

public struct InstrumentationIdentityProbeReport: Codable, Equatable, Sendable {
    public let status: String
    public let modelType: String
    public let boundary: String
    public let observationPath: String
    public let observationGranularity: String
    public let forwardExecuted: Bool
    public let tokenIDs: [Int]
    public let baselineOutput: InstrumentationCaptureValue
    public let instrumentedOutput: InstrumentationCaptureValue
    public let outputComparison: InstrumentationComparison
    public let observations: [InstrumentationCaptureValue]
    public let baselineForwardMilliseconds: Double
    public let instrumentedForwardMilliseconds: Double
    public let captureMilliseconds: Double
    public let captureOverheadPercent: String
    public let overheadEstablished: Bool
    public let timingBoundary: String
    public let peakMemoryOverheadMegabytes: Double
    public let instrumentedModules: [InstrumentationProbeModule]
}

public enum InstrumentationIdentityProbeError: Error, Equatable {
    case missingObservationPath(String)
    case observationPathIsNotInstrumentable(String)
    case duplicateObservationPath(String)
}

extension InstrumentationIdentityProbeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingObservationPath(let path):
            "missing observation path: \(path)"
        case .observationPathIsNotInstrumentable(let path):
            "observation path is not Linear or SwitchLinear: \(path)"
        case .duplicateObservationPath(let path):
            "duplicate observation path: \(path)"
        }
    }
}

public final class InstrumentationCaptureBox: @unchecked Sendable {
    public init() {}

    private let lock = NSLock()
    private var values: [MLXArray] = []

    func append(_ value: MLXArray) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [MLXArray] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class InstrumentedLinear: Linear {
    let captureBox: InstrumentationCaptureBox

    init(cloning source: Linear, captureBox: InstrumentationCaptureBox) {
        self.captureBox = captureBox
        super.init(weight: source.weight, bias: source.bias)
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        let output = super.callAsFunction(x)
        captureBox.append(output)
        return output
    }
}

final class InstrumentedQuantizedLinear: Linear {
    let captureBox: InstrumentationCaptureBox
    let clonedWeight: MLXArray
    let clonedBias: MLXArray?
    let clonedScales: MLXArray
    let clonedBiases: MLXArray?
    let clonedGroupSize: Int
    let clonedBits: Int
    let clonedMode: QuantizationMode

    init(cloning source: QuantizedLinear, captureBox: InstrumentationCaptureBox) {
        self.captureBox = captureBox
        let values = Dictionary(
            uniqueKeysWithValues: source.parameters().flattened()
        )
        guard let weight = values["weight"] else {
            fatalError("QuantizedLinear without weight parameter")
        }
        self.clonedWeight = weight
        self.clonedScales = source.scales
        self.clonedBiases = source.biases
        self.clonedBias = values["bias"]
        self.clonedGroupSize = source.groupSize
        self.clonedBits = source.bits
        self.clonedMode = source.mode
        super.init(weight: clonedWeight, bias: clonedBias)
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        var output = MLX.quantizedMM(
            x,
            clonedWeight,
            scales: clonedScales,
            biases: clonedBiases,
            transpose: true,
            groupSize: clonedGroupSize,
            bits: clonedBits,
            mode: clonedMode
        )
        if let clonedBias {
            output = output + clonedBias
        }
        captureBox.append(output)
        return output
    }
}

final class InstrumentedSwitchLinear: SwitchLinear {
    let captureBox: InstrumentationCaptureBox

    init(
        inputDims: Int,
        outputDims: Int,
        numExperts: Int,
        captureBox: InstrumentationCaptureBox
    ) {
        self.captureBox = captureBox
        super.init(
            inputDims: inputDims,
            outputDims: outputDims,
            numExperts: numExperts
        )
    }

    override func callAsFunction(
        _ x: MLXArray,
        _ indices: MLXArray,
        sortedIndices: Bool = false
    ) -> MLXArray {
        let output = super.callAsFunction(x, indices, sortedIndices: sortedIndices)
        captureBox.append(output)
        return output
    }
}

final class InstrumentedQuantizedSwitchLinear: SwitchLinear {
    let captureBox: InstrumentationCaptureBox
    let clonedWeight: MLXArray
    let clonedBias: MLXArray?
    let quantizedScales: MLXArray
    let quantizedBiases: MLXArray?
    let quantizedGroupSize: Int
    let quantizedBits: Int
    let quantizedMode: QuantizationMode

    init(
        inputDims: Int,
        outputDims: Int,
        numExperts: Int,
        weight: MLXArray,
        bias: MLXArray?,
        scales: MLXArray,
        biases: MLXArray?,
        groupSize: Int,
        bits: Int,
        mode: QuantizationMode,
        captureBox: InstrumentationCaptureBox
    ) {
        self.captureBox = captureBox
        self.clonedWeight = weight
        self.clonedBias = bias
        self.quantizedScales = scales
        self.quantizedBiases = biases
        self.quantizedGroupSize = groupSize
        self.quantizedBits = bits
        self.quantizedMode = mode
        super.init(
            inputDims: inputDims,
            outputDims: outputDims,
            numExperts: numExperts,
            weight: weight,
            bias: bias
        )
    }

    override func callAsFunction(
        _ x: MLXArray,
        _ indices: MLXArray,
        sortedIndices: Bool = false
    ) -> MLXArray {
        var output = MLX.gatherQuantizedMM(
            x,
            clonedWeight,
            scales: quantizedScales,
            biases: quantizedBiases,
            rhsIndices: indices,
            transpose: true,
            groupSize: quantizedGroupSize,
            bits: quantizedBits,
            mode: quantizedMode,
            sortedIndices: sortedIndices
        )
        if let clonedBias {
            output = output + MLX.expandedDimensions(clonedBias[indices], axis: -2)
        }
        captureBox.append(output)
        return output
    }
}

public struct InstrumentationIdentityProbe {
    public init() {}

    public static func supportedObservationPaths(
        model: some MLXNN.Module,
        layerIndices: [Int]
    ) -> [String] {
        let paths = Set(model.leafModules().flattened().map(\.0))
        return layerIndices
            .sorted()
            .map { index -> String in
                let moePath = "model.layers.\(index).mlp.switch_mlp.down_proj"
                let densePath = "model.layers.\(index).mlp.down_proj"
                return paths.contains(moePath) ? moePath : densePath
            }
    }

    public static func install(
        model: some MLXNN.Module,
        observationPaths: Set<String>,
        captureBox: InstrumentationCaptureBox
    ) throws -> [InstrumentationProbeModule] {
        var replacementPaths = Set<String>()
        var replacements: [(String, Module)] = []
        var modules: [InstrumentationProbeModule] = []

        for (path, module) in model.leafModules().flattened() {
            guard observationPaths.contains(path) else { continue }
            guard replacementPaths.insert(path).inserted else {
                throw InstrumentationIdentityProbeError.duplicateObservationPath(path)
            }

            if let quantizedSource = module as? QuantizedSwitchLinear {
                let sourceParameters = quantizedSource.parameters()
                let values = Dictionary(
                    uniqueKeysWithValues: sourceParameters.flattened()
                )
                guard let weight = values["weight"],
                    let scales = values["scales"]
                else {
                    throw InstrumentationIdentityProbeError
                        .observationPathIsNotInstrumentable(path)
                }
                let shape = weight.shape
                let replacement = InstrumentedQuantizedSwitchLinear(
                    inputDims: shape[2],
                    outputDims: shape[1],
                    numExperts: shape[0],
                    weight: weight,
                    bias: values["bias"],
                    scales: scales,
                    biases: values["biases"],
                    groupSize: quantizedSource.groupSize,
                    bits: quantizedSource.bits,
                    mode: quantizedSource.mode,
                    captureBox: captureBox
                )
                replacements.append((path, replacement))
                modules.append(
                    InstrumentationProbeModule(
                        path: path,
                        originalType: String(describing: type(of: module)),
                        replacementType: String(describing: InstrumentedQuantizedSwitchLinear.self),
                        quantized: true
                    )
                )
            } else if let source = module as? SwitchLinear {
                let sourceParameters = source.parameters()
                guard let weight = sourceParameters.flattened()
                    .first(where: { $0.0 == "weight" })?.1
                else {
                    throw InstrumentationIdentityProbeError
                        .observationPathIsNotInstrumentable(path)
                }
                let shape = weight.shape
                let replacement = InstrumentedSwitchLinear(
                    inputDims: shape[2],
                    outputDims: shape[1],
                    numExperts: shape[0],
                    captureBox: captureBox
                )
                replacement.update(
                    parameters: ModuleParameters.unflattened(
                        sourceParameters.flattened().filter {
                            $0.0 == "weight" || $0.0 == "bias"
                        }
                    )
                )
                replacements.append((path, replacement))
                modules.append(
                    InstrumentationProbeModule(
                        path: path,
                        originalType: String(describing: type(of: module)),
                        replacementType: String(describing: InstrumentedSwitchLinear.self),
                        quantized: module is QuantizedSwitchLinear
                    )
                )
            } else if let source = module as? QuantizedLinear {
                // QuantizedLinear is a Linear subclass; it must be cloned with
                // its quantized parameters, otherwise the plain-Linear path
                // would silently change semantics.
                replacements.append(
                    (
                        path,
                        InstrumentedQuantizedLinear(
                            cloning: source,
                            captureBox: captureBox
                        )
                    )
                )
                modules.append(
                    InstrumentationProbeModule(
                        path: path,
                        originalType: String(describing: type(of: module)),
                        replacementType: String(describing: InstrumentedQuantizedLinear.self),
                        quantized: true
                    )
                )
            } else if let source = module as? Linear {
                let replacement = InstrumentedLinear(
                    cloning: source,
                    captureBox: captureBox
                )
                replacements.append((path, replacement))
                modules.append(
                    InstrumentationProbeModule(
                        path: path,
                        originalType: String(describing: type(of: module)),
                        replacementType: String(describing: InstrumentedLinear.self),
                        quantized: module is QuantizedLinear
                    )
                )
            } else {
                throw InstrumentationIdentityProbeError.observationPathIsNotInstrumentable(path)
            }
        }

        let found = Set(modules.map(\.path))
        if let missing = observationPaths.subtracting(found).sorted().first {
            throw InstrumentationIdentityProbeError.missingObservationPath(missing)
        }

        model.update(modules: ModuleChildren.unflattened(replacements))
        return modules.sorted { $0.path < $1.path }
    }

    public static func run(
        modelDirectory: URL,
        prompt: String,
        layerIndices: [Int]
    ) async throws -> InstrumentationIdentityProbeReport {
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )

        return try await container.perform { (context: ModelContext) async throws -> InstrumentationIdentityProbeReport in
            let tokenIDs = try await ChatTemplateGeneration.promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt
            )
            let input = MLXArray(tokenIDs, [1, tokenIDs.count])

            let baselineStart = ContinuousClock.now
            let baselineOutput = context.model(input, cache: nil)
            eval(baselineOutput)
            let baselineForwardMilliseconds = milliseconds(start: baselineStart)
            let baselineMemory = Memory.snapshot()

            let captureBox = InstrumentationCaptureBox()
            let paths = Set(
                supportedObservationPaths(model: context.model, layerIndices: layerIndices)
            )
            let instrumentedModules = try install(
                model: context.model,
                observationPaths: paths,
                captureBox: captureBox
            )

            let instrumentedStart = ContinuousClock.now
            let instrumentedOutput = context.model(input, cache: nil)
            eval(instrumentedOutput)
            let instrumentedForwardMilliseconds = milliseconds(
                start: instrumentedStart
            )
            let instrumentedMemory = Memory.snapshot()

            let captureStart = ContinuousClock.now
            let captured = captureBox.snapshot()
            let baselineLogitValue = InstrumentationCaptureValue(
                kind: .outputLogits,
                array: baselineOutput
            )
            let instrumentedLogitValue = InstrumentationCaptureValue(
                kind: .outputLogits,
                array: instrumentedOutput
            )
            let outputComparison = compare(
                baseline: baselineLogitValue,
                instrumented: instrumentedLogitValue,
                baselineArray: baselineOutput,
                instrumentedArray: instrumentedOutput
            )

            let observedValues = captured.map { observation in
                InstrumentationCaptureValue(
                    kind: .observationValue,
                    array: observation
                )
            }

            let identityPass =
                outputComparison.exactlyEqual
                && captured.count == instrumentedModules.count
                && !observedValues.isEmpty
            let captureMilliseconds = milliseconds(start: captureStart)

            return InstrumentationIdentityProbeReport(
                status: identityPass ? "PASS" : "FAIL",
                modelType: String(describing: type(of: context.model)),
                boundary:
                    "ISOLATED_IDENTITY_PROBE / SINGLE_PROXY_MODULE_POINT / NOT_H_I_X / NOT_DEMAND",
                observationPath: instrumentedModules.first?.path ?? "",
                observationGranularity: instrumentedModules.first?.path.contains(".switch_mlp.") == true
                    ? "MLP_SWITCH_DOWN_PROJ_OUTPUT"
                    : "MLP_DOWN_PROJ_OUTPUT",
                forwardExecuted: true,
                tokenIDs: tokenIDs,
                baselineOutput: baselineLogitValue,
                instrumentedOutput: instrumentedLogitValue,
                outputComparison: outputComparison,
                observations: observedValues,
                baselineForwardMilliseconds: baselineForwardMilliseconds,
                instrumentedForwardMilliseconds: instrumentedForwardMilliseconds,
                captureMilliseconds: captureMilliseconds,
                captureOverheadPercent: "NOT_ESTABLISHED",
                overheadEstablished: false,
                timingBoundary:
                    "RAW_TIMES_ONLY / SINGLE_CONTAINER_WARMUP_ASYMMETRY / OVERHEAD_NOT_ESTABLISHED",
                peakMemoryOverheadMegabytes: Double(
                    instrumentedMemory.peakMemory - baselineMemory.peakMemory
                ) / (1024 * 1024),
                instrumentedModules: instrumentedModules
            )
        }
    }

    static func compare(
        baseline: InstrumentationCaptureValue,
        instrumented: InstrumentationCaptureValue,
        baselineArray: MLXArray,
        instrumentedArray: MLXArray
    ) -> InstrumentationComparison {
        let difference = abs(baselineArray - instrumentedArray)
        let maxDifference = difference.max().item(Float.self)
        return InstrumentationComparison(
            baseline: baseline,
            instrumented: instrumented,
            maxAbsoluteDifference: maxDifference,
            exactlyEqual: baseline.checksum == instrumented.checksum
        )
    }

    static func milliseconds(start: ContinuousClock.Instant) -> Double {
        Double(start.duration(to: .now).components.attoseconds) / 1e18 * 1000
    }

    static func sha256Base64(_ array: MLXArray) -> String {
        eval(array)
        let data = array.asData().data
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
}
