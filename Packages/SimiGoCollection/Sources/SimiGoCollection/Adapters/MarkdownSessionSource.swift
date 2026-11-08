import CryptoKit
import Foundation

/// Markdown session exports: one document, blocks delimited by
/// `### **You**` / `### **Assistant**` / `### **System**`.
///
/// Two properties of this carrier decide the whole adapter:
///
/// 1. It is written once per export and can be very large (the observed corpus
///    has a 137 MB / 2.05M-line document), so reading it is streaming: one
///    megabyte at a time, a line at a time, one turn held at a time. Nothing
///    here ever materialises the document.
/// 2. It does not delimit deliberation from the reply. `#### Thinking` is the
///    only heading inside an assistant block, and the reply follows the
///    deliberation inside that same section — measured over the corpus: of 596
///    rounds, 494 have assistant prose only inside `#### Thinking` and 14 have
///    prose outside it. A reply therefore cannot be separated from its
///    reasoning by structure. The adapter keeps the **tail** of the block
///    (replies end the block) up to `maxAnswerCharacters`, and says so in a
///    diagnostic instead of pretending the boundary was observed.
///
/// `#### Tool:` bodies are never content: they are the agent's own tool traffic
/// (inputs, outputs, repository dumps). They are dropped and counted.
public enum MarkdownSessionSource: SnapshotTranscriptSource {
    public static let sourceType = "md-export"
    public static let adapterVersion = "markdown-session-export/v1"
    public static let sourceKind: TranscriptSourceKind = .wholeFileSnapshot

    /// Upper bound on the assistant tail kept per turn. Replies end the block,
    /// so the tail holds the reply; the cap keeps deliberation out of the
    /// information space and keeps a 596-turn export inside ~19 MB of text.
    static let maxAnswerCharacters = 32 * 1024

    /// Bytes read for recognition. The export's header plus the first round sits
    /// well inside this window.
    private static let recognitionBytes = 64 * 1024

    // MARK: - Recognition

    public static func recognizes(_ data: Data) -> Bool {
        recognizesPrefix(String(decoding: data.prefix(recognitionBytes), as: UTF8.self))
    }

    public static func recognizesPrefix(_ text: String) -> Bool {
        text.contains("### **You**") && text.contains("### **Assistant**")
    }

