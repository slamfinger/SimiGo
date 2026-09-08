import Foundation

/// SimiGo Runtime 调优常量 —— 每项标注白皮书出处，集中于此便于校准与审计。
/// 修改任何一项须按铁律 35/63 以实机 Benchmark 背书，一次只动一个变量（铁律 37）。
enum RuntimeTuning {
    static let gibibyte = 1024 * 1024 * 1024

    // MARK: Memory Governance（§29/§30，铁律 85-90）

    /// §29/§30：Admission 上限（KV 口径；权重感知部分见 NativeMLX）
    static let admissionMemoryLimitBytes = 22 * gibibyte

    /// 实验性 soft allowance：允许在 hard admission 预算以上、但仍受独立
    /// pressure gate 约束的有限窗口内继续运行。当前值仅作为实验旋钮；
    /// 核心实现不得把它当作新的硬上限。
    static let admissionSoftAllowanceBytes: UInt64 = 2 * UInt64(gibibyte)

    /// 实验性 soft path 的独立最低 OS + App emergency reserve。
    /// 与正常 3.5 GiB 基线预留分离，用于防止 soft allowance 将机器直接推到
    /// 物理内存边界；该值只约束 experimental soft ceiling，不改变 hard ceiling。
    static let admissionEmergencyReserveBytes: UInt64 = 1 * UInt64(gibibyte)

    /// §29：MLX 运行时 cache 上限
    static let mlxCacheLimitBytes = 4 * gibibyte

    /// §30：Execution Working Set
    static let executionWorkingSetBytes: UInt64 = 3 * 1024 * 1024 * 1024

    /// §30：Safety Margin
    static let safetyMarginBytes: UInt64 = 1 * 1024 * 1024 * 1024

    /// 权重感知预算的 OS + App 基线预留。
    /// 2026-09-08 调整为 3.5 GiB：此前 4 GiB 在低实际 RSS 压力场景下造成
    /// 200~500 MiB 级 false rejection。保留独立 1 GiB Safety Margin，
    /// 因此不会通过放宽上限来取消 Predictive Admission Control。
    static let osReserveBytes = Int64(3.5 * Double(gibibyte))

    /// Admission 预算下限防御
    static let admissionFloorBytes: UInt64 = 4 * 1024 * 1024 * 1024

    /// Delta KV 投影（35B-A3B 实测 ≈122KB/token）
    static let estimatedKVBytesPerToken: UInt64 = 128 * 1024

    // MARK: Generation（协议默认值集中管理）

    /// Generation 默认上限；避免运行时散落硬编码。
    static let maxGenerationTokens = 4096

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
