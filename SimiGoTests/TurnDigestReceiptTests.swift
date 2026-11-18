import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// #189 的 App 层回归：补摘要的每一轮失败都要在回执里留下原因——
/// 格式不合 / HTTP / 停止各有各的名字，让位与停止不计入失败。
///
/// 手法：`TurnDigestScheduler.completeSession` 注入 URLProtocol stub 拦下
/// 模型请求；`SIMIGO_HOME` 指向临时根，fillMissing 读写都在隔离库里。
/// 让位（yielded）需要真实的引擎竞争，桩层造不出可信判据，此文件不覆盖
/// ——它由回执字段 `yielded` 的连线与真实空窗行为承担。
final class TurnDigestReceiptTests: XCTestCase {
    private var previousHome: String?
    private var homeURL: URL!
    private var previousSession: URLSession!
    private var previousIdleQuietPeriod: TimeInterval?
    private var previousAdmissionLivenessForTesting: (@Sendable () -> (active: Int, waiting: Int))?

    private final class DigestStubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var responder: ((URLRequest) -> (Int, String))?
        nonisolated(unsafe) static var requestDelay: TimeInterval = 0

        private final class RequestCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var active = 0
            private var peak = 0
            private var total = 0

            func enter() {
                lock.lock()
                active += 1
                total += 1
                peak = max(peak, active)
                lock.unlock()
            }

            func leave() {
                lock.lock()
                active -= 1
                lock.unlock()
            }

            func reset() {
                lock.lock()
                active = 0
                peak = 0
                total = 0
                lock.unlock()
            }

