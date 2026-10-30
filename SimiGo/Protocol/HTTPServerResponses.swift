import Foundation
import CryptoKit
import Network
import SimiGoRuntimeContract

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
            // 官方事件层级：文本 finalized 必须先于 part finalized，
            // output_text.done 不能被 response.completed 替代。
            events.append([
                "type": "response.output_text.done",
                "sequence_number": nextSequenceLocked(),
                "item_id": itemId,
                "output_index": outputIndex,
                "content_index": 0,
                "text": messageText
            ])

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

    /// Opt-in ES/IS continuation anchor (`previous_es_state_id`). When the
    /// field is absent this is (false, nil) and the dispatch path is the
    /// unchanged ordinary Responses continuation. Present-but-blank stays
    /// `esStateIDPresent == true` with a nil/empty value so the gate can
    /// fail closed instead of silently falling back.
    let esStateIDPresent: Bool
    let esStateID: String?

    /// Explicit post-generation settlement opt-in (`continuation_settle`).
    /// Absent/false leaves the dispatch path unchanged.
    let continuationSettle: Bool

    /// Raw `settlement_consumption` payload when the key is present. Presence is
    /// recorded separately from presence-of-nil so a malformed payload is a
    /// typed refusal, never a silent fallback to ordinary generation.
    let settlementConsumptionPresent: Bool
    let settlementConsumptionRaw: Any?

    /// C-scope managed-continuation fields (`recompute_policy`,
    /// `idempotency_key`, `consumer_es_state_id`, `root_ids`). Parsed on every
    /// request; `isInert` means the dispatch must stay on the pre-C path.
    let managed: ManagedContinuationFields
}


extension HTTPServer {
    /// ES/IS continuation admission gate for the Responses path. Returns
    /// the messages to generate with, or `nil` when an HTTP refusal has
    /// already been sent (the caller must return without generating).
    ///
    /// Continuation response contract v0.1 (structured `error_kind` /
    /// `reason_code` in the JSON body; see ContinuationSettlement.swift):
    ///
    /// * anchor absent, no settle flag  -> `parsed.canonicalMessages` unchanged.
    /// * anchor absent + settle flag    -> 400 SETTLEMENT_WITHOUT_ANCHOR, no
    ///   generation, no authority invoked.
    /// * present but empty / malformed  -> 422 INPUT_ADMISSION_REFUSED,
    ///   reason_code `invalid_anchor`, no generation.
    /// * settle asked, no settlement
    ///   authority wired               -> 503 SETTLEMENT_AUTHORITY_UNAVAILABLE,
    ///   fail closed BEFORE generation and before the admission call.
    /// * no admission authority wired   -> 503 ADMISSION_AUTHORITY_UNAVAILABLE,
    ///   no generation.
    /// * native IS admission refuses    -> 422 INPUT_ADMISSION_REFUSED,
    ///   reason_code `is_refusal`.
    /// * unknown admission-stage error  -> 500 ADMISSION_ENGINE_ERROR (never 422).
    /// * admission verifies             -> recovered IS value feeds the
    ///   continuation (appended as the generation input).
    func continuationGate(
        parsed: ResponsesParsedRequest,
        context: ConnectionContext
    ) async -> [JSONValue]? {
        guard parsed.esStateIDPresent else {
            if parsed.continuationSettle {
                sendTerminal(.settleWithoutAnchor, context: context)
                return nil
            }
            return parsed.canonicalMessages
        }
        guard let anchor = parsed.esStateID, !anchor.isEmpty else {
            sendTerminal(
                ContinuationAdmissionFailure.invalidAnchor.terminal,
                context: context
            )
            return nil
        }
        // Fail closed before ANY authority work: a settle request whose
        // settlement authority is missing must not produce a generation that
        // can never be settled.
        if parsed.continuationSettle, continuationSettlement == nil {
            sendTerminal(.settlementAuthorityUnavailable, context: context)
            return nil
        }
        guard let admission = continuationAdmission else {
            sendTerminal(.admissionAuthorityUnavailable, context: context)
            return nil
        }
        do {
            let outcome = try await admission(anchor)
            // Part 2 wiring: THIS request executes under a fresh child ES, and
            // the admission's verified bindings travel with it. Both are pinned
            // on the per-request context BEFORE generation, so generation, the
            // settlement attribution and the returned child id are the same
            // identity — not a decoration added after the fact.
            let childESStateID = "es-" + UUID().uuidString.lowercased()
            context.setContinuationBinding(
                ContinuationRequestBinding(
                    parentESStateID: anchor,
                    childESStateID: childESStateID,
                    verifiedBindings: outcome.verifiedBindings))
            // A-2: the IS settlement is the PRE-AUTHORITY for KV reuse on this
            // continuation. The digests verified by admission travel to the child
            // ES; the pool bind site re-checks them against the representation it
            // is about to consume. No KV binding in the settlement therefore means
            // NO authority to reuse KV state — the bind is refused and the turn
            // prefills cold. Requests without an ES anchor register nothing, so the
            // everyday path stays byte-identical to before A-2.
            ISKVBindAuthority.shared.register(
                esStateID: childESStateID,
                verdict: outcome.kvBindings.isEmpty
                    ? .unauthorized(reason: "no_settled_kv_binding")
                    : .authorized(outcome.kvBindings))
            RuntimeTraceLogger.shared.trace(
                "[PROTOCOL] continuation_admitted r=\(context.requestId)"
                + " parent=\(anchor) child=\(childESStateID)"
                + " bindings=\(outcome.verifiedBindings.count)"
                + " kvBindings=\(outcome.kvBindings.count)")
            return parsed.canonicalMessages + [
                JSONValue.object([
                    "role": .string("user"),
                    "content": .string(outcome.recoveredValue)
                ])
            ]
        } catch {
            sendTerminal(continuationAdmissionTerminal(for: error), context: context)
            return nil
        }
    }

