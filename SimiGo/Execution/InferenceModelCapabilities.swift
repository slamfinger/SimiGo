import Foundation
import MLXLMCommon

/// S1 Capability 架构（白皮书 §6.3 演进版，审计第五轮两层化 + 第六轮资格键修正）：
/// Capability 为两层三态，不再用单一 Bool 由 cache topology 直接推导。
///
/// 审计依据（实机证伪）：`isTrimmable == true` 不能推出 `supportsBatchDecode == true`——
/// Qwen3-Coder-30B-A3B（Standard-KV + trimmable + qwen3_moe）实测
/// prefill bit-exact 但 T=1 batched decode 行 1+ 系统性偏离（max|Δ| 9.5→17.75）。
/// Cache topology 只是 **必要条件**，不是充分条件。
///
/// 三原则（审计确立）：
/// ① 性能 GO ≠ 正确性 GO
/// ② Model Capability ≠ Effective Runtime Capability
/// ③ Upstream Dependency 必须经过 Empirical Conformance，不能只靠源码推断

/// 依赖版本常量——与 Package.resolved 锁定版本保持同步。
///
/// 纪律：依赖升级必须同步更新本常量。更新会使 `ExecutionQualificationKey`
/// 与既有 `ValidatedExecutionProfile` 失配、验证状态自动失效（退回 unknown），
/// 强制按白皮书 Conformance Matrix 重新取证（一次只升级一个变量）。
enum DependencyVersions {
    static let mlxSwift = "0.31.6"
    static let mlxSwiftLM = "3.31.4"

    static var identifier: String { "mlx-swift \(mlxSwift) / mlx-swift-lm \(mlxSwiftLM)" }
}

/// 执行资格键：唯一标识一条验证证据的适用环境。
///
/// `ValidatedExecutionProfile` 的 verified 状态**只对键匹配的执行环境有效**——
/// 键失配（依赖升级、模型更换、硬件变更、批宽/精度变化）⇒ 验证状态自动失效。
/// 这防止 `static let verifiedProfile` 退化成无视环境的全局许可证。
struct ExecutionQualificationKey: Sendable, Equatable, Hashable {
    let backendVersion: String     // mlx-swift 版本
    let runtimeVersion: String     // mlx-swift-lm 版本
    let modelFamily: String        // 模型家族（如 "qwen3_moe"）
    let modelFingerprint: String   // 模型标识（路径/ID 的稳定摘要或人工标注）
    let hardwareFamily: String     // 硬件家族（arm64 机器标识）
    let memoryClass: String        // 内存档位（物理内存桶化，如 "32GB"）
    let executionBatchSize: Int    // 批宽（S1 固定 2/4）
    let decodeShape: String        // decode 形状（S1 = "T=1-fixed-quantum"）
    let precision: String          // 数值精度（如 "float16"）

    /// 当前执行环境键（取证时验证所针对的环境）。
    /// hardware/memory 取自本机；模型维度由调用方（知道模型身份的一侧）提供。
    static func currentEnvironment(
        modelFamily: String,
        modelFingerprint: String,
        batchSize: Int,
        precision: String
    ) -> ExecutionQualificationKey {
        ExecutionQualificationKey(
            backendVersion: "mlx-swift \(DependencyVersions.mlxSwift)",
            runtimeVersion: "mlx-swift-lm \(DependencyVersions.mlxSwiftLM)",
            modelFamily: modelFamily,
            modelFingerprint: modelFingerprint,
            hardwareFamily: Self.machineIdentifier,
            memoryClass: Self.memoryClass,
            executionBatchSize: batchSize,
            decodeShape: "T=1-fixed-quantum",
            precision: precision
        )
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }

    private static var memoryClass: String {
        let gib = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        return "\(gib)GB"
    }
}

/// 三态能力状态：unknown（未验证）/ verified（实机验证通过）/ rejected（实机验证失败）
enum CapabilityStatus: Sendable, Equatable {
    case unknown
    case verified
    case rejected
}

/// 第一层：Static Model Capability——来自模型结构（cache topology）。
///
/// 命名纪律（审计第六轮 P2）：Static 层字段只描述**结构事实**（has*），
/// 不得用 `supports*` 表达执行能力——执行能力属于 Validated 层。
struct ModelCapabilities: Sendable, Equatable {
    let hasStandardKV: Bool
    let hasRecurrentState: Bool
    let hasCacheTopologyCompatibleWithTrim: Bool

