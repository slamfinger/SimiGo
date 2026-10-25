import sys

def apply(path, pairs):
    s = open(path, encoding="utf-8").read()
    for i,(o,n) in enumerate(pairs):
        c = s.count(o)
        if c != 1:
            print("FAIL %s replacement %d count=%d" % (path, i, c)); sys.exit(1)
        s = s.replace(o,n)
    open(path,"w",encoding="utf-8").write(s)
    print("patched %s (%d)" % (path, len(pairs)))

A = "/Users/mr.simi/Documents/SimiGo/Packages/LOCALBCore/Tests/LOCALBCoreTests/LOCALBTransportIdentityStoreTests.swift"
apply(A, [
 ("import Crypto\nimport Foundation\nimport X509",
  "import Crypto\nimport Foundation\nimport Security\nimport X509"),
 ("""        XCTAssertEqual(
            SecItemUpdate(corruptQuery as CFDictionary, corruptUpdate as CFDictionary),
            errSecSuccess
        )""",
  """        XCTAssertEqual(
            SecItemUpdate(try store.scopedQuery(corruptQuery) as CFDictionary,
                          corruptUpdate as CFDictionary),
            errSecSuccess
        )"""),
 ("""        defer {
            SecItemDelete([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: orphanTag
            ] as CFDictionary)
        }""",
  """        defer {
            if let scoped = try? store.scopedQuery([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: orphanTag
            ]) { SecItemDelete(scoped as CFDictionary) }
        }"""),
 ("""        XCTAssertEqual(SecItemCopyMatching(orphanQuery as CFDictionary, &orphanRef),
                       errSecSuccess,""",
  """        XCTAssertEqual(SecItemCopyMatching(try store.scopedQuery(orphanQuery) as CFDictionary,
                                           &orphanRef),
                       errSecSuccess,"""),
 ("""        XCTAssertEqual(
            SecItemUpdate(indexQueryDict(for: store) as CFDictionary,
                          [kSecValueData as String: Data(outOfRange.utf8)] as CFDictionary),
            errSecSuccess
        )""",
  """        XCTAssertEqual(
            SecItemUpdate(try store.scopedQuery(indexQueryDict(for: store)) as CFDictionary,
                          [kSecValueData as String: Data(outOfRange.utf8)] as CFDictionary),
            errSecSuccess
        )"""),
 ("""        XCTAssertEqual(SecItemCopyMatching(readQuery as CFDictionary, &readResult),
                       errSecSuccess)""",
  """        XCTAssertEqual(SecItemCopyMatching(try store.scopedQuery(readQuery) as CFDictionary,
                                           &readResult),
                       errSecSuccess)"""),
 ("""        XCTAssertEqual(
            SecItemUpdate(indexQueryDict(for: store) as CFDictionary,
                          [kSecValueData as String: rewritten] as CFDictionary),
            errSecSuccess
        )""",
  """        XCTAssertEqual(
            SecItemUpdate(try store.scopedQuery(indexQueryDict(for: store)) as CFDictionary,
                          [kSecValueData as String: rewritten] as CFDictionary),
            errSecSuccess
        )"""),
 ("""    private func indexQueryDict(for store: LOCALBTransportIdentityStore) -> [String: Any] {""",
  """    // MARK: - Scoped (isolated) keychain

    /// The isolation roots used to cover every persisted path EXCEPT the
    /// Keychain: a run created transport identities in the real login
    /// Keychain. A scoped store must keep the index, key, certificate and the
    /// synthesized SecIdentity in its own keychain file.
    func testScopedKeychainKeepsIdentityOutOfTheDefaultSearchList() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("localb-scope-\\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let keychainPath = dir.appendingPathComponent("transport.keychain-db").path
        let store = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-scope.\\(UUID().uuidString)",
            account: "tls",
            keychainPath: keychainPath)
        let identity = try store.loadOrCreate()
        XCTAssertEqual(identity.spkiSHA256Hex.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keychainPath),
                      "the scoped store must live in its own keychain file")

        // A fresh instance over the SAME scoped file reloads the same identity
        // (process-restart semantics), including a usable SecIdentity.
        let reloaded = try LOCALBTransportIdentityStore(
            service: store.service, account: store.account, keychainPath: keychainPath
        ).loadExisting()
        XCTAssertEqual(reloaded.certificateDER, identity.certificateDER)
        var privateKey: SecKey?
        XCTAssertEqual(SecIdentityCopyPrivateKey(reloaded.secIdentity, &privateKey), errSecSuccess)
        XCTAssertNotNil(privateKey)

        // Nothing became visible to the process default search list (the login
        // Keychain in an unisolated run).
        var defaultRef: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: store.account,
            kSecReturnData as String: true
        ] as CFDictionary, &defaultRef), errSecItemNotFound)

        store.deleteAll()
        XCTAssertThrowsError(try store.loadExisting()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMissing)
        }
    }

    /// Scoping is derived from the isolation roots, never from a separate
    /// switch: a run that redirects `SIMIGO_HOME` cannot keep writing
    /// identities into the real login Keychain.
    func testDefaultKeychainPathOnlyFollowsAnIsolatedManagedRoot() {
        XCTAssertNil(LOCALBTransportIdentityStore.defaultIsolatedKeychainPath(env: [:]))
        XCTAssertNil(LOCALBTransportIdentityStore.defaultIsolatedKeychainPath(
            env: ["SIMIGO_HOME": ""]))
        XCTAssertEqual(
            LOCALBTransportIdentityStore.defaultIsolatedKeychainPath(
                env: ["SIMIGO_HOME": "/Users/example/iso-root"]),
            "/Users/example/iso-root/localb/transport-identity.keychain-db")
    }

    private func indexQueryDict(for store: LOCALBTransportIdentityStore) -> [String: Any] {"""),
])

