import Crypto
import Foundation
#if canImport(Security)
import Security
#endif

/// LOCALB is an independent trust domain. This file deliberately does not
/// modify or extend the frozen trust anchor in PersistentSRSRepresentation.swift.
public enum LOCALBConstants {
    public static let envelopeSchemaID = "SIMIGO_PERSISTENT_SRS_LOCALB_ENVELOPE_V1"
    public static let storageFormatVersion = "PERSISTENT_SRS_LOCALB_STORAGE_V1"
    public static let signatureDomain = "SIMIGO_PERSISTENT_SRS_LOCALB_RECORD_SIGNATURE_V1"
    public static let signingInputMagic = "SIMIGO_PERSISTENT_SRS_LOCALB_SIGNING_INPUT_V1"
    public static let credentialDigestDomain = "LPS01-CRED-V1"
    public static let credentialProtocolVersion = "LPS01-P1"
    public static let envelopeFieldCount: UInt32 = 16
    public static let signingFieldCount: UInt32 = 14
}

/// Typed LOCALB failures. The A-domain status enum remains untouched.
public enum LOCALBStatus: String, Error, Equatable, Sendable {
    case invalidConfiguration = "LOCALB_INVALID_CONFIGURATION"
    case invalidSigningInput = "LOCALB_INVALID_SIGNING_INPUT"
    case invalidPhysicalFrame = "LOCALB_INVALID_PHYSICAL_FRAME"
    case resourceLimit = "LOCALB_RESOURCE_LIMIT"
    case challengeRateLimited = "LOCALB_CHALLENGE_RATE_LIMITED"
    case unknownEnvelopeSchema = "LOCALB_UNKNOWN_ENVELOPE_SCHEMA"
    case nonCanonicalEnvelope = "LOCALB_NON_CANONICAL_ENVELOPE"
    case storageFormatMismatch = "LOCALB_STORAGE_FORMAT_MISMATCH"
    case encodingIdentityMismatch = "LOCALB_ENCODING_IDENTITY_MISMATCH"
    case signatureDomainMismatch = "LOCALB_SIGNATURE_DOMAIN_MISMATCH"
    case completionStateInvalid = "LOCALB_COMPLETION_STATE_INVALID"
    case payloadDigestMismatch = "LOCALB_PAYLOAD_DIGEST_MISMATCH"
    case envelopeDigestMismatch = "LOCALB_ENVELOPE_DIGEST_MISMATCH"
    case invalidPayloadUTF8 = "LOCALB_INVALID_PAYLOAD_UTF8"
    case invalidPayloadJSON = "LOCALB_INVALID_PAYLOAD_JSON"
    case payloadSchemaInvalid = "LOCALB_PAYLOAD_SCHEMA_INVALID"
    case nonCanonicalPayload = "LOCALB_NON_CANONICAL_PAYLOAD"
    case envelopeLogicalKeyMismatch = "LOCALB_ENVELOPE_LOGICAL_KEY_MISMATCH"
    case producerReferenceMismatch = "LOCALB_PRODUCER_REFERENCE_MISMATCH"
    case decisionCoreBindingMismatch = "LOCALB_DECISION_CORE_BINDING_MISMATCH"
    case issuerKeyIDMismatch = "ISSUER_KEYID_MISMATCH"
    case issuerUnknown = "ISSUER_UNKNOWN"
    case issuerPublicKeyMismatch = "ISSUER_PUBKEY_MISMATCH"
    case issuerGenerationMismatch = "ISSUER_GENERATION_MISMATCH"
    case issuerLineageMismatch = "ISSUER_LINEAGE_MISMATCH"
    case issuerKeyRevoked = "ISSUER_KEY_REVOKED"
    case signatureVerificationFailed = "LOCALB_SIGNATURE_VERIFICATION_FAILED"
    case invalidCredentialID = "LOCALB_INVALID_CREDENTIAL_ID"
    case invalidCredentialSecret = "LOCALB_INVALID_CREDENTIAL_SECRET"
    case keychainUnavailable = "LOCALB_KEYCHAIN_UNAVAILABLE"
    case keychainItemCorrupt = "LOCALB_KEYCHAIN_ITEM_CORRUPT"
    case registryCheckpointUnavailable = "LOCALB_REGISTRY_CHECKPOINT_UNAVAILABLE"
    case registryCheckpointMismatch = "LOCALB_REGISTRY_CHECKPOINT_MISMATCH"
    case registryCorrupt = "LOCALB_REGISTRY_CORRUPT"
    case registryPersistenceFailure = "LOCALB_REGISTRY_PERSISTENCE_FAILURE"
    case registryAlreadyInitialized = "LOCALB_REGISTRY_ALREADY_INITIALIZED"
    case registryLineageUninitialized = "LOCALB_REGISTRY_LINEAGE_UNINITIALIZED"
    case registryInvalidTransition = "LOCALB_REGISTRY_INVALID_TRANSITION"
    case registryKeyAlreadyExists = "LOCALB_REGISTRY_KEY_ALREADY_EXISTS"
    case registryNoActiveKey = "LOCALB_REGISTRY_NO_ACTIVE_KEY"
    case issuerKeyNotActive = "ISSUER_KEY_NOT_ACTIVE"
    case pairingCredentialUnknown = "LOCALB_PAIRING_CREDENTIAL_UNKNOWN"
    case pairingCredentialConsumed = "LOCALB_PAIRING_CREDENTIAL_CONSUMED"
    case pairingCredentialExpired = "LOCALB_PAIRING_CREDENTIAL_EXPIRED"
    case pairingCredentialRevoked = "LOCALB_PAIRING_CREDENTIAL_REVOKED"
    case pairingBindingMismatch = "LOCALB_PAIRING_BINDING_MISMATCH"
    case pairingProofInvalid = "LOCALB_PAIRING_PROOF_INVALID"
    case pairingOperatorApprovalRequired = "LOCALB_PAIRING_OPERATOR_APPROVAL_REQUIRED"
    case clientUnknown = "LOCALB_CLIENT_UNKNOWN"
    case clientRevoked = "LOCALB_CLIENT_REVOKED"
    case permissionDenied = "LOCALB_PERMISSION_DENIED"
    case duplicateClient = "LOCALB_DUPLICATE_CLIENT"
    case clientChallengeInvalid = "LOCALB_CLIENT_CHALLENGE_INVALID"
    case invalidProtectedRequest = "LOCALB_INVALID_PROTECTED_REQUEST"
    case clientRequestSignatureInvalid = "LOCALB_CLIENT_REQUEST_SIGNATURE_INVALID"
    case keychainItemMissing = "LOCALB_KEYCHAIN_ITEM_MISSING"
    case hostNotOperational = "LOCALB_HOST_NOT_OPERATIONAL"
    case transportIdentityMissing = "LOCALB_TRANSPORT_IDENTITY_MISSING"
    case transportIdentityCorrupt = "LOCALB_TRANSPORT_IDENTITY_CORRUPT"
    case transportIdentityMismatch = "LOCALB_TRANSPORT_IDENTITY_MISMATCH"
    case transportIdentityGenerationExhausted = "LOCALB_TRANSPORT_IDENTITY_GENERATION_EXHAUSTED"
    case plaintextNotAllowedOnLAN = "LOCALB_PLAINTEXT_NOT_ALLOWED_ON_LAN"
}

