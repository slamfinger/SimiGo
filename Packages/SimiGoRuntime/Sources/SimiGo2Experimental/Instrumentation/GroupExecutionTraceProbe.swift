import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import Tokenizers

/// One observed execution event from the isolated instrumentation path.
/// Minimal observation contract (G1.9-A pilot): the event asserts only that a
/// layer was entered — `layerEntered` is an observation, never a demand
/// claim. No activations, no shapes, no per-event timing are retained.
public enum ExecutionTraceEventKind: String, Codable, Sendable {
    case layerEntered
}

public struct ExecutionTraceEvent: Codable, Equatable, Sendable {
    public let kind: ExecutionTraceEventKind
    public let sequence: Int
    public let modulePath: String
    public let decoderLayer: Int
}

public final class ExecutionTraceEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ExecutionTraceEvent] = []
    private var counter = 0

    public init() {}

    func append(modulePath: String, decoderLayer: Int) {
        lock.lock()
        counter += 1
        let event = ExecutionTraceEvent(
            kind: .layerEntered,
            sequence: counter,
            modulePath: modulePath,
            decoderLayer: decoderLayer
        )
        events.append(event)
        lock.unlock()
    }

    public func snapshot() -> [ExecutionTraceEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    public func clear() {
        lock.lock()
        events.removeAll()
        counter = 0
        lock.unlock()
    }
}

final class TracedLinear: Linear {
    let box: ExecutionTraceEventBox
    let path: String
    let layer: Int

    init(cloning source: Linear, box: ExecutionTraceEventBox, path: String, layer: Int) {
        self.box = box
        self.path = path
        self.layer = layer
        super.init(weight: source.weight, bias: source.bias)
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        let output = super.callAsFunction(x)
        box.append(modulePath: path, decoderLayer: layer)
        return output
    }
}

/// Mirrors MLXNN QuantizedLinear.callAsFunction exactly (quantizedMM + bias)
/// so dense quantized checkpoints are instrumented without changing semantics.
final class TracedQuantizedLinear: Linear {
    let box: ExecutionTraceEventBox
    let path: String
    let layer: Int
    let clonedWeight: MLXArray
    let clonedBias: MLXArray?
    let clonedScales: MLXArray
    let clonedBiases: MLXArray?
    let clonedGroupSize: Int
    let clonedBits: Int
    let clonedMode: QuantizationMode

    init(
        cloning source: QuantizedLinear,
        box: ExecutionTraceEventBox,
        path: String,
        layer: Int
    ) {
        self.box = box
        self.path = path
        self.layer = layer
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
        box.append(modulePath: path, decoderLayer: layer)
        return output
    }
}

final class TracedSwitchLinear: SwitchLinear {
    let box: ExecutionTraceEventBox
    let path: String
    let layer: Int

    init(
        inputDims: Int,
        outputDims: Int,
        numExperts: Int,
        box: ExecutionTraceEventBox,
        path: String,
        layer: Int
    ) {
        self.box = box
        self.path = path
        self.layer = layer
        super.init(inputDims: inputDims, outputDims: outputDims, numExperts: numExperts)
    }

    override func callAsFunction(
        _ x: MLXArray,
        _ indices: MLXArray,
        sortedIndices: Bool = false
    ) -> MLXArray {
        let output = super.callAsFunction(x, indices, sortedIndices: sortedIndices)
        box.append(modulePath: path, decoderLayer: layer)
        return output
    }
}

/// Mirrors the instrumented quantized switch path: recomputes
/// gatherQuantizedMM with the cloned quantized parameters and appends only an
/// event.
final class TracedQuantizedSwitchLinear: SwitchLinear {
    let box: ExecutionTraceEventBox
    let path: String
    let layer: Int
    let clonedWeight: MLXArray
    let clonedBias: MLXArray?
    let clonedScales: MLXArray
    let clonedBiases: MLXArray?
    let clonedGroupSize: Int
    let clonedBits: Int
    let clonedMode: QuantizationMode

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
        box: ExecutionTraceEventBox,
        path: String,
        layer: Int
    ) {
        self.box = box
        self.path = path
        self.layer = layer
        self.clonedWeight = weight
        self.clonedBias = bias
        self.clonedScales = scales
        self.clonedBiases = biases
        self.clonedGroupSize = groupSize
        self.clonedBits = bits
        self.clonedMode = mode
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
            scales: clonedScales,
            biases: clonedBiases,
            rhsIndices: indices,
            transpose: true,
            groupSize: clonedGroupSize,
            bits: clonedBits,
            mode: clonedMode,
            sortedIndices: sortedIndices
        )
        if let clonedBias {
            output = output + MLX.expandedDimensions(clonedBias[indices], axis: -2)
        }
        box.append(modulePath: path, decoderLayer: layer)
        return output
    }
}