    /// Write one structured continuation terminal (contract v0.1).
    func sendTerminal(_ terminal: ContinuationTerminal, context: ConnectionContext) {
        sendError(
            terminal.message,
            status: terminal.status,
            on: context.connection,
            context: context,
            errorKind: terminal.errorKind,
            reasonCode: terminal.reasonCode
        )
    }

    /// Post-generation settlement step (non-streaming Responses path).
    /// Runs the injected authority over the ACTUAL generated text; the native
    /// gate and the authoritative store stay the single settlement path.
    /// `.refused` means an error terminal was already written and the caller
    /// must return without emitting a completed response.
    func settlementStep(
        parsed: ResponsesParsedRequest,
        generatedText: String,
        context: ConnectionContext
    ) async -> ContinuationSettlementStep {
        guard parsed.continuationSettle else { return .notRequested }
        guard let handler = continuationSettlement else {
            sendTerminal(.settlementAuthorityUnavailable, context: context)
            return .refused
        }
        // Fail closed: settlement is only ever authorized by THIS request's own
        // successful admission. A missing binding (or one anchored elsewhere)
        // never falls back to `state.nextInput`.
        guard
            let binding = context.continuationBinding,
            let anchor = parsed.esStateID,
            !anchor.isEmpty,
            binding.parentESStateID == anchor
        else {
            sendTerminal(.settlementEngineError, context: context)
            return .refused
        }
        do {
            return .settled(
                try await handler(
                    ContinuationSettlementRequest(
                        generatedText: generatedText,
                        parentESStateID: binding.parentESStateID,
                        childESStateID: binding.childESStateID,
                        verifiedBindings: binding.verifiedBindings)))
        } catch {
            sendTerminal(continuationSettlementTerminal(for: error), context: context)
            return .refused
        }
    }

    // MARK: - Settlement consumption step (zero model calls)

    enum SettlementConsumptionDispatch {
        /// A typed terminal was already written; return without generating.
        case refused
        case consumed(SettlementConsumptionReceipt)
        case recompute(reason: String)
    }

    /// Parse the typed payload strictly, then drive the injected consumption
    /// authority. Nothing here calls the model; a refusal writes its terminal
    /// and the dispatch must return.
    func settlementConsumptionStep(
        parsed: ResponsesParsedRequest,
        context: ConnectionContext
    ) async -> SettlementConsumptionDispatch {
        let entry: SettlementConsumptionEntry
        do {
            guard let raw = parsed.settlementConsumptionRaw else {
                throw SettlementConsumptionEntry.ParseError.invalidField(
                    "settlement_consumption (must be an object)")
            }
            entry = try SettlementConsumptionEntry.parse(raw)
        } catch {
            sendTerminal(settlementConsumptionTerminal(for: error), context: context)
            return .refused
        }
        guard let handler = settlementConsumption else {
            sendTerminal(.consumptionAuthorityUnavailable, context: context)
            return .refused
        }
        do {
            switch try await handler(entry) {
            case .consumed(let receipt):
                return .consumed(receipt)
            case .recompute(let reason):
                return .recompute(reason: reason)
            }
        } catch {
            sendTerminal(settlementConsumptionTerminal(for: error), context: context)
            return .refused
        }
    }

    /// Build the completed Responses body for a zero-call consumption. The
    /// served text is the re-admitted settled value; `store` is false because
    /// this is NOT a generated turn and must not enter response history as if
    /// the model had produced it.
    func sendSettlementConsumptionResponse(
        _ receipt: SettlementConsumptionReceipt,
        parsed: ResponsesParsedRequest,
        json: [String: Any],
        context: ConnectionContext
    ) {
        let created = Int(Date().timeIntervalSince1970)
        var response = makeResponseObject(
            responseId: parsed.responseId,
            created: created,
            json: json,
            output: buildResponsesOutput(content: receipt.value, calls: []),
            usage: nil,
            completion: .complete)
        response["store"] = false
        response["settlement_consumption"] = [
            "outcome": "consumed",
            "consumption_id": receipt.consumptionID,
            "source_settlement_id": receipt.sourceSettlementID,
            "consumer_es_state_id": receipt.consumerESStateID,
            "consumer_settlement_id": receipt.consumerSettlementID,
            "demand_id": receipt.demandID,
            "canonical_digest": receipt.canonicalDigest,
            "model_calls": receipt.modelCalls,
            "reused_existing": receipt.reusedExisting,
            "derived_settlement": true,
            "contract": [
                "id": receipt.contractID,
                "demand_class": receipt.demandClass,
                "version": receipt.contractVersion,
                "extract": receipt.extractField,
            ],
        ]
        sendJSON(
            response,
            status: 200,
            on: context.connection,
            context: context)
    }

    // MARK: - Managed continuation step (C)

    enum ManagedContinuationPreflight {
        /// No C-scope field: the dispatch stays on the pre-C path.
        case inert
        /// A typed terminal was already written; return without generating.
        case refused
        case managed(policy: SimiGoRecomputePolicy, anchor: String)
    }

    enum ManagedContinuationDispatch {
        /// A typed terminal was already written; return without a body.
        case refused
        case completed(ManagedContinuationResult)
    }

