import Crypto
import Foundation
import XCTest

@testable import LOCALBCore

final class LOCALBRegistryStoreTests: XCTestCase {
    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localb-registry-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func keyEntryKeyID(_ key: Curve25519.Signing.PrivateKey) throws -> String {
        try LOCALBSigningInputV1.keyID(publicKeyRaw: Array(key.publicKey.rawRepresentation))
    }

    func testFirstRunProducesOfflineCheckpointAndMissingCheckpointFailsClosed() throws {
        let store = LOCALBRegistryStore(rootURL: makeRoot())
        let checkpoint = try store.initializeNewLineage()
        XCTAssertEqual(checkpoint.sequence, 1)
        XCTAssertEqual(checkpoint.headHash.count, 32)

        let roundTrip = try LOCALBRegistryCheckpoint.parseOfflineRecord(checkpoint.offlineRecord)
        XCTAssertEqual(roundTrip, checkpoint)

        XCTAssertThrowsError(try store.loadVerified(checkpoint: nil)) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryCheckpointUnavailable)
        }
        let snapshot = try store.loadVerified(checkpoint: checkpoint)
        XCTAssertEqual(snapshot.currentLineageID, checkpoint.lineageID)
    }

    func testVerifiedCheckpointMayBeExtendedByLaterEvents() throws {
        let store = LOCALBRegistryStore(rootURL: makeRoot())
        let firstHead = try store.initializeNewLineage()
        let signingKey = Curve25519.Signing.PrivateKey()
        let publicKey = Array(signingKey.publicKey.rawRepresentation)

        let secondHead = try store.appendKeyRegistration(
            publicKeyRaw: publicKey, generation: 1, checkpoint: firstHead
        )
        XCTAssertEqual(secondHead.sequence, firstHead.sequence + 1)

        // A trusted older checkpoint is valid if it is an exact prefix of the
        // verified local chain; current head equality is not required.
        let snapshotAtOlderCheckpoint = try store.loadVerified(checkpoint: firstHead)
        let keyID = try keyEntryKeyID(signingKey)
        XCTAssertEqual(snapshotAtOlderCheckpoint.entry(for: keyID)?.status, .active)
        XCTAssertEqual(snapshotAtOlderCheckpoint.entry(for: keyID)?.generation, 1)

        let snapshotAtCurrentHead = try store.loadVerified(checkpoint: secondHead)
        XCTAssertEqual(snapshotAtCurrentHead.entry(for: keyID)?.publicKeyRaw, publicKey)
    }

    func testCheckpointMismatchAndFutureCheckpointFailClosed() throws {
        let store = LOCALBRegistryStore(rootURL: makeRoot())
        let checkpoint = try store.initializeNewLineage()

        let forgedSameSequence = try LOCALBRegistryCheckpoint(
            lineageID: checkpoint.lineageID,
            sequence: checkpoint.sequence,
            headHash: [UInt8](repeating: 0xA5, count: 32)
        )
        XCTAssertThrowsError(try store.loadVerified(checkpoint: forgedSameSequence)) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryCheckpointMismatch)
        }

        let future = try LOCALBRegistryCheckpoint(
            lineageID: checkpoint.lineageID,
            sequence: checkpoint.sequence + 10,
            headHash: checkpoint.headHash
        )
        XCTAssertThrowsError(try store.loadVerified(checkpoint: future)) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryCheckpointMismatch)
        }
    }

    func testActiveKeyMustBeRetiredBeforeNextGenerationIsRegistered() throws {
        let store = LOCALBRegistryStore(rootURL: makeRoot())
        var checkpoint = try store.initializeNewLineage()
        let firstKey = Curve25519.Signing.PrivateKey()
        let firstPublic = Array(firstKey.publicKey.rawRepresentation)

        checkpoint = try store.appendKeyRegistration(
            publicKeyRaw: firstPublic, generation: 1, checkpoint: checkpoint
        )
        let secondKey = Curve25519.Signing.PrivateKey()
        XCTAssertThrowsError(try store.appendKeyRegistration(
            publicKeyRaw: Array(secondKey.publicKey.rawRepresentation),
            generation: 2, checkpoint: checkpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryInvalidTransition)
        }

        checkpoint = try store.appendKeyStatusChange(
            keyID: keyEntryKeyID(firstKey), to: .retired, reason: "routine rotation", checkpoint: checkpoint
        )
        checkpoint = try store.appendKeyRegistration(
            publicKeyRaw: Array(secondKey.publicKey.rawRepresentation),
            generation: 2, checkpoint: checkpoint
        )
        let snapshot = try store.loadVerified(checkpoint: checkpoint)
        XCTAssertEqual(snapshot.entry(for: try keyEntryKeyID(firstKey))?.status, .retired)
        XCTAssertEqual(snapshot.entry(for: try keyEntryKeyID(secondKey))?.status, .active)
        XCTAssertEqual(snapshot.entry(for: try keyEntryKeyID(secondKey))?.generation, 2)
    }

    func testRevokedStatusIsTerminalAndJournalRemainsAppendOnly() throws {
        let store = LOCALBRegistryStore(rootURL: makeRoot())
        var checkpoint = try store.initializeNewLineage()
        let key = Curve25519.Signing.PrivateKey()
        checkpoint = try store.appendKeyRegistration(
            publicKeyRaw: Array(key.publicKey.rawRepresentation),
            generation: 1, checkpoint: checkpoint
        )
        checkpoint = try store.appendKeyStatusChange(
            keyID: keyEntryKeyID(key), to: .revoked, reason: "suspected compromise", checkpoint: checkpoint
        )
        XCTAssertThrowsError(try store.appendKeyStatusChange(
            keyID: keyEntryKeyID(key), to: .retired, reason: "post-revoke forbidden", checkpoint: checkpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryInvalidTransition)
        }
        let snapshot = try store.loadVerified(checkpoint: checkpoint)
        XCTAssertEqual(snapshot.entry(for: try keyEntryKeyID(key))?.status, .revoked)
    }

    func testCorruptTailIsNotSilentlyRepaired() throws {
        let root = makeRoot()
        let store = LOCALBRegistryStore(rootURL: root)
        let checkpoint = try store.initializeNewLineage()
        let journal = root.appendingPathComponent(".localb-registry.events")
        let handle = try FileHandle(forWritingTo: journal)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xAA]))
        try handle.synchronize()
        try handle.close()

        XCTAssertThrowsError(try store.loadVerified(checkpoint: checkpoint)) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryCorrupt)
        }
        let dataAfterFailure = try Data(contentsOf: journal)
        XCTAssertEqual(dataAfterFailure.last, 0xAA)
    }
}
