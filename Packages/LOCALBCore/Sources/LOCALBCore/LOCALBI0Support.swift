// Minimal I0 support closure for LOCALBCore.
//
// Provenance: extracted verbatim (by line range) from the SimiGo-Lab frozen
// implementation file
//   simigo2-experimental/Sources/SimiGo2Experimental/PersistentSRSRepresentation.swift
//   git blob f5ea0130d8187b9845f324f653d4f99fcada643a (identical on main and
//   PR #10 branch codex/localb-signing-core-20261016).
//
// Included ranges:
//   lines 7-1030    PersistentSRSStatus, byte-identity helpers, SRSJSONValue,
//                   SRSJSONParserError, SRSJSONLimits, SRSStrictJSONParser,
//                   SRSJCS, SRSStrictUTC, the I0 record model types,
//                   PersistentSRSRecord (+ decode/canonical extension),
//                   SRSEncodingConstants, SRSDecodeError + decode helpers,
//                   SRSCanonical;
//   lines 1193-1224  SRSFrame (physical frame encode).
//
// Deliberately EXCLUDED (frozen Domain-A machinery, not used by LOCALB):
//   SRSSignature (contains the frozen Domain-A production trust anchor),
//   the full SRSEnvelope codec (values/encode/decode reference the frozen
//   Domain-A signature domain), SRSReader, SRSWriter, SRSWriteClassifier and
//   friends, and the attempt-evidence/closure governance machinery.
//
// One documented reduction: SRSEnvelope is carried over as an enum containing
// ONLY the static envelopeDigest function (body verbatim); LOCALB uses no
// other SRSEnvelope member. Semantic parity is enforced by the ported test
// suite.

import Crypto
import Darwin
import Foundation

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
    /// R17: enforce the exact allowed member set for this object class.
    /// Unknown members fail with UNKNOWN_SCHEMA_OR_FIELD; missing members are
    /// reported the same way by value(_:).
    func validateAllowed(_ allowed: Set<String>) throws {
        for (k, _) in members where !allowed.contains(k) {
            throw SRSDecodeError.fail(.unknownSchemaOrField)
        }
    }
    func value(_ key: String) throws -> SRSJSONValue {
        guard let entry = members.first(where: { $0.0 == key }) else {
            throw SRSDecodeError.fail(.unknownSchemaOrField)
        }
        return entry.1
    }
}

private func asObj(_ v: SRSJSONValue) throws -> SRSJSONObj {
    // A value that is not an object where an object is required is an R17
    // structural type violation.
    guard case .object(let members) = v else { throw SRSDecodeError.fail(.unknownSchemaOrField) }
    return SRSJSONObj(members: members)
}

private func asString(_ v: SRSJSONValue, minLength: Int = 0) throws -> String {
    // R17 structural type: a string is required here.
    guard case .string(let s) = v else { throw SRSDecodeError.fail(.unknownSchemaOrField) }
    // R19 schema-level length constraints.
    guard s.utf8.count >= minLength, s.utf8.count <= SRSJSONLimits.maxStringBytes else {
        throw SRSDecodeError.fail(.schemaValidationFailed)
    }
    return s
}

