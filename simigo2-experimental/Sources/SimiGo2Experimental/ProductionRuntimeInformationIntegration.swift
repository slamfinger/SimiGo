import Foundation
import SimiGoRuntimeContract
import CryptoKit

public enum ProductionRuntimeInformationError: Error, Equatable, Sendable {
  case bridgeFailed(command: String, exitCode: Int32, message: String)
  case invalidBridgeResponse(command: String)
  case blockedInformationDemand(command: String, state: String)
  case invalidPersistedExecutionState
}

public struct ProductionRuntimeBridgeReport: Equatable, Sendable {
  public let command: String
  public let advanced: Bool
  public let state: String
  public let computedItemIDs: [String]
  public let reusedItemIDs: [String]
  public let resultDigest: String
}

public struct SerializedProductionExecutionState: Codable, Equatable, Sendable {
  public let id: String
  public let lineageRoot: String
  public let lineageParent: String?
  public let position: Int64
  public let nextInput: String
  public let continuationID: String
  public let lifecycle: String

  public init(handle: ExecutionStateHandle) {
    id = handle.id.rawValue
    lineageRoot = handle.lineage.root.rawValue
    lineageParent = handle.lineage.parent?.rawValue
    position = handle.position.value
    nextInput = handle.continuation.nextInput
    continuationID = handle.continuation.continuationID
    lifecycle = handle.lifecycle.rawValue
  }

  public var handle: ExecutionStateHandle {
    ExecutionStateHandle(
      id: ExecutionID(id),
      lineage: ExecutionLineage(
        root: ExecutionID(lineageRoot),
        parent: lineageParent.map(ExecutionID.init)
      ),
      position: ExecutionPosition(position),
      continuation: ExecutionContinuation(
        nextInput: nextInput,
        continuationID: continuationID
      ),
      lifecycle: ExecutionBranchLifecycle(rawValue: lifecycle) ?? .active
    )
  }
}

public final class ProductionRuntimeInformationIntegration: @unchecked Sendable {
  public static let continuationPoint = "bounded-production-runtime-integration"
  public static let executionID = ExecutionID("PRODUCTION-REAL-PALACE")

  private let labRoot: URL
  private let backend = MLXExecutionStateBackend()
  private lazy var runtime = ExecutionContinuityCoordinator(backend: backend)

  public init(labRoot: URL? = nil) {
    if let labRoot {
      self.labRoot = labRoot.standardizedFileURL
    } else {
      // Sources/SimiGo2Experimental/File.swift -> Lab root.
      self.labRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    }
  }

  private var bridgeURL: URL {
    labRoot.appendingPathComponent("execution-information-loop/production_runtime_bridge.py")
  }
  private var pythonURL: URL {
    labRoot.appendingPathComponent(".build/mp-venv312/bin/python")
  }

  private func runBridge(_ command: String, arguments: [String]) throws -> [String: Any] {
    let pythonExecutable = FileManager.default.fileExists(atPath: pythonURL.path)
      ? pythonURL
      : URL(fileURLWithPath: "/usr/bin/env")
    let processArguments = pythonExecutable.lastPathComponent == "python"
      ? [bridgeURL.path, command] + arguments
      : [bridgeURL.path, command] + arguments

    let process = Process()
    process.executableURL = pythonExecutable
    process.arguments = processArguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard let decoded = try JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
      throw ProductionRuntimeInformationError.invalidBridgeResponse(command: command)
    }
    guard process.terminationStatus == 0, decoded["ok"] as? Bool == true else {
      let message = decoded["error"] as? String ?? String(decoding: error.fileHandleForReading.availableData, as: UTF8.self)
      throw ProductionRuntimeInformationError.bridgeFailed(
        command: command,
        exitCode: process.terminationStatus,
        message: message
      )
    }
    return decoded
  }

  public func initialize(
    database: URL,
    validUntil: String
  ) throws {
    try FileManager.default.createDirectory(
      at: database.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    _ = try runBridge("initialize", arguments: [
      "--database", database.path,
      "--valid-until", validUntil,
    ])
  }

  public func status(database: URL) throws -> [String: Any] {
    try runBridge("status", arguments: ["--database", database.path])
  }

  public func invalidate(
    database: URL,
    itemID: String,
    reason: String
  ) throws {
    _ = try runBridge("invalidate", arguments: [
      "--database", database.path,
      "--item-id", itemID,
      "--reason", reason,
    ])
  }

  public func applyIsolatedSourceRevision(
    database: URL,
    itemID: String,
    version: String
  ) throws {
    _ = try runBridge("source-change", arguments: [
      "--database", database.path,
      "--item-id", itemID,
      "--version", version,
    ])
  }

  @discardableResult
  public func continueWithRealInformation(
    database: URL,
    handle: ExecutionStateHandle?,
    advancementID: String,
    evaluatedAtUTC: String
  ) async throws -> (handle: ExecutionStateHandle, report: ProductionRuntimeBridgeReport) {
    let current: ExecutionStateHandle
    if let handle {
      if runtime.handle(handle.id) != nil {
        current = try await runtime.reattach(handle)
      } else {
        current = try await runtime.attach(handle)
      }
    } else {
      current = try await runtime.create(
        id: Self.executionID,
        position: ExecutionPosition(0),
        continuation: ExecutionContinuation(
          nextInput: "\(Self.continuationPoint)-initial",
          continuationID: "\(Self.continuationPoint)-initial-cont"
        )
      )
    }

    let response = try runBridge("execute", arguments: [
      "--database", database.path,
      "--advancement", advancementID,
      "--evaluated-at", evaluatedAtUTC,
    ])
    guard let result = response["result"] as? [String: Any] else {
      throw ProductionRuntimeInformationError.invalidBridgeResponse(command: "execute")
    }
    let state = result["state"] as? String ?? "UNKNOWN"
    guard result["advanced"] as? Bool == true, state == "ADVANCED" else {
      throw ProductionRuntimeInformationError.blockedInformationDemand(
        command: advancementID,
        state: state
      )
    }

    let computed = result["computed_item_ids"] as? [String] ?? []
    let reused = result["reused_item_ids"] as? [String] ?? []
    let resultPayload = result["result"] as? [String: Any] ?? [:]
    let resultData = try JSONSerialization.data(
      withJSONObject: resultPayload,
      options: [.sortedKeys]
    )
    let digest = SHA256.hash(data: resultData)
    let representationTokens = digest.prefix(16).map { Int($0) }

    let advanced = try await runtime.continueExecution(
      current,
      continuation: ExecutionContinuation(
        nextInput: "\(Self.continuationPoint):\(advancementID)",
        continuationID: "\(Self.continuationPoint):\(advancementID):cont"
      )
    )
    try await runtime.bindRepresentation(
      executionID: advanced.id,
      position: advanced.position,
      payload: MLXPrefixPayload(tokenPrefix: representationTokens)
    )
    _ = try backend.boundPrefix(for: advanced)

    return (
      advanced,
      ProductionRuntimeBridgeReport(
        command: advancementID,
        advanced: true,
        state: state,
        computedItemIDs: computed,
        reusedItemIDs: reused,
        resultDigest: digest.map { String(format: "%02x", $0) }.joined()
      )
    )
  }
}
