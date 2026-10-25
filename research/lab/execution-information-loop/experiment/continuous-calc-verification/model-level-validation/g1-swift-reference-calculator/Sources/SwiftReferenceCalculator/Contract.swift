import CryptoKit
import Foundation

/// Stable failure codes from the frozen contract's `error_and_transaction_contract`.
public enum ContractErrorCode: String, Error {
    case unsupportedUnitID = "UNSUPPORTED_UNIT_ID"
    case invalidPayload = "INVALID_PAYLOAD"
    case dependencySetMismatch = "DEPENDENCY_SET_MISMATCH"
    case invalidDependencyValue = "INVALID_DEPENDENCY_VALUE"
    case arithmeticOverflow = "ARITHMETIC_OVERFLOW"
}

public struct UnitRule {
    public let payloadKeys: [String]
    public let requiredDependencies: [String]
    public let formula: String
}

/// The frozen v1 oracle: A/E double their input, B adds dependency A, C scales
/// dependency A, D sums input + B + C left-to-right with checked int64 arithmetic.
public enum ReferenceContract {
    public static let contractID = "SIMIGO-REFERENCE-CALCULATOR-V1"
    public static let contractVersion = "1.0.0"
    public static let buildID = "swift-reference-calculator/1.0.0+g1"

    public static let rules: [String: UnitRule] = [
        "A": UnitRule(payloadKeys: ["input"], requiredDependencies: [], formula: "value = input * 2"),
        "B": UnitRule(
            payloadKeys: ["input"], requiredDependencies: ["A"],
            formula: "value = dependency_values['A'].swift_value + input"),
        "C": UnitRule(
            payloadKeys: ["factor"], requiredDependencies: ["A"],
            formula: "value = dependency_values['A'].swift_value * factor"),
        "D": UnitRule(
            payloadKeys: ["input"], requiredDependencies: ["B", "C"],
            formula: "value = input + dependency_values['B'].swift_value + dependency_values['C'].swift_value"),
        "E": UnitRule(payloadKeys: ["input"], requiredDependencies: [], formula: "value = input * 2"),
    ]

    public static func compute(
        itemID: String,
        sourcePayload: JSONValue,
        dependencyValues: JSONValue
    ) throws -> JSONValue {
        guard let rule = rules[itemID] else {
            throw ContractErrorCode.unsupportedUnitID
        }
        guard case .object(let payload) = sourcePayload, Set(payload.keys) == Set(rule.payloadKeys) else {
            throw ContractErrorCode.invalidPayload
        }
        var integers: [String: Int64] = [:]
        for key in rule.payloadKeys {
            guard let raw = payload[key], case .integer(let number) = raw else {
                throw ContractErrorCode.invalidPayload
            }
            integers[key] = number
        }
        guard case .object(let dependencies) = dependencyValues,
              Set(dependencies.keys) == Set(rule.requiredDependencies) else {
            throw ContractErrorCode.dependencySetMismatch
        }
        var dependencyIntegers: [String: Int64] = [:]
        for dependencyID in rule.requiredDependencies {
            dependencyIntegers[dependencyID] = try dependencyInteger(dependencies[dependencyID])
        }

        switch itemID {
        case "A", "E":
            let (result, overflow) = integers["input"]!.multipliedReportingOverflow(by: 2)
            guard !overflow else { throw ContractErrorCode.arithmeticOverflow }
            return settled(result)
        case "B":
            let (result, overflow) = dependencyIntegers["A"]!.addingReportingOverflow(integers["input"]!)
            guard !overflow else { throw ContractErrorCode.arithmeticOverflow }
            return settled(result)
        case "C":
            let (result, overflow) = dependencyIntegers["A"]!.multipliedReportingOverflow(by: integers["factor"]!)
            guard !overflow else { throw ContractErrorCode.arithmeticOverflow }
            return settled(result)
        case "D":
            let (partial, firstOverflow) = integers["input"]!.addingReportingOverflow(dependencyIntegers["B"]!)
            guard !firstOverflow else { throw ContractErrorCode.arithmeticOverflow }
            let (result, secondOverflow) = partial.addingReportingOverflow(dependencyIntegers["C"]!)
            guard !secondOverflow else { throw ContractErrorCode.arithmeticOverflow }
            return settled(result)
        default:
            throw ContractErrorCode.unsupportedUnitID
        }
    }

    private static func settled(_ value: Int64) -> JSONValue {
        .object(["swift_value": .string(String(value))])
    }

    /// Dependency results must be exactly `{"swift_value": "<canonical decimal i64>"}`.
    private static func dependencyInteger(_ value: JSONValue?) throws -> Int64 {
        guard let value, case .object(let object) = value,
              Set(object.keys) == ["swift_value"],
              case .string(let text)? = object["swift_value"],
              isCanonicalDecimal(text),
              let parsed = Int64(text) else {
            throw ContractErrorCode.invalidDependencyValue
        }
        return parsed
    }

    /// Grammar: `0|-?[1-9][0-9]*` — rejects leading zeros, "-0", "+1", "".
    public static func isCanonicalDecimal(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return false }
        var offset = 0
        if scalars[0] == "-" { offset = 1 }
        guard offset < scalars.count else { return false }
        if scalars[offset] == "0" {
            return offset == 0 && scalars.count == 1
        }
        guard scalars[offset] >= "1" && scalars[offset] <= "9" else { return false }
        offset += 1
        while offset < scalars.count {
            guard scalars[offset] >= "0" && scalars[offset] <= "9" else { return false }
            offset += 1
        }
        return true
    }

    // MARK: - Digests

    public static func sha256Hex(_ text: String) -> String {
        sha256Hex(Data(text.utf8))
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func canonicalDigest(_ value: JSONValue) throws -> String {
        sha256Hex(try CanonicalJSON.encode(value))
    }

    /// Basis fixed by the contract: `{dependencies, payload, unit_id}`.
    public static func inputDigest(
        itemID: String,
        sourcePayload: JSONValue,
        dependencyValues: JSONValue
    ) throws -> String {
        let basis = JSONValue.object([
            "unit_id": .string(itemID),
            "payload": sourcePayload,
            "dependencies": dependencyValues,
        ])
        return try canonicalDigest(basis)
    }
}
