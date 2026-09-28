import XCTest
import Foundation
import SimiGo2Experimental
@testable import SimiGo

private struct ByteArtifact: PrefixArtifactHandle {
    let bytes: Int?
    var physicalByteCount: Int? { bytes }
}

final class StorageRetentionTests: XCTestCase {
    private func makeStore() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-retention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeCheckpoint(
        _ directory: URL, key: String, date: Date, cacheBytes: Int
    ) throws {
        let base = NativeMLX.cacheFileName(for: key)
        try Data(repeating: 0, count: cacheBytes).write(
            to: directory.appendingPathComponent(base + ".safetensors"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = SessionCacheMetadata(
            storageKey: key,
            modelId: "retention-test-model",
            savedAt: date,
            history: [])
        try encoder.encode(metadata).write(
            to: directory.appendingPathComponent(base + ".meta.json"), options: .atomic)
    }

    func testBranchCheckpointByteBudgetKeepsActiveAndDropsOldestOrphan() throws {
        let directory = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try writeCheckpoint(directory, key: "old", date: now.addingTimeInterval(-60), cacheBytes: 50)
        try writeCheckpoint(directory, key: "active", date: now.addingTimeInterval(-10), cacheBytes: 60)

        let orphanCache = directory.appendingPathComponent("orphan.safetensors")
        try Data(count: 10).write(to: orphanCache)
        let malformedMeta = directory.appendingPathComponent("malformed.meta.json")
        try Data(count: 5).write(to: malformedMeta)
        try Data(count: 5).write(
            to: directory.appendingPathComponent("malformed.safetensors"))

        let result = try BranchCheckpointRetention.enforce(
            directory: directory,
            retainedKeys: ["active"],
            byteBudget: 70)

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanCache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: malformedMeta.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(
                NativeMLX.cacheFileName(for: "old") + ".safetensors").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(
                NativeMLX.cacheFileName(for: "active") + ".safetensors").path))
        XCTAssertEqual(result.removedForBudget, 2)
        XCTAssertGreaterThan(result.freedBytes, 50)
        XCTAssertEqual(result.retainedReceipts, 1)
    }

    func testPrefixPoolPhysicalByteBudgetEvictsLRU() {
        let namespace = PrefixPoolNamespace(modelID: "test", kvFingerprint: "none")
        let pool = ExecutionStatePrefixPool(tokenBudget: 1_000, physicalByteBudget: 25)
        pool.export(namespace: namespace, tokens: [1], artifact: ByteArtifact(bytes: 10))
        pool.export(namespace: namespace, tokens: [1, 2], artifact: ByteArtifact(bytes: 15))

        XCTAssertEqual(pool.totalTokens, 3)
        XCTAssertEqual(pool.totalPhysicalBytes, 25)

        pool.export(namespace: namespace, tokens: [1, 3], artifact: ByteArtifact(bytes: 10))

        XCTAssertEqual(pool.totalTokens, 4)
        XCTAssertEqual(pool.totalPhysicalBytes, 25)
        XCTAssertEqual(pool.stats.evictions, 1)
    }
}
