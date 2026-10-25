import Foundation
import SimiGo2Experimental

struct TaskEntryError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

/// The task item's OWN declaration of how its model output becomes the
/// settlement result value, enforced by the NATIVE
/// `simigo.result-contract/v1` engine before anything is settled.
///
/// There is no second extraction implementation here: the field values this
/// builds the settlement from are exactly the ones the native engine typed,
/// binding-checked and derivation-checked out of the model's own text. A task
/// that declares no contract, or declares a construct the native engine does
/// not implement, is REFUSED - it is never matched to some other task's rules by
/// name, because nothing in this path reads a task name at all.
struct TaskResultContract {
  let verdict: NativeContractVerdict

  init(verdict: NativeContractVerdict) {
    self.verdict = verdict
  }

  /// The reserved identity/provenance keys the settlement record carries
  /// alongside the declared semantic fields. A declaration may not overwrite
  /// them, so a contract cannot smuggle a fake model identity into a
  /// settlement.
  static let reservedKeys: Set<String> = [
    "raw_generated_text", "generated_token_ids", "generated_token_count",
    "model_snapshot_revision", "model_weights_manifest_sha256", "model_call_index",
    "admitted_input_sha256", "admitted_dependency_settlement_object_ids",
    "result_contract_dispatch",
  ]

  /// Build the settlement value from the produced result and the native
  /// verdict. The admitted input identity is included so the settlement record
  /// itself names the dependency objects and input bytes the model consumed.
  func value(
    for produced: ExecutionContinuationResult,
    admitted: ProductionTaskInputAdmission,
    modelIdentity: [String: Any]
  ) throws -> [String: Any] {
    let fields = verdict.settledFields()
    let collision = Set(fields.keys).intersection(TaskResultContract.reservedKeys)
    guard collision.isEmpty else {
      throw TaskEntryError(
        "declared contract fields collide with settlement identity keys: "
          + "\(collision.sorted())")
    }
    var value: [String: Any] = [
      "raw_generated_text": produced.generatedText,
      "generated_token_ids": produced.generatedTokenIDs,
      "generated_token_count": produced.generatedTokenIDs.count,
      "model_snapshot_revision": modelIdentity["snapshot_revision"] as? String ?? "",
      "model_weights_manifest_sha256":
        modelIdentity["weights_manifest_sha256"] as? String ?? "",
      "model_call_index": 1,
      "admitted_input_sha256": admitted.inputSHA256,
      "admitted_dependency_settlement_object_ids":
        admitted.dependencySettlementObjectIDs,
      // The settlement states WHICH declaration produced it and where it was
      // verified, so a reader never has to infer the dispatch from the item's
      // name.
      "result_contract_dispatch": [
        "basis": "declared_contract",
        "authority": "native_pre_settlement",
        "gate": "native.SimiGoResultContracts",
        "contract_sha256": verdict.contractSHA256,
        "declared_schema_version": verdict.trace.schemaVersion,
        "declared_fields": verdict.declaredFieldNames,
      ],
    ]
    for (name, field) in fields {
      value[name] = field
    }
    return value
  }
}
