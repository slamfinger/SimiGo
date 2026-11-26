import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// R11 的 App 层回归：模型暂时没起来造成的一次失败，**不能**把这一轮当成
/// 「做完了」。旧实现在失败分支直接 `finish(job)` 出队，t61 就这样在缺口里
/// 躺到人点「开始」才补上。
///
/// 手法与 `TurnDigestReceiptTests` 相同：`completeSession` 注入 URLProtocol
/// stub，`SIMIGO_HOME` 指向临时根。这里看的是队列行为，不是回执。
final class TurnDigestRetryTests: XCTestCase {
    private var previousHome: String?
    private var homeURL: URL!
    private var previousSession: URLSession!
    private var previousIdleQuietPeriod: TimeInterval?
    private var previousAdmissionLivenessForTesting: (@Sendable () -> (active: Int, waiting: Int))?

    private final class Stub: URLProtocol {
        nonisolated(unsafe) static var responder: ((URLRequest) -> (Int, String))?
        nonisolated(unsafe) static var hits = 0
        nonisolated(unsafe) static var lastURL: URL?
        nonisolated(unsafe) static var responseDelay: TimeInterval = 0
        nonisolated(unsafe) static var blockFirstResponse = false
        nonisolated(unsafe) static var firstRequestStarted = DispatchSemaphore(value: 0)
        nonisolated(unsafe) static var releaseFirstResponse = DispatchSemaphore(value: 0)

