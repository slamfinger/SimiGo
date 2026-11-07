import Foundation

/// Google AI Studio prompt exports: one document is one conversation, held as
/// `chunkedPrompt.chunks` with a `pendingInputs` draft beside it.
///
/// Measured over the 72 recognized documents: the document states no session
/// identifier anywhere, `createTime` is missing on 175 of 4598 chunks, and 5
/// documents contain a step where the stamps run backwards — so document order is
/// the conversation and a stamp is only a label. Chunk `text` is authoritative:
/// concatenating `parts[].text` would double-count it, and exactly one of the 2854
/// rows carrying `parts` disagrees with `text`, which is the row holding a
/// function call where both are empty. The thought flag appears both as
/// `isThought` and as `parts[].thought`, so either reading selects the same set.
/// User chunks arrive in runs of 1 to 5 that together form one prompt, and 169
/// user chunks state no text because they carry an attachment instead.
///
/// Completion is an explicit whitelist, the same rule the other adapters apply:
/// `STOP` is the only value this carrier uses for a finished answer.
/// `MALFORMED_RESPONSE` and `PROHIBITED_CONTENT` exist in the corpus and are not
/// answers, and 29 chunks carry an `errorMessage` of which 3 also carry text —
/// an error's own text never becomes an answer.
///
/// The identity weakness is real and is stated in a diagnostic rather than hidden:
/// with no identifier in the document, the session key comes from the file name
/// and breaks when the file is renamed. `contentDigest` is what makes a re-import
/// of the same bytes recognizable, and reading it belongs to the snapshot revision
/// decision, not to this adapter.
public enum AIStudioSource: SnapshotTranscriptSource {
    public static let sourceType = "aistudio"
    public static let adapterVersion = "aistudio-chunked-prompt/v1"
    public static let sourceKind: TranscriptSourceKind = .wholeFileSnapshot

    private struct Chunk {
        let index: Int
        let role: String
        let text: String?
        let isThought: Bool
        let finishReason: String?
        let hasErrorMessage: Bool
        let hasBranch: Bool
        let hasToolCall: Bool
        let createTime: String?
    }

    public static func recognizes(_ data: Data) -> Bool {
        SnapshotShape.matches(data) { value in
            guard let object = SnapshotJSON.object(value),
                let prompt = SnapshotJSON.object(object["chunkedPrompt"]),
                let chunks = SnapshotJSON.array(prompt["chunks"]),
                SnapshotJSON.object(object["runSettings"]) != nil
            else { return false }
            return chunks.allSatisfy {
                SnapshotJSON.string(SnapshotJSON.object($0)?["role"]) != nil
            }
        }
    }