    static func evaluate(caches: [any KVCache]) -> ModelCapabilities {
        guard !caches.isEmpty else {
            return ModelCapabilities(
                hasStandardKV: false,
                hasRecurrentState: false,
                hasCacheTopologyCompatibleWithTrim: false
            )
        }

        let allTrimmable = caches.allSatisfy { $0.isTrimmable }
        return ModelCapabilities(
            hasStandardKV: allTrimmable,
            hasRecurrentState: !allTrimmable,
            hasCacheTopologyCompatibleWithTrim: allTrimmable
        )
    }
}

/// 第二层：Validated Execution Capability——来自真实运行验证
/// （键匹配的 Backend + Model + Version + Hardware + Execution Shape 组合实证）。
struct ValidatedExecutionProfile: Sendable, Equatable {
    let key: ExecutionQualificationKey
    let batchPrefill: CapabilityStatus
    let batchDecodeT1: CapabilityStatus
    let perSequenceRoPE: CapabilityStatus
    let raggedBatch: CapabilityStatus
    let batchCancellation: CapabilityStatus

    /// 当前锁定依赖组合 + Qwen3-Coder-30B-A3B 实机的验证记录
    /// （证据：BatchDecodeDependencyConformanceTests / KV 全链路审计）：
    /// - batchPrefill = VERIFIED：Qwen3-Coder 与 tiny Qwen3-MoE prefill 均 bit-exact
    /// - batchDecodeT1 = REJECTED：T=1 batched decode 行 1+ logits 与单流系统性偏离
    ///   （max|Δ| 9.5→17.75，tiny 随机权重模型复现——上游缺陷，非 SimiGo 实现问题）
    /// - perSequenceRoPE = VERIFIED：cache 内 K 逐位置对比 0.0（RoPE 层排除）
    ///
    /// hardware/memory 字段钉死取证机器（`uname -m` = "arm64"、32GiB 物理内存），
    /// 必须与 `ExecutionQualificationKey.currentEnvironment` 的产出逐字一致——
    /// 写成任何别名将使键永不匹配、验证状态不可读取（审计第六轮修复）。
    static let qwen3CoderRecord = ValidatedExecutionProfile(
        key: ExecutionQualificationKey(
            backendVersion: "mlx-swift \(DependencyVersions.mlxSwift)",
            runtimeVersion: "mlx-swift-lm \(DependencyVersions.mlxSwiftLM)",
            modelFamily: "qwen3_moe",
            modelFingerprint: "Qwen3-Coder-30B-A3B-Instruct-4bit (mlx-community)",
            hardwareFamily: "arm64",
            memoryClass: "32GB",
            executionBatchSize: 4,
            decodeShape: "T=1-fixed-quantum",
            precision: "float16"
        ),
        batchPrefill: .verified,
        batchDecodeT1: .rejected,
        perSequenceRoPE: .verified,
        raggedBatch: .unknown,
        batchCancellation: .unknown
    )
}

/// Effective Capability 容器：Scheduler 的准入判据来源。
///
/// `effectiveSupportsBatchDecode` 在 evaluate 时判定：
/// Static 必要条件 + profile 键与当前执行环境匹配 + 验证状态全 verified。
/// 键失配 ⇒ 一切验证状态视为 unknown ⇒ gate 关闭 ⇒ Single / interleaved 路径。
struct InferenceModelCapabilities: Sendable, Equatable {
    let model: ModelCapabilities
    let executionProfile: ValidatedExecutionProfile

    /// Effective gate——evaluate 时按环境键匹配判定并固化。
    /// 语义：Batch reject → Execution Gate 选择 Single / interleaved fallback
    /// （注意：fallback 由调用方选择，Scheduler 本身只做拒绝，见白皮书第九章）。
    let effectiveSupportsBatchDecode: Bool

    static func evaluate(
        caches: [any KVCache],
        modelFamily: String,
        modelFingerprint: String,
        precision: String,
        batchSize: Int,
        executionProfile: ValidatedExecutionProfile
    ) -> InferenceModelCapabilities {
        let model = ModelCapabilities.evaluate(caches: caches)

        // 资格键匹配：profile 的验证证据只对键相同的执行环境有效
        let currentKey = ExecutionQualificationKey.currentEnvironment(
            modelFamily: modelFamily,
            modelFingerprint: modelFingerprint,
            batchSize: batchSize,
            precision: precision
        )
        let keyMatches = currentKey == executionProfile.key

        let effective = keyMatches
            && model.hasStandardKV
            && executionProfile.batchPrefill == .verified
            && executionProfile.batchDecodeT1 == .verified

        return InferenceModelCapabilities(
            model: model,
            executionProfile: executionProfile,
            effectiveSupportsBatchDecode: effective
        )
    }
}
