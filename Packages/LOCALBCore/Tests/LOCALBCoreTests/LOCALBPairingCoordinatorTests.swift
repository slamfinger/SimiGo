import Crypto
import Foundation
import XCTest

@testable import LOCALBCore

final class LOCALBPairingCoordinatorTests: XCTestCase {
    private struct Host {
        let root: URL
        let store: LOCALBRegistryStore
        let coordinator: LOCALBPairingCoordinator
        let signingKey: Curve25519.Signing.PrivateKey
        let srsKeyID: String
        let lineageID: String
        let tlsSPKIHash: String
        let checkpoint: LOCALBRegistryCheckpoint
    }

    private func makeHost() throws -> Host {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localb-pairing-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = LOCALBRegistryStore(rootURL: root)
        var checkpoint = try store.initializeNewLineage()
        let signingKey = Curve25519.Signing.PrivateKey()
        let publicKey = Array(signingKey.publicKey.rawRepresentation)
        checkpoint = try store.appendKeyRegistration(
            publicKeyRaw: publicKey, generation: 1, checkpoint: checkpoint
        )
        let srsKeyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: publicKey)
        let tlsSPKIHash = LOCALBBinary.hexLower(LOCALBBinary.sha256(Array("test-host-tls-spki".utf8)))
        return Host(
            root: root, store: store, coordinator: LOCALBPairingCoordinator(registryStore: store),
            signingKey: signingKey, srsKeyID: srsKeyID,
            lineageID: checkpoint.lineageID, tlsSPKIHash: tlsSPKIHash,
            checkpoint: checkpoint
        )
    }

    private func decodeBase64URL(_ value: String) throws -> [UInt8] {
        try LOCALBPairingSubmission.decodeSecretBase64URL(value)
    }

    private func decodeHex(_ value: String) throws -> [UInt8] {
        let bytes = Array(value.utf8)
        guard bytes.count.isMultiple(of: 2) else { throw LOCALBStatus.invalidConfiguration }
        var result: [UInt8] = []
        for i in stride(from: 0, to: bytes.count, by: 2) {
            func nibble(_ byte: UInt8) throws -> UInt8 {
                if byte >= 0x30 && byte <= 0x39 { return byte - 0x30 }
                if byte >= 0x61 && byte <= 0x66 { return byte - 0x61 + 10 }
                throw LOCALBStatus.invalidConfiguration
            }
            result.append(try (nibble(bytes[i]) << 4) | nibble(bytes[i + 1]))
        }
        return result
    }

    private func issue(_ host: Host, mode: LOCALBPairingConfirmationMode = .interactive,
                       expectedClientKey: Curve25519.Signing.PrivateKey? = nil) throws
        -> (LOCALBPairingCredentialPresentation, [UInt8]) {
        let presentation = try host.coordinator.issueCredential(
            scopeLabel: "Pair test client",
            tlsSPKIHash: host.tlsSPKIHash,
            srsKeyID: host.srsKeyID,
            mode: mode,
            expectedClientPublicKeyRaw: expectedClientKey.map { Array($0.publicKey.rawRepresentation) },
            checkpoint: host.checkpoint
        )
        let secret = try decodeBase64URL(presentation.takeSecretBase64URLOnce())
        XCTAssertThrowsError(try presentation.takeSecretBase64URLOnce())
        return (presentation, secret)
    }

    private func makeSubmission(_ presentation: LOCALBPairingCredentialPresentation,
                                secret: [UInt8],
                                clientKey: Curve25519.Signing.PrivateKey,
                                tlsHash: String? = nil,
                                srsKeyID: String? = nil) throws -> LOCALBPairingSubmission {
        let proof = try LOCALBPairingProofV1.sign(
            credentialID: presentation.credentialID,
            sessionNonce: decodeHex(presentation.sessionNonceHex),
            hostInstanceID: presentation.hostInstanceID,
            tlsSPKIHash: presentation.tlsSPKIHash,
            srsKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion,
            with: clientKey
        )
        return LOCALBPairingSubmission(
            credentialID: presentation.credentialID,
            secretRaw: secret,
            clientPublicKeyRaw: Array(clientKey.publicKey.rawRepresentation),
            proofSignatureRaw: proof,
            actualTLSSPKIHash: tlsHash ?? presentation.tlsSPKIHash,
            presentedSRSKeyID: srsKeyID ?? presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion
        )
    }

    private func makeHTTPRequest(
        method: String = "POST",
        authority: String = "127.0.0.1:8080",
        requestTarget: String = "/v1/inference",
        contentType: String? = "application/json",
        contentEncoding: String = "identity",
        body: String = "{\"prompt\":\"hello\"}"
    ) throws -> LOCALBHTTPRequestV1 {
        try LOCALBHTTPRequestV1(
            method: method,
            authority: authority,
            requestTarget: requestTarget,
            contentType: contentType,
            contentEncoding: contentEncoding,
            bodyRaw: Array(body.utf8)
        )
    }

    func testInteractivePairingIsOneCommitAndRevocationIsImmediate() throws {
        let host = try makeHost()
        let (presentation, secret) = try issue(host)
        let clientKey = Curve25519.Signing.PrivateKey()
        let submission = try makeSubmission(presentation, secret: secret, clientKey: clientKey)
        let pending = try host.coordinator.preparePairing(submission, checkpoint: presentation.registryCheckpoint)

        XCTAssertTrue(pending.requiresOperatorConfirmation)
        XCTAssertEqual(pending.scopeLabel, "Pair test client")
        XCTAssertEqual(pending.clientPublicKeyFingerprint.count, 64)
        XCTAssertThrowsError(try host.coordinator.approveAndRegister(
            pending, checkpoint: presentation.registryCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .pairingOperatorApprovalRequired)
        }

        let committedCheckpoint = try host.coordinator.approveAndRegister(
            pending,
            operatorApproved: true,
            operatorAuthorizationReference: "LOCAL-UI-PAIR-CONFIRM-001",
            checkpoint: presentation.registryCheckpoint
        )
        XCTAssertEqual(committedCheckpoint.sequence, 4,
                       "Issuance is one event and consume+register must be exactly one commit event.")
        let state = try host.store.loadPairingState(checkpoint: committedCheckpoint)
        let clientKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )
        XCTAssertEqual(state.credentials[presentation.credentialID]?.status, .consumed)
        XCTAssertEqual(state.clients[clientKeyID]?.status, .active)
        XCTAssertEqual(state.clients[clientKeyID]?.permissions, Set([.inference, .informationRead]))
        XCTAssertFalse(state.clients[clientKeyID]?.permissions.contains(.srsWrite) ?? true)

        let journal = try Data(contentsOf: host.root.appendingPathComponent(".localb-registry.events"))
        XCTAssertNil(journal.range(of: Data(secret)), "The raw bearer secret must never be persisted.")

        let challenge = try host.coordinator.issueRequestChallenge(
            clientKeyID: clientKeyID, permission: .inference,
            checkpoint: committedCheckpoint
        )
        let request = try makeHTTPRequest()
        let requestProof = try LOCALBClientRequestProofV2.sign(
            clientKeyID: clientKeyID, permission: .inference,
            request: request,
            challenge: challenge, with: clientKey
        )
        let authorized = try host.coordinator.authorizeProtectedRequest(
            clientKeyID: clientKeyID, permission: .inference,
            request: request,
            challenge: challenge, proofSignatureRaw: requestProof,
            checkpoint: committedCheckpoint
        )
        XCTAssertEqual(authorized.client.clientKeyID, clientKeyID)
        XCTAssertEqual(authorized.request, request)

        // A fresh challenge plus a proof over the original request must not
        // authorize any altered method, authority, target, media type, or body.
        let alteredMethod = try makeHTTPRequest(method: "GET")
        let alteredAuthority = try makeHTTPRequest(authority: "other.local:8080")
        let alteredTarget = try makeHTTPRequest(requestTarget: "/v1/other")
        let alteredQuery = try makeHTTPRequest(
            requestTarget: "/v1/inference?model=altered"
        )
        let alteredContentType = try makeHTTPRequest(contentType: "application/cbor")
        let alteredBody = try makeHTTPRequest(body: "{\"prompt\":\"tampered\"}")
        for alteredRequest in [
            alteredMethod, alteredAuthority, alteredTarget, alteredQuery,
            alteredContentType, alteredBody
        ] {
            let freshChallenge = try host.coordinator.issueRequestChallenge(
                clientKeyID: clientKeyID, permission: .inference,
                checkpoint: committedCheckpoint
            )
            let originalProof = try LOCALBClientRequestProofV2.sign(
                clientKeyID: clientKeyID, permission: .inference,
                request: request, challenge: freshChallenge, with: clientKey
            )
            XCTAssertThrowsError(try host.coordinator.authorizeProtectedRequest(
                clientKeyID: clientKeyID, permission: .inference,
                request: alteredRequest, challenge: freshChallenge,
                proofSignatureRaw: originalProof, checkpoint: committedCheckpoint
            )) { error in
                XCTAssertEqual(error as? LOCALBStatus, .clientRequestSignatureInvalid)
            }
        }

        XCTAssertThrowsError(try host.coordinator.authorizeProtectedRequest(
            clientKeyID: clientKeyID, permission: .inference,
            request: request,
            challenge: challenge, proofSignatureRaw: requestProof,
            checkpoint: committedCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .clientChallengeInvalid)
        }
        // A permission the client lacks is refused at CHALLENGE ISSUANCE —
        // under-privileged clients never consume ledger capacity at all.
        XCTAssertThrowsError(try host.coordinator.issueRequestChallenge(
            clientKeyID: clientKeyID, permission: .adminTrust,
            checkpoint: committedCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .permissionDenied)
        }

        // Challenge issued BEFORE revocation: the authorize path still
        // re-validates client status and rejects the proof after revocation.
        let preRevocationChallenge = try host.coordinator.issueRequestChallenge(
            clientKeyID: clientKeyID, permission: .inference,
            checkpoint: committedCheckpoint
        )
        let revokedCheckpoint = try host.coordinator.revokeClient(
            clientKeyID: clientKeyID, reason: "operator revoked pairing",
            checkpoint: committedCheckpoint
        )
        let replayProof = try LOCALBClientRequestProofV2.sign(
            clientKeyID: clientKeyID, permission: .inference,
            request: request,
            challenge: preRevocationChallenge, with: clientKey
        )
        XCTAssertThrowsError(try host.coordinator.authorizeProtectedRequest(
            clientKeyID: clientKeyID, permission: .inference,
            request: request,
            challenge: preRevocationChallenge, proofSignatureRaw: replayProof,
            checkpoint: revokedCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .clientRevoked)
        }

        // After revocation, issuance itself fails closed — a revoked client
        // can no longer obtain challenges at all.
        XCTAssertThrowsError(try host.coordinator.issueRequestChallenge(
            clientKeyID: clientKeyID, permission: .inference,
            checkpoint: revokedCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .clientRevoked)
        }
    }

    /// Challenge-issuance resource hardening: registry validation happens
    /// before any ledger capacity is consumed, and per-client pending and
    /// rate limits prevent an unauthenticated TLS peer from starving
    /// legitimate clients of challenges.
    func testChallengeIssuanceValidatesClientAndAppliesResourceLimits()
        throws {
        let host = try makeHost()
        let (presentation, secret) = try issue(host)
        let clientKey = Curve25519.Signing.PrivateKey()
        let submission = try makeSubmission(
            presentation, secret: secret, clientKey: clientKey
        )
        let pendingPairing = try host.coordinator.preparePairing(
            submission, checkpoint: presentation.registryCheckpoint
        )
        let committed = try host.coordinator.approveAndRegister(
            pendingPairing,
            operatorApproved: true,
            operatorAuthorizationReference: "CHALLENGE-LIMIT-TEST",
            checkpoint: presentation.registryCheckpoint
        )
        let clientKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )

        func issueChallenge() throws -> [UInt8] {
            try host.coordinator.issueRequestChallenge(
                clientKeyID: clientKeyID, permission: .inference,
                checkpoint: committed
            )
        }

        // Unknown client: refused before any ledger capacity is used.
        let unknownKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(
                Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
            )
        )
        XCTAssertThrowsError(try host.coordinator.issueRequestChallenge(
            clientKeyID: unknownKeyID, permission: .inference,
            checkpoint: committed
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .clientUnknown)
        }

        // Permission the client lacks: refused at issuance.
        XCTAssertThrowsError(try host.coordinator.issueRequestChallenge(
            clientKeyID: clientKeyID, permission: .srsWrite,
            checkpoint: committed
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .permissionDenied)
        }

        // Per-client pending cap: 64 outstanding challenges, the 65th is
        // refused even though the global budget (8192) is untouched.
        var outstanding: [[UInt8]] = []
        for _ in 0..<64 {
            outstanding.append(try issueChallenge())
        }
        XCTAssertThrowsError(try issueChallenge()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .resourceLimit)
        }

        // Per-client rate limit: consume each outstanding challenge through
        // a valid authorization (freeing pending capacity), then keep
        // issue+consume cycles inside the rate window. 128 issuances per
        // window are allowed; the 129th is rate-limited even though nothing
        // is pending.
        let request = try makeHTTPRequest()
        func consume(_ challenge: [UInt8]) throws {
            let proof = try LOCALBClientRequestProofV2.sign(
                clientKeyID: clientKeyID, permission: .inference,
                request: request, challenge: challenge, with: clientKey
            )
            _ = try host.coordinator.authorizeProtectedRequest(
                clientKeyID: clientKeyID, permission: .inference,
                request: request,
                challenge: challenge, proofSignatureRaw: proof,
                checkpoint: committed
            )
        }
        for challenge in outstanding {
            try consume(challenge)
        }
        for _ in 0..<(128 - 64) {
            try consume(try issueChallenge())
        }
        XCTAssertThrowsError(try issueChallenge()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .challengeRateLimited)
        }
    }

    func testRoutePathAndQueryAreDerivedFromSignedRequestTarget() throws {
        let noQuery = try makeHTTPRequest(requestTarget: "/v1/inference")
        XCTAssertEqual(noQuery.routePath, "/v1/inference")
        XCTAssertNil(noQuery.query)

        let withQuery = try makeHTTPRequest(
            requestTarget: "/v1/inference?model=alpha&trace=1"
        )
        XCTAssertEqual(withQuery.routePath, "/v1/inference")
        XCTAssertEqual(withQuery.query, "model=alpha&trace=1")
        XCTAssertEqual(withQuery.requestTarget, "/v1/inference?model=alpha&trace=1")

        let emptyQuery = try makeHTTPRequest(requestTarget: "/v1/inference?")
        XCTAssertEqual(emptyQuery.routePath, "/v1/inference")
        XCTAssertEqual(emptyQuery.query, "")

        // The route key is the same, but the complete signed target must differ.
        // A query that changes endpoint behavior therefore cannot be altered under
        // a proof over the no-query request.
        let clientKeyID = String(repeating: "a", count: 64)
        let challenge = [UInt8](repeating: 0x7B, count: 32)
        let noQueryInput = try LOCALBClientRequestProofV2.signatureInput(
            clientKeyID: clientKeyID,
            permission: .inference,
            request: noQuery,
            challenge: challenge
        )
        let queryInput = try LOCALBClientRequestProofV2.signatureInput(
            clientKeyID: clientKeyID,
            permission: .inference,
            request: withQuery,
            challenge: challenge
        )
        XCTAssertNotEqual(noQueryInput, queryInput)
    }

    func testHTTPRequestV1RejectsAmbiguousCanonicalization() throws {
        XCTAssertThrowsError(try makeHTTPRequest(method: "post")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(authority: "SIMIGO.LOCAL:8080")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(authority: "simigo.local:08080")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(authority: "simigo.local:65536")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(authority: "simigo.local:abc")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(authority: "999.1.1.1:8080")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(authority: "[::::]:8080")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertNoThrow(try makeHTTPRequest(authority: "[::1]:8080"))
        XCTAssertThrowsError(try makeHTTPRequest(requestTarget: "//other.local/admin")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(requestTarget: "/safe/../admin")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(requestTarget: "/safe/%2E%2E/admin")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(requestTarget: "/v1/item?x=%2f")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(requestTarget: "/v1/%FF")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertNoThrow(try makeHTTPRequest(requestTarget: "/v1/%C3%A9"))
        XCTAssertThrowsError(try makeHTTPRequest(requestTarget: "/safe#fragment")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(contentType: "application/json\r\nx-evil: yes")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(contentEncoding: "gzip")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
    }

    func testWrongSecretDoesNotConsumeCredentialOrLeakTerminalState() throws {
        let host = try makeHost()
        let (presentation, secret) = try issue(host)
        let clientKey = Curve25519.Signing.PrivateKey()
        let wrongSecret = [UInt8](repeating: 0, count: 32)
        let badSubmission = try makeSubmission(
            presentation, secret: wrongSecret, clientKey: clientKey
        )
        XCTAssertThrowsError(try host.coordinator.preparePairing(
            badSubmission, checkpoint: presentation.registryCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidCredentialSecret)
        }

        let stateAfterFailure = try host.store.loadPairingState(checkpoint: presentation.registryCheckpoint)
        XCTAssertEqual(stateAfterFailure.credentials[presentation.credentialID]?.status, .issued)

        // Correct secret with a TLS identity mismatch is also only an
        // aborted attempt: the credential remains ISSUED.
        let badTLSSubmission = try makeSubmission(
            presentation, secret: secret, clientKey: clientKey,
            tlsHash: String(repeating: "f", count: 64)
        )
        XCTAssertThrowsError(try host.coordinator.preparePairing(
            badTLSSubmission, checkpoint: presentation.registryCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .pairingBindingMismatch)
        }
        XCTAssertEqual(
            try host.store.loadPairingState(checkpoint: presentation.registryCheckpoint)
                .credentials[presentation.credentialID]?.status,
            .issued
        )

        // The same credential remains usable by its legitimate holder.
        let validSubmission = try makeSubmission(
            presentation, secret: secret, clientKey: clientKey
        )
        _ = try host.coordinator.preparePairing(validSubmission, checkpoint: presentation.registryCheckpoint)
    }

    func testOperatorRevocationIsTerminalButInvalidSecretDoesNotRevealIt() throws {
        let host = try makeHost()
        let (presentation, secret) = try issue(host)
        let revokedHead = try host.coordinator.revokePairingCredential(
            credentialID: presentation.credentialID,
            reason: "operator cancelled pairing",
            checkpoint: presentation.registryCheckpoint
        )
        let state = try host.store.loadPairingState(checkpoint: revokedHead)
        XCTAssertEqual(state.credentials[presentation.credentialID]?.status, .revoked)

        let clientKey = Curve25519.Signing.PrivateKey()
        let wrongSecret = [UInt8](repeating: 0x7E, count: 32)
        let badSubmission = try makeSubmission(
            presentation, secret: wrongSecret, clientKey: clientKey
        )
        XCTAssertThrowsError(try host.coordinator.preparePairing(
            badSubmission, checkpoint: revokedHead
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidCredentialSecret)
        }

        let validSubmission = try makeSubmission(
            presentation, secret: secret, clientKey: clientKey
        )
        XCTAssertThrowsError(try host.coordinator.preparePairing(
            validSubmission, checkpoint: revokedHead
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .pairingCredentialRevoked)
        }
    }

    func testStrictHeadlessRequiresPreBoundFullClientFingerprint() throws {
        let host = try makeHost()
        let intendedClient = Curve25519.Signing.PrivateKey()
        let attackerClient = Curve25519.Signing.PrivateKey()
        let (presentation, secret) = try issue(
            host, mode: .strictHeadless, expectedClientKey: intendedClient
        )

        let wrongKeySubmission = try makeSubmission(
            presentation, secret: secret, clientKey: attackerClient
        )
        XCTAssertThrowsError(try host.coordinator.preparePairing(
            wrongKeySubmission, checkpoint: presentation.registryCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .pairingBindingMismatch)
        }
        XCTAssertEqual(
            try host.store.loadPairingState(checkpoint: presentation.registryCheckpoint)
                .credentials[presentation.credentialID]?.status,
            .issued
        )

        let intendedSubmission = try makeSubmission(
            presentation, secret: secret, clientKey: intendedClient
        )
        let pending = try host.coordinator.preparePairing(
            intendedSubmission, checkpoint: presentation.registryCheckpoint
        )
        XCTAssertFalse(pending.requiresOperatorConfirmation)
        let checkpoint = try host.coordinator.approveAndRegister(
            pending, checkpoint: presentation.registryCheckpoint
        )
        let clientID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(intendedClient.publicKey.rawRepresentation)
        )
        XCTAssertEqual(
            try host.store.loadPairingState(checkpoint: checkpoint).clients[clientID]?.status,
            .active
        )
    }

    func testPermissionChangesAreImmediateAndCannotGrantSRSWrite() throws {
        let host = try makeHost()
        let (presentation, secret) = try issue(host)
        let clientKey = Curve25519.Signing.PrivateKey()
        let pending = try host.coordinator.preparePairing(
            makeSubmission(presentation, secret: secret, clientKey: clientKey),
            checkpoint: presentation.registryCheckpoint
        )
        let registered = try host.coordinator.approveAndRegister(
            pending,
            operatorApproved: true,
            operatorAuthorizationReference: "LOCAL-UI-PAIR-CONFIRM-002",
            checkpoint: presentation.registryCheckpoint
        )
        let clientID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )

        XCTAssertThrowsError(try host.coordinator.setClientPermissions(
            clientKeyID: clientID, permissions: [.inference, .srsWrite],
            reason: "forbidden test", checkpoint: registered
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryInvalidTransition)
        }

        let challenge = try host.coordinator.issueRequestChallenge(
            clientKeyID: clientID, permission: .informationRead,
            checkpoint: registered
        )
        let changed = try host.coordinator.setClientPermissions(
            clientKeyID: clientID, permissions: [.inference],
            reason: "least-privilege adjustment", checkpoint: registered
        )
        // Issued while the client still held P-INFO-READ: authorization
        // against the post-change checkpoint must still deny.
        let request = try makeHTTPRequest()
        let proof = try LOCALBClientRequestProofV2.sign(
            clientKeyID: clientID, permission: .informationRead,
            request: request,
            challenge: challenge, with: clientKey
        )
        XCTAssertThrowsError(try host.coordinator.authorizeProtectedRequest(
            clientKeyID: clientID, permission: .informationRead,
            request: request,
            challenge: challenge, proofSignatureRaw: proof,
            checkpoint: changed
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .permissionDenied)
        }

        // After the permission change, issuance for the dropped permission
        // is refused outright — no ledger capacity is consumed.
        XCTAssertThrowsError(try host.coordinator.issueRequestChallenge(
            clientKeyID: clientID, permission: .informationRead,
            checkpoint: changed
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .permissionDenied)
        }
    }

    // MARK: - S1: P-BRANCH-CONTROL codec compatibility (owner approval 2026-11-05)

    /// The full new case space — including srsWrite, which the journal-level
    /// decoder previously refused — must round-trip through a pairing commit.
    func testSixPermissionJournalReloadsAfterBranchControl() throws {
        let all: Set<LOCALBPermission> = [.inference, .informationRead, .srsWrite,
                                          .adminPairing, .adminTrust, .branchControl]
        let payload = try LOCALBPairingEventCodec.encodePairingCommit(
            makeCommitPayload(permissions: all)
        )
        XCTAssertEqual(
            try LOCALBPairingEventCodec.decodePairingCommit(payload).permissions, all
        )
    }

    /// Journals written before P-BRANCH-CONTROL existed keep decoding verbatim.
    func testLegacyJournalWithoutBranchControlStillDecodes() throws {
        let legacy: Set<LOCALBPermission> = [.inference, .informationRead,
                                             .adminPairing, .adminTrust]
        let payload = try LOCALBPairingEventCodec.encodePairingCommit(
            makeCommitPayload(permissions: legacy)
        )
        XCTAssertEqual(
            try LOCALBPairingEventCodec.decodePairingCommit(payload).permissions, legacy
        )
    }

    /// The original enum shipped five cases; a legacy journal carrying all
    /// five original permissions (srsWrite included) must decode with the
    /// set preserved in full — no permission dropped, none renamed. This is
    /// the acceptance shape for "旧的五权限 journal 仍能解码" and it is kept
    /// separate from both the four-permission shape above and the six-
    /// permission (post-branchControl) shape below.
    func testLegacyFivePermissionJournalStillDecodes() throws {
        let legacyFive: Set<LOCALBPermission> = [.inference, .informationRead,
                                                 .srsWrite, .adminPairing, .adminTrust]
        let payload = try LOCALBPairingEventCodec.encodePairingCommit(
            makeCommitPayload(permissions: legacyFive)
        )
        XCTAssertEqual(
            try LOCALBPairingEventCodec.decodePairingCommit(payload).permissions, legacyFive
        )
        XCTAssertEqual(legacyFive.count, 5)
        XCTAssertFalse(legacyFive.contains(.branchControl))
    }

    /// The cap derives from allCases.count: a declared 7-entry permissions
    /// field fails closed even though every entry is well-formed and strictly
    /// ordered (the 7th name is unknown, so the unknown guard would also fire).
    func testSevenEntryPermissionFieldFailsClosed() throws {
        let payload = try commitPayloadBytes(permissionsBytes: permissionsFieldBytes([
            "P-ADMIN-PAIRING", "P-ADMIN-TRUST", "P-BRANCH-CONTROL",
            "P-INFERENCE", "P-INFO-READ", "P-QUEUED", "P-SRS-WRITE"
        ]))
        XCTAssertThrowsError(try LOCALBPairingEventCodec.decodePairingCommit(payload)) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryCorrupt)
        }
    }

    /// Unknown permission rawValues keep failing closed.
    func testUnknownPermissionNameFailsClosed() throws {
        let payload = try commitPayloadBytes(
            permissionsBytes: permissionsFieldBytes(["P-INFERENCE", "P-QUEUED"])
        )
        XCTAssertThrowsError(try LOCALBPairingEventCodec.decodePairingCommit(payload)) { error in
            XCTAssertEqual(error as? LOCALBStatus, .registryCorrupt)
        }
    }

    /// Pairing keeps pinning the default set; P-BRANCH-CONTROL must never
    /// enter it silently.
    func testDefaultPairingSetExcludesBranchControl() throws {
        let host = try makeHost()
        let clientKey = Curve25519.Signing.PrivateKey()
        let (presentation, secret) = try issue(
            host, mode: .strictHeadless, expectedClientKey: clientKey
        )
        let submission = try makeSubmission(presentation, secret: secret, clientKey: clientKey)
        let pending = try host.coordinator.preparePairing(
            submission, checkpoint: presentation.registryCheckpoint
        )
        let registered = try host.coordinator.approveAndRegister(
            pending, checkpoint: presentation.registryCheckpoint
        )
        let clientID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )
        let state = try host.store.loadPairingState(checkpoint: registered)
        let permissions = state.clients[clientID]?.permissions ?? []
        XCTAssertEqual(permissions, [.inference, .informationRead])
        XCTAssertFalse(permissions.contains(.branchControl))
    }

    /// branchControl is grantable on the change path, the journal sequence
    /// and head hash both move, and a fresh reload plus the full challenge →
    /// proof → authorize chain see the new permission.
    func testBranchControlGrantSurvivesReloadAndAuthorizes() throws {
        let host = try makeHost()
        let clientKey = Curve25519.Signing.PrivateKey()
        let (presentation, secret) = try issue(
            host, mode: .strictHeadless, expectedClientKey: clientKey
        )
        let submission = try makeSubmission(presentation, secret: secret, clientKey: clientKey)
        let pending = try host.coordinator.preparePairing(
            submission, checkpoint: presentation.registryCheckpoint
        )
        let registered = try host.coordinator.approveAndRegister(
            pending, checkpoint: presentation.registryCheckpoint
        )
        let clientID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )

        let changed = try host.coordinator.setClientPermissions(
            clientKeyID: clientID, permissions: [.inference, .branchControl],
            reason: "S1 branch-control grant", checkpoint: registered
        )
        XCTAssertEqual(changed.sequence, registered.sequence + 1)
        XCTAssertNotEqual(changed.headHash, registered.headHash)

        let reloaded = try host.store.loadPairingState(checkpoint: changed)
        XCTAssertEqual(
            reloaded.clients[clientID]?.permissions, [.inference, .branchControl]
        )

        let challenge = try host.coordinator.issueRequestChallenge(
            clientKeyID: clientID, permission: .branchControl, checkpoint: changed
        )
        let request = try makeHTTPRequest()
        let proof = try LOCALBClientRequestProofV2.sign(
            clientKeyID: clientID, permission: .branchControl,
            request: request, challenge: challenge, with: clientKey
        )
        let authorized = try host.coordinator.authorizeProtectedRequest(
            clientKeyID: clientID, permission: .branchControl,
            request: request, challenge: challenge,
            proofSignatureRaw: proof, checkpoint: changed
        )
        XCTAssertEqual(authorized.permission, .branchControl)
    }

    // MARK: S1 helpers

    private func makeCommitPayload(
        permissions: Set<LOCALBPermission>
    ) -> LOCALBPairingCommitPayload {
        LOCALBPairingCommitPayload(
            credentialID: UUID().uuidString.lowercased(),
            credentialDigest: Array(repeating: 7, count: 32),
            clientPublicKeyRaw: Array(repeating: 9, count: 32),
            clientKeyID: LOCALBBinary.hexLower(LOCALBBinary.sha256(Array(repeating: 9, count: 32))),
            permissions: permissions,
            registeredAtMilliseconds: 1_000,
            proofSignatureRaw: Array(repeating: 11, count: 64),
            tlsSPKIHash: LOCALBBinary.hexLower(LOCALBBinary.sha256(Array("tls".utf8))),
            srsKeyID: LOCALBBinary.hexLower(LOCALBBinary.sha256(Array("srs".utf8))),
            protocolVersion: LOCALBConstants.credentialProtocolVersion,
            operatorAuthorizationReference: "S1-CODEC-TEST"
        )
    }

    private func permissionsFieldBytes(_ names: [String]) -> [UInt8] {
        var out: [UInt8] = []
        LOCALBBinary.appendU16(UInt16(names.count), to: &out)
        for name in names.sorted() {
            let raw = Array(name.utf8)
            LOCALBBinary.appendU16(UInt16(raw.count), to: &out)
            out.append(contentsOf: raw)
        }
        return out
    }

    private func commitPayloadBytes(permissionsBytes: [UInt8]) throws -> [UInt8] {
        try LOCALBPairingFieldCodec.encode(fields: [
            LOCALBPairingFieldCodec.string("credential_id", value: UUID().uuidString.lowercased()),
            LOCALBPairingFieldCodec.bytes(Array(repeating: 7, count: 32), label: "credential_digest"),
            LOCALBPairingFieldCodec.bytes(Array(repeating: 9, count: 32), label: "client_public_key_raw"),
            LOCALBPairingFieldCodec.string(
                "client_key_id",
                value: LOCALBBinary.hexLower(LOCALBBinary.sha256(Array(repeating: 9, count: 32)))
            ),
            LOCALBPairingFieldCodec.bytes(permissionsBytes, label: "permissions"),
            LOCALBPairingFieldCodec.uint64(1_000, label: "registered_at_ms"),
            LOCALBPairingFieldCodec.bytes(Array(repeating: 11, count: 64), label: "proof_signature_raw"),
            LOCALBPairingFieldCodec.string(
                "tls_spki_sha256", value: LOCALBBinary.hexLower(LOCALBBinary.sha256(Array("tls".utf8)))
            ),
            LOCALBPairingFieldCodec.string(
                "srs_key_id", value: LOCALBBinary.hexLower(LOCALBBinary.sha256(Array("srs".utf8)))
            ),
            LOCALBPairingFieldCodec.string(
                "protocol_version", value: LOCALBConstants.credentialProtocolVersion
            ),
            LOCALBPairingFieldCodec.string(
                "operator_authorization_reference", value: "S1-CODEC-TEST"
            )
        ])
    }
}
