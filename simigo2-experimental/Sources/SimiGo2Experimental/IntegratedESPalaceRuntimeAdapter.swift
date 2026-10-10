import Foundation
import SimiGoRuntimeContract
import CryptoKit

public enum IntegratedESPalaceAdapterError: Error, Equatable, Sendable {
  case fixtureManifestDigestMismatch(expected: String, actual: String)
  case primitiveDigestMismatch(family: String, expected: String, actual: String)
  case missingPrimitive(family: String)
  case opaqueLocatorMismatch
  case invalidNextActionPointer
  case ambiguousNextActionPointer(count: Int)
  case staleMandatoryEvidence
  case provenBoundaryViolation
  case carrierReadDenied
  case reuseIdentityMismatch
}

public struct IntegratedPrimitiveItem: Codable, Equatable, Sendable {
  public let path: String
  public let registeredTrigger: String?
  public let sha256: String?
}

public struct IntegratedFixtureManifest: Codable, Equatable, Sendable {
  public let caseId: String
  public let opaqueLocator: String
  public let primitives: [String: IntegratedPrimitiveItem]

  private enum CodingKeys: String, CodingKey {
    case caseId = "case_id"
    case opaqueLocator = "opaque_locator"
    case primitives
  }
}

public struct IntegratedRuntimeInventory: Equatable, Sendable {
  public var fixtureManifest: IntegratedFixtureManifest
  public var closure: [String: AnyCodableValue]
  public var provenance: [String: AnyCodableValue]
  public var nextActions: [String: AnyCodableValue]?
  public var carrierSnapshot: [String: AnyCodableValue]
  public var invocation: [String: AnyCodableValue]
  public var approvedSchemas: [String: AnyCodableValue]
  public var evidenceDestinations: [String: AnyCodableValue]
}

public enum AnyCodableValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([AnyCodableValue])
  case dictionary([String: AnyCodableValue])
}

extension AnyCodableValue: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([AnyCodableValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: AnyCodableValue].self) {
      self = .dictionary(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
    }
  }
}

public struct IntegratedRuntimeDecision: Equatable, Sendable {
  public let decision: String
  public let continuationClass: String
  public let precedenceReason: String
  public let inputDigest: String
  public let outputDigest: String
  public let continuationIdentityDigest: String
}

public struct IntegratedCarrierPersistenceIntent: Equatable, Sendable {
  public let operation: String
  public let continuationIdentityDigest: String
  public let outputDigest: String
  public let carrierMutationAuthorized: Bool
}

public struct IntegratedRuntimeAdapterResult: Equatable, Sendable {
  public let inventory: IntegratedRuntimeInventory
  public let decision: IntegratedRuntimeDecision
  public let executionHandle: ExecutionStateHandle
  public let carrierIntent: IntegratedCarrierPersistenceIntent
}

public struct IntegratedRuntimeApplicationReceipt: Equatable, Sendable {
  public let decision: String
  public let advanced: Bool
  public let executionCreated: Bool
  public let representationBound: Bool
  public let lifecycleRecordsBefore: Int
  public let lifecycleRecordsAfter: Int
  public let positionBefore: Int64?
  public let positionAfter: Int64?
  public let handle: ExecutionStateHandle?
  public let representationPosition: ExecutionPosition?
  public let representationPrefix: [Int]?
}

public struct IntegratedRuntimeAuthority: Sendable {
  public static let boundary = "D002-PACKAGE-V1.0"
  public static let boundaryDigest = "96ba11fd029ed8efb72c440fb475ae31157c4b7a40dd594de46ac80afe2c4af6"
}

public final class IntegratedESPalaceRuntimeAdapter: @unchecked Sendable {
  private let coordinator: ExecutionContinuityCoordinator
  private let backend: MLXExecutionStateBackend

  public init(coordinator: ExecutionContinuityCoordinator, backend: MLXExecutionStateBackend) {
    self.coordinator = coordinator
    self.backend = backend
  }

