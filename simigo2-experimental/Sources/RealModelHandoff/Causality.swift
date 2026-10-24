import Darwin
import Foundation
import SimiGo2Experimental
import SimiGoRuntimeContract

// Controlled causal experiments around the production recovery and settlement
// paths.  This file deliberately contains no new recovery policy: it drives the
// existing entry points and records what they actually did.

struct CausalityError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

func directoryFileIdentities(_ directory: URL) throws -> [[String: Any]] {
  let fileManager = FileManager.default
  guard fileManager.fileExists(atPath: directory.path) else { return [] }
  guard let enumerator = fileManager.enumerator(
    at: directory,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
  ) else {
    return []
  }
  let base = directory.standardizedFileURL.path
  var files: [[String: Any]] = []
  for case let url as URL in enumerator {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else { continue }
    let path = url.standardizedFileURL.path
    let relative = path.hasPrefix(base + "/")
      ? String(path.dropFirst(base.count + 1))
      : path
    let attributes = try fileManager.attributesOfItem(atPath: path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
    files.append([
      "path": relative,
      "size_bytes": size,
      "sha256": try fileSHA256(url),
    ])
  }
  return files.sorted {
    ($0["path"] as? String ?? "") < ($1["path"] as? String ?? "")
  }
}

func readJSONObject(_ url: URL) throws -> [String: Any] {
  let data = try Data(contentsOf: url)
  guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw CausalityError("not a JSON object: \(url.path)")
  }
  return object
}

func phaseErrorLabel(_ error: Error) -> String {
  guard let production = error as? ProductionRuntimeInformationError else {
    return "unexpected: \(String(describing: error))"
  }
  switch production {
  case .durableRecoveryNotConfigured:
    return "durableRecoveryNotConfigured"
  case .informationSpaceHasNoSettledExecution(let state):
    return "informationSpaceHasNoSettledExecution:\(state)"
  case .durableExecutionStateMissing(let executionID):
    return "durableExecutionStateMissing:\(executionID)"
  case .persistedRepresentationUnavailable(let executionID, let position):
    return "persistedRepresentationUnavailable:\(executionID):\(position)"
  case .settlementCheckpointMissing(let executionID):
    return "settlementCheckpointMissing:\(executionID)"
  case .settlementCheckpointMismatch(let executionID, let field):
    return "settlementCheckpointMismatch:\(executionID):\(field)"
  case .modelExecutorUnavailable:
    return "modelExecutorUnavailable"
  case .modelExecutionFailed(let reason):
    return "modelExecutionFailed:\(reason)"
  case .blockedInformationDemand(let command, let state, let items):
    return "blockedInformationDemand:\(command):\(state):\(items.joined(separator: ","))"
  case .bridgeFailed(let command, let exitCode, let message):
    return "bridgeFailed:\(command):\(exitCode):\(message)"
  case .invalidBridgeResponse(let command):
    return "invalidBridgeResponse:\(command)"
  case .launchConfigurationInvalid(let path, let message):
    return "launchConfigurationInvalid:\(path):\(message)"
  case .invalidPersistedExecutionState(let lifecycle):
    return "invalidPersistedExecutionState:\(lifecycle)"
  case .bridgeRefused(let command, let stage, let reason, let itemID):
    return "bridgeRefused:\(command):\(stage):\(reason):\(itemID ?? "")"
  case .informationSpaceInputAdmissionRefused(let itemID, let stage, let reason):
    return "informationSpaceInputAdmissionRefused:\(itemID):\(stage):\(reason)"
  case .informationSpaceInputBindingMismatch(let field):
    return "informationSpaceInputBindingMismatch:\(field)"
  }
}

func processIsAlive(_ pid: Int32) -> Bool {
  guard pid > 0 else { return false }
  if kill(pid, 0) == 0 { return true }
  return errno == EPERM
}

// MARK: - Phase 1: recovery admission

