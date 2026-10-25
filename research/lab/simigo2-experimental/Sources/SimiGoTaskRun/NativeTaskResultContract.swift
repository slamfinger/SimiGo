import Crypto
import Foundation
import SimiGo2Experimental

// NATIVE PRODUCER RESULT-CONTRACT DISPATCH
//
// The ordinary task entry settles a model result ONLY after the NATIVE
// `simigo.result-contract/v1` engine has validated the model's own generated
// text against the item's OWN declaration. Two properties are structural here,
// not conventional:
//
//   1. Nothing in this file or in the engine selects a rule by task name. The
//      inputs are the item's declared contract, the produced text and the
//      values the Information Space admission verified. A task id minted at run
//      time validates exactly like a frozen one, and an item that declares no
//      contract is refused instead of being matched to another task's rules.
//
//   2. The call site is `continueTask`'s `modelValue` closure, which runs
//      BEFORE the result is written to the settlement bridge and before any
//      signature exists. A refusal here therefore creates no settlement object
//      and no signature envelope; it is not a post-hoc complaint.
//
// `verifiedBindings` are projected from the signature-checked admission only:
// each one names the settled object and the value digest it came from, so a
// binding used by the gate is auditable back to an Information Space object
// rather than to a harness-supplied string.

/// One binding value the native gate was allowed to use, with the admitted
/// settled identity it came from.
struct VerifiedContractBinding {
  let name: String
  let value: NativeContractValue
  let source: String
  let placeholder: String
  let itemID: String
  let resultField: String
  let settlementObjectID: String
  let valueSHA256: String
  let resultValueSHA256: String

  func evidence() -> [String: Any] {
    [
      "name": name,
      "value": value.description,
      "source": source,
      "placeholder": placeholder,
      "binding_dependency_item_id": itemID,
      "result_field": resultField,
      "settlement_object_id": settlementObjectID,
      "value_sha256": valueSHA256,
      "result_value_sha256": resultValueSHA256,
    ]
  }
}

/// The native gate's verdict for one produced result, ready to be recorded as
/// evidence and (when accepted) turned into the settlement value.
struct NativeContractVerdict {
  let values: [String: NativeContractValue]
  let trace: NativeResultValidationTrace
  let bindings: [VerifiedContractBinding]
  let declaredFieldNames: [String]
  let declaredConstraintKinds: [String]
  let contractSHA256: String

  /// The declared fields, converted to the plain JSON types the settlement
  /// bridge stores. These are the ONLY task semantic fields the producer
  /// settles: every one of them was extracted, typed and constraint-checked by
  /// the native engine from the model's own text.
  func settledFields() -> [String: Any] {
    var out: [String: Any] = [:]
    for (name, value) in values {
      switch value {
      case .string(let text): out[name] = text
      case .integer(let number): out[name] = number
      case .boolean(let flag): out[name] = flag
      case .null: out[name] = NSNull()
      case .array, .object:
        out[name] = try? JSONSerialization.jsonObject(
          with: JSONEncoder().encode(value))
      }
    }
    return out
  }

  /// Dispatch evidence: what the item declared, what the native engine
  /// verified, and where every binding it used came from. It says nothing about
  /// the task's name, because the gate never looked at one.
  func evidence(generatedText: String) -> [String: Any] {
    [
      "gate": "native.SimiGoResultContracts",
      "authority": "native_pre_settlement",
      "contract_dispatch_basis": "declared_contract",
      "contract_sha256": contractSHA256,
      "declared_schema_version": trace.schemaVersion,
      "declared_fields": declaredFieldNames,
      "declared_constraint_kinds": declaredConstraintKinds,
      "native_validation_status": trace.validationStatus,
      "native_field_extraction": (trace.fieldExtraction.sorted { $0.key < $1.key }.map { name, item in
        [
          "field": name,
          "required": item.required,
          "match_policy": item.matchPolicy,
          "parsed": item.parsed,
        ]
      }),
      "native_constraint_checks": trace.constraintChecks.map { check in
        [
          "index": check.index,
          "kind": check.kind,
          "field": check.field,
          "binding": check.binding ?? "",
          "passed": check.passed,
        ]
      },
      "verified_bindings": bindings.map { $0.evidence() },
      "native_values": (try? JSONSerialization.jsonObject(
        with: JSONEncoder().encode(values))) ?? [:],
      "generated_text_sha256": NativeContractDigest.sha256Hex(Data(generatedText.utf8)),
    ]
  }
}

