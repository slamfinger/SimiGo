import Foundation

/// SimiGo Runtime 调优常量 —— 每项标注白皮书出处，集中于此便于校准与审计。
/// 修改任何一项须按铁律 35/63 以实机 Benchmark 背书，一次只动一个变量（铁律 37）。
enum RuntimeTuning {
    static let gibibyte = 1024 * 1024 * 1024

    // MARK: Memory Governance（§29/§30，铁律 85-90）

    /// §29/§30：Admission 上限（KV 口径；权重感知部分见 NativeMLX）
    static let admissionMemoryLimitBytes = 22 * gibibyte

    /// §29：MLX 运行时 cache 上限
    static let mlxCacheLimitBytes = 4 * gibibyte

    /// §30：Execution Working Set
    static let executionWorkingSetBytes: UInt64 = 3 * 1024 * 1024 * 1024

    /// §30：Safety Margin
    static let safetyMarginBytes: UInt64 = 1 * 1024 * 1024 * 1024

    /// 权重感知预算的 OS + App 基线预留（铁律 63，2026-09-05 实机校准）
    static let osReserveBytes = 4 * gibibyte

    /// Admission 预算下限防御
    static let admissionFloorBytes: UInt64 = 4 * 1024 * 1024 * 1024

    /// Delta KV 投影（35B-A3B 实测 ≈122KB/token）
    static let estimatedKVBytesPerToken: UInt64 = 128 * 1024

    // MARK: Physical KV / Session（§9/§33/§36，铁律 83-90）

    /// §9：Revision 历史上限（非内存预算，铁律 83/89）
    static let maxPhysicalKVRevisions = 16

    /// §33：长上下文阈值
    static let longContextThreshold = 16384

    /// 逻辑会话 TTL
    static let sessionMaxIdleSeconds: TimeInterval = 1800

    // MARK: Responses Store（§47：Responses State ≠ Physical KV）

    /// Responses 存储池上限
    static let responsesStoreMaxCount = 64
    /// Responses 存储池 TTL
    static let responsesStoreTTLSeconds: TimeInterval = 1800

    // MARK: Prefill（§40）

    /// §40：Prefill chunk 基线，不得未经 Benchmark 固化新值
    static let prefillChunkSize = 1024
}