func runPhase1Case(_ options: Options) async throws {
  guard let caseName = options.caseName else {
    throw CausalityError("--case is required")
  }
  let startedAt = utcNow()
  let start = Date()
  let database = options.runDir.appendingPathComponent("carrier.sqlite")
  let stateDirectory = options.stateDirectory
    ?? options.runDir.appendingPathComponent("state", isDirectory: true)
  let evidenceDirectory = options.runDir.appendingPathComponent("evidence", isDirectory: true)
  try FileManager.default.createDirectory(
    at: evidenceDirectory, withIntermediateDirectories: true)

  do {
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

    let databaseBefore = try fileIdentity(database)
    let stateBefore = try directoryFileIdentities(stateDirectory)
    let statusBefore: [String: Any]
    do {
      statusBefore = try integration.status(database: database)
    } catch {
      statusBefore = ["status_error": phaseErrorLabel(error)]
    }

    var recoverySucceeded = false
    var recoveredPosition = -1
    var recoveredLifecycle = ""
    var boundPrefixTokenCount = -1
    var stageAPrefixTailMatches: Any = NSNull()
    var failureLabel: Any = NSNull()
    var failureDescription: Any = NSNull()
    var continueTaskEntered = false
    var productionContinuationInvoked = false
    var admissionStatus = "NOT_ATTEMPTED"
    var admissionEvidence: Any = NSNull()
    var admissionRefusal: Any = NSNull()
    var continuation: [String: Any] = [:]
    var isReads: [String: Any] = [:]
    var prompt: [String: Any] = [:]
    var output: [String: Any] = [:]

    do {
      let recovered = try await integration.recoverExecutionState(database: database)
      recoverySucceeded = true
      recoveredPosition = Int(recovered.position.value)
      recoveredLifecycle = recovered.lifecycle.rawValue
      let bound = try backend.boundPrefix(for: recovered)
      boundPrefixTokenCount = bound.prefix.count

      if let baselineDir = options.baselineDir {
        let stageAURL = baselineDir.appendingPathComponent("evidence/stage-a.json")
        let stageA = try readJSONObject(stageAURL)
        if let stageAContinuation = stageA["continuation"] as? [String: Any],
           let expectedCount = stageAContinuation["updated_prefix_token_count"] as? Int,
           let generated = stageAContinuation["generated_token_ids"] as? [Int] {
          let tail = Array(bound.prefix.suffix(generated.count))
          stageAPrefixTailMatches =
            bound.prefix.count == expectedCount && tail == generated
        }
      }

      if caseName == "A0" {
        // The production task path resolves, admits and materializes the input
        // from IS. The harness neither reads settlements nor interpolates a
        // template; it only names the task item.
        productionContinuationInvoked = true
        let outcome = try await integration.continueTask(
          database: database,
          handle: recovered,
          advancementID: "phase1-a0-u2-\(options.runLabel)",
          evaluatedAtUTC: utcNowPlus(1),
          demandID: "handoff-u2",
          taskItemID: "TASK-U2",
          seedText: nil,
          provenance: ProductionTaskProvenance(
            runID: "causality-phase1-\(options.runLabel)",
            buildSHA256: ProductionTaskProvenance.buildIdentity(
              runtimeRoot: options.labRoot.appendingPathComponent("execution-information-loop")),
            modelSnapshotRevision: identity["snapshot_revision"] as? String ?? "",
            weightsManifestSHA256: identity["weights_manifest_sha256"] as? String ?? ""),
          maxTokens: options.maxTokens
        ) { produced, admitted in
          guard let answer = firstCapture(
            produced.generatedText, pattern: "ANSWER=([A-Za-z0-9]+-[A-Za-z0-9]+)"),
            let secret = admitted.value(forPlaceholder: "secret"),
            let checksum = admitted.value(forPlaceholder: "checksum") else {
            throw CausalityError(
              "real model produced no ANSWER=<secret>-<checksum> line: \(produced.generatedText)")
          }
          let revision = identity["snapshot_revision"] as? String ?? ""
          let weightsDigest = identity["weights_manifest_sha256"] as? String ?? ""
          return [
            "answer": answer,
            "secret": secret,
            "checksum": checksum,
            "secret_source_settlement_object_id":
              admitted.dependencySettlementObjectIDs["TASK-U1"] ?? "",
            "checksum_source_settlement_object_id":
              admitted.dependencySettlementObjectIDs["TASK-SOURCE"] ?? "",
            "raw_generated_text": produced.generatedText,
            "generated_token_ids": produced.generatedTokenIDs,
            "model_snapshot_revision": revision,
            "model_weights_manifest_sha256": weightsDigest,
            "model_call_index": 1,
          ]
        }
        continueTaskEntered = true
        admissionStatus = "ADMITTED"
        admissionEvidence = outcome.admission.evidenceDictionary()
        isReads = [
          "executor_resolved_dependencies": outcome.admission.declaredDependencies,
          "dependency_settlement_object_ids":
            outcome.admission.dependencySettlementObjectIDs,
          "harness_read_settlement_calls": 0,
          "harness_read_item_calls": 0,
        ]
        prompt = [
          "next_input": outcome.admission.inputText,
          "next_input_sha256": outcome.admission.inputSHA256,
          "next_input_byte_length": outcome.admission.inputByteLength,
          "uses_settled_u1_secret": outcome.admission
            .value(forPlaceholder: "secret").map { outcome.admission.inputText.contains($0) } ?? false,
          "uses_settled_checksum": outcome.admission
            .value(forPlaceholder: "checksum").map { outcome.admission.inputText.contains($0) } ?? false,
        ]
        continuation = reportDictionary(outcome.report)
        output = [
          "answer": firstCapture(
            outcome.report.generatedText,
            pattern: "ANSWER=([A-Za-z0-9]+-[A-Za-z0-9]+)") ?? "",
          "generated_text": outcome.report.generatedText,
          "generated_token_ids": outcome.report.generatedTokenIDs,
        ]
      }
    } catch {
      failureLabel = phaseErrorLabel(error)
      failureDescription = String(describing: error)
      if let production = error as? ProductionRuntimeInformationError {
        switch production {
        case .informationSpaceInputAdmissionRefused(let itemID, let stage, let reason):
          admissionStatus = "REFUSED"
          admissionRefusal = ["item_id": itemID, "stage": stage, "reason": reason]
        case .informationSpaceInputBindingMismatch(let field):
          admissionStatus = "BINDING_MISMATCH"
          admissionRefusal = ["field": field]
        default:
          if productionContinuationInvoked { admissionStatus = "ERROR" }
        }
      } else if productionContinuationInvoked {
        admissionStatus = "ERROR"
      }
    }

    let generationCalls = executor.counterSnapshot["model_continuation_calls"] ?? 0
    continueTaskEntered = generationCalls > 0

    let databaseAfter = try fileIdentity(database)
    let stateAfter = try directoryFileIdentities(stateDirectory)
    let record: [String: Any] = [
      "schema_id": "SIMIGO-CAUSALITY-PHASE1-V1",
      "phase": "PHASE1_RECOVERY_ADMISSION",
      "case": caseName,
      "run_label": options.runLabel,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "duration_seconds": Date().timeIntervalSince(start),
      "model": identity,
      "model_load_seconds": loadSeconds,
      "database_before": databaseBefore,
      "database_after": databaseAfter,
      "state_directory": stateDirectory.path,
      "state_before": stateBefore,
      "state_after": stateAfter,
      "is_status_before": statusBefore,
      "recovery_succeeded": recoverySucceeded,
      "recovered_position": recoveredPosition,
      "recovered_lifecycle": recoveredLifecycle,
      "bound_prefix_token_count": boundPrefixTokenCount,
      "stage_a_prefix_tail_matches": stageAPrefixTailMatches,
      "failure_label": failureLabel,
      "failure_description": failureDescription,
      "continue_task_entered": continueTaskEntered,
      "production_continuation_invoked": productionContinuationInvoked,
      "generation_entered": generationCalls > 0,
      "input_admission_status": admissionStatus,
      "input_admission": admissionEvidence,
      "input_admission_refusal": admissionRefusal,
      "counters": executor.counterSnapshot,
      "continuation": continuation,
      "is_reads": isReads,
      "prompt": prompt,
      "output": output,
      "terminal_state": "PHASE1_OBSERVED",
    ]
    try writeExclusiveJSON(
      record, to: evidenceDirectory.appendingPathComponent("phase1.json"))
  } catch {
    let record: [String: Any] = [
      "schema_id": "SIMIGO-CAUSALITY-PHASE1-V1",
      "phase": "PHASE1_RECOVERY_ADMISSION",
      "case": caseName,
      "run_label": options.runLabel,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "failure": String(describing: error),
      "terminal_state": "PHASE1_HARNESS_FAIL",
    ]
    if FileManager.default.fileExists(atPath: evidenceDirectory.path) {
      try? writeExclusiveJSON(
        record, to: evidenceDirectory.appendingPathComponent("phase1-fail.json"))
    }
    throw error
  }
}

