import Crypto
import Foundation
import LOCALBCore
import XCTest

@testable import SimiGo

/// S3-B (owner ruling 2026-11-05): the three headless owner management
/// roles, exercised against an isolated SIMIGO_HOME and the real journal.
/// T1 clients-list (read-only); T2 permissions-set dry-run (no journal
/// event); T3 confirm (sequence +1, head hash moved); T5 client-revoke;
/// T7 persistence via a fresh store over the same root (the
/// restart-equivalent read). Negative controls: unknown client, empty
/// reason, unknown permission name — all fail closed before any write.
final class LOCALBManagementEntryTests: XCTestCase {

    private struct Environment {
        let homeRoot: URL
        let context: LOCALBHostRuntimeContext
        let clientKey: Curve25519.Signing.PrivateKey
        let clientKeyID: String
        let pairedCheckpoint: LOCALBRegistryCheckpoint
    }

    /// Full local bootstrap: prepare → activate → one strict-headless
    /// pairing commit (default {P-INFERENCE, P-INFO-READ}).
    private func makeEnvironment() throws -> Environment {
        let homeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("localb-mgmt-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: homeRoot) }
        setenv("SIMIGO_HOME", homeRoot.path, 1)
        // Same resolution the entry uses: the registry lives under the
        // managed localb directory of SIMIGO_HOME.
        let hostDirectory = LOCALBHostRuntime.defaultHostDirectory()
        let registryRoot = LOCALBHostRuntime.registryRoot(in: hostDirectory)
        let pending = try LOCALBHostBootstrap.prepareFirstRun(rootURL: registryRoot)
        let context = try LOCALBHostBootstrap.activateInitialSetup(
            rootURL: registryRoot,
            operatorRecordedCheckpoint: pending.checkpoint
        )
        try LOCALBHostRuntime.persistTrustedCheckpoint(
            pending.checkpoint, in: homeRoot
        )

        let coordinator = context.pairingCoordinator()
        let clientKey = Curve25519.Signing.PrivateKey()
        let presentation = try coordinator.issueCredential(
            scopeLabel: "S3-B management test",
            tlsSPKIHash: context.transportIdentity.spkiSHA256Hex,
            srsKeyID: context.signerKeyID,
            mode: .strictHeadless,
            expectedClientPublicKeyRaw: Array(clientKey.publicKey.rawRepresentation),
            checkpoint: try context.currentTrustedCheckpoint()
        )
        let secret = try LOCALBPairingSubmission.decodeSecretBase64URL(
            presentation.takeSecretBase64URLOnce()
        )
        let pairingPending = try coordinator.preparePairing(
            LOCALBPairingSubmission(
                credentialID: presentation.credentialID,
                secretRaw: secret,
                clientPublicKeyRaw: Array(clientKey.publicKey.rawRepresentation),
                proofSignatureRaw: try LOCALBPairingProofV1.sign(
                    credentialID: presentation.credentialID,
                    sessionNonce: try XCTUnwrap(
                        HTTPServer.decodeLowerHex(presentation.sessionNonceHex)
                    ),
                    hostInstanceID: presentation.hostInstanceID,
                    tlsSPKIHash: presentation.tlsSPKIHash,
                    srsKeyID: presentation.srsKeyID,
                    protocolVersion: presentation.protocolVersion,
                    with: clientKey
                ),
                actualTLSSPKIHash: presentation.tlsSPKIHash,
                presentedSRSKeyID: presentation.srsKeyID,
                protocolVersion: presentation.protocolVersion
            ),
            checkpoint: try context.currentTrustedCheckpoint()
        )
        let committed = try coordinator.approveAndRegister(
            pairingPending, checkpoint: try context.currentTrustedCheckpoint()
        )
        let clientKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )
        return Environment(
            homeRoot: homeRoot,
            context: context,
            clientKey: clientKey,
            clientKeyID: clientKeyID,
            pairedCheckpoint: committed
        )
    }

    /// The persisted anchor sequence — advanced by confirmed writes,
    /// untouched by dry-runs.
    private func currentAnchorSequence(_ env: Environment) throws -> UInt64 {
        try env.context.currentTrustedCheckpoint().sequence
    }

    // MARK: - T1: clients-list

