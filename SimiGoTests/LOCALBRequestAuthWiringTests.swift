import CryptoKit
import Foundation
import LOCALBCore
import Network
import XCTest

@testable import SimiGo

/// LOCALB B3 request-authorization wiring tests. These exercise the REAL
/// path end to end: a real LOCALB registry with a fully paired ACTIVE
/// client (credential → PoP → operator approval → single commit), a real
/// TLS listener with a pinned SPKI, the real challenge endpoint, real V2
/// proof construction, and real HTTP request/response bytes. No mocks.
///
/// Permission derivation is server-side only: clients never submit a
/// permission value anywhere in this protocol; the table in
/// HTTPServer.localbRoutePolicy(forMethod:routePath:) governs challenge
/// issuance, authorization, and dispatch denial.
final class LOCALBRequestAuthWiringTests: XCTestCase {

    // MARK: - Fixture

    private struct Host {
        let port: UInt16
        let plaintextCompatPort: UInt16
        let spkiHex: String
        let clientKey: Curve25519.Signing.PrivateKey
        let clientKeyID: String
    }

    private func randomPort() -> UInt16 {
        UInt16.random(in: 42000...58000)
    }

    private func makeServer(port: UInt16) -> HTTPServer {
        HTTPServer(
            port: Int(port),
            modelId: "localb-b3-wiring-test",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "localb-b3-wiring-test",
                    savedAt: Date(),
                    history: []
                )
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )
    }

    private static func hexSha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }
            .joined()
    }

    /// Builds the full authorized host: registry lineage, host signing key,
    /// one paired ACTIVE client (default {P-INFERENCE, P-INFO-READ}), a TLS
    /// listener with an explicit loopback plaintext-compatibility port, and
    /// the B3 request-authorization wiring.
    private func makeAuthorizedHost(
        configureAuthorization: Bool = true
    ) throws -> Host {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-b3-wiring-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let store = LOCALBRegistryStore(rootURL: root)
        var checkpoint = try store.initializeNewLineage()
        let hostSigningKey = Curve25519.Signing.PrivateKey()
        let hostPublicKey = Array(hostSigningKey.publicKey.rawRepresentation)
        checkpoint = try store.appendKeyRegistration(
            publicKeyRaw: hostPublicKey,
            generation: 1,
            checkpoint: checkpoint
        )
        let srsKeyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: hostPublicKey)
        let coordinator = LOCALBPairingCoordinator(registryStore: store)

        // Full interactive pairing: issue → PoP submission → operator
        // approval → single commit event (consume + register).
        let presentation = try coordinator.issueCredential(
            scopeLabel: "B3 wiring test client",
            tlsSPKIHash: Self.hexSha256("localb-b3-test-tls-spki"),
            srsKeyID: srsKeyID,
            checkpoint: checkpoint
        )
        let secret = try LOCALBPairingSubmission.decodeSecretBase64URL(
            presentation.takeSecretBase64URLOnce()
        )
        let clientKey = Curve25519.Signing.PrivateKey()
        let pop = try LOCALBPairingProofV1.sign(
            credentialID: presentation.credentialID,
            sessionNonce: try XCTUnwrap(
                HTTPServer.decodeLowerHex(presentation.sessionNonceHex)
            ),
            hostInstanceID: presentation.hostInstanceID,
            tlsSPKIHash: presentation.tlsSPKIHash,
            srsKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion,
            with: clientKey
        )
        let submission = LOCALBPairingSubmission(
            credentialID: presentation.credentialID,
            secretRaw: secret,
            clientPublicKeyRaw: Array(clientKey.publicKey.rawRepresentation),
            proofSignatureRaw: pop,
            actualTLSSPKIHash: presentation.tlsSPKIHash,
            presentedSRSKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion
        )
        let pending = try coordinator.preparePairing(
            submission,
            checkpoint: presentation.registryCheckpoint
        )
        let committed = try coordinator.approveAndRegister(
            pending,
            operatorApproved: true,
            operatorAuthorizationReference: "B3-WIRING-TEST",
            checkpoint: presentation.registryCheckpoint
        )
        let clientKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )

        let transportStore = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-b3.\(UUID().uuidString)",
            account: "tls"
        )
        addTeardownBlock { transportStore.deleteAll() }
        let identity = try transportStore.loadOrCreate()

        let port = randomPort()
        let plaintextCompatPort = randomPort()
        let server = makeServer(port: port)
        server.configureLOCALBTransport(
            identity: identity,
            plaintextCompatibilityPort: Int(plaintextCompatPort)
        )
        if configureAuthorization {
            var trustedCheckpoint = committed
            server.configureLOCALBRequestAuthorization(
                coordinator: coordinator,
                trustedCheckpoint: { trustedCheckpoint }
            )
        }
        try server.start()
        addTeardownBlock { server.stop() }

        return Host(
            port: port,
            plaintextCompatPort: plaintextCompatPort,
            spkiHex: identity.spkiSHA256Hex,
            clientKey: clientKey,
            clientKeyID: clientKeyID
        )
    }

    // MARK: - Raw HTTP helpers

    private func sendRequest(
        port: UInt16,
        spkiHex: String?,
        request: String,
        timeout: TimeInterval = 10
    ) -> Data? {
        let parameters: NWParameters
        if let spkiHex {
            let options = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(
                options.securityProtocolOptions,
                { _, secTrust, complete in
                    guard
                        let trust = sec_trust_copy_ref(secTrust)
                            .takeRetainedValue() as SecTrust?,
                        let certificate = SecTrustGetCertificateAtIndex(trust, 0),
                        let hex = try? LOCALBTransportIdentityStore
                            .spkiSHA256Hex(of: certificate)
                    else {
                        complete(false)
                        return
                    }
                    complete(hex == spkiHex)
                },
                DispatchQueue.global()
            )
            parameters = NWParameters(tls: options)
        } else {
            parameters = .tcp
        }
        let client = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: parameters
        )
        let done = expectation(description: "raw http done")
        var response: Data?
        var fulfilled = false
        let fulfilledLock = NSLock()
        func finish() {
            fulfilledLock.lock()
            let already = fulfilled
            fulfilled = true
            fulfilledLock.unlock()
            if !already { done.fulfill() }
        }
        client.stateUpdateHandler = { state in
            switch state {
            case .ready:
                client.send(
                    content: Data(request.utf8),
                    completion: .contentProcessed { _ in }
                )
                client.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: 256 * 1024
                ) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        response = data
                        finish()
                    } else if isComplete || error != nil {
                        finish()
                    }
                }
            case .failed, .cancelled, .waiting:
                finish()
            default:
                break
            }
        }
        client.start(queue: DispatchQueue.global())
        wait(for: [done], timeout: timeout)
        client.cancel()
        return response
    }

    private func statusLine(of response: Data?) -> String? {
        response.flatMap { String(data: $0, encoding: .utf8) }?
            .components(separatedBy: "\r\n").first
    }

    private func jsonBody(of response: Data?) -> [String: Any]? {
        guard let text = response.flatMap({ String(data: $0, encoding: .utf8) }),
              let range = text.range(of: "\r\n\r\n")
        else { return nil }
        let body = String(text[range.upperBound...])
        return try? JSONSerialization.jsonObject(with: Data(body.utf8))
            as? [String: Any]
    }

    /// Fetches a one-time challenge over pinned TLS for the intended
    /// (method, target); the server derives the permission.
    private func fetchChallenge(
        _ host: Host,
        method: String,
        target: String
    ) throws -> (challenge: [UInt8], permission: String) {
        let body = "{\"method\":\"\(method)\",\"requestTarget\":\"\(target)\"}"
        let request = "POST /localb/auth/challenge HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + body
        let response = sendRequest(
            port: host.port,
            spkiHex: host.spkiHex,
            request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 200 "), "challenge: \(status)")
        let json = try XCTUnwrap(jsonBody(of: response))
        let challengeHex = try XCTUnwrap(json["challenge"] as? String)
        let permission = try XCTUnwrap(json["permission"] as? String)
        let challenge = try XCTUnwrap(HTTPServer.decodeLowerHex(challengeHex))
        XCTAssertEqual(challenge.count, 32)
        return (challenge, permission)
    }

    /// Builds a signed protected request for the exact target/body and
    /// returns the raw HTTP request bytes. `extraHeaders` are sent on the
    /// wire but are NOT part of the signed material — the fixture for
    /// unsigned-header boundary tests.
    private func protectedRequest(
        _ host: Host,
        method: String,
        target: String,
        contentType: String?,
        body: String,
        challenge: [UInt8],
        permission: LOCALBPermission,
        sendTarget: String? = nil,
        sendBody: String? = nil,
        extraHeaders: [(name: String, value: String)] = []
    ) throws -> String {
        let authority = "127.0.0.1:\(host.port)"
        let signed = try LOCALBHTTPRequestV1(
            method: method,
            authority: authority,
            requestTarget: target,
            contentType: contentType,
            bodyRaw: Array(body.utf8)
        )
        let proof = try LOCALBClientRequestProofV2.sign(
            clientKeyID: host.clientKeyID,
            permission: permission,
            request: signed,
            challenge: challenge,
            with: host.clientKey
        )
        let wireTarget = sendTarget ?? target
        let wireBody = sendBody ?? body
        var request = "\(method) \(wireTarget) HTTP/1.1\r\n"
            + "Host: \(authority)\r\n"
        if let contentType {
            request += "Content-Type: \(contentType)\r\n"
        }
        for (name, value) in extraHeaders {
            request += "\(name): \(value)\r\n"
        }
        request += "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "X-SimiGo-LocalB-Challenge: "
            + HTTPServer.encodeLowerHex(challenge) + "\r\n"
            + "X-SimiGo-LocalB-Proof-V2: "
            + Data(proof).base64EncodedString() + "\r\n"
            + "Content-Length: \(wireBody.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + wireBody
        return request
    }

    // MARK: - Tests

    func testProtectedRouteServesOnlyWithVerifiedProofOverTLS() throws {
        let host = try makeAuthorizedHost()
        let (challenge, permission) = try fetchChallenge(
            host, method: "GET", target: "/v1/models"
        )
        XCTAssertEqual(permission, "P-INFO-READ")
        let request = try protectedRequest(
            host,
            method: "GET",
            target: "/v1/models",
            contentType: nil,
            body: "",
            challenge: challenge,
            permission: .informationRead
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 200 "), "got: \(status)")
    }

    func testSignedBodyReachesInferenceEndpoint() throws {
        let host = try makeAuthorizedHost()
        let (challenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        let body =
            "{\"model\":\"localb-b3-wiring-test\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
        let request = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions",
            contentType: "application/json",
            body: body,
            challenge: challenge,
            permission: .inference
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 200 "), "got: \(status)")
    }

    func testTamperedBodyIsRejected() throws {
        let host = try makeAuthorizedHost()
        let (challenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        let signedBody =
            "{\"model\":\"localb-b3-wiring-test\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
        let request = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions",
            contentType: "application/json",
            body: signedBody,
            challenge: challenge,
            permission: .inference,
            sendBody: "{\"model\":\"localb-b3-wiring-test\",\"messages\":[{\"role\":\"user\",\"content\":\"tampered\"}]}"
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 401 "), "got: \(status)")
    }

    func testQueryAlterationIsRejectedAndExactQueryServes() throws {
        let host = try makeAuthorizedHost()

        // Exact signed query still serves the same route.
        let (challenge, _) = try fetchChallenge(
            host, method: "GET", target: "/v1/models?trace=1"
        )
        let ok = try protectedRequest(
            host,
            method: "GET",
            target: "/v1/models?trace=1",
            contentType: nil,
            body: "",
            challenge: challenge,
            permission: .informationRead
        )
        let okResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: ok
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: okResponse)).contains(" 200 ")
        )

        // Same path, altered query under the old proof → rejected.
        let (challenge2, _) = try fetchChallenge(
            host, method: "GET", target: "/v1/models?trace=1"
        )
        let altered = try protectedRequest(
            host,
            method: "GET",
            target: "/v1/models?trace=1",
            contentType: nil,
            body: "",
            challenge: challenge2,
            permission: .informationRead,
            sendTarget: "/v1/models?trace=2"
        )
        let alteredResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: altered
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: alteredResponse)).contains(" 401 ")
        )

        // Empty query and absent query are different signed targets.
        let (challenge3, _) = try fetchChallenge(
            host, method: "GET", target: "/v1/models?"
        )
        let emptyVsAbsent = try protectedRequest(
            host,
            method: "GET",
            target: "/v1/models?",
            contentType: nil,
            body: "",
            challenge: challenge3,
            permission: .informationRead,
            sendTarget: "/v1/models"
        )
        let mismatchResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: emptyVsAbsent
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: mismatchResponse)).contains(" 401 ")
        )
    }

    func testChallengeIsSingleUse() throws {
        let host = try makeAuthorizedHost()
        let (challenge, _) = try fetchChallenge(
            host, method: "GET", target: "/v1/models"
        )
        let request = try protectedRequest(
            host,
            method: "GET",
            target: "/v1/models",
            contentType: nil,
            body: "",
            challenge: challenge,
            permission: .informationRead
        )
        let first = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        XCTAssertTrue(try XCTUnwrap(statusLine(of: first)).contains(" 200 "))
        // Replaying the exact same request (same challenge + proof) fails.
        let second = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        XCTAssertTrue(try XCTUnwrap(statusLine(of: second)).contains(" 401 "))
    }

    func testValidProofOverPlaintextCompatibilityPortIsRefused() throws {
        let host = try makeAuthorizedHost()
        let (challenge, _) = try fetchChallenge(
            host, method: "GET", target: "/v1/models"
        )
        let request = try protectedRequest(
            host,
            method: "GET",
            target: "/v1/models",
            contentType: nil,
            body: "",
            challenge: challenge,
            permission: .informationRead
        )
        // The same request bytes over the plaintext compatibility listener
        // are refused at the transport boundary — the proof is never even
        // evaluated.
        let response = sendRequest(
            port: host.plaintextCompatPort, spkiHex: nil, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 403 "), "got: \(status)")
    }

    func testChallengeEndpointRefusesPlaintextAndUnknownRoutes() throws {
        let host = try makeAuthorizedHost()

        // Plaintext: no challenge issuance.
        let body = "{\"method\":\"GET\",\"requestTarget\":\"/v1/models\"}"
        let plaintextRequest = "POST /localb/auth/challenge HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.plaintextCompatPort)\r\n"
            + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + body
        let plaintextResponse = sendRequest(
            port: host.plaintextCompatPort,
            spkiHex: nil,
            request: plaintextRequest
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: plaintextResponse)).contains(" 403 ")
        )

        // TLS but an unprotected/unknown route: no permission exists, so no
        // challenge is issued.
        let openBody = "{\"method\":\"GET\",\"requestTarget\":\"/health\"}"
        let openRequest = "POST /localb/auth/challenge HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(openBody.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + openBody
        let openResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: openRequest
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: openResponse)).contains(" 400 ")
        )
    }

    func testMissingProofHeadersAndUnconfiguredAuthorizationFailClosed()
        throws {
        let host = try makeAuthorizedHost()

        // Missing proof headers over trusted TLS → 401, never open access.
        let bare = "GET /v1/models HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "Connection: close\r\n\r\n"
        let bareResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: bare
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: bareResponse)).contains(" 401 ")
        )

        // Authorization not configured → protected routes fail closed 503.
        let unconfigured = try makeAuthorizedHost(configureAuthorization: false)
        let (challenge, _) = try fetchChallenge(
            host, method: "GET", target: "/v1/models"
        )
        let request = try protectedRequest(
            host,
            method: "GET",
            target: "/v1/models",
            contentType: nil,
            body: "",
            challenge: challenge,
            permission: .informationRead
        )
        let response = sendRequest(
            port: unconfigured.port,
            spkiHex: unconfigured.spkiHex,
            request: request
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: response)).contains(" 503 ")
        )
    }

    // MARK: - Gate 1: unsigned identity-selection header boundary

    /// Each identity-selection header variant uses its OWN fresh challenge
    /// and a valid proof over the identical signed request (method, target,
    /// content type, body). Only the unsigned header under test differs,
    /// so a rejection proves the header boundary — not a stale challenge
    /// and not a broken proof.
    func testUnsignedIdentitySelectionHeadersAreRejectedOnProtectedRoute()
        throws {
        let host = try makeAuthorizedHost()
        let body =
            "{\"model\":\"localb-b3-wiring-test\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"

        for headerName in HTTPServer.localbIdentitySelectionHeaders()
            .sorted() {
            let (challenge, _) = try fetchChallenge(
                host, method: "POST", target: "/v1/chat/completions"
            )
            let request = try protectedRequest(
                host,
                method: "POST",
                target: "/v1/chat/completions",
                contentType: "application/json",
                body: body,
                challenge: challenge,
                permission: .inference,
                extraHeaders: [(headerName, "rogue-identity")]
            )
            let response = sendRequest(
                port: host.port, spkiHex: host.spkiHex, request: request
            )
            let status = try XCTUnwrap(statusLine(of: response))
            XCTAssertTrue(
                status.contains(" 401 "),
                "\(headerName): expected 401, got: \(status)"
            )
            let text = String(
                decoding: response ?? Data(), as: UTF8.self
            )
            XCTAssertTrue(
                text.contains("LOCALB_UNSIGNED_IDENTITY_HEADER"),
                "\(headerName): expected an explicit rejection reason, "
                    + "got: \(text.prefix(300))"
            )
        }

        // Control: the identical signed request WITHOUT an identity-
        // selection header (fresh challenge, valid proof) still serves —
        // the rejections above are attributable to the header alone.
        let (controlChallenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        let control = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions",
            contentType: "application/json",
            body: body,
            challenge: controlChallenge,
            permission: .inference
        )
        let controlResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: control
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: controlResponse)).contains(" 200 ")
        )

        // Whitespace-only values select no identity and are not violations.
        let (blankChallenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        let blank = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions",
            contentType: "application/json",
            body: body,
            challenge: blankChallenge,
            permission: .inference,
            extraHeaders: [("x-agent-id", "   ")]
        )
        let blankResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: blank
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: blankResponse)).contains(" 200 ")
        )
    }

    /// The sanctioned identity channel: signed JSON body fields (part of
    /// the proof's bodyRaw) still select identity and are not rejected.
    func testSignedJSONIdentityFieldsStillServe() throws {
        let host = try makeAuthorizedHost()
        let (challenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        let body =
            "{\"model\":\"localb-b3-wiring-test\","
            + "\"agent_id\":\"signed-agent\","
            + "\"session_id\":\"signed-session\","
            + "\"branch_id\":\"signed-branch\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
        let request = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions",
            contentType: "application/json",
            body: body,
            challenge: challenge,
            permission: .inference
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: response)).contains(" 200 ")
        )
    }

    // MARK: - Gate 1: dispatch-header construction (pure functions)

    /// The LOCALB dispatch request is rebuilt ONLY from the verified
    /// signed object: its header map can contain at most the signed
    /// content semantics, and never an identity-selection header.
    func testDispatchHeadersAreBuiltOnlyFromSignedContentSemantics() {
        let headers = HTTPServer.localbDispatchHeaders(
            contentType: "application/json",
            contentEncoding: "identity"
        )
        XCTAssertEqual(
            headers,
            [
                "content-type": "application/json",
                "content-encoding": "identity",
            ]
        )
        XCTAssertTrue(
            HTTPServer.localbIdentitySelectionHeaders()
                .isDisjoint(with: headers.keys)
        )

        let noContentType = HTTPServer.localbDispatchHeaders(
            contentType: "",
            contentEncoding: "identity"
        )
        XCTAssertEqual(noContentType, ["content-encoding": "identity"])
        XCTAssertNil(noContentType["content-type"])
    }

    func testIdentitySelectionViolationPredicate() {
        for name in HTTPServer.localbIdentitySelectionHeaders() {
            XCTAssertNotNil(
                HTTPServer.localbIdentitySelectionViolation(
                    in: [name: "value"]
                ),
                "\(name) with a value must be a violation"
            )
            XCTAssertNil(
                HTTPServer.localbIdentitySelectionViolation(
                    in: [name: "  \t "]
                ),
                "\(name) with a whitespace-only value selects nothing"
            )
        }
        XCTAssertNil(
            HTTPServer.localbIdentitySelectionViolation(
                in: [
                    "content-type": "application/json",
                    "x-request-id": "abc",
                    "accept": "text/event-stream",
                ]
            )
        )
    }

    /// The remote-forward boundary is an independently reviewed allowlist:
    /// client headers can never reach the upstream request — not
    /// credentials, not identity, not content negotiation.
    func testRemoteForwardAllowlistPassesOnlySignedContentSemantics() {
        let sample: [String: String] = [
            "content-type": "application/json",
            "content-encoding": "identity",
            "authorization": "Bearer client-chosen",
            "proxy-authorization": "Basic client-chosen",
            "x-agent-id": "rogue",
            "x-session-id": "rogue",
            "x-branch-id": "rogue",
            "accept": "text/event-stream",
            "host": "evil.example",
        ]
        let forwarded = sample.filter {
            HTTPServer.localbRemoteForwardAllowlist().contains($0.key)
        }
        XCTAssertEqual(
            forwarded,
            [
                "content-type": "application/json",
                "content-encoding": "identity",
            ]
        )
    }

    // MARK: - Gate 2: branch operations fail closed

    /// A default-paired client ({P-INFERENCE, P-INFO-READ}) cannot perform
    /// ANY branch operation: challenge issuance refuses with an explicit
    /// denial (distinct from the 400 for open routes), and a dispatch-time
    /// request carrying a well-formed P-INFERENCE proof is denied BEFORE
    /// proof verification — so no proof can bypass the denial. Ordinary
    /// inference keeps serving with the same client.
    func testBranchOperationsAreDeniedForPairedInferenceClient() throws {
        let host = try makeAuthorizedHost()

        for target in [
            "/v1/branches/fork",
            "/v1/branches/delete",
            "/v1/branches/list",
        ] {
            let body =
                "{\"method\":\"POST\",\"requestTarget\":\"\(target)\"}"
            let challengeRequest =
                "POST /localb/auth/challenge HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(host.port)\r\n"
                + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(body.utf8.count)\r\n"
                + "Connection: close\r\n\r\n" + body
            let response = sendRequest(
                port: host.port,
                spkiHex: host.spkiHex,
                request: challengeRequest
            )
            let status = try XCTUnwrap(statusLine(of: response))
            XCTAssertTrue(
                status.contains(" 403 "),
                "\(target) challenge: expected 403, got: \(status)"
            )
            let text = String(
                decoding: response ?? Data(), as: UTF8.self
            )
            XCTAssertTrue(
                text.contains("LOCALB_BRANCH_OPERATIONS_NOT_AUTHORIZED"),
                "\(target) challenge: expected an explicit denial reason, "
                    + "got: \(text.prefix(300))"
            )
        }

        // Dispatch-level denial with a well-formed proof over a branch
        // target: rejected before verification, regardless of proof
        // content.
        let dummyChallenge = [UInt8](repeating: 0x41, count: 32)
        for target in [
            "/v1/branches/fork",
            "/v1/branches/delete",
            "/v1/branches/list",
        ] {
            let request = try protectedRequest(
                host,
                method: "POST",
                target: target,
                contentType: "application/json",
                body: "{\"session_id\":\"s\",\"branch_id\":\"b\"}",
                challenge: dummyChallenge,
                permission: .inference
            )
            let response = sendRequest(
                port: host.port, spkiHex: host.spkiHex, request: request
            )
            let status = try XCTUnwrap(statusLine(of: response))
            XCTAssertTrue(
                status.contains(" 403 "),
                "\(target) dispatch: expected 403, got: \(status)"
            )
        }

        // Ordinary inference keeps its authorized behavior.
        let (challenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        let chatBody =
            "{\"model\":\"localb-b3-wiring-test\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
        let chat = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions",
            contentType: "application/json",
            body: chatBody,
            challenge: challenge,
            permission: .inference
        )
        let chatResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: chat
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: chatResponse)).contains(" 200 ")
        )
    }

    /// The route-policy table maps branch mutations to an explicit denial
    /// that is distinct from open routes and from protected routes.
    func testRoutePolicyDeniesBranchOperationsExplicitly() {
        for target in [
            "/v1/branches/fork",
            "/v1/branches/delete",
            "/v1/branches/list",
        ] {
            XCTAssertEqual(
                HTTPServer.localbRoutePolicy(
                    forMethod: "POST", routePath: target
                ),
                .denied(reason: "LOCALB_BRANCH_OPERATIONS_NOT_AUTHORIZED")
            )
        }
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(forMethod: "GET", routePath: "/health"),
            .open
        )
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(forMethod: "OPTIONS", routePath: "/v1/chat/completions"),
            .open
        )
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(
                forMethod: "POST", routePath: "/v1/chat/completions"
            ),
            .protected(permission: .inference)
        )
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(forMethod: "GET", routePath: "/v1/models"),
            .protected(permission: .informationRead)
        )
    }

    /// Regression: POST /chat/completions (no /v1 prefix) is a real route
    /// that previously fell outside the permission table and was served
    /// WITHOUT verification. It must now fail closed without a proof and
    /// serve normally with a fresh challenge and proof.
    func testBareChatCompletionsPathRequiresProofAndServesWithProof()
        throws {
        let host = try makeAuthorizedHost()
        let body =
            "{\"model\":\"localb-b3-wiring-test\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"

        let bare = "POST /chat/completions HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + body
        let bareResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: bare
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: bareResponse)).contains(" 401 ")
        )

        let (challenge, permission) = try fetchChallenge(
            host, method: "POST", target: "/chat/completions"
        )
        XCTAssertEqual(permission, "P-INFERENCE")
        let authorized = try protectedRequest(
            host,
            method: "POST",
            target: "/chat/completions",
            contentType: "application/json",
            body: body,
            challenge: challenge,
            permission: .inference
        )
        let authorizedResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: authorized
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: authorizedResponse)).contains(" 200 ")
        )
    }

    /// Unknown routes fail closed under the authorized regime — an
    /// explicit denial, never open access and never a bare 404 from the
    /// route switch. Open routes keep serving unauthenticated.
    func testUnknownRoutesFailClosedAndOpenRoutesStayOpen() throws {
        let host = try makeAuthorizedHost()

        let unknown = "GET /v1/nonexistent HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "Connection: close\r\n\r\n"
        let unknownResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: unknown
        )
        let unknownStatus = try XCTUnwrap(statusLine(of: unknownResponse))
        XCTAssertTrue(unknownStatus.contains(" 403 "), "got: \(unknownStatus)")
        XCTAssertTrue(
            String(
                decoding: unknownResponse ?? Data(), as: UTF8.self
            ).contains("LOCALB_ROUTE_UNKNOWN")
        )

        let health = "GET /health HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "Connection: close\r\n\r\n"
        let healthResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: health
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: healthResponse)).contains(" 200 ")
        )

        let preflight = "OPTIONS /v1/chat/completions HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "Origin: https://example.test\r\n"
            + "Access-Control-Request-Method: POST\r\n"
            + "Connection: close\r\n\r\n"
        let preflightResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: preflight
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: preflightResponse))
                .contains(" 204 ")
        )
    }

    // MARK: - Default host resolution (LOCALBHostRuntime wiring)

    /// Environment of an ACTIVATED LOCALB host exactly as production
    /// startup finds one: first-run ceremony → operator checkpoint
    /// persisted outside the registry → one paired ACTIVE client. No
    /// server is started here; callers exercise their own construction
    /// site through LOCALBHostRuntime.applyDefault.
    private struct BootstrapHostEnvironment {
        let hostDirectory: URL
        let keychain: LOCALBKeychainSignerStore
        let transport: LOCALBTransportIdentityStore
        let spkiHex: String
        let clientKey: Curve25519.Signing.PrivateKey
        let clientKeyID: String
    }

    private func makeBootstrapHostEnvironment() throws
        -> BootstrapHostEnvironment {
        let hostDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-b3-boothost-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: hostDirectory)
        }

        let keychain = LOCALBKeychainSignerStore(
            service: "com.simigo.tests.localb-boot.\(UUID().uuidString)",
            account: "signing-key-v1")
        let transport = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-boot.\(UUID().uuidString)",
            account: "tls")
        addTeardownBlock { transport.deleteAll() }

        let registryRoot = LOCALBHostRuntime.registryRoot(in: hostDirectory)
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: registryRoot,
            keychainStore: keychain,
            transportIdentityStore: transport
        )
        _ = try LOCALBHostBootstrap.activateInitialSetup(
            rootURL: registryRoot,
            operatorRecordedCheckpoint: pending.checkpoint,
            keychainStore: keychain,
            transportIdentityStore: transport
        )
        // The activation ceremony records the trusted checkpoint OUTSIDE
        // the registry; ordinary startup consumes it read-only.
        try LOCALBHostRuntime.persistTrustedCheckpoint(
            pending.checkpoint, in: hostDirectory)

        guard case .operational(let context) =
            try LOCALBHostRuntime.resolveOperational(
                hostDirectory: hostDirectory,
                keychainStore: keychain,
                transportIdentityStore: transport
            )
        else {
            throw NSError(
                domain: "LOCALBRequestAuthWiringTests", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "expected an operational host after activation"
                ])
        }

        // Full interactive pairing of one ACTIVE client into the verified
        // registry, exactly like the explicit-injection fixture.
        let coordinator = context.pairingCoordinator()
        var checkpoint = try context.currentTrustedCheckpoint()
        let presentation = try coordinator.issueCredential(
            scopeLabel: "B3 default-path client",
            tlsSPKIHash: pending.transportSPKIHashHex,
            srsKeyID: context.signerKeyID,
            checkpoint: checkpoint
        )
        let secret = try LOCALBPairingSubmission.decodeSecretBase64URL(
            presentation.takeSecretBase64URLOnce()
        )
        let clientKey = Curve25519.Signing.PrivateKey()
        let pop = try LOCALBPairingProofV1.sign(
            credentialID: presentation.credentialID,
            sessionNonce: try XCTUnwrap(
                HTTPServer.decodeLowerHex(presentation.sessionNonceHex)
            ),
            hostInstanceID: presentation.hostInstanceID,
            tlsSPKIHash: presentation.tlsSPKIHash,
            srsKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion,
            with: clientKey
        )
        let submission = LOCALBPairingSubmission(
            credentialID: presentation.credentialID,
            secretRaw: secret,
            clientPublicKeyRaw: Array(clientKey.publicKey.rawRepresentation),
            proofSignatureRaw: pop,
            actualTLSSPKIHash: presentation.tlsSPKIHash,
            presentedSRSKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion
        )
        let pendingPairing = try coordinator.preparePairing(
            submission, checkpoint: checkpoint
        )
        checkpoint = try coordinator.approveAndRegister(
            pendingPairing,
            operatorApproved: true,
            operatorAuthorizationReference: "B3-DEFAULT-PATH",
            checkpoint: checkpoint
        )
        let clientKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )

        return BootstrapHostEnvironment(
            hostDirectory: hostDirectory,
            keychain: keychain,
            transport: transport,
            spkiHex: pending.transportSPKIHashHex,
            clientKey: clientKey,
            clientKeyID: clientKeyID
        )
    }

    /// Ordinary product startup (no explicit injection): an activated host
    /// yields transport identity AND request authorization from one
    /// verified context, and a paired client serves through the full
    /// challenge → proof → dispatch flow.
    func testDefaultHostResolutionServesAuthorizedRequests() throws {
        let environment = try makeBootstrapHostEnvironment()
        let port = randomPort()
        let server = makeServer(port: port)
        try LOCALBHostRuntime.applyDefault(
            to: server,
            bindHost: "127.0.0.1",
            hostDirectory: environment.hostDirectory,
            keychainStore: environment.keychain,
            transportIdentityStore: environment.transport
        )
        try server.start()
        addTeardownBlock { server.stop() }

        let host = Host(
            port: port,
            plaintextCompatPort: 0,
            spkiHex: environment.spkiHex,
            clientKey: environment.clientKey,
            clientKeyID: environment.clientKeyID
        )

        let (challenge, permission) = try fetchChallenge(
            host, method: "GET", target: "/v1/models"
        )
        XCTAssertEqual(permission, "P-INFO-READ")
        let models = try protectedRequest(
            host,
            method: "GET",
            target: "/v1/models",
            contentType: nil,
            body: "",
            challenge: challenge,
            permission: .informationRead
        )
        XCTAssertTrue(
            try XCTUnwrap(
                statusLine(
                    of: sendRequest(
                        port: host.port, spkiHex: host.spkiHex,
                        request: models
                    )
                )
            ).contains(" 200 ")
        )

        let (chatChallenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        let chatBody =
            "{\"model\":\"localb-b3-wiring-test\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
        let chat = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions",
            contentType: "application/json",
            body: chatBody,
            challenge: chatChallenge,
            permission: .inference
        )
        XCTAssertTrue(
            try XCTUnwrap(
                statusLine(
                    of: sendRequest(
                        port: host.port, spkiHex: host.spkiHex,
                        request: chat
                    )
                )
            ).contains(" 200 ")
        )
    }

    /// Before first-run activation the default path NEVER opens protected
    /// routes: without a transport identity startup fails closed, and with
    /// a TLS identity but no activated host, protected routes answer 503
    /// while open routes keep serving.
    func testDefaultHostResolutionFailsClosedBeforeActivation() throws {
        let hostDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-b3-unactivated-\(UUID().uuidString)",
                isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: hostDirectory)
        }
        let keychain = LOCALBKeychainSignerStore(
            service: "com.simigo.tests.localb-unactivated.\(UUID().uuidString)",
            account: "signing-key-v1")
        let transport = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-unactivated.\(UUID().uuidString)",
            account: "tls")
        addTeardownBlock { transport.deleteAll() }

        // No transport identity at all: notInitialized + failClosed
        // transport decision → start() throws.
        let server1 = makeServer(port: randomPort())
        try LOCALBHostRuntime.applyDefault(
            to: server1,
            bindHost: "127.0.0.1",
            hostDirectory: hostDirectory,
            keychainStore: keychain,
            transportIdentityStore: transport
        )
        XCTAssertThrowsError(try server1.start())

        // TLS identity present but host NOT activated: transport-only
        // secure mode. Protected routes fail closed 503; /health serves.
        let identity = try transport.loadOrCreate()
        let port = randomPort()
        let server2 = makeServer(port: port)
        try LOCALBHostRuntime.applyDefault(
            to: server2,
            bindHost: "127.0.0.1",
            hostDirectory: hostDirectory,
            keychainStore: keychain,
            transportIdentityStore: transport
        )
        try server2.start()
        addTeardownBlock { server2.stop() }

        let health = "GET /health HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(port)\r\n"
            + "Connection: close\r\n\r\n"
        XCTAssertTrue(
            try XCTUnwrap(
                statusLine(
                    of: sendRequest(
                        port: port, spkiHex: identity.spkiSHA256Hex,
                        request: health
                    )
                )
            ).contains(" 200 ")
        )

        let protectedRoute = "GET /v1/models HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(port)\r\n"
            + "Connection: close\r\n\r\n"
        XCTAssertTrue(
            try XCTUnwrap(
                statusLine(
                    of: sendRequest(
                        port: port, spkiHex: identity.spkiSHA256Hex,
                        request: protectedRoute
                    )
                )
            ).contains(" 503 ")
        )
    }

    /// A loopback recording upstream: records each request line and always
    /// answers 200 with a fixed JSON body.
    private final class RecordingUpstream: @unchecked Sendable {
        let listener: NWListener
        private let lock = NSLock()
        private var recordedLines: [String] = []
        private(set) var port: UInt16 = 0

        var requestLines: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedLines
        }

        static func start() throws -> RecordingUpstream {
            let listener = try NWListener(using: .tcp)
            let upstream = RecordingUpstream(listener: listener)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    ready.signal()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: DispatchQueue.global())
                connection.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: 65_536
                ) { data, _, _, _ in
                    if let data,
                       let text = String(data: data, encoding: .utf8),
                       let line = text.components(separatedBy: "\r\n").first {
                        upstream.lock.lock()
                        upstream.recordedLines.append(line)
                        upstream.lock.unlock()
                        let body = "{\"ok\":true}"
                        let response =
                            "HTTP/1.1 200 OK\r\n"
                            + "Content-Type: application/json\r\n"
                            + "Content-Length: \(body.utf8.count)\r\n"
                            + "Connection: close\r\n\r\n\(body)"
                        connection.send(
                            content: Data(response.utf8),
                            completion: .contentProcessed { _ in
                                connection.cancel()
                            }
                        )
                    } else {
                        connection.cancel()
                    }
                }
            }
            listener.start(queue: DispatchQueue(label: "recording-upstream"))
            _ = ready.wait(timeout: .now() + 5)
            upstream.port = listener.port?.rawValue ?? 0
            guard upstream.port != 0 else {
                throw NSError(
                    domain: "LOCALBRequestAuthWiringTests", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "recording upstream failed to start"
                    ])
            }
            return upstream
        }

        func stop() {
            listener.cancel()
        }

        private init(listener: NWListener) {
            self.listener = listener
        }
    }

    /// The remote-proxy entry (RemoteOpenAIRuntime) starts through the
    /// SAME default host resolution, and the upstream request carries the
    /// exact SIGNED request target — path AND query. The signed request
    /// and the actually-forwarded request cannot diverge.
    func testRemoteProxyDefaultPathForwardsSignedQueryToUpstream()
        async throws {
        let upstream = try RecordingUpstream.start()
        addTeardownBlock { upstream.stop() }

        let environment = try makeBootstrapHostEnvironment()
        let runtime = RemoteOpenAIRuntime(
            configuration: CloudBackendConfiguration(
                baseURLString: "http://127.0.0.1:\(upstream.port)",
                model: ""
            ),
            apiKey: "test-key"
        )
        let port = randomPort()
        defer { Task.detached { await runtime.stop() } }
        try await runtime.startWithLOCALB(
            ModelInfo(path: "cloud", kind: .cloudOpenAI),
            port: Int(port),
            localbHostDirectory: environment.hostDirectory,
            keychainStore: environment.keychain,
            transportIdentityStore: environment.transport
        )

        let host = Host(
            port: port,
            plaintextCompatPort: 0,
            spkiHex: environment.spkiHex,
            clientKey: environment.clientKey,
            clientKeyID: environment.clientKeyID
        )

        let body =
            "{\"model\":\"cloud\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
        let (challenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions?trace=1"
        )
        let request = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions?trace=1",
            contentType: "application/json",
            body: body,
            challenge: challenge,
            permission: .inference
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 200 "), "got: \(status)")

        // The upstream received the exact signed target, query included.
        let upstreamLine = try XCTUnwrap(upstream.requestLines.first)
        XCTAssertEqual(
            upstreamLine, "POST /v1/chat/completions?trace=1 HTTP/1.1",
            "upstream request line must carry the signed query"
        )
    }
}