func localBIsCanonicalUUID(_ value: String) -> Bool {
    guard let parsed = UUID(uuidString: value) else { return false }
    return parsed.uuidString.lowercased() == value
}

enum LOCALBBinary {
    static func appendU16(_ value: UInt16, to output: inout [UInt8]) {
        output.append(UInt8((value >> 8) & 0xFF))
        output.append(UInt8(value & 0xFF))
    }

    static func appendU32(_ value: UInt32, to output: inout [UInt8]) {
        output.append(UInt8((value >> 24) & 0xFF))
        output.append(UInt8((value >> 16) & 0xFF))
        output.append(UInt8((value >> 8) & 0xFF))
        output.append(UInt8(value & 0xFF))
    }

    static func appendU64(_ value: UInt64, to output: inout [UInt8]) {
        for shift in stride(from: 56, through: 0, by: -8) {
            output.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    static func readU16(_ bytes: [UInt8], _ offset: inout Int) -> UInt16? {
        guard offset >= 0, offset <= bytes.count, bytes.count - offset >= 2 else { return nil }
        let value = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        offset += 2
        return value
    }

    static func readU32(_ bytes: [UInt8], _ offset: inout Int) -> UInt32? {
        guard offset >= 0, offset <= bytes.count, bytes.count - offset >= 4 else { return nil }
        var value: UInt32 = 0
        for _ in 0..<4 { value = (value << 8) | UInt32(bytes[offset]); offset += 1 }
        return value
    }

    static func readU64(_ bytes: [UInt8], _ offset: inout Int) -> UInt64? {
        guard offset >= 0, offset <= bytes.count, bytes.count - offset >= 8 else { return nil }
        var value: UInt64 = 0
        for _ in 0..<8 { value = (value << 8) | UInt64(bytes[offset]); offset += 1 }
        return value
    }

    static func appendField(label: String, type: UInt8, value: [UInt8], to output: inout [UInt8]) throws {
        let labelBytes = Array(label.utf8)
        guard !labelBytes.isEmpty,
              labelBytes.count <= Int(UInt16.max),
              labelBytes.allSatisfy({ $0 < 0x80 }) else {
            throw LOCALBStatus.invalidSigningInput
        }
        appendU16(UInt16(labelBytes.count), to: &output)
        output.append(contentsOf: labelBytes)
        output.append(type)
        appendU64(UInt64(value.count), to: &output)
        output.append(contentsOf: value)
    }

    static func stringBytes(_ value: String) -> [UInt8] { Array(value.utf8) }

    static func hexLower(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(bytes)))
    }

    /// Fixed-size comparison without an early exit on the first differing byte.
    static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for i in lhs.indices { difference |= lhs[i] ^ rhs[i] }
        return difference == 0
    }
}

/// The exact semantic fields entering LOCALB_SIGNING_INPUT_V1.
/// issuer_key_id and payload_digest_hex are intentionally derived and omitted;
/// the reader recomputes and cross-checks both independently.
public struct LOCALBSigningFields: Equatable, Sendable {
    public let logicalKeyIdentity: String
    public let logicalKeyVersion: String
    public let payloadDigestHex: String
    public let signerPublicKeyRaw: [UInt8]
    public let producerAuthorizationReference: String
    public let decisionCoreSourceCommit: String
    public let decisionCoreSourceSHA256Hex: String
    public let issuerGeneration: UInt32
    public let issuerLineageID: String
    public let canonicalPayload: [UInt8]

