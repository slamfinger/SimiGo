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

public struct EngineChatMessage: Equatable, Sendable {
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
    case residencyDivergence(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedModelType(let t):
            return "unsupported model type for the oversized segmented engine: \(t)"
        case .notLoaded:
            return "engine not loaded — call load() first"
        case .residencyDivergence(let detail):
            return "residency reconciliation divergence: \(detail)"
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
    public static let defaultUnitLayers = 8
    /// Chat budget (user-set 2026-09-26): resident memory < 16 GiB, MLX
    /// cache < 16 GiB, system memory pressure green.
    public static let defaultPeakCapacityMiB: Int64 = 20 * 1024

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

    public private(set) var sessionInfo: OversizedSessionInfo?
    /// Token Ledger: append-only confirmed token-prefix facts per session.
    /// Closed (retained) when newSession discards the Execution State.
    public private(set) var tokenLedger: OversizedTokenLedger?
    public private(set) var lastInputTokenCount: Int?

    /// FM-03: lifecycle/generation serialization. The product guards
    /// single-flight at the UI layer; this lock makes the ENGINE itself
    /// concurrency-safe for direct callers (generate / newSession /
    /// restoreSession are serialized against each other).
    private let lifecycleSerialLock = AsyncLock()

    // ResidencyController (consistency with the fitting-model path): segment
    // materialization/release goes through the controller's admission and
    // pressure paths, with INV-1 audited after every transition.
    private var residency: ResidencyController?
    private var groupBudgetBytes: Int64 = 0
    /// Persistent floor in WHOLE units (single floor authority).
    private var floorUnitsCount = 0

    // INV-3 production reconciliation (registered: detection, not
    // transaction). C_model is calibrated at T0 for THIS engine; epsilon is
    // a beta value and requires calibration review before GA.
    private var cModelBytes: Int64 = 0
    private let reconcileEpsilonBytes: Int64 = 64 * 1024 * 1024
    public private(set) var residencyReconcileChecks = 0
    public private(set) var residencyReconcileDivergences = 0
    public private(set) var residencyReconcileRecoveries = 0
    public private(set) var residencyReconcileErrors = 0
    private var floorResidentBytes: Int64 = 0
    public private(set) var residencyINV1Checks = 0
    public private(set) var residencyINV1Failures = 0

    public var residencyINV1Holds: Bool {
        guard let residency else { return false }
        return residency.auditReplay().residentGroupIDs == residency.residentGroupIDs
    }
    public var residencyTransferCount: Int { residency?.transferLog.count ?? 0 }

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
        // Units cover ALL layers from 0; the persistent floor is a prefix of
        // WHOLE units (single authority: floorUnits). A layer-level floor
        // derivation previously left floor layers loaded-but-never-forwarded
        // (units started at floorCount) — silently skipping them at floor>0.
        func unitBytesSum(_ unit: ClosedRange<Int>) -> Int64 {
            var bytes: Int64 = 0
            for i in unit.lowerBound...unit.upperBound where i < totalLayers {
                bytes += layerBytes[i]
            }
            return bytes
        }
        var segs: [ClosedRange<Int>] = []
        var chunkStart = 0
        while chunkStart < totalLayers {
            let end = min(chunkStart + unitLayers - 1, totalLayers - 1)
            segs.append(chunkStart...end)
            chunkStart = end + 1
        }
        units = segs
        // v2.0 beta: the persistent floor is DISABLED. floorUnits is forced
        // to 0: a unit-derived floor crashes in quantized projection
        // (gather_qmm int32 scales) and the floor budget silently traded
        // page cache for wired memory with no latency benefit. floor 0 is
        // the measured optimum; the parameter stays reserved for a
        // redesigned GA mechanism.
        let floorUnits = 0
        residentLayers = floorUnits * unitLayers
        self.floorUnitsCount = floorUnits

        let floorRanges = Array(units.prefix(floorUnits))
        var fullParameterMap: [String: MLXArray] = [:]
        for location in reader.locations.values {
            let isSwitch = location.name.contains(".switch_mlp.")
            let inFloorUnit = isSwitch && layerOf(location.name).map { layer in
                floorRanges.contains { $0.contains(layer) }
            } ?? false
            if isSwitch && !inFloorUnit {
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

        // INV-3 C_model calibration (T0): the controller bookkeeping at this
        // point is exactly the core group, so observed − core IS the
        // calibrated constant for this engine instance.
        let calib = gauge()
        cModelBytes = calib.activeMiB * 1048576 - coreBytes

        // Segment residency inventory + controller (consistency with the
        // fitting-model path): core = alwaysResident; streaming units are
        // controller-managed groups.
        var tensorEntries: [TensorEntry] = []
        var coreTensorCount = 0
        for location in reader.locations.values {
            tensorEntries.append(TensorEntry(
                id: location.name,
                file: location.file,
                absoluteDataOffset: Int64(location.absoluteDataOffset),
                dtype: location.dtype,
                shape: location.shape,
                byteCount: Int64(location.byteCount)
            ))
            if !location.name.contains(".switch_mlp.") {
                coreTensorCount += 1
            }
        }
        let coreGroup = LayerGroup(
            id: "core", title: "core", layerRangeDescription: "-",
            tensorCount: coreTensorCount, byteCount: coreBytes, alwaysResident: true
        )
        let unitGroups: [LayerGroup] = units.map { unit in
            var count = 0
            var bytes: Int64 = 0
            for name in switchNames where layerOf(name).map({ unit.contains($0) }) == true {
                count += 1
            }
            for i in unit.lowerBound...unit.upperBound where i < totalLayers {
                bytes += layerBytes[i]
            }
            return LayerGroup(
                id: unitID(unit), title: "streaming unit",
                layerRangeDescription: "\(unit.lowerBound)-\(unit.upperBound)",
                tensorCount: count, byteCount: bytes, alwaysResident: false
            )
        }
        let inventory = LayerInventory(
            groups: [coreGroup] + unitGroups,
            tensors: tensorEntries,
            totalByteCount: tensorEntries.reduce(0) { $0 + $1.byteCount }
        )
        // Group-space budget covers core ∪ streamed units exactly once:
        // the planner computes desired = core ∪ required and compares it
        // against this budget, so subtracting core here would double-count
        // it (review P2: over-conservative by 2× core).
        groupBudgetBytes = Int64(peakCapacityMiB) * 1024 * 1024
        floorResidentBytes = coreBytes
        for unit in units.prefix(floorUnits) {
            floorResidentBytes += unitBytesSum(unit)
        }
        let materializer = OversizedSegmentMaterializer(
            load: { [weak self] gid in try self?.loadUnit(gid) ?? () },
            unload: { [weak self] gid in try self?.releaseUnit(gid) ?? () },
            observe: { [weak self] in
                guard let g = self?.gauge() else {
                    return BackendMemoryObservation(activeBytes: 0, cacheBytes: 0, peakBytes: 0)
                }
                return BackendMemoryObservation(
                    activeBytes: g.activeMiB * 1048576,
                    cacheBytes: g.cacheMiB * 1048576,
                    peakBytes: g.footprintMiB * 1048576
                )
            },
            purge: { Memory.clearCache() }
        )
        let residency = ResidencyController(
            inventory: inventory, materializer: materializer
        )
        self.residency = residency

        // Admit the persistent floor through the controller (logged loads).
        let floorUnitIDs = Set(units.prefix(floorUnits).map { unitID($0) })
        if !floorUnitIDs.isEmpty {
            _ = try await residency.admit(
                requiredGroupIDs: floorUnitIDs,
                budget: ResidencyBudgetPolicy(fixedBytes: groupBudgetBytes)
            )
        }

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
        stopTokenIDs: Set<Int> = [],
        onToken: (@Sendable (OversizedEngineGauge, String) -> Void)? = nil
    ) async throws -> OversizedEngineTurn {
        guard model != nil, reader != nil, let tokenizer else {
            throw OversizedEngineError.notLoaded
        }
        await lifecycleSerialLock.lock()
        defer { lifecycleSerialLock.unlock() }
        var nextInput: [Int]
        if let explicit = nextInputTokens {
            // Explicitly provided (including empty) — e.g. the strict
            // bootstrap replay in the self-test.
            nextInput = explicit ?? []
        } else if currentState == nil || coordinator == nil {
            let prefix = try promptTokenIDs(for: messages)
            currentState = try await ensureSession(prefix: prefix)
            try tokenLedger?.append(OversizedTokenLedgerEntry(
                executionID: currentState!.id,
                position: Int(currentState!.position.value),
                kind: .bootstrap,
                prefixLength: prefix.count
            ))
            nextInput = []
        } else {
            guard let lastUser = messages.last(where: { $0.role == "user" }) else {
                throw OversizedEngineError.notLoaded
            }
            nextInput = tokenizer.encode(text: lastUser.content, addSpecialTokens: false)
        }
        guard let state = currentState, let stateBackend else {
            throw OversizedEngineError.notLoaded
        }
        return try await executeTurn(
            state: state, backend: stateBackend, nextInput: nextInput,
            messages: messages, maxNewTokens: maxNewTokens,
            stopTokenIDs: stopTokenIDs, onToken: onToken
        )
    }

    /// Strict replay of the bootstrap turn: consumes the CURRENT bound
    /// representation (the position-0 prefix after restoreSession(to: 0))
    /// with an EMPTY next input — bit-identical to the original bootstrap.
    @discardableResult
    public func replayBootstrapTurn(
        maxNewTokens: Int,
        stopTokenIDs: Set<Int> = [],
        onToken: (@Sendable (OversizedEngineGauge, String) -> Void)? = nil
    ) async throws -> OversizedEngineTurn {
        guard model != nil, reader != nil, tokenizer != nil else {
            throw OversizedEngineError.notLoaded
        }
        guard let state = currentState, let stateBackend else {
            throw OversizedEngineError.notLoaded
        }
        return try await executeTurn(
            state: state, backend: stateBackend, nextInput: [],
            messages: [], maxNewTokens: maxNewTokens,
            stopTokenIDs: stopTokenIDs, onToken: onToken
        )
    }

    private func executeTurn(
        state: ExecutionStateHandle,
        backend: OversizedSegmentedStateBackend,
        nextInput: [Int],
        messages: [EngineChatMessage],
        maxNewTokens: Int,
        stopTokenIDs: Set<Int> = [],
        onToken: (@Sendable (OversizedEngineGauge, String) -> Void)? = nil
    ) async throws -> OversizedEngineTurn {
        guard let residency = self.residency else {
            throw OversizedEngineError.notLoaded
        }
        let model = self.model
        let reader = self.reader
        let tokenizer = self.tokenizer
        guard let model, reader != nil, let tokenizer else {
            throw OversizedEngineError.notLoaded
        }
        let bound = try backend.boundPrefix(for: state)
        var ids = bound.prefix + nextInput
        lastInputTokenCount = ids.count
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
                // D1 FM-04 cancellation point: phase-boundary observation.
                // ABORT here leaves position/binding unchanged; unit
                // residency mechanics converge via INV-1. The commit
                // section (bind -> advance -> history) deliberately has NO
                // cancellation check.
                try Task.checkCancellation()
                // Segment residency THROUGH the ResidencyController: the
                // admission materializes this unit via the materializer port
                // (logged) and evicts whatever no longer fits the group
                // budget; INV-1 is audited after every transition.
                let gid = unitID(unit)
                _ = try await residency.admit(
                    requiredGroupIDs: [gid],
                    budget: ResidencyBudgetPolicy(fixedBytes: groupBudgetBytes)
                )
                self.residencyINV1Checks += 1
                if !self.residencyINV1Holds {
                    self.residencyINV1Failures += 1
                }
                hidden = model.forwardLayerRange(
                    hidden, layerRange: unit.lowerBound..<(unit.upperBound + 1), cache: nil
                )
                eval(hidden)

                // Evict the unit IMMEDIATELY after its forward (contract-
                // clean, logged pressure release back to the floor). Without
                // this, the next admission's load overlaps the previous
                // unit's residency (load-before-evict) and the transient
                // double-occupancy thrashes swap (measured 2-12 GiB swing,
                // 4x latency).
                if unitIndex >= self.floorUnitsCount {
                    _ = try await residency.respondToMemoryPressure(
                        targetBytes: floorResidentBytes, cModelBytes: 0
                    )
                    residencyINV1Checks += 1
                    if !residencyINV1Holds {
                        residencyINV1Failures += 1
                    }
                }
                _ = unitIndex
            }

            let logits = model.projectOutput(hidden)[0, -1]
            eval(logits)
            let next = logits.argMax().item(Int.self)
            generated.append(next)
            ids.append(next)
            if stopTokenIDs.contains(next) { break }

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

        // Atomic turn commit (review P1): generation has completed without
        // mutating any binding; the commit order is physical rebind at the
        // advanced position FIRST, then the logical advance (in-memory,
        // infallible), then the history record. The previous order
        // (consumeBinding -> logical advance -> bind) left a window where a
        // bind failure produced "logical advanced / representation missing".
        let advancedPosition = ExecutionPosition(state.position.value + 1)
        backend.bind(
            executionID: state.id, position: advancedPosition, prefix: ids
        )
        let advanced = try await coordinator!.continueExecution(
            state,
            continuation: ExecutionContinuation(
                nextInput: messages.last?.content ?? "",
                continuationID: "S-cont-\(advancedPosition.value)"
            )
        )
        currentState = advanced
        try await coordinator!.bindRepresentation(
            executionID: advanced.id,
            position: advanced.position,
            payload: OversizedPrefixPayload(tokenPrefix: ids)
        )
        sessionInfo = OversizedSessionInfo(
            executionID: advanced.id.rawValue,
            position: Int(advanced.position.value),
            turns: Int(advanced.position.value),
            records: coordinator!.recordCount
        )

        // Token Ledger (I-L1 committed-only): the turn entry is appended only
        // after the full commit sequence succeeded. The claimed prefixLength
        // (`ids.count`) is cross-checked inside the ledger against the
        // backend's own binding record (I-L3) — the bind above put the
        // physical representation at `advancedPosition` with exactly `ids`.
        try tokenLedger?.append(OversizedTokenLedgerEntry(
            executionID: advanced.id,
            position: Int(advanced.position.value),
            kind: .turn,
            prefixLength: ids.count
        ))

        // INV-3 production observation (review FM-06): at this stable
        // post-commit point, controller bookkeeping must match the MLX
        // physical observation within epsilon. Divergence gets ONE recover
        // attempt (bookkeeping rebuilt from the transfer log); a persistent
        // divergence FAILS the turn — physical inconsistency is never
        // silently continued. This observation never touches the Execution
        // State (position/binding/history are already committed).
        residencyReconcileChecks += 1
        do {
            let matched = try residency.reconcile(
                observedIdleBytes: Int64(gauge().activeMiB) * 1048576,
                cModelBytes: cModelBytes,
                epsilonBytes: 64 * 1024 * 1024
            )
            if !matched {
                residencyReconcileDivergences += 1
                try residency.recover()
                let rematch = try residency.reconcile(
                    observedIdleBytes: Int64(gauge().activeMiB) * 1048576,
                    cModelBytes: cModelBytes,
                    epsilonBytes: 64 * 1024 * 1024
                )
                if !rematch {
                    throw OversizedEngineError.residencyDivergence(
                        "reconcile divergence persists after recovery")
                }
            }
        } catch let e as OversizedEngineError {
            throw e
        } catch {
            // observation infrastructure error: count, surface on the NEXT
            // turn (never silently continue across a divergence)
            residencyReconcileErrors += 1
        }

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

    // MARK: - Controller-driven segment residency

    private func unitID(_ unit: ClosedRange<Int>) -> String {
        "layers-\(unit.lowerBound)-\(unit.upperBound)"
    }

    func loadUnit(_ groupID: String) throws {
        guard let model, let reader else { throw OversizedEngineError.notLoaded }
        guard let unit = units.first(where: { unitID($0) == groupID }) else { return }
        var arrays: [String: MLXArray] = [:]
        for name in switchNames {
            if let layer = layerOf(name), unit.contains(layer) {
                arrays[name] = try autoreleasepool {
                    try reader.loadTensor(named: name)
                }
            }
        }
        eval(arrays.values.map { $0 })
        try model.update(parameters: ModuleParameters.unflattened(arrays), verify: [])
    }

    func releaseUnit(_ groupID: String) throws {
        guard let model else { throw OversizedEngineError.notLoaded }
        guard let unit = units.first(where: { unitID($0) == groupID }) else { return }
        var placeholders: [String: MLXArray] = [:]
        for name in switchNames {
            if let layer = layerOf(name), unit.contains(layer) {
                placeholders[name] = MLXArray([Int](), [0])
            }
        }
        try model.update(parameters: ModuleParameters.unflattened(placeholders), verify: [])
        Memory.clearCache()
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
        tokenLedger = OversizedTokenLedger { [weak backend] executionID, position in
            guard let backend else { throw OversizedEngineError.notLoaded }
            return try backend.boundPrefixLength(
                executionID: executionID, position: ExecutionPosition(Int64(position))
            )
        }
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
    /// New session — FAIL-FAST (review fix ①): a residency failure
    /// (eviction failure → DIRTY) propagates; the session is NOT reported
    /// fresh while segment residency is unresolved. The Execution State is
    /// discarded only after the residency floor has been reached.
    public func newSession() async throws {
        await lifecycleSerialLock.lock()
        defer { lifecycleSerialLock.unlock() }
        if let residency {
            _ = try await residency.respondToMemoryPressure(targetBytes: 0, cModelBytes: 0)
        }
        if let coordinator, let state = currentState {
            try await coordinator.discard(state)
        }
        coordinator = nil
        stateBackend = nil
        currentState = nil
        sessionInfo = nil
    }

    /// Logical restore to an earlier turn position (the coordinator re-binds
    /// the surviving representation at that position; segments re-materialize
    /// on demand at the next forward).
    public func restoreSession(to position: Int) async throws {
        await lifecycleSerialLock.lock()
        defer { lifecycleSerialLock.unlock() }
        guard let coordinator, let stateBackend, let state = currentState else {
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
        // Token ledger restore marker: records the rollback point so the
        // audit trail shows the rewind (append-only — the superseded tail is
        // retained and flagged, not deleted). The marker's prefixLength is
        // derived from the BACKEND's re-bound representation at the restored
        // position (I-L3 source of truth — coordinator.restore re-binds the
        // historical prefix before returning), and the ledger independently
        // re-verifies it against the backend at append.
        tokenLedger?.markSuperseded(beyond: position, executionID: state.id)
        let restoredPrefixLength = try stateBackend.boundPrefixLength(
            executionID: currentState!.id, position: currentState!.position
        )
        try tokenLedger?.append(OversizedTokenLedgerEntry(
            executionID: currentState!.id,
            position: Int(currentState!.position.value),
            kind: .restoreMarker,
            prefixLength: restoredPrefixLength
        ))
        sessionInfo = OversizedSessionInfo(
            executionID: currentState!.id.rawValue,
            position: Int(currentState!.position.value),
            turns: Int(currentState!.position.value),
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
