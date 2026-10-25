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

// ORDINARY TASK ENTRY
//
// One process executes exactly one task item on the real model:
//
//   1. read the item's OWN task definition (prompt seed + result contract),
//   2. call the production `continueTask` entry, which resolves and admits the
//      item's declared dependency settlements from the Information Space,
//   3. tokenize and generate, settle the model result, advance the ES, and
//      confirm the IS runtime application.
//
// This binary contains no handoff orchestration: it never reads a settlement,
// never expands an input template, and never receives an input text or a
// settled value through argv, environment or a side file. The only inputs are
// the task item identity and the model snapshot.

/// A fresh execution instance's own preamble. It is not a task input: the
/// admitted task input is appended by the production entry.
let coldSeed = """
SIMIGO-ORDINARY-TASK-COLD-V1
You are executing one task step in a new execution instance.
"""

struct Options {
  let database: URL
  let modelDir: URL
  let labRoot: URL
  let stateDir: URL
  let output: URL
  let itemID: String
  let demandID: String
  let advancementID: String
  let evaluatedAtUTC: String
  let runID: String
  let maxTokens: Int
  /// Admit the item's input and STOP before loading or calling the model. Used
  /// as the model-free probe of the same admission path a real run uses.
  let admissionProbe: Bool

  init(_ arguments: [String]) throws {
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      let key = arguments[index]
      if key == "--admission-probe" {
        values["admission-probe"] = "1"
        index += 1
        continue
      }
      guard key.hasPrefix("--"), index + 1 < arguments.count else {
        throw TaskEntryError("usage: SimiGoTaskRun --database ... --item ...")
      }
      values[String(key.dropFirst(2))] = arguments[index + 1]
      index += 2
    }
    func required(_ name: String) throws -> String {
      guard let value = values[name], !value.isEmpty else {
        throw TaskEntryError("missing --\(name)")
      }
      return value
    }
    database = URL(fileURLWithPath: try required("database"))
    modelDir = URL(fileURLWithPath: try required("model-dir"), isDirectory: true)
    labRoot = URL(fileURLWithPath: try required("lab-root"), isDirectory: true)
    stateDir = URL(fileURLWithPath: try required("state-dir"), isDirectory: true)
    output = URL(fileURLWithPath: try required("out"))
    itemID = try required("item")
    demandID = try required("demand")
    advancementID = try required("advancement")
    evaluatedAtUTC = try required("evaluated-at")
    runID = values["run-id"] ?? "ordinary-task-\(ProcessInfo.processInfo.processIdentifier)"
    maxTokens = Int(values["max-tokens"] ?? "24") ?? 24
    admissionProbe = values["admission-probe"] == "1"
  }
}

final class CountingModelExecutor:
  ProductionRuntimeModelContinuationExecutor, @unchecked Sendable
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

  var snapshot: [String: Int] {
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
}

func utcNow() -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.string(from: Date())
}

func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func sha256File(_ url: URL) throws -> String {
  let handle = try FileHandle(forReadingFrom: url)
  defer { try? handle.close() }
  var hash = SHA256()
  while true {
    guard let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else {
      break
    }
    hash.update(data: chunk)
  }
  return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

func fileIdentity(_ url: URL) throws -> [String: Any] {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
  let inode = (attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? -1
  return [
    "path": url.path,
    "size_bytes": size,
    "inode": String(inode),
    "sha256": try sha256File(url),
  ]
}

func directoryIdentity(_ directory: URL) throws -> [String: String] {
  guard let enumerator = FileManager.default.enumerator(
    at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
    return [:]
  }
  let base = directory.standardizedFileURL.path
  var identity: [String: String] = [:]
  for case let url as URL in enumerator {
    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      continue
    }
    let path = url.standardizedFileURL.path
    let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
    identity[relative] = try sha256File(url)
  }
  return identity
}

func modelIdentity(_ snapshot: URL) throws -> [String: Any] {
  let fileManager = FileManager.default
  let names = try fileManager.contentsOfDirectory(atPath: snapshot.path).sorted()
  var lines: [String] = []
  var weightFiles: [[String: Any]] = []
  for name in names where name.hasSuffix(".safetensors") {
    let url = snapshot.appendingPathComponent(name)
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
    let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path)
    let content = destination.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "file"
    lines.append("\(name):\(content):\(size)")
    weightFiles.append(["name": name, "content": content, "size_bytes": size])
  }
  guard !weightFiles.isEmpty else {
    throw TaskEntryError("model snapshot carries no safetensors weights")
  }
  return [
    "snapshot_path": snapshot.path,
    "snapshot_revision": snapshot.lastPathComponent,
    "weights_manifest_sha256": sha256Hex(
      Data(lines.joined(separator: "\n").utf8)),
    "weight_files": weightFiles,
  ]
}

