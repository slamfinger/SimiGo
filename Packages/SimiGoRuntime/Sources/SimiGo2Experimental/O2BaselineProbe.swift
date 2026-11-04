import Foundation
import Crypto
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import SimiGoRuntimeContract
import Tokenizers

/// O2 — Native MLX baseline probe. ZERO SimiGo intervention: measures what
/// the CURRENT mlx-swift-lm / MLX path actually does with a model whose
/// representation exceeds physical memory.
///
/// Phases:
///   O2-A Mapping/Load footprint — T0 process start, T1/T2 load complete:
///        is the footprint ≈ full weights (H-eager) or small (H-mmap
///        page-backed)?
///   O2-B Selective touch        — load ONE shard via loadArrays without
///        eval, touch a single tensor, then touch all: does logical mapped
///        size differ from physical resident size?
///   O2-C Real forward           — first forward (T3), generations #1/#5/#10
///        (T4/T5/T6): does the footprint converge toward the full weight
///        size once real execution touches every layer?
///
/// NOT a pass/fail gate: the report records measurements. H-mmap vs H-eager
/// is decided by comparing the post-load footprint against the total weight
/// bytes (41.76 GiB, registered in the O1 inventory).
public struct O2MemorySnapshot: Codable, Sendable {
    public let label: String
    public let tMilliseconds: Int64
    public let physFootprintBytes: Int64
    public let residentBytes: Int64
    public let swapUsedBytes: Int64
    public let swapRaw: String
    public let mlxActiveBytes: Int64
    public let mlxCacheBytes: Int64
    public let mlxPeakBytes: Int64
}

public struct O2TouchRecord: Codable, Sendable {
    public let label: String
    public let physFootprintDeltaBytes: Int64
    public let note: String
}

public struct O2GenerationRecord: Codable, Sendable {
    public let index: Int
    public let promptTokens: Int
    public let generatedTokens: Int
    public let totalMilliseconds: Double
    public let ttftMilliseconds: Double
    public let tokensPerSecond: Double
}

public struct O2BaselineReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let physicalTotalBytes: Int64
    public let snapshots: [O2MemorySnapshot]
    public let selectiveTouch: [O2TouchRecord]
    public let generations: [O2GenerationRecord]
    public let firstForwardMilliseconds: Double
    public let promptLogitsChecksum: String
    public let loadMilliseconds: Double
    public let notes: [String]
}

public enum O2BaselineProbe {
    public static let protocolVersion = "G1.9-O2.BASELINE.V1"

