import Foundation

/// Minimal runtime limits that delegate memory governance to MLX.
enum RuntimeTuning {
    static let gibibyte = 1024 * 1024 * 1024

    /// MLX overall allocation limit.
    static let mlxMemoryLimitBytes = 22 * gibibyte

    /// MLX recyclable buffer cache limit.
    static let mlxCacheLimitBytes = 4 * gibibyte

    /// Responses store is protocol state, not inference memory.
    static let responsesStoreMaxCount = 64
    static let responsesStoreTTLSeconds: TimeInterval = 1800
}
