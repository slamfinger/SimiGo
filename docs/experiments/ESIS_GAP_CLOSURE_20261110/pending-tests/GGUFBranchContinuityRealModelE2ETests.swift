import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// Phase 1 ES logical continuity on a real llama.cpp engine.
///
/// The stub-backed tests prove the wiring; only a real engine can answer the
/// question this phase is actually about: when the process holding the KV no
/// longer has it, does a forked branch still get the context it is entitled to
/// — and does the answer come out of the model's own chat template rather than
/// a locally assembled token sequence?
///
/// Nothing here claims shared KV or a cheaper prefill. The engine is measured
/// with its own readings — `n_erased` and per-slot `n_prompt_tokens` for the
/// release, `usage.prompt_tokens_details.cached_tokens` as a negative control
/// that the engine carried nothing reusable — so a forked branch's answer can
/// only come from the context the ledger handed back.
///
/// Gated like `GGUFManagedEntryRealModelE2ETests`:
///   * `SIMIGO_GGUF_E2E_MODEL`, `SIMIGO_GGUF_E2E_BIN`,
///   * the isolated roots injected by `tools/make_isolated_xctestrun.py`.
///
/// IS retrieval is deliberately taken out of the carrier set: every turn here
/// declares `x-simigo-request-scope: internal`, so its chat rows never reach
/// `turn_state='committed'` and can never be retrieved as context. Without
/// that, a committed session chat would hand the fact to the model on its own
/// and the negative control could not fail.
///
/// Turns run over the product's HTTP surface; the branch control plane is
/// driven through the runtime API the HTTP handlers call, because `/v1/branches/*`
/// is refused by the LOCALB route table before any handler runs (measured 403
/// on this run, asserted by `testBranchControlPlaneIsNotReachableOverHTTP`).
/// Phase 1 therefore has evidence at the runtime layer, not at a client-reachable
/// fork endpoint.
final class GGUFBranchContinuityRealModelE2ETests: XCTestCase {

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

    // MARK: - Fork, KV loss, restore

