import Crypto
import Darwin
import Foundation

private enum LOCALBRegistryEventKind: String {
    case lineageInitialized = "LINEAGE_INITIALIZED"
    case keyRegistered = "KEY_REGISTERED"
    case keyStatusChanged = "KEY_STATUS_CHANGED"
    case pairingCredentialIssued = "PAIRING_CREDENTIAL_ISSUED"
    case pairingCommitted = "PAIRING_COMMITTED"
    case pairingCredentialRevoked = "PAIRING_CREDENTIAL_REVOKED"
    case pairingCredentialExpired = "PAIRING_CREDENTIAL_EXPIRED"
    case clientRevoked = "CLIENT_REVOKED"
    case clientPermissionsSet = "CLIENT_PERMISSIONS_SET"
}

public struct LOCALBRegistryCheckpoint: Equatable, Sendable {
    public let lineageID: String
    public let sequence: UInt64
    public let headHash: [UInt8]

    public init(lineageID: String, sequence: UInt64, headHash: [UInt8]) throws {
        guard localBIsCanonicalUUID(lineageID), sequence > 0, headHash.count == 32 else {
            throw LOCALBStatus.registryCorrupt
        }
        self.lineageID = lineageID
        self.sequence = sequence
        self.headHash = headHash
    }

    public var headHashHex: String { LOCALBBinary.hexLower(headHash) }

    /// Human-readable offline checkpoint. Store this outside the registry root.
    public var offlineRecord: String {
        [
            "format=LOCALB-REGISTRY-CHECKPOINT-V1",
            "lineage_id=\(lineageID)",
            "sequence=\(sequence)",
            "head_hash=\(headHashHex)"
        ].joined(separator: "\n")
    }

    public static func parseOfflineRecord(_ text: String) throws -> LOCALBRegistryCheckpoint {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count == 4,
              lines[0] == "format=LOCALB-REGISTRY-CHECKPOINT-V1",
              lines[1].hasPrefix("lineage_id="),
              lines[2].hasPrefix("sequence="),
              lines[3].hasPrefix("head_hash=") else {
            throw LOCALBStatus.registryCheckpointUnavailable
        }
        let lineage = String(lines[1].dropFirst("lineage_id=".count))
        let sequenceText = String(lines[2].dropFirst("sequence=".count))
        let hashHex = String(lines[3].dropFirst("head_hash=".count))
        guard let sequence = UInt64(sequenceText), sequence > 0,
              hashHex.utf8.count == 64,
              hashHex.utf8.allSatisfy({
                  ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
              }) else {
            throw LOCALBStatus.registryCheckpointUnavailable
        }
        var bytes: [UInt8] = []
        let raw = Array(hashHex.utf8)
        for index in stride(from: 0, to: raw.count, by: 2) {
            func nibble(_ byte: UInt8) -> UInt8 {
                byte <= 0x39 ? byte - 0x30 : byte - 0x61 + 10
            }
            bytes.append((nibble(raw[index]) << 4) | nibble(raw[index + 1]))
        }
        return try LOCALBRegistryCheckpoint(lineageID: lineage, sequence: sequence, headHash: bytes)
    }
}

/// Append-only LOCALB key registry. The caller-supplied checkpoint is the
/// operator's trusted external head; the local journal never creates its own
/// trust anchor. No automatic truncation or repair occurs on corruption.
public struct LOCALBRegistryStore {
    private let rootURL: URL
    private let journalURL: URL
    private let lockURL: URL

    private static let eventDomain = Array("SIMIGO_PERSISTENT_SRS_LOCALB_REGISTRY_EVENT_V1".utf8)
    private static let zeroHash = [UInt8](repeating: 0, count: 32)
    private static let maxJournalBytes = 64 * 1_048_576
    private static let maxEventBytes = 1_048_576

    private struct Event {
        let sequence: UInt64
        let timestampMilliseconds: UInt64
        let kind: LOCALBRegistryEventKind
        let subjectID: String
        let payload: [UInt8]
        let previousHash: [UInt8]
    }

    private struct ReplayedState {
        var lineageID: String?
        var sequence: UInt64 = 0
        var headHash = LOCALBRegistryStore.zeroHash
        var positions: [UInt64: [UInt8]] = [:]
        var entries: [String: LOCALBRegistryKeyEntry] = [:]
        var credentials: [String: LOCALBPairingCredentialEntry] = [:]
        var clients: [String: LOCALBClientRegistryEntry] = [:]
        var maxGeneration: UInt32 = 0
    }

    public init(rootURL: URL) {
        let normalizedRoot = rootURL.standardizedFileURL
        self.rootURL = normalizedRoot
        self.journalURL = normalizedRoot.appendingPathComponent(".localb-registry.events", isDirectory: false)
        self.lockURL = normalizedRoot.appendingPathComponent(".localb-registry.lock", isDirectory: false)
    }

