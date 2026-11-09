import Foundation

/// Codex's own session log (`~/.codex/sessions/**.jsonl`), one JSON object per
/// line.
///
/// The log is a stream of events, not a conversation: reasoning items, tool
/// calls and tool outputs are most of the bytes (measured on one 20 MB session:
/// 836 reasoning items, 1,076 function calls, 1,075 function outputs against
/// 171 message items). Only `response_item` / `message` lines carry what was
/// actually said, so only those become turns.
///
/// One round can produce several assistant messages (commentary while working,
/// then the reply). They are joined in arrival order into one answer: the
/// question is what the user asked, the answer is everything the assistant said
/// before the next question.
///
/// Injected user-role text (AGENTS.md, environment context, permissions) is not
/// something the user typed. It is skipped by structure, not by guessing at
/// length.
public enum RolloutSource: SnapshotTranscriptSource {
    public static let sourceType = "codex"
    public static let adapterVersion = "codex-rollout/v1"
    public static let sourceKind: TranscriptSourceKind = .appendOnlyLog

    public static func recognizes(_ data: Data) -> Bool {
        // The first line is the session header. It is matched structurally so a
        // JSON export that merely has a `type` field is not claimed.
        let head = String(decoding: data.prefix(8 * 1024), as: UTF8.self)
        return head.contains("\"type\":\"session_meta\"")
            && head.contains("\"session_id\"")
    }

    public static func interpret(
        _ data: Data, path: String, contentDigest: String
    ) throws -> SnapshotImport {
        var sessionID = (path as NSString).deletingPathExtension
        var turns: [CollectedTurn] = []
        var diagnostics: [CollectionDiagnostic] = []
        var prompt: String?
        var promptAt: String?
        var answerParts: [String] = []
        var turnIndex = 0
        var toolItems = 0
        var injected = 0

        func flush() {
            defer {
                prompt = nil
                promptAt = nil
                answerParts.removeAll()
            }
            guard let prompt, !prompt.isEmpty else { return }
            let answer = answerParts.joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            turnIndex += 1
            turns.append(
                CollectedTurn(
                    identity: RolloutSource.identity(
                        sessionID: sessionID, turnID: "turn-\(turnIndex)",
                        messageID: "turn-\(turnIndex)"),
                    provider: RolloutSource.sourceType,
                    // 与显式写入（`simigo_chat_round` 的 `codex-<id>`）同一
                    // 会话键：两条路径写的是同一段对话，内容去重才对得上。
                    sessionKey: "codex-\(sessionID)",
                    promptText: prompt,
                    answerText: answer,
                    reasoningText: nil,
                    answerModel: nil,
                    timestamp: promptAt,
                    attribution: .declared,
                    disposition: answer.isEmpty
                        ? .recordedIncompleteAnswer : .retrievable))
        }

        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(line.utf8)) as? [String: Any]
            else { continue }
            let type = object["type"] as? String
            let payload = object["payload"] as? [String: Any]
            if type == "session_meta" {
                if let id = payload?["session_id"] as? String, !id.isEmpty {
                    sessionID = id
                }
                continue
            }
            guard type == "response_item", let payload else { continue }
            switch payload["type"] as? String {
            case "function_call", "function_call_output", "custom_tool_call",
                "custom_tool_call_output", "web_search_call":
                toolItems += 1
            case "message":
                let role = payload["role"] as? String
                let body = Self.text(of: payload)
                guard !body.isEmpty else { continue }
                switch role {
                case "user":
                    guard !Self.isInjected(body) else {
                        injected += 1
                        continue
                    }
                    flush()
                    prompt = body
                    promptAt = SnapshotTimestamp.normalize(object["timestamp"] as? String)
                case "assistant":
                    answerParts.append(body)
                default:
                    break
                }
            default:
                break
            }
        }
        flush()

        if toolItems > 0 {
            diagnostics.append(
                CollectionDiagnostic(
                    kind: .toolTraffic, sourceType: sourceType,
                    locator: SnapshotLocator.describe(
                        file: path, sessionID: sessionID, part: "tool-items"),
                    detail:
                        "\(toolItems) tool/reasoning items are the agent's own traffic "
                        + "and are not imported"))
        }
        if injected > 0 {
            diagnostics.append(
                CollectionDiagnostic(
                    kind: .unsupportedShape, sourceType: sourceType,
                    locator: SnapshotLocator.describe(
                        file: path, sessionID: sessionID, part: "injected-user"),
                    detail:
                        "\(injected) injected user-role messages (instructions or "
                        + "environment) were skipped"))
        }
        return SnapshotImport(
            turns: turns, diagnostics: diagnostics, contentDigest: contentDigest)
    }

    private static func text(of payload: [String: Any]) -> String {
        guard let content = payload["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text the harness inserts into the user role. It is not a question, and
    /// importing it would make the instructions look like something the user
    /// said.
    private static func isInjected(_ text: String) -> Bool {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in [
            "# AGENTS.md instructions", "<environment_context>",
            "<user_instructions>", "<permissions instructions>",
            "<apps_instructions>", "<recommended_plugins>",
        ] where head.hasPrefix(prefix) {
            return true
        }
        return false
    }
}
