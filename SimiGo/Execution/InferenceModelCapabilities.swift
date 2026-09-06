import Foundation
import MLXLMCommon

/// S1（白皮书第六章 §6.3）：模型能力声明——Execution Plane 的 Capability 契约。
///
/// 铁律：Runtime 不得按模型名称写特殊分支；一切按 Capability 判定。
/// 推导来源为 cache topology（实机实证，KV 全链路审计第五/六轮）：
/// - 全部 cache 可裁剪（Standard-KV）→ supportsBatchDecode = true
///   （Qwen3-Coder-30B-A3B 实机 batch=4 原型 75.1 tok/s，prefill bit-exact）；
/// - 含 recurrent cache（qwen3_5_moe 混合架构 MambaCache）→ false
///   （实机 NO-GO 证据：batched decode 行 1+ logits 与单流系统性偏离 9.5-17.75）。
struct InferenceModelCapabilities: Sendable, Equatable {
    let supportsBatchDecode: Bool
    let supportsPerSequenceRoPE: Bool
    let supportsIndependentKVState: Bool
    let supportsPromptCacheTrim: Bool
    let supportsRaggedBatch: Bool
    let supportsRecurrentStateBatch: Bool
    let supportsSpeculativeDecode: Bool
    let supportsPagedKV: Bool

    /// 由模型 cache topology 推导能力。
    /// 不变量：非 trimmable cache（recurrent state 不可前缀截断）⇒ Batch/Ragged 一律 false。
    /// Ragged/Speculative/Paged 属 S2/S3，固定 false 直至对应演进阶段立项。
    static func evaluate(caches: [any KVCache]) -> InferenceModelCapabilities {
        let trimmable = !caches.isEmpty && caches.allSatisfy { $0.isTrimmable }

        return InferenceModelCapabilities(
            supportsBatchDecode: trimmable,
            supportsPerSequenceRoPE: trimmable,
            supportsIndependentKVState: trimmable,
            supportsPromptCacheTrim: trimmable,
            supportsRaggedBatch: false,
            supportsRecurrentStateBatch: false,
            supportsSpeculativeDecode: false,
            supportsPagedKV: false
        )
    }
}
