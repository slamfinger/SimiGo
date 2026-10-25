import Foundation
import MLXLMCommon

/// Backend boundary for MLX prompt-cache artifacts. The generic disk store
/// never names this payload type; runtime callers opt into MLX here.
public struct MLXPrefixSnapshotLoader: Sendable {
    private let store: PrefixSnapshotStore

    public init(store: PrefixSnapshotStore) {
        self.store = store
    }

    public func load(_ admission: PrefixAdmission) async throws -> PromptCacheSnapshot {
        try await store.load(admission) { url in
            try loadPromptCacheSnapshot(url: url, materializeArrays: true)
        }
    }

    public func loadSync(_ admission: PrefixAdmission) throws -> PromptCacheSnapshot {
        try store.loadSync(admission) { url in
            try loadPromptCacheSnapshot(url: url, materializeArrays: true)
        }
    }
}
