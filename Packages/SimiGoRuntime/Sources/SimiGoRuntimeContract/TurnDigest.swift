import Foundation

/// 一轮摘要的输入输出约定。摘要是**精编**，不是节选：说清这一轮要解决
/// 什么、结论是什么、哪件明确没做。语气必须跟原文一致——提出就是提出，
/// 没被认可的不能写成「决定」。
public enum TurnDigestText {
    /// 原样正文的截断上限。超长的轮次按已给部分总结，宁可少说，不编。
    public static let maxQuestion = 3_000
    public static let maxAnswer = 9_000
    public static let maxDigest = 300
    public static let maxKeywords = 8

    public static func prompt(question: String, answer: String) -> String {
        """
        你在给一个信息空间写轮次摘要。下面是一轮会话的问题和回答。

        只输出两行，不要任何解释：
        摘要：<两到三句。这一轮要解决什么、最后的结论是什么、哪件事明确没做。\
        措辞必须跟原文一致：原文是提议就写提议，原文是用户裁定才写已定/裁定。\
        不要写「用户说/助手回答」这类套话，不要抄原句>
        关键词：<5 到 8 个词，空格分隔。每个词 2 到 8 个字，尽量用原文里出现过的词，\
        因为以后要拿它去查原文。不要标点，不要整句>

        问题：
        \(String(question.prefix(maxQuestion)))

        回答：
        \(String(answer.prefix(maxAnswer)))
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
