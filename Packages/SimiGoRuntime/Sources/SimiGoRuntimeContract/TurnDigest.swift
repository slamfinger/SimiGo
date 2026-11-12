import Foundation

/// 一轮摘要的输入输出约定。摘要是**精编**，不是节选：说清这一轮要解决
/// 什么、结论是什么、哪件明确没做。语气必须跟原文一致——提出就是提出，
/// 没被认可的不能写成「决定」。
public enum TurnDigestText {
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

    public static func prompt(question: String, answer: String) -> String {
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

        \(note)问题：
        \(String(question.prefix(maxQuestion)))

        回答：
        \(body)
        """
    }

    /// 解析模型的两行输出。格式不对就是 nil——调用方不猜、不兜底，
    /// 只是把这一轮留在「缺摘要」里。
    public static func parse(_ raw: String) -> (digest: String, keywords: [String])? {
        var digest: String?
        var keywordLine: String?
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = stripNoise(String(line))
            if trimmed.hasPrefix("摘要：") || trimmed.hasPrefix("摘要:") {
                digest = stripNoise(String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("关键词：") || trimmed.hasPrefix("关键词:") {
                keywordLine = stripNoise(String(trimmed.dropFirst(4)))
            }
        }
        guard let digest, !digest.isEmpty, let keywordLine else { return nil }
        let terms = splitTerms(keywordLine)
        guard !terms.isEmpty else { return nil }
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
