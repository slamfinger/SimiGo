import Foundation
import SimiGoCollection
import SimiGoRuntimeContract

/// 设置里的「外部信息采集」：按文档结构识别格式，把已结束的会话写进
/// Information Space。
///
/// 识别不是按扩展名——真实导出常常没有扩展名，而旁边的附件挂着误导性的
/// 扩展名（协议里 `SnapshotTranscriptSource.recognizes` 已经写明这一点）。
/// 每个适配器只认自己那一份结构；认不出就当不是它的文件，继续下一个。
///
/// 写入走外部轮次合同（`recordExternalTurn` / `recordExternalResponse` /
/// `verifyExternalTurn`），与 Qoder 采集桥同一条路：没有 ES 结算，因为
/// 那些模型调用不是 SimiGo 执行的。幂等键是源身份，同一份文件重跑不追加。
///
/// 两处「重跑不追加」不是同一件事，缺一不可：
/// - 源身份幂等（request id）挡住**同一适配器**对同一文件的重复读；
/// - 内容去重挡住**另一个载体**已经写过的同一段对话。Qoder 采集桥读的是
///   Qoder 自己的会话存储，而导出的 Markdown 是同一会话的派生视图——两者
///   的源身份天然不同，只有内容能把它们对上。
final class MultiFormatCollection {

    struct Report: Sendable {
        var filesScanned = 0
        var filesRecognized = 0
        var turns = 0
        var written = 0
        var verificationPromoted = 0
        var skippedIncomplete = 0
        var skippedDuplicates = 0
        var skippedExisting = 0
        var skippedOversize = 0
        var failures: [String] = []
        var perFormat: [String: Int] = [:]

        var summary: String {
            let formats = perFormat.isEmpty
                ? "无"
                : perFormat.sorted { $0.key < $1.key }
                    .map { "\($0.key):\($0.value)" }.joined(separator: " ")
            var text = "扫描 \(filesScanned) 个文件，识别 \(filesRecognized)，"
                + "轮次 \(turns)，入库 \(written)（\(formats)）"
            if verificationPromoted > 0 { text += "，可检索 \(verificationPromoted)" }
            if skippedIncomplete > 0 { text += "，仅记录 \(skippedIncomplete)" }
            if skippedDuplicates > 0 { text += "，内容重复跳过 \(skippedDuplicates)" }
            if skippedExisting > 0 { text += "，已在库 \(skippedExisting)" }
            if skippedOversize > 0 { text += "，超限跳过 \(skippedOversize)" }
            if !failures.isEmpty { text += "，失败 \(failures.count)" }
            return text
        }
    }

    /// 单个 JSON 文档的上限。真实导出远小于它；超过的当附件/二进制处理，
    /// 不读。Markdown 会话导出不走这个上限——它按流分块读。
    private static let maxDocumentBytes = 64 * 1024 * 1024

    private let databaseURL: URL
    private var db: ESISDatabase?

    init(databaseURL: URL = ManagedPaths.databaseURL) {
        self.databaseURL = databaseURL
    }

