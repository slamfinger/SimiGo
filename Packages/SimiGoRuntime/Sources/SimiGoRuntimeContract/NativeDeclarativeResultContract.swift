import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Native, task-ID-independent validation for `simigo.result-contract/v1`.
///
/// The caller is responsible for obtaining `verifiedBindings` from the normal
/// Information Space admission path. This module validates the declared
/// relationship between generated fields and those already-verified values; it
/// does not independently establish the provenance of the bindings.
public enum NativeContractValue: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case null
    case array([NativeContractValue])
    case object([String: NativeContractValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? container.decode(Int.self) { self = .integer(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([NativeContractValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: NativeContractValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON contract value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Canonical JSON bytes matching `carrier_loop.canonical`: UTF-8, sorted keys,
    /// compact separators, no escaping of `/`, and no ASCII-only escaping of Unicode.
    /// Digest constraints use this stable representation rather than Swift's debug description.
    public func canonicalJSONData() throws -> Data {
        func foundationValue(_ value: NativeContractValue) -> Any {
            switch value {
            case .string(let string): return string
            case .integer(let integer): return integer
            case .boolean(let boolean): return boolean
            case .null: return NSNull()
            case .array(let values): return values.map(foundationValue)
            case .object(let values): return values.mapValues(foundationValue)
            }
        }
        return try JSONSerialization.data(
            withJSONObject: foundationValue(self),
            options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
    }

    public var description: String {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .boolean(let value): return value ? "true" : "false"
        case .null: return "null"
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "<unprintable>" }
            return text
        }
    }
}

public struct NativeResultContractError: Error, Sendable, Equatable, LocalizedError {
    public let code: String
    public let field: String?
    public let detail: String
    public let stage = "PRODUCER_RESULT_CONTRACT"

    public init(code: String, field: String? = nil, detail: String) {
        self.code = code
        self.field = field
        self.detail = detail
    }

    public var errorDescription: String? {
        let location = field.map { " field=\($0)" } ?? ""
        return "\(code):\(location) \(detail)".trimmingCharacters(in: .whitespaces)
    }
}

public struct NativeResultContract: Codable, Sendable, Equatable {
    public static let supportedVersion = "simigo.result-contract/v1"

    public struct Field: Codable, Sendable, Equatable {
        public enum CaptureGroup: Codable, Sendable, Equatable {
            case index(Int)
            case name(String)

            public init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let value = try? c.decode(Int.self) {
                    guard value >= 0 else {
                        throw DecodingError.dataCorruptedError(in: c, debugDescription: "capture_group index must be >= 0")
                    }
                    self = .index(value)
                    return
                }
                if let value = try? c.decode(String.self), !value.isEmpty {
                    self = .name(value)
                    return
                }
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "capture_group must be a nonnegative integer or nonempty name")
            }

            public func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                switch self {
                case .index(let value): try c.encode(value)
                case .name(let value): try c.encode(value)
                }
            }
        }

        public var pattern: String
        public var captureGroup: CaptureGroup?
        public var type: String
        public var required: Bool
        public var matchPolicy: String
        public var normalize: String
        public var nonempty: Bool
        public var values: [NativeContractValue]?
        public var minimum: Int?
        public var maximum: Int?

        enum CodingKeys: String, CodingKey {
            case pattern
            case captureGroup = "capture_group"
            case type, required
            case matchPolicy = "match_policy"
            case normalize, nonempty, values, minimum, maximum
        }

        public init(
            pattern: String,
            captureGroup: CaptureGroup? = .index(1),
            type: String = "string",
            required: Bool = true,
            matchPolicy: String = "exactly_one",
            normalize: String = "trim",
            nonempty: Bool = true,
            values: [NativeContractValue]? = nil,
            minimum: Int? = nil,
            maximum: Int? = nil
        ) {
            self.pattern = pattern
            self.captureGroup = captureGroup
            self.type = type
            self.required = required
            self.matchPolicy = matchPolicy
            self.normalize = normalize
            self.nonempty = nonempty
            self.values = values
            self.minimum = minimum
            self.maximum = maximum
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pattern = try container.decode(String.self, forKey: .pattern)
            captureGroup = try container.decodeIfPresent(CaptureGroup.self, forKey: .captureGroup) ?? .index(1)
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? "string"
            required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? true
            matchPolicy = try container.decodeIfPresent(String.self, forKey: .matchPolicy) ?? "exactly_one"
            normalize = try container.decodeIfPresent(String.self, forKey: .normalize) ?? "trim"
            nonempty = try container.decodeIfPresent(Bool.self, forKey: .nonempty) ?? true
            values = try container.decodeIfPresent([NativeContractValue].self, forKey: .values)
            minimum = try container.decodeIfPresent(Int.self, forKey: .minimum)
            maximum = try container.decodeIfPresent(Int.self, forKey: .maximum)
        }
    }

    public struct Constraint: Codable, Sendable, Equatable {
        public var kind: String
        public var field: String
        public var binding: String?
        public var parts: [String]?
        public var separator: String?
        public var otherField: String?
        public var value: NativeContractValue?

        enum CodingKeys: String, CodingKey {
            case kind, field, binding, parts, separator
            case otherField = "other_field"
            case value
        }

        public init(kind: String, field: String, binding: String? = nil, parts: [String]? = nil, separator: String? = nil, otherField: String? = nil, value: NativeContractValue? = nil) {
            self.kind = kind
            self.field = field
            self.binding = binding
            self.parts = parts
            self.separator = separator
            self.otherField = otherField
            self.value = value
        }
    }

    public var schemaVersion: String
    public var fields: [String: Field]
    public var constraints: [Constraint]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fields, constraints
    }

    public init(schemaVersion: String = NativeResultContract.supportedVersion, fields: [String: Field], constraints: [Constraint] = []) {
        self.schemaVersion = schemaVersion
        self.fields = fields
        self.constraints = constraints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        fields = try container.decode([String: Field].self, forKey: .fields)
        constraints = try container.decodeIfPresent([Constraint].self, forKey: .constraints) ?? []
    }

    /// Decode with strict-key validation. Unknown keys fail closed instead of being ignored by Codable.
    public static func decodeStrict(from data: Data) throws -> NativeResultContract {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw NativeResultContractError(code: "CONTRACT_INVALID_JSON", detail: String(describing: error))
        }
        guard let object = root as? [String: Any] else {
            throw NativeResultContractError(code: "CONTRACT_INVALID_SCHEMA", detail: "contract root must be an object")
        }
        try requireOnlyKeys(Set(["schema_version", "fields", "constraints"]), actual: Set(object.keys), where: "contract")
        guard let fields = object["fields"] as? [String: Any], !fields.isEmpty else {
            throw NativeResultContractError(code: "CONTRACT_INVALID_SCHEMA", detail: "fields must be a non-empty object")
        }
        for (fieldName, rawSpec) in fields {
            guard let spec = rawSpec as? [String: Any] else {
                throw NativeResultContractError(code: "CONTRACT_INVALID_FIELD_SPEC", field: fieldName, detail: "field spec must be an object")
            }
            try requireOnlyKeys(Set(["pattern", "capture_group", "type", "required", "match_policy", "normalize", "nonempty", "values", "minimum", "maximum"]), actual: Set(spec.keys), where: "field \(fieldName)")
        }
        if let constraints = object["constraints"] {
            guard let entries = constraints as? [Any] else {
                throw NativeResultContractError(code: "CONTRACT_INVALID_SCHEMA", detail: "constraints must be an array")
            }
            for (index, rawConstraint) in entries.enumerated() {
                guard let c = rawConstraint as? [String: Any] else {
                    throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", detail: "constraint \(index) must be an object")
                }
                try requireOnlyKeys(Set(["kind", "field", "binding", "parts", "separator", "other_field", "value"]), actual: Set(c.keys), where: "constraint \(index)")
            }
        }
        do {
            let contract = try JSONDecoder().decode(NativeResultContract.self, from: data)
            try contract.validateDefinition()
            return contract
        } catch let error as NativeResultContractError {
            throw error
        } catch {
            throw NativeResultContractError(code: "CONTRACT_INVALID_SCHEMA", detail: String(describing: error))
        }
    }

    public func validateDefinition() throws {
        guard schemaVersion == Self.supportedVersion else {
            throw NativeResultContractError(code: "CONTRACT_UNKNOWN_SCHEMA_VERSION", detail: "unsupported schema_version \(schemaVersion)")
        }
        guard !fields.isEmpty else {
            throw NativeResultContractError(code: "CONTRACT_INVALID_SCHEMA", detail: "fields must not be empty")
        }
        for (fieldName, field) in fields {
            guard !field.pattern.isEmpty else {
                throw NativeResultContractError(code: "CONTRACT_INVALID_FIELD_SPEC", field: fieldName, detail: "pattern must be non-empty")
            }
            guard ["string", "integer", "boolean", "enum"].contains(field.type) else {
                throw NativeResultContractError(code: "CONTRACT_UNKNOWN_FIELD_TYPE", field: fieldName, detail: "unsupported field type \(field.type)")
            }
            guard ["exactly_one", "first"].contains(field.matchPolicy) else {
                throw NativeResultContractError(code: "CONTRACT_INVALID_FIELD_SPEC", field: fieldName, detail: "unsupported match_policy \(field.matchPolicy)")
            }
            guard ["trim", "upper", "lower"].contains(field.normalize) else {
                throw NativeResultContractError(code: "CONTRACT_UNKNOWN_NORMALIZER", field: fieldName, detail: "unsupported normalizer \(field.normalize)")
            }
            if field.type == "enum", (field.values?.isEmpty ?? true) {
                throw NativeResultContractError(code: "CONTRACT_INVALID_FIELD_SPEC", field: fieldName, detail: "enum field requires non-empty values")
            }
            if let minimum = field.minimum, let maximum = field.maximum, minimum > maximum {
                throw NativeResultContractError(code: "CONTRACT_INVALID_FIELD_SPEC", field: fieldName, detail: "minimum exceeds maximum")
            }
            do {
                _ = try NSRegularExpression(pattern: field.pattern, options: [.anchorsMatchLines])
            } catch {
                throw NativeResultContractError(code: "CONTRACT_INVALID_PATTERN", field: fieldName, detail: String(describing: error))
            }
        }
        for (index, constraint) in constraints.enumerated() {
            guard fields[constraint.field] != nil else {
                throw NativeResultContractError(code: "CONTRACT_CONSTRAINT_FIELD_MISSING", field: constraint.field, detail: "constraint \(index) references a field not declared in contract")
            }
            switch constraint.kind {
            case "equals_binding", "digest_equals_binding":
                guard let binding = constraint.binding, !binding.isEmpty else {
                    throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", field: constraint.field, detail: "\(constraint.kind) requires binding")
                }
            case "concat":
                guard let parts = constraint.parts, !parts.isEmpty, parts.allSatisfy({ fields[$0] != nil }) else {
                    throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", field: constraint.field, detail: "concat requires non-empty parts naming declared fields")
                }
            case "equals_field":
                guard let other = constraint.otherField, fields[other] != nil else {
                    throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", field: constraint.field, detail: "equals_field requires a declared other_field")
                }
            case "equals_literal":
                guard constraint.value != nil else {
                    throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", field: constraint.field, detail: "equals_literal requires value")
                }
            default:
                throw NativeResultContractError(code: "CONTRACT_UNKNOWN_CONSTRAINT", field: constraint.field, detail: "unsupported constraint kind \(constraint.kind)")
            }
        }
    }
}

