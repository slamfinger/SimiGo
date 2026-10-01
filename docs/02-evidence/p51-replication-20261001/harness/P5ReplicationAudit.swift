import XCTest
import Foundation
import CryptoKit
@testable import SimiGo

/// P5-1 Replication — Anchor Failure Boundary under the R0 audit
/// framework (Empirical Replication Audit Phase-1, Day 2).
///
/// Replicated proposition (sealed P5-1 / attempt-1 INCONCLUSIVE record
/// + P5-2-0 root cause): in the current backend, continuation with the
/// semantic anchor (history text) stripped but KV tensors intact is
/// REJECTED by the engine — token-ledger bootstrap requires
/// processedTokenCount ≤ rendered-prompt token count; stripping history
/// breaks alignment → ledger cleared → rebuild → KV discarded
/// (cacheEff 0.00). With the anchor intact the same entry consumes the
/// KV (cacheEff ≈ N/(N+d) ≈ 0.99). KV cache is a Representation
/// fragment, not an independent continuation carrier (engine boundary
/// fact, backend-level).
///
/// Harness-integrity revision vs the original attempt-1 harness: the
/// baseline arm now passes metaFull.history + [probe] (the attempt-1
/// baseline passed [probe] only — the registered implementation defect
/// that made attempt-1 INCONCLUSIVE). Treatment arm keeps [probe] (the
/// (S₀,Δ) form). This correction restores the testability of the
/// boundary contrast; it is a harness defect fix, not a judgment change.
///
/// PRE-REGISTERED REPLICATION JUDGMENT (frozen before execution; no
/// criterion may be modified after seeing data):
///   Per cell (sample × Δ ∈ {ΔA₁, ΔB₁}):
///   C1 surgery: treatment ID-1 tensor SHA == base; restoredHistoryCount==0;
///      baseline restoredHistoryCount == base position
///   C2 authenticity: both arms text non-empty; empty text + toolCalls>0
///      ⇒ D5 channel suspicion ⇒ cell INCONCLUSIVE
///   C3 baseline control: baseline usage.cachedPromptTokens > 0 &&
///      cacheEfficiency > 0.9 (KV consumed — entry path proven alive)
///   C4 boundary: treatment usage.cachedPromptTokens == 0/nil &&
///      (cacheEfficiency == 0.0 or nil) (KV rejected → rebuild)
///   C5 divergence: treatment Y ≠ baseline Y′ (verbatim)
///   Baseline control failure (C3) ⇒ INCONCLUSIVE (对照臂失效——attempt-1
///   教训的机械化), never FAIL.
///   C4 failure (treatment consumes KV) ⇒ FAIL (valid result):
///     「anchor-failure→rebuild 边界未复现」不得改判据重试。
///   Isolation broken ⇒ INCONCLUSIVE.
///   Overall: any FAIL ⇒ FAIL; else any INCONCLUSIVE ⇒ INCONCLUSIVE;
///   else PASS.
///
/// Old artifacts (/tmp/simigo-p5/, original P5/P4 outputs) are NEVER
/// read as judgment input.

final class P5ReplicationAudit: XCTestCase {
  // MARK: frozen constants — same experiment objects as the P4 replication

  static let modelPath =
    "<LOCAL_HOME>/.cache/huggingface/hub/models--peculiar-ragdoll--Nail-Qwen3.6-35B-A3B-MLX/snapshots/31a0106483c94e9fbb0a6d3360ff122d47377058"
  static let work = URL(fileURLWithPath: "/tmp/simigo-p5-replication", isDirectory: true)
  static let realCheckpoints = URL(fileURLWithPath: "<LOCAL_HOME>/.simigo/branch-checkpoints", isDirectory: true)
  static let prefixPool = URL(fileURLWithPath: "<LOCAL_HOME>/.simigo/prefix-pool", isDirectory: true)
  static let productRepo = "<LOCAL_HOME>/Documents/SimiGo"

