import io, sys
p = "/Users/mr.simi/Documents/SimiGo/Packages/LOCALBCore/Sources/LOCALBCore/LOCALBTransportIdentityStore.swift"
s = open(p, encoding="utf-8").read()
R = []

R.append((
'''public struct LOCALBTransportIdentityStore {
    public let service: String
    public let account: String

    public init(service: String = "com.simigo.localb-transport-identity",
                account: String = "tls-identity-v1") {
        self.service = service
        self.account = account
    }''',
'''public struct LOCALBTransportIdentityStore {
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
    }'''))

R.append((
'''    private static let mutationLock = NSLock()''',
'''    private static let mutationLock = NSLock()

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

    /// Add-side scoping (`kSecUseKeychain`).
    private func scoped(_ attributes: [String: Any]) throws -> [String: Any] {
        guard let keychain = try resolveKeychain() else { return attributes }
        var out = attributes
        out[kSecUseKeychain as String] = keychain
        return out
    }

    /// Query-side scoping (`kSecMatchSearchList`) for copy/update/delete.
    private func searchScoped(_ query: [String: Any]) throws -> [String: Any] {
        guard let keychain = try resolveKeychain() else { return query }
        var out = query
        out[kSecMatchSearchList as String] = [keychain]
        return out
    }

    /// Best-effort scoped delete; a store without a scoped keychain keeps the
    /// previous (search-list) behaviour.
    private func deleteScoped(_ query: [String: Any]) {
        guard let scopedQuery = try? searchScoped(query) else { return }
        SecItemDelete(scopedQuery as CFDictionary)
    }'''))

R.append(('        let indexStatus = SecItemAdd(indexAttributes as CFDictionary, nil)',
          '        let indexStatus = SecItemAdd(try scoped(indexAttributes) as CFDictionary, nil)'))
R.append(('        let commitStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)',
          '        let commitStatus = SecItemUpdate(\n            try searchScoped(updateQuery) as CFDictionary, updateAttrs as CFDictionary)'))
R.append((
'''        if let old = previousEnvelope {
            SecItemDelete([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: old.keyTag
            ] as CFDictionary)
            SecItemDelete([
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: old.certLabel
            ] as CFDictionary)
        }''',
'''        if let old = previousEnvelope {
            deleteScoped([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: old.keyTag
            ])
            deleteScoped([
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: old.certLabel
            ])
        }'''))
R.append((
'''        if let envelope = try? readIndexEnvelope() {
            SecItemDelete([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: envelope.keyTag
            ] as CFDictionary)
            SecItemDelete([
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: envelope.certLabel
            ] as CFDictionary)
        }
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)''',
'''        if let envelope = try? readIndexEnvelope() {
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
        ])'''))
R.append(('        let status = SecItemCopyMatching(query as CFDictionary, &result)',
          '        let status = SecItemCopyMatching(try searchScoped(query) as CFDictionary, &result)'))
R.append(('        guard let storedKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, nil) else {',
          '        var keyRequest = keyAttributes\n        keyRequest[kSecUseKeychain as String] = try resolveKeychain()\n        guard let storedKey = SecKeyCreateRandomKey(keyRequest as CFDictionary, nil) else {'))
R.append(('        let certStatus = SecItemAdd(certAttributes as CFDictionary, nil)',
          '        let certStatus = SecItemAdd(try scoped(certAttributes) as CFDictionary, nil)'))
R.append(('        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyResult)',
          '        let keyStatus = SecItemCopyMatching(\n            try searchScoped(keyQuery) as CFDictionary, &keyResult)'))
R.append(('        let identityStatus = SecIdentityCreateWithCertificate(nil, secCertificate, &identityRef)',
          '        let identityStatus = SecIdentityCreateWithCertificate(\n            try resolveKeychain(), secCertificate, &identityRef)'))

for i, (old, new) in enumerate(R):
    n = s.count(old)
    if n != 1:
        print("FAIL replacement %d count=%d" % (i, n)); sys.exit(1)
    s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
print("patched %d replacements; bytes=%d" % (len(R), len(s)))
