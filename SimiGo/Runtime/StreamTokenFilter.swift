import Foundation
import CryptoKit
import MLXLMCommon

// MARK: - Raw <tool_call> Stream Fallback Parser

struct RawToolCallParserFailure: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

nonisolated final class RawToolCallStreamParser: @unchecked Sendable {
    private static let openTag = "<tool_call>"
    private static let closeTag = "</tool_call>"
    private var buffer = ""
    private var insideToolCall = false
    private(set) var rawToolCallDetected = false
    private(set) var failure: RawToolCallParserFailure?
    private static let openHoldback = openTag.count - 1

    nonisolated func feed(_ text: String, onText: (String) -> Void, onToolCall: (ParsedToolCall) -> Void) {
        guard !text.isEmpty, failure == nil else { return }

        buffer.append(contentsOf: text)

        while failure == nil {
            if insideToolCall {
                guard let closeRange = buffer.range(of: Self.closeTag) else { return }

                let body = String(buffer[..<closeRange.lowerBound])
                buffer = String(buffer[closeRange.upperBound...])
                rawToolCallDetected = true

                guard let call = parseToolCall(body) else {
                    failure = RawToolCallParserFailure(message: "Malformed raw <tool_call> payload")
                    buffer = ""
                    insideToolCall = false
                    return
                }

                onToolCall(call)
                insideToolCall = false
                continue
            }

            guard let openRange = buffer.range(of: Self.openTag) else {
                if buffer.count > Self.openHoldback {
                    let outputCount = buffer.count - Self.openHoldback
                    let splitIndex = buffer.index(buffer.startIndex, offsetBy: outputCount)
                    let output = String(buffer[..<splitIndex])
                    buffer = String(buffer[splitIndex...])

                    if !output.isEmpty {
                        onText(output)
                    }
                }

                return
            }

            let before = String(buffer[..<openRange.lowerBound])

            if !before.isEmpty {
                onText(before)
            }

            buffer = String(buffer[openRange.upperBound...])
            insideToolCall = true
            rawToolCallDetected = true
        }
    }

    nonisolated func flush(onText: (String) -> Void) {
        guard failure == nil else { return }

        if insideToolCall {
            failure = RawToolCallParserFailure(message: "Incomplete raw <tool_call> at end of generation")
            buffer = ""
            insideToolCall = false
            return
        }

        if !buffer.isEmpty {
            onText(buffer)
        }

        buffer = ""
    }

    private nonisolated func parseToolCall(_ rawBody: String) -> ParsedToolCall? {
        let trimmed = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let rawName = dictionary["name"] as? String else {
            return nil
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, dictionary.keys.contains("arguments") else {
            return nil
        }

        let rawArguments = dictionary["arguments"]
        let argumentDictionary: [String: Any]

        if let dictionary = rawArguments as? [String: Any] {
            argumentDictionary = dictionary
        } else if let argumentString = rawArguments as? String {
            let trimmedArguments = argumentString.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let argumentData = trimmedArguments.data(using: .utf8),
                  let argumentObject = try? JSONSerialization.jsonObject(with: argumentData),
                  let dictionary = argumentObject as? [String: Any] else {
                return nil
            }

            argumentDictionary = dictionary
        } else {
            return nil
        }

        guard JSONSerialization.isValidJSONObject(argumentDictionary),
              let argumentData = try? JSONSerialization.data(withJSONObject: argumentDictionary, options: [.sortedKeys]),
              let normalizedArguments = try? JSONDecoder().decode([String: JSONValue].self, from: argumentData) else {
            return nil
        }

        let callId: String

        if let rawId = dictionary["id"] as? String,
           !rawId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            callId = rawId
        } else {
            callId = UUID().uuidString
        }

        return ParsedToolCall(id: callId, name: name, arguments: normalizedArguments)
    }
}

// MARK: - Stream Token Filter

