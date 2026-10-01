import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import Tokenizers

/// O4 full-vs-segmented generation performance differential probe
/// (user-directed, 2026-09-26).
///
/// On a model where BOTH residency strategies fit in physical memory,
/// measure the per-token cost of:
///
///   segmented — core resident; per token, per segment: materialize →
///               forwardLayerRange → release (the oversized-model path)
///   full      — all parameters resident, whole-graph forward per token
///
/// Both paths compute the SAME cacheless greedy function (full sequence
/// re-forward per token, no KV authority) on the same model instance; the
/// only difference is the residency/execution strategy. Cross-path token
/// equality is recorded descriptively only — no numeric-equivalence claim
/// (frozen C″ protocol boundary). Order is fixed: segmented first (its
/// pass 1 reads cold from disk, pass 2 warm from page cache), then full.
public struct O4SegmentBreakdown: Codable, Sendable {
    public let segment: Int
    public let readMs: Double
    public let updateMs: Double
    public let forwardMs: Double
    public let releaseMs: Double
}

public struct O4TokenSample: Codable, Sendable {
    public let token: Int
    public let totalMs: Double
    public let segments: [O4SegmentBreakdown]?
    public let activeMiB: Int64
    public let footprintMiB: Int64
    public let swapMiB: Int64
}

public struct O4PathReport: Codable, Sendable {
    public let path: String
    public let loadMs: Double
    public let residentActiveMiB: Int64
    public let residentFootprintMiB: Int64
    public let tokensByPass: [[Int]]
    public let samplesByPass: [[O4TokenSample]]
    public let meanTokenMsByPass: [Double]
    public let peakActiveMiB: Int64
    public let peakFootprintMiB: Int64
}

public struct O4GenerationReport: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let promptTokens: Int
    public let segmentSize: Int
    public let segmentCount: Int
    public let maxFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let paths: [O4PathReport]
    public let crossPathTokensIdentical: Bool
    public let boundary: String
}

public enum O4GenerationProbe {
    public static let protocolVersion = "G1.9-O4.GEN.V1"

    private static let clock = ContinuousClock()

    private static func msSince(_ start: ContinuousClock.Instant) -> Double {
        // NOTE: components.attoseconds alone is only the sub-second
        // component — durations >= 1 s silently lose their whole seconds
        // (measured: a ~6 s token reported as its remainder). Use the full
        // duration.
        let duration = start.duration(to: clock.now)
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return seconds * 1000
    }

    private static func swapUsedMiB() -> Int64 {
        var size = 0
        sysctlbyname("vm.swapusage", nil, &size, nil, 0)
        guard size > 0 else { return 0 }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("vm.swapusage", &buffer, &size, nil, 0)
        let raw = String(cString: buffer)
        let components = raw.split(separator: " ")
        if let usedIndex = components.firstIndex(of: "used"), usedIndex + 1 < components.count {
            let value = components[usedIndex + 1]
            let magnitude = Double(value.dropLast()) ?? 0
            let bytes: Double
            switch value.last {
            case "G": bytes = magnitude * 1024 * 1024 * 1024
            case "M": bytes = magnitude * 1024 * 1024
            case "K": bytes = magnitude * 1024
            default: bytes = magnitude
            }
            return Int64(bytes / 1048576)
        }
        return 0
    }

    private static func memoryGauge() -> (activeMiB: Int64, footprintMiB: Int64, swapMiB: Int64) {
        let mlx = Memory.snapshot()
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        let footprint = result == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
        let swap = swapUsedMiB()
        FileHandle.standardError.write(
            Data(
                "O4 gauge: active=\(mlx.activeMemory / 1048576)MiB footprint=\(footprint / 1048576)MiB swap=\(swap)MiB\n"
                    .utf8)
        )
        return (Int64(mlx.activeMemory / 1048576), footprint / 1048576, swap)
    }

