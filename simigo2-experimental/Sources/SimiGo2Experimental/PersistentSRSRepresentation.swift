import Crypto
import Darwin
import Foundation

// MARK: - Closed failure status registry (Contract v1.8 section 13.5)

public enum PersistentSRSStatus: String, Equatable, Sendable, Error {
    case truncatedRecord = "TRUNCATED_RECORD"
    case magicStartMismatch = "MAGIC_START_MISMATCH"
    case unknownPhysicalFormatVersion = "UNKNOWN_PHYSICAL_FORMAT_VERSION"
    case integerOverflowOrResourceLimit = "INTEGER_OVERFLOW_OR_RESOURCE_LIMIT"
    case physicalLengthMismatch = "PHYSICAL_LENGTH_MISMATCH"
    case magicEndMismatch = "MAGIC_END_MISMATCH"
    case trailingDataAfterRecord = "TRAILING_DATA_AFTER_RECORD"
    case nonCanonicalEnvelope = "NON_CANONICAL_ENVELOPE"
    case unknownEnvelopeSchema = "UNKNOWN_ENVELOPE_SCHEMA"
    case unknownStorageFormatVersion = "UNKNOWN_STORAGE_FORMAT_VERSION"
    case encodingIdentityMismatch = "ENCODING_IDENTITY_MISMATCH"
    case completionStateInvalid = "COMPLETION_STATE_INVALID"
    case envelopeLogicalKeyMismatch = "ENVELOPE_LOGICAL_KEY_MISMATCH"
    case invalidJSONUTF8 = "INVALID_JSON_UTF8"
    case invalidJSONSyntax = "INVALID_JSON_SYNTAX"
    case jsonDepthLimitExceeded = "JSON_DEPTH_LIMIT_EXCEEDED"
    case duplicateJSONMember = "DUPLICATE_JSON_MEMBER"
    case unknownSchemaOrField = "UNKNOWN_SCHEMA_OR_FIELD"
    case schemaValidationFailed = "SCHEMA_VALIDATION_FAILED"
    case unknownPayloadSchema = "UNKNOWN_PAYLOAD_SCHEMA"
    case invalidUTCTimestamp = "INVALID_UTC_TIMESTAMP"
    case nonCanonicalPayloadBytes = "NON_CANONICAL_PAYLOAD_BYTES"
    case payloadDigestMismatch = "PAYLOAD_DIGEST_MISMATCH"
    case envelopeDigestMismatch = "ENVELOPE_DIGEST_MISMATCH"
    case signatureVerificationFailed = "SIGNATURE_VERIFICATION_FAILED"
    case producerAuthorizationReferenceMismatch = "PRODUCER_AUTHORIZATION_REFERENCE_MISMATCH"
    case decisionCoreBindingMismatch = "DECISION_CORE_BINDING_MISMATCH"
    case evidenceLocationUnauthorized = "EVIDENCE_LOCATION_UNAUTHORIZED"
    case persistentLogicalKeyConflict = "PERSISTENT_LOGICAL_KEY_CONFLICT"
    case recordContentIdentityMismatch = "RECORD_CONTENT_IDENTITY_MISMATCH"
    case persistentDuplicateRecordState = "PERSISTENT_DUPLICATE_RECORD_STATE"
    case persistentConcurrentWriteIndeterminate = "PERSISTENT_CONCURRENT_WRITE_INDETERMINATE"
    case canonicalPresenceMismatch = "CANONICAL_PRESENCE_MISMATCH"
    case canonicalMultisetMismatch = "CANONICAL_MULTISET_MISMATCH"
    case recordNotFound = "RECORD_NOT_FOUND"
    case persistenceVerificationIndeterminate = "PERSISTENCE_VERIFICATION_INDETERMINATE"
    // Manifest v2.2 instance-level statuses (section 9.1)
    case attemptCanonicalEncodingMismatch = "ATTEMPT_CANONICAL_ENCODING_MISMATCH"
    case unsupportedCanonicalValueType = "UNSUPPORTED_CANONICAL_VALUE_TYPE"
    case invalidCompletionOrderKey = "INVALID_COMPLETION_ORDER_KEY"
    case attemptEvidenceDigestMismatch = "ATTEMPT_EVIDENCE_DIGEST_MISMATCH"
    // Closure statuses (Manifest v2.2 section 9 phase 2)
    case closureDuplicateCandidate = "CLOSURE_DUPLICATE_CANDIDATE"
    case closureChainForkRejected = "CLOSURE_CHAIN_FORK_REJECTED"
    case closureInvalidationTargetNotHead = "CLOSURE_INVALIDATION_TARGET_NOT_HEAD"
}

// MARK: - UTF-8 byte identity helpers (Contract v1.8 section 7)

func persistentSRSUTF8Bytes(_ s: String) -> [UInt8] {
    Array(s.utf8)
}

func persistentSRSBytesEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    a.count == b.count && a.elementsEqual(b)
}

func persistentSRSCompareBytes(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    // Lexicographic ascending by exact UTF-8 bytes.
    for i in 0..<Swift.min(a.count, b.count) {
        if a[i] != b[i] { return a[i] < b[i] }
    }
    return a.count <= b.count
}

// MARK: - Closed JSON value model and strict parser (R16/R17)

public indirect enum SRSJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([SRSJSONValue])
    case object([(String, SRSJSONValue)])

    // Manual conformance: tuples do not conform to Equatable, so the compiler
    // cannot synthesize == for the object case's associated value.
    public static func == (lhs: SRSJSONValue, rhs: SRSJSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.bool(let a), .bool(let b)):
            return a == b
        case (.number(let a), .number(let b)):
            return a == b
        case (.string(let a), .string(let b)):
            return a == b
        case (.array(let a), .array(let b)):
            guard a.count == b.count else { return false }
            for (x, y) in zip(a, b) where x != y { return false }
            return true
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            for (x, y) in zip(a, b) {
                if x.0 != y.0 || x.1 != y.1 { return false }
            }
            return true
        default:
            return false
        }
    }
}

enum SRSJSONParserError: Error, Equatable {
    case syntax
    case depthLimitExceeded
    case duplicateMember
    case resourceLimit
}

enum SRSJSONLimits {
    static let maxDepth = 8
    static let maxArrayCount = 1_000_000
    static let maxStringBytes = 1_048_576
}

struct SRSStrictJSONParser {
    let bytes: [UInt8]
    var pos = 0

    static func parse(_ data: [UInt8]) -> Result<SRSJSONValue, SRSJSONParserError> {
        var parser = SRSStrictJSONParser(bytes: data)
        guard let value = parser.parseValue(depth: 1) else {
            return .failure(parser.error ?? .syntax)
        }
        parser.skipWhitespace()
        guard parser.pos == parser.bytes.count else {
            return .failure(.syntax)
        }
        return .success(value)
    }

    var error: SRSJSONParserError?

    mutating func fail<T>(_ e: SRSJSONParserError) -> T? {
        if error == nil { error = e }
        return nil
    }

    mutating func skipWhitespace() {
        while pos < bytes.count {
            let b = bytes[pos]
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { pos += 1 } else { break }
        }
    }

    mutating func peek() -> UInt8? {
        pos < bytes.count ? bytes[pos] : nil
    }

    mutating func parseValue(depth: Int) -> SRSJSONValue? {
        if depth > SRSJSONLimits.maxDepth { return fail(.depthLimitExceeded) }
        skipWhitespace()
        guard let b = peek() else { return fail(.syntax) }
        switch b {
        case UInt8(ascii: "{"): return parseObject(depth: depth)
        case UInt8(ascii: "["): return parseArray(depth: depth)
        case UInt8(ascii: "\""): return parseString().map { .string($0) }
        case UInt8(ascii: "t"): return parseLiteral("true", .bool(true))
        case UInt8(ascii: "f"): return parseLiteral("false", .bool(false))
        case UInt8(ascii: "n"): return parseLiteral("null", .null)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return parseNumber()
        default: return fail(.syntax)
        }
    }

    mutating func parseLiteral(_ lit: String, _ value: SRSJSONValue) -> SRSJSONValue? {
        let litBytes = Array(lit.utf8)
        guard pos + litBytes.count <= bytes.count else { return fail(.syntax) }
        for (i, lb) in litBytes.enumerated() where bytes[pos + i] != lb {
            return fail(.syntax)
        }
        pos += litBytes.count
        return value
    }

    mutating func parseNumber() -> SRSJSONValue? {
        let start = pos
        if peek() == UInt8(ascii: "-") { pos += 1 }
        guard let first = peek() else { return fail(.syntax) }
        switch first {
        case UInt8(ascii: "0"):
            pos += 1
        case UInt8(ascii: "1")...UInt8(ascii: "9"):
            while let c = peek(), c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") { pos += 1 }
        default:
            return fail(.syntax)
        }
        if peek() == UInt8(ascii: ".") {
            pos += 1
            guard let d = peek(), d >= UInt8(ascii: "0"), d <= UInt8(ascii: "9") else { return fail(.syntax) }
            while let c = peek(), c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") { pos += 1 }
        }
        if let e = peek(), e == UInt8(ascii: "e") || e == UInt8(ascii: "E") {
            pos += 1
            if let s = peek(), s == UInt8(ascii: "+") || s == UInt8(ascii: "-") { pos += 1 }
            guard let d = peek(), d >= UInt8(ascii: "0"), d <= UInt8(ascii: "9") else { return fail(.syntax) }
            while let c = peek(), c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") { pos += 1 }
        }
        guard let text = String(bytes: bytes[start..<pos], encoding: .utf8) else { return fail(.syntax) }
        return .number(text)
    }

    mutating func parseString() -> String? {
        guard peek() == UInt8(ascii: "\"") else { return fail(.syntax) }
        pos += 1
        var out: [UInt8] = []
        while true {
            guard let b = peek() else { return fail(.syntax) }
            if b == UInt8(ascii: "\"") {
                pos += 1
                guard out.count <= SRSJSONLimits.maxStringBytes else { return fail(.resourceLimit) }
                guard let s = String(bytes: out, encoding: .utf8) else { return fail(.syntax) }
                return s
            }
            if b == UInt8(ascii: "\\") {
                pos += 1
                guard let esc = peek() else { return fail(.syntax) }
                pos += 1
                switch esc {
                case UInt8(ascii: "\""): out.append(UInt8(ascii: "\""))
                case UInt8(ascii: "\\"): out.append(UInt8(ascii: "\\"))
                case UInt8(ascii: "/"): out.append(UInt8(ascii: "/"))
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    guard let u1 = parseHex4() else { return fail(.syntax) }
                    var scalar = UInt32(u1)
                    if u1 >= 0xD800 && u1 <= 0xDBFF {
                        // High surrogate: require a following \uXXXX low surrogate.
                        guard peek() == UInt8(ascii: "\\") else { return fail(.syntax) }
                        pos += 1
                        guard peek() == UInt8(ascii: "u") else { return fail(.syntax) }
                        pos += 1
                        guard let u2 = parseHex4(), u2 >= 0xDC00, u2 <= 0xDFFF else { return fail(.syntax) }
                        scalar = 0x10000 + (UInt32(u1 - 0xD800) << 10) + UInt32(u2 - 0xDC00)
                    } else if u1 >= 0xDC00 && u1 <= 0xDFFF {
                        return fail(.syntax)
                    }
                    guard let sc = Unicode.Scalar(scalar) else { return fail(.syntax) }
                    out.append(contentsOf: Array(String(sc).utf8))
                default:
                    return fail(.syntax)
                }
            } else if b < 0x20 {
                return fail(.syntax)
            } else {
                out.append(b)
                pos += 1
            }
        }
    }

