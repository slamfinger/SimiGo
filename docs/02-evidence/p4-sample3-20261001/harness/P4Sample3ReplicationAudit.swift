import XCTest
import Foundation
import CryptoKit
@testable import SimiGo

/// P4 Sample-3 Replication (G-β) — model-dimension independent sample
/// under the R0 audit framework.
///
/// Human direction (G-β): same protocol, same criteria, independent
/// sample; NO new variables. Sample-3 executes the registered P4
/// protocol (design 792afbc) on a second, architecturally distinct
/// MLX model: Qwen3-Coder-30B-A3B-Instruct-4bit (registered
/// RUNTIME_POSITIVE_CONTROL; standard-attention MoE vs the base
/// model's GDN-hybrid family).
///
/// Protocol-faithfulness notes:
/// · Frozen inputs follow the Sample-2 precedent: a NEW 8-turn script
///   on a new topic, frozen HERE before any computation, with its Δ
///   inputs / anchor words / entities pre-registered in the same
///   structural pattern as S1/S2.
/// · J1..J6 are applied verbatim (same rules, S3's own anchor sets).
/// · Run2 GENUINELY swaps the in-process branch order (design §4).
///   Audit finding F-5 (G-α doc): the original P4 harness's aFirst
///   parameter was decorative — both runs executed A-then-B, so J4
///   there evidences cross-process determinism, not order-permuted
///   independence. Sample-3 implements the swap as registered.
/// · Isolation witness upgraded per G-α F-2/F-3: RECURSIVE content
///   hashing (the depth-1 pool witness was vacuous); checkpoint and
///   pool stores both get real content-level witnesses.
///
/// PRE-REGISTERED JUDGMENT (frozen before execution): J1..J6 exactly
/// as in design 792afbc §6 / P4 replication harness. ID failure ⇒
/// INCONCLUSIVE; J5 failure ⇒ INCONCLUSIVE; J2/J3/J4/J6 failure ⇒
/// FAIL (valid result, criteria immutable); all PASS (both runs,
/// both branches) ⇒ PASS.

final class P4Sample3ReplicationAudit: XCTestCase {
  // MARK: Sample-3 frozen constants (freeze precedes all computation)

  static let modelPath =
    "/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d"
  static let modelName = "Qwen3-Coder-30B-A3B-Instruct-4bit@6e302ea6"
  static let work = URL(fileURLWithPath: "/tmp/simigo-p4-replication", isDirectory: true)
  static let realCheckpoints = URL(fileURLWithPath: "/Users/mr.simi/.simigo/branch-checkpoints", isDirectory: true)
  static let prefixPool = URL(fileURLWithPath: "/Users/mr.simi/.simigo/prefix-pool", isDirectory: true)
  static let productRepo = "/Users/mr.simi/Documents/SimiGo"

  static let s3Session = "p4-sample3-9d2e41"
  static let s3Fixture = URL(fileURLWithPath: "/tmp/simigo-p4-replication/sample3", isDirectory: true)
  static let replicationBase = P4Sample3ReplicationAudit.work.appendingPathComponent("results/replication-sample3", isDirectory: true)

  // Frozen 8-turn script (new topic; user turns; assistant = real gens)
  static let s3Script: [String] = [
    "我想开一家小型咖啡店，计划5月20日试营业，帮我列一个不慌乱的准备节奏。",
    "设备方面最该先定哪几样？",
    "磨豆机和咖啡机如果只能先买一样，先买哪个？",
    "菜单初期上多少款比较合适？",
    "试营业前一周要完成哪些事？",
    "咖啡豆库存大概要备多少？",
    "如果试营业当天人手只有两个人，动线怎么安排最顺？",
    "最后帮我把整体准备顺序复述一遍。"
  ]
  // Frozen futures (S2 structural pattern)
  static let s3dA1 = "PALACE-1 P4 probe: 这个会话此前在规划什么？用一句话概括。"
  static let s3dA2 = "接着上面的总结，再补充一点：这些准备里最重要的一个决定是什么？为什么？"
  static let s3dB1 = "从这个会话中找出一个具体的物品名称或日期，原样写出，不要解释。"
  static let s3dB2 = "用一句话说明你是从会话的哪个部分注意到它的。"
  static let s3AnchorA = ["咖啡", "开业", "准备", "试营业"]
  static let s3Entities = ["咖啡店", "磨豆机", "5月20日", "菜单", "试营业"]

