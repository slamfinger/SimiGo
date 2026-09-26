import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXNN
import SimiGoRuntimeContract
import Tokenizers

// O6 — Execution State × Oversized Model (design registered 2026-09-26).
//
// Layering (who owns what):
//   ExecutionContinuityCoordinator — identity/lineage/position/continuation
//                                    (sovereignty; unchanged from E-line)
//   OversizedSegmentedStateBackend — ExecutionStateBackend over a prefix
//                                    payload; releaseRepresentation IS the
//                                    oversized eviction (all segment weights
//                                    released, logical record survives)
//   SegmentedCore                  — the verified physical machinery
//                                    (placeholder-first load; per segment:
//                                    materialize -> forwardLayerRange ->
//                                    release; seg8 Pareto-best partition)
//   OversizedSegmentedExecutor     — consumes the bound representation via
//                                    cacheless greedy re-forward (E5-v2
//                                    representation-consuming semantics)
//
// The E4 invariant under test at 41.76 GiB scale: an Execution State that
// had its segments evicted IS still the same Execution State.

// MARK: - Payload / result

public struct OversizedPrefixPayload: ExecutionRepresentationPayload, Equatable, Sendable {
    public let tokenPrefix: [Int]
    public init(tokenPrefix: [Int]) {
        self.tokenPrefix = tokenPrefix
    }
}

// MARK: - Segmented physical core

final class O6SegmentedCore: @unchecked Sendable {
    let segments: [ClosedRange<Int>]
    let peakCapacityMiB: Int64 = 30 * 1024

    private let reader: PerTensorSafetensorsReader
    private let model: Qwen3NextModel
    private let switchNames: [String]
    private let clock = ContinuousClock()

    private(set) var peakFootprintMiB: Int64 = 0
    private(set) var maxSwapMiB: Int64 = 0
    private(set) var segmentTransitions: Int = 0

    init(modelDirectory: URL, segmentSize: Int) async throws {
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
        reader = try PerTensorSafetensorsReader(
            modelDirectory: modelDirectory, weightMap: weightMap
        )

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
        self.model = model

        // Placeholder-first: real core, zero-size segment placeholders — the
        // registered cliff fix. update(verify: []) is pure assignment.
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
    }

    func gauge() -> (activeMiB: Int64, footprintMiB: Int64, swapMiB: Int64) {
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
        let fpMiB = footprint / 1048576
        peakFootprintMiB = max(peakFootprintMiB, fpMiB)
        maxSwapMiB = max(maxSwapMiB, swapMiB)
        return (activeMiB, fpMiB, swapMiB)
    }

    /// Materialize one segment (read -> eval -> update; dict scoped so refs
    /// drop with the scope — the D-P3 release fix).
    func materialize(_ segment: ClosedRange<Int>) throws {
        do {
            var arrays: [String: MLXArray] = [:]
            for name in switchNames {
                if let range = name.range(of: #"layers\.(\d+)\."#, options: .regularExpression) {
                    let digits = name[range].split(separator: ".").compactMap { Int($0) }
                    if let layer = digits.first, segment.contains(layer) {
                        arrays[name] = try autoreleasepool {
                            try autoreleasepool { try reader.loadTensor(named: name) }
                        }
                    }
                }
            }
            eval(arrays.values.map { $0 })
            try model.update(parameters: ModuleParameters.unflattened(arrays), verify: [])
        }
        segmentTransitions += 1
    }

    /// Release every segment (the oversized eviction) and purge buffers.
    func releaseAllSegments() throws {
        var placeholders: [String: MLXArray] = [:]
        for name in switchNames {
            placeholders[name] = MLXArray([Int](), [0])
        }
        try model.update(parameters: ModuleParameters.unflattened(placeholders), verify: [])
        Memory.clearCache()
        segmentTransitions += 1
    }

    /// Cacheless greedy generation: full-sequence re-forward per token,
    /// segments materialized/executed/released in order.
    func greedy(prefix: [Int], maxTokens: Int) throws -> [Int] {
        var ids = prefix
        var generated: [Int] = []
        for _ in 0..<maxTokens {
            var hidden = model.embedInputs(MLXArray(ids, [1, ids.count]))
            eval(hidden)
            for segment in segments {
                try materialize(segment)
                hidden = model.forwardLayerRange(
                    hidden, layerRange: segment.lowerBound..<(segment.upperBound + 1), cache: nil
                )
                eval(hidden)
                try releaseSegment(segment)
            }
            let logits = model.projectOutput(hidden)[0, -1]
            eval(logits)
            let next = logits.argMax().item(Int.self)
            generated.append(next)
            ids.append(next)
            _ = gauge()
        }
        return generated
    }

