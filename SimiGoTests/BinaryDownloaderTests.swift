import Foundation
import XCTest

@testable import SimiGo

final class BinaryDownloaderTests: XCTestCase {
    func testCancellationCancelsURLSessionDownloadAndPreservesExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-downloader-\\(UUID().uuidString)", isDirectory: true)
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

        let download = Task {
            try await BinaryDownloader.download(
                from: URL(string: "https://simigo.invalid/engine")!,
                to: destination, configuration: configuration
            ) { _, _ in }
        }

        await fulfillment(of: [started], timeout: 5)
        download.cancel()
        do {
            _ = try await download.value
            XCTFail("cancelled download unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: cancellation is propagated to the async caller.
        }
        await fulfillment(of: [stopped], timeout: 5)
        XCTAssertEqual(try Data(contentsOf: destination), previous)
    }

    func testSuccessfulDownloadAtomicallyReplacesExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-downloader-\\(UUID().uuidString)", isDirectory: true)
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
                headerFields: ["Content-Type": "application/octet-stream"])
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
