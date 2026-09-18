import XCTest
import Foundation
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
@testable import SimiGo

/// Roll-forward Phase A 测量实验（探索文档
/// `docs/experiments/BRANCH_FORK_ROLLFORWARD_EXPLORATION_20260918.md` §5 Phase A，
/// 2026-09-18）。
///
/// 目标：验证 checkpoint-recovery 能否作为**分歧隔离执行模式**——
/// 连续 roll-forward（每成功轮 saveSessionCache → 下轮 loadSessionCache 覆盖 →
/// fragment-continuation）在长程工具密集会话上：
///   1. fork-no-rewind / rebuild 恒 0（免疫性证伪点：任一轮 promptTokens
///      远超 delta ⇒ 引擎内部全模板渲染 ⇒ 免疫性不成立）；
///   2. fragment token 持续 ≈ delta（~1.7k）；
///   3. TTFT 稳定；
///   4. saveCache/loadCache 随上下文（10k→80k+）的劣化曲线（隐藏成本核查）。
///
/// 双臂：
///   - rollforward（50 轮，上下文爬到 ~85k）：每轮 save→load→generate；
///   - control（30 轮，同内容增长）：活会话连续 extend，无 save/load。
///
/// 已知边界（诚实记录）：合成历史的 assistant 消息由模板确定性渲染，
/// **无法复现真实流量中「模型自产 token 序 vs 重渲染键序」的不稳定**——
/// control 臂预期全程 extend（机制推演），分歧税的 before 曲线以
/// BENCH_442FBF_FORK_REWIND_20260918 fixture（真实流量）为准。
/// 本实验的可证伪命题只在 rollforward 臂上。
///
/// 环境门控：`SIMIGO_ROLLFWD_EXP=1`；`SIMIGO_FORK_MODEL` 覆盖模型；
/// `SIMIGO_ROLLFWD_OUT` 指定结果 JSON 输出路径。
final class RollForwardExperimentTests: XCTestCase {

    private static let systemContent =
        "You are a precise assistant. Follow instructions exactly. " +
        "Answer in English without extra words."

    private static let defaultModelPath =
        "/Users/mr.simi/.cache/huggingface/hub/models--peculiar-ragdoll--Nail-Qwen3.6-35B-A3B-MLX"
        + "/snapshots/31a0106483c94e9fbb0a6d3360ff122d47377058"

    /// 每轮上下文增量目标 ≈1.45k tokens（~1.6KB 确定性档案文本）；40 轮 ≈58k。
    /// （首轮实测校准：100 行版实测 ~5.7k tok/轮，密度 ≈1.1 字符/token。）
    private static func chunk(_ round: Int) -> String {
        var lines: [String] = []
        for i in 0..<25 {
            let n = round * 100 + i
            lines.append(
                "Ledger \(n): alpha bravo charlie delta echo foxtrot golf hotel india juliet " +
                "\(n * 7 % 97) kilo lima november oscar papa quebec romeo sierra tango " +
                "\(n * 13 % 89) uniform victor whiskey xray yankee zulu.")
        }
        return "Batch \(round) archive:\n" + lines.joined(separator: "\n")
    }

