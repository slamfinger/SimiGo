import Crypto
import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import os
import SimiGo2Experimental
import SimiGoRuntimeContract

// REAL-MODEL ES -> IS -> FRESH-ES HANDOFF
//
// Stage A: a real MLX model performs step 1 on a bound ES representation; its
//          RESULT is settled into the Information Space; the ES advances,
//          rebinds the advanced representation and binds the IS checkpoint;
//          the old carrier is explicitly released and this process exits.
// Stage C: a NEW process loads the same model snapshot, opens the SAME
//          database file and durable state directory, recovers a fresh ES
//          through the production recovery entry, reads step 1's settlement
//          from IS, and lets the real model perform only the remaining step.
//
// No retry: a failure keeps the run directory untouched and is reported as
// the single observed outcome.

struct HandoffError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

struct Options {
  let runDir: URL
  let modelDir: URL
  let labRoot: URL
  let runLabel: String
  let secret: String?
  let nonceSource: String?
  let maxTokens: Int
  let caseName: String?
  let expectedSecret: String?
  let expectedChecksum: String?
  let u1PID: Int32?
  let stateDirectory: URL?
  let baselineDir: URL?
  let existingTask: Bool

  init(arguments: [String]) throws {
    func value(_ name: String, required: Bool = true) throws -> String? {
      guard let index = arguments.firstIndex(of: "--" + name) else {
        if required { throw HandoffError("missing --\(name)") }
        return nil
      }
      guard index + 1 < arguments.count else {
        throw HandoffError("missing value for --\(name)")
      }
      return arguments[index + 1]
    }
    guard let runDir = try value("run-dir"),
          let modelDir = try value("model-dir"),
          let labRoot = try value("lab-root") else {
      throw HandoffError("run-dir, model-dir and lab-root are required")
    }
    self.runDir = URL(fileURLWithPath: runDir, isDirectory: true).standardizedFileURL
    self.modelDir = URL(fileURLWithPath: modelDir, isDirectory: true).standardizedFileURL
    self.labRoot = URL(fileURLWithPath: labRoot, isDirectory: true).standardizedFileURL
    runLabel = try value("run-label") ?? "handoff-20261022"
    secret = try value("secret", required: false)
    nonceSource = try value("nonce-source", required: false)
    if let raw = try value("max-tokens", required: false) {
      guard let parsed = Int(raw), parsed > 0 else {
        throw HandoffError("invalid --max-tokens: \(raw)")
      }
      maxTokens = parsed
    } else {
      maxTokens = 64
    }
    caseName = try value("case", required: false)
    expectedSecret = try value("expected-secret", required: false)
    expectedChecksum = try value("expected-checksum", required: false)
    if let rawPID = try value("u1-pid", required: false) {
      guard let parsed = Int32(rawPID) else {
        throw HandoffError("invalid --u1-pid: \(rawPID)")
      }
      u1PID = parsed
    } else {
      u1PID = nil
    }
    if let rawState = try value("state-dir", required: false) {
      stateDirectory = URL(fileURLWithPath: rawState, isDirectory: true).standardizedFileURL
    } else {
      stateDirectory = nil
    }
    if let rawBaseline = try value("baseline-dir", required: false) {
      baselineDir = URL(fileURLWithPath: rawBaseline, isDirectory: true).standardizedFileURL
    } else {
      baselineDir = nil
    }
    existingTask = arguments.contains("--existing-task")
  }
}

func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func fileSHA256(_ url: URL) throws -> String {
  try sha256Hex(Data(contentsOf: url))
}

func utcNow() -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
  return formatter.string(from: Date())
}

func utcNowPlus(_ seconds: TimeInterval) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
  return formatter.string(from: Date().addingTimeInterval(seconds))
}