    /// First-run operation only. The returned checkpoint must be recorded
    /// independently by the operator before any trusted service is activated.
    public func initializeNewLineage(lineageID: String = UUID().uuidString.lowercased()) throws -> LOCALBRegistryCheckpoint {
        guard localBIsCanonicalUUID(lineageID) else { throw LOCALBStatus.invalidConfiguration }
        return try withLock(exclusive: true, createRootIfMissing: true) {
            guard !FileManager.default.fileExists(atPath: journalURL.path) else {
                throw LOCALBStatus.registryAlreadyInitialized
            }
            let event = Event(
                sequence: 1,
                timestampMilliseconds: Self.nowMilliseconds(),
                kind: .lineageInitialized,
                subjectID: lineageID,
                payload: [],
                previousHash: Self.zeroHash
            )
            let frame = try Self.encodeEventFrame(event)
            let fd = open(journalURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { throw LOCALBStatus.registryPersistenceFailure }
            defer { close(fd) }
            do {
                try Self.writeAll(fd: fd, bytes: frame)
                guard fsync(fd) == 0 else { throw LOCALBStatus.registryPersistenceFailure }
                try syncRootDirectory()
            } catch {
                // A partial first write is intentionally left fail-closed for
                // explicit recovery; it is never silently deleted or recreated.
                throw error
            }
            let state = try replayJournal()
            guard state.sequence == 1, state.lineageID == lineageID else {
                throw LOCALBStatus.registryCorrupt
            }
            return try Self.checkpoint(for: state)
        }
    }

    /// B1/B2/B3 verification against an operator-held checkpoint.
    /// Passing nil is B2 and always fails closed.
    public func loadVerified(checkpoint: LOCALBRegistryCheckpoint?) throws -> LOCALBRegistrySnapshot {
        guard let checkpoint else { throw LOCALBStatus.registryCheckpointUnavailable }
        return try withLock(exclusive: false, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard let lineageID = state.lineageID else { throw LOCALBStatus.registryLineageUninitialized }
            let entries = state.entries.values.sorted { $0.keyID < $1.keyID }
            let clients = state.clients.values.sorted { $0.clientKeyID < $1.clientKeyID }
            return try LOCALBRegistrySnapshot(currentLineageID: lineageID, entries: entries, clients: clients)
        }
    }

    /// Loads the latest replayed state only after verifying it extends a trusted
    /// operator-held checkpoint. Pairing and per-request auth must call this
    /// rather than retaining stale authority snapshots.
    func loadPairingState(checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBPairingStateView {
        try withLock(exclusive: false, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard let lineageID = state.lineageID else { throw LOCALBStatus.registryLineageUninitialized }
            return LOCALBPairingStateView(
                lineageID: lineageID,
                signingKeys: state.entries.values.sorted { $0.keyID < $1.keyID },
                credentials: state.credentials,
                clients: state.clients
            )
        }
    }

    /// Returns the current local head only after proving it extends the
    /// supplied externally trusted checkpoint. Callers must not persist the
    /// returned head inside the registry and then treat it as an external anchor.
    func currentCheckpoint(extending trustedCheckpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try withLock(exclusive: false, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(trustedCheckpoint, against: state)
            return try Self.checkpoint(for: state)
        }
    }

    /// Adds the next signing key only when no current key is ACTIVE. The new
    /// key's generation must be monotonic within this lineage.
    @discardableResult
    public func appendKeyRegistration(publicKeyRaw: [UInt8], generation: UInt32,
                                      checkpoint: LOCALBRegistryCheckpoint?) throws -> LOCALBRegistryCheckpoint {
        guard publicKeyRaw.count == 32 else { throw LOCALBStatus.invalidConfiguration }
        guard let checkpoint else { throw LOCALBStatus.registryCheckpointUnavailable }
        return try withLock(exclusive: true, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard let lineageID = state.lineageID else { throw LOCALBStatus.registryLineageUninitialized }
            let keyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: publicKeyRaw)
            guard state.entries[keyID] == nil else { throw LOCALBStatus.registryKeyAlreadyExists }
            guard !state.entries.values.contains(where: { $0.status == .active }) else {
                throw LOCALBStatus.registryInvalidTransition
            }
            let expectedGeneration = state.maxGeneration == UInt32.max ? nil : state.maxGeneration + 1
            guard expectedGeneration == generation, generation > 0 else {
                throw LOCALBStatus.issuerGenerationMismatch
            }
            var payload = publicKeyRaw
            LOCALBBinary.appendU32(generation, to: &payload)
            let lineageBytes = Array(lineageID.utf8)
            LOCALBBinary.appendU16(UInt16(lineageBytes.count), to: &payload)
            payload.append(contentsOf: lineageBytes)
            let event = Event(
                sequence: state.sequence + 1,
                timestampMilliseconds: Self.nowMilliseconds(),
                kind: .keyRegistered,
                subjectID: keyID,
                payload: payload,
                previousHash: state.headHash
            )
            try appendEventLocked(event)
            let updated = try replayJournal()
            guard updated.sequence == event.sequence else { throw LOCALBStatus.registryCorrupt }
            return try Self.checkpoint(for: updated)
        }
    }

    /// Status transitions are monotonic: ACTIVE -> RETIRED/LOST/REVOKED;
    /// RETIRED -> LOST/REVOKED; LOST -> REVOKED; REVOKED is terminal.
    @discardableResult
    public func appendKeyStatusChange(keyID: String, to newStatus: LOCALBKeyStatus,
                                      reason: String,
                                      checkpoint: LOCALBRegistryCheckpoint?) throws -> LOCALBRegistryCheckpoint {
        guard let checkpoint else { throw LOCALBStatus.registryCheckpointUnavailable }
        guard newStatus != .active else { throw LOCALBStatus.registryInvalidTransition }
        let reasonBytes = Array(reason.utf8)
        guard !reasonBytes.isEmpty, reasonBytes.count <= 512 else {
            throw LOCALBStatus.registryInvalidTransition
        }
        return try withLock(exclusive: true, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard let entry = state.entries[keyID] else { throw LOCALBStatus.issuerUnknown }
            guard Self.allowedTransition(from: entry.status, to: newStatus) else {
                throw LOCALBStatus.registryInvalidTransition
            }
            guard state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }
            var statusPayload: [UInt8] = []
            let statusBytes = Array(newStatus.rawValue.utf8)
            LOCALBBinary.appendU16(UInt16(statusBytes.count), to: &statusPayload)
            statusPayload.append(contentsOf: statusBytes)
            LOCALBBinary.appendU16(UInt16(reasonBytes.count), to: &statusPayload)
            statusPayload.append(contentsOf: reasonBytes)
            let event = Event(
                sequence: state.sequence + 1,
                timestampMilliseconds: Self.nowMilliseconds(),
                kind: .keyStatusChanged,
                subjectID: keyID,
                payload: statusPayload,
                previousHash: state.headHash
            )
            try appendEventLocked(event)
            let updated = try replayJournal()
            return try Self.checkpoint(for: updated)
        }
    }