    mutating func parseHex4() -> UInt16? {
        var v: UInt16 = 0
        for _ in 0..<4 {
            guard let c = peek() else { return nil }
            let d: UInt16
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): d = UInt16(c - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): d = UInt16(c - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): d = UInt16(c - UInt8(ascii: "A") + 10)
            default: return nil
            }
            v = v << 4 | d
            pos += 1
        }
        return v
    }

    mutating func parseArray(depth: Int) -> SRSJSONValue? {
        pos += 1 // consume [
        var items: [SRSJSONValue] = []
        skipWhitespace()
        if peek() == UInt8(ascii: "]") { pos += 1; return .array(items) }
        while true {
            guard items.count < SRSJSONLimits.maxArrayCount else { return fail(.resourceLimit) }
            guard let v = parseValue(depth: depth + 1) else { return nil }
            items.append(v)
            skipWhitespace()
            guard let sep = peek() else { return fail(.syntax) }
            if sep == UInt8(ascii: ",") { pos += 1; continue }
            if sep == UInt8(ascii: "]") { pos += 1; return .array(items) }
            return fail(.syntax)
        }
    }

    mutating func parseObject(depth: Int) -> SRSJSONValue? {
        pos += 1 // consume {
        var members: [(String, SRSJSONValue)] = []
        skipWhitespace()
        if peek() == UInt8(ascii: "}") { pos += 1; return .object(members) }
        while true {
            skipWhitespace()
            guard let key = parseString() else { return nil }
            skipWhitespace()
            guard peek() == UInt8(ascii: ":") else { return fail(.syntax) }
            pos += 1
            guard let v = parseValue(depth: depth + 1) else { return nil }
            if members.contains(where: { $0.0 == key }) { return fail(.duplicateMember) }
            members.append((key, v))
            skipWhitespace()
            guard let sep = peek() else { return fail(.syntax) }
            if sep == UInt8(ascii: ",") { pos += 1; continue }
            if sep == UInt8(ascii: "}") { pos += 1; return .object(members) }
            return fail(.syntax)
        }
    }
}

// MARK: - RFC 8785 JCS serialization (numeric-free subset; I0 forbids numbers)

enum SRSJCS {
    static func utf16CodeUnits(_ s: String) -> [UInt16] {
        Array(s.utf16)
    }

    static func compareKeys(_ a: String, _ b: String) -> Bool {
        // RFC 8785 sorts object members by UTF-16 code units.
        let ua = utf16CodeUnits(a)
        let ub = utf16CodeUnits(b)
        for i in 0..<Swift.min(ua.count, ub.count) {
            if ua[i] != ub[i] { return ua[i] < ub[i] }
        }
        return ua.count <= ub.count
    }

    static func serializeString(_ s: String) -> [UInt8]? {
        var out: [UInt8] = [UInt8(ascii: "\"")]
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x22: out.append(contentsOf: Array("\\\"".utf8))
            case 0x5C: out.append(contentsOf: Array("\\\\".utf8))
            case 0x08: out.append(contentsOf: Array("\\b".utf8))
            case 0x09: out.append(contentsOf: Array("\\t".utf8))
            case 0x0A: out.append(contentsOf: Array("\\n".utf8))
            case 0x0C: out.append(contentsOf: Array("\\f".utf8))
            case 0x0D: out.append(contentsOf: Array("\\r".utf8))
            case 0x00...0x1F:
                out.append(contentsOf: Array(String(format: "\\u%04x", scalar.value).utf8))
            default:
                out.append(contentsOf: Array(String(scalar).utf8))
            }
        }
        out.append(UInt8(ascii: "\""))
        return out
    }

    static func serialize(_ v: SRSJSONValue) -> [UInt8]? {
        switch v {
        case .null:
            return Array("null".utf8)
        case .bool(true):
            return Array("true".utf8)
        case .bool(false):
            return Array("false".utf8)
        case .number:
            // Numeric values are forbidden in I0 canonical bytes.
            return nil
        case .string(let s):
            return serializeString(s)
        case .array(let items):
            var out: [UInt8] = [UInt8(ascii: "[")]
            for (i, item) in items.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                guard let b = serialize(item) else { return nil }
                out.append(contentsOf: b)
            }
            out.append(UInt8(ascii: "]"))
            return out
        case .object(let members):
            // Deterministic stable sort by RFC 8785 UTF-16 key order; duplicate
            // keys cannot occur because the strict parser rejects them.
            var idx = members.enumerated().map { ($0.0, $0.1) }
            idx.sort {
                if equivalentKeys($0.1.0, $1.1.0) { return $0.0 < $1.0 }
                return compareKeys($0.1.0, $1.1.0)
            }
            idx.sort {
                if equivalentKeys($0.1.0, $1.1.0) { return $0.0 < $1.0 }
                return compareKeys($0.1.0, $1.1.0)
            }
            var out: [UInt8] = [UInt8(ascii: "{")]
            for (i, member) in idx.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                guard let kb = serializeString(member.1.0), let vb = serialize(member.1.1) else { return nil }
                out.append(contentsOf: kb)
                out.append(UInt8(ascii: ":"))
                out.append(contentsOf: vb)
            }
            out.append(UInt8(ascii: "}"))
            return out
        }
    }

    static func equivalentKeys(_ a: String, _ b: String) -> Bool {
        utf16CodeUnits(a) == utf16CodeUnits(b)
    }
}

// MARK: - Strict UTC timestamp parser (Contract v1.8 section 13.4)

enum SRSStrictUTC {
    static func isValid(_ s: String) -> Bool {
        let b = Array(s.utf8)
        // Exact syntax: YYYY-MM-DDTHH:MM:SS[.digits]Z
        guard b.count >= 20 else { return false }
        func digits(_ range: Range<Int>) -> [UInt8] {
            Array(b[range])
        }
        func allDigits(_ bs: [UInt8]) -> Bool {
            !bs.isEmpty && bs.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
        }
        func num(_ bs: [UInt8]) -> Int? {
            guard allDigits(bs) else { return nil }
            var v = 0
            for d in bs { v = v * 10 + Int(d - UInt8(ascii: "0")) }
            return v
        }
        // Seconds separator: 'Z' when no fraction, '.' when a fraction follows;
        // 'Z' is always the final byte.
        guard b[19] == UInt8(ascii: "Z") || b[19] == UInt8(ascii: ".") else { return false }
        if b[19] == UInt8(ascii: ".") {
            guard b.count >= 22 else { return false }
            guard allDigits(Array(b[20..<(b.count - 1)])), b[b.count - 1] == UInt8(ascii: "Z") else { return false }
        }
        guard b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"),
              b[10] == UInt8(ascii: "T"), b[13] == UInt8(ascii: ":"),
              b[16] == UInt8(ascii: ":") else { return false }
        guard let year = num(Array(b[0..<4])), (1...9999).contains(year) else { return false }
        guard let month = num(Array(b[5..<7])), (1...12).contains(month) else { return false }
        guard let day = num(Array(b[8..<10])), (1...31).contains(day) else { return false }
        guard let hour = num(Array(b[11..<13])), (0...23).contains(hour) else { return false }
        guard let minute = num(Array(b[14..<16])), (0...59).contains(minute) else { return false }
        guard let second = num(Array(b[17..<19])), (0...59).contains(second) else { return false }
        // Gregorian leap-year day validity.
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let daysInMonth = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        guard day <= daysInMonth else { return false }
        return true
    }
}

// MARK: - I0 value model (closed mapping of PERSISTENT_SRS_RECORD_JSON_SCHEMA_V1.6)

public struct SRSBindingValue: Equatable, Sendable {
    public var identity: String
    public var version: String
    public var contentDigestHex64: String
    public init(identity: String, version: String, contentDigestHex64: String) {
        self.identity = identity
        self.version = version
        self.contentDigestHex64 = contentDigestHex64
    }
}

public enum SRSRelationStatus: String, Equatable, Sendable {
    case current, superseded, invalidated
}

public enum SRSResolution: String, Equatable, Sendable {
    case resolvedWithoutRecompute = "RESOLVED_WITHOUT_RECOMPUTE"
    case unresolved = "unresolved"
}

public enum SRSDependencyResolution: String, Equatable, Sendable {
    case resolved = "resolved"
    case unresolved = "unresolved"
}

public enum SRSInvalidationStatus: String, Equatable, Sendable {
    case none = "none"
    case superseded = "superseded"
    case invalidated = "invalidated"
}

public enum SRSSettlementStatus: String, Equatable, Sendable {
    case declaredSettled = "DECLARED_SETTLED"
    case contested = "CONTESTED"
    case unresolvedLifecycleConflict = "UNRESOLVED_LIFECYCLE_CONFLICT"
    case invalidated = "INVALIDATED"
}

public enum SRSFreshnessStatus: String, Equatable, Sendable {
    case current
    case freshnessRecheckRequired = "FRESHNESS_RECHECK_REQUIRED"
}

public struct SRSFreshnessRequirement: Equatable, Sendable {
    public var identity: String
    public var evidence: SRSBindingValue?
    public var expectedEvidenceDigestHex64: String
    public var status: SRSFreshnessStatus
    public var validUntilUTC: String?
    public var observedAtUTC: String
    public init(identity: String, evidence: SRSBindingValue?, expectedEvidenceDigestHex64: String,
                status: SRSFreshnessStatus, validUntilUTC: String?, observedAtUTC: String) {
        self.identity = identity
        self.evidence = evidence
        self.expectedEvidenceDigestHex64 = expectedEvidenceDigestHex64
        self.status = status
        self.validUntilUTC = validUntilUTC
        self.observedAtUTC = observedAtUTC
    }
}

public struct SRSDependency: Equatable, Sendable {
    public var binding: SRSBindingValue?
    public var role: String
    public var necessity: String
    public var resolution: SRSDependencyResolution
    public var status: SRSRelationStatus
    public init(binding: SRSBindingValue?, role: String, necessity: String,
                resolution: SRSDependencyResolution, status: SRSRelationStatus) {
        self.binding = binding
        self.role = role
        self.necessity = necessity
        self.resolution = resolution
        self.status = status
    }
}

public struct PersistentSRSRecord: Equatable, Sendable {
    public var logicalKeyIdentity: String
    public var logicalKeyVersion: String
    public var settledBinding: SRSBindingValue?
    public var settlementID: String
    public var settlementStatus: SRSSettlementStatus
    public var sourceRelationIdentity: String
    public var resultIdentity: String
    public var requiresCanonicalIdentityRule: Bool
    public var canonicalIdentityRule: SRSBindingValue?
    public var settledProvenanceBindings: [SRSBindingValue]?
    public var sourceBinding: SRSBindingValue?
    public var sourceSemanticBinding: SRSBindingValue?
    public var sourceApplicabilityCoverage: SRSBindingValue?
    public var sourceInvalidationRecord: SRSBindingValue?
    public var sourceInvalidationStatus: SRSInvalidationStatus
    public var sourceIdentityRule: SRSBindingValue?
    public var sourceStatus: SRSRelationStatus
    public var dependencyBoundary: SRSBindingValue?
    public var dependencies: [SRSDependency]?
    public var resultBinding: SRSBindingValue?
    public var resultResolution: SRSResolution
    public var interpretabilityEvidence: SRSBindingValue?
    public var resultStatus: SRSRelationStatus
    public var provenanceBindings: [SRSBindingValue]?
    public var provenanceLifecycle: SRSSettlementStatus
    public var provenanceBoundary: SRSBindingValue?
    public var lifecycleBindings: [SRSBindingValue]?
    public var lifecycleStatus: SRSSettlementStatus
    public var lifecycleBoundary: SRSBindingValue?
    public var freshnessBoundary: SRSBindingValue?
    public var freshnessRequirements: [SRSFreshnessRequirement]?
    public var resolutionRule: SRSBindingValue?
    public var policies: [SRSBindingValue]?
    public var policyBoundary: SRSBindingValue?
    public var producerAuthorizationReference: String

