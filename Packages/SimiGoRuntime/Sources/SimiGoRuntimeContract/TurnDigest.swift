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
        // 模型爱在行首行尾加星号、项目符号：先剥掉再认标签，认完再剥一次值。
        func strip(_ text: String) -> String {
            var out = Substring(text)
            let noise = CharacterSet(charactersIn: "*-• \t")
            while let f = out.first, f.unicodeScalars.allSatisfy(noise.contains) {
                out = out.dropFirst()
            }
            return out.trimmingCharacters(in: .whitespaces)
        }
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = strip(String(line))
            if trimmed.hasPrefix("摘要：") || trimmed.hasPrefix("摘要:") {
                digest = strip(String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("关键词：") || trimmed.hasPrefix("关键词:") {
                keywordLine = strip(String(trimmed.dropFirst(4)))
            }
        }
        guard let digest, !digest.isEmpty, let keywordLine else { return nil }
        var seen = Set<String>()
        var terms: [String] = []
        let separators = CharacterSet.whitespaces
            .union(CharacterSet(charactersIn: "，、,;；:：()（）[]【】。.\"'“”*"))
        for raw in keywordLine.components(separatedBy: separators) where !raw.isEmpty {
            if seen.insert(raw).inserted { terms.append(raw) }
            if terms.count == maxKeywords { break }
        }
        guard !terms.isEmpty else { return nil }
        return (String(digest.prefix(maxDigest)), terms)
    }
}