func writeExclusiveJSON(_ record: [String: Any], to url: URL) throws {
  let data = try JSONSerialization.data(
    withJSONObject: record, options: [.sortedKeys, .prettyPrinted])
  let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
  guard descriptor >= 0 else {
    throw HandoffError("evidence file already exists or cannot be created: \(url.path)")
  }
  let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  try handle.write(contentsOf: data)
}

func fileIdentity(_ url: URL) throws -> [String: Any] {
  var info = stat()
  guard stat(url.path, &info) == 0 else {
    throw HandoffError("cannot stat \(url.path)")
  }
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
  return [
    "path": url.path,
    "device": String(info.st_dev),
    "inode": String(info.st_ino),
    "size_bytes": size,
    "sha256": try fileSHA256(url),
  ]
}

func firstCapture(_ text: String, pattern: String) -> String? {
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
  let range = NSRange(text.startIndex..<text.endIndex, in: text)
  guard let match = regex.firstMatch(in: text, range: range),
        match.numberOfRanges > 1,
        let captured = Range(match.range(at: 1), in: text) else { return nil }
  return String(text[captured])
}

/// Model identity WITHOUT re-hashing multi-gigabyte weights: every safetensors
/// file in the snapshot is a symlink into the Hugging Face blob store, and the
/// blob file name IS the git-lfs content sha256. We record that digest, the
/// blob's REAL byte size and a manifest digest over (name, digest, size), plus
/// real hashes of the small identity files (config / tokenizer / index).
///
/// `attributesOfItem` reports the size of the symlink itself, so the size has
/// to come from `stat`, which follows the link to the blob.
func modelIdentity(snapshot: URL) throws -> [String: Any] {
  let fileManager = FileManager.default
  let names = try fileManager.contentsOfDirectory(atPath: snapshot.path).sorted()
  var weightFiles: [[String: Any]] = []
  var manifestLines: [String] = []
  for name in names where name.hasSuffix(".safetensors") {
    let url = snapshot.appendingPathComponent(name)
    let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
    let blobName = URL(fileURLWithPath: destination).lastPathComponent
    var blobInfo = stat()
    guard stat(url.path, &blobInfo) == 0 else {
      throw HandoffError("cannot stat weight blob for \(name)")
    }
    let size = Int64(blobInfo.st_size)
    guard blobName.count == 64 else {
      throw HandoffError("weight file \(name) is not linked to a sha256 blob name")
    }
    weightFiles.append([
      "name": name,
      "content_sha256": blobName,
      "size_bytes": size,
      "blob_path": url.resolvingSymlinksInPath().path,
    ])
    manifestLines.append("\(name):\(blobName):\(size)")
  }
  guard !weightFiles.isEmpty else {
    throw HandoffError("model snapshot carries no safetensors weights")
  }
  func identityFile(_ name: String) throws -> String {
    let url = snapshot.appendingPathComponent(name)
    guard fileManager.fileExists(atPath: url.path) else {
      throw HandoffError("model identity file missing: \(name)")
    }
    return try fileSHA256(url)
  }
  return [
    "snapshot_path": snapshot.path,
    "snapshot_revision": snapshot.lastPathComponent,
    "weights_manifest_sha256": sha256Hex(
      Data(manifestLines.joined(separator: "\n").utf8)),
    "weight_files": weightFiles,
    "config_json_sha256": try identityFile("config.json"),
    "tokenizer_json_sha256": try identityFile("tokenizer.json"),
    "tokenizer_config_json_sha256": try identityFile("tokenizer_config.json"),
    "model_index_json_sha256": try identityFile("model.safetensors.index.json"),
  ]
}

