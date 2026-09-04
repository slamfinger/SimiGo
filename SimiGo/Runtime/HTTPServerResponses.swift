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
// MARK: - Responses State


struct StoredResponse: @unchecked Sendable {
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

final class ResponsesStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private let maxCount: Int
    private let ttl: TimeInterval
    private var entries: [String: StoredResponse] = [:]

    init(
        maxCount: Int = RuntimeTuning.responsesStoreMaxCount,
        ttl: TimeInterval = RuntimeTuning.responsesStoreTTLSeconds
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

    func purgeExpiredLocked() {
        let deadline = Date().addingTimeInterval(-ttl)

        entries = entries.filter {
            $0.value.lastAccessAt >= deadline
        }
    }
}

// MARK: - Responses Streaming State

final class ResponsesStreamState: @unchecked Sendable {
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

    func closeAssistantMessageLocked() -> (
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

    func nextSequenceLocked() -> Int {
        sequenceNumber += 1
        return sequenceNumber
    }
}

// MARK: - Responses State Types

struct ResponsesIdentity: Sendable {
    let agentId: String?
    let sessionId: String
    let logicalBranchId: String
    let source: String
    let parentResponseId: String?
}

struct ResponsesParsedRequest: @unchecked Sendable {
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


extension HTTPServer {
    // MARK: - Responses / Non-Streaming

    func handleResponsesNonStreaming(
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

    func handleResponsesStreaming(
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

    func parseResponsesParams(
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

    func parseResponsesTools(
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

    func resolveResponsesIdentity(
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

    func resolveThreadId(
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

    func resolveExplicitSession(
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

    func resolveExplicitBranch(
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

    func normalizedSessionTopology(
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

    func splitResponsesEnvelope(
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

    func mergeResponsesMessages(
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

    func appendParentHistory(
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

    func appendResponsesAssistantOutput(
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

    func shouldStoreResponse(
        _ json: [String: Any]
    ) -> Bool {
        (json["store"] as? Bool) ?? true
    }

    func storeResponse(
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

    func buildResponsesOutput(
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

    func makeInProgressResponse(
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

    func makeCompletedResponse(
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

    func extractAssistantText(
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

    func enqueueResponsesEvents(
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

}
