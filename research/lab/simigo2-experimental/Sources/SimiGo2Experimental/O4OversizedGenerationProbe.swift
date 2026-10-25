import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import Tokenizers

/// O4 oversized real generation probe (Qwen3-Coder-Next-4bit, 41.76 GiB
/// weights > 32 GiB physical — the direct measurement that replaces the
/// 20.15 GiB A/B extrapolation).
///
/// Segmented path only (the full path does not exist at this scale — O2/O3
/// measured): skeleton + quantize + placeholder-first, then per token,
/// per segment: materialize → forwardLayerRange → release. Greedy,
/// cacheless (full-sequence re-forward per token; no second KV authority).
/// Harness-level physical layer only — no Execution State machinery (that
/// composition is O6).
public struct O4OversizedReport: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let promptTokens: Int
    public let segmentSize: Int
    public let segmentCount: Int
    public let prefetch: Bool
    public let residentActiveMiB: Int64
    public let peakActiveMiB: Int64
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let tokensByPass: [[Int]]
    public let samplesByPass: [[O4TokenSample]]
    public let meanTokenMsByPass: [Double]
    public let determinismIdentical: Bool
    public let boundary: String
}

public enum O4OversizedGenerationProbe {
    public static let protocolVersion = "G1.9-O4.OVERSIZEGEN.V1"

    private static let clock = ContinuousClock()

