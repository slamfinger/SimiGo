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
        let userMessageID: Int64
        let resolution: SimiGoInformationLoop.Resolution
        let modelIdentity: String
        let identity: SimiGoSettlementIdentityBinding.Identity
        let parentStateID: String?
        let position: Int
        let eligibility: SimiGoESISDatabase.ChatTurnEligibility
    }

    /// Semantic eligibility is declared by the client, never inferred from the
    /// wire, the session, or the content. `metadata.simigo_request_scope` (or
    /// the `X-SimiGo-Request-Scope` header) set to `internal` marks a client
    /// bookkeeping call — rollout analysis, title generation, memory extraction
    /// — which is recorded for audit but never becomes ordinary conversation
    /// memory or a settled result. Anything else stays an ordinary turn.
    static func turnEligibility(
        from json: [String: Any], headers: [String: String]
    ) -> SimiGoESISDatabase.ChatTurnEligibility {
        let declared = [
            (json["metadata"] as? [String: Any])?["simigo_request_scope"] as? String,
            (json["client_metadata"] as? [String: Any])?["simigo_request_scope"] as? String,
            headers["x-simigo-request-scope"],
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { !$0.isEmpty }
        switch declared {
        case "internal", "internal_operation", "internal-op":
            return .internalOperation
        default:
            return .ordinary
        }
    }

    /// Env-gated provenance capture used to find a real client's per-request
    /// declaration channel. Default off. Header names are safe to record;
    /// values are limited to a non-sensitive allowlist and never include
    /// credentials, cookies, or arbitrary client metadata.
    static func traceClientProvenance(headers: [String: String]) {
        guard ProcessInfo.processInfo.environment["SIMIGO_TRACE_CLIENT_HEADERS"] == "1"
        else { return }
        func clean(_ raw: String) -> String {
            let flattened = raw
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\"", with: "'")
            return flattened.count <= 160
                ? flattened : String(flattened.prefix(160)) + "…"
        }
        let names = headers.keys.sorted().joined(separator: ",")
        let picked = ["originator", "user-agent", "x-codex-turn-metadata",
                      "x-simigo-request-scope"]
            .compactMap { name -> String? in
                guard let value = headers[name] else { return nil }
                return "\(name)=\"\(clean(value))\""
            }
            .joined(separator: " ")
        RuntimeTraceLogger.shared.trace(
            "[CLIENT] headers=\(names)" + (picked.isEmpty ? "" : " " + picked))
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
        }?.object?["content"]?.messageText
        let querySource = queryOverride ?? lastUser
        guard let rawQuery = querySource?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawQuery.isEmpty
        else { return (messages, nil) }
        // Retrieval, the demand row and the reuse key all see the question, not
        // the client's per-turn envelope. Measured 2026-10-29: the envelope owned
        // every extracted term, so 30 hits were greetings and LUA sources and the
        // answer never used the information space it had just searched.
        let query = SimiGoInformationLoop.retrievalQuery(from: rawQuery)
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: true)
        else { return (messages, nil) }
        try? db.runMigrations()

        let infoSession = sessionID
            ?? resolveExplicitSession(from: json, headers: headers)
            ?? Self.informationScope(agentId: agentId, messages: messages)
        let eligibility = Self.turnEligibility(from: json, headers: headers)
        Self.traceClientProvenance(headers: headers)
        let loop = SimiGoInformationLoop(database: db)
        let resolution = try? loop.resolve(.init(
            sessionID: infoSession, query: query, includeChat: true,
            chatSessionIDs: [infoSession], limit: 30))
        let retrieval = resolution ?? SimiGoInformationLoop.Resolution(
            demandID: "", stateID: nil, reused: false, hits: [], inputDigest: "",
            resultSHA256: "", retrievalSettlementID: "", itemIDs: [], staleItemIDs: [])
        let candidate = resolution.map { loop.contextBlock($0) } ?? ""
        // The turn this block is attached to. Inside a tool loop the client
        // repeats the same trailing user message every request, so this is a
        // mid-chain position the engine has already committed.
        let target = messages.lastIndex(where: {
            $0.object?["role"]?.string == "user"
        })
        let turnText = target.flatMap { messages[$0].object?["content"]?.messageText } ?? query
        let snapshot = Self.contextFreezingEnabled
            ? SimiGoISContextLedger.shared.stabilize(
                scope: infoSession, userText: turnText,
                block: candidate, resolution: retrieval)
            : SimiGoISContextLedger.Snapshot(
                block: candidate, resolution: retrieval,
                isReplay: false, candidateChanged: false)
        let context = snapshot.block
        // One readable line per turn: the landed index is the fact that decides
        // whether the committed prefix drifts — a mid-chain index sits inside
        // what the engine already rendered, `tail` does not.
        RuntimeTraceLogger.shared.trace(
            "[IS] contextInject scope=\(infoSession)"
                + " index=\(target.map { String($0) } ?? "tail")"
                + " bytes=\(context.utf8.count) candidateBytes=\(candidate.utf8.count)"
                + " replay=\(snapshot.isReplay ? 1 : 0)"
                + (snapshot.candidateChanged ? " frozenStale=1" : "")
                + (eligibility == .internalOperation ? " eligibility=internal" : "")
        )

        // Persist only this turn's user text, not the whole request envelope:
        // re-storing the accumulated history would make every later retrieval
        // return the same duplicated block. The row starts ineligible and is
        // promoted only when this turn's reply is committed; a declared
        // internal operation never becomes eligible at all.
        let userMessageID = (try? db.appendChatMessage(
            sessionID: infoSession, role: "user", content: query,
            model: modelId, createdAt: Date(), eligibility: eligibility)) ?? -1

        let producer = informationTurnProducer?()
        let parent = (try? db.currentChatStateID(sessionID: infoSession)) ?? nil
        let position = parent
            .flatMap { (try? db.executionStatePosition($0)) ?? nil }
            .map { $0 + 1 } ?? 0
        let turn = InformationTurn(
            db: db, loop: loop, sessionID: infoSession, query: query,
            userMessageID: userMessageID,
            resolution: snapshot.resolution,
            modelIdentity: producer?.modelIdentity ?? modelId,
            identity: producer?.identity ?? .absent,
            parentStateID: parent, position: position,
            eligibility: eligibility)
        var augmented = messages
        func attach(_ block: String, at index: Int) {
            guard !block.isEmpty, var object = augmented[index].object,
                let content = object["content"]
            else { return }
            // 写回规范 .string 形态：注入点两侧（IS 冻结键 / 引擎前缀对账）
            // 必须看到同一表示，multipart 原形在此收敛。
            object["content"] = .string(content.messageText + "\n\n" + block)
            augmented[index] = .object(object)
        }
        // The block must not be re-retrieved per turn into a committed message:
        // the engine reuses its prefix only while every previously rendered
        // message stays byte-identical, and a fresh block here cost a full cold
        // prefill every turn (measured 2026-10-26/27: mode=cold, cacheHitTokens=0).
        // Older user turns already carry their frozen block in the engine's
        // ledger, so replay exactly what was committed for them.
        if Self.contextFreezingEnabled {
            let ledger = SimiGoISContextLedger.shared
            for index in augmented.indices {
                guard index != target,
                    augmented[index].object?["role"]?.string == "user",
                    let text = augmented[index].object?["content"]?.messageText,
                    let replay = ledger.frozenBlock(scope: infoSession, userText: text)
                else { continue }
                attach(replay, at: index)
            }
        }
        if let target {
            attach(context, at: target)
        } else if !context.isEmpty {
            augmented.append(
                .object(["role": .string("user"), "content": .string(context)]))
        }
        return (augmented, turn)
    }

    /// Settle the produced turn: chat text into the IS, then one authoritative
    /// transaction for ES state + settlement + producer identity + advancement.
    ///
    /// `completion` is the engine's verdict for THIS turn: a turn that did not
    /// finish stays in the conversation but registers no settlement, so it can
    /// never be served later as a settled, reusable answer.
    ///
    /// `producedToolCalls` marks an intermediate turn of a tool loop — narration
    /// the client is about to continue, not an answer. Measured 2026-10-29: three
    /// such lines ("工作区里没有直接包含…", 71–150 B) were settled `valid` with full
    /// producer bindings, which makes a progress note a candidate reusable
    /// answer. The conversation line is still stored; only the claim that this
    /// text answers the demand is withheld.
    func settleInformationTurn(
        _ turn: InformationTurn,
        assistantText: String,
        completion: GenerationCompletion,
        producedToolCalls: Bool = false
    ) {
        let text = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? turn.db.commitChatTurn(
            sessionID: turn.sessionID, userMessageID: turn.userMessageID,
            assistantText: text, model: modelId, createdAt: Date(),
            eligibility: turn.eligibility)
        guard turn.eligibility == .ordinary else {
            RuntimeTraceLogger.shared.trace(
                "[SETTLE_SKIP] wire=chat reason=internal_operation "
                    + "session=\(turn.sessionID) settlement_written=0")
            return
        }
        guard completion.isSettleable else {
            RuntimeTraceLogger.shared.trace(
                "[SETTLE_SKIP] wire=chat completion=\(completion.wireName) "
                    + "session=\(turn.sessionID) settlement_written=0")
            return
        }
        guard !producedToolCalls else {
            RuntimeTraceLogger.shared.trace(
                "[SETTLE_SKIP] wire=chat reason=tool_calls "
                    + "session=\(turn.sessionID) settlement_written=0")
            return
        }
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

    /// The chat wire has no incomplete status, so `finish_reason: length` is all
    /// a client can be told there. This block carries what the wire cannot: the
    /// exact termination cause and the fact that nothing was settled. It appears
    /// only on a turn that did not finish, so a normal turn is unchanged.
    private func chatCompletionBlock(
        _ completion: GenerationCompletion
    ) -> [String: Any]? {
        guard !completion.isSettleable else { return nil }
        return [
            "completion": completion.wireName,
            "settlement_written": false,
        ]
    }

    // MARK: - Automatic Information-Space answer reuse (zero model call)

    /// A settled answer the Information Space can serve for this turn.
    struct ReusableAnswer {
        let text: String
        let settlementID: String
        let demandID: String
        let sourceStateID: String
    }

    /// On by default: 「可以复用就不调用模型」 is the product behaviour, and
    /// `SIMIGO_IS_ANSWER_REUSE=0` is the diagnostic off-switch used to prove a
    /// reading came from the model rather than from the Information Space.
    static var isAnswerReuseEnabled: Bool {
        ProcessInfo.processInfo.environment["SIMIGO_IS_ANSWER_REUSE"] != "0"
    }

    /// Prefix-stable Information-Space injection is on by default.
    /// `SIMIGO_IS_CONTEXT_FREEZE=0` restores the per-turn fresh block, which is
    /// the diagnostic channel used to prove a `mode=cold` reading came from the
    /// drifting block rather than from something else.
    static var contextFreezingEnabled: Bool {
        ProcessInfo.processInfo.environment["SIMIGO_IS_CONTEXT_FREEZE"] != "0"
    }

    /// The gate itself lives in the loop so every entry point shares one
    /// fail-closed rule set and the rejection cases are testable without HTTP.
    /// This only adds the diagnostic off-switch and the handler's own shape.
    func reusableAnswer(for turn: InformationTurn) -> ReusableAnswer? {
        guard Self.isAnswerReuseEnabled,
            let reuse = turn.loop.reusableAnswer(
                sessionID: turn.sessionID, query: turn.query,
                identity: turn.identity)
        else { return nil }
        return ReusableAnswer(
            text: reuse.text, settlementID: reuse.settlementID,
            demandID: reuse.demandID, sourceStateID: reuse.sourceStateID)
    }

    /// Serving a reused answer is a read, not a new generation: no settlement is
    /// written (the original stays the single authoritative record of that text),
    /// and only the conversation line is stored so the next turn sees the same
    /// history the client sees. The reuse itself is a row, not just a trace line,
    /// so a later reader can verify the zero-model-call path from the database
    /// alone.
    func recordReusedAnswer(_ reuse: ReusableAnswer, turn: InformationTurn) {
        try? turn.db.commitChatTurn(
            sessionID: turn.sessionID, userMessageID: turn.userMessageID,
            assistantText: reuse.text, model: modelId, createdAt: Date(),
            eligibility: turn.eligibility)
        let demandID = turn.resolution.demandID.isEmpty
            ? reuse.demandID : turn.resolution.demandID
        _ = try? turn.db.recordInformationReuse(
            sourceSettlementID: reuse.settlementID,
            sourceStateID: reuse.sourceStateID,
            demandID: demandID,
            sessionID: turn.sessionID,
            query: turn.query)
        RuntimeTraceLogger.shared.trace(
            "[IS_REUSE] settlement=\(reuse.settlementID) demand=\(demandID) "
                + "state=\(reuse.sourceStateID) model_calls=0")
    }

    /// The wire shape a stream client expects for a reused answer: one content
    /// chunk, one stop chunk, `[DONE]`. Most OpenAI-compatible agents stream by
    /// default, so a short-circuit that only existed on the non-streaming path
    /// would leave the zero-model-call behaviour invisible to them.
    private func serveReusedAnswerStream(
        _ reuse: ReusableAnswer,
        context: ConnectionContext
    ) -> Bool {
        var headers = corsHeaders()
        headers["Content-Type"] = "text/event-stream; charset=utf-8"
        headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        headers["X-Accel-Buffering"] = "no"
        headers["Connection"] = "keep-alive"
        headers["X-Request-Id"] = context.requestId
        if let clientRequestId = context.clientRequestId {
            headers["X-Client-Request-Id"] = clientRequestId
        }
        guard
            sendImmediateStreamingHeaders(
                status: 200, headers: headers, context: context)
        else { return false }

        let responseId = "chatcmpl-\(UUID().uuidString.lowercased())"
        let created = Int(Date().timeIntervalSince1970)

        sendImmediateSSEChunk(
            [
                "id": responseId,
                "object": "chat.completion.chunk",
                "created": created,
                "model": modelId,
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": reuse.text],
                    "finish_reason": NSNull(),
                ]],
                "simigo": [
                    "answer_reuse": true,
                    "model_calls": 0,
                    "settlement_id": reuse.settlementID,
                    "demand_id": reuse.demandID,
                    "source_state_id": reuse.sourceStateID,
                ],
            ],
            context: context)

        sendImmediateSSEChunk(
            [
                "id": responseId,
                "object": "chat.completion.chunk",
                "created": created,
                "model": modelId,
                "choices": [[
                    "index": 0,
                    "delta": [String: Any](),
                    "finish_reason": "stop",
                ]],
            ],
            context: context)

        sendImmediateSSERaw(
            Data("data: [DONE]\n\n".utf8), context: context, close: true)
        return true
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
            seed += "|\(role):\(object["content"]?.messageText ?? "")"
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

        // Same governance rule as the non-streaming path; only the wire form
        // differs. The row is written after the stream is accepted so a failed
        // header write cannot leave a reuse recorded for an answer nobody saw.
        if (tools ?? []).isEmpty, let turn = information.turn,
            let reuse = reusableAnswer(for: turn),
            serveReusedAnswerStream(reuse, context: context)
        {
            recordReusedAnswer(reuse, turn: turn)
            return
        }

        // W4/A: the verdict is taken AFTER IS injection and BEFORE the SSE head
        // or any model work. A refusal writes its 503 here and nothing else.
        if await rejectOnRequestBudget(
            messages: turnMessages,
            tools: tools,
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
            endpoint: "chat.completions"
        ) else {
            failureReason = "concurrency_rejected"
            return
        }
        defer {
            releaseGenerationAdmission(
                admissionTicket,
                endpoint: "chat.completions")
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

            let result = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                turnMessages,
                tools,
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
                    turn,
                    assistantText: streamedContent.value,
                    completion: result.completion,
                    producedToolCalls: hasToolCalls.value)
            }

            var terminalChunk: [String: Any] = [
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
                        : result.completion.finishReason
                ]]
            ]
            if let completionBlock = chatCompletionBlock(result.completion) {
                terminalChunk["simigo"] = completionBlock
            }

            sendImmediateSSEChunk(
                terminalChunk,
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
                self.terminateForClientGone(context)
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
                    self.terminateForClientGone(context)
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
                    self.terminateForClientGone(context)
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

        // Automatic governance, before any model work: a turn whose question was
        // already answered in this information scope is served from the
        // Information Space. Tool-calling turns never reuse — a settled text
        // cannot satisfy a tool-call contract. Placed after the fork so an
        // explicit branch request still takes effect on a reused turn.
        if (tools ?? []).isEmpty, let turn = information.turn,
            let reuse = reusableAnswer(for: turn)
        {
            recordReusedAnswer(reuse, turn: turn)
            sendJSON(
                [
                    "id": "chatcmpl-\(UUID().uuidString.lowercased())",
                    "object": "chat.completion",
                    "created": Int(Date().timeIntervalSince1970),
                    "model": modelId,
                    "choices": [[
                        "index": 0,
                        "message": ["role": "assistant", "content": reuse.text],
                        "finish_reason": "stop",
                    ]],
                    "simigo": [
                        "answer_reuse": true,
                        "model_calls": 0,
                        "settlement_id": reuse.settlementID,
                        "demand_id": reuse.demandID,
                        "source_state_id": reuse.sourceStateID,
                    ],
                ],
                status: 200,
                on: context.connection,
                context: context
            )
            return
        }

        // W4/A: same gate as the streaming path; a reused/tool turn already
        // returned above and never reaches it.
        if await rejectOnRequestBudget(
            messages: turnMessages,
            tools: tools,
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
            endpoint: "chat.completions"
        ) else {
            failureReason = "concurrency_rejected"
            return
        }
        defer {
            releaseGenerationAdmission(
                admissionTicket,
                endpoint: "chat.completions")
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

            let result = try await generateHandler(
                context.requestId,
                agentId,
                sessionId,
                logicalBranchId,
                turnMessages,
                tools,
                config,

                { [weak self, weak context] text in
                    if let self, let context {
                        self.stopDetachedOrphanIfContended(context)
                    }

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
                settleInformationTurn(
                    turn,
                    assistantText: content,
                    completion: result.completion,
                    producedToolCalls: !calls.isEmpty)
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

            var responseBody: [String: Any] = [
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
                            ? result.completion.finishReason
                            : "tool_calls"
                ]]
            ]
            if let completionBlock = chatCompletionBlock(result.completion) {
                responseBody["simigo"] = completionBlock
            }

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
                self.terminateForClientGone(context)
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