    public init() {
        logicalKeyIdentity = ""
        logicalKeyVersion = ""
        settlementID = ""
        settlementStatus = .declaredSettled
        sourceRelationIdentity = ""
        resultIdentity = ""
        requiresCanonicalIdentityRule = false
        sourceInvalidationStatus = .none
        sourceStatus = .current
        resultResolution = .unresolved
        resultStatus = .current
        provenanceLifecycle = .declaredSettled
        lifecycleStatus = .declaredSettled
        producerAuthorizationReference = ""
    }
}

// MARK: - I0 canonical encoding (encoding_identity = PERSISTENT_SRS_CANONICAL_V1)

public enum SRSEncodingConstants {
    public static let payloadSchemaID = "SIMIGO_PERSISTENT_SRS_RECORD_V1"
    public static let encodingIdentity = "PERSISTENT_SRS_CANONICAL_V1"
    public static let decisionCoreSourceCommit = "1d47f3be56dfa8c6bf7619f4566b271ed74aad27"
    public static let decisionCoreSourceSHA256 = "7fec2ed4d6e6f82fe677a7f098ec98d3e99bf4138420f1dd051570c75cf1c72e"
    public static let storageFormatVersion = "PERSISTENT_SRS_STORAGE_V1"
    public static let envelopeSchemaID = "SIMIGO_PERSISTENT_SRS_ENVELOPE_V1"
    public static let completionState = "COMPLETE"
    public static let magicStart = "SIMISRSV1001"
    public static let magicEnd = "SIMISRSV1END"
    public static let physicalVersion: UInt32 = 1
    public static let maxPayloadBytes = 16_777_216
    public static let maxEnvelopeBytes = 1_048_576
    public static let maxTotalBytes = 17_825_900
}

enum SRSDecodeError: Error {
    case fail(PersistentSRSStatus)
}

func isHex64(_ s: String) -> Bool {
    let b = Array(s.utf8)
    return b.count == 64 && b.allSatisfy {
        ($0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9")) ||
        ($0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "f"))
    }
}

func isUTCShape(_ s: String) -> Bool {
    // Schema pattern: ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$
    let b = Array(s.utf8)
    func digits(_ r: Range<Int>) -> Bool {
        !r.isEmpty && r.upperBound <= b.count && b[r].allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
    }
    guard b.count >= 20, digits(0..<4), b[4] == UInt8(ascii: "-"), digits(5..<7),
          b[7] == UInt8(ascii: "-"), digits(8..<10), b[10] == UInt8(ascii: "T"),
          digits(11..<13), b[13] == UInt8(ascii: ":"), digits(14..<16),
          b[16] == UInt8(ascii: ":"), digits(17..<19) else { return false }
    if b[19] == UInt8(ascii: "Z") {
        return true
    }
    if b[19] == UInt8(ascii: ".") {
        guard b.count >= 22, digits(20..<(b.count - 1)),
              b[b.count - 1] == UInt8(ascii: "Z") else { return false }
        return true
    }
    return false
}

private struct SRSJSONObj {
    let members: [(String, SRSJSONValue)]
    func value(_ key: String) throws -> SRSJSONValue {
        guard let entry = members.first(where: { $0.0 == key }) else {
            throw SRSDecodeError.fail(.unknownSchemaOrField)
        }
        return entry.1
    }
}

private func asObj(_ v: SRSJSONValue) throws -> SRSJSONObj {
    guard case .object(let members) = v else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return SRSJSONObj(members: members)
}

private func asString(_ v: SRSJSONValue, minLength: Int = 0) throws -> String {
    guard case .string(let s) = v, s.utf8.count >= minLength, s.utf8.count <= SRSJSONLimits.maxStringBytes else {
        throw SRSDecodeError.fail(.schemaValidationFailed)
    }
    return s
}

private func asBool(_ v: SRSJSONValue) throws -> Bool {
    guard case .bool(let b) = v else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return b
}

private func asHex64(_ v: SRSJSONValue) throws -> String {
    let s = try asString(v)
    guard isHex64(s) else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return s
}

private func asBinding(_ v: SRSJSONValue) throws -> SRSBindingValue? {
    if case .null = v { return nil }
    let o = try asObj(v)
    let identity = try asString(try o.value("identity"), minLength: 1)
    let version = try asString(try o.value("version"), minLength: 1)
    let digest = try asHex64(try o.value("content_digest"))
    return SRSBindingValue(identity: identity, version: version, contentDigestHex64: digest)
}

private func asBindingArray(_ v: SRSJSONValue) throws -> [SRSBindingValue]? {
    if case .null = v { return nil }
    guard case .array(let items) = v else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    guard items.count <= SRSJSONLimits.maxArrayCount else { throw SRSDecodeError.fail(.integerOverflowOrResourceLimit) }
    return try items.map { item -> SRSBindingValue in
        guard let binding = try asBinding(item) else {
            throw SRSDecodeError.fail(.schemaValidationFailed)
        }
        return binding
    }
}

private func asRelationStatus(_ v: SRSJSONValue) throws -> SRSRelationStatus {
    let s = try asString(v)
    guard let r = SRSRelationStatus(rawValue: s) else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return r
}

private func asSettlementStatus(_ v: SRSJSONValue) throws -> SRSSettlementStatus {
    let s = try asString(v)
    guard let r = SRSSettlementStatus(rawValue: s) else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return r
}

private func asResolution(_ v: SRSJSONValue) throws -> SRSResolution {
    let s = try asString(v)
    guard let r = SRSResolution(rawValue: s) else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return r
}

private func asDependencyResolution(_ v: SRSJSONValue) throws -> SRSDependencyResolution {
    let s = try asString(v)
    guard let r = SRSDependencyResolution(rawValue: s) else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return r
}

private func asInvalidationStatus(_ v: SRSJSONValue) throws -> SRSInvalidationStatus {
    let s = try asString(v)
    guard let r = SRSInvalidationStatus(rawValue: s) else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return r
}

private func asUTCTimestamp(_ v: SRSJSONValue) throws -> String {
    let s = try asString(v)
    guard isUTCShape(s) else { throw SRSDecodeError.fail(.schemaValidationFailed) }
    return s
}

extension PersistentSRSRecord {
    // Schema-equivalent closed decode: exact members, types, enums, consts,
    // lengths, and patterns. Equivalent to R19 validation.
    public static func decode(_ v: SRSJSONValue) throws -> PersistentSRSRecord {
        let root = try asObj(v)
        // additionalProperties=false on the root object.
        let allowedRoot: Set<String> = [
            "payload_schema_id", "logical_key", "settled_relation_state", "source_relation",
            "dependency_set", "result", "provenance", "lifecycle", "freshness",
            "resolution_policy", "producer_authorization_reference", "decision_core_binding",
            "encoding_identity",
        ]
        for (k, _) in root.members where !allowedRoot.contains(k) {
            throw SRSDecodeError.fail(.unknownSchemaOrField)
        }
        let schemaID = try asString(try root.value("payload_schema_id"))
        guard schemaID == SRSEncodingConstants.payloadSchemaID else {
            throw SRSDecodeError.fail(.unknownPayloadSchema)
        }
        let encoding = try asString(try root.value("encoding_identity"))
        guard encoding == SRSEncodingConstants.encodingIdentity else {
            throw SRSDecodeError.fail(.encodingIdentityMismatch)
        }
        var r = PersistentSRSRecord()
        let keyObj = try asObj(try root.value("logical_key"))
        r.logicalKeyIdentity = try asString(try keyObj.value("identity"), minLength: 1)
        r.logicalKeyVersion = try asString(try keyObj.value("version"), minLength: 1)

        let settled = try asObj(try root.value("settled_relation_state"))
        r.settledBinding = try asBinding(try settled.value("binding"))
        r.settlementID = try asString(try settled.value("settlement_id"), minLength: 1)
        r.settlementStatus = try asSettlementStatus(try settled.value("status"))
        r.sourceRelationIdentity = try asString(try settled.value("source_relation_identity"), minLength: 1)
        r.resultIdentity = try asString(try settled.value("result_identity"), minLength: 1)
        r.requiresCanonicalIdentityRule = try asBool(try settled.value("requires_canonical_identity_rule"))
        r.canonicalIdentityRule = try asBinding(try settled.value("canonical_identity_rule"))
        r.settledProvenanceBindings = try asBindingArray(try settled.value("provenance_bindings"))

        let source = try asObj(try root.value("source_relation"))
        r.sourceBinding = try asBinding(try source.value("binding"))
        r.sourceSemanticBinding = try asBinding(try source.value("semantic_binding"))
        r.sourceApplicabilityCoverage = try asBinding(try source.value("applicability_coverage"))
        r.sourceInvalidationRecord = try asBinding(try source.value("invalidation_record"))
        r.sourceInvalidationStatus = try asInvalidationStatus(try source.value("invalidation_status"))
        r.sourceIdentityRule = try asBinding(try source.value("identity_rule"))
        r.sourceStatus = try asRelationStatus(try source.value("status"))

        let deps = try asObj(try root.value("dependency_set"))
        r.dependencyBoundary = try asBinding(try deps.value("boundary"))
        if case .null = try deps.value("dependencies") {
            r.dependencies = nil
        } else if case .array(let depItems) = try deps.value("dependencies") {
            guard depItems.count <= SRSJSONLimits.maxArrayCount else { throw SRSDecodeError.fail(.integerOverflowOrResourceLimit) }
            r.dependencies = try depItems.map { item in
                let d = try asObj(item)
                let role = try asString(try d.value("role"), minLength: 1)
                let necessity = try asString(try d.value("necessity"), minLength: 1)
                let resolution = try asDependencyResolution(try d.value("resolution"))
                let status = try asRelationStatus(try d.value("status"))
                let binding = try asBinding(try d.value("binding"))
                return SRSDependency(binding: binding, role: role, necessity: necessity,
                                     resolution: resolution, status: status)
            }
        } else {
            throw SRSDecodeError.fail(.schemaValidationFailed)
        }

        let result = try asObj(try root.value("result"))
        r.resultBinding = try asBinding(try result.value("binding"))
        r.resultResolution = try asResolution(try result.value("resolution"))
        r.interpretabilityEvidence = try asBinding(try result.value("interpretability_evidence"))
        r.resultStatus = try asRelationStatus(try result.value("status"))

        let provenance = try asObj(try root.value("provenance"))
        r.provenanceBindings = try asBindingArray(try provenance.value("bindings"))
        r.provenanceLifecycle = try asSettlementStatus(try provenance.value("lifecycle"))
        r.provenanceBoundary = try asBinding(try provenance.value("boundary"))

        let lifecycle = try asObj(try root.value("lifecycle"))
        r.lifecycleBindings = try asBindingArray(try lifecycle.value("bindings"))
        r.lifecycleStatus = try asSettlementStatus(try lifecycle.value("lifecycle"))
        r.lifecycleBoundary = try asBinding(try lifecycle.value("boundary"))

        let freshness = try asObj(try root.value("freshness"))
        r.freshnessBoundary = try asBinding(try freshness.value("boundary"))
        if case .null = try freshness.value("requirements") {
            r.freshnessRequirements = nil
        } else if case .array(let reqItems) = try freshness.value("requirements") {
            guard reqItems.count <= SRSJSONLimits.maxArrayCount else { throw SRSDecodeError.fail(.integerOverflowOrResourceLimit) }
            r.freshnessRequirements = try reqItems.map { item in
                let f = try asObj(item)
                let identity = try asString(try f.value("identity"), minLength: 1)
                let evidence = try asBinding(try f.value("evidence"))
                let expected = try asHex64(try f.value("expected_evidence_digest"))
                let statusRaw = try asString(try f.value("status"))
                guard let status = SRSFreshnessStatus(rawValue: statusRaw) else {
                    throw SRSDecodeError.fail(.schemaValidationFailed)
                }
                let validUntil: String?
                let vuValue = try f.value("valid_until_utc")
                if case .null = vuValue { validUntil = nil } else { validUntil = try asUTCTimestamp(vuValue) }
                let observed = try asUTCTimestamp(try f.value("observed_at_utc"))
                return SRSFreshnessRequirement(identity: identity, evidence: evidence,
                                               expectedEvidenceDigestHex64: expected, status: status,
                                               validUntilUTC: validUntil, observedAtUTC: observed)
            }
        } else {
            throw SRSDecodeError.fail(.schemaValidationFailed)
        }

        let policy = try asObj(try root.value("resolution_policy"))
        r.resolutionRule = try asBinding(try policy.value("resolution_rule"))
        r.policies = try asBindingArray(try policy.value("policies"))
        r.policyBoundary = try asBinding(try policy.value("boundary"))

        r.producerAuthorizationReference = try asString(try root.value("producer_authorization_reference"), minLength: 1)

        let coreBinding = try asObj(try root.value("decision_core_binding"))
        let commit = try asString(try coreBinding.value("source_commit"))
        let sha = try asHex64(try coreBinding.value("source_sha256"))
        guard commit == SRSEncodingConstants.decisionCoreSourceCommit,
              sha == SRSEncodingConstants.decisionCoreSourceSHA256 else {
            throw SRSDecodeError.fail(.decisionCoreBindingMismatch)
        }
        return r
    }

