import Foundation

/// Incremental turn reconstruction for one Qoder transcript file.
///
/// The accumulator sees only appended entries, so attribution is resolved
/// against the entries it has observed since the baseline. A new anchor closes
/// the previous turn; assistant messages are coalesced by `message.id` and
/// attributed through the parent chain when it reaches the open anchor, or by
/// file order (always flagged for review) when a compaction broke the chain.
public final class TurnAccumulator {
    public struct Context: Sendable, Equatable {
        public let projectID: String
        public let sessionID: String
        public let path: String
        public let isSubagent: Bool

        public init(projectID: String, sessionID: String, path: String, isSubagent: Bool) {
            self.projectID = projectID
            self.sessionID = sessionID
            self.path = path
            self.isSubagent = isSubagent
        }
    }

    /// Hard in-memory limits for one transcript accumulator. Tests can inject
    /// smaller values to exercise the fail-closed paths without huge fixtures.
    struct RetentionLimits: Sendable, Equatable {
        let maxRetainedNodes: Int
        let maxSeenAnchorIDs: Int
        let maxPendingMessages: Int
        let maxPendingTerminalTextBytes: Int

        init(
            maxRetainedNodes: Int = 100_000,
            maxSeenAnchorIDs: Int = 65_536,
            maxPendingMessages: Int = 256,
            maxPendingTerminalTextBytes: Int = 8 * 1024 * 1024
        ) {
            self.maxRetainedNodes = max(1, maxRetainedNodes)
            self.maxSeenAnchorIDs = max(1, maxSeenAnchorIDs)
            self.maxPendingMessages = max(1, maxPendingMessages)
            self.maxPendingTerminalTextBytes = max(1, maxPendingTerminalTextBytes)
        }

        static let production = RetentionLimits()
    }

    private enum NodeKind: Equatable {
        case humanPrompt
        case supervisionCallback
        case continuationPrompt
        case notificationPrompt
        case queuedCommand
        case compactSummary
        case toolResult
        case assistant
        case other

        var isAnchor: Bool {
            switch self {
            case .humanPrompt, .supervisionCallback, .continuationPrompt,
                .notificationPrompt, .queuedCommand:
                return true
            default:
                return false
            }
        }
    }

    private struct Node {
        let parent: String?
        let kind: NodeKind
        let anchorID: String?
        let line: Int64
    }

    private struct Anchor {
        let id: String
        let kind: AnchorKind
        let line: Int64
        let timestamp: String?
        let originKind: String?
        let promptRaw: String
        let promptText: String
        let promptRawDigest: String
        let promptDigest: String
        let injectedPrefixes: [String]
        let isSidechain: Bool
        let requestSetID: String?

        var summary: AnchorSummary {
            AnchorSummary(
                id: id, kind: kind, segmentLine: line, timestamp: timestamp,
                originKind: originKind, isSidechain: isSidechain)
        }
    }

    private struct Terminal {
        let line: Int64
        let timestamp: String?
        let stop: String?
        let text: String
        let digest: String
        let apiError: Bool
    }

    private struct Snapshot {
        let messageID: String
        let firstUUID: String
        let firstLine: Int64
        var lastLine: Int64
        var model: String?
        var isSidechain: Bool
        var lastTerminalLine: Int64?
        var latestTerminal: Terminal?
        var firstTerminalDigest: String?
        var hasConflictingTerminals: Bool
        var relation: AttributionRelation
    }

    private struct PendingTurn {
        let anchor: Anchor
        var messages: [String: Snapshot]
        var messageCount: Int
        var terminalCount: Int
        var lastLine: Int64
        var retainedTerminalTextBytes: Int
        var historyTruncated: Bool
        var interrupted: Bool
        var interruptLine: Int64?
    }

    private struct NodeOrderEntry {
        let id: String
        let line: Int64
    }

    private enum RelationResolution {
        case resolved(AttributionRelation)
        case late
        case beforeAnchor
    }

