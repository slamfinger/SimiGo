import Foundation
import MLX
import MLXLMCommon

// MARK: - Branch Degeneration State

struct BranchDegenerationState: Sendable {
    struct Probe: Sendable {
        let signatures: [String]
        let progress: String
        let projected: Int
        let blocked: Bool
    }

    var lastSignatures: [String] = []
    var lastProgress: String?
    var consecutive = 0
    var round = 0

    func preview(signatures: [String], progress: String, threshold: Int = 3) -> Probe {
        let projected = (signatures == lastSignatures && progress == lastProgress) ? (consecutive + 1) : 1

        return Probe(
            signatures: signatures,
            progress: progress,
            projected: projected,
            blocked: projected >= threshold
        )
    }

    mutating func commitForwarded(_ probe: Probe) {
        round += 1
        lastSignatures = probe.signatures
        lastProgress = probe.progress
        consecutive = probe.projected
    }

    mutating func recordBlocked(_ probe: Probe) {
        commitForwarded(probe)
    }

    mutating func resetOnPlain() {
        round += 1
        lastSignatures.removeAll(keepingCapacity: false)
        lastProgress = nil
        consecutive = 0
    }
}

struct LogicalBranchState: Sendable {
    let logicalBranchId: String
    var toolFingerprint: String
    var degenerationState = BranchDegenerationState()
    var lastActive = Date()
}

// MARK: - Runtime-global Physical KV Revision

struct PhysicalKVRevision: @unchecked Sendable {
    var id: String
    var logicalBranchId: String
    var toolFingerprint: String
    var physicalTokens: [Int]
    var kvCache: [any KVCache]
    var lastActive: Date

    var cacheTokenCount: Int { physicalTokens.count }
    var resident: Bool { !kvCache.isEmpty }
    var estimatedResidentBytes: UInt64 { resident ? UInt64(physicalTokens.count) * 128 * 1024 : 0 }

    mutating func releasePhysicalMemory() {
        for kv in kvCache {
            _ = kv.trim(physicalTokens.count)
        }

        kvCache.removeAll(keepingCapacity: false)
    }
}

struct SessionLogicalState: Sendable {
    var logicalBranches: [String: LogicalBranchState] = [:]
    var lastActive: Date = Date()
}

// MARK: - Compact Log Helpers

nonisolated func compactTokenCount(_ count: Int) -> String {
    if count >= 1000 {
        return String(format: "%.1fk", Double(count) / 1000.0)
    }

    return String(count)
}

// MARK: - Native MLX Runtime
