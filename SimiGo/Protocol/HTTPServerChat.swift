import Foundation
import SimiGoRuntimeContract
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

extension HTTPServer {

    // MARK: - Information turn (ES demand → IS → settlement)

    struct InformationTurn {
        let db: SimiGoESISDatabase
        let loop: SimiGoInformationLoop
        let sessionID: String
        let query: String
        let resolution: SimiGoInformationLoop.Resolution
        let modelIdentity: String
        let identity: SimiGoSettlementIdentityBinding.Identity
        let parentStateID: String?
        let position: Int
    }

    /// Resolve the turn's information demand BEFORE generation and persist the
    /// user message. The returned messages may carry a bounded, digest-verified
    /// Information-Space context block. A stable information scope is used when
    /// the client supplies no session: it groups stored chat only and never
    /// changes the protocol execution session feeding the model runtime.
    func prepareInformationTurn(
        json: [String: Any],
        headers: [String: String],
        agentId: String?,
        messages: [JSONValue],
        sessionID: String? = nil,
        queryOverride: String? = nil
    ) -> (messages: [JSONValue], turn: InformationTurn?) {
        let lastUser = messages.reversed().first {
            $0.object?["role"]?.string == "user"
        }?.object?["content"]?.string
        let querySource = queryOverride ?? lastUser
        guard let query = querySource?.trimmingCharacters(in: .whitespacesAndNewlines),
            !query.isEmpty
        else { return (messages, nil) }
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: true)
        else { return (messages, nil) }
        try? db.runMigrations()

        let infoSession = sessionID
            ?? resolveExplicitSession(from: json, headers: headers)
            ?? Self.informationScope(agentId: agentId, messages: messages)
        let loop = SimiGoInformationLoop(database: db)
        let resolution = try? loop.resolve(.init(
            sessionID: infoSession, query: query, includeChat: true,
            chatSessionIDs: [infoSession], limit: 30))
        let context = resolution.map { loop.contextBlock($0) } ?? ""

        // Persist only this turn's user text, not the whole request envelope:
        // re-storing the accumulated history would make every later retrieval
        // return the same duplicated block.
        try? db.appendChatMessage(
            sessionID: infoSession, role: "user", content: query,
            model: modelId, createdAt: Date())