    private let context: Context
    private let retentionLimits: RetentionLimits
    private var nodes: [String: Node] = [:]
    private var nodeOrder: [NodeOrderEntry] = []
    private var nodeOrderHead = 0
    // Keep the first bounded window exactly. Once it fills, later anchors are
    // still parsed but their turns are closed as history-limit outcomes.
    private var seenAnchorIDs: Set<String> = []
    private var pending: PendingTurn?

    public init(context: Context) {
        self.context = context
        self.retentionLimits = .production
    }

    init(context: Context, retentionLimits: RetentionLimits) {
        self.context = context
        self.retentionLimits = retentionLimits
    }

    public var hasOpenTurn: Bool { pending != nil }

    var retainedNodeCountForTesting: Int { nodes.count }
    var retainedAnchorIDCountForTesting: Int { seenAnchorIDs.count }
    var retainedPendingMessageCountForTesting: Int { pending?.messages.count ?? 0 }
    var retainedPendingTerminalCountForTesting: Int {
        pending?.messages.values.reduce(0) { $0 + ($1.latestTerminal == nil ? 0 : 1) } ?? 0
    }
    var retainedPendingTerminalTextBytesForTesting: Int {
        pending?.retainedTerminalTextBytes ?? 0
    }
    var pendingHistoryTruncatedForTesting: Bool { pending?.historyTruncated ?? false }

    /// Segment line that opened the still-open turn. The tailer persists this
    /// as the replay point so a restart rebuilds the turn from the transcript.
    public var openAnchorSegmentLine: Int64? { pending?.anchor.line }

    public func ingest(
        _ entry: TranscriptEntry, segmentLine: Int64
    ) -> [CollectionEvent] {
        switch entry.type {
        case "assistant":
            return handleAssistant(entry, line: segmentLine)
        case "user":
            return handleUser(entry, line: segmentLine)
        case "attachment":
            return handleAttachment(entry, line: segmentLine)
        default:
            registerNode(entry, line: segmentLine, kind: .other, anchorID: nil)
            return []
        }
    }

    /// Close the open turn without waiting for a later anchor. The tailer does
    /// not call this on every poll: a turn is final only when a boundary says
    /// no later end_turn can still belong to it.
    public func flushCurrentTurn(
        boundary: FinalizationBoundary,
        into events: inout [CollectionEvent]
    ) {
        finalizePending(boundary: boundary, events: &events)
    }

    private func handleUser(
        _ entry: TranscriptEntry, line: Int64
    ) -> [CollectionEvent] {
        let classification = TranscriptClassifier.classifyUser(entry)
        let nodeKind: NodeKind
        switch classification.kind {
        case .humanPrompt: nodeKind = .humanPrompt
        case .continuationPrompt: nodeKind = .continuationPrompt
        case .notificationPrompt: nodeKind = .notificationPrompt
        case .supervisionCallback: nodeKind = .supervisionCallback
        case .compactSummary: nodeKind = .compactSummary
        case .toolResult: nodeKind = .toolResult
        default: nodeKind = .other
        }
        registerNode(entry, line: line, kind: nodeKind, anchorID: nil)

        var events: [CollectionEvent] = []
        switch classification.kind {
        case .humanPrompt:
            guard let id = entry.uuid else { break }
            let raw = entry.message?.text ?? ""
            beginAnchor(
                id: id, kind: .humanPrompt, line: line, timestamp: entry.timestamp,
                originKind: entry.originKind, promptRaw: raw,
                promptText: classification.strippedText,
                injectedPrefixes: classification.injectedPrefixes,
                isSidechain: entry.isSidechain, requestSetID: nil, events: &events)
        case .continuationPrompt:
            beginMetaAnchor(
                entry, id: entry.uuid, kind: .continuationPrompt, line: line,
                text: entry.message?.text ?? "", events: &events)
        case .notificationPrompt:
            beginMetaAnchor(
                entry, id: entry.uuid, kind: .notificationPrompt, line: line,
                text: entry.message?.text ?? "", events: &events)
        case .supervisionCallback:
            beginMetaAnchor(
                entry, id: entry.uuid, kind: .supervisionCallback, line: line,
                text: entry.message?.text ?? "", events: &events)
        case .compactSummary:
            // A compaction rewrites the model's context in the middle of a
            // turn: the answer that follows still belongs to this anchor, so
            // it is an attribution boundary (chain walk stops here), not a
            // finalization boundary. Matches extractor_v3's `compaction_boundary`.
            events.append(
                .compaction(
                    CompactionEvent(
                        path: context.path, sessionID: context.sessionID,
                        segmentLine: line, uuid: entry.uuid)))
        case .interruptMarker:
            // The marker records that the user cancelled; the turn still ends
            // at the next anchor so a late persisted answer is not orphaned.
            if pending != nil {
                pending?.interrupted = true
                pending?.interruptLine = line
            }
        default:
            break
        }
        return events
    }

