import Foundation
import XCTest

@testable import SimiGo

final class BinaryDownloaderTests: XCTestCase {
    func testCancellationCancelsURLSessionDownloadAndPreservesExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-downloader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("engine")
        let previous = Data("previous-engine".utf8)
        try previous.write(to: destination)

        let started = expectation(description: "download request started")
        let stopped = expectation(description: "download request stopped")
        ControlledBinaryDownloadURLProtocol.configure(
            mode: .hold, started: started, stopped: stopped)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledBinaryDownloadURLProtocol.self]

        let sourceURL = URL(string: "https://simigo.invalid/engine")!
        let downloader = BinaryDownloader(
            destination: destination, configuration: configuration) { _, _ in }
        let download = Task { try await downloader.run(url: sourceURL) }

        await fulfillment(of: [started], timeout: 5)
        download.cancel()
        do {
            _ = try await download.value
            XCTFail("cancelled download unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: cancellation is propagated to the async caller.
        }
        await fulfillment(of: [stopped], timeout: 5)

        // A completion callback already queued when cancellation wins must
        // not publish its temporary file over the previously installed binary.
        let lateTemporary = directory.appendingPathComponent("late-download")
        try Data("partial-download".utf8).write(to: lateTemporary)
        let callbackSession = URLSession(configuration: .ephemeral)
        let callbackTask = callbackSession.downloadTask(with: sourceURL)
        downloader.urlSession(
            callbackSession, downloadTask: callbackTask,
            didFinishDownloadingTo: lateTemporary)
        callbackSession.invalidateAndCancel()
        XCTAssertEqual(try Data(contentsOf: destination), previous)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lateTemporary.path))
    }

    func testOversizedDownloadPreservesExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-downloader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("engine")
        let previous = Data("previous-engine".utf8)
        try previous.write(to: destination)
        let payload = Data("oversized".utf8)
        let started = expectation(description: "oversized response started")
        ControlledBinaryDownloadURLProtocol.configure(
            mode: .respond(payload), started: started, stopped: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledBinaryDownloadURLProtocol.self]

        let download = Task {
            try await BinaryDownloader.download(
                from: URL(string: "https://simigo.invalid/engine")!,
                to: destination, configuration: configuration,
                maximumDownloadBytes: Int64(payload.count - 1)
            ) { _, _ in }
        }
        await fulfillment(of: [started], timeout: 5)
        do {
            _ = try await download.value
            XCTFail("oversized payload unexpectedly replaced the installed binary")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "EnvManager")
            XCTAssertEqual(error.code, 413)
            XCTAssertEqual(
                error.localizedDescription,
                "Binary download exceeds the configured \(Int64(payload.count - 1))-byte limit")
        }
        XCTAssertEqual(try Data(contentsOf: destination), previous)
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.map(\.lastPathComponent).sorted(), ["engine"])
    }

    func testSuccessfulDownloadAtomicallyReplacesExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-downloader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("engine")
        try Data("old".utf8).write(to: destination)
        let payload = Data("new-engine".utf8)
        let started = expectation(description: "download request started")
        ControlledBinaryDownloadURLProtocol.configure(
            mode: .respond(payload), started: started, stopped: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledBinaryDownloadURLProtocol.self]

        let download = Task {
            try await BinaryDownloader.download(
                from: URL(string: "https://simigo.invalid/engine")!,
                to: destination, configuration: configuration
            ) { _, _ in }
        }
        await fulfillment(of: [started], timeout: 5)
        let downloadedSize = try await download.value
        XCTAssertEqual(downloadedSize, Int64(payload.count))
        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }
}

private nonisolated final class ControlledBinaryDownloadURLProtocol:
    URLProtocol, @unchecked Sendable
{
    enum Mode: Sendable {
        case hold
        case respond(Data)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var mode: Mode = .hold
    nonisolated(unsafe) private static var started: XCTestExpectation?
    nonisolated(unsafe) private static var stopped: XCTestExpectation?

    static func configure(
        mode: Mode, started: XCTestExpectation, stopped: XCTestExpectation?
    ) {
        lock.lock()
        self.mode = mode
        self.started = started
        self.stopped = stopped
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let mode = Self.mode
        let started = Self.started
        Self.lock.unlock()
        started?.fulfill()

        guard case .respond(let payload) = mode else { return }
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/octet-stream",
                    "Content-Length": String(payload.count),
                ])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.lock.lock()
        let stopped = Self.stopped
        Self.lock.unlock()
        stopped?.fulfill()
    }
}
