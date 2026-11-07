import Foundation
import LOCALBCore
import SimiGoRuntimeContract
import Synchronization

/// The ES/IS service host: an HTTP listener with no model, no upstream
/// provider, and no inference path.
///
/// It exists because the MCP settlement surface (`/mcp`) and the IS read
/// routes are consumers in their own right: an external agent that runs its
/// own model must be able to reach them without SimiGo loading MLX or
/// llama.cpp. It is deliberately NOT a provider proxy — every inference route
/// refuses with `backendNotAvailable`, and there is no upstream client to
/// reach. The listener resolves LOCALB through the same default path as every
/// other site, so protected routes stay fail-closed until the host is
/// activated.
public final class InformationSpaceRuntime: Runtime, @unchecked Sendable {
    private struct State {
        var httpServer: HTTPServer?
        var running = false
    }

    private let state = Mutex(State())

    public var isRunning: Bool { state.withLock { $0.running } }
    public var isGenerating: Bool { false }
    public var isInProcess: Bool { true }

    public init() {}

    /// `Runtime` conformance. The information-space host has no model, so the
    /// descriptor is not consulted; callers that already hold one may use it.
    public func start(_ info: ModelInfo, port: Int) async throws {
        try await start(port: port)
    }

    public func start(port: Int) async throws {
        try await startWithLOCALB(port: port, localbHostDirectory: nil)
    }

    /// Same default host resolution as the managed inference entries: an
    /// activated host supplies transport identity AND request authorization
    /// from one verified context; before activation the listener stays
    /// transport-only and protected routes remain fail-closed (503).
    public func startWithLOCALB(
        port: Int,
        localbHostDirectory: URL?,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) async throws {
        let node = await MainActor.run {
            InferenceNodeConfiguration.shared.snapshot()
        }
        let server = HTTPServer(
            port: port,
            modelId: "simigo-information-space",
            bindHost: node.bindHost,
            bonjourEnabled: node.bonjourEnabled,
            generateHandler: Self.unsupportedGenerate,
            forkBranchHandler: { _, _, _, _ in
                throw RuntError.generationFailed("信息空间服务宿主不提供模型分支")
            },
            deleteBranchHandler: { _, _, _, _ in
                throw RuntError.generationFailed("信息空间服务宿主不提供模型分支")
            },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { [weak self] in
                await self?.checkHealth() ?? false
            },
            cancelGenerationHandler: { _ in }
        )

        try LOCALBHostRuntime.applyDefault(
            to: server,
            bindHost: node.bindHost,
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
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        throw ServiceError.backendNotAvailable(
            "信息空间服务宿主不提供模型推理；请启动 MLX 或 llama.cpp 后再调用推理接口")
    }
}