public struct NativeResultValidationTrace: Codable, Sendable, Equatable {
    public struct FieldTrace: Codable, Sendable, Equatable {
        public let required: Bool
        public let matchPolicy: String
        public let parsed: Bool
    }
    public struct ConstraintTrace: Codable, Sendable, Equatable {
        public let index: Int
        public let kind: String
        public let field: String
        public let binding: String?
        public let parts: [String]?
        public let otherField: String?
        public let passed: Bool
    }

    public let schemaVersion: String
    public let values: [String: NativeContractValue]
    public let fieldExtraction: [String: FieldTrace]
    public let constraintChecks: [ConstraintTrace]
    public let validationStatus: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case values
        case fieldExtraction = "field_extraction"
        case constraintChecks = "constraint_checks"
        case validationStatus = "validation_status"
    }
}

/// Validates generated output solely using a declared contract and values from the
/// verified IS admission result. No task/item ID is accepted, deliberately.
public enum NativeProducerResultContractGate {
    public static let rejectionStage = "PRODUCER_RESULT_CONTRACT"

    /// Production call point: invoke after model generation but before settlement/signing.
    /// `verifiedBindings` must be projected from the successful, signature-checked IS admission.
    public static func validateBeforeSettlement(
        generatedText: String,
        contractJSON: Data,
        verifiedBindings: [String: NativeContractValue]
    ) throws -> NativeResultValidationTrace {
        try NativeDeclarativeResultContractValidator.decodeAndValidate(
            generatedText: generatedText,
            contractJSON: contractJSON,
            verifiedBindings: verifiedBindings
        )
    }

