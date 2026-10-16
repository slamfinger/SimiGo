import Crypto
import Foundation

public enum LOCALBPermission: String, CaseIterable, Hashable, Sendable, Comparable {
    case inference = "P-INFERENCE"
    case informationRead = "P-INFO-READ"
    case srsWrite = "P-SRS-WRITE"
    case adminPairing = "P-ADMIN-PAIRING"
    case adminTrust = "P-ADMIN-TRUST"

    public static func < (lhs: LOCALBPermission, rhs: LOCALBPermission) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum LOCALBClientStatus: String, Equatable, Sendable {
    case active = "ACTIVE"
    case revoked = "REVOKED"
}

public enum LOCALBPairingCredentialStatus: String, Equatable, Sendable {
    case issued = "ISSUED"
    case consumed = "CONSUMED"
    case revoked = "REVOKED"
    case expired = "EXPIRED"
}

public enum LOCALBPairingConfirmationMode: String, Equatable, Sendable {
    case interactive = "INTERACTIVE"
    case strictHeadless = "STRICT_HEADLESS"
}

public struct LOCALBPairingCredentialEntry: Equatable, Sendable {
    public let credentialID: String
    public let digest: [UInt8]
    public let issuedAtMilliseconds: UInt64
    public let expiresAtMilliseconds: UInt64
    public let hostInstanceID: String
    public let tlsSPKIHash: String
    public let srsKeyID: String
    public let issuerGeneration: UInt32
    public let protocolVersion: String
    public let sessionNonce: [UInt8]
    public let scopeLabel: String
    public let confirmationMode: LOCALBPairingConfirmationMode
    public let expectedClientKeyFingerprint: String?
    public var status: LOCALBPairingCredentialStatus

    public init(credentialID: String, digest: [UInt8], issuedAtMilliseconds: UInt64,
                expiresAtMilliseconds: UInt64, hostInstanceID: String, tlsSPKIHash: String,
                srsKeyID: String, issuerGeneration: UInt32, protocolVersion: String,
                sessionNonce: [UInt8], scopeLabel: String,
                confirmationMode: LOCALBPairingConfirmationMode,
                expectedClientKeyFingerprint: String?,
                status: LOCALBPairingCredentialStatus = .issued) {
        self.credentialID = credentialID
        self.digest = digest
        self.issuedAtMilliseconds = issuedAtMilliseconds
        self.expiresAtMilliseconds = expiresAtMilliseconds
        self.hostInstanceID = hostInstanceID
        self.tlsSPKIHash = tlsSPKIHash
        self.srsKeyID = srsKeyID
        self.issuerGeneration = issuerGeneration
        self.protocolVersion = protocolVersion
        self.sessionNonce = sessionNonce
        self.scopeLabel = scopeLabel
        self.confirmationMode = confirmationMode
        self.expectedClientKeyFingerprint = expectedClientKeyFingerprint
        self.status = status
    }
}

public struct LOCALBClientRegistryEntry: Equatable, Sendable {
    public let clientKeyID: String
    public let publicKeyRaw: [UInt8]
    public let lineageID: String
    public let permissions: Set<LOCALBPermission>
    public let status: LOCALBClientStatus
    public let registeredAtMilliseconds: UInt64
    public let revokedReason: String?

    public init(clientKeyID: String, publicKeyRaw: [UInt8], lineageID: String,
                permissions: Set<LOCALBPermission>, status: LOCALBClientStatus,
                registeredAtMilliseconds: UInt64, revokedReason: String? = nil) {
        self.clientKeyID = clientKeyID
        self.publicKeyRaw = publicKeyRaw
        self.lineageID = lineageID
        self.permissions = permissions
        self.status = status
        self.registeredAtMilliseconds = registeredAtMilliseconds
        self.revokedReason = revokedReason
    }
}

public enum LOCALBPairingProofV1 {
    public static let domain = "SIMIGO_PERSISTENT_SRS_LOCALB_CLIENT_POP_V1"

    /// Canonical proof-of-possession input; all binding values are length-prefixed.
    public static func signatureInput(credentialID: String, sessionNonce: [UInt8],
                                      hostInstanceID: String, tlsSPKIHash: String,
                                      srsKeyID: String, protocolVersion: String,
                                      clientPublicKeyRaw: [UInt8]) throws -> [UInt8] {
        guard localBIsCanonicalUUID(credentialID),
              localBIsCanonicalUUID(hostInstanceID),
              sessionNonce.count == 16,
              clientPublicKeyRaw.count == 32,
              Self.isHex64(tlsSPKIHash), Self.isHex64(srsKeyID),
              protocolVersion == LOCALBConstants.credentialProtocolVersion else {
            throw LOCALBStatus.invalidConfiguration
        }
        let fields: [(String, UInt8, [UInt8])] = [
            ("credential_id", 0x02, Array(credentialID.utf8)),
            ("session_nonce", 0x04, sessionNonce),
            ("host_instance_id", 0x02, Array(hostInstanceID.utf8)),
            ("tls_spki_sha256", 0x02, Array(tlsSPKIHash.utf8)),
            ("srs_key_id", 0x02, Array(srsKeyID.utf8)),
            ("protocol_version", 0x02, Array(protocolVersion.utf8)),
            ("client_public_key_raw", 0x04, clientPublicKeyRaw)
        ]
        return try LOCALBPairingFieldCodec.encode(
            domain: Self.domain, fields: fields
        )
    }

    public static func sign(credentialID: String, sessionNonce: [UInt8],
                            hostInstanceID: String, tlsSPKIHash: String,
                            srsKeyID: String, protocolVersion: String,
                            with key: Curve25519.Signing.PrivateKey) throws -> [UInt8] {
        let publicKey = Array(key.publicKey.rawRepresentation)
        let input = try signatureInput(
            credentialID: credentialID, sessionNonce: sessionNonce,
            hostInstanceID: hostInstanceID, tlsSPKIHash: tlsSPKIHash,
            srsKeyID: srsKeyID, protocolVersion: protocolVersion,
            clientPublicKeyRaw: publicKey
        )
        return Array(try key.signature(for: Data(input)))
    }

    static func verify(signature: [UInt8], credential: LOCALBPairingCredentialEntry,
                       clientPublicKeyRaw: [UInt8]) -> Bool {
        guard signature.count == 64,
              let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: Data(clientPublicKeyRaw)),
              let input = try? signatureInput(
                credentialID: credential.credentialID,
                sessionNonce: credential.sessionNonce,
                hostInstanceID: credential.hostInstanceID,
                tlsSPKIHash: credential.tlsSPKIHash,
                srsKeyID: credential.srsKeyID,
                protocolVersion: credential.protocolVersion,
                clientPublicKeyRaw: clientPublicKeyRaw
              ) else { return false }
        return publicKey.isValidSignature(Data(signature), for: Data(input))
    }

    static func isHex64(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 64 && bytes.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
        }
    }
}

public struct LOCALBPairingSubmission {
    /// The secret is request-scoped; this value deliberately is not Codable
    /// and must never be logged.
    public let credentialID: String
    public let secretRaw: [UInt8]
    public let clientPublicKeyRaw: [UInt8]
    public let proofSignatureRaw: [UInt8]
    public let actualTLSSPKIHash: String
    public let presentedSRSKeyID: String
    public let protocolVersion: String