  public func loadInventory(
    fixtureManifestURL: URL,
    expectedManifestSHA256: String,
    opaqueLocator: String
  ) throws -> IntegratedRuntimeInventory {
    let manifestData = try Data(contentsOf: fixtureManifestURL)
    let actualDigest = SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined()
    guard actualDigest == expectedManifestSHA256 else {
      throw IntegratedESPalaceAdapterError.fixtureManifestDigestMismatch(
        expected: expectedManifestSHA256,
        actual: actualDigest
      )
    }
    let manifest = try JSONDecoder().decode(IntegratedFixtureManifest.self, from: manifestData)
    guard manifest.opaqueLocator == opaqueLocator else {
      throw IntegratedESPalaceAdapterError.opaqueLocatorMismatch
    }

    let caseRoot = fixtureManifestURL.deletingLastPathComponent()
    func readPrimitive(_ family: String) throws -> [String: AnyCodableValue]? {
      guard let item = manifest.primitives[family] else {
        throw IntegratedESPalaceAdapterError.missingPrimitive(family: family)
      }
      guard let expectedDigest = item.sha256 else { return nil }
      let url = caseRoot.appendingPathComponent(item.path)
      let data = try Data(contentsOf: url)
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      guard digest == expectedDigest else {
        throw IntegratedESPalaceAdapterError.primitiveDigestMismatch(
          family: family,
          expected: expectedDigest,
          actual: digest
        )
      }
      let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
      guard case .dictionary(let dictionary) = decoded else {
        throw IntegratedESPalaceAdapterError.missingPrimitive(family: family)
      }
      return dictionary
    }

    guard let closure = try readPrimitive("R-I1"),
          let provenance = try readPrimitive("R-I4"),
          let carrier = try readPrimitive("R-I3"),
          let invocation = try readPrimitive("R-I6"),
          let schemas = try readPrimitive("R-I8"),
          let destinations = try readPrimitive("R-I10") else {
      throw IntegratedESPalaceAdapterError.missingPrimitive(family: "mandatory inventory")
    }
    let nextActions = try readPrimitive("R-I5")
    return IntegratedRuntimeInventory(
      fixtureManifest: manifest,
      closure: closure,
      provenance: provenance,
      nextActions: nextActions,
      carrierSnapshot: carrier,
      invocation: invocation,
      approvedSchemas: schemas,
      evidenceDestinations: destinations
    )
  }

  public func makeDecision(
    inventory: IntegratedRuntimeInventory,
    sourceRecordDigest: String
  ) throws -> IntegratedRuntimeDecision {
    if inventory.nextActions == nil {
      return try blocked(
        reason: "MANDATORY_OBJECT_UNRESOLVABLE",
        inventory: inventory,
        actionID: nil,
        targetDigest: sourceRecordDigest
      )
    }
    guard let provenanceStatus = string(inventory.provenance["status"]) else {
      return try blocked(
        reason: "MANDATORY_OBJECT_UNRESOLVABLE",
        inventory: inventory,
        actionID: nil,
        targetDigest: sourceRecordDigest
      )
    }
    guard provenanceStatus == "CURRENT" else {
      return try blocked(
        reason: "MANDATORY_EVIDENCE_SUPERSEDED",
        inventory: inventory,
        actionID: nil,
        targetDigest: sourceRecordDigest
      )
    }

    let actions = actions(inventory.nextActions)
    if actions.contains(where: { string($0["boundary"]) != IntegratedRuntimeAuthority.boundary }) {
      return try blocked(
        reason: "REGISTERED_BOUNDARY_VIOLATION_PROVEN",
        inventory: inventory,
        actionID: actions.first?["action_id"].flatMap(string),
        targetDigest: sourceRecordDigest
      )
    }
    guard actions.count == 1, let action = actions.first else {
      return try blocked(
        reason: "CONFLICTING_VALID_POINTERS",
        inventory: inventory,
        actionID: actions.first?["action_id"].flatMap(string),
        targetDigest: sourceRecordDigest
      )
    }

    let input: [String: AnyCodableValue] = [
      "closure_id": .string(string(inventory.closure["closure_id"]) ?? ""),
      "closure_revision": .string(string(inventory.closure["closure_revision"]) ?? ""),
      "recovered_context_digest": .string(sourceRecordDigest),
      "next_action_id": .string(string(action["action_id"]) ?? ""),
      "target_digest": .string(string(action["target_digest"]) ?? ""),
      "continuation_class": .string(string(action["continuation_class"]) ?? ""),
      "authorization_boundary": .string(IntegratedRuntimeAuthority.boundary),
    ]

    let decision: String
    let continuationClass = string(action["continuation_class"]) ?? ""
    let reason: String
    if continuationClass == "BLOCKED_LAWFUL_CONTINUATION" {
      decision = "BLOCK"
      reason = "REGISTERED_BLOCKING_CONDITION"
    } else if case .dictionary(let settled)? = inventory.carrierSnapshot["settled_record"],
              settled["settled"] == AnyCodableValue.bool(true) {
      guard string(settled["source_record_digest"]) == sourceRecordDigest else {
        throw IntegratedESPalaceAdapterError.reuseIdentityMismatch
      }
      decision = "REUSE"
      reason = "REUSE_PREDICATE_COMPLETE"
    } else {
      decision = "CONTINUE"
      reason = "LAWFUL_CURRENT_CONTINUATION"
    }

    let output: [String: AnyCodableValue] = [
      "decision": .string(decision),
      "continuation_class": .string(continuationClass),
      "typed_reason": .string(reason),
      "no_fallback_guess": .bool(true),
      "no_partial_continuation": .bool(true),
      "no_silent_recompute": .bool(true),
      "no_stale_success": .bool(true),
    ]
    let identity: [String: AnyCodableValue] = [
      "information_closure_identity": .string(string(inventory.closure["closure_id"]) ?? ""),
      "closure_revision": .string(string(inventory.closure["closure_revision"]) ?? ""),
      "recovered_context_digest": .string(sourceRecordDigest),
      "registered_next_action_identity": .string(string(action["action_id"]) ?? ""),
      "registered_continuation_target_digest": .string(string(action["target_digest"]) ?? ""),
      "continuation_class": .string(continuationClass),
      "governing_authorization_boundary": .string(IntegratedRuntimeAuthority.boundary),
      "es_continuation_output_digest": .string(digest(output)),
    ]
    return IntegratedRuntimeDecision(
      decision: decision,
      continuationClass: continuationClass,
      precedenceReason: reason,
      inputDigest: digest(input),
      outputDigest: digest(output),
      continuationIdentityDigest: digest(identity)
    )
  }

