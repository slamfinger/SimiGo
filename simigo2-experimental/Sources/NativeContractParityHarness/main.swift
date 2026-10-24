import Crypto
import Foundation
import SimiGo2Experimental

// CROSS-ENGINE CONTRACT PARITY HARNESS (native side)
//
// Reads the SAME canonical case file the Python production gate reads, runs
// every case through the NATIVE `simigo.result-contract/v1` engine and prints
// one JSON result per case: verdict, structured error code, stage and the typed
// values. It contains no expectations and no case selection: the comparison is
// done by the Python gate, so neither engine can grade its own homework.
//
// This is the only piece of the native integration that is deliberately a
// standalone tool. The production authority lives in `SimiGoTaskRun`'s
// pre-settlement call, not here.

func emit(_ record: [String: Any]) {
  let data = try! JSONSerialization.data(
    withJSONObject: record, options: [.sortedKeys])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
}

func argument(_ name: String, _ arguments: [String]) -> String? {
  guard let index = arguments.firstIndex(of: "--" + name),
        index + 1 < arguments.count else { return nil }
  return arguments[index + 1]
}

func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let casesPath = argument("cases", arguments) else {
  FileHandle.standardError.write(Data(
    "usage: NativeContractParityHarness --cases <expanded.json>\n".utf8))
  exit(2)
}
let url = URL(fileURLWithPath: casesPath)
guard let data = try? Data(contentsOf: url),
      let document = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any],
      let cases = document["cases"] as? [[String: Any]],
      let schemaID = document["schema_id"] as? String else {
  emit(["schema_id": "SIMIGO-NATIVE-CONTRACT-PARITY-RUN-V1",
        "cases_file": casesPath, "error": "case file is unreadable or malformed",
        "case_results": [[String: Any]]()])
  exit(2)
}

var results: [[String: Any]] = []
for var caseRecord in cases {
  // The engine takes the declaration as bytes; re-encode canonically so the
  // bytes are a function of the case, not of dictionary order in the file.
  let contractObject = caseRecord["contract"] ?? [String: Any]()
  let contractData = try! JSONSerialization.data(
    withJSONObject: contractObject, options: [.sortedKeys])
  var bindings: [String: NativeContractValue] = [:]
  if let raw = caseRecord["bindings"] as? [String: Any] {
    for (key, value) in raw {
      // Wrap in an object so the scalar stays a valid JSONSerialization root
      // (no fragmentsAllowed); NativeContractValue decodes from its own field.
      let boxed = try! JSONSerialization.data(
        withJSONObject: ["v": value], options: [.fragmentsAllowed])
      struct Box: Decodable { let v: NativeContractValue }
      bindings[key] = try! JSONDecoder().decode(Box.self, from: boxed).v
    }
  }
  let text = caseRecord["text"] as? String ?? ""
  do {
    let trace = try NativeProducerResultContractGate.validateBeforeSettlement(
      generatedText: text, contractJSON: contractData, verifiedBindings: bindings)
    let values = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(trace.values)) as? [String: Any] ?? [:]
    caseRecord["native_verdict"] = "VALID"
    caseRecord["native_error_code"] = ""
    caseRecord["native_stage"] = ""
    caseRecord["native_values"] = values
  } catch let error as NativeResultContractError {
    caseRecord["native_verdict"] = "REJECT"
    caseRecord["native_error_code"] = error.code
    caseRecord["native_stage"] = error.stage
    caseRecord["native_values"] = [String: Any]()
  } catch {
    caseRecord["native_verdict"] = "REJECT"
    caseRecord["native_error_code"] = "NATIVE_UNCLASSIFIED"
    caseRecord["native_stage"] = NativeProducerResultContractGate.rejectionStage
    caseRecord["native_values"] = [String: Any]()
  }
  results.append(caseRecord)
}

emit([
  "schema_id": "SIMIGO-NATIVE-CONTRACT-PARITY-RUN-V1",
  "cases_schema_id": schemaID,
  "cases_file": casesPath,
  "cases_sha256": sha256Hex(data),
  "case_count": results.count,
  "engine": "native.SimiGoResultContracts",
  "case_results": results,
])
