import Crypto
import Foundation

/// The consumer half of the E-round settlement provenance contract.
///
/// The producer (the validated settlement path in `carrier_loop.py`) signs a
/// canonical payload that binds the settlement object id, the task item, the
/// full provenance record (task object, source, dependency closure, result
/// digest, validity, event) and the signing key id. The consumer verifies that
/// detached signature against a trust anchor that is read from OUTSIDE the
/// Information Space database, then checks that the signed payload still
/// describes the exact settlement objects it is about to admit.
///
/// This verifier can never mint provenance: it holds a public key only.
public enum SettlementProvenanceError: Error, Equatable, CustomStringConvertible {
  case trustAnchorUnavailable(String)
  case trustAnchorInvalid(String)
  case signatureMissing(String)
  case signatureMalformed(String)
  case signatureKeyUntrusted(String)
  case signatureVerificationFailed(String)
  case payloadDisagrees(String)
  case bindingMismatch(String)

  /// Stable machine-readable code, used as the admission refusal stage.
  public var code: String {
    switch self {
    case .trustAnchorUnavailable: return "SETTLEMENT_TRUST_ANCHOR_UNAVAILABLE"
    case .trustAnchorInvalid: return "SETTLEMENT_TRUST_ANCHOR_INVALID"
    case .signatureMissing: return "SETTLEMENT_SIGNATURE_MISSING"
    case .signatureMalformed: return "SETTLEMENT_SIGNATURE_INVALID"
    case .signatureKeyUntrusted: return "SETTLEMENT_SIGNATURE_KEY_UNTRUSTED"
    case .signatureVerificationFailed: return "SETTLEMENT_SIGNATURE_INVALID"
    case .payloadDisagrees: return "SETTLEMENT_PROVENANCE_MISMATCH"
    case .bindingMismatch: return "SETTLEMENT_PROVENANCE_BINDING_MISMATCH"
    }
  }

  public var detail: String {
    switch self {
    case .trustAnchorUnavailable(let value),
         .trustAnchorInvalid(let value),
         .signatureMissing(let value),
         .signatureMalformed(let value),
         .signatureKeyUntrusted(let value),
         .signatureVerificationFailed(let value),
         .payloadDisagrees(let value),
         .bindingMismatch(let value):
      return value
    }
  }

  public var description: String { "\(code): \(detail)" }
}

/// One verified settlement signature, kept as machine-readable evidence.
public struct ProductionTaskSettlementSignature: Equatable, Sendable {
  public let itemID: String
  public let settlementObjectID: String
  public let keyID: String
  public let algorithm: String
  public let eventID: String
  public let eventSequence: Int
  public let previousSettlementObjectID: String?
  public let producerKind: String
  public let producerRunID: String
  public let producerExecutionID: String
  public let resultValueSHA256: String
  public let dependencyObjectIDs: [String: String]
  public let evaluatedAtUTC: String
  public let validUntilUTC: String?
  public let payloadSHA256: String

  public func evidenceDictionary() -> [String: Any] {
    var record: [String: Any] = [
      "item_id": itemID,
      "settlement_object_id": settlementObjectID,
      // An instance exists only after this settlement's detached Ed25519
      // signature verified against the deployment trust anchor, so the record
      // states the verification outcome instead of leaving it implicit.
      "verified": true,
      "key_id": keyID,
      "algorithm": algorithm,
      "event_id": eventID,
      "event_sequence": eventSequence,
      "producer_kind": producerKind,
      "producer_run_id": producerRunID,
      "producer_execution_id": producerExecutionID,
      "result_value_sha256": resultValueSHA256,
      "dependency_object_ids": dependencyObjectIDs,
      "evaluated_at_utc": evaluatedAtUTC,
      "payload_sha256": payloadSHA256,
    ]
    if let previousSettlementObjectID {
      record["previous_settlement_object_id"] = previousSettlementObjectID
    }
    if let validUntilUTC {
      record["valid_until_utc"] = validUntilUTC
    }
    return record
  }
}

/// Ed25519 trust anchor loaded from a deployment file.
public struct SettlementProvenanceTrustAnchor {
  public static let schemaID = "EINFO-SETTLEMENT-TRUST-ANCHOR-V1"
  public static let algorithm = "Ed25519"

  public let keyID: String
  public let publicKey: Curve25519.Signing.PublicKey

