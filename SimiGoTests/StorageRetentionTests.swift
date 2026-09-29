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

    /// #1 回归（差分）：未超预算时整个 sidecar 解码段被跳过——用「畸形
    /// 但配对完好」的 receipt 探针，旧路径会在 decode 失败时立即删除它，
    /// 新路径未超预算必须原样保留。
    func testUnderBudgetSkipsMetadataDecodeAndKeepsMalformedPairs() throws {
        let directory = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try writeCheckpoint(directory, key: "a", date: now, cacheBytes: 40)
        try writeCheckpoint(directory, key: "b", date: now, cacheBytes: 40)
        // 配对完好但 meta 是垃圾字节（decode 必失败的探针）
        let garbageBase = "garbage"
        try Data(repeating: 0, count: 30).write(
            to: directory.appendingPathComponent(garbageBase + ".safetensors"))
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent(garbageBase + ".meta.json"))
        // 真 orphan（有 cache 无 meta）——配对清理与解码无关，必须照常
        let orphanCache = directory.appendingPathComponent("orphan.safetensors")
        try Data(count: 10).write(to: orphanCache)

        let result = try BranchCheckpointRetention.enforce(
            directory: directory,
            retainedKeys: [],
            byteBudget: 64 * 1024 * 1024)

        XCTAssertEqual(result.retainedReceipts, 3)
        XCTAssertGreaterThan(result.retainedBytes, 110)
        XCTAssertEqual(result.removedForBudget, 0)
        XCTAssertEqual(result.removedOrphans, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanCache.path))
        // 探针：解码段未执行，畸形配对存活
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(garbageBase + ".meta.json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(garbageBase + ".safetensors").path))
    }

    /// #1 回归（差分）：同一形态在超预算时必须进入解码段——畸形配对被
    /// 清理，eviction 照旧。锁住「前置门只在未超预算时短路」的边界。
    func testOverBudgetStillDecodesAndRemovesMalformedPairs() throws {
        let directory = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try writeCheckpoint(directory, key: "old", date: now.addingTimeInterval(-60), cacheBytes: 50)
        try writeCheckpoint(directory, key: "active", date: now.addingTimeInterval(-10), cacheBytes: 60)
        let garbageBase = "garbage"
        try Data(repeating: 0, count: 30).write(
            to: directory.appendingPathComponent(garbageBase + ".safetensors"))
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent(garbageBase + ".meta.json"))

        let result = try BranchCheckpointRetention.enforce(
            directory: directory,
            retainedKeys: ["active"],
            byteBudget: 70)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(garbageBase + ".meta.json").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(garbageBase + ".safetensors").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(
                NativeMLX.cacheFileName(for: "old") + ".safetensors").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(
                NativeMLX.cacheFileName(for: "active") + ".safetensors").path))
        XCTAssertEqual(result.retainedReceipts, 1)
    }

    /// #1 回归：预算恰好等于配对总量（边界 =）——eviction 条件是严格
    /// 大于，此时必须走前置门短路且零清理。
    func testExactBudgetBoundaryTakesPreBudgetExit() throws {
        let directory = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try writeCheckpoint(directory, key: "a", date: now, cacheBytes: 100)
        let metaURL = directory.appendingPathComponent(
            NativeMLX.cacheFileName(for: "a") + ".meta.json")
        let cacheURL = directory.appendingPathComponent(
            NativeMLX.cacheFileName(for: "a") + ".safetensors")
        let total = try (FileManager.default.attributesOfItem(
            atPath: metaURL.path)[.size] as! Int)
            + (FileManager.default.attributesOfItem(atPath: cacheURL.path)[.size] as! Int)

        let result = try BranchCheckpointRetention.enforce(
            directory: directory,
            retainedKeys: [],
            byteBudget: total)

        XCTAssertEqual(result.retainedReceipts, 1)
        XCTAssertEqual(result.retainedBytes, Int64(total))
        XCTAssertEqual(result.removedOrphans, 0)
        XCTAssertEqual(result.removedForBudget, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
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
