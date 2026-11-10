import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// D6 — upstream KV is actively invalidated, then the next turn is recovered
/// from the settled IS record rather than the old engine cache.
///
/// Four independent invalidations, each paired with a positive control (the
/// parent prompt really occupied a slot before the invalidation) and a
/// negative control (a phantom anchor is still refused and writes nothing):
/// A. `/slots/{id}?action=erase`;
/// B. engine sleep, then wake on the next request;
/// C. no RAM prompt cache + the parent slot overwritten and erased;
/// D. the same ManagedGGUFRuntime stopped and started again.
///
/// The cold-continuation assertion (`cached_tokens == 0`) is only made where
/// the invalidation removes both the slot KV and the host prompt cache. Sleep
/// and the RAM-cache case run with `--cache-ram 0`; the default 8192 MiB host
/// cache is deliberately not used because upstream exposes no API to clear it.
final class GGUFContinuationD6InvalidationTests: XCTestCase {

    private var isolationRoot: URL!
    private var modelPath: String!
    private var engineBinary: String!

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

    // MARK: - A: slot erase

    @MainActor
    func testD6ASlotEraseRecoversThroughIS() async throws {
        let handle = try await startRuntime(tag: "erase", extraArgs: [])
        addTeardownBlock { await handle.runtime.stop() }
        let session = "d6a-\(UUID().uuidString)"
        let parent = try await settleParent(
            handle, session: session, value: "2718281")

        let before = try await slotPromptTokens(handle.runtime)
        XCTAssertTrue(
            before.contains { $0 > 0 },
            "the parent prompt must occupy a slot before the erase; slots=\(before)")

        let erased = try await eraseEngineSlots(handle.runtime)
        XCTAssertGreaterThan(erased, 0, "the erase must drop the parent prompt")
        let after = try await slotPromptTokens(handle.runtime)
        XCTAssertTrue(
            after.allSatisfy { $0 == 0 },
            "the slot must hold no prompt after erase; slots=\(after)")

        try await assertPhantomRefused(
            handle, parent: parent, session: session)
        try await assertContinuation(
            handle, parent: parent, session: session, value: "2718282")
    }

    // MARK: - B: sleep / wake

    @MainActor
    func testD6BSleepAndWakeRecoversThroughIS() async throws {
        let handle = try await startRuntime(
            tag: "sleep",
            extraArgs: ["--sleep-idle-seconds", "1", "--cache-ram", "0"])
        addTeardownBlock { await handle.runtime.stop() }
        let session = "d6b-\(UUID().uuidString)"
        let parent = try await settleParent(
            handle, session: session, value: "3141592")

        let before = try await slotPromptTokens(handle.runtime)
        XCTAssertTrue(
            before.contains { $0 > 0 },
            "the parent prompt must occupy a slot before sleep; slots=\(before)")

        try await waitForSleeping(handle.runtime)
        let sleeping = try await engineProps(handle.runtime)
        XCTAssertEqual(
            sleeping["is_sleeping"] as? Bool, true,
            "the engine must have unloaded the model and its KV")

        // A refused continuation never reaches the engine, so it must not wake
        // the sleeping model. This separates authority refusal from real work.
        try await assertPhantomRefused(
            handle, parent: parent, session: session)
        let stillSleeping = try await engineProps(handle.runtime)
        XCTAssertEqual(
            stillSleeping["is_sleeping"] as? Bool, true,
            "a refused turn must not wake the engine")

        try await assertContinuation(
            handle, parent: parent, session: session, value: "3141593")
        let awake = try await engineProps(handle.runtime)
        XCTAssertEqual(
            awake["is_sleeping"] as? Bool, false,
            "the admitted continuation must have woken the engine")
    }

    // MARK: - C: RAM prompt cache absent