enum NativeTaskResultContract {
  /// The root keys the native engine implements today. `bindings` is the item's
  /// own selector declaration: it is consumed HERE, to project verified values,
  /// and is not forwarded to the engine, whose strict decoder accepts only
  /// `schema_version` / `fields` / `constraints`. Anything else at the root is
  /// refused rather than quietly dropped.
  static let engineKeys: Set<String> = ["schema_version", "fields", "constraints"]
  static let declarationKeys: Set<String> = ["bindings"]

  /// Refusal description carrying the native engine's structured code, so the
  /// evidence never paraphrases why the producer was rejected.
  struct Rejection: Error, CustomStringConvertible {
    let code: String
    let field: String
    let detail: String
    let stage: String
    var description: String { "\(stage).\(code): field=\(field) \(detail)" }
    func evidence() -> [String: Any] {
      ["kind": "PRODUCER_RESULT_CONTRACT_REFUSAL", "stage": stage,
       "code": code, "field": field, "detail": detail]
    }
  }

  /// Reconstruct a structured refusal record from the settlement wrapper's
  /// reason string when a native contract refusal was re-wrapped as a generic
  /// model-execution failure, so the authoritative evidence stays typed (code,
  /// field, stage) rather than only a string. Returns nil when the reason is not
  /// a result-contract stage.
  static func rejectionEvidence(fromWrappedReason reason: String) -> [String: Any]? {
    let stage = NativeProducerResultContractGate.rejectionStage
    guard let range = reason.range(of: "\(stage).") else { return nil }
    let tail = reason[range.upperBound...]
    let code = String(tail.prefix { $0 != ":" && $0 != " " })
    var field = ""
    if let fr = tail.range(of: "field=") {
      field = String(tail[fr.upperBound...].prefix { $0 != " " })
    }
    return ["kind": "PRODUCER_RESULT_CONTRACT_REFUSAL", "stage": stage,
            "code": code, "field": field, "detail": reason]
  }