    /// Canonical parsed result payload for settlement. Callers must not settle the raw model text
    /// after this gate has rejected it. The production integration should persist/sign only this
    /// validated result and its provenance bindings.
    public static func validatedResultPayload(
        generatedText: String,
        contractJSON: Data,
        verifiedBindings: [String: NativeContractValue]
    ) throws -> Data {
        let trace = try validateBeforeSettlement(
            generatedText: generatedText,
            contractJSON: contractJSON,
            verifiedBindings: verifiedBindings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(trace.values)
    }
}

public enum NativeDeclarativeResultContractValidator {
    public static func validate(
        generatedText: String,
        contract: NativeResultContract,
        verifiedBindings: [String: NativeContractValue]
    ) throws -> NativeResultValidationTrace {
        try contract.validateDefinition()
        var values: [String: NativeContractValue] = [:]
        var extraction: [String: NativeResultValidationTrace.FieldTrace] = [:]

        for (fieldName, spec) in contract.fields.sorted(by: { $0.key < $1.key }) {
            let value = try extract(fieldName: fieldName, spec: spec, from: generatedText)
            values[fieldName] = value
            extraction[fieldName] = .init(required: spec.required, matchPolicy: spec.matchPolicy, parsed: value != .null)
        }

        var traces: [NativeResultValidationTrace.ConstraintTrace] = []
        for (index, constraint) in contract.constraints.enumerated() {
            guard let actual = values[constraint.field] else {
                throw NativeResultContractError(code: "CONTRACT_CONSTRAINT_FIELD_MISSING", field: constraint.field, detail: "parsed field not found")
            }
            switch constraint.kind {
            case "equals_binding":
                guard let bindingName = constraint.binding, let expected = verifiedBindings[bindingName] else {
                    throw NativeResultContractError(code: "CONTRACT_BINDING_MISSING", field: constraint.field, detail: "required verified binding \(constraint.binding ?? "<nil>") is absent")
                }
                guard actual == expected else {
                    throw NativeResultContractError(code: "PRODUCER_RESULT_BINDING_MISMATCH", field: constraint.field, detail: "actual \(actual) does not equal verified binding \(bindingName)=\(expected)")
                }
                traces.append(.init(index: index, kind: constraint.kind, field: constraint.field, binding: bindingName, parts: nil, otherField: nil, passed: true))
            case "digest_equals_binding":
                guard let bindingName = constraint.binding, let binding = verifiedBindings[bindingName] else {
                    throw NativeResultContractError(code: "CONTRACT_BINDING_MISSING", field: constraint.field, detail: "required verified binding \(constraint.binding ?? "<nil>") is absent")
                }
                // Parity with the production Python gate (`declarative_result_contract`
                // + `production_runtime_bridge`): the extracted result field is the RAW
                // value and the verified Information-Space binding carries the COMMITTED
                // canonical digest (e.g. a dependency's `secret_sha256`). The declared
                // transformation is SHA256(canonicalJSON(actual)) == binding, so the
                // generated value commits to something already settled. The digest bytes
                // use the same `carrier_loop.canonical` convention as Python.
                let actualCanonical: Data
                do {
                    actualCanonical = try actual.canonicalJSONData()
                } catch {
                    throw NativeResultContractError(code: "CONTRACT_CANONICALIZATION_FAILED", field: constraint.field, detail: String(describing: error))
                }
                let actualDigest = NativeSHA256.hexDigest(actualCanonical)
                guard case .string(let committedDigest) = binding, actualDigest == committedDigest else {
                    throw NativeResultContractError(code: "PRODUCER_RESULT_DERIVATION_MISMATCH", field: constraint.field, detail: "canonical SHA-256 of actual \(actual) does not equal committed digest in verified binding \(bindingName)")
                }
                traces.append(.init(index: index, kind: constraint.kind, field: constraint.field, binding: bindingName, parts: nil, otherField: nil, passed: true))
            case "concat":
                guard let parts = constraint.parts, !parts.isEmpty else {
                    throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", field: constraint.field, detail: "concat parts are missing")
                }
                var segments: [String] = []
                for part in parts {
                    guard let v = values[part], v != .null else {
                        throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", field: constraint.field, detail: "concat part \(part) is missing/null")
                    }
                    segments.append(v.description)
                }
                let expected = segments.joined(separator: constraint.separator ?? "")
                guard actual == .string(expected) else {
                    throw NativeResultContractError(code: "PRODUCER_RESULT_DERIVATION_MISMATCH", field: constraint.field, detail: "actual \(actual) does not equal derived value \(expected)")
                }
                traces.append(.init(index: index, kind: constraint.kind, field: constraint.field, binding: nil, parts: parts, otherField: nil, passed: true))
            case "equals_field":
                guard let otherName = constraint.otherField, let expected = values[otherName] else {
                    throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", field: constraint.field, detail: "other_field is missing")
                }
                guard actual == expected else {
                    throw NativeResultContractError(code: "PRODUCER_RESULT_FIELD_MISMATCH", field: constraint.field, detail: "actual \(actual) does not equal \(otherName)=\(expected)")
                }
                traces.append(.init(index: index, kind: constraint.kind, field: constraint.field, binding: nil, parts: nil, otherField: otherName, passed: true))
            case "equals_literal":
                guard let expected = constraint.value else {
                    throw NativeResultContractError(code: "CONTRACT_INVALID_CONSTRAINT", field: constraint.field, detail: "literal value is missing")
                }
                guard actual == expected else {
                    throw NativeResultContractError(code: "PRODUCER_RESULT_LITERAL_MISMATCH", field: constraint.field, detail: "actual \(actual) does not equal literal \(expected)")
                }
                traces.append(.init(index: index, kind: constraint.kind, field: constraint.field, binding: nil, parts: nil, otherField: nil, passed: true))
            default:
                throw NativeResultContractError(code: "CONTRACT_UNKNOWN_CONSTRAINT", field: constraint.field, detail: "unsupported constraint kind \(constraint.kind)")
            }
        }
        return .init(schemaVersion: contract.schemaVersion, values: values, fieldExtraction: extraction, constraintChecks: traces, validationStatus: "VALID")
    }

