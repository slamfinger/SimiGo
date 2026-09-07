import Foundation
import MLXLMCommon

/// S1（白皮书第六章 §6.3 演进版，审计第五轮裁决）：
/// Capability 升级为两层三态，不再用单一 Bool 由 cache topology 直接推导。
///
/// 审计依据（实机证伪）：`isTrimmable == true` 不能推出 `supportsBatchDecode == true`——
/// Qwen3-Coder-30B-A3B（Standard-KV + trimmable + qwen3_moe）实测
/// prefill bit-exact 但 T=1 batched decode 行 1+ 系统性偏离（max|Δ| 9.5→17.75）。
/// Cache topology 只是 **必要条件**，不是充分条件。
///
/// 两层：
/// - `ModelCapabilities`：Static Model Capability，来自模型结构（cache topology）
/// - `ValidatedExecutionProfile`：Validated Execution Capability，来自真实运行验证
///   （Backend + Model + Version + Hardware + Execution Shape）
///
/// Scheduler 看的是 `effectiveSupportsBatchDecode`（Effective Capability），
/// 而不是直接看 topology。

/// 三态能力状态：unknown（未验证）/ verified（实机验证通过）/ rejected（实机验证失败）
enum CapabilityStatus: Sendable, Equatable {
    case unknown
    case verified
    case rejected
}

/// 第一层：Static Model Capability——来自模型结构（cache topology），
/// 是必要条件而非充分条件。
struct ModelCapabilities: Sendable, Equatable {
    let hasStandardKV: Bool
    let hasRecurrentState: Bool
    let supportsPerSequenceRoPE: Bool
    let supportsCacheTrim: Bool

    static func evaluate(caches: [any KVCache]) -> ModelCapabilities {
        guard !caches.isEmpty else {
            return ModelCapabilities(
                hasStandardKV: false,
                hasRecurrentState: false,
                supportsPerSequenceRoPE: false,
                supportsCacheTrim: false
            )
        }

        let allTrimmable = caches.allSatisfy { $0.isTrimmable }
        return ModelCapabilities(
            hasStandardKV: allTrimmable,
            hasRecurrentState: !allTrimmable,
            supportsPerSequenceRoPE: allTrimmable,
            supportsCacheTrim: allTrimmable
        )
    }
}

/// 第二层：Validated Execution Capability——来自真实运行验证
/// （Backend + Model + Version + Hardware + Execution Shape 的组合实证）。
struct ValidatedExecutionProfile: Sendable, Equatable {
    let backendIdentifier: String
    let batchPrefill: CapabilityStatus
    let batchDecodeT1: CapabilityStatus
    let raggedBatch: CapabilityStatus
    let batchCancellation: CapabilityStatus

    /// 当前锁定依赖组合的实机验证记录
    /// （证据：BatchDecodeDependencyConformanceTests / Qwen3-Coder-30B-A3B 实机）：
    /// - batchPrefill = VERIFIED：Qwen3-Coder 与 tiny Qwen3-MoE prefill 均 bit-exact
    /// - batchDecodeT1 = REJECTED：T=1 batched decode 行 1+ logits 与单流系统性偏离
    ///   （max|Δ| 9.5→17.75，tiny 随机权重模型复现——上游缺陷，非 SimiGo 实现问题）
    static let mlxSwift0_31_6__mlxSwiftLM3_31_4 = ValidatedExecutionProfile(
        backendIdentifier: "mlx-swift 0.31.6 / mlx-swift-lm 3.31.4",
        batchPrefill: .verified,
        batchDecodeT1: .rejected,
        raggedBatch: .unknown,
        batchCancellation: .unknown
    )
}

/// Effective Capability：Scheduler 的准入判据。
/// 结构按白皮书 §6.3 演进：单 Bool 升级为两层三态。
struct InferenceModelCapabilities: Sendable, Equatable {
    let model: ModelCapabilities
    let execution: ValidatedExecutionProfile

    /// Effective gate：Static 必要条件 + Execution 验证状态同时满足。
    /// 当前锁定依赖下为 false（batchDecodeT1 = rejected）——
    /// BatchedDecodeScheduler 拒绝组批 → Single / interleaved fallback。
    var effectiveSupportsBatchDecode: Bool {
        model.hasStandardKV
            && execution.batchPrefill == .verified
            && execution.batchDecodeT1 == .verified
    }

    /// 兼容读取：Effective gate（语义 = 旧 supportsBatchDecode，但判定来源已修正）
    var supportsBatchDecode: Bool { effectiveSupportsBatchDecode }

    static func evaluate(
        caches: [any KVCache],
        executionProfile: ValidatedExecutionProfile = .mlxSwift0_31_6__mlxSwiftLM3_31_4
    ) -> InferenceModelCapabilities {
        InferenceModelCapabilities(
            model: .evaluate(caches: caches),
            execution: executionProfile
        )
    }
}