    public init(
        logicalKeyIdentity: String,
        logicalKeyVersion: String,
        payloadDigestHex: String,
        signerPublicKeyRaw: [UInt8],
        producerAuthorizationReference: String,
        decisionCoreSourceCommit: String,
        decisionCoreSourceSHA256Hex: String,
        issuerGeneration: UInt32,
        issuerLineageID: String,
        canonicalPayload: [UInt8]
    ) {
        self.logicalKeyIdentity = logicalKeyIdentity
        self.logicalKeyVersion = logicalKeyVersion
        self.payloadDigestHex = payloadDigestHex
        self.signerPublicKeyRaw = signerPublicKeyRaw
        self.producerAuthorizationReference = producerAuthorizationReference
        self.decisionCoreSourceCommit = decisionCoreSourceCommit
        self.decisionCoreSourceSHA256Hex = decisionCoreSourceSHA256Hex
        self.issuerGeneration = issuerGeneration
        self.issuerLineageID = issuerLineageID
        self.canonicalPayload = canonicalPayload
    }
}

public enum LOCALBSigningInputV1 {
    public static func keyID(publicKeyRaw: [UInt8]) throws -> String {
        guard publicKeyRaw.count == 32 else { throw LOCALBStatus.invalidSigningInput }
        return LOCALBBinary.hexLower(LOCALBBinary.sha256(publicKeyRaw))
    }

    /// Canonical, typed, length-prefixed byte projection specified by v0.5.
    /// The 14-field order and field types are part of the protocol.
    public static func encode(_ fields: LOCALBSigningFields) throws -> [UInt8] {
        guard fields.signerPublicKeyRaw.count == 32,
              isHex64(fields.payloadDigestHex),
              isHex64(fields.decisionCoreSourceSHA256Hex),
              !fields.logicalKeyIdentity.isEmpty,
              !fields.logicalKeyVersion.isEmpty,
              localBIsCanonicalUUID(fields.issuerLineageID),
              !fields.producerAuthorizationReference.isEmpty else {
            throw LOCALBStatus.invalidSigningInput
        }

        let prefix = Array(LOCALBConstants.signingInputMagic.utf8)
        var output = prefix
        output.append(0x00)
        LOCALBBinary.appendU32(LOCALBConstants.signingFieldCount, to: &output)

        // Type 0x02 = exact UTF-8 string bytes; 0x04 = byte sequence.
        let strings: [(String, String)] = [
            ("envelope_schema_id", LOCALBConstants.envelopeSchemaID),
            ("storage_format_version", LOCALBConstants.storageFormatVersion),
            ("logical_key_identity", fields.logicalKeyIdentity),
            ("logical_key_version", fields.logicalKeyVersion),
            ("encoding_identity", SRSEncodingConstants.encodingIdentity),
            ("signature_domain", LOCALBConstants.signatureDomain),
        ]
        for (label, value) in strings {
            try LOCALBBinary.appendField(label: label, type: 0x02,
                                         value: Array(value.utf8), to: &output)
        }
        try LOCALBBinary.appendField(label: "signer_public_key_raw", type: 0x04,
                                     value: fields.signerPublicKeyRaw, to: &output)
        try LOCALBBinary.appendField(label: "producer_authorization_reference", type: 0x02,
                                     value: Array(fields.producerAuthorizationReference.utf8), to: &output)
        try LOCALBBinary.appendField(label: "decision_core_source_commit", type: 0x02,
                                     value: Array(fields.decisionCoreSourceCommit.utf8), to: &output)
        try LOCALBBinary.appendField(label: "decision_core_source_sha256", type: 0x02,
                                     value: Array(fields.decisionCoreSourceSHA256Hex.utf8), to: &output)
        try LOCALBBinary.appendField(label: "completion_state", type: 0x02,
                                     value: Array(SRSEncodingConstants.completionState.utf8), to: &output)
        var generationBytes: [UInt8] = []
        LOCALBBinary.appendU32(fields.issuerGeneration, to: &generationBytes)
        try LOCALBBinary.appendField(label: "issuer_generation", type: 0x04,
                                     value: generationBytes, to: &output)
        try LOCALBBinary.appendField(label: "issuer_lineage_id", type: 0x02,
                                     value: Array(fields.issuerLineageID.utf8), to: &output)
        try LOCALBBinary.appendField(label: "canonical_payload", type: 0x04,
                                     value: fields.canonicalPayload, to: &output)
        return output
    }

    public static func sign(_ fields: LOCALBSigningFields,
                            with privateKey: Curve25519.Signing.PrivateKey) throws -> [UInt8] {
        let input = try encode(fields)
        return Array(try privateKey.signature(for: Data(input)))
    }

    public static func verify(_ signature: [UInt8],
                              fields: LOCALBSigningFields) -> Bool {
        guard signature.count == 64,
              let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: Data(fields.signerPublicKeyRaw)),
              let input = try? encode(fields) else { return false }
        return publicKey.isValidSignature(Data(signature), for: Data(input))
    }
}

public enum LOCALBKeyStatus: String, Equatable, Sendable {
    case active = "ACTIVE"
    case retired = "RETIRED"
    case lost = "LOST"
    case revoked = "REVOKED"
}