    public static func decodeAndValidate(
        generatedText: String,
        contractJSON: Data,
        verifiedBindings: [String: NativeContractValue]
    ) throws -> NativeResultValidationTrace {
        let contract = try NativeResultContract.decodeStrict(from: contractJSON)
        return try validate(generatedText: generatedText, contract: contract, verifiedBindings: verifiedBindings)
    }

    private static func extract(fieldName: String, spec: NativeResultContract.Field, from text: String) throws -> NativeContractValue {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: spec.pattern, options: [.anchorsMatchLines])
        } catch {
            throw NativeResultContractError(code: "CONTRACT_INVALID_PATTERN", field: fieldName, detail: String(describing: error))
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        if matches.isEmpty {
            if spec.required {
                throw NativeResultContractError(code: "PRODUCER_RESULT_FIELD_MISSING", field: fieldName, detail: "required field not present in generated text")
            }
            return .null
        }
        if spec.matchPolicy == "exactly_one", matches.count != 1 {
            throw NativeResultContractError(code: "CONTRACT_AMBIGUOUS_FIELD", field: fieldName, detail: "expected one match, found \(matches.count)")
        }
        guard let match = matches.first else {
            if spec.required { throw NativeResultContractError(code: "PRODUCER_RESULT_FIELD_MISSING", field: fieldName, detail: "required field not present") }
            return .null
        }
        let captureRange: NSRange
        switch spec.captureGroup ?? .index(1) {
        case .index(let index):
            guard index >= 0, index < match.numberOfRanges else {
                throw NativeResultContractError(code: "CONTRACT_INVALID_PATTERN", field: fieldName, detail: "capture group index \(index) is not present")
            }
            captureRange = match.range(at: index)
        case .name(let name):
            captureRange = match.range(withName: name)
            guard captureRange.location != NSNotFound else {
                throw NativeResultContractError(code: "CONTRACT_INVALID_PATTERN", field: fieldName, detail: "named capture group \(name) is not present")
            }
        }
        guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: text) else {
            if spec.required { throw NativeResultContractError(code: "PRODUCER_RESULT_FIELD_MISSING", field: fieldName, detail: "capture group produced no value") }
            return .null
        }
        let raw = String(text[swiftRange])
        return try normalizeAndType(raw, fieldName: fieldName, spec: spec)
    }

    private static func normalizeAndType(_ raw: String, fieldName: String, spec: NativeResultContract.Field) throws -> NativeContractValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch spec.type {
        case "string":
            let value: String
            switch spec.normalize {
            case "trim": value = trimmed
            case "upper": value = trimmed.uppercased()
            case "lower": value = trimmed.lowercased()
            default: throw NativeResultContractError(code: "CONTRACT_UNKNOWN_NORMALIZER", field: fieldName, detail: "unsupported normalizer \(spec.normalize)")
            }
            if spec.nonempty && value.isEmpty {
                throw NativeResultContractError(code: "CONTRACT_EMPTY_FIELD", field: fieldName, detail: "field must be non-empty")
            }
            return .string(value)
        case "integer":
            guard let value = Int(trimmed, radix: 10) else {
                throw NativeResultContractError(code: "CONTRACT_TYPE_MISMATCH", field: fieldName, detail: "expected base-10 integer")
            }
            if let minimum = spec.minimum, value < minimum {
                throw NativeResultContractError(code: "CONTRACT_RANGE_VIOLATION", field: fieldName, detail: "\(value) < minimum \(minimum)")
            }
            if let maximum = spec.maximum, value > maximum {
                throw NativeResultContractError(code: "CONTRACT_RANGE_VIOLATION", field: fieldName, detail: "\(value) > maximum \(maximum)")
            }
            return .integer(value)
        case "boolean":
            switch trimmed.lowercased() {
            case "true", "1", "yes": return .boolean(true)
            case "false", "0", "no": return .boolean(false)
            default: throw NativeResultContractError(code: "CONTRACT_TYPE_MISMATCH", field: fieldName, detail: "expected boolean literal")
            }
        case "enum":
            let value = NativeContractValue.string(trimmed)
            guard let choices = spec.values, !choices.isEmpty else {
                throw NativeResultContractError(code: "CONTRACT_INVALID_FIELD_SPEC", field: fieldName, detail: "enum field requires non-empty values")
            }
            guard choices.contains(value) else {
                throw NativeResultContractError(code: "CONTRACT_ENUM_VIOLATION", field: fieldName, detail: "value \(trimmed) is not in the declared enum")
            }
            return value
        default:
            throw NativeResultContractError(code: "CONTRACT_UNKNOWN_FIELD_TYPE", field: fieldName, detail: "unsupported field type \(spec.type)")
        }
    }
}