    @MainActor
    func testD6CRAMCacheAbsentRecoversThroughIS() async throws {
        let handle = try await startRuntime(
            tag: "ram", extraArgs: ["--cache-ram", "0"])
        addTeardownBlock { await handle.runtime.stop() }
        let session = "d6c-\(UUID().uuidString)"
        let parent = try await settleParent(
            handle, session: session, value: "1618033")

        let before = try await slotPromptTokens(handle.runtime)
        XCTAssertTrue(
            before.contains { $0 > 0 },
            "the parent prompt must occupy a slot; slots=\(before)")

        // Replace the slot content with an unrelated direct engine turn. With
        // --cache-ram 0 there is no host copy to fall back to.
        let direct = try await engineChat(
            handle.runtime,
            messages: [["role": "user", "content": "Reply with the single word OK."]],
            maxTokens: 1)
        XCTAssertEqual(direct.status, 200, "direct engine turn failed: \(direct.body)")
        let usage = try XCTUnwrap(direct.body["usage"] as? [String: Any])
        XCTAssertGreaterThan(
            (usage["prompt_tokens"] as? Int) ?? 0, 0,
            "the divergent prompt must actually reach the engine")

        let erased = try await eraseEngineSlots(handle.runtime)
        XCTAssertGreaterThan(erased, 0, "the divergent prompt must be erasable")
        let after = try await slotPromptTokens(handle.runtime)
        XCTAssertTrue(
            after.allSatisfy { $0 == 0 },
            "neither the parent nor the divergent prompt may remain; slots=\(after)")

        try await assertPhantomRefused(
            handle, parent: parent, session: session)
        try await assertContinuation(
            handle, parent: parent, session: session, value: "1618034")
    }

    // MARK: - D: same runtime restart

    @MainActor
    func testD6DRuntimeRestartRecoversThroughIS() async throws {
        let first = try await startRuntime(tag: "restart", extraArgs: [])
        addTeardownBlock { await first.runtime.stop() }
        let session = "d6d-\(UUID().uuidString)"
        let parent = try await settleParent(
            first, session: session, value: "1414213")

        let oldEnginePort = try XCTUnwrap(first.runtime.enginePort)
        let oldPublicPort = first.publicPort
        let oldIdentity = try XCTUnwrap(first.runtime.modelContentIdentity)
        await first.runtime.stop()
        XCTAssertFalse(first.runtime.isRunning)
        XCTAssertNil(first.runtime.enginePort)
        XCTAssertFalse(portAcceptsConnection(oldEnginePort))
        XCTAssertFalse(portAcceptsConnection(oldPublicPort))

        let newPort = Int(try GGUFRestFixture.freePort())
        try await first.runtime.start(
            ModelInfo(path: modelPath, kind: .gguf), port: newPort)
        try GGUFRestFixture.waitUntilListening(port: newPort)
        XCTAssertTrue(first.runtime.isRunning)
        XCTAssertNotEqual(first.runtime.enginePort, oldEnginePort)
        XCTAssertEqual(
            first.runtime.modelContentIdentity?.modelIdentity,
            oldIdentity.modelIdentity,
            "the restart resolves the same checkpoint content identity")
        XCTAssertTrue(
            first.runtime.liveBranches(agentId: nil, sessionId: session).isEmpty,
            "the new engine inherits no rendered transcript")

        let restarted = EngineHandle(runtime: first.runtime, publicPort: newPort)
        try await assertPhantomRefused(
            restarted, parent: parent, session: session)
        try await assertContinuation(
            restarted, parent: parent, session: session, value: "1414214")
    }

    // MARK: - Scenario helpers

    private struct EngineHandle {
        let runtime: ManagedGGUFRuntime
        let publicPort: Int
    }

    private struct Parent {
        let stateID: String
        let settlementID: String
        let settlementCount: Int
        let esis: SimiGoESISDatabase
    }

