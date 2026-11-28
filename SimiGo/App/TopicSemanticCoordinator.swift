import Foundation
import SimiGoRuntimeContract

enum TopicSemanticCoordinator {
    static var interpreter: TopicSemanticInterpreter = LocalModelTopicSemanticInterpreter()
    static var generate: @Sendable (String) async throws -> String = { prompt in
        try await TurnDigestScheduler.generateTopicSemantic(prompt)
    }

    @discardableResult
    static func processNext(sessionID: String) async throws -> Bool {
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        defer { db.close() }
        guard let turn = try db.turnsNeedingTopicSemantics(
            sessionID: sessionID, limit: 1).first else { return false }
        let topics = try db.allEffectiveTopicDefinitions()
        let context = try db.topicSemanticContext(
            sessionID: turn.sessionID, before: turn.turnIndex)
        let hashes = try db.turnSourceHashes(sessionID: turn.sessionID)
        guard let hash = hashes[turn.turnIndex] else {
            throw TopicSemanticPersistenceError.invalidEvidenceReference(
                "\(turn.sessionID)#\(turn.turnIndex)")
        }
        let source = try TopicSemanticSource(
            sessionID: turn.sessionID, turnIndex: turn.turnIndex,
            expectedQuestionSHA256: hash.question,
            expectedAnswerSHA256: hash.answer)
        let request = try TopicSemanticRequest(
            turnRef: source.turnRef,
            currentText: turn.question.isEmpty ? "（空用户消息）" : turn.question,
            context: context,
            topics: topics,
            responseText: turn.answer)
        let result = try await interpreter.interpret(request)
        let now = ISO8601DateFormatter().string(from: Date())
        let route = result.route
        let topicID: String?
        let genesis: TopicGenesisRecord?
        if route.status == .newTopic {
            let generatedID = "topic-\(UUID().uuidString.lowercased())"
            guard let definition = result.newTopic else {
                throw TopicSemanticWireError.missingNewTopicDefinition
            }
            topicID = generatedID
            genesis = try TopicGenesisRecord(
                topicID: generatedID,
                definingParagraph: definition.definingParagraph,
                title: definition.title,
                seedRefs: [source.turnRef],
                reconstructed: false,
                createdAt: now)
        } else {
            topicID = route.topicID
            genesis = nil
        }
        let clarification: TopicScopeClarificationRecord?
        if let text = result.clarification, let topicID {
            clarification = try TopicScopeClarificationRecord(
                clarificationID: "topic-clarification-\(UUID().uuidString.lowercased())",
                topicID: topicID,
                clarification: text,
                sourceRefs: [source.turnRef],
                createdAt: now)
        } else {
            clarification = nil
        }
        let publication = try TopicSemanticPublication(
            genesis: genesis,
            clarification: clarification,
            observation: TurnSemanticObservation(
                turnRef: source.turnRef,
                approximateSemantics: result.approximateSemantics,
                contextRefs: context.map(\.turnRef)),
            assignment: TopicAssignmentRecord(
                assignmentID: "topic-assignment-\(UUID().uuidString.lowercased())",
                turnRef: source.turnRef,
                topicID: topicID,
                status: route.status,
                candidateTopicIDs: route.candidateTopicIDs,
                evidenceRefs: [source.turnRef],
                createdAt: now))
        try db.publishTopicSemantics(publication, source: source)
        RuntimeTraceLogger.shared.trace(
            "[TOPIC_SEMANTICS] session=\(RuntimeTraceLogger.short(turn.sessionID)) "
                + "turn=\(turn.turnIndex) status=\(route.status.rawValue) "
                + "topic=\(topicID ?? "-")")
        return true
    }
}

private struct LocalModelTopicSemanticInterpreter: TopicSemanticInterpreter {
    func interpret(_ request: TopicSemanticRequest) async throws -> TopicSemanticInterpretation {
        let raw = try await TopicSemanticCoordinator.generate(TopicSemanticWire.prompt(request))
        return try TopicSemanticWire.parse(raw, topics: request.topics)
    }
}
