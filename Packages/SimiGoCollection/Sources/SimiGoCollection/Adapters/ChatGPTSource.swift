import Foundation

/// ChatGPT's desktop export (`conversations-*.json`): one file holds many
/// conversations, and each is a `mapping` node tree rooted at `current_node`.
///
/// The structure that makes this carrier recognisable is what it *lacks*: every
/// node carries `{id, message, parent}` and never `children`. DeepSeek's export
/// uses the same `mapping` key but every node states `children`, so the two are
/// told apart by shape rather than by file name — the exports arrive with names
/// like `conversations-000.json` that state nothing about their producer.
///
/// The kept branch is the path from `current_node` back to the root. Siblings
/// exist in the mapping and are deliberately not read: the export records which
/// branch the user is looking at, and picking another would invent an answer.
///
/// Answer text lives in `content.parts` only when `content_type` is `text`.
/// `thoughts` and `reasoning_recap` are separate nodes on the same branch; they
/// travel into `reasoningText`, never into the answer, because a carrier's
/// deliberation is not what the agent said.
public enum ChatGPTSource: SnapshotTranscriptSource {
    public static let sourceType = "chatgpt"
    public static let adapterVersion = "chatgpt-mapping/v1"
    public static let sourceKind: TranscriptSourceKind = .wholeFileSnapshot

    private struct Node {
        let key: String
        let parent: String?
        let role: String?
        let contentType: String?
        let text: String?
        let timestamp: String?
    }

    public static func recognizes(_ data: Data) -> Bool {
        SnapshotShape.matches(data) { value in
            guard let conversations = SnapshotJSON.array(value), !conversations.isEmpty
            else { return false }
            return conversations.allSatisfy { item in
                guard let object = SnapshotJSON.object(item),
                    SnapshotJSON.identifier(object["conversation_id"]) != nil,
                    SnapshotJSON.string(object["current_node"]) != nil,
                    let mapping = SnapshotJSON.object(object["mapping"]),
                    !mapping.isEmpty
                else { return false }
                // DeepSeek's export states `children` on every node; this one
                // never does. A document holding both is neither carrier.
                return mapping.values.allSatisfy { node in
                    SnapshotJSON.object(node)?["children"] == nil
                }
            }
        }
    }