    private func bindingJSON(_ b: SRSBindingValue?) -> SRSJSONValue {
        guard let b else { return .null }
        return .object([
            ("identity", .string(b.identity)),
            ("version", .string(b.version)),
            ("content_digest", .string(b.contentDigestHex64)),
        ])
    }

    private func bindingsJSON(_ list: [SRSBindingValue]?, sortCanonical: Bool) -> SRSJSONValue {
        guard let list else { return .null }
        var items = list.map { bindingJSON($0) }
        if sortCanonical { items = SRSCanonical.sortCollection(items) }
        return .array(items)
    }

    private func dependencyJSON(_ d: SRSDependency) -> SRSJSONValue {
        .object([
            ("binding", bindingJSON(d.binding)),
            ("role", .string(d.role)),
            ("necessity", .string(d.necessity)),
            ("resolution", .string(d.resolution.rawValue)),
            ("status", .string(d.status.rawValue)),
        ])
    }

    /// Encode the canonical I0 JSON value: unordered collections sorted by the
    /// UTF-8 bytes of each element's independent JCS serialization.
    public func canonicalJSONValue() -> SRSJSONValue {
        var depItems: [SRSJSONValue]? = nil
        if let deps = dependencies {
            depItems = SRSCanonical.sortCollection(deps.map { dependencyJSON($0) })
        }
        var reqItems: [SRSJSONValue]? = nil
        if let reqs = freshnessRequirements {
            reqItems = SRSCanonical.sortCollection(reqs.map { req in
                .object([
                    ("identity", .string(req.identity)),
                    ("evidence", bindingJSON(req.evidence)),
                    ("expected_evidence_digest", .string(req.expectedEvidenceDigestHex64)),
                    ("status", .string(req.status.rawValue)),
                    ("valid_until_utc", req.validUntilUTC.map { .string($0) } ?? .null),
                    ("observed_at_utc", .string(req.observedAtUTC)),
                ])
            })
        }
        return .object([
            ("payload_schema_id", .string(SRSEncodingConstants.payloadSchemaID)),
            ("logical_key", .object([
                ("identity", .string(logicalKeyIdentity)),
                ("version", .string(logicalKeyVersion)),
            ])),
            ("settled_relation_state", .object([
                ("binding", bindingJSON(settledBinding)),
                ("settlement_id", .string(settlementID)),
                ("status", .string(settlementStatus.rawValue)),
                ("source_relation_identity", .string(sourceRelationIdentity)),
                ("result_identity", .string(resultIdentity)),
                ("requires_canonical_identity_rule", .bool(requiresCanonicalIdentityRule)),
                ("canonical_identity_rule", bindingJSON(canonicalIdentityRule)),
                ("provenance_bindings", bindingsJSON(settledProvenanceBindings, sortCanonical: true)),
            ])),
            ("source_relation", .object([
                ("binding", bindingJSON(sourceBinding)),
                ("semantic_binding", bindingJSON(sourceSemanticBinding)),
                ("applicability_coverage", bindingJSON(sourceApplicabilityCoverage)),
                ("invalidation_record", bindingJSON(sourceInvalidationRecord)),
                ("invalidation_status", .string(sourceInvalidationStatus.rawValue)),
                ("identity_rule", bindingJSON(sourceIdentityRule)),
                ("status", .string(sourceStatus.rawValue)),
            ])),
            ("dependency_set", .object([
                ("boundary", bindingJSON(dependencyBoundary)),
                ("dependencies", depItems.map { .array($0) } ?? .null),
            ])),
            ("result", .object([
                ("binding", bindingJSON(resultBinding)),
                ("resolution", .string(resultResolution.rawValue)),
                ("interpretability_evidence", bindingJSON(interpretabilityEvidence)),
                ("status", .string(resultStatus.rawValue)),
            ])),
            ("provenance", .object([
                ("bindings", bindingsJSON(provenanceBindings, sortCanonical: true)),
                ("lifecycle", .string(provenanceLifecycle.rawValue)),
                ("boundary", bindingJSON(provenanceBoundary)),
            ])),
            ("lifecycle", .object([
                ("bindings", bindingsJSON(lifecycleBindings, sortCanonical: true)),
                ("lifecycle", .string(lifecycleStatus.rawValue)),
                ("boundary", bindingJSON(lifecycleBoundary)),
            ])),
            ("freshness", .object([
                ("boundary", bindingJSON(freshnessBoundary)),
                ("requirements", reqItems.map { .array($0) } ?? .null),
            ])),
            ("resolution_policy", .object([
                ("resolution_rule", bindingJSON(resolutionRule)),
                ("policies", bindingsJSON(policies, sortCanonical: true)),
                ("boundary", bindingJSON(policyBoundary)),
            ])),
            ("producer_authorization_reference", .string(producerAuthorizationReference)),
            ("decision_core_binding", .object([
                ("source_commit", .string(SRSEncodingConstants.decisionCoreSourceCommit)),
                ("source_sha256", .string(SRSEncodingConstants.decisionCoreSourceSHA256)),
            ])),
            ("encoding_identity", .string(SRSEncodingConstants.encodingIdentity)),
        ])
    }
}

// MARK: - Canonical payload bytes (I1)

public enum SRSCanonical {
    /// Sort an unordered semantic collection by the UTF-8 bytes of each
    /// element's independent JCS serialization, preserving duplicates.
    static func sortCollection(_ items: [SRSJSONValue]) -> [SRSJSONValue] {
        var indexed = items.enumerated().map { ($0.0, $0.1) }
        indexed.sort {
            let a = SRSJCS.serialize($0.1) ?? []
            let b = SRSJCS.serialize($1.1) ?? []
            if persistentSRSBytesEqual(a, b) { return $0.0 < $1.0 }
            return persistentSRSCompareBytes(a, b)
        }
        return indexed.map { $0.1 }
    }

    public static func payloadBytes(_ record: PersistentSRSRecord) -> [UInt8] {
        SRSJCS.serialize(record.canonicalJSONValue()) ?? []
    }

    public static func payloadDigest(_ payload: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(payload)))
    }

    public static func payloadDigestHex(_ digestRaw: [UInt8]) -> String {
        digestRaw.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Unique production signature trust anchor (Contract v1.8 section 8)

public enum SRSSignature {
    public static let anchorID = "SRSVAL_PRODUCTION_RECORD_INTEGRITY_ANCHOR_V1"
    public static let signatureDomain = "SIMIGO_PERSISTENT_SRS_RECORD_SIGNATURE_V1"
    static let recordTag = "SIMIGO_PERSISTENT_SRS_RECORD_V1"
    static let signerPublicKeyBase64 = "+fG2YJ+YnW1RtsX8bCbukUERvSlIq4fvP7cZcs6+VMI="

    public static var signerPublicKeyRaw: [UInt8] {
        Array(Data(base64Encoded: signerPublicKeyBase64) ?? Data())
    }

    public static func signatureInput(payload: [UInt8]) -> [UInt8] {
        var input: [UInt8] = []
        input.append(contentsOf: Array(signatureDomain.utf8))
        input.append(0x00)
        input.append(contentsOf: Array(recordTag.utf8))
        input.append(0x00)
        input.append(contentsOf: payload)
        input.append(0x00)
        input.append(contentsOf: signerPublicKeyRaw)
        return input
    }

    /// Produce an Ed25519 signature over the frozen signature input. Signing is
    /// separated from verification; verification always uses the unique
    /// production anchor.
    public static func sign(payload: [UInt8], with key: Curve25519.Signing.PrivateKey) -> [UInt8] {
        guard let signature = try? key.signature(for: Data(signatureInput(payload: payload))) else {
            return []
        }
        return Array(signature)
    }

    /// R25 verification against the unique production anchor only.
    public static func verify(signature: [UInt8], payload: [UInt8]) -> Bool {
        guard signerPublicKeyRaw.count == 32,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: Data(signerPublicKeyRaw)) else {
            return false
        }
        return publicKey.isValidSignature(Data(signature), for: Data(signatureInput(payload: payload)))
    }
}

// MARK: - Canonical envelope (I4) and envelope digest (I5)

public struct SRSEnvelope {
    public var logicalKeyIdentity: String
    public var logicalKeyVersion: String
    public var payloadDigestHex: String
    public var signerPublicKeyRaw: [UInt8]
    public var signatureRaw: [UInt8]
    public var producerAuthorizationReference: String
    public var decisionCoreSourceCommit: String
    public var decisionCoreSourceSHA256Hex: String

    static let labels: [String] = [
        "envelope_schema_id",
        "storage_format_version",
        "logical_key_identity",
        "logical_key_version",
        "payload_digest_hex",
        "encoding_identity",
        "signature_domain",
        "signer_public_key",
        "signature",
        "producer_authorization_reference",
        "decision_core_source_commit",
        "decision_core_source_sha256",
        "completion_state",
    ]

    public func values() -> [[UInt8]] {
        [
            Array(SRSEncodingConstants.envelopeSchemaID.utf8),
            Array(SRSEncodingConstants.storageFormatVersion.utf8),
            Array(logicalKeyIdentity.utf8),
            Array(logicalKeyVersion.utf8),
            Array(payloadDigestHex.utf8),
            Array(SRSEncodingConstants.encodingIdentity.utf8),
            Array(SRSSignature.signatureDomain.utf8),
            signerPublicKeyRaw,
            signatureRaw,
            Array(producerAuthorizationReference.utf8),
            Array(decisionCoreSourceCommit.utf8),
            Array(decisionCoreSourceSHA256Hex.utf8),
            Array(SRSEncodingConstants.completionState.utf8),
        ]
    }