  /// Validate one produced result with the item's OWN declaration, using only
  /// values the Information Space admission verified. Throws `Rejection` and
  /// settles nothing when the declaration or the text does not hold.
  static func validate(
    payload: [String: Any],
    generatedText: String,
    admitted: ProductionTaskInputAdmission
  ) throws -> NativeContractVerdict {
    guard let declared = payload["semantic_contract"] as? [String: Any] else {
      throw Rejection(code: "CONTRACT_NOT_DECLARED", field: "",
                      detail: "task item declares no readable semantic_contract; "
        + "the producer path refuses instead of choosing rules by task name",
                      stage: NativeProducerResultContractGate.rejectionStage)
    }
    let extra = Set(declared.keys).subtracting(engineKeys).subtracting(declarationKeys)
    guard extra.isEmpty else {
      throw Rejection(code: "CONTRACT_UNKNOWN_ROOT_KEY", field: "",
                      detail: "semantic_contract carries keys the native engine "
        + "does not implement: \(extra.sorted())",
                      stage: NativeProducerResultContractGate.rejectionStage)
    }
    let contractData: Data
    do {
      // Only the keys the engine implements reach it. Serialize the declaration
      // fragment straight from the parsed JSON object so NSNumbers survive
      // faithfully: an AnyCodable round-trip would bridge integer 1 to Bool
      // (NSNumber casts to Bool first) and corrupt `capture_group`, which the
      // strict decoder then refuses. Canonical keys keep the digest stable.
      let forwarded = declared.filter { engineKeys.contains($0.key) }
      contractData = try JSONSerialization.data(
        withJSONObject: forwarded, options: [.sortedKeys, .withoutEscapingSlashes])
    } catch {
      throw Rejection(code: "CONTRACT_NOT_DECLARED", field: "",
                      detail: "semantic_contract is not encodable: \(error)",
                      stage: NativeProducerResultContractGate.rejectionStage)
    }
    let fullContractData: Data
    do {
      fullContractData = try JSONSerialization.data(
        withJSONObject: declared, options: [.sortedKeys])
    } catch {
      throw Rejection(code: "CONTRACT_NOT_DECLARED", field: "",
                      detail: "semantic_contract is not JSON: \(error)",
                      stage: NativeProducerResultContractGate.rejectionStage)
    }

    let verified: [VerifiedContractBinding]
    let bindings: [String: NativeContractValue]
    do {
      // Binding projection reads the item's OWN selector list, so it must be
      // handed the FULL declaration (the `bindings` root key is stripped from
      // `contractData` before it reaches the engine's strict decoder). Passing
      // the engine-only bytes here would leave `object["bindings"]` empty and
      // every equals_binding would then refuse with CONTRACT_BINDING_MISSING.
      (bindings, verified) = try projectVerifiedBindings(
        contractData: fullContractData, admitted: admitted)
    } catch let rejection as Rejection {
      throw rejection
    } catch let error as NativeResultContractError {
      throw Rejection(code: error.code, field: error.field ?? "",
                      detail: error.detail, stage: error.stage)
    }

    let trace: NativeResultValidationTrace
    do {
      trace = try NativeProducerResultContractGate.validateBeforeSettlement(
        generatedText: generatedText,
        contractJSON: contractData,
        verifiedBindings: bindings)
    } catch let error as NativeResultContractError {
      throw Rejection(code: error.code, field: error.field ?? "",
                      detail: error.detail, stage: error.stage)
    } catch {
      throw Rejection(code: "NATIVE_CONTRACT_UNCLASSIFIED", field: "",
                      detail: String(describing: error),
                      stage: NativeProducerResultContractGate.rejectionStage)
    }

    let forwardedObject = try? JSONSerialization.jsonObject(with: contractData)
    let object = forwardedObject as? [String: Any]
    let fields = (object?["fields"] as? [String: Any]).map { dict in
      dict.keys.sorted()
    } ?? []
    let kinds = ((object?["constraints"] as? [[String: Any]]) ?? []).map {
      ($0["kind"] as? String) ?? "?"
    }
    return NativeContractVerdict(
      values: trace.values,
      trace: trace,
      bindings: verified,
      declaredFieldNames: fields,
      declaredConstraintKinds: kinds,
      contractSHA256: NativeContractDigest.sha256Hex(fullContractData))
  }

