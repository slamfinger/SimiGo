import Foundation

/// Incremental turn reconstruction for one Qoder transcript file.
///
/// The accumulator sees only appended entries, so attribution is resolved
/// against the entries it has observed since the baseline. A new anchor closes
/// the previous turn; assistant messages are coalesced by `message.id` and
/// attributed through the parent chain when it reaches the open anchor, or by
/// file order (always flagged for review) when a compaction broke the chain.
public final class QoderTurnAccumulator {
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
        let kind: QoderAnchorKind
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

        var summary: QoderAnchorSummary {
            QoderAnchorSummary(
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
        var lastText: String
        var lastStop: String?
        var model: String?
        var isSidechain: Bool
        var terminals: [Terminal]
        var relation: QoderAttributionRelation
    }

    private struct PendingTurn {
        let anchor: Anchor
        var messages: [String: Snapshot]
        var interrupted: Bool
        var interruptLine: Int64?
    }

    private enum RelationResolution {
        case resolved(QoderAttributionRelation)
        case late
        case beforeAnchor
    }

    private let context: Context
    private var nodes: [String: Node] = [:]
    private var seenAnchorIDs: Set<String> = []
    private var pending: PendingTurn?

    public init(context: Context) {
        self.context = context
    }

    public var hasOpenTurn: Bool { pending != nil }

    /// Segment line that opened the still-open turn. The tailer persists this
    /// as the replay point so a restart rebuilds the turn from the transcript.
    public var openAnchorSegmentLine: Int64? { pending?.anchor.line }

    public func ingest(
        _ entry: QoderTranscriptEntry, segmentLine: Int64
    ) -> [QoderCollectionEvent] {
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
        boundary: QoderFinalizationBoundary,
        into events: inout [QoderCollectionEvent]
    ) {
        finalizePending(boundary: boundary, events: &events)
    }

    private func handleUser(
        _ entry: QoderTranscriptEntry, line: Int64
    ) -> [QoderCollectionEvent] {
        let classification = QoderTranscriptClassifier.classifyUser(entry)
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

        var events: [QoderCollectionEvent] = []
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
                    QoderCompactionEvent(
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
        _ entry: QoderTranscriptEntry, line: Int64
    ) -> [QoderCollectionEvent] {
        guard let attachment = entry.attachment,
            attachment.type == "queued_command",
            let sourceUUID = attachment.sourceUUID, !sourceUUID.isEmpty
        else {
            registerNode(entry, line: line, kind: .other, anchorID: nil)
            return []
        }
        registerNode(entry, line: line, kind: .queuedCommand, anchorID: sourceUUID)
        var events: [QoderCollectionEvent] = []
        beginAnchor(
            id: sourceUUID, kind: .queuedCommand, line: line, timestamp: entry.timestamp,
            originKind: attachment.originKind ?? entry.originKind,
            promptRaw: attachment.promptText, promptText: attachment.promptText,
            injectedPrefixes: [], isSidechain: entry.isSidechain, requestSetID: nil,
            events: &events)
        return events
    }

    private func handleAssistant(
        _ entry: QoderTranscriptEntry, line: Int64
    ) -> [QoderCollectionEvent] {
        registerNode(entry, line: line, kind: .assistant, anchorID: nil)
        var events: [QoderCollectionEvent] = []
        guard let message = entry.message, let messageID = message.id,
            let uuid = entry.uuid
        else { return events }
        guard var turn = pending else {
            if message.stopReason != nil || entry.isAPIMessageError {
                events.append(
                    .orphanAssistant(
                        QoderOrphanAssistant(
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
                    QoderOrphanAssistant(
                        path: context.path, sessionID: context.sessionID,
                        messageID: messageID, segmentLine: line,
                        reason: .lateForClosedTurn)))
            return events
        case .beforeAnchor:
            events.append(
                .orphanAssistant(
                    QoderOrphanAssistant(
                        path: context.path, sessionID: context.sessionID,
                        messageID: messageID, segmentLine: line,
                        reason: .beforeCurrentAnchor)))
            return events
        case .resolved(let relation):
            var snapshot =
                turn.messages[messageID]
                ?? Snapshot(
                    messageID: messageID, firstUUID: uuid, firstLine: line,
                    lastLine: line, lastText: message.text,
                    lastStop: message.stopReason, model: message.model,
                    isSidechain: entry.isSidechain, terminals: [], relation: relation)
            snapshot.lastLine = line
            snapshot.lastText = message.text
            snapshot.lastStop = message.stopReason
            snapshot.model = message.model ?? snapshot.model
            snapshot.isSidechain = snapshot.isSidechain || entry.isSidechain
            let isTerminal =
                message.stopReason == "end_turn" || message.stopReason == "tool_use"
                || message.stopReason == "stop_sequence" || entry.isAPIMessageError
            if isTerminal,
                !snapshot.terminals.contains(where: { $0.line == line })
            {
                snapshot.terminals.append(
                    Terminal(
                        line: line, timestamp: entry.timestamp, stop: message.stopReason,
                        text: message.text, digest: QoderDigest.sha256Hex(message.text),
                        apiError: entry.isAPIMessageError))
            }
            turn.messages[messageID] = snapshot
            pending = turn
        }
        return events
    }

    private func beginMetaAnchor(
        _ entry: QoderTranscriptEntry, id: String?, kind: QoderAnchorKind, line: Int64,
        text: String, events: inout [QoderCollectionEvent]
    ) {
        guard let id else { return }
        beginAnchor(
            id: id, kind: kind, line: line, timestamp: entry.timestamp,
            originKind: entry.originKind, promptRaw: text, promptText: text,
            injectedPrefixes: [], isSidechain: entry.isSidechain,
            requestSetID: entry.requestSetID, events: &events)
    }

    private func beginAnchor(
        id: String, kind: QoderAnchorKind, line: Int64, timestamp: String?,
        originKind: String?, promptRaw: String, promptText: String,
        injectedPrefixes: [String], isSidechain: Bool, requestSetID: String?,
        events: inout [QoderCollectionEvent]
    ) {
        guard !seenAnchorIDs.contains(id) else { return }
        finalizePending(boundary: .nextAnchor, events: &events)
        pruneNodes(before: line)
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = Anchor(
            id: id, kind: kind, line: line, timestamp: timestamp,
            originKind: originKind, promptRaw: promptRaw, promptText: trimmedPrompt,
            promptRawDigest: QoderDigest.sha256Hex(promptRaw),
            promptDigest: QoderDigest.sha256Hex(trimmedPrompt),
            injectedPrefixes: injectedPrefixes, isSidechain: isSidechain,
            requestSetID: requestSetID)
        pending = PendingTurn(
            anchor: anchor, messages: [:], interrupted: false, interruptLine: nil)
        seenAnchorIDs.insert(id)
        _ = events
    }

    private func registerNode(
        _ entry: QoderTranscriptEntry, line: Int64, kind: NodeKind, anchorID: String?
    ) {
        guard let uuid = entry.uuid else { return }
        nodes[uuid] = Node(
            parent: entry.parentUUID, kind: kind, anchorID: anchorID, line: line)
    }

    private func pruneNodes(before line: Int64) {
        nodes = nodes.filter { _, node in
            node.kind.isAnchor || node.kind == .compactSummary || node.line >= line
        }
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
        boundary: QoderFinalizationBoundary, events: inout [QoderCollectionEvent]
    ) {
        guard let turn = pending else { return }
        pending = nil

        var candidates: [(snapshot: Snapshot, terminal: Terminal)] = []
        var ambiguous = false
        var apiErrorAttempts = 0
        var emptyAnswers = 0
        var stopSequences = 0
        var toolOnly = 0
        var terminalCount = 0

        for snapshot in turn.messages.values {
            terminalCount += snapshot.terminals.count
            guard let last = snapshot.terminals.max(by: {
                ($0.line, $0.timestamp ?? "") < ($1.line, $1.timestamp ?? "")
            }) else { continue }
            let distinct = Set(snapshot.terminals.map(\.digest))
            let kind = QoderTranscriptClassifier.classifyTerminal(
                stop: last.stop, text: last.text, apiError: last.apiError,
                ambiguous: snapshot.terminals.count > 1 && distinct.count > 1)
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
            let reason: QoderClosureReason
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
            let lastLine = turn.messages.values.map(\.lastLine).max() ?? turn.anchor.line
            events.append(
                .closedWithoutAnswer(
                    QoderTurnClosure(
                        projectID: context.projectID, sessionID: context.sessionID,
                        isSubagent: context.isSubagent, anchor: turn.anchor.summary,
                        reason: reason, messageCount: turn.messages.count,
                        terminalCount: terminalCount,
                        apiErrorAttempts: apiErrorAttempts,
                        firstSegmentLine: turn.anchor.line, lastSegmentLine: lastLine,
                        finalizedBy: boundary)))
            return
        }

        let disposition: QoderTurnDisposition
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
            case .unattached:
                disposition = .requiresReview(.unattached)
            }
        }

        let superseded = candidates.dropLast().map { candidate in
            QoderSupersededAnswer(
                messageID: candidate.snapshot.messageID,
                answerDigest: candidate.terminal.digest,
                textLength: candidate.terminal.text.count,
                segmentLine: candidate.terminal.line,
                relation: candidate.snapshot.relation)
        }
        let identity = QoderSourceIdentity(
            sourceSessionID: context.sessionID, sourceTurnID: turn.anchor.id,
            sourceMessageID: final.snapshot.messageID)
        events.append(
            .turn(
                QoderCollectedTurn(
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
    }
}