  // MARK: R0 helpers

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func modelHashString() -> String {
    let revision = (P4Sample3ReplicationAudit.modelPath as NSString).lastPathComponent
    let configSHA = (try? Data(contentsOf: URL(fileURLWithPath: P4Sample3ReplicationAudit.modelPath + "/config.json")))
      .map { "config=sha256:" + sha256Hex($0) } ?? "config=UNREADABLE"
    return "\(modelName);\(configSHA)"
  }

  private static let configHashString: String = {
    let canonical = "temperature=0;maxTokens=128;tools=nil;greedy"
    return "sha256:" + P4Sample3ReplicationAudit.sha256Hex(Data(canonical.utf8))
  }()

  private static func harnessSHAString() -> String {
    let data = (try? Data(contentsOf: URL(fileURLWithPath: #filePath))) ?? Data()
    return "sha256:" + sha256Hex(data)
  }

  private func newStore() throws -> AuditArtifactStore {
    try AuditArtifactStore(
      context: AuditRunContext.create(
        modelHash: P4Sample3ReplicationAudit.modelHashString(),
        checkpointHash: nil,
        repoPath: P4Sample3ReplicationAudit.productRepo,
        harnessSHA: P4Sample3ReplicationAudit.harnessSHAString(),
        configHash: P4Sample3ReplicationAudit.configHashString),
      baseDirectory: P4Sample3ReplicationAudit.replicationBase)
  }

  private func verifyOrThrow(_ store: AuditArtifactStore) throws {
    let checks = try store.verify()
    let data = try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: store.directory.appendingPathComponent("r0_verify.json"))
    let failed = checks.filter { !$0.value }
    guard failed.isEmpty else {
      throw NSError(domain: "P4S3.R0", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "R0 verify failed: \(failed.keys.joined(separator: ","))"])
    }
    store.record("r0_verify", payload: ["result": "ALL_PASS"])
  }

  // MARK: serialization + records (mirror P4 replication harness)

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
    var model: String
    var base: BaseRecord
    var aID: IdentityRecord
    var bID: IdentityRecord
    var a: BranchRecord
    var b: BranchRecord
    var checkpointsBefore: Int
    var checkpointsAfter: Int
    var poolBefore: Int
    var poolAfter: Int
    var checkpointsSHA256Before: String
    var checkpointsSHA256After: String
    var poolSHA256Before: String
    var poolSHA256After: String
  }
  struct FormSummary: Codable {
    var role: String
    var r0RunUUID: String
    var model: String
    var base: BaseRecord
    var checkpointsBefore: Int
    var checkpointsAfter: Int
    var poolBefore: Int
    var poolAfter: Int
  }

  private func writeSummary<T: Codable>(_ store: AuditArtifactStore, _ summary: T) throws {
    let data = try JSONEncoder().encode(summary)
    let obj = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
    try store.writeSummary(obj)
  }

  // MARK: canonical serialization + anchor (verbatim from P4 harness)

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

  // MARK: recursive content witness (G-α F-3 fix — depth-complete)

  private func recursiveHash(_ url: URL, base: URL, acc: inout [String]) {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: url.path) else { return }
    for e in entries.sorted() {
      let full = url.appendingPathComponent(e)
      var isDir: ObjCBool = false
      fm.fileExists(atPath: full.path, isDirectory: &isDir)
      if isDir.boolValue {
        recursiveHash(full, base: base, acc: &acc)
      } else {
        let rel = full.path.hasPrefix(base.path + "/")
          ? String(full.path.dropFirst(base.path.count + 1)) : full.path
        let data = (try? Data(contentsOf: full)) ?? Data()
        acc.append("\(rel):" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
      }
    }
  }

  private func dirContentSHA256(_ url: URL) -> String {
    var acc: [String] = []
    recursiveHash(url, base: url, acc: &acc)
    let joined = acc.joined(separator: "\n")
    return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func dirEntries(_ url: URL) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count ?? -1
  }