        let producer = informationTurnProducer?()
        let parent = (try? db.currentChatStateID(sessionID: infoSession)) ?? nil
        let position = parent
            .flatMap { (try? db.executionStatePosition($0)) ?? nil }
            .map { $0 + 1 } ?? 0
        let turn = InformationTurn(
            db: db, loop: loop, sessionID: infoSession, query: query,
            resolution: resolution ?? SimiGoInformationLoop.Resolution(
                demandID: "", stateID: nil, reused: false, hits: [],
                inputDigest: "", resultSHA256: "", retrievalSettlementID: "",
                itemIDs: [], staleItemIDs: []),
            modelIdentity: producer?.modelIdentity ?? modelId,
            identity: producer?.identity
                ?? .init(model: "unspecified", tokenizer: "unspecified"),
            parentStateID: parent, position: position)
        guard !context.isEmpty else { return (messages, turn) }
        var augmented = messages
        // The block must not enter the reusable prefix: the prefix pool keys on the
        // token chain of the message list, and this block changes on every turn
        // because this turn's own user text is already settled into the IS. Leading
        // system insertion therefore destroyed every cross-ES KV bind (measured
        // 2026-10-26: identical request bodies → mode=cold, cacheHitTokens=0).
        // Appending to the trailing user turn keeps the leading prefix byte-stable.
        if let lastUser = augmented.lastIndex(where: {
            $0.object?["role"]?.string == "user"
        }), var obj = augmented[lastUser].object, obj["content"]?.string != nil {
            obj["content"] = .string(obj["content"]!.string! + "\n\n" + context)
            augmented[lastUser] = .object(obj)
        } else {
            augmented.append(
                .object(["role": .string("user"), "content": .string(context)]))
        }
        return (augmented, turn)
    }

    /// Settle the produced turn: chat text into the IS, then one authoritative
    /// transaction for ES state + settlement + producer identity + advancement.
    func settleInformationTurn(_ turn: InformationTurn, assistantText: String) {
        let text = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? turn.db.appendChatMessage(
            sessionID: turn.sessionID, role: "assistant", content: text,
            model: modelId, createdAt: Date())
        _ = try? turn.loop.settleTurn(
            generatedText: text,
            resolution: turn.resolution,
            stateID: "chat-\(UUID().uuidString.lowercased())",
            parentStateID: turn.parentStateID,
            position: turn.position,
            modelIdentity: turn.modelIdentity,
            identity: turn.identity,
            sessionID: turn.sessionID,
            summaryQuery: turn.query,
            actions: ["chat.completion"])
    }

    /// Chat grouping key when the client supplies no session. Derived from the
    /// conversation's opening messages, which clients resend on every turn.
    static func informationScope(agentId: String?, messages: [JSONValue]) -> String {
        var seed = agentId ?? ""
        for message in messages {
            guard let object = message.object,
                let role = object["role"]?.string,
                role == "system" || role == "user"
            else { continue }
            seed += "|\(role):\(object["content"]?.string ?? "")"
            if role == "user" { break }
        }
        let digest = SimiGoSettlementAuthority.payloadDigest(Data(seed.utf8))
        return "info-" + digest.prefix(32)
    }

    // MARK: - Chat Completions / Streaming

    func handleStreaming(
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

        let information = prepareInformationTurn(
            json: json, headers: headers, agentId: agentId, messages: messages)
        let turnMessages = information.messages

        if let forkFrom =
            normalizeIdentifier(
                json["fork_from_branch"] as? String
            )
        {
            do {
                _ = try await forkBranchHandler(
                    agentId,
                    sessionId,
                    forkFrom,
                    logicalBranchId
                )
            } catch {
                sendError(
                    "fork_from_branch failed: \(error.localizedDescription)",
                    status: 400,
                    on: context.connection,
                    context: context
                )
                return
            }
        }

        guard context.markGenerationStarted() else {
            return
        }

        var isSuccess = false
        var failureReason: String?
        defer {
            context.markGenerationFinished()
            context.finishLifecycle(
                success: isSuccess,
                failureReason: failureReason
            )
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
            context: context,
            stream: true
        )

        await context.registerLifecycle()

        let responseId =
            "chatcmpl-\(UUID().uuidString.lowercased())"

        let created =
            Int(Date().timeIntervalSince1970)

        let hasToolCalls =
            Locked(false)

        let streamedContent =
            Locked("")

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

        responseHeaders["Connection"] =
            "keep-alive"

        responseHeaders["X-Request-Id"] =
            context.requestId

        if let clientRequestId =
            context.clientRequestId {
            responseHeaders["X-Client-Request-Id"] =
                clientRequestId
        }

        guard sendImmediateStreamingHeaders(
            status: 200,
            headers: responseHeaders,
            context: context
        ) else {
            return
        }

        // 冷预填充静默窗口保活；handler 收口时取消。
        // makeEvent：静默期发协议内真实事件（空 delta chunk）——前端看门狗
        // 按「事件静默」计数，注释行满足不了它（2026-09-13 实测 ~605-671s 断连）。
        let heartbeat = startSSEHeartbeat(for: context, makeEvent: { [weak self] in
            guard let self else { return nil }
            let chunk: [String: Any] = [
                "id": responseId,
                "object": "chat.completion.chunk",
                "created": created,
                "model": modelId,
                "choices": [[
                    "index": 0,
                    "delta": [String: Any](),
                    "finish_reason": NSNull()
                ]]
            ]
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: chunk
                )
            else {
                return nil
            }
            return Data("data: ".utf8) + data + Data("\n\n".utf8)
        })
        defer { heartbeat.cancel() }

        do {
            // P0-3 补位：RUNNING 由推理 gate 闭包置位，协议层必须先完成
            // CREATED→QUEUED，否则 gate 闭包撞非法迁移、请求被当作取消静默丢弃。
            try await context.transitionToQueued()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            _ = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                turnMessages,
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

                    streamedContent.mutate { $0.append(text) }

                    self.sendImmediateSSEChunk(
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

                    self.sendImmediateSSEChunk(
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

            if let turn = information.turn {
                settleInformationTurn(
                    turn, assistantText: streamedContent.value)
            }

            sendImmediateSSEChunk(
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

            sendImmediateSSERaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )

            isSuccess = true

        } catch is CancellationError {
            // 取消契约：SSE 头已发出且客户端仍在连接时必须给出终态
            // （error chunk + [DONE] + close），否则客户端将无限等待。
            failureReason = context.cancellationFailureReason()
            guard !context.closed else { return }

            sendImmediateSSEChunk(
                [
                    "error": [
                        "message": "Generation cancelled",
                        "type": "cancelled"
                    ]
                ],
                context: context
            )

            sendImmediateSSERaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )

        } catch NativeMLXValidationError.contextDemandExceeded(let demand, let budget) {
            // CONTEXT SAFETY：SSE 头已发出，以可识别错误类型收尾，
            // 客户端（Codex 等）据此压缩上下文重试而非无限等待。
            failureReason = "context_demand_exceeded: \(demand)>\(budget)"
            guard !context.closed else { return }

            sendImmediateSSEChunk(
                [
                    "error": [
                        "message":
                            "context_length_exceeded: prompt content \(demand) tokens exceeds context budget \(budget); compact the conversation and retry",
                        "type":
                            "context_length_exceeded"
                    ]
                ],
                context: context
            )

            sendImmediateSSERaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )

        } catch {
            failureReason = "model_execution_error: \(error.localizedDescription)"
            guard !context.closed else {
                return
            }

            sendImmediateSSEChunk(
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

            sendImmediateSSERaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )
        }
    }

    // MARK: - Direct SSE Transport

    private func sendImmediateStreamingHeaders(
        status: Int,
        headers: [String: String],
        context: ConnectionContext
    ) -> Bool {
        guard !context.closed else {
            return false
        }

        context.touchOutboundActivity()

        var head =
            "HTTP/1.1 \(status) \(reasonPhrase(status))\r\n"

        for (key, value) in headers {
            head +=
                "\(key): \(value)\r\n"
        }

        head += "\r\n"

        context.connection.send(
            content: Data(head.utf8),
            isComplete: false,
            completion: .contentProcessed { [weak self, weak context] error in
                guard let self, let context, let error else { return }
                self.terminate(context, cancelGeneration: true)
                _ = error
            }
        )

        return true
    }

    @discardableResult
    nonisolated private func sendImmediateSSEChunk(
        _ object: [String: Any],
        context: ConnectionContext
    ) -> Bool {
        guard
            !context.closed,
            let data =
                try? JSONSerialization.data(
                    withJSONObject: object
                )
        else {
            return false
        }

        context.touchOutboundActivity()

        var payload =
            Data("data: ".utf8)

        payload.append(data)
        payload.append(contentsOf: "\n\n".utf8)

        context.connection.send(
            content: payload,
            isComplete: false,
            completion: .contentProcessed { [weak self, weak context] error in
                guard let self, let context else { return }
                if error != nil {
                    self.terminate(context, cancelGeneration: true)
                }
            }
        )

        return true
    }

    private func sendImmediateSSERaw(
        _ data: Data,
        context: ConnectionContext,
        close: Bool
    ) {
        guard !context.closed else {
            return
        }

        context.touchOutboundActivity()

        context.connection.send(
            content: data,
            isComplete: close,
            completion: .contentProcessed { [weak self, weak context] error in
                guard let self, let context else { return }

                if error != nil {
                    self.terminate(context, cancelGeneration: true)
                } else if close {
                    self.finish(context)
                    context.connection.cancel()
                }
            }
        )
    }

    // MARK: - Chat Completions / Non-Streaming

    func handleNonStreaming(
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

        let information = prepareInformationTurn(
            json: json, headers: headers, agentId: agentId, messages: messages)
        let turnMessages = information.messages

        if let forkFrom =
            normalizeIdentifier(
                json["fork_from_branch"] as? String
            )
        {
            do {
                _ = try await forkBranchHandler(
                    agentId,
                    sessionId,
                    forkFrom,
                    logicalBranchId
                )
            } catch {
                sendError(
                    "fork_from_branch failed: \(error.localizedDescription)",
                    status: 400,
                    on: context.connection,
                    context: context
                )
                return
            }
        }

        guard context.markGenerationStarted() else {
            return
        }

        var isSuccess = false
        var failureReason: String?
        defer {
            context.markGenerationFinished()
            context.finishLifecycle(
                success: isSuccess,
                failureReason: failureReason
            )
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
            context: context,
            stream: false
        )

        await context.registerLifecycle()

        // 非流式长静默窗口保活（2026-10-16；机制与实测档案见
        // startNonStreamingKeepalive，三个非流式 handler 共用）。
        let keepalive = startNonStreamingKeepalive(
            context: context
        )
        defer { keepalive.settle() }

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

            _ = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                turnMessages,
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

            keepalive.settle()

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

            if let turn = information.turn {
                settleInformationTurn(turn, assistantText: content)
            }
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

            let responseBody: [String: Any] = [
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
            ]

            if keepalive.committed {
                sendDeferredJSONTerminal(
                    responseBody,
                    context: context
                )
            } else {
                sendJSON(
                    responseBody,
                    status: 200,
                    on: context.connection,
                    context: context
                )
            }

            isSuccess = true

        } catch is CancellationError {
            // 取消契约：非流式尚未发出任何字节（keepalive 未提交头）时，
            // 客户端仍连接必须给出 HTTP 终态。
            keepalive.settle()
            failureReason = context.cancellationFailureReason()
            guard !context.closed else { return }

            sendNonStreamingError(
                "Generation cancelled",
                status: 503,
                on: context.connection,
                context: context,
                headCommitted: keepalive.committed
            )

        } catch NativeMLXValidationError.contextDemandExceeded(let demand, let budget) {
            // 未提交头（快失败路径）：直接给 HTTP 400 终态。
            keepalive.settle()
            failureReason = "context_demand_exceeded: \(demand)>\(budget)"
            guard !context.closed else { return }

            sendNonStreamingError(
                "context_length_exceeded: prompt content \(demand) tokens exceeds context budget \(budget); compact the conversation and retry",
                status: 400,
                on: context.connection,
                context: context,
                headCommitted: keepalive.committed
            )
        } catch {
            keepalive.settle()
            failureReason = "model_execution_error: \(error.localizedDescription)"
            guard !context.closed else {
                return
            }

            sendNonStreamingError(
                error.localizedDescription,
                status: 500,
                on: context.connection,
                context: context,
                headCommitted: keepalive.committed
            )
        }
    }

    /// 非流式长静默窗口保活句柄：生成结束方调用 settle()（幂等），
    /// 终结发送前读 committed 决定走原路径（错误状态码保全）还是
    /// 已提交 200 头后的裸 JSON 直发。三个非流式 handler 共用。
    final class NonStreamingKeepalive {

        private let settled: Locked<Bool>

        private let headCommitted: Locked<Bool>

        private let task: Task<Void, Never>

        init(
            settled: Locked<Bool>,
            headCommitted: Locked<Bool>,
            task: Task<Void, Never>
        ) {
            self.settled = settled
            self.headCommitted = headCommitted
            self.task = task
        }

        var committed: Bool {
            headCommitted.value
        }

        func settle() {
            settled.mutate { $0 = true }
            task.cancel()
        }
    }

    /// 非流式长静默窗口保活启动器（2026-10-16，v2.1.14 提取三端点共享）。
    ///
    /// 非流式契约是「生成完成前零出站字节」，而 Node/undici 默认
    /// headersTimeout=300s / bodyTimeout=300s：整整 300 秒拿不到任何
    /// 响应字节即拆连接（2026-10-16 生产实测：11 笔非流式长预填请求
    /// 全部在 301.4s peerClosed，最惨一笔渲染进度 97% 报废，客户端
    /// 盲重试致 GPU 空转约 55 分钟）。流式路径已有立即头 + 空 delta
    /// 事件双保活，非流式此前无装甲。
    ///
    /// 方案：240s 定时器（=300s 死线留 60s 余量）与生成赛跑——窗口
    /// 内完成的请求字节行为与本机制引入前完全一致（错误状态码语义
    /// 保全）；仅超窗请求先提交 200 头（无 Content-Length、close 定
    /// 界），随后每 5s 滴一个 JSON 合法前导空白字节（RFC 8259 ws）
    /// 喂住两层超时，终结时补发全量 JSON 体。该模式下状态码不可逆
    /// （恒 200），错误以同构 error 体承载——此模式客户端在无保活
    /// 时必然死于拆连，任何可解析终态都是严格改进。
    func startNonStreamingKeepalive(
        context: ConnectionContext
    ) -> NonStreamingKeepalive {

        let settled = Locked(false)
        let headCommitted = Locked(false)

        let task = Task { [weak self, weak context] in
            try? await Task.sleep(
                nanoseconds: 240 * 1_000_000_000
            )

            guard
                !Task.isCancelled,
                let self,
                let context,
                !context.closed,
                !settled.value
            else {
                return
            }

            headCommitted.mutate { $0 = true }

            self.sendDeferredJSONHead(context: context)

            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: 5 * 1_000_000_000
                )

                guard
                    !Task.isCancelled,
                    !context.closed,
                    !settled.value
                else {
                    return
                }

                self.sendRaw(
                    Data("\n".utf8),
                    context: context,
                    close: false
                )
            }
        }

        return NonStreamingKeepalive(
            settled: settled,
            headCommitted: headCommitted,
            task: task
        )
    }

    /// keepalive 模式的错误终结：头未提交走原路径（状态码语义不变）；
    /// 头已恒 200 时以同构 error 体直发 + close。
    func sendNonStreamingError(
        _ message: String,
        status: Int,
        on connection: NWConnection,
        context: ConnectionContext,
        headCommitted: Bool
    ) {
        if !headCommitted {
            sendError(
                message,
                status: status,
                on: connection,
                context: context
            )
            return
        }

        sendDeferredJSONTerminal(
            errorBody(message: message, status: status),
            context: context
        )
    }

    /// keepalive 头提交（镜像 sendImmediateStreamingHeaders 的裸写法）：
    /// 200 + JSON 头，无 Content-Length（close 定界体），Connection: close。
    func sendDeferredJSONHead(
        context: ConnectionContext
    ) {
        guard !context.closed else {
            return
        }

        context.touchOutboundActivity()

        var headers = corsHeaders()

        headers["Content-Type"] =
            "application/json; charset=utf-8"

        headers["Connection"] = "close"

        headers["X-Request-Id"] =
            context.requestId

        if let clientRequestId =
            context.clientRequestId {

            headers["X-Client-Request-Id"] =
                clientRequestId
        }

        var head =
            "HTTP/1.1 200 OK\r\n"

        for (key, value) in headers {
            head +=
                "\(key): \(value)\r\n"
        }

        head += "\r\n"

        context.connection.send(
            content: Data(head.utf8),
            isComplete: false,
            completion: .contentProcessed { [weak self, weak context] error in
                guard let self, let context, let error else { return }
                self.terminate(context, cancelGeneration: true)
                _ = error
            }
        )
    }

    /// keepalive 模式的终结发送：头已提交，全量 JSON 体直发 + close
    /// （enqueueSend 自带 error→terminate / close→finish 收口语义）。
    /// 体前可能已有前导空白滴（RFC 8259 合法 ws），客户端解析不受影响。
    func sendDeferredJSONTerminal(
        _ body: [String: Any],
        context: ConnectionContext
    ) {
        guard
            !context.closed,
            let data =
                try? JSONSerialization.data(
                    withJSONObject: body
                )
        else {
            return
        }

        sendRaw(
            data,
            context: context,
            close: true
        )
    }

    func parseChatParams(
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
        // 与 Responses 的 input 同款零序列化转换（TypesBridge.JSONValue.any）：
        // 请求体已完整解析过一次，messages 子树不再走 data → JSONDecoder
        // 的全量重复往返。逐元素 any 转换与旧解码路径对所有 JSON 类型
        // （string/bool/number/null/object/array、非 object 元素、空数组、
        // 非 array messages）行为一致。
        guard
            let rawMessages = json["messages"] as? [Any],
            !rawMessages.isEmpty
        else {
            return nil
        }

        let messages = rawMessages.map { JSONValue.any($0) }

        var tools:
            [JSONValue]?

        // OpenAI clients commonly send `"tools": null`. JSONSerialization
        // throws an ObjC exception for that Any, which `try?` cannot catch.
        if let rawTools =
            json["tools"] as? [[String: Any]],
           !rawTools.isEmpty,
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

}