    public init(credentialID: String, secretRaw: [UInt8], clientPublicKeyRaw: [UInt8],
                proofSignatureRaw: [UInt8], actualTLSSPKIHash: String,
                presentedSRSKeyID: String, protocolVersion: String = LOCALBConstants.credentialProtocolVersion) {
        self.credentialID = credentialID
        self.secretRaw = secretRaw
        self.clientPublicKeyRaw = clientPublicKeyRaw
        self.proofSignatureRaw = proofSignatureRaw
        self.actualTLSSPKIHash = actualTLSSPKIHash
        self.presentedSRSKeyID = presentedSRSKeyID
        self.protocolVersion = protocolVersion
    }

    /// Decode canonical unpadded Base64URL into the exact 32 raw bytes used by
    /// the credential digest. The display string is never the digest input.
    public static func decodeSecretBase64URL(_ value: String) throws -> [UInt8] {
        guard !value.isEmpty,
              value.utf8.allSatisfy({
                  ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) ||
                  ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D || $0 == 0x5F
              }) else {
            throw LOCALBStatus.invalidCredentialSecret
        }
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - (base64.utf8.count % 4)) % 4)
        guard let decoded = Data(base64Encoded: base64), decoded.count == 32 else {
            throw LOCALBStatus.invalidCredentialSecret
        }
        let canonical = decoded.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard canonical == value else { throw LOCALBStatus.invalidCredentialSecret }
        return Array(decoded)
    }
}

public struct LOCALBPairingApprovalRequest {
    public let credentialID: String
    public let scopeLabel: String
    public let clientKeyID: String
    public let clientPublicKeyFingerprint: String
    public let sessionNonceShort: String
    public let confirmationMode: LOCALBPairingConfirmationMode
    public let requiresOperatorConfirmation: Bool

    let clientPublicKeyRaw: [UInt8]
    let proofSignatureRaw: [UInt8]
    let actualTLSSPKIHash: String
    let presentedSRSKeyID: String
    let protocolVersion: String
    let credentialDigest: [UInt8]

    init(credential: LOCALBPairingCredentialEntry, clientPublicKeyRaw: [UInt8],
         proofSignatureRaw: [UInt8], actualTLSSPKIHash: String,
         presentedSRSKeyID: String, protocolVersion: String) throws {
        self.credentialID = credential.credentialID
        self.scopeLabel = credential.scopeLabel
        self.clientKeyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: clientPublicKeyRaw)
        self.clientPublicKeyFingerprint = LOCALBBinary.hexLower(LOCALBBinary.sha256(clientPublicKeyRaw))
        self.sessionNonceShort = LOCALBBinary.hexLower(credential.sessionNonce.prefix(4).map { $0 })
        self.confirmationMode = credential.confirmationMode
        self.requiresOperatorConfirmation = credential.confirmationMode == .interactive
        self.clientPublicKeyRaw = clientPublicKeyRaw
        self.proofSignatureRaw = proofSignatureRaw
        self.actualTLSSPKIHash = actualTLSSPKIHash
        self.presentedSRSKeyID = presentedSRSKeyID
        self.protocolVersion = protocolVersion
        self.credentialDigest = credential.digest
    }
}

public struct LOCALBPairingCredentialSummary: Equatable, Sendable {
    public let credentialID: String
    public let status: LOCALBPairingCredentialStatus
    public let expiresAtMilliseconds: UInt64
    public let scopeLabel: String
    public let confirmationMode: LOCALBPairingConfirmationMode
    public let expectedClientKeyFingerprint: String?
}

public struct LOCALBPairingCredentialListing: Sendable {
    public let registryCheckpoint: LOCALBRegistryCheckpoint
    public let credentials: [LOCALBPairingCredentialSummary]
}

/// One-time host-side display package. The credential secret can be taken only
/// once after the durable ISSUED event has been written.
public final class LOCALBPairingCredentialPresentation {
    public let credentialID: String
    public let expiresAtMilliseconds: UInt64
    public let hostInstanceID: String
    public let tlsSPKIHash: String
    public let srsKeyID: String
    public let protocolVersion: String
    public let sessionNonceHex: String
    public let scopeLabel: String
    public let confirmationMode: LOCALBPairingConfirmationMode
    /// The exact registry head after the durable Issued event.
    public let registryCheckpoint: LOCALBRegistryCheckpoint

    private var secretStorage: String?
    private let lock = NSLock()

    init(entry: LOCALBPairingCredentialEntry, secretBase64URL: String,
         registryCheckpoint: LOCALBRegistryCheckpoint) {
        self.credentialID = entry.credentialID
        self.expiresAtMilliseconds = entry.expiresAtMilliseconds
        self.hostInstanceID = entry.hostInstanceID
        self.tlsSPKIHash = entry.tlsSPKIHash
        self.srsKeyID = entry.srsKeyID
        self.protocolVersion = entry.protocolVersion
        self.sessionNonceHex = LOCALBBinary.hexLower(entry.sessionNonce)
        self.scopeLabel = entry.scopeLabel
        self.confirmationMode = entry.confirmationMode
        self.registryCheckpoint = registryCheckpoint
        self.secretStorage = secretBase64URL
    }

    public func takeSecretBase64URLOnce() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let value = secretStorage else { throw LOCALBStatus.invalidCredentialSecret }
        secretStorage = nil
        return value
    }
}

enum LOCALBPairingFieldCodec {
    struct Field: Equatable {
        let label: String
        let type: UInt8
        let value: [UInt8]
    }

    static func encode(domain: String? = nil, fields: [(String, UInt8, [UInt8])]) throws -> [UInt8] {
        var output: [UInt8] = []
        if let domain {
            output.append(contentsOf: Array(domain.utf8))
            output.append(0x00)
        }
        LOCALBBinary.appendU32(UInt32(fields.count), to: &output)
        for (label, type, value) in fields {
            try LOCALBBinary.appendField(label: label, type: type, value: value, to: &output)
        }
        return output
    }

    static func decode(_ bytes: [UInt8], expected: [(String, UInt8)]) throws -> [Field] {
        var offset = 0
        guard let count = LOCALBBinary.readU32(bytes, &offset), count == UInt32(expected.count) else {
            throw LOCALBStatus.registryCorrupt
        }
        var result: [Field] = []
        result.reserveCapacity(expected.count)
        for (expectedLabel, expectedType) in expected {
            guard let labelLength = LOCALBBinary.readU16(bytes, &offset) else {
                throw LOCALBStatus.registryCorrupt
            }
            let labelCount = Int(labelLength)
            guard labelCount > 0, offset <= bytes.count, bytes.count - offset >= labelCount,
                  let label = String(bytes: bytes[offset..<(offset + labelCount)], encoding: .utf8) else {
                throw LOCALBStatus.registryCorrupt
            }
            offset += labelCount
            guard label == expectedLabel, offset < bytes.count, bytes[offset] == expectedType else {
                throw LOCALBStatus.registryCorrupt
            }
            offset += 1
            guard let valueLength = LOCALBBinary.readU64(bytes, &offset),
                  valueLength <= UInt64(Int.max),
                  offset <= bytes.count, bytes.count - offset >= Int(valueLength) else {
                throw LOCALBStatus.registryCorrupt
            }
            let count = Int(valueLength)
            result.append(Field(label: label, type: expectedType,
                                value: Array(bytes[offset..<(offset + count)])))
            offset += count
        }
        guard offset == bytes.count else { throw LOCALBStatus.registryCorrupt }
        return result
    }