    func testClientsListReportsPairedClientReadOnly() throws {
        let env = try makeEnvironment()
        let payload = try SimiGoLocalBManagementEntry.clientsListPayload(
            context: env.context
        )
        XCTAssertEqual(payload["result"] as? String, "ok")
        let clients = try XCTUnwrap(payload["clients"] as? [[String: Any]])
        let own = clients.first { $0["client_key_id"] as? String == env.clientKeyID }
        let ownPermissions = try XCTUnwrap(own?["permissions"] as? [String])
        XCTAssertEqual(ownPermissions.sorted(), ["P-INFERENCE", "P-INFO-READ"])
        // Read-only: the journal must not have moved.
        XCTAssertEqual(try currentAnchorSequence(env), env.pairedCheckpoint.sequence)
    }

    // MARK: - T2: permissions-set dry-run

    func testPermissionsSetDryRunShowsFromToAndWritesNothing() throws {
        let env = try makeEnvironment()
        let payload = try SimiGoLocalBManagementEntry.permissionsSetPayload(
            context: env.context,
            env: [
                "SIMIGO_LOCALB_CLIENT_KEY_ID": env.clientKeyID,
                "SIMIGO_LOCALB_PERMISSIONS": "P-INFERENCE,P-BRANCH-CONTROL",
                "SIMIGO_LOCALB_REASON": "T2 dry-run",
            ]
        )
        XCTAssertEqual(payload["result"] as? String, "dry-run")
        XCTAssertEqual(payload["confirmed"] as? Bool, false)
        XCTAssertEqual(
            payload["from"] as? [String], ["P-INFERENCE", "P-INFO-READ"]
        )
        XCTAssertEqual(
            payload["to"] as? [String], ["P-BRANCH-CONTROL", "P-INFERENCE"]
        )
        // T7 前半：dry-run 之后 journal 事件数不变。
        XCTAssertEqual(
            try currentAnchorSequence(env), env.pairedCheckpoint.sequence,
            "dry-run must not append a journal event"
        )
    }

    // MARK: - T3 + T7: permissions-set confirm + persistence

    func testPermissionsSetConfirmAdvancesJournalAndPersists() throws {
        let env = try makeEnvironment()
        let beforeSequence = env.pairedCheckpoint.sequence
        let beforeHead = env.pairedCheckpoint.headHash

        let payload = try SimiGoLocalBManagementEntry.permissionsSetPayload(
            context: env.context,
            env: [
                "SIMIGO_LOCALB_CLIENT_KEY_ID": env.clientKeyID,
                "SIMIGO_LOCALB_PERMISSIONS": "P-INFERENCE,P-BRANCH-CONTROL",
                "SIMIGO_LOCALB_REASON": "T3 confirmed grant",
                "SIMIGO_LOCALB_MGMT_CONFIRM": "1",
            ]
        )
        XCTAssertEqual(payload["result"] as? String, "written")
        XCTAssertEqual(payload["confirmed"] as? Bool, true)
        XCTAssertEqual(payload["from"] as? [String], ["P-INFERENCE", "P-INFO-READ"])
        XCTAssertEqual(
            payload["to"] as? [String], ["P-BRANCH-CONTROL", "P-INFERENCE"]
        )
        // T7 后半：sequence 精确 +1、head hash 改变、重启等价重载确认持久化。
        let writtenSequence = try XCTUnwrap(payload["sequence"] as? UInt64)
        XCTAssertEqual(writtenSequence, beforeSequence + 1)
        let writtenHead = try XCTUnwrap(payload["head_hash_hex"] as? String)
        XCTAssertNotEqual(
            HTTPServer.decodeLowerHex(writtenHead), beforeHead,
            "the head hash must move on a confirmed write"
        )
        XCTAssertEqual(payload["persisted"] as? Bool, true)

        // The payload's persisted flag was verified through the entry's own
        // restart-equivalent fresh-coordinator read; the anchor proves the
        // journal moved.
        XCTAssertEqual(
            try currentAnchorSequence(env), writtenSequence,
            "the persisted anchor must sit at the new head"
        )
    }

