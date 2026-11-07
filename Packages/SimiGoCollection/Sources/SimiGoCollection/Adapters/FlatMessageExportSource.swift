import Foundation

/// Flat `messages[]` exports, where one file is one session.
///
/// What the carrier states, measured over the three real exports in the corpus:
/// every row carries `id` (integer, ascending but not contiguous), `timestamp`
/// (epoch seconds), `content` (string), `role` (user / assistant / tool) and a
/// `finish_reason` that only assistant rows fill; the document declares one
/// `session_id` shared by every row. Timestamps are not monotone in all files,
/// so file order is the sequence and a stamp is only a label.
///
/// Two things decide the grading. First, `finish_reason == "tool_calls"` marks a
/// mid-loop round: its text is what the agent said while working, not the answer
/// to the prompt, so it never becomes `answerText` (the same rule the settlement
/// side already applies to tool loops). Second, completion is read as an
/// explicit whitelist — `stop` is the only value that means "answered". A row
/// that states nothing, states `length`, or states a value this adapter has
/// never seen all grade as recorded-but-not-retrievable, because an absent
/// marker is not evidence of a finished answer.
///
/// `reasoning` and `reasoning_content` measured identical across every row of
/// every file, so either is the same fact; `reasoning` is read first. It only
/// ever travels into `reasoningText`. `display_kind == "model_switch"` rows are
/// role=user rows that record a model switch rather than something a human
/// asked, so they never open a turn.
public enum FlatMessageExportSource: SnapshotTranscriptSource {
    public static let sourceType = "flat-export"
    public static let adapterVersion = "flat-message-export/v1"
    public static let sourceKind: TranscriptSourceKind = .wholeFileSnapshot

    private struct Row {
        let index: Int
        let id: String
        let role: String
        let text: String?
        let reasoning: String?
        let finishReason: String?
        let isMarker: Bool
        let isCompacted: Bool
        let timestamp: String?

        var locator: String { "message-\(id)" }
    }

    public static func recognizes(_ data: Data) -> Bool {
        SnapshotShape.matches(data) { value in
            guard let object = SnapshotJSON.object(value),
                let messages = SnapshotJSON.array(object["messages"]),
                !messages.isEmpty
            else { return false }
            return messages.allSatisfy {
                SnapshotJSON.string(SnapshotJSON.object($0)?["role"]) != nil
            }
        }
    }