    static func string(_ value: String) -> (String, UInt8, [UInt8]) {
        (value, 0x02, Array(value.utf8))
    }

    static func string(_ label: String, value: String) -> (String, UInt8, [UInt8]) {
        (label, 0x02, Array(value.utf8))
    }

    static func bytes(_ value: [UInt8], label: String) -> (String, UInt8, [UInt8]) {
        (label, 0x04, value)
    }

    static func uint32(_ value: UInt32, label: String) -> (String, UInt8, [UInt8]) {
        var bytes: [UInt8] = []
        LOCALBBinary.appendU32(value, to: &bytes)
        return (label, 0x04, bytes)
    }

    static func uint64(_ value: UInt64, label: String) -> (String, UInt8, [UInt8]) {
        var bytes: [UInt8] = []
        LOCALBBinary.appendU64(value, to: &bytes)
        return (label, 0x04, bytes)
    }

    static func parseString(_ field: Field) throws -> String {
        guard field.type == 0x02,
              let value = String(bytes: field.value, encoding: .utf8) else {
            throw LOCALBStatus.registryCorrupt
        }
        return value
    }

    static func parseUInt32(_ field: Field) throws -> UInt32 {
        guard field.type == 0x04, field.value.count == 4 else { throw LOCALBStatus.registryCorrupt }
        var offset = 0
        guard let value = LOCALBBinary.readU32(field.value, &offset) else { throw LOCALBStatus.registryCorrupt }
        return value
    }

    static func parseUInt64(_ field: Field) throws -> UInt64 {
        guard field.type == 0x04, field.value.count == 8 else { throw LOCALBStatus.registryCorrupt }
        var offset = 0
        guard let value = LOCALBBinary.readU64(field.value, &offset) else { throw LOCALBStatus.registryCorrupt }
        return value
    }
}

struct LOCALBPairingStateView {
    let lineageID: String
    let signingKeys: [LOCALBRegistryKeyEntry]
    let credentials: [String: LOCALBPairingCredentialEntry]
    let clients: [String: LOCALBClientRegistryEntry]
}

struct LOCALBPairingCommitPayload {
    let credentialID: String
    let credentialDigest: [UInt8]
    let clientPublicKeyRaw: [UInt8]
    let clientKeyID: String
    let permissions: Set<LOCALBPermission>
    let registeredAtMilliseconds: UInt64
    let proofSignatureRaw: [UInt8]
    let tlsSPKIHash: String
    let srsKeyID: String
    let protocolVersion: String
    let operatorAuthorizationReference: String
}

enum LOCALBPairingEventCodec {
    private static let credentialIssuedSchema: [(String, UInt8)] = [
        ("credential_id", 0x02), ("credential_digest", 0x04),
        ("issued_at_ms", 0x04), ("expires_at_ms", 0x04),
        ("host_instance_id", 0x02), ("tls_spki_sha256", 0x02),
        ("srs_key_id", 0x02), ("issuer_generation", 0x04),
        ("protocol_version", 0x02), ("session_nonce", 0x04),
        ("scope_label", 0x02), ("confirmation_mode", 0x02),
        ("expected_client_key_fingerprint", 0x02)
    ]

    private static let pairingCommitSchema: [(String, UInt8)] = [
        ("credential_id", 0x02), ("credential_digest", 0x04),
        ("client_public_key_raw", 0x04), ("client_key_id", 0x02),
        ("permissions", 0x04), ("registered_at_ms", 0x04),
        ("proof_signature_raw", 0x04), ("tls_spki_sha256", 0x02),
        ("srs_key_id", 0x02), ("protocol_version", 0x02),
        ("operator_authorization_reference", 0x02)
    ]

    static func encodeCredentialIssued(_ entry: LOCALBPairingCredentialEntry) throws -> [UInt8] {
        guard entry.status == .issued else { throw LOCALBStatus.registryCorrupt }
        return try LOCALBPairingFieldCodec.encode(fields: [
            LOCALBPairingFieldCodec.string("credential_id", value: entry.credentialID),
            LOCALBPairingFieldCodec.bytes(entry.digest, label: "credential_digest"),
            LOCALBPairingFieldCodec.uint64(entry.issuedAtMilliseconds, label: "issued_at_ms"),
            LOCALBPairingFieldCodec.uint64(entry.expiresAtMilliseconds, label: "expires_at_ms"),
            LOCALBPairingFieldCodec.string("host_instance_id", value: entry.hostInstanceID),
            LOCALBPairingFieldCodec.string("tls_spki_sha256", value: entry.tlsSPKIHash),
            LOCALBPairingFieldCodec.string("srs_key_id", value: entry.srsKeyID),
            LOCALBPairingFieldCodec.uint32(entry.issuerGeneration, label: "issuer_generation"),
            LOCALBPairingFieldCodec.string("protocol_version", value: entry.protocolVersion),
            LOCALBPairingFieldCodec.bytes(entry.sessionNonce, label: "session_nonce"),
            LOCALBPairingFieldCodec.string("scope_label", value: entry.scopeLabel),
            LOCALBPairingFieldCodec.string("confirmation_mode", value: entry.confirmationMode.rawValue),
            LOCALBPairingFieldCodec.string("expected_client_key_fingerprint",
                                           value: entry.expectedClientKeyFingerprint ?? "")
        ])
    }

    static func decodeCredentialIssued(_ payload: [UInt8]) throws -> LOCALBPairingCredentialEntry {
        let f = try LOCALBPairingFieldCodec.decode(payload, expected: credentialIssuedSchema)
        let id = try LOCALBPairingFieldCodec.parseString(f[0])
        let digest = f[1].value
        let issued = try LOCALBPairingFieldCodec.parseUInt64(f[2])
        let expiry = try LOCALBPairingFieldCodec.parseUInt64(f[3])
        let host = try LOCALBPairingFieldCodec.parseString(f[4])
        let tls = try LOCALBPairingFieldCodec.parseString(f[5])
        let srsKey = try LOCALBPairingFieldCodec.parseString(f[6])
        let generation = try LOCALBPairingFieldCodec.parseUInt32(f[7])
        let protocolVersion = try LOCALBPairingFieldCodec.parseString(f[8])
        let nonce = f[9].value
        let scope = try LOCALBPairingFieldCodec.parseString(f[10])
        let modeText = try LOCALBPairingFieldCodec.parseString(f[11])
        let expected = try LOCALBPairingFieldCodec.parseString(f[12])
        guard let mode = LOCALBPairingConfirmationMode(rawValue: modeText) else {
            throw LOCALBStatus.registryCorrupt
        }
        return LOCALBPairingCredentialEntry(
            credentialID: id, digest: digest, issuedAtMilliseconds: issued,
            expiresAtMilliseconds: expiry, hostInstanceID: host, tlsSPKIHash: tls,
            srsKeyID: srsKey, issuerGeneration: generation, protocolVersion: protocolVersion,
            sessionNonce: nonce, scopeLabel: scope, confirmationMode: mode,
            expectedClientKeyFingerprint: expected.isEmpty ? nil : expected
        )
    }