/// Counts the real executor's calls without altering them, and forwards the
/// carrier-release protocol so the production release path sees the same
/// executor surface it expects.
final class CountingModelExecutor:
  ProductionRuntimeModelContinuationExecutor,
  ExecutionCarrierReleasing,
  @unchecked Sendable
{
  private struct Counters {
    var tokenizeText = 0
    var tokenizeSeed = 0
    var continuation = 0
  }

  private let base: MLXPrefixRecomputeExecutor
  private let counters = OSAllocatedUnfairLock(initialState: Counters())

  init(base: MLXPrefixRecomputeExecutor) {
    self.base = base
  }

  var counterSnapshot: [String: Int] {
    counters.withLock { value in
      [
        "tokenize_text_calls": value.tokenizeText,
        "tokenize_seed_calls": value.tokenizeSeed,
        "model_continuation_calls": value.continuation,
      ]
    }
  }

  func tokenizeText(_ text: String) async throws -> [Int] {
    counters.withLock { $0.tokenizeText += 1 }
    return try await base.tokenizeText(text)
  }

  func tokenizeSeedText(_ text: String) async throws -> [Int] {
    counters.withLock { $0.tokenizeSeed += 1 }
    return try await base.tokenizeSeedText(text)
  }

  func continueExecution(
    _ state: ExecutionStateHandle,
    nextInputTokens: [Int],
    maxTokens: Int
  ) async throws -> ExecutionContinuationResult {
    counters.withLock { $0.continuation += 1 }
    return try await base.continueExecution(
      state, nextInputTokens: nextInputTokens, maxTokens: maxTokens)
  }

  func releaseExecutionCarrier(for state: ExecutionStateHandle) throws {
    try base.releaseExecutionCarrier(for: state)
  }

  func verifyCarrierUnusable(for state: ExecutionStateHandle) throws {
    try base.verifyCarrierUnusable(for: state)
  }

  func retiredCarrierStorageIDs(for state: ExecutionStateHandle) -> Set<String> {
    base.retiredCarrierStorageIDs(for: state)
  }

  func verifyAdoptedCarrierIsolated(
    from retiredStorageIDs: Set<String>,
    for state: ExecutionStateHandle
  ) throws {
    try base.verifyAdoptedCarrierIsolated(
      from: retiredStorageIDs, for: state)
  }
}

func reportDictionary(_ report: ProductionTaskContinuationReport) -> [String: Any] {
  [
    "demand_id": report.demandID,
    "task_item_id": report.taskItemID,
    "created_fresh_execution": report.created,
    "computed_item_ids": report.computedItemIDs,
    "reused_item_ids": report.reusedItemIDs,
    "settlement_actions": report.settlementActions.map { action in
      [
        "item_id": action.itemID,
        "action": action.action,
        "settlement_object_id": action.settlementObjectID,
        "result_digest": action.resultDigest,
      ]
    },
    "bridge_result_digest": report.resultDigest,
    "is_pending_state_id": report.isPendingStateID,
    "is_confirmation_state_id": report.isConfirmationStateID,
    "advanced_position": report.advancedPosition,
    "advanced_lifecycle": report.advancedLifecycle,
    "consumed_prefix_length": report.consumedPrefixLength,
    "next_input_token_count": report.nextInputTokenCount,
    "next_input_token_ids": report.nextInputTokenIDs,
    "generated_token_ids": report.generatedTokenIDs,
    "generated_text": report.generatedText,
    "updated_prefix_token_count": report.updatedPrefixTokenCount,
    "tokenize_seed_calls_this_call": report.tokenizeSeedCallCount,
    "tokenize_next_input_calls_this_call": report.tokenizeNextInputCallCount,
    "model_continuation_calls_this_call": report.modelContinuationCallCount,
  ]
}

func settlementObjectID(
  _ report: ProductionTaskContinuationReport,
  itemID: String
) -> String {
  report.settlementActions.first(where: { $0.itemID == itemID })?.settlementObjectID ?? ""
}

