import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXNN
import Tokenizers

/// OversizedSegmentedEngine — the O-line's verified execution mechanics,
/// productized as the app-facing engine (2026-09-26).
///
/// Defaults encode the measured O5 operating point: segment size 8
/// (6×8-layer segments on 48 layers = the Pareto-best configuration on
/// 32 GiB hardware: 7.7 s/token at 8.8 GiB peak, swap 0). Load is
/// placeholder-first (the registered cliff fix) through the single-copy
/// reader; per token, per segment: materialize → forwardLayerRange →
/// release. Generation is greedy and cacheless (full-sequence re-forward;
/// no second KV authority) with checkpoint chat-template multi-turn input.
/// Residency/O6 note: segment eviction here is engine-internal; Execution
/// State semantics live in the O6 components.
///
/// Supported: qwen3_next (the registered oversized architecture). Other
/// model types throw at load.

public struct EngineChatMessage: Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct OversizedEngineGauge: Codable, Sendable {
    public let tokenIndex: Int
    public let activeMiB: Int64
    public let footprintMiB: Int64
    public let swapMiB: Int64
    public let residentSegment: Int
}

public struct OversizedEngineStats: Codable, Sendable {
    public let residentActiveMiB: Int64
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let loadSeconds: Double
    public let meanTokenMs: Double
    public let segmentSize: Int
    public let segmentCount: Int
    public let totalLayers: Int
    public let peakCapacityMiB: Int64
}

public struct OversizedEngineTurn: Sendable {
    public let text: String
    public let tokenIDs: [Int]
    public let meanTokenMs: Double
}

public enum OversizedEngineError: Error, LocalizedError {
    case unsupportedModelType(String)
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case .unsupportedModelType(let t):
            return "unsupported model type for the oversized segmented engine: \(t)"
        case .notLoaded:
            return "engine not loaded — call load() first"
        }
    }
}

public final class OversizedSegmentedEngine: @unchecked Sendable {
    public static let defaultSegmentSize = 8
    public static let peakCapacityMiB: Int64 = 30 * 1024

    private let modelDirectory: URL
    private let segmentSize: Int

    private var model: Qwen3NextModel?
    private var reader: PerTensorSafetensorsReader?
    private var tokenizer: Tokenizers.Tokenizer?
    private var switchNames: [String] = []
    private var segments: [ClosedRange<Int>] = []
    private var totalLayers = 0
    private var modelType = ""

    public private(set) var stats: OversizedEngineStats?

    public init(modelDirectory: URL, segmentSize: Int = OversizedSegmentedEngine.defaultSegmentSize) {
        self.modelDirectory = modelDirectory
        self.segmentSize = segmentSize
    }

    private var clock = ContinuousClock()

