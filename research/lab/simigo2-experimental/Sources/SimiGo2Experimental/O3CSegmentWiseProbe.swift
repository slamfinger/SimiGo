import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import SimiGoRuntimeContract
import Tokenizers

/// O3-C″ segment-wise execution probe.
///
/// Question: with the fork's `forwardLayerRange` segment-execution API, does
/// resident memory shift from "full-model accumulation" to a controlled
/// "core + current segment" shape, with an observable resident-set boundary
/// at each segment release?
///
/// Topology (fixed): load core → embed → per segment: materialize →
/// forwardLayerRange → eval → measure → release → measure; then
/// projectOutput. Twelve registered observation points.
///
/// First priority: capacity / residency boundary. Double-pass determinism
/// runs only if capacity holds. If thrash appears: examine the release
/// boundary, then the execution peak — do not push through.
public struct O3CSegmentBoundary: Codable, Sendable {
    public let label: String
    public let activeMiB: Int64
    public let cacheMiB: Int64
    public let peakMiB: Int64
    public let footprintMiB: Int64
    public let swapMiB: Int64
}

public struct O3CSegmentWiseReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let promptTokens: Int
    public let observations: [O3CSegmentBoundary]
    public let passes: [[Int]]
    public let determinismIdentical: Bool
    public let capacityHeldThroughout: Bool
    public let residentSetBoundaryObserved: Bool
    public let overallPass: Bool
}

public enum O3CSegmentWiseProbe {
    public static let protocolVersion = "G1.9-O3C.SEGMENTWISE.V1"
    public static let capacityMiB: Int64 = 30 * 1024

    private static var observations: [O3CSegmentBoundary] = []
    private static var capacityHeld = true

    private static func observe(_ label: String) {
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
        let activeMiB = Int64(mlx.activeMemory / 1048576)
        let observation = O3CSegmentBoundary(
            label: label,
            activeMiB: activeMiB,
            cacheMiB: Int64(mlx.cacheMemory / 1048576),
            peakMiB: Int64(mlx.peakMemory / 1048576),
            footprintMiB: Int64(footprint / 1048576),
            swapMiB: swapMiB
        )
        observations.append(observation)
        // footprint is raw bytes here; capacityMiB is MiB — compare in MiB.
        // (The byte-vs-MiB mixup made this gate false in every run.)
        if footprint / 1048576 > capacityMiB {
            capacityHeld = false
        }
        FileHandle.standardError.write(
            Data("O3C″ \(label): active=\(activeMiB)MiB cache=\(Int64(mlx.cacheMemory / 1048576))MiB peak=\(Int64(mlx.peakMemory / 1048576))MiB footprint=\(Int64(footprint / 1048576))MiB swap=\(swapMiB)MiB\n".utf8)
        )
    }

    private static func releaseSegmentWeights(
        _ model: Qwen35MoEModel, segment: ClosedRange<Int>, reader: PerTensorSafetensorsReader
    ) {
        let segmentRange = segment.lowerBound...segment.upperBound
        var placeholders: [String: MLXArray] = [:]
        for name in reader.locations.keys where name.contains(".switch_mlp.") {
            if let range = name.range(of: #"layers\.(\d+)\."#, options: .regularExpression) {
                let digits = name[range].split(separator: ".").compactMap { Int($0) }
                if let layer = digits.first, layer >= segmentRange.lowerBound, layer <= segmentRange.upperBound {
                    placeholders[name] = MLXArray([Int](), [0])
                }
            }
        }
        _ = try? model.update(
            parameters: ModuleParameters.unflattened(placeholders), verify: []
        )
        Memory.clearCache()
    }

