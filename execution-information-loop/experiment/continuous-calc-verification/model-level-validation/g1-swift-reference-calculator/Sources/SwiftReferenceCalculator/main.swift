import Foundation

// G1.1 executable: one frozen-contract invocation per process.
//
//   stdin : {"mode":"compute","invocation_id":..., "item_id":..., "source_payload":..., "dependency_values":...}
//           {"mode":"canonicalize","invocation_id":..., "value":...}
//   args  : --events <path>   (append-only JSONL; one started + one terminal per call)
//   stdout: canonical JSON result on success only
//   exit  : 0 success, 2 contract error, 3 malformed request, 4 internal failure

private let contractErrorExit: Int32 = 2
private let malformedRequestExit: Int32 = 3
private let internalFailureExit: Int32 = 4

private func emitStderr(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

private func canonicalText(_ value: JSONValue, fallback: String) -> String {
    (try? CanonicalJSON.encode(value)) ?? fallback
}

private func malformed(_ detail: String) -> Never {
    let payload = JSONValue.object([
        "error": .string("MALFORMED_REQUEST"),
        "detail": .string(detail),
    ])
    emitStderr(canonicalText(payload, fallback: "{\"error\":\"MALFORMED_REQUEST\"}") + "\n")
    exit(malformedRequestExit)
}

/// The executable hashes itself so the event log can be checked against a pin
/// the harness computes independently.
private func executableSHA256() -> String {
    let path = CommandLine.arguments.first ?? ""
    guard let data = FileManager.default.contents(atPath: path) else { return "UNAVAILABLE" }
    return ReferenceContract.sha256Hex(data)
}

private func timestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
}

private func terminate(
    _ log: EventLog,
    record: [String: JSONValue],
    code: String,
    detail: String,
    exitCode: Int32
) -> Never {
    var terminal = record
    terminal["error_code"] = .string(code)
    if !detail.isEmpty {
        terminal["error_detail"] = .string(detail)
    }
    try? log.append(terminal)
    let payload = JSONValue.object([
        "error_code": .string(code),
        "detail": .string(detail),
    ])
    emitStderr(canonicalText(payload, fallback: "{\"error_code\":\"\(code)\"}") + "\n")
    exit(exitCode)
}

// MARK: - Arguments

var eventsPath: String?
var argumentIndex = 1
while argumentIndex < CommandLine.arguments.count {
    let argument = CommandLine.arguments[argumentIndex]
    switch argument {
    case "--events":
        argumentIndex += 1
        guard argumentIndex < CommandLine.arguments.count else {
            malformed("--events requires a path")
        }
        eventsPath = CommandLine.arguments[argumentIndex]
    case "--help":
        print("usage: SwiftReferenceCalculator --events <path>   (request JSON on stdin)")
        exit(0)
    default:
        malformed("unknown argument: \(argument)")
    }
    argumentIndex += 1
}

guard let eventsPath else {
    malformed("--events <path> is required")
}

// MARK: - Request

let requestData = FileHandle.standardInput.readDataToEndOfFile()
guard let requestText = String(data: requestData, encoding: .utf8) else {
    malformed("stdin is not valid UTF-8")
}
let request: JSONValue
do {
    request = try JSONParser.parse(requestText)
} catch {
    malformed("invalid request JSON: \(error)")
}
guard case .object(let envelope) = request else {
    malformed("request must be a JSON object")
}
guard case .string(let mode)? = envelope["mode"] else {
    malformed("missing mode")
}
guard case .string(let invocationID)? = envelope["invocation_id"], !invocationID.isEmpty else {
    malformed("missing invocation_id")
}

let log = EventLog(path: eventsPath)
let executableHash = executableSHA256()

func eventRecord(_ kind: String, seq: Int, extra: [String: JSONValue]) -> [String: JSONValue] {
    var record: [String: JSONValue] = [
        "contract_id": .string(ReferenceContract.contractID),
        "build_id": .string(ReferenceContract.buildID),
        "executable_sha256": .string(executableHash),
        "invocation_id": .string(invocationID),
        "seq": .integer(Int64(seq)),
        "event": .string(kind),
        "ts_utc": .string(timestamp()),
    ]
    for (key, value) in extra {
        record[key] = value
    }
    return record
}

// MARK: - Compute

if mode == "compute" {
    guard case .string(let itemID)? = envelope["item_id"] else {
        malformed("compute requires item_id")
    }
    guard let sourcePayload = envelope["source_payload"] else {
        malformed("compute requires source_payload")
    }
    guard let dependencyValues = envelope["dependency_values"] else {
        malformed("compute requires dependency_values")
    }

    let inputSHA = (try? ReferenceContract.inputDigest(
        itemID: itemID, sourcePayload: sourcePayload, dependencyValues: dependencyValues
    )) ?? "UNAVAILABLE"
    let dependencySHA = (try? ReferenceContract.canonicalDigest(dependencyValues)) ?? "UNAVAILABLE"

    do {
        try log.append(eventRecord("started", seq: 1, extra: [
            "mode": .string("compute"),
            "item_id": .string(itemID),
            "input_sha256": .string(inputSHA),
            "dependencies_sha256": .string(dependencySHA),
        ]))
    } catch {
        emitStderr("cannot write event log: \(error)\n")
        exit(internalFailureExit)
    }

    do {
        let result = try ReferenceContract.compute(
            itemID: itemID, sourcePayload: sourcePayload, dependencyValues: dependencyValues)
        let resultText = try CanonicalJSON.encode(result)
        let resultSHA = ReferenceContract.sha256Hex(resultText)
        try log.append(eventRecord("completed", seq: 2, extra: [
            "item_id": .string(itemID),
            "result_sha256": .string(resultSHA),
            "result": result,
        ]))
        FileHandle.standardOutput.write(Data((resultText + "\n").utf8))
        exit(0)
    } catch let error as ContractErrorCode {
        terminate(
            log,
            record: eventRecord("failed", seq: 2, extra: ["item_id": .string(itemID)]),
            code: error.rawValue,
            detail: "",
            exitCode: contractErrorExit)
    } catch {
        terminate(
            log,
            record: eventRecord("failed", seq: 2, extra: ["item_id": .string(itemID)]),
            code: "INTERNAL_ERROR",
            detail: "\(error)",
            exitCode: internalFailureExit)
    }
}

// MARK: - Canonicalize

if mode == "canonicalize" {
    guard let value = envelope["value"] else {
        malformed("canonicalize requires value")
    }
    do {
        try log.append(eventRecord("started", seq: 1, extra: ["mode": .string("canonicalize")]))
    } catch {
        emitStderr("cannot write event log: \(error)\n")
        exit(internalFailureExit)
    }
    do {
        let canonical = try CanonicalJSON.encode(value)
        let sha = ReferenceContract.sha256Hex(canonical)
        let response = JSONValue.object([
            "canonical_sha256": .string(sha),
            "canonical_utf8_text": .string(canonical),
        ])
        try log.append(eventRecord("completed", seq: 2, extra: ["canonical_sha256": .string(sha)]))
        FileHandle.standardOutput.write(Data((try CanonicalJSON.encode(response) + "\n").utf8))
        exit(0)
    } catch {
        terminate(
            log,
            record: eventRecord("failed", seq: 2, extra: [:]),
            code: "UNSUPPORTED_CANONICAL_VALUE",
            detail: "\(error)",
            exitCode: malformedRequestExit)
    }
}

malformed("unknown mode: \(mode)")
