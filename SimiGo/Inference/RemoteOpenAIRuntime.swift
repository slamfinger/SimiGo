import Foundation
import LOCALBCore
import SimiGoRuntimeContract
import Synchronization

public final class RemoteOpenAIRuntime: Runtime, @unchecked Sendable {
    private struct State {
        var httpServer: HTTPServer?
        var running = false
    }

    private let backend: RemoteOpenAIBackend

    public var isInProcess: Bool { false }
    public var isGenerating: Bool { false }
    private let state = Mutex(State())
    public var isRunning: Bool { state.withLock { $0.running } }

    public init(configuration: CloudBackendConfiguration, apiKey: String) {
        backend = RemoteOpenAIBackend(configuration: configuration, apiKey: apiKey)
    }

    public func start(_ info: ModelInfo, port: Int) async throws {
        try await startWithLOCALB(info, port: port, localbHostDirectory: nil)
    }

    /// Start with the default LOCALB host resolution: an activated host
    /// supplies transport identity AND request authorization from one
    /// verified context; before activation the listener stays
    /// transport-only and protected routes remain fail-closed (503). The
    /// store parameters default to the production Keychain services and
    /// exist for test/management-plane isolation only.
    public func startWithLOCALB(
        _ info: ModelInfo,
        port: Int,
        localbHostDirectory: URL?,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) async throws {
        try backend.configuration.validated(apiKey: backend.apiKey)

        let modelId = backend.configuration.model.isEmpty ? "cloud-openai" : backend.configuration.model
        // A cloud turn still settles into the local ES/IS; its producer identity
        // names the remote model instead of pretending to be a local snapshot.
        let remoteIdentity = InformationTurnProducer(
            modelIdentity: "remote:" + modelId,
            identity: SimiGoSettlementIdentityBinding.Identity(
                model: SimiGoProducerIdentity.canonicalFingerprint(
                    ["remote_model": modelId]),
                tokenizer: SimiGoProducerIdentity.canonicalFingerprint(
                    ["remote_provider": backend.configuration.baseURLString])))
        let server = HTTPServer(
            port: port,
            modelId: modelId,
            generateHandler: Self.unsupportedGenerate,
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(storageKey: "remote/cloud", modelId: modelId, savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { [weak self] in
                await self?.checkHealth() ?? false
            },
            remoteBackend: backend,
            informationTurnProducer: { remoteIdentity }
        )

        // LOCALB B1→B3: the remote-proxy listener reuses the SAME default
        // host resolution as every other listener site (this proxy binds
        // loopback by default — HTTPServer's default bindHost is
        // 127.0.0.1). It is not exempt from the security-mode matrix; an
        // operational LOCALB host yields secure TLS + request
        // authorization, otherwise secure-by-default transport policy with
        // fail-closed protected routes.
        try LOCALBHostRuntime.applyDefault(
            to: server,
            bindHost: "127.0.0.1",
            hostDirectory: localbHostDirectory,
            keychainStore: keychainStore,
            transportIdentityStore: transportIdentityStore
        )
        try await MainActor.run { try server.start() }
        state.withLock {
            $0.httpServer = server
            $0.running = true
        }
    }

    public func stop() async {
        let server = state.withLock { currentState -> HTTPServer? in
            let server = currentState.httpServer
            currentState.httpServer = nil
            currentState.running = false
            return server
        }

        await MainActor.run { server?.stop() }
    }

    public func checkHealth() async -> Bool {
        // Cloud reachability must not own SimiGo's local server lifecycle.
        // A slow or provider-specific failed /models call caused repeated
        // restarts while actual chat requests were still valid.
        isRunning
    }

    private static func unsupportedGenerate(
        requestId: String,
        agentId: String?,
        sessionId: String,
        logicalBranchId: String,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> GenerationResult {
        throw ServiceError.backendNotAvailable("云端 backend 应直接转发原始模型请求")
    }
}
