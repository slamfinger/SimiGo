import Foundation
import CryptoKit

/// Presentation-only filter for streamed text. Tool-call parsing and generation
/// remain entirely in mlx-swift-lm.
nonisolated final class StreamTokenFilter: @unchecked Sendable {
    private static let tags = [
        "<think>", "</think>", "<thought>", "</thought>",
        "<|start_of_think|>", "<|end_of_think|>",
        "<|thought|>", "<|end_of_thought|>",
        "<|im_start|>", "<|im_end|>", "<|endoftext|>",
        "<|assistant|>", "<|user|>", "<|system|>", "<|tool|>",
        "<|eot_id|>", "<|eom_id|>", "<|begin_of_text|>", "<|end_of_text|>",
        "<|start_header_id|>", "<|end_header_id|>"
    ]

    private var buffer = ""
    private var inThinking = false
    private let disableThinking: Bool

    nonisolated init(disableThinking: Bool = false) {
        self.disableThinking = disableThinking
    }

    nonisolated func feed(_ text: String, onChunk: (String) -> Void) {
        guard !text.isEmpty else { return }

        buffer.append(text)
        emitAvailable(onChunk: onChunk, flush: false)
    }

    nonisolated func flush(onChunk: (String) -> Void) {
        emitAvailable(onChunk: onChunk, flush: true)
    }

    private nonisolated func emitAvailable(onChunk: (String) -> Void, flush: Bool) {
        if !disableThinking {
            let text = sanitize(buffer)
            buffer = ""
            guard !text.isEmpty else { return }
            onChunk(text)
            return
        }

        var output = ""
        while !buffer.isEmpty {
            if inThinking {
                guard let end = firstRange(in: buffer, tags: Self.tags.filter { $0.hasPrefix("</") || $0.contains("end_of") }) else {
                    if flush { buffer = "" }
                    return
                }
                buffer = String(buffer[end.upperBound...])
                inThinking = false
                continue
            }

            guard let start = firstRange(in: buffer, tags: ["<think>", "<thought>", "<|start_of_think|>", "<|thought|>"]) else {
                let holdback = 24
                if flush || buffer.count > holdback {
                    let count = flush ? buffer.count : buffer.count - holdback
                    let index = buffer.index(buffer.startIndex, offsetBy: count)
                    output.append(sanitize(String(buffer[..<index])))
                    buffer = String(buffer[index...])
                    if flush { break }
                    continue
                }
                break
            }

            output.append(sanitize(String(buffer[..<start.lowerBound])))
            buffer = String(buffer[start.upperBound...])
            inThinking = true
        }

        let cleaned = sanitize(output)
        if !cleaned.isEmpty { onChunk(cleaned) }
    }

    private nonisolated func firstRange(in text: String, tags: [String]) -> Range<String.Index>? {
        tags.compactMap { text.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
    }

    private nonisolated func sanitize(_ text: String) -> String {
        var result = text
        for tag in Self.tags { result = result.replacingOccurrences(of: tag, with: "") }
        return result
    }
}

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

    /// A ChatSession owns KV for exactly one logical branch.
    var storageKey: String { "\(agentId)/\(sessionId)/\(logicalBranchId)" }
    var traceKey: String { storageKey }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 128 { return trimmed }

        let prefix = String(trimmed.prefix(64))
        let digest = SHA256.hash(data: Data(trimmed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(prefix)_\(digest.prefix(16))"
    }

    static func resolve(agentId: String?, sessionId: String, logicalBranchId: String) throws -> AgentExecutionKey {
        try AgentExecutionKey(agentId: agentId, sessionId: sessionId, logicalBranchId: logicalBranchId)
    }
}
