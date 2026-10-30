import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// `/v1/completions` is the legacy text-completion surface. Its prompt is
/// continuation text, not an Information-Space demand, so SimiGo serves it as a
/// DECLARED compatibility passthrough: no ES preparation, no reuse check, no
/// settlement.
///
/// That boundary has to be checkable from outside, so it is asserted at the
/// real signed HTTP entry rather than living only in a comment: every
/// completion response carries `simigo.managed == false`, and the authoritative
/// store gains no settlement for the request.
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class CompletionsBoundaryHTTPTests: XCTestCase {

    private let port = 59_373

    private var isolationRoot: URL!
    private var host: LOCALBAuthorizedE2E.Host!
    private var stub: Stub!

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        nonisolated(unsafe) var text = ""
        func bump() { lock.withLock { _generate += 1 } }
        var generate: Int { lock.withLock { _generate } }
    }

    private struct Outcome {
        let status: Int
        let body: [String: Any]
        let raw: Data
        let generate: Int

        var firstText: String? {
            (body["choices"] as? [[String: Any]])?.first?["text"] as? String
        }
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "so no real model or user state is touched")
        }
        isolationRoot = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        host = try LOCALBAuthorizedE2E.makeHost()
        let stub = Stub()
        stub.text = "COMPLETION-4C1"
        self.stub = stub
    }

    override func tearDown() {
        stub = nil
        host = nil
        super.tearDown()
    }

    // MARK: - Server + real authorized requests

    @MainActor
    private func withServer(_ run: (Int) async throws -> Void) async throws {
        let stub = stub!
        let server = HTTPServer(
            port: port,
            modelId: "completions-boundary-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _ in
                stub.bump()
                onChunk(stub.text)
                return GenerationResult(text: stub.text, usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "completions-boundary-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer { server.stop() }
        try await run(stub.generate)
    }

    @MainActor
    private func dispatch(_ body: [String: Any]) async throws -> Outcome {
        let stub = stub!
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        for _ in 0..<3 {
            do {
                let result = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST",
                    path: "/v1/completions",
                    contentType: "application/json", body: payload)
                responseData = result.0
                httpResponse = result.1
                break
            } catch let error as URLError
            where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let sent = try XCTUnwrap(
            httpResponse,
            "authorized request never reached the server: \(String(describing: lastError))")
        let data = responseData ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return Outcome(status: sent.statusCode, body: json, raw: data, generate: stub.generate)
    }

    // MARK: - 1) Non-streaming: declared unmanaged, no settlement written

    @MainActor
    func testNonStreamingCompletionDeclaresUnmanagedAndWritesNoSettlement() async throws {
        try await withServer { _ in
            let store = ExecutionStateGraphStore()
            let db = try XCTUnwrap(store.esis)
            let before = try db.readSettlementReceipts().count

            let o = try await dispatch([
                "model": "completions-boundary-test",
                "prompt": "func greet(",
                "session_id": "completions-boundary-\(UUID().uuidString)",
            ])

            XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
            XCTAssertEqual(o.generate, 1, "the passthrough still runs the model")
            XCTAssertEqual(o.firstText, "COMPLETION-4C1")

            let simigo = try XCTUnwrap(o.body["simigo"] as? [String: Any])
            XCTAssertEqual(simigo["managed"] as? Bool, false)
            XCTAssertEqual(simigo["reason"] as? String, "legacy_text_completions")

            XCTAssertEqual(
                try db.readSettlementReceipts().count, before,
                "a passthrough must not claim settled information")
        }
    }

    // MARK: - 2) Streaming: the boundary is declared on the terminal chunk

    @MainActor
    func testStreamingCompletionDeclaresUnmanagedOnTerminalChunkOnly() async throws {
        try await withServer { _ in
            let store = ExecutionStateGraphStore()
            let db = try XCTUnwrap(store.esis)
            let before = try db.readSettlementReceipts().count

            let o = try await dispatch([
                "model": "completions-boundary-test",
                "prompt": "def add(",
                "stream": true,
                "session_id": "completions-stream-\(UUID().uuidString)",
            ])

            XCTAssertEqual(o.status, 200, String(decoding: o.raw, as: UTF8.self))
            XCTAssertEqual(o.generate, 1)
            let raw = String(decoding: o.raw, as: UTF8.self)
            XCTAssertTrue(raw.contains("COMPLETION-4C1"))
            XCTAssertTrue(raw.contains("data: [DONE]"))
            XCTAssertEqual(
                raw.components(separatedBy: "\"managed\":false").count - 1, 1,
                "the boundary is declared exactly once, on the terminal chunk")
            XCTAssertTrue(raw.contains("\"reason\":\"legacy_text_completions\""))

            XCTAssertEqual(
                try db.readSettlementReceipts().count, before,
                "streaming passthrough writes no settlement either")
        }
    }
}
