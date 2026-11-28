import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

final class TopicSemanticGenesisTests: XCTestCase {
    private func open() throws -> (URL, ESISDatabase) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-topic-semantics-\(UUID().uuidString).sqlite3")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func seedTurn(
        _ db: ESISDatabase,
        session: String,
        turn: Int,
        question: String,
        answer: String = "已记录",
        withDigest: Bool = true
    ) throws -> TopicSemanticSource {
        let request = "r\(turn)"
        try db.recordExternalTurn(
            sessionID: session, provider: "local", requestID: request,
            userText: question, model: nil, createdAt: Date())
        try db.recordExternalResponse(
            sessionID: session, provider: "local", requestID: request,
            assistantText: answer, model: nil, createdAt: Date())
        _ = try db.recordTurnIndex(sessionID: session, turnIndex: turn, requestID: request, at: Date())
        let source = try TopicSemanticSource(
            sessionID: session, turnIndex: turn,
            expectedQuestionSHA256: TurnDigestText.sourceSHA256(question),
            expectedAnswerSHA256: TurnDigestText.sourceSHA256(answer))
        if withDigest {
            _ = try db.recordTurnDigest(
                sessionID: session, turnIndex: turn,
                digest: "轮次摘要：\(question)", keywords: "semantic-test",
                expectedQuestionSHA256: source.expectedQuestionSHA256,
                expectedAnswerSHA256: source.expectedAnswerSHA256)
        }
        return source
    }

    private func publication(
        source: TopicSemanticSource,
        semantics: String,
        route: TopicSemanticRoute,
        genesis: TopicGenesisRecord? = nil,
        clarification: TopicScopeClarificationRecord? = nil,
        contextRefs: [String] = [],
        suffix: String = "a",
        createdAt: String = "2026-11-28T12:00:00Z"
    ) throws -> TopicSemanticPublication {
        try TopicSemanticPublication(
            genesis: genesis,
            clarification: clarification,
            observation: TurnSemanticObservation(
                turnRef: source.turnRef,
                approximateSemantics: semantics,
                contextRefs: contextRefs),
            assignment: TopicAssignmentRecord(
                assignmentID: "assignment-\(source.turnRef)-\(suffix)",
                turnRef: source.turnRef,
                topicID: route.topicID,
                status: route.status,
                candidateTopicIDs: route.candidateTopicIDs,
                evidenceRefs: [source.turnRef],
                createdAt: createdAt))
    }

    func testSchema55AndGreetingDoesNotCreateTopic() async throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        XCTAssertEqual(ESISDatabase.currentSchemaVersion, 55)
        let source = try seedTurn(db, session: "greetings", turn: 1, question: "你好")
        let router = ExplicitTopicReferenceRouter()
        let result = try await router.interpret(TopicSemanticRequest(
            turnRef: source.turnRef, currentText: "你好", context: [], topics: []))
        XCTAssertEqual(result.route.status, .nonTopic)
        XCTAssertNil(result.route.topicID)
        try db.publishTopicSemantics(
            try publication(source: source, semantics: result.approximateSemantics, route: result.route),
            source: source)
        XCTAssertTrue(try db.allTopicGeneses().isEmpty)
        XCTAssertEqual(try db.currentTopicAssignment(turnRef: source.turnRef)?.status, .nonTopic)
    }

    func testSchema55MigrationIsIdempotentAfterRepairCreatesTables() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        try db.rawExec("DELETE FROM schema_migrations WHERE version=55;")
        try db.runMigrations()
        XCTAssertEqual(try db.count("schema_migrations WHERE version=55"), 1)
        XCTAssertEqual(try db.count("""
            sqlite_master WHERE type='trigger'
              AND name IN (
                'topic_genesis_no_update', 'topic_genesis_no_delete',
                'topic_scope_clarification_no_update', 'topic_scope_clarification_no_delete',
                'turn_semantics_no_update', 'turn_semantics_no_delete',
                'topic_assignment_no_update', 'topic_assignment_no_delete'
              )
            """), 8)
    }

    func testBriefTopicIsCreatedAtGenesisAndRecognizedAcrossSessions() async throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let first = try seedTurn(db, session: "session-a", turn: 1, question: "brief相关，先聊话题身份")
        let genesis = try TopicGenesisRecord(
            topicID: "topic-brief",
            definingParagraph: "讨论 brief 的话题定义、话题开头与后续语义归类。",
            title: "brief 话题设计",
            seedRefs: [first.turnRef], reconstructed: false,
            createdAt: "2026-11-28T12:00:00Z")
        let firstResult = try await ExplicitTopicReferenceRouter().interpret(TopicSemanticRequest(
            turnRef: first.turnRef, currentText: "brief相关，先聊话题身份", context: [],
            topics: [try EffectiveTopicDefinition(genesis: genesis, clarifications: [])]))
        let newRoute = try TopicSemanticRoute(status: .newTopic, topicID: genesis.topicID)
        try db.publishTopicSemantics(
            try publication(
                source: first, semantics: firstResult.approximateSemantics,
                route: newRoute, genesis: genesis),
            source: first)

        let second = try seedTurn(db, session: "session-b", turn: 1, question: "brief 的那个归属怎么实现")
        let definition = try XCTUnwrap(try db.effectiveTopicDefinition(topicID: genesis.topicID))
        let secondResult = try await ExplicitTopicReferenceRouter().interpret(TopicSemanticRequest(
            turnRef: second.turnRef, currentText: "brief 的那个归属怎么实现", context: [],
            topics: [definition]))
        XCTAssertEqual(secondResult.route.status, .assigned)
        try db.publishTopicSemantics(
            try publication(
                source: second, semantics: secondResult.approximateSemantics,
                route: secondResult.route),
            source: second)
        XCTAssertEqual(try db.currentTopicAssignment(turnRef: second.turnRef)?.topicID, genesis.topicID)
        XCTAssertEqual(try db.topicGenesis(topicID: genesis.topicID), genesis)
    }

    func testDeicticTurnUsesOnlyPriorContextAndUnmatchedTurnStaysAmbiguous() async throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let first = try seedTurn(db, session: "context", turn: 1, question: "brief 设计")
        let genesis = try TopicGenesisRecord(
            topicID: "brief", definingParagraph: "brief 话题设计与实现",
            title: "brief", seedRefs: [first.turnRef], reconstructed: false,
            createdAt: "2026-11-28T12:00:00Z")
        try db.publishTopicSemantics(
            try publication(
                source: first, semantics: "brief 话题设计",
                route: TopicSemanticRoute(status: .newTopic, topicID: "brief"), genesis: genesis),
            source: first)
        let second = try seedTurn(db, session: "context", turn: 2, question: "那个怎么实现")
        let request = try TopicSemanticRequest(
            turnRef: second.turnRef, currentText: "那个怎么实现",
            context: [try TopicSemanticContext(turnRef: first.turnRef, text: "brief 设计")],
            topics: [try XCTUnwrap(try db.effectiveTopicDefinition(topicID: "brief"))])
        let contextual = try await ExplicitTopicReferenceRouter().interpret(request)
        XCTAssertEqual(contextual.route.status, .assigned)
        let isolated = try await ExplicitTopicReferenceRouter().interpret(TopicSemanticRequest(
            turnRef: second.turnRef, currentText: "那个怎么实现", context: [],
            topics: [try XCTUnwrap(try db.effectiveTopicDefinition(topicID: "brief"))]))
        XCTAssertEqual(isolated.route.status, .ambiguous)
        XCTAssertNil(isolated.route.topicID)
    }

    func testScopeClarificationAppendsAndGenesisRemainsImmutable() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let first = try seedTurn(db, session: "scope", turn: 1, question: "brief 是什么")
        let genesis = try TopicGenesisRecord(
            topicID: "brief", definingParagraph: "brief 是话题开头。",
            title: "brief", seedRefs: [first.turnRef], reconstructed: false,
            createdAt: "2026-11-28T12:00:00Z")
        try db.publishTopicSemantics(
            try publication(
                source: first, semantics: "brief 话题定义",
                route: TopicSemanticRoute(status: .newTopic, topicID: "brief"), genesis: genesis),
            source: first)
        let second = try seedTurn(db, session: "scope", turn: 2, question: "范围也包括语义归类")
        let clarification = try TopicScopeClarificationRecord(
            clarificationID: "clarification-1", topicID: "brief",
            clarification: "范围后来扩展到近似语义归类。",
            sourceRefs: [second.turnRef], createdAt: "2026-11-28T12:01:00Z")
        try db.publishTopicSemantics(
            try publication(
                source: second, semantics: "brief 范围澄清",
                route: TopicSemanticRoute(status: .assigned, topicID: "brief"),
                clarification: clarification, contextRefs: [first.turnRef]),
            source: second)
        let laterClarification = try TopicScopeClarificationRecord(
            clarificationID: "clarification-0", topicID: "brief",
            clarification: "同秒追加的边界仍排在后。",
            sourceRefs: [second.turnRef], createdAt: clarification.createdAt)
        try db.publishTopicSemantics(
            try publication(
                source: second, semantics: "brief 范围澄清",
                route: TopicSemanticRoute(status: .assigned, topicID: "brief"),
                clarification: laterClarification, contextRefs: [first.turnRef], suffix: "b"),
            source: second)
        let effective = try XCTUnwrap(try db.effectiveTopicDefinition(topicID: "brief"))
        XCTAssertEqual(effective.genesisParagraph, genesis.definingParagraph)
        XCTAssertEqual(effective.clarifications, [clarification, laterClarification])
        XCTAssertTrue(effective.renderedParagraph.hasSuffix(laterClarification.clarification))
        XCTAssertThrowsError(try db.rawExec("UPDATE topic_genesis SET title='changed';"))
        XCTAssertThrowsError(try db.rawExec("DELETE FROM topic_genesis WHERE topic_id='brief';"))
        XCTAssertEqual(try db.topicGenesis(topicID: "brief"), genesis)
    }

    func testStaleSourceRejectsWholePublication() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let source = try seedTurn(db, session: "stale", turn: 1, question: "brief")
        let stale = try TopicSemanticSource(
            sessionID: source.sessionID, turnIndex: source.turnIndex,
            expectedQuestionSHA256: source.expectedQuestionSHA256,
            expectedAnswerSHA256: TurnDigestText.sourceSHA256("changed"))
        let genesis = try TopicGenesisRecord(
            topicID: "brief", definingParagraph: "brief 定义", title: "brief",
            seedRefs: [source.turnRef], reconstructed: false, createdAt: "2026-11-28T12:00:00Z")
        let value = try publication(
            source: source, semantics: "brief 定义",
            route: TopicSemanticRoute(status: .newTopic, topicID: "brief"), genesis: genesis)
        XCTAssertThrowsError(try db.publishTopicSemantics(value, source: stale)) { error in
            guard let dbError = error as? ESISDatabase.DatabaseError,
                  case .staleTurnDigestSource = dbError else {
                return XCTFail("expected stale source, got \(error)")
            }
        }
        XCTAssertTrue(try db.allTopicGeneses().isEmpty)
        XCTAssertNil(try db.turnSemanticObservation(turnRef: source.turnRef))
    }

    func testFutureEvidenceReferenceIsRejected() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let source = try seedTurn(db, session: "causal", turn: 1, question: "brief")
        let value = try publication(
            source: source, semantics: "brief 定义",
            route: TopicSemanticRoute(status: .ambiguous, topicID: nil),
            contextRefs: ["causal#2"])
        XCTAssertThrowsError(try db.publishTopicSemantics(value, source: source)) { error in
            XCTAssertEqual(error as? TopicSemanticPersistenceError, .futureEvidence("causal#2"))
        }
        XCTAssertNil(try db.turnSemanticObservation(turnRef: source.turnRef))
    }

    func testSemanticLabelsStayOutOfDigestKeywordsAndObjectStore() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let source = try seedTurn(db, session: "separation", turn: 1, question: "你好")
        let objectsBefore = try db.count("is_objects")
        let label = "简单问候，没有具体任务"
        try db.publishTopicSemantics(
            try publication(
                source: source, semantics: label,
                route: TopicSemanticRoute(status: .nonTopic, topicID: nil)),
            source: source)
        let digest = try XCTUnwrap(try db.turnDigest(sessionID: source.sessionID, turnIndex: 1))
        XCTAssertFalse(digest.digest.contains(label))
        XCTAssertFalse(digest.keywords.contains(label))
        XCTAssertEqual(try db.count("is_objects"), objectsBefore)
        XCTAssertEqual(try db.turnSemanticObservation(turnRef: source.turnRef)?.approximateSemantics, label)
    }

    func testAssignmentCorrectionIsAppendOnlyAndIdempotent() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let source = try seedTurn(db, session: "decisions", turn: 1, question: "brief")
        let first = try publication(
            source: source, semantics: "证据不足",
            route: TopicSemanticRoute(status: .ambiguous, topicID: nil), suffix: "z")
        try db.publishTopicSemantics(first, source: source)
        try db.publishTopicSemantics(first, source: source)
        XCTAssertEqual(try db.topicAssignments(turnRef: source.turnRef).count, 1)
        let second = try publication(
            source: source, semantics: "证据不足",
            route: TopicSemanticRoute(status: .nonTopic, topicID: nil), suffix: "a")
        try db.publishTopicSemantics(second, source: source)
        let rows = try db.topicAssignments(turnRef: source.turnRef)
        XCTAssertEqual(rows.map(\.status), [.ambiguous, .nonTopic])
        XCTAssertEqual(try db.currentTopicAssignment(turnRef: source.turnRef)?.status, .nonTopic)
        XCTAssertThrowsError(try db.rawExec("DELETE FROM topic_assignment;"))
        XCTAssertEqual(try db.topicAssignments(turnRef: source.turnRef).count, 2)
    }

    func testPendingSemanticsIncludesFoldedReuseAndIsSessionScoped() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let first = try seedTurn(db, session: "folded", turn: 1, question: "brief 设计")
        let folded = try seedTurn(
            db, session: "folded", turn: 2, question: "brief 设计", withDigest: false)
        _ = try seedTurn(db, session: "other", turn: 1, question: "你好")
        XCTAssertEqual(try db.fillFoldedReuseDigests(sessionID: "folded").map(\.turn), [2])
        XCTAssertEqual(try db.turnDigest(sessionID: "folded", turnIndex: 2)?.digest,
                       try db.turnDigest(sessionID: "folded", turnIndex: 1)?.digest)

        let pending = try db.turnsNeedingTopicSemantics(sessionID: "folded")
        XCTAssertEqual(pending.map(\.turnIndex), [1, 2])
        XCTAssertEqual(pending.map(\.question), ["brief 设计", "brief 设计"])
        XCTAssertEqual(try db.turnsNeedingTopicSemantics(limit: 1).first?.sessionID, "folded")
        XCTAssertNil(try db.turnsNeedingTopicSemantics(sessionID: "missing").first)

        let route = try TopicSemanticRoute(status: .ambiguous, topicID: nil)
        try db.publishTopicSemantics(
            try publication(source: first, semantics: "brief 话题", route: route), source: first)
        try db.publishTopicSemantics(
            try publication(source: folded, semantics: "brief 话题", route: route), source: folded)
        XCTAssertTrue(try db.turnsNeedingTopicSemantics(sessionID: "folded").isEmpty)
        XCTAssertEqual(try db.turnsNeedingTopicSemantics(sessionID: "other").map(\.turnIndex), [1])
    }

    func testPriorSemanticContextIsChronologicalBoundedAndExcludesCurrentTurn() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        for turn in 1...3 {
            _ = try seedTurn(
                db, session: "history", turn: turn,
                question: "问题\(turn)", answer: "回答\(turn)")
        }
        _ = try seedTurn(db, session: "unrelated", turn: 1, question: "外来内容")
        let context = try db.topicSemanticContext(sessionID: "history", before: 3, limit: 2)
        XCTAssertEqual(context.map(\.turnRef), ["history#1", "history#2"])
        XCTAssertEqual(context.map(\.text), ["用户：问题1\n助手：回答1", "用户：问题2\n助手：回答2"])
        XCTAssertTrue(try db.topicSemanticContext(sessionID: "history", before: 1).isEmpty)
        XCTAssertTrue(try db.topicSemanticContext(sessionID: "history", before: 3, limit: 0).isEmpty)
    }

    func testPublicationRejectsGenesisOutsideNewTopicAndClarificationOutsideAssignment() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        let source = try seedTurn(db, session: "publication", turn: 1, question: "brief")
        let genesis = try TopicGenesisRecord(
            topicID: "brief", definingParagraph: "讨论 brief 的话题定义。",
            title: "brief", seedRefs: [source.turnRef], reconstructed: false,
            createdAt: "2026-11-28T12:00:00Z")
        let clarification = try TopicScopeClarificationRecord(
            clarificationID: "clarify-brief", topicID: "brief",
            clarification: "只讨论话题身份。", sourceRefs: [source.turnRef],
            createdAt: "2026-11-28T12:00:00Z")
        let ambiguous = try TopicSemanticRoute(status: .ambiguous, topicID: nil)
        XCTAssertThrowsError(try publication(
            source: source, semantics: "brief", route: ambiguous, genesis: genesis)) {
            XCTAssertEqual($0 as? TopicSemanticError, .unexpectedGenesis)
        }
        XCTAssertThrowsError(try publication(
            source: source, semantics: "brief", route: ambiguous,
            clarification: clarification)) {
            XCTAssertEqual($0 as? TopicSemanticError, .invalidClarification)
        }
        XCTAssertThrowsError(try publication(
            source: source, semantics: "brief",
            route: TopicSemanticRoute(status: .newTopic, topicID: "other"), genesis: genesis)) {
            XCTAssertEqual($0 as? TopicSemanticError, .publicationTopicMismatch)
        }
        XCTAssertTrue(try db.allTopicGeneses().isEmpty)
    }

    func testMissingPastEvidenceReferenceRejectsWholePublication() throws {
        let (url, db) = try open()
        defer { db.close(); cleanup(url) }
        _ = try seedTurn(db, session: "gaps", turn: 1, question: "第一轮")
        let source = try seedTurn(db, session: "gaps", turn: 3, question: "第三轮")
        XCTAssertThrowsError(try db.publishTopicSemantics(
            try publication(
                source: source, semantics: "第三轮",
                route: TopicSemanticRoute(status: .ambiguous, topicID: nil),
                contextRefs: ["gaps#2"]),
            source: source)) {
            XCTAssertEqual($0 as? TopicSemanticPersistenceError, .invalidEvidenceReference("gaps#2"))
        }
        XCTAssertNil(try db.turnSemanticObservation(turnRef: source.turnRef))
    }

    func testWireAcceptsBareJSONAndRejectsFencesUnknownTopicsAndInvalidGenesis() throws {
        let genesis = try TopicGenesisRecord(
            topicID: "brief", definingParagraph: "讨论 brief 的话题定义与实现。",
            title: "brief", seedRefs: ["source#1"], reconstructed: false,
            createdAt: "2026-11-28T12:00:00Z")
        let topics = [try EffectiveTopicDefinition(genesis: genesis, clarifications: [])]
        let assigned = """
        {"approximate_semantics":"继续 brief 归属实现","status":"assigned","topic_id":"brief","candidate_topic_ids":["brief"],"defining_paragraph":null,"title":null,"clarification":null}
        """
        let result = try TopicSemanticWire.parse(assigned, topics: topics)
        XCTAssertEqual(result.route.status, .assigned)
        XCTAssertEqual(result.route.topicID, "brief")

        XCTAssertThrowsError(try TopicSemanticWire.parse("```json\n\(assigned)\n```", topics: topics)) {
            XCTAssertEqual($0 as? TopicSemanticWireError, .malformedJSON)
        }
        XCTAssertThrowsError(try TopicSemanticWire.parse(
            assigned.replacingOccurrences(of: "\"brief\"", with: "\"unknown\""), topics: topics)) {
            XCTAssertEqual($0 as? TopicSemanticWireError, .unknownTopic("unknown"))
        }
        XCTAssertThrowsError(try TopicSemanticWire.parse(
            """
            {"approximate_semantics":"新话题","status":"new-topic","topic_id":null,"candidate_topic_ids":[],"defining_paragraph":null,"title":"新话题","clarification":null}
            """, topics: topics)) {
            XCTAssertEqual($0 as? TopicSemanticWireError, .missingNewTopicDefinition)
        }
        XCTAssertThrowsError(try TopicSemanticWire.parse(
            """
            {"approximate_semantics":"非话题","status":"non-topic","topic_id":"brief","candidate_topic_ids":[],"defining_paragraph":null,"title":null,"clarification":null}
            """, topics: topics)) {
            XCTAssertEqual($0 as? TopicSemanticWireError, .invalidRoute)
        }
    }

    func testWireCreatesGenesisDefinitionOnlyForNewTopic() throws {
        let result = try TopicSemanticWire.parse(
            """
            {"approximate_semantics":"开始讨论新的发布流程","status":"new-topic","topic_id":null,"candidate_topic_ids":[],"defining_paragraph":"讨论软件发布的准备、验证与回滚。","title":"发布流程","clarification":null}
            """, topics: [])
        XCTAssertEqual(result.route.status, .newTopic)
        XCTAssertEqual(result.newTopic?.definingParagraph, "讨论软件发布的准备、验证与回滚。")
        XCTAssertEqual(result.route.topicID, "pending-new-topic")
    }
}