    private func handleAttachment(
        _ entry: TranscriptEntry, line: Int64
    ) -> [CollectionEvent] {
        guard let attachment = entry.attachment,
            attachment.type == "queued_command",
            let sourceUUID = attachment.sourceUUID, !sourceUUID.isEmpty
        else {
            registerNode(entry, line: line, kind: .other, anchorID: nil)
            return []
        }
        registerNode(entry, line: line, kind: .queuedCommand, anchorID: sourceUUID)
        var events: [CollectionEvent] = []
        beginAnchor(
            id: sourceUUID, kind: .queuedCommand, line: line, timestamp: entry.timestamp,
            originKind: attachment.originKind ?? entry.originKind,
            promptRaw: attachment.promptText, promptText: attachment.promptText,
            injectedPrefixes: [], isSidechain: entry.isSidechain, requestSetID: nil,
            events: &events)
        return events
    }

    private func handleAssistant(
        _ entry: TranscriptEntry, line: Int64
    ) -> [CollectionEvent] {
        registerNode(entry, line: line, kind: .assistant, anchorID: nil)
        var events: [CollectionEvent] = []
        guard let message = entry.message, let messageID = message.id,
            let uuid = entry.uuid
        else { return events }
        guard var turn = pending else {
            if message.stopReason != nil || entry.isAPIMessageError {
                events.append(
                    .orphanAssistant(
                        OrphanAssistant(
                            path: context.path, sessionID: context.sessionID,
                            messageID: messageID, segmentLine: line,
                            reason: .noOpenTurn)))
            }
            return events
        }

        switch resolveRelation(firstUUID: uuid, firstLine: line, turn: turn) {
        case .late:
            events.append(
                .orphanAssistant(
                    OrphanAssistant(
                        path: context.path, sessionID: context.sessionID,
                        messageID: messageID, segmentLine: line,
                        reason: .lateForClosedTurn)))
            return events
        case .beforeAnchor:
            events.append(
                .orphanAssistant(
                    OrphanAssistant(
                        path: context.path, sessionID: context.sessionID,
                        messageID: messageID, segmentLine: line,
                        reason: .beforeCurrentAnchor)))
            return events
        case .resolved(let relation):
            turn.lastLine = max(turn.lastLine, line)
            let isTerminal =
                message.stopReason == "end_turn" || message.stopReason == "tool_use"
                || message.stopReason == "stop_sequence" || entry.isAPIMessageError
            var snapshot: Snapshot
            if let existing = turn.messages[messageID] {
                snapshot = existing
            } else {
                turn.messageCount += 1
                guard turn.messages.count < retentionLimits.maxPendingMessages else {
                    turn.historyTruncated = true
                    if isTerminal { turn.terminalCount += 1 }
                    pending = turn
                    return events
                }
                snapshot = Snapshot(
                    messageID: messageID, firstUUID: uuid, firstLine: line,
                    lastLine: line, model: message.model,
                    isSidechain: entry.isSidechain, lastTerminalLine: nil,
                    latestTerminal: nil, firstTerminalDigest: nil,
                    hasConflictingTerminals: false, relation: relation)
            }
            snapshot.lastLine = line
            snapshot.model = message.model ?? snapshot.model
            snapshot.isSidechain = snapshot.isSidechain || entry.isSidechain
            if isTerminal, snapshot.lastTerminalLine != line {
                let digest = SourceDigest.sha256Hex(message.text)
                if let firstDigest = snapshot.firstTerminalDigest {
                    if digest != firstDigest { snapshot.hasConflictingTerminals = true }
                } else {
                    snapshot.firstTerminalDigest = digest
                }

                let oldBytes = snapshot.latestTerminal?.text.utf8.count ?? 0
                let newBytes = message.text.utf8.count
                let nextBytes = turn.retainedTerminalTextBytes - oldBytes + newBytes
                if nextBytes <= retentionLimits.maxPendingTerminalTextBytes {
                    snapshot.latestTerminal = Terminal(
                        line: line, timestamp: entry.timestamp, stop: message.stopReason,
                        text: message.text, digest: digest,
                        apiError: entry.isAPIMessageError)
                    turn.retainedTerminalTextBytes = nextBytes
                } else {
                    // Keep only the digest/conflict evidence. Finalization below
                    // emits an explicit closure instead of an eligible answer.
                    turn.historyTruncated = true
                }
                snapshot.lastTerminalLine = line
                turn.terminalCount += 1
            }
            turn.messages[messageID] = snapshot
            pending = turn
        }
        return events
    }

