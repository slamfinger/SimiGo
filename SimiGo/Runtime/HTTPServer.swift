import Foundation
import CryptoKit
import Network

/// SimiGo 本机 / 局域网共享 OpenAI-compatible HTTP Server
///
/// 设计边界：
/// - 负责 HTTP/TCP、OpenAI JSON、SSE、连接生命周期、Responses 状态链与请求取消。
/// - 不负责 generation queue / KV cache / prefix cache / tool execution。
/// - NativeMLX.generate(...) 是唯一推理入口。
/// - 同一 Session 的并发一致性由 NativeMLX.SessionGenerationGate 负责。
///
/// Session / KV 分层原则：
///
/// 1. HTTPServer 只负责确定“这个请求属于哪个逻辑 Session”。
/// 2. HTTPServer 不根据 messages 猜测 Session。
/// 3. HTTPServer 不为了 KV reuse 主动压缩不同请求的 SessionId。
/// 4. Physical KV 是否复用，由 NativeMLX / KV Runtime 根据真实 token prefix、
///    tool fingerprint、runtime lineage 等条件决定。
///
/// OpenAI Chat / Completions：
///
///     explicit session
///             ↓
///     preserve client identity
///             ↓
///     no explicit session
///             ↓
///     request-scoped session
///
/// 不再存在：
///
///     messages
///        ↓
///     deriveStableSessionId()
///        ↓
///     强行合并 Session
///
/// Responses：
///
/// previous_response_id
///         ↓
/// StoredResponse
///         ↓
/// parent.agentId / parent.sessionId / parent.logicalBranchId
///         ↓
/// canonicalMessages
///         ↓
/// NativeMLX.generate(...)
///         ↓
/// StoredResponse(newResponseId)
///
/// StoredResponse 只保存协议层逻辑历史，不保存 Physical KV。
/// Physical KV 是否复用由 NativeMLX 自己依据真实 token prefix /
/// tool fingerprint / runtime lineage 决定。
public final class HTTPServer: @unchecked Sendable {

    // MARK: - Public Types