B = "/Users/mr.simi/Documents/SimiGo/Packages/LOCALBCore/Tests/LOCALBCoreTests/LOCALBHostBootstrapTests.swift"
apply(B, [
 ("        XCTAssertEqual(SecItemAdd(corruptIndex as CFDictionary, nil), errSecSuccess)",
  "        XCTAssertEqual(SecItemAdd(try corruptStore.scopedAdd(corruptIndex) as CFDictionary, nil),\n                       errSecSuccess)"),
])

C = "/Users/mr.simi/Documents/SimiGo/SimiGoTests/LOCALBTransportWiringTests.swift"
apply(C, [
 ("        XCTAssertEqual(SecItemAdd(corruptIndex as CFDictionary, nil), errSecDuplicateItem)",
  "        XCTAssertEqual(SecItemAdd(try corruptStore.scopedAdd(corruptIndex) as CFDictionary, nil),\n                       errSecDuplicateItem)"),
 ("""        XCTAssertEqual(
            SecItemUpdate(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: corruptStore.service,
                    kSecAttrAccount as String: corruptStore.account
                ] as CFDictionary,
                [kSecValueData as String: Data("garbage".utf8)] as CFDictionary
            ),
            errSecSuccess
        )""",
  """        XCTAssertEqual(
            SecItemUpdate(
                try corruptStore.scopedQuery([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: corruptStore.service,
                    kSecAttrAccount as String: corruptStore.account
                ]) as CFDictionary,
                [kSecValueData as String: Data("garbage".utf8)] as CFDictionary
            ),
            errSecSuccess
        )"""),
 ("        XCTAssertNotNil(SecKeyCreateRandomKey(squatterAttrs as CFDictionary, nil))",
  "        XCTAssertNotNil(SecKeyCreateRandomKey(\n            try mismatchStore.scopedAdd(squatterAttrs) as CFDictionary, nil))"),
 ("""        XCTAssertEqual(
            SecItemCopyMatching(readQuery as CFDictionary, &readResult), errSecSuccess
        )""",
  """        XCTAssertEqual(
            SecItemCopyMatching(try mismatchStore.scopedQuery(readQuery) as CFDictionary,
                                &readResult),
            errSecSuccess
        )"""),
 ("""        XCTAssertEqual(
            SecItemUpdate(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: mismatchStore.service,
                    kSecAttrAccount as String: mismatchStore.account
                ] as CFDictionary,
                [kSecValueData as String: rewritten] as CFDictionary
            ),
            errSecSuccess
        )""",
  """        XCTAssertEqual(
            SecItemUpdate(
                try mismatchStore.scopedQuery([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: mismatchStore.service,
                    kSecAttrAccount as String: mismatchStore.account
                ]) as CFDictionary,
                [kSecValueData as String: rewritten] as CFDictionary
            ),
            errSecSuccess
        )"""),
 ("""        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: squatterTag
        ] as CFDictionary)""",
  """        if let scopedSquatter = try? mismatchStore.scopedQuery([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: squatterTag
        ]) { SecItemDelete(scopedSquatter as CFDictionary) }"""),
 ("""        XCTAssertEqual(
            SecItemUpdate(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: store.service,
                    kSecAttrAccount as String: store.account
                ] as CFDictionary,
                [kSecValueData as String: Data("corrupted".utf8)] as CFDictionary
            ),
            errSecSuccess
        )""",
  """        XCTAssertEqual(
            SecItemUpdate(
                try store.scopedQuery([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: store.service,
                    kSecAttrAccount as String: store.account
                ]) as CFDictionary,
                [kSecValueData as String: Data("corrupted".utf8)] as CFDictionary
            ),
            errSecSuccess
        )"""),
])
