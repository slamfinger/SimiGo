import XCTest
@testable import SimiGo2Experimental
import SimiGoRuntimeContract

/// L49（契约③）隔离测试：fork 点内容寻址原语——零模型、零 IO、纯函数。
///
/// 这些是结构性质（谓词级），不是阈值门：
/// 1. 地址不混入身份：同一覆盖前缀内容，无论「出自哪个会话/分支」
///    （本原语根本没有身份入参）都得到同一地址——H2「内容寻址后同前缀
///    两次 hit 相同」的结构前提。
/// 2. 内容区分度：不同内容（消息数、内容、角色、顺序）⇒ 不同地址。
/// 3. 与池寻址同源：产出喂给 `SettlementKVBinding.Representation` 得到
///    与池一致的 poolKey 分量（同前缀 ⇒ 同 poolKey，跨分支可比）。
final class ForkPointAddressTests: XCTestCase {

    private let messages: [(role: String, content: String)] = [
        ("system", "你是 SimiGo。"),
        ("user", "读 IS 领单"),
        ("assistant", "已认领 L49，契约③ 分叉点内容寻址。"),
        ("user", "隔离测试跑起来"),
    ]

    func testSameContentYieldsIdenticalAddressAcrossSessionsAndBranches() {
        // fork 点地址只由内容导出：同内容两次求址（模拟两个不同
        // session/branch 的 fork 位点）逐分量相等。
        let a = ForkPointAddress.digest(messages: messages)
        let b = ForkPointAddress.digest(messages: messages)
        XCTAssertEqual(a.boundaryHash, b.boundaryHash)
        XCTAssertEqual(a.contentDigest, b.contentDigest)
        XCTAssertEqual(a.contentDigest.count, 64)
        // SHA-256 十六进制小写（与 sidecar/pool 的 contentDigest 口径一致）。
        XCTAssertEqual(a.contentDigest, a.contentDigest.lowercased())
    }

    func testDifferentContentYieldsDifferentAddresses() {
        let baseline = ForkPointAddress.digest(messages: messages)
        struct Variant {
            let name: String
            let messages: [(role: String, content: String)]
        }
        let variants: [Variant] = [
            Variant(name: "多一条消息", messages: messages + [("user", "继续")]),
            Variant(name: "同长不同内容", messages: messages.map {
                ($0.role, $0.content + "！")
            }),
            Variant(name: "角色不同", messages: [("system", "你是 SimiGo。"),
                                                  ("user", "读 IS 领单"),
                                                  ("user", "已认领 L49，契约③ 分叉点内容寻址。"),
                                                  ("user", "隔离测试跑起来")]),
            Variant(name: "顺序不同", messages: [(messages[3].role, messages[3].content),
                                                  (messages[2].role, messages[2].content),
                                                  (messages[1].role, messages[1].content),
                                                  (messages[0].role, messages[0].content)]),
        ]
        for variant in variants {
            let address = ForkPointAddress.digest(messages: variant.messages)
            XCTAssertNotEqual(address.boundaryHash, baseline.boundaryHash,
                              "\(variant.name) 的链哈希不应与基线相同")
            XCTAssertNotEqual(address.contentDigest, baseline.contentDigest,
                              "\(variant.name) 的内容承诺不应与基线相同")
        }
        // 变体之间也两两不同（内容承诺 64 hex 无碰撞）。
        let digests = variants.map { ForkPointAddress.digest(messages: $0.messages).contentDigest }
        XCTAssertEqual(Set(digests).count, digests.count)
    }

    func testAddressFeedsSettlementKVBindingPoolKey() {
        // 与池同源：同内容 ⇒ 同 poolKey（跨分支/会话可比）；内容变 ⇒ poolKey 变。
        func poolKey(of messages: [(role: String, content: String)]) -> String {
            let address = ForkPointAddress.digest(messages: messages)
            return SettlementKVBinding.Representation(
                modelID: "ornith-ai/Ornith-1.5-35B-A3B-MLX-4bit",
                kvFingerprint: "base|think:1|physical:abc",
                tokenCount: 4096,
                boundaryHash: address.boundaryHash,
                contentDigest: address.contentDigest).poolKey
        }
        let same = poolKey(of: messages)
        XCTAssertEqual(same, poolKey(of: messages))
        XCTAssertNotEqual(same, poolKey(of: messages + [("user", "换话题")]))
        // poolKey 的内容承诺段就是 ForkPointAddress 的 contentDigest。
        XCTAssertTrue(same.hasSuffix(ForkPointAddress.digest(messages: messages).contentDigest))
    }

    func testEmptyPrefixHasStableAddress() {
        // 空覆盖前缀（fork 在零消息处）也是稳定内容地址，不崩、不随机。
        let a = ForkPointAddress.digest(messages: [])
        let b = ForkPointAddress.digest(messages: [])
        XCTAssertEqual(a.boundaryHash, b.boundaryHash)
        XCTAssertEqual(a.contentDigest, b.contentDigest)
        XCTAssertNotEqual(a.contentDigest,
                          ForkPointAddress.digest(messages: [("user", "x")]).contentDigest)
    }
}