        override class func canInit(with request: URLRequest) -> Bool {
            responder != nil
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let responder = Self.responder, let url = request.url else { return }
            Self.hits += 1
            Self.lastURL = url
            let hit = Self.hits
            if hit == 1 && Self.blockFirstResponse {
                Self.firstRequestStarted.signal()
                _ = Self.releaseFirstResponse.wait(timeout: .now() + 20)
            }
            if Self.responseDelay > 0 { Thread.sleep(forTimeInterval: Self.responseDelay) }
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
            .appendingPathComponent(
                "simigo-digest-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: homeURL, withIntermediateDirectories: true)
        setenv("SIMIGO_HOME", homeURL.path, 1)

        // These tests enqueue jobs directly instead of seeding a turn through
        // recordExternalTurn/recordExternalResponse. The worker still probes
        // turn_digests before generation, so initialize the isolated IS schema
        // here; otherwise the probe fails with "no such table" before URLProtocol
        // is reached and every retry assertion measures fixture setup, not retry.
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
        Stub.lastURL = nil
        Stub.blockFirstResponse = false
        Stub.firstRequestStarted = DispatchSemaphore(value: 0)
        Stub.releaseFirstResponse = DispatchSemaphore(value: 0)
    }

    override func tearDown() async throws {
        // Unblock an in-flight URLProtocol request before waiting for the
        // detached drain worker to relinquish the isolated database.
        Stub.releaseFirstResponse.signal()
        let drained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(drained, "digest drain must finish before SIMIGO_HOME is restored")
        TurnDigestScheduler.resetQueueForTesting()
        Stub.responder = nil
        Stub.responseDelay = 0
        Stub.blockFirstResponse = false
        TurnDigestScheduler.idleQuietPeriodForTesting = previousIdleQuietPeriod
        TurnDigestScheduler.admissionLivenessForTesting = previousAdmissionLivenessForTesting
        TurnDigestScheduler.completeSession = previousSession
        if let previousHome {
            setenv("SIMIGO_HOME", previousHome, 1)
        } else {
            unsetenv("SIMIGO_HOME")
        }
        try? FileManager.default.removeItem(at: homeURL)
        try await super.tearDown()
    }

    private func openDatabase() throws -> ESISDatabase {
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        try db.runMigrations()
        return db
    }

    // This helper opens a new connection and reruns migration checks. Tests must
    // wait for the drain to become idle before calling it; polling by reopening
    // while the worker writes can race SQLite schema/FTS initialization.
    private func digestCount(session: String, turn: Int) throws -> Int {
        let db = try openDatabase()
        defer { db.close() }
        return try db.turnDigest(sessionID: session, turnIndex: turn) == nil ? 0 : 1
    }

    /// 造一条真缺口：轮账上有、摘要没有。启动重建按的就是这份账。
    private func seedUndigestedTurn(
        session: String,
        question: String = "问：模型没起来的那一轮怎么办",
        answer: String = "答：留在队里等下一次调度"
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

    private static func modelBody(_ content: String) -> String {
        let object: [String: Any] = [
            "choices": [["message": ["role": "assistant", "content": content]]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    private static let goodAnswer = """
    摘要：这一轮定的是失败之后留在队里等下一次调度，不设上限也不丢弃
    关键词：摘要 重试 队列 缺口
    """

    /// 等到条件成立，超时就红。摘要任务要先等 1.5 s 空窗，给足余量。
    private func waitUntil(
        _ what: String, timeout: TimeInterval = 25,
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: () throws -> Bool
    ) async rethrows {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("等不到：\(what)", file: file, line: line)
    }

    func testDigestRequestUsesEnvironmentPortBeforePersistedPort() async throws {
        let previousEnvironmentPort = ProcessInfo.processInfo.environment["SIMIGO_PORT"]
        let previousConfiguredPort = AppConfig.get(.apiPort)
        defer {
            if let previousEnvironmentPort {
                setenv("SIMIGO_PORT", previousEnvironmentPort, 1)
            } else {
                unsetenv("SIMIGO_PORT")
            }
            AppConfig.set(previousConfiguredPort, for: .apiPort)
        }
        AppConfig.set("18005", for: .apiPort)
        setenv("SIMIGO_PORT", "18004", 1)
        Stub.responder = { _ in (200, Self.modelBody(Self.goodAnswer)) }

        TurnDigestScheduler.schedule(
            sessionID: "s-env-port", turnIndex: 1,
            question: "问：环境端口", answer: "答：环境端口优先")
        let idle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(idle)
        XCTAssertEqual(Stub.lastURL?.absoluteString, "http://127.0.0.1:18004/v1/chat/completions")
    }

    func testDigestRequestUsesPersistedPortWithoutEnvironmentOverride() async throws {
        let previousEnvironmentPort = ProcessInfo.processInfo.environment["SIMIGO_PORT"]
        let previousConfiguredPort = AppConfig.get(.apiPort)
        defer {
            if let previousEnvironmentPort {
                setenv("SIMIGO_PORT", previousEnvironmentPort, 1)
            } else {
                unsetenv("SIMIGO_PORT")
            }
            AppConfig.set(previousConfiguredPort, for: .apiPort)
        }
        unsetenv("SIMIGO_PORT")
        AppConfig.set("18005", for: .apiPort)
        Stub.responder = { _ in (200, Self.modelBody(Self.goodAnswer)) }

        TurnDigestScheduler.schedule(
            sessionID: "s-config-port", turnIndex: 1,
            question: "问：持久化端口", answer: "答：读取 APIPort")
        let idle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(idle)
        XCTAssertEqual(Stub.lastURL?.absoluteString, "http://127.0.0.1:18005/v1/chat/completions")
    }

    /// 一次暂时失败不出队；下一次 `schedule` 落新轮时把上一轮再试一次，
    /// 试成了就落摘要——这正是 t61 + t62 的真实时序。
    func testTransientFailureKeepsTurnAndNextScheduleRetriesIt() async throws {
        Stub.responder = { _ in (503, "engine starting") }
        TurnDigestScheduler.schedule(
            sessionID: "s-retry", turnIndex: 1,
            question: "问：摘要失败之后呢", answer: "答：留在队里")

        try await waitUntil("第一次尝试失败并留下诊断") {
            TurnDigestScheduler.lastTransientFailure != nil
        }
        let firstDrainIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard firstDrainIdle else {
            XCTFail("the failed attempt must relinquish the drain before database inspection")
            return
        }
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 1, "失败的一轮还在队里，没被当成做完")
        XCTAssertEqual(try digestCount(session: "s-retry", turn: 1), 0, "失败不写行")
        XCTAssertEqual(Stub.hits, 1, "一次失败只试一次，不在本轮里自旋")

        // 模型起来了。写下一轮就是下一次独立触发：队首的 s-retry#1 先被再试。
        Stub.responder = { _ in (200, Self.modelBody(Self.goodAnswer)) }
        TurnDigestScheduler.schedule(
            sessionID: "s-retry", turnIndex: 2,
            question: "问：补上了吗", answer: "答：补上了")

        let secondDrainIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard secondDrainIdle else {
            XCTFail("both digest attempts must relinquish the worker before database inspection")
            return
        }
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 0, "成了就出队")
        XCTAssertEqual(try digestCount(session: "s-retry", turn: 1), 1)
        XCTAssertEqual(try digestCount(session: "s-retry", turn: 2), 1)
    }

    /// Re-scheduling the same key after a transient failure must restart the worker.
    /// The failed job remains queued, so the dedupe path must not return before
    /// checking whether the old worker has already relinquished ownership.
    func testRescheduleSameTurnRestartsDrainAfterTransientFailure() async throws {
        Stub.responder = { _ in (503, "engine starting") }
        TurnDigestScheduler.schedule(
            sessionID: "s-same-key-retry", turnIndex: 1,
            question: "问：同一轮再次调度", answer: "答：必须重新启动 drain")

        try await waitUntil("same-key first attempt failed") {
            TurnDigestScheduler.lastTransientFailure != nil
        }
        let firstDrainIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard firstDrainIdle else {
            XCTFail("the failed same-key attempt must relinquish the drain")
            return
        }
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 1)
        XCTAssertEqual(Stub.hits, 1)

        Stub.responder = { _ in (200, Self.modelBody(Self.goodAnswer)) }
        TurnDigestScheduler.schedule(
            sessionID: "s-same-key-retry", turnIndex: 1,
            question: "问：同一轮再次调度", answer: "答：必须重新启动 drain")

        let retryDrainIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard retryDrainIdle else {
            XCTFail("same-key retry must finish before its durable row is inspected")
            return
        }
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 0)
        XCTAssertEqual(Stub.hits, 2)
        XCTAssertEqual(try digestCount(session: "s-same-key-retry", turn: 1), 1)
    }

    /// ① badFormat 有界重试（owner 2026-11-23 裁定 ②+①）：格式不合不再一律
    /// 永久出队——随机退化模型再喂一遍可能换个格式就过。第一次不合留队，下一
    /// 次触发换成合格输出即落摘要（与暂时失败同型，但有界，见下一例）。
    func testBadFormatRetriedOnNextScheduleThenSucceeds() async throws {
        Stub.responder = { _ in (200, Self.modelBody("这不是按格式输出的模型回答")) }
        TurnDigestScheduler.schedule(
            sessionID: "s-badformat-retry", turnIndex: 1,
            question: "问：格式不合怎么办", answer: "答：再试一次")
        try await waitUntil("badFormat 第一次尝试留下诊断") {
            TurnDigestScheduler.lastTransientFailure != nil
        }
        let firstIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard firstIdle else { XCTFail("badFormat attempt must relinquish drain"); return }
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 1, "格式不合有界重试期内仍留队")
        XCTAssertEqual(try digestCount(session: "s-badformat-retry", turn: 1), 0)
        XCTAssertEqual(Stub.hits, 1)

        Stub.responder = { _ in (200, Self.modelBody(Self.goodAnswer)) }
        TurnDigestScheduler.schedule(
            sessionID: "s-badformat-retry", turnIndex: 2,
            question: "问：补上了吗", answer: "答：补上了")
        let secondIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard secondIdle else { XCTFail("retry must relinquish drain"); return }
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 0)
        XCTAssertEqual(try digestCount(session: "s-badformat-retry", turn: 1), 1)
        XCTAssertEqual(try digestCount(session: "s-badformat-retry", turn: 2), 1)
    }

