import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// E2 — SimiGo itself restarts between the two turns.
///
/// Two test methods run in TWO separate test-host processes against the same
/// isolated roots. Phase A settles a turn on a real engine and leaves a
/// handoff record in `SIMIGO_HOME`; phase B starts from nothing but that record
/// plus the authoritative SQLite store: no in-memory graph, no branch ledger,
/// no engine process, no KV.
///
/// Run order matters and is explicit:
///   1. `-only-testing:.../testPhaseAEngineTurnSettlesAndLeavesHandoff`
///   2. a NEW xcodebuild invocation for
///      `-only-testing:.../testPhaseBNewHostProcessContinuesFromPersistedIS`
///
/// The handoff carries phase A's host PID; phase B asserts it is running in a
/// different process, so a run that accidentally reused the same host cannot
/// pass as evidence.
final class GGUFContinuationE2CrossProcessTests: XCTestCase {

    private var isolationRoot: URL!
    private var modelPath: String!
    private var engineBinary: String!

    private static let parentValue = "31415926"
    private static let continuationValue = "31415927"

    private struct Handoff: Codable {
        let session: String
        let parentStateID: String
        let parentSettlementID: String
        let parentValue: String
        let continuationValue: String
        let modelIdentity: String
        let hostPID: Int
        let enginePort: Int
        let publicPort: Int
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty, home.hasPrefix("/"),
            env["SIMIGO_STATE_GRAPH_STORE"]?.isEmpty == false,
            env["SIMIGO_CACHE_ROOT"]?.isEmpty == false
        else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "so no real user state is touched")
        }
        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        guard let model = env["SIMIGO_GGUF_E2E_MODEL"],
            FileManager.default.fileExists(atPath: model)
        else { throw XCTSkip("SIMIGO_GGUF_E2E_MODEL not injected") }
        guard let binary = env["SIMIGO_GGUF_E2E_BIN"],
            FileManager.default.isExecutableFile(atPath: binary)
        else { throw XCTSkip("SIMIGO_GGUF_E2E_BIN not injected") }
        modelPath = model
        engineBinary = binary
    }

    private var handoffURL: URL {
        isolationRoot.appendingPathComponent("gguf-e2-handoff.json")
    }

    // MARK: - Phase A

    @MainActor
    func testPhaseAEngineTurnSettlesAndLeavesHandoff() async throws {
        try? FileManager.default.removeItem(at: handoffURL)
        let session = "gguf-e2-\(UUID().uuidString)"
        let store = ExecutionStateGraphStore()
        let esis = try XCTUnwrap(store.esis)

        let engine = try await startEngine(tag: "e2a")
        addTeardownBlock { await engine.runtime.stop() }
        let enginePort = try XCTUnwrap(engine.runtime.enginePort)

        let turn = try await responses(
            port: engine.publicPort,
            body: [
                "model": modelName(from: modelPath),
                "session_id": session,
                "stream": false,
                "max_tokens": 24,
                "temperature": 0,
                "input": "Output only this integer and nothing else, no punctuation: "
                    + Self.parentValue,
            ])
        XCTAssertEqual(turn.status, 200, describe(turn))
        XCTAssertEqual(
            try XCTUnwrap(assistantText(turn.body)), Self.parentValue,
            "phase A must settle the exact integer; body=\(turn.body)")

        let anchors = try XCTUnwrap(turn.body["simigo"] as? [String: Any])
        let parentStateID = try XCTUnwrap(anchors["es_state_id"] as? String)
        let parentSettlementID = try XCTUnwrap(anchors["settlement_id"] as? String)
        XCTAssertEqual(
            try esis.settlementValidity(parentSettlementID), "valid")
        XCTAssertEqual(
            try esis.latestSettlementID(forStateID: parentStateID),
            parentSettlementID)

        let identity = try XCTUnwrap(engine.runtime.modelContentIdentity)
        let handoff = Handoff(
            session: session,
            parentStateID: parentStateID,
            parentSettlementID: parentSettlementID,
            parentValue: Self.parentValue,
            continuationValue: Self.continuationValue,
            modelIdentity: identity.modelIdentity,
            hostPID: Int(getpid()),
            enginePort: enginePort,
            publicPort: engine.publicPort)
        try JSONEncoder().encode(handoff).write(to: handoffURL, options: .atomic)

        // The engine and the listener both die with this phase; the records stay.
        await engine.runtime.stop()
        XCTAssertFalse(portAcceptsConnection(enginePort))
        XCTAssertFalse(portAcceptsConnection(engine.publicPort))
        XCTAssertEqual(
            try esis.latestSettlementID(forStateID: parentStateID),
            parentSettlementID,
            "the parent settlement survives the host that produced it")
    }

    // MARK: - Phase B

    @MainActor
    func testPhaseBNewHostProcessContinuesFromPersistedIS() async throws {
        guard FileManager.default.fileExists(atPath: handoffURL.path) else {
            return XCTFail(
                "no handoff at \(handoffURL.path): run phase A in a FIRST xcodebuild "
                + "invocation, then phase B in a NEW invocation")
        }
        let handoff = try JSONDecoder().decode(
            Handoff.self, from: try Data(contentsOf: handoffURL))

        // A different host process is the precondition, not an assumption.
        XCTAssertNotEqual(
            Int(getpid()), handoff.hostPID,
            "phase B must run in a NEW test-host process")
        XCTAssertFalse(
            portAcceptsConnection(handoff.enginePort),
            "phase A's engine process must be gone before phase B starts")
        XCTAssertFalse(
            portAcceptsConnection(handoff.publicPort),
            "phase A's listener must be gone before phase B starts")

        // Nothing in this process ever held the parent in memory: read it back
        // from the authoritative store only.
        let db = try SimiGoESISDatabase(url: SimiGoPaths.databaseURL)
        let parentRow = try XCTUnwrap(
            try db.readGraph().states.first { $0.id == handoff.parentStateID },
            "the parent Execution State must be read back from SQLite")
        XCTAssertEqual(
            parentRow.nextInput, handoff.parentValue,
            "the IS value survived the host restart")
        XCTAssertEqual(
            try db.settlementValidity(handoff.parentSettlementID), "valid")
        XCTAssertEqual(
            try db.latestSettlementID(forStateID: handoff.parentStateID),
            handoff.parentSettlementID)
        let settlementsBefore = try db.readSettlementReceipts().count

        let engine = try await startEngine(tag: "e2b")
        addTeardownBlock { await engine.runtime.stop() }
        XCTAssertEqual(
            engine.runtime.modelContentIdentity?.modelIdentity,
            handoff.modelIdentity,
            "the content identity is resolved from the bytes, so a new process "
            + "resolves the same identity")
        XCTAssertTrue(
            engine.runtime.liveBranches(
                agentId: nil, sessionId: handoff.session).isEmpty,
            "the new host inherits no branch ledger")
        // Baseline engine counters. The engine's own accounting is the witness:
        // every refused request must leave it exactly where startup left it.
        let startupCounters = try await engineCounters(engine.runtime)

        // Pre-generation refusals: neither authority may be reached, and the
        // engine must not process a single prompt.
        for body in [
            continuationBody(handoff: handoff, anchor: "es-no-such-anchor-\(UUID())"),
            continuationBody(handoff: handoff, anchor: "   "),
        ] {
            let refused = try await responses(port: engine.publicPort, body: body)
            XCTAssertEqual(
                refused.status, 422, describe(refused))
            let error = try XCTUnwrap(refused.body["error"] as? [String: Any])
            XCTAssertEqual(error["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
            let countersAfterRefusal = try await engineCounters(engine.runtime)
            XCTAssertEqual(
                countersAfterRefusal, startupCounters,
                "a refused continuation must not reach the engine; "
                + "counters=\(countersAfterRefusal) body=\(refused.body)")
            XCTAssertEqual(
                try db.readSettlementReceipts().count, settlementsBefore,
                "a refused continuation writes no settlement")
        }

        // The real continuation: only the persisted anchor and the admitted
        // value carry phase A's result forward.
        XCTAssertFalse(
            continuationInput(handoff).contains(handoff.parentValue),
            "the client's input must not carry the recovered value")
        let turn = try await responses(
            port: engine.publicPort,
            body: continuationBody(handoff: handoff, anchor: handoff.parentStateID))
        XCTAssertEqual(turn.status, 200, describe(turn))
        let generated = try XCTUnwrap(assistantText(turn.body), describe(turn))
        XCTAssertTrue(
            generated.contains("ANSWER=\(handoff.continuationValue)"),
            "the new host must settle the recovered value plus one; got: \(generated)")

        let usage = try XCTUnwrap(turn.body["usage"] as? [String: Any])
        let details = try XCTUnwrap(usage["input_tokens_details"] as? [String: Any])
        XCTAssertEqual(
            details["cached_tokens"] as? Int, 0,
            "the new engine reports a cold prompt; usage=\(usage)")

        // Positive control: the same counter witness moves once a request is
        // actually admitted, so the refusals above were not witnessed vacuously.
        let countersAfterTurn = try await engineCounters(engine.runtime)
        XCTAssertGreaterThan(
            countersAfterTurn.promptTokens, startupCounters.promptTokens,
            "the counter witness observes admitted prompt work")
        XCTAssertGreaterThan(
            countersAfterTurn.predictedTokens, startupCounters.predictedTokens,
            "the counter witness observes admitted generation")

        let settlement = try XCTUnwrap(
            turn.body["continuation_settlement"] as? [String: Any])
        let childStateID = try XCTUnwrap(settlement["child_es_state_id"] as? String)
        let childSettlementID = try XCTUnwrap(settlement["settlement_id"] as? String)
        let anchors = try XCTUnwrap(turn.body["simigo"] as? [String: Any])
        XCTAssertEqual(anchors["es_state_id"] as? String, childStateID)
        XCTAssertEqual(anchors["settlement_id"] as? String, childSettlementID)

        let childRow = try XCTUnwrap(
            try db.readGraph().states.first { $0.id == childStateID })
        XCTAssertEqual(childRow.parentID, handoff.parentStateID)
        XCTAssertEqual(childRow.nextInput, handoff.continuationValue)
        XCTAssertEqual(childRow.modelIdentity, handoff.modelIdentity)
        XCTAssertTrue(
            try db.upstreamDependencyClosure(ofSettlement: childSettlementID)
                .contains(handoff.parentSettlementID),
            "the cross-process continuation cites the parent settlement")
        XCTAssertEqual(
            try db.latestSettlementID(forStateID: handoff.parentStateID),
            handoff.parentSettlementID,
            "the parent is not re-settled after the host restart")
    }

    // MARK: - Engine

    private struct EngineHandle {
        let runtime: ManagedGGUFRuntime
        let publicPort: Int
    }

    @MainActor
    private func startEngine(tag: String) async throws -> EngineHandle {
        setenv("SIMIGO_LLAMA_PARALLEL", "1", 1)
        let slotStore = isolationRoot.appendingPathComponent(
            "slots-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: slotStore, withIntermediateDirectories: true)

        var config = ModelConfig()
        config.ctxSize = 4096
        config.maxTokens = 64
        config.temperature = 0
        config.jinja = true

        let backend = BackendConfig(
            name: "llama.cpp",
            customExecutable: engineBinary,
            args: { info, cfg, port in
                BackendConfig.llama.args(info, cfg, port)
                    + [
                        "--slot-save-path", slotStore.path,
                        "--ctx-checkpoints", "0",
                        "--metrics",
                    ]
            },
            healthEndpoint: "/health",
            startupTimeout: 600,
            kind: .gguf)

        let runtime = ManagedGGUFRuntime(config: config, backendConfig: backend)
        let port = Int(try GGUFRestFixture.freePort())
        try await runtime.start(ModelInfo(path: modelPath, kind: .gguf), port: port)
        try GGUFRestFixture.waitUntilListening(port: port)
        XCTAssertTrue(runtime.isRunning, "engine \(tag) did not reach the running state")
        try await waitForEngineHealth(runtime)
        return EngineHandle(runtime: runtime, publicPort: port)
    }

    private struct EngineObservationUnavailable: Error {}

    /// The public listener accepts connections before llama-server has loaded
    /// the checkpoint, so readiness must be observed on the engine itself.
    private func waitForEngineHealth(
        _ runtime: ManagedGGUFRuntime, timeout: TimeInterval = 600
    ) async throws {
        let port = try XCTUnwrap(runtime.enginePort)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var request = URLRequest(
                url: URL(string: "http://127.0.0.1:\(port)/health")!)
            request.timeoutInterval = 5
            if let (_, response) = try? await URLSession.shared.data(for: request),
                (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTFail("engine did not report healthy within \(Int(timeout))s")
        throw EngineObservationUnavailable()
    }

    // MARK: - Wire

    private func continuationInput(_ handoff: Handoff) -> String {
        "Continue the settled task."
    }

    private func continuationBody(handoff: Handoff, anchor: String) -> [String: Any] {
        [
            "model": modelName(from: modelPath),
            "session_id": handoff.session,
            "stream": false,
            "max_tokens": 64,
            "temperature": 0,
            "instructions": """
                You are continuing a settled task.
                A previous result is supplied as the LAST user message.
                Reply with exactly two lines and nothing else:
                TASK=gguf-continuation/v1
                ANSWER=<the previous result as an integer plus 1>
                """,
            "input": continuationInput(handoff),
            "previous_es_state_id": anchor,
            "continuation_settle": true,
        ]
    }

    private func responses(
        port: Int, body: [String: Any]
    ) async throws -> (status: Int, body: [String: Any]) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 900
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, json)
    }

    private func assistantText(_ body: [String: Any]) -> String? {
        guard let output = body["output"] as? [[String: Any]] else { return nil }
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "output_text" {
                if let text = part["text"] as? String {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    private func describe(_ turn: (status: Int, body: [String: Any])) -> String {
        "status=\(turn.status) body=\(turn.body)"
    }

    // MARK: - Engine observation

    private struct EngineCounters: Equatable {
        let promptTokens: Int
        let predictedTokens: Int
    }

    private func engineCounters(
        _ runtime: ManagedGGUFRuntime, timeout: TimeInterval = 300
    ) async throws -> EngineCounters {
        let port = try XCTUnwrap(runtime.enginePort)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let counters = try? await readEngineCounters(port: port) {
                return counters
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        } while Date() < deadline
        XCTFail(
            "engine /metrics never exposed its counters within \(Int(timeout))s; "
            + "the refusal witness is unavailable")
        throw EngineObservationUnavailable()
    }

    private func readEngineCounters(port: Int) async throws -> EngineCounters? {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/metrics")!)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        var values: [String: Int] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: " ")
            guard fields.count >= 2 else { continue }
            values[String(fields[0])] = Int(fields[1])
        }
        guard let prompt = values["llamacpp:prompt_tokens_total"],
            let predicted = values["llamacpp:tokens_predicted_total"]
        else { return nil }
        return EngineCounters(promptTokens: prompt, predictedTokens: predicted)
    }

    private func portAcceptsConnection(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