    /// Request-shape and policy gate for the managed-continuation entry. It runs
    /// BEFORE any generation tracking or authority work, so a refused request
    /// never calls the model, never creates a snapshot and never settles.
    ///
    /// Validation order is fixed (interface design §D2): shape, then value
    /// legality, then mutual exclusion, then other request semantics.
    ///
    /// * no C-scope field                  -> `.inert`, pre-C path unchanged
    /// * unusable C-scope field            -> 422 INPUT_ADMISSION_REFUSED
    /// * unsupported / anchorless policy   -> 400 INVALID_REQUEST_ENTRY
    /// * policy + settlement_consumption   -> 400 recompute_policy_conflict
    /// * policy + continuation_settle      -> 422 (the managed commit settles)
    /// * policy + no usable anchor         -> 422 INPUT_ADMISSION_REFUSED
    func managedContinuationPreflight(
        parsed: ResponsesParsedRequest,
        context: ConnectionContext
    ) -> ManagedContinuationPreflight {
        // Shape first: a C-scope field that cannot be used is refused even when
        // no policy arrived, so a typo never hides behind an inert request.
        if let shapeError = parsed.managed.shapeError {
            sendTerminal(
                ManagedContinuationFailure.invalidRequest(shapeError).terminal,
                context: context)
            return .refused
        }
        guard parsed.managed.policyPresent else {
            guard parsed.managed.hasCScopeFields else { return .inert }
            sendTerminal(
                ManagedContinuationFailure.invalidRequest(
                    "\(SimiGoRecomputePolicy.requestKey) (required with idempotency_key, consumer_es_state_id or root_ids)"
                ).terminal,
                context: context)
            return .refused
        }
        let policy: SimiGoRecomputePolicy
        do {
            policy = try SimiGoRecomputePolicy.resolve(
                managedAnchorPresent: parsed.esStateIDPresent,
                settlementConsumptionPresent: parsed.settlementConsumptionPresent,
                raw: parsed.managed.policyRaw)
        } catch {
            sendTerminal(managedContinuationTerminal(for: error), context: context)
            return .refused
        }
        // The managed commit owns its settlement; a second legacy settle request
        // would double-settle the same turn.
        if parsed.continuationSettle {
            sendTerminal(
                ManagedContinuationFailure.invalidRequest(
                    "continuation_settle (managed continuation settles its own commit)"
                ).terminal,
                context: context)
            return .refused
        }
        guard let anchor = parsed.esStateID, !anchor.isEmpty else {
            sendTerminal(
                ManagedContinuationFailure.refused(
                    SimiGoManagedRefusal.Refusal(
                        cause: .invalidAnchor, origin: .request, phase: .pre)
                ).terminal,
                context: context)
            return .refused
        }
        return .managed(policy: policy, anchor: anchor)
    }

    /// Drive the injected managed pipeline (P1 → S → G → P2) for one request.
    /// The handler owns the DB and the model; this layer only reports.
    func managedContinuationStep(
        parsed: ResponsesParsedRequest,
        policy: SimiGoRecomputePolicy,
        anchor: String,
        context: ConnectionContext
    ) async -> ManagedContinuationDispatch {
        guard let handler = managedContinuation else {
            sendTerminal(
                ManagedContinuationFailure.unavailable.terminal,
                context: context)
            return .refused
        }
        do {
            let result = try await handler(
                ManagedContinuationRequest(
                    requestId: context.requestId,
                    agentId: parsed.agentId,
                    sessionId: parsed.sessionId,
                    logicalBranchId: parsed.logicalBranchId,
                    anchorESStateID: anchor,
                    policy: policy,
                    idempotencyKey: parsed.managed.idempotencyKey,
                    consumerESStateID: parsed.managed.consumerESStateID,
                    rootIDs: parsed.managed.rootIDs,
                    messages: parsed.canonicalMessages,
                    tools: parsed.tools,
                    config: parsed.config))
            return .completed(result)
        } catch {
            sendTerminal(managedContinuationTerminal(for: error), context: context)
            return .refused
        }
    }

    /// Emit the completed Responses body for a committed or replayed managed
    /// execution. `replayable` stays JSON null unless the commit attested it.
    func sendManagedContinuationResponse(
        _ result: ManagedContinuationResult,
        policy: SimiGoRecomputePolicy,
        anchor: String,
        parsed: ResponsesParsedRequest,
        json: [String: Any],
        keepalive: NonStreamingKeepalive,
        context: ConnectionContext
    ) {
        let created = Int(Date().timeIntervalSince1970)
        let output = buildResponsesOutput(
            content: result.content,
            calls: result.toolCalls)
        var response = makeResponseObject(
            responseId: parsed.responseId,
            created: created,
            json: json,
            output: output,
            usage: result.usage,
            completion: .complete)
        response["managed_continuation"] = managedContinuationPayload(
            result, policy: policy, anchor: anchor)
        // A replay produced no new turn, so it must not enter response history
        // as if the model had generated it again.
        let shouldStore = shouldStoreResponse(json) && !result.reusedExecution
        response["store"] = shouldStore
        if shouldStore {
            storeResponse(
                responseId: parsed.responseId,
                agentId: parsed.agentId,
                sessionId: parsed.sessionId,
                logicalBranchId: parsed.logicalBranchId,
                preambleMessages: parsed.preambleMessages,
                historyMessages: appendParentHistory(
                    parent: parsed.parent,
                    currentHistory: appendResponsesAssistantOutput(
                        historyMessages: parsed.currentHistoryMessages,
                        content: result.content,
                        calls: result.toolCalls)),
                output: output,
                response: response)
        }
        if keepalive.committed {
            sendDeferredJSONTerminal(
                response,
                context: context
            )
        } else {
            sendJSON(
                response,
                status: 200,
                on: context.connection,
                context: context)
        }
    }