    public typealias GenerateHandler = @Sendable (
        _ requestId: String,
        _ agentId: String?,
        _ sessionId: String,
        _ logicalBranchId: String,
        _ messages: [JSONValue],
        _ tools: [JSONValue]?,
        _ config: ModelConfig,
        _ onChunk: @escaping @Sendable (String) -> Void,
        _ onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> String

    public typealias CheckHealthHandler = @Sendable () async -> Bool

    public typealias CancelGenerationHandler = @Sendable (_ requestId: String) -> Void

    // MARK: - Limits

    private static let maxHeaderBytes = 64 * 1024
    private static let maxHeaderLineBytes = 8 * 1024
    private static let maxHeaderCount = 128
    private static let maxBodyBytes = 16 * 1024 * 1024
    private static let receiveChunkSize = 32 * 1024

    // MARK: - HTTP Errors

    private enum HTTPServerError: Error {
        case badRequest(String)
        case payloadTooLarge
        case unsupportedTransferEncoding(String)
        case expectationFailed
        case clientDisconnected

        var statusCode: Int {
            switch self {
            case .badRequest, .clientDisconnected:
                return 400
            case .payloadTooLarge:
                return 413
            case .unsupportedTransferEncoding:
                return 501
            case .expectationFailed:
                return 417
            }
        }

        var message: String {
            switch self {
            case .badRequest(let message):
                return message
            case .payloadTooLarge:
                return "Request body too large"
            case .unsupportedTransferEncoding(let value):
                return "Unsupported Transfer-Encoding: \(value)"
            case .expectationFailed:
                return "Unsupported Expect header"
            case .clientDisconnected:
                return "Client disconnected before the request was complete"
            }
        }
    }

    // MARK: - Connection Context

    final class ConnectionContext: @unchecked Sendable {
        let connection: NWConnection
        let key: ObjectIdentifier
        let requestId: String
        let sendQueue: DispatchQueue

        private let stateLock = NSLock()

        private var _requestTask: Task<Void, Never>?
        private var _clientRequestId: String?
        private var _agentId: String?
        private var _sessionId: String?
        private var _logicalBranchId: String?

        private var _generationStarted = false
        private var _cancellationSignalled = false
        private var _closed = false

        init(connection: NWConnection) {
            self.connection = connection
            self.key = ObjectIdentifier(connection)
            self.requestId = "req-\(UUID().uuidString.lowercased())"
            self.sendQueue = DispatchQueue(
                label: "com.simigo.httpserver.send.\(UUID().uuidString)",
                qos: .userInitiated
            )
        }

        var closed: Bool {
            stateLock.withLock {
                _closed
            }
        }

        var agentId: String? {
            stateLock.withLock {
                _agentId
            }
        }

        var sessionId: String? {
            stateLock.withLock {
                _sessionId
            }
        }

        var logicalBranchId: String? {
            stateLock.withLock {
                _logicalBranchId
            }
        }

        var clientRequestId: String? {
            stateLock.withLock {
                _clientRequestId
            }
        }

        func setIdentity(
            agentId: String?,
            sessionId: String?,
            logicalBranchId: String? = nil,
            clientRequestId: String? = nil
        ) {
            stateLock.withLock {
                _agentId = agentId
                _sessionId = sessionId
                _logicalBranchId = logicalBranchId
                _clientRequestId = clientRequestId
            }
        }

        @discardableResult
        func markGenerationStarted() -> Bool {
            stateLock.withLock {
                guard !_closed else {
                    return false
                }

                _generationStarted = true
                return true
            }
        }

        func markGenerationFinished() {
            stateLock.withLock {
                _generationStarted = false
            }
        }

        func registerLifecycle() async {
            await RuntimeLifecycleCoordinator.shared.register(
                requestID: requestId,
                agentID: agentId,
                sessionID: sessionId
            )
        }

        func transitionToRunning() async throws {
            try await RuntimeLifecycleCoordinator.shared.transition(requestID: requestId, to: .running)
        }

        func transitionToQueued() async throws {
            try await RuntimeLifecycleCoordinator.shared.transition(requestID: requestId, to: .queued)
        }

        /// 统一终止入口：defer 中无法 await，以独立 Task 汇入协调器（幂等）。
        func finishLifecycle(success: Bool) {
            Task {
                await RuntimeLifecycleCoordinator.shared.finish(
                    requestID: requestId,
                    success: success,
                    reason: success ? "completed" : "cancelled_or_failed"
                )
            }
        }

        @discardableResult
        func setRequestTask(_ task: Task<Void, Never>) -> Bool {
            stateLock.withLock {
                guard !_closed else {
                    return false
                }

                _requestTask = task
                return true
            }
        }

        func closeAndTakeRequestTask(
            cancelGeneration: Bool
        ) -> (
            shouldCancelGeneration: Bool,
            requestTask: Task<Void, Never>?
        ) {
            stateLock.withLock {
                let shouldCancel =
                    cancelGeneration &&
                    _generationStarted &&
                    !_cancellationSignalled

                if shouldCancel {
                    _cancellationSignalled = true
                }

                _closed = true

                let task = _requestTask
                _requestTask = nil

                return (
                    shouldCancel,
                    task
                )
            }
        }

        @discardableResult
        func markClosed() -> Bool {
            stateLock.withLock {
                let wasOpen = !_closed

                _closed = true
                _requestTask = nil

                return wasOpen
            }
        }

        func canSend() -> Bool {
            stateLock.withLock {
                !_closed
            }
        }
    }

    // MARK: - HTTP Request

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    // MARK: - Server State

    private let port: NWEndpoint.Port
    let modelId: String
    private let bindHost: String
    private let bonjourEnabled: Bool

    let generateHandler: GenerateHandler
    private let checkHealthHandler: CheckHealthHandler
    private let cancelGenerationHandler: CancelGenerationHandler?

    private let queue = DispatchQueue(
        label: "com.simigo.httpserver.connections",
        qos: .userInitiated
    )

    private var listener: NWListener?

    private var connections: [ObjectIdentifier: ConnectionContext] = [:]
    private let connectionLock = NSLock()

    let responsesStore = ResponsesStateStore()

    // MARK: - Init

    public init(
        port: Int,
        modelId: String,
        bindHost: String = "127.0.0.1",
        bonjourEnabled: Bool = true,
        generateHandler: @escaping GenerateHandler,
        checkHealthHandler: @escaping CheckHealthHandler,
        cancelGenerationHandler: CancelGenerationHandler? = nil
    ) {
        guard let endpointPort = NWEndpoint.Port(
            rawValue: UInt16(port)
        ) else {
            fatalError("Invalid HTTP server port: \(port)")
        }

        self.port = endpointPort
        self.modelId = modelId

        let normalizedHost =
            bindHost.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        self.bindHost =
            normalizedHost.isEmpty
            ? "127.0.0.1"
            : normalizedHost

        self.bonjourEnabled = bonjourEnabled
        self.generateHandler = generateHandler
        self.checkHealthHandler = checkHealthHandler
        self.cancelGenerationHandler = cancelGenerationHandler
    }

    // MARK: - Lifecycle

    public func start() throws {
        guard listener == nil else {
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true

        let parameters = NWParameters(
            tls: nil,
            tcp: tcpOptions
        )

        parameters.allowLocalEndpointReuse = true

        let normalizedHost =
            bindHost
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

        let isLoopback =
            normalizedHost == "127.0.0.1" ||
            normalizedHost == "localhost" ||
            normalizedHost == "::1"

        if isLoopback {
            parameters.requiredInterfaceType = .loopback
        }

        let newListener = try NWListener(
            using: parameters,
            on: port
        )

        if !isLoopback && bonjourEnabled {
            newListener.service = NWListener.Service(
                name: "SimiGo",
                type: "_http._tcp",
                domain: nil,
                txtRecord: nil
            )
        }

        newListener.newConnectionHandler = {
            [weak self] connection in
            self?.accept(connection)
        }

        newListener.stateUpdateHandler = {
            [weak self] state in

            guard let self else {
                return
            }

            switch state {
            case .ready:
                print(
                    "✅ [HTTPServer] 监听 " +
                    "\(self.bindHost):\(self.port.rawValue) " +
                    "model=\(self.modelId)"
                )

            case .failed(let error):
                print(
                    "❌ [HTTPServer] listener failed: " +
                    "\(error.localizedDescription)"
                )

            case .cancelled:
                print("🛑 [HTTPServer] listener stopped")

            default:
                break
            }
        }

        newListener.start(queue: queue)
        listener = newListener
    }

    public func stop() {
        listener?.cancel()
        listener = nil

        let contexts: [ConnectionContext] = connectionLock.withLock {
            let values = Array(connections.values)
            connections.removeAll()
            return values
        }

        for context in contexts {
            terminate(
                context,
                cancelGeneration: true
            )
        }

        responsesStore.clear()
    }

    // MARK: - Connection Lifecycle

    private func accept(_ connection: NWConnection) {
        let context = ConnectionContext(
            connection: connection
        )

        connectionLock.withLock {
            connections[context.key] = context
        }

        connection.stateUpdateHandler = {
            [weak self, weak context] state in

            guard let self, let context else {
                return
            }

            switch state {
            case .failed, .cancelled:
                self.terminate(
                    context,
                    cancelGeneration: true
                )

            default:
                break
            }
        }

        connection.start(queue: queue)

        let task = Task {
            [weak self, weak context] in

            guard let self, let context else {
                return
            }

            do {
                guard !context.closed else {
                    return
                }

                let request =
                    try await self.readRequest(
                        from: connection
                    )

                guard !context.closed else {
                    return
                }

                try await self.route(
                    request,
                    context: context
                )

            } catch is CancellationError {
                // terminate() owns cancellation.

            } catch {
                guard !context.closed else {
                    return
                }

                let serverError =
                    error as? HTTPServerError

                let status =
                    serverError?.statusCode ?? 400

                let message =
                    serverError?.message ??
                    error.localizedDescription

                self.sendError(
                    message,
                    status: status,
                    on: connection,
                    context: context
                )
            }
        }

        if !context.setRequestTask(task) {
            task.cancel()
        }
    }

    func finish(_ context: ConnectionContext) {
        context.markClosed()

        connectionLock.withLock {
            guard connections[context.key] === context else {
                return
            }

            connections.removeValue(
                forKey: context.key
            )
        }
    }

    func terminate(
        _ context: ConnectionContext,
        cancelGeneration: Bool
    ) {
        let result =
            context.closeAndTakeRequestTask(
                cancelGeneration: cancelGeneration
            )

        connectionLock.withLock {
            if connections[context.key] === context {
                connections.removeValue(
                    forKey: context.key
                )
            }
        }

        result.requestTask?.cancel()

        if result.shouldCancelGeneration {
            cancelGenerationHandler?(
                context.requestId
            )
        }

        context.connection.cancel()
    }

    // MARK: - Routing

    private func route(
        _ request: HTTPRequest,
        context: ConnectionContext
    ) async throws {
        switch (request.method, request.path) {

        case ("OPTIONS", _):
            _ = sendResponse(
                status: 204,
                headers: corsHeaders(
                    extra: [
                        "Content-Length": "0"
                    ]
                ),
                body: Data(),
                on: context.connection,
                context: context,
                close: true
            )

        case ("GET", "/health"):
            let ok =
                await checkHealthHandler()

            sendJSON(
                [
                    "status": ok ? "ok" : "unavailable",
                    "model": modelId
                ],
                status: ok ? 200 : 503,
                on: context.connection,
                context: context
            )

        case ("HEAD", "/health"):
            let ok =
                await checkHealthHandler()

            let response: [String: Any] = [
                "status": ok ? "ok" : "unavailable",
                "model": modelId
            ]

            let body =
                (try? JSONSerialization.data(
                    withJSONObject: response
                )) ?? Data()

            _ = sendResponse(
                status: ok ? 200 : 503,
                headers: corsHeaders(
                    extra: [
                        "Content-Type":
                            "application/json; charset=utf-8",
                        "Content-Length":
                            "\(body.count)"
                    ]
                ),
                body: Data(),
                on: context.connection,
                context: context,
                close: true
            )

        case ("GET", "/v1/models"),
             ("GET", "/models"):

            sendJSON(
                [
                    "object": "list",
                    "data": [[
                        "id": modelId,
                        "object": "model",
                        "created":
                            Int(
                                Date()
                                    .timeIntervalSince1970
                            ),
                        "owned_by": "simigo"
                    ]]
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("GET", "/v1/models/\(modelId)"):

            sendJSON(
                [
                    "id": modelId,
                    "object": "model",
                    "created":
                        Int(
                            Date()
                                .timeIntervalSince1970
                        ),
                    "owned_by": "simigo"
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("POST", "/v1/chat/completions"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            if (json["stream"] as? Bool) == true {
                await handleStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            } else {
                await handleNonStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            }

        case ("POST", "/v1/completions"),
             ("POST", "/completions"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            if (json["stream"] as? Bool) == true {
                await handleTextCompletionsStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            } else {
                await handleTextCompletionsNonStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            }

        case ("POST", "/v1/responses"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            if (json["stream"] as? Bool) == true {
                await handleResponsesStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            } else {
                await handleResponsesNonStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            }

        default:
            sendError(
                "Endpoint not found",
                status: 404,
                on: context.connection,
                context: context
            )
        }
    }

    // MARK: - Identity Helpers

    func resolveClientRequestId(
        from json: [String: Any],
        headers: [String: String]
    ) -> String? {

        if let value =
            normalizeIdentifier(
                json["request_id"] as? String
            ) {
            return value
        }

        return normalizeIdentifier(
            headers["x-request-id"]
        )
    }

    func normalizedHeaderValue(
        _ value: String?
    ) -> String? {
        normalizeIdentifier(value)
    }

    func normalizeIdentifier(
        _ value: String?
    ) -> String? {

        guard let value else {
            return nil
        }

        let trimmed =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.count <= 128 {
            return trimmed
        }

        let prefix =
            String(trimmed.prefix(64))

        let digest =
            SHA256.hash(
                data: Data(trimmed.utf8)
            )
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
            .prefix(16)

        return "\(prefix)_\(digest)"
    }

    func resolveExplicitAgentId(
        from json: [String: Any],
        headers: [String: String]
    ) -> String? {

        if let value =
            normalizeIdentifier(
                json["agent_id"] as? String
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                headers["x-simigo-agent"]
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                headers["x-agent-id"]
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                json["agent"] as? String
            ) {
            return value
        }

        if let metadata =
            json["metadata"] as? [String: Any] {

            if let value =
                normalizeIdentifier(
                    metadata["agent_id"] as? String
                ) {
                return value
            }

            if let value =
                normalizeIdentifier(
                    metadata["agent"] as? String
                ) {
                return value
            }
        }

        return nil
    }

    /// 本次 HTTP 请求在没有明确 Session 时使用的独立 Session。
    ///
    /// 注意：
    /// - 这是 execution/session identity，不是 KV identity。
    /// - 不参与跨请求 KV reuse 判断。
    /// - 每次调用都会生成新的 UUID。
    func makeRequestScopedSessionId(
        requestNamespace: String
    ) -> String {

        return "\(requestNamespace)-request:\(UUID().uuidString.lowercased())"
    }

    // MARK: - Execution Identity

    struct ResolvedExecutionIdentity: Sendable {
        let agentId: String?
        let sessionId: String
        let logicalBranchId: String
        let source: String
    }

    /// OpenAI Chat / Completions 的 Identity Resolution。
    ///
    /// 核心原则：
    ///
    /// 1. 显式 session_id / conversation_id / headers：
    ///    原样保留（只做长度规范化和 topology 解析）。
    ///
    /// 2. Codex thread_id：
    ///    保留为 Codex thread session。
    ///
    /// 3. 不再使用 user 作为 Session。
    ///
    /// 4. 不再根据 messages 前缀生成 Session。
    ///
    /// 5. 没有明确 Session 时，每个 HTTP request 使用独立 Session。
    ///
    /// 6. KV reuse 不在这里做，由 NativeMLX / KV Runtime 决定。
    func resolveExecutionIdentity(
        from json: [String: Any],
        headers: [String: String]
    ) -> ResolvedExecutionIdentity {

        let agentId =
            resolveExplicitAgentId(
                from: json,
                headers: headers
            )

        // 1. Explicit Session
        if let explicitSession =
            resolveExplicitSession(
                from: json,
                headers: headers
            ) {

            let topology =
                normalizedSessionTopology(
                    explicitSession
                )

            return ResolvedExecutionIdentity(
                agentId: agentId,
                sessionId: topology.sessionId,
                logicalBranchId:
                    topology.branchId
                    ?? resolveExplicitBranch(
                        from: json,
                        headers: headers
                    )
                    ?? "main",
                source:
                    topology.branchId == nil
                    ? "explicit_session"
                    : "explicit_session_topology"
            )
        }

        // 2. Codex Thread
        if let threadId =
            resolveThreadId(
                from: json,
                headers: headers
            ) {

            return ResolvedExecutionIdentity(
                agentId: agentId,
                sessionId:
                    "codex-thread:\(threadId)",
                logicalBranchId:
                    resolveExplicitBranch(
                        from: json,
                        headers: headers
                    )
                    ?? "main",
                source:
                    "codex.thread_id"
            )
        }

        // 3. No explicit Session.
        //
        // 这里绝对不能再从 messages 推导。
        //
        // 每个 HTTP request 独立。
        //
        // NativeMLX 后续仍可以：
        // - token prefix match
        // - tool fingerprint match
        // - physical KV reuse
        //
        // 因此不需要人为合并 Session。
        let requestSessionId =
            makeRequestScopedSessionId(
                requestNamespace: "openai"
            )

        return ResolvedExecutionIdentity(
            agentId: agentId,
            sessionId: requestSessionId,
            logicalBranchId:
                resolveExplicitBranch(
                    from: json,
                    headers: headers
                )
                ?? "main",
            source:
                "generated_request_session"
        )
    }

    /// 统一打印 OpenAI Execution Identity。
    ///
    /// 这条日志非常重要：
    ///
    /// [SimiGo Protocol] [EXECUTION]
    /// endpoint=chat.completions
    /// request=req-xxx
    /// clientRequest=...
    /// agent=...
    /// session=...
    /// branch=...
    ///
    /// 用于验证：
    /// - 两个不同 request 是否真的拿到不同 Session。
    /// - 是否存在意外 Session canonicalization。
    func printExecutionIdentity(
        endpoint: String,
        context: ConnectionContext
    ) {
        print(
            "[SimiGo Protocol] " +
            "[EXECUTION] " +
            "endpoint=\(endpoint) " +
            "request=\(context.requestId) " +
            "clientRequest=\(context.clientRequestId ?? "-") " +
            "agent=\(context.agentId ?? "default") " +
            "session=\(context.sessionId ?? "-") " +
            "branch=\(context.logicalBranchId ?? "main")"
        )
    }

    // MARK: - Parameter Extraction

    func extractConfig(
        from json: [String: Any]
    ) -> ModelConfig {

        var config =
            ModelConfig()

        if let maxTokens =
            json["max_completion_tokens"] as? Int
            ?? json["max_tokens"] as? Int {

            config.maxTokens =
                maxTokens
        }

        if let value =
            (json["temperature"] as? NSNumber)?
            .floatValue {

            config.temperature =
                value
        }

        if let value =
            (json["top_p"] as? NSNumber)?
            .floatValue {

            config.topP =
                value
        }

        if let value =
            json["top_k"] as? Int {

            config.topK =
                value
        }

        if let value =
            (json["min_p"] as? NSNumber)?
            .floatValue {

            config.minP =
                value
        }

        if let value =
            (json["repeat_penalty"] as? NSNumber)?
            .floatValue {

            config.repeatPenalty =
                value
        }

        if let value =
            (json["presence_penalty"] as? NSNumber)?
            .floatValue {

            config.presencePenalty =
                value
        }

        if let disableThinking =
            json["disable_thinking"] as? Bool {

            config.disableThinking =
                disableThinking

        } else if let enableThinking =
                    json["enable_thinking"] as? Bool {

            config.disableThinking =
                !enableThinking
        }

        return config
    }

    // MARK: - Parameter Parsing

    func sendJSON(
        _ object: [String: Any],
        status: Int,
        on connection: NWConnection,
        context: ConnectionContext
    ) {

        guard
            let data =
                try? JSONSerialization.data(
                    withJSONObject:
                        object
                )
        else {
            return
        }

        var headers =
            corsHeaders()

        headers["Content-Type"] =
            "application/json; charset=utf-8"

        headers["Content-Length"] =
            "\(data.count)"

        headers["X-Request-Id"] =
            context.requestId

        if let clientRequestId =
            context.clientRequestId {

            headers["X-Client-Request-Id"] =
                clientRequestId
        }

        _ = sendResponse(
            status: status,
            headers: headers,
            body: data,
            on: connection,
            context: context,
            close: true
        )
    }

    @discardableResult
    func sendResponse(
        status: Int,
        headers: [String: String],
        body: Data,
        on connection: NWConnection,
        context: ConnectionContext,
        close: Bool
    ) -> Bool {

        guard !context.closed else {
            return false
        }

        var head =
            "HTTP/1.1 " +
            "\(status) " +
            "\(reasonPhrase(status))\r\n"

        for (key, value) in headers {
            head +=
                "\(key): \(value)\r\n"
        }

        head += "\r\n"

        var packet =
            Data(head.utf8)

        packet.append(body)

        return enqueueSend(
            packet,
            context: context,
            close: close
        )
    }

    func sendSSEChunk(
        _ object: [String: Any],
        context: ConnectionContext
    ) {

        guard
            !context.closed,
            let data =
                try? JSONSerialization.data(
                    withJSONObject:
                        object
                )
        else {
            return
        }

        var payload =
            Data("data: ".utf8)

        payload.append(data)
        payload.append(
            contentsOf:
                "\n\n".utf8
        )

        _ = enqueueSend(
            payload,
            context: context,
            close: false
        )
    }

    func sendRaw(
        _ data: Data,
        context: ConnectionContext,
        close: Bool
    ) {
        _ = enqueueSend(
            data,
            context: context,
            close: close
        )
    }

    @discardableResult
    private func enqueueSend(
        _ data: Data,
        context: ConnectionContext,
        close: Bool
    ) -> Bool {

        guard context.canSend() else {
            return false
        }

        context.sendQueue.async {
            [weak self, weak context] in

            guard
                let self,
                let context,
                context.canSend()
            else {
                return
            }

            context.connection.send(
                content: data,
                isComplete: close,
                completion:
                    .contentProcessed {
                        [weak self, weak context] error in

                        guard
                            let self,
                            let context
                        else {
                            return
                        }

                        if error != nil {

                            self.terminate(
                                context,
                                cancelGeneration: true
                            )

                        } else if close {

                            self.finish(context)

                            context.connection.cancel()
                        }
                    }
            )
        }

        return true
    }

    func sendError(
        _ message: String,
        status: Int,
        on connection: NWConnection,
        context: ConnectionContext
    ) {

        let errorType: String

        switch status {
        case 400, 404, 417:
            errorType =
                "invalid_request_error"

        case 413:
            errorType =
                "request_too_large"

        case 501:
            errorType =
                "not_implemented"

        case 503:
            errorType =
                "server_error"

        default:
            errorType =
                "server_error"
        }

        sendJSON(
            [
                "error": [
                    "message": message,
                    "type": errorType,
                    "param": NSNull(),
                    "code": NSNull()
                ]
            ],
            status: status,
            on: connection,
            context: context
        )
    }

    private func reasonPhrase(
        _ status: Int
    ) -> String {

        switch status {
        case 200:
            return "OK"

        case 204:
            return "No Content"

        case 400:
            return "Bad Request"

        case 404:
            return "Not Found"

        case 413:
            return "Request Entity Too Large"

        case 417:
            return "Expectation Failed"

        case 500:
            return "Internal Server Error"

        case 501:
            return "Not Implemented"

        case 503:
            return "Service Unavailable"

        default:
            return "Error"
        }
    }

    // MARK: - JSON

    private func decodeJSONObject(
        _ body: Data
    ) throws -> [String: Any] {

        guard
            !body.isEmpty,

            let json =
                try? JSONSerialization.jsonObject(
                    with: body
                ) as? [String: Any]
        else {
            throw HTTPServerError.badRequest(
                "Malformed JSON body"
            )
        }

        return json
    }

    func jsonValueDictionary(
        _ value: JSONValue
    ) -> [String: Any]? {

        guard
            let data =
                try? JSONEncoder().encode(
                    value
                ),

            let object =
                try? JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    // MARK: - HTTP Parsing

    private func readRequest(
        from connection: NWConnection
    ) async throws -> HTTPRequest {

        var buffer =
            Data()

        let delimiter =
            Data(
                "\r\n\r\n".utf8
            )

        while
            buffer.range(
                of: delimiter
            ) == nil {

            guard
                let chunk =
                    try await connection.receiveAsync(
                        min: 1,
                        max:
                            Self.receiveChunkSize
                    ),

                !chunk.isEmpty
            else {
                throw HTTPServerError.clientDisconnected
            }

            buffer.append(chunk)

            if buffer.count >
                Self.maxHeaderBytes {

                throw HTTPServerError.payloadTooLarge
            }
        }

        guard
            let headerRange =
                buffer.range(
                    of: delimiter
                )
        else {
            throw HTTPServerError.badRequest(
                "Malformed headers"
            )
        }

        guard
            headerRange.lowerBound <=
                Self.maxHeaderBytes
        else {
            throw HTTPServerError.payloadTooLarge
        }

        guard
            let headerText =
                String(
                    data:
                        buffer[
                            ..<headerRange
                                .lowerBound
                        ],
                    encoding: .utf8
                )
        else {
            throw HTTPServerError.badRequest(
                "Headers are not valid UTF-8"
            )
        }

        let lines =
            headerText.components(
                separatedBy: "\r\n"
            )

        guard
            let requestLine =
                lines.first
        else {
            throw HTTPServerError.badRequest(
                "Missing request line"
            )
        }

        guard
            requestLine.utf8.count <=
                Self.maxHeaderLineBytes
        else {
            throw HTTPServerError.payloadTooLarge
        }

        let requestParts =
            requestLine.split(
                separator: " ",
                omittingEmptySubsequences: true
            )

        guard
            requestParts.count == 3
        else {
            throw HTTPServerError.badRequest(
                "Malformed request line"
            )
        }

        let method =
            String(
                requestParts[0]
            )
            .uppercased()

        let target =
            String(
                requestParts[1]
            )

        let version =
            String(
                requestParts[2]
            )
            .uppercased()

        guard
            version == "HTTP/1.1" ||
            version == "HTTP/1.0"
        else {
            throw HTTPServerError.badRequest(
                "Unsupported HTTP version"
            )
        }

        let path =
            String(
                target.split(
                    separator: "?",
                    maxSplits: 1,
                    omittingEmptySubsequences:
                        false
                ).first ?? ""
            )

        guard !path.isEmpty else {
            throw HTTPServerError.badRequest(
                "Empty request target"
            )
        }

        var headers:
            [String: String] = [:]

        var headerCount =
            0

        for line in lines.dropFirst() {

            if line.isEmpty {
                continue
            }

            headerCount += 1

            guard
                headerCount <=
                    Self.maxHeaderCount
            else {
                throw HTTPServerError.payloadTooLarge
            }

            guard
                line.utf8.count <=
                    Self.maxHeaderLineBytes
            else {
                throw HTTPServerError.payloadTooLarge
            }

            guard
                let colon =
                    line.firstIndex(
                        of: ":"
                    )
            else {
                throw HTTPServerError.badRequest(
                    "Malformed header"
                )
            }

            let key =
                String(
                    line[..<colon]
                )
                .trimmingCharacters(
                    in: .whitespaces
                )
                .lowercased()

            guard !key.isEmpty else {
                throw HTTPServerError.badRequest(
                    "Empty header name"
                )
            }

            let value =
                String(
                    line[
                        line.index(after: colon)...
                    ]
                )
                .trimmingCharacters(
                    in: .whitespaces
                )

            headers[key] =
                value
        }

        if let transferEncoding =
            headers["transfer-encoding"],
           !transferEncoding
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty {

            throw HTTPServerError
                .unsupportedTransferEncoding(
                    transferEncoding
                )
        }

        if let expect =
            headers["expect"],
           !expect
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty {

            throw HTTPServerError
                .expectationFailed
        }

        let bodyStart =
            headerRange.upperBound

        var body =
            buffer.subdata(
                in:
                    bodyStart..<buffer.count
            )

        let contentLength: Int

        if let rawLength =
            headers["content-length"] {

            guard
                let parsed =
                    Int(
                        rawLength
                            .trimmingCharacters(
                                in: .whitespaces
                            )
                    ),

                parsed >= 0
            else {
                throw HTTPServerError.badRequest(
                    "Invalid Content-Length"
                )
            }

            contentLength =
                parsed

        } else {
            contentLength =
                0
        }

        guard
            contentLength <=
                Self.maxBodyBytes
        else {
            throw HTTPServerError.payloadTooLarge
        }

        if contentLength == 0,
           !body.isEmpty {

            throw HTTPServerError.badRequest(
                "Request body requires Content-Length"
            )
        }

        if body.count >
            contentLength {

            body =
                body.prefix(
                    contentLength
                )
        }

        while
            body.count <
            contentLength {

            guard
                let chunk =
                    try await connection.receiveAsync(
                        min: 1,
                        max:
                            min(
                                Self.receiveChunkSize,
                                contentLength -
                                    body.count
                            )
                    ),

                !chunk.isEmpty
            else {
                throw HTTPServerError.clientDisconnected
            }

            let remaining =
                contentLength -
                body.count

            if chunk.count >
                remaining {

                body.append(
                    chunk.prefix(
                        remaining
                    )
                )

                break
            }

            body.append(chunk)
        }

        guard
            body.count ==
                contentLength
        else {
            throw HTTPServerError.clientDisconnected
        }

        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: body
        )
    }
}

// MARK: - Thread-Safe Value

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        lock.lock()
        defer {
            lock.unlock()
        }

        return _value
    }

    func set(_ value: T) {
        lock.lock()
        defer {
            lock.unlock()
        }

        _value = value
    }

    func mutate(
        _ transform: (inout T) -> Void
    ) {
        lock.lock()
        defer {
            lock.unlock()
        }

        transform(&_value)
    }

    @discardableResult
    func mutateReturning<R>(
        _ transform: (inout T) -> R
    ) -> R {

        lock.lock()
        defer {
            lock.unlock()
        }

        return transform(&_value)
    }
}

// MARK: - NSLock Helper

private extension NSLock {
    func withLock<T>(
        _ body: () throws -> T
    ) rethrows -> T {

        lock()
        defer {
            unlock()
        }

        return try body()
    }
}

// MARK: - NWConnection Async Receive

private extension NWConnection {
    func receiveAsync(
        min: Int = 1,
        max: Int = 32 * 1024
    ) async throws -> Data? {

        try await withCheckedThrowingContinuation {
            continuation in

            receive(
                minimumIncompleteLength: min,
                maximumLength: max
            ) {
                data,
                _,
                _,
                error in

                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else {
                    continuation.resume(
                        returning: data
                    )
                }
            }
        }
    }
}
