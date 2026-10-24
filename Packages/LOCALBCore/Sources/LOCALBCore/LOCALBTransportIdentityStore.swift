import Crypto
import Foundation
import Security
import SwiftASN1
import X509

/// Test-target-only injection points for deterministic failure/retry tests
/// (same pattern as SRSRefreshFailureInjector). Production code never sets
/// them; both hooks are one-shot (consumed on next use); every test must
/// still reset them defensively.
enum LocalBTransportTestHooks {
    /// When true, the NEXT createVerifiedIdentity call fails with
    /// .transportIdentityCorrupt AFTER the private key has been permanently
    /// written but BEFORE certificate creation — the exact partial-write
    /// failure window. One-shot: cleared by the consuming call.
    static var failAfterKeyWrite = false
    /// When non-nil, the next createVerifiedIdentity call uses this exact
    /// attempt ID, making physical key tags deterministic. One-shot: the
    /// consuming call reads and clears it.
    static var nextAttemptID: String?

    static func reset() {
        failAfterKeyWrite = false
        nextAttemptID = nil
    }

    /// Consumes the pending attempt-ID override (if any), defaulting to a
    /// fresh full UUID.
    static func takeAttemptID() -> String {
        if let pending = nextAttemptID {
            nextAttemptID = nil
            return pending
        }
        return UUID().uuidString.lowercased()
    }
}

#if canImport(Security)

/// A loaded LOCALB transport (TLS) identity: the certificate DER, the SPKI
/// fingerprint that pairing credentials bind to, and the real `SecIdentity`
/// required by `NWProtocolTLS`. The SecIdentity is only produced after the
/// full delivery chain has been verified: certificate parses, the certificate
/// public key matches the Keychain-stored private key, and the Keychain
/// synthesizes a usable identity for that exact certificate.
public struct LOCALBTransportIdentityHandle {
    public let certificateDER: [UInt8]
    public let spkiSHA256Hex: String
    public let secIdentity: SecIdentity
}

/// LOCALB Trust Domain B transport (TLS) server identity store.
///
/// Completely separate Keychain items, usage, and lifecycle from the LOCALB
/// record-signing key (`LOCALBKeychainSignerStore`): a different service, a
/// different account family, and independent rotation. Rotating one identity
/// never touches the other.
///
/// Layout (per store instance), designed around an explicit commit point:
///   - INDEX item: one generic password (service/account) whose data is a
///     small JSON envelope {version, generation, certificate_der, key_tag}.
///     The index is the SINGLE authoritative pointer; updating it is the
///     commit of a new identity (one atomic SecItemUpdate).
///   - Per generation g: a permanent kSecClassKey item tagged
///     "<service>#<account>#key#g<g>" (keys are retrieved by application
///     tag — label queries do not match kSecClassKey) and a
///     kSecClassCertificate item labeled "<service>#<account>#cert#g<g>"
///     (needed so the Keychain can synthesize the SecIdentity).
///
/// Failure semantics (2026-10-16 review fixes):
///   - No failure path ever deletes existing items. A lost concurrent race
///     re-reads and returns the winner's verified identity; a partial state
///     (some items missing or corrupt) is an EXPLICIT failure that preserves
///     evidence for the operator — never a guess-and-clear recovery.
///   - rotate() builds and fully verifies the NEXT generation under fresh,
///     collision-free tags BEFORE the single-index-update commit. Failure
///     before the commit leaves the current identity untouched; failure
///     after it leaves the new identity usable (superseded old-generation
///     items may linger as unreachable orphans — harmless, unique tags).
public struct LOCALBTransportIdentityStore {
    public let service: String
    public let account: String
    /// Optional dedicated keychain FILE that scopes every item operation of
    /// this store (index, key, certificate, identity synthesis).
    ///
    /// `nil` is the production default outside an isolated root: items live in
    /// the process default Keychain search list, i.e. the login Keychain, so
    /// existing identities and pairing credentials survive.
    ///
    /// When `SIMIGO_HOME` redirects the managed root (isolated test / candidate
    /// runs), the default resolves to a keychain file INSIDE that root, so a
    /// run can never leave transport identities in the real login Keychain.
    /// This is the only identity material the isolation roots used to miss.
    public let keychainPath: String?

    public init(service: String = "com.simigo.localb-transport-identity",
                account: String = "tls-identity-v1",
                keychainPath: String? = LOCALBTransportIdentityStore.defaultIsolatedKeychainPath()) {
        self.service = service
        self.account = account
        self.keychainPath = keychainPath
    }