    private static func quantizedModel(
        modelDirectory: URL, configData: Data, baseConfig: BaseConfiguration
    ) async throws -> Qwen35MoEModel {
        let index = try JSONSerialization.jsonObject(
            with: Data(contentsOf: modelDirectory.appendingPathComponent("model.safetensors.index.json"))
        ) as? [String: Any]
        guard let weightMap = index?["weight_map"] as? [String: String] else {
            throw O3CError.invalidTensorIndex
        }
        let model = try await MLXLLM.LLMModelFactory.shared.typeRegistry.createModel(
            configuration: configData, modelType: baseConfig.modelType
        ) as! Qwen35MoEModel
        let quantizedModules: Set<String> = Set(
            weightMap.keys.filter { $0.hasSuffix(".scales") }.map { String($0.dropLast(".scales".count)) }
        )
        quantize(model: model, filter: { path, _ in
            guard quantizedModules.contains(path) else { return nil }
            if let perLayer = baseConfig.perLayerQuantization?.quantization(layer: path) {
                return (groupSize: perLayer.groupSize, bits: perLayer.bits, mode: perLayer.mode)
            }
            return nil
        }, apply: { module, groupSize, bits, mode in
            quantizeSingle(layer: module, groupSize: groupSize, bits: bits, mode: mode)
        })
        return model
    }