    private func releaseSegment(_ segment: ClosedRange<Int>) throws {
        var placeholders: [String: MLXArray] = [:]
        for name in switchNames {
            if let range = name.range(of: #"layers\.(\d+)\."#, options: .regularExpression) {
                let digits = name[range].split(separator: ".").compactMap { Int($0) }
                if let layer = digits.first, segment.contains(layer) {
                    placeholders[name] = MLXArray([Int](), [0])
                }
            }
        }
        try model.update(parameters: ModuleParameters.unflattened(placeholders), verify: [])
        Memory.clearCache()
    }
}

// MARK: - Oversized ExecutionStateBackend

public final class OversizedSegmentedStateBackend: ExecutionStateBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var prefixes: [ExecutionID: [Int]] = [:]
    private var boundPositions: [ExecutionID: ExecutionPosition] = [:]
    /// Physical eviction hook (the oversized segment release). Decoupled
    /// from O6SegmentedCore so the app engine can host the same backend.
    private let releaseAll: () throws -> Void

    init(releaseAll: @escaping () throws -> Void) {
        self.releaseAll = releaseAll
    }

    public func bind(executionID: ExecutionID, position: ExecutionPosition, prefix: [Int]) {
        lock.lock(); defer { lock.unlock() }
        prefixes[executionID] = prefix
        boundPositions[executionID] = position
    }

    public func boundPrefix(
        for state: ExecutionStateHandle
    ) throws -> (prefix: [Int], position: ExecutionPosition) {
        lock.lock(); defer { lock.unlock() }
        guard let prefix = prefixes[state.id], let bound = boundPositions[state.id] else {
            throw ExecutionStateBackendError.noBoundRepresentation(state.id)
        }
        guard bound == state.position else {
            throw ExecutionStateBackendError.representationPositionMismatch(
                executionID: state.id, bound: bound, logical: state.position)
        }
        return (prefix, bound)
    }

    public func consumeBinding(for state: ExecutionStateHandle) {
        lock.lock(); defer { lock.unlock() }
        prefixes[state.id] = nil
        boundPositions[state.id] = nil
    }

    public func captureRepresentation(
        for state: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation {
        lock.lock()
        let prefix = prefixes[state.id]
        let bound = boundPositions[state.id]
        lock.unlock()
        guard let prefix, let bound else {
            throw ExecutionStateBackendError.noBoundRepresentation(state.id)
        }
        guard bound == state.position else {
            throw ExecutionStateBackendError.representationPositionMismatch(
                executionID: state.id, bound: bound, logical: state.position)
        }
        return ExecutionRepresentation(
            executionID: state.id, position: state.position,
            payload: OversizedPrefixPayload(tokenPrefix: prefix))
    }

    public func deriveRepresentation(
        from parent: ExecutionRepresentation, for child: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation {
        guard let parentPayload = parent.payload as? OversizedPrefixPayload else {
            throw ExecutionStateBackendError.foreignRepresentationPayload(parent.executionID)
        }
        let payload = OversizedPrefixPayload(tokenPrefix: parentPayload.tokenPrefix)
        bind(executionID: child.id, position: child.position, prefix: payload.tokenPrefix)
        return ExecutionRepresentation(
            executionID: child.id, position: child.position, payload: payload)
    }

    public func restoreRepresentation(_ representation: ExecutionRepresentation) async throws {
        guard let payload = representation.payload as? OversizedPrefixPayload else {
            throw ExecutionStateBackendError.foreignRepresentationPayload(representation.executionID)
        }
        bind(
            executionID: representation.executionID, position: representation.position,
            prefix: payload.tokenPrefix)
    }

    /// The oversized eviction: release every segment's weights, then drop
    /// the prefix binding. ORDER IS THE ATOMICITY CONTRACT (review:
    /// backend physical atomicity): the fallible physical release runs
    /// FIRST — a failure leaves the binding INTACT and retryable — and the
    /// infallible binding cleanup commits last. The logical Execution
    /// State survives either way (E4 invariant at segment granularity).
    public func releaseRepresentation(_ representation: ExecutionRepresentation) async throws {
        try releaseAll()
        lock.lock()
        prefixes[representation.executionID] = nil
        boundPositions[representation.executionID] = nil
        lock.unlock()
    }
}

// MARK: - Oversized executor (representation-consuming, E5-v2 semantics)

public final class OversizedSegmentedExecutor: @unchecked Sendable {
    private let core: O6SegmentedCore
    private let backend: OversizedSegmentedStateBackend
    private let tokenizer: Tokenizers.Tokenizer

    init(core: O6SegmentedCore, backend: OversizedSegmentedStateBackend, tokenizer: Tokenizers.Tokenizer) {
        self.core = core
        self.backend = backend
        self.tokenizer = tokenizer
    }

    public func tokenizeText(_ text: String) throws -> [Int] {
        try tokenizer.encode(text: text, addSpecialTokens: false)
    }

    public func tokenizeSeedText(_ text: String) throws -> [Int] {
        try tokenizer.encode(text: text, addSpecialTokens: true)
    }

    public func continueExecution(
        _ state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int
    ) async throws -> ExecutionContinuationResult {
        let bound = try backend.boundPrefix(for: state)
        let inputTokens = bound.prefix + nextInputTokens
        let generated = try core.greedy(prefix: inputTokens, maxTokens: maxTokens)
        backend.consumeBinding(for: state)
        let text: String = tokenizer.decode(tokens: generated, skipSpecialTokens: true)
        return ExecutionContinuationResult(
            executionID: state.id,
            consumedPrefixLength: bound.prefix.count,
            nextInputTokenCount: nextInputTokens.count,
            generatedTokenIDs: generated,
            generatedText: text,
            updatedPayload: OversizedPrefixPayload(tokenPrefix: inputTokens + generated)
        )
    }
}

// MARK: - O6 scenario report

public struct O6Check: Codable, Sendable {
    public let name: String
    public let pass: Bool
    public let detail: String
}

public struct O6ExecutionStateReport: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let segmentSize: Int
    public let segmentCount: Int
    public let checks: [O6Check]
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let overallPass: Bool
    public let boundary: String
}