  /// Project the contract's own binding selectors onto the admitted closure.
  /// Only `input_binding` selectors are supported here, and each resolves to a
  /// value that the Information Space admission already verified byte-for-byte
  /// and signature-wise (`resolveTaskInput` checked `value_sha256`, the
  /// object identity, the UTF-8 slice and the settlement signatures before this
  /// is ever reached). A selector naming anything else refuses fail-closed: the
  /// native engine will not be handed a value it cannot account for.
  static func projectVerifiedBindings(
    contractData: Data,
    admitted: ProductionTaskInputAdmission
  ) throws -> ([String: NativeContractValue], [VerifiedContractBinding]) {
    guard let object = try JSONSerialization.jsonObject(with: contractData)
            as? [String: Any] else {
      throw Rejection(code: "CONTRACT_INVALID_SCHEMA", field: "",
                      detail: "contract must be an object",
                      stage: NativeProducerResultContractGate.rejectionStage)
    }
    var resolved: [String: NativeContractValue] = [:]
    var provenance: [VerifiedContractBinding] = []
    let specs = (object["bindings"] as? [[String: Any]]) ?? []
    for (index, spec) in specs.enumerated() {
      guard let name = spec["name"] as? String, !name.isEmpty else {
        throw Rejection(code: "CONTRACT_INVALID_BINDING_SPEC", field: "",
                        detail: "binding \(index) must name a binding",
                        stage: NativeProducerResultContractGate.rejectionStage)
      }
      guard !provenance.contains(where: { $0.name == name }) else {
        throw Rejection(code: "CONTRACT_DUPLICATE_BINDING", field: name,
                        detail: "binding \(name) declared twice",
                        stage: NativeProducerResultContractGate.rejectionStage)
      }
      let source = spec["source"] as? String ?? ""
      guard source == "input_binding" else {
        throw Rejection(code: "CONTRACT_UNSUPPORTED_BINDING_SOURCE_NATIVE",
                        field: name,
                        detail: "the native producer gate admits only "
          + "input_binding selectors; \(source.isEmpty ? "<absent>" : source) "
          + "names a value this call site cannot account for",
                        stage: NativeProducerResultContractGate.rejectionStage)
      }
      guard let placeholder = spec["placeholder"] as? String, !placeholder.isEmpty else {
        throw Rejection(code: "CONTRACT_INVALID_BINDING_SPEC", field: name,
                        detail: "input_binding selector needs a placeholder",
                        stage: NativeProducerResultContractGate.rejectionStage)
      }
      // The item declares which placeholder its binding projects; the admission
      // carries the settled object and value the IS verified for that placeholder.
      guard let admittedBinding = payloadInputBindings(admitted: admitted)[placeholder] else {
        throw Rejection(code: "CONTRACT_BINDING_MISSING", field: name,
                        detail: "input placeholder \(placeholder) is not declared "
          + "by the item and admitted",
                        stage: NativeProducerResultContractGate.rejectionStage)
      }
      resolved[name] = .string(admittedBinding.value)
      provenance.append(VerifiedContractBinding(
        name: name,
        value: .string(admittedBinding.value),
        source: source,
        placeholder: placeholder,
        itemID: admittedBinding.itemID,
        resultField: admittedBinding.resultField,
        settlementObjectID: admittedBinding.settlementObjectID,
        valueSHA256: admittedBinding.valueSHA256,
        resultValueSHA256: admittedBinding.resultValueSHA256))
    }
    return (resolved, provenance)
  }

  /// The admitted placeholder -> binding map, restricted to the item's declared
  /// dependencies (the same check `resolveTaskInput` applies, restated here
  /// against the verified admission so a binding cannot point outside the
  /// admitted closure).
  private static func payloadInputBindings(
    admitted: ProductionTaskInputAdmission
  ) -> [String: ProductionTaskInputBinding] {
    var out: [String: ProductionTaskInputBinding] = [:]
    for binding in admitted.bindings
    where admitted.declaredDependencies.contains(binding.itemID)
      || admitted.dependencySettlementObjectIDs[binding.itemID] != nil {
      out[binding.placeholder] = binding
    }
    return out
  }
}

/// Encodes an arbitrary JSON fragment read from the item's own record.
struct AnyCodable: Codable {
  let value: Any

  init(_ value: Any) { self.value = value }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let object = try? container.decode([String: AnyCodable].self) {
      value = object.mapValues { $0.value }
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map { $0.value }
    } else if let flag = try? container.decode(Bool.self) {
      value = flag
    } else if let number = try? container.decode(Double.self) {
      value = number
    } else if let text = try? container.decode(String.self) {
      value = text
    } else if container.decodeNil() {
      value = NSNull()
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "unsupported JSON fragment")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case let object as [String: Any]:
      try container.encode(object.mapValues { AnyCodable($0) })
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let flag as Bool:
      try container.encode(flag)
    case let number as Int:
      try container.encode(number)
    case let number as Double:
      try container.encode(number)
    case let text as String:
      try container.encode(text)
    default:
      try container.encodeNil()
    }
  }
}

enum NativeContractDigest {
  /// The same primitive the entry uses for every other recorded digest, so the
  /// contract digest and the settlement digests are comparable bytes.
  static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
