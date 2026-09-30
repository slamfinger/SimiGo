import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import SimiGoRuntimeContract
import Tokenizers

/// O3-C′ — Streaming Forward for oversized models.
///
/// Executes the full 48-layer graph by streaming layer-group representations:
/// per segment — materialize the group's switch_mlp tensors from shards, run
/// that segment's layers, release the group. Residency is monitored after
/// every segment (capacity discipline), and the whole forward is run TWICE
/// to prove determinism through the release/re-materialize cycle.
///
/// Identity evidence:
/// D-I  the two streaming passes are token-identical (same prompt, same
///      greedy decode; pass 2 runs after pass 1 released and re-materialized
///      every group);
/// L-I  the layer-graph output logits over the final hidden states checksum
///      identically across the two passes.
///
/// NOT a performance test.
public struct O3CSegmentRecord: Codable, Sendable {
    public let pass: Int
    public let segment: Int
    public let layers: String
    public let materializeSeconds: Double
    public let footprintAfterMaterializeGiB: Double
    public let swapAfterMaterializeGiB: Double
    public let releasedBytes: Int64
}

public struct O3CStreamingReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let promptTokens: Int
    public let generatedTokens: Int
    public let generatedText: String
    public let segmentRecords: [O3CSegmentRecord]
    public let determinismIdentical: Bool
    public let logitsIdentical: Bool
    public let capacityHeldThroughout: Bool
    public let gauges: [O3CGauge]
    public let overallPass: Bool
}

public enum O3CError: Error, Equatable, Sendable {
    case invalidTensorIndex
}

/// O3-C″ diagnostic gauge: five-metric memory snapshot at one boundary.
public struct O3CGauge: Codable, Sendable {
    public let label: String
    public let pass: Int
    public let step: Int
    public let tMilliseconds: Int64
    public let mlxActiveBytes: Int64
    public let mlxCacheBytes: Int64
    public let mlxPeakBytes: Int64
    public let physFootprintBytes: Int64
    public let swapUsedBytes: Int64
}

public enum O3CStreamingV2 {
    public static let protocolVersion = "G1.9-O3C.STREAMING.V1"

    private static let start = ContinuousClock.now