public enum O6ExecutionStateScenario {
    public static let protocolVersion = "G1.9-O6.EXECSTATE.V1"

    public static func run(
        modelDirectory: URL,
        maxTokens: Int = 4,
        segmentSize: Int = 8
    ) async throws -> O6ExecutionStateReport {
        var checks: [O6Check] = []
        func check(_ name: String, _ pass: Bool, _ detail: String) {
            checks.append(O6Check(name: name, pass: pass, detail: detail))
        }

        let core = try await O6SegmentedCore(
            modelDirectory: modelDirectory, segmentSize: segmentSize
        )
        let backend = OversizedSegmentedStateBackend(releaseAll: { try core.releaseAllSegments() })
        let coordinator = ExecutionContinuityCoordinator(backend: backend)
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
        let executor = OversizedSegmentedExecutor(
            core: core, backend: backend, tokenizer: tokenizer
        )

        let seedText = "def is_palindrome(s):"
        let parentUserText = "Explain it briefly."
        let childUserText = "Now write tests for it."
        let seedTokens = try executor.tokenizeSeedText(seedText)

        // -- Parent P: create + bootstrap generation (consumes prefix).
        _ = try await coordinator.create(
            id: ExecutionID("P"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: parentUserText, continuationID: "P-cont-0")
        )
        try backend.bind(executionID: ExecutionID("P"), position: ExecutionPosition(0), prefix: seedTokens)
        let u1 = try executor.tokenizeText(parentUserText)
        let outP1 = try await executor.continueExecution(
            coordinator.handle(ExecutionID("P"))!, nextInputTokens: u1, maxTokens: maxTokens
        )
        _ = try await coordinator.continueExecution(
            coordinator.handle(ExecutionID("P"))!,
            continuation: ExecutionContinuation(nextInput: parentUserText, continuationID: "P-cont-1")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("P"), position: ExecutionPosition(1),
            payload: outP1.updatedPayload
        )
        let parentAfterTurn1 = coordinator.handle(ExecutionID("P"))!

        // -- Non-interference reference: parent turn 2 BEFORE the child episode.
        let u2 = try executor.tokenizeText(parentUserText + " In one sentence.")
        let referenceParentTurn2 = try await executor.continueExecution(
            parentAfterTurn1, nextInputTokens: u2, maxTokens: maxTokens
        )
        // Roll the physical binding back to the post-turn-1 checkpoint so the
        // fork point matches (the reference run consumed the binding).
        try await backend.restoreRepresentation(
            ExecutionRepresentation(
                executionID: ExecutionID("P"), position: ExecutionPosition(1),
                payload: outP1.updatedPayload)
        )

        // -- Fork C at the parent's post-turn-1 position.
        let child = try await coordinator.fork(
            ExecutionForkRequest(
                parent: parentAfterTurn1,
                childID: ExecutionID("C"),
                childPosition: ExecutionPosition(1),
                childContinuation: ExecutionContinuation(
                    nextInput: childUserText, continuationID: "C-cont-2")
            )
        )
        check(
            "PARENT_IDENTITY_STABLE",
            parentAfterTurn1.id == ExecutionID("P")
                && parentAfterTurn1.lineage.parent == nil,
            "parent identity/lineage unchanged across fork")
        check(
            "CHILD_LINEAGE_TRACEABLE",
            child.lineage.parent == ExecutionID("P") && child.lineage.root == parentAfterTurn1.lineage.root,
            "child lineage parent=P, root shared")

        // -- Child run 1 (divergent input) from the fork point.
        let uc = try executor.tokenizeText(childUserText)
        let childRun1 = try await executor.continueExecution(
            child, nextInputTokens: uc, maxTokens: maxTokens
        )
        _ = try await coordinator.continueExecution(
            child,
            continuation: ExecutionContinuation(nextInput: childUserText, continuationID: "C-cont-3")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("C"), position: ExecutionPosition(2),
            payload: childRun1.updatedPayload
        )

        check(
            "FORK_DIVERGENCE",
            childRun1.generatedTokenIDs != referenceParentTurn2.generatedTokenIDs,
            "child continuation diverged from parent continuation")

        // -- EVICT: release the child's CURRENT representation binding (pos 2)
        // and all segment weights. The fork-point representation (pos 1) was
        // derived at fork time and lives in the coordinator's history — it
        // survives the eviction, exactly as in E5.
        let currentChildRep = try await backend.captureRepresentation(
            for: coordinator.handle(ExecutionID("C"))!
        )
        try await backend.releaseRepresentation(currentChildRep)
        let afterEvict = core.gauge()

        // -- LOGICAL RESTORE to the fork point (pos 1): the coordinator finds
        // the surviving fork-point representation in its history and the
        // backend re-binds it; logical position returns to 1.
        let restoredChild = try await coordinator.restore(
            coordinator.handle(ExecutionID("C"))!,
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(1),
                continuation: ExecutionContinuation(
                    nextInput: childUserText, continuationID: "C-cont-2")
            )
        )
        check(
            "RESTORE_TO_FORK_POINT",
            restoredChild.position == ExecutionPosition(1)
                && restoredChild.lifecycle == .restored,
            "logical position rolled back to the fork point; segments re-materialize on demand")