  public func applyToRealRuntime(
    executionID: ExecutionID,
    decision: IntegratedRuntimeDecision
  ) async throws -> IntegratedRuntimeApplicationReceipt {
    let beforeCount = coordinator.recordCount
    let existing = coordinator.handle(executionID)
    let positionBefore = existing?.position.value

    switch decision.decision {
    case "BLOCK":
      return IntegratedRuntimeApplicationReceipt(
        decision: decision.decision,
        advanced: false,
        executionCreated: false,
        representationBound: false,
        lifecycleRecordsBefore: beforeCount,
        lifecycleRecordsAfter: coordinator.recordCount,
        positionBefore: positionBefore,
        positionAfter: positionBefore,
        handle: existing,
        representationPosition: nil,
        representationPrefix: nil
      )
    case "REUSE":
      guard decision.continuationClass == "SETTLED_CONTINUATION",
            decision.precedenceReason == "REUSE_PREDICATE_COMPLETE",
            !decision.continuationIdentityDigest.isEmpty,
            !decision.outputDigest.isEmpty else {
        throw IntegratedESPalaceAdapterError.reuseIdentityMismatch
      }
      guard let live = existing else {
        throw IntegratedESPalaceAdapterError.reuseIdentityMismatch
      }
      let bound = try backend.boundPrefix(for: live)
      return IntegratedRuntimeApplicationReceipt(
        decision: decision.decision,
        advanced: false,
        executionCreated: false,
        representationBound: false,
        lifecycleRecordsBefore: beforeCount,
        lifecycleRecordsAfter: coordinator.recordCount,
        positionBefore: positionBefore,
        positionAfter: live.position.value,
        handle: live,
        representationPosition: bound.position,
        representationPrefix: bound.prefix
      )
    case "CONTINUE":
      let created = existing == nil
      let base: ExecutionStateHandle
      if let existing {
        base = existing
      } else {
        base = try await coordinator.create(
          id: executionID,
          position: ExecutionPosition(0),
          continuation: ExecutionContinuation(
            nextInput: decision.inputDigest,
            continuationID: decision.continuationIdentityDigest
          )
        )
      }
      let advanced = try await coordinator.continueExecution(
        base,
        continuation: ExecutionContinuation(
          nextInput: decision.inputDigest,
          continuationID: decision.continuationIdentityDigest
        )
      )
      let allTokens: [Int] = decision.outputDigest.compactMap { character in character.hexDigitValue }
      let tokens = Array(allTokens.prefix(16))
      try await coordinator.bindRepresentation(
        executionID: advanced.id,
        position: advanced.position,
        payload: MLXPrefixPayload(tokenPrefix: tokens)
      )
      let bound = try backend.boundPrefix(for: advanced)
      return IntegratedRuntimeApplicationReceipt(
        decision: decision.decision,
        advanced: advanced.position.value == (base.position.value + 1),
        executionCreated: created,
        representationBound: bound.position == advanced.position,
        lifecycleRecordsBefore: beforeCount,
        lifecycleRecordsAfter: coordinator.recordCount,
        positionBefore: positionBefore,
        positionAfter: advanced.position.value,
        handle: advanced,
        representationPosition: bound.position,
        representationPrefix: bound.prefix
      )
    default:
      throw IntegratedESPalaceAdapterError.invalidNextActionPointer
    }
  }

