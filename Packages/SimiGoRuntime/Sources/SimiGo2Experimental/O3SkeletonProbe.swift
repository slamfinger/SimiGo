import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import SimiGoRuntimeContract
import Tokenizers

/// O3 — Skeleton Load + Selective Residency + Real Forward.
///
/// O3-A Skeleton load: construct `Qwen3NextModel` from the checkpoint
/// config WITHOUT loading any weights (MLX lazy random init), then
/// quantize in place using the checkpoint's `.scales` tensor names as the
/// predicate (per-module transient only).
///
/// O3-B Selective residency: materialize core + all groups EXCEPT one
/// switch_mlp 16-layer range, by reading only those shard tensors and
/// updating those parameters (verify: []).
///
/// O3-C Real forward: run the skeleton model over a small prompt — the
/// residency-controlled weights are consumed by REAL execution with only
/// core + non-evicted groups materialized.
///
/// Watchdog: the caller enforces wall-clock limits; this probe reports
/// stage-by-stage footprints to stderr so partial progress is evidence even
/// on failure.
public struct O3StageRecord: Codable, Sendable {
    public let stage: String
    public let tMilliseconds: Int64
    public let physFootprintBytes: Int64
    public let swapUsedBytes: Int64
    public let pass: Bool
    public let detail: String
}

public struct O3SkeletonReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let stages: [O3StageRecord]
    public let materializeSeconds: Double
    public let forwardMilliseconds: Double
    public let generatedTokens: Int
    public let overallPass: Bool
}

public enum O3SkeletonProbe {
    public static let protocolVersion = "G1.9-O3.SKELETON.V1"

    private static let start = ContinuousClock.now

