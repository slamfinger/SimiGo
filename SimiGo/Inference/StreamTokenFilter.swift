import Foundation
import CryptoKit
import Synchronization
import MLXLMCommon

// MARK: - Raw <tool_call> Stream Fallback Parser

struct RawToolCallParserFailure: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

nonisolated final class RawToolCallStreamParser: @unchecked Sendable {
    private var templates: [ToolCallTemplate]
    private var buffer = ""
    private var activeTemplate: ToolCallTemplate?
    private var activeOpenTagRange: Range<String.Index>?
    private var insideToolCall = false
    private(set) var rawToolCallDetected = false
    private(set) var failure: RawToolCallParserFailure?

    init(templates: [any ToolCallTemplate] = ToolCallTemplates.all) {
        self.templates = templates
    }

    nonisolated func feed(_ text: String, onText: (String) -> Void, onToolCall: (ParsedToolCall) -> Void) {
        guard !text.isEmpty, failure == nil else { return }
        buffer.append(contentsOf: text)

        while failure == nil {
            if !insideToolCall {
                var foundMatch = false
                for template in templates {
                    if let openRange = template.findOpenTag(in: buffer) {
                        // P1 修复：推送标签之前的普通文本，防止内容丢失。
                        // buffer 保持原样（不裁剪），因为 parse 依赖 openTagRange
                        // 在 buffer 中的绝对位置来定位内容起点。
                        let before = String(buffer[..<openRange.lowerBound])
                        if !before.isEmpty { onText(before) }

                        activeTemplate = template
                        activeOpenTagRange = openRange
                        insideToolCall = true
                        rawToolCallDetected = true
                        foundMatch = true
                        break
                    }
                }

                if !foundMatch {
                    let currentMaxOpenHoldback = templates.map { $0.maxOpenHoldback }.max() ?? 0
                    if buffer.count > currentMaxOpenHoldback {
                        let outputCount = buffer.count - currentMaxOpenHoldback
                        let splitIndex = buffer.index(buffer.startIndex, offsetBy: outputCount)
                        let output = String(buffer[..<splitIndex])
                        buffer = String(buffer[splitIndex...])
                        if !output.isEmpty { onText(output) }
                    }
                    return
                }
            }

            if insideToolCall, let template = activeTemplate, let openRange = activeOpenTagRange {
                if let closeRange = template.findCloseTag(in: buffer) {
                    let fullTextForParsing = String(buffer[..<closeRange.upperBound])
                    guard let call = template.parse(fullText: fullTextForParsing, openTagRange: openRange, closeTagRange: closeRange) else {
                        failure = RawToolCallParserFailure(message: "Malformed tool call for template: \(template.name)")
                        buffer = ""; insideToolCall = false; return
                    }
                    onToolCall(call)
                    buffer = String(buffer[closeRange.upperBound...])
                    insideToolCall = false; activeTemplate = nil; activeOpenTagRange = nil
                    continue
                } else {
                    return
                }
            }
        }
    }

    nonisolated func flush(onText: (String) -> Void) {
        guard failure == nil else { return }
        if insideToolCall, let template = activeTemplate, let openRange = activeOpenTagRange {
            if template.parse(fullText: buffer, openTagRange: openRange, closeTagRange: nil) == nil {
                failure = RawToolCallParserFailure(message: "Incomplete tool call at end of stream")
            }
            buffer = ""; insideToolCall = false; activeTemplate = nil; activeOpenTagRange = nil
            return
        }
        if !buffer.isEmpty { onText(buffer) }
        buffer = ""
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
                if buffer.count > holdback { buffer = String(buffer.suffix(holdback)) }
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

    nonisolated func flush(onChunk: (String) -> Void) {
        if isInsideThink {
            buffer = ""; pendingText = ""; isInsideThink = false; return
        }
        if !buffer.isEmpty {
            let cleaned = Self.removeThinkTagsAndSpecialTokens(buffer)
            if !cleaned.isEmpty { pendingText.append(contentsOf: cleaned) }
        }
        buffer = ""
        emitStableText(onChunk: onChunk, force: true)
    }

    private nonisolated func emitStableText(onChunk: (String) -> Void, force: Bool) {
        guard !pendingText.isEmpty else { return }
        if force {
            let output = pendingText; pendingText = ""
            if !output.isEmpty { onChunk(output) }
            return
        }
        while !pendingText.isEmpty {
            guard let boundary = findSafeBoundary(in: pendingText, allowPartial: pendingText.count > Self.maxPendingCharacters) else { return }
            let candidate = String(pendingText[..<boundary])
            pendingText = String(pendingText[boundary...])
            if !candidate.isEmpty { onChunk(candidate) }
        }
    }

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
        if let bestIndex { return bestIndex }
        if allowPartial && text.count >= Self.maxPendingCharacters { return text.index(text.startIndex, offsetBy: Self.maxPendingCharacters) }
        return nil
    }

    private nonisolated func earliestRange(in text: String, tags: [String]) -> Range<String.Index>? {
        var result: Range<String.Index>?
        for tag in tags {
            guard let candidate = text.range(of: tag) else { continue }
            if result == nil || candidate.lowerBound < result!.lowerBound { result = candidate }
        }
        return result
    }

    private nonisolated func maxTagLength(_ tags: [String]) -> Int { tags.map(\.count).max() ?? 0 }

    private nonisolated static func isCJKCharacter(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x20000...0x2A6DF).contains(value) || (0x3040...0x309F).contains(value) || (0x30A0...0x30FF).contains(value) || (0xAC00...0xD7AF).contains(value)
    }

    private nonisolated static func isPunctuationOrSymbol(_ char: Character) -> Bool {
        let symbols = ",.!?;:，。！？；：、\"'()[]{}（）《》〈〉【】『』“”‘’—–…·`"
        return symbols.contains(char)
    }

    private nonisolated static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return removeThinkTagsAndSpecialTokens(text)
    }

    private nonisolated static func removeThinkTagsAndSpecialTokens(_ input: String) -> String {
        var result = input
        for token in knownSpecialTokens { result = result.replacingOccurrences(of: token, with: "") }
        for tag in thinkStartTags { result = result.replacingOccurrences(of: tag, with: "") }
        for tag in thinkEndTags { result = result.replacingOccurrences(of: tag, with: "") }
        return result
    }
}

