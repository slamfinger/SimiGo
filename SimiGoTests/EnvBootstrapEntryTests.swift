import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

/// env-bootstrap 入口与数据库接口的单测：
/// - evaluate 的 fail-closed 语义（env 门控、workroot 绝对路径要求）；
/// - 空白数据库创建 + 工作目录注册的 round-trip（新库 → upsertRoot → 重开读回）；
/// - stableRootID 跨运行稳定。
final class EnvBootstrapEntryTests: XCTestCase {

    // MARK: - evaluate

    func testEvaluateGating() {
        XCTAssertFalse(SimiGoEnvBootstrapEntry.evaluate(env: [:]).requested)
        XCTAssertFalse(
            SimiGoEnvBootstrapEntry
                .evaluate(env: ["SIMIGO_ENV_BOOTSTRAP": ""]).requested)
        let ok = SimiGoEnvBootstrapEntry.evaluate(env: ["SIMIGO_ENV_BOOTSTRAP": "1"])
        XCTAssertTrue(ok.requested)
        XCTAssertTrue(ok.valid)
        XCTAssertNil(ok.error)

        let relative = SimiGoEnvBootstrapEntry.evaluate(
            env: ["SIMIGO_ENV_BOOTSTRAP": "1", "SIMIGO_WORKROOT": "relative/path"])
        XCTAssertTrue(relative.requested)
        XCTAssertFalse(relative.valid)
        XCTAssertNotNil(relative.error)

        let absolute = SimiGoEnvBootstrapEntry.evaluate(
            env: ["SIMIGO_ENV_BOOTSTRAP": "1", "SIMIGO_WORKROOT": "/tmp/somewhere"])
        XCTAssertTrue(absolute.valid)
    }

    // MARK: - Database interface round-trip

    func testFreshDatabaseCreationAndWorkRootRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("envboot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("simigo.sqlite3")

        // Blank creation.
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))
        let db = try SimiGoESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
        let schema = try db.schemaVersion()
        XCTAssertGreaterThanOrEqual(schema, 3)

        // Work-root registration, then read back from a fresh handle.
        let workPath = "/tmp/simigo-work-\(UUID().uuidString)"
        let rootID = "work-" + EnvManager.stableRootID(forPath: workPath)
        try db.upsertRoot(
            rootID: rootID, category: "work",
            displayName: workPath, locatorType: "path", status: "registered")
        let reopened = try SimiGoESISDatabase(url: dbURL, createIfNeeded: false)
        let roots = try reopened.listRoots()
        XCTAssertTrue(roots.contains { $0.rootID == rootID && $0.category == "work" },
                      "registered work root must survive a reopen: \(roots)")

        // Existing databases are never blanked by createIfNeeded.
        _ = try SimiGoESISDatabase(url: dbURL, createIfNeeded: true)
        let after = try SimiGoESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertTrue(try after.listRoots().contains { $0.rootID == rootID })
    }

    func testStableRootIDIsDeterministic() {
        XCTAssertEqual(
            EnvManager.stableRootID(forPath: "/a/b/c"),
            EnvManager.stableRootID(forPath: "/a/b/c"))
        XCTAssertNotEqual(
            EnvManager.stableRootID(forPath: "/a/b/c"),
            EnvManager.stableRootID(forPath: "/a/b/d"))
    }
}
