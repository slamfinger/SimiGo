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

    // MARK: - Responses State

    private static let storedResponsesMaxCount = 64
    private static let storedResponsesTTL: TimeInterval = 1800

    private struct StoredResponse: @unchecked Sendable {
        let responseId: String
        let agentId: String?
        let sessionId: String
        let logicalBranchId: String
        let preambleMessages: [JSONValue]
        let historyMessages: [JSONValue]
        let output: [[String: Any]]
        let response: [String: Any]
        let createdAt: Date
        let lastAccessAt: Date
    }

    private final class ResponsesStateStore: @unchecked Sendable {
        private let lock = NSLock()
        private let maxCount: Int
        private let ttl: TimeInterval
        private var entries: [String: StoredResponse] = [:]

        init(
            maxCount: Int = HTTPServer.storedResponsesMaxCount,
            ttl: TimeInterval = HTTPServer.storedResponsesTTL
        ) {
            self.maxCount = max(1, maxCount)
            self.ttl = max(1, ttl)
        }

        func get(_ responseId: String) -> StoredResponse? {
            lock.withLock {
                purgeExpiredLocked()

                guard let current = entries[responseId] else {
                    return nil
                }

                let refreshed = StoredResponse(
                    responseId: current.responseId,
                    agentId: current.agentId,
                    sessionId: current.sessionId,
                    logicalBranchId: current.logicalBranchId,
                    preambleMessages: current.preambleMessages,
                    historyMessages: current.historyMessages,
                    output: current.output,
                    response: current.response,
                    createdAt: current.createdAt,
                    lastAccessAt: Date()
                )

                entries[responseId] = refreshed
                return refreshed
            }
        }

        func put(_ response: StoredResponse) {
            lock.withLock {
                purgeExpiredLocked()
                entries[response.responseId] = response

                guard entries.count > maxCount else {
                    return
                }

                let victims = entries.values.sorted {
                    $0.lastAccessAt < $1.lastAccessAt
                }

                let removeCount = entries.count - maxCount

                for victim in victims.prefix(max(0, removeCount)) {
                    entries.removeValue(forKey: victim.responseId)
                }
            }
        }

        func clear() {
            lock.withLock {
                entries.removeAll()
            }
        }

        private func purgeExpiredLocked() {
            let deadline = Date().addingTimeInterval(-ttl)

            entries = entries.filter {
                $0.value.lastAccessAt >= deadline
            }
        }
    }

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

    private final class ConnectionContext: @unchecked Sendable {
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

    // MARK: - Responses Streaming State

    private final class ResponsesStreamState: @unchecked Sendable {
        private let lock = NSLock()

        private var sequenceNumber = 0
        private var outputItems: [[String: Any]] = []

        private var messageItemId: String?
        private var messageText = ""
        private var messageContentStarted = false

        func nextSequence() -> Int {
            lock.withLock {
                sequenceNumber += 1
                return sequenceNumber
            }
        }

        func appendAssistantText(_ text: String) -> [[String: Any]] {
            guard !text.isEmpty else {
                return []
            }

            return lock.withLock {
                var events: [[String: Any]] = []

                let itemId: String
                let outputIndex: Int

                if let existingId = messageItemId {
                    itemId = existingId

                    outputIndex =
                        outputItems.firstIndex {
                            ($0["id"] as? String) == existingId
                        }
                        ?? max(outputItems.count - 1, 0)

                } else {
                    itemId = "msg-\(UUID().uuidString.lowercased())"
                    outputIndex = outputItems.count

                    messageItemId = itemId

                    let item: [String: Any] = [
                        "id": itemId,
                        "type": "message",
                        "status": "in_progress",
                        "role": "assistant",
                        "content": []
                    ]

                    outputItems.append(item)

                    events.append([
                        "type": "response.output_item.added",
                        "sequence_number": nextSequenceLocked(),
                        "output_index": outputIndex,
                        "item": item
                    ])
                }

                if !messageContentStarted {
                    messageContentStarted = true

                    events.append([
                        "type": "response.content_part.added",
                        "sequence_number": nextSequenceLocked(),
                        "item_id": itemId,
                        "output_index": outputIndex,
                        "content_index": 0,
                        "part": [
                            "type": "output_text",
                            "text": "",
                            "annotations": []
                        ]
                    ])
                }

                messageText += text

                events.append([
                    "type": "response.output_text.delta",
                    "sequence_number": nextSequenceLocked(),
                    "item_id": itemId,
                    "output_index": outputIndex,
                    "content_index": 0,
                    "delta": text,
                    "logprobs": []
                ])

                return events
            }
        }

        func appendToolCall(_ call: ParsedToolCall) -> [[String: Any]] {
            return lock.withLock {
                var events: [[String: Any]] = []

                if let closed = closeAssistantMessageLocked() {
                    events.append(contentsOf: closed.events)
                }

                let outputIndex = outputItems.count
                let itemId = "fc-\(UUID().uuidString.lowercased())"

                let inProgress: [String: Any] = [
                    "id": itemId,
                    "type": "function_call",
                    "status": "in_progress",
                    "call_id": call.id,
                    "name": call.name,
                    "arguments": ""
                ]

                outputItems.append(inProgress)

                events.append([
                    "type": "response.output_item.added",
                    "sequence_number": nextSequenceLocked(),
                    "output_index": outputIndex,
                    "item": inProgress
                ])

                events.append([
                    "type": "response.function_call_arguments.delta",
                    "sequence_number": nextSequenceLocked(),
                    "item_id": itemId,
                    "output_index": outputIndex,
                    "delta": call.argumentsJSON
                ])

                events.append([
                    "type": "response.function_call_arguments.done",
                    "sequence_number": nextSequenceLocked(),
                    "item_id": itemId,
                    "output_index": outputIndex,
                    "arguments": call.argumentsJSON
                ])

                let doneItem: [String: Any] = [
                    "id": itemId,
                    "type": "function_call",
                    "status": "completed",
                    "call_id": call.id,
                    "name": call.name,
                    "arguments": call.argumentsJSON
                ]

                outputItems[outputIndex] = doneItem

                events.append([
                    "type": "response.output_item.done",
                    "sequence_number": nextSequenceLocked(),
                    "output_index": outputIndex,
                    "item": doneItem
                ])

                return events
            }
        }

        func closeAssistantMessage() -> [[String: Any]] {
            lock.withLock {
                closeAssistantMessageLocked()?.events ?? []
            }
        }

        func snapshotOutputItems() -> [[String: Any]] {
            lock.withLock {
                outputItems
            }
        }

        private func closeAssistantMessageLocked() -> (
            itemId: String,
            outputIndex: Int,
            doneItem: [String: Any],
            events: [[String: Any]]
        )? {
            guard let itemId = messageItemId else {
                return nil
            }

            let outputIndex =
                outputItems.firstIndex {
                    ($0["id"] as? String) == itemId
                }
                ?? max(outputItems.count - 1, 0)

            var events: [[String: Any]] = []

            if messageContentStarted {
                events.append([
                    "type": "response.content_part.done",
                    "sequence_number": nextSequenceLocked(),
                    "item_id": itemId,
                    "output_index": outputIndex,
                    "content_index": 0,
                    "part": [
                        "type": "output_text",
                        "text": messageText,
                        "annotations": []
                    ]
                ])
            }

            let doneMessage: [String: Any] = [
                "id": itemId,
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": messageText,
                    "annotations": []
                ]]
            ]

            if outputIndex < outputItems.count {
                outputItems[outputIndex] = doneMessage
            }

            events.append([
                "type": "response.output_item.done",
                "sequence_number": nextSequenceLocked(),
                "output_index": outputIndex,
                "item": doneMessage
            ])

            messageItemId = nil
            messageText = ""
            messageContentStarted = false

            return (
                itemId,
                outputIndex,
                doneMessage,
                events
            )
        }

        private func nextSequenceLocked() -> Int {
            sequenceNumber += 1
            return sequenceNumber
        }
    }

    // MARK: - Server State

    private let port: NWEndpoint.Port
    private let modelId: String
    private let bindHost: String
    private let bonjourEnabled: Bool

    private let generateHandler: GenerateHandler
    private let checkHealthHandler: CheckHealthHandler
    private let cancelGenerationHandler: CancelGenerationHandler?

    private let queue = DispatchQueue(
        label: "com.simigo.httpserver.connections",
        qos: .userInitiated
    )

    private var listener: NWListener?

    private var connections: [ObjectIdentifier: ConnectionContext] = [:]
    private let connectionLock = NSLock()

    private let responsesStore = ResponsesStateStore()

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

    private func finish(_ context: ConnectionContext) {
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

    private func terminate(
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

    // MARK: - Chat Completions / Streaming

    private func handleStreaming(
        _ json: [String: Any],
        headers: [String: String],
        context: ConnectionContext
    ) async {
        guard
            let parsed = parseChatParams(
                json,
                headers: headers
            )
        else {
            sendError(
                "Invalid messages payload",
                status: 400,
                on: context.connection,
                context: context
            )
            return
        }

        let (
            agentId,
            sessionId,
            logicalBranchId,
            messages,
            tools,
            config
        ) = parsed

        guard context.markGenerationStarted() else {
            return
        }

        // 2. Use defer to ensure lifecycle completion (success or failure)
        var isSuccess = false
        defer {
            context.markGenerationFinished()
            context.finishLifecycle(success: isSuccess)
        }

        context.setIdentity(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId,
            clientRequestId:
                resolveClientRequestId(
                    from: json,
                    headers: headers
                )
        )

        printExecutionIdentity(
            endpoint: "chat.completions",
            context: context
        )

        // 1. Register lifecycle after identity is known, before any transition
        await context.registerLifecycle()

        let responseId =
            "chatcmpl-\(UUID().uuidString.lowercased())"

        let created =
            Int(Date().timeIntervalSince1970)

        let hasToolCalls =
            Locked(false)

        let toolCallIndexCounter =
            Locked(0)

        var responseHeaders =
            corsHeaders()

        responseHeaders["Content-Type"] =
            "text/event-stream; charset=utf-8"

        responseHeaders["Cache-Control"] =
            "no-cache, no-store, must-revalidate"

        responseHeaders["X-Accel-Buffering"] =
            "no"

        responseHeaders["X-Request-Id"] =
            context.requestId

        if let clientRequestId =
            context.clientRequestId {
            responseHeaders["X-Client-Request-Id"] =
                clientRequestId
        }

        guard sendResponse(
            status: 200,
            headers: responseHeaders,
            body: Data(),
            on: context.connection,
            context: context,
            close: false
        ) else {
            return
        }

        do {
            try await context.transitionToQueued()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            // 4. Transition to RUNNING right before generation
            try await context.transitionToRunning()

            _ = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                messages,
                tools,
                config,

                { [weak self, weak context] text in
                    guard
                        let self,
                        let context,
                        !text.isEmpty,
                        !context.closed
                    else {
                        return
                    }

                    self.sendSSEChunk(
                        [
                            "id": responseId,
                            "object":
                                "chat.completion.chunk",
                            "created": created,
                            "model": self.modelId,
                            "choices": [[
                                "index": 0,
                                "delta": [
                                    "content": text
                                ],
                                "finish_reason": NSNull()
                            ]]
                        ],
                        context: context
                    )
                },

                { [weak self, weak context] call in
                    guard
                        let self,
                        let context,
                        !context.closed
                    else {
                        return
                    }

                    hasToolCalls.set(true)

                    let toolIndex =
                        toolCallIndexCounter
                            .mutateReturning { index in
                                let current = index
                                index += 1
                                return current
                            }

                    self.sendSSEChunk(
                        [
                            "id": responseId,
                            "object":
                                "chat.completion.chunk",
                            "created": created,
                            "model": self.modelId,
                            "choices": [[
                                "index": 0,
                                "delta": [
                                    "tool_calls": [[
                                        "index": toolIndex,
                                        "id": call.id,
                                        "type": "function",
                                        "function": [
                                            "name": call.name,
                                            "arguments":
                                                call.argumentsJSON
                                        ]
                                    ]]
                                ],
                                "finish_reason":
                                    NSNull()
                            ]]
                        ],
                        context: context
                    )
                }
            )

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            sendSSEChunk(
                [
                    "id": responseId,
                    "object":
                        "chat.completion.chunk",
                    "created": created,
                    "model": modelId,
                    "choices": [[
                        "index": 0,
                        "delta": [String: Any](),
                        "finish_reason":
                            hasToolCalls.value
                            ? "tool_calls"
                            : "stop"
                    ]]
                ],
                context: context
            )

            sendRaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )

            isSuccess = true

        } catch is CancellationError {
            // Silent cancellation.

        } catch {
            guard !context.closed else {
                return
            }

            sendSSEChunk(
                [
                    "error": [
                        "message":
                            error.localizedDescription,
                        "type":
                            "server_error"
                    ]
                ],
                context: context
            )

            sendRaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )
        }
    }

    // MARK: - Chat Completions / Non-Streaming

    private func handleNonStreaming(
        _ json: [String: Any],
        headers: [String: String],
        context: ConnectionContext
    ) async {
        guard
            let parsed = parseChatParams(
                json,
                headers: headers
            )
        else {
            sendError(
                "Invalid messages payload",
                status: 400,
                on: context.connection,
                context: context
            )
            return
        }

        let (
            agentId,
            sessionId,
            logicalBranchId,
            messages,
            tools,
            config
        ) = parsed

        guard context.markGenerationStarted() else {
            return
        }

        // 2. Use defer to ensure lifecycle completion (success or failure)
        var isSuccess = false
        defer {
            context.markGenerationFinished()
            context.finishLifecycle(success: isSuccess)
        }

        context.setIdentity(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId,
            clientRequestId:
                resolveClientRequestId(
                    from: json,
                    headers: headers
                )
        )

        printExecutionIdentity(
            endpoint: "chat.completions",
            context: context
        )

        // 1. Register lifecycle after identity is known, before any transition
        await context.registerLifecycle()

        let fullContent =
            Locked("")

        let toolCalls =
            Locked<[ParsedToolCall]>([])

        do {
            try await context.transitionToQueued()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            // 4. Transition to RUNNING right before generation
            try await context.transitionToRunning()

            _ = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                messages,
                tools,
                config,

                { text in
                    fullContent.mutate {
                        $0.append(text)
                    }
                },

                { call in
                    toolCalls.mutate {
                        $0.append(call)
                    }
                }
            )

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            let calls =
                toolCalls.value

            let content =
                fullContent.value

            let message: [String: Any]

            if calls.isEmpty {
                message = [
                    "role": "assistant",
                    "content": content
                ]
            } else {
                message = [
                    "role": "assistant",
                    "content": content,
                    "tool_calls": calls.map { call in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": [
                                "name": call.name,
                                "arguments":
                                    call.argumentsJSON
                            ]
                        ]
                    }
                ]
            }

            sendJSON(
                [
                    "id":
                        "chatcmpl-\(UUID().uuidString.lowercased())",
                    "object":
                        "chat.completion",
                    "created":
                        Int(
                            Date()
                                .timeIntervalSince1970
                        ),
                    "model": modelId,
                    "choices": [[
                        "index": 0,
                        "message": message,
                        "finish_reason":
                            calls.isEmpty
                            ? "stop"
                            : "tool_calls"
                    ]]
                ],
                status: 200,
                on: context.connection,
                context: context
            )

            isSuccess = true

        } catch is CancellationError {
            // Silent cancellation.

        } catch {
            guard !context.closed else {
                return
            }

            sendError(
                error.localizedDescription,
                status: 500,
                on: context.connection,
                context: context
            )
        }
    }

    // MARK: - Text Completions / Streaming

    private func handleTextCompletionsStreaming(
        _ json: [String: Any],
        headers: [String: String],
        context: ConnectionContext
    ) async {
        guard
            let parsed = parseCompletionParams(
                json,
                headers: headers
            )
        else {
            sendError(
                "Invalid prompt payload",
                status: 400,
                on: context.connection,
                context: context
            )
            return
        }

        let (
            agentId,
            sessionId,
            logicalBranchId,
            messages,
            config
        ) = parsed

        guard context.markGenerationStarted() else {
            return
        }

        var isSuccess = false
        defer {
            context.markGenerationFinished()
            context.finishLifecycle(success: isSuccess)
        }

        context.setIdentity(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId,
            clientRequestId:
                resolveClientRequestId(
                    from: json,
                    headers: headers
                )
        )

        printExecutionIdentity(
            endpoint: "completions",
            context: context
        )

        await context.registerLifecycle()

        let responseId =
            "cmpl-\(UUID().uuidString.lowercased())"

        let created =
            Int(Date().timeIntervalSince1970)

        var responseHeaders =
            corsHeaders()

        responseHeaders["Content-Type"] =
            "text/event-stream; charset=utf-8"

        responseHeaders["Cache-Control"] =
            "no-cache, no-store, must-revalidate"

        responseHeaders["X-Accel-Buffering"] =
            "no"

        responseHeaders["X-Request-Id"] =
            context.requestId

        guard sendResponse(
            status: 200,
            headers: responseHeaders,
            body: Data(),
            on: context.connection,
            context: context,
            close: false
        ) else {
            return
        }

        do {
            try await context.transitionToQueued()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            // 4. Transition to RUNNING right before generation
            try await context.transitionToRunning()

            _ = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                messages,
                nil,
                config,

                { [weak self, weak context] text in
                    guard
                        let self,
                        let context,
                        !text.isEmpty,
                        !context.closed
                    else {
                        return
                    }

                    self.sendSSEChunk(
                        [
                            "id": responseId,
                            "object": "text_completion",
                            "created": created,
                            "model": self.modelId,
                            "choices": [[
                                "text": text,
                                "index": 0,
                                "logprobs": NSNull(),
                                "finish_reason": NSNull()
                            ]]
                        ],
                        context: context
                    )
                },

                { _ in }
            )

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            sendSSEChunk(
                [
                    "id": responseId,
                    "object": "text_completion",
                    "created": created,
                    "model": modelId,
                    "choices": [[
                        "text": "",
                        "index": 0,
                        "logprobs": NSNull(),
                        "finish_reason": "stop"
                    ]]
                ],
                context: context
            )

            sendRaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )

            isSuccess = true

        } catch is CancellationError {
            // Silent cancellation.

        } catch {
            guard !context.closed else {
                return
            }

            sendSSEChunk(
                [
                    "error": [
                        "message":
                            error.localizedDescription,
                        "type":
                            "server_error"
                    ]
                ],
                context: context
            )

            sendRaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )
        }
    }

    // MARK: - Text Completions / Non-Streaming

    private func handleTextCompletionsNonStreaming(
        _ json: [String: Any],
        headers: [String: String],
        context: ConnectionContext
    ) async {
        guard
            let parsed = parseCompletionParams(
                json,
                headers: headers
            )
        else {
            sendError(
                "Invalid prompt payload",
                status: 400,
                on: context.connection,
                context: context
            )
            return
        }

        let (
            agentId,
            sessionId,
            logicalBranchId,
            messages,
            config
        ) = parsed

        guard context.markGenerationStarted() else {
            return
        }

        var isSuccess = false
        defer {
            context.markGenerationFinished()
            context.finishLifecycle(success: isSuccess)
        }

        context.setIdentity(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId,
            clientRequestId:
                resolveClientRequestId(
                    from: json,
                    headers: headers
                )
        )

        printExecutionIdentity(
            endpoint: "completions",
            context: context
        )

        await context.registerLifecycle()

        let fullContent =
            Locked("")

        do {
            try await context.transitionToQueued()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            // 4. Transition to RUNNING right before generation
            try await context.transitionToRunning()

            _ = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                messages,
                nil,
                config,

                { text in
                    fullContent.mutate {
                        $0.append(text)
                    }
                },

                { _ in }
            )

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            sendJSON(
                [
                    "id":
                        "cmpl-\(UUID().uuidString.lowercased())",
                    "object":
                        "text_completion",
                    "created":
                        Int(
                            Date()
                                .timeIntervalSince1970
                        ),
                    "model": modelId,
                    "choices": [[
                        "text": fullContent.value,
                        "index": 0,
                        "logprobs": NSNull(),
                        "finish_reason": "stop"
                    ]],
                    "usage": [
                        "prompt_tokens": 0,
                        "completion_tokens": 0,
                        "total_tokens": 0
                    ]
                ],
                status: 200,
                on: context.connection,
                context: context
            )

            isSuccess = true

        } catch is CancellationError {
            // Silent cancellation.

        } catch {
            guard !context.closed else {
                return
            }

            sendError(
                error.localizedDescription,
                status: 500,
                on: context.connection,
                context: context
            )
        }
    }

    // MARK: - Responses State Types

    private struct ResponsesIdentity: Sendable {
        let agentId: String?
        let sessionId: String
        let logicalBranchId: String
        let source: String
        let parentResponseId: String?
    }

    private struct ResponsesParsedRequest: @unchecked Sendable {
        let agentId: String?
        let sessionId: String
        let logicalBranchId: String

        let currentInputMessages: [JSONValue]
        let canonicalMessages: [JSONValue]

        let tools: [JSONValue]?
        let config: ModelConfig

        let responseId: String

        let preambleMessages: [JSONValue]
        let currentHistoryMessages: [JSONValue]

        let parent: StoredResponse?
    }

    // MARK: - Responses / Non-Streaming

    private func handleResponsesNonStreaming(
        _ json: [String: Any],
        headers: [String: String],
        context: ConnectionContext
    ) async {
        guard
            let parsed = parseResponsesParams(
                json,
                headers: headers
            )
        else {
            sendError(
                "Invalid input or previous_response_id payload",
                status: 400,
                on: context.connection,
                context: context
            )
            return
        }

        guard context.markGenerationStarted() else {
            return
        }

        var isSuccess = false
        defer {
            context.markGenerationFinished()
            context.finishLifecycle(success: isSuccess)
        }

        context.setIdentity(
            agentId: parsed.agentId,
            sessionId: parsed.sessionId,
            logicalBranchId: parsed.logicalBranchId,
            clientRequestId:
                resolveClientRequestId(
                    from: json,
                    headers: headers
                )
        )

        printExecutionIdentity(
            endpoint: "responses",
            context: context
        )

        await context.registerLifecycle()

        let created =
            Int(Date().timeIntervalSince1970)

        let fullContent =
            Locked("")

        let toolCalls =
            Locked<[ParsedToolCall]>([])

        do {
            try await context.transitionToQueued()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            // 4. Transition to RUNNING right before generation
            try await context.transitionToRunning()

            _ = try await generateHandler(
                context.requestId,
                parsed.agentId,
                parsed.sessionId,
                parsed.logicalBranchId,
                parsed.canonicalMessages,
                parsed.tools,
                parsed.config,

                { text in
                    fullContent.mutate {
                        $0.append(text)
                    }
                },

                { call in
                    toolCalls.mutate {
                        $0.append(call)
                    }
                }
            )

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            let content =
                fullContent.value

            let calls =
                toolCalls.value

            let output =
                buildResponsesOutput(
                    content: content,
                    calls: calls
                )

            let response =
                makeCompletedResponse(
                    responseId: parsed.responseId,
                    created: created,
                    json: json,
                    output: output
                )

            let currentHistory =
                appendResponsesAssistantOutput(
                    historyMessages:
                        parsed.currentHistoryMessages,
                    content: content,
                    calls: calls
                )

            let finalHistory =
                appendParentHistory(
                    parent: parsed.parent,
                    currentHistory: currentHistory
                )

            if shouldStoreResponse(json) {
                storeResponse(
                    responseId: parsed.responseId,
                    agentId: parsed.agentId,
                    sessionId: parsed.sessionId,
                    logicalBranchId: parsed.logicalBranchId,
                    preambleMessages:
                        parsed.preambleMessages,
                    historyMessages:
                        finalHistory,
                    output: output,
                    response: response
                )
            }

            sendJSON(
                response,
                status: 200,
                on: context.connection,
                context: context
            )

            isSuccess = true

        } catch is CancellationError {
            // Silent cancellation.

        } catch {
            guard !context.closed else {
                return
            }

            sendError(
                error.localizedDescription,
                status: 500,
                on: context.connection,
                context: context
            )
        }
    }

    // MARK: - Responses / Streaming

    private func handleResponsesStreaming(
        _ json: [String: Any],
        headers: [String: String],
        context: ConnectionContext
    ) async {
        guard
            let parsed = parseResponsesParams(
                json,
                headers: headers
            )
        else {
            sendError(
                "Invalid input or previous_response_id payload",
                status: 400,
                on: context.connection,
                context: context
            )
            return
        }

        // 2. Use defer to ensure lifecycle completion (success or failure)
        var isSuccess = false
        defer {
            context.markGenerationFinished()
            context.finishLifecycle(success: isSuccess)
        }

        context.setIdentity(
            agentId: parsed.agentId,
            sessionId: parsed.sessionId,
            logicalBranchId: parsed.logicalBranchId,
            clientRequestId:
                resolveClientRequestId(
                    from: json,
                    headers: headers
                )
        )

        printExecutionIdentity(
            endpoint: "responses",
            context: context
        )

        await context.registerLifecycle()

        let created =
            Int(Date().timeIntervalSince1970)

        let streamState =
            ResponsesStreamState()

        let toolCalls =
            Locked<[ParsedToolCall]>([])

        var responseHeaders =
            corsHeaders()

        responseHeaders["Content-Type"] =
            "text/event-stream; charset=utf-8"

        responseHeaders["Cache-Control"] =
            "no-cache, no-store, must-revalidate"

        responseHeaders["X-Accel-Buffering"] =
            "no"

        responseHeaders["X-Request-Id"] =
            context.requestId

        if let clientRequestId =
            context.clientRequestId {
            responseHeaders["X-Client-Request-Id"] =
                clientRequestId
        }

        guard sendResponse(
            status: 200,
            headers: responseHeaders,
            body: Data(),
            on: context.connection,
            context: context,
            close: false
        ) else {
            return
        }

        let initialResponse =
            makeInProgressResponse(
                responseId: parsed.responseId,
                created: created,
                json: json
            )

        let createdEvent: [String: Any] = [
            "type": "response.created",
            "sequence_number":
                streamState.nextSequence(),
            "response": initialResponse
        ]

        let progressEvent: [String: Any] = [
            "type": "response.in_progress",
            "sequence_number":
                streamState.nextSequence(),
            "response": initialResponse
        ]

        enqueueResponsesEvents(
            context: context,
            events: [
                createdEvent,
                progressEvent
            ],
            close: false
        )

        do {
            try await context.transitionToQueued()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            // 4. Transition to RUNNING right before generation
            try await context.transitionToRunning()

            _ = try await generateHandler(
                context.requestId,
                parsed.agentId,
                parsed.sessionId,
                parsed.logicalBranchId,
                parsed.canonicalMessages,
                parsed.tools,
                parsed.config,

                { [weak self, weak context] text in
                    guard
                        let self,
                        let context,
                        !context.closed,
                        !text.isEmpty
                    else {
                        return
                    }

                    let events =
                        streamState
                            .appendAssistantText(text)

                    self.enqueueResponsesEvents(
                        context: context,
                        events: events,
                        close: false
                    )
                },
                { [weak self, weak context] call in
                    guard
                        let self,
                        let context,
                        !context.closed
                    else {
                        return
                    }

                    toolCalls.mutate {
                        $0.append(call)
                    }

                    let events =
                        streamState
                            .appendToolCall(call)

                    self.enqueueResponsesEvents(
                        context: context,
                        events: events,
                        close: false
                    )
                }
            )

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            isSuccess = true // <--- Mark success before final events

            let finalContent =
                extractAssistantText(
                    from:
                        streamState.snapshotOutputItems()
                )

            let finalCalls =
                toolCalls.value

            let finalOutput =
                streamState.snapshotOutputItems()

            let currentHistory =
                appendResponsesAssistantOutput(
                    historyMessages:
                        parsed.currentHistoryMessages,
                    content: finalContent,
                    calls: finalCalls
                )

            let finalHistory =
                appendParentHistory(
                    parent: parsed.parent,
                    currentHistory: currentHistory
                )

            if shouldStoreResponse(json) {
                storeResponse(
                    responseId: parsed.responseId,
                    agentId: parsed.agentId,
                    sessionId: parsed.sessionId,
                    logicalBranchId: parsed.logicalBranchId,
                    preambleMessages:
                        parsed.preambleMessages,
                    historyMessages:
                        finalHistory,
                    output: finalOutput,
                    response: makeCompletedResponse(
                        responseId: parsed.responseId,
                        created: created,
                        json: json,
                        output: finalOutput
                    )
                )
            }

            var completionEvents =
                streamState.closeAssistantMessage()

            completionEvents.append([
                "type": "response.completed",
                "sequence_number":
                    streamState.nextSequence(),
                "response": makeCompletedResponse(
                    responseId: parsed.responseId,
                    created: created,
                    json: json,
                    output: finalOutput
                )
            ])

            enqueueResponsesEvents(
                context: context,
                events: completionEvents,
                close: true
            )

        } catch is CancellationError {
            // Silent cancellation.
        } catch {
            guard !context.closed else {
                return
            }

            let failedResponse: [String: Any] = [
                "id": parsed.responseId,
                "object": "response",
                "status": "failed",
                "error": [
                    "message":
                        error.localizedDescription,
                    "type":
                        "server_error"
                ]
            ]

            let event: [String: Any] = [
                "type": "response.failed",
                "sequence_number":
                    streamState.nextSequence(),
                "response": failedResponse
            ]

            enqueueResponsesEvents(
                context: context,
                events: [event],
                close: true
            )
        }
    }

    // MARK: - Responses Parameters

    private func parseResponsesParams(
        _ json: [String: Any],
        headers: [String: String] = [:]
    ) -> ResponsesParsedRequest? {

        let responseId =
            "resp-\(UUID().uuidString.lowercased())"

        let rawInput =
            json["input"]

        var messages: [[String: Any]] = []

        if let instructions =
            json["instructions"] as? String,
           !instructions.isEmpty {

            messages.append([
                "role": "system",
                "content": instructions
            ])
        }

        if let inputText =
            rawInput as? String {

            messages.append([
                "role": "user",
                "content": inputText
            ])

        } else if let inputItems =
                    rawInput as? [[String: Any]] {

            var seenCallInputs =
                Set<String>()

            var seenCallOutputs =
                Set<String>()

            for item in inputItems {

                let type =
                    item["type"] as? String

                if type == "function_call_output" {
                    let callId =
                        (item["call_id"] as? String) ?? ""

                    guard !callId.isEmpty else {
                        continue
                    }

                    if !seenCallOutputs.contains(callId) {
                        seenCallOutputs.insert(callId)

                        messages.append([
                            "role": "tool",
                            "tool_call_id": callId,
                            "content":
                                Self.stringifyResponsesOutput(
                                    item["output"]
                                )
                        ])
                    }

                    continue
                }

                if type == "function_call" {
                    let callId =
                        (item["call_id"] as? String) ??
                        (item["id"] as? String) ??
                        UUID().uuidString

                    let name =
                        (item["name"] as? String) ?? ""

                    guard !name.isEmpty else {
                        continue
                    }

                    guard !seenCallInputs.contains(callId) else {
                        continue
                    }

                    seenCallInputs.insert(callId)

                    let arguments =
                        (item["arguments"] as? String) ??
                        "{}"

                    messages.append([
                        "role": "assistant",
                        "content": "",
                        "tool_calls": [[
                            "id": callId,
                            "type": "function",
                            "function": [
                                "name": name,
                                "arguments": arguments
                            ]
                        ]]
                    ])

                    continue
                }

                let role =
                    (item["role"] as? String) ??
                    "user"

                var message: [String: Any] = [
                    "role": role,
                    "content":
                        Self.stringifyResponsesContent(
                            item["content"]
                        )
                ]

                if let calls =
                    item["tool_calls"] as? [[String: Any]],
                   !calls.isEmpty {

                    message["tool_calls"] = calls

                } else if let calls =
                            item["calls"] as? [[String: Any]],
                          !calls.isEmpty {

                    message["tool_calls"] = calls
                }

                messages.append(message)
            }

        } else {
            return nil
        }

        guard !messages.isEmpty else {
            return nil
        }

        let tools =
            parseResponsesTools(json)

        let config =
            extractConfig(from: json)

        guard
            let identity =
                resolveResponsesIdentity(
                    from: json,
                    headers: headers,
                    responseId: responseId
                )
        else {
            print(
                "[SimiGo Protocol] " +
                "[RESPONSES] identity resolution failed"
            )

            return nil
        }

        let currentInputMessages =
            messages.map { message in
                JSONValue.object(
                    message.mapValues {
                        JSONValue.any($0)
                    }
                )
            }

        let split =
            splitResponsesEnvelope(
                currentInputMessages
            )

        let effectivePreamble:
            [JSONValue]

        if let parent =
            identity.parentResponseId
                .flatMap({
                    responsesStore.get($0)
                }) {

            effectivePreamble =
                split.preambleMessages.isEmpty
                ? parent.preambleMessages
                : split.preambleMessages

        } else {
            effectivePreamble =
                split.preambleMessages
        }

        let parent =
            identity.parentResponseId.flatMap {
                responsesStore.get($0)
            }

        let canonicalMessages =
            mergeResponsesMessages(
                parent: parent,
                currentPreamble: effectivePreamble,
                currentHistory: split.historyMessages
            )

        let parentHistoryCount =
            parent?.historyMessages.count ?? 0

        print(
            "[SimiGo Protocol] " +
            "[SESSION] " +
            "endpoint=responses " +
            "agent=\(identity.agentId ?? "default") " +
            "session=\(identity.sessionId) " +
            "branch=\(identity.logicalBranchId) " +
            "source=\(identity.source) " +
            "previous=\(identity.parentResponseId ?? "-") " +
            "input=\(messages.count) " +
            "parentHistory=\(parentHistoryCount) " +
            "canonical=\(canonicalMessages.count)"
        )

        return ResponsesParsedRequest(
            agentId: identity.agentId,
            sessionId: identity.sessionId,
            logicalBranchId: identity.logicalBranchId,
            currentInputMessages: currentInputMessages,
            canonicalMessages: canonicalMessages,
            tools: tools,
            config: config,
            responseId: responseId,
            preambleMessages: effectivePreamble,
            currentHistoryMessages: split.historyMessages,
            parent: parent
        )
    }

    private func parseResponsesTools(
        _ json: [String: Any]
    ) -> [JSONValue]? {

        guard
            let rawTools =
                json["tools"] as? [[String: Any]],
            !rawTools.isEmpty
        else {
            return nil
        }

        let mapped: [[String: Any]] =
            rawTools.compactMap { tool in

                let toolType =
                    tool["type"] as? String

                let function =
                    (tool["function"] as? [String: Any])
                    ?? tool

                guard
                    let name =
                        function["name"] as? String,
                    !name.isEmpty
                else {
                    return nil
                }

                var functionBody: [String: Any] = [
                    "name": name,
                    "description":
                        (function["description"] as? String)
                        ?? "",
                    "parameters":
                        (function["parameters"]
                            as? [String: Any])
                        ?? [:]
                ]

                if let strict =
                    function["strict"] as? Bool {
                    functionBody["strict"] = strict
                }

                let outputType =
                    (
                        toolType == nil ||
                        toolType == "function"
                    )
                    ? "function"
                    : toolType!

                return [
                    "type": outputType,
                    "function": functionBody
                ]
            }

        guard !mapped.isEmpty else {
            return nil
        }

        guard
            let data =
                try? JSONSerialization.data(
                    withJSONObject: mapped
                )
        else {
            return nil
        }

        return try? JSONDecoder()
            .decode(
                [JSONValue].self,
                from: data
            )
    }

    // MARK: - Responses Identity

    private func resolveResponsesIdentity(
        from json: [String: Any],
        headers: [String: String],
        responseId: String
    ) -> ResponsesIdentity? {

        let explicitAgent =
            resolveExplicitAgentId(
                from: json,
                headers: headers
            )

        // 1. Explicit parent response chain.
        //
        // Responses 的 parent linkage 是明确的，
        // 因此这里继续继承 parent.sessionId。
        if let previousId =
            normalizeIdentifier(
                json["previous_response_id"] as? String
            ) {

            guard
                let parent =
                    responsesStore.get(previousId)
            else {
                print(
                    "[SimiGo Protocol] " +
                    "[RESPONSES] unknown previous_response_id=" +
                    "\(previousId)"
                )

                return nil
            }

            if let requestAgent = explicitAgent,
               let parentAgent = parent.agentId,
               requestAgent != parentAgent {

                print(
                    "[SimiGo Protocol] " +
                    "[RESPONSES] agent mismatch " +
                    "previous=\(previousId) " +
                    "parent=\(parentAgent) " +
                    "request=\(requestAgent)"
                )

                return nil
            }

            if let explicitSession =
                resolveExplicitSession(
                    from: json,
                    headers: headers
                ) {

                let normalizedExplicit =
                    normalizedSessionTopology(
                        explicitSession
                    ).sessionId

                if normalizedExplicit != parent.sessionId {
                    print(
                        "[SimiGo Protocol] " +
                        "[RESPONSES] session mismatch " +
                        "previous=\(previousId) " +
                        "parent=\(parent.sessionId) " +
                        "request=\(normalizedExplicit)"
                    )

                    return nil
                }
            }

            if let explicitBranch =
                resolveExplicitBranch(
                    from: json,
                    headers: headers
                ),
               explicitBranch != parent.logicalBranchId {

                print(
                    "[SimiGo Protocol] " +
                    "[RESPONSES] branch mismatch " +
                    "previous=\(previousId) " +
                    "parent=\(parent.logicalBranchId) " +
                    "request=\(explicitBranch)"
                )

                return nil
            }

            return ResponsesIdentity(
                agentId:
                    parent.agentId ?? explicitAgent,
                sessionId:
                    parent.sessionId,
                logicalBranchId:
                    parent.logicalBranchId,
                source:
                    "previous_response_id",
                parentResponseId:
                    parent.responseId
            )
        }

        // 2. Explicit client session.
        //
        // 不做 canonical merge，只规范化。
        if let explicitSession =
            resolveExplicitSession(
                from: json,
                headers: headers
            ) {

            let topology =
                normalizedSessionTopology(
                    explicitSession
                )

            return ResponsesIdentity(
                agentId: explicitAgent,
                sessionId: topology.sessionId,
                logicalBranchId:
                    resolveExplicitBranch(
                        from: json,
                        headers: headers
                    )
                    ?? topology.branchId
                    ?? "main",
                source:
                    topology.branchId == nil
                    ? "explicit_session"
                    : "explicit_session_topology",
                parentResponseId: nil
            )
        }

        // 3. Codex thread identity.
        if let threadId =
            resolveThreadId(
                from: json,
                headers: headers
            ) {

            return ResponsesIdentity(
                agentId: explicitAgent,
                sessionId:
                    "codex-thread:\(threadId)",
                logicalBranchId:
                    resolveExplicitBranch(
                        from: json,
                        headers: headers
                    )
                    ?? "main",
                source: "codex.thread_id",
                parentResponseId: nil
            )
        }

        // 4. No explicit session:
        //
        // 不使用 user，不使用 messages 推导。
        // 本请求使用独立 execution session。
        //
        // Responses 后续若想继续链路，应通过
        // previous_response_id 显式恢复 parent。
        let requestSessionId =
            makeRequestScopedSessionId(
                requestNamespace: "responses"
            )

        return ResponsesIdentity(
            agentId: explicitAgent,
            sessionId: requestSessionId,
            logicalBranchId:
                resolveExplicitBranch(
                    from: json,
                    headers: headers
                )
                ?? "main",
            source:
                "generated_request_session",
            parentResponseId: nil
        )
    }

    private func resolveThreadId(
        from json: [String: Any],
        headers: [String: String]
    ) -> String? {

        if let value =
            normalizeIdentifier(
                json["thread_id"] as? String
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                json["threadId"] as? String
            ) {
            return value
        }

        if let metadata =
            json["client_metadata"] as? [String: Any],
           let value =
            normalizeIdentifier(
                metadata["thread_id"] as? String
            ) {
            return value
        }

        if let metadata =
            json["metadata"] as? [String: Any],
           let value =
            normalizeIdentifier(
                metadata["thread_id"] as? String
            ) {
            return value
        }

        if let raw =
            normalizedHeaderValue(
                headers["x-codex-turn-metadata"]
            ),
           let data =
            raw.data(using: .utf8),
           let object =
            try? JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any],
           let value =
            normalizeIdentifier(
                object["thread_id"] as? String
            ) {
            return value
        }

        for key in [
            "thread-id",
            "x-codex-thread-id",
            "x-thread-id"
        ] {
            if let value =
                normalizeIdentifier(
                    headers[key]
                ) {
                return value
            }
        }

        return nil
    }

    private func resolveExplicitSession(
        from json: [String: Any],
        headers: [String: String]
    ) -> String? {

        if let value =
            normalizeIdentifier(
                json["session_id"] as? String
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                json["conversation_id"] as? String
            ) {
            return value
        }

        if let value =
            normalizedHeaderValue(
                headers["x-simigo-session"]
            ) {
            return value
        }

        if let value =
            normalizedHeaderValue(
                headers["x-session-id"]
            ) {
            return value
        }

        if let metadata =
            json["client_metadata"] as? [String: Any],
           let value =
            normalizeIdentifier(
                metadata["session_id"] as? String
            ) {
            return value
        }

        if let metadata =
            json["metadata"] as? [String: Any],
           let value =
            normalizeIdentifier(
                metadata["session_id"] as? String
            ) {
            return value
        }

        return nil
    }

    private func resolveExplicitBranch(
        from json: [String: Any],
        headers: [String: String]
    ) -> String? {

        if let value =
            normalizeIdentifier(
                json["logical_branch_id"] as? String
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                json["branch_id"] as? String
            ) {
            return value
        }

        if let value =
            normalizedHeaderValue(
                headers["x-logical-branch-id"]
            ) {
            return value
        }

        if let value =
            normalizedHeaderValue(
                headers["x-branch-id"]
            ) {
            return value
        }

        return nil
    }

    private func normalizedSessionTopology(
        _ raw: String
    ) -> (
        sessionId: String,
        branchId: String?
    ) {

        let normalized =
            normalizeIdentifier(raw) ?? raw

        if normalized.contains("/") {
            let parts =
                normalized.split(
                    separator: "/",
                    maxSplits: 1,
                    omittingEmptySubsequences: true
                )

            if parts.count == 2,
               !parts[0].isEmpty,
               !parts[1].isEmpty {

                return (
                    String(parts[0]),
                    String(parts[1])
                )
            }
        }

        return (
            normalized,
            nil
        )
    }

    // MARK: - Responses History

    private func splitResponsesEnvelope(
        _ messages: [JSONValue]
    ) -> (
        preambleMessages: [JSONValue],
        historyMessages: [JSONValue]
    ) {

        var preamble: [JSONValue] = []
        var history: [JSONValue] = []

        var enteredHistory = false

        for message in messages {

            guard
                let object =
                    jsonValueDictionary(message)
            else {
                history.append(message)
                enteredHistory = true
                continue
            }

            let role =
                object["role"] as? String

            if !enteredHistory &&
                (role == "system" || role == "developer") {

                preamble.append(message)

            } else {
                enteredHistory = true
                history.append(message)
            }
        }

        return (
            preamble,
            history
        )
    }

    private func mergeResponsesMessages(
        parent: StoredResponse?,
        currentPreamble: [JSONValue],
        currentHistory: [JSONValue]
    ) -> [JSONValue] {

        var merged: [JSONValue] = []

        if !currentPreamble.isEmpty {
            merged.append(
                contentsOf: currentPreamble
            )

        } else if let parent {
            merged.append(
                contentsOf:
                    parent.preambleMessages
            )
        }

        if let parent {
            merged.append(
                contentsOf:
                    parent.historyMessages
            )
        }

        merged.append(
            contentsOf:
                currentHistory
        )

        return merged
    }

    private func appendParentHistory(
        parent: StoredResponse?,
        currentHistory: [JSONValue]
    ) -> [JSONValue] {

        var result: [JSONValue] = []

        if let parent {
            result.append(
                contentsOf:
                    parent.historyMessages
            )
        }

        result.append(
            contentsOf:
                currentHistory
        )

        return result
    }

    private func appendResponsesAssistantOutput(
        historyMessages: [JSONValue],
        content: String,
        calls: [ParsedToolCall]
    ) -> [JSONValue] {

        var result =
            historyMessages

        var assistant: [String: Any] = [
            "role": "assistant",
            "content": content
        ]

        if !calls.isEmpty {
            assistant["tool_calls"] =
                calls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments":
                                call.argumentsJSON
                        ]
                    ]
                }
        }

        if !content.isEmpty || !calls.isEmpty {
            result.append(
                JSONValue.object(
                    assistant.mapValues {
                        JSONValue.any($0)
                    }
                )
            )
        }

        return result
    }

    private func shouldStoreResponse(
        _ json: [String: Any]
    ) -> Bool {
        (json["store"] as? Bool) ?? true
    }

    private func storeResponse(
        responseId: String,
        agentId: String?,
        sessionId: String,
        logicalBranchId: String,
        preambleMessages: [JSONValue],
        historyMessages: [JSONValue],
        output: [[String: Any]],
        response: [String: Any]
    ) {

        let now = Date()

        responsesStore.put(
            StoredResponse(
                responseId: responseId,
                agentId: agentId,
                sessionId: sessionId,
                logicalBranchId: logicalBranchId,
                preambleMessages:
                    preambleMessages,
                historyMessages:
                    historyMessages,
                output: output,
                response: response,
                createdAt: now,
                lastAccessAt: now
            )
        )

        print(
            "[SimiGo Protocol] " +
            "[STORE] " +
            "response=\(responseId) " +
            "agent=\(agentId ?? "default") " +
            "session=\(sessionId) " +
            "branch=\(logicalBranchId) " +
            "history=\(historyMessages.count)"
        )
    }

    // MARK: - Responses Helpers

    private static func stringifyResponsesContent(
        _ content: Any?
    ) -> String {

        guard let content else {
            return ""
        }

        if let string =
            content as? String {
            return string
        }

        if let parts =
            content as? [[String: Any]] {

            return parts.compactMap { part in
                let type =
                    part["type"] as? String

                guard
                    type == nil ||
                    type == "input_text" ||
                    type == "output_text" ||
                    type == "text"
                else {
                    return nil
                }

                return part["text"] as? String
            }.joined()
        }

        if let parts =
            content as? [Any] {

            return parts.compactMap { item in

                guard
                    let part =
                        item as? [String: Any]
                else {
                    return nil
                }

                let type =
                    part["type"] as? String

                guard
                    type == nil ||
                    type == "input_text" ||
                    type == "output_text" ||
                    type == "text"
                else {
                    return nil
                }

                return part["text"] as? String

            }.joined()
        }

        if let dict =
            content as? [String: Any] {

            return dict["text"] as? String
                ?? ""
        }

        return ""
    }

    private static func stringifyResponsesOutput(
        _ output: Any?
    ) -> String {

        if let string =
            output as? String {
            return string
        }

        if let dict =
            output as? [String: Any] {

            let text =
                stringifyResponsesContent(
                    dict
                )

            if !text.isEmpty {
                return text
            }

            if let data =
                try? JSONSerialization.data(
                    withJSONObject: dict
                ),
               let encoded =
                String(
                    data: data,
                    encoding: .utf8
                ) {
                return encoded
            }
        }

        if let parts =
            output as? [[String: Any]] {

            let text =
                stringifyResponsesContent(
                    parts
                )

            if !text.isEmpty {
                return text
            }

            if let data =
                try? JSONSerialization.data(
                    withJSONObject: parts
                ),
               let encoded =
                String(
                    data: data,
                    encoding: .utf8
                ) {
                return encoded
            }
        }

        return String(
            describing:
                output ?? ""
        )
    }

    private func buildResponsesOutput(
        content: String,
        calls: [ParsedToolCall]
    ) -> [[String: Any]] {

        var items:
            [[String: Any]] = []

        if !content.isEmpty {

            items.append([
                "id":
                    "msg-\(UUID().uuidString.lowercased())",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": content,
                    "annotations": []
                ]]
            ])
        }

        for call in calls {

            items.append([
                "id":
                    "fc-\(UUID().uuidString.lowercased())",
                "type": "function_call",
                "status": "completed",
                "call_id": call.id,
                "name": call.name,
                "arguments":
                    call.argumentsJSON
            ])
        }

        return items
    }

    private func makeInProgressResponse(
        responseId: String,
        created: Int,
        json: [String: Any]
    ) -> [String: Any] {

        [
            "id": responseId,
            "object": "response",
            "created_at": created,
            "status": "in_progress",
            "model": modelId,
            "output": [],
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "instructions":
                json["instructions"] ?? NSNull(),
            "metadata":
                json["metadata"] ?? [:]
        ]
    }

    private func makeCompletedResponse(
        responseId: String,
        created: Int,
        json: [String: Any],
        output: [[String: Any]]
    ) -> [String: Any] {

        [
            "id": responseId,
            "object": "response",
            "created_at": created,
            "status": "completed",
            "completed_at": created,
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "instructions":
                json["instructions"] ?? NSNull(),
            "model": modelId,
            "output": output,
            "parallel_tool_calls":
                json["parallel_tool_calls"] ?? true,
            "previous_response_id":
                json["previous_response_id"] ?? NSNull(),
            "store":
                json["store"] ?? true,
            "temperature":
                json["temperature"] ?? 1,
            "text": [
                "format": [
                    "type": "text"
                ]
            ],
            "tool_choice":
                json["tool_choice"] ?? "auto",
            "tools":
                json["tools"] ?? [],
            "top_p":
                json["top_p"] ?? 1,
            "truncation":
                json["truncation"] ?? "disabled",
            "usage": [
                "input_tokens": 0,
                "output_tokens": 0,
                "output_tokens_details": [
                    "reasoning_tokens": 0
                ],
                "total_tokens": 0
            ],
            "user":
                json["user"] ?? NSNull(),
            "metadata":
                json["metadata"] ?? [:]
        ]
    }

    private func extractAssistantText(
        from outputItems: [[String: Any]]
    ) -> String {

        outputItems.compactMap {
            item -> String? in

            guard
                (item["type"] as? String)
                == "message"
            else {
                return nil
            }

            guard
                let content =
                    item["content"]
                    as? [[String: Any]]
            else {
                return nil
            }

            return content
                .compactMap {
                    $0["text"] as? String
                }
                .joined()

        }.joined()
    }

    // MARK: - Identity Helpers

    private func resolveClientRequestId(
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

    private func normalizedHeaderValue(
        _ value: String?
    ) -> String? {
        normalizeIdentifier(value)
    }

    private func normalizeIdentifier(
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

    private func resolveExplicitAgentId(
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
    private func makeRequestScopedSessionId(
        requestNamespace: String
    ) -> String {

        return "\(requestNamespace)-request:\(UUID().uuidString.lowercased())"
    }

    // MARK: - Execution Identity

    private struct ResolvedExecutionIdentity: Sendable {
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
    private func resolveExecutionIdentity(
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
    private func printExecutionIdentity(
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

    private func extractConfig(
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

    private func parseChatParams(
        _ json: [String: Any],
        headers: [String: String] = [:]
    ) -> (
        String?,
        String,
        String,
        [JSONValue],
        [JSONValue]?,
        ModelConfig
    )? {

        guard
            let rawMessages =
                json["messages"],

            let messageData =
                try? JSONSerialization.data(
                    withJSONObject:
                        rawMessages
                ),

            let messages =
                try? JSONDecoder()
                    .decode(
                        [JSONValue].self,
                        from: messageData
                    ),

            !messages.isEmpty
        else {
            return nil
        }

        var tools:
            [JSONValue]?

        if let rawTools =
            json["tools"],
           let toolData =
            try? JSONSerialization.data(
                withJSONObject:
                    rawTools
            ) {

            tools =
                try? JSONDecoder()
                    .decode(
                        [JSONValue].self,
                        from: toolData
                    )
        }

        // 注意：
        // 不再把 messages 传入 Identity Resolver。
        // Session 与 KV prefix matching 已彻底解耦。
        let identity =
            resolveExecutionIdentity(
                from: json,
                headers: headers
            )

        return (
            identity.agentId,
            identity.sessionId,
            identity.logicalBranchId,
            messages,
            tools,
            extractConfig(
                from: json
            )
        )
    }

    private func parseCompletionParams(
        _ json: [String: Any],
        headers: [String: String] = [:]
    ) -> (
        String?,
        String,
        String,
        [JSONValue],
        ModelConfig
    )? {

        let promptText: String

        if let prompt =
            json["prompt"] as? String {

            if let suffix =
                json["suffix"] as? String,
               !suffix.isEmpty {

                promptText =
                    prompt + suffix

            } else {
                promptText =
                    prompt
            }

        } else if let promptArray =
                    json["prompt"] as? [String] {

            promptText =
                promptArray.joined(
                    separator: "\n"
                )

        } else {
            return nil
        }

        let userMessage: [String: Any] = [
            "role": "user",
            "content": promptText
        ]

        guard
            let messageData =
                try? JSONSerialization.data(
                    withJSONObject:
                        [userMessage]
                ),

            let messages =
                try? JSONDecoder()
                    .decode(
                        [JSONValue].self,
                        from: messageData
                    )
        else {
            return nil
        }

        // 同样不从 messages 推导 Session。
        let identity =
            resolveExecutionIdentity(
                from: json,
                headers: headers
            )

        return (
            identity.agentId,
            identity.sessionId,
            identity.logicalBranchId,
            messages,
            extractConfig(
                from: json
            )
        )
    }

    // MARK: - HTTP Output

    private func corsHeaders(
        extra: [String: String] = [:]
    ) -> [String: String] {

        var headers: [String: String] = [
            "Access-Control-Allow-Origin":
                "*",

            "Access-Control-Allow-Methods":
                "GET, POST, OPTIONS",

            "Access-Control-Allow-Headers":
                "Content-Type, Authorization, " +
                "X-Requested-With, X-SimiGo-Agent, " +
                "X-Agent-Id, X-Session-Id, " +
                "X-SimiGo-Session, X-Request-Id, " +
                "X-Logical-Branch-Id, X-Branch-Id, " +
                "thread-id, x-thread-id, " +
                "x-codex-thread-id, x-session-id, " +
                "x-codex-session-id, " +
                "x-codex-turn-metadata",

            "Access-Control-Expose-Headers":
                "X-Request-Id, X-Client-Request-Id",

            "Connection":
                "close"
        ]

        for (key, value) in extra {
            headers[key] = value
        }

        return headers
    }

    private func sendJSON(
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
    private func sendResponse(
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

    private func sendSSEChunk(
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

    private func sendRaw(
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

    private func enqueueResponsesEvents(
        context: ConnectionContext,
        events: [[String: Any]],
        close: Bool
    ) {

        guard !events.isEmpty else {

            if close {
                terminate(
                    context,
                    cancelGeneration: false
                )
            }

            return
        }

        context.sendQueue.async {
            [weak self, weak context] in

            guard
                let self,
                let context,
                !context.closed
            else {
                return
            }

            for (index, event)
                in events.enumerated() {

                guard
                    let data =
                        try? JSONSerialization.data(
                            withJSONObject:
                                event
                        )
                else {
                    continue
                }

                var payload =
                    Data("data: ".utf8)

                payload.append(data)
                payload.append(
                    contentsOf:
                        "\n\n".utf8
                )

                let isLast =
                    close &&
                    index ==
                    events.count - 1

                context.connection.send(
                    content: payload,
                    isComplete: isLast,
                    completion:
                        .contentProcessed {
                            [weak self, weak context]
                            error in

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

                            } else if isLast {

                                self.finish(
                                    context
                                )

                                context.connection
                                    .cancel()
                            }
                        }
                )
            }
        }
    }

    private func sendError(
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

    private func jsonValueDictionary(
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

private final class Locked<T>: @unchecked Sendable {
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
