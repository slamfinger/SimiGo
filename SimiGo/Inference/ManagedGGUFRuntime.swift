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
    private struct State: @unchecked Sendable {
        var engine: ProcessRuntime?
        var server: HTTPServer?
        var client: GGUFEngineClient?
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
            let producer = InformationTurnProducer(
                modelIdentity: SimiGoProducerIdentity.canonicalModelIdentity(
                    fromPath: info.path),
                identity: SimiGoProducerIdentity.identity(fromPath: info.path))
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
                    generateHandler: { requestId, _, _, _, messages, tools, requestConfig, onChunk, onToolCall in
                        try await client.generate(
                            requestId: requestId,
                            messages: messages,
                            tools: tools,
                            config: requestConfig,
                            onChunk: onChunk,
                            onToolCall: onToolCall)
                    },
                    // The llama.cpp process holds no per-session KV snapshot;
                    // an honest refusal beats fabricated branch metadata.
                    forkBranchHandler: { _, _, _, _ in
                        throw RuntError.generationFailed("GGUF 后端不提供分支快照")
                    },
                    deleteBranchHandler: { _, _, _ in },
                    listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
                    checkHealthHandler: { [weak engine] in
                        await engine?.checkHealth() ?? false
                    },
                    cancelGenerationHandler: { requestId in
                        client.cancel(requestId: requestId)
                    },
                    baseConfigProvider: { baseConfig },
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