    /// Structural probe for a file that may be far larger than memory.
    public static func recognizesPrefix(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: recognitionBytes) else { return false }
        return recognizes(head)
    }

    // MARK: - Reading

    /// Streaming read. The digest is taken over every byte read, so it is the
    /// same value `readSnapshot` would compute for a whole-file read.
    public static func readSnapshot(at url: URL) throws -> SnapshotImport {
        let path = url.lastPathComponent
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw SnapshotReadError.unreadable(path: path, detail: String(describing: error))
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        var builder = Builder(
            path: path, sessionID: url.deletingPathExtension().lastPathComponent)
        // 字节缓冲按行切分，每个读块只压缩一次。逐行 `removeSubrange` 会让
        // 每个 1 MB 块搬移 O(n²) 字节——实测同一份 137 MB 导出要 73 秒；
        // 进程内扫描 + 每块一次压缩后降到秒级。
        var buffer: [UInt8] = []
        buffer.reserveCapacity(2 << 20)
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            buffer.append(contentsOf: chunk)
            var start = 0
            for index in buffer.indices where buffer[index] == 0x0A {
                builder.consume(
                    String(decoding: buffer[start..<index], as: UTF8.self))
                start = index + 1
            }
            if start > 0 { buffer.removeFirst(start) }
        }
        if !buffer.isEmpty {
            builder.consume(String(decoding: buffer, as: UTF8.self))
        }
        builder.finish()
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return SnapshotImport(
            turns: builder.turns, diagnostics: builder.diagnostics, contentDigest: digest)
    }

    public static func interpret(
        _ data: Data, path: String, contentDigest: String
    ) throws -> SnapshotImport {
        guard recognizes(data) else {
            throw SnapshotReadError.foreignDocument(
                path: path, detail: "\(sourceType) does not claim this document")
        }
        var builder = Builder(
            path: path, sessionID: (path as NSString).deletingPathExtension)
        for line in String(decoding: data, as: UTF8.self).split(
            separator: "\n", omittingEmptySubsequences: false)
        {
            builder.consume(String(line))
        }
        builder.finish()
        return SnapshotImport(
            turns: builder.turns, diagnostics: builder.diagnostics,
            contentDigest: contentDigest)
    }

    // MARK: - Parsing

    private enum Speaker {
        case none, you, assistant, system
    }

    private enum Section {
        case prose, thinking, tool
    }

    private enum Heading: Equatable {
        case you, assistant, system, subsection(String)
    }

    private static func heading(of line: String) -> Heading? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "### **You**": return .you
        case "### **Assistant**": return .assistant
        case "### **System**": return .system
        default:
            guard trimmed.hasPrefix("#### ") else { return nil }
            return .subsection(String(trimmed.dropFirst(5)))
        }
    }

    private struct Builder {
        let path: String
        let sessionID: String
        var workDirectory: String?
        var exportedAt: String?
        var speaker: Speaker = .none
        var section: Section = .prose
        var turnIndex = 0
        var prompt: [String] = []
        var answerLines: [String] = []
        var answerCharacters = 0
        var toolBlocks = 0
        var thinkingBlocks = 0
        var turns: [CollectedTurn] = []
        var diagnostics: [CollectionDiagnostic] = []

        /// Qoder names its project directories by replacing every `/` of the
        /// work directory with `-`; a session that was collected natively lives
        /// under exactly this prefix, which is what the content dedupe compares
        /// against.
        var projectID: String {
            (workDirectory ?? "").replacingOccurrences(of: "/", with: "-")
        }

        var sessionKey: String {
            MarkdownSessionSource.sessionKey(projectID: projectID, sessionID: sessionID)
        }

        mutating func consume(_ line: String) {
            if let heading = MarkdownSessionSource.heading(of: line) {
                switch heading {
                case .you:
                    finishTurn()
                    turnIndex += 1
                    speaker = .you
                    section = .prose
                case .assistant:
                    speaker = .assistant
                    section = .prose
                case .system:
                    speaker = .system
                    section = .prose
                case .subsection(let name):
                    guard speaker == .assistant else { return }
                    if name.lowercased().hasPrefix("thinking") {
                        section = .thinking
                        thinkingBlocks += 1
                    } else {
                        section = .tool
                        if name.lowercased().hasPrefix("tool") { toolBlocks += 1 }
                    }
                }
                return
            }
            switch speaker {
            case .none:
                captureHeader(line)
            case .you:
                prompt.append(line)
            case .assistant:
                guard section != .tool else { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[hook:") { return }
                appendAnswer(line)
            case .system:
                break
            }
        }

        mutating func finish() {
            finishTurn()
            if toolBlocks > 0 {
                diagnostics.append(
                    makeDiagnostic(
                        part: "tool-blocks", kind: .toolTraffic,
                        detail:
                            "\(toolBlocks) tool sections are the agent's own traffic "
                            + "and are not imported"))
            }
            if thinkingBlocks > 0 {
                diagnostics.append(
                    makeDiagnostic(
                        part: "thinking-blocks", kind: .unsupportedShape,
                        detail:
                            "the carrier does not delimit deliberation from the reply; "
                            + "each answer is the last \(MarkdownSessionSource.maxAnswerCharacters) "
                            + "characters of its assistant block"))
            }
            if workDirectory == nil {
                diagnostics.append(
                    makeDiagnostic(
                        part: "work_directory", kind: .unsupportedShape,
                        detail:
                            "the document states no work directory; the session key "
                            + "carries no project component"))
            }
        }

        private mutating func captureHeader(_ line: String) {
            if let value = MarkdownSessionSource.headerValue(
                line, label: "**Work Directory:**")
            {
                workDirectory = value
            } else if let value = MarkdownSessionSource.headerValue(line, label: "**Exported:**")
            {
                exportedAt = SnapshotTimestamp.normalize(value)
            }
        }

        private mutating func appendAnswer(_ line: String) {
            answerLines.append(line)
            answerCharacters += line.count + 1
            guard answerCharacters > MarkdownSessionSource.maxAnswerCharacters else { return }
            var drop = 0
            while answerCharacters > MarkdownSessionSource.maxAnswerCharacters,
                drop < answerLines.count
            {
                answerCharacters -= answerLines[drop].count + 1
                drop += 1
            }
            answerLines.removeFirst(drop)
        }

        private mutating func finishTurn() {
            defer {
                prompt.removeAll()
                answerLines.removeAll(keepingCapacity: true)
                answerCharacters = 0
            }
            let promptText = prompt.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !promptText.isEmpty else { return }
            let answerText = answerLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = MarkdownSessionSource.identity(
                sessionID: sessionID, turnID: "turn-\(turnIndex)",
                messageID: "turn-\(turnIndex)")
            turns.append(
                CollectedTurn(
                    identity: identity,
                    provider: MarkdownSessionSource.sourceType,
                    sessionKey: sessionKey,
                    promptText: promptText,
                    answerText: answerText,
                    reasoningText: nil,
                    answerModel: nil,
                    timestamp: exportedAt,
                    attribution: .fileOrderOnly,
                    disposition: answerText.isEmpty
                        ? .recordedIncompleteAnswer : .retrievable))
            if answerText.isEmpty {
                diagnostics.append(
                    makeDiagnostic(
                        part: "turn-\(turnIndex)", kind: .incompleteTurn,
                        detail: "prompt has no assistant content outside tool sections"))
            }
        }

        private func makeDiagnostic(
            part: String, kind: CollectionDiagnostic.Kind, detail: String
        ) -> CollectionDiagnostic {
            CollectionDiagnostic(
                kind: kind, sourceType: MarkdownSessionSource.sourceType,
                locator: SnapshotLocator.describe(
                    file: path, sessionID: sessionID, part: part),
                detail: detail)
        }
    }

    /// `**Work Directory:** \`/path\`` → `/path`. The label is matched at the
    /// start of the line so a sentence that merely mentions the label cannot be
    /// read as the header.
    static func headerValue(_ line: String, label: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(label) else { return nil }
        var value = String(trimmed.dropFirst(label.count))
            .trimmingCharacters(in: .whitespaces)
        value = value.replacingOccurrences(of: "`", with: "")
        return value.isEmpty ? nil : value
    }
}