func makeIntegration(
  options: Options,
  executor: CountingModelExecutor,
  backend: MLXExecutionStateBackend,
  stateDirectory: URL,
  resetToFreshBaseline: Bool
) throws -> ProductionRuntimeInformationIntegration {
  let trustAnchorPath = ProcessInfo.processInfo.environment["SIMIGO_SETTLEMENT_TRUST_ANCHOR"]
  let configuration = ProductionRuntimeLaunchConfiguration(
    runtimeRoot: options.labRoot.appendingPathComponent("execution-information-loop"),
    pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
    snapshotPath: options.labRoot.appendingPathComponent(
      "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"),
    validityPolicyPath: options.labRoot.appendingPathComponent(
      "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"),
    settlementTrustAnchorPath: trustAnchorPath.map { URL(fileURLWithPath: $0) }
  )
  return try ProductionRuntimeInformationIntegration(
    configuration: configuration,
    modelExecutor: executor,
    backend: backend,
    semanticStateDirectory: stateDirectory,
    resetToFreshBaseline: resetToFreshBaseline
  )
}

func loadModel(_ options: Options) async throws -> (ModelContainer, Double) {
  let start = Date()
  let container = try await LLMModelFactory.shared.loadContainer(
    from: options.modelDir,
    using: #huggingFaceTokenizerLoader()
  )
  return (container, Date().timeIntervalSince(start))
}

func stageADirectories(_ options: Options) throws -> (URL, URL, URL) {
  let database = options.runDir.appendingPathComponent("carrier.sqlite")
  let stateDirectory = options.runDir.appendingPathComponent("state", isDirectory: true)
  let evidenceDirectory = options.runDir.appendingPathComponent("evidence", isDirectory: true)
  return (database, stateDirectory, evidenceDirectory)
}

