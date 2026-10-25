import Crypto
import Foundation
import Security
import X509
import XCTest

@testable import LOCALBCore

final class LOCALBTransportIdentityStoreTests: XCTestCase {
    private func makeStore() -> LOCALBTransportIdentityStore {
        LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-transport.\(UUID().uuidString)",
            account: "tls"
        )
    }

    func testFirstCreationPersistsAndReloadsIdentically() throws {
        let store = makeStore()
        defer { store.deleteAll() }

        let first = try store.loadOrCreate()
        XCTAssertGreaterThan(first.certificateDER.count, 100)
        XCTAssertEqual(first.spkiSHA256Hex.count, 64)

        // A new store instance (simulating process restart) must load the
        // SAME identity bytes — no silent regeneration.
        let reloaded = try LOCALBTransportIdentityStore(
            service: store.service, account: store.account
        ).loadExisting()
        XCTAssertEqual(reloaded.certificateDER, first.certificateDER)
        XCTAssertEqual(reloaded.spkiSHA256Hex, first.spkiSHA256Hex)
    }

    func testLoadExistingMissingFailsClosedWithoutCreation() throws {
        let store = makeStore()
        defer { store.deleteAll() }

        XCTAssertThrowsError(try store.loadExisting()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMissing)
        }
        // Fail-closed means fail-closed: nothing was created by the attempt.
        XCTAssertThrowsError(try store.loadExisting()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMissing)
        }
    }

    func testSPKIEqualsIndependentP256SubjectPublicKeyInfoEncoding() throws {
        // Deterministic P-256 key: any valid scalar works; 0x5a…5a < n.
        let scalar = [UInt8](repeating: 0x5a, count: 32)
        let key = try P256.Signing.PrivateKey(rawRepresentation: Data(scalar))
        let name = try X509.DistinguishedName {
            X509.CommonName("LOCALB SPKI vector")
        }
        let certificate = try X509.Certificate(
            version: .v3,
            serialNumber: X509.Certificate.SerialNumber(bytes: [1, 2, 3, 4]),
            publicKey: X509.Certificate.PublicKey(key.publicKey),
            notValidBefore: Date(timeIntervalSince1970: 0),
            notValidAfter: Date(timeIntervalSince1970: 4_102_444_800),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: X509.Certificate.Extensions(),
            issuerPrivateKey: X509.Certificate.PrivateKey(key)
        )
        let der = try LOCALBTransportIdentityStore.certificateDER(certificate)

        // Independent construction of the RFC 5280 SubjectPublicKeyInfo DER
        // for P-256: the standard 26-byte header + the 65-byte X9.63 point.
        var expectedSPKI: [UInt8] = [
            0x30, 0x59,             // SEQUENCE (89 bytes)
            0x30, 0x13,             //   SEQUENCE AlgorithmIdentifier (19)
            0x06, 0x07,             //     OID 1.2.840.10045.2.1 (ecPublicKey)
            0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
            0x06, 0x08,             //     OID 1.2.840.10045.3.1.7 (prime256v1)
            0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00        //   BIT STRING (66 = 0x00 unused + 65)
        ]
        expectedSPKI.append(contentsOf: Array(key.publicKey.x963Representation))
        XCTAssertEqual(expectedSPKI.count, 91)

        let expectedHex = LOCALBBinary.hexLower(Array(SHA256.hash(data: Data(expectedSPKI))))
        XCTAssertEqual(try LOCALBTransportIdentityStore.spkiSHA256Hex(ofCertificateDER: der),
                       expectedHex)
    }

    func testRotationChangesFingerprintAndNeverServesOldOne() throws {
        let store = makeStore()
        defer { store.deleteAll() }

        let first = try store.loadOrCreate()
        let rotated = try store.rotate()

        XCTAssertNotEqual(rotated.new.spkiSHA256Hex, first.spkiSHA256Hex)
        XCTAssertEqual(rotated.previousSPKIHex, first.spkiSHA256Hex)

        let reloaded = try store.loadExisting()
        XCTAssertEqual(reloaded.spkiSHA256Hex, rotated.new.spkiSHA256Hex)
        XCTAssertNotEqual(reloaded.spkiSHA256Hex, first.spkiSHA256Hex)
    }

    func testConcurrentFirstCreationAllCallersSucceedWithOneStableIdentity() throws {
        let store = makeStore()
        defer { store.deleteAll() }

        // With in-process mutation serialization, every one of the 4
        // concurrent callers must FINISH, must SUCCEED, and must observe the
        // SAME stable SPKI (first creator wins; the rest read the winner's
        // committed identity).
        let callerCount = 4
        let group = DispatchGroup()
        let lock = NSLock()
        var outcomes: [Result<String, Error>] = []
        for index in 0..<callerCount {
            group.enter()
            DispatchQueue(label: "localb-concurrent-create-\(index)").async {
                defer { group.leave() }
                let outcome = Result {
                    try store.loadOrCreate().spkiSHA256Hex
                }
                lock.lock()
                outcomes.append(outcome)
                lock.unlock()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success,
                       "all concurrent creators must finish")

        let spkis = outcomes.compactMap { try? $0.get() }
        XCTAssertEqual(spkis.count, callerCount,
                       "all \(callerCount) creators must succeed; failures: " +
                       "\(outcomes.compactMap { if case .failure(let e) = $0 { return e } ; return nil })")
        XCTAssertEqual(Set(spkis).count, 1,
                       "all handles must share one stable SPKI")

        let reloaded = try store.loadExisting()
        XCTAssertEqual(reloaded.spkiSHA256Hex, spkis[0])
    }

    func testCorruptIndexFailsClosed() throws {
        let store = makeStore()
        defer { store.deleteAll() }
        let first = try store.loadOrCreate()

        // Corrupt the authoritative index in place.
        let corruptQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: store.account
        ]
        let corruptUpdate: [String: Any] = [
            kSecValueData as String: Data("not-a-valid-envelope".utf8)
        ]
        XCTAssertEqual(
            SecItemUpdate(try store.scopedQuery(corruptQuery) as CFDictionary,
                          corruptUpdate as CFDictionary),
            errSecSuccess
        )

        // A corrupt index is a typed explicit failure for both paths.
        XCTAssertThrowsError(try store.rotate()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityCorrupt)
        }
        XCTAssertThrowsError(try store.loadExisting()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityCorrupt)
        }

        // Evidence preserved: the previously verified private key and
        // certificate items are still in the Keychain (no destructive
        // cleanup ran) — proven via the retained handle's SecIdentity.
        var keyRef: SecKey?
        _ = SecIdentityCopyPrivateKey(first.secIdentity, &keyRef)
        XCTAssertNotNil(keyRef)
        var certRef: SecCertificate?
        _ = SecIdentityCopyCertificate(first.secIdentity, &certRef)
        XCTAssertNotNil(certRef)
    }

    func testRotationFailureBeforeCommitPreservesCurrentIdentity() throws {
        let store = makeStore()
        defer { store.deleteAll() }
        let first = try store.loadOrCreate()

        // Deterministic failure injection: fixed attempt ID, fail AFTER the
        // private key is permanently written, BEFORE certificate creation.
        LocalBTransportTestHooks.nextAttemptID = "00000000-0000-0000-0000-000000000001"
        LocalBTransportTestHooks.failAfterKeyWrite = true
        defer { LocalBTransportTestHooks.reset() }

        XCTAssertThrowsError(try store.rotate()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityCorrupt)
        }

        // (a) The failed attempt left a PERMANENT orphan key under its exact
        // deterministic physical tag.
        let orphanTag = Data(
            "\(store.service)#\(store.account)#key#g2#a00000000-0000-0000-0000-000000000001".utf8
        )
        defer {
            if let scoped = try? store.scopedQuery([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: orphanTag
            ]) { SecItemDelete(scoped as CFDictionary) }
        }
        let orphanQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: orphanTag,
            kSecReturnRef as String: true
        ]
        var orphanRef: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(try store.scopedQuery(orphanQuery) as CFDictionary,
                                           &orphanRef),
                       errSecSuccess,
                       "the orphan key must exist after the injected failure")

        // (b) The OLD identity is still fully loadable: the index commit
        // never happened.
        XCTAssertEqual(try store.loadExisting().spkiSHA256Hex, first.spkiSHA256Hex)

        // (c) Retry with a DIFFERENT attempt ID succeeds — the per-attempt
        // physical ID cannot collide with the orphan. (Under the previous
        // deterministic-tag implementation, this retry reused the same tag
        // and failed.)
        LocalBTransportTestHooks.nextAttemptID = "00000000-0000-0000-0000-000000000002"
        LocalBTransportTestHooks.failAfterKeyWrite = false
        let rotated = try store.rotate()
        XCTAssertNotEqual(rotated.new.spkiSHA256Hex, first.spkiSHA256Hex)
        XCTAssertEqual(rotated.previousSPKIHex, first.spkiSHA256Hex)

        // (d) Restart (a fresh store instance) loads the NEW identity — not
        // the old one and not any transient identity.
        let restarted = try LOCALBTransportIdentityStore(
            service: store.service, account: store.account
        ).loadExisting()
        XCTAssertEqual(restarted.spkiSHA256Hex, rotated.new.spkiSHA256Hex)
    }

    func testDecodeIndexRejectsOutOfRangeGenerationWithoutTrapping() throws {
        let store = makeStore()
        defer { store.deleteAll() }
        _ = try store.loadOrCreate()

        // Overwrite the index with a structurally valid envelope whose
        // generation exceeds UInt32.max: must be a typed corrupt failure,
        // never a runtime trap.
        let outOfRange = """
        {"version":2,"generation":\(Int(UInt32.max) + 1),\
        "certificate_der":"AAAA","key_tag":"AAAA","cert_label":"x"}
        """
        XCTAssertEqual(
            SecItemUpdate(try store.scopedQuery(indexQueryDict(for: store)) as CFDictionary,
                          [kSecValueData as String: Data(outOfRange.utf8)] as CFDictionary),
            errSecSuccess
        )
        XCTAssertThrowsError(try store.loadExisting()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityCorrupt)
        }
    }

    func testRotationAtGenerationCeilingFailsWithTypedExhaustion() throws {
        let store = makeStore()
        defer { store.deleteAll() }
        _ = try store.loadOrCreate()

        // Rewrite ONLY the generation field to the UInt32 ceiling (all other
        // fields stay the real verified values), then rotate: the increment
        // must fail with the typed exhaustion status, never overflow.
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: store.account,
            kSecReturnData as String: true
        ]
        var readResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(try store.scopedQuery(readQuery) as CFDictionary,
                                           &readResult),
                       errSecSuccess)
        let data = try XCTUnwrap(readResult as? Data)
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        envelope["generation"] = Int(UInt32.max)
        let rewritten = try JSONSerialization.data(withJSONObject: envelope)
        XCTAssertEqual(
            SecItemUpdate(try store.scopedQuery(indexQueryDict(for: store)) as CFDictionary,
                          [kSecValueData as String: rewritten] as CFDictionary),
            errSecSuccess
        )

        // Loading a ceiling-generation identity is still legal…
        _ = try store.loadExisting()
        // …but rotating past it is a typed exhaustion failure.
        XCTAssertThrowsError(try store.rotate()) { error in
            XCTAssertEqual(error as? LOCALBStatus,
                           .transportIdentityGenerationExhausted)
        }
    }

    // MARK: - Scoped (isolated) keychain

    /// The isolation roots used to cover every persisted path EXCEPT the
    /// Keychain: a run created transport identities in the real login
    /// Keychain. A scoped store must keep the index, key, certificate and the
    /// synthesized SecIdentity in its own keychain file.
    func testScopedKeychainKeepsIdentityOutOfTheDefaultSearchList() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("localb-scope-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let keychainPath = dir.appendingPathComponent("transport.keychain-db").path
        let store = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-scope.\(UUID().uuidString)",
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

    /// Scoping follows the managed roots: an isolated `SIMIGO_HOME` first, then
    /// the production managed root. The login Keychain is never the default:
    /// its per-signature ACLs refused every re-signed build (2026-10-26
    /// real-domain failure, CSSMERR_CSP_OPERATION_AUTH_DENIED).
    func testDefaultKeychainPathFollowsManagedRoots() {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo/localb/transport-identity.keychain-db").path
        XCTAssertEqual(LOCALBTransportIdentityStore.defaultScopedKeychainPath(env: [:]), home)
        XCTAssertEqual(
            LOCALBTransportIdentityStore.defaultScopedKeychainPath(
                env: ["SIMIGO_HOME": ""]),
            home)
        XCTAssertEqual(
            LOCALBTransportIdentityStore.defaultScopedKeychainPath(
                env: ["SIMIGO_HOME": "/Users/example/iso-root"]),
            "/Users/example/iso-root/localb/transport-identity.keychain-db")
        XCTAssertEqual(
            LOCALBKeychainScope.scopedDefault(
                fileName: "production-signer.keychain-db", env: [:]),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".simigo/localb/production-signer.keychain-db").path)
    }

    private func indexQueryDict(for store: LOCALBTransportIdentityStore) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: store.account
        ]
    }
}