nonisolated final class StreamTokenFilter: @unchecked Sendable {
    private static let thinkStartTags = ["<think>", "<|start_of_think|>", "<thought>", "<|thought|>"]
    private static let thinkEndTags = ["</think>", "<|end_of_think|>", "</thought>", "<|end_of_thought|>"]

    private static let knownSpecialTokens: Set<String> = [
        "<|im_start|>", "<|im_end|>", "<|endoftext|>", "<|assistant|>",
        "<|user|>", "<|system|>", "<|tool|>", "<|eot_id|>",
        "<|eom_id|>", "<|begin_of_text|>", "<|end_of_text|>",
        "<|start_header_id|>", "<|end_header_id|>"
    ]

    private var buffer = ""
    private var pendingText = ""
    private var isInsideThink = false
    private let disableThinking: Bool
    private static let maxPendingCharacters = 128

    nonisolated init(disableThinking: Bool = false) {
        self.disableThinking = disableThinking
    }

    // MARK: Feed

    nonisolated func feed(_ text: String, onChunk: (String) -> Void) {
        guard !text.isEmpty else { return }

        buffer.append(contentsOf: text)

        while true {
            if isInsideThink {
                if let endRange = earliestRange(in: buffer, tags: Self.thinkEndTags) {
                    buffer = String(buffer[endRange.upperBound...])
                    isInsideThink = false
                    continue
                }

                let holdback = maxTagLength(Self.thinkEndTags)

                if buffer.count > holdback {
                    buffer = String(buffer.suffix(holdback))
                }

                return
            }

            if let startRange = earliestRange(in: buffer, tags: Self.thinkStartTags) {
                let before = String(buffer[..<startRange.lowerBound])

                if !before.isEmpty {
                    pendingText.append(contentsOf: Self.sanitize(before))
                    emitStableText(onChunk: onChunk, force: false)
                }

                buffer = String(buffer[startRange.upperBound...])
                isInsideThink = true
                continue
            }

            if let endRange = earliestRange(in: buffer, tags: Self.thinkEndTags) {
                let before = String(buffer[..<endRange.lowerBound])

                if !before.isEmpty {
                    pendingText.append(contentsOf: Self.sanitize(before))
                    emitStableText(onChunk: onChunk, force: false)
                }

                buffer = String(buffer[endRange.upperBound...])
                continue
            }

            let holdback = max(maxTagLength(Self.thinkStartTags), maxTagLength(Self.thinkEndTags))

            if buffer.count > holdback {
                let outputCount = buffer.count - holdback
                let splitIndex = buffer.index(buffer.startIndex, offsetBy: outputCount)
                let output = String(buffer[..<splitIndex])
                buffer = String(buffer[splitIndex...])

                if !output.isEmpty {
                    pendingText.append(contentsOf: Self.sanitize(output))
                    emitStableText(onChunk: onChunk, force: false)
                }
            }

            return
        }
    }

    // MARK: Flush

    nonisolated func flush(onChunk: (String) -> Void) {
        if isInsideThink {
            buffer = ""
            pendingText = ""
            isInsideThink = false
            return
        }

        if !buffer.isEmpty {
            let cleaned = Self.removeThinkTagsAndSpecialTokens(buffer)

            if !cleaned.isEmpty {
                pendingText.append(contentsOf: cleaned)
            }
        }

        buffer = ""
        emitStableText(onChunk: onChunk, force: true)
    }

    // MARK: Stable Text Emission

    private nonisolated func emitStableText(onChunk: (String) -> Void, force: Bool) {
        guard !pendingText.isEmpty else { return }

        if force {
            let output = pendingText
            pendingText = ""

            if !output.isEmpty {
                onChunk(output)
            }

            return
        }

        while !pendingText.isEmpty {
            guard let boundary = findSafeBoundary(
                in: pendingText,
                allowPartial: pendingText.count > Self.maxPendingCharacters
            ) else {
                return
            }

            let candidate = String(pendingText[..<boundary])
            pendingText = String(pendingText[boundary...])

            if !candidate.isEmpty {
                onChunk(candidate)
            }
        }
    }

    // MARK: Safe Boundary

    private nonisolated func findSafeBoundary(in text: String, allowPartial: Bool) -> String.Index? {
        guard !text.isEmpty else { return nil }

        var bestIndex: String.Index?

        for index in text.indices {
            let char = text[index]
            let nextIndex = text.index(after: index)

            if char.isWhitespace || char.isNewline || Self.isPunctuationOrSymbol(char) {
                bestIndex = nextIndex
            } else if let scalar = char.unicodeScalars.first, Self.isCJKCharacter(scalar) {
                bestIndex = nextIndex
            }
        }

        if let bestIndex {
            return bestIndex
        }

        if allowPartial && text.count >= Self.maxPendingCharacters {
            return text.index(text.startIndex, offsetBy: Self.maxPendingCharacters)
        }

        return nil
    }

    // MARK: Tag Search

    private nonisolated func earliestRange(in text: String, tags: [String]) -> Range<String.Index>? {
        var result: Range<String.Index>?

        for tag in tags {
            guard let candidate = text.range(of: tag) else { continue }

            if result == nil || candidate.lowerBound < result!.lowerBound {
                result = candidate
            }
        }

        return result
    }

    private nonisolated func maxTagLength(_ tags: [String]) -> Int {
        tags.map(\.count).max() ?? 0
    }

    // MARK: Character Helpers

    private nonisolated static func isCJKCharacter(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value

        return (0x4E00...0x9FFF).contains(value) ||
               (0x3400...0x4DBF).contains(value) ||
               (0x20000...0x2A6DF).contains(value) ||
               (0x3040...0x309F).contains(value) ||
               (0x30A0...0x30FF).contains(value) ||
               (0xAC00...0xD7AF).contains(value)
    }

    private nonisolated static func isPunctuationOrSymbol(_ char: Character) -> Bool {
        let symbols = ",.!?;:，。！？；：、\"'()[]{}（）《》〈〉【】『』“”‘’—–…·`"
        return symbols.contains(char)
    }

    // MARK: Sanitization

    private nonisolated static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return removeThinkTagsAndSpecialTokens(text)
    }

    private nonisolated static func removeThinkTagsAndSpecialTokens(_ input: String) -> String {
        var result = input

        for token in knownSpecialTokens {
            result = result.replacingOccurrences(of: token, with: "")
        }

        for tag in thinkStartTags {
            result = result.replacingOccurrences(of: tag, with: "")
        }

        for tag in thinkEndTags {
            result = result.replacingOccurrences(of: tag, with: "")
        }

        return result
    }
}

