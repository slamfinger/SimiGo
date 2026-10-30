import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// Route 04 at the real HTTP boundary: the admission level decides how many
/// turns may be in flight, while further turns wait in a bounded FIFO instead
/// of reaching the generator.
///
/// The generator is a stub that parks until the test releases it, so "in
/// flight" is observable as "inside the generate handler". This test does not
/// assert the model-side single-flight rule: that stays the runtime gate's job
/// (`RuntimeTuning.serializeGeneration`), and route 04 never widens it.
///
/// Each request uses its own session id, and the stub answers
/// `ANSWER[<session>]`, so an answer carrying another request's marker would be
/// a genuine context bleed.
final class RequestAdmissionHTTPTests: XCTestCase {

    private var host: LOCALBAuthorizedE2E.Host!
    private var modelPath: String!
    private var stub: ParkingStub!

    private final class ParkingStub: @unchecked Sendable {
        private let lock = NSLock()
        private var entered: [String] = []
        private var agents: [String: String] = [:]
        private var inFlight = 0
        private var peakInFlight = 0
        private var parked: [CheckedContinuation<Void, Never>] = []

        func enterAndPark(_ marker: String, agent: String?) async {
            lock.lock()
            entered.append(marker)
            agents[marker] = agent ?? "<nil>"
            inFlight += 1
            peakInFlight = max(peakInFlight, inFlight)
            lock.unlock()

            await withCheckedContinuation { continuation in
                lock.lock()
                parked.append(continuation)
                lock.unlock()
            }

            lock.lock()
            inFlight -= 1
            lock.unlock()
        }

        var entries: [String] {
            lock.withLock { entered }
        }

        func agent(for marker: String) -> String? {
            lock.withLock { agents[marker] }
        }

        var entryCount: Int {
            lock.withLock { entered.count }
        }

        var parkedCount: Int {
            lock.withLock { parked.count }
        }

        var peak: Int {
            lock.withLock { peakInFlight }
        }

        func waitForEntries(_ count: Int, timeout: TimeInterval = 8) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if entryCount >= count { return true }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return entryCount >= count
        }