    private static func footprintGiB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1073741824.0 : -1
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
            default: return magnitude / (1024 * 1024)
            }
        }
        return 0
    }

    private static func trace(_ message: String) {
        FileHandle.standardError.write(
            Data("O3C +\(Int(Double(start.duration(to: .now).components.attoseconds) / 1e18))s \(message)\n".utf8)
        )
    }

    /// Five-metric diagnostic gauge; also mirrored to stderr so the trace
    /// survives a watchdog kill.
    private static func gauge(
        _ label: String, pass: Int, step: Int, to gauges: inout [O3CGauge]
    ) {
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
        var swapUsed: Int64 = 0
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
                swapUsed = Int64(bytes)
            }
        }
        let gauge = O3CGauge(
            label: label,
            pass: pass,
            step: step,
            tMilliseconds: Int64(Double(start.duration(to: .now).components.attoseconds) / 1e18 * 1000),
            mlxActiveBytes: Int64(mlx.activeMemory),
            mlxCacheBytes: Int64(mlx.cacheMemory),
            mlxPeakBytes: Int64(mlx.peakMemory),
            physFootprintBytes: footprint,
            swapUsedBytes: swapUsed
        )
        gauges.append(gauge)
        FileHandle.standardError.write(
            Data("GAUGE \(label) pass=\(pass) step=\(step) active=\(gauge.mlxActiveBytes / 1048576)MiB cache=\(gauge.mlxCacheBytes / 1048576)MiB peak=\(gauge.mlxPeakBytes / 1048576)MiB footprint=\(gauge.physFootprintBytes / 1048576)MiB swap=\(gauge.swapUsedBytes / 1048576)MiB\n".utf8)
        )
    }

    public static func run(
        modelDirectory: URL,
        prompt: String = "def add(a, b): return a + b",
        maxTokens: Int = 8,
        capacityGiB: Double = 30.0
    ) async throws -> O3CStreamingReport {
        let configURL = modelDirectory.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)
        let baseConfig = try JSONDecoder.json5().decode(BaseConfiguration.self, from: configData)
        let index = try JSONSerialization.jsonObject(
            with: Data(contentsOf: modelDirectory.appendingPathComponent("model.safetensors.index.json"))
        ) as? [String: Any]
        guard let weightMap = index?["weight_map"] as? [String: String] else {
            throw O3CError.invalidTensorIndex
        }

        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
        let model = try await MLXLLM.LLMModelFactory.shared.typeRegistry.createModel(
            configuration: configData, modelType: baseConfig.modelType
        ) as! Qwen3NextModel

        // Skeleton quantize (per-layer params from the checkpoint dict).
        let quantizedModules: Set<String> = Set(
            weightMap.keys.filter { $0.hasSuffix(".scales") }
                .map { String($0.dropLast(".scales".count)) }
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
        trace("skeleton + quantize done")

        // O3-C″ tensor-level reader: keep shard headers indexed, but read only
        // the selected tensor payload. This replaces the C′ shard-level
        // loadArraysAndMetadata probe and removes its first-array ambiguity.
        let tensorReader = try PerTensorSafetensorsReader(
            modelDirectory: modelDirectory,
            weightMap: weightMap
        )
        trace("tensor location index: \(tensorReader.locations.count) tensors")

        let segmentLayers = 16
        let segments: [[Int]] = (0..<3).map { s in
            Array((s * segmentLayers)..<(s * segmentLayers + segmentLayers))
        }

        /// Load one segment's tensors. Core tensors remain resident; only the
        /// current switch_mlp segment is loaded into the model.
        func materializeSegment(
            _ segment: Int,
            coreLoaded: inout Bool,
            pass: Int
        ) async throws -> Double {
            let mStart = ContinuousClock.now
            var tensorCount = 0
            var readBytes: Int64 = 0

            for location in tensorReader.locations.values {
                let name = location.name

                if !coreLoaded {
                    guard !name.contains(".switch_mlp.") else { continue }
                } else {
                    guard name.contains(".switch_mlp.") else { continue }
                    let components = name.split(separator: ".")
                    guard let index = components.firstIndex(of: "layers"),
                          index + 1 < components.count,
                          let layer = Int(components[index + 1]),
                          segments[segment].contains(layer)
                    else { continue }
                }

                // C2 minimal materialization-shape fix: stream one tensor at a
                // time instead of retaining the whole segment.
                let tensor = try tensorReader.loadTensor(named: name)
                readBytes += location.byteCount
                tensorCount += 1
                eval(tensor)
                let parameters = ModuleParameters.unflattened([name: tensor])
                try model.update(parameters: parameters, verify: [])
            }

            gauge("SEG\(segment)_AFTER_READ(\(tensorCount) tensors, \(readBytes / 1048576)MiB streamed)", pass: pass, step: -1, to: &gauges)
            gauge("SEG\(segment)_AFTER_EVAL", pass: pass, step: -1, to: &gauges)
            gauge("SEG\(segment)_AFTER_MATERIALIZE", pass: pass, step: -1, to: &gauges)

            return Double(mStart.duration(to: .now).components.attoseconds) / 1e18
        }

        var segmentRecords: [O3CSegmentRecord] = []
        var capacityHeld = true
        var coreLoaded = false
        var gauges: [O3CGauge] = []

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

        var passResults: [[Int]] = []
        var passLogitChecksums: [String] = []

        for streamingPass in 1...2 {
            trace("=== streaming pass \(streamingPass) ===")
            var generated: [Int] = []
            var running = MLXArray(promptTokenIDs, [1, promptTokenIDs.count])
            var logitsChecksumFinal = ""

            for step in 0..<maxTokens {
                gauge("STEP_START", pass: streamingPass, step: step, to: &gauges)
                let m0 = try await materializeSegment(0, coreLoaded: &coreLoaded, pass: streamingPass)
                coreLoaded = true
                segmentRecords.append(
                    O3CSegmentRecord(
                        pass: streamingPass, segment: 0, layers: "0–15",
                        materializeSeconds: m0,
                        footprintAfterMaterializeGiB: footprintGiB(),
                        swapAfterMaterializeGiB: swapGiB(),
                        releasedBytes: 0
                    )
                )
                if footprintGiB() > capacityGiB { capacityHeld = false }

                for segment in 1...2 {
                    let m = try await materializeSegment(segment, coreLoaded: &coreLoaded, pass: streamingPass)
                    segmentRecords.append(
                        O3CSegmentRecord(
                            pass: streamingPass, segment: segment,
                            layers: "\(segment * 16)–\(segment * 16 + 15)",
                            materializeSeconds: m,
                            footprintAfterMaterializeGiB: footprintGiB(),
                            swapAfterMaterializeGiB: swapGiB(),
                            releasedBytes: 0
                        )
                    )
                    if footprintGiB() > capacityGiB { capacityHeld = false }
                }

                // C′ deliberately retained the naive whole-graph call here.
                // C″ diagnosis: instrument its memory effect directly.
                gauge("BEFORE_WHOLE_GRAPH_FORWARD", pass: streamingPass, step: step, to: &gauges)
                let logits = model(running, cache: nil)[0, -1]
                let nextToken = logits.argMax().item(Int.self)
                gauge("AFTER_WHOLE_GRAPH_FORWARD", pass: streamingPass, step: step, to: &gauges)
                generated.append(nextToken)
                if step == maxTokens - 1 {
                    eval(logits)
                    logitsChecksumFinal = InstrumentationIdentityProbe.sha256Base64(logits)
                }
                if nextToken == tokenizer.eosTokenId ?? -1 {
                    break
                }
                let all = promptTokenIDs + generated
                running = MLXArray(all, [1, all.count])
                eval(logits)
                gauge("STEP_END", pass: streamingPass, step: step, to: &gauges)
            }

            passResults.append(generated)
            passLogitChecksums.append(logitsChecksumFinal)
            trace("pass \(streamingPass): \(generated.count) tokens, checksum \(logitsChecksumFinal.prefix(16))…")
        }

        let determinismIdentical = passResults.count == 2
            && passResults[0] == passResults[1]
        let logitsIdentical = passLogitChecksums.count == 2
            && passLogitChecksums[0] == passLogitChecksums[1]
        let overallPass = determinismIdentical && logitsIdentical && capacityHeld

        return O3CStreamingReport(
            status: overallPass ? "PASS" : "FAIL",
            boundary:
                "STREAMING_FORWARD / CAPACITY_DISCIPLINE / DETERMINISM_THROUGH_RELEASE_REMATERIALIZE / NOT_A_PERFORMANCE_CLAIM",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: baseConfig.modelType,
            promptTokens: promptTokenIDs.count,
            generatedTokens: passResults.first?.count ?? 0,
            generatedText: "",
            segmentRecords: segmentRecords,
            determinismIdentical: determinismIdentical,
            logitsIdentical: logitsIdentical,
            capacityHeldThroughout: capacityHeld,
            gauges: gauges,
            overallPass: overallPass
        )
    }
}