    static func encodePairingCommit(_ value: LOCALBPairingCommitPayload) throws -> [UInt8] {
        guard value.credentialDigest.count == 32, value.clientPublicKeyRaw.count == 32,
              value.proofSignatureRaw.count == 64 else { throw LOCALBStatus.registryCorrupt }
        return try LOCALBPairingFieldCodec.encode(fields: [
            LOCALBPairingFieldCodec.string("credential_id", value: value.credentialID),
            LOCALBPairingFieldCodec.bytes(value.credentialDigest, label: "credential_digest"),
            LOCALBPairingFieldCodec.bytes(value.clientPublicKeyRaw, label: "client_public_key_raw"),
            LOCALBPairingFieldCodec.string("client_key_id", value: value.clientKeyID),
            LOCALBPairingFieldCodec.bytes(encodePermissions(value.permissions), label: "permissions"),
            LOCALBPairingFieldCodec.uint64(value.registeredAtMilliseconds, label: "registered_at_ms"),
            LOCALBPairingFieldCodec.bytes(value.proofSignatureRaw, label: "proof_signature_raw"),
            LOCALBPairingFieldCodec.string("tls_spki_sha256", value: value.tlsSPKIHash),
            LOCALBPairingFieldCodec.string("srs_key_id", value: value.srsKeyID),
            LOCALBPairingFieldCodec.string("protocol_version", value: value.protocolVersion),
            LOCALBPairingFieldCodec.string("operator_authorization_reference",
                                           value: value.operatorAuthorizationReference)
        ])
    }

    static func decodePairingCommit(_ payload: [UInt8]) throws -> LOCALBPairingCommitPayload {
        let f = try LOCALBPairingFieldCodec.decode(payload, expected: pairingCommitSchema)
        return LOCALBPairingCommitPayload(
            credentialID: try LOCALBPairingFieldCodec.parseString(f[0]),
            credentialDigest: f[1].value,
            clientPublicKeyRaw: f[2].value,
            clientKeyID: try LOCALBPairingFieldCodec.parseString(f[3]),
            permissions: try decodePermissions(f[4].value),
            registeredAtMilliseconds: try LOCALBPairingFieldCodec.parseUInt64(f[5]),
            proofSignatureRaw: f[6].value,
            tlsSPKIHash: try LOCALBPairingFieldCodec.parseString(f[7]),
            srsKeyID: try LOCALBPairingFieldCodec.parseString(f[8]),
            protocolVersion: try LOCALBPairingFieldCodec.parseString(f[9]),
            operatorAuthorizationReference: try LOCALBPairingFieldCodec.parseString(f[10])
        )
    }

    static func encodeCredentialDisposition(credentialID: String, digest: [UInt8],
                                            reason: String) throws -> [UInt8] {
        guard digest.count == 32, !reason.isEmpty, reason.utf8.count <= 512 else {
            throw LOCALBStatus.registryInvalidTransition
        }
        return try LOCALBPairingFieldCodec.encode(fields: [
            LOCALBPairingFieldCodec.string("credential_id", value: credentialID),
            LOCALBPairingFieldCodec.bytes(digest, label: "credential_digest"),
            LOCALBPairingFieldCodec.string("reason", value: reason)
        ])
    }

    static func decodeCredentialDisposition(_ payload: [UInt8]) throws -> (String, [UInt8], String) {
        let f = try LOCALBPairingFieldCodec.decode(payload, expected: [
            ("credential_id", 0x02), ("credential_digest", 0x04), ("reason", 0x02)
        ])
        let id = try LOCALBPairingFieldCodec.parseString(f[0])
        let reason = try LOCALBPairingFieldCodec.parseString(f[2])
        guard !reason.isEmpty, reason.utf8.count <= 512 else { throw LOCALBStatus.registryCorrupt }
        return (id, f[1].value, reason)
    }

    static func encodeClientRevocation(clientKeyID: String, reason: String) throws -> [UInt8] {
        guard LOCALBPairingProofV1.isHex64(clientKeyID), !reason.isEmpty, reason.utf8.count <= 512 else {
            throw LOCALBStatus.registryInvalidTransition
        }
        return try LOCALBPairingFieldCodec.encode(fields: [
            LOCALBPairingFieldCodec.string("client_key_id", value: clientKeyID),
            LOCALBPairingFieldCodec.string("reason", value: reason)
        ])
    }

    static func decodeClientRevocation(_ payload: [UInt8]) throws -> (String, String) {
        let f = try LOCALBPairingFieldCodec.decode(payload, expected: [
            ("client_key_id", 0x02), ("reason", 0x02)
        ])
        let id = try LOCALBPairingFieldCodec.parseString(f[0])
        let reason = try LOCALBPairingFieldCodec.parseString(f[1])
        guard LOCALBPairingProofV1.isHex64(id), !reason.isEmpty, reason.utf8.count <= 512 else {
            throw LOCALBStatus.registryCorrupt
        }
        return (id, reason)
    }

    static func encodePermissionChange(clientKeyID: String, permissions: Set<LOCALBPermission>,
                                       reason: String) throws -> [UInt8] {
        guard LOCALBPairingProofV1.isHex64(clientKeyID), !reason.isEmpty, reason.utf8.count <= 512,
              !permissions.contains(.srsWrite) else {
            throw LOCALBStatus.registryInvalidTransition
        }
        return try LOCALBPairingFieldCodec.encode(fields: [
            LOCALBPairingFieldCodec.string("client_key_id", value: clientKeyID),
            LOCALBPairingFieldCodec.bytes(encodePermissions(permissions), label: "permissions"),
            LOCALBPairingFieldCodec.string("reason", value: reason)
        ])
    }

    static func decodePermissionChange(_ payload: [UInt8]) throws -> (String, Set<LOCALBPermission>, String) {
        let f = try LOCALBPairingFieldCodec.decode(payload, expected: [
            ("client_key_id", 0x02), ("permissions", 0x04), ("reason", 0x02)
        ])
        let id = try LOCALBPairingFieldCodec.parseString(f[0])
        let permissions = try decodePermissions(f[1].value)
        let reason = try LOCALBPairingFieldCodec.parseString(f[2])
        guard LOCALBPairingProofV1.isHex64(id), !permissions.contains(.srsWrite),
              !reason.isEmpty, reason.utf8.count <= 512 else { throw LOCALBStatus.registryCorrupt }
        return (id, permissions, reason)
    }

    private static func encodePermissions(_ permissions: Set<LOCALBPermission>) -> [UInt8] {
        let values = permissions.sorted().map { Array($0.rawValue.utf8) }
        var output: [UInt8] = []
        LOCALBBinary.appendU16(UInt16(values.count), to: &output)
        for value in values {
            LOCALBBinary.appendU16(UInt16(value.count), to: &output)
            output.append(contentsOf: value)
        }
        return output
    }

    private static func decodePermissions(_ bytes: [UInt8]) throws -> Set<LOCALBPermission> {
        var offset = 0
        guard let count = LOCALBBinary.readU16(bytes, &offset), count <= 5 else {
            throw LOCALBStatus.registryCorrupt
        }
        var result = Set<LOCALBPermission>()
        var previous: String?
        for _ in 0..<count {
            guard let length = LOCALBBinary.readU16(bytes, &offset) else { throw LOCALBStatus.registryCorrupt }
            let size = Int(length)
            guard size > 0, offset <= bytes.count, bytes.count - offset >= size,
                  let raw = String(bytes: bytes[offset..<(offset + size)], encoding: .utf8),
                  let permission = LOCALBPermission(rawValue: raw),
                  !result.contains(permission),
                  previous == nil || previous! < raw else {
                throw LOCALBStatus.registryCorrupt
            }
            result.insert(permission)
            previous = raw
            offset += size
        }
        guard offset == bytes.count, !result.contains(.srsWrite) else {
            throw LOCALBStatus.registryCorrupt
        }
        return result
    }
}