    @MainActor
    func testForkedBranchStillKnowsItsContextAfterTheEngineLosesKV() async throws {
        let (runtime, port) = try await startRuntime(parallel: 1)
        let session = "gguf-fork-\(UUID().uuidString)"
        let code = "ZEBRA-42"

        // 1. The parent turn puts the fact in front of the engine.
        let parentPrompt =
            "记住这个编号：斑马编号是 \(code)。之后我只会问编号，回答时只输出编号本身。"
        let parent = try await chat(
            port: port, session: session, branch: "main",
            messages: [["role": "user", "content": parentPrompt]],
            maxTokens: 32)
        let parentAnswer = try assistantText(parent)
        XCTAssertFalse(parentAnswer.isEmpty, "the real engine produced no parent answer")
        let parentTranscript: [[String: String]] = [
            ["role": "user", "content": parentPrompt],
            ["role": "assistant", "content": parentAnswer],
        ]

        // 2. Fork is logical: the child inherits the transcript, nothing else.
        let child = try fork(runtime, session: session, from: "main", to: "child")
        XCTAssertEqual(
            child.history.count, 2,
            "a fork hands the child exactly what the engine has already rendered")
        XCTAssertNil(child.kvFingerprint, "a logical fork must not claim a KV fingerprint")
        XCTAssertNil(child.cacheSHA256, "a logical fork has no cache bytes to checksum")
        XCTAssertNil(child.checkpointGeneration, "Phase 1 writes no GGUF branch checkpoint")

        // 3. Instrument characterization. Measured at this pin: sending the SAME
        //    transcript twice reuses nothing (cached_tokens 0/0) once context
        //    checkpoints are disabled, while with the default 32 checkpoints the
        //    same pair reads 48/48 even after a slot erase. So for this hybrid
        //    model all cross-request prefix reuse comes from checkpoints, and
        //    `cached_tokens` cannot act as a warm/cold pair. What it does give is
        //    a negative control: with reuse pinned at zero, nothing in the
        //    continuity below can be credited to KV the engine still holds.
        let warm = try await engineUsage(runtime: runtime, messages: parentTranscript, maxTokens: 1)
        let warmAgain = try await engineUsage(runtime: runtime, messages: parentTranscript, maxTokens: 1)
        XCTAssertEqual(
            warmAgain.cachedTokens, 0,
            "with checkpoints disabled the engine must not reuse its own prefix "
            + "(first pass cached=\(warm.cachedTokens), second=\(warmAgain.cachedTokens)); "
            + "if it does, this configuration cannot isolate the ledger as the carrier")

        // 4. The child supplies only its new question.
        let firstChild = try await chat(
            port: port, session: session, branch: "child",
            messages: [["role": "user", "content": "我的斑马编号是什么？只输出编号。"]],
            maxTokens: 32)
        let firstChildText = try assistantText(firstChild)
        XCTAssertTrue(
            firstChildText.contains(code),
            "the forked branch must be handed its parent's context, got: \(firstChildText)")

        // 5. Release the old KV in the engine's own accounting: the erase drops
        //    the slot's prompt record and its sequence mapping, and the slot then
        //    reports that it holds nothing. A prefix-disjoint prompt is written
        //    over the freed window so any residual reuse would surface.
        let heldBefore = try await slotPromptTokens(runtime)
        XCTAssertTrue(
            heldBefore.contains { $0 > 0 },
            "no slot reports a held prompt before the release: \(heldBefore)")
        let erased = try await eraseEngineSlots(runtime: runtime)
        XCTAssertGreaterThan(
            erased, 0,
            "the release instrument must actually drop a prompt — an erase that "
            + "returned nothing would leave the readings below unexplained")
        let heldAfter = try await slotPromptTokens(runtime)
        XCTAssertTrue(
            heldAfter.allSatisfy { $0 == 0 },
            "the engine must report no held prompt after the release: \(heldAfter)")
        _ = try await engineUsage(
            runtime: runtime,
            messages: [["role": "user", "content": String(repeating: "无关填充内容 segment ", count: 60)]],
            maxTokens: 1)
        let cold = try await engineUsage(
            runtime: runtime, messages: parentTranscript, maxTokens: 1)
        XCTAssertEqual(
            cold.cachedTokens, 0,
            "measured: cached warm=\(warm.cachedTokens)/\(warmAgain.cachedTokens) vs after the "
            + "release \(cold.cachedTokens), prompt tokens released=\(erased), held before "
            + "\(heldBefore) vs after \(heldAfter). Any reuse here would mean the engine still "
            + "carried the transcript and the restore below would prove nothing.")

        // 6. Restore after the release: the branch still knows the fact, because
        //    the ledger hands the engine the whole context and the engine
        //    re-renders and re-prefills it.
        let afterRelease = try await chat(
            port: port, session: session, branch: "child",
            messages: [["role": "user", "content": "把你要记住的编号再输出一次，只输出编号。"]],
            maxTokens: 32)
        let afterReleaseText = try assistantText(afterRelease)
        XCTAssertTrue(
            afterReleaseText.contains(code),
            "continuity must not depend on the engine's KV, got: \(afterReleaseText)")

        // 7. Paired negative control: a branch with no ledger record gets nothing
        //    reconstructed, so the fact is unreachable.
        let orphan = try await chat(
            port: port, session: session, branch: "orphan",
            messages: [["role": "user", "content": "我的斑马编号是什么？只输出编号。"]],
            maxTokens: 32)
        let orphanText = try assistantText(orphan)
        XCTAssertFalse(
            orphanText.contains(code),
            "the control branch must NOT know the code — if it does, the fact reached it "
            + "by some path other than the branch ledger and the whole test is vacuous. "
            + "got: \(orphanText)")

        // 8. Listing and release.
        let live = runtime.liveBranches(agentId: nil, sessionId: session)
        XCTAssertTrue(live.contains("child"), "live branches: \(live)")
        let checkpointFiles = ((try? FileManager.default.contentsOfDirectory(
            atPath: SimiGoRuntimeCachePaths.branchCheckpointsRoot.path)) ?? [])
            .filter { $0.contains(session) }
        XCTAssertTrue(
            checkpointFiles.isEmpty,
            "Phase 1 must write no GGUF branch checkpoint for \(session): \(checkpointFiles)")

        runtime.deleteBranch(agentId: nil, sessionId: session, branchId: "child")
        XCTAssertFalse(
            runtime.liveBranches(agentId: nil, sessionId: session).contains("child"),
            "a deleted branch must leave the live set")
        let reforkError = refusedFork(
            runtime, session: session, from: "child", to: "grandchild")
        XCTAssertNotNil(
            reforkError,
            "a released branch must not keep handing out continuity")
    }

    // MARK: - Branch independence and concurrency

