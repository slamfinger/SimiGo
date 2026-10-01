import XCTest
import Foundation
import CryptoKit
@testable import SimiGo

/// P4 Replication — Common Base topology re-verification under the R0
/// audit framework (Empirical Replication Audit Phase-1, plan 9dbdbd0).
///
/// The pre-registered design (Lab 792afbc), its frozen inputs, identity
/// checks ID-1..4 and judgment rules J1..J6 are applied VERBATIM from the
/// original execution harness (Palace1R4P4ExecutionTests @ 70081e5).
/// What changes is only the evidence channel: every invocation writes
/// into its own results/replication/{runUUID}/ artifact directory
/// (metadata.json / events.jsonl / summary.json / hashes.json /
/// r0_verify.json) per R0-1..R0-6. The shared append-only observation
/// file and the original run artifacts (/tmp/simigo-p4/) are NEVER read
/// as judgment input (replication principle 3); old results are expected
/// comparison only.
///
/// Invocation order (each = one independent xcodebuild process):
///   1. testP4ReplicationS2Form      freeze → form → save S0'
///   2. testP4ReplicationS1Run1      A-first
///   3. testP4ReplicationS1Run2      B-first
///   4. testP4ReplicationS2Run1      A-first
///   5. testP4ReplicationS2Run2      B-first
///   6. testP4ReplicationAdjudicate  mechanical J1..J6 → judgment.json

final class P4ReplicationAudit: XCTestCase {
  // MARK: frozen constants — verbatim from the committed design 792afbc

  static let modelPath =
    "<LOCAL_HOME>/.cache/huggingface/hub/models--peculiar-ragdoll--Nail-Qwen3.6-35B-A3B-MLX/snapshots/31a0106483c94e9fbb0a6d3360ff122d47377058"
  static let work = URL(fileURLWithPath: "/tmp/simigo-p4-replication", isDirectory: true)
  static let realCheckpoints = URL(fileURLWithPath: "<LOCAL_HOME>/.simigo/branch-checkpoints", isDirectory: true)
  static let prefixPool = URL(fileURLWithPath: "<LOCAL_HOME>/.simigo/prefix-pool", isDirectory: true)
  static let productRepo = "<LOCAL_HOME>/Documents/SimiGo"

  static let s1Session = "5401315f-faa7-4984-9639-fccef06ae188"
  static let s1Fixture = URL(fileURLWithPath: "/tmp/simigo-palace1-e1/esr2/t3gateB/b0", isDirectory: true)
  static let s2Session = "p4-sample2-7f3a9c"
  static let s2Fixture = URL(fileURLWithPath: "/tmp/simigo-p4-replication/sample2", isDirectory: true)

  // Sample 1 futures (design §3, verbatim, pre-registered)
  static let s1dA1 = "PALACE-1 E3 probe: 这个会话此前在做什么？用一句话概括。"
  static let s1dA2 = "接着上一句，再补充一点：这些文件属于什么性质的材料？"
  static let s1dB1 = "从这个会话中找出一个文件或目录的名称，原样写出名称，不要解释。"
  static let s1dB2 = "用一句话说明你是从会话的哪个部分注意到它的。"
  static let s1AnchorA = ["桌面", "参考文件", "管理制度"]

  // Sample 2 frozen script (user turns; assistant turns are real generations)
  static let s2Script: [String] = [
    "我想规划一次京都三日旅行，11月3日出发，帮我安排一个不赶的行程。",
    "第一天下午只想轻松一点，有什么推荐？",
    "岚山和清水寺如果分两天，你会怎么排？",
    "第二天上午想去伏见稻荷，大概要留多少时间？",
    "11月3日当天京都天气通常怎么样，需要备什么？",
    "行程里哪一天适合安排晚餐吃得讲究一点？",
    "如果第三天上午想睡到自然醒，剩下的半天怎么安排最顺？",
    "最后帮我把三天的顺序整体复述一遍。"
  ]
  // Sample 2 futures (pre-registered at freeze, same pattern as sample 1)
  static let s2dA1 = "PALACE-1 P4 probe: 这个会话此前在规划什么？用一句话概括。"
  static let s2dA2 = "接着上面的总结，再补充一点：这趟旅行最重要的一个地点是什么？为什么？"
  static let s2dB1 = "从这个会话中找出一个具体的地名或日期，原样写出，不要解释。"
  static let s2dB2 = "用一句话说明你是从会话的哪个部分注意到它的。"
  static let s2AnchorA = ["京都", "岚山", "伏见稻荷", "清水寺", "旅行"]
  static let s2Entities = ["京都", "岚山", "伏见稻荷", "11月3日", "清水寺"]

