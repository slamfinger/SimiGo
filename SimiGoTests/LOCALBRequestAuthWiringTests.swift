import CryptoKit
import Foundation
import LOCALBCore
import Network
import Security
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
    /// Owner ruling 2026-11-05 (S2): a client holding only the pairing
    /// default permissions is refused at the CORRECT stage for every branch
    /// target — the registry validation inside challenge issuance (400
    /// permissionDenied, before any ledger consumption) — and a well-formed
    /// dispatch attempt over a branch target dies at challenge consumption
    /// (401), never reaching the branch handlers. Ordinary inference keeps
    /// its authorized behavior.
    func testLANInformationReadRoutesRequireRealTLSProofAndReachDispatch() throws {
        let host = try makeAuthorizedHost()
        let routes = [
            ("GET", "/v1/simigo/env"),
            ("GET", "/v1/simigo/roots"),
            ("GET", "/v1/simigo/is/status"),
        ]

        for (method, target) in routes {
            let noProof = "\(method) \(target) HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(host.port)\r\n"
                + "Connection: close\r\n\r\n"
            let refused = sendRequest(
                port: host.port, spkiHex: host.spkiHex, request: noProof)
            XCTAssertTrue(
                try XCTUnwrap(statusLine(of: refused)).contains(" 401 "),
                "\(method) \(target) must reject a TLS peer without LOCALB proof")

            let (challenge, permission) = try fetchChallenge(
                host, method: method, target: target)
            XCTAssertEqual(permission, LOCALBPermission.informationRead.rawValue)
            let authorized = try protectedRequest(
                host, method: method, target: target, contentType: nil, body: "",
                challenge: challenge, permission: .informationRead)
            let response = sendRequest(
                port: host.port, spkiHex: host.spkiHex, request: authorized)
            let status = try XCTUnwrap(statusLine(of: response))
            XCTAssertFalse(
                status.contains(" 401 "),
                "\(method) \(target) with P-INFO-READ must pass request authorization; got \(status)")
        }
    }

    func testSearchAndRootMutationRoutesRejectNoProofOverRealTLS() throws {
        let host = try makeAuthorizedHost()
        let requests: [(method: String, target: String, body: String)] = [
            ("GET", "/v1/simigo/search?q=proof-boundary", ""),
            ("POST", "/v1/simigo/search", ""),
            ("PUT", "/v1/simigo/roots", ""),
            ("POST", "/v1/simigo/roots", ""),
        ]

        for item in requests {
            let contentType = item.body.isEmpty ? "" : "Content-Type: application/json\r\n"
            let noProof = "\(item.method) \(item.target) HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(host.port)\r\n"
                + contentType
                + "Content-Length: \(item.body.utf8.count)\r\n"
                + "Connection: close\r\n\r\n"
                + item.body
            let response = sendRequest(
                port: host.port, spkiHex: host.spkiHex, request: noProof)
            let status = try XCTUnwrap(statusLine(of: response))
            XCTAssertTrue(
                status.contains(" 401 "),
                "\(item.method) \(item.target) must reject a TLS peer without LOCALB proof; got \(status)")

            // P-SRS-WRITE is host-owned and intentionally absent from the
            // paired-client grant set. The public TLS challenge path must not
            // issue a proof that the registry cannot authorize.
            let challengeBody = "{\"method\":\"\(item.method)\","
                + "\"requestTarget\":\"\(item.target)\"}"
            let challengeRequest = "POST /localb/auth/challenge HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(host.port)\r\n"
                + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(challengeBody.utf8.count)\r\n"
                + "Connection: close\r\n\r\n" + challengeBody
            let challengeResponse = sendRequest(
                port: host.port, spkiHex: host.spkiHex, request: challengeRequest)
            let challengeStatus = try XCTUnwrap(statusLine(of: challengeResponse))
            XCTAssertTrue(
                challengeStatus.contains(" 400 "),
                "P-SRS-WRITE is not delegable to paired LAN clients; got \(challengeStatus)")
        }
    }

    func testSlowRequestHeadAndBodyAreClosedAtAbsoluteDeadlines() throws {
        let limits = HTTPServer.RequestLimits(
            maxConnections: 8,
            headerTimeout: .milliseconds(250),
            bodyTimeout: .milliseconds(250))
        let host = try makeAuthorizedHost(requestLimits: limits)

        let slowHead = try openPinnedTLSConnection(host)
        try sendPartialBytes(
            "GET /v1/models HTTP/1.1\r\nHost: 127.0.0.1\r\n",
            over: slowHead)
        assertPeerClosed(slowHead, timeout: 3)

        let slowBody = try openPinnedTLSConnection(host)
        let partialBodyRequest =
            "POST /v1/simigo/search HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: 128\r\n"
            + "Connection: close\r\n\r\n"
            + "{"
        try sendPartialBytes(partialBodyRequest, over: slowBody)
        assertPeerClosed(slowBody, timeout: 3)
        waitForConnectionSnapshot(
            try XCTUnwrap(host.server), active: 0, refusedOverCap: 0)
    }

    func testConnectionCapRefusesExcessAndReleasesIncompleteRequestSlots() throws {
        let limits = HTTPServer.RequestLimits(
            maxConnections: 2,
            headerTimeout: .seconds(30),
            bodyTimeout: .seconds(30))
        let host = try makeAuthorizedHost(requestLimits: limits)
        let server = try XCTUnwrap(host.server)

        // Capacity is observed through the server's admission accounting,
        // never through client TLS state: an over-cap peer may sit in
        // .waiting/.preparing without surfacing a reset, which proves nothing
        // about whether the server spent a slot on it.
        let first = try openPinnedTLSConnection(host)
        let second = try openPinnedTLSConnection(host)
        waitForConnectionSnapshot(server, active: 2, refusedOverCap: 0)

        // Keep both accepted sockets inside the real header-read path, so the
        // later disconnect is an incomplete-request disconnect rather than an
        // idle-socket teardown.
        let partialHead = "GET /v1/models HTTP/1.1\r\nHost: 127.0.0.1:\(host.port)\r\n"
        try sendPartialBytes(partialHead, over: first)
        try sendPartialBytes(partialHead, over: second)

        let excess = startPinnedTLSConnection(host)
        waitForConnectionSnapshot(server, active: 2, refusedOverCap: 1)
        excess.cancel()

        // The decisive check: a peer that vanished mid-header must return its
        // slot, or the cap converts one aborted request into permanent
        // capacity loss. Prove reuse by admitting a replacement afterwards.
        first.cancel()
        waitForConnectionSnapshot(server, active: 1, refusedOverCap: 1)
        let replacement = try openPinnedTLSConnection(host)
        waitForConnectionSnapshot(server, active: 2, refusedOverCap: 1)
        try sendPartialBytes(partialHead, over: replacement)

        server.stop()
        waitForConnectionSnapshot(
            server,
            active: 0,
            refusedOverCap: 1,
            timeout: 0.5,
            message: "stop must synchronously release every accepted slot")
        second.cancel()
        replacement.cancel()
    }

    private func openPinnedTLSConnection(
        _ host: LOCALBTestCase.Host
    ) throws -> NWConnection {
        let connection = startPinnedTLSConnection(host)
        let ready = expectation(description: "pinned TLS connection ready")
        let stateLock = NSLock()
        var fulfilled = false
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            stateLock.lock()
            let shouldFulfill = !fulfilled
            fulfilled = true
            stateLock.unlock()
            if shouldFulfill { ready.fulfill() }
        }
        // A connection can already be ready before the handler is installed.
        if case .ready = connection.state {
            stateLock.lock()
            let shouldFulfill = !fulfilled
            fulfilled = true
            stateLock.unlock()
            if shouldFulfill { ready.fulfill() }
        }
        wait(for: [ready], timeout: 5)
        return connection
    }

    /// Starts a pinned TLS socket without waiting for any state: the caller
    /// observes capacity on the server, where admission is decided.
    private func startPinnedTLSConnection(
        _ host: LOCALBTestCase.Host
    ) -> NWConnection {
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
                complete(hex == host.spkiHex)
            },
            DispatchQueue.global())

        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: host.port)!,
            using: NWParameters(tls: options))
        connection.start(queue: DispatchQueue.global())
        return connection
    }

    private func sendPartialBytes(_ request: String, over connection: NWConnection) throws {
        let sent = expectation(description: "partial request bytes sent")
        connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
            XCTAssertNil(error)
            sent.fulfill()
        })
        wait(for: [sent], timeout: 3)
    }

    private func assertPeerClosed(
        _ connection: NWConnection,
        timeout: TimeInterval
    ) {
        let closed = expectation(description: "server closed incomplete connection")
        let stateLock = NSLock()
        var fulfilled = false
        func fulfillClosed() {
            stateLock.lock()
            let shouldFulfill = !fulfilled
            fulfilled = true
            stateLock.unlock()
            if shouldFulfill { closed.fulfill() }
        }

        // An excess socket can reach TLS ready and then be reset; some Network
        //.framework releases report that as a connection state transition,
        // others as a receive error/EOF. Accept either actual peer-close signal.
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                fulfillClosed()
            default:
                break
            }
        }
        if case .failed = connection.state { fulfillClosed() }
        if case .cancelled = connection.state { fulfillClosed() }
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 1
        ) { _, _, isComplete, error in
            if error != nil || isComplete {
                fulfillClosed()
            }
        }
        wait(for: [closed], timeout: timeout)
        connection.cancel()
    }

    private func waitForConnectionSnapshot(
        _ server: HTTPServer,
        active: Int,
        refusedOverCap: Int,
        timeout: TimeInterval = 3,
        message: @autoclosure () -> String = ""
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var snapshot = server.connectionSnapshot()
        while Date() < deadline {
            snapshot = server.connectionSnapshot()
            if snapshot.active == active,
               snapshot.refusedOverCap == refusedOverCap {
                return
            }
            // This module defaults to MainActor isolation, so slot release
            // runs on the main actor. Blocking the main thread with
            // Thread.sleep would starve terminate() and make a healthy
            // release look like a leak; spin the run loop instead.
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(
            snapshot,
            HTTPServer.ConnectionSnapshot(
                active: active,
                refusedOverCap: refusedOverCap),
            message())
    }

    func testBranchOperationsRequireBranchControlPermission() throws {
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
                status.contains(" 400 "),
                "\(target) challenge: expected 400, got: \(status)"
            )
            let json = try XCTUnwrap(jsonBody(of: response))
            let bodyText = String(
                decoding: try XCTUnwrap(JSONSerialization.data(
                    withJSONObject: json
                )), as: UTF8.self
            )
            XCTAssertTrue(
                bodyText.lowercased().contains("denied"),
                "\(target) challenge: expected the registry-stage "
                    + "permission denial, got: \(bodyText.prefix(300))"
            )
        }

        // Dispatch-stage: a well-formed proof over a branch target cannot
        // even reach verification with a usable challenge — the challenge
        // consumption gate refuses (401) and the branch handlers never run.
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
                status.contains(" 401 "),
                "\(target) dispatch: expected 401, got: \(status)"
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

    /// The route-policy table maps branch operations to the dedicated
    /// P-BRANCH-CONTROL permission — protected, distinct from open, from
    /// P-INFERENCE, and from the previous explicit denial.
    func testRoutePolicyProtectsBranchOperationsWithBranchControl() {
        for target in [
            "/v1/branches/fork",
            "/v1/branches/delete",
            "/v1/branches/list",
        ] {
            XCTAssertEqual(
                HTTPServer.localbRoutePolicy(
                    forMethod: "POST", routePath: target
                ),
                .protected(permission: .branchControl)
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

    // MARK: - S2: plaintext allowlist and permission independence
    // (owner ruling 2026-11-05)

    /// The plaintext compatibility surface must NOT serve branch
    /// operations: without a proof the request falls through the (removed)
    /// blanket exemption into the proof ceremony and dies at challenge
    /// consumption (401) — the branch handlers never run, so no response
    /// can carry a branch result.
    func testPlaintextBranchOperationsWithoutProofAreRejected() throws {
        let host = try makeAuthorizedHost()
        for target in [
            "/v1/branches/fork",
            "/v1/branches/delete",
            "/v1/branches/list",
        ] {
            let request = "POST \(target) HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(host.plaintextCompatPort)\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(("{\"session_id\":\"s\"}").utf8.count)\r\n"
                + "Connection: close\r\n\r\n{\"session_id\":\"s\"}"
            let response = sendRequest(
                port: host.plaintextCompatPort, spkiHex: nil, request: request
            )
            let status = try XCTUnwrap(statusLine(of: response))
            // Header-less plaintext dies pre-ceremony (403, unauthenticated);
            // with LOCALB headers but no proof it dies at challenge
            // consumption (401). Both are refusals at an authorization
            // stage; neither is service, and neither is a blanket pass.
            let refused = status.contains(" 401 ") || status.contains(" 403 ")
            XCTAssertTrue(
                refused,
                "\(target) plaintext: expected 401/403 (proof ceremony "
                    + "required), got: \(status)"
            )
            let text = String(decoding: response ?? Data(), as: UTF8.self)
            XCTAssertFalse(
                status.contains(" 200 "),
                "\(target) plaintext must never serve a branch result: "
                    + "\(status)"
            )
            XCTAssertFalse(
                text.lowercased().contains("\"ok\""),
                "\(target) plaintext must never serve a branch result"
            )
        }
    }

    /// The compatibility surface keeps serving inference without a proof
    /// (2026-10-26 behavior, unchanged by S2).
    func testPlaintextInferenceStaysCompatibleWithoutProof() throws {
        let host = try makeAuthorizedHost()
        let body =
            "{\"model\":\"localb-b3-wiring-test\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
        let request = "POST /v1/chat/completions HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.plaintextCompatPort)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + body
        let response = sendRequest(
            port: host.plaintextCompatPort, spkiHex: nil, request: request
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: response)).contains(" 200 ")
        )
    }

    /// A client holding ONLY P-BRANCH-CONTROL: branch operations run the
    /// full challenge → proof → consume ceremony over TLS and serve, while
    /// generation is refused at challenge issuance (registry-stage
    /// permission denial). Proves both directions of the independence.
    func testBranchControlOnlyClientServesBranchAndRefusesGeneration() throws {
        let host = try makeAuthorizedHost()
        let coordinator = try XCTUnwrap(host.coordinator)
        let checkpointBox = try XCTUnwrap(host.trustedCheckpoint)
        let changed = try coordinator.setClientPermissions(
            clientKeyID: host.clientKeyID,
            permissions: [.branchControl],
            reason: "S2 branchControl-only fixture",
            checkpoint: checkpointBox.value
        )
        checkpointBox.value = changed

        // Branch challenge over TLS: issued, bound to P-BRANCH-CONTROL.
        let (challengeHex, challengePermission) = try fetchChallenge(
            host, method: "POST", target: "/v1/branches/list"
        )
        XCTAssertEqual(
            challengePermission, "P-BRANCH-CONTROL",
            "the branch challenge must bind the dedicated permission"
        )

        // Full ceremony over TLS → the branch handler serves.
        let request = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/branches/list",
            contentType: "application/json",
            body: "{\"session_id\":\"s\"}",
            challenge: challengeHex,
            permission: .branchControl
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(
            status.contains(" 200 "),
            "branch dispatch with valid proof: expected 200, got: \(status)"
        )
        let json = try XCTUnwrap(jsonBody(of: response))
        XCTAssertEqual(json["ok"] as? Bool, true, "branch list must serve")

        // Generation is refused for this client at challenge issuance.
        let generationBody =
            "{\"method\":\"POST\",\"requestTarget\":\"/v1/chat/completions\"}"
        let generationRequest =
            "POST /localb/auth/challenge HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(generationBody.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + generationBody
        let generationResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: generationRequest
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: generationResponse)).contains(" 400 "),
            "generation must be refused at challenge issuance"
        )
        // Stage evidence by contrast: the SAME registry state just issued a
        // branchControl challenge (200 above), so this 400 is the
        // permission check refusing generation — not an availability fault.
    }

    /// Dispatch-stage independence: an inference-bound challenge and proof
    /// cannot authorize a branch target — the canonical-permission match in
    /// the verification gate rejects before the branch handlers run.
    func testInferenceChallengeCannotAuthorizeBranchTarget() throws {
        let host = try makeAuthorizedHost()
        let (challenge, _) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        let request = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/branches/list",
            contentType: "application/json",
            body: "{\"session_id\":\"s\"}",
            challenge: challenge,
            permission: .inference
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(
            status.contains(" 401 "),
            "expected 401 for an inference proof on a branch target, "
                + "got: \(status)"
        )
        XCTAssertFalse(
            status.contains(" 200 "),
            "branch result must never be served on an inference proof"
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
