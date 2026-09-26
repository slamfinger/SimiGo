import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXNN
import SimiGoRuntimeContract
import Tokenizers

/// OversizedSegmentedEngine — the O-line's verified execution mechanics,
/// productized as the app-facing engine, tuned for normal conversation
/// (2026-09-26 user budget: resident memory < 16 GiB, MLX cache < 16 GiB,
/// system memory pressure green/normal).
///
/// Policy: PERSISTENT LAYER FLOOR — the first L layers' switch_mlp weights
/// load real at startup and stay resident (never re-read); the remaining
/// layers stream in small units (materialize → forwardLayerRange → release
/// per unit). L is derived from the actual per-layer byte sizes so that
/// core + floor + one streaming unit fits the resident budget. Per-token
/// re-read volume drops from the full switch span (~40.5 GiB) to the
/// streamed span only.
///
/// Defaults encode the measured O5 baseline (segment unit 4-8 layers,
/// Pareto-best granularity on 32 GiB hardware). Load is placeholder-first
/// (the registered cliff fix) through the single-copy reader; generation
/// is greedy and cacheless (no second KV authority) with checkpoint
/// chat-template multi-turn input. Supported: qwen3_next.

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
    public let cacheMiB: Int64
    public let swapMiB: Int64
    public let streamingUnit: Int
    /// System memory-pressure level (kern.memorystatus_vm_pressure_level):
    /// 1 = normal (green), 2 = warning, 4 = critical.
    public let pressureLevel: Int32
}

public struct OversizedEngineStats: Codable, Sendable {
    public let residentActiveMiB: Int64
    public let peakFootprintMiB: Int64
    public let peakCacheMiB: Int64
    public let maxSwapMiB: Int64
    public let maxPressureLevel: Int32
    public let loadSeconds: Double
    public let meanTokenMs: Double
    public let unitLayers: Int
    public let unitCount: Int
    public let residentLayers: Int
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

public struct OversizedSessionInfo: Codable, Sendable {
    public let executionID: String
    public let position: Int
    public let turns: Int
    public let records: Int
}

public final class OversizedSegmentedEngine: @unchecked Sendable {
    public static let defaultUnitLayers = 24
    /// Chat budget (user-set 2026-09-26): resident memory < 16 GiB, MLX
    /// cache < 16 GiB, system memory pressure green.
    public static let defaultPeakCapacityMiB: Int64 = 16 * 1024

    private let modelDirectory: URL
    private let unitLayers: Int
    private let peakCapacityMiB: Int64
    /// Derivation-only budget for the persistent floor. Decoupled from the
    /// PASS gate: pushing the floor up trades page cache for wired memory,
    /// so the latency/pressure optimum is measured, not assumed.
    private let floorBudgetMiB: Int64

    private var model: Qwen3NextModel?
    private var reader: PerTensorSafetensorsReader?
    private var tokenizer: Tokenizers.Tokenizer?
    private var switchNames: [String] = []
    private var units: [ClosedRange<Int>] = []
    private var residentLayers = 0
    private var totalLayers = 0
    private var modelType = ""

    public private(set) var stats: OversizedEngineStats?

    // Execution State session layer (strict): every conversation turn is a
    // lifecycle-recorded continueExecution on a real Execution State; the
    // conversation prefix IS the bound representation; new session =
    // discard + create; restore = logical rollback (used by the self-test).
    private var coordinator: ExecutionContinuityCoordinator?
    private var stateBackend: OversizedSegmentedStateBackend?
    private var currentState: ExecutionStateHandle?
    private var sessionTurnCount = 0

    public private(set) var sessionInfo: OversizedSessionInfo?

    public init(
        modelDirectory: URL,
        unitLayers: Int = OversizedSegmentedEngine.defaultUnitLayers,
        peakCapacityMiB: Int64 = OversizedSegmentedEngine.defaultPeakCapacityMiB,
        floorBudgetMiB: Int64? = 4096
    ) {
        self.modelDirectory = modelDirectory
        self.unitLayers = unitLayers
        self.peakCapacityMiB = peakCapacityMiB
        self.floorBudgetMiB = floorBudgetMiB ?? peakCapacityMiB
    }

    private let clock = ContinuousClock()

    private func pressureLevel() -> Int32 {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) != 0 {
            return -1
        }
        return level
    }

