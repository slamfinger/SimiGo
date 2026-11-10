import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// E1 — the engine process dies, SimiGo and the ES/IS authority survive.
///
/// Turn 1 runs on a real llama.cpp engine and settles into ES/IS; the response
/// publishes the anchor. The whole runtime is then stopped (listener closed,
/// engine process dead, branch ledger cleared). A SECOND engine process is
/// started on the same checkpoint. The continuation names only the parent
/// `previous_es_state_id`: the value the next turn needs is recovered by IS
/// admission, appended by the gate, and the generated result settles into a
/// NEW child Execution State with a real dependency edge to the parent.
///
/// What this proves (and what it does not):
/// * the parent settlement was NOT re-submitted and is still the parent's only
///   settlement;
/// * the new engine is a different process and its first turn reports
///   `cached_tokens == 0` (with checkpoints disabled for this run), so nothing
///   it answers can be credited to KV the old process held;
/// * the settled value travelled from the IS record into the new process.
/// It does NOT claim the model internally did no recomputation.
///
/// Gated like the other real-model suites: `SIMIGO_GGUF_E2E_MODEL`,
/// `SIMIGO_GGUF_E2E_BIN` and the isolated roots injected by
/// `tools/make_isolated_xctestrun.py`.
final class GGUFContinuationE1RealModelE2ETests: XCTestCase {

    private var isolationRoot: URL!
    private var modelPath: String!
    private var engineBinary: String!

    /// The parent answer is an integer so the GGUF continuation contract can
    /// derive `expected_next_value = parent + 1`. It is large enough that the
    /// continuation answer cannot be guessed from the client's own text.
    private static let parentValue = "8675309"
    private static let continuationValue = "8675310"

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

    // MARK: - E1

