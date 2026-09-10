import Foundation

/// Protocol-layer retention limits for Responses state.
/// These values bound service bookkeeping only; they do not govern inference memory or KV cache.
enum RuntimeTuning {
    static let responsesStoreMaxCount = 64
    static let responsesStoreTTLSeconds: TimeInterval = 1800
}