/// Immutable request representation used by both signature verification and dispatch.
/// The adapter MUST construct this from the exact parsed request and must dispatch
/// the returned LOCALBAuthorizedRequest.request, never a separately reparsed body.
public struct LOCALBHTTPRequestV1: Equatable, Sendable {
    /// Hard cap for protected request bodies. The HTTP adapter must enforce
    /// the same cap before buffering body bytes, not only after parsing.
    public static let maximumBodyBytes = 64 * 1_048_576

    public let method: String
    public let authority: String
    /// Exact canonical origin-form target authenticated by V2, including any query.
    public let requestTarget: String
    /// Route key derived exactly once from requestTarget after validation.
    /// Dispatch must use authorized.request.routePath, never a pre-auth parser path.
    public let routePath: String
    /// Query without '?'; nil means no query delimiter, while "" means an empty query.
    /// Query-dependent behavior must consume authorized.request.query.
    public let query: String?
    public let contentType: String
    public let contentEncoding: String
    public let bodyRaw: [UInt8]
    public let bodySHA256Hex: String
    public let bodyLength: UInt64

    public init(
        method: String,
        authority: String,
        requestTarget: String,
        contentType: String? = nil,
        contentEncoding: String = "identity",
        bodyRaw: [UInt8]
    ) throws {
        let selectedContentType = contentType ?? ""
        guard Self.isCanonicalMethod(method),
              Self.isCanonicalAuthority(authority),
              Self.isCanonicalTarget(requestTarget),
              Self.isCanonicalHeaderValue(selectedContentType, maximumBytes: 512),
              contentEncoding == "identity",
              bodyRaw.count <= Self.maximumBodyBytes else {
            throw LOCALBStatus.invalidProtectedRequest
        }
        let targetParts = Self.splitCanonicalTarget(requestTarget)
        self.method = method
        self.authority = authority
        self.requestTarget = requestTarget
        self.routePath = targetParts.path
        self.query = targetParts.query
        self.contentType = selectedContentType
        self.contentEncoding = contentEncoding
        self.bodyRaw = bodyRaw
        self.bodySHA256Hex = LOCALBBinary.hexLower(LOCALBBinary.sha256(bodyRaw))
        self.bodyLength = UInt64(bodyRaw.count)
    }

    private static func isCanonicalMethod(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 16 else { return false }
        return bytes.allSatisfy {
            ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D
        }
    }

    /// Authority is lower-case ASCII as consumed by routing; aliases must be
    /// normalized by the HTTP adapter before constructing this value.
    private static func isCanonicalAuthority(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 255,
              value == value.lowercased(),
              bytes.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else {
            return false
        }

        let host: String
        let port: String?
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]"), close > value.startIndex else {
                return false
            }
            host = String(value[value.index(after: value.startIndex)..<close])
            let suffix = String(value[value.index(after: close)...])
            if suffix.isEmpty {
                port = nil
            } else {
                guard suffix.first == ":" else { return false }
                port = String(suffix.dropFirst())
            }
            guard isCanonicalIPv6Literal(host) else { return false }
        } else {
            let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count <= 2, !pieces[0].isEmpty else { return false }
            host = String(pieces[0])
            port = pieces.count == 2 ? String(pieces[1]) : nil
            guard isCanonicalDNSOrIPv4Host(host) else { return false }
        }

        if let port {
            guard isCanonicalPort(port) else { return false }
        }
        return true
    }

    private static func isCanonicalPort(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 5,
              bytes.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
              !(bytes.count > 1 && bytes[0] == 0x30),
              let parsed = UInt32(value), parsed >= 1, parsed <= 65_535 else {
            return false
        }
        return true
    }

    private static func isCanonicalDNSOrIPv4Host(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 253,
              bytes.first != 0x2E, bytes.last != 0x2E else {
            return false
        }
        let numericLike = bytes.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2E
        }
        if numericLike {
            let octets = value.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4 else { return false }
            for octet in octets {
                let octetBytes = Array(octet.utf8)
                guard !octetBytes.isEmpty, octetBytes.count <= 3,
                      octetBytes.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                      !(octetBytes.count > 1 && octetBytes[0] == 0x30),
                      let number = UInt16(String(octet)), number <= 255 else {
                    return false
                }
            }
            return true
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        for label in labels {
            let labelBytes = Array(label.utf8)
            guard !labelBytes.isEmpty, labelBytes.count <= 63,
                  isASCIIAlphaNumeric(labelBytes[0]),
                  isASCIIAlphaNumeric(labelBytes[labelBytes.count - 1]),
                  labelBytes.allSatisfy({ isASCIIAlphaNumeric($0) || $0 == 0x2D }) else {
                return false
            }
        }
        return true
    }

    private static func isCanonicalIPv6Literal(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.contains(0x3A), !value.contains(":::"),
              bytes.allSatisfy({
                  ($0 >= 0x30 && $0 <= 0x39) ||
                  ($0 >= 0x61 && $0 <= 0x66) || $0 == 0x3A
              }) else {
            return false
        }

        func validGroup(_ group: Substring) -> Bool {
            let groupBytes = Array(group.utf8)
            return !groupBytes.isEmpty && groupBytes.count <= 4 && groupBytes.allSatisfy {
                ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
            }
        }

        if let compression = value.range(of: "::") {
            guard value[compression.upperBound...].range(of: "::") == nil else {
                return false
            }
            let leftText = String(value[..<compression.lowerBound])
            let rightText = String(value[compression.upperBound...])
            let left: [Substring] = leftText.isEmpty ? [] : leftText.split(separator: ":", omittingEmptySubsequences: false)
            let right: [Substring] = rightText.isEmpty ? [] : rightText.split(separator: ":", omittingEmptySubsequences: false)
            let groups = left + right
            return groups.count < 8 && groups.allSatisfy(validGroup)
        }

        let groups = value.split(separator: ":", omittingEmptySubsequences: false)
        return groups.count == 8 && groups.allSatisfy(validGroup)
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x61 && byte <= 0x7A)
    }

    /// Strict origin-form target. This rejects fragments, ambiguous path
    /// separators/dot segments, non-canonical percent escapes, and escaped
    /// path separators. The exact accepted target is signed and must also be
    /// the target used for routing (no post-verification normalization).
    private static func isCanonicalTarget(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 8_192, bytes[0] == 0x2F,
              !(bytes.count > 1 && bytes[1] == 0x2F),
              bytes.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E && $0 != 0x5C && $0 != 0x23 }) else {
            return false
        }
        let queryStart = bytes.firstIndex(of: 0x3F) ?? bytes.count
        let pathBytes = Array(bytes[..<queryStart])
        let path = String(decoding: pathBytes, as: UTF8.self)
        guard !path.contains("//") else { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.contains(where: { $0 == "." || $0 == ".." }) else { return false }

        func isAllowedRawTargetByte(_ byte: UInt8, inQuery: Bool) -> Bool {
            if Self.isUnreserved(byte) { return true }
            // RFC 3986 sub-delimiters plus ':' and '@' are valid pchar bytes.
            switch byte {
            case 0x21, 0x24, 0x26, 0x27, 0x28, 0x29, 0x2A,
                 0x2B, 0x2C, 0x3B, 0x3D, 0x3A, 0x40, 0x2F:
                return true
            case 0x3F:
                return inQuery
            default:
                return false
            }
        }

        var index = 0
        var encodedUTF8Run: [UInt8] = []
        while index < bytes.count {
            guard bytes[index] == 0x25 else {
                if !encodedUTF8Run.isEmpty {
                    guard String(bytes: encodedUTF8Run, encoding: .utf8) != nil else {
                        return false
                    }
                    encodedUTF8Run.removeAll(keepingCapacity: true)
                }
                // The first '?' is the path/query delimiter; later '?' bytes
                // are valid query characters and are accepted by the helper.
                if index == queryStart {
                    index += 1
                    continue
                }
                guard isAllowedRawTargetByte(
                    bytes[index],
                    inQuery: index > queryStart
                ) else {
                    return false
                }
                index += 1
                continue
            }
            guard index + 2 < bytes.count,
                  let high = Self.hexNibble(bytes[index + 1]),
                  let low = Self.hexNibble(bytes[index + 2]) else {
                return false
            }
            let decoded = (high << 4) | low
            guard !Self.isUnreserved(decoded), decoded >= 0x20, decoded != 0x7F,
                  decoded != 0x5C else {
                return false
            }
            if decoded < 0x80 {
                if index < queryStart { return false }
                if !encodedUTF8Run.isEmpty {
                    guard String(bytes: encodedUTF8Run, encoding: .utf8) != nil else {
                        return false
                    }
                    encodedUTF8Run.removeAll(keepingCapacity: true)
                }
            } else {
                encodedUTF8Run.append(decoded)
            }
            index += 3
        }
        if !encodedUTF8Run.isEmpty,
           String(bytes: encodedUTF8Run, encoding: .utf8) == nil {
            return false
        }
        return true
    }

    /// Split only after the full target passes canonical validation. The original
    /// requestTarget remains the signed field; routePath/query are immutable views
    /// derived from that same value, avoiding a second parse of HTTPRequest.path.
    private static func splitCanonicalTarget(_ value: String) -> (path: String, query: String?) {
        let bytes = Array(value.utf8)
        guard let queryStart = bytes.firstIndex(of: 0x3F) else {
            return (value, nil)
        }
        let path = String(decoding: bytes[..<queryStart], as: UTF8.self)
        let query = String(decoding: bytes[(queryStart + 1)...], as: UTF8.self)
        return (path, query)
    }

    private static func isCanonicalHeaderValue(_ value: String, maximumBytes: Int) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count <= maximumBytes else { return false }
        if bytes.isEmpty { return true }
        guard bytes.first != 0x20, bytes.last != 0x20 else { return false }
        return bytes.allSatisfy { $0 >= 0x20 && $0 <= 0x7E }
    }

    /// Canonical percent-escape hex digits are uppercase only.
    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        if byte >= 0x30 && byte <= 0x39 { return byte - 0x30 }
        if byte >= 0x41 && byte <= 0x46 { return byte - 0x41 + 10 }
        return nil
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
    }
}