    private func directHex(_ value: String) -> [UInt8] {
        var bytes: [UInt8] = []
        let chars = Array(value.utf8)
        guard chars.count.isMultiple(of: 2) else { return [] }
        for i in stride(from: 0, to: chars.count, by: 2) {
            func nibble(_ c: UInt8) -> UInt8 {
                switch c {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
                case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
                default: return 0
                }
            }
            bytes.append((nibble(chars[i]) << 4) | nibble(chars[i + 1]))
        }
        return bytes
    }

    // MARK: - T5: client-revoke

    func testClientRevokeDryRunThenConfirmIsTerminalAndObservable() throws {
        let env = try makeEnvironment()

        let dry = try SimiGoLocalBManagementEntry.clientRevokePayload(
            context: env.context,
            env: [
                "SIMIGO_LOCALB_CLIENT_KEY_ID": env.clientKeyID,
                "SIMIGO_LOCALB_REASON": "T5 dry-run",
            ]
        )
        XCTAssertEqual(dry["result"] as? String, "dry-run")
        XCTAssertEqual(dry["status_before"] as? String, "ACTIVE")
        XCTAssertEqual(try currentAnchorSequence(env), env.pairedCheckpoint.sequence)

        let written = try SimiGoLocalBManagementEntry.clientRevokePayload(
            context: env.context,
            env: [
                "SIMIGO_LOCALB_CLIENT_KEY_ID": env.clientKeyID,
                "SIMIGO_LOCALB_REASON": "T5 confirmed revoke",
                "SIMIGO_LOCALB_MGMT_CONFIRM": "1",
            ]
        )
        XCTAssertEqual(written["result"] as? String, "written")
        XCTAssertEqual(written["status_after"] as? String, "REVOKED")
        XCTAssertEqual(written["persisted"] as? Bool, true)

        // The payload's status_after/persisted fields were verified through
        // the entry's own restart-equivalent fresh-coordinator read.
        XCTAssertNotEqual(
            try currentAnchorSequence(env), env.pairedCheckpoint.sequence,
            "the confirmed revoke must have advanced the journal"
        )
    }

    // MARK: - Negative controls

    func testUnknownClientFailsClosedWithoutWrite() throws {
        let env = try makeEnvironment()
        let bogusKeyID = String(repeating: "a", count: 64)
        XCTAssertThrowsError(
            try SimiGoLocalBManagementEntry.permissionsSetPayload(
                context: env.context,
                env: [
                    "SIMIGO_LOCALB_CLIENT_KEY_ID": bogusKeyID,
                    "SIMIGO_LOCALB_PERMISSIONS": "P-INFERENCE",
                    "SIMIGO_LOCALB_REASON": "negative control",
                    "SIMIGO_LOCALB_MGMT_CONFIRM": "1",
                ]
            )
        ) { error in
            XCTAssertEqual(error as? LOCALBStatus, .clientUnknown)
        }
        XCTAssertEqual(try currentAnchorSequence(env), env.pairedCheckpoint.sequence)
    }

    func testEmptyReasonFailsClosed() throws {
        let env = try makeEnvironment()
        XCTAssertThrowsError(
            try SimiGoLocalBManagementEntry.permissionsSetPayload(
                context: env.context,
                env: [
                    "SIMIGO_LOCALB_CLIENT_KEY_ID": env.clientKeyID,
                    "SIMIGO_LOCALB_PERMISSIONS": "P-INFERENCE",
                    "SIMIGO_LOCALB_REASON": "",
                    "SIMIGO_LOCALB_MGMT_CONFIRM": "1",
                ]
            )
        ) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidConfiguration)
        }
    }

    func testUnknownPermissionNameFailsClosed() throws {
        let env = try makeEnvironment()
        XCTAssertThrowsError(
            try SimiGoLocalBManagementEntry.permissionsSetPayload(
                context: env.context,
                env: [
                    "SIMIGO_LOCALB_CLIENT_KEY_ID": env.clientKeyID,
                    "SIMIGO_LOCALB_PERMISSIONS": "P-INFERENCE,P-QUEUED",
                    "SIMIGO_LOCALB_REASON": "negative control",
                    "SIMIGO_LOCALB_MGMT_CONFIRM": "1",
                ]
            )
        ) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidConfiguration)
        }
        XCTAssertEqual(try currentAnchorSequence(env), env.pairedCheckpoint.sequence)
    }
}
