import XCTest

@testable import SimiGoRuntimeContract

/// L44 机械摘要档：确定性、零模型调用、输出即落库形态。
/// 同输入恒同输出——它是渲染前缀与检索词表的字节稳定源。
final class TurnDigestMechanicalTests: XCTestCase {
    func testDeterministicSameInputSameOutput() {
        let q = "为什么压实边界移动会导致冷重建？"
        let a = "检查点处边界跳变，有界 brief 前缀冷重建一次，按间隔摊薄。其余轮次边界固定。"
        let first = TurnDigestText.mechanical(question: q, answer: a)
        let second = TurnDigestText.mechanical(question: q, answer: a)
        XCTAssertEqual(first.digest, second.digest)
        XCTAssertEqual(first.keywords, second.keywords)
        XCTAssertFalse(first.digest.isEmpty)
        XCTAssertTrue(first.digest.hasPrefix("问题："))
        XCTAssertTrue(first.digest.contains("回答要点"))
    }

    func testKeywordsBoundedAndStable() {
        let q = "信息空间的内容寻址结算怎么保证新鲜度"
        let a = "结算绑定 model 身份与 payload 摘要，源变更即失效。依赖闭包声明随之提交。"
        let keywords = TurnDigestText.mechanicalKeywords(question: q, answer: a)
        XCTAssertFalse(keywords.isEmpty)
        XCTAssertLessThanOrEqual(keywords.count, 8)
        XCTAssertEqual(Set(keywords).count, keywords.count, "关键词不得重复")
        for term in keywords {
            XCTAssertLessThanOrEqual(term.count, 8)
        }
        let again = TurnDigestText.mechanicalKeywords(question: q, answer: a)
        XCTAssertEqual(keywords, again)
    }

    func testKeywordExcludesStopwordFragments() {
        let keywords = TurnDigestText.mechanicalKeywords(
            question: "这个可以吗",
            answer: "没有其他需要。")
        XCTAssertFalse(keywords.contains("这个"))
        XCTAssertFalse(keywords.contains("没有"))
    }

    func testLatinTokensEnterKeywords() {
        let q = "How does RTK fix initialization work?"
        let a = "Carrier phase ambiguity resolution enables centimeter positioning with base rover correction."
        let keywords = TurnDigestText.mechanicalKeywords(question: q, answer: a)
        XCTAssertTrue(keywords.contains("carrier") || keywords.contains("ambiguity"),
                      "拉丁词应入关键词：\(keywords)")
    }

    func testLongAnswerTruncatedBounded() {
        let a = String(repeating: "这是一段很长的回答内容，用于验证截断有界。", count: 500)
        let out = TurnDigestText.mechanical(question: "长轮截断", answer: a)
        XCTAssertLessThan(out.digest.count, 500)
    }

    func testEmptyAnswerStillProducesQuestionDigest() {
        let out = TurnDigestText.mechanical(question: "只有问题的轮次", answer: "   ")
        XCTAssertFalse(out.digest.isEmpty)
        XCTAssertTrue(out.digest.contains("只有问题的轮次"))
    }
}