  static let replicationBase = P4ReplicationAudit.work.appendingPathComponent("results/replication", isDirectory: true)

  // MARK: R0 context helpers

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func modelHashString() -> String {
    let revision = (Self.modelPath as NSString).lastPathComponent
    let configSHA = (try? Data(contentsOf: URL(fileURLWithPath: Self.modelPath + "/config.json")))
      .map { "config=sha256:" + sha256Hex($0) } ?? "config=UNREADABLE"
    return "Nail-Qwen3.6-35B-A3B-MLX@\(revision);\(configSHA)"
  }

  // Stored-property initializers may not reference Self; use the
  // concrete type name instead.
  private static let configHashString: String = {
    // Canonical description of the frozen inference configuration.
    let canonical = "temperature=0;maxTokens=128;tools=nil;greedy"
    return "sha256:" + P4ReplicationAudit.sha256Hex(Data(canonical.utf8))
  }()

  private static func harnessSHAString() -> String {
    // #file = this source file's absolute path at compile time.
    let data = (try? Data(contentsOf: URL(fileURLWithPath: #filePath))) ?? Data()
    return "sha256:" + sha256Hex(data)
  }

  private func makeContext(checkpointHash: String?) throws -> AuditRunContext {
    AuditRunContext.create(
      modelHash: Self.modelHashString(),
      checkpointHash: checkpointHash,
      repoPath: Self.productRepo,
      harnessSHA: Self.harnessSHAString(),
      configHash: Self.configHashString)
  }

  private func newStore(checkpointHash: String?) throws -> AuditArtifactStore {
    try AuditArtifactStore(context: makeContext(checkpointHash: checkpointHash),
                           baseDirectory: Self.replicationBase)
  }

  private func verifyOrThrow(_ store: AuditArtifactStore) throws {
    let checks = try store.verify()
    let data = try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: store.directory.appendingPathComponent("r0_verify.json"))
    let failed = checks.filter { !$0.value }
    guard failed.isEmpty else {
      throw NSError(domain: "P4Replication.R0", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "R0 verify failed: \(failed.keys.joined(separator: ","))"])
    }
    store.record("r0_verify", payload: ["result": "ALL_PASS"])
  }

  // MARK: canonical serialization + anchor (verbatim from original harness)

  private func canonical(_ v: JSONValue) -> String {
    switch v {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .number(let n): return n.description
    case .string(let s):
      return "\"" + s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n") + "\""
    case .array(let a): return "[" + a.map { canonical($0) }.joined(separator: ",") + "]"
    case .object(let o):
      return "{" + o.keys.sorted().map { k in canonical(.string(k)) + ":" + canonical(o[k]!) }.joined(separator: ",") + "}"
    }
  }

  private func messageCanonical(_ msg: JSONValue) -> String {
    let obj = msg.object ?? [:]
    let role = obj["role"]?.string ?? ""
    let content: String
    switch obj["content"] {
    case .string(let s): content = s
    default: content = ""
    }
    let tc = obj["tool_calls"].map { canonical($0) } ?? "-"
    return [role, content, tc].joined(separator: "\u{1F}")
  }

  private func anchorHex(_ history: [JSONValue]) -> String {
    let joined = history.map(messageCanonical).joined(separator: "\u{1E}")
    return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func transcriptText(_ history: [JSONValue]) -> String {
    history.map { ($0.object?["content"]?.string) ?? "" }.joined(separator: "\n")
  }

  // MARK: message builders (verbatim from original harness)

  private func userMsg(_ text: String) -> JSONValue {
    .object(["role": .string("user"), "content": .string(text)])
  }

  private func assistantMsg(_ text: String, _ toolCalls: [String]) -> JSONValue {
    var object: [String: JSONValue] = [
      "role": .string("assistant"),
      "content": text.isEmpty ? .null : .string(text)
    ]
    if !toolCalls.isEmpty {
      object["tool_calls_raw"] = .string(toolCalls.joined(separator: " ||| "))
    }
    return .object(object)
  }

  // MARK: records (original structs + R0 fields)

  struct TurnRecord: Codable {
    var text: String
    var toolCalls: [String]
    var generationTokens: String
    var promptTokens: String
    var streamEnd: String
  }
  struct BranchRecord: Codable { var t1: TurnRecord; var t2: TurnRecord }
  struct BaseRecord: Codable {
    var key: String
    var position: Int
    var anchor: String
    var tensorSHA: String
    var metaSHA: String
    var transcript: String
  }
  struct IdentityRecord: Codable {
    var id1: Bool; var id2: Bool; var id3: Bool; var id4: Bool
    var tensorSHA: String; var key: String; var position: Int; var anchor: String
  }
  struct RunSummary: Codable {
    var role: String
    var sample: String
    var run: String
    var order: String
    var r0RunUUID: String
    var base: BaseRecord
    var aID: IdentityRecord
    var bID: IdentityRecord
    var a: BranchRecord
    var b: BranchRecord
    var checkpointsBefore: Int
    var checkpointsAfter: Int
    var poolBefore: Int
    var poolAfter: Int
  }
  struct FormSummary: Codable {
    var role: String
    var r0RunUUID: String
    var base: BaseRecord
    var checkpointsBefore: Int
    var checkpointsAfter: Int
    var poolBefore: Int
    var poolAfter: Int
  }

  private func writeRunSummary(_ store: AuditArtifactStore, _ summary: RunSummary) throws {
    let data = try JSONEncoder().encode(summary)
    let obj = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
    try store.writeSummary(obj)
  }

  private func writeFormSummary(_ store: AuditArtifactStore, _ summary: FormSummary) throws {
    let data = try JSONEncoder().encode(summary)
    let obj = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
    try store.writeSummary(obj)
  }

  // MARK: base record (verbatim logic)

  private func baseRecord(sessionId: String, fixture: URL) throws -> BaseRecord {
    let metaURL = fixture.appendingPathComponent("default_\(sessionId)_main.meta.json")
    let tensorURL = fixture.appendingPathComponent("default_\(sessionId)_main.safetensors")
    let metaData = try Data(contentsOf: metaURL)
    let metaObj = try JSONDecoder().decode([String: JSONValue].self, from: metaData)
    let history: [JSONValue]
    switch metaObj["history"] {
    case .array(let a): history = a
    default: throw NSError(domain: "P4Replication", code: 1, userInfo: [NSLocalizedDescriptionKey: "fixture meta has no history array"])
    }
    return BaseRecord(
      key: "default_\(sessionId)_main",
      position: history.count,
      anchor: anchorHex(history),
      tensorSHA: try NativeMLX.sha256HexOfFile(at: tensorURL),
      metaSHA: try NativeMLX.sha256HexOfFile(at: metaURL),
      transcript: transcriptText(history))
  }

  // MARK: one branch (restore + identity checks + two turns)

  private func runBranch(
    native: NativeMLX, store: AuditArtifactStore, tag: String, sessionId: String, fixture: URL,
    base: BaseRecord, first: String, second: String, config: ModelConfig
  ) async throws -> (BranchRecord, IdentityRecord) {
    store.record("restore_start", payload: ["branch": tag])
    let clock = ContinuousClock()
    let restoreStart = clock.now
    let meta = try await native.loadSessionCache(sessionId: sessionId, from: fixture)
    let restoreMs = clock.now - restoreStart
    store.record("restore_complete", payload: [
      "branch": tag, "position": "\(meta.history.count)",
      "duration_ms": "\(restoreMs.components.seconds * 1000 + restoreMs.components.attoseconds / 1_000_000_000_000_000)"])

    // ID-1..4 (verbatim semantics: artifact / addressing / position / anchor)
    let tensorURL = fixture.appendingPathComponent("default_\(sessionId)_main.safetensors")
    let tensorSHA = try NativeMLX.sha256HexOfFile(at: tensorURL)
    let restoredAnchor = anchorHex(meta.history)
    let id = IdentityRecord(
      id1: tensorSHA == base.tensorSHA,
      id2: "default_\(sessionId)_main" == base.key,
      id3: meta.history.count == base.position,
      id4: restoredAnchor == base.anchor,
      tensorSHA: tensorSHA,
      key: "default_\(sessionId)_main",
      position: meta.history.count,
      anchor: restoredAnchor)
    store.record("identity_checks", payload: [
      "branch": tag,
      "id1_artifact_sha": id.id1 ? "YES" : "NO",
      "id2_key": id.id2 ? "YES" : "NO",
      "id3_position": id.id3 ? "YES" : "NO",
      "id4_anchor": id.id4 ? "YES" : "NO"])

    var messages = meta.history
    let r1 = try await turn(native: native, store: store, tag: "\(tag)-t1", sessionId: sessionId,
                            messages: messages + [userMsg(first)], config: config)
    messages = messages + [userMsg(first), assistantMsg(r1.text, r1.toolCalls)]
    let r2 = try await turn(native: native, store: store, tag: "\(tag)-t2", sessionId: sessionId,
                            messages: messages + [userMsg(second)], config: config)
    return (BranchRecord(t1: r1, t2: r2), id)
  }

  private func turn(
    native: NativeMLX, store: AuditArtifactStore, tag: String, sessionId: String,
    messages: [JSONValue], config: ModelConfig
  ) async throws -> TurnRecord {
    let requestId = "p4repl-\(tag)"
    await RuntimeLifecycleCoordinator.shared.register(requestID: requestId, sessionID: sessionId)
    defer { Task { await RuntimeLifecycleCoordinator.shared.finish(requestID: requestId, success: true, reason: "p4repl") } }
    var chunks: [String] = []
    var toolCalls: [String] = []
    var gen = "NONE", prompt = "NONE", streamEnd = "NORMAL"
    store.record("generate_start", payload: ["turn": tag])
    let clock = ContinuousClock()
    let start = clock.now
    do {
      let result = try await native.generate(
        requestId: requestId,
        sessionId: sessionId,
        logicalBranchId: "main",
        messages: messages,
        tools: nil,
        config: config,
        onChunk: { chunks.append($0) },
        onToolCall: { parsed in
          toolCalls.append("\(parsed.name) \(parsed.argumentsJSON)")
        })
      gen = result.usage.map { String($0.generationTokens) } ?? "NONE"
      prompt = result.usage.map { String($0.promptTokens) } ?? "NONE"
    } catch {
      streamEnd = "THREW: \(error)"
    }
    let ms = clock.now - start
    store.record("generate_complete", payload: [
      "turn": tag, "stream_end": streamEnd == "NORMAL" ? "NORMAL" : "ERROR",
      "duration_ms": "\(ms.components.seconds * 1000 + ms.components.attoseconds / 1_000_000_000_000_000)"])
    let text = chunks.joined()
    store.record("turn_result", payload: [
      "turn": tag, "text_chars": "\(text.count)", "text": text,
      "tool_call_count": "\(toolCalls.count)",
      "generation_tokens": gen, "prompt_tokens": prompt, "stream_end": streamEnd])
    return TurnRecord(text: text, toolCalls: toolCalls, generationTokens: gen,
                      promptTokens: prompt, streamEnd: streamEnd)
  }

  private func makeConfig() -> ModelConfig {
    var config = ModelConfig()
    config.temperature = 0
    config.maxTokens = 128
    return config
  }

  private func startNative(store: AuditArtifactStore) async throws -> NativeMLX {
    RuntimeTuning.conditionalRestoreEnabled = false
    RuntimeTuning.rollforwardEnabled = false
    store.record("model_load_start")
    let clock = ContinuousClock()
    let start = clock.now
    let native = NativeMLX(
      info: ModelInfo(path: Self.modelPath, kind: .mlx),
      config: ModelConfig())
    try await native.start(ModelInfo(path: Self.modelPath, kind: .mlx), port: 18134)
    let ms = clock.now - start
    store.record("model_load_complete", payload: [
      "duration_ms": "\(ms.components.seconds * 1000 + ms.components.attoseconds / 1_000_000_000_000_000)",
      "model": "Nail-Qwen3.6-35B-A3B-MLX"])
    return native
  }

  private func dirEntries(_ url: URL) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count ?? -1
  }

  // MARK: one run (order parameterized; Run1 = A,B; Run2 = B,A)

  private func runOnce(sample: String, run: String, order: String, sessionId: String, fixture: URL,
                       dA1: String, dA2: String, dB1: String, dB2: String) async throws {
    let store = try newStore(checkpointHash: nil)
    store.record("run_start", payload: ["experiment": "P4-replication", "sample": sample, "run": run, "order": order])
    defer { store.finish() }

    let before = dirEntries(Self.realCheckpoints)
    let poolBefore = dirEntries(Self.prefixPool)
    store.record("isolation_baseline", payload: [
      "real_branch_checkpoints_before": "\(before)", "prefix_pool_before": "\(poolBefore)"])

    // base-record BEFORE any branch runs (design §1)
    let base = try baseRecord(sessionId: sessionId, fixture: fixture)
    store.record("base_record", payload: [
      "key": base.key, "position": "\(base.position)", "anchor": base.anchor,
      "tensorSHA": base.tensorSHA, "metaSHA": base.metaSHA])

    let native = try await startNative(store: store)
    defer { Task { try? await native.stop() } }

    let config = makeConfig()
    let (aRec, aID) = try await runBranch(native: native, store: store, tag: "\(sample)-\(run)-A",
                                          sessionId: sessionId, fixture: fixture,
                                          base: base, first: dA1, second: dA2, config: config)
    let (bRec, bID) = try await runBranch(native: native, store: store, tag: "\(sample)-\(run)-B",
                                          sessionId: sessionId, fixture: fixture,
                                          base: base, first: dB1, second: dB2, config: config)

    let after = dirEntries(Self.realCheckpoints)
    let poolAfter = dirEntries(Self.prefixPool)
    store.record("isolation_check", payload: [
      "real_branch_checkpoints_after": "\(after)", "prefix_pool_after": "\(poolAfter)"])

    let summary = RunSummary(role: "run", sample: sample, run: run, order: order,
                             r0RunUUID: store.runUUID, base: base,
                             aID: aID, bID: bID, a: aRec, b: bRec,
                             checkpointsBefore: before, checkpointsAfter: after,
                             poolBefore: poolBefore, poolAfter: poolAfter)
    try writeRunSummary(store, summary)
    try store.writeHashes([
      "model": Self.modelHashString(),
      "checkpoint_tensor_sha256": base.tensorSHA,
      "checkpoint_meta_sha256": base.metaSHA])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["sample": sample, "run": run])
  }

