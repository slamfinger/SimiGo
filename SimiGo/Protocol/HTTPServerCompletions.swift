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