    @MainActor
    func testConcurrentBranchesAnswerFromTheirOwnContexts() async throws {
        let (runtime, port) = try await startRuntime(parallel: 2)
        let session = "gguf-concurrent-\(UUID().uuidString)"

        _ = try await chat(
            port: port, session: session, branch: "main",
            messages: [["role": "user", "content": "接下来你会分支，先只回答：准备"]],
            maxTokens: 16)
        _ = try fork(runtime, session: session, from: "main", to: "alpha")
        _ = try fork(runtime, session: session, from: "main", to: "beta")

        // Each branch is taught a different code, concurrently.
        async let a = chat(
            port: port, session: session, branch: "alpha",
            messages: [["role": "user", "content": "记住：你的代号是 ALPHA-7。只输出代号。"]],
            maxTokens: 16)
        async let b = chat(
            port: port, session: session, branch: "beta",
            messages: [["role": "user", "content": "记住：你的代号是 BETA-9。只输出代号。"]],
            maxTokens: 16)
        _ = try await (a, b)

        // Both ask for their own code at the same time, supplying no history.
        async let askAlpha = chat(
            port: port, session: session, branch: "alpha",
            messages: [["role": "user", "content": "你的代号是什么？只输出代号。"]],
            maxTokens: 16)
        async let askBeta = chat(
            port: port, session: session, branch: "beta",
            messages: [["role": "user", "content": "你的代号是什么？只输出代号。"]],
            maxTokens: 16)
        let alpha = try assistantText(await askAlpha)
        let beta = try assistantText(await askBeta)

        XCTAssertTrue(alpha.contains("ALPHA-7"), "alpha answered: \(alpha)")
        XCTAssertTrue(beta.contains("BETA-9"), "beta answered: \(beta)")
        XCTAssertFalse(alpha.contains("BETA-9"), "alpha leaked beta's context: \(alpha)")
        XCTAssertFalse(beta.contains("ALPHA-7"), "beta leaked alpha's context: \(beta)")

        // Structural half of the same claim: the parent transcript never grew
        // from the children's turns, so a later fork of the parent cannot carry
        // a child's content.
        let fromParent = try fork(runtime, session: session, from: "main", to: "gamma")
        XCTAssertEqual(
            fromParent.history.count, 2,
            "the parent must still hold only its own turn after both children ran")
    }

    // MARK: - Cancel

    /// A cancelled turn must not leave a branch that claims continuity. The
    /// branch under test gets no prior record, so the only way a fork from it
    /// could succeed is if the abandoned turn had been observed anyway.
    @MainActor
    func testCancelledTurnLeavesNoBranchContinuity() async throws {
        let (runtime, port) = try await startRuntime(parallel: 2)
        let session = "gguf-cancel-\(UUID().uuidString)"

        _ = try await chat(
            port: port, session: session, branch: "main",
            messages: [["role": "user", "content": "只回答：就绪"]], maxTokens: 16)

        // A stream long enough to still be decoding when it is abandoned, then a
        // second request that takes the generation window: the product stops the
        // orphan at the next token boundary through the standard cancel wiring.
        try await abandonStreamingTurn(
            port: port, session: session, branch: "doomed",
            prompt: "从 1 开始连续报数，一直报到 400，每个数字单独一行，不要停顿。")
        let next = try await chat(
            port: port, session: session, branch: "main",
            messages: [["role": "user", "content": "只回答：继续"]], maxTokens: 16)
        _ = try assistantText(next)

        let probeError = refusedFork(
            runtime, session: session, from: "doomed", to: "probe")
        XCTAssertNotNil(
            probeError,
            "a cancelled turn must not leave a usable transcript behind — the branch would "
            + "otherwise claim continuity it never settled")
        XCTAssertFalse(
            runtime.liveBranches(agentId: nil, sessionId: session).contains("doomed"),
            "the abandoned branch must not appear as live: \(runtime.liveBranches(agentId: nil, sessionId: session))")

        // Paired positive control: the same branch becomes forkable as soon as a
        // turn of it actually completes, so the refusal above is about the
        // cancelled turn and not about the branch name.
        _ = try await chat(
            port: port, session: session, branch: "doomed",
            messages: [["role": "user", "content": "只回答：完成"]], maxTokens: 16)
        let after = try fork(runtime, session: session, from: "doomed", to: "probe2")
        XCTAssertEqual(after.history.count, 2, "a settled turn must give the branch continuity")
    }

    // MARK: - Runtime