    public static func encode(_ envelope: SRSEnvelope) -> [UInt8] {
        let labels = Self.labels
        let values = envelope.values()
        var out: [UInt8] = []
        func appendU16(_ v: UInt16) {
            out.append(UInt8(v >> 8 & 0xFF)); out.append(UInt8(v & 0xFF))
        }
        func appendU32(_ v: UInt32) {
            out.append(UInt8(v >> 24 & 0xFF)); out.append(UInt8(v >> 16 & 0xFF))
            out.append(UInt8(v >> 8 & 0xFF)); out.append(UInt8(v & 0xFF))
        }
        func appendU64(_ v: UInt64) {
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8(v >> UInt64(shift) & 0xFF))
            }
        }
        appendU32(UInt32(labels.count))
        for (i, label) in labels.enumerated() {
            let labelBytes = Array(label.utf8)
            appendU16(UInt16(labelBytes.count))
            out.append(contentsOf: labelBytes)
            appendU64(UInt64(values[i].count))
            out.append(contentsOf: values[i])
        }
        return out
    }

    /// Strict decode: exactly 13 ordered fields with exact labels; no trailing
    /// bytes. Returns raw field values in fixed order.
    public static func decode(_ bytes: [UInt8]) -> Result<[[UInt8]], PersistentSRSStatus> {
        func readU32(_ b: [UInt8], _ offset: inout Int) -> UInt32? {
            guard offset + 4 <= b.count else { return nil }
            var v: UInt32 = 0
            for _ in 0..<4 { v = v << 8 | UInt32(b[offset]); offset += 1 }
            return v
        }
        func readU64(_ b: [UInt8], _ offset: inout Int) -> UInt64? {
            guard offset + 8 <= b.count else { return nil }
            var v: UInt64 = 0
            for _ in 0..<8 { v = v << 8 | UInt64(b[offset]); offset += 1 }
            return v
        }
        var pos = 0
        guard let count = readU32(bytes, &pos), count == 13 else {
            return .failure(.nonCanonicalEnvelope)
        }
        var values: [[UInt8]] = []
        for expected in Self.labels {
            guard pos + 2 <= bytes.count else { return .failure(.nonCanonicalEnvelope) }
            let labelLen = Int(bytes[pos]) << 8 | Int(bytes[pos + 1])
            pos += 2
            guard pos + labelLen <= bytes.count else { return .failure(.nonCanonicalEnvelope) }
            let label = String(bytes: bytes[pos..<pos + labelLen], encoding: .utf8)
            guard label == expected else { return .failure(.nonCanonicalEnvelope) }
            pos += labelLen
            guard let valueLen = readU64(bytes, &pos), valueLen <= UInt64(SRSEncodingConstants.maxEnvelopeBytes) else {
                return .failure(.nonCanonicalEnvelope)
            }
            guard pos + Int(valueLen) <= bytes.count else { return .failure(.nonCanonicalEnvelope) }
            values.append(Array(bytes[pos..<pos + Int(valueLen)]))
            pos += Int(valueLen)
        }
        guard pos == bytes.count else { return .failure(.nonCanonicalEnvelope) }
        return .success(values)
    }

    public static func envelopeDigest(canonicalEnvelopeBytes: [UInt8]) -> [UInt8] {
        var input: [UInt8] = Array("SIMIGO_PERSISTENT_SRS_ENVELOPE_DIGEST_V1".utf8)
        input.append(0x00)
        input.append(contentsOf: canonicalEnvelopeBytes)
        return Array(SHA256.hash(data: Data(input)))
    }
}

// MARK: - Physical frame (P0)

public struct SRSFrame {
    public var payloadBytes: [UInt8]
    public var envelopeBytes: [UInt8]
    public var payloadDigestRaw: [UInt8]
    public var envelopeDigestRaw: [UInt8]

    public static func encode(_ frame: SRSFrame) -> [UInt8] {
        var out: [UInt8] = []
        out.append(contentsOf: Array(SRSEncodingConstants.magicStart.utf8))
        func appendU32(_ v: UInt32) {
            out.append(UInt8(v >> 24 & 0xFF)); out.append(UInt8(v >> 16 & 0xFF))
            out.append(UInt8(v >> 8 & 0xFF)); out.append(UInt8(v & 0xFF))
        }
        func appendU64(_ v: UInt64) {
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8(v >> UInt64(shift) & 0xFF))
            }
        }
        appendU32(SRSEncodingConstants.physicalVersion)
        appendU64(UInt64(frame.payloadBytes.count))
        appendU64(UInt64(frame.envelopeBytes.count))
        out.append(contentsOf: frame.payloadDigestRaw)
        out.append(contentsOf: frame.payloadBytes)
        out.append(contentsOf: frame.envelopeBytes)
        out.append(contentsOf: frame.envelopeDigestRaw)
        out.append(contentsOf: Array(SRSEncodingConstants.magicEnd.utf8))
        return out
    }
}

// MARK: - Reader pipeline (R1-R30, Contract v1.8 section 13)

public struct SRSVerifiedRecord: Equatable, Sendable {
    public var logicalKeyIdentity: String
    public var logicalKeyVersion: String
    public var payloadBytes: [UInt8]
    public var payloadDigestRaw: [UInt8]

    public var logicalKeyBytes: ([UInt8], [UInt8]) {
        (persistentSRSUTF8Bytes(logicalKeyIdentity), persistentSRSUTF8Bytes(logicalKeyVersion))
    }
}

public enum SRSReader {
    /// Execute reader checks R1-R29. R28 checks the path against the authorized
    /// root. When `performUniquenessScan` is false, R29 is skipped (used by the
    /// writer's W3 classification, which runs the scan separately).
    public static func read(
        data: [UInt8],
        path: URL,
        authorizedRoot: URL,
        performUniquenessScan: Bool
    ) -> Result<SRSVerifiedRecord, PersistentSRSStatus> {
        // R28 evidence location is authorized (checked first by contract order:
        // R28 runs after R1-R27, but the root comparison is order-independent
        // metadata; it is enforced below at its contract position).
        func authorizedLocation() -> Bool {
            let rootPath = authorizedRoot.standardizedFileURL.path
            let filePath = path.standardizedFileURL.path
            return filePath.hasPrefix(rootPath + "/")
        }

        // R1
        guard data.count >= 108 else { return .failure(.truncatedRecord) }
        // R2
        let startMagic = Array(SRSEncodingConstants.magicStart.utf8)
        guard Array(data[0..<12]) == startMagic else { return .failure(.magicStartMismatch) }
        // R3
        let version = UInt32(data[12]) << 24 | UInt32(data[13]) << 16 | UInt32(data[14]) << 8 | UInt32(data[15])
        guard version == SRSEncodingConstants.physicalVersion else { return .failure(.unknownPhysicalFormatVersion) }
        // R4 (checked arithmetic on lengths)
        var payloadLen: UInt64 = 0
        var envelopeLen: UInt64 = 0
        for i in 0..<8 { payloadLen = payloadLen << 8 | UInt64(data[16 + i]) }
        for i in 0..<8 { envelopeLen = envelopeLen << 8 | UInt64(data[24 + i]) }
        guard payloadLen <= UInt64(SRSEncodingConstants.maxPayloadBytes),
              envelopeLen <= UInt64(SRSEncodingConstants.maxEnvelopeBytes),
              payloadLen <= UInt64(Int.max), envelopeLen <= UInt64(Int.max),
              108 <= Int.max - Int(payloadLen) - Int(envelopeLen) else {
            return .failure(.integerOverflowOrResourceLimit)
        }
        // R5 (limits)
        guard 108 + Int(payloadLen) + Int(envelopeLen) <= SRSEncodingConstants.maxTotalBytes else {
            return .failure(.integerOverflowOrResourceLimit)
        }
        let declaredTotal = 108 + Int(payloadLen) + Int(envelopeLen)
        // R6
        guard declaredTotal <= data.count else { return .failure(.physicalLengthMismatch) }
        // R7
        let endMagic = Array(SRSEncodingConstants.magicEnd.utf8)
        guard Array(data[(declaredTotal - 12)..<declaredTotal]) == endMagic else {
            return .failure(.magicEndMismatch)
        }
        // R8
        guard data.count == declaredTotal else { return .failure(.trailingDataAfterRecord) }

        let headerDigestStart = 32
        let payloadDigestRaw = Array(data[headerDigestStart..<headerDigestStart + 32])
        let payloadStart = 64
        let payloadEnd = payloadStart + Int(payloadLen)
        let envelopeStart = payloadEnd
        let envelopeEnd = envelopeStart + Int(envelopeLen)
        let payload = Array(data[payloadStart..<payloadEnd])
        let envelope = Array(data[envelopeStart..<envelopeEnd])
        let envelopeDigestRaw = Array(data[envelopeEnd..<envelopeEnd + 32])

        // R9-R13 envelope structure and exact values.
        let envelopeFields: [[UInt8]]
        switch SRSEnvelope.decode(envelope) {
        case .success(let v): envelopeFields = v
        case .failure(let s): return .failure(s)
        }
        func fieldString(_ i: Int) -> String? {
            String(bytes: envelopeFields[i], encoding: .utf8)
        }
        guard fieldString(0) == SRSEncodingConstants.envelopeSchemaID else { return .failure(.unknownEnvelopeSchema) }
        guard fieldString(1) == SRSEncodingConstants.storageFormatVersion else { return .failure(.unknownStorageFormatVersion) }
        guard fieldString(5) == SRSEncodingConstants.encodingIdentity else { return .failure(.encodingIdentityMismatch) }
        guard fieldString(12) == SRSEncodingConstants.completionState else { return .failure(.completionStateInvalid) }
        let envKeyIdentity = fieldString(2) ?? ""
        let envKeyVersion = fieldString(3) ?? ""

        // R15 payload UTF-8 validity
        guard String(bytes: payload, encoding: .utf8) != nil else { return .failure(.invalidJSONUTF8) }
        // R16 strict JSON syntax
        let jsonValue: SRSJSONValue
        switch SRSStrictJSONParser.parse(payload) {
        case .success(let v): jsonValue = v
        case .failure(let e):
            switch e {
            case .depthLimitExceeded: return .failure(.jsonDepthLimitExceeded)
            case .duplicateMember: return .failure(.duplicateJSONMember)
            case .resourceLimit: return .failure(.integerOverflowOrResourceLimit)
            case .syntax: return .failure(.invalidJSONSyntax)
            }
        }
        // R17-R19 closed schema validation (decode performs R17 member/type and
        // R18/R19 const checks).
        let record: PersistentSRSRecord
        do {
            record = try PersistentSRSRecord.decode(jsonValue)
        } catch let e as SRSDecodeError {
            switch e {
            case .fail(let s): return .failure(s)
            }
        } catch {
            return .failure(.persistenceVerificationIndeterminate)
        }
        // R20 strict UTC calendar validity.
        if let reqs = record.freshnessRequirements {
            for req in reqs {
                guard SRSStrictUTC.isValid(req.observedAtUTC) else { return .failure(.invalidUTCTimestamp) }
                if let vu = req.validUntilUTC, !SRSStrictUTC.isValid(vu) {
                    return .failure(.invalidUTCTimestamp)
                }
            }
        }
        // R21 canonical byte equality.
        let canonical = SRSCanonical.payloadBytes(record)
        guard persistentSRSBytesEqual(canonical, payload) else { return .failure(.nonCanonicalPayloadBytes) }
        // R22 header digest equals envelope digest.
        guard fieldString(4) == SRSCanonical.payloadDigestHex(payloadDigestRaw) else {
            return .failure(.payloadDigestMismatch)
        }
        // R23 recomputed payload digest equals that digest.
        let recomputedPayloadDigest = SRSCanonical.payloadDigest(payload)
        guard persistentSRSBytesEqual(recomputedPayloadDigest, payloadDigestRaw) else {
            return .failure(.payloadDigestMismatch)
        }
        // R24 envelope digest.
        let recomputedEnvelopeDigest = SRSEnvelope.envelopeDigest(canonicalEnvelopeBytes: envelope)
        guard persistentSRSBytesEqual(recomputedEnvelopeDigest, envelopeDigestRaw) else {
            return .failure(.envelopeDigestMismatch)
        }
        // R25 signature: domain/signer exactness enforced by envelope value
        // equality, then Ed25519 verification against the unique anchor.
        guard Array(envelopeFields[6]) == Array(SRSSignature.signatureDomain.utf8),
              envelopeFields[7] == SRSSignature.signerPublicKeyRaw,
              envelopeFields[8].count == 64,
              SRSSignature.verify(signature: envelopeFields[8], payload: payload) else {
            return .failure(.signatureVerificationFailed)
        }
        // R26 producer reference equals I0.
        guard fieldString(9) == record.producerAuthorizationReference else {
            return .failure(.producerAuthorizationReferenceMismatch)
        }
        // R27 Decision Core binding equals I0 and frozen values.
        guard fieldString(10) == SRSEncodingConstants.decisionCoreSourceCommit,
              fieldString(11) == SRSEncodingConstants.decisionCoreSourceSHA256 else {
            return .failure(.decisionCoreBindingMismatch)
        }
        // R14 envelope logical key equals I0 logical key by exact UTF-8 bytes.
        guard persistentSRSBytesEqual(persistentSRSUTF8Bytes(envKeyIdentity), persistentSRSUTF8Bytes(record.logicalKeyIdentity)),
              persistentSRSBytesEqual(persistentSRSUTF8Bytes(envKeyVersion), persistentSRSUTF8Bytes(record.logicalKeyVersion)) else {
            return .failure(.envelopeLogicalKeyMismatch)
        }
        // R28 evidence location authorized.
        guard authorizedLocation() else { return .failure(.evidenceLocationUnauthorized) }
        let verified = SRSVerifiedRecord(
            logicalKeyIdentity: record.logicalKeyIdentity,
            logicalKeyVersion: record.logicalKeyVersion,
            payloadBytes: payload,
            payloadDigestRaw: payloadDigestRaw
        )
        // R29 ordered logical-key uniqueness scan.
        if performUniquenessScan {
            switch uniquenessScan(authorizedRoot: authorizedRoot, excludePath: path, proposed: verified) {
            case .success: break
            case .failure(let s): return .failure(s)
            }
        }
        // R30
        return .success(verified)
    }

