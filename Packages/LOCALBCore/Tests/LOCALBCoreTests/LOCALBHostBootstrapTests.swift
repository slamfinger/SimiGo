import Crypto
import Foundation
import XCTest

@testable import LOCALBCore

final class LOCALBHostBootstrapTests: XCTestCase {
    private func makeKeychainStore() -> LOCALBKeychainSignerStore {
        LOCALBKeychainSignerStore(
            service: "com.simigo.tests.localb.\(UUID().uuidString)",
            account: "signer"
        )
    }

    private func makeRecord() -> PersistentSRSRecord {
        func binding(_ name: String) -> SRSBindingValue {
            SRSBindingValue(identity: name, version: "1.0.0",
                            contentDigestHex64: String(repeating: "a", count: 64))
        }
        var record = PersistentSRSRecord()
        record.logicalKeyIdentity = "bootstrap-record"
        record.logicalKeyVersion = "1.0.0"
        record.settledBinding = binding("settled")
        record.settlementID = "settle-bootstrap-001"
        record.settlementStatus = .declaredSettled
        record.sourceRelationIdentity = "source"
        record.resultIdentity = "result"
        record.requiresCanonicalIdentityRule = false
        record.sourceBinding = binding("source-binding")
        record.sourceInvalidationStatus = .none
        record.sourceStatus = .current
        record.dependencyBoundary = binding("dependency-boundary")
        record.dependencies = []
        record.resultBinding = binding("result-binding")
        record.resultResolution = .resolvedWithoutRecompute
        record.resultStatus = .current
        record.provenanceBindings = []
        record.provenanceLifecycle = .declaredSettled
        record.lifecycleBindings = []
        record.lifecycleStatus = .declaredSettled
        record.policies = []
        record.producerAuthorizationReference = "BOOTSTRAP-TEST-AUDIT"
        return record
    }

