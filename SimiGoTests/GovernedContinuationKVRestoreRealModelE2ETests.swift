import XCTest
import Foundation
import SimiGoRuntimeContract
@testable import SimiGo

/// A-9 / goal steps 2-3: the FIRST attempt at the intersection that §3.14 proved
/// had never been executed — a GOVERNED (ES-anchor) continuation that is also
/// IS-authorised for KV reuse, on the real model, over the product Responses
/// entry point.
///
/// Turn 1 settles (`continuation_settle=true`), so the admitted child ES becomes
/// the execution branch and the turn-end prefix export is the representation the
/// settlement is allowed to claim (`NativeMLXPrefixPool.export` ->
/// `rememberRepresentation(forBranch:)` -> `settleContinuationResult(kvRepresentation:)`).
/// Turn 2 continues from THAT child, replays Turn 1's exact message chain, and
/// must therefore bind the pooled artifact under the authority the IS settlement
/// just published: `kvBindings=1`, no `isKvBindRejected`, a `poolBind`, and a
/// completion line that reports `mode=restore` with a delta far below Turn 1's
/// cold prefill.
///
/// Nothing here is a fixture shortcut: the anchor is staged in the product's
/// authoritative store, both turns are signed LOCALB HTTP requests, and the
/// reuse claim is read off the engine's own trace line.
final class GovernedContinuationKVRestoreRealModelE2ETests: XCTestCase {
    private let port = 18_473
    /// The negative batch runs in the same process right after the positive one;
    /// the first runtime's `stop()` is a fire-and-forget Task, so the two turns
    /// must not contend for one listener.
    private let tamperPort = 18_474
    private var activePort = 18_473
    private var host: LOCALBAuthorizedE2E.Host!

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
        return snapshots.first?.path ?? hub.appendingPathComponent("NOT-PRESENT").path
    }

    /// ~16KB shared document (≈4-6K tokens) so the cold/warm delta is measurable
    /// at the same scale as the registered §3.12/§3.13 evidence. The per-run
    /// nonce keeps a previous run's pool boundaries from serving Turn 1.
    private let document: String = {
        var lines: [String] = ["Run nonce: \(UUID().uuidString)"]
        for i in 0..<220 {
            lines.append(
                "Section \(i): The runtime keeps execution state as a first-class "
                    + "object; representations bind to logical states by content, and "
                    + "continuity survives sessions and restarts. (\(i) of 220)")
        }
        return lines.joined(separator: "\n")
    }()

    /// The semantic value the staged anchor settles to, and therefore the exact
    /// text the gate injects as the recovered continuation input.
    private let anchorValue = "A9-GOVERNED-KV-7301"

    // MARK: - helpers

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
            port: activePort,
            localbTransportIdentity: host.identity,
            localbRequestAuthorization: (
                coordinator: host.coordinator,
                trustedCheckpoint: host.checkpointProvider
            )
        )
        return runtime
    }

    private func responses(
        messages: [[String: String]], anchor: String, settle: Bool
    ) async throws -> (json: [String: Any], text: String, status: Int, seconds: Double) {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "governed-kv-e2e",
            "input": messages,
            "stream": false,
            "previous_es_state_id": anchor,
            "continuation_settle": settle,
        ])
        let start = Date()
        let (data, response) = try await LOCALBAuthorizedE2E.send(
            host: host, port: activePort, method: "POST",
            path: "/v1/responses", contentType: "application/json", body: body)
        let text = String(decoding: data, as: UTF8.self)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (json, text, response.statusCode, Date().timeIntervalSince(start))
    }

    private func assistantText(from json: [String: Any], raw: String) throws -> String {
        let output = try XCTUnwrap(json["output"] as? [[String: Any]], raw)
        let item = try XCTUnwrap(output.first, "output empty: \(raw)")
        let content = try XCTUnwrap(item["content"] as? [[String: Any]], raw)
        let text = try XCTUnwrap(
            content.first?["text"] as? String, "no text content: \(raw)")
        return text
    }

    private var traceURL: URL {
        SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log")
    }

    private func traceWindow(since offset: Int, timeout: TimeInterval = 3) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var window = ""
        repeat {
            if let data = try? Data(contentsOf: traceURL), data.count > offset {
                window = String(decoding: data.suffix(data.count - offset), as: UTF8.self)
            }
            if window.contains("RELEASED") { return window }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return window
    }

    private func traceSize() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: traceURL.path)
        return attributes?[.size] as? Int ?? 0
    }

    private func integerField(_ marker: String, in line: Substring) -> Int {
        guard let range = line.range(of: marker) else { return -1 }
        let digits = line[range.upperBound...].prefix { $0.isNumber || $0 == "-" }
        return Int(digits) ?? -1
    }

    /// The pooled artifact identified by content hash on an export / bind line.
    /// Equal hashes across the two turns mean the SAME object was re-consumed,
    /// not a freshly recomputed prefix.
    private func refHash(onLineWith marker: String, in window: String) -> String? {
        guard let line = window.split(separator: "\n").first(where: { $0.contains(marker) }),
              let range = line.range(of: "refHash=") else { return nil }
        return String(line[range.upperBound...].prefix { $0.isHexDigit })
    }

    /// The engine's own per-turn accounting line for a governed turn.
    private func completionLine(in window: String, requestTag: String) throws -> Substring {
        let line = try XCTUnwrap(
            window.split(separator: "\n").last { $0.contains("promptTokens=") },
            "no completion line in the \(requestTag) window: \(window)")
        return line
    }

    // MARK: - the experiment

    func testGovernedContinuationRestoresSettledKVAcrossExecutionStates() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let anchor = try await MainActor.run { try stageSettledAnchor(value: anchorValue) }
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        // ---- Turn 1: big cold prefill + real generation + settlement -------
        let turn1Prompt = document + "\n\nQuestion: what is the run token?\n"
            + "Answer with exactly this single line and nothing else: RESULT=\(anchorValue)"
        let offset1 = traceSize()
        let (firstJSON, firstText, firstStatus, firstSeconds) = try await responses(
            messages: [["role": "user", "content": turn1Prompt]],
            anchor: anchor, settle: true)
        XCTAssertEqual(firstStatus, 200, firstText)
        let window1 = traceWindow(since: offset1)
        // The success payload is merged into the completed body under
        // `continuation_settlement` (HTTPServer.settlementPayload).
        let settlement = try XCTUnwrap(
            firstJSON["continuation_settlement"] as? [String: Any],
            "no continuation_settlement object in the response: \(firstText)")
        let childES = try XCTUnwrap(
            settlement["child_es_state_id"] as? String,
            "settlement payload missing child_es_state_id: \(firstText)")
        XCTAssertEqual(
            settlement["identity_binding_published"] as? Bool, true, firstText)
        XCTAssertTrue(
            window1.contains("continuation_admitted"),
            "Turn 1 admission marker missing: \(window1)")
        XCTAssertTrue(
            window1.contains("continuation_branch child=\(childES)"),
            "Turn 1 did not execute under the child ES branch: \(window1)")
        XCTAssertTrue(
            window1.contains("poolExport"),
            "Turn 1 exported no prefix representation to bind later: \(window1)")
        let turn1ExportHash = try XCTUnwrap(
            refHash(onLineWith: "poolExport ", in: window1),
            "Turn 1 export carried no artifact hash: \(window1)")
        let turn1Line = try completionLine(in: window1, requestTag: "Turn 1")
        let turn1PromptTokens = integerField("promptTokens=", in: turn1Line)
        XCTAssertGreaterThan(turn1PromptTokens, 1000, "Turn 1: \(turn1Line)")

        let assistantText = try assistantText(from: firstJSON, raw: firstText)

        // ---- Turn 2: replay Turn 1's chain, continue from the settled child -
        // The gate appends ITS recovered value, so the replayed chain must be
        // exactly Turn 1's [user, recovered, assistant] triple.
        let offset2 = traceSize()
        let (secondJSON, secondText, secondStatus, secondSeconds) = try await responses(
            messages: [
                ["role": "user", "content": turn1Prompt],
                ["role": "user", "content": anchorValue],
                ["role": "assistant", "content": assistantText],
            ],
            anchor: childES, settle: true)
        XCTAssertEqual(secondStatus, 200, secondText)
        let window2 = traceWindow(since: offset2)

        // (1) the IS settlement of Turn 1's child carried KV authority for this
        // admission. The settlement transaction writes BOTH kv rows
        // (kv.cache_fingerprint + kv.pool_key), so the admitted count is the
        // product's own authority quantum — assert it is non-zero, not a
        // hand-picked number.
        let admitted2 = try XCTUnwrap(
            window2.split(separator: "\n").first {
                $0.contains("continuation_admitted") && $0.contains("parent=\(childES)")
            },
            "Turn 2 was not admitted against Turn 1's child ES: \(window2)")
        XCTAssertGreaterThan(
            integerField("kvBindings=", in: admitted2), 0,
            "Turn 2 admission carried no settled KV binding: \(admitted2)")

        // (2) the bind site accepted the pooled artifact under that authority,
        // and the artifact it bound is byte-for-byte the one Turn 1 exported.
        XCTAssertFalse(
            window2.contains("isKvBindRejected"),
            "IS authority refused the bind: \(window2)")
        let turn2BindHash = try XCTUnwrap(
            refHash(onLineWith: "poolBind ", in: window2),
            "No poolBind: the governed turn consumed no bound prefix: \(window2)")
        XCTAssertEqual(
            turn2BindHash, turn1ExportHash,
            "Turn 2 bound a different artifact than Turn 1 exported")

        // (3) the engine PAID ONLY THE DELTA. This is the anti-recomputation claim.
        // The old turn's live session is gone (the branch fork is refused for
        // "no live source session"), so nothing in Turn 1's process cache could
        // have served this — the bound prefix came from the pooled artifact the
        // IS settlement authorised.
        XCTAssertTrue(
            window2.contains("no live source session"),
            "Turn 2 still had Turn 1's live session available: \(window2)")
        let turn2Line = try completionLine(in: window2, requestTag: "Turn 2")
        XCTAssertTrue(
            turn2Line.contains("mode=restore"),
            "Turn 2 did not restore the bound boundary: \(turn2Line)")
        let turn2Delta = integerField("promptTokens=", in: turn2Line)
        XCTAssertGreaterThan(turn2Delta, 0, "Turn 2: \(turn2Line)")
        XCTAssertLessThan(
            turn2Delta, turn1PromptTokens / 2,
            "Turn 2 re-prefilled the settled prefix: Δ\(turn2Delta) vs cold \(turn1PromptTokens)")
        XCTAssertGreaterThan(
            integerField("cacheHitTokens=", in: turn2Line), 0, "Turn 2: \(turn2Line)")

        // ---- report the ratio in the failure-free case too ------------------
        let ratio = secondSeconds / max(firstSeconds, 0.001)
        print("""
        [A9] turn1 status=\(firstStatus) promptTokens=\(turn1PromptTokens) \
        seconds=\(String(format: "%.2f", firstSeconds)) child=\(childES) \
        export=\(turn1ExportHash)
        [A9] turn2 status=\(secondStatus) delta=\(turn2Delta) \
        seconds=\(String(format: "%.2f", secondSeconds)) wallRatio=\(String(format: "%.3f", ratio)) \
        bind=\(turn2BindHash) \
        kvBindings=\(integerField("kvBindings=", in: admitted2)) \
        cacheHit=\(integerField("cacheHitTokens=", in: turn2Line))
        [A9] turn1 line: \(turn1Line)
        [A9] turn2 line: \(turn2Line)
        """)
        _ = runtime
    }

    // MARK: - goal step 4: the refusal half, on the SAME governed path

    /// Corrupt every pool sidecar declaration under the prefix-pool root: the
    /// recorded model identity in each declaration no longer describes the
    /// artifact next to it. The IS settlement is left untouched and still VALID,
    /// so the admission grants the bind — this is the case where authority is
    /// correct and only the physical object is wrong.
    private func tamperPoolDeclarations() throws -> [String] {
        let fm = FileManager.default
        let root = SimiGoRuntimeCachePaths.prefixPoolRoot
        let namespaces = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { $0.hasDirectoryPath } ?? []
        var tampered: [String] = []
        for namespace in namespaces {
            let names = (try? fm.contentsOfDirectory(atPath: namespace.path)) ?? []
            for name in names where name.hasSuffix(".json") {
                let url = namespace.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      var declaration = (try? JSONSerialization.jsonObject(with: data))
                        as? [String: Any] else { continue }
                declaration["modelID"] = "tampered/model-id-a9-negative"
                try JSONSerialization.data(withJSONObject: declaration).write(to: url)
                tampered.append(name)
            }
        }
        return tampered
    }

    /// A-9 negative batch: a governed continuation whose IS authority is granted
    /// but whose pooled representation has been tampered with must NOT restore.
    /// The engine re-pays the whole prefix — a wrong artifact being consumed would
    /// be worse than a slow turn, and "output identical / prefix exists / DB read
    /// succeeded" is not what this asserts.
    func testZGovernedContinuationRefusesTamperedPoolDeclaration() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let tamperValue = "A9-TAMPER-KV-7302"
        let anchor = try await MainActor.run { try stageSettledAnchor(value: tamperValue) }
        activePort = tamperPort
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        // ---- Turn 1: cold compute + settlement, exactly as the positive batch --
        let turn1Prompt = document + "\n\nQuestion: what is the run token?\n"
            + "Answer with exactly this single line and nothing else: RESULT=\(tamperValue)"
        let offset1 = traceSize()
        let (firstJSON, firstText, firstStatus, firstSeconds) = try await responses(
            messages: [["role": "user", "content": turn1Prompt]],
            anchor: anchor, settle: true)
        XCTAssertEqual(firstStatus, 200, firstText)
        let window1 = traceWindow(since: offset1)
        let settlement = try XCTUnwrap(
            firstJSON["continuation_settlement"] as? [String: Any],
            "no continuation_settlement object in the response: \(firstText)")
        let childES = try XCTUnwrap(
            settlement["child_es_state_id"] as? String, firstText)
        XCTAssertTrue(window1.contains("poolExport"), window1)
        let exportHash = try XCTUnwrap(
            refHash(onLineWith: "poolExport ", in: window1), window1)
        let turn1Line = try completionLine(in: window1, requestTag: "Turn 1")
        let turn1PromptTokens = integerField("promptTokens=", in: turn1Line)
        XCTAssertGreaterThan(turn1PromptTokens, 1000, "Turn 1: \(turn1Line)")
        let assistantText = try assistantText(from: firstJSON, raw: firstText)

        // ---- INJECT: every pool declaration now lies about its artifact --------
        let tampered = try tamperPoolDeclarations()
        XCTAssertFalse(
            tampered.isEmpty,
            "no pool sidecar present to tamper — the injection never happened")

        // ---- Turn 2: same governed replay, authority granted, object corrupt ---
        let offset2 = traceSize()
        let (_, secondText, secondStatus, secondSeconds) = try await responses(
            messages: [
                ["role": "user", "content": turn1Prompt],
                ["role": "user", "content": tamperValue],
                ["role": "assistant", "content": assistantText],
            ],
            anchor: childES, settle: true)
        XCTAssertEqual(secondStatus, 200, secondText)
        let window2 = traceWindow(since: offset2)

        // (1) the grant is REAL — otherwise this batch would only show that an
        // unauthorised turn refuses, which §3.14 already measured.
        let admitted = try XCTUnwrap(
            window2.split(separator: "\n").first {
                $0.contains("continuation_admitted") && $0.contains("parent=\(childES)")
            },
            "Turn 2 was not admitted against Turn 1's child ES: \(window2)")
        XCTAssertGreaterThan(
            integerField("kvBindings=", in: admitted), 0,
            "Turn 2 admission carried no KV authority, so the injection tested "
                + "the wrong boundary: \(admitted)")

        // (2) the tampered object was NOT bound.
        XCTAssertFalse(
            window2.contains("poolBind messages="),
            "Turn 2 bound a pool entry whose declaration was tampered: \(window2)")

        // (3) the turn FAIL-CLOSED to a full cold prefill — the model paid the
        // whole settled prefix again instead of consuming the wrong artifact.
        let turn2Line = try completionLine(in: window2, requestTag: "Turn 2")
        XCTAssertTrue(
            turn2Line.contains("mode=cold"),
            "Turn 2 did not fall back to cold: \(turn2Line)")
        let turn2PromptTokens = integerField("promptTokens=", in: turn2Line)
        XCTAssertGreaterThanOrEqual(
            Double(turn2PromptTokens), Double(turn1PromptTokens) * 0.9,
            "Turn 2 consumed a prefix the pool could not vouch for: "
                + "\(turn2PromptTokens) vs cold \(turn1PromptTokens)")

        let rejected = window2.split(separator: "\n").filter {
            $0.contains("isKvBindRejected") || $0.contains("poolBindFailed")
                || $0.contains("poolTokenHitRejected")
        }
        let ratio = secondSeconds / max(firstSeconds, 0.001)
        print("""
        [A9-NEG] tamperedSidecars=\(tampered.count) turn1=\(turn1PromptTokens) \
        child=\(childES) export=\(exportHash)
        [A9-NEG] turn2 promptTokens=\(turn2PromptTokens) seconds=\(String(format: "%.2f", secondSeconds)) \
        wallRatio=\(String(format: "%.3f", ratio))
        [A9-NEG] rejection lines: \(rejected.isEmpty ? "NONE (pool simply missed)" : rejected.joined(separator: " ;; "))
        [A9-NEG] turn2 line: \(turn2Line)
        """)
        _ = runtime
    }

    // MARK: - A-11: restore across a PROCESS restart

    /// The strongest available reading for "settled computation detached from the
    /// old KV cache's lifetime": the process that computed and settled Turn 1 is
    /// GONE before Turn 2 is asked. Nothing in-memory (sessions, engine caches,
    /// pool objects) can be what Turn 2 consumes; only the authoritative SQLite
    /// rows and the on-disk pool artifacts survive into the second process.
    ///
    /// Two selections, two processes, one window, one isolation root:
    ///   -only-testing:.../GovernedContinuationKVRestoreRealModelE2ETests/testA11ProcessA...
    ///   -only-testing:.../GovernedContinuationKVRestoreRealModelE2ETests/testA11ProcessB...
    /// The runner hands the exchange file path through `SIMIGO_A11_HANDOFF`; with
    /// out it both tests skip, so the single-process batches above stay intact.
    private let restartPort = 18_475

    private var handoffURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["SIMIGO_A11_HANDOFF"] else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func writeHandoff(_ fields: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: fields).write(to: url)
    }

    private func readHandoff(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "handoff at \(url.path) is not a JSON object")
    }

    /// Process A: compute + settle under the governed entry point, then hand the
    /// settled child ES and the exact replay chain to process B and die.
    func testA11ProcessAGovernedTurnOneHandsOffSettledChild() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let handoff = try XCTUnwrap(
            handoffURL, "SIMIGO_A11_HANDOFF is not set — run this selection via build/a11")
        let restartValue = "A11-RESTART-KV-7401"
        let anchor = try await MainActor.run { try stageSettledAnchor(value: restartValue) }
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        let turn1Prompt = document + "\n\nQuestion: what is the run token?\n"
            + "Answer with exactly this single line and nothing else: RESULT=\(restartValue)"
        let offset1 = traceSize()
        let (firstJSON, firstText, firstStatus, firstSeconds) = try await responses(
            messages: [["role": "user", "content": turn1Prompt]],
            anchor: anchor, settle: true)
        XCTAssertEqual(firstStatus, 200, firstText)
        let window1 = traceWindow(since: offset1)
        let settlement = try XCTUnwrap(
            firstJSON["continuation_settlement"] as? [String: Any],
            "no continuation_settlement in the response: \(firstText)")
        let childES = try XCTUnwrap(
            settlement["child_es_state_id"] as? String, firstText)
        XCTAssertTrue(
            window1.contains("poolExport"),
            "Turn 1 exported nothing to bind later: \(window1)")
        let exportHash = try XCTUnwrap(
            refHash(onLineWith: "poolExport ", in: window1), window1)
        let turn1Line = try completionLine(in: window1, requestTag: "Turn 1 A-11")
        let turn1PromptTokens = integerField("promptTokens=", in: turn1Line)
        XCTAssertGreaterThan(turn1PromptTokens, 1000, String(turn1Line))
        // The session carrying this turn's in-memory KV is released before the
        // process exits, so process B cannot inherit it even in principle.
        XCTAssertTrue(
            window1.contains("RELEASED"),
            "Turn 1 released no session: \(window1)")
        let assistantText = try assistantText(from: firstJSON, raw: firstText)

        try writeHandoff([
            "value": restartValue,
            "turn1Prompt": turn1Prompt,
            "assistantText": assistantText,
            "childES": childES,
            "exportHash": exportHash,
            "turn1PromptTokens": turn1PromptTokens,
            "turn1Seconds": firstSeconds,
        ], to: handoff)
        print("""
        [A11-P1] turn1 status=\(firstStatus) promptTokens=\(turn1PromptTokens) \
        seconds=\(String(format: "%.2f", firstSeconds)) child=\(childES) \
        export=\(exportHash)
        [A11-P1] turn1 line: \(turn1Line)
        """)
        _ = runtime
    }

    /// Process B: a brand new engine, a brand new ES, a settled parent it never
    /// computed. Restore here means the IS-authorised on-disk artifact is doing
    /// the work.
    func testA11ProcessBRestoresSettledKVAfterProcessRestart() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let handoff = try XCTUnwrap(
            handoffURL, "SIMIGO_A11_HANDOFF is not set — run this selection via build/a11")
        let fields = try readHandoff(from: handoff)
        let restartValue = try XCTUnwrap(fields["value"] as? String)
        let turn1Prompt = try XCTUnwrap(fields["turn1Prompt"] as? String)
        let assistantText = try XCTUnwrap(fields["assistantText"] as? String)
        let childES = try XCTUnwrap(fields["childES"] as? String)
        let exportHash = try XCTUnwrap(fields["exportHash"] as? String)
        let turn1PromptTokens = try XCTUnwrap(fields["turn1PromptTokens"] as? NSNumber).intValue
        let turn1Seconds = try XCTUnwrap(fields["turn1Seconds"] as? NSNumber).doubleValue

        // Everything this process appends from here on — including engine startup.
        // `poolRescan` is emitted lazily by NativeMLXPrefixPool.makeStore(), so it
        // can land before the turn window; the restart claim only needs the fact
        // that THIS process had to re-register the disk boundaries at all, because
        // its in-memory pool index started empty.
        let offsetB0 = traceSize()
        activePort = restartPort
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        let offset2 = traceSize()
        let (secondJSON, secondText, secondStatus, secondSeconds) = try await responses(
            messages: [
                ["role": "user", "content": turn1Prompt],
                ["role": "user", "content": restartValue],
                ["role": "assistant", "content": assistantText],
            ],
            anchor: childES, settle: true)
        XCTAssertEqual(secondStatus, 200, secondText)
        let window2 = traceWindow(since: offset2)

        // (1) admitted against the previous PROCESS's settled child.
        let admitted = try XCTUnwrap(
            window2.split(separator: "\n").first {
                $0.contains("continuation_admitted") && $0.contains("parent=\(childES)")
            },
            "Turn 2 was not admitted against the handed-off child ES: \(window2)")
        XCTAssertGreaterThan(
            integerField("kvBindings=", in: admitted), 0,
            "the settlement written by process A carried no KV authority: \(admitted)")

        // (2) THIS process re-registered the on-disk boundaries into a pool whose
        // in-memory index was empty — the artifact cannot have been computed here.
        let windowB = traceWindow(since: offsetB0)
        let rescan = windowB.split(separator: "\n").first { $0.contains("poolRescan") }
        XCTAssertNotNil(rescan, "no pool rescan in process B's trace: \(windowB)")

        // (3) the bound object is the one process A exported (content hash).
        XCTAssertTrue(
            window2.contains("poolHit messages="),
            "Turn 2 missed the pool after the restart: \(window2)")
        XCTAssertTrue(
            window2.contains("poolBind messages="),
            "Turn 2 bound nothing after the restart: \(window2)")
        let bindHash = try XCTUnwrap(
            refHash(onLineWith: "poolBind ", in: window2), window2)
        XCTAssertEqual(
            bindHash, exportHash,
            "Turn 2 bound a different artifact than process A exported")
        XCTAssertFalse(
            window2.contains("isKvBindRejected"),
            "the restart turn was rejected by the bind authority: \(window2)")

        // (4) computation avoided: restore, not cold, and a delta far below the
        // cold prefill process A paid.
        let turn2Line = try completionLine(in: window2, requestTag: "Turn 2 A-11")
        XCTAssertTrue(turn2Line.contains("mode=restore"), String(turn2Line))
        let turn2PromptTokens = integerField("promptTokens=", in: turn2Line)
        XCTAssertLessThan(
            turn2PromptTokens, turn1PromptTokens / 2,
            "Turn 2 re-paid too much of the settled prefix: \(turn2Line)")
        XCTAssertGreaterThan(
            integerField("cacheHitTokens=", in: turn2Line), 0, String(turn2Line))
        _ = secondJSON

        let ratio = secondSeconds / max(turn1Seconds, 0.001)
        print("""
        [A11-P2] rescan: \(rescan ?? "NONE")
        [A11-P2] rescan_in_turn_window=\(window2.contains("poolRescan")) \
        rescan_in_process_window=\(windowB.contains("poolRescan"))
        [A11-P2] admitted: \(admitted)
        [A11-P2] turn2 bind=\(bindHash) export=\(exportHash) child=\(childES) \
        promptTokens=\(turn2PromptTokens) cacheHit=\(integerField("cacheHitTokens=", in: turn2Line)) \
        seconds=\(String(format: "%.2f", secondSeconds)) wallRatio=\(String(format: "%.3f", ratio))
        [A11-P2] turn2 line: \(turn2Line)
        """)
        _ = runtime
    }

    // MARK: - A-12: the remaining goal-step-4 injections, governed path

    /// A-12 runs in the SAME process and window as the A-9 positive batch, so each
    /// batch needs its own listener (the previous runtime's `stop()` is
    /// fire-and-forget and would otherwise contend).
    private let invalidatePort = 18_476
    private let identityPort = 18_477

    @MainActor
    private func isDatabase() throws -> SimiGoESISDatabase {
        try XCTUnwrap(
            ExecutionStateGraphStore().esis,
            "the product's authoritative ES/IS database is not open")
    }

    /// Stage an anchor whose settlement records the producer identity re-derived
    /// from `producerPath`, and return the settlement the admission will read.
    /// `settleProducerResult` does not police WHO it is told produced the value —
    /// the mismatch is enforced where it belongs, at IS admission, by the
    /// consumer's own identity.
    @MainActor
    private func stageSettledAnchor(value: String, producerPath: String)
        throws -> (anchorID: String, settlementID: String, bindings: [String: String])
    {
        let store = ExecutionStateGraphStore()
        let producer = SimiGoProducerIdentity.identity(fromPath: producerPath)
        let root = try store.create()
        try store.continueState(root, input: value)
        let state = try XCTUnwrap(store.state(root.id))
        _ = try store.settleProducerResult(
            generatedText: "RESULT=\(value)",
            boundToState: state,
            producerIdentity: producer)
        let db = try XCTUnwrap(store.esis, "IS database unavailable while staging")
        let sid = try XCTUnwrap(
            db.latestSettlementID(forStateID: state.id),
            "staging produced no settlement row for \(state.id)")
        return (state.id, sid, try db.settlementBindings(settlementID: sid))
    }

    /// 缺失结算, done with the product's OWN invalidation API rather than a
    /// hand-deleted row: mark the settlement Turn 1 just wrote invalid (with its
    /// dependent closure) and leave the pool artifact + identity bindings alone.
    /// The next admission must therefore hit `Refusal.invalidated`, which is the
    /// authority boundary — not the physical object boundary A-10 measured.
    @MainActor
    private func invalidateSettlement(ofStateID stateID: String) throws
        -> (settlementID: String, cascade: [String], validityBefore: String, validityAfter: String)
    {
        let db = try isDatabase()
        let sid = try XCTUnwrap(
            db.latestSettlementID(forStateID: stateID),
            "no settlement recorded for \(stateID) — nothing to invalidate")
        let before = try db.settlementValidity(sid)
        let cascade = try db.invalidateSettlement(sid)
        return (sid, cascade, before, try db.settlementValidity(sid))
    }

    /// A plain non-continuation turn on the SAME running engine. Its only job is to
    /// prove the refusal below was about the anchor, not about a dead runtime: if
    /// the engine still answers an ordinary request, an implementation that quietly
    /// fell back to normal generation for a bad anchor would be caught here.
    private func plainResponses(prompt: String) async throws
        -> (text: String, status: Int)
    {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "governed-kv-e2e",
            "input": [["role": "user", "content": prompt]],
            "stream": false,
        ])
        let (data, response) = try await LOCALBAuthorizedE2E.send(
            host: host, port: activePort, method: "POST",
            path: "/v1/responses", contentType: "application/json", body: body)
        return (String(decoding: data, as: UTF8.self), response.statusCode)
    }

    private func refusalProbe(_ window: String, parent: String) -> [Substring] {
        window.split(separator: "\n").filter {
            $0.contains("continuation_admitted") && $0.contains("parent=\(parent)")
        }
    }

    /// A-12 injection 1 (goal step 4, 「缺失结算」): after a genuinely settled,
    /// governed Turn 1, the settlement is invalidated by the product's own
    /// cascade API. Turn 2 must be refused BEFORE any token is produced — the
    /// settled computation is no longer authorized for reuse, even though the
    /// pooled artifact is still on disk and untouched.
    func testA12GovernedContinuationRefusesInvalidatedSettlement() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let missingValue = "A12-INVALID-SETTLEMENT-7501"
        let anchor = try await MainActor.run { try stageSettledAnchor(value: missingValue) }
        activePort = invalidatePort
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        let turn1Prompt = document + "\n\nQuestion: what is the run token?\n"
            + "Answer with exactly this single line and nothing else: RESULT=\(missingValue)"
        let offset1 = traceSize()
        let (firstJSON, firstText, firstStatus, firstSeconds) = try await responses(
            messages: [["role": "user", "content": turn1Prompt]],
            anchor: anchor, settle: true)
        XCTAssertEqual(firstStatus, 200, firstText)
        let window1 = traceWindow(since: offset1)
        let settlement = try XCTUnwrap(
            firstJSON["continuation_settlement"] as? [String: Any], firstText)
        let childES = try XCTUnwrap(settlement["child_es_state_id"] as? String, firstText)
        XCTAssertTrue(
            window1.contains("poolExport"),
            "Turn 1 exported no pooled prefix, so the injection would prove nothing: \(window1)")
        let turn1Line = try completionLine(in: window1, requestTag: "A12-1 Turn 1")
        let turn1PromptTokens = integerField("promptTokens=", in: turn1Line)
        XCTAssertGreaterThan(turn1PromptTokens, 1000, String(turn1Line))
        let assistantText = try assistantText(from: firstJSON, raw: firstText)

        let injected = try await MainActor.run {
            try invalidateSettlement(ofStateID: childES)
        }
        XCTAssertEqual(
            injected.validityBefore, "valid", "Turn 1's settlement was never valid: \(injected)")
        XCTAssertNotEqual(
            injected.validityAfter, "valid",
            "the product's own invalidation did not take: \(injected)")

        let offset2 = traceSize()
        let (_, secondText, secondStatus, _) = try await responses(
            messages: [
                ["role": "user", "content": turn1Prompt],
                ["role": "user", "content": missingValue],
                ["role": "assistant", "content": assistantText],
            ],
            anchor: childES, settle: true)
        let window2 = traceWindow(since: offset2, timeout: 2)
        XCTAssertEqual(secondStatus, 422, secondText)
        XCTAssertTrue(
            secondText.lowercased().contains("refus"),
            "expected an explicit pre-generation refusal, got: \(secondText)")
        // Nothing was admitted and nothing was computed.
        XCTAssertTrue(
            refusalProbe(window2, parent: childES).isEmpty,
            "an invalidated settlement was still admitted: \(window2)")
        XCTAssertFalse(
            window2.contains("poolBind messages="),
            "the invalidated turn bound a pooled prefix: \(window2)")
        XCTAssertFalse(
            window2.contains("promptTokens="),
            "the invalidated turn ran the model at all: \(window2)")

        // Control: the SAME engine, an ordinary request — still answers. So the 422
        // above is an authority refusal, not an unavailable runtime.
        let (controlText, controlStatus) = try await plainResponses(
            prompt: "Reply with exactly the single word: OK")
        XCTAssertEqual(controlStatus, 200, controlText)

        print("""
        [A12-INVALID] child=\(childES) settlement=\(injected.settlementID) \
        validity=\(injected.validityBefore)->\(injected.validityAfter) \
        cascade=\(injected.cascade.count)
        [A12-INVALID] turn1 promptTokens=\(turn1PromptTokens) \
        seconds=\(String(format: "%.2f", firstSeconds))
        [A12-INVALID] turn2 status=\(secondStatus) body=\(secondText)
        [A12-INVALID] control status=\(controlStatus)
        [A12-INVALID] window2: \(window2)
        """)
        _ = runtime
    }

    /// A-12 injection 2 (goal step 4, 「身份不匹配」): the anchor's settlement is
    /// VALID, its payload digest verifies, and the pooled artifact is intact — the
    /// only defect is that the recorded producer is not this runtime's model. The
    /// governed turn must be refused before generation, and must not silently
    /// generate anyway.
    func testA12GovernedContinuationRefusesMismatchedProducerIdentity() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let identityValue = "A12-IDENTITY-MISMATCH-7502"
        let foreignPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("a12-foreign-model-snapshot-7503").path
        let real = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let foreign = SimiGoProducerIdentity.identity(fromPath: foreignPath)
        XCTAssertNotEqual(
            real, foreign, "the identity injection is a no-op — nothing was mismatched")

        let staged = try await MainActor.run {
            try stageSettledAnchor(value: identityValue, producerPath: foreignPath)
        }
        let validity = try await MainActor.run {
            try self.isDatabase().settlementValidity(staged.settlementID)
        }
        XCTAssertEqual(
            validity, "valid",
            "the staged settlement must be valid: the ONLY defect is WHO produced it")

        activePort = identityPort
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        let offset1 = traceSize()
        let (_, firstText, firstStatus, _) = try await responses(
            messages: [["role": "user", "content":
                "Question: what is the run token?\n"
                + "Answer with exactly this single line and nothing else: RESULT=\(identityValue)"]],
            anchor: staged.anchorID, settle: true)
        let window1 = traceWindow(since: offset1, timeout: 2)
        XCTAssertEqual(firstStatus, 422, firstText)
        XCTAssertTrue(
            firstText.lowercased().contains("refus"),
            "expected an explicit pre-generation refusal, got: \(firstText)")
        XCTAssertTrue(
            refusalProbe(window1, parent: staged.anchorID).isEmpty,
            "a mismatched producer identity was admitted: \(window1)")
        XCTAssertFalse(
            window1.contains("poolBind messages="),
            "the identity-refused turn bound a prefix: \(window1)")
        XCTAssertFalse(
            window1.contains("promptTokens="),
            "the identity-refused turn ran the model at all: \(window1)")

        let (controlText, controlStatus) = try await plainResponses(
            prompt: "Reply with exactly the single word: OK")
        XCTAssertEqual(controlStatus, 200, controlText)

        print("""
        [A12-IDENTITY] anchor=\(staged.anchorID) settlement=\(staged.settlementID) \
        validity=\(validity)
        [A12-IDENTITY] real.model=\(real.model) foreign.model=\(foreign.model)
        [A12-IDENTITY] recordedBindings=\(staged.bindings)
        [A12-IDENTITY] status=\(firstStatus) body=\(firstText)
        [A12-IDENTITY] control status=\(controlStatus)
        [A12-IDENTITY] window1: \(window1)
        """)
        _ = runtime
    }

    // MARK: - A-13: dependency change, on the governed KV continuation path

    /// §3.19 closed the invalidated-settlement and producer-identity injections;
    /// the fourth class in the acceptance chain (a physical-file dependency change)
    /// had only ever been replayed on the IS retrieval settlement path. These two
    /// selections put it on the governed KV continuation path.
    ///
    /// Everything is the product's own surface: `settleWorkRootContents` indexes and
    /// content-addresses a real work root, `linkSettlementToExternalFile` writes the
    /// settlement -> file binding whose closure the product walks when a file
    /// changes, and `addDependency` writes the settlement -> settlement edge that
    /// admission's upstream closure walks. Re-running the settle pass over the
    /// edited file is the same call the settings-page reconcile makes per root.
    /// Nothing here pokes the database by hand.
    ///
    /// HONEST SCOPE (this is also what task #28 records as the gap): the governed
    /// continuation settlement transaction itself writes no file dependency edge
    /// (`recordNativeSettlementWithIdentity` passes `advancement: nil`), so the edge
    /// from the model's settled turn to the upstream IS settlement is declared here
    /// with the product's own `addDependency`. This batch measures "does a changed
    /// physical dependency stop the settled computation from being re-consumed" —
    /// not "does the continuation settlement wire itself up".
    private let dependencyPort = 18_478
    private let dependencyCleanPort = 18_479

    private struct A13Fixture {
        let rootID: String
        let rootURL: URL
        let fileA: String
        let fileB: String
        let anchorA: String
        let settlementA: String
        let settlementB: String
        // The revision counter must read the PHYSICAL FILE identity
        // ("file:<root>/<rel>"), which is where settleWorkRootContents appends
        // content-settle/content-update revisions. The "settlement:<sid> -> file:..."
        // identity only gains a revision when the edge is linked, not when the file
        // changes, so it cannot witness a content change.
        let revisionsA: Int
        let revisionsB: Int
        let validityA: String
        let validityB: String
        let scanned: Int
        let settled: Int
        let objectsCreated: Int
    }

    @MainActor
    private func stageA13Fixture(value: String) throws -> A13Fixture {
        let fm = FileManager.default
        let token = String(UUID().uuidString.prefix(8))
        let rootID = "a13-\(token)"
        let rootURL = fm.temporaryDirectory.appendingPathComponent("a13-root-\(token)")
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileA = "dep-a-\(token).md"
        let fileB = "dep-b-\(token).md"
        try """
        SimiGo A-13 upstream source A (this file is the dependency that changes).
        value=\(value)-A-v1
        """.write(
            to: rootURL.appendingPathComponent(fileA), atomically: true, encoding: .utf8)
        try """
        SimiGo A-13 upstream source B (this file stays byte-identical).
        value=\(value)-B-v1
        """.write(
            to: rootURL.appendingPathComponent(fileB), atomically: true, encoding: .utf8)

        let db = try isDatabase()
        let report = try db.settleWorkRootContents(
            rootID: rootID, rootURL: rootURL, category: "a13work", carryText: true)
        let stagedA = try stageSettledAnchor(value: "\(value)-A", producerPath: modelPath)
        let stagedB = try stageSettledAnchor(value: "\(value)-B", producerPath: modelPath)
        try db.linkSettlementToExternalFile(
            settlementID: stagedA.settlementID, binding: "a13-source-a",
            rootID: rootID, relativePath: fileA)
        try db.linkSettlementToExternalFile(
            settlementID: stagedB.settlementID, binding: "a13-source-b",
            rootID: rootID, relativePath: fileB)

        let fileLedgerA = "file:\(rootID)/\(fileA)"
        let fileLedgerB = "file:\(rootID)/\(fileB)"
        return A13Fixture(
            rootID: rootID, rootURL: rootURL, fileA: fileA, fileB: fileB,
            anchorA: stagedA.anchorID,
            settlementA: stagedA.settlementID, settlementB: stagedB.settlementID,
            revisionsA: try db.dependencyHistory(fileLedgerA).count,
            revisionsB: try db.dependencyHistory(fileLedgerB).count,
            validityA: try db.settlementValidity(stagedA.settlementID),
            validityB: try db.settlementValidity(stagedB.settlementID),
            scanned: report.scanned, settled: report.settled,
            objectsCreated: report.objectsCreated)
    }

    @MainActor
    private func a13ChildSettlement(forStateID stateID: String) throws -> String {
        let db = try isDatabase()
        return try XCTUnwrap(
            db.latestSettlementID(forStateID: stateID),
            "the governed Turn 1 wrote no settlement row for \(stateID)")
    }

    @MainActor
    private func a13DeclareDependency(from childSettlement: String, to upstream: String) throws {
        try isDatabase().addDependency(
            fromSettlement: childSettlement, toSettlement: upstream, kind: "a13-input")
    }

    @MainActor
    private func a13Validities(childSettlement: String, fixture: A13Fixture) throws
        -> (child: String, upstreamA: String, upstreamB: String,
            revisionsA: Int, revisionsB: Int) {
        let db = try isDatabase()
        return (
            try db.settlementValidity(childSettlement),
            try db.settlementValidity(fixture.settlementA),
            try db.settlementValidity(fixture.settlementB),
            try db.dependencyHistory("file:\(fixture.rootID)/\(fixture.fileA)").count,
            try db.dependencyHistory("file:\(fixture.rootID)/\(fixture.fileB)").count)
    }

    /// INJECT: rewrite dep-a on disk, then let the product's own content-settle pass
    /// re-detect it and run its invalidation closure.
    @MainActor
    private func a13ChangeDependencyA(fixture: A13Fixture, value: String) throws
        -> (changed: Int, invalidatedSettlements: Int) {
        try """
        SimiGo A-13 upstream source A (this file is the dependency that changes).
        value=\(value)-A-v2-INJECTED-CHANGE
        """.write(
            to: fixture.rootURL.appendingPathComponent(fixture.fileA),
            atomically: true, encoding: .utf8)
        let report = try isDatabase().settleWorkRootContents(
            rootID: fixture.rootID, rootURL: fixture.rootURL,
            category: "a13work", carryText: true)
        return (report.changed, report.invalidatedSettlements)
    }

    /// The governed continuation whose settled prefix depends on a physical file
    /// that has since changed must be refused before any token, and the pooled
    /// artifact of that dead computation must not be re-consumed.
    func testA13GovernedContinuationRefusesChangedFileDependency() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let depValue = "A13-DEP-CHANGE-7601"
        let fixture = try await MainActor.run { try stageA13Fixture(value: depValue) }
        XCTAssertEqual(fixture.validityA, "valid", "upstream A must start valid")
        XCTAssertEqual(fixture.validityB, "valid", "upstream B must start valid")
        XCTAssertGreaterThan(
            fixture.revisionsA, 0,
            "linkSettlementToExternalFile wrote no dependency ledger — the carried "
                + "content or the dependency_id convention differs")

        activePort = dependencyPort
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        let turn1Prompt = document + "\n\nQuestion: what is the run token?\n"
            + "Answer with exactly this single line and nothing else: RESULT=\(depValue)"
        let offset1 = traceSize()
        let (firstJSON, firstText, firstStatus, firstSeconds) = try await responses(
            messages: [["role": "user", "content": turn1Prompt]],
            anchor: fixture.anchorA, settle: true)
        XCTAssertEqual(firstStatus, 200, firstText)
        let window1 = traceWindow(since: offset1)
        let settlement = try XCTUnwrap(
            firstJSON["continuation_settlement"] as? [String: Any],
            "no continuation_settlement object in the response: \(firstText)")
        let childES = try XCTUnwrap(
            settlement["child_es_state_id"] as? String, firstText)
        XCTAssertTrue(window1.contains("poolExport"), window1)
        let exportHash = try XCTUnwrap(
            refHash(onLineWith: "poolExport ", in: window1), window1)
        let turn1Line = try completionLine(in: window1, requestTag: "Turn 1 A-13")
        let turn1PromptTokens = integerField("promptTokens=", in: turn1Line)
        XCTAssertGreaterThan(turn1PromptTokens, 1000, String(turn1Line))
        let assistantText = try assistantText(from: firstJSON, raw: firstText)

        let childSettlement = try await MainActor.run {
            try self.a13ChildSettlement(forStateID: childES)
        }
        try await MainActor.run {
            try self.a13DeclareDependency(
                from: childSettlement, to: fixture.settlementA)
        }
        let before = try await MainActor.run {
            try self.a13Validities(childSettlement: childSettlement, fixture: fixture)
        }
        XCTAssertEqual(
            before.child, "valid",
            "the settled continuation turn must be valid before the injection")

        let injected = try await MainActor.run {
            try self.a13ChangeDependencyA(fixture: fixture, value: depValue)
        }
        XCTAssertGreaterThanOrEqual(injected.changed, 1, "no file change detected")
        let after = try await MainActor.run {
            try self.a13Validities(childSettlement: childSettlement, fixture: fixture)
        }
        // (1) the closure reached the model's settled turn transitively ...
        XCTAssertNotEqual(after.child, "valid", "child settlement stayed valid")
        XCTAssertNotEqual(after.upstreamA, "valid", "file-bound settlement stayed valid")
        // ... and only there: the settlement bound to the untouched file survives.
        XCTAssertEqual(
            after.upstreamB, "valid",
            "an unrelated settlement was dragged into the invalidation closure")
        XCTAssertGreaterThan(
            after.revisionsA, before.revisionsA,
            "no new dependency revision was appended for the changed file")
        XCTAssertEqual(
            after.revisionsB, before.revisionsB,
            "the untouched file appended a dependency revision anyway")

        let offset2 = traceSize()
        // The gate appends the RECOVERED anchor value, which is the fixture's
        // staged value ("<value>-A"), so the replayed chain must carry that exact
        // string — otherwise the message-chain pool lookup cannot match and the
        // turn falls back to token-level reuse no matter what the dependency says.
        let (_, secondText, secondStatus, _) = try await responses(
            messages: [
                ["role": "user", "content": turn1Prompt],
                ["role": "user", "content": "\(depValue)-A"],
                ["role": "assistant", "content": assistantText],
            ],
            anchor: childES, settle: true)
        XCTAssertEqual(
            secondStatus, 422,
            "a continuation whose IS dependency changed was not refused: \(secondText)")
        XCTAssertTrue(
            secondText.lowercased().contains("refus"),
            "expected an explicit pre-generation refusal, got: \(secondText)")
        let window2 = traceWindow(since: offset2, timeout: 2)
        XCTAssertTrue(
            refusalProbe(window2, parent: childES).isEmpty,
            "a changed dependency was admitted: \(window2)")
        XCTAssertFalse(
            window2.contains("poolBind messages="),
            "Turn 2 bound a prefix whose dependency changed: \(window2)")
        XCTAssertFalse(
            window2.contains("promptTokens="),
            "the changed-dependency turn ran the model at all: \(window2)")

        let (controlText, controlStatus) = try await plainResponses(
            prompt: "Reply with exactly the single word: OK")
        XCTAssertEqual(controlStatus, 200, controlText)

        print("""
        [A13-DEP] root=\(fixture.rootID) scanned=\(fixture.scanned) \
        settled=\(fixture.settled) objects=\(fixture.objectsCreated) \
        ledgerA=\(fixture.revisionsA) ledgerB=\(fixture.revisionsB)
        [A13-DEP] child=\(childES) childSettlement=\(childSettlement) \
        upstreamA=\(fixture.settlementA) upstreamB=\(fixture.settlementB)
        [A13-DEP] validity child=\(before.child)->\(after.child) \
        upstreamA=\(after.upstreamA) upstreamB=\(after.upstreamB)
        [A13-DEP] revisionsA=\(before.revisionsA)->\(after.revisionsA) \
        revisionsB=\(before.revisionsB)->\(after.revisionsB) \
        report changed=\(injected.changed) invalidatedSettlements=\(injected.invalidatedSettlements)
        [A13-DEP] turn1 promptTokens=\(turn1PromptTokens) export=\(exportHash) \
        seconds=\(String(format: "%.2f", firstSeconds))
        [A13-DEP] turn2 status=\(secondStatus) body=\(secondText)
        [A13-DEP] control status=\(controlStatus)
        """)
        _ = runtime
    }

    /// Same chain, dependency NOT changed: the continuation must still restore. This
    /// is what turns the refusal above into a causal reading — the declared edge does
    /// not break restore; only a changed physical premise does. It is also the model
    /// level reading for "an unchanged dependency's settled result really is reused".
    func testA13GovernedContinuationRestoresWithUnchangedFileDependency() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let keepValue = "A13-DEP-UNCHANGED-7602"
        let fixture = try await MainActor.run { try stageA13Fixture(value: keepValue) }
        activePort = dependencyCleanPort
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }

        let turn1Prompt = document + "\n\nQuestion: what is the run token?\n"
            + "Answer with exactly this single line and nothing else: RESULT=\(keepValue)"
        let offset1 = traceSize()
        let (firstJSON, firstText, firstStatus, firstSeconds) = try await responses(
            messages: [["role": "user", "content": turn1Prompt]],
            anchor: fixture.anchorA, settle: true)
        XCTAssertEqual(firstStatus, 200, firstText)
        let window1 = traceWindow(since: offset1)
        let settlement = try XCTUnwrap(
            firstJSON["continuation_settlement"] as? [String: Any],
            "no continuation_settlement object in the response: \(firstText)")
        let childES = try XCTUnwrap(
            settlement["child_es_state_id"] as? String, firstText)
        XCTAssertTrue(window1.contains("poolExport"), window1)
        let exportHash = try XCTUnwrap(
            refHash(onLineWith: "poolExport ", in: window1), window1)
        let turn1Line = try completionLine(in: window1, requestTag: "Turn 1 A-13 KEEP")
        let turn1PromptTokens = integerField("promptTokens=", in: turn1Line)
        XCTAssertGreaterThan(turn1PromptTokens, 1000, String(turn1Line))
        let assistantText = try assistantText(from: firstJSON, raw: firstText)

        let childSettlement = try await MainActor.run {
            try self.a13ChildSettlement(forStateID: childES)
        }
        try await MainActor.run {
            try self.a13DeclareDependency(from: childSettlement, to: fixture.settlementA)
        }
        let state = try await MainActor.run {
            try self.a13Validities(childSettlement: childSettlement, fixture: fixture)
        }
        XCTAssertEqual(state.child, "valid", String(describing: state))
        XCTAssertEqual(state.upstreamA, "valid", String(describing: state))

        let offset2 = traceSize()
        let (_, secondText, secondStatus, secondSeconds) = try await responses(
            messages: [
                ["role": "user", "content": turn1Prompt],
                ["role": "user", "content": "\(keepValue)-A"],
                ["role": "assistant", "content": assistantText],
            ],
            anchor: childES, settle: true)
        XCTAssertEqual(secondStatus, 200, secondText)
        let window2 = traceWindow(since: offset2)
        let admitted = try XCTUnwrap(
            window2.split(separator: "\n").first {
                $0.contains("continuation_admitted") && $0.contains("parent=\(childES)")
            },
            "Turn 2 was not admitted with a valid dependency: \(window2)")
        XCTAssertGreaterThan(integerField("kvBindings=", in: admitted), 0, String(admitted))
        XCTAssertTrue(window2.contains("poolBind messages="), window2)
        let bindHash = try XCTUnwrap(refHash(onLineWith: "poolBind ", in: window2), window2)
        XCTAssertEqual(bindHash, exportHash, "bound a different artifact than exported")
        let turn2Line = try completionLine(in: window2, requestTag: "Turn 2 A-13 KEEP")
        XCTAssertTrue(turn2Line.contains("mode=restore"), String(turn2Line))
        let turn2PromptTokens = integerField("promptTokens=", in: turn2Line)
        XCTAssertLessThan(
            turn2PromptTokens, turn1PromptTokens / 2,
            "Turn 2 re-paid the settled prefix: \(turn2Line)")
        XCTAssertGreaterThan(
            integerField("cacheHitTokens=", in: turn2Line), 0, String(turn2Line))

        print("""
        [A13-KEEP] child=\(childES) childSettlement=\(childSettlement) \
        upstreamA=\(fixture.settlementA) upstreamB=\(fixture.settlementB)
        [A13-KEEP] validity child=\(state.child) upstreamA=\(state.upstreamA) \
        upstreamB=\(state.upstreamB) revisionsA=\(state.revisionsA) revisionsB=\(state.revisionsB)
        [A13-KEEP] turn2 bind=\(bindHash) export=\(exportHash) \
        promptTokens=\(turn2PromptTokens)/\(turn1PromptTokens) \
        cacheHit=\(integerField("cacheHitTokens=", in: turn2Line)) \
        seconds=\(String(format: "%.2f", secondSeconds)) \
        wallRatio=\(String(format: "%.3f", secondSeconds / max(firstSeconds, 0.001)))
        [A13-KEEP] turn2 line: \(turn2Line)
        """)
        _ = runtime
    }

    // MARK: - A-14 / goal stage A: stop prefix-pool writes with the existing switch

    /// Relative path -> byte size under the pool root. Empty when the directory
    /// does not exist, which is the expected disabled state, not an error.
    private func prefixPoolInventory() -> [String: Int] {
        let root = SimiGoRuntimeCachePaths.prefixPoolRoot
        var inventory: [String: Int] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return inventory }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true
            else { continue }
            inventory[String(url.path.dropFirst(root.path.count))] = values.fileSize ?? -1
        }
        return inventory
    }

    /// Goal stage A. ONE plain, non-continuation turn. The turn-end message-chain
    /// export has no length floor, so a short prompt still reaches the exact write
    /// site Stage A is about (`NativeMLXPrefixPool.export` -> `PrefixSnapshotStore.
    /// export`). A short prompt is deliberate: the 9.3k-token version of this test
    /// stalled this machine after prefill (swap at 11.5 GB), and the token-boundary
    /// export (which needs >2048 tokens) is gated by the SAME `prefixPoolEnabled`
    /// flag, so nothing about the switch is left unobserved.
    /// The same fixture runs in two windows and branches on the switch it observes:
    ///   * default (pool ON): the turn must leave a `poolExport` and new files —
    ///     the control proving this fixture can SEE a pool write;
    ///   * `SIMIGO_PREFIX_POOL=0`: the turn must still answer 200 with assistant
    ///     text while the pool root gains nothing and no pool marker appears.
    /// Without the control window "no new files" would be unfalsifiable: a fixture
    /// that never writes at all would read the same.
    func testA14StageAPrefixPoolSwitch() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let poolEnabled = RuntimeTuning.prefixPoolEnabled
        let runtime = try await startRealRuntime()
        let offset = traceSize()
        let before = prefixPoolInventory()
        let prompt = "Reply with exactly the single word: OK"
        let started = Date()
        let (text, status) = try await plainResponses(prompt: prompt)
        let seconds = Date().timeIntervalSince(started)
        let window = traceWindow(since: offset, timeout: 5)
        let after = prefixPoolInventory()
        let added = Set(after.keys).subtracting(before.keys).sorted()
        let removed = Set(before.keys).subtracting(after.keys).sorted()
        let addedBytes = added.reduce(0) { $0 + (after[$1] ?? 0) }

        XCTAssertEqual(status, 200, String(text.prefix(600)))
        XCTAssertTrue(text.contains("\"output\""), "no assistant output: \(String(text.prefix(600)))")
        let completion = try XCTUnwrap(
            window.split(separator: "\n").last { $0.contains("promptTokens=") },
            "no completion line for the plain turn: \(window)")
        XCTAssertTrue(completion.contains("mode=cold"))

        if poolEnabled {
            XCTAssertFalse(
                added.isEmpty,
                "pool is ON but the turn exported nothing — this fixture cannot detect a write: \(window)")
            XCTAssertTrue(
                window.contains("poolExport"),
                "pool is ON but no poolExport was traced: \(window)")
        } else {
            XCTAssertTrue(
                added.isEmpty,
                "SIMIGO_PREFIX_POOL=0 but new KV files appeared: \(added.prefix(6))")
            XCTAssertEqual(after, before, "pool root changed with the pool disabled")
            XCTAssertTrue(removed.isEmpty)
            for marker in ["poolExport", "poolHit", "poolTokenHit", "poolBind", "poolTokenExport"] {
                XCTAssertFalse(
                    window.contains(marker),
                    "\(marker) appeared with the pool disabled: \(window)")
            }
        }
        print("""
        [A14] poolEnabled=\(poolEnabled) status=\(status) \
        seconds=\(String(format: "%.2f", seconds)) addedFiles=\(added.count) \
        addedBytes=\(addedBytes) removedFiles=\(removed.count)
        [A14] inventory before=\(before.count) after=\(after.count) \
        sample=\(added.prefix(4).joined(separator: ","))
        [A14] completion: \(completion)
        [A14] poolMarkers: export=\(window.contains("poolExport")) \
        tokenExport=\(window.contains("poolTokenExport")) \
        hit=\(window.contains("poolHit")) tokenHit=\(window.contains("poolTokenHit")) \
        bind=\(window.contains("poolBind"))
        """)
        _ = runtime
    }

    // MARK: - A-15 / task #35: can a new ES continue with the prefix pool OFF?

    /// The decisive separation for goal stage A: IS admission vs a KV artifact.
    ///
    /// Same fixture, same binary, same two governed turns; the only difference
    /// between the two windows is `SIMIGO_PREFIX_POOL`. The write side is closed
    /// by the product's own guard (`NativeMLX` skips the turn-end export), so
    /// `NativeMLXPrefixPool.representation(forBranch:)` returns nil, Turn 1's
    /// settlement records no KV row, and the next admission is `kvBindings=0` by
    /// construction rather than by fixture.
    ///
    ///   * pool ON (control): Turn 1 exports, Turn 2's admission carries the KV
    ///     row and binds the SAME artifact -> `mode=restore`, small delta.
    ///   * pool OFF: Turn 2 is STILL admitted (`bindings>0`) and still settles a
    ///     second child — IS alone authorises the continuation — but the engine
    ///     re-pays the whole chain: `mode=cold`, promptTokens >= Turn 1's cold
    ///     cost, cacheHitTokens=0, and no pool file anywhere on disk.
    ///
    /// The off window is the honest answer to "can the persisted KV be dropped
    /// now": correctness survives, reuse does not, because the IS record carries
    /// the settled VALUE and its authority but not the model representation.
    private let noPoolPort = 18_480

    func testA15GovernedContinuationWithoutPrefixPool() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        let poolEnabled = RuntimeTuning.prefixPoolEnabled
        let value = "A15-NO-POOL-7901"
        let anchor = try await MainActor.run {
            try stageSettledAnchor(value: "\(value)-A", producerPath: modelPath)
        }
        activePort = noPoolPort
        let runtime = try await startRealRuntime()
        defer { Task { await runtime.stop() } }
        let poolBefore = prefixPoolInventory()

        let turn1Prompt = document + "\n\nQuestion: what is the run token?\n"
            + "Answer with exactly this single line and nothing else: RESULT=\(value)"
        let offset1 = traceSize()
        let (firstJSON, firstText, firstStatus, firstSeconds) = try await responses(
            messages: [["role": "user", "content": turn1Prompt]],
            anchor: anchor.anchorID, settle: true)
        XCTAssertEqual(firstStatus, 200, firstText)
        let window1 = traceWindow(since: offset1)
        let settlement = try XCTUnwrap(
            firstJSON["continuation_settlement"] as? [String: Any],
            "no continuation_settlement object in the response: \(firstText)")
        let childES = try XCTUnwrap(settlement["child_es_state_id"] as? String, firstText)
        XCTAssertTrue(
            window1.contains("continuation_admitted"), "Turn 1 was not admitted: \(window1)")
        XCTAssertTrue(
            window1.contains("continuation_branch child=\(childES)"),
            "Turn 1 did not execute under the child ES branch: \(window1)")
        let turn1Line = try completionLine(in: window1, requestTag: "Turn 1 A-15")
        XCTAssertTrue(turn1Line.contains("mode=cold"), String(turn1Line))
        let turn1PromptTokens = integerField("promptTokens=", in: turn1Line)
        XCTAssertGreaterThan(turn1PromptTokens, 1000, String(turn1Line))
        let assistantText = try assistantText(from: firstJSON, raw: firstText)

        // Turn 1 must settle an IS row either way; with the pool off that row is
        // the only thing the next turn can be authorised by.
        let childSettlement = try await MainActor.run {
            try self.a13ChildSettlement(forStateID: childES)
        }
        let turn1Validity = try await MainActor.run {
            try self.isDatabase().settlementValidity(childSettlement)
        }
        XCTAssertEqual(turn1Validity, "valid")

        let offset2 = traceSize()
        let (secondJSON, secondText, secondStatus, secondSeconds) = try await responses(
            messages: [
                ["role": "user", "content": turn1Prompt],
                ["role": "user", "content": "\(value)-A"],
                ["role": "assistant", "content": assistantText],
            ],
            anchor: childES, settle: true)
        XCTAssertEqual(secondStatus, 200, secondText)
        let window2 = traceWindow(since: offset2)
        let admitted = try XCTUnwrap(
            window2.split(separator: "\n").first {
                $0.contains("continuation_admitted") && $0.contains("parent=\(childES)")
            },
            "Turn 2 was not admitted from Turn 1's child ES: \(window2)")
        // Admission is the IS authority's verdict and does not consult the pool.
        XCTAssertGreaterThan(integerField("bindings=", in: admitted), 0, String(admitted))
        let turn2Line = try completionLine(in: window2, requestTag: "Turn 2 A-15")
        let turn2PromptTokens = integerField("promptTokens=", in: turn2Line)
        let turn2CacheHit = integerField("cacheHitTokens=", in: turn2Line)
        // The second child must exist as an IS settlement too: the continuation
        // completed and settled with no KV artifact to bind.
        let secondSettlement = try XCTUnwrap(
            secondJSON["continuation_settlement"] as? [String: Any], secondText)
        let secondChild = try XCTUnwrap(
            secondSettlement["child_es_state_id"] as? String, secondText)
        let secondChildSettlement = try await MainActor.run {
            try self.a13ChildSettlement(forStateID: secondChild)
        }
        let secondValidity = try await MainActor.run {
            try self.isDatabase().settlementValidity(secondChildSettlement)
        }
        XCTAssertEqual(secondValidity, "valid")
        let poolAfter = prefixPoolInventory()

        if poolEnabled {
            // Control: this fixture CAN reuse pooled state, so "nothing bound"
            // in the off window is caused by the switch, not by the fixture.
            XCTAssertTrue(window1.contains("poolExport"), window1)
            let exportHash = try XCTUnwrap(
                refHash(onLineWith: "poolExport ", in: window1), window1)
            XCTAssertGreaterThan(
                integerField("kvBindings=", in: admitted), 0, String(admitted))
            XCTAssertFalse(window2.contains("isKvBindRejected"), window2)
            XCTAssertTrue(window2.contains("poolBind messages="), window2)
            let bindHash = try XCTUnwrap(
                refHash(onLineWith: "poolBind ", in: window2), window2)
            XCTAssertEqual(bindHash, exportHash, "Turn 2 bound a different artifact than exported")
            XCTAssertTrue(turn2Line.contains("mode=restore"), String(turn2Line))
            XCTAssertLessThan(turn2PromptTokens, turn1PromptTokens / 2, String(turn2Line))
            XCTAssertGreaterThan(turn2CacheHit, 0, String(turn2Line))
        } else {
            // Write side: the turn-end export never ran.
            for marker in ["poolExport", "poolTokenExport"] {
                XCTAssertFalse(
                    window1.contains(marker), "\(marker) traced with the pool off: \(window1)")
            }
            XCTAssertTrue(
                poolBefore.isEmpty, "pool root was not empty before the turn: \(poolBefore)")
            XCTAssertEqual(poolAfter, poolBefore, "the pool root changed with the pool off")
            // No KV row was recorded by Turn 1's settlement...
            XCTAssertTrue(
                admitted.contains("kvBindings=0"),
                "Turn 1 settled a KV binding although it exported nothing: \(admitted)")
            // ...so nothing could be bound, and the whole chain is re-paid.
            for marker in ["poolHit", "poolBind", "poolTokenHit", "poolTokenExport"] {
                XCTAssertFalse(
                    window2.contains(marker), "\(marker) traced with the pool off: \(window2)")
            }
            XCTAssertTrue(turn2Line.contains("mode=cold"), String(turn2Line))
            XCTAssertGreaterThanOrEqual(
                turn2PromptTokens, turn1PromptTokens,
                "Turn 2 did not re-pay the settled prefix: \(turn2Line)")
            XCTAssertEqual(turn2CacheHit, 0, String(turn2Line))
        }

        print("""
        [A15] poolEnabled=\(poolEnabled) status1=\(firstStatus) status2=\(secondStatus)
        [A15] turn1 child=\(childES) settlement=\(childSettlement) validity=\(turn1Validity) \
        promptTokens=\(turn1PromptTokens) seconds=\(String(format: "%.2f", firstSeconds))
        [A15] turn2 child=\(secondChild) settlement=\(secondChildSettlement) \
        validity=\(secondValidity) promptTokens=\(turn2PromptTokens) \
        cacheHit=\(turn2CacheHit) seconds=\(String(format: "%.2f", secondSeconds))
        [A15] admission: \(admitted)
        [A15] poolFiles before=\(poolBefore.count) after=\(poolAfter.count) \
        export1=\(window1.contains("poolExport")) bind2=\(window2.contains("poolBind"))
        [A15] turn1 line: \(turn1Line)
        [A15] turn2 line: \(turn2Line)
        """)
        _ = runtime
    }
}
