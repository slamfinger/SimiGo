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

}