    func managedContinuationPayload(
        _ result: ManagedContinuationResult,
        policy: SimiGoRecomputePolicy,
        anchor: String
    ) -> [String: Any] {
        [
            "outcome": result.reusedExecution
                ? "replayed"
                : (result.recomputed ? "recomputed" : "committed"),
            "execution_id": result.executionID,
            "es_state_id": result.childESStateID,
            "parent_es_state_id": anchor,
            "settlement_id": result.settlementID,
            "declared_snapshot_id": result.declaredSnapshotID,
            "final_snapshot_id": result.finalSnapshotID,
            "idempotency_fingerprint": result.fingerprint,
            "model_calls": result.modelCalls,
            "settlements_written": result.settlementsWritten,
            "replayable": result.replayable.map { $0 as Any } ?? NSNull(),
            "recomputed": result.recomputed,
            "reused_execution": result.reusedExecution,
            "recompute_policy": policy.rawValue,
        ]
    }

    /// Slice 8 Part 2: make the admitted child ES the EXECUTION/CACHE identity of
    /// THIS generation. The runtime keys its session (and therefore its KV cache
    /// and checkpoints) by (agent, session, branch), so the child ES becomes that
    /// branch, forked from the request's branch to carry the parent's KV lineage.
    ///
    /// A fork that cannot run in this process (e.g. no live parent session after
    /// a restart) degrades to a COLD child branch: the request messages are
    /// replayed, so correctness is preserved, and the degradation is traced
    /// instead of being claimed as a warm reuse. Non-continuation requests keep
    /// the client's branch unchanged.
    func continuationExecutionBranch(
        parsed: ResponsesParsedRequest,
        context: ConnectionContext
    ) async -> String {
        // Only a continuation that will SETTLE gets a child ES identity: that
        // identity is created by the settlement commit. An admission-only
        // continuation settles nothing, so inventing a branch for it would
        // strand KV/checkpoints under an id no ES row will ever name.
        guard parsed.continuationSettle, let binding = context.continuationBinding else {
            return parsed.logicalBranchId
        }
        let source = parsed.logicalBranchId
        guard source != binding.childESStateID else { return source }
        do {
            _ = try await forkBranchHandler(
                parsed.agentId,
                parsed.sessionId,
                source,
                binding.childESStateID
            )
        } catch {
            RuntimeTraceLogger.shared.trace(
                "[PROTOCOL] continuation_branch_cold child=\(binding.childESStateID)"
                + " from=\(source) err=\(error.localizedDescription)")
        }
        RuntimeTraceLogger.shared.trace(
            "[PROTOCOL] continuation_branch child=\(binding.childESStateID) from=\(source)")
        return binding.childESStateID
    }

    /// Success payload merged into the completed response body.
    func settlementPayload(_ outcome: ContinuationSettlementOutcome) -> [String: Any] {
        [
            "settlement_id": outcome.settlementID,
            "identity_binding_published": outcome.identityBindingPublished,
            // Child ES identity: the settlement belongs to this state, and it is
            // the anchor a subsequent continuation must pass as
            // `previous_es_state_id`.
            "child_es_state_id": outcome.childESStateID
        ]
    }

    // MARK: - Responses information turn (ES demand → IS → settlement)

    static func lastUserText(_ messages: [JSONValue]) -> String? {
        messages.reversed().first {
            $0.object?["role"]?.string == "user"
        }?.object?["content"]?.messageText
    }

    /// A tool-continuation turn must not be short-circuited by an answer settled
    /// for the user message that led into it. `currentInputMessages` is in chat
    /// form, where a Responses `function_call_output` item arrives as `role:
    /// "tool"`; only the tail after the last user message counts, so a long
    /// session that used tools earlier still reuses ordinary repeats.
    static func isToolContinuation(_ parsed: ResponsesParsedRequest) -> Bool {
        let items = parsed.currentInputMessages
        let lastUser = items.lastIndex { $0.object?["role"]?.string == "user" }
        let tail = lastUser.map { items[($0 + 1)...] } ?? items[...]
        if tail.contains(where: { $0.object?["role"]?.string == "tool" }) {
            return true
        }
        return (parsed.parent?.output ?? []).contains {
            ($0["type"] as? String) == "function_call"
        }
    }

    /// IS grouping key for a Responses conversation. An explicit session or a
    /// Codex thread is the client's declared conversation; without one the
    /// execution session is request-scoped (a new id every turn), so the key is
    /// derived from the opening messages instead. This never changes the
    /// execution session feeding the runtime.
    func responsesInformationScope(
        parsed: ResponsesParsedRequest,
        json: [String: Any],
        headers: [String: String]
    ) -> String {
        if let explicit = resolveExplicitSession(from: json, headers: headers) {
            return explicit
        }
        if let thread = resolveThreadId(from: json, headers: headers) {
            return "codex-thread:\(thread)"
        }
        return Self.informationScope(
            agentId: parsed.agentId, messages: parsed.canonicalMessages)
    }

