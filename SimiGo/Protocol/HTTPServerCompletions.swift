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

extension HTTPServer {
    /// `/v1/completions` is a declared compatibility passthrough, not a managed
    /// turn: its prompt is continuation text rather than an Information-Space
    /// demand, so it runs no ES preparation, no IS reuse check and no
    /// settlement. The wire marker keeps that boundary checkable from outside,
    /// so a completion can never be read as an information-continuity result.
    /// The managed entries are `/v1/chat/completions` and `/v1/responses`.
    static var unmanagedCompletionsBlock: [String: Any] {
        ["managed": false, "reason": "legacy_text_completions"]
    }

    /// The text-completions marker, extended with the engine's verdict whenever
    /// the turn did not finish. A completed turn keeps the block byte-identical
    /// to `unmanagedCompletionsBlock`; only an unfinished one carries the cause,
    /// because `finish_reason` alone cannot distinguish cap from cancellation.
    static func completionsBlock(
        _ completion: GenerationCompletion
    ) -> [String: Any] {
        var block = unmanagedCompletionsBlock
        guard !completion.isSettleable else { return block }
        block["completion"] = completion.wireName
        if let reason = completion.incompleteReason {
            block["incomplete_reason"] = reason
        }
        return block
    }

    // MARK: - Text Completions / Streaming

    func handleTextCompletionsStreaming(
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

        // W4/A: text completions carry no information turn, so the verdict runs
        // straight after parsing and before any SSE head or model work.
        if await rejectOnRequestBudget(
            messages: messages,
            tools: nil,
            config: config,
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId,
            headers: headers,
            context: context
        ) {
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

        guard let admissionTicket = await acquireGenerationAdmission(
            for: context,
            endpoint: "completions"
        ) else {
            failureReason = "concurrency_rejected"
            return
        }
        defer {
            releaseGenerationAdmission(
                admissionTicket,
                endpoint: "completions")
        }

        guard context.markGenerationStarted() else {
            return
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
            context: context,
            stream: true
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

        responseHeaders["Connection"] =
            "keep-alive"

        responseHeaders["X-Request-Id"] =
            context.requestId

        guard sendImmediateCompletionsHeaders(
            status: 200,
            headers: responseHeaders,
            context: context
        ) else {
            return
        }

        // 冷预填充静默窗口保活；handler 收口时取消。
        // makeEvent：静默期发协议内真实事件（空 text delta）。
        let heartbeat = startSSEHeartbeat(for: context, makeEvent: { [weak self] in
            guard let self else { return nil }
            let chunk: [String: Any] = [
                "id": responseId,
                "object": "text_completion",
                "created": created,
                "model": modelId,
                "choices": [[
                    "text": "",
                    "index": 0,
                    "logprobs": NSNull(),
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

            let result = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                messages,
                nil,
                config,

                { [weak self, weak context] text in
                    if let self, let context {
                        self.stopDetachedOrphanIfContended(context)
                    }

                    guard
                        let self,
                        let context,
                        !text.isEmpty,
                        !context.closed
                    else {
                        return
                    }

                    self.sendImmediateCompletionsChunk(
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

            sendImmediateCompletionsChunk(
                [
                    "id": responseId,
                    "object": "text_completion",
                    "created": created,
                    "model": modelId,
                    "choices": [[
                        "text": "",
                        "index": 0,
                        "logprobs": NSNull(),
                        "finish_reason": result.completion.finishReason
                    ]],
                    "simigo": Self.completionsBlock(result.completion)
                ],
                context: context
            )

            sendImmediateCompletionsRaw(
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

            sendImmediateCompletionsChunk(
                [
                    "error": [
                        "message": "Generation cancelled",
                        "type": "cancelled"
                    ]
                ],
                context: context
            )

            sendImmediateCompletionsRaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )

        } catch NativeMLXValidationError.contextDemandExceeded(let demand, let budget) {
            // CONTEXT SAFETY：SSE 头已发出，以可识别错误类型收尾。
            failureReason = "context_demand_exceeded: \(demand)>\(budget)"
            guard !context.closed else {
                return
            }

            sendImmediateCompletionsChunk(
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

            sendImmediateCompletionsRaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )
        } catch {
            failureReason = "model_execution_error: \(error.localizedDescription)"
            guard !context.closed else {
                return
            }

            sendImmediateCompletionsChunk(
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

            sendImmediateCompletionsRaw(
                Data("data: [DONE]\n\n".utf8),
                context: context,
                close: true
            )
        }
    }

    // MARK: - Direct SSE Transport

    private func sendImmediateCompletionsHeaders(
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
                guard let self, let context, error != nil else { return }
                self.terminateForClientGone(context)
            }
        )

        return true
    }

    @discardableResult
    nonisolated private func sendImmediateCompletionsChunk(
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
                guard let self, let context, error != nil else { return }
                self.terminateForClientGone(context)
            }
        )

        return true
    }

    private func sendImmediateCompletionsRaw(
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
                    self.terminateForClientGone(context)
                } else if close {
                    self.finish(context)
                    context.connection.cancel()
                }
            }
        )
    }

    // MARK: - Text Completions / Non-Streaming

    func handleTextCompletionsNonStreaming(
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

        // W4/A: same gate as the streaming path, before lifecycle/generation.
        if await rejectOnRequestBudget(
            messages: messages,
            tools: nil,
            config: config,
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId,
            headers: headers,
            context: context
        ) {
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

        guard let admissionTicket = await acquireGenerationAdmission(
            for: context,
            endpoint: "completions"
        ) else {
            failureReason = "concurrency_rejected"
            return
        }
        defer {
            releaseGenerationAdmission(
                admissionTicket,
                endpoint: "completions")
        }

        guard context.markGenerationStarted() else {
            return
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

        do {
            try await context.transitionToQueued()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            let result = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                messages,
                nil,
                config,

                { [weak self, weak context] text in
                    if let self, let context {
                        self.stopDetachedOrphanIfContended(context)
                    }

                    fullContent.mutate {
                        $0.append(text)
                    }
                },

                { _ in }
            )

            keepalive.settle()

            guard
                !context.closed,
                !Task.isCancelled
            else {
                return
            }

            let responseBody: [String: Any] = [
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
                "simigo": Self.completionsBlock(result.completion),
                "choices": [[
                    "text": fullContent.value,
                    "index": 0,
                    "logprobs": NSNull(),
                    "finish_reason": result.completion.finishReason
                ]],
                "usage": [
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0
                ]
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
            // 取消契约：keepalive 头未提交时客户端仍连接必须给 HTTP 终态。
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
            // CONTEXT SAFETY：头未提交（快失败路径）直接给 HTTP 400 终态。
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

    func parseCompletionParams(
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

    func corsHeaders(
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

}