    /// R29: scan all final records in root/records for the proposed ordered
    /// logical key. Fail-closed on any record that cannot be fully verified.
    public static func uniquenessScan(
        authorizedRoot: URL,
        excludePath: URL,
        proposed: SRSVerifiedRecord
    ) -> Result<Void, PersistentSRSStatus> {
        let recordsDir = authorizedRoot.appendingPathComponent("records", isDirectory: true)
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: recordsDir, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "psrs" }
        } catch {
            // A missing records directory with only the proposed record present
            // is still exclusive; any other directory error is indeterminate.
            if (error as NSError).code == NSFileReadNoSuchFileError { return .success(()) }
            return .failure(.persistenceVerificationIndeterminate)
        }
        var sameKeyCount = 0
        for file in files {
            if file.standardizedFileURL.path == excludePath.standardizedFileURL.path { continue }
            guard let rawData = try? Data(contentsOf: file), rawData.count <= SRSEncodingConstants.maxTotalBytes else {
                return .failure(.persistenceVerificationIndeterminate)
            }
            let other = Array(rawData)
            // Every scanned record must independently pass R1-R28 before its
            // logical key can be trusted (fail-closed).
            let otherVerified: SRSVerifiedRecord
            switch read(data: other, path: file, authorizedRoot: authorizedRoot, performUniquenessScan: false) {
            case .success(let v): otherVerified = v
            case .failure: return .failure(.persistenceVerificationIndeterminate)
            }
            if otherVerified.logicalKeyBytes == proposed.logicalKeyBytes {
                sameKeyCount += 1
                // Two final records sharing one ordered logical key is a
                // duplicate record state regardless of byte equality.
                return .failure(.persistentDuplicateRecordState)
            }
        }
        if sameKeyCount > 1 { return .failure(.persistentDuplicateRecordState) }
        return .success(())
    }
}

// MARK: - Shared write classification (production logic used by W3 and tests)

public enum SRSWriteClassification: Equatable, Sendable {
    case newRecord
    case existingEquivalentRecord
    case persistentLogicalKeyConflict
    case recordContentIdentityMismatch
}

public enum SRSWriteClassifier {
    /// Shared pure classification used by the production write path (W3) and
    /// the V-PERSIST-21 test-only caller. Inputs are already-verified
    /// descriptors; no filesystem effect occurs here.
    public static func classify(
        existingLogicalKey: (identity: [UInt8], version: [UInt8])?,
        existingPayload: [UInt8]?,
        proposedLogicalKey: (identity: [UInt8], version: [UInt8]),
        proposedPayload: [UInt8]
    ) -> SRSWriteClassification {
        guard let existingKey = existingLogicalKey, let existingPayload else {
            return .newRecord
        }
        if existingKey != proposedLogicalKey {
            return .recordContentIdentityMismatch
        }
        if persistentSRSBytesEqual(existingPayload, proposedPayload) {
            return .existingEquivalentRecord
        }
        return .persistentLogicalKeyConflict
    }
}

// MARK: - Writer (W1-W16, Contract v1.8 section 14)

public enum SRSWriteOutcome: Equatable, Sendable {
    case created
    case idempotentComplete
}

public enum SRSWriteResult: Equatable, Sendable {
    case success(SRSWriteOutcome)
    case failure(PersistentSRSStatus)
}

public enum SRSWriter {
    public static func write(
        record: PersistentSRSRecord,
        signingKey: Curve25519.Signing.PrivateKey,
        root: URL
    ) -> SRSWriteResult {
        let recordsDir = root.appendingPathComponent("records", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: recordsDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.persistenceVerificationIndeterminate)
        }

        // W1: acquire the exclusive writer lock (flock on root/.writer.lock).
        let lockPath = root.appendingPathComponent(".writer.lock")
        let fd = open(lockPath.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return .failure(.persistenceVerificationIndeterminate) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return .failure(.persistentConcurrentWriteIndeterminate) }
        defer { flock(fd, LOCK_UN) }

        // W7 prerequisite values.
        let payload = SRSCanonical.payloadBytes(record)
        let payloadDigest = SRSCanonical.payloadDigest(payload)
        let digestHex = SRSCanonical.payloadDigestHex(payloadDigest)
        let targetPath = recordsDir.appendingPathComponent("\(digestHex).psrs")

        // W2/W3: inspect an existing proposed content path if present.
        var classification = SRSWriteClassification.newRecord
        var equivalentExistingPath: URL?
        if FileManager.default.fileExists(atPath: targetPath.path) {
            guard let rawData = try? Data(contentsOf: targetPath),
                  rawData.count <= SRSEncodingConstants.maxTotalBytes else {
                return .failure(.persistenceVerificationIndeterminate)
            }
            let existingBytes = Array(rawData)
            // R1-R28 on that exact path before classification.
            let existingVerified: SRSVerifiedRecord
            switch SRSReader.read(data: existingBytes, path: targetPath, authorizedRoot: root, performUniquenessScan: false) {
            case .success(let v): existingVerified = v
            case .failure(let s): return .failure(s)
            }
            classification = SRSWriteClassifier.classify(
                existingLogicalKey: existingVerified.logicalKeyBytes,
                existingPayload: existingVerified.payloadBytes,
                proposedLogicalKey: (persistentSRSUTF8Bytes(record.logicalKeyIdentity), persistentSRSUTF8Bytes(record.logicalKeyVersion)),
                proposedPayload: payload
            )
            if classification == .existingEquivalentRecord {
                equivalentExistingPath = targetPath
            }
        }

        switch classification {
        case .recordContentIdentityMismatch:
            // Section 14.2: final, no retry, no rename, no delete.
            return .failure(.recordContentIdentityMismatch)
        case .persistentLogicalKeyConflict:
            return .failure(.persistentLogicalKeyConflict)
        case .existingEquivalentRecord:
            // W4-W9: verify the existing record completely, then report
            // IDEMPOTENT_COMPLETE. Never overwrite, stage, or delete.
            guard let existingPath = equivalentExistingPath,
                  let rawData = try? Data(contentsOf: existingPath) else {
                return .failure(.persistenceVerificationIndeterminate)
            }
            switch SRSReader.read(data: Array(rawData), path: existingPath, authorizedRoot: root, performUniquenessScan: true) {
            case .success:
                return .success(.idempotentComplete)
            case .failure(let s):
                return .failure(s)
            }
        case .newRecord:
            // Scan all other final records for the proposed logical key.
            if FileManager.default.fileExists(atPath: targetPath.path) {
                return .failure(.persistenceVerificationIndeterminate)
            }
            let recordsDirFiles = (try? FileManager.default.contentsOfDirectory(at: recordsDir, includingPropertiesForKeys: nil)) ?? []
            var sameKeyExisting: SRSVerifiedRecord?
            for file in recordsDirFiles where file.pathExtension == "psrs" {
                guard let rawData = try? Data(contentsOf: file),
                      rawData.count <= SRSEncodingConstants.maxTotalBytes else {
                    return .failure(.persistenceVerificationIndeterminate)
                }
                let otherVerified: SRSVerifiedRecord
                switch SRSReader.read(data: Array(rawData), path: file, authorizedRoot: root, performUniquenessScan: false) {
                case .success(let v): otherVerified = v
                case .failure(let s): return .failure(s)
                }
                if otherVerified.logicalKeyBytes == (persistentSRSUTF8Bytes(record.logicalKeyIdentity), persistentSRSUTF8Bytes(record.logicalKeyVersion)) {
                    if sameKeyExisting != nil { return .failure(.persistentDuplicateRecordState) }
                    sameKeyExisting = otherVerified
                }
            }
            if let existing = sameKeyExisting {
                // W3 same-key branch against a different physical record.
                let cls = SRSWriteClassifier.classify(
                    existingLogicalKey: existing.logicalKeyBytes,
                    existingPayload: existing.payloadBytes,
                    proposedLogicalKey: (persistentSRSUTF8Bytes(record.logicalKeyIdentity), persistentSRSUTF8Bytes(record.logicalKeyVersion)),
                    proposedPayload: payload
                )
                switch cls {
                case .existingEquivalentRecord:
                    return .success(.idempotentComplete)
                case .persistentLogicalKeyConflict:
                    return .failure(.persistentLogicalKeyConflict)
                default:
                    return .failure(.persistenceVerificationIndeterminate)
                }
            }

            // W7: construct I0-I5 exactly.
            let signature = SRSSignature.sign(payload: payload, with: signingKey)
            guard signature.count == 64 else { return .failure(.persistenceVerificationIndeterminate) }
            let envelope = SRSEnvelope(
                logicalKeyIdentity: record.logicalKeyIdentity,
                logicalKeyVersion: record.logicalKeyVersion,
                payloadDigestHex: digestHex,
                signerPublicKeyRaw: SRSSignature.signerPublicKeyRaw,
                signatureRaw: signature,
                producerAuthorizationReference: record.producerAuthorizationReference,
                decisionCoreSourceCommit: SRSEncodingConstants.decisionCoreSourceCommit,
                decisionCoreSourceSHA256Hex: SRSEncodingConstants.decisionCoreSourceSHA256
            )
            let envelopeBytes = SRSEnvelope.encode(envelope)
            let envelopeDigest = SRSEnvelope.envelopeDigest(canonicalEnvelopeBytes: envelopeBytes)
            let frame = SRSFrame(
                payloadBytes: payload,
                envelopeBytes: envelopeBytes,
                payloadDigestRaw: payloadDigest,
                envelopeDigestRaw: envelopeDigest
            )
            let frameBytes = SRSFrame.encode(frame)

            // W9-W11: staging in the same root, then atomic rename.
            let stagingPath = root.appendingPathComponent("staging", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: stagingPath, withIntermediateDirectories: true)
                let stageFile = stagingPath.appendingPathComponent(UUID().uuidString + ".tmp")
                try Data(frameBytes).write(to: stageFile)
                if FileManager.default.fileExists(atPath: targetPath.path) {
                    // Target appeared after W3 under the same lock: repeat
                    // classification rather than renaming over it.
                    try? FileManager.default.removeItem(at: stageFile)
                    return .failure(.persistentConcurrentWriteIndeterminate)
                }
                try FileManager.default.moveItem(at: stageFile, to: targetPath)
            } catch {
                return .failure(.persistenceVerificationIndeterminate)
            }

