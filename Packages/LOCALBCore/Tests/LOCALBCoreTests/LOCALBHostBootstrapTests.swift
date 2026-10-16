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

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localb-bootstrap-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testFirstRunIsPendingUntilExternalCheckpointThenSignsOperationally() throws {
        let root = makeRoot()
        let keychain = makeKeychainStore()
        let pending = try LOCALBHostBootstrap.prepareFirstRun(rootURL: root, keychainStore: keychain)
        XCTAssertEqual(pending.checkpoint.sequence, 2)
        XCTAssertEqual(pending.lineageID, pending.checkpoint.lineageID)
        XCTAssertTrue(pending.offlineCheckpointRecord.contains(pending.checkpoint.headHashHex))

        let runtime = try LOCALBHostBootstrap.activateInitialSetup(
            rootURL: root,
            operatorRecordedCheckpoint: pending.checkpoint,
            keychainStore: keychain
        )
        XCTAssertEqual(runtime.lineageID, pending.lineageID)
        XCTAssertEqual(runtime.signerKeyID, pending.signerKeyID)

        let frame = try runtime.signRecord(makeRecord())
        let store = LOCALBRegistryStore(rootURL: root)
        let snapshot = try store.loadVerified(checkpoint: pending.checkpoint)
        let result = LOCALBRecordReader.read(data: frame, registry: snapshot)
        XCTAssertEqual(try result.get().issuerKeyID, pending.signerKeyID)
    }

    func testInitialActivationRejectsCheckpointThatIsNotCurrentHead() throws {
        let root = makeRoot()
        let keychain = makeKeychainStore()
        let pending = try LOCALBHostBootstrap.prepareFirstRun(rootURL: root, keychainStore: keychain)
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
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: root, keychainStore: setupKeychain
        )
        let absentKeychain = makeKeychainStore()

        XCTAssertThrowsError(try LOCALBHostBootstrap.openOperational(
            rootURL: root,
            trustedCheckpoint: pending.checkpoint,
            keychainStore: absentKeychain
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .keychainItemMissing)
        }
        XCTAssertThrowsError(try absentKeychain.loadExisting()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .keychainItemMissing)
        }
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