    /// Settle a Responses turn into ES/IS. When the continuation path already
    /// committed the authoritative settlement for this turn, only the demand
    /// advancement is still missing: it is linked to that exact settlement row
    /// instead of creating a second one.
    ///
    /// `completion` is the engine's verdict for THIS turn. A turn that did not
    /// finish stays in the conversation but is never registered as a settled
    /// result, so an unfinished answer can never be consumed or reused later.
    func settleResponsesInformationTurn(
        _ turn: InformationTurn,
        assistantText: String,
        settlementID: String?,
        stateID: String?,
        completion: GenerationCompletion
    ) {
        let text = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? turn.db.commitChatTurn(
            sessionID: turn.sessionID, userMessageID: turn.userMessageID,
            assistantText: text, model: modelId, createdAt: Date(),
            eligibility: turn.eligibility)
        guard turn.eligibility == .ordinary else {
            RuntimeTraceLogger.shared.trace(
                "[SETTLE_SKIP] wire=responses reason=internal_operation "
                    + "session=\(turn.sessionID) settlement_written=0")
            return
        }
        guard completion.isSettleable else {
            RuntimeTraceLogger.shared.trace(
                "[SETTLE_SKIP] wire=responses completion=\(completion.wireName) "
                    + "session=\(turn.sessionID) settlement_written=0")
            return
        }

        if let settlementID {
            guard !turn.resolution.demandID.isEmpty,
                !turn.resolution.retrievalSettlementID.isEmpty
            else { return }
            let result = (try? turn.db.settlementReceipt(settlementID))?.payload
                ?? Data(text.utf8)
            _ = try? turn.db.recordInformationAdvancement(.init(
                demandID: turn.resolution.demandID,
                stateID: stateID ?? turn.resolution.stateID ?? "",
                settlementID: settlementID,
                retrievalSettlementID: turn.resolution.retrievalSettlementID,
                actions: ["responses.completion"],
                result: result))
            if let stateID {
                try? turn.db.linkChatSession(
                    sessionID: turn.sessionID, stateID: stateID,
                    modelIdentity: turn.modelIdentity)
            }
            // The continuation settlement is authoritative but was produced
            // before this handler could name its demand: distill it now so a
            // later demand can reuse the conclusion.
            _ = try? turn.db.recordSettlementSummary(
                settlementID: settlementID, sessionID: turn.sessionID,
                query: turn.query)
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
            actions: ["responses.completion"])
    }

    // MARK: - Automatic IS answer reuse (zero model call)

    /// The wire block for a served answer that was READ from a settled result
    /// rather than generated. `model_calls: 0` describes this turn; the source
    /// settlement stays the only authoritative record of that text, so a reuse
    /// writes no settlement of its own.
    func answerReuseBlock(_ reuse: ReusableAnswer) -> [String: Any] {
        [
            "answer_reuse": true,
            "model_calls": 0,
            "settlement_id": reuse.settlementID,
            "demand_id": reuse.demandID,
            "source_state_id": reuse.sourceStateID,
        ]
    }

    /// A reused answer is protocol history for this conversation, so it is
    /// stored when the client asked for storage — a `previous_response_id`
    /// chain that continues from it would otherwise 400. The stored body keeps
    /// the `simigo` block, so the reuse is never presented as a generation.
    func storeReusedResponsesAnswer(
        _ reuse: ReusableAnswer,
        parsed: ResponsesParsedRequest,
        json: [String: Any],
        output: [[String: Any]],
        response: [String: Any]
    ) {
        guard shouldStoreResponse(json) else { return }
        storeResponse(
            responseId: parsed.responseId,
            agentId: parsed.agentId,
            sessionId: parsed.sessionId,
            logicalBranchId: parsed.logicalBranchId,
            preambleMessages: parsed.preambleMessages,
            historyMessages: appendParentHistory(
                parent: parsed.parent,
                currentHistory: appendResponsesAssistantOutput(
                    historyMessages: parsed.currentHistoryMessages,
                    content: reuse.text, calls: [])),
            output: output,
            response: response)
    }

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

        // C-scope managed continuation. Inert (no C-scope field) leaves this
        // path byte-identical; a refused request writes its typed terminal and
        // never generates, stores or settles anything.
        var managedPolicy: SimiGoRecomputePolicy?
        var managedAnchor: String?
        switch managedContinuationPreflight(parsed: parsed, context: context) {
        case .refused:
            return
        case .inert:
            break
        case .managed(let policy, let anchor):
            managedPolicy = policy
            managedAnchor = anchor
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
            endpoint: "responses"
        ) else {
            failureReason = "concurrency_rejected"
            return
        }
        defer {
            releaseGenerationAdmission(
                admissionTicket,
                endpoint: "responses")
        }

        guard context.markGenerationStarted() else {
            return
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
            context: context,
            stream: false
        )

        await context.registerLifecycle()

        // Explicit zero-call consumption opt-in. Absent leaves this path
        // byte-identical; a refusal returns with the typed terminal already
        // written and NOTHING generated.
        var consumptionNote: [String: Any]?
        if parsed.settlementConsumptionPresent {
            switch await settlementConsumptionStep(parsed: parsed, context: context) {
            case .refused:
                failureReason = "settlement_consumption_refused"
                return
            case .consumed(let receipt):
                sendSettlementConsumptionResponse(
                    receipt,
                    parsed: parsed,
                    json: json,
                    context: context
                )
                isSuccess = true
                return
            case .recompute(let reason):
                consumptionNote = [
                    "outcome": "recompute",
                    "reason": reason,
                ]
            }
        }

        // 非流式长静默窗口保活（2026-10-16；机制与实测档案见
        // startNonStreamingKeepalive，三个非流式 handler 共用）。
        let keepalive = startNonStreamingKeepalive(
            context: context
        )
        defer { keepalive.settle() }

        // The managed pipeline owns P1 → S → G → P2 for this request, including
        // the model call and the commit. It returns before the ordinary
        // generation path, which stays unreachable for C-scope requests.
        if let managedPolicy, let managedAnchor {
            switch await managedContinuationStep(
                parsed: parsed,
                policy: managedPolicy,
                anchor: managedAnchor,
                context: context
            ) {
            case .refused:
                failureReason = "managed_continuation_refused"
                return
            case .completed(let result):
                sendManagedContinuationResponse(
                    result,
                    policy: managedPolicy,
                    anchor: managedAnchor,
                    parsed: parsed,
                    json: json,
                    keepalive: keepalive,
                    context: context)
                isSuccess = true
                return
            }
        }

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

            guard let continuationMessages = await continuationGate(
                parsed: parsed,
                context: context
            ) else {
                return
            }

