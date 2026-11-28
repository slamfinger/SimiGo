import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// G3：摘要归属。双档混跑后，库里必须能回答「这条摘要哪档生成、来自哪条
/// 路由的轮次」。同一会话走一遍机械档与模型档，断言两行 lane / source_route
/// 不同且可查。
final class TurnDigestAttributionTests: XCTestCase {
    private var previousHome: String?
    private var homeURL: URL!
    private var previousSession: URLSession!
    private var previousIdleQuietPeriod: TimeInterval?
    private var previousAdmissionLivenessForTesting: (@Sendable () -> (active: Int, waiting: Int))?
    private var previousMechanical: String?

    private final class Stub: URLProtocol {
        nonisolated(unsafe) static var body = ""
        nonisolated(unsafe) static var hits = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.hits += 1
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    override func setUpWithError() throws {
        guard TurnDigestScheduler.resetQueueForTesting() else {
            throw NSError(
                domain: "TurnDigestAttributionTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "previous test left a live digest worker"])
        }
        let env = ProcessInfo.processInfo.environment
        previousHome = env["SIMIGO_HOME"]
        previousMechanical = env["SIMIGO_DIGEST_MECHANICAL"]
        homeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "simigo-digest-attribution-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: homeURL, withIntermediateDirectories: true)
        setenv("SIMIGO_HOME", homeURL.path, 1)

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
        Stub.body = """
        {"choices":[{"message":{"role":"assistant","content":"摘要：这一轮定的是归属怎么记\\n关键词：摘要 归属 路由"}}]}
        """
        unsetenv("SIMIGO_DIGEST_MECHANICAL")
    }

    override func tearDown() async throws {
        let drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard drained else {
            XCTFail("digest drain must finish before SIMIGO_HOME is restored")
            throw NSError(
                domain: "TurnDigestAttributionTests", code: 1,
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
        if let previousMechanical {
            setenv("SIMIGO_DIGEST_MECHANICAL", previousMechanical, 1)
        } else {
            unsetenv("SIMIGO_DIGEST_MECHANICAL")
        }
        try? FileManager.default.removeItem(at: homeURL)
        try await super.tearDown()
    }

    private func openDatabase() throws -> ESISDatabase {
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        try db.runMigrations()
        return db
    }

    /// 造一条真缺口，并把这一轮回答的模型写成会话行会记的那个值。
    @discardableResult
    private func seedTurn(
        session: String, turn: Int, requestID: String, model: String?
    ) throws -> (question: String, answer: String) {
        let question = "问\(turn)：这一轮摘要算哪一档"
        let answer = "答\(turn)：按生成方式与来源路由各记一列"
        let db = try openDatabase()
        defer { db.close() }
        try db.recordExternalTurn(
            sessionID: session, provider: "local", requestID: requestID,
            userText: question, model: model, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: session, provider: "local", requestID: requestID,
            assistantText: answer, model: model, createdAt: Date())
        try db.recordTurnIndex(
            sessionID: session, turnIndex: turn, requestID: requestID, at: Date())
        return (question, answer)
    }

    func testMechanicalAndModelDigestsCarryDistinctLaneAndSourceRoute() async throws {
        let session = "digest-attribution"

        // 第一轮：机械档，本地模型。
        let first = try seedTurn(
            session: session, turn: 1, requestID: "r1", model: "ornith-35b")
        setenv("SIMIGO_DIGEST_MECHANICAL", "1", 1)
        TurnDigestScheduler.schedule(
            sessionID: session, turnIndex: 1,
            question: first.question, answer: first.answer)
        var drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(drained, "机械档 drain 必须自行排空")
        XCTAssertEqual(Stub.hits, 0, "机械档不得发起模型调用")

        // 第二轮：模型档，云路由。
        let second = try seedTurn(
            session: session, turn: 2, requestID: "r2", model: "cloud:gpt-5")
        unsetenv("SIMIGO_DIGEST_MECHANICAL")
        TurnDigestScheduler.schedule(
            sessionID: session, turnIndex: 2,
            question: second.question, answer: second.answer)
        drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(drained, "模型档 drain 必须自行排空")
        XCTAssertEqual(Stub.hits, 1, "模型档要走一次模型调用")

        let db = try openDatabase()
        defer { db.close() }
        let mechanical = try XCTUnwrap(db.turnDigest(sessionID: session, turnIndex: 1))
        let model = try XCTUnwrap(db.turnDigest(sessionID: session, turnIndex: 2))
        XCTAssertEqual(mechanical.lane, "mechanical")
        XCTAssertEqual(mechanical.sourceRoute, "local:ornith-35b")
        XCTAssertEqual(model.lane, "model")
        XCTAssertEqual(model.sourceRoute, "cloud:gpt-5")
        XCTAssertNotEqual(mechanical.lane, model.lane)
        XCTAssertNotEqual(mechanical.sourceRoute, model.sourceRoute)
    }
}
