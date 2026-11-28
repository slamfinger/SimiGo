import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

final class TopicSemanticCoordinatorTests: XCTestCase {
    private var previousHome: String?
    private var homeURL: URL!
    private var previousInterpreter: TopicSemanticInterpreter!

    override func setUpWithError() throws {
        previousHome = ProcessInfo.processInfo.environment["SIMIGO_HOME"]
        homeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-topic-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        setenv("SIMIGO_HOME", homeURL.path, 1)
        previousInterpreter = TopicSemanticCoordinator.interpreter
    }

    override func tearDown() {
        TopicSemanticCoordinator.interpreter = previousInterpreter
        if let previousHome {
            setenv("SIMIGO_HOME", previousHome, 1)
        } else {
            unsetenv("SIMIGO_HOME")
        }
        try? FileManager.default.removeItem(at: homeURL)
        super.tearDown()
    }

    private final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [TopicSemanticRequest] = []

        func append(_ request: TopicSemanticRequest) {
            lock.lock()
            values.append(request)
            lock.unlock()
        }

        var snapshot: [TopicSemanticRequest] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private struct Interpreter: TopicSemanticInterpreter {
        let box: RequestBox

        func interpret(_ request: TopicSemanticRequest) async throws -> TopicSemanticInterpretation {
            box.append(request)
            if request.turnRef == "topics#1" {
                return try TopicSemanticInterpretation(
                    approximateSemantics: "开始讨论 brief 的话题定义与归属",
                    route: TopicSemanticRoute(status: .newTopic, topicID: "model-placeholder"),
                    newTopic: TopicSemanticNewTopic(
                        definingParagraph: "讨论 brief 的话题定义、开头与后续归属。",
                        title: "brief 话题设计"))
            }
            if request.turnRef == "topics#2" {
                guard let topicID = request.topics.first?.topicID else {
                    throw TopicSemanticError.missingAssignedTopicID
                }
                return try TopicSemanticInterpretation(
                    approximateSemantics: "继续实现话题归属",
                    route: TopicSemanticRoute(
                        status: .assigned,
                        topicID: topicID,
                        candidateTopicIDs: request.topics.map(\.topicID)))
            }
            return try TopicSemanticInterpretation(
                approximateSemantics: "简单问候，没有具体任务",
                route: TopicSemanticRoute(status: .nonTopic, topicID: nil))
        }
    }

    private func openDatabase() throws -> ESISDatabase {
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        try db.runMigrations()
        return db
    }

    private func seedTurn(
        _ db: ESISDatabase, session: String, turn: Int, question: String, answer: String
    ) throws {
        let request = "r\(turn)"
        try db.recordExternalTurn(
            sessionID: session, provider: "local", requestID: request,
            userText: question, model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: session, provider: "local", requestID: request,
            assistantText: answer, model: nil, createdAt: Date())
        _ = try db.recordTurnIndex(
            sessionID: session, turnIndex: turn, requestID: request, at: Date())
        _ = try db.recordTurnDigest(
            sessionID: session, turnIndex: turn,
            digest: "摘要：\(question)", keywords: "semantic-test",
            expectedQuestionSHA256: TurnDigestText.sourceSHA256(question),
            expectedAnswerSHA256: TurnDigestText.sourceSHA256(answer))
    }

    func testCoordinatorCreatesGenesisThenUsesPriorContextWithoutBackfillingOtherSessions() async throws {
        let db = try openDatabase()
        defer { db.close() }
        try seedTurn(db, session: "topics", turn: 1,
                     question: "brief相关，定义话题身份", answer: "先用一段定义")
        try seedTurn(db, session: "topics", turn: 2,
                     question: "那个归属怎么实现", answer: "按话题定义归类")
        try seedTurn(db, session: "other", turn: 1,
                     question: "你好", answer: "你好")
        let box = RequestBox()
        TopicSemanticCoordinator.interpreter = Interpreter(box: box)

        let firstProcessed = try await TopicSemanticCoordinator.processNext(sessionID: "topics")
        let secondProcessed = try await TopicSemanticCoordinator.processNext(sessionID: "topics")
        let drained = try await TopicSemanticCoordinator.processNext(sessionID: "topics")
        XCTAssertTrue(firstProcessed)
        XCTAssertTrue(secondProcessed)
        XCTAssertFalse(drained)

        let requests = box.snapshot
        XCTAssertEqual(requests.map(\.turnRef), ["topics#1", "topics#2"])
        XCTAssertEqual(requests[0].responseText, "先用一段定义")
        XCTAssertTrue(requests[0].context.isEmpty)
        XCTAssertTrue(requests[0].topics.isEmpty)
        XCTAssertEqual(requests[1].context.map(\.turnRef), ["topics#1"])
        XCTAssertTrue(requests[1].context[0].text.contains("brief相关"))
        XCTAssertEqual(requests[1].topics.count, 1)

        let genesis = try XCTUnwrap(try db.allTopicGeneses().first)
        XCTAssertEqual(genesis.title, "brief 话题设计")
        XCTAssertEqual(genesis.seedRefs, ["topics#1"])
        XCTAssertEqual(try db.currentTopicAssignment(turnRef: "topics#2")?.topicID, genesis.topicID)
        XCTAssertEqual(try db.turnSemanticObservation(turnRef: "topics#2")?.contextRefs, ["topics#1"])
        XCTAssertEqual(try db.turnsNeedingTopicSemantics(sessionID: "other").map(\.turnIndex), [1])
        XCTAssertTrue(try db.turnsNeedingTopicSemantics(sessionID: "topics").isEmpty)
    }

    func testCoordinatorStoresGreetingSemanticsWithoutCreatingTopic() async throws {
        let db = try openDatabase()
        defer { db.close() }
        try seedTurn(db, session: "greeting", turn: 1, question: "你好", answer: "你好")
        TopicSemanticCoordinator.interpreter = Interpreter(box: RequestBox())

        let processed = try await TopicSemanticCoordinator.processNext(sessionID: "greeting")
        XCTAssertTrue(processed)
        XCTAssertTrue(try db.allTopicGeneses().isEmpty)
        XCTAssertEqual(try db.currentTopicAssignment(turnRef: "greeting#1")?.status, .nonTopic)
        XCTAssertEqual(try db.turnSemanticObservation(turnRef: "greeting#1")?.approximateSemantics,
                       "简单问候，没有具体任务")
    }
}