        func waitForParked(_ count: Int, timeout: TimeInterval = 8) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if parkedCount >= count { return true }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return parkedCount >= count
        }

        func releaseAll() {
            lock.lock()
            let ready = parked
            parked = []
            lock.unlock()
            ready.forEach { $0.resume() }
        }
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py")
        }
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(
                URL(fileURLWithPath: home, isDirectory: true).path),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoAdmissionHTTP-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"request-admission-http-model-free-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        host = try LOCALBAuthorizedE2E.makeHost()
        stub = ParkingStub()
    }

    override func tearDown() {
        stub?.releaseAll()
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        stub = nil
        host = nil
        super.tearDown()
    }

    // MARK: - Harness

    @MainActor
    private func withServer<T>(
        level: Int,
        queueCapacity: Int,
        port: Int,
        _ run: () async throws -> T
    ) async throws -> T {
        let stub = self.stub!
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let server = HTTPServer(
            port: port,
            modelId: "request-admission-http-test",
            generateHandler: { _, agentId, sessionId, _, _, _, _, onChunk, _ in
                await stub.enterAndPark(sessionId, agent: agentId)
                let text = "ANSWER[\(sessionId)]"
                onChunk(text)
                return GenerationResult(
                    text: text, usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "request-admission-http-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            informationTurnProducer: {
                InformationTurnProducer(
                    modelIdentity: identity.model, identity: identity)
            },
            requestAdmission: RequestAdmissionScheduler(
                limit: level, queueCapacity: queueCapacity)
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer {
            stub.releaseAll()
            server.stop()
        }
        return try await run()
    }

    private struct Outcome {
        let status: Int
        let raw: String
    }

    @MainActor
    private func dispatch(
        port: Int, session: String, agent: String = "default",
        prompt: String? = nil
    ) async throws -> Outcome {
        let body: [String: Any] = [
            "model": "request-admission-http-test",
            "messages": [["role": "user", "content": prompt ?? "probe \(session)"]],
            "session_id": session,
            "agent_id": agent,
            "stream": false,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        for _ in 0..<3 {
            do {
                let result = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST",
                    path: "/v1/chat/completions",
                    contentType: "application/json", body: payload)
                return Outcome(
                    status: result.1.statusCode,
                    raw: String(decoding: result.0, as: UTF8.self))
            } catch let error as URLError
            where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        XCTFail("request never reached the server: \(String(describing: lastError))")
        throw URLError(.cannotConnectToHost)
    }

    @MainActor
    private func start(
        port: Int, session: String, agent: String = "default",
        prompt: String? = nil
    ) -> Task<Result<Outcome, Error>, Never> {
        Task {
            do {
                return .success(
                    try await dispatch(
                        port: port, session: session, agent: agent, prompt: prompt))
            } catch {
                return .failure(error)
            }
        }
    }

    private func outcomes(
        _ tasks: [Task<Result<Outcome, Error>, Never>]
    ) async throws -> [Outcome] {
        var results: [Outcome] = []
        for task in tasks {
            switch await task.value {
            case .success(let outcome): results.append(outcome)
            case .failure(let error): throw error
            }
        }
        return results
    }

    // MARK: - Levels

    /// Level N admits N turns; request N+1 waits until a slot is released.
    /// Every answer carries only its own request's marker.
    @MainActor
    func testLevelAdmitsExactlyItsLevelAndAnswersStayPerRequest() async throws {
        let cases: [(level: Int, port: Int)] = [
            (1, 59_520), (2, 59_521), (4, 59_522),
        ]

        for testCase in cases {
            let level = testCase.level
            let port = testCase.port
            let sessions = (0...level).map { "admit-\(level)-\($0)" }

            // Each level needs its own stub: counters from a previous level
            // would otherwise be read as this level's admissions.
            stub = ParkingStub()

            let answers = try await withServer(
                level: level, queueCapacity: 4, port: port
            ) {
                let tasks = sessions.map { self.start(port: port, session: $0) }

                let admitted = await self.stub.waitForEntries(level)
                XCTAssertTrue(
                    admitted,
                    "level \(level): exactly the level's worth of turns reach the generator")
                let parked = await self.stub.waitForParked(level)
                XCTAssertTrue(
                    parked,
                    "level \(level): admitted turns are all in flight")

                try? await Task.sleep(nanoseconds: 400_000_000)
                XCTAssertEqual(
                    self.stub.entryCount, level,
                    "level \(level): request \(level + 1) waits instead of entering the generator")
                XCTAssertEqual(
                    self.stub.peak, level,
                    "level \(level): generator entry never exceeds the level")

                self.stub.releaseAll()
                let queuedAdmitted = await self.stub.waitForEntries(level + 1)
                XCTAssertTrue(
                    queuedAdmitted,
                    "level \(level): the queued turn is admitted after a release")
                let queuedParked = await self.stub.waitForParked(1)
                XCTAssertTrue(
                    queuedParked,
                    "level \(level): the queued turn is in flight before release")
                self.stub.releaseAll()

                return try await self.outcomes(tasks)
            }

            for (index, answer) in answers.enumerated() {
                XCTAssertEqual(answer.status, 200, answer.raw)
                XCTAssertTrue(
                    answer.raw.contains("ANSWER[\(sessions[index])]"),
                    "level \(level): answer \(index) belongs to its own request")
                for other in sessions.indices where other != index {
                    XCTAssertFalse(
                        answer.raw.contains("ANSWER[\(sessions[other])]"),
                        "level \(level): answer \(index) carries another request's answer")
                }
            }
        }
    }

    /// A saturated queue is refused with a real 503 and never reaches the
    /// generator; releasing the admitted turn drains the queued work.
    @MainActor
    func testSaturatedQueueRefusesTheNextRequestWith503() async throws {
        let port = 59_530

        let result = try await withServer(level: 1, queueCapacity: 2, port: port) {
            let tasks = (0..<3).map { self.start(port: port, session: "admit-full-\($0)") }

            let admitted = await self.stub.waitForEntries(1)
            XCTAssertTrue(admitted, "the first turn is admitted")
            let parked = await self.stub.waitForParked(1)
            XCTAssertTrue(parked, "the first turn is in flight")

            let refused = try await self.dispatch(port: port, session: "admit-full-refused")
            XCTAssertEqual(refused.status, 503, refused.raw)
            XCTAssertFalse(
                refused.raw.contains("ANSWER["),
                "a refused request never reaches the generator")

            self.stub.releaseAll()
            let queuedAdmitted = await self.stub.waitForEntries(2)
            XCTAssertTrue(
                queuedAdmitted,
                "the first queued turn is admitted after the release")
            self.stub.releaseAll()
            let lastAdmitted = await self.stub.waitForEntries(3)
            XCTAssertTrue(
                lastAdmitted,
                "the last queued turn is admitted after the second release")
            // Three turns share one slot, so a fixed number of releases can race
            // a turn that has not parked yet; drain deterministically instead of
            // letting the suite hang on an unreleased continuation.
            // Hold the stub strongly: the drain may wake once more after the
            // test returns, when tearDown has already cleared `self.stub`.
            let parkedStub = self.stub
            let drain = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    parkedStub?.releaseAll()
                }
            }
            defer { drain.cancel() }
            return (try await self.outcomes(tasks), refused)
        }

        for answer in result.0 {
            XCTAssertEqual(answer.status, 200, answer.raw)
        }
        XCTAssertFalse(
            stub.entries.contains("admit-full-refused"),
            "the refused request is not in the generator")
    }

    /// Level 4 under mixed sources: a normal turn, two agent turns and one
    /// external-API turn are admitted together, keep their own agent identity,
    /// and a fifth request from any source is refused while all four are in
    /// flight. Identity normalization itself is covered elsewhere
    /// (`AgentExecutionKeyTests`); this asserts the admission layer does not
    /// blend sources or admit beyond the level.
    @MainActor
    func testLevelFourKeepsMixedSourcesIsolated() async throws {
        let port = 59_540
        let sources: [(agent: String, session: String)] = [
            (agent: "default", session: "mix-user"),
            (agent: "codex", session: "mix-codex"),
            (agent: "zcode", session: "mix-zcode"),
            (agent: "extapi", session: "mix-extapi"),
        ]

        let answers = try await withServer(level: 4, queueCapacity: 0, port: port) {
            let tasks = sources.map {
                self.start(port: port, session: $0.session, agent: $0.agent)
            }

            let admitted = await self.stub.waitForEntries(4)
            XCTAssertTrue(admitted, "four mixed-source turns are admitted together")
            let parked = await self.stub.waitForParked(4)
            XCTAssertTrue(parked, "all four are in flight")
            XCTAssertEqual(self.stub.peak, 4, "mixed load never exceeds the level")

            for source in sources {
                XCTAssertEqual(
                    self.stub.agent(for: source.session), source.agent,
                    "request \(source.session) reaches the generator as \(source.agent)")
            }

            let refused = try await self.dispatch(port: port, session: "mix-overflow")
            XCTAssertEqual(refused.status, 503, refused.raw)
            XCTAssertFalse(
                refused.raw.contains("ANSWER["),
                "the refused request never reaches the generator")
            XCTAssertEqual(
                self.stub.entryCount, 4,
                "the fifth request does not enter the generator")

            // Hold the stub strongly: the drain may wake once more after the
            // test returns, when tearDown has already cleared `self.stub`.
            let parkedStub = self.stub
            let drain = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    parkedStub?.releaseAll()
                }
            }
            defer { drain.cancel() }

            let finished = try await self.outcomes(tasks)

            // Slots must come back after the four in-flight turns complete. A
            // released ticket may still be held for a moment while the response
            // is written, so this asserts reclamation within a bounded window,
            // not instant reclamation.
            var reclamationAttempts: [Int] = []
            var afterRelease: Outcome?
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                let outcome = try await self.dispatch(
                    port: port, session: "mix-after-release")
                reclamationAttempts.append(outcome.status)
                if outcome.status == 200 {
                    afterRelease = outcome
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertEqual(
                afterRelease?.status, 200,
                "a slot is reclaimed after the four in-flight turns complete; attempts=\(reclamationAttempts)")
            XCTAssertTrue(
                afterRelease?.raw.contains("ANSWER[mix-after-release]") ?? false,
                "the post-reclamation answer belongs to its own request")
            return finished
        }

        for (index, answer) in answers.enumerated() {
            XCTAssertEqual(answer.status, 200, answer.raw)
            XCTAssertTrue(
                answer.raw.contains("ANSWER[\(sources[index].session)]"),
                "answer \(index) belongs to its own source")
            for other in sources.indices where other != index {
                XCTAssertFalse(
                    answer.raw.contains("ANSWER[\(sources[other].session)]"),
                    "answer \(index) carries another source's answer")
            }
        }
    }

    /// Level 2 opens interleaving, so a second request is in flight while the
    /// first is still generating. The reuse gate only serves *settled* answers,
    /// so the second request must reach the generator even when its user text
    /// matches the first one exactly: recorded-but-unsettled knowledge is not
    /// consumable by a concurrent request. Same text, different sessions — the
    /// stub answers `ANSWER[<session>]`, so any cross-request reuse is visible.
    @MainActor
    func testLevelTwoDoesNotReuseAnInFlightAnswer() async throws {
        let port = 59_550
        let prompt = "shared in-flight probe"

        let outcomes = try await withServer(level: 2, queueCapacity: 0, port: port) {
            let first = self.start(port: port, session: "inflight-a", prompt: prompt)
            let firstParked = await self.stub.waitForParked(1)
            XCTAssertTrue(firstParked, "the first request is in flight")

            let second = self.start(port: port, session: "inflight-b", prompt: prompt)
            let bothParked = await self.stub.waitForParked(2)
            XCTAssertTrue(
                bothParked,
                "a concurrent request with the same user text reaches the generator instead of consuming the in-flight answer")
            XCTAssertEqual(
                self.stub.peak, 2, "both requests generate concurrently at level 2")

            // Hold the stub strongly: the drain may wake once more after the
            // test returns, when tearDown has already cleared `self.stub`.
            let parkedStub = self.stub
            let drain = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    parkedStub?.releaseAll()
                }
            }
            defer { drain.cancel() }
            return try await self.outcomes([first, second])
        }

        for (index, answer) in outcomes.enumerated() {
            XCTAssertEqual(answer.status, 200, answer.raw)
            XCTAssertFalse(
                answer.raw.contains("answer_reuse"),
                "request \(index) was answered by the model, not reused from another turn")
        }
        XCTAssertTrue(
            outcomes[0].raw.contains("ANSWER[inflight-a]"),
            "the first answer belongs to the first request")
        XCTAssertTrue(
            outcomes[1].raw.contains("ANSWER[inflight-b]")
                && !outcomes[1].raw.contains("ANSWER[inflight-a]"),
            "the second answer belongs to the second request")
    }
}
