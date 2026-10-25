import XCTest
import Foundation
import SimiGoRuntimeContract
import SimiGo2Experimental
@testable import SimiGo

/// 真实模型载体交接实验（门控，缺省 XCTSkip）。
///
/// 目的：把 c3082e6 的「载体已释放（引用解除）」升级为「结算结果脱离旧载体后
/// 仍能在新 ES 上继续执行」，并按三级事实**分别**记录，绝不合并成一句：
///
///   ① RELEASE  旧分支不再可解析：`hasLiveSessionBranch == false` +
///     `verifyCarrierUnusable` 不抛；报告里的 clearIssued/checkpointFilesDeleted
///     只作 LIFECYCLE_EVENT 记录。
///   ② RESTORE  新 ES 从 IS 恢复：**新鲜** `ExecutionStateGraphStore`（新连接、
///     只读 SQLite）读出子 ES 的血统与 settled nextInput，并以同一 producer
///     identity 重新 admission；全过程不触碰任何 ChatSession。
///   ③ CONTINUE 真实模型在新分支上续算，并用引擎实测的 cache hit / prefill
///     delta / reuse mode 说明「哪一支的 KV 被用了」；冷臂（所有载体已释放）
///     同样能续算，用于证明语义结果不依赖旧载体。**旧 KV 的物理页归还仍然
///     不可观测，本实验不宣称。**
///
/// 链路（全部走产品路径）：
///   真实 HTTP POST /v1/responses（LOCALB 授权）
///     → continuationGate → admission（SQLite IS）
///     → continuationExecutionBranch（fork：child ES id == 分支 id）
///     → 真实 MLX 生成 → settlementStep（child ES + settlement 一个事务提交）
///     → MLXRuntimeCarrierOwner 释放旧分支
///     → 新鲜 store 恢复 → 暖臂/冷臂续算
///
/// 门控：`SIMIGO_FORK_EXP=1` + `SIMIGO_FORK_MODEL=<本机 MLX 权重目录>`。
/// 建议同时 `SIMIGO_PREFIX_POOL=0`：跨会话前缀池会用别处的快照掩盖分支级复用，
/// 让「旧分支未被访问」的推断失去排他性。
final class RealModelCarrierHandoffTests: XCTestCase {

    private let port = 18_472
    private var host: LOCALBAuthorizedE2E.Host!
    private let sessionID = "handoff-" + UUID().uuidString.prefix(8).lowercased()
    private var evidence: [String: Any] = [:]
    private var generatePassesObserved: [String: Int] = [:]

    private static let value = "7143"
    private static let systemPrompt =
        "You are a precise assistant. Reply with output only. "
        + "When the user gives you a number, answer with exactly one line: RESULT=<number>"
    private static let primeUser = "The number is \(value)."

    override func setUp() {
        super.setUp()
        // 实验需要跨阶段汇总证据：单点失败不应丢掉后续测量。
        continueAfterFailure = true
    }

    // MARK: - Gate

    private static func requireModel() throws -> String {
        guard ProcessInfo.processInfo.environment["SIMIGO_FORK_EXP"] == "1" else {
            throw XCTSkip("载体交接实验：需 SIMIGO_FORK_EXP=1 与 SIMIGO_FORK_MODEL")
        }
        guard let path = ProcessInfo.processInfo.environment["SIMIGO_FORK_MODEL"],
              !path.isEmpty else {
            throw XCTSkip("载体交接实验：需 SIMIGO_FORK_MODEL 指定本机权重目录")
        }
        guard FileManager.default.fileExists(atPath: path + "/config.json") else {
            throw XCTSkip("模型不存在：\(path)")
        }
        return path
    }

    // MARK: - HTTP exchange

    private struct Exchange {
        let status: Int
        let raw: String
        let json: [String: Any]

        var assistantText: String {
            guard let output = json["output"] as? [[String: Any]] else { return "" }
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                if let text = content.first?["text"] as? String { return text }
            }
            return ""
        }