func runStageA(_ options: Options) async throws {
  let startedAt = utcNow()
  let start = Date()
  let (database, stateDirectory, evidenceDirectory) = try stageADirectories(options)
  let failureURL = evidenceDirectory.appendingPathComponent("stage-a-fail.json")

  do {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: options.runDir, withIntermediateDirectories: options.existingTask)
    try fileManager.createDirectory(
      at: stateDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(
      at: evidenceDirectory, withIntermediateDirectories: true)

    let identity = try modelIdentity(snapshot: options.modelDir)
    let (container, loadSeconds) = try await loadModel(options)
    let backend = MLXExecutionStateBackend()
    let executor = CountingModelExecutor(
      base: MLXPrefixRecomputeExecutor(container: container, backend: backend))
    let integration = try makeIntegration(
      options: options,
      executor: executor,
      backend: backend,
      stateDirectory: stateDirectory,
      resetToFreshBaseline: true)

    let definitionAt = utcNow()
    let definition: [String: Any]
    if options.existingTask {
      let sourceItemResponse = try integration.readItem(
        database: database, itemID: "TASK-SOURCE")
      let sourceSettlementResponse = try integration.readSettlement(
        database: database, itemID: "TASK-SOURCE")
      guard let sourceItem = sourceItemResponse["item"] as? [String: Any],
            let sourcePayload = sourceItem["source_payload"] as? [String: Any],
            let logText = sourcePayload["log_text"] as? String,
            let sourceSettlement = sourceSettlementResponse["settlement"] as? [String: Any],
            let sourceResult = sourceSettlement["result"] as? [String: Any],
            let sourceValue = sourceResult["value"] as? [String: Any],
            let secretSHA = sourceValue["secret_sha256"] as? String,
            let checksum = sourceValue["checksum"] as? String else {
        throw HandoffError("existing task has no readable source registration")
      }
      definition = [
        "ok": true,
        "mode": "existing_task",
        "secret_sha256": secretSHA,
        "checksum": checksum,
        "log_text_sha256": sha256Hex(Data(logText.utf8)),
      ]
    } else {
      let randomNonce = options.nonceSource == "random"
      if randomNonce && options.secret != nil {
        throw HandoffError("--nonce-source random conflicts with --secret")
      }
      if let nonceSource = options.nonceSource, nonceSource != "random" {
        throw HandoffError("unknown --nonce-source: \(nonceSource)")
      }
      definition = try integration.defineTask(
        database: database,
        evaluatedAtUTC: definitionAt,
        runLabel: options.runLabel,
        secret: options.secret,
        randomSecret: randomNonce)
    }
    guard definition["ok"] as? Bool == true else {
      throw HandoffError("task definition was not acknowledged")
    }
    let itemResponse = try integration.readItem(database: database, itemID: "TASK-U1")
    guard let item = itemResponse["item"] as? [String: Any],
          let payload = item["source_payload"] as? [String: Any],
          let seedText = payload["prompt_seed"] as? String else {
      throw HandoffError("step 1 item carries no prompt material")
    }
    let revision = identity["snapshot_revision"] as? String ?? ""
    let weightsDigest = identity["weights_manifest_sha256"] as? String ?? ""

    let advancementAt = utcNowPlus(1)
    let outcome = try await integration.continueTask(
      database: database,
      handle: nil,
      advancementID: "handoff-a-u1-\(options.runLabel)",
      evaluatedAtUTC: advancementAt,
      demandID: "handoff-u1",
      taskItemID: "TASK-U1",
      seedText: seedText,
      provenance: ProductionTaskProvenance(
        runID: "handoff-a-u1-\(options.runLabel)",
        buildSHA256: ProductionTaskProvenance.buildIdentity(
          runtimeRoot: options.labRoot.appendingPathComponent("execution-information-loop")),
        modelSnapshotRevision: revision,
        weightsManifestSHA256: weightsDigest),
      maxTokens: options.maxTokens
    ) { produced, _ in
      guard let secret = firstCapture(produced.generatedText, pattern: "SECRET=([A-Za-z0-9]+)") else {
        throw HandoffError("real model produced no SECRET=<value> line: \(produced.generatedText)")
      }
      return [
        "secret": secret,
        "raw_generated_text": produced.generatedText,
        "generated_token_ids": produced.generatedTokenIDs,
        "model_snapshot_revision": revision,
        "model_weights_manifest_sha256": weightsDigest,
        "model_call_index": 1,
      ]
    }

    let retired = try integration.releaseExecutionCarrier(for: outcome.handle)
    let oldBindingUnusable = (try? backend.boundPrefix(for: outcome.handle)) == nil
      && backend.isCarrierRetired(for: outcome.handle.id)
    let databaseIdentity = try fileIdentity(database)
    // The stage-A evidence is a pre-U2 surface. Keep the raw U1 answer only in
    // the IS settlement (the legitimate information channel); here retain the
    // token ids and a text digest so a nonce cannot be read back from evidence.
    var sanitizedContinuation = reportDictionary(outcome.report)
    sanitizedContinuation.removeValue(forKey: "generated_text")
    sanitizedContinuation["generated_text_sha256"] = sha256Hex(
      Data(outcome.report.generatedText.utf8))

    let record: [String: Any] = [
      "schema_id": "SIMIGO-REAL-MODEL-HANDOFF-STAGE-V1",
      "stage": "A",
      "run_label": options.runLabel,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "duration_seconds": Date().timeIntervalSince(start),
      "model": identity,
      "model_load_seconds": loadSeconds,
      "database": databaseIdentity,
      "semantic_state_directory": stateDirectory.path,
      "task_definition": [
        "mode": definition["mode"] ?? "created",
        "evaluated_at_utc": definitionAt,
        "demand_id": "handoff-u1",
        "item_id": "TASK-U1",
        "log_text_sha256": definition["log_text_sha256"] ?? "",
        "secret_sha256": definition["secret_sha256"] ?? "",
        "checksum": definition["checksum"] ?? "",
        "nonce_source": options.nonceSource == "random"
          ? "runtime_random_128bit"
          : (options.secret != nil ? "explicit_secret" : "run_label_derived"),
        "random_secret": definition["random_secret"] ?? false,
        "nonce_bits": definition["nonce_bits"] ?? NSNull(),
      ],
      "prompt": [
        "seed_sha256": sha256Hex(Data(seedText.utf8)),
        "next_input_sha256": outcome.admission.inputSHA256,
        "next_input_byte_length": outcome.admission.inputByteLength,
        "input_admission": outcome.admission.evidenceDictionary(),
      ],
      "continuation": sanitizedContinuation,
      "counters": executor.counterSnapshot,
      "carrier_release": [
        "released": true,
        "retired_storage_ids": retired.sorted(),
        "old_binding_unusable": oldBindingUnusable,
        "kv_carrier_present": !retired.isEmpty,
        "g3_cache_session_installed": false,
      ],
      "propositions": [
        "arc_reference_release": "UNPROVEN_NOT_INSTRUMENTED",
        "old_carrier_not_reusable": "PASS_BINDING_LEVEL_TOMBSTONE_VERIFIED",
        "gpu_memory_returned_to_os": "UNPROVEN_NOT_A_SUCCESS_CONDITION",
      ],
      "terminal_state": "STAGE_A_PASS",
    ]
    try writeExclusiveJSON(record, to: evidenceDirectory.appendingPathComponent("stage-a.json"))
  } catch {
    let record: [String: Any] = [
      "schema_id": "SIMIGO-REAL-MODEL-HANDOFF-STAGE-V1",
      "stage": "A",
      "run_label": options.runLabel,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "failure": String(describing: error),
      "terminal_state": "STAGE_A_FAIL",
    ]
    if FileManager.default.fileExists(atPath: evidenceDirectory.path) {
      try? writeExclusiveJSON(record, to: failureURL)
    }
    throw error
  }
}

