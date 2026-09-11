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

    private static let thinkStartTags = [
        "<think>", "<thought>", "<|start_of_think|>", "<|thought|>"
    ]

    private static let thinkEndTags = [
        "</think>", "</thought>", "<|end_of_think|>", "<|end_of_thought|>"
    ]

    private static let maxPendingCharacters = 48

    private var buffer = ""
    private var pendingText = ""
    private var inThinking = false
    private let disableThinking: Bool

    nonisolated init(disableThinking: Bool = false) {
        self.disableThinking = disableThinking
    }

    nonisolated func feed(_ text: String, onChunk: (String) -> Void) {
        guard !text.isEmpty else { return }

        // Fast path: when thinking is disabled there is no reason to retain
        // stream text between model chunks. This keeps TTFT and live rendering
        // independent of the presentation filter's safety buffer.
        if disableThinking {
            let cleaned = Self.sanitize(text)
            if !cleaned.isEmpty {
                onChunk(cleaned)
            }
            return
        }

        buffer.append(contentsOf: text)
        emitAvailable(onChunk: onChunk, flush: false)
    }

    nonisolated func flush(onChunk: (String) -> Void) {
        emitAvailable(onChunk: onChunk, flush: true)
    }

    private nonisolated func emitAvailable(
        onChunk: (String) -> Void,
        flush: Bool
    ) {
        while !buffer.isEmpty {
            if inThinking {
                guard let end = Self.firstRange(
                    in: buffer,
                    tags: Self.thinkEndTags
                ) else {
                    if flush {
                        buffer = ""
                        pendingText = ""
                    } else if buffer.count > Self.maxPendingCharacters {
                        buffer = String(buffer.suffix(Self.maxPendingCharacters))
                    }
                    return
                }

                buffer = String(buffer[end.upperBound...])
                inThinking = false
                continue
            }

            if let start = Self.firstRange(
                in: buffer,
                tags: Self.thinkStartTags
            ) {
                let before = String(buffer[..<start.lowerBound])
                if !before.isEmpty {
                    pendingText.append(contentsOf: Self.sanitize(before))
                    emitPending(onChunk: onChunk, force: true)
                }
                buffer = String(buffer[start.upperBound...])
                inThinking = true
                continue
            }

            let holdback =
                Self.thinkStartTags.map(\.count).max() ?? 0

            if flush {
                pendingText.append(contentsOf: Self.sanitize(buffer))
                buffer = ""
                emitPending(onChunk: onChunk, force: true)
                return
            }

            guard buffer.count > holdback else {
                return
            }

            let outputCount = buffer.count - holdback
            let splitIndex = buffer.index(
                buffer.startIndex,
                offsetBy: outputCount
            )
            let output = String(buffer[..<splitIndex])
            buffer = String(buffer[splitIndex...])
            pendingText.append(contentsOf: Self.sanitize(output))
            emitPending(onChunk: onChunk, force: false)
        }
    }

    private nonisolated func emitPending(
        onChunk: (String) -> Void,
        force: Bool
    ) {
        guard !pendingText.isEmpty else { return }

        if force || pendingText.count >= Self.maxPendingCharacters {
            let output = pendingText
            pendingText = ""
            onChunk(output)
        }
    }

    private static nonisolated func firstRange(
        in text: String,
        tags: [String]
    ) -> Range<String.Index>? {
        tags.compactMap { text.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static nonisolated func sanitize(_ text: String) -> String {
        var result = text
        for tag in Self.tags {
            result = result.replacingOccurrences(of: tag, with: "")
        }
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

    /// Compact trace label: the default agent is omitted and long session ids
    /// collapse to their last block, e.g. `9dc810/main`.
    var traceKey: String {
        let agent = agentId == "default" ? "" : "\(agentId)/"
        let suffix = sessionId.split(separator: "-").last.map(String.init) ?? sessionId
        let session = suffix.count > 6 ? String(suffix.suffix(6)) : suffix
        return "\(agent)\(session)/\(logicalBranchId)"
    }

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