        /// 结果契约约束的是**值**（`^RESULT=(.+)$`），不是逐字节文本：不同架构的
        /// tokenizer/模板会多出尾随换行（Qwen3-Coder 实测 `"RESULT=7143\n"`）。
        /// 本实验的核心验收不看输出一致性，所以这里按值比较，原始文本仍原样入证据。
        var assistantContractValue: String {
            assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var usage: [String: Any] { json["usage"] as? [String: Any] ?? [:] }
        var promptTokens: Int { usage["input_tokens"] as? Int ?? -1 }
        var cachedTokens: Int {
            let details = usage["input_tokens_details"] as? [String: Any] ?? [:]
            return details["cached_tokens"] as? Int ?? -1
        }
        var settlementPayload: [String: Any] {
            json["continuation_settlement"] as? [String: Any] ?? [:]
        }
        var settlementID: String? {
            json["settlement_id"] as? String
                ?? settlementPayload["settlement_id"] as? String
        }
        var childESStateID: String? {
            json["child_es_state_id"] as? String
                ?? settlementPayload["child_es_state_id"] as? String
        }

        var summary: [String: Any] {
            [
                "status": status,
                "assistant_text": assistantText,
                "assistant_contract_value": assistantContractValue,
                "prompt_tokens": promptTokens,
                "cached_tokens": cachedTokens,
                "settlement_id": settlementID ?? "-",
                "child_es_state_id": childESStateID ?? "-",
                "identity_binding_published":
                    settlementPayload["identity_binding_published"] ?? "-",
                "error_kind": json["error_kind"] ?? "-",
                "reason_code": json["reason_code"] ?? "-",
                "body_prefix": String(raw.prefix(400)),
            ]
        }
    }

    private func requestBody(
        input: [[String: Any]], anchor: String?, settle: Bool, branch: String = "main"
    ) -> [String: Any] {
        var json: [String: Any] = [
            "model": "carrier-handoff",
            "input": input,
            "stream": false,
            "session_id": sessionID,
            "logical_branch_id": branch,
            "temperature": 0,
            "max_tokens": 24,
        ]
        if let anchor { json["previous_es_state_id"] = anchor }
        if settle { json["continuation_settle"] = true }
        return json
    }

    private func post(_ json: [String: Any]) async throws -> Exchange {
        let data = try JSONSerialization.data(withJSONObject: json)
        let (payload, response) = try await LOCALBAuthorizedE2E.send(
            host: host, port: port, method: "POST", path: "/v1/responses",
            contentType: "application/json", body: data)
        let raw = String(decoding: payload, as: UTF8.self)
        let parsed = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        return Exchange(status: response.statusCode, raw: raw, json: parsed)
    }

    /// 引擎实测（ENGINE_RUNTIME 级）：本轮实际预填 token、引擎报告的 cache hit、
    /// 复用模式，以及累计 generate pass 数（用于证伪「结算又跑了一次生成器」）。
    private func engineSnapshot(_ runtime: NativeMLX, label: String) -> [String: Any] {
        let snapshot = runtime.observation.snapshot()
        let events = snapshot["events"] as? [String: Any] ?? [:]
        let passes = snapshot["generate_passes"] as? Int ?? -1
        generatePassesObserved[label] = passes
        return [
            "prefill_tokens_observed": snapshot["prefill_tokens_observed"] ?? NSNull(),
            "prompt_tokens_engine_reported": snapshot["prompt_tokens_engine_reported"] ?? NSNull(),
            "cache_hit_tokens_engine_reported": snapshot["cache_hit_tokens_engine_reported"] ?? NSNull(),
            "cache_reuse_mode_engine_reported": snapshot["cache_reuse_mode_engine_reported"] ?? NSNull(),
            "reused_session": snapshot["reused_session"] ?? NSNull(),
            "generate_passes": passes,
            "events": events,
        ]
    }

    private func liveBranches(_ runtime: NativeMLX) -> [String] {
        runtime.listSessionBranches(sessionId: sessionID).liveBranches
    }

    private func liveBranches(_ runtime: NativeMLX, contain branch: String) -> Bool {
        liveBranches(runtime).contains { $0 == branch || $0.hasPrefix(branch + "#") }
    }

    // MARK: - Evidence artifact