  static let s1Session = "5401315f-faa7-4984-9639-fccef06ae188"
  static let s1Fixture = URL(fileURLWithPath: "/tmp/simigo-palace1-e1/esr2/t3gateB/b0", isDirectory: true)
  static let s2Session = "p4-sample2-7f3a9c"
  // The replication campaign's own S₀′ (formed by P4 replication S2Form,
  // audit-20261001-333E166E) — the same P4→P5 chain the original used.
  static let s2Fixture = URL(fileURLWithPath: "/tmp/simigo-p4-replication/sample2", isDirectory: true)

  // Frozen Δ inputs (verbatim from the P4/P5 preregistration)
  static let s1dA1 = "PALACE-1 E3 probe: 这个会话此前在做什么？用一句话概括。"
  static let s1dB1 = "从这个会话中找出一个文件或目录的名称，原样写出名称，不要解释。"
  static let s2dA1 = "PALACE-1 P4 probe: 这个会话此前在规划什么？用一句话概括。"
  static let s2dB1 = "从这个会话中找出一个具体的地名或日期，原样写出，不要解释。"

  static let replicationBase = P5ReplicationAudit.work.appendingPathComponent("results/replication", isDirectory: true)

  // MARK: R0 helpers (same as P4 replication harness)

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func modelHashString() -> String {
    let revision = (P5ReplicationAudit.modelPath as NSString).lastPathComponent
    let configSHA = (try? Data(contentsOf: URL(fileURLWithPath: P5ReplicationAudit.modelPath + "/config.json")))
      .map { "config=sha256:" + sha256Hex($0) } ?? "config=UNREADABLE"
    return "Nail-Qwen3.6-35B-A3B-MLX@\(revision);\(configSHA)"
  }

  private static let configHashString: String = {
    let canonical = "temperature=0;maxTokens=128;tools=nil;greedy"
    return "sha256:" + P5ReplicationAudit.sha256Hex(Data(canonical.utf8))
  }()

  private static func harnessSHAString() -> String {
    let data = (try? Data(contentsOf: URL(fileURLWithPath: #filePath))) ?? Data()
    return "sha256:" + sha256Hex(data)
  }

  private func newStore() throws -> AuditArtifactStore {
    try AuditArtifactStore(
      context: AuditRunContext.create(
        modelHash: P5ReplicationAudit.modelHashString(),
        checkpointHash: nil,
        repoPath: P5ReplicationAudit.productRepo,
        harnessSHA: P5ReplicationAudit.harnessSHAString(),
        configHash: P5ReplicationAudit.configHashString),
      baseDirectory: P5ReplicationAudit.replicationBase)
  }

  private func verifyOrThrow(_ store: AuditArtifactStore) throws {
    let checks = try store.verify()
    let data = try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: store.directory.appendingPathComponent("r0_verify.json"))
    let failed = checks.filter { !$0.value }
    guard failed.isEmpty else {
      throw NSError(domain: "P5Replication.R0", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "R0 verify failed: \(failed.keys.joined(separator: ","))"])
    }
    store.record("r0_verify", payload: ["result": "ALL_PASS"])
  }

  // MARK: serialization + record types (mirror original P5 harness)

  private func userMsg(_ text: String) -> JSONValue {
    .object(["role": .string("user"), "content": .string(text)])
  }

  struct BaseRecord: Codable {
    var key: String
    var position: Int
    var anchor: String
    var tensorSHA: String
    var metaSHA: String
  }

  struct ArmRecord: Codable {
    var delta: String
    var restoredHistoryCount: Int
    var restoreError: String
    var text: String
    var toolCalls: [String]
    var generationTokens: String
    var cachedPromptTokens: String
    var cacheEfficiency: String
    var streamEnd: String
  }

  struct CellRecord: Codable {
    var sample: String
    var delta: String
    var id1TensorSHA: Bool
    var baseline: ArmRecord
    var treatment: ArmRecord
    var equalBaseline: Bool
  }

  struct RunSummary: Codable {
    var role: String
    var sample: String
    var r0RunUUID: String
    var base: BaseRecord
    var surgeryRecord: String
    var surgeryChangedKeys: String
    var surgeryHistoryFrom: Int
    var surgeryHistoryTo: Int
    var id1TensorSHA: Bool
    var cells: [CellRecord]
    var checkpointsBefore: Int
    var checkpointsAfter: Int
    var poolBefore: Int
    var poolAfter: Int
    var checkpointsSHA256Before: String
    var checkpointsSHA256After: String
    var poolSHA256Before: String
    var poolSHA256After: String
  }

  private func writeSummary(_ store: AuditArtifactStore, _ summary: RunSummary) throws {
    let data = try JSONEncoder().encode(summary)
    let obj = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
    try store.writeSummary(obj)
  }

  // MARK: helpers

  private func dirEntries(_ url: URL) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count ?? -1
  }