    public static func interpret(
        _ data: Data, path: String, contentDigest: String
    ) throws -> SnapshotImport {
        let conversations = try SnapshotShape.array(from: data, path: path)
        guard !conversations.isEmpty else {
            throw SnapshotReadError.foreignDocument(
                path: path, detail: "the export holds no conversations")
        }

        var turns: [CollectedTurn] = []
        var diagnostics: [CollectionDiagnostic] = []
        for (position, value) in conversations.enumerated() {
            guard let conversation = SnapshotJSON.object(value) else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: nil, part: "conversation-\(position)",
                        kind: .unsupportedShape, detail: "conversation is not an object")
                )
                continue
            }
            guard let sessionID = SnapshotJSON.identifier(conversation["conversation_id"])
            else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: nil, part: "conversation-\(position)",
                        kind: .unsupportedShape,
                        detail: "conversation states no conversation_id; no derived identity is invented")
                )
                continue
            }
            guard let mapping = SnapshotJSON.object(conversation["mapping"]),
                !mapping.isEmpty
            else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: "mapping",
                        kind: .unsupportedShape, detail: "mapping is not a non-empty object")
                )
                continue
            }
            guard let currentNode = SnapshotJSON.string(conversation["current_node"]),
                mapping[currentNode] != nil
            else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: "current_node",
                        kind: .unsupportedShape,
                        detail: "current_node names no node in this mapping; the kept branch is unknown")
                )
                continue
            }
            read(
                mapping: mapping, currentNode: currentNode, path: path, sessionID: sessionID,
                turns: &turns, diagnostics: &diagnostics)
        }
        return SnapshotImport(
            turns: turns, diagnostics: diagnostics, contentDigest: contentDigest)
    }

    private static func read(
        mapping: [String: Any], currentNode: String, path: String, sessionID: String,
        turns: inout [CollectedTurn], diagnostics: inout [CollectionDiagnostic]
    ) {
        var nodes: [String: Node] = [:]
        nodes.reserveCapacity(mapping.count)
        for (key, value) in mapping {
            guard let object = SnapshotJSON.object(value) else { continue }
            let message = SnapshotJSON.object(object["message"])
            let content = SnapshotJSON.object(message?["content"])
            nodes[key] = Node(
                key: key,
                parent: SnapshotJSON.string(object["parent"]),
                role: SnapshotJSON.string(SnapshotJSON.object(message?["author"])?["role"]),
                contentType: SnapshotJSON.string(content?["content_type"]),
                text: text(in: content),
                timestamp: epochStamp(SnapshotJSON.double(message?["create_time"])))
        }

        // `current_node` names the leaf the export left selected; walking parents
        // gives the branch in reading order.
        var chain: [Node] = []
        var cursor: String? = currentNode
        var visited: Set<String> = []
        while let key = cursor, let node = nodes[key], visited.insert(key).inserted {
            chain.append(node)
            cursor = node.parent
        }
        chain.reverse()

        var prompt: Node?
        var promptText = ""
        var reasoning: [String] = []
        var answered = false

        func closeUnanswered() {
            guard let p = prompt, !answered else { return }
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "node-\(p.key)",
                    kind: .incompleteTurn,
                    detail: "no assistant text node follows this prompt on the kept branch"))
        }

        for node in chain {
            switch (node.role, node.contentType) {
            case ("user", _):
                closeUnanswered()
                guard let text = node.text, !text.isEmpty else {
                    diagnostics.append(
                        diagnostic(
                            path: path, sessionID: sessionID, part: "node-\(node.key)",
                            kind: .skippedAttachment,
                            detail: "user node states no text"))
                    prompt = nil
                    promptText = ""
                    answered = false
                    continue
                }
                prompt = node
                promptText = text
                reasoning = []
                answered = false
            case ("assistant", "text"):
                guard let p = prompt, let text = node.text, !text.isEmpty else { continue }
                if answered {
                    diagnostics.append(
                        diagnostic(
                            path: path, sessionID: sessionID, part: "node-\(node.key)",
                            kind: .unboundAnswer,
                            detail: "a second assistant text node follows the same prompt; only the first is imported"))
                    continue
                }
                turns.append(
                    CollectedTurn(
                        identity: identity(
                            sessionID: sessionID, turnID: p.key, messageID: node.key),
                        provider: sourceType,
                        sessionKey: sessionKey(projectID: "", sessionID: sessionID),
                        promptText: promptText,
                        answerText: text,
                        reasoningText: reasoning.isEmpty ? nil : reasoning.joined(separator: "\n\n"),
                        answerModel: nil,
                        timestamp: node.timestamp ?? p.timestamp,
                        attribution: .declared,
                        disposition: .retrievable))
                answered = true
            case ("assistant", _):
                if let text = node.text, !text.isEmpty { reasoning.append(text) }
            default:
                continue
            }
        }
        closeUnanswered()
    }

    /// Only `parts[].text` strings are answer text. Non-string parts are
    /// attachments and state no text of their own.
    private static func text(in content: [String: Any]?) -> String? {
        guard let parts = SnapshotJSON.array(content?["parts"]) else { return nil }
        let pieces = parts.compactMap { SnapshotJSON.string($0) }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined()
    }

    /// The export stamps messages as epoch seconds with a fraction.
    private static func epochStamp(_ value: Double?) -> String? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: value))
    }

    private static func diagnostic(
        path: String, sessionID: String?, part: String, kind: CollectionDiagnostic.Kind,
        detail: String
    ) -> CollectionDiagnostic {
        CollectionDiagnostic(
            kind: kind, sourceType: sourceType,
            locator: SnapshotLocator.describe(file: path, sessionID: sessionID, part: part),
            detail: detail)
    }
}