public struct LOCALBAuthorizedRequest: Equatable, Sendable {
    public let client: LOCALBClientRegistryEntry
    public let permission: LOCALBPermission
    public let request: LOCALBHTTPRequestV1

    fileprivate init(client: LOCALBClientRegistryEntry, permission: LOCALBPermission,
                     request: LOCALBHTTPRequestV1) {
        self.client = client
        self.permission = permission
        self.request = request
    }
}

/// V2 replaces the prior challenge-only proof. A signature is valid only for
/// one exact method/authority/target/content-type/body tuple and one fresh
/// challenge. V1 proofs are not accepted by authorizeProtectedRequest.
public enum LOCALBClientRequestProofV2 {
    public static let domain = "SIMIGO_PERSISTENT_SRS_LOCALB_CLIENT_REQUEST_CONTENT_V2"
    public static let canonicalizationVersion = "LOCALB_HTTP_REQUEST_CANONICAL_V1"

    public static func signatureInput(
        clientKeyID: String,
        permission: LOCALBPermission,
        request: LOCALBHTTPRequestV1,
        challenge: [UInt8]
    ) throws -> [UInt8] {
        guard LOCALBPairingProofV1.isHex64(clientKeyID), challenge.count == 32 else {
            throw LOCALBStatus.invalidConfiguration
        }
        return try LOCALBPairingFieldCodec.encode(domain: domain, fields: [
            LOCALBPairingFieldCodec.string("canonicalization_version", value: canonicalizationVersion),
            LOCALBPairingFieldCodec.string("client_key_id", value: clientKeyID),
            LOCALBPairingFieldCodec.string("required_permission", value: permission.rawValue),
            LOCALBPairingFieldCodec.bytes(challenge, label: "server_challenge"),
            LOCALBPairingFieldCodec.string("http_method", value: request.method),
            LOCALBPairingFieldCodec.string("authority", value: request.authority),
            LOCALBPairingFieldCodec.string("request_target", value: request.requestTarget),
            LOCALBPairingFieldCodec.string("content_type", value: request.contentType),
            LOCALBPairingFieldCodec.string("content_encoding", value: request.contentEncoding),
            LOCALBPairingFieldCodec.string("body_sha256", value: request.bodySHA256Hex),
            LOCALBPairingFieldCodec.uint64(request.bodyLength, label: "body_length")
        ])
    }

    public static func sign(
        clientKeyID: String,
        permission: LOCALBPermission,
        request: LOCALBHTTPRequestV1,
        challenge: [UInt8],
        with key: Curve25519.Signing.PrivateKey
    ) throws -> [UInt8] {
        let input = try signatureInput(
            clientKeyID: clientKeyID, permission: permission, request: request, challenge: challenge
        )
        return Array(try key.signature(for: Data(input)))
    }
}

private final class LOCALBClientChallengeLedger {
    private struct IssuedChallenge {
        let clientKeyID: String
        let permission: LOCALBPermission
        let expiresAtMilliseconds: UInt64
    }

    private let lock = NSLock()
    private var issued: [String: IssuedChallenge] = [:]
    /// Per-client issuance timestamps inside the rolling rate window.
    private var issuanceLog: [String: [UInt64]] = [:]
    private let lifetimeMilliseconds: UInt64 = 60_000
    private let maximumPending = 8_192
    /// Resource-exhaustion hardening: a single client can neither dominate
    /// the global pending budget nor issue unboundedly, so unauthenticated
    /// TLS peers cannot starve legitimate clients of challenges.
    private let maximumPendingPerClient = 64
    private let issuanceWindowMilliseconds: UInt64 = 10_000
    private let maximumIssuesPerClientPerWindow = 128