    /// Default scoping rule: only an explicitly isolated managed root scopes
    /// the identity into its own keychain file.
    public static func defaultIsolatedKeychainPath(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let home = env["SIMIGO_HOME"], !home.isEmpty else { return nil }
        let root = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        return root
            .appendingPathComponent("localb", isDirectory: true)
            .appendingPathComponent("transport-identity.keychain-db", isDirectory: false)
            .path
    }

    /// Physical tags are unique PER ATTEMPT, not per logical generation: a
    /// failed attempt whose key was permanently written but whose
    /// certificate/verification/index-commit never completed leaves an
    /// orphan that can NEVER collide with a retry (which draws a fresh
    /// attempt ID). The logical generation number is audit/display metadata
    /// carried in the index; the index's stored key tag is the single
    /// physical pointer.
    private func keyTag(generation: UInt32, attemptID: String) -> Data {
        Data("\(service)#\(account)#key#g\(generation)#a\(attemptID)".utf8)
    }

    private func certLabel(generation: UInt32, attemptID: String) -> String {
        "\(service)#\(account)#cert#g\(generation)#a\(attemptID)"
    }

    /// Process-wide serialization of identity-mutating operations. Identity
    /// creation/rotation is a rare operator action; concurrent Keychain
    /// call sequences (create key + add cert + synthesize identity + commit
    /// index) from multiple threads can interleave into Security-framework
    /// internal waits. Serializing preserves the observable semantics — all
    /// concurrent callers still return the winner's stable verified SPKI —
    /// while eliminating the interleaving. Read paths (loadExisting) do not
    /// take this lock.
    private static let mutationLock = NSLock()

    // MARK: - Keychain scoping