    private func gauge() -> (
        activeMiB: Int64, footprintMiB: Int64, cacheMiB: Int64, swapMiB: Int64, pressure: Int32
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
        return (
            Int64(mlx.activeMemory / 1048576), footprint / 1048576,
            Int64(mlx.cacheMemory / 1048576), swapMiB, pressureLevel()
        )
    }

    private func layerOf(_ name: String) -> Int? {
        guard let range = name.range(of: #"layers\.(\d+)\."#, options: .regularExpression) else {
            return nil
        }
        let digits = name[range].split(separator: ".").compactMap { Int($0) }
        return digits.first
    }

    /// Skeleton + per-layer quantize + budgeted placeholder-first load:
    /// real tensors for the core AND the persistent layer floor; zero-size
    /// placeholders for the streamed units. ONE update before any eval —
    /// the registered cliff fix. update(verify: []) is pure assignment.
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
        switchNames = reader.locations.values
            .filter { $0.name.contains(".switch_mlp.") }
            .map { $0.name }

        // Budgeted persistent-floor derivation from actual per-layer bytes.
        var layerBytes = [Int64](repeating: 0, count: totalLayers)
        var coreBytes: Int64 = 0
        for location in reader.locations.values {
            if location.name.contains(".switch_mlp."), let layer = layerOf(location.name),
               layer < totalLayers {
                layerBytes[layer] += Int64(location.byteCount)
            } else if !location.name.contains(".switch_mlp.") {
                coreBytes += Int64(location.byteCount)
            }
        }
        let unitCount0 = max(1, totalLayers / max(1, unitLayers))
        let avgLayerBytes = layerBytes.isEmpty
            ? Int64(0)
            : layerBytes.reduce(Int64(0), +) / Int64(max(1, layerBytes.count))
        let budgetBytes = floorBudgetMiB * 1024 * 1024
        let unitBytes = avgLayerBytes * Int64(unitLayers)
        let floorCount = Int(
            max(0, min(Double(totalLayers - unitLayers), floor(Double(budgetBytes - coreBytes - unitBytes) / Double(max(avgLayerBytes, 1)))))
        )
        residentLayers = floorCount
        var segs: [ClosedRange<Int>] = []
        var start = floorCount
        while start < totalLayers {
            let end = min(start + unitLayers - 1, totalLayers - 1)
            segs.append(start...end)
            start = end + 1
        }
        units = segs
        _ = unitCount0

