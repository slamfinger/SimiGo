import Foundation
import SimiGoRuntimeContract
import Synchronization

/// llama.cpp as a managed backend.
///
/// The engine runs as a child process on a loopback-only internal port; the
/// client-facing listener is the product `HTTPServer`. Every GGUF turn
/// therefore passes the same ES/IS, answer-reuse and admission path as an
/// in-process MLX turn instead of reaching the engine directly.
final class ManagedGGUFRuntime: Runtime, @unchecked Sendable {
    /// MONITOR ONLY (Issue #15 R2-B, owner ruling 2026-11-08): classifies
    /// /slots samples into structured progress states — progressing /
    /// observing_no_progress / candidate_stall / baseline_reset / unobservable
    /// / phase_transition_or_unknown. It never restarts, never terminates a
    /// task and never touches the busy-protection policy; a candidate stall
    /// is labelled evidence only, and the window is a label threshold
    /// (default 30s, deliberately wider than R1's observed normal maximum of
    /// 4.04s), not a production restart threshold.
    let progressMonitor = SlotProgressMonitor.productionDefault()

    private struct State: @unchecked Sendable {
        var engine: ProcessRuntime?
        var server: HTTPServer?
        var client: GGUFEngineClient?
        var enginePort: Int?
        var running = false
    }

    private let config: ModelConfig
    private let backendConfig: BackendConfig
    private let state = Mutex(State())

    var isRunning: Bool { state.withLock { $0.running } }
    var isGenerating: Bool {
        state.withLock { $0.client?.activeRequestCount ?? 0 > 0 }
    }
    var isInProcess: Bool { false }
    /// The loopback port the engine was started on, kept only so slot probes
    /// can reach the engine directly instead of the product listener.
    var enginePort: Int? { state.withLock { $0.enginePort } }

    init(config: ModelConfig, backendConfig: BackendConfig) {
        self.config = config
        self.backendConfig = backendConfig
    }

