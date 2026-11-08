import Foundation
import SQLite3

/// opencode's local store (`~/.local/share/opencode/opencode.db`): a SQLite
/// database whose `session_message` table holds one row per message, keyed by
/// `session_id` and ordered by `seq`.
///
/// This carrier is a database, not a document, so it does not implement
/// `SnapshotTranscriptSource`: there is no file whose bytes could be digested.
/// What the two paths share is the output — `SnapshotImport` — so the caller
/// treats both as one batch of turns.
///
/// Measured over the real store (213 messages, 2 sessions): `type` is
/// `user`, `assistant`, `idle`, `system` or `model-switched`; a user row states
/// `text`, while an assistant row states `content` as a parts array where only
/// `type == "text"` parts are answer text and `reasoning` parts are deliberation.
/// `finish` is `stop`, `tool-calls` or `error` — a tool-calls row usually carries
/// no text at all, so it is a step inside a round rather than an answer.
public enum OpenCodeSource {
    public static let sourceType = "opencode"
    public static let adapterVersion = "opencode-session-message/v1"

    public enum ReadError: Error, CustomStringConvertible {
        case unreadable(String)
        case missingStore(String)

        public var description: String {
            switch self {
            case .unreadable(let detail): return detail
            case .missingStore(let path): return "opencode store not found at \(path)"
            }
        }
    }

    public static func defaultDatabaseURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/share/opencode/opencode.db")
    }

    /// A file is this carrier only if it is a SQLite database carrying the
    /// message table; the name alone proves nothing.
    public static func recognizes(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, handle != nil
        else {
            if handle != nil { sqlite3_close(handle) }
            return false
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='session_message'"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    public static func collect(at url: URL = defaultDatabaseURL()) throws -> SnapshotImport {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadError.missingStore(url.path)
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, handle != nil
        else {
            throw ReadError.unreadable("cannot open \(url.path)")
        }
        defer { sqlite3_close(handle) }

        let sql = """
        SELECT id, session_id, seq, type, data FROM session_message
        WHERE type IN ('user','assistant') ORDER BY session_id, seq
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ReadError.unreadable(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        var digestSource = ""
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                let sessionText = sqlite3_column_text(statement, 1),
                let typeText = sqlite3_column_text(statement, 3)
            else { continue }
            let id = String(cString: idText)
            let sessionID = String(cString: sessionText)
            let type = String(cString: typeText)
            let seq = Int(sqlite3_column_int64(statement, 2))
            var data = Data()
            if let bytes = sqlite3_column_blob(statement, 4) {
                data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 4)))
            }
            digestSource += "\(id)|\(sessionID)|\(seq)|"
            rows.append(Row(id: id, sessionID: sessionID, seq: seq, type: type, data: data))
        }
        guard sqlite3_errcode(handle) == SQLITE_OK || sqlite3_errcode(handle) == SQLITE_DONE
        else {
            throw ReadError.unreadable(String(cString: sqlite3_errmsg(handle)))
        }

        var turns: [CollectedTurn] = []
        var diagnostics: [CollectionDiagnostic] = []
        var index = 0
        while index < rows.count {
            let row = rows[index]
            guard row.type == "user" else {
                index += 1
                continue
            }
            let promptText = userText(in: row.data)
            var cursor = index + 1
            var answer: (row: Row, text: String, reasoning: [String], finish: String?)?
            while cursor < rows.count, rows[cursor].sessionID == row.sessionID {
                if rows[cursor].type == "user" { break }
                if let parsed = assistantText(in: rows[cursor].data), !parsed.text.isEmpty {
                    answer = (rows[cursor], parsed.text, parsed.reasoning, parsed.finish)
                    break
                }
                cursor += 1
            }
            defer { index = max(cursor + 1, index + 1) }

            guard let promptText, !promptText.isEmpty else {
                diagnostics.append(
                    diagnostic(
                        sessionID: row.sessionID, part: "msg-\(row.id)",
                        kind: .skippedAttachment, detail: "user message states no text"))
                continue
            }
            guard let answer else {
                diagnostics.append(
                    diagnostic(
                        sessionID: row.sessionID, part: "msg-\(row.id)",
                        kind: .incompleteTurn,
                        detail: "no assistant text message follows this prompt in the store"))
                continue
            }
            turns.append(
                CollectedTurn(
                    identity: CollectionSourceIdentity(
                        sourceType: sourceType, sourceSessionID: row.sessionID,
                        sourceTurnID: "seq-\(row.seq)", sourceMessageID: answer.row.id,
                        sourceRevision: 1, adapterVersion: adapterVersion),
                    provider: sourceType,
                    sessionKey: "\(sourceType):\(row.sessionID)",
                    promptText: promptText,
                    answerText: answer.text,
                    reasoningText: answer.reasoning.isEmpty
                        ? nil : answer.reasoning.joined(separator: "\n\n"),
                    answerModel: nil,
                    timestamp: nil,
                    attribution: .fileOrderOnly,
                    disposition: answer.finish == "error"
                        ? .recordedIncompleteAnswer : .retrievable))
        }

        return SnapshotImport(
            turns: turns, diagnostics: diagnostics,
            contentDigest: CollectionDigest.sha256Hex(digestSource))
    }

    private struct Row {
        let id: String
        let sessionID: String
        let seq: Int
        let type: String
        let data: Data
    }

    private static func object(from data: Data) -> [String: Any]? {
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return value as? [String: Any]
    }

    private static func userText(in data: Data) -> String? {
        guard let object = object(from: data) else { return nil }
        return object["text"] as? String
    }

    private static func assistantText(
        in data: Data
    ) -> (text: String, reasoning: [String], finish: String?)? {
        guard let object = object(from: data) else { return nil }
        let parts = object["content"] as? [[String: Any]] ?? []
        var pieces: [String] = []
        var reasoning: [String] = []
        for part in parts {
            guard let type = part["type"] as? String,
                let text = part["text"] as? String
            else { continue }
            if type == "text" { pieces.append(text) }
            if type == "reasoning" { reasoning.append(text) }
        }
        return (pieces.joined(), reasoning, object["finish"] as? String)
    }

    private static func diagnostic(
        sessionID: String, part: String, kind: CollectionDiagnostic.Kind, detail: String
    ) -> CollectionDiagnostic {
        CollectionDiagnostic(
            kind: kind, sourceType: sourceType,
            locator: SnapshotLocator.describe(
                file: "opencode.db", sessionID: sessionID, part: part),
            detail: detail)
    }
}