    @MainActor
    func testContinuationSurvivesEngineProcessDeath() async throws {
        let session = "gguf-e1-\(UUID().uuidString)"
        let store = ExecutionStateGraphStore()
        let esis = try XCTUnwrap(store.esis)

        // ---- Phase A: the first engine process answers and settles ----

        let firstStart = try await startEngine(tag: "a")
        addTeardownBlock { await firstStart.runtime.stop() }
        XCTAssertTrue(
            portAcceptsConnection(firstStart.publicPort),
            "the product listener must be reachable before the turn")
        XCTAssertTrue(
            firstStart.runtime.liveBranches(agentId: nil, sessionId: session).isEmpty,
            "no branch is live before the first turn")

        let turn1 = try await responses(
            port: firstStart.publicPort,
            body: [
                "model": modelName(from: modelPath),
                "session_id": session,
                "stream": false,
                "max_tokens": 24,
                "temperature": 0,
                "input": "Output only this integer and nothing else, no punctuation: "
                    + Self.parentValue,
            ])
        XCTAssertEqual(turn1.status, 200, describe(turn1))
        XCTAssertEqual(
            try XCTUnwrap(assistantText(turn1.body)), Self.parentValue,
            "the parent turn must settle the exact integer; body=\(turn1.body)")
        XCTAssertEqual(turn1.body["status"] as? String, "completed")

        let parentIDs = try XCTUnwrap(
            turn1.body["simigo"] as? [String: Any],
            "a settled ordinary turn publishes its ES/IS anchor")
        let parentStateID = try XCTUnwrap(parentIDs["es_state_id"] as? String)
        let parentSettlementID = try XCTUnwrap(parentIDs["settlement_id"] as? String)
        XCTAssertEqual(
            try esis.settlementValidity(parentSettlementID), "valid")
        XCTAssertEqual(
            try esis.latestSettlementID(forStateID: parentStateID),
            parentSettlementID,
            "the anchor names the settlement the state actually carries")

        let parentRow = try XCTUnwrap(
            try esis.readGraph().states.first { $0.id == parentStateID })
        XCTAssertEqual(
            parentRow.nextInput, Self.parentValue,
            "the parent's IS next-input is the settled answer the continuation recovers")
        let parentSettlementCount = try settlementsWritten(
            forState: parentStateID, in: esis)
        XCTAssertEqual(parentSettlementCount, 1)

        // The first engine did hold a branch record; losing it with the process
        // is the paired precondition for the recovery below.
        XCTAssertTrue(
            firstStart.runtime.liveBranches(agentId: nil, sessionId: session)
                .contains("main"),
            "the first engine's turn must have been observed by its ledger")

        // ---- The engine (and its listener) dies; SimiGo keeps the records ----

        let oldEnginePort = try XCTUnwrap(firstStart.runtime.enginePort)
        let oldPublicPort = firstStart.publicPort
        // A stopped runtime forgets its identity, so the comparison value must
        // be captured while the first process is still alive.
        let oldIdentity = try XCTUnwrap(firstStart.runtime.modelContentIdentity)
        await firstStart.runtime.stop()
        XCTAssertFalse(firstStart.runtime.isRunning)
        XCTAssertNil(firstStart.runtime.enginePort, "a stopped runtime keeps no engine endpoint")
        XCTAssertTrue(
            firstStart.runtime.liveBranches(agentId: nil, sessionId: session).isEmpty,
            "the dead engine's rendered transcripts are cleared, so no fork can hand them back")
        XCTAssertFalse(
            portAcceptsConnection(oldEnginePort),
            "the old engine process must be gone, not merely detached")
        XCTAssertFalse(
            portAcceptsConnection(oldPublicPort),
            "the old product listener must be closed")

        let parentAfterDeath = try XCTUnwrap(
            try esis.readGraph().states.first { $0.id == parentStateID })
        XCTAssertEqual(
            parentAfterDeath.nextInput, Self.parentValue,
            "the IS value outlives the engine that produced it")
        XCTAssertEqual(
            try esis.latestSettlementID(forStateID: parentStateID),
            parentSettlementID,
            "stopping the engine neither re-settles nor drops the parent record")

        // ---- Phase B: a NEW engine process continues from the anchor only ----

        let secondStart = try await startEngine(tag: "b")
        addTeardownBlock { await secondStart.runtime.stop() }
        XCTAssertNotEqual(
            secondStart.publicPort, oldPublicPort,
            "the second engine is served by a fresh listener")
        XCTAssertFalse(
            portAcceptsConnection(oldEnginePort),
            "the new engine must not resurrect the old process")
        XCTAssertEqual(
            secondStart.runtime.modelContentIdentity?.modelIdentity,
            oldIdentity.modelIdentity,
            "the content identity is the checkpoint's, so it survives the process")
        XCTAssertTrue(
            secondStart.runtime.liveBranches(agentId: nil, sessionId: session).isEmpty,
            "the new engine inherits no rendered transcript from the old one")

        let instructions = """
            You are continuing a settled task.
            A previous result is supplied as the LAST user message.
            Reply with exactly two lines and nothing else:
            TASK=gguf-continuation/v1
            ANSWER=<the previous result as an integer plus 1>
            """
        let continuationInput = "Continue the settled task."
        XCTAssertFalse(
            continuationInput.contains(Self.parentValue),
            "the client's own input must not carry the recovered value")
        XCTAssertFalse(
            instructions.contains(Self.parentValue),
            "the instructions must not carry the recovered value")

        let turn2 = try await responses(
            port: secondStart.publicPort,
            body: [
                "model": modelName(from: modelPath),
                "session_id": session,
                "stream": false,
                "max_tokens": 64,
                "temperature": 0,
                "instructions": instructions,
                "input": continuationInput,
                "previous_es_state_id": parentStateID,
                "continuation_settle": true,
            ])
        XCTAssertEqual(turn2.status, 200, describe(turn2))
        let generated = try XCTUnwrap(assistantText(turn2.body), describe(turn2))
        XCTAssertTrue(
            generated.contains("ANSWER=\(Self.continuationValue)"),
            "the new engine must settle the recovered value plus one; got: \(generated)")

        let usage = try XCTUnwrap(turn2.body["usage"] as? [String: Any])
        let inputDetails = try XCTUnwrap(usage["input_tokens_details"] as? [String: Any])
        XCTAssertEqual(
            inputDetails["cached_tokens"] as? Int, 0,
            "the new process must report a cold prompt; usage=\(usage)")

        let settlement = try XCTUnwrap(
            turn2.body["continuation_settlement"] as? [String: Any],
            describe(turn2))
        let childStateID = try XCTUnwrap(settlement["child_es_state_id"] as? String)
        let childSettlementID = try XCTUnwrap(settlement["settlement_id"] as? String)
        let anchors = try XCTUnwrap(
            turn2.body["simigo"] as? [String: Any],
            "the committed continuation publishes both anchors")
        XCTAssertEqual(anchors["es_state_id"] as? String, childStateID)
        XCTAssertEqual(anchors["settlement_id"] as? String, childSettlementID)

        // The child is a NEW state, produced by THIS engine, cited against the
        // parent settlement the admission verified.
        let childRow = try XCTUnwrap(
            try esis.readGraph().states.first { $0.id == childStateID })
        XCTAssertEqual(childRow.parentID, parentStateID)
        XCTAssertEqual(childRow.position, parentRow.position + 1)
        XCTAssertEqual(
            childRow.nextInput, Self.continuationValue,
            "the child round-trips the value it settled")
        XCTAssertEqual(
            childRow.modelIdentity,
            secondStart.runtime.modelContentIdentity?.modelIdentity,
            "the child names the producer that generated it")
        XCTAssertTrue(
            try esis.upstreamDependencyClosure(ofSettlement: childSettlementID)
                .contains(parentSettlementID),
            "the continuation settlement cites the parent settlement as a real dependency")
        XCTAssertEqual(
            try esis.latestSettlementID(forStateID: parentStateID),
            parentSettlementID,
            "the parent is not re-settled by the continuation")
        XCTAssertEqual(
            try settlementsWritten(forState: parentStateID, in: esis), 1,
            "the parent keeps exactly one settlement")

        // Chainability through the IS record, not through any echoed client text.
        let recovered = try store.admitContinuation(
            stateID: childStateID,
            consumer: try XCTUnwrap(secondStart.runtime.modelContentIdentity).producer)
        XCTAssertEqual(recovered.recoveredValue, Self.continuationValue)
        XCTAssertEqual(recovered.settlementID, childSettlementID)

        // The user-facing history is the settled assistant text of both turns.
        let messages = try esis.listChatMessages(sessionID: session)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant", "user", "assistant"])
        XCTAssertEqual(messages[1].content, Self.parentValue)
        XCTAssertTrue(messages[3].content.contains("ANSWER=\(Self.continuationValue)"))
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
            "slots-e1-\(tag)-\(UUID().uuidString)", isDirectory: true)
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
                // Test-only strictness, NOT a product default: with checkpoints
                // disabled the engine keeps no restorable KV snapshots, so the
                // new process cannot replay the old turn's prompt by accident.
                BackendConfig.llama.args(info, cfg, port)
                    + ["--slot-save-path", slotStore.path, "--ctx-checkpoints", "0"]
            },
            healthEndpoint: "/health",
            startupTimeout: 600,
            kind: .gguf)

        let runtime = ManagedGGUFRuntime(config: config, backendConfig: backend)
        let port = Int(try GGUFRestFixture.freePort())
        try await runtime.start(ModelInfo(path: modelPath, kind: .gguf), port: port)
        try GGUFRestFixture.waitUntilListening(port: port)
        XCTAssertTrue(runtime.isRunning, "engine \(tag) did not reach the running state")
        return EngineHandle(runtime: runtime, publicPort: port)
    }

    // MARK: - Wire

    private func responses(
        port: Int, body: [String: Any]
    ) async throws -> (status: Int, body: [String: Any]) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Cold prefill on a real checkpoint is minutes, not seconds.
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

    // MARK: - Process / store observation

    /// True when a TCP connect to loopback `port` succeeds. Used to prove the
    /// old engine process and its listener are actually gone.
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

    @MainActor
    private func settlementsWritten(
        forState stateID: String, in db: SimiGoESISDatabase
    ) throws -> Int {
        try db.readSettlementReceipts().filter { $0.stateID == stateID }.count
    }
}