            // ES demand before generation: the demand is resolved against the
            // settled IS (physical index + stored chat) and the verified
            // context fragment is prepended; the SAME turn object later
            // settles the produced result and advances that demand.
            let information = prepareInformationTurn(
                json: json,
                headers: headers,
                agentId: parsed.agentId,
                messages: continuationMessages,
                sessionID: responsesInformationScope(
                    parsed: parsed, json: json, headers: headers),
                queryOverride: Self.lastUserText(parsed.currentInputMessages)
                    ?? Self.lastUserText(parsed.canonicalMessages))
            let turnMessages = information.messages

            // 「可以复用就不调用模型」: an exact repeat of an already-answered
            // question in this scope is served from the settled result. Explicit
            // consumption is a different opt-in contract and always wins — a
            // requested recompute is never silently turned into a reuse.
            if consumptionNote == nil, !Self.isToolContinuation(parsed),
                let turn = information.turn, let reuse = reusableAnswer(for: turn) {
                recordReusedAnswer(reuse, turn: turn)
                let output = buildResponsesOutput(content: reuse.text, calls: [])
                var response = makeResponseObject(
                    responseId: parsed.responseId,
                    created: created,
                    json: json,
                    output: output,
                    usage: nil,
                    completion: .complete)
                response["simigo"] = answerReuseBlock(reuse)
                storeReusedResponsesAnswer(
                    reuse, parsed: parsed, json: json,
                    output: output, response: response)
                sendJSON(
                    response, status: 200, on: context.connection, context: context)
                isSuccess = true
                return
            }

            // W4/A: verdict after IS injection, before any model work.
            if await rejectOnRequestBudget(
                messages: turnMessages,
                tools: parsed.tools,
                config: parsed.config,
                agentId: parsed.agentId,
                sessionId: parsed.sessionId,
                logicalBranchId: parsed.logicalBranchId,
                headers: headers,
                context: context
            ) {
                failureReason = "prefill_budget_exceeded"
                return
            }

            // A verified continuation executes under its child ES identity.
            let executionBranchID = await continuationExecutionBranch(
                parsed: parsed,
                context: context
            )

            let result = try await generateHandler(
                context.requestId,
                parsed.agentId,
                parsed.sessionId,
                executionBranchID,
                turnMessages,
                parsed.tools,
                parsed.config,

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

            let content =
                fullContent.value

            // T-1: a turn that did not finish registers no settlement of any
            // kind — neither the requested continuation settlement nor the
            // Information-Space answer — so a half answer can never come back
            // later as a settled, reusable conclusion.
            let settlementOutcome: ContinuationSettlementOutcome?
            if !result.completion.isSettleable {
                settlementOutcome = nil
            } else {
                // Settlement runs over the actual generated text BEFORE the
                // completed response is assembled. A refusal here produces an
                // error terminal and no completed response, no partial settle.
                switch await settlementStep(
                    parsed: parsed,
                    generatedText: content,
                    context: context
                ) {
                case .notRequested:
                    settlementOutcome = nil
                case .refused:
                    return
                case .settled(let settled):
                    settlementOutcome = settled
                }
            }

            if let turn = information.turn {
                settleResponsesInformationTurn(
                    turn,
                    assistantText: content,
                    settlementID: settlementOutcome?.settlementID,
                    stateID: settlementOutcome?.childESStateID,
                    completion: result.completion)
            }

            let calls =
                toolCalls.value

            let output =
                buildResponsesOutput(
                    content: content,
                    calls: calls
                )

            var response =
                makeResponseObject(
                    responseId: parsed.responseId,
                    created: created,
                    json: json,
                    output: output,
                    usage: result.usage,
                    completion: result.completion
                )

            if let settlementOutcome {
                response["continuation_settlement"] = settlementPayload(settlementOutcome)
            }
            if let consumptionNote {
                // No reuse happened; the explicit recompute and its reason are
                // reported so a refusal can never be disguised as a hit.
                response["settlement_consumption"] = consumptionNote
            }

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

            if keepalive.committed {
                sendDeferredJSONTerminal(
                    response,
                    context: context
                )
            } else {
                sendJSON(
                    response,
                    status: 200,
                    on: context.connection,
                    context: context
                )
            }

            isSuccess = true

        } catch is CancellationError {
            // 取消契约：keepalive 头未提交时客户端仍连接必须给 HTTP
            // 终态，否则将无限等待。
            keepalive.settle()
            failureReason = context.cancellationFailureReason()
            guard !context.closed else {
                return
            }

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
            guard !context.closed else {
                return
            }

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
            endpoint: "responses"
        ) else {
            failureReason = "concurrency_rejected"
            return
        }
        defer {
            releaseGenerationAdmission(
                admissionTicket,
                endpoint: "responses")
        }

        guard context.markGenerationStarted() else {
            return
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
            context: context,
            stream: true
        )

        await context.registerLifecycle()

        // C-scope managed continuation is not available on the streaming path
        // in v1. Shape/policy refusals keep their precise terminal; a
        // well-formed C request is refused BEFORE the SSE 200 head, so a real
        // client never sees a 200 that carries a mid-stream refusal.
        switch managedContinuationPreflight(parsed: parsed, context: context) {
        case .refused:
            return
        case .inert:
            break
        case .managed:
            sendTerminal(
                ManagedContinuationFailure.unsupportedOnStream.terminal,
                context: context)
            return
        }

        // Contract fix A: `continuation_settle` is an unsupported combination on
        // the streaming Responses path. Reject it at the TRANSPORT level BEFORE
        // committing the SSE `200 text/event-stream` header, so a real client
        // observes HTTP 501 (never a 200 that carries a mid-stream 501). This
        // refuses before any generation and before any settlement authority runs.
        if parsed.continuationSettle {
            sendTerminal(.settlementUnsupportedOnStream, context: context)
            return
        }
        // Consumption is a zero-call, completed-response operation; the SSE
        // contract has no semantics for it. Refuse BEFORE the 200 stream head.
        if parsed.settlementConsumptionPresent {
            sendTerminal(.consumptionUnsupportedOnStream, context: context)
            return
        }