            var snapshot: (active: Int, peak: Int, total: Int) {
                lock.lock()
                defer { lock.unlock() }
                return (active, peak, total)
            }
        }

        private static let counter = RequestCounter()
        static func resetRequestCounters() { counter.reset() }
        static var requestSnapshot: (active: Int, peak: Int, total: Int) { counter.snapshot }

        override class func canInit(with request: URLRequest) -> Bool { responder != nil }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let responder = Self.responder, let url = request.url else { return }
            Self.counter.enter()
            defer { Self.counter.leave() }
            if Self.requestDelay > 0 { Thread.sleep(forTimeInterval: Self.requestDelay) }
            let (status, body) = responder(request)
            let http = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        previousHome = env["SIMIGO_HOME"]
        homeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-digest-receipt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        setenv("SIMIGO_HOME", homeURL.path, 1)

        previousSession = TurnDigestScheduler.completeSession
        previousIdleQuietPeriod = TurnDigestScheduler.idleQuietPeriodForTesting
        previousAdmissionLivenessForTesting = TurnDigestScheduler.admissionLivenessForTesting
        TurnDigestScheduler.idleQuietPeriodForTesting = 0
        TurnDigestScheduler.admissionLivenessForTesting = { (active: 0, waiting: 0) }
        TurnDigestScheduler.resetQueueForTesting()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DigestStubURLProtocol.self]
        TurnDigestScheduler.completeSession = URLSession(configuration: config)
    }

    override func tearDown() {
        DigestStubURLProtocol.responder = nil
        DigestStubURLProtocol.requestDelay = 0
        DigestStubURLProtocol.resetRequestCounters()
        TurnDigestScheduler.resetQueueForTesting()
        TurnDigestScheduler.idleQuietPeriodForTesting = previousIdleQuietPeriod
        TurnDigestScheduler.admissionLivenessForTesting = previousAdmissionLivenessForTesting
        TurnDigestScheduler.completeSession = previousSession
        if let previousHome {
            setenv("SIMIGO_HOME", previousHome, 1)
        } else {
            unsetenv("SIMIGO_HOME")
        }
        try? FileManager.default.removeItem(at: homeURL)
        super.tearDown()
    }

    private func openDatabase() throws -> ESISDatabase {
        let db = try ESISDatabase(
            url: ManagedPaths.databaseURL, createIfNeeded: true)
        try db.runMigrations()
        return db
    }

    /// 造一条「有账无摘要」的轮（真缺口，补录才有东西可补）。
    private func seedUndigestedTurn(session: String) throws {
        let db = try openDatabase()
        defer { db.close() }
        try db.recordExternalTurn(
            sessionID: session, provider: "local", requestID: "r1",
            userText: "问：闸门什么时候开", model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: session, provider: "local", requestID: "r1",
            assistantText: "答：汛前三天", model: nil, createdAt: Date())
        try db.recordTurnIndex(sessionID: session, turnIndex: 1,
                               requestID: "r1", at: Date())
    }

    private static func modelBody(_ content: String) -> String {
        let object: [String: Any] = [
            "choices": [["message": ["role": "assistant", "content": content]]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    func testParseFailureLeavesNamedReasonInReceipt() async throws {
        try seedUndigestedTurn(session: "s-parse")
        DigestStubURLProtocol.responder = { _ in
            (200, Self.modelBody("这不是按格式输出的模型回答"))
        }

        let receipt = await TurnDigestScheduler.fillMissing(limit: 1) { _, _ in }

        XCTAssertEqual(receipt.done, 0)
        XCTAssertEqual(receipt.failed, 1)
        XCTAssertNil(receipt.stoppedAt)
        XCTAssertEqual(receipt.failures.first?.key, "s-parse#1")
        XCTAssertEqual(receipt.failures.first?.reason, "格式不合",
                       "回执必须说得出「格式不合」，而不是只有一个失败数（#189 验收原文）")
        // 缺口仍在账上：失败不写行。
        let db = try openDatabase()
        defer { db.close() }
        XCTAssertEqual(try db.undigestedTurns().count, 1)
    }

    func testHTTPFailureNamesTheLayer() async throws {
        try seedUndigestedTurn(session: "s-http")
        DigestStubURLProtocol.responder = { _ in (503, "unavailable") }

        let receipt = await TurnDigestScheduler.fillMissing(limit: 1) { _, _ in }

        XCTAssertEqual(receipt.failed, 1)
        XCTAssertEqual(receipt.failures.first?.key, "s-http#1")
        XCTAssertEqual(receipt.failures.first?.reason, "HTTP：模型返回非 200")
    }

    /// Incremental drain and manual backfill arbitrate through one shared async gate.
    /// RuntimeStateReporter is idle in this URLProtocol test, so without the app-side
    /// gate the two background requests would overlap and cancel one another in product.
    func testIncrementalDrainAndBackfillShareOneGenerationAdmission() async throws {
        try seedUndigestedTurn(session: "a-fill")
        try seedUndigestedTurn(session: "b-drain")
        DigestStubURLProtocol.responder = { _ in
            (200, Self.modelBody("""
            摘要：增量与补录共用生成准入，互不取消彼此的请求
            关键词：摘要 增量 补录 准入
            """))
        }
        DigestStubURLProtocol.requestDelay = 0.25
        DigestStubURLProtocol.resetRequestCounters()

        TurnDigestScheduler.schedule(
            sessionID: "b-drain", turnIndex: 1,
            question: "问：增量", answer: "答：增量")
        let firstDeadline = Date().addingTimeInterval(5)
        while Date() < firstDeadline && DigestStubURLProtocol.requestSnapshot.active == 0 {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(DigestStubURLProtocol.requestSnapshot.active, 1,
                       "incremental drain should have entered the stub")

        // Backfill's database snapshot contains both turns; limit=1 selects a-fill.
        // It must wait for the same permit instead of racing b-drain's request.
        let receipt = await TurnDigestScheduler.fillMissing(limit: 1) { _, _ in }
        XCTAssertEqual(receipt.done, 1)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let db = try openDatabase()
            let fillDigest = try db.turnDigest(sessionID: "a-fill", turnIndex: 1)
            let drainDigest = try db.turnDigest(sessionID: "b-drain", turnIndex: 1)
            let complete = fillDigest != nil && drainDigest != nil
            db.close()
            if complete && TurnDigestScheduler.pendingDepth == 0 { break }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let db = try openDatabase()
        defer { db.close() }
        XCTAssertNotNil(try db.turnDigest(sessionID: "a-fill", turnIndex: 1))
        XCTAssertNotNil(try db.turnDigest(sessionID: "b-drain", turnIndex: 1))
        XCTAssertEqual(DigestStubURLProtocol.requestSnapshot.total, 2,
                       "the two committed gaps should each be generated once")
        XCTAssertEqual(DigestStubURLProtocol.requestSnapshot.peak, 1,
                       "incremental drain and backfill must not overlap")
    }

    func testStopIsNotCountedAsFailure() async throws {
        try seedUndigestedTurn(session: "s-stop")
        let stop = TurnDigestScheduler.DigestStop()
        stop.cancel()

        let receipt = await TurnDigestScheduler.fillMissing(stop: stop) { _, _ in }

        XCTAssertEqual(receipt.done, 0)
        XCTAssertEqual(receipt.failed, 0, "停止不是失败（#189 验收原文）")
        XCTAssertEqual(receipt.failures, [])
        XCTAssertEqual(receipt.stoppedAt, "s-stop#1")
    }
}