    public static func run(
        modelDirectory: URL,
        prompt: String = "def add(a, b): return a + b",
        maxNewTokens: Int = 8,
        passes: Int = 2,
        segmentSize: Int = 10
    ) async throws -> O4GenerationReport {
        let configData = try Data(contentsOf: modelDirectory.appendingPathComponent("config.json"))
        let baseConfig = try JSONDecoder.json5().decode(BaseConfiguration.self, from: configData)
        let index = try JSONSerialization.jsonObject(
            with: Data(contentsOf: modelDirectory.appendingPathComponent("model.safetensors.index.json"))
        ) as? [String: Any]
        guard let weightMap = index?["weight_map"] as? [String: String] else {
            throw O3CError.invalidTensorIndex
        }

        let modelType = baseConfig.modelType
        let reader = try PerTensorSafetensorsReader(
            modelDirectory: modelDirectory, weightMap: weightMap
        )
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
        let messages: [[String: any Sendable]] = [["role": "user", "content": prompt]]
        let promptTokenIDs = try tokenizer.applyChatTemplate(
            messages: messages,
            chatTemplate: nil,
            addGenerationPrompt: true,
            truncation: false,
            maxLength: nil,
            tools: nil,
            additionalContext: ["enable_thinking": false]
        )

        // Segment partition from the model's actual layer count.
        let configObject = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        let textConfigObject = configObject?["text_config"] as? [String: Any]
        let totalLayers = (textConfigObject?["num_hidden_layers"] as? Int) ?? 40
        var segments: [ClosedRange<Int>] = []
        var start = 0
        while start < totalLayers {
            let end = min(start + segmentSize - 1, totalLayers - 1)
            segments.append(start...end)
            start = end + 1
        }

        let switchNames: [String] = reader.locations.values
            .filter { $0.name.contains(".switch_mlp.") }
            .map { $0.name }
        let coreNames: [String] = reader.locations.values
            .filter { !$0.name.contains(".switch_mlp.") }
            .map { $0.name }

        func loadReal(_ names: [String]) throws -> [String: MLXArray] {
            var map: [String: MLXArray] = [:]
            for name in names {
                map[name] = try autoreleasepool { try reader.loadTensor(named: name) }
            }
            eval(map.values.map { $0 })
            return map
        }

        // ---- Skeleton: createModel -> quantize -> placeholder-first update.
        // Lazily-created quantized modules hold lazy RANDOM arrays; ONE pure
        // assignment update replaces every parameter with real (core) or
        // zero-size placeholder (switch_mlp) tensors before any evaluation.
        let model = try await quantizedModel(
            modelDirectory: modelDirectory, configData: configData, baseConfig: baseConfig
        )
        let coreArrays = try loadReal(coreNames)
        var placeholderMap = coreArrays
        for name in switchNames {
            placeholderMap[name] = MLXArray([Int](), [0])
        }
        let covered = Set(placeholderMap.keys)
        for (path, _) in model.parameters().flattened() where !covered.contains(path) {
            placeholderMap[path] = MLXArray([Int](), [0])
        }
        try model.update(parameters: ModuleParameters.unflattened(placeholderMap), verify: [])
        Memory.clearCache()

        var paths: [O4PathReport] = []

        // ================= Path 1: SEGMENTED (runs first; pass 1 reads
        // cold from disk, pass 2 warm from page cache) =================
        do {
            let loadStart = clock.now
            let segmentedGauge = memoryGauge()
            let loadMs = msSince(loadStart)
            var peakActive = segmentedGauge.activeMiB
            var peakFootprint = segmentedGauge.footprintMiB

            var tokensByPass: [[Int]] = []
            var samplesByPass: [[O4TokenSample]] = []
            var meanByPass: [Double] = []

            for _ in 1...passes {
                var ids = promptTokenIDs
                var passTokens: [Int] = []
                var passSamples: [O4TokenSample] = []
                for _ in 0..<maxNewTokens {
                    let tokenStart = clock.now
                    var hidden = model.embedInputs(MLXArray(ids, [1, ids.count]))
                    eval(hidden)
                    var breakdowns: [O4SegmentBreakdown] = []
                    for (segIndex, segment) in segments.enumerated() {
                        var readMs = 0.0, updateMs = 0.0, forwardMs = 0.0, releaseMs = 0.0
                        do {
                            // Materialize: read + eval inside this scope; the
                            // dict must drop its refs when the scope exits.
                            let readStart = clock.now
                            var arrays: [String: MLXArray] = [:]
                            for name in switchNames {
                                if let range = name.range(
                                    of: #"layers\.(\d+)\."#, options: .regularExpression
                                ) {
                                    let digits =
                                        name[range].split(separator: ".").compactMap { Int($0) }
                                    if let layer = digits.first, segment.contains(layer) {
                                        arrays[name] = try autoreleasepool {
                                            try reader.loadTensor(named: name)
                                        }
                                    }
                                }
                            }
                            eval(arrays.values.map { $0 })
                            readMs = msSince(readStart)

                            let updateStart = clock.now
                            try model.update(
                                parameters: ModuleParameters.unflattened(arrays), verify: []
                            )
                            updateMs = msSince(updateStart)
                        }
                        let forwardStart = clock.now
                        hidden = model.forwardLayerRange(
                            hidden,
                            layerRange: segment.lowerBound..<(segment.upperBound + 1),
                            cache: nil
                        )
                        eval(hidden)
                        forwardMs = msSince(forwardStart)

                        let releaseStart = clock.now
                        var placeholders: [String: MLXArray] = [:]
                        for name in switchNames {
                            if let range = name.range(
                                of: #"layers\.(\d+)\."#, options: .regularExpression
                            ) {
                                let digits = name[range].split(separator: ".").compactMap { Int($0) }
                                if let layer = digits.first, segment.contains(layer) {
                                    placeholders[name] = MLXArray([Int](), [0])
                                }
                            }
                        }
                        try model.update(
                            parameters: ModuleParameters.unflattened(placeholders), verify: []
                        )
                        Memory.clearCache()
                        releaseMs = msSince(releaseStart)

                        breakdowns.append(
                            O4SegmentBreakdown(
                                segment: segIndex, readMs: readMs, updateMs: updateMs,
                                forwardMs: forwardMs, releaseMs: releaseMs)
                        )
                    }
                    let projectStart = clock.now
                    let logits = model.projectOutput(hidden)[0, -1]
                    eval(logits)
                    let next = logits.argMax().item(Int.self)
                    let totalMs = msSince(tokenStart)
                    _ = projectStart

                    let gauge = memoryGauge()
                    peakActive = max(peakActive, gauge.activeMiB)
                    peakFootprint = max(peakFootprint, gauge.footprintMiB)
                    passTokens.append(next)
                    ids.append(next)
                    passSamples.append(
                        O4TokenSample(
                            token: next, totalMs: totalMs, segments: breakdowns,
                            activeMiB: gauge.activeMiB, footprintMiB: gauge.footprintMiB,
                            swapMiB: gauge.swapMiB)
                    )
                }
                tokensByPass.append(passTokens)
                samplesByPass.append(passSamples)
                meanByPass.append(passSamples.map { $0.totalMs }.reduce(0, +) / Double(max(1, passSamples.count)))
            }
            let endGauge = memoryGauge()
            paths.append(
                O4PathReport(
                    path: "segmented", loadMs: loadMs,
                    residentActiveMiB: segmentedGauge.activeMiB,
                    residentFootprintMiB: segmentedGauge.footprintMiB,
                    tokensByPass: tokensByPass, samplesByPass: samplesByPass,
                    meanTokenMsByPass: meanByPass, peakActiveMiB: peakActive,
                    peakFootprintMiB: peakFootprint)
            )
            _ = endGauge
        }

        // ================= Path 2: FULL (upgrade the same model instance to
        // all-real residency; whole-graph forward per token) =============
        do {
            let loadStart = clock.now
            var fullArrays = try loadReal(switchNames)
            fullArrays.merge(coreArrays) { _, new in new }
            try model.update(parameters: ModuleParameters.unflattened(fullArrays), verify: [])
            eval(model.parameters())
            Memory.clearCache()
            let loadMs = msSince(loadStart)
            let fullGauge = memoryGauge()

            var peakActive = fullGauge.activeMiB
            var peakFootprint = fullGauge.footprintMiB
            var tokensByPass: [[Int]] = []
            var samplesByPass: [[O4TokenSample]] = []
            var meanByPass: [Double] = []

            for _ in 1...passes {
                var ids = promptTokenIDs
                var passTokens: [Int] = []
                var passSamples: [O4TokenSample] = []
                for _ in 0..<maxNewTokens {
                    let tokenStart = clock.now
                    let logits = model(MLXArray(ids, [1, ids.count]), cache: nil)[0, -1]
                    eval(logits)
                    let next = logits.argMax().item(Int.self)
                    let totalMs = msSince(tokenStart)
                    let gauge = memoryGauge()
                    peakActive = max(peakActive, gauge.activeMiB)
                    peakFootprint = max(peakFootprint, gauge.footprintMiB)
                    passTokens.append(next)
                    ids.append(next)
                    passSamples.append(
                        O4TokenSample(
                            token: next, totalMs: totalMs, segments: nil,
                            activeMiB: gauge.activeMiB, footprintMiB: gauge.footprintMiB,
                            swapMiB: gauge.swapMiB)
                    )
                }
                tokensByPass.append(passTokens)
                samplesByPass.append(passSamples)
                meanByPass.append(passSamples.map { $0.totalMs }.reduce(0, +) / Double(max(1, passSamples.count)))
            }
            paths.append(
                O4PathReport(
                    path: "full", loadMs: loadMs,
                    residentActiveMiB: fullGauge.activeMiB,
                    residentFootprintMiB: fullGauge.footprintMiB,
                    tokensByPass: tokensByPass, samplesByPass: samplesByPass,
                    meanTokenMsByPass: meanByPass, peakActiveMiB: peakActive,
                    peakFootprintMiB: peakFootprint)
            )
        }

        let segmentedTokens = paths.first { $0.path == "segmented" }?.tokensByPass.flatMap { $0 }
        let fullTokens = paths.first { $0.path == "full" }?.tokensByPass.flatMap { $0 }
        let crossIdentical = segmentedTokens == fullTokens

        let maxFootprint = paths.map { $0.peakFootprintMiB }.max() ?? 0
        let maxSwap =
            paths
            .flatMap { $0.samplesByPass.flatMap { $0 } }
            .map { $0.swapMiB }
            .max() ?? 0

        return O4GenerationReport(
            status: "MEASURED",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: modelType,
            promptTokens: promptTokenIDs.count,
            segmentSize: segmentSize,
            segmentCount: segments.count,
            maxFootprintMiB: maxFootprint,
            maxSwapMiB: maxSwap,
            paths: paths,
            crossPathTokensIdentical: crossIdentical,
            boundary:
                "PERFORMANCE_DIFFERENTIAL_MEASUREMENT / SAME_FUNCTION_TWO_RESIDENCY_STRATEGIES / NO_NUMERIC_EQUIVALENCE_CLAIM / NOT_A_CAPACITY_CLAIM_FOR_OVERSIZED_MODELS"
        )
    }
}