        // W4/A Q2: on the ordinary path the budget verdict must exist BEFORE
        // the SSE 200 head, so the continuation gate, the IS-injected messages
        // and the verdict are all taken here; the do-block reuses them instead
        // of repeating the work. An ES-anchored continuation keeps its
        // byte-identical order (its admission terminal contract depends on it)
        // and the gate records that it stayed inactive there.
        var hoistedContinuationMessages: [JSONValue]?
        var hoistedInformation: (messages: [JSONValue], turn: InformationTurn?)?
        if !parsed.esStateIDPresent {
            guard let gatedMessages = await continuationGate(
                parsed: parsed,
                context: context
            ) else {
                return
            }
            let information = prepareInformationTurn(
                json: json,
                headers: headers,
                agentId: parsed.agentId,
                messages: gatedMessages,
                sessionID: responsesInformationScope(
                    parsed: parsed, json: json, headers: headers),
                queryOverride: Self.lastUserText(parsed.currentInputMessages)
                    ?? Self.lastUserText(parsed.canonicalMessages))
            hoistedContinuationMessages = gatedMessages
            hoistedInformation = (information.messages, information.turn)
            // A settled answer never reaches the model, so it is never refused
            // by a prefill budget (「可以复用就不调用模型」 wins).
            let reuseWouldServe =
                !Self.isToolContinuation(parsed)
                && information.turn.flatMap { reusableAnswer(for: $0) } != nil
            if !reuseWouldServe,
                await rejectOnRequestBudget(
                    messages: information.messages,
                    tools: parsed.tools,
                    config: parsed.config,
                    agentId: parsed.agentId,
                    sessionId: parsed.sessionId,
                    logicalBranchId: parsed.logicalBranchId,
                    headers: headers,
                    context: context
                )
            {
                failureReason = "prefill_budget_exceeded"
                return
            }
        } else {
            noteBudgetGateInactive(reason: "es_anchored_stream", context: context)
        }

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

        // 冷预填充静默窗口保活；handler 收口时取消。
        // makeEvent：静默期重发 response.in_progress（协议内真实事件，
        // sequence 单调递增，快照固定为请求态）——前端看门狗按事件静默计数。
        let progressResponseData = try? JSONSerialization.data(
            withJSONObject: makeInProgressResponse(
                responseId: parsed.responseId,
                created: created,
                json: json
            )
        )
        let heartbeat = startSSEHeartbeat(for: context, makeEvent: {
            guard
                let responseData = progressResponseData,
                !responseData.isEmpty
            else {
                return nil
            }
            let event =
                "{\"type\":\"response.in_progress\",\"sequence_number\":"
                + String(streamState.nextSequence())
                + ",\"response\":"
                + String(decoding: responseData, as: UTF8.self)
                + "}"
            return Data("data: ".utf8) + Data(event.utf8) + Data("\n\n".utf8)
        })
        defer { heartbeat.cancel() }

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

            let continuationMessages: [JSONValue]
            if let hoistedContinuationMessages {
                continuationMessages = hoistedContinuationMessages
            } else {
                guard let gatedMessages = await continuationGate(
                    parsed: parsed,
                    context: context
                ) else {
                    return
                }
                continuationMessages = gatedMessages
            }

            // Streaming cannot hold a completed response back until settlement
            // is known: an explicit settle request on the stream path fails
            // closed BEFORE generation instead of producing unsettled output.
            if parsed.continuationSettle {
                sendTerminal(.settlementUnsupportedOnStream, context: context)
                return
            }

            // ES demand before generation (see the non-streaming path). The
            // ordinary path already prepared it above, before the SSE head.
            let information: (messages: [JSONValue], turn: InformationTurn?)
            if let hoistedInformation {
                information = hoistedInformation
            } else {
                information = prepareInformationTurn(
                    json: json,
                    headers: headers,
                    agentId: parsed.agentId,
                    messages: continuationMessages,
                    sessionID: responsesInformationScope(
                        parsed: parsed, json: json, headers: headers),
                    queryOverride: Self.lastUserText(parsed.currentInputMessages)
                        ?? Self.lastUserText(parsed.canonicalMessages))
            }
            let turnMessages = information.messages

            // Most Agents stream by default, so the zero-call reuse has to exist
            // on this wire too: the client receives the same event sequence a
            // generated turn produces, carrying the settled text and a `simigo`
            // block that names the source settlement (see the non-streaming path
            // for the gate's contract).
            if !Self.isToolContinuation(parsed),
                let turn = information.turn, let reuse = reusableAnswer(for: turn) {
                recordReusedAnswer(reuse, turn: turn)
                var events = streamState.appendAssistantText(reuse.text)
                events.append(contentsOf: streamState.closeAssistantMessage())
                let output = streamState.snapshotOutputItems()
                var response = makeResponseObject(
                    responseId: parsed.responseId,
                    created: created,
                    json: json,
                    output: output,
                    usage: nil,
                    completion: .complete)
                response["simigo"] = answerReuseBlock(reuse)
                storeReusedResponsesAnswer(
                    reuse, parsed: parsed, json: json,
                    output: output, response: response)
                events.append([
                    "type": "response.completed",
                    "sequence_number": streamState.nextSequence(),
                    "response": response
                ])
                enqueueResponsesEvents(
                    context: context,
                    events: events,
                    close: true
                )
                isSuccess = true
                return
            }

            // A verified continuation executes under its child ES identity.
            let executionBranchID = await continuationExecutionBranch(
                parsed: parsed,
                context: context
            )

