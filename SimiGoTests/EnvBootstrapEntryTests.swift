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


    func testBinaryDownloaderRejectsOversizedDownloadedFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-download-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        let destination = directory.appendingPathComponent("staged.bin")
        try Data(repeating: 0x41, count: 9).write(to: source)

        let downloader = BinaryDownloader(
            destination: destination, maximumBytes: 8,
            configuration: Self.stallingDownloadConfiguration(), progress: { _, _ in })
        let transfer = Task {
            try await downloader.run(url: URL(string: "https://127.0.0.1/unused")!)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        downloader.finishDownloadedFile(at: source, statusCode: 200)

        do {
            _ = try await transfer.value
            XCTFail("expected the 9-byte file to exceed the 8-byte limit")
        } catch let error as BinaryDownloaderError {
            guard case .maximumSizeExceeded(let limit, let actual) = error else {
                return XCTFail("unexpected downloader error: \(error)")
            }
            XCTAssertEqual(limit, 8)
            XCTAssertEqual(actual, 9)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testBinaryDownloaderCancellationWinsAgainstLateFinishCallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-download-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("late.bin")
        let destination = directory.appendingPathComponent("staged.bin")
        try Data(repeating: 0x42, count: 32).write(to: source)

        let downloader = BinaryDownloader(
            destination: destination, maximumBytes: 1024,
            configuration: Self.stallingDownloadConfiguration(), progress: { _, _ in })
        let transfer = Task {
            try await downloader.run(url: URL(string: "https://127.0.0.1/unused")!)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        transfer.cancel()

        do {
            _ = try await transfer.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        // Simulate a URLSession finish callback that was queued before cancellation completed.
        downloader.finishDownloadedFile(at: source, statusCode: 200)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testBinaryDownloaderRejectsInvalidLimitBeforeStarting() async {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-download-\(UUID().uuidString)")
        do {
            _ = try await BinaryDownloader.download(
                from: URL(string: "https://127.0.0.1/unused")!,
                to: destination, maximumBytes: 0, progress: { _, _ in })
            XCTFail("expected an invalid limit error")
        } catch let error as BinaryDownloaderError {
            XCTAssertEqual(error, .invalidMaximumBytes)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private static func stallingDownloadConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BinaryDownloadStallingURLProtocol.self]
        return configuration
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


private final class BinaryDownloadStallingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "1048576"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Deliberately do not finish: the caller controls completion/cancellation.
    }

    override func stopLoading() {}
}