    public static func interpret(
        _ data: Data, path: String, contentDigest: String
    ) throws -> SnapshotImport {
        let document = try SnapshotShape.object(from: data, path: path)
        guard let prompt = SnapshotJSON.object(document["chunkedPrompt"]),
            let rawChunks = SnapshotJSON.array(prompt["chunks"])
        else {
            throw SnapshotReadError.foreignDocument(
                path: path, detail: "chunkedPrompt.chunks is not a list")
        }

        // Nothing in the document names the conversation, so the file has to.
        let sessionID = (path as NSString).deletingPathExtension
        var diagnostics: [CollectionDiagnostic] = [
            diagnostic(
                sessionID: sessionID, path: path, part: "chunkedPrompt",
                kind: .unsupportedShape,
                detail:
                    "the document declares no session identifier; the identity is derived "
                    + "from the file name and breaks when it is renamed")
        ]
        let answerModel = SnapshotJSON.string(
            SnapshotJSON.object(document["runSettings"])?["model"])

        // A pending input is what the composer held when the export was taken. It
        // was never sent, so it cannot be a prompt however complete its text is.
        for (position, draft) in (SnapshotJSON.array(prompt["pendingInputs"]) ?? []).enumerated() {
            let stated = SnapshotText.usable(SnapshotJSON.object(draft)?["text"])
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "pendingInputs-\(position)",
                    kind: .unsentDraft,
                    detail: stated == nil
                        ? "pending input is a draft the user never sent; not imported"
                        : "pending input holds text but was never sent; not imported"))
        }

        var turns: [CollectedTurn] = []
        var promptBlock: [Chunk] = []
        var answerRun: [Chunk] = []
        var unboundRun: [Int] = []

        for (index, raw) in rawChunks.enumerated() {
            guard let chunk = chunk(from: raw, index: index) else {
                diagnostics.append(
                    diagnostic(
                        sessionID: sessionID, path: path, part: "chunk-\(index)",
                        kind: .unsupportedShape, detail: "chunk is not an object with a role"))
                continue
            }
            switch chunk.role {
            case "user":
                if chunk.text == nil {
                    diagnostics.append(
                        diagnostic(
                            sessionID: sessionID, path: path, part: "chunk-\(index)",
                            kind: .skippedAttachment,
                            detail:
                                "user chunk states no text; it carries an attachment or an "
                                + "empty input, so it contributes nothing to the prompt"))
                }
                // A model run belongs to the prompt block in front of it, so it
                // closes before this chunk joins that block.
                if !answerRun.isEmpty {
                    if !promptBlock.isEmpty {
                        emitTurn(
                            promptBlock: promptBlock, answerRun: answerRun, into: &turns,
                            sessionID: sessionID, path: path, answerModel: answerModel,
                            diagnostics: &diagnostics)
                    }
                    answerRun = []
                    // The next round's prompt is its own run: carrying the earlier
                    // chunks forward would make every question the whole history.
                    promptBlock = []
                }
                promptBlock.append(chunk)
            case "model":
                if promptBlock.isEmpty {
                    unboundRun.append(index)
                } else {
                    answerRun.append(chunk)
                }
            default:
                diagnostics.append(
                    diagnostic(
                        sessionID: sessionID, path: path, part: "chunk-\(index)",
                        kind: .unsupportedShape, detail: "unknown role \(chunk.role)"))
            }
        }
        if !answerRun.isEmpty {
            emitTurn(
                promptBlock: promptBlock, answerRun: answerRun, into: &turns,
                sessionID: sessionID, path: path, answerModel: answerModel,
                diagnostics: &diagnostics)
        }
        if let first = unboundRun.first, let last = unboundRun.last {
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "chunks \(first)-\(last)",
                    kind: .unboundAnswer,
                    detail:
                        "\(unboundRun.count) model chunks precede any user chunk, so no prompt "
                        + "of this document can be bound to them"))
        }
        return SnapshotImport(
            turns: turns, diagnostics: diagnostics, contentDigest: contentDigest)
    }

    /// One prompt block plus the model run that followed it.
    private static func emitTurn(
        promptBlock: [Chunk], answerRun: [Chunk], into turns: inout [CollectedTurn],
        sessionID: String, path: String, answerModel: String?,
        diagnostics: inout [CollectionDiagnostic]
    ) {
        let promptParts = promptBlock.compactMap(\.text)
        guard let firstPrompt = promptBlock.first, !promptParts.isEmpty else {
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path,
                    part: "chunk-\(promptBlock.first?.index ?? answerRun.first?.index ?? 0)",
                    kind: .incompleteTurn,
                    detail: "the model run has no stated question in front of it"))
            return
        }

        let reasoning = answerRun.filter(\.isThought).compactMap(\.text)
        // An answer chunk is one that says something to the user: not a thought,
        // not an error, not a function call.
        let answers = answerRun.filter { !$0.isThought && !$0.hasErrorMessage && !$0.hasToolCall }
        let answerTexts = answers.compactMap(\.text)
        let errors = answerRun.filter(\.hasErrorMessage)
        let toolCalls = answerRun.filter(\.hasToolCall)
        let branchCount =
            answerRun.filter(\.hasBranch).count + promptBlock.filter(\.hasBranch).count
        guard let terminal = answers.last(where: { $0.text != nil }), !answerTexts.isEmpty else {
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "chunk-\(firstPrompt.index)",
                    kind: .incompleteTurn,
                    detail:
                        "model run carries no answer text"
                        + (reasoning.isEmpty ? "" : " (thought fragments only)")))
            return
        }

        var disposition: CollectionTurnDisposition
        switch terminal.finishReason {
        case "STOP":
            disposition = .retrievable
        case .none:
            disposition = .recordedIncompleteAnswer
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "chunk-\(terminal.index)",
                    kind: .incompleteTurn,
                    detail: "answer chunk states no finishReason: an absent marker is "
                        + "not a finished answer"))
        case .some(let value):
            disposition = .recordedIncompleteAnswer
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "chunk-\(terminal.index)",
                    kind: .unsupportedShape, detail: "answer did not finish normally: \(value)"))
        }
        // A chunk anywhere in the run that reports its own end says something about
        // the round, even when the terminal chunk claimed success.
        let abnormal = answerRun.filter {
            $0.index != terminal.index && (($0.finishReason ?? "STOP") != "STOP")
        }
        if !abnormal.isEmpty {
            disposition = .recordedIncompleteAnswer
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "chunk-\(abnormal[0].index)",
                    kind: .unsupportedShape,
                    detail: "\(abnormal.count) chunk(s) in the run report an abnormal end"))
        }
        if !errors.isEmpty {
            // An error beside the answer means the round did not complete as
            // stated, whatever the last answer chunk claimed.
            disposition = .recordedIncompleteAnswer
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "chunk-\(errors[0].index)",
                    kind: .unsupportedShape,
                    detail:
                        "\(errors.count) error chunk(s) in the run; their text is never an answer"))
        }
        if branchCount > 0 {
            disposition = .recordedIncompleteAnswer
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "chunk-\(firstPrompt.index)",
                    kind: .unsupportedShape,
                    detail:
                        "\(branchCount) branch marker(s): the document says this round belongs to a "
                        + "branch, so the prompt/answer binding is not settled by it either"))
        }
        if !toolCalls.isEmpty {
            diagnostics.append(
                diagnostic(
                    sessionID: sessionID, path: path, part: "chunk-\(toolCalls[0].index)",
                    kind: .toolTraffic,
                    detail:
                        "\(toolCalls.count) function call(s) in the run are not part of the answer"))
        }

        turns.append(
            CollectedTurn(
                identity: identity(
                    sessionID: sessionID,
                    turnID: "prompt-\(firstPrompt.index)",
                    messageID: "chunk-\(terminal.index)"),
                provider: sourceType,
                sessionKey: sessionKey(projectID: "", sessionID: sessionID),
                promptText: promptParts.joined(separator: "\n"),
                answerText: answerTexts.joined(separator: "\n\n"),
                reasoningText: reasoning.isEmpty ? nil : reasoning.joined(separator: "\n\n"),
                answerModel: answerModel,
                timestamp: terminal.createTime ?? firstPrompt.createTime,
                attribution: .fileOrderOnly,
                disposition: disposition))
    }

    private static func chunk(from value: Any?, index: Int) -> Chunk? {
        guard let object = SnapshotJSON.object(value),
            let role = SnapshotJSON.string(object["role"])
        else { return nil }
        let parts = SnapshotJSON.array(object["parts"]) ?? []
        let isThought =
            SnapshotJSON.bool(object["isThought"]) == true
            || parts.contains { SnapshotJSON.bool(SnapshotJSON.object($0)?["thought"]) == true }
        return Chunk(
            index: index,
            role: role,
            text: SnapshotText.usable(object["text"]),
            isThought: isThought,
            finishReason: SnapshotJSON.string(object["finishReason"]),
            hasErrorMessage: object["errorMessage"] != nil,
            hasBranch: object["branchParent"] != nil || object["branchChildren"] != nil,
            hasToolCall:
                object["resolvedFunctionCall"] != nil
                || parts.contains { SnapshotJSON.object($0)?["functionCall"] != nil },
            createTime: SnapshotTimestamp.normalize(SnapshotJSON.string(object["createTime"]))
        )
    }

    private static func diagnostic(
        sessionID: String, path: String, part: String, kind: CollectionDiagnostic.Kind,
        detail: String
    ) -> CollectionDiagnostic {
        CollectionDiagnostic(
            kind: kind, sourceType: sourceType,
            locator: SnapshotLocator.describe(file: path, sessionID: sessionID, part: part),
            detail: detail)
    }
}