    private func beginMetaAnchor(
        _ entry: TranscriptEntry, id: String?, kind: AnchorKind, line: Int64,
        text: String, events: inout [CollectionEvent]
    ) {
        guard let id else { return }
        beginAnchor(
            id: id, kind: kind, line: line, timestamp: entry.timestamp,
            originKind: entry.originKind, promptRaw: text, promptText: text,
            injectedPrefixes: [], isSidechain: entry.isSidechain,
            requestSetID: entry.requestSetID, events: &events)
    }

    private func beginAnchor(
        id: String, kind: AnchorKind, line: Int64, timestamp: String?,
        originKind: String?, promptRaw: String, promptText: String,
        injectedPrefixes: [String], isSidechain: Bool, requestSetID: String?,
        events: inout [CollectionEvent]
    ) {
        guard !seenAnchorIDs.contains(id) else { return }
        finalizePending(boundary: .nextAnchor, events: &events)
        pruneNodes(before: line)
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = Anchor(
            id: id, kind: kind, line: line, timestamp: timestamp,
            originKind: originKind, promptRaw: promptRaw, promptText: trimmedPrompt,
            promptRawDigest: SourceDigest.sha256Hex(promptRaw),
            promptDigest: SourceDigest.sha256Hex(trimmedPrompt),
            injectedPrefixes: injectedPrefixes, isSidechain: isSidechain,
            requestSetID: requestSetID)
        let canRememberAnchor = seenAnchorIDs.count < retentionLimits.maxSeenAnchorIDs
        pending = PendingTurn(
            anchor: anchor, messages: [:], messageCount: 0, terminalCount: 0,
            lastLine: line, retainedTerminalTextBytes: 0,
            historyTruncated: !canRememberAnchor,
            interrupted: false, interruptLine: nil)
        if canRememberAnchor { seenAnchorIDs.insert(id) }
        _ = events
    }

    private func registerNode(
        _ entry: TranscriptEntry, line: Int64, kind: NodeKind, anchorID: String?
    ) {
        guard let uuid = entry.uuid else { return }
        nodes[uuid] = Node(
            parent: entry.parentUUID, kind: kind, anchorID: anchorID, line: line)
        nodeOrder.append(NodeOrderEntry(id: uuid, line: line))
        enforceNodeLimit()
    }