    public static func interpret(
        _ data: Data, path: String, contentDigest: String
    ) throws -> SnapshotImport {
        let document = try SnapshotShape.object(from: data, path: path)
        guard let rawMessages = SnapshotJSON.array(document["messages"]) else {
            throw SnapshotReadError.foreignDocument(
                path: path, detail: "messages is not a list")
        }

        var diagnostics: [CollectionDiagnostic] = []
        // The session may be stated by the document or by its rows; only when
        // neither states one does the file name have to carry the identity.
        let documentSession = SnapshotJSON.identifier(document["session_id"])
        let rowSession = rawMessages
            .compactMap { SnapshotJSON.identifier(SnapshotJSON.object($0)?["session_id"]) }
            .first
        let sessionID =
            documentSession ?? rowSession ?? (path as NSString).deletingPathExtension
        if documentSession == nil {
            let detail: String
            if let rowSession {
                detail =
                    "the document declares no session identifier; the identity comes from "
                    + "the row session \(rowSession)"
            } else {
                detail =
                    "neither the document nor its rows declare a session identifier; the "
                    + "identity is derived from the file name and breaks when it is renamed"
            }
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "session_id",
                    kind: .unsupportedShape, detail: detail))
        }
        if let stated = SnapshotJSON.integer(document["message_count"]),
            stated != rawMessages.count
        {
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "message_count",
                    kind: .unsupportedShape,
                    detail: "message_count says \(stated), messages holds \(rawMessages.count)"))
        }

        var turns: [CollectedTurn] = []
        var openPrompt: Row?
        var unboundIndices: [Int] = []
        var unboundWithText = 0

        for (index, raw) in rawMessages.enumerated() {
            guard let row = row(from: raw, index: index, path: path, sessionID: sessionID,
                                diagnostics: &diagnostics)
            else { continue }

            if row.isMarker {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: row.locator,
                        kind: .unsupportedShape,
                        detail:
                            "model_switch row: it is displayed as a user row but records a "
                            + "model change, so no turn is opened"))
                continue
            }

            switch row.role {
            case "user":
                if let previous = openPrompt {
                    diagnostics.append(
                        unanswered(path: path, sessionID: sessionID, prompt: previous))
                    openPrompt = nil
                }
                guard row.text != nil else {
                    diagnostics.append(
                        diagnostic(
                            path: path, sessionID: sessionID, part: row.locator,
                            kind: .unsupportedShape,
                            detail: "user row states no prompt text"))
                    break
                }
                flushUnbound(
                    indices: &unboundIndices, withText: &unboundWithText, path: path,
                    sessionID: sessionID, diagnostics: &diagnostics)
                openPrompt = row

            case "assistant":
                guard let prompt = openPrompt else {
                    unboundIndices.append(row.index)
                    if row.text != nil { unboundWithText += 1 }
                    break
                }
                if row.finishReason == "tool_calls" {
                    // Mid-loop: the agent is still working, so this row neither
                    // answers the prompt nor closes it.
                    diagnostics.append(
                        diagnostic(
                            path: path, sessionID: sessionID, part: row.locator,
                            kind: .toolTraffic,
                            detail: "tool round: its text is what the agent said while working"))
                    break
                }
                openPrompt = nil
                guard let answerText = row.text else {
                    diagnostics.append(
                        diagnostic(
                            path: path, sessionID: sessionID, part: row.locator,
                            kind: .incompleteTurn,
                            detail: "terminal assistant row states no answer text"))
                    break
                }
                let disposition = grade(
                    finishReason: row.finishReason, path: path, sessionID: sessionID,
                    locator: row.locator, diagnostics: &diagnostics)
                turns.append(
                    CollectedTurn(
                        identity: identity(
                            sessionID: sessionID, turnID: prompt.id, messageID: row.id),
                        provider: sourceType,
                        sessionKey: sessionKey(projectID: "", sessionID: sessionID),
                        promptText: prompt.text ?? "",
                        answerText: answerText,
                        reasoningText: row.reasoning,
                        answerModel: nil,
                        timestamp: row.timestamp ?? prompt.timestamp,
                        attribution: prompt.isCompacted
                            ? .fileOrderAfterCompaction : .fileOrderOnly,
                        disposition: disposition))

            case "tool":
                if openPrompt == nil {
                    unboundIndices.append(row.index)
                }

            default:
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: row.locator,
                        kind: .unsupportedShape, detail: "unknown role \(row.role)"))
            }
        }

        if let previous = openPrompt {
            diagnostics.append(unanswered(path: path, sessionID: sessionID, prompt: previous))
        }
        flushUnbound(
            indices: &unboundIndices, withText: &unboundWithText, path: path,
            sessionID: sessionID, diagnostics: &diagnostics)

        return SnapshotImport(
            turns: turns, diagnostics: diagnostics, contentDigest: contentDigest)
    }

    // MARK: - Grading

    /// `stop` is the only completion this carrier states. Everything else is
    /// recorded and never retrieved, so an unknown value cannot silently read
    /// as a finished answer.
    private static func grade(
        finishReason: String?, path: String, sessionID: String, locator: String,
        diagnostics: inout [CollectionDiagnostic]
    ) -> CollectionTurnDisposition {
        switch finishReason {
        case "stop":
            return .retrievable
        case "length":
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: locator,
                    kind: .incompleteTurn, detail: "answer truncated by the token budget"))
            return .recordedIncompleteAnswer
        case .none:
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: locator,
                    kind: .incompleteTurn,
                    detail: "no finish_reason: an absent marker is not a finished answer"))
            return .recordedIncompleteAnswer
        case .some(let value):
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: locator,
                    kind: .unsupportedShape, detail: "unrecognised finish_reason \(value)"))
            return .recordedIncompleteAnswer
        }
    }

    private static func unanswered(
        path: String, sessionID: String, prompt: Row
    ) -> CollectionDiagnostic {
        diagnostic(
            path: path, sessionID: sessionID, part: prompt.locator,
            kind: .incompleteTurn, detail: "prompt has no terminal assistant row")
    }

    /// Rows that appear before any prompt have no question to bind to. They are
    /// reported as one run so a real export that opens with tool traffic yields
    /// one line rather than dozens.
    private static func flushUnbound(
        indices: inout [Int], withText: inout Int, path: String, sessionID: String,
        diagnostics: inout [CollectionDiagnostic]
    ) {
        defer {
            indices.removeAll()
            withText = 0
        }
        guard let first = indices.first, let last = indices.last else { return }
        diagnostics.append(
            diagnostic(
                path: path, sessionID: sessionID, part: "rows \(first)-\(last)",
                kind: .unboundAnswer,
                detail:
                    "\(indices.count) assistant/tool rows outside any prompt "
                    + "(\(withText) with text) are not imported"))
    }

    // MARK: - Reading

    private static func row(
        from value: Any?, index: Int, path: String, sessionID: String,
        diagnostics: inout [CollectionDiagnostic]
    ) -> Row? {
        guard let object = SnapshotJSON.object(value),
            let role = SnapshotJSON.string(object["role"])
        else {
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "row-\(index)",
                    kind: .unsupportedShape, detail: "row is not an object with a role"))
            return nil
        }
        let identifier = SnapshotJSON.identifier(object["id"]) ?? "index-\(index)"
        var reasoning = SnapshotText.usable(object["reasoning"])
        if reasoning == nil {
            reasoning = SnapshotText.usable(object["reasoning_content"])
        }
        return Row(
            index: index,
            id: identifier,
            role: role,
            text: SnapshotText.usable(object["content"]),
            reasoning: reasoning,
            finishReason: SnapshotJSON.string(object["finish_reason"]),
            isMarker: SnapshotJSON.string(object["display_kind"]) == "model_switch",
            isCompacted: SnapshotJSON.integer(object["compacted"]) == 1,
            timestamp: SnapshotTimestamp.epochSeconds(SnapshotJSON.double(object["timestamp"]))
        )
    }

    private static func diagnostic(
        path: String, sessionID: String, part: String, kind: CollectionDiagnostic.Kind,
        detail: String
    ) -> CollectionDiagnostic {
        CollectionDiagnostic(
            kind: kind, sourceType: sourceType,
            locator: SnapshotLocator.describe(file: path, sessionID: sessionID, part: part),
            detail: detail)
    }
}