    private func evidenceURL() -> URL {
        if let storePath = ProcessInfo.processInfo.environment["SIMIGO_STATE_GRAPH_STORE"],
           !storePath.isEmpty {
            return URL(fileURLWithPath: (storePath as NSString).deletingLastPathComponent)
                .appendingPathComponent("carrier-handoff-\(sessionID).json")
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-handoff-\(sessionID).json")
    }

    private func writeEvidence() {
        evidence["session_id"] = sessionID
        evidence["port"] = port
        evidence["experiment_gates"] = [
            "SIMIGO_FORK_EXP": ProcessInfo.processInfo.environment["SIMIGO_FORK_EXP"] ?? "-",
            "SIMIGO_FORK_MODEL": ProcessInfo.processInfo.environment["SIMIGO_FORK_MODEL"] ?? "-",
            "SIMIGO_PREFIX_POOL": ProcessInfo.processInfo.environment["SIMIGO_PREFIX_POOL"] ?? "-",
            "SIMIGO_STATE_GRAPH_STORE":
                ProcessInfo.processInfo.environment["SIMIGO_STATE_GRAPH_STORE"] ?? "-",
            "SIMIGO_CACHE_ROOT": ProcessInfo.processInfo.environment["SIMIGO_CACHE_ROOT"] ?? "-",
        ]
        evidence["not_proven"] = [
            "kv_buffer_physical_release": "NOT_INSTRUMENTED：ChatSession 不暴露 buffer 身份，"
                + "clear() 只证引用解除；物理页归还未观测，不宣称。",
            "per_layer_forward_calls": "NOT_INSTRUMENTED：无逐层 forward 钩子；"
                + "generation_tokens 仅作 token 粒度代理。",
        ]
        evidence["observed_at"] = ISO8601DateFormatter().string(from: Date())
        do {
            let data = try JSONSerialization.data(
                withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: evidenceURL(), options: .atomic)
            print("[CARRIER-HANDOFF] evidence written to \(evidenceURL().path)")
        } catch {
            print("[CARRIER-HANDOFF] evidence write FAILED: \(error)")
        }
    }

    /// 追溯产品自己写的 trace（分支查找 / fork / 释放 / cold 降级都在里面）。
    private func traceTail(limit: Int = 160) -> [String] {
        RuntimeTraceLogger.shared.flush()
        let url = SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let marks = ["[MLX]", "[PROTOCOL]", "[CARRIER]", "[EXEC]"]
        let hits = text.split(separator: "\n").map(String.init).filter { line in
            marks.contains { line.contains($0) }
                && (line.contains(sessionID) || line.contains("continuation_"))
        }
        return Array(hits.suffix(limit))
    }

    // MARK: - The experiment

    func testRealModelForkSettleReleaseRestoreContinue() async throws {
        let modelPath = try Self.requireModel()
        let modelInfo = ModelInfo(path: modelPath, kind: .mlx)
        let value = Self.value

        // ---- 身份固定：权重 + tokenizer 内容摘要（settle 与 admit 必须一致）----
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        evidence["model"] = [
            "path": modelPath,
            "model_fingerprint": identity.model,
            "tokenizer_fingerprint": identity.tokenizer,
            "tokenizer_artifacts": SimiGoProducerIdentity.tokenizerIdentity(fromPath: modelPath),
        ]

        let runtime = NativeMLX(info: modelInfo, config: ModelConfig())
        host = try LOCALBAuthorizedE2E.makeHost()
        try await runtime.startWithLOCALB(
            modelInfo,
            port: port,
            localbTransportIdentity: host.identity,
            localbRequestAuthorization: (
                coordinator: host.coordinator,
                trustedCheckpoint: host.checkpointProvider
            )
        )
        defer { Task { await runtime.stop() } }
        evidence["runtime_started"] = true

        // ---- 0. Staging：父 ES 已结算（真实 SQLite 权威库 + 身份绑定）----
        let parentID = try await MainActor.run { () -> String in
            let store = ExecutionStateGraphStore()
            let root = try store.create()
            try store.continueState(root, input: value)
            let state = try XCTUnwrap(store.state(root.id))
            _ = try store.settleProducerResult(
                generatedText: "RESULT=\(value)",
                boundToState: state,
                producerIdentity: identity)
            return state.id
        }
        evidence["parent"] = ["es_state_id": parentID, "next_input": value]

        // ---- 1. Fork 前的真实载体：让分支 "main" 拥有真实 ChatSession + KV ----
        let transcript: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt],
            ["role": "user", "content": Self.primeUser],
        ]
        let prime = try await post(requestBody(input: transcript, anchor: nil, settle: false))
        XCTAssertEqual(prime.status, 200, prime.raw)
        XCTAssertFalse(prime.assistantText.isEmpty, "prime 未产生任何输出：\(prime.raw)")
        var primeEvidence = prime.summary
        primeEvidence["engine"] = engineSnapshot(runtime, label: "prime")
        primeEvidence["live_branches"] = liveBranches(runtime)
        evidence["phase1_prime"] = primeEvidence
        XCTAssertTrue(liveBranches(runtime, contain: "main"),
                      "prime 之后 main 分支应持有真实会话：\(liveBranches(runtime))")