// MARK: - Physical Token Recorder & Iterator

nonisolated final class PhysicalTokenRecorder: @unchecked Sendable {
    private var tokens: [Int] = []

    nonisolated init() {}

    nonisolated func append(_ token: Int) {
        tokens.append(token)
    }

    nonisolated func discardLastIfPresent() {
        _ = tokens.popLast()
    }

    nonisolated func snapshot() -> [Int] {
        tokens
    }
}

nonisolated struct PhysicalLedgerTokenIterator: TokenIteratorProtocol, @unchecked Sendable {
    private var base: TokenIterator
    private let recorder: PhysicalTokenRecorder

    nonisolated init(base: TokenIterator, recorder: PhysicalTokenRecorder) {
        self.base = base
        self.recorder = recorder
    }

    nonisolated var maxTokens: Int? { base.maxTokens }
    nonisolated var tokenCount: Int { base.tokenCount }
    nonisolated var promptPrefillTime: TimeInterval { base.promptPrefillTime }
    nonisolated var speculativeDecodingTelemetry: SpeculativeDecodingTelemetry? { base.speculativeDecodingTelemetry }

    nonisolated mutating func discardGeneratedToken() {
        recorder.discardLastIfPresent()
        base.discardGeneratedToken()
    }

    nonisolated mutating func next() -> Int? {
        guard let token = base.next() else { return nil }
        recorder.append(token)
        return token
    }
}

// MARK: - Agent / Session / Branch Identity

nonisolated struct AgentExecutionKey: Hashable, Sendable {
    let agentId: String
    let sessionId: String
    let logicalBranchId: String

    init(agentId: String?, sessionId: String, logicalBranchId: String) throws {
        self.agentId = Self.normalize(agentId) ?? "default"

        guard let session = Self.normalize(sessionId) else {
            throw NativeMLXValidationError.invalidExecutionKey("sessionId cannot be empty")
        }

        guard let branch = Self.normalize(logicalBranchId) else {
            throw NativeMLXValidationError.invalidExecutionKey("logicalBranchId cannot be empty")
        }

        self.sessionId = session
        self.logicalBranchId = branch
    }

    var storageKey: String { "\(agentId)/\(sessionId)" }
    var gateKey: String { "\(agentId)/\(sessionId)/\(logicalBranchId)" }
    var traceKey: String { gateKey }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count <= 128 {
            return trimmed
        }

        let prefix = String(trimmed.prefix(64))
        let hash = SHA256.hash(data: Data(trimmed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return "\(prefix)_\(hash.prefix(16))"
    }

    static func resolve(agentId: String?, sessionId: String, logicalBranchId: String) throws -> AgentExecutionKey {
        try AgentExecutionKey(agentId: agentId, sessionId: sessionId, logicalBranchId: logicalBranchId)
    }
}