        // -- Child run 2 consuming the RESTORED fork-point representation with
        // the SAME next input: token-identical to run 1 (D-I).
        let childRun2 = try await executor.continueExecution(
            coordinator.handle(ExecutionID("C"))!, nextInputTokens: uc, maxTokens: maxTokens
        )
        check(
            "CHILD_DETERMINISM_THROUGH_SEGMENT_EVICT_RESTORE",
            childRun2.generatedTokenIDs == childRun1.generatedTokenIDs
                && childRun2.generatedText == childRun1.generatedText,
            "run2 after evict+restore == run1, consuming the restored fork-point representation")

        // -- Parent turn 2 (actual) after the whole child episode.
        let actualParentTurn2 = try await executor.continueExecution(
            coordinator.handle(ExecutionID("P"))!, nextInputTokens: u2, maxTokens: maxTokens
        )
        check(
            "PARENT_NON_INTERFERENCE",
            actualParentTurn2.generatedTokenIDs == referenceParentTurn2.generatedTokenIDs,
            "parent turn 2 after the child episode == pre-fork reference")

        // -- Capacity/residency bounds across the whole scenario.
        let endGauge = core.gauge()
        check(
            "RESIDENCY_BOUNDED_ZERO_SWAP",
            core.peakFootprintMiB <= core.peakCapacityMiB && core.maxSwapMiB == 0,
            "peak footprint \(core.peakFootprintMiB) MiB <= \(core.peakCapacityMiB) MiB, max swap \(core.maxSwapMiB) MiB")
        check(
            "SEGMENT_TRANSITIONS_EXECUTED",
            core.segmentTransitions > 0,
            "\(core.segmentTransitions) segment materialize/release transitions executed")
        _ = afterEvict
        _ = endGauge

        let overallPass = checks.allSatisfy { $0.pass }
        return O6ExecutionStateReport(
            status: overallPass ? "PASS" : "FAIL",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: "qwen3_next",
            segmentSize: segmentSize,
            segmentCount: core.segments.count,
            checks: checks,
            peakFootprintMiB: core.peakFootprintMiB,
            maxSwapMiB: core.maxSwapMiB,
            overallPass: overallPass,
            boundary:
                "EXECUTION_STATE_X_OVERSIZED / SEGMENT_EVICT_RESTORE_IDENTITY / HARNESS_LEVEL / NOT_A_PERFORMANCE_CLAIM"
        )
    }
}
