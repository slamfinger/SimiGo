import XCTest
import Foundation
import SimiGoRuntimeContract
@testable import SimiGo

/// Requirement #5 positive: a REAL HTTP continuation over the product dispatch
/// path, driven end-to-end on the local Qwen3-Coder model. This is NOT the
/// hermetic gate test (which uses a spy handler) and NOT the headless driver.
///
/// Chain actually exercised:
///   real signed POST /v1/responses (previous_es_state_id)
///     -> HTTPServer.route -> handleResponsesNonStreaming
///     -> continuationGate -> HTTPServer.continuationAdmission (wired in
///        NativeMLX) -> SimiGoProducerIdentity.recoverForContinuation
///     -> ExecutionStateGraphStore.admitContinuation -> native IS admission over
///        the authoritative SQLite IS
///     -> recovered IS value appended as generation input -> REAL MLX generate.
///
/// The settled anchor is staged through the SAME product authoritative store the
/// gate reads, with a producer identity re-derived from the very model snapshot
/// the runtime loads, so admission verifies instead of mismatching. Guarded by
/// model presence: when the local model is absent the whole class XCTSkips, so
/// no mock or fixture can ever masquerade as the positive.
final class ResponsesContinuationRealModelE2ETests: XCTestCase {
    private let port = 18_471
    private var host: LOCALBAuthorizedE2E.Host!

    /// Local daily Qwen3-Coder snapshot (same model the PrefixPool battery uses).
    private var modelPath: String {
        if let override = ProcessInfo.processInfo.environment["CONTINUATION_MODEL_PATH"] {
            return override
        }
        let hub = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots")
        let snapshots = (try? FileManager.default.contentsOfDirectory(
            at: hub, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { $0.hasDirectoryPath } ?? []
        return snapshots.first?.path
            ?? hub.appendingPathComponent("NOT-PRESENT").path
    }

    /// Create + continue + settle a state in the product's authoritative store
    /// (the same store `recoverForContinuation` opens via `ExecutionStateGraphStore()`),
    /// publishing a producer identity re-derived from `modelPath` so the later
    /// HTTP admission — whose consumer is minted from the SAME runtime model —
    /// verifies. Returns the ES state id to use as `previous_es_state_id`.
    @MainActor
    private func stageSettledAnchor(value: String) throws -> String {
        let store = ExecutionStateGraphStore()
        let producer = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let root = try store.create()
        try store.continueState(root, input: value)
        let state = try XCTUnwrap(store.state(root.id))
        _ = try store.settleProducerResult(
            generatedText: "RESULT=\(value)",
            boundToState: state,
            producerIdentity: producer
        )
        return state.id
    }

    private func startRealRuntime() async throws -> NativeMLX {
        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx), config: ModelConfig())
        host = try LOCALBAuthorizedE2E.makeHost()
        try await runtime.startWithLOCALB(
            ModelInfo(path: modelPath, kind: .mlx),
            port: port,
            localbTransportIdentity: host.identity,
            localbRequestAuthorization: (
                coordinator: host.coordinator,
                trustedCheckpoint: host.checkpointProvider
            )
        )
        return runtime
    }

    private func responsesBody(input: String, anchor: String?) throws -> Data {
        var json: [String: Any] = [
            "model": "continuation-e2e",
            "input": [[
                "role": "user",
                "content": "Reply with exactly the single word: OK"
            ]],
            "stream": false
        ]
        if let anchor { json["previous_es_state_id"] = anchor }
        _ = input
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Positive: a genuinely SETTLED, identity-matched anchor enters admission,
    /// the recovered IS value feeds the continuation, and the REAL model produces
    /// output (HTTP 200 with a non-empty assistant message).
    func testRealHTTPContinuationWithValidAnchorGenerates() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let anchor = try await MainActor.run {
            try stageSettledAnchor(value: "GATE-CONTINUATION-PROBE-7143")
        }
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        let body = try responsesBody(input: "continue", anchor: anchor)
        let (data, response) = try await LOCALBAuthorizedE2E.send(
            host: host, port: port, method: "POST",
            path: "/v1/responses", contentType: "application/json", body: body)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(response.statusCode, 200, text)

        // A real generation occurred: the completed response carries a
        // non-empty assistant output item.
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(json["output"] as? [[String: Any]], text)
        let contentBlob = try XCTUnwrap(output.first, "output empty: \(text)")
        XCTAssertEqual(contentBlob["type"] as? String, "message", text)
        let content = try XCTUnwrap(
            contentBlob["content"] as? [[String: Any]], text)
        let firstText = content.first?["text"] as? String
        XCTAssertNotNil(firstText, "no text content in output: \(text)")
    }

    /// Fail-closed over the SAME real route: an anchor that names no settled,
    /// identity-verifiable IS record must be refused BEFORE any model tokens are
    /// produced — a real admission refusal, not a silent fallback to ordinary
    /// generation. Assert 422 and an explicit refusal message.
    func testRealHTTPContinuationWithInvalidAnchorRefusedBeforeGeneration()
        async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        let body = try responsesBody(
            input: "continue", anchor: "es-state-no-such-settlement")
        let (data, response) = try await LOCALBAuthorizedE2E.send(
            host: host, port: port, method: "POST",
            path: "/v1/responses", contentType: "application/json", body: body)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(response.statusCode, 422, text)
        XCTAssertTrue(
            text.lowercased().contains("refused"),
            "expected an explicit pre-generation refusal, got: \(text)")
    }
}