public struct LOCALBRegistryKeyEntry: Equatable, Sendable {
    public let keyID: String
    public let publicKeyRaw: [UInt8]
    public let generation: UInt32
    public let status: LOCALBKeyStatus
    public let lineageID: String

    public init(keyID: String, publicKeyRaw: [UInt8], generation: UInt32,
                status: LOCALBKeyStatus, lineageID: String) {
        self.keyID = keyID
        self.publicKeyRaw = publicKeyRaw
        self.generation = generation
        self.status = status
        self.lineageID = lineageID
    }
}

/// Immutable verification view. Production callers must construct this only
/// from an independently verified registry log/checkpoint; this value itself
/// is not a substitute for the persistent append-only registry.
public struct LOCALBRegistrySnapshot: Sendable {
    public let currentLineageID: String
    private let entriesByKeyID: [String: LOCALBRegistryKeyEntry]
    private let clientsByKeyID: [String: LOCALBClientRegistryEntry]

    init(currentLineageID: String, entries: [LOCALBRegistryKeyEntry],
         clients: [LOCALBClientRegistryEntry] = []) throws {
        guard localBIsCanonicalUUID(currentLineageID) else { throw LOCALBStatus.invalidConfiguration }
        var map: [String: LOCALBRegistryKeyEntry] = [:]
        for entry in entries {
            guard entry.publicKeyRaw.count == 32,
                  entry.generation > 0,
                  localBIsCanonicalUUID(entry.lineageID),
                  let recomputed = try? LOCALBSigningInputV1.keyID(publicKeyRaw: entry.publicKeyRaw),
                  recomputed == entry.keyID,
                  map[entry.keyID] == nil else {
                throw LOCALBStatus.invalidConfiguration
            }
            map[entry.keyID] = entry
        }
        var clientMap: [String: LOCALBClientRegistryEntry] = [:]
        for client in clients {
            guard client.publicKeyRaw.count == 32,
                  client.lineageID == currentLineageID,
                  let recomputed = try? LOCALBSigningInputV1.keyID(publicKeyRaw: client.publicKeyRaw),
                  recomputed == client.clientKeyID,
                  !client.permissions.contains(.srsWrite),
                  clientMap[client.clientKeyID] == nil else {
                throw LOCALBStatus.invalidConfiguration
            }
            clientMap[client.clientKeyID] = client
        }
        self.currentLineageID = currentLineageID
        self.entriesByKeyID = map
        self.clientsByKeyID = clientMap
    }

    public func entry(for keyID: String) -> LOCALBRegistryKeyEntry? {
        entriesByKeyID[keyID]
    }

    public func clientEntry(for keyID: String) -> LOCALBClientRegistryEntry? {
        clientsByKeyID[keyID]
    }

    public var keyEntries: [LOCALBRegistryKeyEntry] {
        entriesByKeyID.values.sorted { $0.keyID < $1.keyID }
    }

    public var clientEntries: [LOCALBClientRegistryEntry] {
        clientsByKeyID.values.sorted { $0.clientKeyID < $1.clientKeyID }
    }
}

public struct LOCALBVerifiedRecord: Equatable, Sendable {
    public let logicalKeyIdentity: String
    public let logicalKeyVersion: String
    public let payloadBytes: [UInt8]
    public let payloadDigestHex: String
    public let issuerKeyID: String
    public let issuerGeneration: UInt32
    public let issuerLineageID: String
    public let producerAuthorizationReference: String

    public init(logicalKeyIdentity: String, logicalKeyVersion: String,
                payloadBytes: [UInt8], payloadDigestHex: String, issuerKeyID: String,
                issuerGeneration: UInt32, issuerLineageID: String,
                producerAuthorizationReference: String) {
        self.logicalKeyIdentity = logicalKeyIdentity
        self.logicalKeyVersion = logicalKeyVersion
        self.payloadBytes = payloadBytes
        self.payloadDigestHex = payloadDigestHex
        self.issuerKeyID = issuerKeyID
        self.issuerGeneration = issuerGeneration
        self.issuerLineageID = issuerLineageID
        self.producerAuthorizationReference = producerAuthorizationReference
    }
}

private struct LOCALBEnvelope {
    static let labels: [String] = [
        "envelope_schema_id",
        "storage_format_version",
        "logical_key_identity",
        "logical_key_version",
        "payload_digest_hex",
        "encoding_identity",
        "signature_domain",
        "signer_public_key_raw",
        "signature_raw",
        "producer_authorization_reference",
        "decision_core_source_commit",
        "decision_core_source_sha256",
        "completion_state",
        "issuer_key_id",
        "issuer_generation",
        "issuer_lineage_id",
    ]