            let result = try await generateHandler(
                context.requestId,
                parsed.agentId,
                parsed.sessionId,
                executionBranchID,
                turnMessages,
                parsed.tools,
                parsed.config,

                { [weak self, weak context] text in
                    if let self, let context {
                        self.stopDetachedOrphanIfContended(context)
                    }

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

            // 先关闭消息（output_item.done + 填充 content），再取快照——
            // 否则 response.completed 的 output 携带 in_progress/content=[] 的过期状态。
            var completionEvents =
                streamState.closeAssistantMessage()

            let finalOutput =
                streamState.snapshotOutputItems()

            let finalContent =
                extractAssistantText(from: finalOutput)

            if let turn = information.turn {
                settleResponsesInformationTurn(
                    turn,
                    assistantText: finalContent,
                    settlementID: nil,
                    stateID: nil,
                    completion: result.completion)
            }

            let finalCalls =
                toolCalls.value

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
                    response: makeResponseObject(
                        responseId: parsed.responseId,
                        created: created,
                        json: json,
                        output: finalOutput,
                        usage: result.usage,
                        completion: result.completion
                    )
                )
            }

            // An unfinished turn ends the event chain with the incomplete
            // terminal, so a stream client cannot read it as a finished answer.
            completionEvents.append([
                "type": result.completion == .complete
                    ? "response.completed" : "response.incomplete",
                "sequence_number":
                    streamState.nextSequence(),
                "response": makeResponseObject(
                    responseId: parsed.responseId,
                    created: created,
                    json: json,
                    output: finalOutput,
                    usage: result.usage,
                    completion: result.completion
                )
            ])

            enqueueResponsesEvents(
                context: context,
                events: completionEvents,
                close: true
            )

        } catch is CancellationError {
            // 取消契约：
            // 客户端已断连（closed）→ 静默；客户端仍连接 →
            // 必须送达 terminal event 并关闭流，
            // 否则客户端会永远等待本轮 response。
            failureReason = context.cancellationFailureReason()
            guard !context.closed else {
                return
            }

            let cancelledResponse: [String: Any] = [
                "id": parsed.responseId,
                "object": "response",
                "status": "failed",
                "error": [
                    "message":
                        "Generation cancelled",
                    "type":
                        "cancelled"
                ]
            ]

            let event: [String: Any] = [
                "type": "response.failed",
                "sequence_number":
                    streamState.nextSequence(),
                "response": cancelledResponse
            ]

            enqueueResponsesEvents(
                context: context,
                events: [event],
                close: true
            )
        } catch NativeMLXValidationError.contextDemandExceeded(let demand, let budget) {
            // CONTEXT SAFETY：SSE 头已发出，以可识别错误类型收尾，
            // 客户端（Codex 等）据此压缩上下文重试而非无限等待。
            failureReason = "context_demand_exceeded: \(demand)>\(budget)"
            guard !context.closed else {
                return
            }

            let failedResponse: [String: Any] = [
                "id": parsed.responseId,
                "object": "response",
                "status": "failed",
                "error": [
                    "message":
                        "context_length_exceeded: prompt content \(demand) tokens exceeds context budget \(budget); compact the conversation and retry",
                    "type":
                        "context_length_exceeded"
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
        } catch {
            failureReason = "model_execution_error: \(error.localizedDescription)"
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

        let esAnchorPresent = json.keys.contains("previous_es_state_id")
        let esAnchorValue = (json["previous_es_state_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let esSettleRequested = (json["continuation_settle"] as? Bool) ?? false

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
            parent: parent,
            esStateIDPresent: esAnchorPresent,
            esStateID: esAnchorValue,
            continuationSettle: esSettleRequested,
            settlementConsumptionPresent: json.keys.contains("settlement_consumption"),
            settlementConsumptionRaw: json["settlement_consumption"],
            managed: ManagedContinuationFields.parse(json)
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

            // 直接在 JSONValue 层读 role（此前每条消息走一次
            // JSONValue → JSONEncoder → JSONSerialization 全量往返，只为取
            // 一个字段）。非 object 消息与旧 jsonValueDictionary 返回 nil
            // 的分支语义一致：进 history。
            guard
                case .object(let object) = message
            else {
                history.append(message)
                enteredHistory = true
                continue
            }

            let role =
                object["role"]?.string

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

    /// Build the Responses body for a finished turn. `completion` is the
    /// engine's own termination verdict and decides the reported status: a
    /// turn that did not finish is `incomplete` with its reason, never
    /// `completed`. Text that was READ from a settlement (answer reuse,
    /// consumption, managed replay) carries `.complete` because the gate that
    /// served it only ever admits settled, complete conclusions.
    func makeResponseObject(
        responseId: String,
        created: Int,
        json: [String: Any],
        output: [[String: Any]],
        usage: GenerationUsageReport? = nil,
        completion: GenerationCompletion
    ) -> [String: Any] {
        // P1-2：usage 来自真实 token ledger（GenerateCompletionInfo 透传）；
        // 无报告时回退全 0（向后兼容）。
        let usagePayload: [String: Any] = [
            "input_tokens": usage?.inputTokens ?? 0,
            "input_tokens_details": [
                "cached_tokens": usage?.cachedPromptTokens ?? 0
            ],
            "output_tokens": usage?.outputTokens ?? 0,
            "output_tokens_details": [
                "reasoning_tokens": 0
            ],
            "total_tokens": usage.map { $0.totalTokens } ?? 0
        ]
        let incompleteDetails: Any = completion.incompleteReason
            .map { ["reason": $0] } ?? NSNull()

        return [
            "id": responseId,
            "object": "response",
            "created_at": created,
            "status": completion == .complete ? "completed" : "incomplete",
            "completed_at": created,
            "error": NSNull(),
            "incomplete_details": incompleteDetails,
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
            "usage": usagePayload,
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

            context.touchOutboundActivity()

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

                                self.terminateForClientGone(
                                    context
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
