import Foundation

/// 一轮摘要的输入输出约定。摘要是**精编**，不是节选：说清这一轮要解决
/// 什么、结论是什么、哪件明确没做。语气必须跟原文一致——提出就是提出，
/// 没被认可的不能写成「决定」。
public enum TurnDigestText {
    public struct SourceRecord: Equatable, Sendable {
        public let sourceID: String
        public let version: Int
        public let status: String
        public let supersedes: String
        public let value: String

        public init(sourceID: String, version: Int, status: String,
                    supersedes: String, value: String) {
            self.sourceID = sourceID
            self.version = version
            self.status = status
            self.supersedes = supersedes
            self.value = value
        }
    }

    public enum SourceRecordError: Error, Equatable, Sendable {
        case malformed(String)
        case ambiguous(String)
    }

    private static let sourceHeaderFields = [
        "source_id", "version", "document_id", "value", "note_kind", "status",
        "representation", "supersedes", "recorded_at", "content",
    ]

    private static func sourceHeaderKey(_ line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colon])
        return sourceHeaderFields.contains(key) ? key : nil
    }

    private static func sourceIDHeaderValue(_ line: String) -> String? {
        guard line.hasPrefix("source_id:") else { return nil }
        let raw = String(line.dropFirst("source_id:".count))
        return raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
    }

    public static func sourceRecords(in text: String) throws -> [SourceRecord] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let sourceMarkers: Set<String> = [
            "document_id", "note_kind", "representation", "recorded_at",
        ]
        var records: [SourceRecord] = []
        var seen = Set<String>()
        var cursor = 0
        var insideContent = false
        while cursor < lines.count {
            let start = cursor
            var headerLines: [String] = []
            while cursor < lines.count {
                guard let key = sourceHeaderKey(lines[cursor]) else { break }
                headerLines.append(lines[cursor])
                cursor += 1
                if key == "content" { break }
            }
            let keys = headerLines.compactMap(sourceHeaderKey)
            let uniqueKeys = Set(keys)
            let hasStrongMarker = !uniqueKeys.filter({ sourceMarkers.contains($0) }).isEmpty
            let hasSourceID = headerLines.contains {
                guard let sourceID = sourceIDHeaderValue($0) else { return false }
                return UUID(uuidString: sourceID) != nil
            }
            let hasRecordCore = ["version", "value", "status", "supersedes"]
                .allSatisfy { uniqueKeys.contains($0) }
            let hasMetadataRecord = hasStrongMarker && hasRecordCore
            // Content is free-form; a new record there needs core metadata, not markers alone.
            let looksLikeSource = insideContent
                ? hasMetadataRecord
                : (hasSourceID || hasMetadataRecord)
            guard looksLikeSource else {
                if cursor == start { cursor += 1 }
                continue
            }

            var fields: [String: String] = [:]
            for (offset, line) in headerLines.enumerated() {
                guard let colon = line.firstIndex(of: ":") else {
                    throw SourceRecordError.malformed("header line \(start + offset + 1)")
                }
                let key = String(line[..<colon])
                guard sourceHeaderFields.contains(key), fields[key] == nil else {
                    throw SourceRecordError.ambiguous("header field \(key)")
                }
                var value = String(line[line.index(after: colon)...])
                if value.hasPrefix(" ") { value.removeFirst() }
                fields[key] = value
            }
            guard fields.count == sourceHeaderFields.count else {
                throw SourceRecordError.malformed("incomplete source header")
            }
            let sourceID = fields["source_id"]!
            guard UUID(uuidString: sourceID) != nil, sourceID == sourceID.uppercased(),
                  seen.insert(sourceID).inserted else {
                throw SourceRecordError.ambiguous("source_id \(sourceID)")
            }
            let rawVersion = fields["version"]!
            guard let version = Int(rawVersion), version > 0,
                  String(version) == rawVersion else {
                throw SourceRecordError.malformed("version \(rawVersion)")
            }
            let value = fields["value"]!
            let status = fields["status"]!
            guard !value.isEmpty, !status.isEmpty else {
                throw SourceRecordError.malformed("empty value or status")
            }
            records.append(SourceRecord(
                sourceID: sourceID, version: version, status: status,
                supersedes: fields["supersedes"]!, value: value))
            insideContent = true
        }
        return records
    }

    public static func sourceCarrier(turnIndex: Int, records: [SourceRecord]) -> String? {
        guard !records.isEmpty else { return nil }
        let body = records.map {
            "source_id: \($0.sourceID)\nversion: \($0.version)\nstatus: \($0.status)\n"
                + "supersedes: \($0.supersedes)\nvalue: \($0.value)"
        }.joined(separator: "\n\n")
        return "[L3 source records t\(turnIndex)]\n\(body)\n[/L3 source records t\(turnIndex)]"
    }

    public static func digestWithSourceCarrier(
        _ digest: String, turnIndex: Int, question: String
    ) throws -> String {
        let records = try sourceRecords(in: question)
        guard let carrier = sourceCarrier(turnIndex: turnIndex, records: records) else {
            return digest
        }
        guard !digest.hasSuffix(carrier) else { return digest }
        return digest + "\n" + carrier
    }

    /// SHA-256 of the exact source text used to generate a turn digest.
    /// Shared with the App target so snapshot fingerprints use the carrier's
    /// canonical digest implementation without exposing its internal hasher.
    public static func sourceSHA256(_ text: String) -> String {
        NativeSHA256.hexDigest(Data(text.utf8))
    }

    /// 投喂上限。超长的轮次按已给部分总结，宁可少说，不编。
    ///
    /// 分层投喂：散文行全留，代码块只留前几行、声明行和报错行——长回答里
    /// 代码占 86%–97%，语义全在散文里（2026-11-11 实测：纯散文用 178 字
    /// 写出比喂 3004 字更具体的摘要；头尾切法把六成预算花在代码尾巴上）。
    public static let maxQuestion = 1_200
    public static let maxFeed = 1_800
    public static let maxDigest = 300
    public static let maxKeywords = 8
    private static let headLines = 6
    private static let maxDeclLines = 12
    private static let maxErrorLines = 8
    private static let maxHeadLines = 10
    private static let maxDeclChars = 60

    private static let modifiers: Set<String> = [
        "public", "private", "internal", "fileprivate", "open", "static",
        "final", "override", "mutating", "nonisolated", "async", "lazy",
        "weak", "unowned", "convenience", "required",
    ]
    private static let declKeywords: Set<String> = [
        "func", "class", "struct", "enum", "protocol", "extension", "actor",
        "let", "var", "init", "deinit", "case", "import", "subscript",
        "def", "function", "export", "interface", "type",
    ]
    private static let errorMarks = [
        "error", "错误", "报错", "失败", "warning", "警告",
        "exception", "traceback", "fatal", "panic",
    ]

    private static func isDecl(_ line: String) -> Bool {
        let tokens = line.split { $0 == " " || $0 == "\t" }.map(String.init)
        for token in tokens {
            if token.hasPrefix("@") || token.hasPrefix("//") { continue }
            if modifiers.contains(token) { continue }
            return declKeywords.contains(token)
        }
        return false
    }

    private static func isError(_ line: String) -> Bool {
        let lower = line.lowercased()
        return errorMarks.contains { lower.contains($0) }
    }

    private static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    /// 散文行 + 每块前 6 行 + 声明行 + 报错行。代码体不进 prompt。
    ///
    /// 代码体是「修饰」不是「主谓宾」，且留着它会把预算吃光。
    /// 第二个返回值：有没有代码行被藏掉——藏了才需要向模型交代一句。
    static func feed(_ answer: String) -> (text: String, layered: Bool) {
        var prose: [String] = [], heads: [String] = []
        var errors: [String] = [], decls: [String] = []
        var inside = false, firstN = 0, hidden = 0
        for raw in answer.split(
            separator: "\n", omittingEmptySubsequences: false) {
            if isFence(String(raw)) {
                inside.toggle()
                firstN = 0
                continue
            }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if !inside {
                prose.append(line)
                continue
            }
            if firstN < headLines {
                heads.append(line)
                firstN += 1
            } else {
                hidden += 1
            }
            if isError(line) { errors.append(line) }
            if isDecl(line) { decls.append(line) }
        }
        var parts = prose + decls.prefix(maxDeclLines)
        var seen = Set(parts)
        for line in heads.prefix(maxHeadLines) where seen.insert(line).inserted {
            parts.append(line)
        }
        for line in errors.prefix(maxErrorLines) where seen.insert(line).inserted {
            parts.append(line)
        }
        let shaped = parts.joined(separator: "\n")
        guard shaped.count > maxFeed else { return (shaped, hidden > 0) }
        let half = maxFeed / 2
        return (String(shaped.prefix(half)) + "\n……\n" + String(shaped.suffix(half)),
                true)
    }

    /// 代码概况：几块、多少行、有哪些声明。
    ///
    /// 只留散文时模型会误判成「没给代码 / 只给了片段」（实测同一轮连出三次）。
    /// 补这一行规模与声明清单，它不用看代码体也知道给了什么。
    static func codeMeta(_ answer: String) -> String {
        var blocks = 0, lines = 0, inside = false
        var decls: [String] = []
        for raw in answer.split(
            separator: "\n", omittingEmptySubsequences: false) {
            if isFence(String(raw)) {
                inside.toggle()
                if inside { blocks += 1 }
                continue
            }
            guard inside else { continue }
            lines += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if decls.count < maxDeclLines && isDecl(line) {
                decls.append(String(line.prefix(maxDeclChars)))
            }
        }
        guard blocks > 0 else { return "" }
        return "【代码概况】\(blocks) 个代码块，共 \(lines) 行；"
            + "声明：\(decls.joined(separator: "；"))"
    }

    /// 简报背景的上限。简报是项目级判断，摘要是单轮精编——背景只用来
    /// 消歧术语与上下文，不能喧宾夺主，更不能被抄进摘要正文。
    public static let maxBackground = 1_200

    private static func backgroundSection(_ background: String?) -> String {
        guard let background else { return "" }
        let trimmed = background.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return """
        【项目简报背景（仅供理解术语与上下文；摘要只写本轮：不得抄简报内容，\
        不得把简报里的事写成本轮的结论）】
        \(String(trimmed.prefix(maxBackground)))

        """
    }

    public static func prompt(
        question: String, answer: String, background: String? = nil
    ) -> String {
        let (fed, layered) = feed(answer)
        var body = fed
        let meta = codeMeta(answer)
        if !meta.isEmpty { body += "\n\n" + meta }
        // 说明了「这一层你看不到」比只说「别提」管用：只写别提，模型照样
        // 报「代码未全部提供」。
        let note = layered ? """
        注意：回答里的代码体已略去，只留下散文、声明行与报错行。所以你**看不到**\
        代码是否完整，这一层也不在摘要范围内——不要评价代码完不完整、有没有给全、\
        是否只是片段。原文只要出现代码块，就说明这一轮把代码给出了，\
        不要写「只给了片段」「未提供完整代码」。\
        摘要只写：这一轮要解决什么、结论是什么、哪件事明确没做。

        """
        : ""
        return """
        你在给一个信息空间写轮次摘要。下面是一轮会话的问题和回答。

        只输出两行，不要任何解释：
        摘要：<两到三句。这一轮要解决什么、最后的结论是什么、哪件事明确没做。\
        措辞必须跟原文一致：原文是提议就写提议，原文是用户裁定才写已定/裁定。\
        不要写「用户说/助手回答」这类套话，不要抄原句>
        关键词：<5 到 8 个词，空格分隔。每个词 2 到 8 个字，尽量用原文里出现过的词，\
        因为以后要拿它去查原文。不要标点，不要整句>

        \(backgroundSection(background))\(note)问题：
        \(String(question.prefix(maxQuestion)))

        回答：
        \(body)
        """
    }

    /// 解析模型的两行输出。显式标签始终优先；仅当完全没有标签且正好
    /// 两条非空行时，才按「首行摘要、末行关键词」兼容模型漏标签的输出。
    /// 其他结构仍返回 nil，不把解释文字猜成摘要。
    public static func parse(
        _ raw: String,
        onReject: ((String) -> Void)? = nil
    ) -> (digest: String, keywords: [String])? {
        let lines = raw.split(
            separator: "\n", omittingEmptySubsequences: false
        ).map { stripNoise(String($0)) }.filter { !$0.isEmpty }

        var digest: String?
        var keywordLine: String?
        for trimmed in lines {
            if trimmed.hasPrefix("摘要：") || trimmed.hasPrefix("摘要:") {
                digest = stripNoise(String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("关键词：") || trimmed.hasPrefix("关键词:") {
                keywordLine = stripNoise(String(trimmed.dropFirst(4)))
            }
        }

        // Only the exact two-line, fully unlabelled shape gets positional fallback.
        // A partially labelled or explanatory multi-line response remains invalid.
        if digest == nil && keywordLine == nil {
            guard lines.count == 2 else {
                onReject?("unlabelled_line_count")
                return nil
            }
            let fallbackTerms = splitTerms(lines[1])
            guard fallbackTerms.count >= 2 else {
                onReject?("unlabelled_keyword_count")
                return nil
            }
            digest = lines[0]
            keywordLine = lines[1]
        }

        guard let digest, !digest.isEmpty, let keywordLine else {
            onReject?(digest?.isEmpty == true ? "empty_digest" : "missing_keywords")
            return nil
        }
        let terms = splitTerms(keywordLine)
        guard !terms.isEmpty else {
            onReject?("empty_keywords")
            return nil
        }
        return (String(digest.prefix(maxDigest)), terms)
    }

    /// 只问关键词。摘要正文不动——已经有摘要的轮次缺的是检索入口，不是再写一遍。
    ///
    /// 和整轮摘要同一把尺子：**尽量**用原文里的字面（2026-11-12 裁定「尽量
    /// 用原文里出现过的词，这是正确的」），必要时才用同义说法。
    ///
    /// 「尽量」是偏好不是门槛：检索走 `digest LIKE ? OR keywords LIKE ?`，
    /// 摘要已经覆盖了字面，词表比摘要多出来的那部分入口正是「原文里没有、
    /// 讲的却是这件事」的说法。所以 `mergeKeywords` 不按原文筛，也让别名词
    /// 进得来（同一次实测：只留原文里有的词，别名查询召回 177/177 → 54/177）。
    public static func keywordPrompt(question: String, answer: String) -> String {
        let (fed, _) = feed(answer)
        return """
        下面是一轮会话的问题和回答。只给这一轮的关键词，不要摘要。

        只输出一行词，不要标签、不要解释：
        <5 到 8 个词，空格分隔，每个词 2 到 8 个字。尽量用原文里出现过的字面，\
        必要时才用同义说法（术语、换个说法）。这些词以后就是检索入口。\
        不要标点，不要整句>

        问题：
        \(String(question.prefix(maxQuestion)))

        回答：
        \(fed)
        """
    }

    /// 只认关键词。有标签按标签取；没有标签按最后一行取——问的就是一行词，
    /// 不能因为少了「关键词」四个字就判成失败（本机模型单行提问时 10/10
    /// 不带标签，2026-11-12 实测）。两行都认不出就是 nil，调用方不猜。
    public static func parseKeywords(_ raw: String) -> [String]? {
        var lines: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = stripNoise(String(line))
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        for line in lines {
            guard let label = ["关键词：", "关键词:"].first(where: { line.hasPrefix($0) })
            else { continue }
            let terms = splitTerms(String(line.dropFirst(label.count)))
            if !terms.isEmpty { return terms }
        }
        // 兜底只吃「一整行词」：带冒号的说明是别的字段（摘要 / 解释），不猜。
        guard let last = lines.last, !last.contains("："), !last.contains(":") else { return nil }
        let terms = splitTerms(last)
        return terms.isEmpty ? nil : terms
    }

    /// 合并已有的词与新要来的词：已有顺序不动，新增只去重、截到上限。
    ///
    /// 这里**不**按「是否出现在原文」筛。原文里没有的字面恰恰是关键词层比
    /// 摘要多出来的入口；把它筛掉，词表就退化成摘要的副本（同一次实测：
    /// 别名查询召回 177/177 → 54/177）。
    public static func mergeKeywords(_ existing: [String], _ proposed: [String]) -> [String] {
        var seen = Set(existing)
        var out = existing
        for term in proposed where seen.insert(term).inserted {
            out.append(term)
            if out.count == maxKeywords { break }
        }
        return out
    }

    /// 模型爱在行首行尾加星号、项目符号：先剥掉再认标签，认完再剥一次值。
    private static func stripNoise(_ text: String) -> String {
        var out = Substring(text)
        let noise = CharacterSet(charactersIn: "*-• \t")
        while let f = out.first, f.unicodeScalars.allSatisfy(noise.contains) {
            out = out.dropFirst()
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// 词表的切法与上限：两种路径（整轮摘要、只修词）共用一把尺子，
    /// 否则同一批词在两条路上会被切出不同结果。
    private static func splitTerms(_ keywordLine: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        let separators = CharacterSet.whitespaces
            .union(CharacterSet(charactersIn: "，、,;；:：()（）[]【】。.\"'“”*"))
        for raw in keywordLine.components(separatedBy: separators) where !raw.isEmpty {
            if seen.insert(raw).inserted { terms.append(raw) }
            if terms.count == maxKeywords { break }
        }
        return terms
    }
}

/// 一次补摘要/补词的回执（#189）：「成 N 轮，败 M 轮」说不出为什么，这里把
/// 每一轮的失败原因留下来。让位与停止不是这一轮的错，不计入 `failed`，但
/// 回执要能说清「让位 N 次、停止于哪一轮」。
public struct DigestRepairReceipt: Equatable, Sendable {
    public struct Failure: Equatable, Sendable {
        /// `sessionID#turnIndex`。
        public let key: String
        /// 人读得懂的一行：格式不合 / HTTP：… / 写库：…
        public let reason: String

        public init(key: String, reason: String) {
            self.key = key
            self.reason = reason
        }
    }

    /// 真正补上的轮数。
    public let done: Int
    /// 真失败的轮数（格式、HTTP、写库），不含让位与停止。
    public let failed: Int
    /// 逐轮失败明细，与 `failed` 一一对应。
    public let failures: [Failure]
    /// 让位次数（这一轮没轮到引擎，等下一个空窗再来）。
    public let yielded: Int
    /// 人按了停止时，停在哪一轮（`sessionID#turnIndex`）；没停止为 nil。
    public let stoppedAt: String?

    public init(done: Int, failed: Int, failures: [Failure],
                yielded: Int, stoppedAt: String?) {
        self.done = done
        self.failed = failed
        self.failures = failures
        self.yielded = yielded
        self.stoppedAt = stoppedAt
    }

    public static let empty = DigestRepairReceipt(
        done: 0, failed: 0, failures: [], yielded: 0, stoppedAt: nil)

    /// 失败原因的用词。分类必须可区分：格式不合（模型输出没通过解析）、
    /// HTTP（请求层失败）、写库（生成成功但落库失败）。让位/停止不在这里——
    /// 它们不是失败。
    public enum FailureReason {
        public static let badFormat = "格式不合"
        public static let noContent = "HTTP：模型返回里没有 content"
        public static let notOK = "HTTP：模型返回非 200"

        public static func describe(_ error: Error) -> String {
            switch error {
            case DigestionError.badFormat:
                return badFormat
            case let ns as NSError where ns.domain == "TurnDigest":
                switch ns.code {
                case 1: return notOK
                case 2: return noContent
                default: return "HTTP：\(ns.localizedDescription)"
                }
            default:
                return "HTTP：\(error.localizedDescription)"
            }
        }
    }

    /// 调度器内部的消化错误。放在契约包里是为了让失败分类可被契约测试
    /// 直接断言（`FillMissing` 在 App 目标，包测试够不到）。
    public enum DigestionError: Error, Equatable, Sendable {
        /// 人按了停止。
        case stopped
        /// 有人要用引擎，这一轮让位。
        case yielded
        /// 模型输出没通过解析。
        case badFormat
        /// 写库失败。
        case database(String)
        /// The turn changed while this snapshot was being summarized; discard
        /// this output and enqueue the current message version.
        case staleSource
    }
}