    /// Materializes TTL expiry events during an authenticated local-management
    /// operation, never as a side effect of an unauthenticated Phase-V failure.
    @discardableResult
    func expireDuePairingCredentials(checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try withLock(exclusive: true, createRootIfMissing: false) {
            var state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            let now = Self.nowMilliseconds()
            let expiredIDs = state.credentials.values
                .filter { $0.status == .issued && $0.expiresAtMilliseconds <= now }
                .map(\.credentialID)
                .sorted()
            for credentialID in expiredIDs {
                guard let credential = state.credentials[credentialID],
                      state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }
                let payload = try LOCALBPairingEventCodec.encodeCredentialDisposition(
                    credentialID: credentialID, digest: credential.digest, reason: "time-to-live elapsed"
                )
                let event = Event(
                    sequence: state.sequence + 1,
                    timestampMilliseconds: now,
                    kind: .pairingCredentialExpired,
                    subjectID: credentialID,
                    payload: payload,
                    previousHash: state.headHash
                )
                try appendEventLocked(event)
                state = try replayJournal()
            }
            return try Self.checkpoint(for: state)
        }
    }

    /// Persist the credential digest and binding only; the bearer secret is never stored.
    @discardableResult
    func appendPairingCredentialIssued(_ credential: LOCALBPairingCredentialEntry,
                                      checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try withLock(exclusive: true, createRootIfMissing: false) {
            var state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)

            guard credential.status == .issued,
                  localBIsCanonicalUUID(credential.credentialID),
                  credential.digest.count == 32,
                  credential.issuedAtMilliseconds > 0,
                  credential.expiresAtMilliseconds == credential.issuedAtMilliseconds + 5 * 60 * 1_000,
                  credential.hostInstanceID == state.lineageID,
                  LOCALBPairingProofV1.isHex64(credential.tlsSPKIHash),
                  LOCALBPairingProofV1.isHex64(credential.srsKeyID),
                  credential.issuerGeneration > 0,
                  credential.protocolVersion == LOCALBConstants.credentialProtocolVersion,
                  credential.sessionNonce.count == 16,
                  !credential.scopeLabel.isEmpty, credential.scopeLabel.utf8.count <= 512,
                  state.credentials[credential.credentialID] == nil,
                  state.credentials.count < 100_000 else {
                throw LOCALBStatus.invalidConfiguration
            }
            if credential.confirmationMode == .strictHeadless {
                guard let fingerprint = credential.expectedClientKeyFingerprint,
                      LOCALBPairingProofV1.isHex64(fingerprint) else {
                    throw LOCALBStatus.invalidConfiguration
                }
            } else if credential.expectedClientKeyFingerprint != nil {
                throw LOCALBStatus.invalidConfiguration
            }
            guard let issuer = state.entries[credential.srsKeyID],
                  issuer.status == .active,
                  issuer.generation == credential.issuerGeneration,
                  issuer.lineageID == credential.hostInstanceID else {
                throw LOCALBStatus.issuerKeyNotActive
            }
            guard state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }
            let payload = try LOCALBPairingEventCodec.encodeCredentialIssued(credential)
            let event = Event(
                sequence: state.sequence + 1,
                timestampMilliseconds: credential.issuedAtMilliseconds,
                kind: .pairingCredentialIssued,
                subjectID: credential.credentialID,
                payload: payload,
                previousHash: state.headHash
            )
            try appendEventLocked(event)
            return try Self.checkpoint(for: replayJournal())
        }
    }

    /// Convert a TTL-expired credential to a permanent terminal registry state.
    /// The caller must invoke this only after Phase V has verified the secret.
    @discardableResult
    func expirePairingCredentialIfDue(credentialID: String, digest: [UInt8],
                                      checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try withLock(exclusive: true, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard let credential = state.credentials[credentialID] else {
                throw LOCALBStatus.pairingCredentialUnknown
            }
            guard credential.status == .issued else { throw LOCALBStatus.pairingCredentialExpired }
            guard LOCALBBinary.constantTimeEqual(credential.digest, digest) else {
                throw LOCALBStatus.invalidCredentialSecret
            }
            let now = Self.nowMilliseconds()
            guard now >= credential.expiresAtMilliseconds else {
                throw LOCALBStatus.registryInvalidTransition
            }
            guard state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }
            let payload = try LOCALBPairingEventCodec.encodeCredentialDisposition(
                credentialID: credentialID, digest: digest, reason: "time-to-live elapsed"
            )
            let event = Event(sequence: state.sequence + 1, timestampMilliseconds: now,
                              kind: .pairingCredentialExpired, subjectID: credentialID,
                              payload: payload, previousHash: state.headHash)
            try appendEventLocked(event)
            return try Self.checkpoint(for: replayJournal())
        }
    }

    /// A single PAIRING_COMMITTED event consumes the credential and creates the
    /// client entry. Replay verifies the client PoP and all issuance bindings.
    @discardableResult
    func commitPairing(_ pending: LOCALBPairingApprovalRequest,
                       operatorAuthorizationReference: String?,
                       checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try withLock(exclusive: true, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard let credential = state.credentials[pending.credentialID] else {
                throw LOCALBStatus.pairingCredentialUnknown
            }
            guard credential.status == .issued else {
                switch credential.status {
                case .consumed: throw LOCALBStatus.pairingCredentialConsumed
                case .expired: throw LOCALBStatus.pairingCredentialExpired
                case .revoked: throw LOCALBStatus.pairingCredentialRevoked
                case .issued: preconditionFailure("unreachable: guard excludes .issued")
                }
            }
            let now = Self.nowMilliseconds()
            guard now < credential.expiresAtMilliseconds else {
                throw LOCALBStatus.pairingCredentialExpired
            }
            guard LOCALBBinary.constantTimeEqual(credential.digest, pending.credentialDigest),
                  pending.actualTLSSPKIHash == credential.tlsSPKIHash,
                  pending.presentedSRSKeyID == credential.srsKeyID,
                  pending.protocolVersion == credential.protocolVersion,
                  credential.hostInstanceID == state.lineageID,
                  pending.clientPublicKeyRaw.count == 32 else {
                throw LOCALBStatus.pairingBindingMismatch
            }
            guard let issuer = state.entries[credential.srsKeyID],
                  issuer.status == .active,
                  issuer.generation == credential.issuerGeneration,
                  issuer.lineageID == credential.hostInstanceID else {
                throw LOCALBStatus.issuerKeyNotActive
            }
            let recomputedClientKeyID = try LOCALBSigningInputV1.keyID(
                publicKeyRaw: pending.clientPublicKeyRaw
            )
            guard recomputedClientKeyID == pending.clientKeyID else {
                throw LOCALBStatus.pairingBindingMismatch
            }
            if credential.confirmationMode == .strictHeadless {
                let fingerprint = LOCALBBinary.hexLower(
                    LOCALBBinary.sha256(pending.clientPublicKeyRaw)
                )
                guard fingerprint == credential.expectedClientKeyFingerprint,
                      operatorAuthorizationReference == nil else {
                    throw LOCALBStatus.pairingBindingMismatch
                }
            } else {
                let reference = operatorAuthorizationReference ?? ""
                guard pending.requiresOperatorConfirmation,
                      !reference.isEmpty, reference.utf8.count <= 512 else {
                    throw LOCALBStatus.pairingOperatorApprovalRequired
                }
            }
            guard LOCALBPairingProofV1.verify(
                signature: pending.proofSignatureRaw,
                credential: credential,
                clientPublicKeyRaw: pending.clientPublicKeyRaw
            ) else {
                throw LOCALBStatus.pairingProofInvalid
            }
            guard state.clients[recomputedClientKeyID] == nil else {
                throw LOCALBStatus.duplicateClient
            }
            guard state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }

            let payload = try LOCALBPairingEventCodec.encodePairingCommit(
                LOCALBPairingCommitPayload(
                    credentialID: credential.credentialID,
                    credentialDigest: credential.digest,
                    clientPublicKeyRaw: pending.clientPublicKeyRaw,
                    clientKeyID: recomputedClientKeyID,
                    permissions: [.inference, .informationRead],
                    registeredAtMilliseconds: now,
                    proofSignatureRaw: pending.proofSignatureRaw,
                    tlsSPKIHash: pending.actualTLSSPKIHash,
                    srsKeyID: pending.presentedSRSKeyID,
                    protocolVersion: pending.protocolVersion,
                    operatorAuthorizationReference: operatorAuthorizationReference ?? ""
                )
            )
            let event = Event(sequence: state.sequence + 1, timestampMilliseconds: now,
                              kind: .pairingCommitted, subjectID: credential.credentialID,
                              payload: payload, previousHash: state.headHash)
            try appendEventLocked(event)
            return try Self.checkpoint(for: replayJournal())
        }
    }

    @discardableResult
    func appendPairingCredentialRevocation(credentialID: String, reason: String,
                                           checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try withLock(exclusive: true, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard let credential = state.credentials[credentialID] else {
                throw LOCALBStatus.pairingCredentialUnknown
            }
            guard credential.status == .issued else {
                throw LOCALBStatus.registryInvalidTransition
            }
            let now = Self.nowMilliseconds()
            if now >= credential.expiresAtMilliseconds {
                guard state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }
                let expiredPayload = try LOCALBPairingEventCodec.encodeCredentialDisposition(
                    credentialID: credentialID, digest: credential.digest, reason: "time-to-live elapsed"
                )
                let expiredEvent = Event(
                    sequence: state.sequence + 1, timestampMilliseconds: now,
                    kind: .pairingCredentialExpired, subjectID: credentialID,
                    payload: expiredPayload, previousHash: state.headHash
                )
                try appendEventLocked(expiredEvent)
                return try Self.checkpoint(for: replayJournal())
            }
            guard state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }
            let payload = try LOCALBPairingEventCodec.encodeCredentialDisposition(
                credentialID: credentialID, digest: credential.digest, reason: reason
            )
            let event = Event(sequence: state.sequence + 1, timestampMilliseconds: now,
                              kind: .pairingCredentialRevoked, subjectID: credentialID,
                              payload: payload, previousHash: state.headHash)
            try appendEventLocked(event)
            return try Self.checkpoint(for: replayJournal())
        }
    }

    @discardableResult
    func appendClientRevocation(clientKeyID: String, reason: String,
                                checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try withLock(exclusive: true, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard state.clients[clientKeyID]?.status == .active else {
                throw LOCALBStatus.clientUnknown
            }
            guard state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }
            let payload = try LOCALBPairingEventCodec.encodeClientRevocation(
                clientKeyID: clientKeyID, reason: reason
            )
            let event = Event(sequence: state.sequence + 1, timestampMilliseconds: Self.nowMilliseconds(),
                              kind: .clientRevoked, subjectID: clientKeyID,
                              payload: payload, previousHash: state.headHash)
            try appendEventLocked(event)
            return try Self.checkpoint(for: replayJournal())
        }
    }

    @discardableResult
    func appendClientPermissions(clientKeyID: String, permissions: Set<LOCALBPermission>,
                                reason: String,
                                checkpoint: LOCALBRegistryCheckpoint) throws -> LOCALBRegistryCheckpoint {
        try withLock(exclusive: true, createRootIfMissing: false) {
            let state = try replayJournal()
            try Self.verifyCheckpoint(checkpoint, against: state)
            guard state.clients[clientKeyID]?.status == .active else {
                throw LOCALBStatus.clientUnknown
            }
            guard state.sequence < UInt64.max else { throw LOCALBStatus.registryCorrupt }
            let payload = try LOCALBPairingEventCodec.encodePermissionChange(
                clientKeyID: clientKeyID, permissions: permissions, reason: reason
            )
            let event = Event(sequence: state.sequence + 1, timestampMilliseconds: Self.nowMilliseconds(),
                              kind: .clientPermissionsSet, subjectID: clientKeyID,
                              payload: payload, previousHash: state.headHash)
            try appendEventLocked(event)
            return try Self.checkpoint(for: replayJournal())
        }
    }

    // MARK: Locking and durable append

    private func withLock<T>(exclusive: Bool, createRootIfMissing: Bool,
                             _ body: () throws -> T) throws -> T {
        if createRootIfMissing {
            try FileManager.default.createDirectory(
                at: rootURL, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw LOCALBStatus.registryLineageUninitialized
            }
        }
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw LOCALBStatus.registryPersistenceFailure }
        defer { close(fd) }
        guard flock(fd, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
            throw LOCALBStatus.registryPersistenceFailure
        }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    private func appendEventLocked(_ event: Event) throws {
        let frame = try Self.encodeEventFrame(event)
        guard frame.count <= Self.maxEventBytes else { throw LOCALBStatus.resourceLimit }
        let fd = open(journalURL.path, O_WRONLY | O_APPEND)
        guard fd >= 0 else { throw LOCALBStatus.registryPersistenceFailure }
        defer { close(fd) }
        try Self.writeAll(fd: fd, bytes: frame)
        guard fsync(fd) == 0 else { throw LOCALBStatus.registryPersistenceFailure }
        try syncRootDirectory()
    }

    private func syncRootDirectory() throws {
        let fd = open(rootURL.path, O_RDONLY)
        guard fd >= 0 else { throw LOCALBStatus.registryPersistenceFailure }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw LOCALBStatus.registryPersistenceFailure }
    }

    private static func writeAll(fd: Int32, bytes: [UInt8]) throws {
        var writtenTotal = 0
        while writtenTotal < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: writtenTotal), bytes.count - writtenTotal)
            }
            guard written > 0 else { throw LOCALBStatus.registryPersistenceFailure }
            writtenTotal += written
        }
    }

    // MARK: Canonical event encoding

    private static func encodeEventBody(_ event: Event) throws -> [UInt8] {
        let kindBytes = Array(event.kind.rawValue.utf8)
        let subjectBytes = Array(event.subjectID.utf8)
        guard kindBytes.count <= Int(UInt16.max),
              subjectBytes.count > 0, subjectBytes.count <= Int(UInt16.max),
              event.previousHash.count == 32,
              event.payload.count <= Int(UInt32.max) else {
            throw LOCALBStatus.registryCorrupt
        }
        var body: [UInt8] = []
        LOCALBBinary.appendU64(event.sequence, to: &body)
        LOCALBBinary.appendU64(event.timestampMilliseconds, to: &body)
        LOCALBBinary.appendU16(UInt16(kindBytes.count), to: &body)
        body.append(contentsOf: kindBytes)
        LOCALBBinary.appendU16(UInt16(subjectBytes.count), to: &body)
        body.append(contentsOf: subjectBytes)
        LOCALBBinary.appendU32(UInt32(event.payload.count), to: &body)
        body.append(contentsOf: event.payload)
        body.append(contentsOf: event.previousHash)
        return body
    }

    private static func encodeEventFrame(_ event: Event) throws -> [UInt8] {
        let body = try encodeEventBody(event)
        var hashInput = eventDomain
        hashInput.append(0x00)
        hashInput.append(contentsOf: body)
        let eventHash = LOCALBBinary.sha256(hashInput)
        var output: [UInt8] = []
        LOCALBBinary.appendU32(UInt32(body.count + eventHash.count), to: &output)
        output.append(contentsOf: body)
        output.append(contentsOf: eventHash)
        return output
    }

    private func replayJournal() throws -> ReplayedState {
        guard let data = try? Data(contentsOf: journalURL), data.count <= Self.maxJournalBytes else {
            throw LOCALBStatus.registryCorrupt
        }
        let bytes = Array(data)
        var cursor = 0
        var state = ReplayedState()
        while cursor < bytes.count {
            guard let framedLength = LOCALBBinary.readU32(bytes, &cursor) else {
                throw LOCALBStatus.registryCorrupt
            }
            let recordLength = Int(framedLength)
            guard recordLength >= 32, recordLength <= Self.maxEventBytes,
                  cursor <= bytes.count, bytes.count - cursor >= recordLength else {
                throw LOCALBStatus.registryCorrupt
            }
            let bodyLength = recordLength - 32
            let body = Array(bytes[cursor..<(cursor + bodyLength)])
            let storedHash = Array(bytes[(cursor + bodyLength)..<(cursor + recordLength)])
            cursor += recordLength

            var hashInput = Self.eventDomain
            hashInput.append(0x00)
            hashInput.append(contentsOf: body)
            let computedHash = LOCALBBinary.sha256(hashInput)
            guard LOCALBBinary.constantTimeEqual(storedHash, computedHash) else {
                throw LOCALBStatus.registryCorrupt
            }
            let event = try Self.decodeEventBody(body)
            guard event.sequence == state.sequence + 1,
                  LOCALBBinary.constantTimeEqual(event.previousHash, state.headHash) else {
                throw LOCALBStatus.registryCorrupt
            }
            try Self.apply(event, state: &state)
            state.sequence = event.sequence
            state.headHash = computedHash
            state.positions[event.sequence] = computedHash
        }
        guard state.sequence > 0, state.lineageID != nil else {
            throw LOCALBStatus.registryLineageUninitialized
        }
        return state
    }

    private static func decodeEventBody(_ body: [UInt8]) throws -> Event {
        var offset = 0
        guard let sequence = LOCALBBinary.readU64(body, &offset),
              let timestamp = LOCALBBinary.readU64(body, &offset),
              let kindLength = LOCALBBinary.readU16(body, &offset) else {
            throw LOCALBStatus.registryCorrupt
        }
        let kindCount = Int(kindLength)
        guard kindCount > 0, offset <= body.count, body.count - offset >= kindCount,
              let kindText = String(bytes: body[offset..<(offset + kindCount)], encoding: .utf8),
              let kind = LOCALBRegistryEventKind(rawValue: kindText) else {
            throw LOCALBStatus.registryCorrupt
        }
        offset += kindCount
        guard let subjectLength = LOCALBBinary.readU16(body, &offset) else {
            throw LOCALBStatus.registryCorrupt
        }
        let subjectCount = Int(subjectLength)
        guard subjectCount > 0, offset <= body.count, body.count - offset >= subjectCount,
              let subject = String(bytes: body[offset..<(offset + subjectCount)], encoding: .utf8) else {
            throw LOCALBStatus.registryCorrupt
        }
        offset += subjectCount
        guard let payloadLength = LOCALBBinary.readU32(body, &offset),
              payloadLength <= UInt32(Self.maxEventBytes),
              offset <= body.count, body.count - offset >= Int(payloadLength) + 32 else {
            throw LOCALBStatus.registryCorrupt
        }
        let payloadCount = Int(payloadLength)
        let payload = Array(body[offset..<(offset + payloadCount)])
        offset += payloadCount
        let previousHash = Array(body[offset..<(offset + 32)])
        offset += 32
        guard offset == body.count else { throw LOCALBStatus.registryCorrupt }
        return Event(sequence: sequence, timestampMilliseconds: timestamp,
                     kind: kind, subjectID: subject, payload: payload,
                     previousHash: previousHash)
    }

    private static func apply(_ event: Event, state: inout ReplayedState) throws {
        switch event.kind {
        case .lineageInitialized:
            guard state.sequence == 0, event.sequence == 1, event.payload.isEmpty,
                  localBIsCanonicalUUID(event.subjectID) else {
                throw LOCALBStatus.registryCorrupt
            }
            state.lineageID = event.subjectID

        case .keyRegistered:
            guard let lineageID = state.lineageID,
                  state.sequence > 0,
                  state.entries[event.subjectID] == nil else {
                throw LOCALBStatus.registryCorrupt
            }
            var offset = 0
            guard event.payload.count >= 32 + 4 + 2 else { throw LOCALBStatus.registryCorrupt }
            let publicKeyRaw = Array(event.payload[0..<32])
            offset = 32
            guard let generation = LOCALBBinary.readU32(event.payload, &offset),
                  let lineageLength = LOCALBBinary.readU16(event.payload, &offset) else {
                throw LOCALBStatus.registryCorrupt
            }
            let length = Int(lineageLength)
            guard length > 0, offset <= event.payload.count,
                  event.payload.count - offset == length,
                  let eventLineage = String(bytes: event.payload[offset..<event.payload.count], encoding: .utf8),
                  eventLineage == lineageID,
                  let keyID = try? LOCALBSigningInputV1.keyID(publicKeyRaw: publicKeyRaw),
                  keyID == event.subjectID,
                  generation == (state.maxGeneration == UInt32.max ? 0 : state.maxGeneration + 1),
                  generation > 0,
                  !state.entries.values.contains(where: { $0.status == .active }) else {
                throw LOCALBStatus.registryCorrupt
            }
            state.entries[keyID] = LOCALBRegistryKeyEntry(
                keyID: keyID, publicKeyRaw: publicKeyRaw, generation: generation,
                status: .active, lineageID: lineageID
            )
            state.maxGeneration = generation

        case .keyStatusChanged:
            guard let existing = state.entries[event.subjectID] else {
                throw LOCALBStatus.registryCorrupt
            }
            var offset = 0
            guard let statusLength = LOCALBBinary.readU16(event.payload, &offset) else {
                throw LOCALBStatus.registryCorrupt
            }
            let statusCount = Int(statusLength)
            guard statusCount > 0, offset <= event.payload.count,
                  event.payload.count - offset >= statusCount,
                  let statusText = String(bytes: event.payload[offset..<(offset + statusCount)], encoding: .utf8) else {
                throw LOCALBStatus.registryCorrupt
            }
            offset += statusCount
            guard let reasonLength = LOCALBBinary.readU16(event.payload, &offset) else {
                throw LOCALBStatus.registryCorrupt
            }
            let reasonCount = Int(reasonLength)
            guard reasonCount > 0, offset <= event.payload.count,
                  event.payload.count - offset == reasonCount,
                  String(bytes: event.payload[offset..<event.payload.count], encoding: .utf8) != nil,
                  let nextStatus = LOCALBKeyStatus(rawValue: statusText),
                  nextStatus != .active,
                  Self.allowedTransition(from: existing.status, to: nextStatus) else {
                throw LOCALBStatus.registryCorrupt
            }
            state.entries[event.subjectID] = LOCALBRegistryKeyEntry(
                keyID: existing.keyID, publicKeyRaw: existing.publicKeyRaw,
                generation: existing.generation, status: nextStatus,
                lineageID: existing.lineageID
            )

        case .pairingCredentialIssued:
            let credential = try LOCALBPairingEventCodec.decodeCredentialIssued(event.payload)
            guard event.subjectID == credential.credentialID,
                  credential.status == .issued,
                  credential.issuedAtMilliseconds == event.timestampMilliseconds,
                  credential.digest.count == 32,
                  localBIsCanonicalUUID(credential.credentialID),
                  let lineageID = state.lineageID,
                  credential.hostInstanceID == lineageID,
                  credential.expiresAtMilliseconds == credential.issuedAtMilliseconds + 5 * 60 * 1_000,
                  LOCALBPairingProofV1.isHex64(credential.tlsSPKIHash),
                  LOCALBPairingProofV1.isHex64(credential.srsKeyID),
                  credential.issuerGeneration > 0,
                  credential.protocolVersion == LOCALBConstants.credentialProtocolVersion,
                  credential.sessionNonce.count == 16,
                  !credential.scopeLabel.isEmpty, credential.scopeLabel.utf8.count <= 512,
                  state.credentials[credential.credentialID] == nil else {
                throw LOCALBStatus.registryCorrupt
            }
            if credential.confirmationMode == .strictHeadless {
                guard let fingerprint = credential.expectedClientKeyFingerprint,
                      LOCALBPairingProofV1.isHex64(fingerprint) else {
                    throw LOCALBStatus.registryCorrupt
                }
            } else if credential.expectedClientKeyFingerprint != nil {
                throw LOCALBStatus.registryCorrupt
            }
            guard let issuer = state.entries[credential.srsKeyID],
                  issuer.status == .active,
                  issuer.generation == credential.issuerGeneration,
                  issuer.lineageID == credential.hostInstanceID else {
                throw LOCALBStatus.registryCorrupt
            }
            state.credentials[credential.credentialID] = credential

        case .pairingCommitted:
            let commit = try LOCALBPairingEventCodec.decodePairingCommit(event.payload)
            guard event.subjectID == commit.credentialID,
                  commit.registeredAtMilliseconds == event.timestampMilliseconds,
                  commit.credentialDigest.count == 32,
                  commit.clientPublicKeyRaw.count == 32,
                  commit.proofSignatureRaw.count == 64,
                  !commit.permissions.contains(.srsWrite),
                  commit.permissions == Set([.inference, .informationRead]),
                  let credential = state.credentials[commit.credentialID],
                  credential.status == .issued,
                  LOCALBBinary.constantTimeEqual(credential.digest, commit.credentialDigest),
                  event.timestampMilliseconds >= credential.issuedAtMilliseconds,
                  event.timestampMilliseconds < credential.expiresAtMilliseconds,
                  commit.tlsSPKIHash == credential.tlsSPKIHash,
                  commit.srsKeyID == credential.srsKeyID,
                  commit.protocolVersion == credential.protocolVersion,
                  let lineageID = state.lineageID,
                  credential.hostInstanceID == lineageID,
                  let issuer = state.entries[credential.srsKeyID],
                  issuer.status == .active,
                  issuer.generation == credential.issuerGeneration,
                  issuer.lineageID == lineageID,
                  let calculatedClientKeyID = try? LOCALBSigningInputV1.keyID(
                    publicKeyRaw: commit.clientPublicKeyRaw
                  ),
                  calculatedClientKeyID == commit.clientKeyID,
                  state.clients[commit.clientKeyID] == nil,
                  LOCALBPairingProofV1.verify(
                    signature: commit.proofSignatureRaw, credential: credential,
                    clientPublicKeyRaw: commit.clientPublicKeyRaw
                  ) else {
                throw LOCALBStatus.registryCorrupt
            }
            if credential.confirmationMode == .strictHeadless {
                let fingerprint = LOCALBBinary.hexLower(LOCALBBinary.sha256(commit.clientPublicKeyRaw))
                guard fingerprint == credential.expectedClientKeyFingerprint,
                      commit.operatorAuthorizationReference.isEmpty else {
                    throw LOCALBStatus.registryCorrupt
                }
            } else {
                guard !commit.operatorAuthorizationReference.isEmpty,
                      commit.operatorAuthorizationReference.utf8.count <= 512 else {
                    throw LOCALBStatus.registryCorrupt
                }
            }
            var consumedCredential = credential
            consumedCredential.status = .consumed
            state.credentials[commit.credentialID] = consumedCredential
            state.clients[commit.clientKeyID] = LOCALBClientRegistryEntry(
                clientKeyID: commit.clientKeyID,
                publicKeyRaw: commit.clientPublicKeyRaw,
                lineageID: lineageID,
                permissions: commit.permissions,
                status: .active,
                registeredAtMilliseconds: commit.registeredAtMilliseconds
            )

        case .pairingCredentialRevoked, .pairingCredentialExpired:
            let disposition = try LOCALBPairingEventCodec.decodeCredentialDisposition(event.payload)
            let targetID = disposition.0
            let digest = disposition.1
            let reason = disposition.2
            guard event.subjectID == targetID, !reason.isEmpty,
                  var credential = state.credentials[targetID],
                  credential.status == .issued,
                  LOCALBBinary.constantTimeEqual(credential.digest, digest) else {
                throw LOCALBStatus.registryCorrupt
            }
            if event.kind == .pairingCredentialExpired {
                guard event.timestampMilliseconds >= credential.expiresAtMilliseconds else {
                    throw LOCALBStatus.registryCorrupt
                }
                credential.status = .expired
            } else {
                guard event.timestampMilliseconds <= credential.expiresAtMilliseconds else {
                    throw LOCALBStatus.registryCorrupt
                }
                credential.status = .revoked
            }
            state.credentials[targetID] = credential

        case .clientRevoked:
            let value = try LOCALBPairingEventCodec.decodeClientRevocation(event.payload)
            guard event.subjectID == value.0,
                  var client = state.clients[value.0],
                  client.status == .active else {
                throw LOCALBStatus.registryCorrupt
            }
            client = LOCALBClientRegistryEntry(
                clientKeyID: client.clientKeyID,
                publicKeyRaw: client.publicKeyRaw,
                lineageID: client.lineageID,
                permissions: client.permissions,
                status: .revoked,
                registeredAtMilliseconds: client.registeredAtMilliseconds,
                revokedReason: value.1
            )
            state.clients[value.0] = client

        case .clientPermissionsSet:
            let value = try LOCALBPairingEventCodec.decodePermissionChange(event.payload)
            guard event.subjectID == value.0,
                  var client = state.clients[value.0],
                  client.status == .active else {
                throw LOCALBStatus.registryCorrupt
            }
            client = LOCALBClientRegistryEntry(
                clientKeyID: client.clientKeyID,
                publicKeyRaw: client.publicKeyRaw,
                lineageID: client.lineageID,
                permissions: value.1,
                status: client.status,
                registeredAtMilliseconds: client.registeredAtMilliseconds,
                revokedReason: client.revokedReason
            )
            state.clients[value.0] = client
        }
    }

    private static func verifyCheckpoint(_ checkpoint: LOCALBRegistryCheckpoint,
                                         against state: ReplayedState) throws {
        guard let lineage = state.lineageID, lineage == checkpoint.lineageID else {
            throw LOCALBStatus.registryCheckpointMismatch
        }
        guard checkpoint.sequence <= state.sequence,
              let trustedHash = state.positions[checkpoint.sequence],
              LOCALBBinary.constantTimeEqual(trustedHash, checkpoint.headHash) else {
            throw LOCALBStatus.registryCheckpointMismatch
        }
        // The replay above verifies every event and previous-hash link from
        // the checkpoint through the current head, so any later head is a
        // trusted extension rather than an equality-only comparison.
    }

    private static func checkpoint(for state: ReplayedState) throws -> LOCALBRegistryCheckpoint {
        guard let lineageID = state.lineageID else { throw LOCALBStatus.registryLineageUninitialized }
        return try LOCALBRegistryCheckpoint(lineageID: lineageID,
                                            sequence: state.sequence,
                                            headHash: state.headHash)
    }

    private static func allowedTransition(from old: LOCALBKeyStatus, to new: LOCALBKeyStatus) -> Bool {
        switch old {
        case .active: return new == .retired || new == .lost || new == .revoked
        case .retired: return new == .lost || new == .revoked
        case .lost: return new == .revoked
        case .revoked: return false
        }
    }

    private static func nowMilliseconds() -> UInt64 {
        let value = Date().timeIntervalSince1970 * 1_000
        return value > 0 ? UInt64(value) : 0
    }
}