  public static func load(path: String) throws -> SettlementProvenanceTrustAnchor {
    guard let data = FileManager.default.contents(atPath: path) else {
      throw SettlementProvenanceError.trustAnchorUnavailable(path)
    }
    guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SettlementProvenanceError.trustAnchorInvalid("anchor is not a JSON object")
    }
    guard raw["schema_id"] as? String == Self.schemaID else {
      throw SettlementProvenanceError.trustAnchorInvalid("anchor schema is not \(Self.schemaID)")
    }
    guard raw["algorithm"] as? String == Self.algorithm else {
      throw SettlementProvenanceError.trustAnchorInvalid("anchor algorithm is not Ed25519")
    }
    guard let keyID = raw["key_id"] as? String, !keyID.isEmpty else {
      throw SettlementProvenanceError.trustAnchorInvalid("anchor has no key id")
    }
    guard let encoded = raw["public_key_base64"] as? String,
          let keyBytes = Data(base64Encoded: encoded),
          keyBytes.count == 32,
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes) else {
      throw SettlementProvenanceError.trustAnchorInvalid("anchor public key is malformed")
    }
    return SettlementProvenanceTrustAnchor(keyID: keyID, publicKey: publicKey)
  }
}

public enum SettlementProvenanceVerifier {
  public static let signatureSchemaID = "EINFO-SETTLEMENT-SIGNATURE-V1"
  public static let provenanceSchemaID = "EINFO-SETTLEMENT-PROVENANCE-V1"
  public static let settlementSchemaID = "EINFO-SETTLEMENT-V1"
  public static let settlementContract = "EINFO-SETTLEMENT-CONTRACT-V1"

  /// Verify every signed settlement behind one admitted input.
  ///
  /// `dependencies` is the bridge's resolved dependency closure (transitive),
  /// keyed by item id. `bindings` are the substitutions the input materialized
  /// from. Refusal is total: one missing, untrusted, malformed or stale
  /// signature rejects the whole admission.
  public static func verify(
    signatures: [[String: Any]],
    dependencies: [String: [String: Any]],
    declaredDependencies: [String],
    bindings: [ProductionTaskInputBinding],
    trustAnchorPath: String
  ) throws -> [ProductionTaskSettlementSignature] {
    let anchor = try SettlementProvenanceTrustAnchor.load(path: trustAnchorPath)
    guard !dependencies.isEmpty || declaredDependencies.isEmpty else {
      throw SettlementProvenanceError.signatureMissing(
        "item declares \(declaredDependencies.count) dependencies but none resolved")
    }

    var byItem: [String: [String: Any]] = [:]
    for envelope in signatures {
      guard let itemID = envelope["item_id"] as? String, !itemID.isEmpty else {
        throw SettlementProvenanceError.signatureMalformed("envelope has no item id")
      }
      guard byItem[itemID] == nil else {
        throw SettlementProvenanceError.signatureMalformed("duplicate signature for \(itemID)")
      }
      byItem[itemID] = envelope
    }
    for itemID in declaredDependencies where byItem[itemID] == nil {
      throw SettlementProvenanceError.signatureMissing("declared dependency \(itemID)")
    }
    for itemID in dependencies.keys where byItem[itemID] == nil {
      throw SettlementProvenanceError.signatureMissing("resolved dependency \(itemID)")
    }

    var verified: [ProductionTaskSettlementSignature] = []
    for itemID in dependencies.keys.sorted() {
      guard let dependency = dependencies[itemID], let envelope = byItem[itemID] else {
        throw SettlementProvenanceError.signatureMissing(itemID)
      }
      verified.append(
        try verifyOne(
          envelope: envelope, itemID: itemID, dependency: dependency,
          dependencies: dependencies, anchor: anchor))
    }

    for binding in bindings {
      guard let dependency = dependencies[binding.itemID] else {
        throw SettlementProvenanceError.bindingMismatch(
          "binding \(binding.placeholder) names unverified item \(binding.itemID)")
      }
      guard let objectID = dependency["settlement_object_id"] as? String,
            objectID == binding.settlementObjectID else {
        throw SettlementProvenanceError.bindingMismatch(
          "binding \(binding.placeholder) settlement object disagrees")
      }
      guard let resultSHA = dependency["result_value_sha256"] as? String,
            resultSHA == binding.resultValueSHA256 else {
        throw SettlementProvenanceError.bindingMismatch(
          "binding \(binding.placeholder) result digest disagrees")
      }
    }
    return verified
  }

