import Foundation
import XCTest

@testable import SimiGo

final class SlotActivityTests: XCTestCase {

    private func activity(_ json: String, status: Int = 200) -> SlotActivity {
        SlotActivityParser.activity(from: Data(json.utf8), statusCode: status)
    }

    /// Payload measured from the locked b11720 binary before it processed a task.
    func testLockedIdleSchemaIsIdle() {
        XCTAssertEqual(
            activity(#"[{"id":0,"n_ctx":4096,"speculative":false,"is_processing":false}]"#),
            .idle)
    }

    /// Payload measured from the locked binary while a request was in flight.
    /// b11720 reports no `state` field in either case.
    func testLockedBusySchemaIsBusy() {
        let json = #"[{"id":0,"n_ctx":4096,"speculative":false,"is_processing":true,"# +
            #""id_task":24,"n_prompt_tokens":1944,"n_prompt_tokens_processed":9,"# +
            #""n_prompt_tokens_cache":1931}]"#
        XCTAssertEqual(activity(json), .busy)
    }

    func testAnyBusySlotMarksTheEngineBusy() {
        XCTAssertEqual(
            activity(#"[{"id":0,"is_processing":false},{"id":1,"is_processing":true}]"#),
            .busy)
    }

    func testAllIdleSlotsAreIdle() {
        XCTAssertEqual(
            activity(#"[{"id":0,"is_processing":false},{"id":1,"is_processing":false}]"#),
            .idle)
    }

    /// The field the old probe read. Without `is_processing` it is neither
    /// idle nor busy: the schema mismatch is surfaced as unknown.
    func testLegacyStateFieldIsUnknown() {
        XCTAssertEqual(activity(#"[{"id":0,"n_ctx":4096,"state":0}]"#), .unknown)
        XCTAssertEqual(activity(#"[{"id":0,"n_ctx":4096,"state":1}]"#), .unknown)
    }

    func testMissingIsProcessingIsUnknown() {
        XCTAssertEqual(
            activity(#"[{"id":0,"n_ctx":4096,"speculative":false}]"#),
            .unknown)
    }

    func testMalformedIsProcessingIsUnknown() {
        XCTAssertEqual(activity(#"[{"id":0,"is_processing":"true"}]"#), .unknown)
        XCTAssertEqual(activity(#"[{"id":0,"is_processing":1}]"#), .unknown)
        XCTAssertEqual(activity(#"[{"id":0,"is_processing":null}]"#), .unknown)
    }

    func testEmptySlotsIsUnknown() {
        XCTAssertEqual(activity("[]"), .unknown)
    }

    func testNonArrayPayloadIsUnknown() {
        XCTAssertEqual(activity(#"{"slots":[]}"#), .unknown)
        XCTAssertEqual(activity(#""idle""#), .unknown)
    }

    func testUnreadablePayloadIsUnknown() {
        XCTAssertEqual(activity("not json"), .unknown)
    }

    func testNon200StatusIsUnknown() {
        XCTAssertEqual(
            activity(#"[{"id":0,"is_processing":false}]"#, status: 503),
            .unknown)
    }

    /// A definitive busy slot outranks a malformed sibling.
    func testBusyOutranksMalformedSibling() {
        XCTAssertEqual(
            activity(#"[{"id":0,"is_processing":"bad"},{"id":1,"is_processing":true}]"#),
            .busy)
    }

    /// The probe must address the engine's loopback port, never the product
    /// listener. This is the wiring assertion the parser tests cannot make.
    func testProbeReadsBusyFromEngineLoopback() async {
        BusySlotsURLProtocol.reset()
        let activity = await GGUFSlotActivityProbe.activity(
            port: 54_321,
            session: probeSession(BusySlotsURLProtocol.self))
        XCTAssertEqual(activity, .busy)
        let request = BusySlotsURLProtocol.recordedRequest()
        XCTAssertEqual(
            request?.url?.absoluteString,
            "http://127.0.0.1:54321/slots")
        XCTAssertEqual(request?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testProbeRequestBypassesURLCache() {
        let request = GGUFSlotActivityProbe.makeRequest(port: 54_323)
        XCTAssertEqual(
            request?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request?.url?.absoluteString, "http://127.0.0.1:54323/slots")
        XCTAssertEqual(request?.timeoutInterval, 1.0)
    }

    func testProbeTreatsMissingEngineEndpointAsUnknown() async {
        MissingSlotsURLProtocol.reset()
        let activity = await GGUFSlotActivityProbe.activity(
            port: 54_322,
            session: probeSession(MissingSlotsURLProtocol.self))
        XCTAssertEqual(activity, .unknown)
    }

    func testResolverPreservesBusyProvider() async {
        let provider = StubSlotActivityProvider(.busy)
        let activity = await SlotActivityResolver.activity(
            for: provider as SlotActivityProviding?)
        XCTAssertEqual(activity, .busy)
    }

    func testHealthCheckPolicySkipsConfirmedBusyPreflightOnly() {
        XCTAssertTrue(GGUFHealthCheckPolicy.shouldSkipPreflight(
            isGGUF: true, isInProcess: false, injectedFailure: false,
            slotActivity: .busy))
        XCTAssertFalse(GGUFHealthCheckPolicy.shouldSkipPreflight(
            isGGUF: true, isInProcess: false, injectedFailure: true,
            slotActivity: .busy))
        XCTAssertFalse(GGUFHealthCheckPolicy.shouldSkipPreflight(
            isGGUF: true, isInProcess: false, injectedFailure: false,
            slotActivity: .unknown))
        XCTAssertFalse(GGUFHealthCheckPolicy.shouldSkipPreflight(
            isGGUF: false, isInProcess: false, injectedFailure: false,
            slotActivity: .busy))
    }

    func testHealthCheckPolicyDefersFailedBusySlotButRestartsUnknownOrIdle() {
        XCTAssertTrue(GGUFHealthCheckPolicy.shouldDeferRestart(
            isGGUF: true, slotActivity: .busy))
        XCTAssertFalse(GGUFHealthCheckPolicy.shouldRestartAfterFailure(
            isCancelled: false, runtimeIsCurrent: true,
            isGGUF: true, slotActivity: .busy))
        XCTAssertTrue(GGUFHealthCheckPolicy.shouldRestartAfterFailure(
            isCancelled: false, runtimeIsCurrent: true,
            isGGUF: true, slotActivity: .unknown))
        XCTAssertTrue(GGUFHealthCheckPolicy.shouldRestartAfterFailure(
            isCancelled: false, runtimeIsCurrent: true,
            isGGUF: true, slotActivity: .idle))
    }

    func testHealthCheckPolicyNeverRestartsCancelledOrReplacedRuntime() {
        XCTAssertFalse(GGUFHealthCheckPolicy.shouldRestartAfterFailure(
            isCancelled: true, runtimeIsCurrent: true,
            isGGUF: true, slotActivity: .idle))
        XCTAssertFalse(GGUFHealthCheckPolicy.shouldRestartAfterFailure(
            isCancelled: false, runtimeIsCurrent: false,
            isGGUF: true, slotActivity: .idle))
    }

    func testResolverReturnsUnknownWithoutProvider() async {
        let provider: SlotActivityProviding? = nil
        let activity = await SlotActivityResolver.activity(for: provider)
        XCTAssertEqual(activity, .unknown)
    }

    private func probeSession(_ protocolClass: URLProtocol.Type) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }
}

private nonisolated final class BusySlotsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var request: URLRequest?

    static func reset() {
        lock.lock()
        request = nil
        lock.unlock()
    }

    static func recordedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.request = self.request
        Self.lock.unlock()
        respond(status: 200, body: #"[{"id":0,"is_processing":true}]"#)
    }

    override func stopLoading() {}

    private func respond(status: Int, body: String) {
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated final class MissingSlotsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var unused: Int?

    static func reset() {
        lock.lock()
        unused = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private nonisolated final class StubSlotActivityProvider:
    SlotActivityProviding, @unchecked Sendable
{
    let value: SlotActivity

    init(_ value: SlotActivity) {
        self.value = value
    }

    func slotActivity() async -> SlotActivity { value }
}