  // MARK: base record

  private func baseRecord(sessionId: String, fixture: URL) throws -> BaseRecord {
    let metaURL = fixture.appendingPathComponent("default_\(sessionId)_main.meta.json")
    let tensorURL = fixture.appendingPathComponent("default_\(sessionId)_main.safetensors")
    let metaData = try Data(contentsOf: metaURL)
    let metaObj = try JSONDecoder().decode([String: JSONValue].self, from: metaData)
    let history: [JSONValue]
    switch metaObj["history"] {
    case .array(let a): history = a
    default: throw NSError(domain: "P4S3", code: 1, userInfo: [NSLocalizedDescriptionKey: "fixture meta has no history array"])
    }
    return BaseRecord(
      key: "default_\(sessionId)_main",
      position: history.count,
      anchor: anchorHex(history),
      tensorSHA: try NativeMLX.sha256HexOfFile(at: tensorURL),
      metaSHA: try NativeMLX.sha256HexOfFile(at: metaURL),
      transcript: transcriptText(history))
  }

  // MARK: branch (restore + ID-1..4 + two turns)

  private func runBranch(
    native: NativeMLX, store: AuditArtifactStore, tag: String, sessionId: String, fixture: URL,
    base: BaseRecord, first: String, second: String, config: ModelConfig
  ) async throws -> (BranchRecord, IdentityRecord) {
    store.record("restore_start", payload: ["branch": tag])
    let clock = ContinuousClock()
    let rStart = clock.now
    let meta = try await native.loadSessionCache(sessionId: sessionId, from: fixture)
    let rMs = clock.now - rStart
    store.record("restore_complete", payload: [
      "branch": tag, "position": "\(meta.history.count)",
      "duration_ms": "\(rMs.components.seconds * 1000 + rMs.components.attoseconds / 1_000_000_000_000_000)"])

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
    let requestId = "p4s3-\(tag)"
    await RuntimeLifecycleCoordinator.shared.register(requestID: requestId, sessionID: sessionId)
    defer { Task { await RuntimeLifecycleCoordinator.shared.finish(requestID: requestId, success: true, reason: "p4s3") } }
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
      info: ModelInfo(path: P4Sample3ReplicationAudit.modelPath, kind: .mlx),
      config: ModelConfig())
    try await native.start(ModelInfo(path: P4Sample3ReplicationAudit.modelPath, kind: .mlx), port: 18134)
    let ms = clock.now - start
    store.record("model_load_complete", payload: [
      "duration_ms": "\(ms.components.seconds * 1000 + ms.components.attoseconds / 1_000_000_000_000_000)",
      "model": P4Sample3ReplicationAudit.modelName])
    return native
  }

  // MARK: one run — GENUINE order swap (Run1 = A,B; Run2 = B,A)

  private func runOnce(run: String, aFirst: Bool) async throws {
    let store = try newStore()
    store.record("run_start", payload: [
      "experiment": "P4-sample3", "run": run,
      "order": aFirst ? "A-first" : "B-first",
      "order_genuinely_swapped": "YES"])
    defer { store.finish() }

    let before = dirEntries(P4Sample3ReplicationAudit.realCheckpoints)
    let poolBefore = dirEntries(P4Sample3ReplicationAudit.prefixPool)
    let cpSHA256Before = dirContentSHA256(P4Sample3ReplicationAudit.realCheckpoints)
    let poolSHA256Before = dirContentSHA256(P4Sample3ReplicationAudit.prefixPool)
    store.record("isolation_baseline", payload: [
      "real_branch_checkpoints_before": "\(before)", "prefix_pool_before": "\(poolBefore)",
      "checkpoints_content_sha256_before": cpSHA256Before,
      "pool_content_sha256_before": poolSHA256Before])

    let base = try baseRecord(sessionId: P4Sample3ReplicationAudit.s3Session,
                              fixture: P4Sample3ReplicationAudit.s3Fixture)
    store.record("base_record", payload: [
      "key": base.key, "position": "\(base.position)", "anchor": base.anchor,
      "tensorSHA": base.tensorSHA, "metaSHA": base.metaSHA])

    let native = try await startNative(store: store)
    defer { Task { try? await native.stop() } }

    let config = makeConfig()
    // GENUINE order swap (design §4; F-5): branch EXECUTION order
    // follows the run's order parameter.
    let aPair: (BranchRecord, IdentityRecord)
    let bPair: (BranchRecord, IdentityRecord)
    if aFirst {
      aPair = try await runBranch(native: native, store: store, tag: "s3-\(run)-A",
                                  sessionId: P4Sample3ReplicationAudit.s3Session,
                                  fixture: P4Sample3ReplicationAudit.s3Fixture,
                                  base: base, first: P4Sample3ReplicationAudit.s3dA1,
                                  second: P4Sample3ReplicationAudit.s3dA2, config: config)
      bPair = try await runBranch(native: native, store: store, tag: "s3-\(run)-B",
                                  sessionId: P4Sample3ReplicationAudit.s3Session,
                                  fixture: P4Sample3ReplicationAudit.s3Fixture,
                                  base: base, first: P4Sample3ReplicationAudit.s3dB1,
                                  second: P4Sample3ReplicationAudit.s3dB2, config: config)
    } else {
      bPair = try await runBranch(native: native, store: store, tag: "s3-\(run)-B",
                                  sessionId: P4Sample3ReplicationAudit.s3Session,
                                  fixture: P4Sample3ReplicationAudit.s3Fixture,
                                  base: base, first: P4Sample3ReplicationAudit.s3dB1,
                                  second: P4Sample3ReplicationAudit.s3dB2, config: config)
      aPair = try await runBranch(native: native, store: store, tag: "s3-\(run)-A",
                                  sessionId: P4Sample3ReplicationAudit.s3Session,
                                  fixture: P4Sample3ReplicationAudit.s3Fixture,
                                  base: base, first: P4Sample3ReplicationAudit.s3dA1,
                                  second: P4Sample3ReplicationAudit.s3dA2, config: config)
    }
    let (aRec, aID) = aPair
    let (bRec, bID) = bPair

    let after = dirEntries(P4Sample3ReplicationAudit.realCheckpoints)
    let poolAfter = dirEntries(P4Sample3ReplicationAudit.prefixPool)
    let cpSHA256After = dirContentSHA256(P4Sample3ReplicationAudit.realCheckpoints)
    let poolSHA256After = dirContentSHA256(P4Sample3ReplicationAudit.prefixPool)
    store.record("isolation_check", payload: [
      "real_branch_checkpoints_after": "\(after)", "prefix_pool_after": "\(poolAfter)",
      "checkpoints_content_sha256_after": cpSHA256After,
      "pool_content_sha256_after": poolSHA256After])

    let summary = RunSummary(
      role: "run", sample: "s3", run: run,
      order: aFirst ? "A-first" : "B-first",
      r0RunUUID: store.runUUID, model: P4Sample3ReplicationAudit.modelName,
      base: base, aID: aID, bID: bID, a: aRec, b: bRec,
      checkpointsBefore: before, checkpointsAfter: after,
      poolBefore: poolBefore, poolAfter: poolAfter,
      checkpointsSHA256Before: cpSHA256Before, checkpointsSHA256After: cpSHA256After,
      poolSHA256Before: poolSHA256Before, poolSHA256After: poolSHA256After)
    try writeSummary(store, summary)
    try store.writeHashes([
      "model": P4Sample3ReplicationAudit.modelHashString(),
      "checkpoint_tensor_sha256": base.tensorSHA,
      "checkpoint_meta_sha256": base.metaSHA])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["run": run])
  }

  // MARK: Sample-3 formation (freeze → form → save)

  func testP4S3Form() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P4-sample3", "role": "form"])
    defer { store.finish() }

    for (i, t) in P4Sample3ReplicationAudit.s3Script.enumerated() {
      store.record("frozen_script", payload: ["index": "\(i)", "text": t])
    }
    store.record("frozen_futures", payload: [
      "dA1": P4Sample3ReplicationAudit.s3dA1, "dA2": P4Sample3ReplicationAudit.s3dA2,
      "dB1": P4Sample3ReplicationAudit.s3dB1, "dB2": P4Sample3ReplicationAudit.s3dB2,
      "anchorA": P4Sample3ReplicationAudit.s3AnchorA.joined(separator: "|"),
      "entities": P4Sample3ReplicationAudit.s3Entities.joined(separator: "|")])

    let before = dirEntries(P4Sample3ReplicationAudit.realCheckpoints)
    let poolBefore = dirEntries(P4Sample3ReplicationAudit.prefixPool)
    store.record("isolation_baseline", payload: [
      "real_branch_checkpoints_before": "\(before)", "prefix_pool_before": "\(poolBefore)"])

    let native = try await startNative(store: store)
    defer { Task { try? await native.stop() } }

    let config = makeConfig()
    var messages: [JSONValue] = []
    for (i, u) in P4Sample3ReplicationAudit.s3Script.enumerated() {
      messages.append(userMsg(u))
      let r = try await turn(native: native, store: store, tag: "s3-form-t\(i + 1)",
                             sessionId: P4Sample3ReplicationAudit.s3Session,
                             messages: messages, config: config)
      messages.append(assistantMsg(r.text, r.toolCalls))
    }

    store.record("checkpoint_save_start")
    let savedURL = try await native.saveSessionCache(
      sessionId: P4Sample3ReplicationAudit.s3Session, to: P4Sample3ReplicationAudit.s3Fixture)
    store.record("checkpoint_save_complete", payload: ["saved_to": savedURL.path])

    let base = try baseRecord(sessionId: P4Sample3ReplicationAudit.s3Session,
                              fixture: P4Sample3ReplicationAudit.s3Fixture)
    store.record("base_record", payload: [
      "key": base.key, "position": "\(base.position)", "anchor": base.anchor,
      "tensorSHA": base.tensorSHA, "metaSHA": base.metaSHA])

    let after = dirEntries(P4Sample3ReplicationAudit.realCheckpoints)
    let poolAfter = dirEntries(P4Sample3ReplicationAudit.prefixPool)
    store.record("isolation_check", payload: [
      "real_branch_checkpoints_after": "\(after)", "prefix_pool_after": "\(poolAfter)"])

    let summary = FormSummary(role: "form", r0RunUUID: store.runUUID,
                              model: P4Sample3ReplicationAudit.modelName,
                              base: base,
                              checkpointsBefore: before, checkpointsAfter: after,
                              poolBefore: poolBefore, poolAfter: poolAfter)
    try writeSummary(store, summary)
    try store.writeHashes([
      "model": P4Sample3ReplicationAudit.modelHashString(),
      "checkpoint_tensor_sha256": base.tensorSHA,
      "checkpoint_meta_sha256": base.metaSHA])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["role": "form"])
  }

  // MARK: Sample-3 runs (genuine swap)

  func testP4S3Run1() async throws {
    try await runOnce(run: "run1", aFirst: true)
  }

  func testP4S3Run2() async throws {
    try await runOnce(run: "run2", aFirst: false)
  }

  // MARK: Mechanical adjudication — J1..J6 verbatim (design §6)

  func testP4S3Adjudicate() throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P4-sample3", "role": "judgment"])
    defer { store.finish() }

    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(atPath: P4Sample3ReplicationAudit.replicationBase.path)
    var summaries: [String: (RunSummary, String)] = [:]
    for name in entries.sorted() {
      let dir = P4Sample3ReplicationAudit.replicationBase.appendingPathComponent(name, isDirectory: true)
      let summaryURL = dir.appendingPathComponent("summary.json")
      guard let data = try? Data(contentsOf: summaryURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (obj["role"] as? String) == "run"
      else { continue }
      let decoded = try JSONDecoder().decode(RunSummary.self, from: data)
      guard summaries[decoded.run] == nil else {
        throw NSError(domain: "P4S3.Judgment", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "duplicate summary for run \(decoded.run)"])
      }
      summaries[decoded.run] = (decoded, name)
    }
    guard let r1 = summaries["run1"], let r2 = summaries["run2"], summaries.count == 2 else {
      throw NSError(domain: "P4S3.Judgment", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "expected exactly 2 run summaries, found: \(summaries.keys.sorted().joined(separator: ","))"])
    }
    store.record("judgment_inputs", payload: ["run1": r1.1, "run2": r2.1])

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
    let probeNgrams = ngram4(P4Sample3ReplicationAudit.s3dA1 + P4Sample3ReplicationAudit.s3dA2
                             + P4Sample3ReplicationAudit.s3dB1 + P4Sample3ReplicationAudit.s3dB2)
    func anchorB(_ output: String, _ transcript: String) -> Bool {
      !ngram4(output).intersection(ngram4(transcript)).subtracting(probeNgrams).isEmpty
    }

    let run1 = r1.0, run2 = r2.0
    var v: [String: String] = [:]
    let idOK = [run1.aID, run1.bID, run2.aID, run2.bID].allSatisfy { $0.id1 && $0.id2 && $0.id3 && $0.id4 }
    let baseOK = run1.base.anchor == run2.base.anchor
      && run1.base.position == run2.base.position
      && run1.base.tensorSHA == run2.base.tensorSHA
      && run1.base.key == run2.base.key
    v["J1_identity"] = (idOK && baseOK) ? "PASS" : "INCONCLUSIVE"

    func divergence(_ r: RunSummary) -> Bool {
      let a = r.a.t1.text + r.a.t2.text
      let b = r.b.t1.text + r.b.t2.text
      return !a.isEmpty && !b.isEmpty && a != b
    }
    v["J2_divergence"] = (divergence(run1) && divergence(run2)) ? "PASS" : "FAIL"

    func anchoring(_ r: RunSummary) -> Bool {
      containsAny(r.a.t1.text, P4Sample3ReplicationAudit.s3AnchorA)
        && anchorB(r.b.t1.text, r.base.transcript)
    }
    v["J3_anchoring"] = (anchoring(run1) && anchoring(run2)) ? "PASS" : "FAIL"

    v["J4_order_independence"] =
      (run1.a.t1.text == run2.a.t1.text && run1.a.t2.text == run2.a.t2.text
        && run1.b.t1.text == run2.b.t1.text && run1.b.t2.text == run2.b.t2.text)
      ? "PASS" : "FAIL"

    func isolation(_ r: RunSummary) -> Bool {
      r.checkpointsBefore == r.checkpointsAfter && (r.poolAfter - r.poolBefore) == 0
    }
    let isolationSHA = run1.checkpointsSHA256Before == run1.checkpointsSHA256After
      && run1.poolSHA256Before == run1.poolSHA256After
      && run2.checkpointsSHA256Before == run2.checkpointsSHA256After
      && run2.poolSHA256Before == run2.poolSHA256After
    v["J5_isolation_counts"] = (isolation(run1) && isolation(run2)) ? "PASS" : "INCONCLUSIVE"
    v["J5_isolation_content_sha"] = isolationSHA ? "PASS" : "CHANGED(见 F-2 常态导出注记)"

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
    if v["J1_identity"] == "INCONCLUSIVE" || v["J5_isolation_counts"] == "INCONCLUSIVE" {
      verdict = "INCONCLUSIVE"
    } else if v.values.allSatisfy({ $0 == "PASS" }) {
      verdict = "PASS"
    } else {
      verdict = "FAIL"
    }
    v["verdict"] = verdict

    for (k, val) in v { store.record("judgment", payload: ["cell": k, "value": val]) }
    store.record("judgment_note", payload: [
      "text": "mechanical J1..J6 per design 792afbc §6; order swap GENUINE (F-5); recursive content witness (F-3 fix); pool content changes are registered runtime export behavior (F-2) and are recorded, not judged"])

    var judgment: [String: Any] = [:]
    judgment["cells"] = v
    judgment["overall"] = verdict
    judgment["inputs"] = ["run1": r1.1, "run2": r2.1]
    let jdata = try JSONSerialization.data(withJSONObject: judgment, options: [.prettyPrinted, .sortedKeys])
    try jdata.write(to: store.directory.appendingPathComponent("judgment.json"))
    try store.writeHashes(["model": P4Sample3ReplicationAudit.modelHashString()])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["role": "judgment", "overall": verdict])
    print("[p4s3] overall: \(verdict)")
  }
}
