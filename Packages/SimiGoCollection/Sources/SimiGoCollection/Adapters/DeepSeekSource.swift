import Foundation

/// DeepSeek's `conversations.json`: one file holds every conversation, and each
/// conversation is a node tree rather than a list of rows.
///
/// Measured over the real export (142 conversations, 2542 nodes): every node has
/// exactly `children`, `id`, `message`, `parent`; `parent` and `children` agree in
/// both directions with no exceptions, and node ids are unique only inside one
/// conversation, which is why the identity carries the conversation id. A node
/// holds a fragment *sequence*, and the sequence decides what the node is:
/// - a prompt node carries `REQUEST` first (or `FILE` then `REQUEST` 12 times) and
///   never a `RESPONSE`;
/// - an answer node ends with exactly one `RESPONSE` — `RESPONSE` is never
///   followed by another fragment in any of the 1183 answer nodes — and may carry
///   `THINK`, `SEARCH`, `TOOL_OPEN`, `TOOL_SEARCH` or `TOOL_FIND` in front of it;
/// - every `RESPONSE` node is the child of a prompt node, with no exceptions.
///
/// That last fact is what makes this carrier stronger than the other two: the
/// prompt/answer binding is stated by the document, so `attribution` is
/// `.declared` rather than file order. The binding is still read in both
/// directions — the child must also name this node as its `parent` — because a
/// one-sided link is the carrier contradicting itself, not evidence.
///
/// Completion has no marker to read, so it comes from structure: 22 prompt nodes
/// have a child that never reached a `RESPONSE` (it stops at `THINK` or at tool
/// traffic), and those are recorded as incomplete instead of being treated as
/// short answers. Four prompt nodes carry 2 to 5 `RESPONSE` siblings — regenerations
/// that the export does not resolve into a kept branch — so no turn is emitted for
/// them at all: picking one would invent which answer the user accepted.
///
/// `THINK` content only ever travels into `reasoningText`. `SEARCH`, `TOOL_*` and
/// `FILE` fragments state no `content` at all, so nothing is dropped from an
/// answer by excluding them; they are reported because the round used tools.
public enum DeepSeekSource: SnapshotTranscriptSource {
    public static let sourceType = "deepseek"
    public static let adapterVersion = "deepseek-mapping/v1"
    public static let sourceKind: TranscriptSourceKind = .wholeFileSnapshot

    /// Fragment types this carrier is known to use. Anything else is an
    /// unrecognised marker, not an empty fragment.
    private static let knownFragments: Set<String> = [
        "REQUEST", "RESPONSE", "THINK", "SEARCH", "TOOL_OPEN", "TOOL_SEARCH", "TOOL_FIND", "FILE",
    ]

    private struct Node {
        let key: String
        let parent: String?
        let children: [String]
        let fragments: [Fragment]
        let model: String?
        let insertedAt: String?
    }

    private struct Fragment {
        let type: String
        let text: String?
    }