  /// Content-level isolation witness (verbatim semantics from the
  /// original P5 harness).
  private func dirSHA256(_ url: URL) -> String {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return "DIR_MISSING" }
    let hashes = files.sorted().map { name -> String in
      let fileURL = url.appendingPathComponent(name)
      guard let data = try? Data(contentsOf: fileURL) else { return "\(name):READ_ERR" }
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      return "\(name):\(digest)"
    }
    let joined = hashes.joined(separator: "\n")
    return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func baseRecord(sessionId: String, fixture: URL) throws -> BaseRecord {
    let metaURL = fixture.appendingPathComponent("default_\(sessionId)_main.meta.json")
    let tensorURL = fixture.appendingPathComponent("default_\(sessionId)_main.safetensors")
    let metaData = try Data(contentsOf: metaURL)
    let metaObj = try JSONDecoder().decode([String: JSONValue].self, from: metaData)
    let history: [JSONValue]
    switch metaObj["history"] {
    case .array(let a): history = a
    default: throw NSError(domain: "P5Replication", code: 1, userInfo: [NSLocalizedDescriptionKey: "fixture meta has no history array"])
    }
    return BaseRecord(
      key: "default_\(sessionId)_main",
      position: history.count,
      anchor: "not-used-in-p5-1",
      tensorSHA: try NativeMLX.sha256HexOfFile(at: tensorURL),
      metaSHA: try NativeMLX.sha256HexOfFile(at: metaURL))
  }

