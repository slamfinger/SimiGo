import XCTest
import Foundation
import CryptoKit

// MARK: - Audit Run Context

struct AuditRunContext {
  let runUUID: String
  let gitCommit: String
  let gitDirty: Bool
  let modelHash: String?
  let checkpointHash: String?
  let harnessSHA: String?
  let configHash: String?
  let startWallTime: String
  let startMonotonicNs: UInt64

  static func create(modelHash: String? = nil, checkpointHash: String? = nil,
                     repoPath: String? = nil, harnessSHA: String? = nil,
                     configHash: String? = nil) -> AuditRunContext {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let uuid = "audit-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
    let (commit, dirty) = AuditRunContext.gitSnapshot(repoPath: repoPath)
    let clock = ContinuousClock()
    let mono = DispatchTime.now().uptimeNanoseconds
    return AuditRunContext(
      runUUID: uuid,
      gitCommit: commit,
      gitDirty: dirty,
      modelHash: modelHash,
      checkpointHash: checkpointHash,
      harnessSHA: harnessSHA,
      configHash: configHash,
      startWallTime: ISO8601DateFormatter().string(from: Date()),
      startMonotonicNs: mono)
  }

  static func gitSnapshot(repoPath: String? = nil) -> (commit: String, dirty: Bool) {
    let prefix: String
    if let repoPath {
      let quoted = repoPath.contains(" ") ? "'\(repoPath)'" : repoPath
      prefix = "git -C \(quoted) "
    } else {
      prefix = "git "
    }
    let commit = runShell(prefix + "rev-parse HEAD") ?? "UNKNOWN"
    let status = runShell(prefix + "status --porcelain") ?? ""
    return (commit, !status.isEmpty)
  }

  static func runShell(_ command: String) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch { return nil }
  }
}

// MARK: - Audit Event

struct AuditEvent: Codable {
  let runUUID: String
  let event: String
  let wallTime: String
  let monotonicNs: UInt64
  let payload: [String: String]

  init(runUUID: String, event: String, payload: [String: String] = [:]) {
    self.runUUID = runUUID
    self.event = event
    self.wallTime = ISO8601DateFormatter().string(from: Date())
    let clock = ContinuousClock()
    self.monotonicNs = DispatchTime.now().uptimeNanoseconds
    self.payload = payload
  }
}

// MARK: - Audit Artifact Store

final class AuditArtifactStore: @unchecked Sendable {
  let runUUID: String
  let directory: URL
  private let eventsFileHandle: FileHandle
  private let lock = NSLock()
  private var monotonicBase: UInt64
  

  /// Directory: results/replication/{runUUID}/
  /// Throws if directory already exists (prevents stale artifact reuse).
  init(context: AuditRunContext, baseDirectory: URL = URL(fileURLWithPath: "results/replication", isDirectory: true)) throws {
    self.runUUID = context.runUUID
    self.directory = baseDirectory.appendingPathComponent(context.runUUID, isDirectory: true)

    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw AuditStoreError.directoryExists(directory.path)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // Write metadata.json
    let metadata: [String: Any] = [
      "runUUID": context.runUUID,
      "gitCommit": context.gitCommit,
      "gitDirty": context.gitDirty,
      "modelHash": context.modelHash ?? "N/A",
      "checkpointHash": context.checkpointHash ?? "N/A",
      "harnessSHA": context.harnessSHA ?? "N/A",
      "configHash": context.configHash ?? "N/A",
      "startWallTime": context.startWallTime,
      "startMonotonicNs": "\(context.startMonotonicNs)",
    ]
    let metaData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    try metaData.write(to: directory.appendingPathComponent("metadata.json"))

    // Open events.jsonl for appending
    let eventsPath = directory.appendingPathComponent("events.jsonl")
    FileManager.default.createFile(atPath: eventsPath.path, contents: nil)
    self.eventsFileHandle = try FileHandle(forWritingTo: eventsPath)
    self.monotonicBase = context.startMonotonicNs
  }

  enum AuditStoreError: Error, LocalizedError {
    case directoryExists(String)
    case notOpen
    var errorDescription: String? {
      switch self {
      case .directoryExists(let path): return "Audit directory already exists: \(path)"
      case .notOpen: return "Audit store not open"
      }
    }
  }

  /// Record an event with monotonic timestamp
  func record(_ event: String, payload: [String: String] = [:]) {
    lock.lock()
    defer { lock.unlock() }
    let monoNs = DispatchTime.now().uptimeNanoseconds
    let entry = AuditEvent(runUUID: runUUID, event: event, payload: payload)
    guard let data = try? JSONEncoder().encode(entry),
          let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8)
    else { return }
    eventsFileHandle.write(line)
  }

  /// Write summary.json
  func writeSummary(_ summary: [String: Any]) throws {
    lock.lock()
    defer { lock.unlock() }
    let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: directory.appendingPathComponent("summary.json"))
  }

  /// Write hashes.json
  func writeHashes(_ hashes: [String: String]) throws {
    lock.lock()
    defer { lock.unlock() }
    let data = try JSONSerialization.data(withJSONObject: hashes, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: directory.appendingPathComponent("hashes.json"))
  }

  /// Close file handle
  func finish() {
    lock.lock()
    defer { lock.unlock() }
    try? eventsFileHandle.close()
  }

  /// Read back all events (for verification)
  func readEvents() throws -> [AuditEvent] {
    let path = directory.appendingPathComponent("events.jsonl")
    let data = try Data(contentsOf: path)
    let lines = String(data: data, encoding: .utf8)?
      .split(separator: "\n")
      .compactMap { line -> AuditEvent? in
        guard let lineData = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AuditEvent.self, from: lineData)
      } ?? []
    return lines
  }

  /// Verify artifact integrity
  func verify() throws -> [String: Bool] {
    var checks: [String: Bool] = [:]
    // UUID isolation
    checks["unique_run"] = FileManager.default.fileExists(atPath: directory.path)
    // Metadata exists
    checks["metadata_exists"] = FileManager.default.fileExists(atPath: directory.appendingPathComponent("metadata.json").path)
    // Events exist
    checks["events_exists"] = FileManager.default.fileExists(atPath: directory.appendingPathComponent("events.jsonl").path)
    // Events readable
    let events = try readEvents()
    checks["events_readable"] = !events.isEmpty
    // Events have same UUID
    checks["events_same_uuid"] = events.allSatisfy { $0.runUUID == runUUID }
    // Monotonic ordering (non-decreasing)
    let timestamps = events.map { $0.monotonicNs }
    checks["monotonic_ordering"] = zip(timestamps, timestamps.dropFirst()).allSatisfy { $0 <= $1 }
    // No duplicate events (same event name + same monotonic)
    let eventKeys = events.map { "\($0.event):\($0.monotonicNs)" }
    checks["no_duplicate_events"] = Set(eventKeys).count == eventKeys.count
    // Schema valid (all events have required fields)
    checks["schema_valid"] = events.allSatisfy { !$0.event.isEmpty && !$0.wallTime.isEmpty }
    return checks
  }
}