            // W13-W16: reopen final path and execute R1-R29.
            guard let written = try? Data(contentsOf: targetPath) else {
                return .failure(.persistenceVerificationIndeterminate)
            }
            switch SRSReader.read(data: Array(written), path: targetPath, authorizedRoot: root, performUniquenessScan: true) {
            case .success:
                return .success(.created)
            case .failure(let s):
                return .failure(s)
            }
        }
    }
}

// MARK: - Immutable attempt evidence records (Manifest v2.2 section 9)

public struct SRSAttemptEvidenceInput: Equatable, Sendable {
    public var attemptID: String
    public var matrixScenario: String
    public var batchIdentity: String
    public var humanAuthorizationRecord: String
    public var fixtureDigest: String
    public var completedAtUTC: String
    public var operationOutcome: String
    public var scenarioVerdict: String
    public var runtimeBindingsJSON: SRSJSONValue
    public var observerAuthorizationReference: String?
    public var startStopEvidenceJSON: SRSJSONValue
    public var outputTypedFailureEvidenceJSON: SRSJSONValue?

    public init(attemptID: String, matrixScenario: String, batchIdentity: String,
                humanAuthorizationRecord: String, fixtureDigest: String,
                completedAtUTC: String, operationOutcome: String, scenarioVerdict: String,
                runtimeBindingsJSON: SRSJSONValue, observerAuthorizationReference: String?,
                startStopEvidenceJSON: SRSJSONValue, outputTypedFailureEvidenceJSON: SRSJSONValue?) {
        self.attemptID = attemptID
        self.matrixScenario = matrixScenario
        self.batchIdentity = batchIdentity
        self.humanAuthorizationRecord = humanAuthorizationRecord
        self.fixtureDigest = fixtureDigest
        self.completedAtUTC = completedAtUTC
        self.operationOutcome = operationOutcome
        self.scenarioVerdict = scenarioVerdict
        self.runtimeBindingsJSON = runtimeBindingsJSON
        self.observerAuthorizationReference = observerAuthorizationReference
        self.startStopEvidenceJSON = startStopEvidenceJSON
        self.outputTypedFailureEvidenceJSON = outputTypedFailureEvidenceJSON
    }
}

public struct SRSAttemptSealedEvidence: Equatable, Sendable {
    public var coreCanonicalData: [UInt8]
    public var baseEvidenceDigest: [UInt8]
    public var baseEvidenceDigestHex: String
    public var completionOrderKeyValue: [UInt8]
    public var sealedCanonicalData: [UInt8]
    public var evidenceDigest: [UInt8]
}

public enum SRSAttemptEvidence {
    static let coreMagic = "SIMISRS-ACORE-V1"
    static let sealedMagic = "SIMISRS-ASEALED-V1"
    static let orderKeyMagic = "SIMISRS-AKEY-V1"
    static let coreCoreFieldCount: UInt32 = 12
    static let sealedFieldCount: UInt32 = 14
    static let coreFieldLabels: [String] = [
        "attempt_id", "matrix_scenario", "batch_identity", "human_authorization_record",
        "fixture_digest", "completed_at_utc", "operation_outcome", "scenario_verdict",
        "implementation_runtime_environment_bindings", "observer_authorization_reference",
        "start_stop_evidence", "output_and_typed_failure_evidence",
    ]

    // Value types: 0x00 NULL, 0x01 BOOLEAN, 0x02 UTF8, 0x03 JSON, 0x04 BYTES,
    // 0x05 COMPLETION_ORDER_KEY_V1.
    static func field(_ label: String, type: UInt8, value: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        let labelBytes = Array(label.utf8)
        out.append(UInt8(labelBytes.count >> 8 & 0xFF))
        out.append(UInt8(labelBytes.count & 0xFF))
        out.append(contentsOf: labelBytes)
        out.append(type)
        for shift in stride(from: 56, through: 0, by: -8) {
            out.append(UInt8(UInt64(value.count) >> UInt64(shift) & 0xFF))
        }
        out.append(contentsOf: value)
        return out
    }

    static func appendU32(_ out: inout [UInt8], _ v: UInt32) {
        out.append(UInt8(v >> 24 & 0xFF)); out.append(UInt8(v >> 16 & 0xFF))
        out.append(UInt8(v >> 8 & 0xFF)); out.append(UInt8(v & 0xFF))
    }

    static func coreCanonicalData(_ input: SRSAttemptEvidenceInput) -> [UInt8]? {
        func stringValue(_ s: String) -> [UInt8] { Array(s.utf8) }
        func jsonValue(_ v: SRSJSONValue) -> [UInt8]? { SRSJCS.serialize(v) }
        var fields: [[UInt8]] = []
        func append(_ label: String, _ type: UInt8, _ value: [UInt8]) { fields.append(field(label, type: type, value: value)) }
        append("attempt_id", 0x02, stringValue(input.attemptID))
        append("matrix_scenario", 0x02, stringValue(input.matrixScenario))
        append("batch_identity", 0x02, stringValue(input.batchIdentity))
        append("human_authorization_record", 0x02, stringValue(input.humanAuthorizationRecord))
        append("fixture_digest", 0x02, stringValue(input.fixtureDigest))
        append("completed_at_utc", 0x02, stringValue(input.completedAtUTC))
        append("operation_outcome", 0x02, stringValue(input.operationOutcome))
        append("scenario_verdict", 0x02, stringValue(input.scenarioVerdict))
        guard let rb = jsonValue(input.runtimeBindingsJSON) else { return nil }
        append("implementation_runtime_environment_bindings", 0x03, rb)
        if let obs = input.observerAuthorizationReference {
            append("observer_authorization_reference", 0x02, stringValue(obs))
        } else {
            append("observer_authorization_reference", 0x00, [])
        }
        guard let ss = jsonValue(input.startStopEvidenceJSON) else { return nil }
        append("start_stop_evidence", 0x03, ss)
        if let of = input.outputTypedFailureEvidenceJSON {
            guard let ofb = jsonValue(of) else { return nil }
            append("output_and_typed_failure_evidence", 0x03, ofb)
        } else {
            append("output_and_typed_failure_evidence", 0x00, [])
        }
        var out: [UInt8] = Array(coreMagic.utf8)
        appendU32(&out, coreCoreFieldCount)
        for f in fields { out.append(contentsOf: f) }
        return out
    }

    static func baseEvidenceDigest(coreCanonicalData: [UInt8]) -> [UInt8] {
        var input: [UInt8] = Array("SIMIGO_PERSISTENT_SRS_ATTEMPT_CORE_V1".utf8)
        input.append(0x00)
        input.append(contentsOf: coreCanonicalData)
        return Array(SHA256.hash(data: Data(input)))
    }

    /// completion_order_key_value. Fractional digits use exact supplied digits;
    /// the order key is independent of base digest computation.
    static func completionOrderKey(
        completedAtUTC: String, baseDigestHex: String, attemptID: String,
        fractionalDigits: String
    ) -> [UInt8]? {
        guard SRSStrictUTC.isValid(completedAtUTC) else { return nil }
        let b = Array(completedAtUTC.utf8)
        func num(_ r: Range<Int>) -> Int {
            var v = 0
            for i in r { v = v * 10 + Int(b[i] - UInt8(ascii: "0")) }
            return v
        }
        let year = num(0..<4)
        let month = num(5..<7)
        let day = num(8..<10)
        let hour = num(11..<13)
        let minute = num(14..<16)
        let second = num(17..<19)
        var out: [UInt8] = Array(orderKeyMagic.utf8)
        out.append(UInt8(year >> 8 & 0xFF)); out.append(UInt8(year & 0xFF))
        out.append(UInt8(month)); out.append(UInt8(day))
        out.append(UInt8(hour)); out.append(UInt8(minute)); out.append(UInt8(second))
        let fracDigits = Array(fractionalDigits.utf8)
        appendU32(&out, UInt32(fracDigits.count))
        out.append(contentsOf: fracDigits)
        out.append(contentsOf: Array(baseDigestHex.utf8))
        let attemptBytes = Array(attemptID.utf8)
        for shift in stride(from: 56, through: 0, by: -8) {
            out.append(UInt8(UInt64(attemptBytes.count) >> UInt64(shift) & 0xFF))
        }
        out.append(contentsOf: attemptBytes)
        return out
    }

    public static func build(_ input: SRSAttemptEvidenceInput, fractionalDigits: String = "") -> Result<SRSAttemptSealedEvidence, PersistentSRSStatus> {
        guard let core = coreCanonicalData(input) else {
            return .failure(.attemptCanonicalEncodingMismatch)
        }
        let base = baseEvidenceDigest(coreCanonicalData: core)
        let baseHex = base.map { String(format: "%02x", $0) }.joined()
        guard let orderKey = completionOrderKey(
            completedAtUTC: input.completedAtUTC, baseDigestHex: baseHex,
            attemptID: input.attemptID, fractionalDigits: fractionalDigits
        ) else {
            return .failure(.invalidCompletionOrderKey)
        }
        var sealed: [UInt8] = Array(sealedMagic.utf8)
        appendU32(&sealed, sealedFieldCount)
        // Drop the core magic AND its own field_count (12); the sealed header
        // carries field_count 14 followed by the 12 core fields.
        sealed.append(contentsOf: core.dropFirst(Array(coreMagic.utf8).count + 4))
        sealed.append(contentsOf: field("base_evidence_digest", type: 0x02, value: Array(baseHex.utf8)))
        sealed.append(contentsOf: field("completion_order_key", type: 0x05, value: orderKey))
        var digestInput: [UInt8] = Array("SIMIGO_PERSISTENT_SRS_ATTEMPT_SEALED_V1".utf8)
        digestInput.append(0x00)
        digestInput.append(contentsOf: sealed)
        let evidenceDigest = Array(SHA256.hash(data: Data(digestInput)))
        return .success(SRSAttemptSealedEvidence(
            coreCanonicalData: core,
            baseEvidenceDigest: base,
            baseEvidenceDigestHex: baseHex,
            completionOrderKeyValue: orderKey,
            sealedCanonicalData: sealed,
            evidenceDigest: evidenceDigest
        ))
    }