    func start(_ info: ModelInfo, port: Int) async throws {
        guard let enginePort = Self.freeLoopbackPort() else {
            throw ServiceError.backendNotAvailable("无法为 llama.cpp 分配内部端口")
        }
        let slots = Self.engineSlots()
        let launchArgs = Self.pinningLoopbackHost(
            backendConfig.args(info, config, enginePort))
        let engine = ProcessRuntime(config: backendConfig, launchArgs: launchArgs)
        let alias = modelName(from: info.path)

        Service.log(
            "🧩 llama.cpp 受管入口: public=\(port) engine=127.0.0.1:\(enginePort) parallel=\(slots)")

        try await engine.start(info, port: enginePort)

        do {
            let client = GGUFEngineClient(
                endpoint: .init(
                    baseURL: URL(string: "http://127.0.0.1:\(enginePort)")!,
                    model: alias))
            // The checkpoint's content digest now decides the producer identity
            // for the whole session, and every later admission, settlement and
            // consumption resolves the same value. Resolve it here, off the
            // cooperative pool: hashing is once per file stamp, but "once" is a
            // multi-GB read and must not happen inside a request.
            // One resolution, two renderings: see `ProducerIdentity.identities`.
            let seeds = await Task.detached(priority: .userInitiated) {
                ProducerIdentity.identities(fromPath: info.path)
            }.value
            let producer = InformationTurnProducer(
                modelIdentity: seeds.model, identity: seeds.producer)
            let node = await MainActor.run {
                InferenceNodeConfiguration.shared.snapshot()
            }
            let admissionLimit = max(RuntimeTuning.requestConcurrencyLevel, slots)
            let baseConfig = config

            let server = await MainActor.run {
                HTTPServer(
                    port: port,
                    modelId: alias,
                    bindHost: node.bindHost,
                    bonjourEnabled: node.bonjourEnabled,
                    generateHandler: { requestId, _, _, _, messages, tools, requestConfig, onChunk, onToolCall, onReasoning in
                        // P0-3 对齐（2026-11-06）：GGUF 此前从不置 RUNNING，
                        // 于是每个跑满引擎的成功请求都以 `finish(from: QUEUED)`
                        // 收尾（2026-10-30 实测 FORCE_RELEASED 32 次），
                        // 在途标记缺失、真实占用与 LC 状态不一致。
                        // MLX 在拿到 generation gate 后置位；GGUF 在这里拿到的是
                        // 已 admission 的同一窗口，语义相同。转换失败不影响生成：
                        // 已被取消的请求由 client.cancel 收口，重复调用则忽略。
                        try? await RuntimeLifecycleCoordinator.shared.transition(
                            requestID: requestId,
                            to: .running)
                        return try await client.generate(
                            requestId: requestId,
                            messages: messages,
                            tools: tools,
                            config: requestConfig,
                            onChunk: onChunk,
                            onToolCall: onToolCall,
                            onReasoning: onReasoning)
                    },
                    // The llama.cpp process holds no per-session KV snapshot;
                    // an honest refusal beats fabricated branch metadata.
                    forkBranchHandler: { _, _, _, _ in
                        throw RuntError.generationFailed("GGUF 后端不提供分支快照")
                    },
                    deleteBranchHandler: { _, _, _, _ in
                        throw RuntError.generationFailed("GGUF 后端不提供分支快照")
                    },
                    listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
                    checkHealthHandler: { [weak engine] in
                        await engine?.checkHealth() ?? false
                    },
                    cancelGenerationHandler: { requestId in
                        client.cancel(requestId: requestId)
                    },
                    baseConfigProvider: { baseConfig },
                    // Continuation over llama.cpp: the prefix cells live inside
                    // llama-server, so this runtime exports no prefix
                    // representation and the settlement records no KV claim. The
                    // settlement itself is the same authority as on MLX — the
                    // value, payload digest, validity and dependency closure are
                    // verified identically; only the carrier-specific KV lookup
                    // is nil. That is why a continuation can be resumed here by
                    // injecting the recovered value, and why it cannot inherit
                    // KV state produced by another engine.
                    continuationAdmission: { esStateID in
                        let modelPath = info.path
                        let admitted = try await MainActor.run {
                            try ProducerIdentity.recoverForContinuation(
                                stateID: esStateID, modelPath: modelPath)
                        }
                        return ContinuationAdmissionOutcome(
                            esStateID: esStateID,
                            recoveredValue: admitted.recoveredValue,
                            verifiedBindings: admitted.verifiedBindings,
                            kvBindings: admitted.kvBindings)
                    },
                    continuationSettlement: makeContinuationSettlementHandler(
                        modelPath: info.path) { _ in nil },
                    // llama-server keeps the prefix cells internally and this
                    // runtime exports no representation, so it declares that
                    // instead of letting a client discover it by a failed call.
                    // Settlement consumption is nil here and therefore
                    // unsupported from the wiring; managed continuation is
                    // wired above on the value-injection path and never reuses
                    // this engine's KV.
                    kvRepresentationAvailable: .unsupported,
                    informationTurnProducer: { producer },
                    requestAdmission: RequestAdmissionScheduler(limit: admissionLimit)
                )
            }
            try LOCALBHostRuntime.applyDefault(
                to: server,
                bindHost: node.bindHost,
                hostDirectory: nil)
            try await MainActor.run { try server.start() }

            state.withLock {
                $0.engine = engine
                $0.server = server
                $0.client = client
                $0.enginePort = enginePort
                $0.running = true
            }
        } catch {
            await engine.stop()
            throw error
        }
    }

    func stop() async {
        let (server, client, engine) = state.withLock {
            current -> (HTTPServer?, GGUFEngineClient?, ProcessRuntime?) in
            let snapshot = (current.server, current.client, current.engine)
            current.server = nil
            current.client = nil
            current.engine = nil
            current.enginePort = nil
            current.running = false
            return snapshot
        }
        client?.cancelAll()
        if let server {
            await MainActor.run { server.stop() }
        }
        await engine?.stop()
    }

    func checkHealth() async -> Bool {
        let engine = state.withLock { $0.engine }
        guard let engine else { return false }
        return await engine.checkHealth()
    }

    private static func engineSlots() -> Int {
        let raw = ProcessInfo.processInfo.environment["SIMIGO_LLAMA_PARALLEL"] ?? "1"
        return max(1, min(4, Int(raw) ?? 1))
    }

    /// The launch args builder derives `--host` from the *public* node config,
    /// which may be 0.0.0.0 in LAN mode. The engine is now an internal detail
    /// behind the product listener and has no auth of its own, so it must never
    /// listen beyond loopback.
    static func pinningLoopbackHost(_ args: [String]) -> [String] {
        var args = args
        if let index = args.firstIndex(of: "--host"), index + 1 < args.count {
            args[index + 1] = "127.0.0.1"
        }
        return args
    }

    /// A port the kernel confirms is bindable on loopback. The engine binds it
    /// a moment later, so this is a reservation by convention, not a lock.
    private static func freeLoopbackPort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }
}