    func issue(clientKeyID: String, permission: LOCALBPermission) throws -> [UInt8] {
        guard LOCALBPairingProofV1.isHex64(clientKeyID) else {
            throw LOCALBStatus.invalidConfiguration
        }
        var generator = SystemRandomNumberGenerator()
        let challenge = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let challengeID = LOCALBBinary.hexLower(LOCALBBinary.sha256(challenge))
        let now = Self.nowMilliseconds()
        lock.lock()
        defer { lock.unlock() }
        issued = issued.filter { $0.value.expiresAtMilliseconds > now }
        guard issued.count < maximumPending else { throw LOCALBStatus.resourceLimit }
        let pendingForClient = issued.values.lazy
            .filter { $0.clientKeyID == clientKeyID }
            .count
        guard pendingForClient < maximumPendingPerClient else {
            throw LOCALBStatus.resourceLimit
        }
        var recent = issuanceLog[clientKeyID]?.filter {
            $0 > now - issuanceWindowMilliseconds
        } ?? []
        guard recent.count < maximumIssuesPerClientPerWindow else {
            throw LOCALBStatus.challengeRateLimited
        }
        recent.append(now)
        issuanceLog[clientKeyID] = recent
        issued[challengeID] = IssuedChallenge(
            clientKeyID: clientKeyID,
            permission: permission,
            expiresAtMilliseconds: now + lifetimeMilliseconds
        )
        return challenge
    }

    func consume(_ challenge: [UInt8], clientKeyID: String, permission: LOCALBPermission) -> Bool {
        guard challenge.count == 32 else { return false }
        let challengeID = LOCALBBinary.hexLower(LOCALBBinary.sha256(challenge))
        let now = Self.nowMilliseconds()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = issued.removeValue(forKey: challengeID),
              entry.expiresAtMilliseconds > now,
              entry.clientKeyID == clientKeyID,
              entry.permission == permission else {
            return false
        }
        return true
    }

    private static func nowMilliseconds() -> UInt64 {
        let value = Date().timeIntervalSince1970 * 1_000
        return value > 0 ? UInt64(value) : 0
    }
}

public struct LOCALBPairingCoordinator {
    private let registryStore: LOCALBRegistryStore
    private let requestChallenges: LOCALBClientChallengeLedger

    public init(registryStore: LOCALBRegistryStore) {
        self.registryStore = registryStore
        self.requestChallenges = LOCALBClientChallengeLedger()
    }

    /// Local-management-plane operation only; do not expose this method on the
    /// unauthenticated inference/LAN API.
    public func issueCredential(
        scopeLabel: String,
        tlsSPKIHash: String,
        srsKeyID: String,
        mode: LOCALBPairingConfirmationMode = .interactive,
        expectedClientPublicKeyRaw: [UInt8]? = nil,
        checkpoint: LOCALBRegistryCheckpoint
    ) throws -> LOCALBPairingCredentialPresentation {
        let scopeBytes = Array(scopeLabel.utf8)
        guard !scopeBytes.isEmpty, scopeBytes.count <= 512,
              LOCALBPairingProofV1.isHex64(tlsSPKIHash),
              LOCALBPairingProofV1.isHex64(srsKeyID) else {
            throw LOCALBStatus.invalidConfiguration
        }
        let preIssueCheckpoint = try registryStore.expireDuePairingCredentials(checkpoint: checkpoint)
        let state = try registryStore.loadPairingState(checkpoint: preIssueCheckpoint)
        guard let issuer = state.signingKeys.first(where: { $0.keyID == srsKeyID }),
              issuer.status == .active,
              issuer.lineageID == state.lineageID else {
            throw LOCALBStatus.issuerKeyNotActive
        }

        let expectedFingerprint: String?
        switch mode {
        case .interactive:
            guard expectedClientPublicKeyRaw == nil else { throw LOCALBStatus.invalidConfiguration }
            expectedFingerprint = nil
        case .strictHeadless:
            guard let key = expectedClientPublicKeyRaw, key.count == 32 else {
                throw LOCALBStatus.invalidConfiguration
            }
            expectedFingerprint = LOCALBBinary.hexLower(LOCALBBinary.sha256(key))
        }

        let material = try LOCALBPairingCredentialMaterial.issue()
        let rawSecret = try material.takeSecretRawOnce()
        let now = Self.nowMilliseconds()
        let expiry = now + 5 * 60 * 1_000
        var generator = SystemRandomNumberGenerator()
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let credential = LOCALBPairingCredentialEntry(
            credentialID: material.credentialID,
            digest: material.digest,
            issuedAtMilliseconds: now,
            expiresAtMilliseconds: expiry,
            hostInstanceID: state.lineageID,
            tlsSPKIHash: tlsSPKIHash,
            srsKeyID: srsKeyID,
            issuerGeneration: issuer.generation,
            protocolVersion: LOCALBConstants.credentialProtocolVersion,
            sessionNonce: nonce,
            scopeLabel: scopeLabel,
            confirmationMode: mode,
            expectedClientKeyFingerprint: expectedFingerprint,
            status: .issued
        )
        let issuedCheckpoint = try registryStore.appendPairingCredentialIssued(
            credential, checkpoint: preIssueCheckpoint
        )
        let secretBase64URL = Data(rawSecret).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return LOCALBPairingCredentialPresentation(
            entry: credential, secretBase64URL: secretBase64URL,
            registryCheckpoint: issuedCheckpoint
        )
    }

