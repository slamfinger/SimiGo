import CryptoKit
import Foundation

// DETACHED CONTINUATION DRIVER
//
// Native orchestration of the two-process handoff:
//
//   U1 process (producer): real model computes the item, settles its result
//   into the Information Space and exits. This driver WAITS for that exit.
//
//   U2 process (consumer): a NEW OS process with a NEW logical execution id
//   and an EMPTY state directory. It runs the ordinary production
//   `continueTask`, which resolves and admits the U1 settlement from IS itself.
//
// The driver never loads the model, never reads a settlement or task item, and
// never builds a model input. It only owns process boundaries, execution-state
// directory identity, timing and evidence assembly. Python is not on this path.

struct DriverError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

struct Options {
  let binary: URL
  let labRoot: URL
  let modelDir: URL
  let database: URL
  let worldDir: URL
  let runID: String
  let evaluatedAtU1: String
  let evaluatedAtU2: String
  let u1Item: String
  let u1Demand: String
  let u1Advancement: String
  let u2Item: String
  let u2Demand: String
  let u2Advancement: String
  let u1ExecutionID: String
  let u2ExecutionID: String
  let u1Out: URL
  let u2Out: URL
  let out: URL
  let maxTokens: Int

  init(_ arguments: [String]) throws {
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      let key = arguments[index]
      guard key.hasPrefix("--"), index + 1 < arguments.count else {
        throw DriverError("usage: SimiGoDetachedDriver --binary ... --out ...")
      }
      values[String(key.dropFirst(2))] = arguments[index + 1]
      index += 2
    }
    func required(_ name: String) throws -> String {
      guard let value = values[name], !value.isEmpty else {
        throw DriverError("missing --\(name)")
      }
      return value
    }
    binary = URL(fileURLWithPath: try required("binary"))
    labRoot = URL(fileURLWithPath: try required("lab-root"), isDirectory: true)
    modelDir = URL(fileURLWithPath: try required("model-dir"), isDirectory: true)
    database = URL(fileURLWithPath: try required("database"))
    worldDir = URL(fileURLWithPath: try required("world-dir"), isDirectory: true)
    runID = try required("run-id")
    evaluatedAtU1 = try required("evaluated-at-u1")
    evaluatedAtU2 = try required("evaluated-at-u2")
    u1Item = try required("u1-item")
    u1Demand = try required("u1-demand")
    u1Advancement = try required("u1-advancement")
    u2Item = try required("u2-item")
    u2Demand = try required("u2-demand")
    u2Advancement = try required("u2-advancement")
    u1ExecutionID = try required("u1-execution-id")
    u2ExecutionID = try required("u2-execution-id")
    u1Out = URL(fileURLWithPath: try required("u1-out"))
    u2Out = URL(fileURLWithPath: try required("u2-out"))
    out = URL(fileURLWithPath: try required("out"))
    maxTokens = Int(values["max-tokens"] ?? "24") ?? 24
  }
}

func utcNow() -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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