        // ---- 2. Fork + Settle（同一个请求：admission → fork(child ES) → 生成 → 结算）----
        let continuedTranscript = transcript + [
            ["role": "assistant", "content": prime.assistantText]
        ]
        let first = try await post(
            requestBody(input: continuedTranscript, anchor: parentID, settle: true))
        XCTAssertEqual(first.status, 200, first.raw)
        let childID = try XCTUnwrap(first.childESStateID, "结算成功必须回传 child ES id：\(first.raw)")
        let settlementID = try XCTUnwrap(first.settlementID, "结算成功必须回传 settlement id：\(first.raw)")
        XCTAssertEqual(first.assistantContractValue, "RESULT=\(value)",
                       "生成必须满足结果契约：\(first.raw)")

        evidence["phase2_fork_settle"] = [
            "exchange": first.summary,
            "engine": engineSnapshot(runtime, label: "fork+settle"),
            "child_es_state_id": childID,
            "settlement_id": settlementID,
            "live_branches_after_settle": liveBranches(runtime),
        ]
        // Fork 真的发生了：child ES id 就是新分支 id，且它持有真实会话。
        XCTAssertNotEqual(childID, "main")
        XCTAssertTrue(liveBranches(runtime, contain: childID),
                      "child ES 分支应持有真实会话：\(liveBranches(runtime))")
        XCTAssertTrue(liveBranches(runtime, contain: "main"), "父分支此时仍应存活")
        // 暖复用：fork 携带了父分支的 KV，所以本轮不应全量预填。
        XCTAssertGreaterThan(first.cachedTokens, 0,
                             "child 分支应从 fork 继承 KV（cached=\(first.cachedTokens)）")

        // ---- 3. Release：释放旧分支（真实 MLX 池），并回读地址不再可解析 ----
        let owner = MLXRuntimeCarrierOwner(runtime: runtime)
        let oldRef = ExecutionCarrierRef(agentID: nil, sessionID: sessionID, branchID: "main")
        let report = try await owner.releaseExecutionCarrier(oldRef)
        try owner.verifyCarrierUnusable(oldRef)
        evidence["phase3_release"] = [
            "branch": "main",
            "carrier_was_live": report.carrierWasLive,
            "clear_issued": report.clearIssued,
            "sessions_released": report.sessionsReleased,
            "binding_detached": report.bindingDetached,
            "checkpoint_files_deleted": report.checkpointFilesDeleted,
            "still_live_afterwards": report.stillLiveAfterwards,
            "retired_storage": String(describing: report.retiredStorage),
            "live_branches_after_release": liveBranches(runtime),
        ]
        XCTAssertTrue(report.carrierWasLive, "旧分支释放前应真的持有载体")
        XCTAssertGreaterThanOrEqual(report.sessionsReleased, 1)
        XCTAssertTrue(report.clearIssued, "持有会话就必须发起 clear()")
        XCTAssertFalse(report.stillLiveAfterwards)
        XCTAssertFalse(liveBranches(runtime, contain: "main"),
                       "释放后 main 分支不应再可解析：\(liveBranches(runtime))")
        XCTAssertTrue(liveBranches(runtime, contain: childID), "child 分支不应被连带释放")
        // 分片键（system prompt 开头的会话键是 `main#<fp>`）必须一起消失。
        XCTAssertFalse(liveBranches(runtime).contains { $0.hasPrefix("main#") })

        // ---- 4. Restore：只从 IS（新连接、只读 SQLite）恢复新 ES ----
        let restored = try await MainActor.run {
            () -> (parentID: String?, nextInput: String?, checkpoints: Int,
                   recovered: String, admissionSettlementID: String) in
            let store = ExecutionStateGraphStore()   // 新鲜实例：新的 SQLite 连接
            let child = try XCTUnwrap(store.state(childID), "IS 中应存在该 child ES 行")
            let admitted = try store.admitContinuation(
                stateID: childID,
                consumer: SimiGoProducerIdentity.identity(fromPath: modelPath))
            return (child.parentID, child.nextInput, store.checkpoints(for: childID).count,
                    admitted.recoveredValue, admitted.settlementID)
        }
        evidence["phase4_restore"] = [
            "parent_id": restored.parentID ?? "-",
            "next_input": restored.nextInput ?? "-",
            "checkpoints": restored.checkpoints,
            "recovered_value": restored.recovered,
            "admission_settlement_id": restored.admissionSettlementID,
            "expected_parent": parentID,
        ]
        XCTAssertEqual(restored.parentID, parentID, "child ES 的血统必须指向父 ES")
        XCTAssertEqual(restored.nextInput, value, "IS 恢复出的语义值必须是结算值")
        XCTAssertEqual(restored.recovered, value)
        XCTAssertEqual(restored.admissionSettlementID, settlementID,
                       "恢复读到的 settlement 必须就是本请求结算的那一条")