    private func pruneNodes(before line: Int64) {
        let lookback = Int64(clamping: retentionLimits.maxRetainedNodes)
        let cutoff = line > lookback ? line - lookback : 0
        nodes = nodes.filter { _, node in node.line >= cutoff }
        rebuildNodeOrder()
    }

    private func enforceNodeLimit() {
        while nodes.count > retentionLimits.maxRetainedNodes {
            if nodeOrderHead >= nodeOrder.count {
                rebuildNodeOrder()
                if nodeOrder.isEmpty { return }
            }
            let candidate = nodeOrder[nodeOrderHead]
            nodeOrderHead += 1
            if nodes[candidate.id]?.line == candidate.line {
                nodes.removeValue(forKey: candidate.id)
            }
        }
        compactNodeOrderIfNeeded()
    }

    private func compactNodeOrderIfNeeded() {
        if nodeOrderHead > 0,
           nodeOrderHead >= 1_024 || nodeOrderHead * 2 >= nodeOrder.count {
            nodeOrder = Array(nodeOrder[nodeOrderHead...])
            nodeOrderHead = 0
        }
        let maximumQueueEntries = retentionLimits.maxRetainedNodes > Int.max / 2
            ? Int.max : retentionLimits.maxRetainedNodes * 2
        if nodeOrder.count > maximumQueueEntries {
            rebuildNodeOrder()
        }
    }

    private func rebuildNodeOrder() {
        nodeOrder = nodes.map { NodeOrderEntry(id: $0.key, line: $0.value.line) }
            .sorted {
                if $0.line != $1.line { return $0.line < $1.line }
                return $0.id < $1.id
            }
        nodeOrderHead = 0
    }

    private func resolveRelation(
        firstUUID: String, firstLine: Int64, turn: PendingTurn
    ) -> RelationResolution {
        var current = nodes[firstUUID]?.parent
        var steps = 0
        var hitCompaction = false
        while let id = current, let node = nodes[id], steps < 100_000 {
            if let anchorID = node.anchorID {
                return anchorID == turn.anchor.id ? .resolved(.parentChain) : .late
            }
            if node.kind.isAnchor {
                return id == turn.anchor.id ? .resolved(.parentChain) : .late
            }
            if node.kind == .compactSummary {
                hitCompaction = true
                break
            }
            current = node.parent
            steps += 1
        }
        if turn.anchor.line < firstLine {
            return .resolved(
                hitCompaction ? .fileOrderAfterCompaction : .fileOrderNoChain)
        }
        return .beforeAnchor
    }