    static func values(fields: LOCALBSigningFields, signature: [UInt8]) throws -> [[UInt8]] {
        guard signature.count == 64 else { throw LOCALBStatus.invalidSigningInput }
        var generation: [UInt8] = []
        LOCALBBinary.appendU32(fields.issuerGeneration, to: &generation)
        return [
            Array(LOCALBConstants.envelopeSchemaID.utf8),
            Array(LOCALBConstants.storageFormatVersion.utf8),
            Array(fields.logicalKeyIdentity.utf8),
            Array(fields.logicalKeyVersion.utf8),
            Array(fields.payloadDigestHex.utf8),
            Array(SRSEncodingConstants.encodingIdentity.utf8),
            Array(LOCALBConstants.signatureDomain.utf8),
            fields.signerPublicKeyRaw,
            signature,
            Array(fields.producerAuthorizationReference.utf8),
            Array(fields.decisionCoreSourceCommit.utf8),
            Array(fields.decisionCoreSourceSHA256Hex.utf8),
            Array(SRSEncodingConstants.completionState.utf8),
            Array(try LOCALBSigningInputV1.keyID(publicKeyRaw: fields.signerPublicKeyRaw).utf8),
            generation,
            Array(fields.issuerLineageID.utf8),
        ]
    }

    static func encode(_ values: [[UInt8]]) throws -> [UInt8] {
        guard values.count == labels.count else { throw LOCALBStatus.nonCanonicalEnvelope }
        var output: [UInt8] = []
        LOCALBBinary.appendU32(LOCALBConstants.envelopeFieldCount, to: &output)
        for (label, value) in zip(labels, values) {
            let labelBytes = Array(label.utf8)
            guard labelBytes.count <= Int(UInt16.max) else { throw LOCALBStatus.nonCanonicalEnvelope }
            LOCALBBinary.appendU16(UInt16(labelBytes.count), to: &output)
            output.append(contentsOf: labelBytes)
            LOCALBBinary.appendU64(UInt64(value.count), to: &output)
            output.append(contentsOf: value)
        }
        return output
    }

    /// R2: read only the envelope's first field. Does not parse or interpret payload.
    static func peekSchemaID(_ bytes: [UInt8]) -> Result<String, LOCALBStatus> {
        var offset = 0
        guard let count = LOCALBBinary.readU32(bytes, &offset),
              count > 0, count <= 64,
              let labelLength = LOCALBBinary.readU16(bytes, &offset) else {
            return .failure(.nonCanonicalEnvelope)
        }
        let labelCount = Int(labelLength)
        guard labelCount > 0, offset <= bytes.count, bytes.count - offset >= labelCount else {
            return .failure(.nonCanonicalEnvelope)
        }
        let label = String(bytes: bytes[offset..<(offset + labelCount)], encoding: .utf8)
        offset += labelCount
        guard label == labels[0] else { return .failure(.nonCanonicalEnvelope) }
        guard let valueLength = LOCALBBinary.readU64(bytes, &offset),
              valueLength <= UInt64(SRSEncodingConstants.maxEnvelopeBytes),
              valueLength <= UInt64(Int.max),
              offset <= bytes.count, bytes.count - offset >= Int(valueLength) else {
            return .failure(.nonCanonicalEnvelope)
        }
        guard let schema = String(bytes: bytes[offset..<(offset + Int(valueLength))], encoding: .utf8) else {
            return .failure(.nonCanonicalEnvelope)
        }
        return .success(schema)
    }

    static func decode(_ bytes: [UInt8]) -> Result<[[UInt8]], LOCALBStatus> {
        var offset = 0
        guard let count = LOCALBBinary.readU32(bytes, &offset),
              count == LOCALBConstants.envelopeFieldCount else {
            return .failure(.nonCanonicalEnvelope)
        }
        var values: [[UInt8]] = []
        values.reserveCapacity(labels.count)
        for expectedLabel in labels {
            guard let labelLength = LOCALBBinary.readU16(bytes, &offset) else {
                return .failure(.nonCanonicalEnvelope)
            }
            let length = Int(labelLength)
            guard length > 0, offset <= bytes.count, bytes.count - offset >= length else {
                return .failure(.nonCanonicalEnvelope)
            }
            let label = String(bytes: bytes[offset..<(offset + length)], encoding: .utf8)
            offset += length
            guard label == expectedLabel else { return .failure(.nonCanonicalEnvelope) }
            guard let valueLength = LOCALBBinary.readU64(bytes, &offset),
                  valueLength <= UInt64(SRSEncodingConstants.maxEnvelopeBytes),
                  valueLength <= UInt64(Int.max),
                  offset <= bytes.count, bytes.count - offset >= Int(valueLength) else {
                return .failure(.nonCanonicalEnvelope)
            }
            values.append(Array(bytes[offset..<(offset + Int(valueLength))]))
            offset += Int(valueLength)
        }
        guard offset == bytes.count else { return .failure(.nonCanonicalEnvelope) }
        return .success(values)
    }
}

public enum LOCALBRecordWriter {
    /// Creates a LOCALB frame. It never calls or mutates the frozen A-domain writer.
    public static func encode(record: PersistentSRSRecord,
                              signingKey: Curve25519.Signing.PrivateKey,
                              lineageID: String,
                              issuerGeneration: UInt32,
                              registry: LOCALBRegistrySnapshot) throws -> [UInt8] {
        let publicKeyRaw = Array(signingKey.publicKey.rawRepresentation)
        guard localBIsCanonicalUUID(lineageID),
              lineageID == registry.currentLineageID,
              issuerGeneration > 0 else {
            throw LOCALBStatus.invalidConfiguration
        }
        let keyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: publicKeyRaw)
        guard let entry = registry.entry(for: keyID) else { throw LOCALBStatus.issuerUnknown }
        guard entry.status == .active else {
            if entry.status == .revoked { throw LOCALBStatus.issuerKeyRevoked }
            throw LOCALBStatus.issuerKeyNotActive
        }
        guard entry.publicKeyRaw == publicKeyRaw else { throw LOCALBStatus.issuerPublicKeyMismatch }
        guard entry.generation == issuerGeneration else { throw LOCALBStatus.issuerGenerationMismatch }
        guard entry.lineageID == lineageID else { throw LOCALBStatus.issuerLineageMismatch }