  private static func verifyOne(
    envelope: [String: Any],
    itemID: String,
    dependency: [String: Any],
    dependencies: [String: [String: Any]],
    anchor: SettlementProvenanceTrustAnchor
  ) throws -> ProductionTaskSettlementSignature {
    guard envelope["schema_id"] as? String == signatureSchemaID else {
      throw SettlementProvenanceError.signatureMalformed("\(itemID): signature schema")
    }
    guard envelope["algorithm"] as? String == SettlementProvenanceTrustAnchor.algorithm else {
      throw SettlementProvenanceError.signatureMalformed("\(itemID): signature algorithm")
    }
    guard let keyID = envelope["key_id"] as? String, keyID == anchor.keyID else {
      throw SettlementProvenanceError.signatureKeyUntrusted("\(itemID): key id")
    }
    guard let objectID = envelope["settlement_object_id"] as? String,
          let dependencyObjectID = dependency["settlement_object_id"] as? String,
          objectID == dependencyObjectID else {
      throw SettlementProvenanceError.payloadDisagrees(
        "\(itemID): signed object id does not name the admitted settlement object")
    }
    guard envelope["item_id"] as? String == itemID else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): signed item id")
    }
    guard let payload = envelope["payload"] as? [String: Any] else {
      throw SettlementProvenanceError.signatureMalformed("\(itemID): payload")
    }
    guard let payloadBase64 = envelope["payload_canonical_base64"] as? String,
          let payloadBytes = Data(base64Encoded: payloadBase64) else {
      throw SettlementProvenanceError.signatureMalformed("\(itemID): canonical payload")
    }
    guard let decoded = try? JSONSerialization.jsonObject(with: payloadBytes),
          let decodedObject = decoded as? [String: Any],
          (decodedObject as NSDictionary).isEqual(payload as NSDictionary) else {
      throw SettlementProvenanceError.signatureMalformed(
        "\(itemID): canonical bytes do not encode the presented payload")
    }
    guard let signatureBase64 = envelope["signature_base64"] as? String,
          let signature = Data(base64Encoded: signatureBase64) else {
      throw SettlementProvenanceError.signatureMalformed("\(itemID): signature bytes")
    }
    guard anchor.publicKey.isValidSignature(signature, for: payloadBytes) else {
      throw SettlementProvenanceError.signatureVerificationFailed(
        "\(itemID): Ed25519 verification failed")
    }

    guard payload["schema_id"] as? String == provenanceSchemaID,
          payload["algorithm"] as? String == SettlementProvenanceTrustAnchor.algorithm,
          payload["key_id"] as? String == keyID else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): payload identity")
    }
    guard payload["settlement_object_id"] as? String == objectID,
          payload["settlement_schema_id"] as? String == settlementSchemaID,
          payload["settlement_contract"] as? String == settlementContract,
          payload["item_id"] as? String == itemID else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): payload settlement binding")
    }
    guard let provenance = payload["provenance"] as? [String: Any],
          provenance["schema_id"] as? String == provenanceSchemaID else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): provenance record")
    }

    // The signed task identity must still be the item the input names.
    guard let task = provenance["task"] as? [String: Any],
          task["item_id"] as? String == itemID else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): task identity")
    }
    // The signed result digest must be the digest the bridge admitted.
    guard let signedResultSHA = provenance["result_value_sha256"] as? String,
          signedResultSHA == dependency["result_value_sha256"] as? String else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): result digest")
    }
    // The signed source identity must still match the admitted source version.
    guard let source = provenance["source"] as? [String: Any],
          source["version"] as? String == dependency["source_version"] as? String else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): source version")
    }
    // The signed dependency closure must be exactly the closure the bridge used.
    guard let signedDependencies = provenance["dependencies"] as? [String: Any],
          let admittedDependencies = dependency["dependency_object_ids"] as? [String: String],
          Set(signedDependencies.keys) == Set(admittedDependencies.keys) else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): dependency closure")
    }
    var signedDependencyObjects: [String: String] = [:]
    for (dependencyID, value) in signedDependencies {
      guard let record = value as? [String: Any],
            let signedObjectID = record["object_id"] as? String,
            signedObjectID == admittedDependencies[dependencyID] else {
        throw SettlementProvenanceError.payloadDisagrees(
          "\(itemID): dependency \(dependencyID) object")
      }
      // A transitive dependency that the consumer also admits must agree on
      // its result digest; a dependency outside the closure is not admitted.
      if let admitted = dependencies[dependencyID] {
        guard record["result_value_sha256"] as? String
          == admitted["result_value_sha256"] as? String else {
          throw SettlementProvenanceError.payloadDisagrees(
            "\(itemID): dependency \(dependencyID) result digest")
        }
      }
      signedDependencyObjects[dependencyID] = signedObjectID
    }
    // Validity basis signed by the producer must be the basis admitted now.
    guard let validity = provenance["validity"] as? [String: Any],
          validity["evaluated_at_utc"] as? String
            == dependency["evaluated_at_utc"] as? String,
          validity["valid_until_utc"] as? String
            == dependency["valid_until_utc"] as? String else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): validity basis")
    }
    guard let event = provenance["event"] as? [String: Any],
          let eventID = event["settlement_event_id"] as? String, !eventID.isEmpty,
          let sequence = event["sequence"] as? Int, sequence >= 1 else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): settlement event")
    }
    guard let producer = provenance["producer"] as? [String: Any],
          let producerKind = producer["kind"] as? String, !producerKind.isEmpty,
          let producerRunID = producer["run_id"] as? String, !producerRunID.isEmpty,
          let producerExecutionID = producer["execution_id"] as? String,
          !producerExecutionID.isEmpty else {
      throw SettlementProvenanceError.payloadDisagrees("\(itemID): producer identity")
    }

    return ProductionTaskSettlementSignature(
      itemID: itemID,
      settlementObjectID: objectID,
      keyID: keyID,
      algorithm: SettlementProvenanceTrustAnchor.algorithm,
      eventID: eventID,
      eventSequence: sequence,
      previousSettlementObjectID: event["previous_settlement_object_id"] as? String,
      producerKind: producerKind,
      producerRunID: producerRunID,
      producerExecutionID: producerExecutionID,
      resultValueSHA256: signedResultSHA,
      dependencyObjectIDs: signedDependencyObjects,
      evaluatedAtUTC: validity["evaluated_at_utc"] as? String ?? "",
      validUntilUTC: validity["valid_until_utc"] as? String,
      payloadSHA256: SHA256Hex.string(payloadBytes)
    )
  }
}