        // ---- 5a. Continue（暖臂）：旧分支已不存在，child 分支继续真实生成 ----
        // 产品在续算输入尾部追加恢复出的 IS 值（user "7143"）；下一轮要复用
        // child 的 KV，客户端转录必须也包含这一条，否则前缀不匹配 → 冷重建。
        let appended: [String: Any] = ["role": "user", "content": value]
        let warmTranscript = continuedTranscript + [
            appended,
            ["role": "assistant", "content": first.assistantText],
        ]
        // 产品语义：fork 的源分支是客户端自己的 `logical_branch_id`，不是
        // `previous_es_state_id`。所以要接着上一轮的 child 载体续算，客户端必须
        // 把分支指向那个 child ES id；否则源仍是 "main"（已释放）→ cold 降级。
        let warm = try await post(
            requestBody(input: warmTranscript, anchor: childID, settle: true,
                        branch: childID))
        XCTAssertEqual(warm.status, 200, warm.raw)
        let grandchildID = try XCTUnwrap(warm.childESStateID, warm.raw)
        evidence["phase5a_continue_warm"] = [
            "exchange": warm.summary,
            "engine": engineSnapshot(runtime, label: "continue-warm"),
            "source_branch": childID,
            "child_es_state_id": grandchildID,
            "live_branches": liveBranches(runtime),
        ]
        XCTAssertEqual(warm.assistantContractValue, "RESULT=\(value)", warm.raw)
        XCTAssertGreaterThan(warm.cachedTokens, 0,
                             "child 分支的 KV 应在暖臂被复用（cached=\(warm.cachedTokens)）")
        XCTAssertTrue(liveBranches(runtime, contain: grandchildID))

        // ---- 5b. Continue（冷臂）：先把所有载体释放，再续算 ----
        let childRelease = try await owner.releaseExecutionCarrier(
            ExecutionCarrierRef(agentID: nil, sessionID: sessionID, branchID: childID))
        let grandchildRelease = try await owner.releaseExecutionCarrier(
            ExecutionCarrierRef(agentID: nil, sessionID: sessionID, branchID: grandchildID))
        try owner.verifyCarrierUnusable(
            ExecutionCarrierRef(agentID: nil, sessionID: sessionID, branchID: grandchildID))
        let coldTranscript = warmTranscript + [
            appended,
            ["role": "assistant", "content": warm.assistantText],
        ]
        let liveBeforeCold = liveBranches(runtime)
        let cold = try await post(
            requestBody(input: coldTranscript, anchor: grandchildID, settle: true,
                        branch: grandchildID))
        XCTAssertEqual(cold.status, 200,
                       "没有载体也必须能续算（fork 降级为 cold，语义不受影响）：\(cold.raw)")
        let coldChildID = try XCTUnwrap(cold.childESStateID, cold.raw)
        evidence["phase5b_continue_cold"] = [
            "exchange": cold.summary,
            "engine": engineSnapshot(runtime, label: "continue-cold"),
            "released_child": childRelease.sessionsReleased,
            "released_grandchild": grandchildRelease.sessionsReleased,
            "live_branches_before_cold": liveBeforeCold,
            "child_es_state_id": coldChildID,
            "live_branches_after_cold": liveBranches(runtime),
        ]
        XCTAssertTrue(liveBeforeCold.isEmpty, "冷臂前不应有任何存活载体：\(liveBeforeCold)")
        XCTAssertEqual(cold.assistantContractValue, "RESULT=\(value)", cold.raw)
        XCTAssertEqual(cold.cachedTokens, 0, "无载体时应全量预填（cached=\(cold.cachedTokens)）")
        XCTAssertTrue(liveBranches(runtime, contain: coldChildID))

        // ---- 6. 结算没有重新跑生成器：4 个请求 ⇒ 4 个 generate pass ----
        let finalSnapshot = runtime.observation.snapshot()
        let finalPasses = finalSnapshot["generate_passes"] as? Int ?? -1
        evidence["generation_accounting"] = [
            "http_requests": 4,
            "generate_passes_total": finalPasses,
            "per_request": generatePassesObserved,
            "cold_rebuilds": (finalSnapshot["events"] as? [String: Any])?["cold_rebuild"] ?? NSNull(),
            "reuse_misses": (finalSnapshot["events"] as? [String: Any])?["reuse_miss"] ?? NSNull(),
        ]
        XCTAssertEqual(finalPasses, 4, "每个 HTTP 请求只应有一次生成 pass（结算不得重跑生成器）")

        evidence["trace_tail"] = traceTail()
        writeEvidence()
    }
}