        let payload = SRSCanonical.payloadBytes(record)
        guard !payload.isEmpty, payload.count <= SRSEncodingConstants.maxPayloadBytes else {
            throw LOCALBStatus.resourceLimit
        }
        let digest = SRSCanonical.payloadDigest(payload)
        let fields = LOCALBSigningFields(
            logicalKeyIdentity: record.logicalKeyIdentity,
            logicalKeyVersion: record.logicalKeyVersion,
            payloadDigestHex: SRSCanonical.payloadDigestHex(digest),
            signerPublicKeyRaw: publicKeyRaw,
            producerAuthorizationReference: record.producerAuthorizationReference,
            decisionCoreSourceCommit: SRSEncodingConstants.decisionCoreSourceCommit,
            decisionCoreSourceSHA256Hex: SRSEncodingConstants.decisionCoreSourceSHA256,
            issuerGeneration: issuerGeneration,
            issuerLineageID: lineageID,
            canonicalPayload: payload
        )
        let signature = try LOCALBSigningInputV1.sign(fields, with: signingKey)
        let envelopeBytes = try LOCALBEnvelope.encode(LOCALBEnvelope.values(fields: fields, signature: signature))
        guard envelopeBytes.count <= SRSEncodingConstants.maxEnvelopeBytes else {
            throw LOCALBStatus.resourceLimit
        }
        let envelopeDigest = SRSEnvelope.envelopeDigest(canonicalEnvelopeBytes: envelopeBytes)
        let frame = SRSFrame(payloadBytes: payload, envelopeBytes: envelopeBytes,
                             payloadDigestRaw: digest, envelopeDigestRaw: envelopeDigest)
        let bytes = SRSFrame.encode(frame)
        guard bytes.count <= SRSEncodingConstants.maxTotalBytes else { throw LOCALBStatus.resourceLimit }
        return bytes
    }
}

public enum LOCALBRecordReader {
    private struct FrameLayout {
        let payloadDigest: [UInt8]
        let payloadRange: Range<Int>
        let envelopeRange: Range<Int>
        let envelopeDigest: [UInt8]
    }

    /// R1: validate only physical structure and byte ranges; no payload parsing.
    private static func parseFrameStructure(_ data: [UInt8]) -> Result<FrameLayout, LOCALBStatus> {
        guard data.count >= 108 else { return .failure(.invalidPhysicalFrame) }
        guard data.count <= SRSEncodingConstants.maxTotalBytes else { return .failure(.resourceLimit) }
        let startMagic = Array(SRSEncodingConstants.magicStart.utf8)
        guard Array(data[0..<12]) == startMagic else { return .failure(.invalidPhysicalFrame) }
        var versionOffset = 12
        guard let version = LOCALBBinary.readU32(data, &versionOffset),
              version == SRSEncodingConstants.physicalVersion else {
            return .failure(.invalidPhysicalFrame)
        }
        var lengthOffset = 16
        guard let payloadLength64 = LOCALBBinary.readU64(data, &lengthOffset),
              let envelopeLength64 = LOCALBBinary.readU64(data, &lengthOffset),
              payloadLength64 <= UInt64(SRSEncodingConstants.maxPayloadBytes),
              envelopeLength64 <= UInt64(SRSEncodingConstants.maxEnvelopeBytes),
              payloadLength64 <= UInt64(Int.max),
              envelopeLength64 <= UInt64(Int.max) else {
            return .failure(.resourceLimit)
        }
        let payloadLength = Int(payloadLength64)
        let envelopeLength = Int(envelopeLength64)
        guard payloadLength <= Int.max - 108,
              envelopeLength <= Int.max - 108 - payloadLength else {
            return .failure(.resourceLimit)
        }
        let total = 108 + payloadLength + envelopeLength
        guard total == data.count else { return .failure(.invalidPhysicalFrame) }
        let endStart = total - 12
        guard Array(data[endStart..<total]) == Array(SRSEncodingConstants.magicEnd.utf8) else {
            return .failure(.invalidPhysicalFrame)
        }
        let payloadStart = 64
        let payloadEnd = payloadStart + payloadLength
        let envelopeEnd = payloadEnd + envelopeLength
        let payloadDigest = Array(data[32..<64])
        let envelopeDigest = Array(data[envelopeEnd..<(envelopeEnd + 32)])
        return .success(FrameLayout(
            payloadDigest: payloadDigest,
            payloadRange: payloadStart..<payloadEnd,
            envelopeRange: payloadEnd..<envelopeEnd,
            envelopeDigest: envelopeDigest
        ))
    }