    /// ① 有界：连续格式不合超过 maxFormatAttempts(3) 仍不合 → 永久出队留缺口，
    /// 不无限自旋（与无上限的暂时失败区分）。4 次独立触发：前 3 次留队，第 4 次永久。
    func testBadFormatBoundedThenPermanentlyDeferred() async throws {
        Stub.responder = { _ in (200, Self.modelBody("这不是按格式输出的模型回答")) }
        for _ in 0..<4 {
            TurnDigestScheduler.schedule(
                sessionID: "s-badformat-bound", turnIndex: 1,
                question: "问：一直不合", answer: "答：一直不合")
            let idle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
            guard idle else { XCTFail("each attempt must relinquish drain"); return }
        }
        XCTAssertEqual(Stub.hits, 4, "1 次初始 + 3 次有界重试，第 4 次判永久")
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 0, "超上限永久出队")
        XCTAssertEqual(try digestCount(session: "s-badformat-bound", turn: 1), 0, "留缺口不写行")
    }

    /// 连续失败不忙循环：没有新触发，队列就静静躺着，不再打模型。
    func testRepeatedFailureDoesNotSpin() async throws {
        Stub.responder = { _ in (503, "engine starting") }
        TurnDigestScheduler.schedule(
            sessionID: "s-spin", turnIndex: 1, question: "问：一", answer: "答：一")

        try await waitUntil("第一次尝试失败") { TurnDigestScheduler.lastTransientFailure != nil }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(Stub.hits, 1, "失败之后要等下一次独立触发，不许自己重排")
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 1, "队里那轮不许被静默丢弃")
    }

    /// 重复触发同一轮不产生第二份摘要：写入是 UPSERT，重试是安全的。
    func testRetryOfSameTurnWritesOneDigest() async throws {
        Stub.responder = { _ in (200, Self.modelBody(Self.goodAnswer)) }
        TurnDigestScheduler.schedule(
            sessionID: "s-idem", turnIndex: 1, question: "问：一", answer: "答：一")
        let firstDrainIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard firstDrainIdle else {
            XCTFail("the first digest write must finish before database inspection")
            return
        }
        XCTAssertEqual(try digestCount(session: "s-idem", turn: 1), 1)

        TurnDigestScheduler.schedule(
            sessionID: "s-idem", turnIndex: 1, question: "问：一", answer: "答：一")
        let secondDrainIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard secondDrainIdle else {
            XCTFail("the duplicate scheduling pass must relinquish the worker")
            return
        }

        let db = try openDatabase()
        defer { db.close() }
        XCTAssertEqual(try db.count("turn_digests"), 1, "同一轮只有一份摘要")
    }

    /// The in-memory batch is bounded at 64, but the durable IS gap ledger is not.
    /// Launch replay should feed the first batch and the drain must automatically fetch
    /// the next batch after it empties, without requiring another app event or restart.
    func testBacklogBeyondMemoryQueueCapacityIsRefilledFromLedger() async throws {
        for index in 0..<65 {
            try seedUndigestedTurn(session: String(format: "overflow-%03d", index))
        }
        Stub.responder = { _ in (503, "engine temporarily unavailable") }
        Stub.responseDelay = 0.1
        TurnDigestScheduler.replayPendingDigestsAtLaunch()

        try await waitUntil("first batch stops after one transient failure", timeout: 15) {
            TurnDigestScheduler.lastTransientFailure != nil
        }
        XCTAssertEqual(TurnDigestScheduler.pendingDepth, 64,
                       "all first-batch turns remain queued after the transient failure")

        // A 65th turn arrives while the old queue is full and dormant. It cannot be
        // enqueued, but the rejected trigger must wake the existing batch; after that
        // batch finishes, the drain must fetch this 65th gap from IS automatically.
        Stub.responder = { _ in (200, Self.modelBody(Self.goodAnswer)) }
        Stub.responseDelay = 0.02
        TurnDigestScheduler.schedule(
            sessionID: "overflow-064", turnIndex: 1,
            question: "问：第六十五轮", answer: "答：由 IS 缺口续取")

        let observationDB = try openDatabase()
        defer { observationDB.close() }
        try await waitUntil("65 ledger gaps are drained into durable digests", timeout: 60) {
            let gapCount = try observationDB.undigestedTurns().count
            let digestCount = try observationDB.count("turn_digests")
            let queueDepth = TurnDigestScheduler.pendingDepth
            return gapCount == 0 && digestCount == 65 && queueDepth == 0
        }
        let workerDrained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(
            workerDrained,
            "the worker must release the isolated database before the test tears it down")

        XCTAssertEqual(try observationDB.count("turn_digests"), 65)
        XCTAssertTrue(try observationDB.undigestedTurns().isEmpty)
    }

    /// A correction arriving after generation starts must supersede the captured
    /// prompt; the old model response is rejected at the database commit boundary.
    func testCorrectionDuringActiveDigestRejectsOldSnapshotAndRequeuesCurrentText() async throws {
        let session = "s-correction-race"
        let oldQuestion = "问题：这一轮需要修正"
        let oldAnswer = "旧答案：原始内容"
        let newAnswer = "新答案：已经核实的内容"
        try seedUndigestedTurn(
            session: session, question: oldQuestion, answer: oldAnswer)

        Stub.blockFirstResponse = true
        Stub.responder = { request in
            let body = request.httpBody ?? Data()
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let messages = object?["messages"] as? [[String: Any]]
            let prompt = messages?.first?["content"] as? String ?? ""
            if prompt.contains(oldAnswer) {
                return (200, Self.modelBody(
                    "摘要：这是旧答案产生的摘要\n关键词：旧答案 原始内容"))
            }
            return (200, Self.modelBody(
                "摘要：这是更正后答案产生的摘要\n关键词：更正 答案"))
        }

        TurnDigestScheduler.schedule(
            sessionID: session, turnIndex: 1,
            question: oldQuestion, answer: oldAnswer)
        XCTAssertEqual(
            Stub.firstRequestStarted.wait(timeout: .now() + 5), .success,
            "the old snapshot must be in flight before the correction")

        let db = try openDatabase()
        let correction = try db.correctChatMessage(
            sessionID: session, requestID: "r1", role: "assistant",
            correctedText: newAnswer, reason: "test active digest race",
            actor: "test", at: Date())
        XCTAssertEqual(correction.invalidatedTurnIndex, 1)
        let currentQuestion = try XCTUnwrap(
            db.chatMessageText(sessionID: session, requestID: "r1", role: "user"))
        db.close()

        // This is the same scheduling action performed by simigo_chat_correct.
        // It replaces the queued snapshot without starting a second drain.
        TurnDigestScheduler.schedule(
            sessionID: session, turnIndex: 1,
            question: currentQuestion, answer: newAnswer)
        Stub.releaseFirstResponse.signal()

        let observationDB = try openDatabase()
        defer { observationDB.close() }
        try await waitUntil("only the corrected source version is committed", timeout: 20) {
            try observationDB.turnDigest(sessionID: session, turnIndex: 1)?.digest
                    == "这是更正后答案产生的摘要"
                && TurnDigestScheduler.pendingDepth == 0
        }
        let workerDrained = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        XCTAssertTrue(
            workerDrained,
            "the old and replacement snapshots must share one drain worker")
        XCTAssertEqual(Stub.hits, 2,
                       "the stale response is rejected and the corrected snapshot is generated")
    }

    /// 待办只在内存里：进程没了，队就没了。缺口还在账上，启动按账重建。
    func testLaunchRebuildsPendingFromGaps() async throws {
        try seedUndigestedTurn(session: "s-reboot")
        Stub.responder = { _ in (503, "engine starting") }
        TurnDigestScheduler.schedule(
            sessionID: "s-reboot", turnIndex: 1,
            question: "问：重启之后呢", answer: "答：按缺口重建")
        try await waitUntil("第一次尝试失败") { TurnDigestScheduler.lastTransientFailure != nil }

        // 「重启」：内存队列清空，模型这时起来了，只剩库里的缺口。
        TurnDigestScheduler.resetQueueForTesting()
        Stub.responder = { _ in (200, Self.modelBody(Self.goodAnswer)) }
        TurnDigestScheduler.replayPendingDigestsAtLaunch()

        // The first hit was the failing attempt above; only the replay's own
        // request makes it two. Waiting on that count (instead of hits == 1,
        // already true here) keeps the observation DB-free until the worker is
        // guaranteed to have run, and the drain wait below covers the write.
        try await waitUntil("launch replay reaches the model stub") { Stub.hits == 2 }
        let replayDrainIdle = await TurnDigestScheduler.waitForDrainToBecomeIdleForTesting()
        guard replayDrainIdle else {
            XCTFail("launch replay must finish before its durable row is inspected")
            return
        }
        XCTAssertEqual(try digestCount(session: "s-reboot", turn: 1), 1)
    }
}
