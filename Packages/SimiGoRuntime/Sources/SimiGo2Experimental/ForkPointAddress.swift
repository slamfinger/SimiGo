import Foundation

/// L49（契约③ 前置件）：fork 点的内容寻址原语。
///
/// 契约③（§十一）：分叉点按 digest 链尾内容哈希寻址——fork 点的物理地址
/// 只由「覆盖前缀的内容承诺」导出，不得混入会话/分支身份（storageKey、
/// branch id 都是身份，不是内容）。此前 fork 位点的 RepresentationRef
/// 由 `[sourceStorageKey, targetStorageKey, tokenCount]` 哈希导出：内容
/// 相同的 fork 前缀在不同分支/会话下得到不同地址（同前缀各自冷、跨会话
/// 零共享），而不同内容碰巧同长同 id 也无法区分——物理分叉点与语义账本
/// 脱钩的物理层根因。
///
/// 本原语与磁盘池/内存池的现有内容寻址同源：消息流编码用
/// `PrefixMessageChain`（与日常路径轮末导出逐字节同一编码），承诺用
/// `PrefixChain.hash`（快索引）＋ `PrefixChain.contentDigest`（SHA-256，
/// 授权比较用的那一枚）。产出的三元量可直接喂给
/// `SettlementKVBinding.Representation` 得到与池一致的 poolKey 分量。
///
/// 无模型依赖、无 IO、纯函数；调用方负责消息序与 `boundLength`（fork 点
/// token 数）的因果语义——本函数不解释 token 数，也不核对它与消息流的关系。
public enum ForkPointAddress {

    /// fork 点地址：覆盖前缀（fork 点之前的全部消息）的内容承诺。
    ///
    /// - Parameter messages: 覆盖前缀的消息流（角色＋内容），顺序即链序。
    ///   编码与日常路径池导出完全一致（`PrefixMessageChain.stream`）。
    /// - Returns: `boundaryHash`＝消息链哈希（快索引）；`contentDigest`＝
    ///   SHA-256 内容承诺（64 hex，授权比较用）。
    public static func digest(
        messages: [(role: String, content: String)]
    ) -> (boundaryHash: UInt64, contentDigest: String) {
        let stream = PrefixMessageChain.stream(messages)
        return (
            PrefixChain.hash(stream),
            PrefixChain.contentDigest(stream, domain: .messageSequence)
        )
    }
}