    public static func read(data: [UInt8],
                            registry: LOCALBRegistrySnapshot) -> Result<LOCALBVerifiedRecord, LOCALBStatus> {
        let layout: FrameLayout
        switch parseFrameStructure(data) {
        case .success(let value): layout = value
        case .failure(let error): return .failure(error)
        }

        let envelopeBytes = Array(data[layout.envelopeRange])

        // R2-R3: reject foreign schemas before payload parsing or interpretation.
        let schemaID: String
        switch LOCALBEnvelope.peekSchemaID(envelopeBytes) {
        case .success(let value): schemaID = value
        case .failure(let error): return .failure(error)
        }
        guard schemaID == LOCALBConstants.envelopeSchemaID else {
            return .failure(.unknownEnvelopeSchema)
        }

        // R4: validate complete envelope structure, constants, and envelope digest.
        let envelopeFields: [[UInt8]]
        switch LOCALBEnvelope.decode(envelopeBytes) {
        case .success(let value): envelopeFields = value
        case .failure(let error): return .failure(error)
        }
        func string(_ index: Int) -> String? {
            guard index >= 0, index < envelopeFields.count else { return nil }
            return String(bytes: envelopeFields[index], encoding: .utf8)
        }
        guard string(0) == LOCALBConstants.envelopeSchemaID else {
            return .failure(.unknownEnvelopeSchema)
        }
        guard string(1) == LOCALBConstants.storageFormatVersion else {
            return .failure(.storageFormatMismatch)
        }
        guard string(5) == SRSEncodingConstants.encodingIdentity else {
            return .failure(.encodingIdentityMismatch)
        }
        guard string(6) == LOCALBConstants.signatureDomain else {
            return .failure(.signatureDomainMismatch)
        }
        guard string(12) == SRSEncodingConstants.completionState else {
            return .failure(.completionStateInvalid)
        }
        let envelopeDigest = SRSEnvelope.envelopeDigest(canonicalEnvelopeBytes: envelopeBytes)
        guard LOCALBBinary.constantTimeEqual(envelopeDigest, layout.envelopeDigest) else {
            return .failure(.envelopeDigestMismatch)
        }

        // R5: only after schema acceptance do we interpret the I0 payload.
        let payloadBytes = Array(data[layout.payloadRange])
        guard String(bytes: payloadBytes, encoding: .utf8) != nil else {
            return .failure(.invalidPayloadUTF8)
        }
        let parsedPayload: SRSJSONValue
        switch SRSStrictJSONParser.parse(payloadBytes) {
        case .success(let value): parsedPayload = value
        case .failure: return .failure(.invalidPayloadJSON)
        }
        let record: PersistentSRSRecord
        do {
            record = try PersistentSRSRecord.decode(parsedPayload)
        } catch {
            return .failure(.payloadSchemaInvalid)
        }
        guard persistentSRSBytesEqual(SRSCanonical.payloadBytes(record), payloadBytes) else {
            return .failure(.nonCanonicalPayload)
        }
        let computedPayloadDigest = SRSCanonical.payloadDigest(payloadBytes)
        guard LOCALBBinary.constantTimeEqual(layout.payloadDigest, computedPayloadDigest),
              string(4) == SRSCanonical.payloadDigestHex(computedPayloadDigest) else {
            return .failure(.payloadDigestMismatch)
        }

        let logicalIdentity = string(2) ?? ""
        let logicalVersion = string(3) ?? ""
        guard persistentSRSBytesEqual(Array(logicalIdentity.utf8), Array(record.logicalKeyIdentity.utf8)),
              persistentSRSBytesEqual(Array(logicalVersion.utf8), Array(record.logicalKeyVersion.utf8)) else {
            return .failure(.envelopeLogicalKeyMismatch)
        }
        guard string(9) == record.producerAuthorizationReference else {
            return .failure(.producerReferenceMismatch)
        }
        guard string(10) == SRSEncodingConstants.decisionCoreSourceCommit,
              string(11) == SRSEncodingConstants.decisionCoreSourceSHA256 else {
            return .failure(.decisionCoreBindingMismatch)
        }
        guard envelopeFields[7].count == 32, envelopeFields[8].count == 64,
              let generation = Self.decodeGeneration(envelopeFields[14]),
              let lineage = string(15), !lineage.isEmpty,
              let claimedKeyID = string(13) else {
            return .failure(.nonCanonicalEnvelope)
        }

        // R6a-R6f: bind signed assertions to the same trusted registry entry.
        guard let computedKeyID = try? LOCALBSigningInputV1.keyID(publicKeyRaw: envelopeFields[7]),
              computedKeyID == claimedKeyID else {
            return .failure(.issuerKeyIDMismatch)
        }
        guard let entry = registry.entry(for: claimedKeyID) else {
            return .failure(.issuerUnknown)
        }
        guard LOCALBBinary.constantTimeEqual(envelopeFields[7], entry.publicKeyRaw) else {
            return .failure(.issuerPublicKeyMismatch)
        }
        guard entry.generation == generation else {
            return .failure(.issuerGenerationMismatch)
        }
        guard entry.lineageID == lineage, lineage == registry.currentLineageID else {
            return .failure(.issuerLineageMismatch)
        }
        guard entry.status != .revoked else { return .failure(.issuerKeyRevoked) }
        guard entry.status == .active || entry.status == .retired || entry.status == .lost else {
            return .failure(.issuerUnknown)
        }

        // R6g: verify the complete signature projection (including lineage).
        let signingFields = LOCALBSigningFields(
            logicalKeyIdentity: logicalIdentity,
            logicalKeyVersion: logicalVersion,
            payloadDigestHex: string(4) ?? "",
            signerPublicKeyRaw: envelopeFields[7],
            producerAuthorizationReference: string(9) ?? "",
            decisionCoreSourceCommit: string(10) ?? "",
            decisionCoreSourceSHA256Hex: string(11) ?? "",
            issuerGeneration: generation,
            issuerLineageID: lineage,
            canonicalPayload: payloadBytes
        )
        guard LOCALBSigningInputV1.verify(envelopeFields[8], fields: signingFields) else {
            return .failure(.signatureVerificationFailed)
        }

        return .success(LOCALBVerifiedRecord(
            logicalKeyIdentity: record.logicalKeyIdentity,
            logicalKeyVersion: record.logicalKeyVersion,
            payloadBytes: payloadBytes,
            payloadDigestHex: SRSCanonical.payloadDigestHex(computedPayloadDigest),
            issuerKeyID: claimedKeyID,
            issuerGeneration: generation,
            issuerLineageID: lineage,
            producerAuthorizationReference: record.producerAuthorizationReference
        ))
    }

