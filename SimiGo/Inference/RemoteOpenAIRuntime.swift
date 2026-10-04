import Foundation
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
        try backend.configuration.validated(apiKey: backend.apiKey)

        let modelId = backend.configuration.model.isEmpty ? "cloud-openai" : backend.configuration.model
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
            remoteBackend: backend
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