    /// Phase V validates the secret without mutating credential state. Only a
    /// valid secret enters Phase P and authenticates TLS/key binding + PoP.
    public func preparePairing(_ submission: LOCALBPairingSubmission,
                               checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBPairingApprovalRequest {
        let state = try registryStore.loadPairingState(checkpoint: checkpoint)
        guard let credential = state.credentials[submission.credentialID] else {
            throw LOCALBStatus.pairingCredentialUnknown
        }
        // Phase V runs before credential-state disclosure. A wrong secret is
        // only an attempt failure and never changes or reveals terminal state.
        guard let calculatedDigest = try? LOCALBPairingCredentialMaterial.credentialDigest(
            credentialID: submission.credentialID, secretRaw: submission.secretRaw
        ), LOCALBBinary.constantTimeEqual(calculatedDigest, credential.digest) else {
            throw LOCALBStatus.invalidCredentialSecret
        }
        guard credential.status == .issued else {
            switch credential.status {
            case .consumed: throw LOCALBStatus.pairingCredentialConsumed
            case .revoked: throw LOCALBStatus.pairingCredentialRevoked
            case .expired: throw LOCALBStatus.pairingCredentialExpired
            case .issued: preconditionFailure("unreachable: guard excludes .issued")
            }
        }
        let now = Self.nowMilliseconds()
        guard now < credential.expiresAtMilliseconds else {
            // No journal mutation on this failed attempt. A local-management
            // expiry sweep will persist EXPIRED and return its new checkpoint.
            throw LOCALBStatus.pairingCredentialExpired
        }

        // Phase P: binding and PoP checks occur only after the secret is valid.
        guard submission.clientPublicKeyRaw.count == 32,
              submission.actualTLSSPKIHash == credential.tlsSPKIHash,
              submission.presentedSRSKeyID == credential.srsKeyID,
              submission.protocolVersion == credential.protocolVersion,
              credential.hostInstanceID == state.lineageID else {
            throw LOCALBStatus.pairingBindingMismatch
        }
        guard let issuer = state.signingKeys.first(where: { $0.keyID == credential.srsKeyID }),
              issuer.status == .active,
              issuer.generation == credential.issuerGeneration,
              issuer.lineageID == credential.hostInstanceID else {
            throw LOCALBStatus.issuerKeyNotActive
        }
        let fingerprint = LOCALBBinary.hexLower(LOCALBBinary.sha256(submission.clientPublicKeyRaw))
        if credential.confirmationMode == .strictHeadless,
           fingerprint != credential.expectedClientKeyFingerprint {
            throw LOCALBStatus.pairingBindingMismatch
        }
        guard LOCALBPairingProofV1.verify(
            signature: submission.proofSignatureRaw, credential: credential,
            clientPublicKeyRaw: submission.clientPublicKeyRaw
        ) else {
            throw LOCALBStatus.pairingProofInvalid
        }
        return try LOCALBPairingApprovalRequest(
            credential: credential, clientPublicKeyRaw: submission.clientPublicKeyRaw,
            proofSignatureRaw: submission.proofSignatureRaw,
            actualTLSSPKIHash: submission.actualTLSSPKIHash,
            presentedSRSKeyID: submission.presentedSRSKeyID,
            protocolVersion: submission.protocolVersion
        )
    }

    /// Interactive approval must come from the local management UI. Strict
    /// headless mode is pre-bound at issuance and therefore has no network-time
    /// approval switch. The registry commit itself consumes the credential and
    /// registers the client in exactly one durable event.
    @discardableResult
    public func approveAndRegister(_ pending: LOCALBPairingApprovalRequest,
                                   operatorApproved: Bool = false,
                                   operatorAuthorizationReference: String? = nil,
                                   checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        if pending.requiresOperatorConfirmation {
            guard operatorApproved,
                  let reference = operatorAuthorizationReference,
                  !reference.isEmpty, reference.utf8.count <= 512 else {
                throw LOCALBStatus.pairingOperatorApprovalRequired
            }
        } else {
            guard !operatorApproved, operatorAuthorizationReference == nil else {
                throw LOCALBStatus.invalidConfiguration
            }
        }
        return try registryStore.commitPairing(
            pending, operatorAuthorizationReference: operatorAuthorizationReference,
            checkpoint: checkpoint
        )
    }

    /// Issues a random, short-lived, one-time server challenge bound to the
    /// client key identity and the exact permission requested.
    /// Challenge issuance performs the SAME registry validation as
    /// authorization (unknown / revoked / under-privileged clients are
    /// refused BEFORE any challenge-ledger capacity is consumed), then
    /// applies per-client pending and rate limits inside the ledger.
    /// Authorization re-validates at consume time — revocation between
    /// issuance and use is still rejected there.
    public func issueRequestChallenge(clientKeyID: String,
                                      permission: LOCALBPermission,
                                      checkpoint: LOCALBRegistryCheckpoint) throws -> [UInt8] {
        let state = try registryStore.loadPairingState(checkpoint: checkpoint)
        guard let client = state.clients[clientKeyID] else {
            throw LOCALBStatus.clientUnknown
        }
        guard client.status == .active else {
            throw LOCALBStatus.clientRevoked
        }
        guard client.permissions.contains(permission) else {
            throw LOCALBStatus.permissionDenied
        }
        return try requestChallenges.issue(clientKeyID: clientKeyID, permission: permission)
    }

    /// Per-request authentication reloads verified state and consumes a
    /// challenge issued by this coordinator. Reuse, expiry, cross-client or
    /// cross-permission replay is rejected before registry authorization.
    /// Every authorization decision verifies the exact request representation
    /// returned to the caller. The HTTP adapter MUST dispatch using
    /// authorized.request (especially bodyRaw) and must derive the canonical
    /// target/authority from the same request bytes used by its router.
    public func authorizeProtectedRequest(
        clientKeyID: String,
        permission: LOCALBPermission,
        request: LOCALBHTTPRequestV1,
        challenge: [UInt8],
        proofSignatureRaw: [UInt8],
        checkpoint: LOCALBRegistryCheckpoint
    ) throws -> LOCALBAuthorizedRequest {
        guard requestChallenges.consume(challenge, clientKeyID: clientKeyID, permission: permission) else {
            throw LOCALBStatus.clientChallengeInvalid
        }
        let state = try registryStore.loadPairingState(checkpoint: checkpoint)
        guard let client = state.clients[clientKeyID] else { throw LOCALBStatus.clientUnknown }
        guard client.status == .active else { throw LOCALBStatus.clientRevoked }
        guard client.permissions.contains(permission) else { throw LOCALBStatus.permissionDenied }
        let expectedKeyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: client.publicKeyRaw)
        guard expectedKeyID == clientKeyID else { throw LOCALBStatus.registryCorrupt }
        guard proofSignatureRaw.count == 64,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: Data(client.publicKeyRaw)),
              let input = try? LOCALBClientRequestProofV2.signatureInput(
                clientKeyID: clientKeyID, permission: permission, request: request, challenge: challenge
              ),
              publicKey.isValidSignature(Data(proofSignatureRaw), for: Data(input)) else {
            throw LOCALBStatus.clientRequestSignatureInvalid
        }
        return LOCALBAuthorizedRequest(client: client, permission: permission, request: request)
    }
    /// Management UI listing. Expired credentials are persisted as terminal
    /// EXPIRED events; responses exclude both the bearer secret and its digest.
    public func listPairingCredentials(checkpoint: LOCALBRegistryCheckpoint) throws
        -> LOCALBPairingCredentialListing {
        let currentCheckpoint = try registryStore.expireDuePairingCredentials(checkpoint: checkpoint)
        let state = try registryStore.loadPairingState(checkpoint: currentCheckpoint)
        let summaries = state.credentials.values.map {
            LOCALBPairingCredentialSummary(
                credentialID: $0.credentialID,
                status: $0.status,
                expiresAtMilliseconds: $0.expiresAtMilliseconds,
                scopeLabel: $0.scopeLabel,
                confirmationMode: $0.confirmationMode,
                expectedClientKeyFingerprint: $0.expectedClientKeyFingerprint
            )
        }.sorted { $0.credentialID < $1.credentialID }
        return LOCALBPairingCredentialListing(
            registryCheckpoint: currentCheckpoint,
            credentials: summaries
        )
    }

    public func listClients(checkpoint: LOCALBRegistryCheckpoint) throws -> [LOCALBClientRegistryEntry] {
        try registryStore.loadPairingState(checkpoint: checkpoint).clients.values
            .sorted { $0.clientKeyID < $1.clientKeyID }
    }

    /// Local-management-plane only; unauthenticated clients cannot revoke
    /// pairing credentials.
    @discardableResult
    public func revokePairingCredential(credentialID: String, reason: String,
                                        checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try registryStore.appendPairingCredentialRevocation(
            credentialID: credentialID, reason: reason, checkpoint: checkpoint
        )
    }

    @discardableResult
    public func revokeClient(clientKeyID: String, reason: String,
                             checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try registryStore.appendClientRevocation(clientKeyID: clientKeyID, reason: reason, checkpoint: checkpoint)
    }

    @discardableResult
    public func setClientPermissions(clientKeyID: String, permissions: Set<LOCALBPermission>,
                                     reason: String,
                                     checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try registryStore.appendClientPermissions(
            clientKeyID: clientKeyID, permissions: permissions, reason: reason, checkpoint: checkpoint
        )
    }

    private static func nowMilliseconds() -> UInt64 {
        let value = Date().timeIntervalSince1970 * 1_000
        return value > 0 ? UInt64(value) : 0
    }
}