    private static func decodeGeneration(_ bytes: [UInt8]) -> UInt32? {
        guard bytes.count == 4 else { return nil }
        var offset = 0
        return LOCALBBinary.readU32(bytes, &offset)
    }
}

/// Canonical one-time pairing-credential material. The secret is intentionally
/// not Codable and the type has no CustomStringConvertible implementation.
public final class LOCALBPairingCredentialMaterial {
    public let credentialID: String
    public let digest: [UInt8]
    private var secretStorage: [UInt8]?
    private let secretLock = NSLock()

    private init(credentialID: String, secretRaw: [UInt8], digest: [UInt8]) {
        self.credentialID = credentialID
        self.secretStorage = secretRaw
        self.digest = digest
    }

    public static func issue() throws -> LOCALBPairingCredentialMaterial {
        let credentialID = UUID().uuidString.lowercased()
        var generator = SystemRandomNumberGenerator()
        let secret = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let digest = try credentialDigest(credentialID: credentialID, secretRaw: secret)
        return LOCALBPairingCredentialMaterial(credentialID: credentialID, secretRaw: secret, digest: digest)
    }

    /// The host gets one opportunity to hand the secret to its trusted display
    /// path. The material object then drops its copy and cannot re-display it.
    public func takeSecretRawOnce() throws -> [UInt8] {
        secretLock.lock()
        defer { secretLock.unlock() }
        guard let secret = secretStorage else { throw LOCALBStatus.invalidCredentialSecret }
        secretStorage = nil
        return secret
    }

    /// Preferred display path; the base64url representation is not the digest input.
    public func takeSecretBase64URLOnce() throws -> String {
        let secret = try takeSecretRawOnce()
        return Data(secret).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func credentialDigest(credentialID: String, secretRaw: [UInt8]) throws -> [UInt8] {
        let idBytes = Array(credentialID.utf8)
        guard isCanonicalUUIDv4(idBytes), secretRaw.count == 32 else {
            throw LOCALBStatus.invalidCredentialID
        }
        var input = Array(LOCALBConstants.credentialDigestDomain.utf8)
        input.append(0x00)
        LOCALBBinary.appendU16(UInt16(idBytes.count), to: &input)
        input.append(contentsOf: idBytes)
        LOCALBBinary.appendU32(UInt32(secretRaw.count), to: &input)
        input.append(contentsOf: secretRaw)
        return LOCALBBinary.sha256(input)
    }

    /// Pure verification: a failure never mutates or consumes any credential state.
    public func verify(presentedSecretRaw: [UInt8]) -> Bool {
        guard let computed = try? Self.credentialDigest(credentialID: credentialID, secretRaw: presentedSecretRaw) else {
            return false
        }
        return LOCALBBinary.constantTimeEqual(computed, digest)
    }

    private static func isCanonicalUUIDv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 36 else { return false }
        for index in [8, 13, 18, 23] where bytes[index] != 0x2D { return false }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) { continue }
            let validHex = (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66)
            guard validHex else { return false }
        }
        guard bytes[14] == 0x34, [0x38, 0x39, 0x61, 0x62].contains(bytes[19]) else { return false }
        return true
    }
}

#if canImport(Security)
public struct LOCALBKeychainSignerStore {
    public let service: String
    public let account: String

    public init(service: String = "com.simigo.localb-production-signer",
                account: String = "signing-key-v1") {
        self.service = service
        self.account = account
    }

    /// Loads the existing identity or creates it once. Concurrent first-use
    /// races resolve by reading the winning Keychain item; no key rotation occurs.
    /// Ordinary startup must never silently replace a missing identity.
    public func loadExisting() throws -> Curve25519.Signing.PrivateKey {
        guard let existing = try readExisting() else { throw LOCALBStatus.keychainItemMissing }
        return existing
    }

    public func loadOrCreate() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try readExisting() { return existing }
        let generated = Curve25519.Signing.PrivateKey()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: generated.rawRepresentation
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return generated }
        if status == errSecDuplicateItem, let winner = try readExisting() { return winner }
        throw LOCALBStatus.keychainUnavailable
    }

    private func readExisting() throws -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw LOCALBStatus.keychainUnavailable
        }
        guard data.count == 32,
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
            throw LOCALBStatus.keychainItemCorrupt
        }
        return key
    }
}
#endif