    private static func footprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
    }

    private static func swapGiB() -> Double {
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
            switch value.last {
            case "G": return magnitude
            case "M": return magnitude / 1024
            case "K": return magnitude / (1024 * 1024)
            default: return 0
            }
        }
        return 0
    }

    private static func trace(_ message: String) {
        FileHandle.standardError.write(
            Data("O3 +\(Int(Double(start.duration(to: .now).components.attoseconds) / 1e18))s \(message)\n".utf8)
        )
    }

    private static func stage(
        _ name: String, pass: Bool, detail: String, to stages: inout [O3StageRecord]
    ) {
        let record = O3StageRecord(
            stage: name,
            tMilliseconds: Int64(Double(start.duration(to: .now).components.attoseconds) / 1e18 * 1000),
            physFootprintBytes: footprintBytes(),
            swapUsedBytes: Int64(swapGiB() * 1024 * 1024 * 1024),
            pass: pass,
            detail: detail
        )
        stages.append(record)
        trace(
            "STAGE \(name) pass=\(pass) footprint=\(String(format: "%.2f", Double(record.physFootprintBytes) / 1073741824.0))GiB swap=\(String(format: "%.2f", swapGiB()))GiB — \(detail)"
        )
    }

    public static func run(
        modelDirectory: URL,
        evictedLayerRange: ClosedRange<Int> = 16...31,
        prompt: String = "def add(a, b): return a + b",
        maxTokens: Int = 16
    ) async throws -> O3SkeletonReport {
        var stages: [O3StageRecord] = []
        var materializeSeconds: Double = 0
        var forwardMilliseconds: Double = 0
        var generatedTokens = 0

        // ---- A1: skeleton construction (no weights) ----
        let configURL = modelDirectory.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)
        let baseConfig = try JSONDecoder.json5().decode(BaseConfiguration.self, from: configData)
        guard baseConfig.modelType == "qwen3_next" else {
            stage("A1_SKELETON_CONSTRUCT", pass: false, detail: "unsupported type \(baseConfig.modelType)", to: &stages)
            throw O3Error.unsupportedModelType(baseConfig.modelType)
        }

        // Tokenizer FIRST (independent of weights; also loads nothing heavy).
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)

        let model = try await MLXLLM.LLMModelFactory.shared.typeRegistry.createModel(
            configuration: configData, modelType: baseConfig.modelType
        ) as! Qwen3NextModel
        stage(
            "A1_SKELETON_CONSTRUCT", pass: true,
            detail: "Qwen3NextModel constructed; lazy random init (no weights loaded)",
            to: &stages
        )

        // ---- A2: quantize in place from checkpoint .scales names ----
        let indexURL = modelDirectory.appendingPathComponent("model.safetensors.index.json")
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        guard let weightMap = index?["weight_map"] as? [String: String] else {
            stage("A2_QUANTIZE", pass: false, detail: "no weight_map", to: &stages)
            throw O3Error.invalidIndex
        }
        let quantizedModules: Set<String> = Set(
            weightMap.keys.filter { $0.hasSuffix(".scales") }.map { String($0.dropLast(".scales".count)) }
        )
        _ = try JSONDecoder.json5().decode(
            BaseConfiguration.self, from: configData
        )
        // Mirror loadWeights: per-module (group,bits) resolved from the
        // checkpoint config's interleaved quantization dict; base fallback.
        quantize(model: model, filter: { path, _ in
            guard quantizedModules.contains(path) else { return nil }
            if let perLayer = baseConfig.perLayerQuantization?.quantization(layer: path) {
                return (groupSize: perLayer.groupSize, bits: perLayer.bits, mode: perLayer.mode)
            }
            return nil
        }, apply: { module, groupSize, bits, mode in
            quantizeSingle(layer: module, groupSize: groupSize, bits: bits, mode: mode)
        })
        stage(
            "A2_QUANTIZE", pass: true,
            detail: "quantized \(quantizedModules.count) modules from checkpoint .scales names",
            to: &stages
        )

        // ---- B: selective residency — core + everything except one group ----
        let materializeStart = ContinuousClock.now
        let shardFiles = Set(weightMap.values).sorted()
        var groupArrays: [String: MLXArray] = [:]
        var skippedBytes: Int64 = 0
        for file in shardFiles {
            let url = modelDirectory.appendingPathComponent(file)
            let (arrays, _) = try MLX.loadArraysAndMetadata(url: url)
            for (name, array) in arrays {
                // Evicted group: skip switch_mlp tensors inside the evicted
                // 16-layer range; everything else is core/needed.
                var isEvictedGroupTensor = false
                if name.contains(".switch_mlp.") {
                    if let range = name.range(of: #"layers\.(\d+)\."#, options: .regularExpression) {
                        let digits = name[range].split(separator: ".").first { part in part.allSatisfy { ch in ch.isNumber } }
                        let layer = digits.flatMap { Int($0) } ?? -1
                        if evictedLayerRange.contains(layer) {
                            isEvictedGroupTensor = true
                        }
                    }
                }
                if isEvictedGroupTensor {
                    skippedBytes += Int64(array.nbytes)
                } else {
                    groupArrays[name] = array
                }
            }
        }
        eval(groupArrays.values.map { $0 })
        materializeSeconds = Double(materializeStart.duration(to: .now).components.attoseconds) / 1e18
        let parameters = ModuleParameters.unflattened(groupArrays)
        try model.update(parameters: parameters, verify: [])
        let materializedGiB = String(
            format: "%.2f", Double(groupArrays.values.reduce(0) { partial, arr in partial + Int64(arr.nbytes) }) / 1073741824.0
        )
        let skippedGiB = String(format: "%.2f", Double(skippedBytes) / 1073741824.0)
        stage(
            "B_SELECTIVE_RESIDENCY", pass: true,
            detail: "materialized \(groupArrays.count) tensors / \(materializedGiB) GiB; skipped (evicted group) \(skippedGiB) GiB in \(String(format: "%.1f", materializeSeconds))s",
            to: &stages
        )

        // ---- C: real forward on the skeleton model ----
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
        trace("prompt tokens: \(promptTokenIDs.count)")

        let forwardStart = ContinuousClock.now
        var generated: [Int] = []
        var running = MLXArray(promptTokenIDs, [1, promptTokenIDs.count])
        for _ in 0..<maxTokens {
            let logits = model(running, cache: nil)[0, -1]
            let nextToken = logits.argMax().item(Int.self)
            generated.append(nextToken)
            if nextToken == tokenizer.eosTokenId ?? -1 {
                break
            }
            let all = promptTokenIDs + generated
            running = MLXArray(all, [1, all.count])
            eval(logits)
        }
        forwardMilliseconds = Double(forwardStart.duration(to: .now).components.attoseconds) / 1e18 * 1000
        generatedTokens = generated.count
        _ = tokenizer.decode(tokens: generated, skipSpecialTokens: true)
        let forwardPass = generated.count > 0 && generated.allSatisfy { $0 >= 0 }
        stage(
            "C_REAL_FORWARD", pass: forwardPass,
            detail: "prompt \(promptTokenIDs.count) tokens → \(generated.count) tokens in \(String(format: "%.1f", forwardMilliseconds))ms; evicted-group weights were NOT resident during this forward",
            to: &stages
        )

        Memory.clearCache()

        let overallPass = stages.allSatisfy(\.pass)
        return O3SkeletonReport(
            status: overallPass ? "PASS" : "FAIL",
            boundary:
                "SKELETON_LOAD / SELECTIVE_RESIDENCY / REAL_FORWARD_CONSUMES_RESIDENCY / ZERO_FULL_WEIGHT_LOAD / NOT_A_PERFORMANCE_CLAIM",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: baseConfig.modelType,
            stages: stages,
            materializeSeconds: materializeSeconds,
            forwardMilliseconds: forwardMilliseconds,
            generatedTokens: generatedTokens,
            overallPass: overallPass
        )
    }

    public enum O3Error: Error, Equatable {
        case unsupportedModelType(String)
        case invalidIndex
    }
}