enum SHA256Hex {
  static func string(_ data: Data) -> String {
    var hasher = SHA256()
    hasher.update(data: data)
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

/// The producer identity a model task binds into its settlement declaration.
/// The producer uses it to describe HOW the result came to exist; the consumer
/// never accepts these claims without the detached signature over them.
public struct ProductionTaskProvenance: Equatable, Sendable {
  public let runID: String
  public let executionID: String
  public let buildSHA256: String
  public let modelSnapshotRevision: String
  public let weightsManifestSHA256: String
  public let processID: String

  public init(
    runID: String,
    executionID: String = UUID().uuidString.lowercased(),
    buildSHA256: String,
    modelSnapshotRevision: String,
    weightsManifestSHA256: String,
    processID: String = String(ProcessInfo.processInfo.processIdentifier)
  ) {
    self.runID = runID
    self.executionID = executionID
    self.buildSHA256 = buildSHA256
    self.modelSnapshotRevision = modelSnapshotRevision
    self.weightsManifestSHA256 = weightsManifestSHA256
    self.processID = processID
  }

  /// Identity of the code that is about to sign: the running executable plus
  /// the bridge and provenance module it drives. This is recorded, not trusted:
  /// the signature proves which key signed, not that this build is honest.
  public static func buildIdentity(runtimeRoot: URL?) -> String {
    var lines: [String] = []
    var paths = [URL(fileURLWithPath: CommandLine.arguments.first ?? "")]
    if let runtimeRoot {
      paths.append(runtimeRoot.appendingPathComponent("production_runtime_bridge.py"))
      paths.append(runtimeRoot.appendingPathComponent("settlement_provenance.py"))
    }
    for path in paths {
      guard let data = FileManager.default.contents(atPath: path.standardizedFileURL.path) else {
        continue
      }
      lines.append("\(path.lastPathComponent):\(SHA256Hex.string(data))")
    }
    guard !lines.isEmpty else { return "unavailable" }
    return SHA256Hex.string(Data(lines.joined(separator: "\n").utf8))
  }

  /// The producer attestation handed to the signing settlement path.
  /// `generated_token_ids_sha256` is over the canonical JSON array, matching
  /// the Python `digest(value)` the bridge recomputes.
  public func override(generatedTokenIDs: [Int]) -> [String: Any] {
    let tokenJSON = "[" + generatedTokenIDs.map(String.init).joined(separator: ",") + "]"
    return [
      "producer": [
        "kind": "model_task",
        "run_id": runID,
        "execution_id": executionID,
        "process_id": processID,
        "build_sha256": buildSHA256,
      ],
      "model": [
        "snapshot_revision": modelSnapshotRevision,
        "weights_manifest_sha256": weightsManifestSHA256,
      ],
      "output": [
        "generated_token_ids_sha256": SHA256Hex.string(Data(tokenJSON.utf8)),
        "generated_token_count": generatedTokenIDs.count,
      ],
    ]
  }
}
