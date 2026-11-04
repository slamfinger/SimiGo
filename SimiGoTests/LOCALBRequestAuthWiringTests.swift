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
final class LOCALBRequestAuthWiringTests: LOCALBTestCase {

    /// TLS / fail-closed intent requires a dedicated secure-mode process;
    /// loopback defaults to plaintext otherwise (owner ruling 2026-10-26).
    private func requireSecureTransportPrecondition() {
        XCTAssertEqual(
            ProcessInfo.processInfo.environment["SIMIGO_TRANSPORT"]?
                .lowercased(),
            "secure",
            "TLS/fail-closed test requires a dedicated SIMIGO_TRANSPORT=secure process"
        )
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
        // Owner ruling 2026-10-26: the explicit plaintext compatibility
        // listener is the local developer/tool surface; protected routes
        // are served there without the proof ceremony. The invariant that
        // still holds is the marking — such responses must never claim TLS.
        let response = sendRequest(
            port: host.plaintextCompatPort, spkiHex: nil, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 200 "), "got: \(status)")
        let raw = try XCTUnwrap(
            response.flatMap { String(data: $0, encoding: .utf8) }
        ).lowercased()
        XCTAssertTrue(
            raw.contains("x-simigo-protection: unprotected-by-localb"),
            "plaintext compat response must be marked unprotected: \(raw)"
        )
        XCTAssertFalse(
            raw.contains("x-simigo-protection: localb-tls"),
            "plaintext compat response must never claim TLS: \(raw)"
        )
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

    /// Ordinary product startup (no explicit injection): an activated host
    /// yields transport identity AND request authorization from one
    /// verified context, and a paired client serves through the full
    /// challenge → proof → dispatch flow.
    func testDefaultHostResolutionServesAuthorizedRequests() throws {
        requireSecureTransportPrecondition()
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
        requireSecureTransportPrecondition()
        let hostDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-b3-unactivated-\(UUID().uuidString)",
                isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: hostDirectory)
        }
        let keychainRoot = hostDirectory
            .appendingPathComponent("keychains", isDirectory: true)
        let signerKeychainPath = keychainRoot
            .appendingPathComponent("production-signer.keychain-db").path
        let transportKeychainPath = keychainRoot
            .appendingPathComponent("transport-identity.keychain-db").path
        let keychain = LOCALBKeychainSignerStore(
            service: "com.simigo.tests.localb-unactivated.\(UUID().uuidString)",
            account: "signing-key-v1",
            keychainPath: signerKeychainPath)
        let transport = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-unactivated.\(UUID().uuidString)",
            account: "tls",
            keychainPath: transportKeychainPath)
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
        LOCALBTestIsolation.assertKeychainLanded(
            transport.keychainPath, expected: transportKeychainPath)
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

}