    @MainActor
    private func startRuntime(parallel: Int) async throws -> (ManagedGGUFRuntime, Int) {
        setenv("SIMIGO_LLAMA_PARALLEL", "\(parallel)", 1)
        let slotStore = isolationRoot.appendingPathComponent("slots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: slotStore, withIntermediateDirectories: true)

        var config = ModelConfig()
        config.ctxSize = 4096
        config.maxTokens = 64
        config.temperature = 0
        // The caliber under test is the model's own template: with jinja off the
        // engine would fall back to a generic one, and the reconstructed
        // transcript would be rendered by something other than the GGUF metadata.
        config.jinja = true

        let backend = BackendConfig(
            name: "llama.cpp",
            customExecutable: engineBinary,
            args: { info, cfg, port in
                // Two additions to the product's launch args, both for the
                // release instrument:
                //   * `--slot-save-path` unlocks the engine's `/slots` action
                //     endpoint (it refuses every action without it).
                //   * `--ctx-checkpoints 0` stops the slot from keeping
                //     restorable KV snapshots. Measured with the default 32: a
                //     slot erase released 71 prompt tokens yet the engine still
                //     reported cached_tokens 48/48, because `prompt_clear()`
                //     leaves `prompt.checkpoints` intact. Continuity has to hold
                //     with no engine-side carrier at all, so this runs the
                //     strictest configuration rather than the default one.
                BackendConfig.llama.args(info, cfg, port)
                    + ["--slot-save-path", slotStore.path, "--ctx-checkpoints", "0"]
            },
            healthEndpoint: "/health",
            startupTimeout: 600,
            kind: .gguf)

        let runtime = ManagedGGUFRuntime(config: config, backendConfig: backend)
        let port = Int(try GGUFRestFixture.freePort())
        try await runtime.start(ModelInfo(path: modelPath, kind: .gguf), port: port)
        addTeardownBlock { await runtime.stop() }
        try GGUFRestFixture.waitUntilListening(port: port)
        XCTAssertNotNil(runtime.engineIdentity, "the engine identity probe must read /props")

        // The caliber the ledger relies on is the engine's own: this is the model's
        // embedded template and BOS, not a generic fallback, and the slot count the
        // product assumed is the one the engine reports.
        let props = try await engineProps(runtime)
        XCTAssertFalse(
            props.chatTemplate.isEmpty,
            "the engine reports no chat template, so a reconstructed transcript would be "
            + "rendered by something other than the model's own template")
        XCTAssertFalse(props.bosToken.isEmpty, "the engine reports no BOS token")
        XCTAssertEqual(
            props.modelPath, modelPath,
            "the engine must be serving the model SimiGo handed it")
        XCTAssertEqual(
            props.totalSlots, parallel,
            "the product's slot assumption and the engine's must agree")
        return (runtime, port)
    }

    // MARK: - Branch control plane

    /// Phase 1's fork/restore/list/delete are driven through the runtime API
    /// that the HTTP handlers call. The HTTP route itself is not reachable —
    /// see `testBranchControlPlaneIsNotReachableOverHTTP` — so the runtime
    /// layer is the furthest live layer this evidence can cover.
    private func fork(
        _ runtime: ManagedGGUFRuntime, session: String, from: String, to: String
    ) throws -> SessionCacheMetadata {
        try runtime.forkBranch(
            agentId: nil, sessionId: session,
            sourceBranch: from, targetBranch: to,
            modelId: modelName(from: modelPath))
    }

    private func refusedFork(
        _ runtime: ManagedGGUFRuntime, session: String, from: String, to: String
    ) -> String? {
        do {
            _ = try fork(runtime, session: session, from: from, to: to)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// The product's HTTP branch surface stays refused by the LOCALB route
    /// table, which is checked before dispatch and therefore applies to the
    /// plaintext loopback listener as well as to TLS. Recorded here so that the
    /// gap between "the runtime can fork" and "a client can ask it to" is a
    /// measured fact instead of an assumption.
    func testBranchControlPlaneIsNotReachableOverHTTP() throws {
        for route in ["/v1/branches/fork", "/v1/branches/delete", "/v1/branches/list"] {
            guard case .denied(let reason) = HTTPServer.localbRoutePolicy(
                forMethod: "POST", routePath: route)
            else {
                return XCTFail("\(route) is not denied by the LOCALB route table")
            }
            XCTAssertEqual(reason, "LOCALB_BRANCH_OPERATIONS_NOT_AUTHORIZED")
        }
    }

    // MARK: - Product wire

    private func chat(
        port: Int, session: String, branch: String,
        messages: [[String: String]], maxTokens: Int
    ) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("internal", forHTTPHeaderField: "x-simigo-request-scope")
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelName(from: modelPath),
            "session_id": session,
            "branch_id": branch,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": 0,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(status, 200, "chat turn failed: \(body)")
        return body
    }

    private func assistantText(_ body: [String: Any]) throws -> String {
        let choices = try XCTUnwrap(body["choices"] as? [[String: Any]], "no choices in \(body)")
        let message = try XCTUnwrap(choices.first?["message"] as? [String: Any])
        return (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same messages the product handed the engine, re-sent to the engine
    /// directly. Only the engine can report what it reused.
    private struct EngineUsage {
        let promptTokens: Int
        let cachedTokens: Int
    }

    private enum ProbeFailure: Error {
        case missingEnginePort
        case unreadable
    }

    private func enginePort(_ runtime: ManagedGGUFRuntime) throws -> Int {
        guard let enginePort = runtime.enginePort else { throw ProbeFailure.missingEnginePort }
        return enginePort
    }

    private func engineUsage(
        runtime: ManagedGGUFRuntime, messages: [[String: String]], maxTokens: Int
    ) async throws -> EngineUsage {
        let port = try enginePort(runtime)
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelName(from: modelPath),
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": 0,
            "cache_prompt": true,
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let usage = body["usage"] as? [String: Any]
        else { throw ProbeFailure.unreadable }
        let details = usage["prompt_tokens_details"] as? [String: Any]
        return EngineUsage(
            promptTokens: (usage["prompt_tokens"] as? NSNumber)?.intValue ?? -1,
            cachedTokens: (details?["cached_tokens"] as? NSNumber)?.intValue ?? -1)
    }

    private struct EngineProps {
        let chatTemplate: String
        let bosToken: String
        let modelPath: String
        let totalSlots: Int
    }

    private func engineProps(_ runtime: ManagedGGUFRuntime) async throws -> EngineProps {
        let port = try enginePort(runtime)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/props")!)
        request.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProbeFailure.unreadable }
        return EngineProps(
            chatTemplate: json["chat_template"] as? String ?? "",
            bosToken: json["bos_token"] as? String ?? "",
            modelPath: json["model_path"] as? String ?? "",
            totalSlots: (json["total_slots"] as? NSNumber)?.intValue ?? -1)
    }

    /// What each slot says it currently holds, in the engine's own token count.
    private func slotPromptTokens(_ runtime: ManagedGGUFRuntime) async throws -> [Int] {
        let port = try enginePort(runtime)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/slots")!)
        request.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let slots = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw ProbeFailure.unreadable }
        let reported = slots.compactMap { $0["n_prompt_tokens"] as? NSNumber }
        guard !reported.isEmpty else { throw ProbeFailure.unreadable }
        return reported.map { $0.intValue }
    }

    /// `POST /slots/{id_slot}` at this pin reads `action` from the query/path
    /// parameters, never from the JSON body, and the whole endpoint is refused
    /// unless the server was started with `--slot-save-path`. Returns the number
    /// of prompt tokens the engine says it dropped.
    private func eraseEngineSlots(runtime: ManagedGGUFRuntime) async throws -> Int {
        let port = try enginePort(runtime)
        var list = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/slots")!)
        list.httpMethod = "GET"
        let (slotsData, _) = try await URLSession.shared.data(for: list)
        guard let slots = try? JSONSerialization.jsonObject(with: slotsData) as? [[String: Any]]
        else { throw ProbeFailure.unreadable }
        var erased = 0
        for slot in slots {
            guard let id = (slot["id"] as? NSNumber) ?? (slot["id_slot"] as? NSNumber) else { continue }
            var request = URLRequest(
                url: URL(string: "http://127.0.0.1:\(port)/slots/\(id.intValue)?action=erase")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertEqual(status, 200, "slot \(id) erase returned \(status): \(body)")
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            erased += (json?["n_erased"] as? NSNumber)?.intValue ?? 0
        }
        return erased
    }

    /// Start a streaming turn, read a few deltas, then walk away. The product
    /// detaches it and the next request contends it away.
    private func abandonStreamingTurn(
        port: Int, session: String, branch: String, prompt: String
    ) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("internal", forHTTPHeaderField: "x-simigo-request-scope")
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelName(from: modelPath),
            "session_id": session,
            "branch_id": branch,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 512,
            "temperature": 0,
            "stream": true,
        ])
        let task = URLSession.shared.dataTask(with: request)
        task.resume()
        // Long enough for generation to be underway, short enough to abandon it.
        try await Task.sleep(nanoseconds: 4_000_000_000)
        task.cancel()
    }
}
