import Foundation

public enum QoderUserEntryKind: String, Sendable, Equatable {
    case humanPrompt = "human_prompt"
    case continuationPrompt = "continuation_prompt"
    case notificationPrompt = "notification_prompt"
    case supervisionCallback = "supervision_callback"
    case compactSummary = "compact_summary"
    case interruptMarker = "interrupt_marker"
    case meta
    case toolResult = "tool_result"
    case imageOnly = "image_only"
    case emptyUserInput = "empty_user_input"
    case injectedContext = "injected_context"
}

public enum QoderAssistantTerminalKind: String, Sendable, Equatable {
    case answerCandidate = "answer_candidate"
    case emptyAnswer = "empty_answer"
    case stopSequence = "stop_sequence"
    case executionEvent = "execution_event"
    case apiError = "api_error"
    case ambiguousTerminal = "ambiguous_terminal"
    case unknownStop = "unknown_stop"
}

public struct QoderUserClassification: Sendable, Equatable {
    public let kind: QoderUserEntryKind
    /// Text with known injected context prefixes removed; the anchor's
    /// semantic prompt. For non-prompt entries this is the trimmed raw text.
    public let strippedText: String
    public let injectedPrefixes: [String]
}

public enum QoderTranscriptClassifier {
    public static let knownInjectedTags: Set<String> = [
        "qoder_delegated_input_sources", "system-reminder", "qoder_system_reminder",
    ]

    static let continuationMarkers: [String] = [
        "Continue working toward the active thread goal",
        "A goal has been set.",
    ]

    private static let supervisionPrefix = "[监督回调]"
    private static let notificationPrefix = "[SYSTEM NOTIFICATION - NOT USER INPUT]"

    private static let interruptRegex = try! NSRegularExpression(
        pattern: #"^\s*\[Request interrupted by user(?: for tool use)?\]\s*$"#)

    public static func classifyUser(
        _ entry: QoderTranscriptEntry
    ) -> QoderUserClassification {
        let message = entry.message
        let blocks = message?.blocks ?? []
        let rawText = message?.text ?? ""
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        if entry.hasToolUseResult || blocks.contains(where: { $0.type == "tool_result" }) {
            return .init(kind: .toolResult, strippedText: trimmed, injectedPrefixes: [])
        }
        if entry.isCompactSummary || entry.isVisibleInTranscriptOnly {
            return .init(kind: .compactSummary, strippedText: trimmed, injectedPrefixes: [])
        }
        if isInterruptMarker(rawText) {
            return .init(kind: .interruptMarker, strippedText: trimmed, injectedPrefixes: [])
        }
        if leadingTrimmed(rawText).hasPrefix(supervisionPrefix) {
            return .init(kind: .supervisionCallback, strippedText: trimmed, injectedPrefixes: [])
        }
        if entry.isMeta {
            let lead = leadingTrimmed(rawText)
            if continuationMarkers.contains(where: { lead.hasPrefix($0) }) {
                return .init(kind: .continuationPrompt, strippedText: trimmed, injectedPrefixes: [])
            }
            if entry.originKind == "task-notification" || lead.hasPrefix(notificationPrefix) {
                return .init(kind: .notificationPrompt, strippedText: trimmed, injectedPrefixes: [])
            }
            return .init(kind: .meta, strippedText: trimmed, injectedPrefixes: [])
        }
        if trimmed.isEmpty {
            let hasImage = blocks.contains(where: { $0.isImage })
            return .init(
                kind: hasImage ? .imageOnly : .emptyUserInput,
                strippedText: "", injectedPrefixes: [])
        }
        let (stripped, prefixes) = stripInjectedPrefixes(rawText)
        if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .init(kind: .injectedContext, strippedText: stripped, injectedPrefixes: prefixes)
        }
        return .init(kind: .humanPrompt, strippedText: stripped, injectedPrefixes: prefixes)
    }

    public static func classifyAssistantTerminal(
        _ entry: QoderTranscriptEntry, text: String, ambiguous: Bool
    ) -> QoderAssistantTerminalKind {
        classifyTerminal(
            stop: entry.message?.stopReason, text: text,
            apiError: entry.isAPIMessageError, ambiguous: ambiguous)
    }

    public static func classifyTerminal(
        stop: String?, text: String, apiError: Bool, ambiguous: Bool
    ) -> QoderAssistantTerminalKind {
        if ambiguous { return .ambiguousTerminal }
        if apiError { return .apiError }
        switch stop {
        case "end_turn":
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .emptyAnswer : .answerCandidate
        case "stop_sequence":
            return .stopSequence
        case "tool_use":
            return .executionEvent
        default:
            return .unknownStop
        }
    }

    /// Strip leading injected-context elements such as `<system-reminder>`.
    /// Only known tag names are stripped; an unknown leading element is kept
    /// verbatim so a real prompt is never silently rewritten.
    public static func stripInjectedPrefixes(_ text: String) -> (String, [String]) {
        var rest = text[...]
        var prefixes: [String] = []
        while true {
            var index = rest.startIndex
            while index < rest.endIndex, rest[index].isWhitespace {
                index = rest.index(after: index)
            }
            guard index < rest.endIndex, rest[index] == "<" else { break }
            guard let close = rest[index...].firstIndex(of: ">") else { break }
            let inner = rest[rest.index(after: index)..<close]
            let name = String(inner.prefix { !$0.isWhitespace })
            guard !name.isEmpty, knownInjectedTags.contains(name) else { break }
            let closing = "</\(name)>"
            guard let range = rest.range(of: closing, range: index..<rest.endIndex) else {
                break
            }
            rest = rest[range.upperBound...]
            prefixes.append(name)
        }
        return (String(rest), prefixes)
    }

    private static func leadingTrimmed(_ text: String) -> String {
        String(text.drop { $0.isWhitespace })
    }

    private static func isInterruptMarker(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return interruptRegex.firstMatch(in: text, options: [], range: range) != nil
    }
}