/// G1.9-A isolated instrumentation: captures a measured group/layer execution
/// trace from real forward passes without modifying MLX internals and without
/// retaining activation values.
public enum GroupExecutionTraceProbe {
    public static func decoderLayer(fromPath path: String) -> Int {
        guard
            let range = path.range(of: #"layers\.(\d+)\."#, options: .regularExpression)
        else {
            return -1
        }
        let digits = path[range].split(separator: ".").first { $0.allSatisfy(\.isNumber) }
        return digits.flatMap { Int($0) } ?? -1
    }

    /// All MLP down-projection observation paths across decoder layers — both
    /// fused-MoE (`mlp.switch_mlp.down_proj`) and dense (`mlp.down_proj`)
    /// variants, under any model-specific prefix (`model.layers.*`,
    /// `language_model.model.layers.*`). Shared-expert projections are
    /// excluded by construction: their paths end `.shared_expert.down_proj`,
    /// so every captured event maps to exactly one declared optional group.
    public static func allObservationPaths(model: some MLXNN.Module) -> [String] {
        model.leafModules().flattened()
            .map(\.0)
            .filter { path in
                path.hasSuffix(".mlp.down_proj")
                    || path.hasSuffix(".mlp.switch_mlp.down_proj")
            }
            .sorted()
    }

    public static func passCount(events: [ExecutionTraceEvent]) -> Int {
        guard let firstLayerEvent = events.first(where: { $0.decoderLayer == 0 }) else {
            return 0
        }
        let firstPath = firstLayerEvent.modulePath
        return events.filter { $0.modulePath == firstPath }.count
    }

    /// Stability comparison: two traces are stable when their observed
    /// (module, layer) event streams are identical. Stability is an
    /// instrumentation property — it does not imply predictability.
    public static func tracesStable(_ a: [ExecutionTraceEvent], _ b: [ExecutionTraceEvent]) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            let sameModule = lhs.modulePath == rhs.modulePath
            let sameLayer = lhs.decoderLayer == rhs.decoderLayer
            if !(sameModule && sameLayer) {
                return false
            }
        }
        return true
    }

    /// Discovery helper: lists leaf module paths of the loaded model that
    /// contain the filter substring. Used to register the actual module
    /// naming per model class before installing observation points.
    public static func leafModulePathAudit(
        modelDirectory: URL,
        filterSubstring: String
    ) async throws -> LeafModulePathAuditReport {
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        return await container.perform { (context: ModelContext) -> LeafModulePathAuditReport in
            let paths = context.model.leafModules().flattened().map(\.0).sorted()
            let matching = paths.filter { $0.contains(filterSubstring) }
            return LeafModulePathAuditReport(
                modelType: String(describing: type(of: context.model)),
                leafModuleCount: paths.count,
                matchingCount: matching.count,
                sampleMatchingPaths: Array(matching.prefix(80)),
                matchingLayers: Set(matching.compactMap { decoderLayer(fromPath: $0) })
                    .sorted()
            )
        }
    }

    public static func run(
        modelDirectory: URL,
        prompt: String = "Return exactly one word: ping",
        maxTokens: Int = 8
    ) async throws -> GroupExecutionTraceReport {
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )

        // Phase 1: tokenize, warm up, baseline logits checksum. Performed in
        // its own perform block: ChatTemplateGeneration.generate performs its
        // own container access, so no generation may run nested inside this
        // closure.
        let (tokenIDs, baselineChecksum, modelType) = try await container.perform {
            (context: ModelContext) async throws -> ([Int], String, String) in
            let tokenIDs = try await ChatTemplateGeneration.promptTokenIDs(
                tokenizer: context.tokenizer,
                modelDirectory: modelDirectory,
                prompt: prompt
            )
            let input = MLXArray(tokenIDs, [1, tokenIDs.count])
            _ = context.model(input, cache: nil)
            let logits = context.model(input, cache: nil)
            eval(logits)
            let checksum = InstrumentationIdentityProbe.sha256Base64(logits)
            let modelType = String(describing: type(of: context.model))
            Memory.clearCache()
            return (tokenIDs, checksum, modelType)
        }

        func generation() async throws -> String {
            try await ChatTemplateGeneration.generate(
                container: container,
                modelDirectory: modelDirectory,
                prompt: prompt,
                maxTokens: maxTokens
            )
        }

        let memoryBefore = Memory.snapshot()
        _ = try await generation()
        let baselineSteadyStart = ContinuousClock.now
        let baselineText = try await generation()
        let baselineSteadyMilliseconds = elapsedMs(start: baselineSteadyStart)
        let baselineMemoryAfter = Memory.snapshot()

        // Phase 2: install trace modules on the model object. The replacement
        // persists across subsequent perform blocks.
        let box = ExecutionTraceEventBox()
        let installed = try await container.perform {
            (context: ModelContext) async throws -> [String] in
            let paths = allObservationPaths(model: context.model)
            return try install(
                model: context.model,
                observationPaths: Set(paths),
                box: box
            )
        }

        // Phase 3: instrumented single-forward logits identity.
        let instrumentedChecksum = try await container.perform {
            (context: ModelContext) async throws -> String in
            let input = MLXArray(tokenIDs, [1, tokenIDs.count])
            let logits = context.model(input, cache: nil)
            eval(logits)
            let checksum = InstrumentationIdentityProbe.sha256Base64(logits)
            Memory.clearCache()
            return checksum
        }
        let instrumentedForwardEventCount = box.snapshot().count
        box.clear()

        // Phase 4: two instrumented generations; stability = both event
        // streams identical modulo timestamps, steady pass timed.
        let instrumentedWarmText = try await generation()
        let instrumentedWarmTrace = box.snapshot()
        box.clear()
        let instrumentedSteadyStart = ContinuousClock.now
        let instrumentedText = try await generation()
        let instrumentedSteadyMilliseconds = elapsedMs(start: instrumentedSteadyStart)
        let instrumentedMemoryAfter = Memory.snapshot()
        let trace = box.snapshot()

        let identityPass = baselineChecksum == instrumentedChecksum
        let textIdentityPass = baselineText == instrumentedWarmText
            && baselineText == instrumentedText
        let observedPassCount = passCount(events: trace)
        let eventsPerPass = observedPassCount == 0 ? 0 : trace.count / observedPassCount
        // Generation may stop at EOS before maxTokens, so the pass count is a
        // measured quantity, not an assumption; stability requires the two
        // instrumented streams to agree exactly.
        let stabilityPass =
            tracesStable(instrumentedWarmTrace, trace)
            && instrumentedWarmText == instrumentedText
            && eventsPerPass == installed.count
            && observedPassCount >= 1
        let steadyOverheadPercent =
            baselineSteadyMilliseconds == 0
            ? nil
            : (instrumentedSteadyMilliseconds - baselineSteadyMilliseconds)
                / baselineSteadyMilliseconds * 100

        return GroupExecutionTraceReport(
            status: identityPass && textIdentityPass && stabilityPass ? "PASS" : "FAIL",
            modelType: modelType,
            boundary:
                "ISOLATED_INSTRUMENTATION / EVENT_ONLY_TRACE / NOT_PREDICTION / NOT_DEMAND / EXPERT_DEMAND_NOT_INSTRUMENTED",
            promptTokenCount: tokenIDs.count,
            maxTokens: maxTokens,
            instrumentedModuleCount: installed.count,
            baselineLogitsChecksum: baselineChecksum,
            instrumentedLogitsChecksum: instrumentedChecksum,
            logitsIdentityPass: identityPass,
            baselineText: baselineText,
            instrumentedText: instrumentedText,
            textIdentityPass: textIdentityPass,
            instrumentedForwardEventCount: instrumentedForwardEventCount,
            traceEventCount: trace.count,
            passCount: observedPassCount,
            eventsPerPass: eventsPerPass,
            traceStabilityPass: stabilityPass,
            baselineSteadyGenerationMilliseconds: baselineSteadyMilliseconds,
            instrumentedSteadyGenerationMilliseconds: instrumentedSteadyMilliseconds,
            steadyStateOverheadPercent: steadyOverheadPercent,
            timingBoundary:
                "WARMUP_SYMMETRIC / ONE_STEADY_BASELINE_VS_ONE_STEADY_INSTRUMENTED / OVERHEAD_DESCRIPTIVE",
            peakMemoryOverheadMegabytes: Double(
                instrumentedMemoryAfter.peakMemory - max(memoryBefore.peakMemory, baselineMemoryAfter.peakMemory)
            ) / (1024 * 1024),
            trace: trace
        )
    }

    static func install(
        model: some MLXNN.Module,
        observationPaths: Set<String>,
        box: ExecutionTraceEventBox
    ) throws -> [String] {
        var replacementPaths = Set<String>()
        var replacements: [(String, Module)] = []
        var installedPaths: [String] = []

        for (path, module) in model.leafModules().flattened() {
            guard observationPaths.contains(path) else { continue }
            guard replacementPaths.insert(path).inserted else {
                throw InstrumentationIdentityProbeError.duplicateObservationPath(path)
            }
            let layer = decoderLayer(fromPath: path)

            if let source = module as? QuantizedSwitchLinear {
                let values = Dictionary(
                    uniqueKeysWithValues: source.parameters().flattened()
                )
                guard let weight = values["weight"], let scales = values["scales"] else {
                    throw InstrumentationIdentityProbeError
                        .observationPathIsNotInstrumentable(path)
                }
                let shape = weight.shape
                replacements.append(
                    (
                        path,
                        TracedQuantizedSwitchLinear(
                            inputDims: shape[2],
                            outputDims: shape[1],
                            numExperts: shape[0],
                            weight: weight,
                            bias: values["bias"],
                            scales: scales,
                            biases: values["biases"],
                            groupSize: source.groupSize,
                            bits: source.bits,
                            mode: source.mode,
                            box: box,
                            path: path,
                            layer: layer
                        )
                    )
                )
            } else if let source = module as? SwitchLinear {
                let parameters = source.parameters()
                let values = Dictionary(
                    uniqueKeysWithValues: parameters.flattened()
                )
                guard let weight = values["weight"] else {
                    throw InstrumentationIdentityProbeError
                        .observationPathIsNotInstrumentable(path)
                }
                let shape = weight.shape
                let replacement = TracedSwitchLinear(
                    inputDims: shape[2],
                    outputDims: shape[1],
                    numExperts: shape[0],
                    box: box,
                    path: path,
                    layer: layer
                )
                replacement.update(
                    parameters: ModuleParameters.unflattened(
                        parameters.flattened().filter { $0.0 == "weight" || $0.0 == "bias" }
                    )
                )
                replacements.append((path, replacement))
            } else if let source = module as? QuantizedLinear {
                replacements.append(
                    (
                        path,
                        TracedQuantizedLinear(
                            cloning: source,
                            box: box,
                            path: path,
                            layer: layer
                        )
                    )
                )
            } else if let source = module as? Linear {
                replacements.append(
                    (
                        path,
                        TracedLinear(
                            cloning: source,
                            box: box,
                            path: path,
                            layer: layer
                        )
                    )
                )
            } else {
                throw InstrumentationIdentityProbeError.observationPathIsNotInstrumentable(path)
            }
            installedPaths.append(path)
        }

        if let missing = observationPaths.subtracting(Set(installedPaths)).sorted().first {
            throw InstrumentationIdentityProbeError.missingObservationPath(missing)
        }

        model.update(modules: ModuleChildren.unflattened(replacements))
        return installedPaths.sorted()
    }

    private static func elapsedMs(start: ContinuousClock.Instant) -> Double {
        Double(start.duration(to: .now).components.attoseconds) / 1e18 * 1000
    }
}
public struct LeafModulePathAuditReport: Codable, Sendable {
    public let modelType: String
    public let leafModuleCount: Int
    public let matchingCount: Int
    public let sampleMatchingPaths: [String]
    public let matchingLayers: [Int]
}

public struct GroupExecutionTraceReport: Codable, Sendable {
    public let status: String
    public let modelType: String
    public let boundary: String
    public let promptTokenCount: Int
    public let maxTokens: Int
    public let instrumentedModuleCount: Int
    public let baselineLogitsChecksum: String
    public let instrumentedLogitsChecksum: String
    public let logitsIdentityPass: Bool
    public let baselineText: String
    public let instrumentedText: String
    public let textIdentityPass: Bool
    public let instrumentedForwardEventCount: Int
    public let traceEventCount: Int
    public let passCount: Int
    public let eventsPerPass: Int
    public let traceStabilityPass: Bool
    public let baselineSteadyGenerationMilliseconds: Double
    public let instrumentedSteadyGenerationMilliseconds: Double
    public let steadyStateOverheadPercent: Double?
    public let timingBoundary: String
    public let peakMemoryOverheadMegabytes: Double
    public let trace: [ExecutionTraceEvent]
}
