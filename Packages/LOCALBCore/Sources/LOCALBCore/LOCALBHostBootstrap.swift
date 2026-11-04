import Crypto
import Foundation

/// A first-run result is NOT operational. The caller must display and have the
/// operator record the checkpoint outside the registry before activation.
public struct LOCALBHostPendingActivation {
    public let lineageID: String
    public let signerKeyID: String
    public let signerGeneration: UInt32
    public let checkpoint: LOCALBRegistryCheckpoint
    /// SPKI fingerprint of the transport (TLS) identity created during the
    /// first-run ceremony. Pairing credentials bind to this value; it must be
    /// displayed to the operator through the trusted local channel.
    public let transportSPKIHashHex: String

    public var offlineCheckpointRecord: String { checkpoint.offlineRecord }
}

/// Returned only after registry/checkpoint/Keychain identity checks succeed.
/// Every signing call reloads the current registry state; this value does not
/// cache client permissions or key lifecycle state.
public struct LOCALBHostRuntimeContext {
    public let lineageID: String
    public let signerKeyID: String
    public let signerGeneration: UInt32
    /// Loaded (never created) at ordinary startup; required for the TLS
    /// listener. Separate lifecycle from the signing key.
    public let transportIdentity: LOCALBTransportIdentityHandle
    private let store: LOCALBRegistryStore
    private let signingKey: Curve25519.Signing.PrivateKey
    private let trustedCheckpoint: LOCALBRegistryCheckpoint
    private let pairingService: LOCALBPairingCoordinator

    init(lineageID: String, signerKeyID: String, signerGeneration: UInt32,
         transportIdentity: LOCALBTransportIdentityHandle,
         store: LOCALBRegistryStore, signingKey: Curve25519.Signing.PrivateKey,
         trustedCheckpoint: LOCALBRegistryCheckpoint) {
        self.lineageID = lineageID
        self.signerKeyID = signerKeyID
        self.signerGeneration = signerGeneration
        self.transportIdentity = transportIdentity
        self.store = store
        self.signingKey = signingKey
        self.trustedCheckpoint = trustedCheckpoint
        self.pairingService = LOCALBPairingCoordinator(registryStore: store)
    }

    public func currentRegistrySnapshot() throws -> LOCALBRegistrySnapshot {
        let snapshot = try store.loadVerified(checkpoint: trustedCheckpoint)
        guard snapshot.currentLineageID == lineageID,
              let signer = snapshot.entry(for: signerKeyID),
              signer.status == .active,
              signer.generation == signerGeneration,
              signer.lineageID == lineageID,
              signer.publicKeyRaw == Array(signingKey.publicKey.rawRepresentation) else {
            throw LOCALBStatus.hostNotOperational
        }
        return snapshot
    }

    /// LOCALB record signing is available only through an activated context and
    /// is re-authorized against the latest registry snapshot on every call.
    public func signRecord(_ record: PersistentSRSRecord) throws -> [UInt8] {
        let snapshot = try currentRegistrySnapshot()
        return try LOCALBRecordWriter.encode(
            record: record,
            signingKey: signingKey,
            lineageID: lineageID,
            issuerGeneration: signerGeneration,
            registry: snapshot
        )
    }

    /// Retain and reuse this coordinator for challenge issue/consume so its
    /// single-use challenge ledger remains shared across the server lifecycle.
    public func pairingCoordinator() -> LOCALBPairingCoordinator {
        pairingService
    }

    /// Current registry head checkpoint, re-verified against the trusted
    /// anchor on every call. Production request-authorization wiring uses
    /// this as the per-call trusted checkpoint so clients paired after this
    /// process started are still authorized, without ever trusting an
    /// unverified head.
    public func currentTrustedCheckpoint() throws -> LOCALBRegistryCheckpoint {
        try store.currentCheckpoint(extending: trustedCheckpoint)
    }
}

