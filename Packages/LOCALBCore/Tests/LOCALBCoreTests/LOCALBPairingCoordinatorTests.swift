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
            clientKeyID: clientKeyID, permission: .inference
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
                clientKeyID: clientKeyID, permission: .inference
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
        let adminChallenge = try host.coordinator.issueRequestChallenge(
            clientKeyID: clientKeyID, permission: .adminTrust
        )
        XCTAssertThrowsError(try host.coordinator.authorizeProtectedRequest(
            clientKeyID: clientKeyID, permission: .adminTrust,
            request: request,
            challenge: adminChallenge, proofSignatureRaw: [],
            checkpoint: committedCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .permissionDenied)
        }

        let revokedCheckpoint = try host.coordinator.revokeClient(
            clientKeyID: clientKeyID, reason: "operator revoked pairing",
            checkpoint: committedCheckpoint
        )
        let replayChallenge = try host.coordinator.issueRequestChallenge(
            clientKeyID: clientKeyID, permission: .inference
        )
        let replayProof = try LOCALBClientRequestProofV2.sign(
            clientKeyID: clientKeyID, permission: .inference,
            request: request,
            challenge: replayChallenge, with: clientKey
        )
        XCTAssertThrowsError(try host.coordinator.authorizeProtectedRequest(
            clientKeyID: clientKeyID, permission: .inference,
            request: request,
            challenge: replayChallenge, proofSignatureRaw: replayProof,
            checkpoint: revokedCheckpoint
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .clientRevoked)
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
        XCTAssertThrowsError(try makeHTTPRequest(requestTarget: "/v1/item?q=[bad]")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertThrowsError(try makeHTTPRequest(requestTarget: "/v1/item?q=\"bad\"")) { error in
            XCTAssertEqual(error as? LOCALBStatus, .invalidProtectedRequest)
        }
        XCTAssertNoThrow(try makeHTTPRequest(requestTarget: "/v1/item?q=%5BB%5D"))
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

        let changed = try host.coordinator.setClientPermissions(
            clientKeyID: clientID, permissions: [.inference],
            reason: "least-privilege adjustment", checkpoint: registered
        )
        let challenge = try host.coordinator.issueRequestChallenge(
            clientKeyID: clientID, permission: .informationRead
        )
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
    }
}