  /// Surgery (verbatim semantics from the original harness): copy
  /// meta+safetensors, rewrite meta.history = []. Only [history] changes;
  /// safetensors bytes untouched.
  private func prepareStrippedFixture(sample: String, sessionId: String, fixture: URL,
                                      store: AuditArtifactStore) throws -> URL {
    let dst = P5ReplicationAudit.work.appendingPathComponent("\(sample)-nohist", isDirectory: true)
    try? FileManager.default.removeItem(at: dst)
    try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
    let base = "default_\(sessionId)_main"
    for ext in ["safetensors", "meta.json"] {
      try FileManager.default.copyItem(
        at: fixture.appendingPathComponent("\(base).\(ext)"),
        to: dst.appendingPathComponent("\(base).\(ext)"))
    }
    let metaURL = dst.appendingPathComponent("\(base).meta.json")
    var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as! [String: Any]
    let fromCount = (obj["history"] as? [Any])?.count ?? -1
    obj["history"] = [Any]()
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted])
    try data.write(to: metaURL)
    store.record("surgery", payload: [
      "sample": sample, "changed_keys": "[history]",
      "history_from": "\(fromCount)", "history_to": "0"])
    return dst
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
      info: ModelInfo(path: P5ReplicationAudit.modelPath, kind: .mlx),
      config: ModelConfig())
    try await native.start(ModelInfo(path: P5ReplicationAudit.modelPath, kind: .mlx), port: 18134)
    let ms = clock.now - start
    store.record("model_load_complete", payload: [
      "duration_ms": "\(ms.components.seconds * 1000 + ms.components.attoseconds / 1_000_000_000_000_000)",
      "model": "Nail-Qwen3.6-35B-A3B-MLX"])
    return native
  }

  /// One arm: restore (record history count) + one generate (record
  /// text/toolCalls/usage incl. cachedPromptTokens + cacheEfficiency).
  private func runArm(
    native: NativeMLX, store: AuditArtifactStore, tag: String, sessionId: String,
    fixture: URL, delta: String, withHistory: Bool
  ) async throws -> ArmRecord {
    var record = ArmRecord(
      delta: delta, restoredHistoryCount: -1, restoreError: "",
      text: "", toolCalls: [], generationTokens: "NONE",
      cachedPromptTokens: "NONE", cacheEfficiency: "NONE", streamEnd: "NORMAL")
    store.record("restore_start", payload: ["arm": tag])
    let clock = ContinuousClock()
    let rStart = clock.now
    let meta: SessionCacheMetadata
    do {
      meta = try await native.loadSessionCache(sessionId: sessionId, from: fixture)
    } catch {
      record.restoreError = "\(error)"
      record.streamEnd = "RESTORE_FAILED"
      store.record("restore_failed", payload: ["arm": tag, "error": "\(error)"])
      return record
    }
    let rMs = clock.now - rStart
    record.restoredHistoryCount = meta.history.count
    store.record("restore_complete", payload: [
      "arm": tag, "position": "\(meta.history.count)",
      "duration_ms": "\(rMs.components.seconds * 1000 + rMs.components.attoseconds / 1_000_000_000_000_000)"])

    let requestId = "p5repl-\(tag)"
    await RuntimeLifecycleCoordinator.shared.register(requestID: requestId, sessionID: sessionId)
    defer { Task { await RuntimeLifecycleCoordinator.shared.finish(requestID: requestId, success: true, reason: "p5repl") } }
    var chunks: [String] = []
    var toolCalls: [String] = []
    // Baseline arm = fullHistory + Δ (attempt-1 defect corrected);
    // treatment arm = [Δ] (the (S₀,Δ) form).
    let messages: [JSONValue] = withHistory
      ? meta.history + [userMsg(delta)]
      : [userMsg(delta)]
    store.record("generate_start", payload: ["arm": tag, "with_history": withHistory ? "YES" : "NO"])
    let gStart = clock.now
    do {
      let result = try await native.generate(
        requestId: requestId,
        sessionId: sessionId,
        logicalBranchId: "main",
        messages: messages,
        tools: nil,
        config: makeConfig(),
        onChunk: { chunks.append($0) },
        onToolCall: { parsed in
          toolCalls.append("\(parsed.name) \(parsed.argumentsJSON)")
        })
      record.generationTokens = result.usage.map { String($0.generationTokens) } ?? "NONE"
      record.cachedPromptTokens = result.usage.flatMap { $0.cachedPromptTokens.map(String.init) } ?? "NONE"
      record.cacheEfficiency = result.usage.flatMap { $0.cacheEfficiency.map { String(format: "%.4f", $0) } } ?? "NONE"
    } catch {
      record.streamEnd = "THREW: \(error)"
    }
    let gMs = clock.now - gStart
    record.text = chunks.joined()
    record.toolCalls = toolCalls
    store.record("generate_complete", payload: [
      "arm": tag, "stream_end": record.streamEnd == "NORMAL" ? "NORMAL" : "ERROR",
      "duration_ms": "\(gMs.components.seconds * 1000 + gMs.components.attoseconds / 1_000_000_000_000_000)"])
    store.record("arm_result", payload: [
      "arm": tag, "text_chars": "\(record.text.count)", "text": record.text,
      "tool_call_count": "\(toolCalls.count)",
      "generation_tokens": record.generationTokens,
      "cached_prompt_tokens": record.cachedPromptTokens,
      "cache_efficiency": record.cacheEfficiency])
    return record
  }

  private func runSample(sample: String, sessionId: String, fixture: URL,
                         dA1: String, dB1: String) async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P5-1-replication", "sample": sample])
    defer { store.finish() }

    let cpBefore = dirEntries(P5ReplicationAudit.realCheckpoints)
    let poolBefore = dirEntries(P5ReplicationAudit.prefixPool)
    let cpSHA256Before = dirSHA256(P5ReplicationAudit.realCheckpoints)
    let poolSHA256Before = dirSHA256(P5ReplicationAudit.prefixPool)
    store.record("isolation_baseline", payload: [
      "real_branch_checkpoints_before": "\(cpBefore)", "prefix_pool_before": "\(poolBefore)",
      "checkpoints_sha256_before": cpSHA256Before, "pool_sha256_before": poolSHA256Before])

    let base = try baseRecord(sessionId: sessionId, fixture: fixture)
    store.record("base_record", payload: [
      "key": base.key, "position": "\(base.position)",
      "tensorSHA": base.tensorSHA, "metaSHA": base.metaSHA])

    let native = try await startNative(store: store)
    defer { Task { try? await native.stop() } }

    // Phase 1: baseline arms — full fixture, fullHistory + Δ (corrected)
    var cells: [CellRecord] = []
    for (deltaName, delta) in [("dA1", dA1), ("dB1", dB1)] {
      let baseline = try await runArm(
        native: native, store: store, tag: "\(sample)-base-\(deltaName)",
        sessionId: sessionId, fixture: fixture, delta: delta, withHistory: true)

      // Phase 2: treatment arms — stripped fixture, [Δ]
      let stripped = try prepareStrippedFixture(sample: sample, sessionId: sessionId,
                                                fixture: fixture, store: store)
      let tensorSHA = try NativeMLX.sha256HexOfFile(
        at: stripped.appendingPathComponent("default_\(sessionId)_main.safetensors"))
      let id1 = tensorSHA == base.tensorSHA
      store.record("surgery_id1", payload: ["sample": sample, "delta": deltaName, "id1_tensor_sha_match": id1 ? "YES" : "NO"])
      let treatment = try await runArm(
        native: native, store: store, tag: "\(sample)-treat-\(deltaName)",
        sessionId: sessionId, fixture: stripped, delta: delta, withHistory: false)

      cells.append(CellRecord(
        sample: sample, delta: deltaName, id1TensorSHA: id1,
        baseline: baseline, treatment: treatment,
        equalBaseline: treatment.text == baseline.text))
    }

    let cpAfter = dirEntries(P5ReplicationAudit.realCheckpoints)
    let poolAfter = dirEntries(P5ReplicationAudit.prefixPool)
    let cpSHA256After = dirSHA256(P5ReplicationAudit.realCheckpoints)
    let poolSHA256After = dirSHA256(P5ReplicationAudit.prefixPool)
    store.record("isolation_check", payload: [
      "real_branch_checkpoints_after": "\(cpAfter)", "prefix_pool_after": "\(poolAfter)",
      "checkpoints_sha256_after": cpSHA256After, "pool_sha256_after": poolSHA256After])

    let summary = RunSummary(
      role: "run", sample: sample, r0RunUUID: store.runUUID, base: base,
      surgeryRecord: "history only; baseline computed in-run with fullHistory+delta (attempt-1 defect corrected)",
      surgeryChangedKeys: "[history]", surgeryHistoryFrom: base.position, surgeryHistoryTo: 0,
      id1TensorSHA: cells.allSatisfy { $0.id1TensorSHA },
      cells: cells,
      checkpointsBefore: cpBefore, checkpointsAfter: cpAfter,
      poolBefore: poolBefore, poolAfter: poolAfter,
      checkpointsSHA256Before: cpSHA256Before, checkpointsSHA256After: cpSHA256After,
      poolSHA256Before: poolSHA256Before, poolSHA256After: poolSHA256After)
    try writeSummary(store, summary)
    try store.writeHashes([
      "model": P5ReplicationAudit.modelHashString(),
      "checkpoint_tensor_sha256": base.tensorSHA,
      "checkpoint_meta_sha256": base.metaSHA])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["sample": sample])
  }

  // MARK: invocations (independent processes)

  func testP5ReplS1() async throws {
    try await runSample(sample: "s1", sessionId: P5ReplicationAudit.s1Session,
                        fixture: P5ReplicationAudit.s1Fixture,
                        dA1: P5ReplicationAudit.s1dA1, dB1: P5ReplicationAudit.s1dB1)
  }

  func testP5ReplS2() async throws {
    try await runSample(sample: "s2", sessionId: P5ReplicationAudit.s2Session,
                        fixture: P5ReplicationAudit.s2Fixture,
                        dA1: P5ReplicationAudit.s2dA1, dB1: P5ReplicationAudit.s2dB1)
  }

  // MARK: Mechanical adjudication — pre-registered rules (header §judgment)

  func testP5ReplAdjudicate() throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P5-1-replication", "role": "judgment"])
    defer { store.finish() }

    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(atPath: P5ReplicationAudit.replicationBase.path)
    var summaries: [String: (RunSummary, String)] = [:]
    for name in entries.sorted() {
      let dir = P5ReplicationAudit.replicationBase.appendingPathComponent(name, isDirectory: true)
      let summaryURL = dir.appendingPathComponent("summary.json")
      guard let data = try? Data(contentsOf: summaryURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (obj["role"] as? String) == "run"
      else { continue }
      let decoded = try JSONDecoder().decode(RunSummary.self, from: data)
      guard summaries[decoded.sample] == nil else {
        throw NSError(domain: "P5Replication.Judgment", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "duplicate summary for sample \(decoded.sample) — stale run dirs present; clean replication base and rerun the full sequence"])
      }
      summaries[decoded.sample] = (decoded, name)
    }
    guard let s1 = summaries["s1"], let s2 = summaries["s2"], summaries.count == 2 else {
      throw NSError(domain: "P5Replication.Judgment", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "expected exactly 2 run summaries (s1, s2), found: \(summaries.keys.sorted().joined(separator: ","))"])
    }
    store.record("judgment_inputs", payload: ["s1": s1.1, "s2": s2.1])

    func efficiency(_ arm: ArmRecord) -> Double? {
      arm.cacheEfficiency == "NONE" ? nil : Double(arm.cacheEfficiency)
    }
    func cachedTokens(_ arm: ArmRecord) -> Int? {
      arm.cachedPromptTokens == "NONE" ? nil : Int(arm.cachedPromptTokens)
    }

    func judge(_ s: RunSummary) -> [String: String] {
      var v: [String: String] = [:]
      // Isolation (counts + content SHA)
      let isolationCount = s.checkpointsBefore == s.checkpointsAfter && (s.poolAfter - s.poolBefore) == 0
      let isolationSHA = s.checkpointsSHA256Before == s.checkpointsSHA256After
          && s.poolSHA256Before == s.poolSHA256After
      let isolation = isolationCount && isolationSHA
      v["isolation"] = isolation ? "PASS" : "BROKEN"

      // Surgery authenticity (sample-level)
      v["surgery_changed_keys"] = s.surgeryChangedKeys == "[history]" ? "OK" : "BROKEN"
      v["surgery_history"] = (s.surgeryHistoryFrom == s.base.position && s.surgeryHistoryTo == 0) ? "OK" : "BROKEN"
      v["id1_tensor_sha"] = s.id1TensorSHA ? "YES" : "NO"

      for c in s.cells {
        let tag = "\(c.sample)-\(c.delta)"
        // C1 surgery in effect
        let c1 = c.id1TensorSHA
          && c.treatment.restoredHistoryCount == 0
          && c.baseline.restoredHistoryCount == s.base.position
          && c.treatment.restoreError.isEmpty && c.baseline.restoreError.isEmpty
        // C2 authenticity + D5 channel
        let d5 = (c.treatment.text.isEmpty && !c.treatment.toolCalls.isEmpty)
          || (c.baseline.text.isEmpty && !c.baseline.toolCalls.isEmpty)
        let c2 = !c.baseline.text.isEmpty && !c.treatment.text.isEmpty && !d5
        // C3 baseline control: KV consumed
        let c3 = (cachedTokens(c.baseline).map { $0 > 0 } ?? false)
          && (efficiency(c.baseline).map { $0 > 0.9 } ?? false)
        // C4 boundary: KV rejected on stripped history
        let c4 = (cachedTokens(c.treatment).map { $0 == 0 } ?? true)
          && (efficiency(c.treatment).map { $0 == 0.0 } ?? true)
        // C5 divergence Y ≠ Y′
        let c5 = !c.equalBaseline

        v["\(tag)_C1_surgery"] = c1 ? "PASS" : "INCONCLUSIVE"
        v["\(tag)_C2_authentic"] = d5 ? "INCONCLUSIVE-D5" : (c2 ? "PASS" : "INCONCLUSIVE")
        v["\(tag)_C3_baseline_control"] = c3 ? "PASS" : "INCONCLUSIVE"
        v["\(tag)_C4_boundary_rebuild"] = c4 ? "PASS" : "FAIL"
        v["\(tag)_C5_divergence"] = c5 ? "PASS" : "FAIL"
        v["\(tag)_baseline_cacheEff"] = c.baseline.cacheEfficiency
        v["\(tag)_treatment_cacheEff"] = c.treatment.cacheEfficiency
      }

      let cellVerdicts = v.values.filter { $0 == "PASS" || $0 == "FAIL" || $0.hasPrefix("INCONCLUSIVE") }
      let verdict: String
      if !isolation || v.values.contains(where: { $0 == "BROKEN" }) || v.values.contains(where: { $0 == "NO" }) {
        verdict = "INCONCLUSIVE"
      } else if cellVerdicts.contains("FAIL") {
        verdict = "FAIL"
      } else if cellVerdicts.contains(where: { $0.hasPrefix("INCONCLUSIVE") }) {
        verdict = "INCONCLUSIVE"
      } else {
        verdict = "PASS"
      }
      v["verdict"] = verdict
      return v
    }

    let j1 = judge(s1.0), j2 = judge(s2.0)
    for (k, val) in j1 { store.record("judgment", payload: ["cell": "s1_\(k)", "value": val]) }
    for (k, val) in j2 { store.record("judgment", payload: ["cell": "s2_\(k)", "value": val]) }

    let overall: String
    if j1["verdict"] == "INCONCLUSIVE" || j2["verdict"] == "INCONCLUSIVE" {
      overall = "INCONCLUSIVE"
    } else if j1["verdict"] == "PASS" && j2["verdict"] == "PASS" {
      overall = "PASS"
    } else {
      overall = "FAIL"
    }
    store.record("judgment", payload: ["cell": "overall", "value": overall])
    store.record("judgment_note", payload: [
      "text": "mechanical application of the pre-registered replication judgment (header); baseline arm corrected to fullHistory+delta per registered attempt-1 defect; old artifacts never read as judgment input"])

    var judgment: [String: Any] = [:]
    judgment["s1"] = j1
    judgment["s2"] = j2
    judgment["overall"] = overall
    judgment["inputs"] = ["s1": s1.1, "s2": s2.1]
    judgment["registered_wording_fail"] =
      "anchor-failure→rebuild 边界未复现（treatment 消费 KV）——有效结果，不得改判据重试"
    judgment["registered_wording_pass"] =
      "anchor 对齐断裂→rebuild 边界复现：历史剥离（KV 完好）→ KV 被拒（cacheEff 0.00）；锚在位→KV 消费（cacheEff≈0.99）"
    let jdata = try JSONSerialization.data(withJSONObject: judgment, options: [.prettyPrinted, .sortedKeys])
    try jdata.write(to: store.directory.appendingPathComponent("judgment.json"))
    try store.writeHashes(["model": P5ReplicationAudit.modelHashString()])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["role": "judgment", "overall": overall])
    print("[p5repl] overall: \(overall)")
  }
}