    /// Opens (or creates) the scoped keychain file. A keychain created here is
    /// unlocked with an empty password: it is a throwaway store inside an
    /// isolated root, kept at 0600, never a user credential container.
    private func resolveKeychain() throws -> SecKeychain? {
        guard let path = keychainPath else { return nil }
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
        } catch {
            throw LOCALBStatus.keychainUnavailable
        }
        if !fm.fileExists(atPath: path) {
            var created: SecKeychain?
            let createStatus = SecKeychainCreate(path, 0, "", false, nil, &created)
            if createStatus == errSecSuccess, let created {
                chmod(path, 0o600)
                return created
            }
            guard createStatus == errSecDuplicateItem else {
                throw LOCALBStatus.keychainUnavailable
            }
        }
        var opened: SecKeychain?
        let openStatus = SecKeychainOpen(path, &opened)
        guard openStatus == errSecSuccess, let keychain = opened else {
            throw LOCALBStatus.keychainUnavailable
        }
        SecKeychainUnlock(keychain, 0, "", true)
        return keychain
    }

    /// Add-side scoping (`kSecUseKeychain`). Public so callers that must issue
    /// their own Keychain writes (tests, diagnostics) hit the same store.
    public func scopedAdd(_ attributes: [String: Any]) throws -> [String: Any] {
        guard let keychain = try resolveKeychain() else { return attributes }
        var out = attributes
        out[kSecUseKeychain as String] = keychain
        return out
    }

    /// Query-side scoping (`kSecMatchSearchList`) for copy/update/delete.
    /// Public for the same reason as `scopedAdd`; it throws instead of silently
    /// falling back to the login Keychain when a scoped file cannot be opened.
    public func scopedQuery(_ query: [String: Any]) throws -> [String: Any] {
        guard let keychain = try resolveKeychain() else { return query }
        var out = query
        out[kSecMatchSearchList as String] = [keychain]
        return out
    }

    /// Best-effort scoped delete; a store without a scoped keychain keeps the
    /// previous (search-list) behaviour.
    private func deleteScoped(_ query: [String: Any]) {
        guard let resolved = try? scopedQuery(query) else { return }
        SecItemDelete(resolved as CFDictionary)
    }

    // MARK: - SPKI computation

    /// SHA-256 over the certificate's DER `SubjectPublicKeyInfo` sequence.
    ///
    /// Implementation note: `Certificate.PublicKey.subjectPublicKeyInfoBytes`
    /// deliberately NOT used — it returns algorithm-specific canonical key
    /// bytes (e.g. ANSI X9.63), not the DER SPKI encoding. The SPKI DER is
    /// obtained by DER-serializing `Certificate.PublicKey`, whose default
    /// ASN.1 identifier is exactly SubjectPublicKeyInfo.
    public static func spkiSHA256(ofCertificateDER der: [UInt8]) throws -> [UInt8] {
        let certificate = try Certificate(derEncoded: der[...])
        var serializer = DER.Serializer()
        try certificate.publicKey.serialize(
            into: &serializer,
            withIdentifier: Certificate.PublicKey.defaultIdentifier
        )
        return Array(SHA256.hash(data: Data(serializer.serializedBytes)))
    }

    public static func spkiSHA256Hex(ofCertificateDER der: [UInt8]) throws -> String {
        LOCALBBinary.hexLower(try spkiSHA256(ofCertificateDER: der))
    }

    /// Client-side convenience: compute the SPKI fingerprint from a
    /// `SecCertificate` obtained via `SecTrust` during a TLS handshake.
    public static func spkiSHA256Hex(of secCertificate: SecCertificate) throws -> String {
        let der = [UInt8](SecCertificateCopyData(secCertificate) as Data)
        return try spkiSHA256Hex(ofCertificateDER: der)
    }

    /// DER bytes of a certificate (internal; shared with tests).
    static func certificateDER(_ certificate: Certificate) throws -> [UInt8] {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer, withIdentifier: Certificate.defaultIdentifier)
        return serializer.serializedBytes
    }

    // MARK: - Index envelope

    private struct IndexEnvelope {
        var generation: UInt32
        var certificateDER: [UInt8]
        var keyTag: Data
        var certLabel: String
    }

    private static func encodeIndex(_ envelope: IndexEnvelope) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "version": 2,
            "generation": Int(envelope.generation),
            "certificate_der": Data(envelope.certificateDER).base64EncodedString(),
            "key_tag": envelope.keyTag.base64EncodedString(),
            "cert_label": envelope.certLabel
        ])
    }

    private static func decodeIndex(_ data: Data) throws -> IndexEnvelope {
        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LOCALBStatus.transportIdentityCorrupt
            }
            object = decoded
        } catch let error as LOCALBStatus {
            throw error
        } catch {
            throw LOCALBStatus.transportIdentityCorrupt
        }
        guard let version = object["version"] as? Int, version == 2,
              let generation = object["generation"] as? Int,
              generation >= 1,
              // Upper bound BEFORE the UInt32 conversion: an out-of-range
              // value in a corrupt index must be a typed failure, never a
              // runtime trap.
              generation <= Int(UInt32.max),
              let derB64 = object["certificate_der"] as? String,
              let derData = Data(base64Encoded: derB64),
              let tagB64 = object["key_tag"] as? String,
              let tagData = Data(base64Encoded: tagB64),
              let certLabel = object["cert_label"] as? String else {
            throw LOCALBStatus.transportIdentityCorrupt
        }
        return IndexEnvelope(
            generation: UInt32(generation),
            certificateDER: [UInt8](derData),
            keyTag: tagData,
            certLabel: certLabel
        )
    }

    // MARK: - Load / create

    /// Ordinary startup path: NEVER creates or replaces a missing identity.
    public func loadExisting() throws -> LOCALBTransportIdentityHandle {
        guard let existing = try readExisting() else {
            throw LOCALBStatus.transportIdentityMissing
        }
        return existing
    }

    /// Explicit first-run (and rotation) path: the ONLY path that creates
    /// items. Concurrent first-use races are resolved WITHOUT destruction:
    /// a caller whose key creation lost the race re-reads and returns the
    /// winner's verified identity; any partial state is an explicit failure
    /// with evidence preserved.
    @discardableResult
    public func loadOrCreate() throws -> LOCALBTransportIdentityHandle {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        if let existing = try readExisting() { return existing }
        let current = try readIndexEnvelope()
        // A present-but-corrupt index is an explicit failure; it is never
        // cleared or overwritten by loadOrCreate. A generation at the UInt32
        // ceiling is a typed exhaustion failure, never an overflow trap.
        let baseGeneration = current?.generation ?? 0
        guard baseGeneration < UInt32.max else {
            throw LOCALBStatus.transportIdentityGenerationExhausted
        }
        let generation = baseGeneration + 1
        let attemptID = LocalBTransportTestHooks.takeAttemptID()

        let der: [UInt8]
        do {
            der = try createVerifiedIdentity(
                generation: generation,
                keyTag: keyTag(generation: generation, attemptID: attemptID),
                certLabel: certLabel(generation: generation, attemptID: attemptID)
            )
        } catch {
            // NEVER destructive on failure. Re-query first: a concurrent
            // caller may have committed a complete, verified identity — if
            // so, reuse the winner's identity instead of failing.
            if let winner = try readExisting() { return winner }
            throw error
        }

        // Commit: the index add is the single pointer flip. On a concurrent
        // duplicate (another caller committed first), re-read and return the
        // winner's identity; our just-created attempt items remain as
        // unreachable orphans with unique per-attempt tags — harmless, and
        // swept by a later rotate/deleteAll.
        let indexAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: try Self.encodeIndex(IndexEnvelope(
                generation: generation,
                certificateDER: der,
                keyTag: keyTag(generation: generation, attemptID: attemptID),
                certLabel: certLabel(generation: generation, attemptID: attemptID)
            ))
        ]
        let indexStatus = SecItemAdd(try scopedAdd(indexAttributes) as CFDictionary, nil)
        if indexStatus == errSecDuplicateItem {
            guard let winner = try readExisting() else {
                // The other caller's items are incomplete: explicit failure,
                // evidence preserved.
                throw LOCALBStatus.transportIdentityCorrupt
            }
            return winner
        }
        guard indexStatus == errSecSuccess else {
            throw LOCALBStatus.keychainUnavailable
        }

        guard let handle = try readExisting() else {
            throw LOCALBStatus.transportIdentityCorrupt
        }
        return handle
    }

    /// Explicit rotation ceremony: builds and FULLY verifies the next
    /// generation under fresh, collision-free tags, then commits with a
    /// single atomic index update. Failure before the commit leaves the
    /// current identity untouched; the old SPKI fingerprint is returned for
    /// operator re-pairing notices and is never served again afterwards.
    @discardableResult
    public func rotate() throws -> (new: LOCALBTransportIdentityHandle, previousSPKIHex: String) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        let previous = try loadExisting()
        let previousEnvelope = try readIndexEnvelope()

        // Generation ceiling: a typed exhaustion failure, never an overflow.
        let baseGeneration = previousEnvelope?.generation ?? 1
        guard baseGeneration < UInt32.max else {
            throw LOCALBStatus.transportIdentityGenerationExhausted
        }
        let generation = baseGeneration + 1
        let attemptID = LocalBTransportTestHooks.takeAttemptID()
        let der = try createVerifiedIdentity(
            generation: generation,
            keyTag: keyTag(generation: generation, attemptID: attemptID),
            certLabel: certLabel(generation: generation, attemptID: attemptID)
        )

        // COMMIT POINT: one atomic index update flips the identity pointer.
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: try Self.encodeIndex(IndexEnvelope(
                generation: generation,
                certificateDER: der,
                keyTag: keyTag(generation: generation, attemptID: attemptID),
                certLabel: certLabel(generation: generation, attemptID: attemptID)
            ))
        ]
        let commitStatus = SecItemUpdate(
            try scopedQuery(updateQuery) as CFDictionary, updateAttrs as CFDictionary)
        guard commitStatus == errSecSuccess else {
            // Commit failed: the NEW generation items exist but are
            // unreachable; the CURRENT identity is untouched. Explicit
            // failure, evidence preserved.
            throw LOCALBStatus.keychainUnavailable
        }

        guard let handle = try readExisting() else {
            throw LOCALBStatus.transportIdentityCorrupt
        }

        // Best-effort sweep of the superseded generation's items. Failure is
        // harmless: unique tags keep them unreachable.
        if let old = previousEnvelope {
            deleteScoped([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: old.keyTag
            ])
            deleteScoped([
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: old.certLabel
            ])
        }

        return (handle, previous.spkiSHA256Hex)
    }

    /// Removes this store's items (operator reset / test cleanup). Deletes
    /// the index-referenced generation items and the index; orphaned
    /// generations from failed rotates are left in place (unreachable,
    /// unique tags) rather than guessed at.
    public func deleteAll() {
        if let envelope = try? readIndexEnvelope() {
            deleteScoped([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: envelope.keyTag
            ])
            deleteScoped([
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: envelope.certLabel
            ])
        }
        deleteScoped([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ])
    }

    // MARK: - Internals

    private func readIndexEnvelope() throws -> IndexEnvelope? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(try scopedQuery(query) as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw LOCALBStatus.keychainUnavailable
        }
        return try Self.decodeIndex(data)
    }

    private func readExisting() throws -> LOCALBTransportIdentityHandle? {
        // Index: the single authoritative pointer.
        guard let envelope = try readIndexEnvelope() else { return nil }

        return try verifyDeliveryChain(
            certificateDER: envelope.certificateDER,
            keyTag: envelope.keyTag
        )
    }

    /// Creates a fresh key + self-signed certificate under the given tags and
    /// verifies the full delivery chain, returning the verified certificate
    /// DER. NEVER deletes or overwrites any existing item.
    private func createVerifiedIdentity(
        generation: UInt32,
        keyTag: Data,
        certLabel: String
    ) throws -> [UInt8] {
        // 1. Generate the private key INSIDE the Keychain (permanent, tagged)
        //    so that the Keychain can synthesize a real SecIdentity for TLS.
        let keyAttributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrLabel as String: certLabel + ".key",
            kSecAttrIsPermanent as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var keyRequest = keyAttributes
        keyRequest[kSecUseKeychain as String] = try resolveKeychain()
        guard let storedKey = SecKeyCreateRandomKey(keyRequest as CFDictionary, nil) else {
            // Never destructive on failure: if the tag is taken, a concurrent
            // caller or a previous orphan owns it; if the Keychain is simply
            // unavailable, nothing is deleted either way. The caller decides.
            throw LOCALBStatus.keychainUnavailable
        }

        // Export the private material once (software key) to build the
        // self-signed certificate. macOS returns the SEC1 combined form:
        // 0x04 || public X||Y (64 bytes) || private scalar (32 bytes).
        guard let external = SecKeyCopyExternalRepresentation(storedKey, nil) as Data?,
              external.count == 97, external.first == 0x04,
              let signingKey = try? P256.Signing.PrivateKey(
                  rawRepresentation: Data(external[65..<97])) else {
            throw LOCALBStatus.transportIdentityCorrupt
        }

        // Test-only partial-write injection: the key is now PERMANENTLY in
        // the Keychain; fail before the certificate step. This reproduces
        // the exact failure window the per-attempt IDs must survive.
        if LocalBTransportTestHooks.failAfterKeyWrite {
            LocalBTransportTestHooks.failAfterKeyWrite = false
            throw LOCALBStatus.transportIdentityCorrupt
        }

        // 2. Self-signed certificate, valid for ten years; rotation is an
        //    explicit ceremony and never silent.
        let commonName = "SimiGo LOCALB Transport g\(generation) " +
            LOCALBBinary.hexLower(Array(UUID().uuidString.utf8.sha256().prefix(8)))
        var serialBytes = [UInt8](repeating: 0, count: 16)
        let rngResult = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
        guard rngResult == errSecSuccess else { throw LOCALBStatus.keychainUnavailable }
        let certificate: Certificate
        do {
            let name = try DistinguishedName { CommonName(commonName) }
            certificate = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(bytes: serialBytes),
                publicKey: Certificate.PublicKey(signingKey.publicKey),
                notValidBefore: Date().addingTimeInterval(-86_400),
                notValidAfter: Date().addingTimeInterval(10 * 365 * 86_400),
                issuer: name,
                subject: name,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: Certificate.Extensions(),
                issuerPrivateKey: Certificate.PrivateKey(signingKey)
            )
        } catch {
            throw LOCALBStatus.transportIdentityCorrupt
        }
        let der = try Self.certificateDER(certificate)

        // 3. Persist the certificate item (needed for SecIdentity synthesis).
        guard let secCertificate = SecCertificateCreateWithData(nil, Data(der) as CFData) else {
            throw LOCALBStatus.transportIdentityCorrupt
        }
        let certAttributes: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certLabel,
            kSecValueRef as String: secCertificate
        ]
        let certStatus = SecItemAdd(try scopedAdd(certAttributes) as CFDictionary, nil)
        guard certStatus == errSecSuccess || certStatus == errSecDuplicateItem else {
            throw LOCALBStatus.keychainUnavailable
        }

        // 4. Verify the full delivery chain of what was just created.
        _ = try verifyDeliveryChain(certificateDER: der, keyTag: keyTag)
        return der
    }

    /// Full delivery-chain verification: certificate parses; the certificate
    /// public key matches the Keychain-stored private key found by tag; the
    /// Keychain synthesizes a real SecIdentity for exactly this certificate.
    private func verifyDeliveryChain(
        certificateDER der: [UInt8],
        keyTag: Data
    ) throws -> LOCALBTransportIdentityHandle {
        let certificate: Certificate
        do {
            certificate = try Certificate(derEncoded: der[...])
        } catch {
            throw LOCALBStatus.transportIdentityCorrupt
        }

        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var keyResult: CFTypeRef?
        let keyStatus = SecItemCopyMatching(
            try scopedQuery(keyQuery) as CFDictionary, &keyResult)
        guard keyStatus == errSecSuccess, let keyRef = keyResult else {
            // Index points at a key that is absent: partial state — explicit
            // failure, evidence preserved.
            throw keyStatus == errSecItemNotFound
                ? LOCALBStatus.transportIdentityCorrupt
                : LOCALBStatus.keychainUnavailable
        }
        let secKey = unsafeDowncast(keyRef, to: SecKey.self)

        guard let publicSecKey = SecKeyCopyPublicKey(secKey),
              let publicExternal = SecKeyCopyExternalRepresentation(publicSecKey, nil) as Data?,
              let publicKey = try? P256.Signing.PublicKey(x963Representation: publicExternal),
              certificate.publicKey == Certificate.PublicKey(publicKey) else {
            throw LOCALBStatus.transportIdentityMismatch
        }

        guard let secCertificate = SecCertificateCreateWithData(nil, Data(der) as CFData) else {
            throw LOCALBStatus.transportIdentityCorrupt
        }
        var identityRef: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(
            try resolveKeychain(), secCertificate, &identityRef)
        guard identityStatus == errSecSuccess, let identity = identityRef else {
            throw LOCALBStatus.transportIdentityMismatch
        }

        return LOCALBTransportIdentityHandle(
            certificateDER: der,
            spkiSHA256Hex: try Self.spkiSHA256Hex(ofCertificateDER: der),
            secIdentity: identity
        )
    }
}