    /// V1-V5 evidence verification over sealed canonical bytes.
    public static func verify(sealed: [UInt8], claimedEvidenceDigest: [UInt8]) -> Result<Void, PersistentSRSStatus> {
        // V1: parse shape, magic, count, order, types; no trailing bytes.
        let magicBytes = Array(sealedMagic.utf8)
        guard sealed.count > magicBytes.count + 4 else { return .failure(.attemptCanonicalEncodingMismatch) }
        guard Array(sealed[0..<magicBytes.count]) == magicBytes else { return .failure(.attemptCanonicalEncodingMismatch) }
        var pos = magicBytes.count
        var count: UInt32 = 0
        for _ in 0..<4 { count = count << 8 | UInt32(sealed[pos]); pos += 1 }
        guard count == sealedFieldCount else { return .failure(.attemptCanonicalEncodingMismatch) }
        struct ParsedField {
            var label: String
            var type: UInt8
            var value: [UInt8]
        }
        var parsed: [ParsedField] = []
        for expected in coreFieldLabels + ["base_evidence_digest", "completion_order_key"] {
            guard pos + 2 <= sealed.count else { return .failure(.attemptCanonicalEncodingMismatch) }
            let labelLen = Int(sealed[pos]) << 8 | Int(sealed[pos + 1])
            pos += 2
            guard pos + labelLen <= sealed.count else { return .failure(.attemptCanonicalEncodingMismatch) }
            guard let label = String(bytes: sealed[pos..<pos + labelLen], encoding: .utf8), label == expected else {
                return .failure(.attemptCanonicalEncodingMismatch)
            }
            pos += labelLen
            guard pos + 1 <= sealed.count else { return .failure(.attemptCanonicalEncodingMismatch) }
            let type = sealed[pos]
            pos += 1
            guard [0x00, 0x01, 0x02, 0x03, 0x04, 0x05].contains(type) else {
                return .failure(.unsupportedCanonicalValueType)
            }
            guard pos + 8 <= sealed.count else { return .failure(.attemptCanonicalEncodingMismatch) }
            var valueLen: UInt64 = 0
            for _ in 0..<8 { valueLen = valueLen << 8 | UInt64(sealed[pos]); pos += 1 }
            guard valueLen <= UInt64(SRSEncodingConstants.maxTotalBytes), pos + Int(valueLen) <= sealed.count else {
                return .failure(.attemptCanonicalEncodingMismatch)
            }
            parsed.append(ParsedField(label: label, type: type, value: Array(sealed[pos..<pos + Int(valueLen)])))
            pos += Int(valueLen)
        }
        guard pos == sealed.count else { return .failure(.attemptCanonicalEncodingMismatch) }
        // V2: recompute base digest from the 12 core fields.
        let coreFields = parsed[0..<12]
        var core = Array(coreMagic.utf8)
        appendU32(&core, coreCoreFieldCount)
        for f in coreFields {
            core.append(contentsOf: field(f.label, type: f.type, value: f.value))
        }
        let recomputedBase = baseEvidenceDigest(coreCanonicalData: core)
        guard parsed[12].type == 0x02, persistentSRSBytesEqual(parsed[12].value, Array(recomputedBase.map { String(format: "%02x", $0) }.joined().utf8)) else {
            return .failure(.attemptEvidenceDigestMismatch)
        }
        // V3: recompute the completion order key.
        func coreStringValue(_ label: String) -> String? {
            guard let f = coreFields.first(where: { $0.label == label }), f.type == 0x02 else { return nil }
            return String(bytes: f.value, encoding: .utf8)
        }
        guard let attemptID = coreStringValue("attempt_id"),
              let completedAt = coreStringValue("completed_at_utc"),
              parsed[13].type == 0x05 else {
            return .failure(.invalidCompletionOrderKey)
        }
        // Extract the exact fractional digits encoded in the stored order key.
        let storedOrderKey = parsed[13].value
        let orderKeyMagicLength = Array(orderKeyMagic.utf8).count
        guard storedOrderKey.count >= orderKeyMagicLength + 11 else {
            return .failure(.invalidCompletionOrderKey)
        }
        let fracBase = orderKeyMagicLength + 7
        let fracCount = Int(storedOrderKey[fracBase]) << 24 | Int(storedOrderKey[fracBase + 1]) << 16
            | Int(storedOrderKey[fracBase + 2]) << 8 | Int(storedOrderKey[fracBase + 3])
        let fracStart = orderKeyMagicLength + 11
        guard fracStart + fracCount <= storedOrderKey.count,
            let fractionalDigits = String(bytes: storedOrderKey[fracStart..<fracStart + fracCount], encoding: .utf8) else {
            return .failure(.invalidCompletionOrderKey)
        }
        guard let recomputedOrderKey = completionOrderKey(
            completedAtUTC: completedAt, baseDigestHex: String(bytes: parsed[12].value, encoding: .utf8) ?? "",
            attemptID: attemptID, fractionalDigits: fractionalDigits
        ), persistentSRSBytesEqual(recomputedOrderKey, parsed[13].value) else {
            return .failure(.invalidCompletionOrderKey)
        }
        // V4/V5: the sealed bytes are the input; recompute the sealed digest.
        var digestInput: [UInt8] = Array("SIMIGO_PERSISTENT_SRS_ATTEMPT_SEALED_V1".utf8)
        digestInput.append(0x00)
        digestInput.append(contentsOf: sealed)
        let recomputedEvidence = Array(SHA256.hash(data: Data(digestInput)))
        guard persistentSRSBytesEqual(recomputedEvidence, claimedEvidenceDigest) else {
            return .failure(.attemptEvidenceDigestMismatch)
        }
        return .success(())
    }
}

// MARK: - Attempt status projection, batch states, budget, closure chain

public enum SRSAttemptEventType: String, Equatable, Sendable {
    case executed = "EXECUTED"
    case failed = "FAILED"
    case excludedByAuthorizedSupersession = "EXCLUDED_BY_AUTHORIZED_SUPERSESSION"
}

public struct SRSAttemptStatusEvent: Equatable, Sendable {
    public var eventID: String
    public var attemptID: String
    public var eventType: SRSAttemptEventType
    public var priorEventID: String?
    public init(eventID: String, attemptID: String, eventType: SRSAttemptEventType, priorEventID: String?) {
        self.eventID = eventID
        self.attemptID = attemptID
        self.eventType = eventType
        self.priorEventID = priorEventID
    }
}

public enum SRSAttemptProjection: String, Sendable {
    case executedActive = "EXECUTED_ACTIVE"
    case failed = "FAILED"
    case excluded = "EXCLUDED"
}

/// Current attempt projection: derived only from the latest valid event for
/// the attempt in the append-only event log order.
public func srsCurrentAttemptProjection(events: [SRSAttemptStatusEvent], attemptID: String) -> SRSAttemptProjection? {
    guard let latest = events.last(where: { $0.attemptID == attemptID }) else { return nil }
    switch latest.eventType {
    case .executed: return .executedActive
    case .failed: return .failed
    case .excludedByAuthorizedSupersession: return .excluded
    }
}

public enum SRSBatchState: String, Equatable, Sendable {
    case active = "ACTIVE"
    case complete = "COMPLETE"
    case superseded = "SUPERSEDED"
    case failedClosed = "FAILED_CLOSED"
}

/// Batch transition rules: FAILED_CLOSED is terminal; SUPERSEDED only from
/// ACTIVE or COMPLETE; COMPLETE only from ACTIVE.
public func srsBatchTransitionAllowed(from: SRSBatchState, to: SRSBatchState) -> Bool {
    switch (from, to) {
    case (.active, .complete), (.active, .superseded), (.complete, .superseded), (.active, .failedClosed):
        return true
    default:
        return false
    }
}

/// Each EXECUTION_BATCH_nn is limited to at most 16 fixture executions.
public func srsBatchBudgetAllows(executedAttemptCount: Int, cap: Int = 16) -> Bool {
    executedAttemptCount <= cap
}

public struct SRSClosureCandidate: Equatable, Sendable {
    public var scenario: String
    public var attemptID: String
    public var completionOrderKeyBytes: [UInt8]
    public init(scenario: String, attemptID: String, completionOrderKeyBytes: [UInt8]) {
        self.scenario = scenario
        self.attemptID = attemptID
        self.completionOrderKeyBytes = completionOrderKeyBytes
    }
}

public enum SRSClosure {
    /// Phase 2 registration: one candidate per scenario in the Candidate
    /// Closure Set; duplicate registration is CLOSURE_DUPLICATE_CANDIDATE.
    public static func registerCandidate(
        _ candidate: SRSClosureCandidate, into set: [SRSClosureCandidate]
    ) -> Result<[SRSClosureCandidate], PersistentSRSStatus> {
        if set.contains(where: { $0.scenario == candidate.scenario }) {
            return .failure(.closureDuplicateCandidate)
        }
        return .success(set + [candidate])
    }

    /// Phase 2 selection: group eligible attempts by scenario, sort ascending
    /// by immutable completion_order_key bytes, select the last element.
    /// Duplicate registration for one scenario is CLOSURE_DUPLICATE_CANDIDATE;
    /// multiple eligible source attempts are normal.
    public static func selectFinalAttempts(_ register: [SRSClosureCandidate]) -> Result<[SRSClosureCandidate], PersistentSRSStatus> {
        var byScenario: [String: [SRSClosureCandidate]] = [:]
        for candidate in register {
            byScenario[candidate.scenario, default: []].append(candidate)
        }
        var selected: [SRSClosureCandidate] = []
        for (scenario, group) in byScenario {
            var group = group
            group.sort {
                if persistentSRSBytesEqual($0.completionOrderKeyBytes, $1.completionOrderKeyBytes) {
                    return $0.attemptID < $1.attemptID
                }
                return persistentSRSCompareBytes($0.completionOrderKeyBytes, $1.completionOrderKeyBytes)
            }
            if let last = group.last {
                if selected.contains(where: { $0.scenario == scenario }) {
                    return .failure(.closureDuplicateCandidate)
                }
                selected.append(last)
            }
        }
        return .success(selected)
    }
}

public enum SRSClosureHeadState: String, Equatable, Sendable {
    case active = "ACTIVE"
    case superseded = "SUPERSEDED"
    case invalidated = "INVALIDATED"
}

public struct SRSClosureCommitRecord: Equatable, Sendable {
    public var closureVersion: Int
    public var priorClosureHeadVersion: Int?
    public var candidates: [SRSClosureCandidate]
    public var headState: SRSClosureHeadState
    public init(closureVersion: Int, priorClosureHeadVersion: Int?, candidates: [SRSClosureCandidate], headState: SRSClosureHeadState) {
        self.closureVersion = closureVersion
        self.priorClosureHeadVersion = priorClosureHeadVersion
        self.candidates = candidates
        self.headState = headState
    }
}

public struct SRSClosureInvalidation: Equatable, Sendable {
    public var targetClosureVersion: Int
    public init(targetClosureVersion: Int) {
        self.targetClosureVersion = targetClosureVersion
    }
}

public enum SRSClosureChain {
    /// Validate the linear chain C1..Cn and return the current head with the
    /// projected head state. Forks, duplicate versions, skipped versions, and
    /// out-of-chain commits are rejected.
    public static func validateChain(_ commits: [SRSClosureCommitRecord]) -> Result<SRSClosureCommitRecord, PersistentSRSStatus> {
        guard let first = commits.first else {
            return .failure(.persistenceVerificationIndeterminate)
        }
        guard first.closureVersion == 1, first.priorClosureHeadVersion == nil else {
            return .failure(.closureChainForkRejected)
        }
        var head = first
        for commit in commits.dropFirst() {
            guard commit.closureVersion == head.closureVersion + 1,
                    commit.priorClosureHeadVersion == head.closureVersion else {
                return .failure(.closureChainForkRejected)
            }
            // The previous head becomes SUPERSEDED if it was ACTIVE; it stays
            // INVALIDATED if already INVALIDATED. The new commit is ACTIVE.
            head = SRSClosureCommitRecord(
                closureVersion: commit.closureVersion,
                priorClosureHeadVersion: commit.priorClosureHeadVersion,
                candidates: commit.candidates,
                headState: .active
            )
        }
        return .success(head)
    }

    /// An invalidation is in-chain only when it targets the current head.
    public static func applyInvalidation(
        _ invalidation: SRSClosureInvalidation, head: SRSClosureCommitRecord
    ) -> Result<SRSClosureCommitRecord, PersistentSRSStatus> {
        guard invalidation.targetClosureVersion == head.closureVersion else {
            return .failure(.closureInvalidationTargetNotHead)
        }
        var invalidated = head
        invalidated.headState = .invalidated
        return .success(invalidated)
    }
}