  public func carrierIntent(for decision: IntegratedRuntimeDecision) -> IntegratedCarrierPersistenceIntent {
    IntegratedCarrierPersistenceIntent(
      operation: decision.decision == "REUSE" ? "VERIFY_SETTLED_REUSE" : "APPEND_TYPED_DECISION",
      continuationIdentityDigest: decision.continuationIdentityDigest,
      outputDigest: decision.outputDigest,
      carrierMutationAuthorized: false
    )
  }

  private func blocked(
    reason: String,
    inventory: IntegratedRuntimeInventory,
    actionID: String?,
    targetDigest: String
  ) throws -> IntegratedRuntimeDecision {
    let actionID = actionID ?? string(inventory.closure["closure_id"]) ?? ""
    let input: [String: AnyCodableValue] = [
      "closure_id": .string(string(inventory.closure["closure_id"]) ?? ""),
      "closure_revision": .string(string(inventory.closure["closure_revision"]) ?? ""),
      "recovered_context_digest": .string(targetDigest),
      "next_action_id": .string(actionID),
      "target_digest": .string(targetDigest),
      "continuation_class": .string("BLOCKED_DEFECT"),
      "authorization_boundary": .string(IntegratedRuntimeAuthority.boundary),
    ]
    let output: [String: AnyCodableValue] = [
      "decision": .string("BLOCK"),
      "continuation_class": .string("BLOCKED_DEFECT"),
      "typed_reason": .string(reason),
      "no_fallback_guess": .bool(true),
      "no_partial_continuation": .bool(true),
      "no_silent_recompute": .bool(true),
      "no_stale_success": .bool(true),
    ]
    let identity: [String: AnyCodableValue] = [
      "information_closure_identity": .string(string(inventory.closure["closure_id"]) ?? ""),
      "closure_revision": .string(string(inventory.closure["closure_revision"]) ?? ""),
      "recovered_context_digest": .string(targetDigest),
      "registered_next_action_identity": .string(actionID),
      "registered_continuation_target_digest": .string(targetDigest),
      "continuation_class": .string("BLOCKED_DEFECT"),
      "governing_authorization_boundary": .string(IntegratedRuntimeAuthority.boundary),
      "es_continuation_output_digest": .string(digest(output)),
    ]
    return IntegratedRuntimeDecision(
      decision: "BLOCK",
      continuationClass: "BLOCKED_DEFECT",
      precedenceReason: reason,
      inputDigest: digest(input),
      outputDigest: digest(output),
      continuationIdentityDigest: digest(identity)
    )
  }

  private func actions(_ value: [String: AnyCodableValue]?) -> [[String: AnyCodableValue]] {
    guard case .array(let array)? = value?["actions"] else { return [] }
    return array.compactMap { item in
      if case .dictionary(let dictionary) = item { return dictionary }
      return nil
    }
  }

  private func string(_ value: AnyCodableValue?) -> String? {
    if case .string(let string)? = value { return string }
    return nil
  }

  private func digest(_ value: [String: AnyCodableValue]) -> String {
    let object = Self.jsonObject(.dictionary(value))
    let encoded = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
  }

  private static func jsonObject(_ value: AnyCodableValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let value): return value
    case .int(let value): return value
    case .double(let value): return value
    case .string(let value): return value
    case .array(let array): return array.map(jsonObject)
    case .dictionary(let dictionary):
      var result: [String: Any] = [:]
      for (key, item) in dictionary { result[key] = jsonObject(item) }
      return result
    }
  }
}