// MARK: - Phase 2: actual handoff data path

private let coldU2Seed = """
SIMIGO-HANDOFF-COLD-U2-V1
You are executing step 2 in a fresh execution instance.
"""

func runPhase2U2(_ options: Options) async throws {
  guard let caseName = options.caseName else {
    throw CausalityError("--case is required")
  }
  let startedAt = utcNow()
  let start = Date()
  let database = options.runDir.appendingPathComponent("carrier.sqlite")
  guard let stateDirectory = options.stateDirectory else {
    throw CausalityError("--state-dir is required for phase2-u2")
  }
  let evidenceDirectory = options.runDir.appendingPathComponent("evidence", isDirectory: true)
  try FileManager.default.createDirectory(
    at: evidenceDirectory, withIntermediateDirectories: true)
  if !FileManager.default.fileExists(atPath: stateDirectory.path) {
    try FileManager.default.createDirectory(
      at: stateDirectory, withIntermediateDirectories: true)
  }
  let stateEntriesBefore = try FileManager.default.contentsOfDirectory(
    atPath: stateDirectory.path)
  let stateDirectoryWasEmpty = stateEntriesBefore.isEmpty

  do {
    let u1PID = options.u1PID
    let u1AliveAtStart = u1PID.map(processIsAlive) ?? false
    if u1AliveAtStart {
      throw CausalityError("U1 process \(u1PID ?? -1) is still alive; U2 is not independent")
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

    let databaseBefore = try fileIdentity(database)
    let stateBefore = try directoryFileIdentities(stateDirectory)
    let statusBefore: [String: Any]
    do {
      statusBefore = try integration.status(database: database)
    } catch {
      statusBefore = ["status_error": phaseErrorLabel(error)]
    }

    // The executor resolves, admits and materializes the U2 input from IS.
    // Nothing here reads a settlement or interpolates a template.
    var secret = ""
    var checksum = ""
    var u1ObjectID = ""
    var sourceObjectID = ""
    var admission: ProductionTaskInputAdmission?
    var admissionStatus = "NOT_ATTEMPTED"
    var admissionRefusal: Any = NSNull()
    var productionContinuationInvoked = false
    var continueTaskEntered = false
    var continuation: [String: Any] = [:]
    var output: [String: Any] = [:]
    var settledReport: ProductionTaskContinuationReport?
    var settlementFailureLabel: Any = NSNull()
    var settlementFailureDescription: Any = NSNull()
    // The production continuation throws after generation when the model value
    // is rejected; keep the produced text here so a failure is diagnosable
    // (truncation vs. wrong characters) instead of only a bridge message.
    var lastGeneratedText = ""
    var lastGeneratedTokenIDs: [Int] = []
    var lastParsedAnswer = ""
    var modelValueFailure = ""

    let revision = identity["snapshot_revision"] as? String ?? ""
    let weightsDigest = identity["weights_manifest_sha256"] as? String ?? ""
    productionContinuationInvoked = true
    do {
      let outcome = try await integration.continueTask(
        database: database,
        handle: nil,
        advancementID: "phase2-\(caseName)-u2-\(options.runLabel)",
        evaluatedAtUTC: utcNowPlus(1),
        demandID: "handoff-u2",
        taskItemID: "TASK-U2",
        seedText: coldU2Seed,
        provenance: ProductionTaskProvenance(
          runID: "causality-phase2-\(caseName)-\(options.runLabel)",
          buildSHA256: ProductionTaskProvenance.buildIdentity(
            runtimeRoot: options.labRoot.appendingPathComponent("execution-information-loop")),
          modelSnapshotRevision: revision,
          weightsManifestSHA256: weightsDigest),
        maxTokens: options.maxTokens
      ) { produced, admitted in
        lastGeneratedText = produced.generatedText
        lastGeneratedTokenIDs = produced.generatedTokenIDs
        guard let answer = firstCapture(
          produced.generatedText, pattern: "ANSWER=([A-Za-z0-9]+-[A-Za-z0-9]+)"),
          let admittedSecret = admitted.value(forPlaceholder: "secret"),
          let admittedChecksum = admitted.value(forPlaceholder: "checksum") else {
          modelValueFailure = "no ANSWER line or admitted placeholder value"
          throw CausalityError(
            "real model produced no ANSWER=<secret>-<checksum> line: \(produced.generatedText)")
        }
        lastParsedAnswer = answer
        return [
          "answer": answer,
          "secret": admittedSecret,
          "checksum": admittedChecksum,
          "secret_source_settlement_object_id":
            admitted.dependencySettlementObjectIDs["TASK-U1"] ?? "",
          "checksum_source_settlement_object_id":
            admitted.dependencySettlementObjectIDs["TASK-SOURCE"] ?? "",
          "raw_generated_text": produced.generatedText,
          "generated_token_ids": produced.generatedTokenIDs,
          "model_snapshot_revision": revision,
          "model_weights_manifest_sha256": weightsDigest,
          "model_call_index": 1,
        ]
      }
      admission = outcome.admission
      admissionStatus = "ADMITTED"
      secret = outcome.admission.value(forPlaceholder: "secret") ?? ""
      checksum = outcome.admission.value(forPlaceholder: "checksum") ?? ""
      u1ObjectID = outcome.admission.dependencySettlementObjectIDs["TASK-U1"] ?? ""
      sourceObjectID = outcome.admission.dependencySettlementObjectIDs["TASK-SOURCE"] ?? ""
      settledReport = outcome.report
      continuation = reportDictionary(outcome.report)
    } catch {
      settlementFailureLabel = phaseErrorLabel(error)
      settlementFailureDescription = String(describing: error)
      if let production = error as? ProductionRuntimeInformationError {
        switch production {
        case .informationSpaceInputAdmissionRefused(let itemID, let stage, let reason):
          admissionStatus = "REFUSED"
          admissionRefusal = ["item_id": itemID, "stage": stage, "reason": reason]
        case .informationSpaceInputBindingMismatch(let field):
          admissionStatus = "BINDING_MISMATCH"
          admissionRefusal = ["field": field]
        default:
          admissionStatus = "ERROR"
        }
      } else {
        admissionStatus = "ERROR"
      }
    }

    let generationCalls = executor.counterSnapshot["model_continuation_calls"] ?? 0
    continueTaskEntered = generationCalls > 0
    let expectedAnswer = "\(secret)-\(checksum)"
    if let report = settledReport {
      let answer = firstCapture(
        report.generatedText,
        pattern: "ANSWER=([A-Za-z0-9]+-[A-Za-z0-9]+)") ?? ""
      output = [
        "answer": answer,
        "answer_sha256": sha256Hex(Data(answer.utf8)),
        "expected_answer_sha256": sha256Hex(Data(expectedAnswer.utf8)),
        "matches_settled_expected": !answer.isEmpty && answer == expectedAnswer,
        "generated_text": report.generatedText,
        "generated_token_ids": report.generatedTokenIDs,
        "model_continuation_calls_this_call": report.modelContinuationCallCount,
      ]
    }

    var statusAfter: [String: Any] = [:]
    do {
      statusAfter = try integration.status(database: database)
    } catch {
      statusAfter = ["status_error": phaseErrorLabel(error)]
    }
    let lifecycleRecords = integration.lifecycleRecordSummary()
    func lifecycleObserved(_ operation: String, at position: Int) -> Bool {
      lifecycleRecords.contains { record in
        (record["operation"] as? String) == operation
          && (record["result_position"] as? Int) == position
      }
    }
    let createdAt0 = lifecycleObserved("created", at: 0)
    let continuedAt1 = lifecycleObserved("continued", at: 1)
    let reattachedAt1 = lifecycleObserved("reattached", at: 1)
    let databaseAfter = try fileIdentity(database)
    let stateAfter = try directoryFileIdentities(stateDirectory)
    let actions = continuation["settlement_actions"] as? [[String: Any]] ?? []
    let u1Action = actions.first { ($0["item_id"] as? String) == "TASK-U1" } ?? [:]
    let u2Action = actions.first { ($0["item_id"] as? String) == "TASK-U2" } ?? [:]
    let answerText = output["answer"] as? String ?? ""
    let outputFollowsSettlement = !answerText.isEmpty && answerText == expectedAnswer
    let terminal: String
    if admissionStatus == "REFUSED" || admissionStatus == "BINDING_MISMATCH" {
      terminal = "PHASE2_INPUT_ADMISSION_REFUSAL"
    } else if settlementFailureLabel is String {
      terminal = generationCalls == 0
        ? "PHASE2_PRE_GENERATION_FAILURE"
        : "PHASE2_SETTLEMENT_REFUSAL"
    } else if caseName == "B3b" {
      terminal = "PHASE2_OBSERVED_SUBSTITUTION"
    } else {
      terminal = "PHASE2_OBSERVED_SUCCESS"
    }
    let record: [String: Any] = [
      "schema_id": "SIMIGO-CAUSALITY-PHASE2-V2",
      "phase": "PHASE2_HANDOFF_DATA_PATH",
      "case": caseName,
      "run_label": options.runLabel,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "duration_seconds": Date().timeIntervalSince(start),
      "model": identity,
      "model_load_seconds": loadSeconds,
      "decode_parameters": [
        "max_tokens": options.maxTokens,
        "strategy": "greedy_argmax_no_sampling",
        "stop_on_eos": true,
      ],
      "u1_process": [
        "pid": u1PID ?? -1,
        "alive_at_start": u1AliveAtStart,
        "alive_at_end": u1PID.map(processIsAlive) ?? false,
      ],
      "fresh_execution": [
        "state_directory": stateDirectory.path,
        "state_directory_was_empty": stateDirectoryWasEmpty,
        "state_entries_before": stateEntriesBefore,
        "new_os_process": true,
        "process_pid": Int(ProcessInfo.processInfo.processIdentifier),
        "logical_execution_id": "PRODUCTION-REAL-PALACE",
        "es_identity_note": "new execution instance; executionID string is reused, so this is not a claim of new logical ES lineage",
        "no_durable_handle_passed": true,
        "cold_seed": coldU2Seed,
        "cold_seed_sha256": sha256Hex(Data(coldU2Seed.utf8)),
        "cold_seed_contains_expected_secret": !secret.isEmpty
          && coldU2Seed.contains(secret),
        "created_fresh_execution": continuation["created_fresh_execution"] ?? NSNull(),
        "advanced_position": continuation["advanced_position"] ?? NSNull(),
        "advanced_lifecycle": continuation["advanced_lifecycle"] ?? NSNull(),
      ],
      "database_before": databaseBefore,
      "database_after": databaseAfter,
      "state_before": stateBefore,
      "state_after": stateAfter,
      "is_status_before": statusBefore,
      "is_status_after": statusAfter,
      "harness_is_reads": [],
      "harness_read_settlement_calls": 0,
      "harness_read_item_calls": 0,
      "is_reads": [
        "resolved_by": "production-runtime-bridge:resolve-model-input",
        "declared_dependencies": admission?.declaredDependencies ?? [],
        "dependency_settlement_object_ids":
          admission?.dependencySettlementObjectIDs ?? [:],
        "u2_item_source_payload_template_sha256": admission?.templateSHA256 ?? "",
        "read_u1_item_via_item_api": false,
      ],
      "input_admission_status": admissionStatus,
      "input_admission": admission?.evidenceDictionary() ?? NSNull(),
      "input_admission_refusal": admissionRefusal,
      "production_continuation_invoked": productionContinuationInvoked,
      "generation_entered": generationCalls > 0,
      "prompt": [
        "seed_text": coldU2Seed,
        "seed_sha256": sha256Hex(Data(coldU2Seed.utf8)),
        "next_input": admission?.inputText ?? "",
        "next_input_sha256": admission?.inputSHA256 ?? "",
        "next_input_byte_length": admission?.inputByteLength ?? 0,
        "next_input_uses_settled_secret": !secret.isEmpty
          && (admission?.inputText.contains(secret) ?? false),
        "next_input_uses_settled_checksum": !checksum.isEmpty
          && (admission?.inputText.contains(checksum) ?? false),
        "next_input_contains_expected_secret": !secret.isEmpty
          && (admission?.inputText.contains(secret) ?? false),
      ],
      "continue_task_entered": continueTaskEntered,
      "settlement_failure_label": settlementFailureLabel,
      "settlement_failure_description": settlementFailureDescription,
      "generated_on_failure": [
        "text": lastGeneratedText,
        "token_ids": lastGeneratedTokenIDs,
        "parsed_answer": lastParsedAnswer,
        "model_value_failure": modelValueFailure,
        "text_sha256": sha256Hex(Data(lastGeneratedText.utf8)),
      ],
      "counters": executor.counterSnapshot,
      "es_lifecycle_records": lifecycleRecords,
      "es_lifecycle": [
        "created_at_position_0": createdAt0,
        "continued_at_position_1": continuedAt1,
        "reattached_at_position_1": reattachedAt1,
        "entry": createdAt0 ? "created@0" : "NOT_OBSERVED",
        "exit": continuedAt1 ? "continued@1" : "NOT_OBSERVED",
        "no_reattached_at_1": !reattachedAt1,
      ],
      "u1_generation_calls_during_u2_phase": 0,
      "u2_generation_calls_during_u2_phase": executor.counterSnapshot["model_continuation_calls"] ?? 0,
      "continuation": continuation,
      "u1_action": u1Action,
      "u2_action": u2Action,
      "u1_reused": (continuation["reused_item_ids"] as? [String] ?? []).contains("TASK-U1"),
      "u1_recomputed": (continuation["computed_item_ids"] as? [String] ?? []).contains("TASK-U1"),
      "u1_settlement_object_id": u1ObjectID,
      "source_settlement_object_id": sourceObjectID,
      "settled_expected_answer_sha256": sha256Hex(Data(expectedAnswer.utf8)),
      "output_follows_is_settlement": outputFollowsSettlement,
      "c4_authenticity": caseName == "B3b"
        ? "SUBSTITUTED_VALUE_IS_DIGEST_VALID_BUT_NOT_LINEAGE_AUTHENTIC"
        : "NOT_ASSESSED_IN_THIS_CONDITION",
      "output": output,
      "terminal_state": terminal,
    ]
    try writeExclusiveJSON(
      record, to: evidenceDirectory.appendingPathComponent("phase2.json"))
  } catch {
    let record: [String: Any] = [
      "schema_id": "SIMIGO-CAUSALITY-PHASE2-V1",
      "phase": "PHASE2_HANDOFF_DATA_PATH",
      "case": caseName,
      "run_label": options.runLabel,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "started_at_utc": startedAt,
      "completed_at_utc": utcNow(),
      "failure": String(describing: error),
      "terminal_state": "PHASE2_HARNESS_FAIL",
    ]
    if FileManager.default.fileExists(atPath: evidenceDirectory.path) {
      try? writeExclusiveJSON(
        record, to: evidenceDirectory.appendingPathComponent("phase2-fail.json"))
    }
    throw error
  }
}