    private func finalizePending(
        boundary: FinalizationBoundary, events: inout [CollectionEvent]
    ) {
        guard let turn = pending else { return }
        pending = nil

        if turn.historyTruncated {
            events.append(
                .closedWithoutAnswer(
                    TurnClosure(
                        projectID: context.projectID, sessionID: context.sessionID,
                        isSubagent: context.isSubagent, anchor: turn.anchor.summary,
                        reason: .historyLimitExceeded, messageCount: turn.messageCount,
                        terminalCount: turn.terminalCount, apiErrorAttempts: 0,
                        firstSegmentLine: turn.anchor.line, lastSegmentLine: turn.lastLine,
                        finalizedBy: boundary)))
            return
        }

        var candidates: [(snapshot: Snapshot, terminal: Terminal)] = []
        var ambiguous = false
        var apiErrorAttempts = 0
        var emptyAnswers = 0
        var stopSequences = 0
        var toolOnly = 0

        for snapshot in turn.messages.values {
            guard let last = snapshot.latestTerminal else { continue }
            let kind = TranscriptClassifier.classifyTerminal(
                stop: last.stop, text: last.text, apiError: last.apiError,
                ambiguous: snapshot.hasConflictingTerminals)
            switch kind {
            case .answerCandidate:
                candidates.append((snapshot, last))
            case .ambiguousTerminal:
                ambiguous = true
            case .apiError:
                apiErrorAttempts += 1
            case .emptyAnswer:
                emptyAnswers += 1
            case .stopSequence:
                stopSequences += 1
            case .executionEvent:
                toolOnly += 1
            case .unknownStop:
                break
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.terminal.line != rhs.terminal.line {
                return lhs.terminal.line < rhs.terminal.line
            }
            return (lhs.terminal.timestamp ?? "") < (rhs.terminal.timestamp ?? "")
        }

        guard let final = candidates.last else {
            let reason: ClosureReason
            if turn.interrupted {
                reason = .interrupted
            } else if ambiguous {
                reason = .ambiguousTerminal
            } else if apiErrorAttempts > 0 {
                reason = .apiError
            } else if emptyAnswers > 0 {
                reason = .emptyAnswer
            } else if stopSequences > 0 {
                reason = .stopSequence
            } else if toolOnly > 0 {
                reason = .toolOnly
            } else {
                reason = .noAnswer
            }
            events.append(
                .closedWithoutAnswer(
                    TurnClosure(
                        projectID: context.projectID, sessionID: context.sessionID,
                        isSubagent: context.isSubagent, anchor: turn.anchor.summary,
                        reason: reason, messageCount: turn.messageCount,
                        terminalCount: turn.terminalCount,
                        apiErrorAttempts: apiErrorAttempts,
                        firstSegmentLine: turn.anchor.line, lastSegmentLine: turn.lastLine,
                        finalizedBy: boundary)))
            return
        }

        let disposition: TurnDisposition
        if context.isSubagent || turn.anchor.isSidechain {
            disposition = .internalRecord
        } else if !turn.anchor.kind.isHuman {
            disposition = .deferredAutoTurn(turn.anchor.kind)
        } else if turn.interrupted {
            disposition = .requiresReview(.interrupted)
        } else {
            switch final.snapshot.relation {
            case .parentChain:
                disposition = .eligible
            case .fileOrderAfterCompaction:
                disposition = .requiresReview(.fileOrderAfterCompaction)
            case .fileOrderNoChain:
                disposition = .requiresReview(.fileOrderNoChain)
            }
        }

        let superseded = candidates.dropLast().map { candidate in
            SupersededAnswer(
                messageID: candidate.snapshot.messageID,
                answerDigest: candidate.terminal.digest,
                textLength: candidate.terminal.text.count,
                segmentLine: candidate.terminal.line,
                relation: candidate.snapshot.relation)
        }
        let identity = SourceIdentity(
            sourceSessionID: context.sessionID, sourceTurnID: turn.anchor.id,
            sourceMessageID: final.snapshot.messageID)
        events.append(
            .turn(
                CollectedTurnRecord(
                    candidateID:
                        "qoder:\(context.sessionID):\(turn.anchor.id):\(final.snapshot.messageID)",
                    identity: identity, projectID: context.projectID,
                    sessionID: context.sessionID, isSubagent: context.isSubagent,
                    anchor: turn.anchor.summary, promptRaw: turn.anchor.promptRaw,
                    promptText: turn.anchor.promptText,
                    promptRawDigest: turn.anchor.promptRawDigest,
                    promptDigest: turn.anchor.promptDigest,
                    answerText: final.terminal.text,
                    answerDigest: final.terminal.digest,
                    messageID: final.snapshot.messageID,
                    answerModel: final.snapshot.model,
                    timestamp: final.terminal.timestamp,
                    relation: final.snapshot.relation, disposition: disposition,
                    interrupted: turn.interrupted,
                    apiErrorAttempts: apiErrorAttempts,
                    supersededEndTurns: superseded,
                    firstSegmentLine: turn.anchor.line,
                    lastSegmentLine: final.terminal.line,
                    finalizedBy: boundary)))
    }}