func writeEvidence(_ record: [String: Any], to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let data = try JSONSerialization.data(
    withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
  try data.write(to: url, options: .atomic)
}

func run(_ arguments: [String]) async throws {
  let options = try Options(arguments)
  let startedAt = utcNow()
  let start = Date()
  let fileManager = FileManager.default
  try fileManager.createDirectory(at: options.stateDir, withIntermediateDirectories: true)

  let databaseBefore = try fileIdentity(options.database)
  let stateBefore = try directoryIdentity(options.stateDir)

  let runtimeRoot = options.labRoot.appendingPathComponent("execution-information-loop")
  let trustAnchorPath = ProcessInfo.processInfo.environment["SIMIGO_SETTLEMENT_TRUST_ANCHOR"]
  let configuration = ProductionRuntimeLaunchConfiguration(
    runtimeRoot: runtimeRoot,
    pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
    snapshotPath: options.labRoot.appendingPathComponent(
      "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"),
    validityPolicyPath: options.labRoot.appendingPathComponent(
      "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"),
    settlementTrustAnchorPath: trustAnchorPath.map { URL(fileURLWithPath: $0) })

  if options.admissionProbe {
    // Model-free admission probe: the SAME `resolveTaskInput` a real run uses,
    // with no model executor attached and no fresh-baseline reset. Zero model
    // work by construction, so a refusal here is a pre-generation refusal.
    let integration = try ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: nil,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: options.stateDir,
      resetToFreshBaseline: false)
    var probeAdmission: ProductionTaskInputAdmission?
    var probeRefusal: [String: Any] = [:]
    var probeFailure = ""
    do {
      probeAdmission = try integration.resolveTaskInput(
        database: options.database,
        taskItemID: options.itemID,
        evaluatedAtUTC: options.evaluatedAtUTC)
    } catch let error as ProductionRuntimeInformationError {
      switch error {
      case .informationSpaceInputAdmissionRefused(let itemID, let stage, let reason):
        probeRefusal = ["kind": "ADMISSION_REFUSED", "item_id": itemID,
                        "stage": stage, "reason": reason]
      case .informationSpaceInputBindingMismatch(let field):
        probeRefusal = ["kind": "BINDING_MISMATCH", "field": field]
      default:
        probeFailure = String(describing: error)
      }
    } catch {
      probeFailure = String(describing: error)
    }
    let databaseAfter = try fileIdentity(options.database)
    let stateAfter = try directoryIdentity(options.stateDir)
    let probeStatus: String
    if probeAdmission != nil {
      probeStatus = "ADMITTED"
    } else if let kind = probeRefusal["kind"] as? String {
      probeStatus = kind
    } else {
      probeStatus = "NOT_ATTEMPTED"
    }
    var probeRecord: [String: Any] = [
      "schema_id": "SIMIGO-ORDINARY-TASK-ENTRY-V1",
      "entry": "SimiGoTaskRun",
      "mode": "admission_probe",
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "duration_seconds": Date().timeIntervalSince(start),
      "task_item_id": options.itemID,
      "demand_id": options.demandID,
      "advancement_id": options.advancementID,
      "evaluated_at_utc": options.evaluatedAtUTC,
      "run_id": options.runID,
      "database": options.database.path,
      "database_before": databaseBefore,
      "database_after": databaseAfter,
      "database_unchanged": (databaseBefore["sha256"] as? String)
        == (databaseAfter["sha256"] as? String),
      "state_directory": options.stateDir.path,
      "state_before": stateBefore,
      "state_after": stateAfter,
      "state_unchanged": stateBefore == stateAfter,
      "counters": [
        "tokenize_text_calls": 0,
        "tokenize_seed_calls": 0,
        "model_continuation_calls": 0,
      ],
      "generation_entered": false,
      "model_loaded": false,
      "input_admission_status": probeStatus,
      "input_admission": probeAdmission?.evidenceDictionary() ?? [:],
      "input_admission_refusal": probeRefusal,
      "failure": probeFailure,
      "trust_anchor_path": trustAnchorPath ?? "",
    ]
    if let probeAdmission {
      probeRecord["declared_dependencies"] = probeAdmission.declaredDependencies
      probeRecord["dependency_settlement_object_ids"] =
        probeAdmission.dependencySettlementObjectIDs
      probeRecord["admitted_input_sha256"] = probeAdmission.inputSHA256
      probeRecord["settlement_signatures"] = probeAdmission.settlementSignatures.map {
        $0.evidenceDictionary()
      }
    }
    probeRecord["terminal_state"] = probeAdmission != nil
      ? "INPUT_ADMITTED" : "INPUT_ADMISSION_REFUSED"
    try writeEvidence(probeRecord, to: options.output)
    if probeAdmission == nil {
      throw TaskEntryError(
        probeFailure.isEmpty ? "input not admitted: \(probeRefusal)" : probeFailure)
    }
    return
  }

  let loadStart = Date()
  let container = try await LLMModelFactory.shared.loadContainer(
    from: options.modelDir, using: #huggingFaceTokenizerLoader())
  let loadSeconds = Date().timeIntervalSince(loadStart)
  let identity = try modelIdentity(options.modelDir)

  let backend = MLXExecutionStateBackend()
  let executor = CountingModelExecutor(
    base: MLXPrefixRecomputeExecutor(container: container, backend: backend))
  let integration = try ProductionRuntimeInformationIntegration(
    configuration: configuration,
    modelExecutor: executor,
    backend: backend,
    semanticStateDirectory: options.stateDir,
    resetToFreshBaseline: true)
  let provenance = ProductionTaskProvenance(
    runID: options.runID,
    buildSHA256: ProductionTaskProvenance.buildIdentity(runtimeRoot: runtimeRoot),
    modelSnapshotRevision: identity["snapshot_revision"] as? String ?? "",
    weightsManifestSHA256: identity["weights_manifest_sha256"] as? String ?? "")

  // The item's OWN task definition: its prompt seed and its result contract.
  // No settlement is read and no template is expanded here.
  let itemResponse = try integration.readItem(database: options.database, itemID: options.itemID)
  guard let item = itemResponse["item"] as? [String: Any],
        let payload = item["source_payload"] as? [String: Any] else {
    throw TaskEntryError("task item \(options.itemID) has no readable definition")
  }
  let declaredSeed = payload["prompt_seed"] as? String
  let seedText = declaredSeed ?? coldSeed
  let contract = try TaskResultContract(payload: payload)

  var outcome: ProductionTaskInformationContinuation?
  var refusal: [String: Any] = [:]
  var failure = ""
  do {
    outcome = try await integration.continueTask(
      database: options.database,
      handle: nil,
      advancementID: options.advancementID,
      evaluatedAtUTC: options.evaluatedAtUTC,
      demandID: options.demandID,
      taskItemID: options.itemID,
      seedText: seedText,
      provenance: provenance,
      maxTokens: options.maxTokens
    ) { produced, admitted in
      try contract.value(
        for: produced, admitted: admitted, modelIdentity: identity)
    }
  } catch let error as ProductionRuntimeInformationError {
    switch error {
    case .informationSpaceInputAdmissionRefused(let itemID, let stage, let reason):
      refusal = ["kind": "ADMISSION_REFUSED", "item_id": itemID,
                 "stage": stage, "reason": reason]
    case .informationSpaceInputBindingMismatch(let field):
      refusal = ["kind": "BINDING_MISMATCH", "field": field]
    default:
      failure = String(describing: error)
    }
  } catch {
    failure = String(describing: error)
  }

  let databaseAfter = try fileIdentity(options.database)
  let stateAfter = try directoryIdentity(options.stateDir)
  let admitted = outcome?.admission
  let report = outcome?.report
  let admissionStatus: String
  if admitted != nil {
    admissionStatus = "ADMITTED"
  } else if let kind = refusal["kind"] as? String {
    admissionStatus = kind
  } else {
    admissionStatus = "NOT_ATTEMPTED"
  }

  var record: [String: Any] = [
    "schema_id": "SIMIGO-ORDINARY-TASK-ENTRY-V1",
    "entry": "SimiGoTaskRun",
    "pid": Int(ProcessInfo.processInfo.processIdentifier),
    "started_at_utc": startedAt,
    "completed_at_utc": utcNow(),
    "duration_seconds": Date().timeIntervalSince(start),
    "task_item_id": options.itemID,
    "demand_id": options.demandID,
    "advancement_id": options.advancementID,
    "evaluated_at_utc": options.evaluatedAtUTC,
    "max_tokens": options.maxTokens,
    "model": identity,
    "model_load_seconds": loadSeconds,
    "seed_source": declaredSeed == nil ? "builtin_cold_seed" : "item.prompt_seed",
    "seed_sha256": sha256Hex(Data(seedText.utf8)),
    "database": options.database.path,
    "database_before": databaseBefore,
    "database_after": databaseAfter,
    "database_unchanged": (databaseBefore["sha256"] as? String)
      == (databaseAfter["sha256"] as? String),
    "state_directory": options.stateDir.path,
    "state_before": stateBefore,
    "state_after": stateAfter,
    "state_unchanged": stateBefore == stateAfter,
    "counters": executor.snapshot,
    "generation_entered": (executor.snapshot["model_continuation_calls"] ?? 0) > 0,
    "run_id": options.runID,
    "provenance_identity": [
      "run_id": provenance.runID,
      "execution_id": provenance.executionID,
      "process_id": provenance.processID,
      "build_sha256": provenance.buildSHA256,
    ],
    "trust_anchor_path": trustAnchorPath ?? "",
    "input_admission_status": admissionStatus,
    "input_admission": admitted?.evidenceDictionary() ?? [:],
    "input_admission_refusal": refusal,
    "failure": failure,
  ]
  if let admitted {
    record["declared_dependencies"] = admitted.declaredDependencies
    record["dependency_settlement_object_ids"] = admitted.dependencySettlementObjectIDs
    record["admitted_input_sha256"] = admitted.inputSHA256
    record["admitted_input_byte_length"] = admitted.inputByteLength
    record["bindings"] = admitted.bindings.map { binding in
      [
        "placeholder": binding.placeholder,
        "item_id": binding.itemID,
        "value": binding.value,
        "value_sha256": binding.valueSHA256,
        "settlement_object_id": binding.settlementObjectID,
        "byte_offset": binding.byteOffset,
        "byte_length": binding.byteLength,
      ]
    }
  }
  if let report {
    record["settlement"] = [
      "computed_item_ids": report.computedItemIDs,
      "reused_item_ids": report.reusedItemIDs,
      "actions": report.settlementActions.map { action in
        [
          "item_id": action.itemID,
          "action": action.action,
          "settlement_object_id": action.settlementObjectID,
          "result_digest": action.resultDigest,
          "settlement_signature_object_id": action.settlementSignatureObjectID ?? "",
        ]
      },
      "settlement_signature_object_id": report.settlementSignatureObjectID,
      "signed_settlement_object_id": report.signedSettlementObjectID,
      "settlement_signature_key_id": report.settlementSignatureKeyID,
      "is_pending_state_id": report.isPendingStateID,
      "is_confirmation_state_id": report.isConfirmationStateID,
      "advanced_position": report.advancedPosition,
      "advanced_lifecycle": report.advancedLifecycle,
      "generated_token_count": report.generatedTokenIDs.count,
      "updated_prefix_token_count": report.updatedPrefixTokenCount,
      "tokenize_seed_calls_this_call": report.tokenizeSeedCallCount,
      "tokenize_next_input_calls_this_call": report.tokenizeNextInputCallCount,
      "model_continuation_calls_this_call": report.modelContinuationCallCount,
    ]
    record["generated_text"] = report.generatedText
    record["generated_text_sha256"] = sha256Hex(Data(report.generatedText.utf8))
    record["generated_token_ids"] = report.generatedTokenIDs
  }
  record["terminal_state"] = report != nil ? "TASK_SETTLED"
    : (refusal.isEmpty ? "TASK_FAILED" : "INPUT_ADMISSION_REFUSED")

  try writeEvidence(record, to: options.output)
  if report == nil {
    throw TaskEntryError(
      failure.isEmpty ? "task did not settle: \(refusal)" : failure)
  }
}

@main
struct SimiGoTaskRun {
  static func main() async {
    do {
      try await run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      FileHandle.standardError.write(
        Data(("error: \(error)\n").utf8))
      exit(1)
    }
  }
}