func runStageC(_ options: Options) async throws {
  let startedAt = utcNow()
  let start = Date()
  let (database, stateDirectory, evidenceDirectory) = try stageADirectories(options)
  let stageAURL = evidenceDirectory.appendingPathComponent("stage-a.json")
  let failureURL = evidenceDirectory.appendingPathComponent("stage-c-fail.json")

  do {
    guard let stageAData = try? Data(contentsOf: stageAURL),
          let stageA = try? JSONSerialization.jsonObject(with: stageAData) as? [String: Any],
          (stageA["terminal_state"] as? String) == "STAGE_A_PASS",
          let stageAContinuation = stageA["continuation"] as? [String: Any] else {
      throw HandoffError("stage A did not complete; refusing to continue")
    }
    guard let stageADatabase = stageA["database"] as? [String: Any],
          let stageASha = stageADatabase["sha256"] as? String,
          let stageAInode = stageADatabase["inode"] as? String,
          let stageAPrefixCount = stageAContinuation["updated_prefix_token_count"] as? Int,
          let stageAGenerated = stageAContinuation["generated_token_ids"] as? [Int],
          let stageAU1ObjectID = settlementObjectIDFrom(stageAContinuation, itemID: "TASK-U1"),
          let stageASourceObjectID = settlementObjectIDFrom(stageAContinuation, itemID: "TASK-SOURCE") else {
      throw HandoffError("stage A evidence is incomplete")
    }

    // The physical database must be the SAME file stage A settled into, before
    // this process writes anything.
    let databaseAtStart = try fileIdentity(database)
    guard let startInode = databaseAtStart["inode"] as? String, startInode == stageAInode else {
      throw HandoffError("stage C opened a different physical database file")
    }
    guard let startSha = databaseAtStart["sha256"] as? String, startSha == stageASha else {
      throw HandoffError("stage C database bytes differ from stage A's settled database")
    }

    let identity = try modelIdentity(snapshot: options.modelDir)
    let (container, loadSeconds) = try await loadModel(options)
    let backend = MLXExecutionStateBackend()
    let executor = CountingModelExecutor(
      base: MLXPrefixRecomputeExecutor(container: container, backend: backend))
    let integration = try makeIntegration(
      options: options,
      executor: executor,
      backend: backend,
      stateDirectory: stateDirectory,
      resetToFreshBaseline: false)

    let isStatusBefore = try integration.status(database: database)
    let recovered = try await integration.recoverExecutionState(database: database)
    let bound = try backend.boundPrefix(for: recovered)
    let tail = Array(bound.prefix.suffix(stageAGenerated.count))
    let prefixTailMatches = bound.prefix.count == stageAPrefixCount && tail == stageAGenerated
    guard prefixTailMatches else {
      throw HandoffError(
        "recovered prefix does not match the settled stage-A representation")
    }

    // The ordinary production entry resolves and admits the step-2 input from
    // IS itself. This stage neither reads a settlement nor interpolates a
    // template; it only recovers the ES and names the task item.
    let revision = identity["snapshot_revision"] as? String ?? ""
    let weightsDigest = identity["weights_manifest_sha256"] as? String ?? ""

    let advancementAt = utcNow()
    var admittedSecret = ""
    var admittedChecksum = ""
    var admittedU1ObjectID = ""
    var admittedSourceObjectID = ""
    let outcome = try await integration.continueTask(
      database: database,
      handle: recovered,
      advancementID: "handoff-c-u2-\(options.runLabel)",
      evaluatedAtUTC: advancementAt,
      demandID: "handoff-u2",
      taskItemID: "TASK-U2",
      seedText: nil,
      provenance: ProductionTaskProvenance(
        runID: "handoff-c-u2-\(options.runLabel)",
        buildSHA256: ProductionTaskProvenance.buildIdentity(
          runtimeRoot: options.labRoot.appendingPathComponent("execution-information-loop")),
        modelSnapshotRevision: revision,
        weightsManifestSHA256: weightsDigest),
      maxTokens: 32
    ) { produced, admitted in
      guard let answer = firstCapture(
        produced.generatedText, pattern: "ANSWER=([A-Za-z0-9]+-[A-Za-z0-9]+)"),
        let secret = admitted.value(forPlaceholder: "secret"),
        let checksum = admitted.value(forPlaceholder: "checksum") else {
        throw HandoffError("real model produced no ANSWER=<secret>-<checksum> line: \(produced.generatedText)")
      }
      admittedSecret = secret
      admittedChecksum = checksum
      admittedU1ObjectID = admitted.dependencySettlementObjectIDs["TASK-U1"] ?? ""
      admittedSourceObjectID = admitted.dependencySettlementObjectIDs["TASK-SOURCE"] ?? ""
      return [
        "answer": answer,
        "secret": secret,
        "checksum": checksum,
        "secret_source_settlement_object_id": admittedU1ObjectID,
        "checksum_source_settlement_object_id": admittedSourceObjectID,
        "raw_generated_text": produced.generatedText,
        "generated_token_ids": produced.generatedTokenIDs,
        "model_snapshot_revision": revision,
        "model_weights_manifest_sha256": weightsDigest,
        "model_call_index": 1,
      ]
    }
    // The admitted settlement objects must be the SAME objects stage A settled;
    // otherwise stage C would continue from a different input than the one the
    // handoff's first step produced.
    guard admittedU1ObjectID == stageAU1ObjectID,
          admittedSourceObjectID == stageASourceObjectID else {
      throw HandoffError("stage C admitted a different settlement object than stage A")
    }

    let databaseAfter = try fileIdentity(database)
    let stageAState = isStatusBefore["execution_state"] as? [String: Any] ?? [:]

    let record: [String: Any] = [
      "schema_id": "SIMIGO-REAL-MODEL-HANDOFF-STAGE-V1",
      "stage": "C",
      "run_label": options.runLabel,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "stage_a_pid": stageA["pid"] ?? -1,
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "duration_seconds": Date().timeIntervalSince(start),
      "model": identity,
      "model_load_seconds": loadSeconds,
      "database_at_start": databaseAtStart,
      "database_after": databaseAfter,
      "semantic_state_directory": stateDirectory.path,
      "recovery": [
        "authorized_by_is_state_id": stageAState["state_id"] ?? "",
        "authorized_by_is_runtime_application_status": stageAState["runtime_application_status"] ?? "",
        "recovered_position": recovered.position.value,
        "recovered_lifecycle": recovered.lifecycle.rawValue,
        "bound_prefix_token_count": bound.prefix.count,
        "stage_a_prefix_token_count": stageAPrefixCount,
        "prefix_tail_matches_stage_a_generated_tokens": prefixTailMatches,
        "persisted_representation_rebound": true,
        "tokenize_seed_calls_this_call": outcome.report.tokenizeSeedCallCount,
      ],
      "is_reads": [
        "u1_settlement_object_id": admittedU1ObjectID,
        "stage_a_u1_settlement_object_id": stageAU1ObjectID,
        "u1_settlement_object_matches_stage_a": admittedU1ObjectID == stageAU1ObjectID,
        "checksum_source_settlement_object_id": admittedSourceObjectID,
        "stage_a_source_settlement_object_id": stageASourceObjectID,
        "source_settlement_object_matches_stage_a":
          admittedSourceObjectID == stageASourceObjectID,
        "harness_read_settlement_calls": 0,
        "harness_read_item_calls": 0,
        "resolved_by": "production entry: resolveTaskInput",
      ],
      "prompt": [
        "next_input_sha256": outcome.admission.inputSHA256,
        "next_input_byte_length": outcome.admission.inputByteLength,
        "next_input_uses_admitted_u1_secret":
          outcome.admission.inputText.contains(admittedSecret),
        "next_input_uses_admitted_checksum":
          outcome.admission.inputText.contains(admittedChecksum),
        "input_admission": outcome.admission.evidenceDictionary(),
      ],
      "continuation": reportDictionary(outcome.report),
      "counters": executor.counterSnapshot,
      "incremental_work": [
        "new_generated_token_count": outcome.report.generatedTokenIDs.count,
        "generated_tokens_differ_from_stage_a": outcome.report.generatedTokenIDs != stageAGenerated,
        "computed_item_ids": outcome.report.computedItemIDs,
        "reused_item_ids": outcome.report.reusedItemIDs,
      ],
      "terminal_state": "STAGE_C_PASS",
    ]
    try writeExclusiveJSON(record, to: evidenceDirectory.appendingPathComponent("stage-c.json"))
  } catch {
    let record: [String: Any] = [
      "schema_id": "SIMIGO-REAL-MODEL-HANDOFF-STAGE-V1",
      "stage": "C",
      "run_label": options.runLabel,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "failure": String(describing: error),
      "terminal_state": "STAGE_C_FAIL",
    ]
    try? writeExclusiveJSON(record, to: failureURL)
    throw error
  }
}

func settlementObjectIDFrom(_ continuation: [String: Any], itemID: String) -> String? {
  guard let actions = continuation["settlement_actions"] as? [[String: Any]] else {
    return nil
  }
  for action in actions where (action["item_id"] as? String) == itemID {
    return action["settlement_object_id"] as? String
  }
  return nil
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
  guard let command = arguments.first else {
    throw HandoffError("usage: RealModelHandoff <stage-a|stage-c|phase1-case|phase2-u2> --run-dir ... --model-dir ... --lab-root ... [--run-label ...]")
  }
  let options = try Options(arguments: arguments)
  switch command {
  case "stage-a":
    try await runStageA(options)
  case "stage-c":
    try await runStageC(options)
  case "phase1-case":
    try await runPhase1Case(options)
  case "phase2-u2":
    try await runPhase2U2(options)
  default:
    throw HandoffError("unknown command: \(command)")
  }
  exit(0)
} catch {
  FileHandle.standardError.write(
    Data("REAL_MODEL_HANDOFF_FAIL: \(error)\n".utf8))
  exit(1)
}