private func asBool(_ v: SRSJSONValue) throws -> Bool {
    // R17 structural type: a boolean is required here.
    guard case .bool(let b) = v else { throw SRSDecodeError.fail(.unknownSchemaOrField) }
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
    try o.validateAllowed(["identity", "version", "content_digest"])
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
        try keyObj.validateAllowed(["identity", "version"])
        r.logicalKeyIdentity = try asString(try keyObj.value("identity"), minLength: 1)
        r.logicalKeyVersion = try asString(try keyObj.value("version"), minLength: 1)

        let settled = try asObj(try root.value("settled_relation_state"))
        try settled.validateAllowed(["binding", "settlement_id", "status", "source_relation_identity",
                                     "result_identity", "requires_canonical_identity_rule",
                                     "canonical_identity_rule", "provenance_bindings"])
        r.settledBinding = try asBinding(try settled.value("binding"))
        r.settlementID = try asString(try settled.value("settlement_id"), minLength: 1)
        r.settlementStatus = try asSettlementStatus(try settled.value("status"))
        r.sourceRelationIdentity = try asString(try settled.value("source_relation_identity"), minLength: 1)
        r.resultIdentity = try asString(try settled.value("result_identity"), minLength: 1)
        r.requiresCanonicalIdentityRule = try asBool(try settled.value("requires_canonical_identity_rule"))
        r.canonicalIdentityRule = try asBinding(try settled.value("canonical_identity_rule"))
        r.settledProvenanceBindings = try asBindingArray(try settled.value("provenance_bindings"))

        let source = try asObj(try root.value("source_relation"))
        try source.validateAllowed(["binding", "semantic_binding", "applicability_coverage",
                                    "invalidation_record", "invalidation_status", "identity_rule", "status"])
        r.sourceBinding = try asBinding(try source.value("binding"))
        r.sourceSemanticBinding = try asBinding(try source.value("semantic_binding"))
        r.sourceApplicabilityCoverage = try asBinding(try source.value("applicability_coverage"))
        r.sourceInvalidationRecord = try asBinding(try source.value("invalidation_record"))
        r.sourceInvalidationStatus = try asInvalidationStatus(try source.value("invalidation_status"))
        r.sourceIdentityRule = try asBinding(try source.value("identity_rule"))
        r.sourceStatus = try asRelationStatus(try source.value("status"))

        let deps = try asObj(try root.value("dependency_set"))
        try deps.validateAllowed(["boundary", "dependencies"])
        r.dependencyBoundary = try asBinding(try deps.value("boundary"))
        if case .null = try deps.value("dependencies") {
            r.dependencies = nil
        } else if case .array(let depItems) = try deps.value("dependencies") {
            guard depItems.count <= SRSJSONLimits.maxArrayCount else { throw SRSDecodeError.fail(.integerOverflowOrResourceLimit) }
            r.dependencies = try depItems.map { item in
                let d = try asObj(item)
                try d.validateAllowed(["binding", "role", "necessity", "resolution", "status"])
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
        try result.validateAllowed(["binding", "resolution", "interpretability_evidence", "status"])
        r.resultBinding = try asBinding(try result.value("binding"))
        r.resultResolution = try asResolution(try result.value("resolution"))
        r.interpretabilityEvidence = try asBinding(try result.value("interpretability_evidence"))
        r.resultStatus = try asRelationStatus(try result.value("status"))

        let provenance = try asObj(try root.value("provenance"))
        try provenance.validateAllowed(["bindings", "lifecycle", "boundary"])
        r.provenanceBindings = try asBindingArray(try provenance.value("bindings"))
        r.provenanceLifecycle = try asSettlementStatus(try provenance.value("lifecycle"))
        r.provenanceBoundary = try asBinding(try provenance.value("boundary"))

        let lifecycle = try asObj(try root.value("lifecycle"))
        try lifecycle.validateAllowed(["bindings", "lifecycle", "boundary"])
        r.lifecycleBindings = try asBindingArray(try lifecycle.value("bindings"))
        r.lifecycleStatus = try asSettlementStatus(try lifecycle.value("lifecycle"))
        r.lifecycleBoundary = try asBinding(try lifecycle.value("boundary"))

        let freshness = try asObj(try root.value("freshness"))
        try freshness.validateAllowed(["boundary", "requirements"])
        r.freshnessBoundary = try asBinding(try freshness.value("boundary"))
        if case .null = try freshness.value("requirements") {
            r.freshnessRequirements = nil
        } else if case .array(let reqItems) = try freshness.value("requirements") {
            guard reqItems.count <= SRSJSONLimits.maxArrayCount else { throw SRSDecodeError.fail(.integerOverflowOrResourceLimit) }
            r.freshnessRequirements = try reqItems.map { item in
                let f = try asObj(item)
                try f.validateAllowed(["identity", "evidence", "expected_evidence_digest", "status",
                                       "valid_until_utc", "observed_at_utc"])
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
        try policy.validateAllowed(["resolution_rule", "policies", "boundary"])
        r.resolutionRule = try asBinding(try policy.value("resolution_rule"))
        r.policies = try asBindingArray(try policy.value("policies"))
        r.policyBoundary = try asBinding(try policy.value("boundary"))

        r.producerAuthorizationReference = try asString(try root.value("producer_authorization_reference"), minLength: 1)

        let coreBinding = try asObj(try root.value("decision_core_binding"))
        try coreBinding.validateAllowed(["source_commit", "source_sha256"])
        let commit = try asString(try coreBinding.value("source_commit"))
        let sha = try asHex64(try coreBinding.value("source_sha256"))
        guard commit == SRSEncodingConstants.decisionCoreSourceCommit,
              sha == SRSEncodingConstants.decisionCoreSourceSHA256 else {
            // Payload-layer const violation is an R19 schema failure; the
            // DECISION_CORE_BINDING_MISMATCH status is reserved for the
    // envelope-layer R27 check.
            throw SRSDecodeError.fail(.schemaValidationFailed)
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


// MARK: - Canonical envelope digest (I5) — minimal extraction

public enum SRSEnvelope {
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