  // MARK: Sample 1 (existing real checkpoint, read-only fixture)

  func testP4ReplicationS1Run1() async throws {
    try await runOnce(sample: "s1", run: "run1", order: "A-first", sessionId: Self.s1Session,
                      fixture: Self.s1Fixture,
                      dA1: Self.s1dA1, dA2: Self.s1dA2, dB1: Self.s1dB1, dB2: Self.s1dB2)
  }

  func testP4ReplicationS1Run2() async throws {
    try await runOnce(sample: "s1", run: "run2", order: "B-first", sessionId: Self.s1Session,
                      fixture: Self.s1Fixture,
                      dA1: Self.s1dA1, dA2: Self.s1dA2, dB1: Self.s1dB1, dB2: Self.s1dB2)
  }

  // MARK: Sample 2 — freeze, form, save (one process, fresh fixture)

  func testP4ReplicationS2Form() async throws {
    let store = try newStore(checkpointHash: "formed-in-this-run")
    store.record("run_start", payload: ["experiment": "P4-replication", "role": "form"])
    defer { store.finish() }

    // Freeze BEFORE any computation (design: freeze-then-form)
    for (i, t) in Self.s2Script.enumerated() { store.record("frozen_script", payload: ["index": "\(i)", "text": t]) }
    store.record("frozen_futures", payload: [
      "dA1": Self.s2dA1, "dA2": Self.s2dA2, "dB1": Self.s2dB1, "dB2": Self.s2dB2,
      "anchorA": Self.s2AnchorA.joined(separator: "|"),
      "entities": Self.s2Entities.joined(separator: "|")])

    let before = dirEntries(Self.realCheckpoints)
    let poolBefore = dirEntries(Self.prefixPool)
    store.record("isolation_baseline", payload: [
      "real_branch_checkpoints_before": "\(before)", "prefix_pool_before": "\(poolBefore)"])

    let native = try await startNative(store: store)
    defer { Task { try? await native.stop() } }

    let config = makeConfig()
    var messages: [JSONValue] = []
    for (i, u) in Self.s2Script.enumerated() {
      messages.append(userMsg(u))
      let r = try await turn(native: native, store: store, tag: "s2-form-t\(i + 1)",
                             sessionId: Self.s2Session, messages: messages, config: config)
      messages.append(assistantMsg(r.text, r.toolCalls))
    }

    store.record("checkpoint_save_start")
    let savedURL = try await native.saveSessionCache(sessionId: Self.s2Session, to: Self.s2Fixture)
    store.record("checkpoint_save_complete", payload: ["saved_to": savedURL.path])

    let base = try baseRecord(sessionId: Self.s2Session, fixture: Self.s2Fixture)
    store.record("base_record", payload: [
      "key": base.key, "position": "\(base.position)", "anchor": base.anchor,
      "tensorSHA": base.tensorSHA, "metaSHA": base.metaSHA])

    let after = dirEntries(Self.realCheckpoints)
    let poolAfter = dirEntries(Self.prefixPool)
    store.record("isolation_check", payload: [
      "real_branch_checkpoints_after": "\(after)", "prefix_pool_after": "\(poolAfter)"])

    let summary = FormSummary(role: "form", r0RunUUID: store.runUUID, base: base,
                              checkpointsBefore: before, checkpointsAfter: after,
                              poolBefore: poolBefore, poolAfter: poolAfter)
    try writeFormSummary(store, summary)
    try store.writeHashes([
      "model": Self.modelHashString(),
      "checkpoint_tensor_sha256": base.tensorSHA,
      "checkpoint_meta_sha256": base.metaSHA])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["role": "form"])
  }

  // MARK: Sample 2 runs

  func testP4ReplicationS2Run1() async throws {
    try await runOnce(sample: "s2", run: "run1", order: "A-first", sessionId: Self.s2Session,
                      fixture: Self.s2Fixture,
                      dA1: Self.s2dA1, dA2: Self.s2dA2, dB1: Self.s2dB1, dB2: Self.s2dB2)
  }

  func testP4ReplicationS2Run2() async throws {
    try await runOnce(sample: "s2", run: "run2", order: "B-first", sessionId: Self.s2Session,
                      fixture: Self.s2Fixture,
                      dA1: Self.s2dA1, dA2: Self.s2dA2, dB1: Self.s2dB1, dB2: Self.s2dB2)
  }

  // MARK: Mechanical adjudication — J1..J6 verbatim from design §6

  /// Reads ONLY the summary.json of role=run directories under THIS
  /// replication's results/replication/ base. Original-run artifacts
  /// (/tmp/simigo-p4/) are never touched.
  func testP4ReplicationAdjudicate() throws {
    let store = try newStore(checkpointHash: nil)
    store.record("run_start", payload: ["experiment": "P4-replication", "role": "judgment"])
    defer { store.finish() }

    // Collect role=run summaries from this replication only.
    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(atPath: Self.replicationBase.path)
    var summaries: [String: (RunSummary, String)] = [:]
    for name in entries.sorted() {
      let dir = Self.replicationBase.appendingPathComponent(name, isDirectory: true)
      let summaryURL = dir.appendingPathComponent("summary.json")
      guard let data = try? Data(contentsOf: summaryURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (obj["role"] as? String) == "run"
      else { continue }
      let decoded = try JSONDecoder().decode(RunSummary.self, from: data)
      let key = "\(decoded.sample)|\(decoded.run)"
      guard summaries[key] == nil else {
        throw NSError(domain: "P4Replication.Judgment", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "duplicate summary for \(key) — stale run dirs present; clean replication base and rerun the full sequence"])
      }
      summaries[key] = (decoded, name)
    }
    guard let s1r1 = summaries["s1|run1"], let s1r2 = summaries["s1|run2"],
          let s2r1 = summaries["s2|run1"], let s2r2 = summaries["s2|run2"], summaries.count == 4 else {
      throw NSError(domain: "P4Replication.Judgment", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "expected exactly 4 run summaries (s1/s2 × run1/run2), found: \(summaries.keys.sorted().joined(separator: ","))"])
    }
    store.record("judgment_inputs", payload: [
      "s1_run1": s1r1.1, "s1_run2": s1r2.1, "s2_run1": s2r1.1, "s2_run2": s2r2.1])

    func ngram4(_ s: String) -> Set<String> {
      let chars = Array(s)
      guard chars.count >= 4 else { return [] }
      var out = Set<String>()
      for i in 0...(chars.count - 4) { out.insert(String(chars[i...(i + 3)])) }
      return out
    }
    func shares4gram(_ a: String, _ b: String) -> Bool {
      !ngram4(a).intersection(ngram4(b)).isEmpty
    }
    func containsAny(_ s: String, _ set: [String]) -> Bool {
      set.contains { s.contains($0) }
    }

    // Sample-1 B-anchor: 4-gram shared with transcript, excluding probe 4-grams
    let s1ProbeNgrams = ngram4(Self.s1dA1 + Self.s1dA2 + Self.s1dB1 + Self.s1dB2)
    func s1AnchorB(_ output: String, _ transcript: String) -> Bool {
      !ngram4(output).intersection(ngram4(transcript)).subtracting(s1ProbeNgrams).isEmpty
    }

    func judge(anchorA: [String], run1: RunSummary, run2: RunSummary,
               anchorB: (String, String) -> Bool) -> [String: String] {
      var v: [String: String] = [:]
      // J1 identity (all restores, both runs) + cross-run base equality
      let idOK = [run1.aID, run1.bID, run2.aID, run2.bID].allSatisfy { $0.id1 && $0.id2 && $0.id3 && $0.id4 }
      let baseOK = run1.base.anchor == run2.base.anchor
        && run1.base.position == run2.base.position
        && run1.base.tensorSHA == run2.base.tensorSHA
        && run1.base.key == run2.base.key
      v["J1_identity"] = (idOK && baseOK) ? "PASS" : "INCONCLUSIVE"

      // J2 divergence
      func divergence(_ r: RunSummary) -> Bool {
        let a = r.a.t1.text + r.a.t2.text
        let b = r.b.t1.text + r.b.t2.text
        return !a.isEmpty && !b.isEmpty && a != b
      }
      v["J2_divergence"] = (divergence(run1) && divergence(run2)) ? "PASS" : "FAIL"

      // J3 content sensitivity (anchoring of first turns)
      func anchoring(_ r: RunSummary) -> Bool {
        containsAny(r.a.t1.text, anchorA) && anchorB(r.b.t1.text, r.base.transcript)
      }
      v["J3_anchoring"] = (anchoring(run1) && anchoring(run2)) ? "PASS" : "FAIL"

      // J4 order independence (verbatim across swapped-order runs)
      v["J4_order_independence"] =
        (run1.a.t1.text == run2.a.t1.text && run1.a.t2.text == run2.a.t2.text
          && run1.b.t1.text == run2.b.t1.text && run1.b.t2.text == run2.b.t2.text)
        ? "PASS" : "FAIL"

      // J5 isolation
      func isolation(_ r: RunSummary) -> Bool {
        r.checkpointsBefore == r.checkpointsAfter && (r.poolAfter - r.poolBefore) == 0
      }
      v["J5_isolation"] = (isolation(run1) && isolation(run2)) ? "PASS" : "INCONCLUSIVE"

      // J6 independent evolution
      func evolution(_ r: RunSummary) -> Bool {
        func ok(_ own: BranchRecord, _ other: BranchRecord) -> Bool {
          guard !own.t2.text.isEmpty else { return false }
          if own.t2.text == other.t1.text || own.t2.text == other.t2.text { return false }
          return shares4gram(own.t2.text, own.t1.text + r.base.transcript)
        }
        return ok(r.a, r.b) && ok(r.b, r.a)
      }
      v["J6_evolution"] = (evolution(run1) && evolution(run2)) ? "PASS" : "FAIL"

      let verdict: String
      if v["J1_identity"] == "INCONCLUSIVE" || v["J5_isolation"] == "INCONCLUSIVE" {
        verdict = "INCONCLUSIVE"
      } else if v.values.allSatisfy({ $0 == "PASS" }) {
        verdict = "PASS"
      } else {
        verdict = "FAIL"
      }
      v["verdict"] = verdict
      return v
    }

    let s1 = judge(anchorA: Self.s1AnchorA, run1: s1r1.0, run2: s1r2.0) { out, transcript in
      s1AnchorB(out, transcript)
    }
    let s2 = judge(anchorA: Self.s2AnchorA, run1: s2r1.0, run2: s2r2.0) { out, _ in
      containsAny(out, Self.s2Entities)
    }

    for (k, val) in s1 { store.record("judgment", payload: ["cell": "s1_\(k)", "value": val]) }
    for (k, val) in s2 { store.record("judgment", payload: ["cell": "s2_\(k)", "value": val]) }

    let overall: String
    if s1["verdict"] == "INCONCLUSIVE" || s2["verdict"] == "INCONCLUSIVE" {
      overall = "INCONCLUSIVE"
    } else if s1["verdict"] == "PASS" && s2["verdict"] == "PASS" {
      overall = "PASS"
    } else {
      overall = "FAIL"
    }
    store.record("judgment", payload: ["cell": "overall", "value": overall])
    store.record("judgment_note", payload: [
      "text": "mechanical application of design 792afbc §6 pre-registered rules; sample-3 model dimension remains a registered coverage gap"])

    var judgment: [String: Any] = [:]
    judgment["s1"] = s1
    judgment["s2"] = s2
    judgment["overall"] = overall
    judgment["inputs"] = ["s1_run1": s1r1.1, "s1_run2": s1r2.1, "s2_run1": s2r1.1, "s2_run2": s2r2.1]
    let jdata = try JSONSerialization.data(withJSONObject: judgment, options: [.prettyPrinted, .sortedKeys])
    try jdata.write(to: store.directory.appendingPathComponent("judgment.json"))
    try store.writeHashes(["model": Self.modelHashString()])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["role": "judgment", "overall": overall])
    print("[p4-repl] overall: \(overall)")
  }
}