    @MainActor
    private func startRuntime(
        tag: String, extraArgs: [String]
    ) async throws -> EngineHandle {
        setenv("SIMIGO_LLAMA_PARALLEL", "1", 1)
        let slotStore = isolationRoot.appendingPathComponent(
            "slots-d6-\(tag)-\(UUID().uuidString)", isDirectory: true)
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
                    ]
                    + extraArgs
            },
            healthEndpoint: "/health",
            startupTimeout: 600,
            kind: .gguf)

        let runtime = ManagedGGUFRuntime(config: config, backendConfig: backend)
        let port = Int(try GGUFRestFixture.freePort())
        try await runtime.start(ModelInfo(path: modelPath, kind: .gguf), port: port)
        try GGUFRestFixture.waitUntilListening(port: port)
        XCTAssertTrue(runtime.isRunning, "engine \(tag) did not reach running")
        return EngineHandle(runtime: runtime, publicPort: port)
    }

    @MainActor
    private func settleParent(
        _ handle: EngineHandle, session: String, value: String
    ) async throws -> Parent {
        let turn = try await responses(
            port: handle.publicPort,
            body: [
                "model": modelName(from: modelPath),
                "session_id": session,
                "stream": false,
                "max_tokens": 24,
                "temperature": 0,
                "input": "Output only this integer and nothing else, no punctuation: "
                    + value,
            ])
        XCTAssertEqual(turn.status, 200, describe(turn))
        XCTAssertEqual(
            try XCTUnwrap(assistantText(turn.body)), value,
            "the parent turn must settle the exact integer; body=\(turn.body)")

        let anchors = try XCTUnwrap(turn.body["simigo"] as? [String: Any])
        let stateID = try XCTUnwrap(anchors["es_state_id"] as? String)
        let settlementID = try XCTUnwrap(anchors["settlement_id"] as? String)

        let store = ExecutionStateGraphStore()
        let esis = try XCTUnwrap(store.esis)
        XCTAssertEqual(try esis.settlementValidity(settlementID), "valid")
        XCTAssertEqual(
            try esis.latestSettlementID(forStateID: stateID), settlementID)
        let count = try settlementsWritten(forState: stateID, in: esis)
        XCTAssertEqual(count, 1)
        let row = try XCTUnwrap(
            try esis.readGraph().states.first { $0.id == stateID })
        XCTAssertEqual(row.nextInput, value)

        return Parent(
            stateID: stateID,
            settlementID: settlementID,
            settlementCount: count,
            esis: esis)
    }

    @MainActor
    private func assertPhantomRefused(
        _ handle: EngineHandle, parent: Parent, session: String
    ) async throws {
        let before = try parent.esis.readSettlementReceipts().count
        let turn = try await responses(
            port: handle.publicPort,
            body: continuationBody(
                session: session,
                anchor: "es-does-not-exist-\(UUID().uuidString)",
                previousStateID: parent.stateID))
        XCTAssertEqual(turn.status, 422, describe(turn))
        let error = try XCTUnwrap(turn.body["error"] as? [String: Any])
        XCTAssertEqual(error["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")
        XCTAssertEqual(
            try parent.esis.readSettlementReceipts().count, before,
            "a refused continuation must write no settlement")
        XCTAssertEqual(
            try parent.esis.latestSettlementID(forStateID: parent.stateID),
            parent.settlementID,
            "a refused continuation must not touch the parent")
    }

    @MainActor
    private func assertContinuation(
        _ handle: EngineHandle, parent: Parent, session: String, value: String
    ) async throws {
        let input = "Continue the settled task."
        XCTAssertFalse(
            input.contains(try parentValue(parent)),
            "the client must not carry the recovered value")

        let turn = try await responses(
            port: handle.publicPort,
            body: continuationBody(
                session: session,
                anchor: parent.stateID,
                previousStateID: parent.stateID))
        XCTAssertEqual(turn.status, 200, describe(turn))
        let generated = try XCTUnwrap(assistantText(turn.body), describe(turn))
        XCTAssertTrue(
            generated.contains("ANSWER=\(value)"),
            "the continuation must answer from the recovered value; got: \(generated)")

        let usage = try XCTUnwrap(turn.body["usage"] as? [String: Any])
        let details = try XCTUnwrap(
            usage["input_tokens_details"] as? [String: Any])
        XCTAssertEqual(
            details["cached_tokens"] as? Int, 0,
            "the invalidated KV must not contribute cached tokens; usage=\(usage)")
        XCTAssertGreaterThan(
            (usage["input_tokens"] as? Int) ?? 0, 0,
            "the continuation must actually reach the model")
        XCTAssertGreaterThan(
            (usage["output_tokens"] as? Int) ?? 0, 0,
            "the model must actually generate the answer")

        let settlement = try XCTUnwrap(
            turn.body["continuation_settlement"] as? [String: Any])
        let childStateID = try XCTUnwrap(
            settlement["child_es_state_id"] as? String)
        let childSettlementID = try XCTUnwrap(
            settlement["settlement_id"] as? String)
        let anchors = try XCTUnwrap(turn.body["simigo"] as? [String: Any])
        XCTAssertEqual(anchors["es_state_id"] as? String, childStateID)
        XCTAssertEqual(anchors["settlement_id"] as? String, childSettlementID)

        let child = try XCTUnwrap(
            try parent.esis.readGraph().states.first { $0.id == childStateID })
        let parentRow = try XCTUnwrap(
            try parent.esis.readGraph().states.first { $0.id == parent.stateID })
        XCTAssertEqual(child.parentID, parent.stateID)
        XCTAssertEqual(child.nextInput, value)
        XCTAssertEqual(child.modelIdentity, parentRow.modelIdentity)
        XCTAssertTrue(
            try parent.esis.upstreamDependencyClosure(ofSettlement: childSettlementID)
                .contains(parent.settlementID),
            "the child settlement must cite the parent settlement")
        XCTAssertEqual(
            try parent.esis.latestSettlementID(forStateID: parent.stateID),
            parent.settlementID,
            "the parent must not be re-settled")
        XCTAssertEqual(
            try settlementsWritten(forState: parent.stateID, in: parent.esis),
            parent.settlementCount,
            "the parent settlement must not be re-submitted")
    }

    private func parentValue(_ parent: Parent) throws -> String {
        try XCTUnwrap(
            try parent.esis.readGraph().states
                .first { $0.id == parent.stateID }?.nextInput)
    }

    private func continuationBody(
        session: String, anchor: String, previousStateID: String
    ) -> [String: Any] {
        [
            "model": modelName(from: modelPath),
            "session_id": session,
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
            "input": "Continue the settled task.",
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

    // MARK: - Engine probes

    @MainActor
    private func enginePort(_ runtime: ManagedGGUFRuntime) throws -> Int {
        try XCTUnwrap(runtime.enginePort)
    }

    @MainActor
    private func engineSlots(
        _ runtime: ManagedGGUFRuntime
    ) async throws -> [[String: Any]] {
        let port = try enginePort(runtime)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/slots")!)
        request.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let slots = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw ProbeFailure.unreadable }
        return slots
    }

    @MainActor
    private func slotPromptTokens(
        _ runtime: ManagedGGUFRuntime
    ) async throws -> [Int] {
        try await engineSlots(runtime).compactMap {
            ($0["n_prompt_tokens"] as? NSNumber)?.intValue
        }
    }

    @MainActor
    private func eraseEngineSlots(
        _ runtime: ManagedGGUFRuntime
    ) async throws -> Int {
        var erased = 0
        for slot in try await engineSlots(runtime) {
            guard let id = (slot["id"] as? NSNumber) ?? (slot["id_slot"] as? NSNumber)
            else { continue }
            let port = try enginePort(runtime)
            var request = URLRequest(
                url: URL(string: "http://127.0.0.1:\(port)/slots/\(id.intValue)?action=erase")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            XCTAssertEqual(
                status, 200,
                "slot erase returned \(status): \(String(decoding: data, as: UTF8.self))")
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            erased += (json?["n_erased"] as? NSNumber)?.intValue ?? 0
        }
        return erased
    }

    @MainActor
    private func engineProps(
        _ runtime: ManagedGGUFRuntime
    ) async throws -> [String: Any] {
        let port = try enginePort(runtime)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/props")!)
        request.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let props = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProbeFailure.unreadable }
        return props
    }

    @MainActor
    private func waitForSleeping(
        _ runtime: ManagedGGUFRuntime, timeout: TimeInterval = 60
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let props = try await engineProps(runtime)
            if (props["is_sleeping"] as? Bool) == true {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTFail("engine did not enter sleep within \(Int(timeout))s")
        throw ProbeFailure.unreadable
    }

    @MainActor
    private func engineChat(
        _ runtime: ManagedGGUFRuntime,
        messages: [[String: String]],
        maxTokens: Int
    ) async throws -> (status: Int, body: [String: Any]) {
        let port = try enginePort(runtime)
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelName(from: modelPath),
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": 0,
            "stream": false,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, json)
    }

    private enum ProbeFailure: Error {
        case unreadable
    }

    @MainActor
    private func settlementsWritten(
        forState stateID: String, in db: SimiGoESISDatabase
    ) throws -> Int {
        try db.readSettlementReceipts().filter { $0.stateID == stateID }.count
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