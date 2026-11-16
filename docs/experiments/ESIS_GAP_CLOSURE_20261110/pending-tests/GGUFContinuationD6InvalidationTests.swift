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
/// Anchors are read from the authoritative store, never from the response body.
/// A plain generated turn emits no `simigo` block at all — that key appears only
/// on the zero-call reuse path (`answerReuseBlock`) — so the ES state id and the
/// settlement id of a parent turn exist only in SQLite. Measured 2026-11-10, and
/// the reason this file diverges from the archived design it was adapted from.
///
/// `n_erased` and the erase semantics are measured on the pinned b11720 engine,
/// not inferred from `strings`: erase returns `{"id_slot":N,"n_erased":M}` and a
/// post-erase replay of the same prompt reports `cached_tokens == 0` even with
/// the default 8192 MiB host cache at `--parallel 1`. That is why arm A keeps the
/// default cache and arms B and C pass `--cache-ram 0`: sleep and the divergent
/// overwrite are the two cases where a host copy could genuinely serve the
/// prompt, and upstream exposes no API to clear it.
///
/// Restate, not derive: `ExecutionStateGraph.referenceResultContractJSON` is the
/// contract a settling continuation is authorized under — `^RESULT=(.+)$` plus an
/// `equals_binding` against the `next_input` binding that `ISAdmission.admit`
/// mints from the recovered value (ContinuationSettlement.swift:306,
/// ExecutionStateGraph.swift:408/540). Measured 2026-11-10: a continuation that
/// answered `TASK=…/ANSWER=<value+1>` reached the engine, streamed 20 content
/// deltas and 40 bytes of text, and was then refused
/// `NATIVE_RESULT_CONTRACT_REJECTED / PRODUCER_RESULT_FIELD_MISSING`. So the
/// answer must copy the recovered value. The proof is unchanged, and if anything
/// sharper: no digit travels in the client's turn, so digits in the answer can
/// only have come from IS.
///
/// Gated, because each arm costs a model load and real GPU work:
///   * `SIMIGO_GGUF_E2E_MODEL` — absolute path to a `.gguf` checkpoint,
///   * `SIMIGO_GGUF_E2E_BIN` — absolute path to a `llama-server` executable,
///   * the three isolated roots injected by `tools/make_isolated_xctestrun.py`.
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
            ManagedPaths.databaseURL.path.hasPrefix(isolationRoot.path),
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
        let parent = try await settleParent(handle, session: session, value: "2718281")

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

        try await assertPhantomRefused(handle, parent: parent, session: session)
        try await assertContinuation(
            handle, parent: parent, session: session)
    }

    // MARK: - B: sleep / wake

    @MainActor
    func testD6BSleepAndWakeRecoversThroughIS() async throws {
        let handle = try await startRuntime(
            tag: "sleep",
            extraArgs: ["--sleep-idle-seconds", "1", "--cache-ram", "0"])
        addTeardownBlock { await handle.runtime.stop() }
        let session = "d6b-\(UUID().uuidString)"
        let parent = try await settleParent(handle, session: session, value: "3141592")

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
        try await assertPhantomRefused(handle, parent: parent, session: session)
        let stillSleeping = try await engineProps(handle.runtime)
        XCTAssertEqual(
            stillSleeping["is_sleeping"] as? Bool, true,
            "a refused turn must not wake the engine")

        try await assertContinuation(
            handle, parent: parent, session: session)
        let awake = try await engineProps(handle.runtime)
        XCTAssertEqual(
            awake["is_sleeping"] as? Bool, false,
            "the admitted continuation must have woken the engine")
    }

    // MARK: - C: RAM prompt cache absent

    @MainActor
    func testD6CRAMCacheAbsentRecoversThroughIS() async throws {
        let handle = try await startRuntime(tag: "ram", extraArgs: ["--cache-ram", "0"])
        addTeardownBlock { await handle.runtime.stop() }
        let session = "d6c-\(UUID().uuidString)"
        let parent = try await settleParent(handle, session: session, value: "1618033")

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

        try await assertPhantomRefused(handle, parent: parent, session: session)
        try await assertContinuation(
            handle, parent: parent, session: session)
    }

    // MARK: - D: same runtime restart

    @MainActor
    func testD6DRuntimeRestartRecoversThroughIS() async throws {
        let first = try await startRuntime(tag: "restart", extraArgs: [])
        let runtime = first.runtime
        addTeardownBlock { await runtime.stop() }
        let session = "d6d-\(UUID().uuidString)"
        let parent = try await settleParent(first, session: session, value: "1414213")

        // Positive control on the OLD engine: without it, "every slot reports no
        // prompt" after the restart would be the same reading a never-used engine
        // gives, and would prove nothing.
        let before = try await slotPromptTokens(runtime)
        XCTAssertTrue(
            before.contains { $0 > 0 },
            "the parent prompt must occupy a slot before the restart; slots=\(before)")

        let oldEnginePort = try enginePort(runtime)
        let oldPublicPort = first.publicPort
        await runtime.stop()
        XCTAssertFalse(runtime.isRunning)
        XCTAssertNil(runtime.enginePort)
        XCTAssertFalse(portAcceptsConnection(oldEnginePort))
        XCTAssertFalse(portAcceptsConnection(oldPublicPort))

        // `GGUFRestFixture.freePort` proves a port is bindable and then releases
        // it, and it samples 42000...58000 — inside the macOS ephemeral range. On
        // restart the gap between reservation and listen is a whole model load,
        // and that gap was measured being filled by another process (NWListener:
        // "Address already in use", no listener, engine fine). Re-reserving is the
        // harness's job; the product's restart contract is what is under test.
        var restarted: EngineHandle?
        var lastFailure: String = "never attempted"
        for _ in 0..<3 {
            let candidate = Int(try GGUFRestFixture.freePort())
            do {
                try await runtime.start(ModelInfo(path: modelPath, kind: .gguf), port: candidate)
                try GGUFRestFixture.waitUntilListening(port: candidate)
                restarted = EngineHandle(runtime: runtime, publicPort: candidate)
                break
            } catch {
                lastFailure = "\(error)"
                await runtime.stop()
            }
        }
        let handle = try XCTUnwrap(
            restarted, "restart never reached a listening server: \(lastFailure)")
        XCTAssertTrue(runtime.isRunning)
        XCTAssertNotEqual(try enginePort(runtime), oldEnginePort)

        // The restart must be a genuinely empty engine, not a re-attachment to
        // the old process. `listBranchesHandler` is hardcoded to return nothing
        // on this backend, so asking it would prove nothing; the engine's own
        // slot table does.
        let fresh = try await slotPromptTokens(runtime)
        XCTAssertTrue(
            fresh.allSatisfy { $0 == 0 },
            "the restarted engine inherits no prompt KV; slots=\(fresh)")

        try await assertPhantomRefused(handle, parent: parent, session: session)
        try await assertContinuation(handle, parent: parent, session: session)
    }

    // MARK: - Scenario helpers

    private struct EngineHandle {
        let runtime: ManagedGGUFRuntime
        let publicPort: Int
    }

    private struct Parent {
        let session: String
        let stateID: String
        let settlementID: String
        let settlementCount: Int
        let esis: ESISDatabase
    }

    @MainActor
    private func startRuntime(tag: String, extraArgs: [String]) async throws -> EngineHandle {
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
        let input =
            "Output only this integer and nothing else, no punctuation: " + value
        let turn = try await responses(
            port: handle.publicPort,
            body: [
                "model": modelName(from: modelPath),
                "session_id": session,
                "stream": false,
                "max_tokens": 24,
                "temperature": 0,
                "input": input,
            ])
        XCTAssertEqual(turn.status, 200, describe(turn))
        XCTAssertEqual(
            try XCTUnwrap(assistantText(turn.body)), value,
            "the parent turn must settle the exact integer; body=\(turn.body)")

        let db = try ESISDatabase(url: ManagedPaths.databaseURL)
        let stateID = try XCTUnwrap(
            try db.currentChatStateID(sessionID: session),
            "a complete turn advances the session to an ES state: \(describe(turn))")
        let answered = try XCTUnwrap(
            try db.answeredDemand(sessionID: session, query: input),
            "a complete real turn settles its demand")
        XCTAssertEqual(
            try db.latestSettlementID(forStateID: stateID), answered.answerSettlementID,
            "the demand must advance the session's own state")
        XCTAssertEqual(try db.settlementValidity(answered.answerSettlementID), "valid")

        let count = try settlementsWritten(forState: stateID, in: db)
        XCTAssertEqual(count, 1)
        let row = try XCTUnwrap(
            try db.readGraph().states.first { $0.id == stateID })
        XCTAssertEqual(row.nextInput, value)

        return Parent(
            session: session,
            stateID: stateID,
            settlementID: answered.answerSettlementID,
            settlementCount: count,
            esis: db)
    }

    @MainActor
    private func assertPhantomRefused(
        _ handle: EngineHandle, parent: Parent, session: String
    ) async throws {
        let phantom = "es-does-not-exist-\(UUID().uuidString)"
        let turn = try await responses(
            port: handle.publicPort,
            body: continuationBody(session: session, anchor: phantom))
        XCTAssertEqual(turn.status, 422, describe(turn))
        let error = try XCTUnwrap(turn.body["error"] as? [String: Any])
        XCTAssertEqual(error["error_kind"] as? String, "INPUT_ADMISSION_REFUSED")

        XCTAssertNil(
            try parent.esis.latestSettlementID(forStateID: phantom),
            "a refused continuation must write no settlement")
        XCTAssertEqual(
            try settlementsWritten(forState: parent.stateID, in: parent.esis),
            parent.settlementCount,
            "a refused continuation must not re-settle the parent")
        XCTAssertEqual(
            try parent.esis.currentChatStateID(sessionID: session), parent.stateID,
            "a refused continuation must not advance the session")
    }

    @MainActor
    private func assertContinuation(
        _ handle: EngineHandle, parent: Parent, session: String
    ) async throws {
        let input = "Continue the settled task."
        let recovered = try parentValue(parent)
        XCTAssertNotEqual(
            recovered, input,
            "the client must not carry the recovered value")

        let turn = try await responses(
            port: handle.publicPort,
            body: continuationBody(session: session, anchor: parent.stateID))
        XCTAssertEqual(turn.status, 200, describe(turn))
        let generated = try XCTUnwrap(assistantText(turn.body), describe(turn))
        // The digits never travelled in the client's turn, so the only source for
        // them in this generation is the value admission recovered from IS.
        XCTAssertEqual(
            generated, "RESULT=\(recovered)",
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
            turn.body["continuation_settlement"] as? [String: Any], describe(turn))
        let childStateID = try XCTUnwrap(settlement["child_es_state_id"] as? String)
        let childSettlementID = try XCTUnwrap(settlement["settlement_id"] as? String)

        let child = try XCTUnwrap(
            try parent.esis.readGraph().states.first { $0.id == childStateID })
        let parentRow = try XCTUnwrap(
            try parent.esis.readGraph().states.first { $0.id == parent.stateID })
        XCTAssertEqual(child.parentID, parent.stateID)
        // The child settlement's payload IS the recovered value: both
        // settlements carry the same content-addressed digest, and the child
        // ES row persists it as next_input in the same commit (the restart
        // contract of ChildExecutionState).
        XCTAssertEqual(
            try parent.esis.settlementPayloadDigest(childSettlementID),
            try parent.esis.settlementPayloadDigest(parent.settlementID),
            "the settled child payload must be the recovered value")
        XCTAssertEqual(child.nextInput, try parentValue(parent),
                       "the child ES row must persist the settled value as next_input")
        XCTAssertEqual(child.modelIdentity, parentRow.modelIdentity)
        XCTAssertEqual(
            try parent.esis.latestSettlementID(forStateID: childStateID),
            childSettlementID)
        XCTAssertEqual(
            try parent.esis.currentChatStateID(sessionID: session), childStateID,
            "the settled child becomes the session's state")
        // The continuation settlement records its admission-verified parent as
        // an upstream dependency in the same commit, so a later parent-source
        // invalidation cascades to the child along the closure.
        XCTAssertTrue(
            try parent.esis.upstreamDependencyClosure(ofSettlement: childSettlementID)
                .contains(parent.settlementID),
            "the child settlement must depend on the parent settlement it was admitted against")
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

    private func continuationBody(session: String, anchor: String) -> [String: Any] {
        [
            "model": modelName(from: modelPath),
            "session_id": session,
            "stream": false,
            "max_tokens": 64,
            "temperature": 0,
            "instructions": """
                You are continuing a settled task.
                The previous result is supplied as the LAST user message.
                Reply with exactly one line and nothing else:
                RESULT=<the previous result, copied digit for digit>
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

    private func enginePort(_ runtime: ManagedGGUFRuntime) throws -> Int {
        try XCTUnwrap(runtime.enginePort)
    }

    private func engineSlots(_ runtime: ManagedGGUFRuntime) async throws -> [[String: Any]] {
        let port = try enginePort(runtime)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/slots")!)
        request.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let slots = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw ProbeFailure.unreadableSlots }
        // An empty slot table would make every downstream "no prompt remains"
        // assertion true by vacuity. `--slots` is emitted by BackendConfig.llama;
        // if it is not answered, the harness is broken, not the engine.
        guard !slots.isEmpty else { throw ProbeFailure.emptySlotTable }
        return slots
    }

    /// Tokens currently loaded in each slot's prompt. Measured on b11720: an
    /// engine that has never processed a prompt answers `/slots` with
    /// `id, speculative, is_processing, n_ctx` and NO `n_prompt_tokens` key at
    /// all, so absence is the empty case rather than a broken probe. Every arm
    /// that reads a zero must also read a non-zero from the same engine first
    /// (arms A/C/D) — that positive control is what keeps this mapping honest.
    private func slotPromptTokens(_ runtime: ManagedGGUFRuntime) async throws -> [Int] {
        try await engineSlots(runtime).map { slot in
            (slot["n_prompt_tokens"] as? NSNumber)?.intValue ?? 0
        }
    }

    private func eraseEngineSlots(_ runtime: ManagedGGUFRuntime) async throws -> Int {
        var erased = 0
        for slot in try await engineSlots(runtime) {
            guard let id = (slot["id"] as? NSNumber) ?? (slot["id_slot"] as? NSNumber)
            else { throw ProbeFailure.missingSlotID(slot) }
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
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            // Measured on the pinned engine: erase always answers with
            // {id_slot, n_erased}. A silent 0 here would let an erase that
            // removed nothing pass as a successful invalidation.
            let nErased = try XCTUnwrap(
                (json["n_erased"] as? NSNumber)?.intValue,
                "erase response carries no n_erased: \(json)")
            erased += nErased
        }
        return erased
    }

    private func engineProps(_ runtime: ManagedGGUFRuntime) async throws -> [String: Any] {
        let port = try enginePort(runtime)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/props")!)
        request.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let props = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProbeFailure.unreadableProps }
        return props
    }

    private func waitForSleeping(
        _ runtime: ManagedGGUFRuntime, timeout: TimeInterval = 60
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let props = try await engineProps(runtime)
            if (props["is_sleeping"] as? Bool) == true { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTFail("engine did not enter sleep within \(Int(timeout))s")
        throw ProbeFailure.didNotSleep
    }

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

    private enum ProbeFailure: Error, CustomStringConvertible {
        case unreadableSlots
        case unreadableProps
        case emptySlotTable
        case didNotSleep
        case missingSlotID([String: Any])

        var description: String {
            switch self {
            case .unreadableSlots: return "GET /slots returned no JSON array"
            case .unreadableProps: return "GET /props returned no JSON object"
            case .emptySlotTable: return "/slots returned an empty table; no invalidation is observable"
            case .didNotSleep: return "engine never reported is_sleeping"
            case .missingSlotID(let slot): return "/slots entry carries no id: \(slot)"
            }
        }
    }

    private func settlementsWritten(forState stateID: String, in db: ESISDatabase) throws -> Int {
        try db.readSettlementReceipts().filter { $0.stateID == stateID }.count
    }

    private func portAcceptsConnection(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
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