        var fullParameterMap: [String: MLXArray] = [:]
        for location in reader.locations.values {
            let isSwitch = location.name.contains(".switch_mlp.")
            let persistent =
                !isSwitch
                || (layerOf(location.name).flatMap { $0 < residentLayers } ?? false)
            if persistent {
                fullParameterMap[location.name] = try autoreleasepool {
                    try reader.loadTensor(named: location.name)
                }
            } else {
                fullParameterMap[location.name] = MLXArray([Int](), [0])
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
        let loadDuration = loadStart.duration(to: clock.now)
        let loadSeconds = Double(loadDuration.components.seconds)
            + Double(loadDuration.components.attoseconds) / 1e18
        let stats = OversizedEngineStats(
            residentActiveMiB: g.activeMiB,
            peakFootprintMiB: g.footprintMiB,
            peakCacheMiB: g.cacheMiB,
            maxSwapMiB: g.swapMiB,
            maxPressureLevel: g.pressure,
            loadSeconds: loadSeconds,
            meanTokenMs: 0,
            unitLayers: unitLayers,
            unitCount: units.count,
            residentLayers: residentLayers,
            totalLayers: totalLayers,
            peakCapacityMiB: peakCapacityMiB
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

    /// Multi-turn greedy generation with per-token streaming callbacks —
    /// strictly through the Execution State layer: turn 1 bootstraps the
    /// session (chat-template prefix bound at position 0); every later turn
    /// CONSUMES the bound representation (raw continuation, E5-v2 encoding),
    /// advances the logical position (lifecycle record), and rebinds the
    /// advanced prefix. The persistent floor forwards in one call; streamed
    /// units follow materialize → forward → release.
    @discardableResult
    public func generate(
        messages: [EngineChatMessage],
        maxNewTokens: Int,
        nextInputTokens: [Int]?? = nil,
        onToken: (@Sendable (OversizedEngineGauge, String) -> Void)? = nil
    ) async throws -> OversizedEngineTurn {
        guard let model, let reader, let tokenizer else {
            throw OversizedEngineError.notLoaded
        }
        var nextInput: [Int]
        if let explicit = nextInputTokens {
            // Explicitly provided (including empty) — e.g. the strict
            // bootstrap replay in the self-test.
            nextInput = explicit ?? []
        } else if currentState == nil || coordinator == nil {
            let prefix = try promptTokenIDs(for: messages)
            currentState = try await ensureSession(prefix: prefix)
            nextInput = []
        } else {
            guard let lastUser = messages.last(where: { $0.role == "user" }) else {
                throw OversizedEngineError.notLoaded
            }
            nextInput = try tokenizer.encode(text: lastUser.content, addSpecialTokens: false)
        }
        guard let state = currentState, let stateBackend else {
            throw OversizedEngineError.notLoaded
        }
        return try await executeTurn(
            state: state, backend: stateBackend, nextInput: nextInput,
            messages: messages, maxNewTokens: maxNewTokens, onToken: onToken
        )
    }

    /// Strict replay of the bootstrap turn: consumes the CURRENT bound
    /// representation (the position-0 prefix after restoreSession(to: 0))
    /// with an EMPTY next input — bit-identical to the original bootstrap.
    @discardableResult
    public func replayBootstrapTurn(
        maxNewTokens: Int,
        onToken: (@Sendable (OversizedEngineGauge, String) -> Void)? = nil
    ) async throws -> OversizedEngineTurn {
        guard let model, let reader, let tokenizer else {
            throw OversizedEngineError.notLoaded
        }
        guard let state = currentState, let stateBackend else {
            throw OversizedEngineError.notLoaded
        }
        return try await executeTurn(
            state: state, backend: stateBackend, nextInput: [],
            messages: [], maxNewTokens: maxNewTokens, onToken: onToken
        )
    }

    private func executeTurn(
        state: ExecutionStateHandle,
        backend: OversizedSegmentedStateBackend,
        nextInput: [Int],
        messages: [EngineChatMessage],
        maxNewTokens: Int,
        onToken: (@Sendable (OversizedEngineGauge, String) -> Void)? = nil
    ) async throws -> OversizedEngineTurn {
        let model = self.model
        let reader = self.reader
        let tokenizer = self.tokenizer
        guard let model, let reader, let tokenizer else {
            throw OversizedEngineError.notLoaded
        }
        let bound = try backend.boundPrefix(for: state)
        var ids = bound.prefix + nextInput
        var generated: [Int] = []
        var tokenMs: [Double] = []
        var peakFootprint: Int64 = 0
        var peakCache: Int64 = 0
        var maxSwap: Int64 = 0
        var maxPressure: Int32 = 0

        for index in 0..<maxNewTokens {
            let tokenStart = clock.now
            var hidden = model.embedInputs(MLXArray(ids, [1, ids.count]))
            eval(hidden)

            if residentLayers > 0 {
                hidden = model.forwardLayerRange(
                    hidden, layerRange: 0..<residentLayers, cache: nil
                )
                eval(hidden)
            }

            for (unitIndex, unit) in units.enumerated() {
                do {
                    var arrays: [String: MLXArray] = [:]
                    for name in switchNames {
                        if let layer = layerOf(name), unit.contains(layer) {
                            arrays[name] = try autoreleasepool {
                                try reader.loadTensor(named: name)
                            }
                        }
                    }
                    eval(arrays.values.map { $0 })
                    try model.update(
                        parameters: ModuleParameters.unflattened(arrays), verify: []
                    )
                }
                hidden = model.forwardLayerRange(
                    hidden, layerRange: unit.lowerBound..<(unit.upperBound + 1), cache: nil
                )
                eval(hidden)
                var placeholders: [String: MLXArray] = [:]
                for name in switchNames {
                    if let layer = layerOf(name), unit.contains(layer) {
                        placeholders[name] = MLXArray([Int](), [0])
                    }
                }
                try model.update(
                    parameters: ModuleParameters.unflattened(placeholders), verify: []
                )
                Memory.clearCache()
                _ = unitIndex
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
            peakCache = max(peakCache, g.cacheMiB)
            maxSwap = max(maxSwap, g.swapMiB)
            maxPressure = max(maxPressure, g.pressure)
            let tokenText = tokenizer.decode(tokens: [next], skipSpecialTokens: true)
            onToken?(OversizedEngineGauge(
                tokenIndex: index + 1, activeMiB: g.activeMiB,
                footprintMiB: g.footprintMiB, cacheMiB: g.cacheMiB, swapMiB: g.swapMiB,
                streamingUnit: units.isEmpty ? -1 : units[units.count - 1].lowerBound,
                pressureLevel: g.pressure
            ), tokenText)
        }

        // Physical prefix consumed; advance the logical Execution State and
        // rebind the advanced representation (E5-v2 pattern).
        backend.consumeBinding(for: state)
        let advanced = try await coordinator!.continueExecution(
            state,
            continuation: ExecutionContinuation(
                nextInput: messages.last?.content ?? "",
                continuationID: "S-cont-\(state.position.value + 1)"
            )
        )
        currentState = advanced
        sessionTurnCount += 1
        try await coordinator!.bindRepresentation(
            executionID: advanced.id,
            position: advanced.position,
            payload: OversizedPrefixPayload(tokenPrefix: ids)
        )
        sessionInfo = OversizedSessionInfo(
            executionID: advanced.id.rawValue,
            position: Int(advanced.position.value),
            turns: sessionTurnCount,
            records: coordinator!.recordCount
        )

        let text = tokenizer.decode(tokens: generated, skipSpecialTokens: true)
        let mean = tokenMs.isEmpty ? 0 : tokenMs.reduce(0, +) / Double(tokenMs.count)
        if var s = stats {
            s = OversizedEngineStats(
                residentActiveMiB: s.residentActiveMiB,
                peakFootprintMiB: max(s.peakFootprintMiB, peakFootprint),
                peakCacheMiB: max(s.peakCacheMiB, peakCache),
                maxSwapMiB: max(s.maxSwapMiB, maxSwap),
                maxPressureLevel: max(s.maxPressureLevel, maxPressure),
                loadSeconds: s.loadSeconds,
                meanTokenMs: mean,
                unitLayers: s.unitLayers,
                unitCount: s.unitCount,
                residentLayers: s.residentLayers,
                totalLayers: s.totalLayers,
                peakCapacityMiB: s.peakCapacityMiB
            )
            stats = s
        }
        return OversizedEngineTurn(text: text, tokenIDs: generated, meanTokenMs: mean)
    }

    // MARK: - Execution State session

    private func ensureSession(prefix: [Int]) async throws -> ExecutionStateHandle {
        guard coordinator == nil, stateBackend == nil, currentState == nil else {
            throw OversizedEngineError.notLoaded
        }
        let backend = OversizedSegmentedStateBackend(releaseAll: { [weak self] in
            guard let self else { return }
            try self.releaseAllSegments()
        })
        let coordinator = ExecutionContinuityCoordinator(backend: backend)
        let state = try await coordinator.create(
            id: ExecutionID("S"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: "", continuationID: "S-cont-0")
        )
        backend.bind(executionID: state.id, position: state.position, prefix: prefix)
        try await coordinator.bindRepresentation(
            executionID: state.id, position: state.position,
            payload: OversizedPrefixPayload(tokenPrefix: prefix)
        )
        stateBackend = backend
        self.coordinator = coordinator
        currentState = state
        return state
    }

    /// New session: discard the current Execution State (lifecycle record)
    /// and reset. The next generate() bootstraps a fresh state.
    public func newSession() async throws {
        if let coordinator, let state = currentState {
            try await coordinator.discard(state)
        }
        coordinator = nil
        stateBackend = nil
        currentState = nil
        sessionTurnCount = 0
        sessionInfo = nil
    }

    /// Logical restore to an earlier turn position (the coordinator re-binds
    /// the surviving representation at that position; segments re-materialize
    /// on demand at the next forward).
    public func restoreSession(to position: Int) async throws {
        guard let coordinator, let state = currentState else {
            throw OversizedEngineError.notLoaded
        }
        currentState = try await coordinator.restore(
            state,
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(Int64(position)),
                continuation: ExecutionContinuation(
                    nextInput: "", continuationID: "S-restore-\(position)")
            )
        )
        sessionInfo = OversizedSessionInfo(
            executionID: currentState!.id.rawValue,
            position: Int(currentState!.position.value),
            turns: sessionTurnCount,
            records: coordinator.recordCount
        )
    }

    /// The oversized eviction: release every streamed layer's weights
    /// (persistent floor stays).
    public func releaseAllSegments() throws {
        guard let model else { throw OversizedEngineError.notLoaded }
        var placeholders: [String: MLXArray] = [:]
        for name in switchNames {
            if let layer = layerOf(name), layer >= residentLayers {
                placeholders[name] = MLXArray([Int](), [0])
            }
        }
        try model.update(parameters: ModuleParameters.unflattened(placeholders), verify: [])
        Memory.clearCache()
    }
}