/// Portable SHA-256 implementation used only for deterministic contract digests.
/// Keeping this implementation local avoids shell tools or runtime-dependent digest APIs.
enum NativeSHA256 {
    private static let initialState: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    static func hexDigest(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return portableHexDigest(data)
        #endif
    }

    private static func portableHexDigest(_ data: Data) -> String {
        var message = Array(data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var state = initialState
        for blockStart in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let offset = blockStart + index * 4
                words[index] = (UInt32(message[offset]) << 24)
                    | (UInt32(message[offset + 1]) << 16)
                    | (UInt32(message[offset + 2]) << 8)
                    | UInt32(message[offset + 3])
            }
            for index in 16..<64 {
                let x = words[index - 15]
                let y = words[index - 2]
                let sigma0 = rotateRight(x, by: 7) ^ rotateRight(x, by: 18) ^ (x >> 3)
                let sigma1 = rotateRight(y, by: 17) ^ rotateRight(y, by: 19) ^ (y >> 10)
                words[index] = words[index - 16] &+ sigma0 &+ words[index - 7] &+ sigma1
            }

            var a = state[0], b = state[1], c = state[2], d = state[3]
            var e = state[4], f = state[5], g = state[6], h = state[7]
            for index in 0..<64 {
                let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choose = (e & f) ^ ((~e) & g)
                let temp1 = h &+ sum1 &+ choose &+ roundConstants[index] &+ words[index]
                let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = sum0 &+ majority
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            state[0] = state[0] &+ a; state[1] = state[1] &+ b
            state[2] = state[2] &+ c; state[3] = state[3] &+ d
            state[4] = state[4] &+ e; state[5] = state[5] &+ f
            state[6] = state[6] &+ g; state[7] = state[7] &+ h
        }
        return state.map { String(format: "%08x", $0) }.joined()
    }
}

private func requireOnlyKeys(_ allowed: Set<String>, actual: Set<String>, where location: String) throws {
    let unknown = actual.subtracting(allowed).sorted()
    guard unknown.isEmpty else {
        throw NativeResultContractError(code: "CONTRACT_UNKNOWN_KEY", detail: "unknown key(s) in \(location): \(unknown.joined(separator: ", "))")
    }
}
