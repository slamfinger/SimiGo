import XCTest

@testable import SimiGo
@testable import SimiGoRuntimeContract

/// L44 机械摘要档·调度器层：旗标开 ⇒ 摘要零模型调用落库（HTTP 面零命中），
/// digest 不再占主 backend。旗标关的路径由既有 TurnDigestRetryTests 覆盖。
final class TurnDigestMechanicalSchedulerTests: XCTestCase {
    private var previousHome: String?
    private var homeURL: URL!
    private var previousSession: URLSession!
    private var previousIdleQuietPeriod: TimeInterval?
    private var previousAdmissionLivenessForTesting: (@Sendable () -> (active: Int, waiting: Int))?

    private final class Stub: URLProtocol {
        nonisolated(unsafe) static var hits = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.hits += 1
            // 机械档下任何模型调用都是缺陷：命中即回 599 让测试可诊断。
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 599, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("mechanical-must-not-call-model".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    override func setUpWithError() throws {
        guard TurnDigestScheduler.resetQueueForTesting() else {
            throw NSError(
                domain: "TurnDigestMechanicalSchedulerTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "previous test left a live digest worker"])
        }
        let env = ProcessInfo.processInfo.environment
        previousHome = env["SIMIGO_HOME"]
        homeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "simigo-digest-mechanical-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: homeURL, withIntermediateDirectories: true)
        setenv("SIMIGO_HOME", homeURL.path, 1)
        previousHome = previousHome ?? env["SIMIGO_HOME"]

        let database = try openDatabase()
        database.close()

        previousSession = TurnDigestScheduler.completeSession
        previousIdleQuietPeriod = TurnDigestScheduler.idleQuietPeriodForTesting
        previousAdmissionLivenessForTesting = TurnDigestScheduler.admissionLivenessForTesting
        TurnDigestScheduler.idleQuietPeriodForTesting = 0
        TurnDigestScheduler.admissionLivenessForTesting = { (active: 0, waiting: 0) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        TurnDigestScheduler.completeSession = URLSession(configuration: config)
        TurnDigestScheduler.resetQueueForTesting()
        Stub.hits = 0
        setenv("SIMIGO_DIGEST_MECHANICAL", "1", 1)
    }

    override func tearDown() async throws {
        let drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard drained else {
            XCTFail("digest drain must finish before SIMIGO_HOME is restored")
            throw NSError(
                domain: "TurnDigestMechanicalSchedulerTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "digest drain timed out; cleanup parked"])
        }
        XCTAssertTrue(TurnDigestScheduler.resetQueueForTesting())
        TurnDigestScheduler.idleQuietPeriodForTesting = previousIdleQuietPeriod
        TurnDigestScheduler.admissionLivenessForTesting = previousAdmissionLivenessForTesting
        TurnDigestScheduler.completeSession = previousSession
        if let previousHome {
            setenv("SIMIGO_HOME", previousHome, 1)
        } else {
            unsetenv("SIMIGO_HOME")
        }
        unsetenv("SIMIGO_DIGEST_MECHANICAL")
        try? FileManager.default.removeItem(at: homeURL)
        try await super.tearDown()
    }

    private func openDatabase() throws -> ESISDatabase {
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        try db.runMigrations()
        return db
    }

    /// 造一条真缺口：轮账上有、摘要没有。
    private func seedUndigestedTurn(
        session: String, question: String, answer: String
    ) throws {
        let db = try openDatabase()
        defer { db.close() }
        try db.recordExternalTurn(
            sessionID: session, provider: "local", requestID: "r1",
            userText: question, model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: session, provider: "local", requestID: "r1",
            assistantText: answer, model: nil, createdAt: Date())
        try db.recordTurnIndex(sessionID: session, turnIndex: 1,
                               requestID: "r1", at: Date())
    }

    func testMechanicalFlagWritesDigestWithoutModelCall() async throws {
        let session = "mech-sched-1"
        try seedUndigestedTurn(
            session: session,
            question: "机械摘要档落库要满足什么条件",
            answer: "旗标开启即零模型调用，摘要与关键词确定性产出，模型未装载也照常落库。")
        TurnDigestScheduler.schedule(
            sessionID: session, turnIndex: 1,
            question: "机械摘要档落库要满足什么条件",
            answer: "旗标开启即零模型调用，摘要与关键词确定性产出，模型未装载也照常落库。")
        let drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(drained, "机械档 drain 必须自行排空（不等模型）")
        XCTAssertEqual(Stub.hits, 0, "机械档不得发起任何模型调用")
        let db = try openDatabase()
        defer { db.close() }
        let record = try db.turnDigest(sessionID: session, turnIndex: 1)
        XCTAssertNotNil(record, "机械档摘要必须落库")
        XCTAssertFalse(record?.digest.isEmpty ?? true)
        XCTAssertTrue(record?.digest.contains("回答要点") ?? false,
                      "机械档摘要形态：\(record?.digest.prefix(80) ?? "")")
        XCTAssertFalse(record?.keywords.isEmpty ?? true, "机械档关键词必须落库")
    }
}