    func importDirectory(_ root: URL) throws -> Report {
        var report = Report()
        // 本机已知的 SQLite 会话库不属于任何导出目录，但它同样是一次性
        // 历史采集的对象：先读它，再扫目录。
        try importOpenCode(into: &report)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return report }

        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            report.filesScanned += 1
            try ingest(url, size: values?.fileSize ?? 0, into: &report)
        }
        return report
    }

    /// opencode 把会话放在自己的 SQLite 库里，选目录采不到它。库不存在就
    /// 静默跳过——没装 opencode 不是一次采集失败。
    private func importOpenCode(into report: inout Report) throws {
        let url = OpenCodeSource.defaultDatabaseURL()
        guard OpenCodeSource.recognizes(at: url) else { return }
        report.filesScanned += 1
        do {
            let imported = try OpenCodeSource.collect(at: url)
            try deliver(imported.turns, format: OpenCodeSource.sourceType, into: &report)
        } catch {
            report.failures.append("opencode.db: \(error)")
        }
    }

    private func ingest(_ url: URL, size: Int, into report: inout Report) throws {
        // Markdown 会话导出：流式读，先于体积上限判断。
        if MarkdownSessionSource.recognizesPrefix(at: url) {
            let snapshot = try MarkdownSessionSource.readSnapshot(at: url)
            try deliver(
                snapshot.turns, format: MarkdownSessionSource.sourceType, into: &report)
            return
        }
        guard size <= Self.maxDocumentBytes else {
            report.skippedOversize += 1
            return
        }
        // SQLite 会话库由 `importOpenCode` 走数据库通道读取，字节扫描读不懂它。
        let ext = url.pathExtension.lowercased()
        guard ext != "db", ext != "sqlite", ext != "sqlite3" else { return }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        do {
            if let imported = try read(data: data, url: url), !imported.turns.isEmpty {
                try deliver(imported.turns, format: imported.format, into: &report)
            }
        } catch {
            report.failures.append("\(url.lastPathComponent): \(error)")
        }
    }

    private func deliver(
        _ turns: [CollectedTurn], format: String, into report: inout Report
    ) throws {
        guard !turns.isEmpty else { return }
        report.filesRecognized += 1
        report.perFormat[format, default: 0] += turns.count
        report.turns += turns.count
        for turn in turns {
            // 一个文件可以装多个会话：按每个 turn 自己的 session 家族取索引，
            // 否则第一个会话的答案会把第二个会话的同一句话误判成重复。
            let dedupe = try dedupeIndex(for: turn.sessionKey)
            if dedupe.containsExact(prompt: turn.promptText, answer: turn.answerText) {
                report.skippedDuplicates += 1
                continue
            }
            let outcome = try write(turn)
            if outcome.written {
                report.written += 1
                if outcome.promoted { report.verificationPromoted += 1 }
            } else if outcome.existed {
                report.skippedExisting += 1
            } else {
                report.skippedIncomplete += 1
            }
        }
    }

    private struct Recognized {
        let format: String
        let turns: [CollectedTurn]
    }

    /// 识别顺序即优先级：AI Studio 与 DeepSeek 的顶层键互斥，flat 导出
    /// 认 `messages` 数组，放在最后，避免把别的结构当消息列表读。
    private func read(data: Data, url: URL) throws -> Recognized? {
        if RolloutSource.recognizes(data) {
            let importResult = try RolloutSource.readSnapshot(at: url)
            return Recognized(format: RolloutSource.sourceType, turns: importResult.turns)
        }
        if ChatGPTSource.recognizes(data) {
            let importResult = try ChatGPTSource.readSnapshot(at: url)
            return Recognized(format: ChatGPTSource.sourceType, turns: importResult.turns)
        }
        if AIStudioSource.recognizes(data) {
            let importResult = try AIStudioSource.readSnapshot(at: url)
            return Recognized(format: AIStudioSource.sourceType, turns: importResult.turns)
        }
        if DeepSeekSource.recognizes(data) {
            let importResult = try DeepSeekSource.readSnapshot(at: url)
            return Recognized(format: DeepSeekSource.sourceType, turns: importResult.turns)
        }
        if FlatMessageExportSource.recognizes(data) {
            let importResult = try FlatMessageExportSource.readSnapshot(at: url)
            return Recognized(
                format: FlatMessageExportSource.sourceType, turns: importResult.turns)
        }
        return nil
    }

    private struct Outcome {
        let written: Bool
        let promoted: Bool
        var existed: Bool = false
    }

    private func write(_ turn: CollectedTurn) throws -> Outcome {
        guard !turn.promptText.isEmpty, !turn.answerText.isEmpty else {
            return Outcome(written: false, promoted: false)
        }
        let database = try open()
        if try database.externalTurnExists(
            sessionID: turn.sessionKey, requestID: turn.identity.operationKey)
        {
            return Outcome(written: false, promoted: false, existed: true)
        }
        let eligibility: ESISDatabase.ChatTurnEligibility =
            turn.disposition == .auditOnly ? .internalOperation : .ordinary
        let verified = turn.disposition == .retrievable
        let now = Date()
        try database.recordExternalTurn(
            sessionID: turn.sessionKey, provider: turn.provider,
            requestID: turn.identity.operationKey, userText: turn.promptText,
            model: turn.answerModel, createdAt: now, eligibility: eligibility)
        try database.recordExternalResponse(
            sessionID: turn.sessionKey, provider: turn.provider,
            requestID: turn.identity.operationKey, assistantText: turn.answerText,
            model: turn.answerModel, createdAt: now, eligibility: eligibility)
        guard verified else { return Outcome(written: true, promoted: false) }
        let promoted = try database.verifyExternalTurn(
            sessionID: turn.sessionKey, requestID: turn.identity.operationKey,
            verifiedAt: now)
        return Outcome(written: true, promoted: promoted > 0)
    }

    // MARK: - Content dedupe

    /// Prompt → its already-delivered answers, for one session family.
    ///
    /// Scope is the session family, not the whole database: the same sentence in
    /// two unrelated projects is two facts, and collapsing them would silently
    /// drop a turn the user asked about twice.
    private struct DedupeIndex {
        private var answers: [String: [String]] = [:]

        init(_ rows: [ESISDatabase.ExternalTurnText]) {
            for row in rows {
                let prompt = Self.normalized(row.prompt)
                let answer = Self.normalized(row.answer)
                guard !prompt.isEmpty, !answer.isEmpty else { continue }
                answers[prompt, default: []].append(answer)
            }
        }

        /// The export re-describes the same turn with its deliberation attached
        /// (a delivered reply is a suffix of the export's answer tail), so a
        /// suffix match counts as the same turn. Equality covers the plain case.
        func containsExact(prompt: String, answer: String) -> Bool {
            let normalizedPrompt = Self.normalized(prompt)
            let normalizedAnswer = Self.normalized(answer)
            guard !normalizedAnswer.isEmpty,
                let delivered = answers[normalizedPrompt]
            else { return false }
            return delivered.contains {
                $0 == normalizedAnswer
                    || normalizedAnswer.hasSuffix($0)
                    || $0.hasSuffix(normalizedAnswer)
            }
        }

        static func normalized(_ text: String) -> String {
            text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
    }

    private var dedupeCache: [String: DedupeIndex] = [:]

    /// Prefixes compared for one session key. A derived export
    /// (`md-export:<project>/<file>`) must also see the native collector's rows
    /// for the same project (`qoder:<project>/<session>`): those are the same
    /// conversation delivered by a different carrier.
    private static func dedupePrefixes(forSessionKey key: String) -> [String] {
        // `codex-<uuid>` 的另一半是显式写入时用过的短 id（`codex-<uuid 前 8 位>`，
        // 见 `simigo_chat_round` 的调用方）。短 id 是长 id 的前缀，LIKE 一并覆盖。
        if key.hasPrefix("codex-") {
            let id = key.dropFirst("codex-".count)
            return [key, "codex-" + String(id.prefix(8))]
        }
        guard let colon = key.firstIndex(of: ":") else { return [key] }
        let rest = key[key.index(after: colon)...]
        guard let slash = rest.lastIndex(of: "/") else { return [key] }
        let project = String(rest[..<slash])
        guard !project.isEmpty else { return [key] }
        return [key, "qoder:\(project)/"]
    }

    private func dedupeIndex(for sessionKey: String) throws -> DedupeIndex {
        let prefixes = Self.dedupePrefixes(forSessionKey: sessionKey)
        let cacheKey = prefixes.joined(separator: "|")
        if let cached = dedupeCache[cacheKey] { return cached }
        let rows = try open().externalTurnTexts(sessionPrefixes: prefixes)
        let index = DedupeIndex(rows)
        dedupeCache[cacheKey] = index
        return index
    }

    private func open() throws -> ESISDatabase {
        if let db { return db }
        let database = try ESISDatabase(url: databaseURL, createIfNeeded: true)
        try database.runMigrations()
        db = database
        return database
    }
}
