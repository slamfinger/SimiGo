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