/// Recursive file manifest of a directory, used to prove the consumer state
/// directory was empty before the consumer process started.
func directoryManifest(_ directory: URL) throws -> [String: String] {
  guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
  guard let enumerator = FileManager.default.enumerator(
    at: directory,
    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else {
    return [:]
  }
  let base = directory.standardizedFileURL.path
  var manifest: [String: String] = [:]
  for case let url as URL in enumerator {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
    if values.isDirectory == true { continue }
    guard values.isRegularFile == true else { continue }
    let path = url.standardizedFileURL.path
    let relative = path.hasPrefix(base + "/")
      ? String(path.dropFirst(base.count + 1)) : path
    manifest[relative] = try sha256File(url)
  }
  return manifest
}

func readJSON(_ url: URL) -> [String: Any] {
  guard let data = try? Data(contentsOf: url),
        let object = try? JSONSerialization.jsonObject(with: data),
        let dictionary = object as? [String: Any] else {
    return [:]
  }
  return dictionary
}

func writeJSON(_ value: [String: Any], to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let data = try JSONSerialization.data(
    withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
  try data.write(to: url, options: .atomic)
}

struct ChildOutcome {
  var pid: Int
  var startedAtUTC: String
  var exitedAtUTC: String
  var exitCode: Int32
  var timedOut: Bool
  var stdoutPath: String
  var stderrPath: String
  var evidence: [String: Any]
}

func runChild(
  binary: URL,
  arguments: [String],
  environment: [String: String],
  logDirectory: URL,
  name: String,
  timeoutSeconds: Double
) throws -> ChildOutcome {
  try FileManager.default.createDirectory(
    at: logDirectory, withIntermediateDirectories: true)
  let stdoutURL = logDirectory.appendingPathComponent("\(name).stdout.log")
  let stderrURL = logDirectory.appendingPathComponent("\(name).stderr.log")
  FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
  FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
  let stdout = try FileHandle(forWritingTo: stdoutURL)
  let stderr = try FileHandle(forWritingTo: stderrURL)

  let process = Process()
  process.executableURL = binary
  process.arguments = arguments
  process.environment = environment
  process.standardOutput = stdout
  process.standardError = stderr
  let startedAt = utcNow()
  try process.run()
  let pid = Int(process.processIdentifier)

  let deadline = Date().addingTimeInterval(timeoutSeconds)
  var timedOut = false
  while process.isRunning {
    if Date() > deadline {
      timedOut = true
      process.terminate()
      break
    }
    Thread.sleep(forTimeInterval: 0.1)
  }
  process.waitUntilExit()
  try? stdout.close()
  try? stderr.close()
  return ChildOutcome(
    pid: pid,
    startedAtUTC: startedAt,
    exitedAtUTC: utcNow(),
    exitCode: process.terminationStatus,
    timedOut: timedOut,
    stdoutPath: stdoutURL.path,
    stderrPath: stderrURL.path,
    evidence: [:])
}

/// One field of the settlement action record the producer wrote for `itemID`.
func actionField(_ evidence: [String: Any], _ itemID: String,
                 _ key: String) -> Any? {
  guard let settlement = evidence["settlement"] as? [String: Any],
        let actions = settlement["actions"] as? [[String: Any]] else { return nil }
  guard let action = actions.first(where: { ($0["item_id"] as? String) == itemID }) else {
    return nil
  }
  return action[key]
}

/// One field of the signature record the consumer produced while admitting
/// `itemID`. Absent when the consumer never reached verification.
func signatureField(_ evidence: [String: Any], _ itemID: String,
                    _ key: String) -> Any? {
  guard let admission = evidence["input_admission"] as? [String: Any],
        let signatures = admission["settlement_signatures"] as? [[String: Any]] else {
    return nil
  }
  guard let record = signatures.first(where: { ($0["item_id"] as? String) == itemID }) else {
    return nil
  }
  return record[key]
}

func run(_ arguments: [String]) throws {
  let fileManager = FileManager.default
  let options = try Options(arguments)
  try fileManager.createDirectory(at: options.worldDir, withIntermediateDirectories: true)

  let u1StateDir = options.worldDir.appendingPathComponent("u1-state", isDirectory: true)
  let u2StateDir = options.worldDir.appendingPathComponent("u2-state", isDirectory: true)
  let logDir = options.worldDir.appendingPathComponent("process-logs", isDirectory: true)

  // A consumer state directory must start EMPTY. If either directory already
  // exists with content the run refuses instead of deleting or reusing state.
  for directory in [u1StateDir, u2StateDir] {
    if fileManager.fileExists(atPath: directory.path) {
      let manifest = try directoryManifest(directory)
      guard manifest.isEmpty else {
        throw DriverError(
          "state directory \(directory.path) is not empty; refusing to reuse state")
      }
    }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  let u1StateBefore = try directoryManifest(u1StateDir)
  let u2StateBefore = try directoryManifest(u2StateDir)
  guard u1StateBefore.isEmpty, u2StateBefore.isEmpty else {
    throw DriverError("fresh state directories are not empty before U1 start")
  }

  let inherited = ProcessInfo.processInfo.environment
  var producerEnvironment = inherited
  producerEnvironment["SIMIGO_SETTLEMENT_PROVENANCE"] = "required"
  var consumerEnvironment = inherited
  // The consumer admits under `verify`: every settlement it reads as a
  // dependency must verify against the deployment trust anchor, and the
  // bridge refuses to admit when it does not. It still holds the signing
  // material because the same process is the PRODUCER of its own new
  // settlement for U2 - it may mint only that settlement. Re-minting a
  // dependency is not possible through this entry: dependencies are read as
  // verified objects, never rewritten. Forging a dependency is what the
  // byte-tamper control measures against the anchor, not against key access.
  consumerEnvironment["SIMIGO_SETTLEMENT_PROVENANCE"] = "verify"

  let startedAt = utcNow()

  var u1 = try runChild(
    binary: options.binary,
    arguments: [
      "--database", options.database.path,
      "--model-dir", options.modelDir.path,
      "--lab-root", options.labRoot.path,
      "--state-dir", u1StateDir.path,
      "--out", options.u1Out.path,
      "--item", options.u1Item,
      "--demand", options.u1Demand,
      "--advancement", options.u1Advancement,
      "--evaluated-at", options.evaluatedAtU1,
      "--run-id", "\(options.runID)-u1",
      "--execution-id", options.u1ExecutionID,
      "--max-tokens", String(options.maxTokens),
    ],
    environment: producerEnvironment,
    logDirectory: logDir,
    name: "u1",
    timeoutSeconds: 900)
  u1.evidence = readJSON(options.u1Out)
  let u1StateAfter = try directoryManifest(u1StateDir)

  var u2: ChildOutcome?
  var u2StateAfter: [String: String] = [:]
  var u2EvidenceBeforeStart: [String: Any] = [:]
  if u1.exitCode == 0 && !u1.timedOut {
    // The producer process has exited and been reaped by waitUntilExit().
    // Only now is the consumer allowed to start, with its own empty state.
    u2EvidenceBeforeStart = [
      "u1_pid": u1.pid,
      "u1_exited_at_utc": u1.exitedAtUTC,
      "u1_exit_code": Int(u1.exitCode),
      "u2_state_manifest_before": u2StateBefore,
      "u2_state_empty_before_start": u2StateBefore.isEmpty,
    ]
    var outcome = try runChild(
      binary: options.binary,
      arguments: [
        "--database", options.database.path,
        "--model-dir", options.modelDir.path,
        "--lab-root", options.labRoot.path,
        "--state-dir", u2StateDir.path,
        "--out", options.u2Out.path,
        "--item", options.u2Item,
        "--demand", options.u2Demand,
        "--advancement", options.u2Advancement,
        "--evaluated-at", options.evaluatedAtU2,
        "--run-id", "\(options.runID)-u2",
        "--execution-id", options.u2ExecutionID,
        "--max-tokens", String(options.maxTokens),
      ],
      environment: consumerEnvironment,
      logDirectory: logDir,
      name: "u2",
      timeoutSeconds: 900)
    outcome.evidence = readJSON(options.u2Out)
    u2 = outcome
    u2StateAfter = try directoryManifest(u2StateDir)
  }

  let u1Execution = (u1.evidence["execution_state"] as? [String: Any]) ?? [:]
  let u2Execution = (u2?.evidence["execution_state"] as? [String: Any]) ?? [:]
  let u1Settlement = (u1.evidence["settlement"] as? [String: Any]) ?? [:]
  let u2Settlement = (u2?.evidence["settlement"] as? [String: Any]) ?? [:]
  let u1Counters = (u1.evidence["counters"] as? [String: Any]) ?? [:]
  let u2Counters = (u2?.evidence["counters"] as? [String: Any]) ?? [:]
  let u2Evidence = u2?.evidence ?? [String: Any]()

  // The object the consumer verified must be the very object the producer
  // settled: no re-minted copy of the dependency is admitted.
  let u1DependencyObject = (actionField(u1.evidence, options.u1Item,
                                        "settlement_object_id") as? String) ?? ""
  let u1VerifiedObject = (signatureField(u2Evidence, options.u1Item,
                                         "settlement_object_id") as? String) ?? ""
  let consumerVerifiedU1Signature = (signatureField(u2Evidence, options.u1Item,
                                                    "verified") as? Bool) ?? false

  let checks: [String: Bool] = [
    "producer_exited_before_consumer_start":
      u2 != nil && u1.exitCode == 0 && !u1.timedOut,
    "distinct_processes": u2 != nil && u1.pid != (u2?.pid ?? u1.pid),
    "distinct_execution_state_ids":
      (u1Execution["execution_id"] as? String) != nil
      && (u2Execution["execution_id"] as? String) != nil
      && (u1Execution["execution_id"] as? String)
        != (u2Execution["execution_id"] as? String),
    "consumer_state_empty_before_start": u2EvidenceBeforeStart[
      "u2_state_empty_before_start"] as? Bool ?? false,
    "consumer_created_new_state": u2Execution["created"] as? Bool ?? false,
    "consumer_started_at_position_zero":
      ((u2Execution["advanced_position"] as? NSNumber)?.int64Value) == 1
      && (u2Execution["created"] as? Bool ?? false),
    "producer_generated_once":
      ((u1Counters["model_continuation_calls"] as? NSNumber)?.intValue) == 1,
    "consumer_generated_once":
      ((u2Counters["model_continuation_calls"] as? NSNumber)?.intValue) == 1,
    "consumer_reused_u1": (u2Settlement["reused_item_ids"] as? [String] ?? [])
      .contains(options.u1Item),
    "consumer_did_not_recompute_u1": !(u2Settlement["computed_item_ids"] as? [String] ?? [])
      .contains(options.u1Item),
    "consumer_settled": !u2Settlement.isEmpty,
    "producer_settled": !u1Settlement.isEmpty,
    "consumer_verifies_u1_signature": consumerVerifiedU1Signature,
    "consumer_did_not_remint_u1_object":
      !u1DependencyObject.isEmpty && u1VerifiedObject == u1DependencyObject,
  ]

  let record: [String: Any] = [
    "schema_id": "SIMIGO-DETACHED-CONTINUATION-DRIVER-V1",
    "run_id": options.runID,
    "database": options.database.path,
    "world_dir": options.worldDir.path,
    "driver_pid": Int(ProcessInfo.processInfo.processIdentifier),
    "started_at_utc": startedAt,
    "completed_at_utc": utcNow(),
    "producer": [
      "pid": u1.pid,
      "started_at_utc": u1.startedAtUTC,
      "exited_at_utc": u1.exitedAtUTC,
      "exit_code": Int(u1.exitCode),
      "timed_out": u1.timedOut,
      "execution_id": options.u1ExecutionID,
      "state_directory": u1StateDir.path,
      "state_manifest_before": u1StateBefore,
      "state_manifest_after": u1StateAfter,
      "stdout": u1.stdoutPath,
      "stderr": u1.stderrPath,
      "evidence_path": options.u1Out.path,
      "counters": u1Counters,
      "settlement": u1Settlement,
      "execution_state": u1Execution,
    ],
    "consumer": [
      "pid": u2.map { $0.pid } ?? NSNull(),
      "started_at_utc": u2?.startedAtUTC ?? NSNull(),
      "exited_at_utc": u2?.exitedAtUTC ?? NSNull(),
      "exit_code": u2.map { Int($0.exitCode) } ?? NSNull(),
      "timed_out": u2.map { $0.timedOut } ?? NSNull(),
      "execution_id": options.u2ExecutionID,
      "state_directory": u2StateDir.path,
      "state_manifest_before": u2StateBefore,
      "state_manifest_after": u2StateAfter,
      "stdout": u2?.stdoutPath ?? NSNull(),
      "stderr": u2?.stderrPath ?? NSNull(),
      "evidence_path": options.u2Out.path,
      "counters": u2Counters,
      "settlement": u2Settlement,
      "execution_state": u2Execution,
      "evidence_before_start": u2EvidenceBeforeStart,
    ],
    "u1_settlement_object_id_from_producer": u1DependencyObject,
    "u1_settlement_object_id_verified_by_consumer": u1VerifiedObject,
    "checks": checks,
    "verdict": checks.values.allSatisfy { $0 } ? "OBSERVED" : "INCOMPLETE",
  ]
  try writeJSON(record, to: options.out)
  print(try String(
    data: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
    encoding: .utf8) ?? "{}")
  if u1.exitCode != 0 { exit(1) }
  if let u2, u2.exitCode != 0 { exit(1) }
}

@main
struct SimiGoDetachedDriver {
  static func main() {
    do {
      try run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      exit(1)
    }
  }
}
