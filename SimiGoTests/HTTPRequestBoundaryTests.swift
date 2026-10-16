import Foundation
import Network
import XCTest

@testable import SimiGo

/// LOCALB B3 product parser-boundary tests (product parser gate, step 1).
///
/// The parser must preserve the exact method token and the exact origin-form
/// request target, reject duplicate headers instead of overwriting them, and
/// accept Content-Length framing only. Pure-parser cases exercise the single
/// interpretation point directly; raw-socket cases prove the rejections
/// surface as real HTTP error responses from a real listener.
///
/// These cover the parser gate only. Query-bound signature mismatch, exact
/// body-byte dispatch, and trusted-TLS-context denial belong to the B3 wiring
/// gate and are intentionally NOT claimed here.
final class HTTPRequestBoundaryTests: XCTestCase {

    // MARK: - Helpers

    private func parse(
        _ head: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HTTPServer.HTTPRequestHeadParser.Head {
        try HTTPServer.HTTPRequestHeadParser.parse(head)
    }

    private func assertBadRequest(
        _ head: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try HTTPServer.HTTPRequestHeadParser.parse(head),
            file: file,
            line: line
        ) { error in
            guard case HTTPServer.HTTPServerError.badRequest = error else {
                return XCTFail(
                    "expected badRequest, got \(error)",
                    file: file,
                    line: line
                )
            }
        }
    }

    // MARK: - Method token preserved exactly

    func testCanonicalMethodIsPreservedVerbatim() throws {
        let head = try parse(
            "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n"
        )
        XCTAssertEqual(head.method, "POST")
    }

    func testLowercaseMethodIsRejectedNotUppercased() {
        assertBadRequest("get /health HTTP/1.1\r\nHost: 127.0.0.1\r\n")
    }

    func testMixedCaseMethodIsRejected() {
        assertBadRequest("Get /health HTTP/1.1\r\nHost: 127.0.0.1\r\n")
        assertBadRequest("gEt /health HTTP/1.1\r\nHost: 127.0.0.1\r\n")
    }

    func testMethodWithIllegalCharactersIsRejected() {
        assertBadRequest("GET;X /health HTTP/1.1\r\nHost: 127.0.0.1\r\n")
        assertBadRequest("GET\\x /health HTTP/1.1\r\nHost: 127.0.0.1\r\n")
    }