    public static func recognizes(_ data: Data) -> Bool {
        SnapshotShape.matches(data) { value in
            guard let conversations = SnapshotJSON.array(value), !conversations.isEmpty
            else { return false }
            // A `mapping` key alone is not enough: ChatGPT's export has one too.
            // This carrier states `children` on its nodes; that export never does.
            return conversations.allSatisfy { item in
                guard let mapping = SnapshotJSON.object(
                    SnapshotJSON.object(item)?["mapping"]), !mapping.isEmpty
                else { return false }
                return mapping.values.contains {
                    SnapshotJSON.object($0)?["children"] != nil
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
            guard let mapping = SnapshotJSON.object(conversation["mapping"]) else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: SnapshotJSON.identifier(conversation["id"]),
                        part: "mapping", kind: .unsupportedShape,
                        detail: "mapping is not an object; nothing can be read from this conversation")
                )
                continue
            }
            guard let sessionID = SnapshotJSON.identifier(conversation["id"]) else {
                // Without the conversation id there is no session to bind turns to,
                // and inventing one from the position would collide on re-export.
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: nil, part: "conversation-\(position)",
                        kind: .unsupportedShape,
                        detail:
                            "conversation states no id; its "
                            + "\(mapping.count) nodes are not imported under a derived identity")
                )
                continue
            }
            read(
                mapping: mapping, path: path, sessionID: sessionID,
                turns: &turns, diagnostics: &diagnostics)
        }
        return SnapshotImport(
            turns: turns, diagnostics: diagnostics, contentDigest: contentDigest)
    }

    private static func read(
        mapping: [String: Any], path: String, sessionID: String,
        turns: inout [CollectedTurn], diagnostics: inout [CollectionDiagnostic]
    ) {
        var nodes: [String: Node] = [:]
        nodes.reserveCapacity(mapping.count)
        for (key, value) in mapping {
            guard let object = SnapshotJSON.object(value) else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: "node-\(key)",
                        kind: .unsupportedShape, detail: "node is not an object")
                )
                continue
            }
            nodes[key] = Node(
                key: key,
                parent: SnapshotJSON.string(object["parent"]),
                children: (SnapshotJSON.array(object["children"]) ?? []).compactMap {
                    SnapshotJSON.string($0)
                },
                fragments: fragments(in: object),
                model: SnapshotJSON.string(SnapshotJSON.object(object["message"])?["model"]),
                insertedAt: SnapshotTimestamp.normalize(
                    SnapshotJSON.string(SnapshotJSON.object(object["message"])?["inserted_at"]))
            )
        }

        // Order comes from each prompt node's own stamp and is only for reporting:
        // the prompt/answer binding below never depends on it.
        let prompts = nodes.values.filter { $0.fragments.contains { $0.type == "REQUEST" } }
            .sorted { lhs, rhs in
                if lhs.insertedAt != rhs.insertedAt {
                    return (lhs.insertedAt ?? "") < (rhs.insertedAt ?? "")
                }
                return numericOrder(lhs.key, rhs.key)
            }

        for prompt in prompts {
            let requests = prompt.fragments.filter { $0.type == "REQUEST" }
            guard let request = requests.first, requests.count == 1 else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: "node-\(prompt.key)",
                        kind: .unsupportedShape,
                        detail: "\(requests.count) REQUEST fragments in one node: the prompt is ambiguous")
                )
                continue
            }
            guard let promptText = request.text else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: "node-\(prompt.key)",
                        kind: .unsupportedShape,
                        detail: "REQUEST fragment states no content")
                )
                continue
            }
            if prompt.fragments.contains(where: { $0.type == "FILE" }) {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: "node-\(prompt.key)",
                        kind: .skippedAttachment,
                        detail: "the prompt node also carries a FILE fragment; it states no text")
                )
            }

            var answers: [Node] = []
            for childKey in prompt.children {
                guard let child = nodes[childKey] else {
                    diagnostics.append(
                        diagnostic(
                            path: path, sessionID: sessionID, part: "node-\(prompt.key)",
                            kind: .unsupportedShape,
                            detail: "child \(childKey) is not in the mapping")
                    )
                    continue
                }
                if child.fragments.contains(where: { $0.type == "RESPONSE" }) {
                    answers.append(child)
                }
            }
            guard !answers.isEmpty else {
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: "node-\(prompt.key)",
                        kind: .incompleteTurn,
                        detail:
                            "no child of this prompt node reached a RESPONSE fragment"
                            + (prompt.children.isEmpty ? " (it has no children)" : ""))
                )
                continue
            }
            guard answers.count == 1 else {
                // The export keeps every regeneration and does not say which one
                // the user kept, so none of them can be chosen here.
                diagnostics.append(
                    diagnostic(
                        path: path, sessionID: sessionID, part: "node-\(prompt.key)",
                        kind: .unboundAnswer,
                        detail:
                            "\(answers.count) sibling answers under one prompt "
                            + "(\(answers.map(\.key).joined(separator: ", "))); the carrier does not "
                            + "resolve which one was kept, so no turn is imported")
                )
                continue
            }
            emitTurn(
                prompt: prompt, promptText: promptText, answer: answers[0], nodes: nodes,
                path: path, sessionID: sessionID, turns: &turns, diagnostics: &diagnostics)
        }
    }

    private static func emitTurn(
        prompt: Node, promptText: String, answer: Node, nodes: [String: Node],
        path: String, sessionID: String,
        turns: inout [CollectedTurn], diagnostics: inout [CollectionDiagnostic]
    ) {
        let responses = answer.fragments.filter { $0.type == "RESPONSE" }
        guard let response = responses.first, responses.count == 1 else {
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "node-\(answer.key)",
                    kind: .unsupportedShape,
                    detail: "\(responses.count) RESPONSE fragments in one answer node")
            )
            return
        }
        guard let answerText = response.text else {
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "node-\(answer.key)",
                    kind: .incompleteTurn,
                    detail: "RESPONSE fragment states no content")
            )
            return
        }

        let reasoning = answer.fragments.filter { $0.type == "THINK" }.compactMap(\.text)
        let toolKinds = answer.fragments.filter {
            $0.type == "SEARCH" || $0.type == "TOOL_OPEN" || $0.type == "TOOL_SEARCH"
                || $0.type == "TOOL_FIND"
        }
        let unknown = answer.fragments.filter { !knownFragments.contains($0.type) }

        var disposition: CollectionTurnDisposition = .retrievable
        if !unknown.isEmpty {
            // An unrecognised marker in the answer means something happened in
            // this round that this adapter cannot classify.
            disposition = .recordedIncompleteAnswer
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "node-\(answer.key)",
                    kind: .unsupportedShape,
                    detail:
                        "unrecognised fragment type(s) \(unknown.map(\.type).sorted().joined(separator: ", "))"
                )
            )
        }
        if !toolKinds.isEmpty {
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "node-\(answer.key)",
                    kind: .toolTraffic,
                    detail:
                        "\(toolKinds.count) search/tool fragment(s) precede the answer; "
                        + "they state no content, so nothing is dropped from the answer")
            )
        }
        // The prompt names this node as its child; the node must name the prompt
        // back. A link only stated one way is not a declared binding.
        guard answer.parent == prompt.key else {
            diagnostics.append(
                diagnostic(
                    path: path, sessionID: sessionID, part: "node-\(answer.key)",
                    kind: .unsupportedShape,
                    detail:
                        "the answer node names \(answer.parent ?? "no parent") rather than its "
                        + "prompt node, so the binding is not declared on both sides")
            )
            return
        }

        turns.append(
            CollectedTurn(
                identity: identity(
                    sessionID: sessionID, turnID: prompt.key, messageID: answer.key),
                provider: sourceType,
                sessionKey: sessionKey(projectID: "", sessionID: sessionID),
                promptText: promptText,
                answerText: answerText,
                reasoningText: reasoning.isEmpty ? nil : reasoning.joined(separator: "\n\n"),
                answerModel: answer.model,
                timestamp: answer.insertedAt ?? prompt.insertedAt,
                attribution: .declared,
                disposition: disposition))
    }

    private static func fragments(in object: [String: Any]) -> [Fragment] {
        guard let message = SnapshotJSON.object(object["message"]),
            let raw = SnapshotJSON.array(message["fragments"])
        else { return [] }
        return raw.compactMap { value in
            guard let fragment = SnapshotJSON.object(value),
                let type = SnapshotJSON.string(fragment["type"])
            else { return nil }
            return Fragment(type: type, text: SnapshotText.usable(fragment["content"]))
        }
    }

    /// Node ids are short numeric strings inside a conversation, so a numeric
    /// comparison is the order the carrier itself used when creating them.
    private static func numericOrder(_ lhs: String, _ rhs: String) -> Bool {
        if let left = Int(lhs), let right = Int(rhs), left != right { return left < right }
        return lhs < rhs
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