    private func gauge() -> (activeMiB: Int64, footprintMiB: Int64, swapMiB: Int64) {
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
        var swapMiB: Int64 = 0
        var size = 0
        sysctlbyname("vm.swapusage", nil, &size, nil, 0)
        if size > 0 {
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
                swapMiB = Int64(bytes / 1048576)
            }
        }
        return (Int64(mlx.activeMemory / 1048576), footprint / 1048576, swapMiB)
    }

    /// Skeleton + per-layer quantize + placeholder-first load (real core,
    /// zero-size segment placeholders — the registered cliff fix).
    public func load() async throws -> OversizedEngineStats {
        let loadStart = clock.now
        let configData = try Data(contentsOf: modelDirectory.appendingPathComponent("config.json"))
        let baseConfig = try JSONDecoder.json5().decode(BaseConfiguration.self, from: configData)
        guard baseConfig.modelType == "qwen3_next" else {
            throw OversizedEngineError.unsupportedModelType(baseConfig.modelType)
        }
        modelType = baseConfig.modelType
        let index = try JSONSerialization.jsonObject(
            with: Data(contentsOf: modelDirectory.appendingPathComponent("model.safetensors.index.json"))
        ) as? [String: Any]
        guard let weightMap = index?["weight_map"] as? [String: String] else {
            throw O3CError.invalidTensorIndex
        }
        let reader = try PerTensorSafetensorsReader(
            modelDirectory: modelDirectory, weightMap: weightMap
        )
        self.reader = reader
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
        self.tokenizer = tokenizer

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
            if let base = baseConfig.quantization {
                return (groupSize: base.groupSize, bits: base.bits, mode: base.mode)
            }
            return nil
        }, apply: { module, groupSize, bits, mode in
            quantizeSingle(layer: module, groupSize: groupSize, bits: bits, mode: mode)
        })

        let configObject = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        let totalLayers =
            (configObject?["num_hidden_layers"] as? Int)
            ?? ((configObject?["text_config"] as? [String: Any])?["num_hidden_layers"] as? Int)
            ?? 48
        self.totalLayers = totalLayers
        var segs: [ClosedRange<Int>] = []
        var start = 0
        while start < totalLayers {
            let end = min(start + segmentSize - 1, totalLayers - 1)
            segs.append(start...end)
            start = end + 1
        }
        segments = segs
        switchNames = reader.locations.values
            .filter { $0.name.contains(".switch_mlp.") }
            .map { $0.name }

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
        self.model = model

        let g = gauge()
        let loadSeconds =
            Double(loadStart.duration(to: clock.now).components.seconds)
            + Double(loadStart.duration(to: clock.now).components.attoseconds) / 1e18
        let stats = OversizedEngineStats(
            residentActiveMiB: g.activeMiB,
            peakFootprintMiB: g.footprintMiB,
            maxSwapMiB: g.swapMiB,
            loadSeconds: loadSeconds,
            meanTokenMs: 0,
            segmentSize: segmentSize,
            segmentCount: segs.count,
            totalLayers: totalLayers,
            peakCapacityMiB: Self.peakCapacityMiB
        )
        self.stats = stats
        return stats
    }

    private func promptTokenIDs(for messages: [EngineChatMessage]) throws -> [Int] {
        guard let tokenizer else { throw OversizedEngineError.notLoaded }
        let msgs: [[String: any Sendable]] = messages.map {
            ["role": $0.role, "content": $0.content]
        }
        let external = modelDirectory.appendingPathComponent("chat_template.jinja")
        if FileManager.default.fileExists(atPath: external.path) {
            let template = try String(contentsOf: external, encoding: .utf8)
            return try tokenizer.applyChatTemplate(
                messages: msgs,
                chatTemplate: .literal(template),
                addGenerationPrompt: true,
                truncation: false,
                maxLength: nil,
                tools: nil,
                additionalContext: ["enable_thinking": false]
            )
        }
        return try tokenizer.applyChatTemplate(messages: msgs)
    }

    /// Multi-turn greedy generation with per-token streaming callbacks.
    @discardableResult
    public func generate(
        messages: [EngineChatMessage],
        maxNewTokens: Int,
        onToken: (@Sendable (OversizedEngineGauge, String) -> Void)? = nil
    ) async throws -> OversizedEngineTurn {
        guard let model, let reader, let tokenizer else {
            throw OversizedEngineError.notLoaded
        }
        var ids = try promptTokenIDs(for: messages)
        var generated: [Int] = []
        var tokenMs: [Double] = []
        var peakFootprint: Int64 = 0
        var maxSwap: Int64 = 0

        for index in 0..<maxNewTokens {
            let tokenStart = clock.now
            var hidden = model.embedInputs(MLXArray(ids, [1, ids.count]))
            eval(hidden)
            var residentSegment = -1
            for (segIndex, segment) in segments.enumerated() {
                do {
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
                    eval(arrays.values.map { $0 })
                    try model.update(
                        parameters: ModuleParameters.unflattened(arrays), verify: []
                    )
                }
                residentSegment = segIndex
                hidden = model.forwardLayerRange(
                    hidden,
                    layerRange: segment.lowerBound..<(segment.upperBound + 1),
                    cache: nil
                )
                eval(hidden)
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
            }
            let logits = model.projectOutput(hidden)[0, -1]
            eval(logits)
            let next = logits.argMax().item(Int.self)
            generated.append(next)
            ids.append(next)

            let duration = tokenStart.duration(to: clock.now)
            let ms = Double(duration.components.seconds) * 1000
                + Double(duration.components.attoseconds) / 1e15
            tokenMs.append(ms)

            let g = gauge()
            peakFootprint = max(peakFootprint, g.footprintMiB)
            maxSwap = max(maxSwap, g.swapMiB)
            let tokenText = tokenizer.decode(tokens: [next], skipSpecialTokens: true)
            onToken?(OversizedEngineGauge(
                tokenIndex: index + 1, activeMiB: g.activeMiB,
                footprintMiB: g.footprintMiB, swapMiB: g.swapMiB,
                residentSegment: residentSegment
            ), tokenText)
        }

        let text = tokenizer.decode(tokens: generated, skipSpecialTokens: true)
        let mean = tokenMs.isEmpty ? 0 : tokenMs.reduce(0, +) / Double(tokenMs.count)
        if var s = stats {
            s = OversizedEngineStats(
                residentActiveMiB: s.residentActiveMiB,
                peakFootprintMiB: max(s.peakFootprintMiB, peakFootprint),
                maxSwapMiB: max(s.maxSwapMiB, maxSwap),
                loadSeconds: s.loadSeconds,
                meanTokenMs: mean,
                segmentSize: s.segmentSize,
                segmentCount: s.segmentCount,
                totalLayers: s.totalLayers,
                peakCapacityMiB: s.peakCapacityMiB
            )
            stats = s
        }
        return OversizedEngineTurn(text: text, tokenIDs: generated, meanTokenMs: mean)
    }

    /// The oversized eviction: release every segment's weights.
    public func releaseAllSegments() throws {
        guard let model else { throw OversizedEngineError.notLoaded }
        var placeholders: [String: MLXArray] = [:]
        for name in switchNames {
            placeholders[name] = MLXArray([Int](), [0])
        }
        try model.update(parameters: ModuleParameters.unflattened(placeholders), verify: [])
        Memory.clearCache()
    }
}
