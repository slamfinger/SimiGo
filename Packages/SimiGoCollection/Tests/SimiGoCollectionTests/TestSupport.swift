import Foundation
@testable import SimiGoCollection

enum Fixture {
    static let sessionID = "session-1"
    static let projectID = "-Users-test-project"
    static let timestamp = "2026-10-31T00:00:00Z"

    static func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func userLine(
        uuid: String,
        parent: String? = nil,
        text: String,
        isMeta: Bool = false,
        originKind: String? = nil,
        isCompactSummary: Bool = false,
        isVisibleInTranscriptOnly: Bool = false,
        isSidechain: Bool = false,
        toolResult: Bool = false,
        image: Bool = false,
        sessionID: String = Fixture.sessionID,
        timestamp: String = Fixture.timestamp
    ) -> String {
        var content: [[String: Any]] = []
        if image {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/png", "data": ""],
            ])
        } else if toolResult {
            content.append([
                "type": "tool_result", "tool_use_id": "tool-1", "content": text,
            ])
        } else if !text.isEmpty {
            content.append(["type": "text", "text": text])
        }
        var object: [String: Any] = [
            "type": "user",
            "uuid": uuid,
            "sessionId": sessionID,
            "timestamp": timestamp,
            "isMeta": isMeta,
            "isCompactSummary": isCompactSummary,
            "isVisibleInTranscriptOnly": isVisibleInTranscriptOnly,
            "isSidechain": isSidechain,
            "message": ["role": "user", "content": content],
        ]
        if let parent { object["parentUuid"] = parent }
        if let originKind { object["origin"] = ["kind": originKind] }
        if toolResult { object["toolUseResult"] = ["ok": true] }
        return json(object)
    }

    static func assistantLine(
        uuid: String,
        parent: String? = nil,
        messageID: String,
        text: String,
        stop: String? = "end_turn",
        model: String = "test-model",
        apiError: Bool = false,
        sessionID: String = Fixture.sessionID,
        timestamp: String = Fixture.timestamp
    ) -> String {
        var blocks: [[String: Any]] = []
        if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
        var message: [String: Any] = [
            "id": messageID, "role": "assistant", "model": model, "content": blocks,
        ]
        if let stop { message["stop_reason"] = stop }
        var object: [String: Any] = [
            "type": "assistant", "uuid": uuid, "sessionId": sessionID,
            "timestamp": timestamp, "message": message,
        ]
        if let parent { object["parentUuid"] = parent }
        if apiError { object["isApiErrorMessage"] = true }
        return json(object)
    }

    static func systemCompactLine(
        uuid: String, text: String = "context compaction",
        sessionID: String = Fixture.sessionID, timestamp: String = Fixture.timestamp
    ) -> String {
        json([
            "type": "system", "uuid": uuid, "sessionId": sessionID,
            "timestamp": timestamp, "isCompactSummary": true, "content": text,
        ])
    }

    static func queuedLine(
        uuid: String,
        sourceUUID: String,
        prompt: String,
        parent: String? = nil,
        sessionID: String = Fixture.sessionID,
        timestamp: String = Fixture.timestamp
    ) -> String {
        var object: [String: Any] = [
            "type": "attachment", "uuid": uuid, "sessionId": sessionID,
            "timestamp": timestamp,
            "attachment": [
                "type": "queued_command", "source_uuid": sourceUUID,
                "prompt": [["type": "text", "text": prompt]],
                "origin": ["kind": "queued"],
            ],
        ]
        if let parent { object["parentUuid"] = parent }
        return json(object)
    }

    static func turnLines(
        anchor: String = "u-1", answerUUID: String = "a-1", messageID: String = "m-1",
        prompt: String = "hello", answer: String = "world", nextAnchor: String = "u-2",
        parent: String? = nil
    ) -> [String] {
        [
            userLine(uuid: anchor, parent: parent, text: prompt),
            assistantLine(uuid: answerUUID, parent: anchor, messageID: messageID, text: answer),
            userLine(uuid: nextAnchor, parent: answerUUID, text: "next"),
        ]
    }

    static func context(
        sessionID: String = Fixture.sessionID, isSubagent: Bool = false,
        path: String = "/tmp/transcript.jsonl"
    ) -> QoderTurnAccumulator.Context {
        QoderTurnAccumulator.Context(
            projectID: Fixture.projectID, sessionID: sessionID, path: path,
            isSubagent: isSubagent)
    }

    static func feed(
        _ accumulator: QoderTurnAccumulator, _ lines: [String], startingAt: Int64 = 1
    ) -> [QoderCollectionEvent] {
        var events: [QoderCollectionEvent] = []
        for (index, line) in lines.enumerated() {
            let entry = try! QoderTranscriptLineParser.parse(Data(line.utf8))
            events.append(
                contentsOf: accumulator.ingest(
                    entry, segmentLine: startingAt + Int64(index)))
        }
        return events
    }

    static func turns(_ events: [QoderCollectionEvent]) -> [QoderCollectedTurn] {
        events.compactMap {
            if case .turn(let turn) = $0 { return turn }
            return nil
        }
    }

    static func closures(_ events: [QoderCollectionEvent]) -> [QoderTurnClosure] {
        events.compactMap {
            if case .closedWithoutAnswer(let closure) = $0 { return closure }
            return nil
        }
    }

    static func baselines(_ events: [QoderCollectionEvent]) -> [QoderBaselineEvent] {
        events.compactMap {
            if case .baseline(let event) = $0 { return event }
            return nil
        }
    }

    static func compactions(_ events: [QoderCollectionEvent]) -> [QoderCompactionEvent] {
        events.compactMap {
            if case .compaction(let event) = $0 { return event }
            return nil
        }
    }

    static func orphans(_ events: [QoderCollectionEvent]) -> [QoderOrphanAssistant] {
        events.compactMap {
            if case .orphanAssistant(let event) = $0 { return event }
            return nil
        }
    }

    static func failures(_ events: [QoderCollectionEvent]) -> [QoderParseFailure] {
        events.compactMap {
            if case .parseFailure(let event) = $0 { return event }
            return nil
        }
    }

    static func append(_ text: String, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    static func appendLine(_ line: String, to url: URL) throws {
        try append(line + "\n", to: url)
    }

    static func writeLines(_ lines: [String], to url: URL, append: Bool = false) throws {
        let text = lines.map { $0 + "\n" }.joined()
        if append {
            try Fixture.append(text, to: url)
        } else {
            try text.write(to: url, atomically: false, encoding: .utf8)
        }
    }
}