    private func makeTransportStore() -> LOCALBTransportIdentityStore {
        // Throwaway file keychain: the default path is the REAL managed store
        // and must never receive test identities.
        let store = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-bootstrap.\(UUID().uuidString)",
            account: "tls",
            keychainPath: NSTemporaryDirectory()
                + "/localb-tests-\(UUID().uuidString).keychain-db"
        )
        addTeardownBlock { store.deleteAll() }
        return store
    }

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localb-bootstrap-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testFirstRunIsPendingUntilExternalCheckpointThenSignsOperationally() throws {
        let root = makeRoot()
        let keychain = makeKeychainStore()
        let transport = makeTransportStore()
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: root, keychainStore: keychain, transportIdentityStore: transport
        )
        XCTAssertEqual(pending.checkpoint.sequence, 2)
        XCTAssertEqual(pending.lineageID, pending.checkpoint.lineageID)
        XCTAssertTrue(pending.offlineCheckpointRecord.contains(pending.checkpoint.headHashHex))
        XCTAssertEqual(pending.transportSPKIHashHex.count, 64)

        let runtime = try LOCALBHostBootstrap.activateInitialSetup(
            rootURL: root,
            operatorRecordedCheckpoint: pending.checkpoint,
            keychainStore: keychain,
            transportIdentityStore: transport
        )
        XCTAssertEqual(runtime.lineageID, pending.lineageID)
        XCTAssertEqual(runtime.signerKeyID, pending.signerKeyID)
        XCTAssertEqual(runtime.transportIdentity.spkiSHA256Hex, pending.transportSPKIHashHex)

        let frame = try runtime.signRecord(makeRecord())
        let store = LOCALBRegistryStore(rootURL: root)
        let snapshot = try store.loadVerified(checkpoint: pending.checkpoint)
        let result = LOCALBRecordReader.read(data: frame, registry: snapshot)
        XCTAssertEqual(try result.get().issuerKeyID, pending.signerKeyID)
    }

    func testInitialActivationRejectsCheckpointThatIsNotCurrentHead() throws {
        let root = makeRoot()
        let keychain = makeKeychainStore()
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: root, keychainStore: keychain, transportIdentityStore: makeTransportStore()
        )
        let store = LOCALBRegistryStore(rootURL: root)
        let wrong = try LOCALBRegistryCheckpoint(
            lineageID: pending.lineageID,
            sequence: 1,
            headHash: [UInt8](repeating: 0, count: 32)
        )
        XCTAssertThrowsError(try LOCALBHostBootstrap.activateInitialSetup(
            rootURL: root, operatorRecordedCheckpoint: wrong, keychainStore: keychain
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryCheckpointMismatch)
        }
        XCTAssertNotNil(try store.loadVerified(checkpoint: pending.checkpoint))
    }

    func testNormalStartupNeverCreatesMissingKeychainIdentity() throws {
        let root = makeRoot()
        let setupKeychain = makeKeychainStore()
        let transport = makeTransportStore()
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: root, keychainStore: setupKeychain, transportIdentityStore: transport
        )
        let absentKeychain = makeKeychainStore()

        XCTAssertThrowsError(try LOCALBHostBootstrap.openOperational(
            rootURL: root,
            trustedCheckpoint: pending.checkpoint,
            keychainStore: absentKeychain,
            transportIdentityStore: transport
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .keychainItemMissing)
        }
        XCTAssertThrowsError(try absentKeychain.loadExisting()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .keychainItemMissing)
        }
    }

    func testNormalStartupFailsClosedWhenTransportIdentityMissing() throws {
        let root = makeRoot()
        let keychain = makeKeychainStore()
        let transport = makeTransportStore()
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: root, keychainStore: keychain, transportIdentityStore: transport
        )
        let absentTransport = makeTransportStore()

        XCTAssertThrowsError(try LOCALBHostBootstrap.openOperational(
            rootURL: root,
            trustedCheckpoint: pending.checkpoint,
            keychainStore: keychain,
            transportIdentityStore: absentTransport
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMissing)
        }
        // Fail-closed: the failed attempt created nothing.
        XCTAssertThrowsError(try absentTransport.loadExisting()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMissing)
        }
        // The real transport identity is untouched.
        XCTAssertEqual(try transport.loadExisting().spkiSHA256Hex,
                       pending.transportSPKIHashHex)
    }

    func testFirstRunTLSFailureLeavesRegistryRootRetryable() throws {
        let root = makeRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Pre-seed a CORRUPT transport index: loadOrCreate must fail
        // explicitly (evidence preserved, no destructive cleanup) BEFORE the
        // registry advances.
        let corruptStore = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-bootstrap.\(UUID().uuidString)",
            account: "tls"
        )
        addTeardownBlock { corruptStore.deleteAll() }
        let corruptIndex: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: corruptStore.service,
            kSecAttrAccount as String: corruptStore.account,
            kSecValueData as String: Data("not-a-valid-envelope".utf8)
        ]
        XCTAssertEqual(SecItemAdd(try corruptStore.scopedAdd(corruptIndex) as CFDictionary, nil),
                       errSecSuccess)

        XCTAssertThrowsError(try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: root,
            keychainStore: makeKeychainStore(),
            transportIdentityStore: corruptStore
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityCorrupt)
        }

        // The registry root must still be EMPTY: TLS failure must not leave a
        // state that blocks a retry of first-run.
        let children = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )
        XCTAssertTrue(children.isEmpty, "root must be empty after TLS failure")

        // A retry with a healthy transport store succeeds on the same root.
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: root,
            keychainStore: makeKeychainStore(),
            transportIdentityStore: makeTransportStore()
        )
        XCTAssertEqual(pending.transportSPKIHashHex.count, 64)
    }

    func testFirstRunRefusesNonEmptyRegistryRootInsteadOfSilentlyResettingTrust() throws {
        let root = makeRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0x42]).write(to: root.appendingPathComponent("unknown-state.bin"))
        XCTAssertThrowsError(try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: root, keychainStore: makeKeychainStore()
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryAlreadyInitialized)
        }
    }
}