extension Sequence where Element == UInt8 {
    fileprivate func sha256() -> [UInt8] {
        Array(SHA256.hash(data: Data(self)))
    }
}

/// Keychain-file scoping shared by every LOCALB Keychain store.
///
/// The isolation roots used to redirect the filesystem only; Keychain items
/// always landed in the login Keychain. A store built under a redirected
/// `SIMIGO_HOME` now keeps its items in
/// `<SIMIGO_HOME>/localb/<file>.keychain-db`, scoped per call, so an isolated
/// run cannot add items to real user state. Outside an isolated root `path` is
/// nil and the default search list (the login Keychain) is used unchanged.
public struct LOCALBKeychainScope {
    let path: String?
    let fileName: String

    public init(path: String?, fileName: String) {
        self.path = path
        self.fileName = fileName
    }

    public static func isolatedDefault(
        fileName: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let home = env["SIMIGO_HOME"], !home.isEmpty else { return nil }
        let root = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        return root
            .appendingPathComponent("localb", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
            .path
    }

    func resolve() throws -> SecKeychain? {
        guard let path else { return nil }
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
        } catch {
            throw LOCALBStatus.keychainUnavailable
        }
        if !fm.fileExists(atPath: path) {
            var created: SecKeychain?
            let createStatus = SecKeychainCreate(path, 0, "", false, nil, &created)
            if createStatus == errSecSuccess, let created {
                chmod(path, 0o600)
                return created
            }
            guard createStatus == errSecDuplicateItem else {
                throw LOCALBStatus.keychainUnavailable
            }
        }
        var opened: SecKeychain?
        let openStatus = SecKeychainOpen(path, &opened)
        guard openStatus == errSecSuccess, let keychain = opened else {
            throw LOCALBStatus.keychainUnavailable
        }
        SecKeychainUnlock(keychain, 0, "", true)
        return keychain
    }

    func addScope(_ attributes: [String: Any]) throws -> [String: Any] {
        guard let keychain = try resolve() else { return attributes }
        var out = attributes
        out[kSecUseKeychain as String] = keychain
        return out
    }

    func queryScope(_ query: [String: Any]) throws -> [String: Any] {
        guard let keychain = try resolve() else { return query }
        var out = query
        out[kSecMatchSearchList as String] = [keychain]
        return out
    }

    func deleteScoped(_ query: [String: Any]) {
        guard let resolved = try? queryScope(query) else { return }
        SecItemDelete(resolved as CFDictionary)
    }
}

#endif