/// Synthetic whole-file snapshots.
///
/// Every document here is invented: no real conversation, export or account file
/// from the reference corpus is copied into the package. The shapes and the
/// fields that are present or absent follow the measurements recorded in each
/// adapter's documentation, so a fixture states the same facts a real export
/// states without containing one.
enum SnapshotFixture {
    static func file(_ object: Any, named name: String, in test: String) throws -> URL {
        try file(encode(object), named: name, in: test)
    }

    static func file(_ data: Data, named name: String, in test: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-snapshot-" + test, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    static func encode(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// The instant an adapter's normalized stamp names, read back with a
    /// formatter the adapters never use. Comparing instants instead of strings
    /// keeps the assertion independent of the bridge's own output shape.
    static func instant(_ timestamp: String?) -> Double? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)?.timeIntervalSince1970
    }

    /// Reads back a normalized stamp with the form the delivery sink accepts.
    /// nil when the bridge did not emit that form, which is itself the fact a
    /// caller asserts.
    static func parsed(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
    }

    /// The instant a test intends, built from UTC calendar components instead of
    /// from any formatter the bridge uses, so the comparison is independent of
    /// the code under test.
    static func moment(
        year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    static func matching(
        _ snapshot: SnapshotImport, _ kind: CollectionDiagnostic.Kind
    ) -> [CollectionDiagnostic] {
        snapshot.diagnostics.filter { $0.kind == kind }
    }

    // MARK: - Flat message export

    static func flatRow(
        id: Int,
        role: String,
        text: String = "row",
        finish: String? = nil,
        reasoning: String? = nil,
        modelSwitch: Bool = false,
        compacted: Bool = false,
        timestamp: Double = 1_760_000_000
    ) -> [String: Any] {
        var row: [String: Any] = [
            "id": id, "role": role, "content": text, "timestamp": timestamp,
            "observed": 0,
        ]
        if let finish { row["finish_reason"] = finish }
        if let reasoning {
            row["reasoning"] = reasoning
            row["reasoning_content"] = reasoning
        }
        if modelSwitch { row["display_kind"] = "model_switch" }
        if compacted { row["compacted"] = 1 }
        return row
    }

    static func flatDocument(
        _ rows: [[String: Any]], sessionID: String? = "flat-session-1",
        messageCount: Int? = nil
    ) -> [String: Any] {
        var document: [String: Any] = [
            "exported_at": "2026-11-07T00:00:00Z",
            "message_count": messageCount ?? rows.count,
            "messages": rows,
            "session": NSNull(),
            "title": "synthetic export",
        ]
        if let sessionID { document["session_id"] = sessionID }
        return document
    }

    // MARK: - AI Studio prompt export

    static func aiChunk(
        role: String,
        text: String? = "chunk",
        thought: Bool = false,
        thoughtInParts: Bool = false,
        finish: String? = nil,
        errorMessage: String? = nil,
        branch: Bool = false,
        functionCall: Bool = false,
        createTime: String? = "2026-11-07T00:00:00Z"
    ) -> [String: Any] {
        var chunk: [String: Any] = ["role": role]
        if let text { chunk["text"] = text }
        if thought { chunk["isThought"] = true }
        if let finish { chunk["finishReason"] = finish }
        if let errorMessage { chunk["errorMessage"] = errorMessage }
        if branch {
            chunk["branchParent"] = ["id": "synthetic-parent"]
            chunk["branchChildren"] = [["id": "synthetic-child"]]
        }
        var parts: [[String: Any]] = []
        if let text { parts.append(["text": text, "thought": thoughtInParts]) }
        if functionCall {
            parts.append(["functionCall": ["name": "synthetic_tool", "args": [:]]])
        }
        if !parts.isEmpty { chunk["parts"] = parts }
        if let createTime { chunk["createTime"] = createTime }
        return chunk
    }

    static func aiDocument(
        _ chunks: [[String: Any]], pendingInputs: [[String: Any]] = [],
        model: String = "synthetic-gemini"
    ) -> [String: Any] {
        [
            "chunkedPrompt": ["chunks": chunks, "pendingInputs": pendingInputs],
            "runSettings": ["model": model, "temperature": 1.0],
            "systemInstruction": NSNull(),
        ]
    }

    // MARK: - DeepSeek conversation mapping

    /// The carrier's own fragment shapes: `SEARCH`, `TOOL_SEARCH` and `FILE`
    /// state no `content` in any real export, so a fixture that gave them text
    /// would test a document that does not exist.
    static func dsFragment(type: String, content: String? = nil) -> [String: Any] {
        var fragment: [String: Any] = ["type": type]
        if let content { fragment["content"] = content }
        switch type {
        case "SEARCH", "TOOL_SEARCH": fragment["results"] = []
        case "FILE": fragment["files"] = []
        default: break
        }
        return fragment
    }

    static func dsNode(
        id: String,
        parent: String?,
        children: [String] = [],
        fragments: [[String: Any]]? = [["type": "REQUEST", "content": "question"]],
        model: String = "deepseek-chat",
        insertedAt: String = "2026-11-07T08:00:00.000000+00:00"
    ) -> [String: Any] {
        var node: [String: Any] = ["id": id, "children": children]
        if let parent {
            node["parent"] = parent
        } else {
            node["parent"] = NSNull()
        }
        if let fragments {
            node["message"] = [
                "fragments": fragments, "inserted_at": insertedAt, "model": model,
            ]
        } else {
            node["message"] = NSNull()
        }
        return node
    }

    /// The mapping is keyed by the node's own id, as it is in the real export, so
    /// a test cannot give a node one key under `parent` and another in the map.
    static func dsNodes(_ nodes: [[String: Any]]) -> [String: Any] {
        Dictionary(
            uniqueKeysWithValues: nodes.map {
                (($0["id"] as? String) ?? "", $0)
            })
    }

    static func dsConversation(
        id: String?, nodes: [[String: Any]], title: String = "synthetic conversation"
    ) -> [String: Any] {
        var conversation: [String: Any] = [
            "mapping": dsNodes(nodes), "title": title,
            "inserted_at": "2026-11-07T08:00:00.000000+00:00",
            "updated_at": "2026-11-07T08:05:00.000000+00:00",
        ]
        if let id { conversation["id"] = id }
        return conversation
    }
}