    /// TodoWrite 形态：多键嵌套 tool_calls（client echo 形态）。
    private static func assistantToolCall(_ round: Int) -> SimiGo.JSONValue {
        .object([
            "role": .string("assistant"),
            "content": .string(""),
            "tool_calls": .array([
                .object([
                    "type": .string("function"),
                    "id": .string("call_\(round)"),
                    "function": .object([
                        "name": .string("note_write"),
                        "arguments": .object([
                            "notes": .array([
                                .string("batch \(round) item a"),
                                .string("batch \(round) item b"),
                                .string("batch \(round) item c"),
                            ]),
                            "batch": .number(Double(round)),
                            "tag": .string("batch-\(round)"),
                            "priority": .number(Double(round % 5)),
                            "meta": .object([
                                "source": .string("rollfwd-exp"),
                                "round": .number(Double(round)),
                                "ok": .bool(true),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])
    }

    private static func toolResult(_ round: Int) -> SimiGo.JSONValue {
        .object([
            "role": .string("tool"),
            "tool_call_id": .string("call_\(round)"),
            "content": .string("Recorded batch \(round)."),
        ])
    }

    private static func requireEnabled() throws -> String {
        guard ProcessInfo.processInfo.environment["SIMIGO_ROLLFWD_EXP"] == "1" else {
            throw XCTSkip("roll-forward Phase A：需 SIMIGO_ROLLFWD_EXP=1 且本机存在权重")
        }
        let path = ProcessInfo.processInfo.environment["SIMIGO_FORK_MODEL"]
            ?? defaultModelPath
        guard FileManager.default.fileExists(atPath: path + "/config.json") else {
            throw XCTSkip("模型不存在：\(path)")
        }
        return path
    }

    private static func greedyConfig() -> ModelConfig {
        var cfg = ModelConfig()
        cfg.temperature = 0
        cfg.maxTokens = 24
        cfg.disableThinking = true
        cfg.useMTP = false
        return cfg
    }

    private struct RoundRecord: Codable {
        var round: Int
        var promptTokens: Int
        var ttftS: Double
        var genTokens: Int
        var tps: Double
        var cachedPromptTokens: Int
        var cacheEfficiency: Double
        var saveS: Double?
        var loadS: Double?
        var footprintMB: Double
        var swapMB: Double?
        var wallS: Double
    }

    private struct ArmResult: Codable {
        var name: String
        var rounds: [RoundRecord] = []
        var saveFailures: [String] = []
        var loadFailures: [String] = []
        var immunityViolations: [String] = []
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func mean(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func p95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let pos = 0.95 * Double(s.count - 1)
        let lo = Int(pos), hi = min(lo + 1, s.count - 1)
        let frac = pos - Double(lo)
        return s[lo] * (1 - frac) + s[hi] * frac
    }

    func testRollForwardPhaseA() async throws {
        let modelPath = try Self.requireEnabled()
        let outPath = ProcessInfo.processInfo.environment["SIMIGO_ROLLFWD_OUT"]
            ?? (FileManager.default.temporaryDirectory
                .appendingPathComponent("rollfwd_results.json").path)

        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: Self.greedyConfig())
        try await runtime.start(info, port: 18787)

        var results: [String: ArmResult] = [:]

        // ── Arm R：roll-forward 50 轮 ────────────────────────────────
        var armR = ArmResult(name: "rollforward")
        var contextTokensR = 0
        var messagesR: [SimiGo.JSONValue] = [
            .object(["role": .string("system"), "content": .string(Self.systemContent)])
        ]
        let rfDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollfwd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rfDir, withIntermediateDirectories: true)

        for round in 1...40 {
            messagesR.append(.object(["role": .string("user"), "content": .string(Self.chunk(round))]))
            messagesR.append(Self.assistantToolCall(round))
            messagesR.append(Self.toolResult(round))

            var saveS: Double?
            var loadS: Double?
            // roll-forward：round 1 生成后首存；此后每轮生成前恢复上轮 checkpoint。
            if round > 1 {
                var t0 = Date()
                do {
                    _ = try await runtime.saveSessionCache(
                        sessionId: "rollfwd", logicalBranchId: "main", to: rfDir)
                    saveS = Date().timeIntervalSince(t0)
                } catch {
                    armR.saveFailures.append("round \(round): \(error.localizedDescription)")
                }
                t0 = Date()
                do {
                    _ = try await runtime.loadSessionCache(
                        sessionId: "rollfwd", logicalBranchId: "main",
                        config: Self.greedyConfig(), from: rfDir)
                    loadS = Date().timeIntervalSince(t0)
                } catch {
                    armR.loadFailures.append("round \(round): \(error.localizedDescription)")
                }
            }

            let requestId = "rollfwd-r\(round)-\(UUID().uuidString.prefix(8).lowercased())"
            await RuntimeLifecycleCoordinator.shared.register(
                requestID: requestId, sessionID: "rollfwd")
            let w0 = Date()
            let result = try await runtime.generate(
                requestId: requestId, agentId: nil, sessionId: "rollfwd",
                logicalBranchId: "main", messages: messagesR, tools: nil,
                config: Self.greedyConfig()
            ) { _ in }
            let wall = Date().timeIntervalSince(w0)
            let usage = try XCTUnwrap(result.usage, "round \(round) 缺 usage")
            let rec = RoundRecord(
                round: round, promptTokens: usage.promptTokens, ttftS: usage.ttftSeconds ?? -1,
                genTokens: usage.generationTokens, tps: usage.tokensPerSecond ?? -1,
                cachedPromptTokens: usage.cachedPromptTokens ?? -1,
                cacheEfficiency: usage.cacheEfficiency ?? -1,
                saveS: saveS, loadS: loadS,
                footprintMB: Double(RuntimeTuning.footprintBytes()) / 1048576,
                swapMB: RuntimeTuning.swapUsedBytes().map { Double($0) / 1048576 },
                wallS: wall)
            armR.rounds.append(rec)
            // 免疫性探针（相对阈值）：本轮 fragment 若超过累计上下文的一半，
            // 说明引擎做了全模板渲染（首轮除外——首轮冷启动本就是全量）。
            if round > 1, usage.promptTokens * 2 > contextTokensR {
                armR.immunityViolations.append(
                    "round \(round): promptTokens=\(usage.promptTokens)"
                    + " contextBefore=\(contextTokensR)")
            }
            contextTokensR += usage.promptTokens + usage.generationTokens
            messagesR.append(.object([
                "role": .string("assistant"), "content": .string(result.text)
            ]))
            if round == 10 || round == 20 || round == 30 || round == 40 {
                let tail = armR.rounds.suffix(round)
                print("[ROLLFWD][\(round)] fragMean="
                      + String(format: "%.0f", Self.mean(tail.map(\.promptTokens)))
                      + " saveMean=" + String(format: "%.2fs", Self.mean(tail.compactMap(\.saveS)))
                      + " saveMax=" + String(format: "%.2fs", tail.compactMap(\.saveS).max() ?? 0)
                      + " loadMean=" + String(format: "%.2fs", Self.mean(tail.compactMap(\.loadS)))
                      + " loadMax=" + String(format: "%.2fs", tail.compactMap(\.loadS).max() ?? 0)
                      + " ttftMean=" + String(format: "%.2fs", Self.mean(tail.map(\.ttftS)))
                      + " swap=" + String(format: "%.0fMB", tail.last?.swapMB ?? 0))
            }
        }
        results["rollforward"] = armR

        // ── Arm C：control 活会话 30 轮 ──────────────────────────────
        var armC = ArmResult(name: "control")
        var messagesC: [SimiGo.JSONValue] = [
            .object(["role": .string("system"), "content": .string(Self.systemContent)])
        ]
        for round in 1...15 {
            messagesC.append(.object(["role": .string("user"), "content": .string(Self.chunk(round))]))
            messagesC.append(Self.assistantToolCall(round))
            messagesC.append(Self.toolResult(round))
            let requestId = "ctrl-r\(round)-\(UUID().uuidString.prefix(8).lowercased())"
            await RuntimeLifecycleCoordinator.shared.register(
                requestID: requestId, sessionID: "ctrl")
            let w0 = Date()
            let result = try await runtime.generate(
                requestId: requestId, agentId: nil, sessionId: "ctrl",
                logicalBranchId: "main", messages: messagesC, tools: nil,
                config: Self.greedyConfig()
            ) { _ in }
            let wall = Date().timeIntervalSince(w0)
            let usage = try XCTUnwrap(result.usage, "round \(round) 缺 usage")
            armC.rounds.append(RoundRecord(
                round: round, promptTokens: usage.promptTokens, ttftS: usage.ttftSeconds ?? -1,
                genTokens: usage.generationTokens, tps: usage.tokensPerSecond ?? -1,
                cachedPromptTokens: usage.cachedPromptTokens ?? -1,
                cacheEfficiency: usage.cacheEfficiency ?? -1,
                saveS: nil, loadS: nil,
                footprintMB: Double(RuntimeTuning.footprintBytes()) / 1048576,
                swapMB: RuntimeTuning.swapUsedBytes().map { Double($0) / 1048576 },
                wallS: wall))
            messagesC.append(.object([
                "role": .string("assistant"), "content": .string(result.text)
            ]))
            if round == 10 || round == 15 {
                let tail = armC.rounds.suffix(round)
                print("[CONTROL][\(round)] promptMean="
                      + String(format: "%.0f", Self.mean(tail.map(\.promptTokens)))
                      + " promptMax=\(tail.map(\.promptTokens).max() ?? 0)"
                      + " ttftMean=" + String(format: "%.2fs", Self.mean(tail.map(\.ttftS))))
            }
        }
        results["control"] = armC

        await runtime.stop()

        // ── 汇总输出 ────────────────────────────────────────────────
        let payload: [String: Any] = [
            "model": modelPath,
            "rollforward": try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(armR)),
            "control": try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(armC)),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)

        let rRounds = armR.rounds
        print("[ROLLFWD][summary] rounds=\(rRounds.count)"
              + " fragMean=" + String(format: "%.0f", Self.mean(rRounds.map(\.promptTokens)))
              + " fragMax=\(rRounds.map(\.promptTokens).max() ?? 0)"
              + " saveMean=" + String(format: "%.2fs", Self.mean(rRounds.compactMap(\.saveS)))
              + " saveMax=" + String(format: "%.2fs", rRounds.compactMap(\.saveS).max() ?? 0)
              + " loadMean=" + String(format: "%.2fs", Self.mean(rRounds.compactMap(\.loadS)))
              + " loadMax=" + String(format: "%.2fs", rRounds.compactMap(\.loadS).max() ?? 0)
              + " ttftMean=" + String(format: "%.2fs", Self.mean(rRounds.map(\.ttftS)))
              + " violations=\(armR.immunityViolations.count)"
              + " saveFailures=\(armR.saveFailures.count)"
              + " loadFailures=\(armR.loadFailures.count)")
        print("[ROLLFWD][results] \(outPath)")

        // 免疫性断言（数据已全部采集后执行；违反即理论证伪）。
        XCTAssertTrue(armR.immunityViolations.isEmpty,
                      "分歧免疫性被证伪：\(armR.immunityViolations)")
        XCTAssertTrue(armR.loadFailures.isEmpty, "loadSessionCache 失败：\(armR.loadFailures)")
    }

    // MARK: - 纯函数单测（无需模型，常规测试跑常驻）

    func testRollforwardRiskDetector() {
        func assistant(_ toolCalls: [SimiGo.JSONValue]?) -> SimiGo.JSONValue {
            var o: [String: SimiGo.JSONValue] = [
                "role": .string("assistant"), "content": .string("")
            ]
            if let toolCalls { o["tool_calls"] = .array(toolCalls) }
            return .object(o)
        }
        func call(_ args: SimiGo.JSONValue) -> SimiGo.JSONValue {
            .object(["type": .string("function"),
                     "function": .object(["name": .string("t"), "arguments": args])])
        }
        // 多键参数 → risky（TodoWrite 形态）
        XCTAssertTrue(SimiGo.NativeMLX.rollforwardRisk(lastJSON: assistant([
            call(.object(["b": .number(1), "a": .number(2)])),
        ])))
        // 单键纯量 → safe（Bash command 形态）
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardRisk(lastJSON: assistant([
            call(.object(["command": .string("ls")])),
        ])))
        // 单键但嵌套多键对象 → risky
        XCTAssertTrue(SimiGo.NativeMLX.rollforwardRisk(lastJSON: assistant([
            call(.object(["cmd": .object(["x": .number(1), "y": .number(2)])])),
        ])))
        // 多键对象数组元素多键 → risky（notes 数组形态）
        XCTAssertTrue(SimiGo.NativeMLX.rollforwardRisk(lastJSON: assistant([
            call(.object(["notes": .array([
                .object(["k": .number(1), "j": .number(2)]),
            ])])),
        ])))
        // 无 tool_calls / 无尾消息 → safe
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardRisk(lastJSON: assistant(nil)))
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardRisk(lastJSON: nil))
    }

    func testRollforwardCompatible() {
        func user(_ text: String) -> SimiGo.JSONValue {
            .object(["role": .string("user"), "content": .string(text)])
        }
        // checkpoint 历史 = incoming 真前缀 → 兼容
        XCTAssertTrue(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: [user("a"), user("b"), user("c")],
            restoredHistory: [user("a"), user("b")]))
        // 历史更长（陈旧/超前）→ 不兼容
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: [user("a")],
            restoredHistory: [user("a"), user("b")]))
        // 同长（无 delta）→ 不兼容
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: [user("a")],
            restoredHistory: [user("a")]))
        // 前缀内容漂移 → 不兼容
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: [user("a"), user("changed")],
            restoredHistory: [user("a"), user("b")]))
        // role 改变（content 相同）→ 不兼容（外审 P0-2：渲染路径字段对账）
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: [.object(["role": .string("user"), "content": .string("a")]),
                       user("b")],
            restoredHistory: [.object(["role": .string("assistant"), "content": .string("a")]),
                              user("b")]))
        // tool_call_id 改变 → 不兼容
        func tool(_ id: String) -> SimiGo.JSONValue {
            .object(["role": .string("tool"), "tool_call_id": .string(id),
                     "content": .string("ok")])
        }
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: [user("a"), tool("call_2")],
            restoredHistory: [user("a"), tool("call_X")]))
        // tool_calls 结构改变（arguments 键集不同）→ 不兼容
        func asst(_ args: SimiGo.JSONValue) -> SimiGo.JSONValue {
            .object(["role": .string("assistant"), "content": .string(""),
                     "tool_calls": .array([.object([
                        "type": .string("function"),
                        "id": .string("call_1"),
                        "function": .object(["name": .string("t"), "arguments": args]),
                     ])])])
        }
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: [user("a"), asst(.object(["b": .number(1), "a": .number(2)])), user("c")],
            restoredHistory: [user("a"), asst(.object(["a": .number(2), "b": .number(9)]))]))
        // arguments 键集与值相同（仅构造插入序不同）→ 兼容（dict 相等与序无关）
        XCTAssertTrue(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: [user("a"), asst(.object(["a": .number(1), "b": .number(2)])), user("c")],
            restoredHistory: [user("a"), asst(.object(["b": .number(2), "a": .number(1)]))]))
    }

    func testCheckpointMetadataFingerprintRoundTrip() throws {
        // 新格式：kvFingerprint 编解码往返
        let meta = SimiGo.SessionCacheMetadata(
            storageKey: "s", modelId: "m", savedAt: Date(),
            history: [.object(["role": .string("user"), "content": .string("x")])],
            kvFingerprint: "fullPrecision-fp")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(SimiGo.SessionCacheMetadata.self, from: data)
        XCTAssertEqual(back.kvFingerprint, "fullPrecision-fp")
        // 旧格式：无 kvFingerprint 键 → 解码为 nil（向后兼容）
        let legacy = """
        {"history":[],"modelId":"m","savedAt":"2026-01-01T00:00:00Z","storageKey":"s"}
        """
        let old = try decoder.decode(SimiGo.SessionCacheMetadata.self,
                                     from: Data(legacy.utf8))
        XCTAssertNil(old.kvFingerprint)
    }

    func testMessageRenderCompatibleDistinguishesNullFromStringNull() {
        // P1-1 回归（2026-09-18）：.description 比较会把 .string("null") 与
        // .null 判为相等（类型折叠假阳性 → 放行 → 渲染分叉）；结构相等必须区分。
        XCTAssertFalse(SimiGo.NativeMLX.messageRenderCompatible(
            .object(["role": .string("user"), "content": .null]),
            .object(["role": .string("user"), "content": .string("null")])))
    }

    func testMessageRenderCompatibleNormalizesArgumentsStringVsObject() {
        // 根因修复回归（2026-09-18 真机 74 连 checkpointStale）：引擎账本
        // arguments=dict，OpenAI 回显 arguments=string——同值必须判兼容。
        func asst(_ args: SimiGo.JSONValue) -> SimiGo.JSONValue {
            .object(["role": .string("assistant"), "content": .string(""),
                     "tool_calls": .array([.object([
                        "type": .string("function"),
                        "id": .string("call_1"),
                        "function": .object(["name": .string("t"), "arguments": args]),
                     ])])])
        }
        XCTAssertTrue(SimiGo.NativeMLX.messageRenderCompatible(
            asst(.object(["title": .string("diag"), "priority": .number(3)])),
            asst(.string("{\"title\": \"diag\", \"priority\": 3}"))))
        // 值不同（3 vs 9）→ 仍不兼容
        XCTAssertFalse(SimiGo.NativeMLX.messageRenderCompatible(
            asst(.object(["priority": .number(3)])),
            asst(.string("{\"priority\": 9}"))))
        // 非法 JSON 字符串按原样比较 → 与 dict 不兼容
        XCTAssertFalse(SimiGo.NativeMLX.messageRenderCompatible(
            asst(.object(["priority": .number(3)])),
            asst(.string("not-json"))))
        // 标量字符串不折叠（"3" ≠ 3）
        XCTAssertFalse(SimiGo.NativeMLX.messageRenderCompatible(
            asst(.object(["v": .number(3)])),
            asst(.object(["v": .string("3")]))))
    }

    func testRollforwardDiffLinePointsAtDivergentField() {
        func user(_ text: String) -> SimiGo.JSONValue {
            .object(["role": .string("user"), "content": .string(text)])
        }
        func tool(_ id: String) -> SimiGo.JSONValue {
            .object(["role": .string("tool"), "tool_call_id": .string(id),
                     "content": .string("ok")])
        }
        let line = SimiGo.NativeMLX.rollforwardDiffLine(
            incoming: [user("a"), tool("call_2"), user("c")],
            restoredHistory: [user("a"), tool("call_X")])
        XCTAssertTrue(line.contains("index=1"), line)
        XCTAssertTrue(line.contains("field=tool_call_id"), line)
        XCTAssertTrue(line.contains("call_X") && line.contains("call_2"), line)
    }

    func testRollforwardDiffLineReportsMissingField() {
        func user(_ text: String) -> SimiGo.JSONValue {
            .object(["role": .string("user"), "content": .string(text)])
        }
        // incoming 缺 content（isPrefix 容错方向）→ diff 标 field=content，
        // ckpt 侧为值、incoming 侧为 null——74 连 stale 归因的关键形态。
        let line = SimiGo.NativeMLX.rollforwardDiffLine(
            incoming: [.object(["role": .string("user")]), user("b"), user("c")],
            restoredHistory: [user("a"), user("b")])
        XCTAssertTrue(line.contains("index=0 field=content"), line)
    }

    func testRollforwardDiffLineHistoryCount() {
        func user(_ text: String) -> SimiGo.JSONValue {
            .object(["role": .string("user"), "content": .string(text)])
        }
        let line = SimiGo.NativeMLX.rollforwardDiffLine(
            incoming: [user("a")],
            restoredHistory: [user("a"), user("b")])
        XCTAssertTrue(line.contains("reason=historyCount"), line)
    }

    func testRollforwardDiffLineAgreesWithCompatibilityVerdict() {
        func user(_ text: String) -> SimiGo.JSONValue {
            .object(["role": .string("user"), "content": .string(text)])
        }
        // 行为判定 false 的样本（非 count 分支），diff 必须给出具体分歧而非 none
        func asst(_ args: SimiGo.JSONValue) -> SimiGo.JSONValue {
            .object(["role": .string("assistant"), "content": .string(""),
                     "tool_calls": .array([.object([
                        "type": .string("function"),
                        "id": .string("call_1"),
                        "function": .object(["name": .string("t"), "arguments": args]),
                     ])])])
        }
        let incoming = [user("a"), asst(.object(["a": .number(1)])), user("c")]
        let restored = [user("a"), asst(.object(["a": .number(2)]))]
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: incoming, restoredHistory: restored))
        let line = SimiGo.NativeMLX.rollforwardDiffLine(
            incoming: incoming, restoredHistory: restored)
        XCTAssertTrue(line.contains("field="), line)
        XCTAssertFalse(line.contains("reason=none"), line)
    }

    func testRollforwardDiffLineUnifiesNormalizationWithVerdict() {
        // 外审 P1 回归（2026-09-18）：diff 诊断必须与行为判定同规则——前缀里
        // arguments string≡object 同值的良性轮次不得拦路，否则真分歧（后轮
        // content 变更）会被误报成 tool_calls 首分歧。
        func user(_ text: String) -> SimiGo.JSONValue {
            .object(["role": .string("user"), "content": .string(text)])
        }
        func asst(_ args: SimiGo.JSONValue) -> SimiGo.JSONValue {
            .object(["role": .string("assistant"), "content": .string(""),
                     "tool_calls": .array([.object([
                        "type": .string("function"),
                        "id": .string("call_1"),
                        "function": .object(["name": .string("t"), "arguments": args]),
                     ])])])
        }
        // restored 须为 incoming 真前缀且更短（diff 的 historyCount 守卫）。
        let incoming = [user("a"), asst(.string("{\"a\": 1}")), user("b-new"), user("c")]
        let restored = [user("a"), asst(.object(["a": .number(1)])), user("b-old")]
        XCTAssertFalse(SimiGo.NativeMLX.rollforwardCompatible(
            incoming: incoming, restoredHistory: restored))
        let line = SimiGo.NativeMLX.rollforwardDiffLine(
            incoming: incoming, restoredHistory: restored)
        XCTAssertTrue(line.contains("index=2 field=content"), line)
        XCTAssertFalse(line.contains("tool_calls"), line)
    }

    func testConditionalRestoreGate() {
        // 旧 rf 开启 → 无条件放行（不设 delta 门，保持 a210155 前语义可 A/B）
        XCTAssertEqual(
            SimiGo.NativeMLX.conditionalRestoreGate(
                rollforwardEnabled: true, conditionalRestoreEnabled: false,
                incoming: [], ledgerCount: 0),
            .allowed)
        // 都关 → 禁用（纯 extend）
        XCTAssertEqual(
            SimiGo.NativeMLX.conditionalRestoreGate(
                rollforwardEnabled: false, conditionalRestoreEnabled: false,
                incoming: [], ledgerCount: 0),
            .skipDisabled)
        // conditional 开 + 小 delta（400 字符 ≈ 107 tok 粗估）→ 放行
        let small = SimiGo.JSONValue.object([
            "role": .string("tool"),
            "content": .string(String(repeating: "x", count: 400))])
        XCTAssertEqual(
            SimiGo.NativeMLX.conditionalRestoreGate(
                rollforwardEnabled: false, conditionalRestoreEnabled: true,
                incoming: [small], ledgerCount: 0),
            .allowed)
        // conditional 开 + 大 delta（40k 字符 ≈ 10k tok 粗估 > 8192 门）→ 拒，
        // 且带回估算值供 trace
        let big = SimiGo.JSONValue.object([
            "role": .string("tool"),
            "content": .string(String(repeating: "x", count: 40_000))])
        let decision = SimiGo.NativeMLX.conditionalRestoreGate(
            rollforwardEnabled: false, conditionalRestoreEnabled: true,
            incoming: [big], ledgerCount: 0)
        guard case .skipDeltaTooLarge(let estimate) = decision else {
            return XCTFail("expected skipDeltaTooLarge, got \(decision)")
        }
        XCTAssertGreaterThan(estimate, 8192)
    }

    func testEstimateDeltaTokens() {
        func user(_ text: String) -> SimiGo.JSONValue {
            .object(["role": .string("user"), "content": .string(text)])
        }
        // 账本全覆盖 → 0
        XCTAssertEqual(
            SimiGo.NativeMLX.estimateDeltaTokens(
                incoming: [user("a")], ledgerCount: 1), 0)
        // 新增消息 = compact-JSON 字符数 ÷ 4（{"role":"user","content":"bbbb"}
        // 两种键序下字符数同为 32 → 32/4 = 8，长度与键序无关）
        XCTAssertEqual(
            SimiGo.NativeMLX.estimateDeltaTokens(
                incoming: [user("a"), user("bbbb")], ledgerCount: 1), 8)
    }

    func testEstimateDeltaTokensCJK() {
        // CJK 感知口径（log-only 校准对照）：CJK 字符 ≈1 token、其余 ÷4。
        // 400 个中文字 ≈ 400 tok——chars÷4 口径只给 ~100（低估 ~4×），
        // 即 2026-09-18 生产 12k 级回填全过 8192 门的成因。
        let cjk = String(repeating: "小说", count: 200)
        let message: SimiGo.JSONValue = .object([
            "role": .string("tool"), "content": .string(cjk)])
        let est = SimiGo.NativeMLX.estimateDeltaTokensCJK(
            incoming: [message], ledgerCount: 0)
        XCTAssertGreaterThanOrEqual(est, 400)
        XCTAssertLessThan(est, 430)  // 包装层 ASCII ÷4
        // 对照：chars÷4 口径同输入仅 ~1/4——门的失真量级
        let asciiEst = SimiGo.NativeMLX.estimateDeltaTokens(
            incoming: [message], ledgerCount: 0)
        XCTAssertGreaterThan(asciiEst, 0)
        XCTAssertLessThan(asciiEst * 3, est)
    }
}