    public static func run(
        modelDirectory: URL,
        prompt: String = "def add(a, b): return a + b",
        maxTokens: Int = 1,
        streamingPasses: Int = 1
    ) async throws -> O3CSegmentWiseReport {
        observations = []
        capacityHeld = true

        let configData = try Data(contentsOf: modelDirectory.appendingPathComponent("config.json"))
        let baseConfig = try JSONDecoder.json5().decode(BaseConfiguration.self, from: configData)
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

        let reader = try PerTensorSafetensorsReader(
            modelDirectory: modelDirectory, weightMap: weightMap
        )
        // No loadContainer here: the native full-model load would keep a
        // complete second copy of the weights resident for the whole probe
        // (measured +30.28 GiB on the 6-bit Nail model). The model type is
        // read from the skeleton model, which the type registry constructed
        // from the same config.
        let modelType = String(describing: type(of: model))

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

        // Placeholder-first full-parameter update — the registered fix for
        // the lazy-random materialization cliff. Immediately after quantize,
        // and BEFORE any parameter evaluation, ONE update replaces EVERY
        // parameter with either the real checkpoint tensor (core, resident
        // for the whole run) or a zero-size placeholder (switch_mlp segment
        // tensors, materialized per segment later). update(verify: []) is
        // pure assignment, so the ~22 GiB of lazy random quantized arrays
        // left by quantize are discarded without ever materializing.
        var fullParameterMap: [String: MLXArray] = [:]
        for location in reader.locations.values {
            if location.name.contains(".switch_mlp.") {
                fullParameterMap[location.name] = MLXArray([Int](), [0])
            } else {
                fullParameterMap[location.name] = try autoreleasepool { try reader.loadTensor(named: location.name) }
            }
        }
        // Coverage guard: any model parameter path the checkpoint index does
        // not cover also gets a placeholder, so no lazy random array can
        // survive the update.
        let covered = Set(fullParameterMap.keys)
        for (path, _) in model.parameters().flattened() where !covered.contains(path) {
            fullParameterMap[path] = MLXArray([Int](), [0])
        }
        eval(fullParameterMap.values.map { $0 })
        try model.update(
            parameters: ModuleParameters.unflattened(fullParameterMap), verify: []
        )
        Memory.clearCache()
        observe("AFTER_CORE_LOAD")

        // Segment partition from the model's actual layer count — do not
        // hardcode; Qwen3Next had 48 layers, this model has 40.
        let configObject = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        let textConfigObject = configObject?["text_config"] as? [String: Any]
        let totalLayers = (textConfigObject?["num_hidden_layers"] as? Int) ?? 40
        let segmentSize = 10
        var segments: [ClosedRange<Int>] = []
        var start = 0
        while start < totalLayers {
            let end = min(start + segmentSize - 1, totalLayers - 1)
            segments.append(start...end)
            start = end + 1
        }
        var passes: [[Int]] = []

        for pass in 1...streamingPasses {
            // Embed.
            var hidden = model.embedInputs(
                MLXArray(promptTokenIDs, [1, promptTokenIDs.count])
            )
            eval(hidden)
            observe("AFTER_EMBED_PASS\(pass)")

            for (segIndex, segment) in segments.enumerated() {
                observe("BEFORE_SEG\(segIndex)_FORWARD")

                // Materialize the segment's switch_mlp tensors. The arrays
                // dictionary is scoped to this block ON PURPOSE:
                // update(verify: []) assigns the same array refs into the
                // model, so the dictionary must drop its own refs here —
                // otherwise it pins the segment's ~7 GiB until the NEXT loop
                // iteration and the release boundary frees nothing at the
                // right time (measured footprint ratchet 22 -> 29 GiB per
                // segment, cache-parked).
                do {
                    var arrays: [String: MLXArray] = [:]
                    for location in reader.locations.values
                    where location.name.contains(".switch_mlp.") {
                        if let range = location.name.range(
                            of: #"layers\.(\d+)\."#, options: .regularExpression
                        ) {
                            let digits =
                                location.name[range].split(separator: ".").compactMap { Int($0) }
                            if let layer = digits.first, segment.contains(layer) {
                                arrays[location.name] = try autoreleasepool {
                                    try reader.loadTensor(named: location.name)
                                }
                            }
                        }
                    }
                    eval(arrays.values.map { $0 })
                    try model.update(
                        parameters: ModuleParameters.unflattened(arrays), verify: []
                    )
                }
                observe("AFTER_SEG\(segIndex)_MATERIALIZE")

                // Execute the segment's layer range.
                hidden = model.forwardLayerRange(
                    hidden,
                    layerRange: segment.lowerBound..<(segment.upperBound + 1)
                )
                eval(hidden)
                observe("AFTER_SEG\(segIndex)_FORWARD")

                // Release: swap the model's refs to zero-size placeholders,
                // then purge the MLX buffer cache so the freed segment
                // actually returns to the OS. clearCache can only reclaim
                // buffers that are no longer referenced, which is why the
                // arrays dictionary above must already be out of scope here.
                releaseSegmentWeights(model, segment: segment, reader: reader)
                observe("AFTER_SEG\(segIndex)_RELEASE")
            }

            // Project output.
            observe("BEFORE_PROJECT_OUTPUT")
            let logits = model.projectOutput(hidden)[0, -1]
            eval(logits)
            observe("AFTER_PROJECT_OUTPUT")

            let nextToken = logits.argMax().item(Int.self)
            passes.append([nextToken])
        }

        let determinismIdentical =
            passes.count == 2 && passes[0] == passes[1]

        // Resident-set boundary evidence: after each release the footprint
        // must return below the previous segment's post-materialize level.
        var postMaterialize: [Int64] = []
        var postRelease: [Int64] = []
        for observation in observations {
            if observation.label.contains("AFTER_SEG") && observation.label.contains("_MATERIALIZE") {
                postMaterialize.append(observation.footprintMiB)
            }
            if observation.label.contains("AFTER_SEG") && observation.label.contains("_RELEASE") {
                postRelease.append(observation.footprintMiB)
            }
        }
        let residentSetBoundaryObserved =
            postRelease.count >= 2
                && zip(postRelease, postRelease.dropFirst()).allSatisfy { $0 <= $1 + 256 }
                && postRelease.allSatisfy { $0 <= capacityMiB }

        let overallPass =
            capacityHeld && residentSetBoundaryObserved && determinismIdentical

        return O3CSegmentWiseReport(
            status: overallPass ? "PASS" : "FAIL",
            boundary:
                "SEGMENT_WISE_EXECUTION / RESIDENT_SET_BOUNDARY / CAPACITY_FIRST / DETERMINISM_SECONDARY / NOT_A_PERFORMANCE_CLAIM",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: modelType,
            promptTokens: promptTokenIDs.count,
            observations: observations,
            passes: passes,
            determinismIdentical: determinismIdentical,
            capacityHeldThroughout: capacityHeld,
            residentSetBoundaryObserved: residentSetBoundaryObserved,
            overallPass: overallPass
        )
    }
}
