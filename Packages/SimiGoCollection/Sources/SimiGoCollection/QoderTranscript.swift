import Foundation

public struct QoderContentBlock: Sendable, Equatable {
    public let type: String
    public let text: String
    public let toolUseID: String?
    public let toolName: String?
    public let toolResultIsError: Bool
    public let isImage: Bool
}

public struct QoderTranscriptMessage: Sendable, Equatable {
    public let role: String?
    public let id: String?
    public let model: String?
    public let stopReason: String?
    public let stopSequence: String?
    public let blocks: [QoderContentBlock]
    public let text: String
}

public struct QoderAttachment: Sendable, Equatable {
    public let type: String
    public let sourceUUID: String?
    public let promptText: String
    public let originKind: String?
}

public struct QoderTranscriptEntry: Sendable, Equatable {
    public let type: String
    public let uuid: String?
    public let parentUUID: String?
    public let sessionID: String?
    public let timestamp: String?
    public let isMeta: Bool
    public let isCompactSummary: Bool
    public let isVisibleInTranscriptOnly: Bool
    public let isSidechain: Bool
    public let originKind: String?
    public let requestSetID: String?
    public let isAPIMessageError: Bool
    public let promptID: String?
    public let hasToolUseResult: Bool
    public let errorText: String?
    public let displayErrorCode: String?
    public let message: QoderTranscriptMessage?
    public let attachment: QoderAttachment?
}

public enum QoderTranscriptParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformedJSON(String)
    case notAnObject

    public var description: String {
        switch self {
        case .malformedJSON(let detail): return "malformed transcript JSON: \(detail)"
        case .notAnObject: return "transcript line is not a JSON object"
        }
    }
}

public enum QoderTranscriptLineParser {
    public static func parse(_ data: Data) throws -> QoderTranscriptEntry {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw QoderTranscriptParseError.malformedJSON(String(describing: error))
        }
        guard let json = object as? [String: Any] else {
            throw QoderTranscriptParseError.notAnObject
        }
        let messageObject = json.qObject("message")
        return QoderTranscriptEntry(
            type: json.qString("type") ?? "",
            uuid: json.qString("uuid"),
            parentUUID: json.qString("parentUuid"),
            sessionID: json.qString("sessionId"),
            timestamp: json.qTimestamp(),
            isMeta: json.qBool("isMeta") ?? false,
            isCompactSummary: json.qBool("isCompactSummary") ?? false,
            isVisibleInTranscriptOnly: json.qBool("isVisibleInTranscriptOnly") ?? false,
            isSidechain: json.qBool("isSidechain") ?? false,
            originKind: json.qObject("origin")?.qString("kind"),
            requestSetID: json.qString("requestSetId"),
            isAPIMessageError: json.qBool("isApiErrorMessage") ?? false,
            promptID: json.qString("promptId"),
            hasToolUseResult: json.qHas("toolUseResult"),
            errorText: json.qString("error"),
            displayErrorCode: json.qString("displayErrorCode"),
            message: messageObject.map(parseMessage),
            attachment: json.qObject("attachment").map(parseAttachment)
        )
    }

    private static func parseMessage(_ json: [String: Any]) -> QoderTranscriptMessage {
        let content = json["content"]
        let blocks = parseBlocks(content)
        let text: String
        if let string = content as? String {
            text = string
        } else {
            text = blocks.filter { $0.type == "text" }.map(\.text).joined()
        }
        return QoderTranscriptMessage(
            role: json.qString("role"),
            id: json.qString("id"),
            model: json.qString("model"),
            stopReason: json.qString("stop_reason"),
            stopSequence: json.qString("stop_sequence"),
            blocks: blocks,
            text: text
        )
    }

    private static func parseBlocks(_ content: Any?) -> [QoderContentBlock] {
        guard let array = content as? [Any] else { return [] }
        return array.compactMap { item in
            guard let object = item as? [String: Any],
                let type = object.qString("type")
            else { return nil }
            return QoderContentBlock(
                type: type,
                text: object.qString("text") ?? "",
                toolUseID: object.qString("id") ?? object.qString("tool_use_id"),
                toolName: object.qString("name"),
                toolResultIsError: object.qBool("is_error") ?? false,
                isImage: type == "image")
        }
    }

    private static func parseAttachment(_ json: [String: Any]) -> QoderAttachment {
        let prompt = json["prompt"]
        let promptText: String
        if let string = prompt as? String {
            promptText = string
        } else if let blocks = prompt as? [Any] {
            promptText = blocks.compactMap { item -> String? in
                guard let object = item as? [String: Any],
                    object.qString("type") == "text"
                else { return nil }
                return object.qString("text")
            }.joined()
        } else {
            promptText = ""
        }
        return QoderAttachment(
            type: json.qString("type") ?? "",
            sourceUUID: json.qString("source_uuid"),
            promptText: promptText,
            originKind: json.qObject("origin")?.qString("kind")
        )
    }
}

private extension Dictionary where Key == String, Value == Any {
    func qString(_ key: String) -> String? {
        self[key] as? String
    }

    func qBool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        return nil
    }

    func qObject(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func qHas(_ key: String) -> Bool {
        keys.contains(key)
    }

    func qTimestamp() -> String? {
        if let value = self["timestamp"] as? String { return value }
        if let value = self["timestamp"] as? NSNumber {
            return String(value.int64Value)
        }
        return nil
    }
}