    func testOverlongMethodTokenIsRejected() {
        let longMethod = String(repeating: "A", count: 17)
        assertBadRequest(
            "\(longMethod) /health HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        )
    }

    // MARK: - Exact origin-form target preserved

    func testTargetWithQueryIsPreservedExactlyAndPathDerivedOnce() throws {
        let head = try parse(
            "GET /v1/inference?model=alpha&trace=1 HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        )
        XCTAssertEqual(head.requestTarget, "/v1/inference?model=alpha&trace=1")
        XCTAssertEqual(head.path, "/v1/inference")
    }

    func testEmptyQueryIsDistinctFromAbsentQuery() throws {
        let emptyQuery = try parse(
            "GET /v1/inference? HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        )
        XCTAssertEqual(emptyQuery.requestTarget, "/v1/inference?")
        XCTAssertEqual(emptyQuery.path, "/v1/inference")

        let absentQuery = try parse(
            "GET /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        )
        XCTAssertEqual(absentQuery.requestTarget, "/v1/inference")
        XCTAssertEqual(absentQuery.path, "/v1/inference")

        // Same route path, different exact targets: the foundation for
        // query-bound request proofs in the B3 wiring gate.
        XCTAssertNotEqual(emptyQuery.requestTarget, absentQuery.requestTarget)
        XCTAssertEqual(emptyQuery.path, absentQuery.path)
    }

    func testAbsoluteFormTargetIsRejected() {
        assertBadRequest(
            "GET http://127.0.0.1/health HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        )
    }

    func testTargetWithFragmentIsRejected() {
        assertBadRequest("GET /health#frag HTTP/1.1\r\nHost: 127.0.0.1\r\n")
    }

    func testTargetWithControlCharacterIsRejected() {
        assertBadRequest(
            "GET /health?\ttrace=1 HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        )
    }

    func testOversizedTargetIsRejected() {
        let longTarget = "/" + String(repeating: "a", count: 8_192)
        XCTAssertThrowsError(
            try parse(
                "GET \(longTarget) HTTP/1.1\r\nHost: 127.0.0.1\r\n"
            )
        ) { error in
            guard case HTTPServer.HTTPServerError.payloadTooLarge = error
            else {
                return XCTFail("expected payloadTooLarge, got \(error)")
            }
        }
    }

    // MARK: - Duplicate headers rejected, never overwritten

    func testExactCaseDuplicateHeaderIsRejected() {
        assertBadRequest(
            "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "X-Trace: 1\r\nX-Trace: 2\r\n"
        )
    }

    func testCaseVariantDuplicateHeaderIsRejected() {
        assertBadRequest(
            "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "X-Trace: 1\r\nx-trace: 2\r\n"
        )
    }

    func testCaseVariantDuplicateHostIsRejected() {
        // Previously "host: b" silently overwrote "Host: a".
        assertBadRequest(
            "GET /health HTTP/1.1\r\nHost: a.example\r\nhost: b.example\r\n"
        )
    }

    func testConflictingDuplicateContentLengthIsRejected() {
        // Previously the last value (7) silently won.
        assertBadRequest(
            "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "Content-Length: 5\r\nContent-Length: 7\r\n"
        )
    }

    func testMalformedHeaderNameIsRejected() {
        assertBadRequest(
            "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nBad Name: v\r\n"
        )
        assertBadRequest(
            "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n : v\r\n"
        )
    }

    func testControlCharacterInHeaderValueIsRejected() {
        assertBadRequest(
            "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "X-Trace: a\u{01}b\r\n"
        )
    }

    // MARK: - Body framing: Content-Length only

    func testTransferEncodingIsRejectedEvenWhenEmpty() {
        XCTAssertThrowsError(
            try parse(
                "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                    + "Transfer-Encoding: \r\nContent-Length: 0\r\n"
            )
        ) { error in
            guard case HTTPServer.HTTPServerError.unsupportedTransferEncoding
            = error
            else {
                return XCTFail(
                    "expected unsupportedTransferEncoding, got \(error)"
                )
            }
            XCTAssertEqual(
                (error as? HTTPServer.HTTPServerError)?.statusCode,
                501
            )
        }
    }

    func testTransferEncodingChunkedIsRejected() {
        XCTAssertThrowsError(
            try parse(
                "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                    + "Transfer-Encoding: chunked\r\n"
            )
        )
    }

    func testNonDecimalContentLengthIsRejected() {
        assertBadRequest(
            "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "Content-Length: abc\r\n"
        )
        assertBadRequest(
            "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "Content-Length: +5\r\n"
        )
        assertBadRequest(
            "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "Content-Length: 5x\r\n"
        )
        assertBadRequest(
            "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "Content-Length:\r\n"
        )
    }

    func testLeadingZeroContentLengthIsAccepted() throws {
        // RFC 7230 Content-Length is 1*DIGIT; "007" is legal and equals 7.
        // The authoritative length for signing is derived from the actual
        // body bytes, never from this spelling.
        let head = try parse(
            "POST /v1/inference HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                + "Content-Length: 007\r\n"
        )
        XCTAssertEqual(head.contentLength, 7)
    }

    // MARK: - Authority from the single Host

    func testAuthorityComesFromHost() throws {
        let head = try parse(
            "GET /health HTTP/1.1\r\nHost: 127.0.0.1:8443\r\n"
        )
        XCTAssertEqual(head.authority, "127.0.0.1:8443")
    }

    func testHTTP11RequiresHost() {
        assertBadRequest("GET /health HTTP/1.1\r\n")
        assertBadRequest("GET /health HTTP/1.1\r\nHost: \r\n")
    }

    func testHTTP10WithoutHostIsAccepted() throws {
        let head = try parse("GET /health HTTP/1.0\r\n")
        XCTAssertEqual(head.authority, "")
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.requestTarget, "/health")
    }

    // MARK: - Raw-socket cases (real listener, real responses)

    private func randomPort() -> UInt16 {
        UInt16.random(in: 42000...58000)
    }

    private func makeLegacyLoopbackServer() throws -> (HTTPServer, UInt16) {
        let port = randomPort()
        let server = HTTPServer(
            port: Int(port),
            modelId: "parser-boundary-test",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "parser-boundary-test",
                    savedAt: Date(),
                    history: []
                )
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )
        // Loopback plaintext compatibility mode is the only listener that
        // serves plaintext; B1 fail-closed behavior is exercised by the
        // LOCALBTransportWiringTests suite, not here.
        server.configureLOCALBSecurityMode(.legacyPlaintextCompat)
        try server.start()
        addTeardownBlock { server.stop() }
        return (server, port)
    }

    /// Sends raw request bytes over plaintext TCP and returns the first
    /// chunk of the response (nil if the connection failed before any data).
    private func sendRawHTTP(
        port: UInt16,
        request: String,
        timeout: TimeInterval = 5
    ) -> Data? {
        let client = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
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
                    maximumLength: 64 * 1024
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

    func testLowercaseMethodRejectedOnTheWire() throws {
        let (_, port) = try makeLegacyLoopbackServer()
        let response = sendRawHTTP(
            port: port,
            request: "get /health HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 400 "), "got: \(status)")
    }

    func testCaseVariantDuplicateHostRejectedOnTheWire() throws {
        let (_, port) = try makeLegacyLoopbackServer()
        let response = sendRawHTTP(
            port: port,
            request: "GET /health HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\nhost: evil.example\r\n"
                + "Connection: close\r\n\r\n"
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 400 "), "got: \(status)")
    }

    func testTransferEncodingRejectedOnTheWire() throws {
        let (_, port) = try makeLegacyLoopbackServer()
        let response = sendRawHTTP(
            port: port,
            request: "POST /v1/chat/completions HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n"
                + "Connection: close\r\n\r\n"
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 501 "), "got: \(status)")
    }

    func testRouteStillServesPathWithQueryOnTheWire() throws {
        let (_, port) = try makeLegacyLoopbackServer()
        let response = sendRawHTTP(
            port: port,
            request: "GET /health?trace=1 HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 200 "), "got: \(status)")
    }

    // MARK: - Field-name whitespace before the colon (RFC 9112 §5.1)

    /// Whitespace between a header field name and the colon MUST be
    /// rejected. The raw name is validated as a token before case
    /// normalization — illegal whitespace is never trimmed into acceptance.
    func testWhitespaceBeforeHeaderColonIsRejected() throws {
        assertBadRequest(
            "GET /health HTTP/1.1\r\n"
                + "Host : 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        assertBadRequest(
            "POST /v1/chat/completions HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\nContent-Length : 2\r\n"
                + "Connection: close\r\n\r\n{}"
        )
        assertBadRequest(
            "GET /health HTTP/1.1\r\n"
                + "Host\t: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        // Sanity: the exact same heads WITHOUT the pre-colon whitespace
        // still parse, so the rejection is attributable to the whitespace.
        let head = try parse(
            "GET /health HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        XCTAssertEqual(head.headers["host"], "127.0.0.1")
    }

    func testWhitespaceBeforeHeaderColonRejectedOnTheWire() throws {
        let (_, port) = try makeLegacyLoopbackServer()
        let response = sendRawHTTP(
            port: port,
            request: "GET /health HTTP/1.1\r\n"
                + "Host : 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 400 "), "got: \(status)")
    }

    // MARK: - Request-line whitespace (RFC 9112 §3)

    /// The request line is exactly `method SP request-target SP
    /// HTTP-version`. Leading, trailing, doubled, or tab separators are
    /// non-canonical and rejected — never collapsed.
    func testRequestLineWithNonCanonicalWhitespaceIsRejected() throws {
        assertBadRequest("GET  /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        assertBadRequest(" GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        assertBadRequest("GET /health HTTP/1.1 \r\nHost: 127.0.0.1\r\n\r\n")
        assertBadRequest("GET\t/health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        assertBadRequest("GET /health\tHTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        // Sanity: the canonical single-space form still parses.
        let head = try parse(
            "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        )
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.requestTarget, "/health")
    }

    func testDoubledSpaceRequestLineRejectedOnTheWire() throws {
        let (_, port) = try makeLegacyLoopbackServer()
        let response = sendRawHTTP(
            port: port,
            request: "GET  /health HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 400 "), "got: \(status)")
    }
}