    private static func msSince(_ start: ContinuousClock.Instant) -> Double {
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
                "O4 oversized gauge: active=\(mlx.activeMemory / 1048576)MiB footprint=\(footprint / 1048576)MiB swap=\(swap)MiB\n"
                    .utf8)
        )
        return (Int64(mlx.activeMemory / 1048576), footprint / 1048576, swap)
    }

    public static func run(
        modelDirectory: URL,
        prompt: String = "Write a Python function that merges two sorted lists.",
        promptRepeat: Int = 1,
        maxNewTokens: Int = 8,
        passes: Int = 2,
        segmentSize: Int = 16,
        prefetch: Bool = false
    ) async throws -> O4OversizedReport {
        let configData = try Data(contentsOf: modelDirectory.appendingPathComponent("config.json"))
        let baseConfig = try JSONDecoder.json5().decode(BaseConfiguration.self, from: configData)
        guard baseConfig.modelType == "qwen3_next" else {
            throw O3CError.invalidTensorIndex
        }
        let index = try JSONSerialization.jsonObject(
            with: Data(contentsOf: modelDirectory.appendingPathComponent("model.safetensors.index.json"))
        ) as? [String: Any]
        guard let weightMap = index?["weight_map"] as? [String: String] else {
            throw O3CError.invalidTensorIndex
        }
        let reader = try PerTensorSafetensorsReader(
            modelDirectory: modelDirectory, weightMap: weightMap
        )
        let effectivePrompt =
            Array(repeating: prompt, count: max(1, promptRepeat)).joined(separator: "\n\n")
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
        let messages: [[String: any Sendable]] = [["role": "user", "content": effectivePrompt]]
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
        let totalLayers =
            (configObject?["num_hidden_layers"] as? Int)
            ?? ((configObject?["text_config"] as? [String: Any])?["num_hidden_layers"] as? Int)
            ?? 48
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

        // ---- Skeleton + quantize + placeholder-first (the registered fix).
        let model = try await MLXLLM.LLMModelFactory.shared.typeRegistry.createModel(
            configuration: configData, modelType: baseConfig.modelType
        ) as! Qwen3NextModel
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

        var fullParameterMap: [String: MLXArray] = [:]
        for location in reader.locations.values {
            if location.name.contains(".switch_mlp.") {
                fullParameterMap[location.name] = MLXArray([Int](), [0])
            } else {
                fullParameterMap[location.name] = try autoreleasepool {
                    try reader.loadTensor(named: location.name)
                }
            }
        }
        let covered = Set(fullParameterMap.keys)
        for (path, _) in model.parameters().flattened() where !covered.contains(path) {
            fullParameterMap[path] = MLXArray([Int](), [0])
        }
        eval(fullParameterMap.values.map { $0 })
        try model.update(parameters: ModuleParameters.unflattened(fullParameterMap), verify: [])
        Memory.clearCache()
        let resident = memoryGauge()

        var peakActive = resident.activeMiB
        var peakFootprint = resident.footprintMiB
        var maxSwap = resident.swapMiB
        var tokensByPass: [[Int]] = []
        var samplesByPass: [[O4TokenSample]] = []
        var meanByPass: [Double] = []

        // Prefetch pipelining (O5 lever): while forward(seg i) runs on the
        // device, segment i+1's tensors are read on a background task. Peak
        // memory gains the in-flight next segment (core + current + next).
        @Sendable func startSegmentRead(
            _ segment: ClosedRange<Int>
        ) -> Task<UnsafeSendableBox<[String: MLXArray]>, Error> {
            Task.detached(priority: .userInitiated) {
                var arrays: [String: MLXArray] = [:]
                for name in switchNames {
                    if let range = name.range(
                        of: #"layers\.(\d+)\."#, options: .regularExpression
                    ) {
                        let digits = name[range].split(separator: ".").compactMap { Int($0) }
                        if let layer = digits.first, segment.contains(layer) {
                            arrays[name] = try autoreleasepool {
                                try reader.loadTensor(named: name)
                            }
                        }
                    }
                }
                return UnsafeSendableBox(value: arrays)
            }
        }

        for _ in 1...passes {
            var ids = promptTokenIDs
            var passTokens: [Int] = []
            var passSamples: [O4TokenSample] = []
            for _ in 0..<maxNewTokens {
                // Pipeline state resets per token: the fill read for seg 0 is
                // exposed each token (no cross-token overlap — the previous
                // token's last segment is still in flight when seg 0's read
                // would need to start, and double-buffering across the token
                // boundary would double peak residency).
                var pending: Task<UnsafeSendableBox<[String: MLXArray]>, Error>? =
                    prefetch ? startSegmentRead(segments[0]) : nil
                let tokenStart = clock.now
                var hidden = model.embedInputs(MLXArray(ids, [1, ids.count]))
                eval(hidden)
                var breakdowns: [O4SegmentBreakdown] = []
                for (segIndex, segment) in segments.enumerated() {
                    var readMs = 0.0, updateMs = 0.0, forwardMs = 0.0, releaseMs = 0.0
                    let arrays: [String: MLXArray]
                    do {
                        let readStart = clock.now
                        if prefetch {
                            arrays = try await pending!.value.value
                            pending = nil
                        } else {
                            var dict: [String: MLXArray] = [:]
                            for name in switchNames {
                                if let range = name.range(
                                    of: #"layers\.(\d+)\."#, options: .regularExpression
                                ) {
                                    let digits =
                                        name[range].split(separator: ".").compactMap { Int($0) }
                                    if let layer = digits.first, segment.contains(layer) {
                                        dict[name] = try autoreleasepool {
                                            try reader.loadTensor(named: name)
                                        }
                                    }
                                }
                            }
                            arrays = dict
                        }
                        eval(arrays.values.map { $0 })
                        readMs = msSince(readStart)

                        let updateStart = clock.now
                        try model.update(
                            parameters: ModuleParameters.unflattened(arrays), verify: []
                        )
                        updateMs = msSince(updateStart)
                    }
                    // Start the next read BEFORE the forward so the two
                    // overlap; its residual cost surfaces at the next await.
                    var nextTask: Task<UnsafeSendableBox<[String: MLXArray]>, Error>? = nil
                    if prefetch, segIndex + 1 < segments.count {
                        nextTask = startSegmentRead(segments[segIndex + 1])
                    }
                    let forwardStart = clock.now
                    hidden = model.forwardLayerRange(
                        hidden,
                        layerRange: segment.lowerBound..<(segment.upperBound + 1),
                        cache: nil
                    )
                    eval(hidden)
                    forwardMs = msSince(forwardStart)
                    pending = nextTask

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
                let logits = model.projectOutput(hidden)[0, -1]
                eval(logits)
                let next = logits.argMax().item(Int.self)
                let totalMs = msSince(tokenStart)

                let gauge = memoryGauge()
                peakActive = max(peakActive, gauge.activeMiB)
                peakFootprint = max(peakFootprint, gauge.footprintMiB)
                maxSwap = max(maxSwap, gauge.swapMiB)
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
            meanByPass.append(
                passSamples.map { $0.totalMs }.reduce(0, +) / Double(max(1, passSamples.count)))
        }

        let determinismIdentical =
            tokensByPass.count == 2 && tokensByPass[0] == tokensByPass[1]

        return O4OversizedReport(
            status: determinismIdentical ? "PASS" : "MEASURED",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: baseConfig.modelType,
            promptTokens: promptTokenIDs.count,
            segmentSize: segmentSize,
            segmentCount: segments.count,
            prefetch: prefetch,
            residentActiveMiB: resident.activeMiB,
            peakActiveMiB: peakActive,
            peakFootprintMiB: peakFootprint,
            maxSwapMiB: maxSwap,
            tokensByPass: tokensByPass,
            samplesByPass: samplesByPass,
            meanTokenMsByPass: meanByPass,
            determinismIdentical: determinismIdentical,
            boundary:
                "OVERSIZED_REAL_GENERATION / SEGMENTED_ONLY / FULL_PATH_DOES_NOT_EXIST_AT_SCALE / HARNESS_LEVEL_NO_EXECUTION_STATE_O6_PENDING / NOT_A_PERFORMANCE_CLAIM"
        )
    }
}