    public static func physFootprintAndResident() -> (footprint: Int64, resident: Int64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (-1, -1) }
        return (Int64(info.phys_footprint), Int64(info.resident_size))
    }

    public static func swapUsage() -> (usedBytes: Int64, raw: String) {
        var size = 0
        sysctlbyname("vm.swapusage", nil, &size, nil, 0)
        guard size > 0 else { return (0, "") }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("vm.swapusage", &buffer, &size, nil, 0)
        let raw = String(cString: buffer)
        // Format: "total = 1024.00M used = 0.00M free = 1024.00M"
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
            return (Int64(bytes), raw)
        }
        return (0, raw)
    }

    public static func physicalTotalBytes() -> Int64 {
        var size = 0
        sysctlbyname("hw.memsize", nil, &size, nil, 0)
        guard size == MemoryLayout<UInt64>.size else { return 0 }
        var value: UInt64 = 0
        sysctlbyname("hw.memsize", &value, &size, nil, 0)
        return Int64(value)
    }

    public static func run(
        modelDirectory: URL,
        prompt: String = "Write a Python function that adds two numbers.",
        maxTokens: Int = 48,
        generations: Int = 10
    ) async throws -> O2BaselineReport {
        let start = ContinuousClock.now
        var snapshots: [O2MemorySnapshot] = []
        var notes: [String] = []

        func snap(_ label: String) {
            let (footprint, resident) = physFootprintAndResident()
            let (swapUsed, _) = swapUsage()
            let mlx = Memory.snapshot()
            snapshots.append(
                O2MemorySnapshot(
                    label: label,
                    tMilliseconds: Int64(Double(start.duration(to: .now).components.attoseconds) / 1e18 * 1000),
                    physFootprintBytes: footprint,
                    residentBytes: resident,
                    swapUsedBytes: swapUsed,
                    swapRaw: "",
                    mlxActiveBytes: Int64(mlx.activeMemory),
                    mlxCacheBytes: Int64(mlx.cacheMemory),
                    mlxPeakBytes: Int64(mlx.peakMemory)
                )
            )
        }

        snapshots.append(snapLabel("T0_PROCESS_START", start: start))

        // O2-A: native load — the fork's real path (factory + full weight
        // load; creation and weight read are one call in the native path).
        let loadStart = ContinuousClock.now
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        let loadMilliseconds = Double(loadStart.duration(to: .now).components.attoseconds) / 1e18 * 1000
        let modelType: String = await container.perform { (context: ModelContext) in
            String(describing: type(of: context.model))
        }
        snapshots.append(snapLabel("T1_T2_LOAD_COMPLETE", start: start))

        // O2-B: selective touch on one shard (pure MLX arrays, no model, no
        // SimiGo): mmap-load without eval, touch ONE tensor, then ALL —
        // measuring whether mapped size stays non-resident until touched.
        var touchRecords: [O2TouchRecord] = []
        let shardURL = modelDirectory
            .appendingPathComponent("model-00001-of-00009.safetensors")
        if FileManager.default.fileExists(atPath: shardURL.path) {
            let (arrays, _) = try MLX.loadArraysAndMetadata(url: shardURL)
            Memory.clearCache()
            let names = arrays.keys.sorted()

            if let firstName = names.first, let array = arrays[firstName] {
                let before = physFootprintAndResident().footprint
                let probeSum = array.sum()
                eval(probeSum)
                _ = probeSum.item(Float.self)
                let after = physFootprintAndResident().footprint
                touchRecords.append(
                    O2TouchRecord(
                        label: "SINGLE_TENSOR_\(firstName)",
                        physFootprintDeltaBytes: after - before,
                        note: "shard tensor count: \(names.count)"
                    )
                )
            }

            let beforeAll = physFootprintAndResident().footprint
            let sums = arrays.map { _, array in array.sum() }
            eval(sums)
            _ = sums.map { $0.item(Float.self) }
            let afterAll = physFootprintAndResident().footprint
            touchRecords.append(
                O2TouchRecord(
                    label: "ALL_TENSORS_IN_SHARD",
                    physFootprintDeltaBytes: afterAll - beforeAll,
                    note: "touched all \(arrays.count) tensors of the shard"
                )
            )
            Memory.clearCache()
        } else {
            notes.append("selective touch skipped: shard file not found")
        }

        // O2-C: real forward (T3) + generations (T4/T5/T6 milestones).
        let promptTokenIDs: [Int] = try await container.perform { (context: ModelContext) in
            let messages: [[String: any Sendable]] = [
                ["role": "user", "content": prompt]
            ]
            if let configured = context.tokenizer as? Tokenizers.PreTrainedTokenizer,
                configured.hasChatTemplate
            {
                return try configured.applyChatTemplate(
                    messages: messages,
                    tools: nil,
                    additionalContext: ["enable_thinking": false]
                )
            }
            return try context.tokenizer.applyChatTemplate(messages: messages)
        }

        let forwardStart = ContinuousClock.now
        let logitsChecksum: String = await container.perform { (context: ModelContext) -> String in
            let logits = context.model(
                MLXArray(promptTokenIDs, [1, promptTokenIDs.count]), cache: nil
            )
            eval(logits)
            let checksum = InstrumentationIdentityProbe.sha256Base64(logits)
            Memory.clearCache()
            return checksum
        }
        let forwardMs = Double(forwardStart.duration(to: .now).components.attoseconds) / 1e18 * 1000
        snap("T3_FIRST_FORWARD_COMPLETE")

        var generationRecords: [O2GenerationRecord] = []
        for index in 1...max(1, generations) {
            let genStart = ContinuousClock.now
            let (ttftMilliseconds, tokens) = await container.perform { (context: ModelContext) -> (Double, [Int]) in
                var ttftMilliseconds: Double = 0
                var tokens: [Int] = []
                var running = MLXArray(promptTokenIDs, [1, promptTokenIDs.count])
                var first = true
                for _ in 0..<maxTokens {
                    let logits = context.model(running, cache: nil)[0, -1]
                    let nextToken = logits.argMax().item(Int.self)
                    if first {
                        ttftMilliseconds = Double(
                            genStart.duration(to: .now).components.attoseconds
                        ) / 1e18 * 1000
                        first = false
                    }
                    tokens.append(nextToken)
                    if nextToken == context.tokenizer.eosTokenId ?? -1 {
                        break
                    }
                    let promptAndGenerated = promptTokenIDs + tokens
                    running = MLXArray(promptAndGenerated, [1, promptAndGenerated.count])
                    eval(logits)
                }
                return (ttftMilliseconds, tokens)
            }
            let totalMs = Double(genStart.duration(to: .now).components.attoseconds) / 1e18 * 1000
            let steadyTokens = max(tokens.count - 1, 1)
            let steadySeconds = max(totalMs - ttftMilliseconds, 0.001) / 1000
            generationRecords.append(
                O2GenerationRecord(
                    index: index,
                    promptTokens: promptTokenIDs.count,
                    generatedTokens: tokens.count,
                    totalMilliseconds: totalMs,
                    ttftMilliseconds: ttftMilliseconds,
                    tokensPerSecond: Double(steadyTokens) / steadySeconds
                )
            )
            if index == 1 || index == 5 || index == generations {
                snap("T\(index == 1 ? 4 : index == 5 ? 5 : 6)_GEN_\(index)")
            }
        }

        snapshots.append(snapLabel("END", start: start))
        _ = forwardMs
        _ = logitsChecksum

        return O2BaselineReport(
            status: "COMPLETED",
            boundary:
                "NATIVE_MLX_BASELINE / ZERO_SIMIGO_INTERVENTION / MEASUREMENT_ONLY / NOT_A_PERFORMANCE_CLAIM",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: modelType,
            physicalTotalBytes: physicalTotalBytes(),
            snapshots: snapshots,
            selectiveTouch: touchRecords,
            generations: generationRecords,
            firstForwardMilliseconds: forwardMs,
            promptLogitsChecksum: logitsChecksum,
            loadMilliseconds: loadMilliseconds,
            notes: notes
        )
    }

    private static func snapLabel(
        _ label: String,
        start: ContinuousClock.Instant
    ) -> O2MemorySnapshot {
        let (footprint, resident) = physFootprintAndResident()
        let (swapUsed, _) = swapUsage()
        let mlx = Memory.snapshot()
        return O2MemorySnapshot(
            label: label,
            tMilliseconds: Int64(Double(start.duration(to: .now).components.attoseconds) / 1e18 * 1000),
            physFootprintBytes: footprint,
            residentBytes: resident,
            swapUsedBytes: swapUsed,
            swapRaw: "",
            mlxActiveBytes: Int64(mlx.activeMemory),
            mlxCacheBytes: Int64(mlx.cacheMemory),
            mlxPeakBytes: Int64(mlx.peakMemory)
        )
    }
}