// MARK: - Physical Token Recorder & Iterator

nonisolated final class PhysicalTokenRecorder: @unchecked Sendable {
    private let lock = Mutex<[Int]>([])
    nonisolated init() {}
    nonisolated func append(_ token: Int) { lock.withLock { $0.append(token) } }
    nonisolated func discardLastIfPresent() { lock.withLock { _ = $0.popLast() } }
    nonisolated func snapshot() -> [Int] { lock.withLock { $0 } }
}

nonisolated struct PhysicalLedgerTokenIterator: TokenIteratorProtocol, @unchecked Sendable {
    private var base: TokenIterator
    private let recorder: PhysicalTokenRecorder
    nonisolated init(base: TokenIterator, recorder: PhysicalTokenRecorder) { self.base = base; self.recorder = recorder }
    nonisolated var maxTokens: Int? { base.maxTokens }
    nonisolated var tokenCount: Int { base.tokenCount }
    nonisolated var promptPrefillTime: TimeInterval { base.promptPrefillTime }
    nonisolated var speculativeDecodingTelemetry: SpeculativeDecodingTelemetry? { base.speculativeDecodingTelemetry }
    nonisolated mutating func discardGeneratedToken() {}
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
        guard let session = Self.normalize(sessionId) else { throw NativeMLXValidationError.invalidExecutionKey("sessionId cannot be empty") }
        guard let branch = Self.normalize(logicalBranchId) else { throw NativeMLXValidationError.invalidExecutionKey("logicalBranchId cannot be empty") }
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
        if trimmed.count <= 128 { return trimmed }
        let prefix = String(trimmed.prefix(64))
        let hash = SHA256.hash(data: Data(trimmed.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(prefix)_\(hash.prefix(16))"
    }
    static func resolve(agentId: String?, sessionId: String, logicalBranchId: String) throws -> AgentExecutionKey {
        try AgentExecutionKey(agentId: agentId, sessionId: sessionId, logicalBranchId: logicalBranchId)
    }
}