public enum LOCALBHostBootstrap {
    /// Explicit local first-run ceremony. Creates a key only on this path, then
    /// creates the first registry lineage and registers generation 1. It
    /// returns SETUP/PENDING, never an operational context.
    public static func prepareFirstRun(
        rootURL: URL,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore = LOCALBTransportIdentityStore()
    ) throws -> LOCALBHostPendingActivation {
        let root = rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw LOCALBStatus.registryAlreadyInitialized }
            let children = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil
            )
            guard children.isEmpty else {
                // Existing files without an intact registry are NOT silently
                // treated as first-run; require explicit recovery.
                throw LOCALBStatus.registryAlreadyInitialized
            }
        }
        // Transport (TLS) identity first: if its creation fails, the registry
        // root is still EMPTY and first-run can be retried cleanly — the
        // registry is never advanced into a state that blocks its own
        // restart. Existing Keychain items follow read-only recovery rules;
        // a failure here never silently deletes or rebuilds an identity.
        let transport = try transportIdentityStore.loadOrCreate()
        let store = LOCALBRegistryStore(rootURL: root)
        let signingKey = try keychainStore.loadOrCreate()
        let genesisCheckpoint = try store.initializeNewLineage()
        let publicKeyRaw = Array(signingKey.publicKey.rawRepresentation)
        let keyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: publicKeyRaw)
        let registeredCheckpoint = try store.appendKeyRegistration(
            publicKeyRaw: publicKeyRaw,
            generation: 1,
            checkpoint: genesisCheckpoint
        )
        let snapshot = try store.loadVerified(checkpoint: registeredCheckpoint)
        guard let entry = snapshot.entry(for: keyID),
              entry.status == .active,
              entry.generation == 1,
              entry.lineageID == registeredCheckpoint.lineageID,
              entry.publicKeyRaw == publicKeyRaw else {
            throw LOCALBStatus.hostNotOperational
        }
        return LOCALBHostPendingActivation(
            lineageID: snapshot.currentLineageID,
            signerKeyID: keyID,
            signerGeneration: 1,
            checkpoint: registeredCheckpoint,
            transportSPKIHashHex: transport.spkiSHA256Hex
        )
    }

    /// First activation is stricter than ordinary restart: the externally
    /// recorded checkpoint must equal the current head, not merely be a prefix.
    public static func activateInitialSetup(
        rootURL: URL,
        operatorRecordedCheckpoint: LOCALBRegistryCheckpoint,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore = LOCALBTransportIdentityStore()
    ) throws -> LOCALBHostRuntimeContext {
        let store = LOCALBRegistryStore(rootURL: rootURL.standardizedFileURL)
        let current = try store.currentCheckpoint(extending: operatorRecordedCheckpoint)
        guard current.lineageID == operatorRecordedCheckpoint.lineageID,
              current.sequence == operatorRecordedCheckpoint.sequence,
              LOCALBBinary.constantTimeEqual(current.headHash, operatorRecordedCheckpoint.headHash) else {
            throw LOCALBStatus.registryCheckpointMismatch
        }
        return try openOperational(
            rootURL: rootURL,
            trustedCheckpoint: operatorRecordedCheckpoint,
            keychainStore: keychainStore,
            transportIdentityStore: transportIdentityStore
        )
    }

    /// Normal startup. It never creates or rotates a Keychain key. The registry
    /// must verify against a trusted external checkpoint, and the existing
    /// Keychain public key must byte-match the single ACTIVE registry entry.
    public static func openOperational(
        rootURL: URL,
        trustedCheckpoint: LOCALBRegistryCheckpoint,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore = LOCALBTransportIdentityStore()
    ) throws -> LOCALBHostRuntimeContext {
        let store = LOCALBRegistryStore(rootURL: rootURL.standardizedFileURL)
        let state = try store.loadPairingState(checkpoint: trustedCheckpoint)
        let active = state.signingKeys.filter { $0.status == .active }
        guard active.count == 1, let activeEntry = active.first,
              activeEntry.lineageID == state.lineageID else {
            throw LOCALBStatus.registryNoActiveKey
        }

        // Important: ordinary startup calls loadExisting, never loadOrCreate.
        let signingKey = try keychainStore.loadExisting()
        let publicKeyRaw = Array(signingKey.publicKey.rawRepresentation)
        let recomputedKeyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: publicKeyRaw)
        guard recomputedKeyID == activeEntry.keyID,
              LOCALBBinary.constantTimeEqual(publicKeyRaw, activeEntry.publicKeyRaw) else {
            throw LOCALBStatus.hostNotOperational
        }

        // Ordinary startup never creates or replaces the transport identity;
        // a missing identity fails closed with no regeneration.
        let transportIdentity = try transportIdentityStore.loadExisting()

        return LOCALBHostRuntimeContext(
            lineageID: state.lineageID,
            signerKeyID: activeEntry.keyID,
            signerGeneration: activeEntry.generation,
            transportIdentity: transportIdentity,
            store: store,
            signingKey: signingKey,
            trustedCheckpoint: trustedCheckpoint
        )
    }
}
