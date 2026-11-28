import Foundation
import SQLite3

public enum TopicSemanticPersistenceError: Error, Equatable {
    case immutableConflict(kind: String, id: String)
    case futureEvidence(String)
    case invalidEvidenceReference(String)
    case missingTopic(String)
    case malformedStoredRecord(String)
}

public extension ESISDatabase {
    func turnsNeedingTopicSemantics(
        sessionID: String? = nil, limit: Int = 20
    ) throws -> [UndigestedTurn] {
        let stmt = try prepare("""
        SELECT l.session_id, l.turn_index,
               (SELECT m.id FROM chat_messages m
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='user' LIMIT 1),
               (SELECT m.id FROM chat_messages m
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='assistant' LIMIT 1),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='user' LIMIT 1),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='assistant' LIMIT 1)
          FROM chat_turn_ledger l
         WHERE \(Self.digestableTurnSourcePredicate)
           AND EXISTS (SELECT 1 FROM turn_digests d
                        WHERE d.session_id=l.session_id AND d.turn_index=l.turn_index)
           AND NOT EXISTS (SELECT 1 FROM turn_semantics s
                            WHERE s.turn_ref=l.session_id || '#' || l.turn_index)
           AND (? IS NULL OR l.session_id=?)
         ORDER BY l.session_id, l.turn_index LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, sessionID)
        try bind(stmt, 3, Int64(max(0, limit)))
        var rows: [UndigestedTurn] = []
        while try stepRowOrDone(stmt) {
            func text(_ index: Int32) -> String? {
                sqlite3_column_text(stmt, index).map { String(cString: $0) }
            }
            rows.append(UndigestedTurn(
                sessionID: text(0) ?? "",
                turnIndex: Int(sqlite3_column_int64(stmt, 1)),
                questionMessageID: sqlite3_column_type(stmt, 2) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 2),
                answerMessageID: sqlite3_column_type(stmt, 3) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 3),
                question: text(4) ?? "",
                answer: text(5) ?? ""))
        }
        return rows
    }

    func topicSemanticContext(
        sessionID: String, before turnIndex: Int, limit: Int = 6
    ) throws -> [TopicSemanticContext] {
        let stmt = try prepare("""
        SELECT l.turn_index,
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='user' LIMIT 1),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='assistant' LIMIT 1)
          FROM chat_turn_ledger l
         WHERE l.session_id=? AND l.turn_index<?
           AND \(Self.digestableTurnSourcePredicate)
         ORDER BY l.turn_index DESC LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        try bind(stmt, 3, Int64(max(0, limit)))
        var rows: [(Int, TopicSemanticContext)] = []
        while try stepRowOrDone(stmt) {
            let index = Int(sqlite3_column_int64(stmt, 0))
            let question = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let answer = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            rows.append((index, try TopicSemanticContext(
                turnRef: "\(sessionID)#\(index)",
                text: "用户：\(question)\n助手：\(answer)")))
        }
        return rows.sorted { $0.0 < $1.0 }.map(\.1)
    }

    func publishTopicSemantics(
        _ publication: TopicSemanticPublication,
        source: TopicSemanticSource
    ) throws {
        try transactionResult {
            try verifyTurnDigestSource(
                sessionID: source.sessionID,
                turnIndex: source.turnIndex,
                expectedQuestionSHA256: source.expectedQuestionSHA256,
                expectedAnswerSHA256: source.expectedAnswerSHA256)
            guard publication.observation.turnRef == source.turnRef,
                  publication.assignment.turnRef == source.turnRef else {
                throw TopicSemanticPersistenceError.invalidEvidenceReference(source.turnRef)
            }
            try validateCausalRefs(publication, source: source)

            if let genesis = publication.genesis {
                try insertGenesisIfAbsent(genesis)
            }
            if publication.assignment.status == .newTopic, publication.genesis == nil {
                throw TopicSemanticPersistenceError.missingTopic(
                    publication.assignment.topicID ?? "new-topic")
            }
            if let topicID = publication.assignment.topicID,
               try topicGenesis(topicID: topicID) == nil {
                throw TopicSemanticPersistenceError.missingTopic(topicID)
            }
            for candidate in publication.assignment.candidateTopicIDs {
                if try topicGenesis(topicID: candidate) == nil {
                    throw TopicSemanticPersistenceError.missingTopic(candidate)
                }
            }
            if let clarification = publication.clarification {
                if try topicGenesis(topicID: clarification.topicID) == nil {
                    throw TopicSemanticPersistenceError.missingTopic(clarification.topicID)
                }
                try insertClarificationIfAbsent(clarification)
            }
            try insertObservationIfAbsent(publication.observation)
            try insertAssignmentIfAbsent(publication.assignment)
        }
    }

    func topicGenesis(topicID: String) throws -> TopicGenesisRecord? {
        let stmt = try prepare("""
        SELECT topic_id, defining_paragraph, title, seed_refs_json, reconstructed, created_at
          FROM topic_genesis WHERE topic_id=? LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, topicID)
        guard try stepRowOrDone(stmt) else { return nil }
        return try TopicGenesisRecord(
            topicID: columnText(stmt, 0),
            definingParagraph: columnText(stmt, 1),
            title: columnText(stmt, 2),
            seedRefs: decodeStrings(stmt, 3),
            reconstructed: sqlite3_column_int64(stmt, 4) != 0,
            createdAt: columnText(stmt, 5))
    }

    func allTopicGeneses() throws -> [TopicGenesisRecord] {
        let stmt = try prepare("SELECT topic_id FROM topic_genesis ORDER BY created_at, topic_id;")
        defer { sqlite3_finalize(stmt) }
        var ids: [String] = []
        while try stepRowOrDone(stmt) { ids.append(columnText(stmt, 0)) }
        return try ids.map { topicID in
            guard let record = try topicGenesis(topicID: topicID) else {
                throw TopicSemanticPersistenceError.malformedStoredRecord(topicID)
            }
            return record
        }
    }

    func effectiveTopicDefinition(topicID: String) throws -> EffectiveTopicDefinition? {
        guard let genesis = try topicGenesis(topicID: topicID) else { return nil }
        let stmt = try prepare("""
        SELECT clarification_id, topic_id, clarification, source_refs_json, created_at
          FROM topic_scope_clarification
         WHERE topic_id=? ORDER BY rowid;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, topicID)
        var clarifications: [TopicScopeClarificationRecord] = []
        while try stepRowOrDone(stmt) {
            clarifications.append(try TopicScopeClarificationRecord(
                clarificationID: columnText(stmt, 0),
                topicID: columnText(stmt, 1),
                clarification: columnText(stmt, 2),
                sourceRefs: decodeStrings(stmt, 3),
                createdAt: columnText(stmt, 4)))
        }
        return try EffectiveTopicDefinition(genesis: genesis, clarifications: clarifications)
    }

    func allEffectiveTopicDefinitions() throws -> [EffectiveTopicDefinition] {
        try allTopicGeneses().compactMap { genesis in
            guard let definition = try effectiveTopicDefinition(topicID: genesis.topicID) else {
                throw TopicSemanticPersistenceError.malformedStoredRecord(genesis.topicID)
            }
            return definition
        }
    }

    func turnSemanticObservation(turnRef: String) throws -> TurnSemanticObservation? {
        let stmt = try prepare("""
        SELECT turn_ref, approximate_semantics, context_refs_json
          FROM turn_semantics WHERE turn_ref=? LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, turnRef)
        guard try stepRowOrDone(stmt) else { return nil }
        return try TurnSemanticObservation(
            turnRef: columnText(stmt, 0),
            approximateSemantics: columnText(stmt, 1),
            contextRefs: decodeStrings(stmt, 2))
    }

    func topicAssignments(turnRef: String) throws -> [TopicAssignmentRecord] {
        let stmt = try prepare("""
        SELECT assignment_id, turn_ref, topic_id, status, candidate_topic_ids_json,
               evidence_refs_json, created_at
          FROM topic_assignment
         WHERE turn_ref=? ORDER BY rowid;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, turnRef)
        var records: [TopicAssignmentRecord] = []
        while try stepRowOrDone(stmt) {
            let rawStatus = columnText(stmt, 3)
            guard let status = TopicAssignmentStatus(rawValue: rawStatus) else {
                throw TopicSemanticPersistenceError.malformedStoredRecord(rawStatus)
            }
            records.append(try TopicAssignmentRecord(
                assignmentID: columnText(stmt, 0),
                turnRef: columnText(stmt, 1),
                topicID: optionalColumnText(stmt, 2),
                status: status,
                candidateTopicIDs: decodeStrings(stmt, 4),
                evidenceRefs: decodeStrings(stmt, 5),
                createdAt: columnText(stmt, 6)))
        }
        return records
    }

    func currentTopicAssignment(turnRef: String) throws -> TopicAssignmentRecord? {
        let stmt = try prepare("""
        SELECT assignment_id FROM topic_assignment
         WHERE turn_ref=? ORDER BY rowid DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, turnRef)
        guard try stepRowOrDone(stmt) else { return nil }
        return try topicAssignments(turnRef: turnRef).last
    }

    private func insertGenesisIfAbsent(_ record: TopicGenesisRecord) throws {
        if let existing = try topicGenesis(topicID: record.topicID) {
            guard existing == record else {
                throw TopicSemanticPersistenceError.immutableConflict(
                    kind: "topic_genesis", id: record.topicID)
            }
            return
        }
        try execBinding("""
        INSERT INTO topic_genesis(
            topic_id, defining_paragraph, title, seed_refs_json, reconstructed, created_at)
        VALUES(?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, record.topicID)
            try bind(stmt, 2, record.definingParagraph)
            try bind(stmt, 3, record.title)
            try bind(stmt, 4, encodeStrings(record.seedRefs))
            try bind(stmt, 5, Int64(record.reconstructed ? 1 : 0))
            try bind(stmt, 6, record.createdAt)
        }
    }

    private func insertClarificationIfAbsent(_ record: TopicScopeClarificationRecord) throws {
        if try clarificationExists(record.clarificationID) {
            guard try clarification(record.clarificationID) == record else {
                throw TopicSemanticPersistenceError.immutableConflict(
                    kind: "topic_scope_clarification", id: record.clarificationID)
            }
            return
        }
        try execBinding("""
        INSERT INTO topic_scope_clarification(
            clarification_id, topic_id, clarification, source_refs_json, created_at)
        VALUES(?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, record.clarificationID)
            try bind(stmt, 2, record.topicID)
            try bind(stmt, 3, record.clarification)
            try bind(stmt, 4, encodeStrings(record.sourceRefs))
            try bind(stmt, 5, record.createdAt)
        }
    }

    private func insertObservationIfAbsent(_ record: TurnSemanticObservation) throws {
        if let existing = try turnSemanticObservation(turnRef: record.turnRef) {
            guard existing == record else {
                throw TopicSemanticPersistenceError.immutableConflict(
                    kind: "turn_semantics", id: record.turnRef)
            }
            return
        }
        try execBinding("""
        INSERT INTO turn_semantics(turn_ref, approximate_semantics, context_refs_json)
        VALUES(?,?,?);
        """) { stmt in
            try bind(stmt, 1, record.turnRef)
            try bind(stmt, 2, record.approximateSemantics)
            try bind(stmt, 3, encodeStrings(record.contextRefs))
        }
    }

    private func insertAssignmentIfAbsent(_ record: TopicAssignmentRecord) throws {
        if try assignmentExists(record.assignmentID) {
            let existing = try topicAssignments(turnRef: record.turnRef).first {
                $0.assignmentID == record.assignmentID
            }
            guard existing == record else {
                throw TopicSemanticPersistenceError.immutableConflict(
                    kind: "topic_assignment", id: record.assignmentID)
            }
            return
        }
        try execBinding("""
        INSERT INTO topic_assignment(
            assignment_id, turn_ref, topic_id, status, candidate_topic_ids_json,
            evidence_refs_json, created_at)
        VALUES(?,?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, record.assignmentID)
            try bind(stmt, 2, record.turnRef)
            try bind(stmt, 3, record.topicID)
            try bind(stmt, 4, record.status.rawValue)
            try bind(stmt, 5, encodeStrings(record.candidateTopicIDs))
            try bind(stmt, 6, encodeStrings(record.evidenceRefs))
            try bind(stmt, 7, record.createdAt)
        }
    }

    private func validateCausalRefs(
        _ publication: TopicSemanticPublication,
        source: TopicSemanticSource
    ) throws {
        let refs = publication.observation.contextRefs
            + publication.assignment.evidenceRefs
            + (publication.genesis?.seedRefs ?? [])
            + (publication.clarification?.sourceRefs ?? [])
        for ref in refs {
            let parts = ref.split(separator: "#", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == Substring(source.sessionID),
                  let turn = Int(parts[1]) else {
                throw TopicSemanticPersistenceError.invalidEvidenceReference(ref)
            }
            guard turn > 0, turn <= source.turnIndex else {
                throw TopicSemanticPersistenceError.futureEvidence(ref)
            }
            let stmt = try prepare("""
            SELECT COUNT(*) FROM chat_turn_ledger l
             WHERE l.session_id=? AND l.turn_index=?
               AND \(Self.digestableTurnSourcePredicate);
            """)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, source.sessionID)
            try bind(stmt, 2, Int64(turn))
            guard try stepRowOrDone(stmt), sqlite3_column_int64(stmt, 0) == 1 else {
                throw TopicSemanticPersistenceError.invalidEvidenceReference(ref)
            }
        }
    }

    private func clarificationExists(_ id: String) throws -> Bool {
        let stmt = try prepare("SELECT 1 FROM topic_scope_clarification WHERE clarification_id=? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, id)
        return try stepRowOrDone(stmt)
    }

    private func clarification(_ id: String) throws -> TopicScopeClarificationRecord? {
        let stmt = try prepare("""
        SELECT clarification_id, topic_id, clarification, source_refs_json, created_at
          FROM topic_scope_clarification WHERE clarification_id=? LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, id)
        guard try stepRowOrDone(stmt) else { return nil }
        return try TopicScopeClarificationRecord(
            clarificationID: columnText(stmt, 0),
            topicID: columnText(stmt, 1),
            clarification: columnText(stmt, 2),
            sourceRefs: decodeStrings(stmt, 3),
            createdAt: columnText(stmt, 4))
    }

    private func assignmentExists(_ id: String) throws -> Bool {
        let stmt = try prepare("SELECT 1 FROM topic_assignment WHERE assignment_id=? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, id)
        return try stepRowOrDone(stmt)
    }

    private func encodeStrings(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TopicSemanticPersistenceError.malformedStoredRecord("json-encode")
        }
        return text
    }

    private func decodeStrings(_ stmt: OpaquePointer, _ index: Int32) throws -> [String] {
        guard let data = sqlite3_column_text(stmt, index).map({
            Data(bytes: $0, count: Int(sqlite3_column_bytes(stmt, index)))
        }) else {
            throw TopicSemanticPersistenceError.malformedStoredRecord("json-null")
        }
        let values: [String]
        do {
            values = try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw TopicSemanticPersistenceError.malformedStoredRecord("json-decode")
        }
        return values
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
    }

    private func optionalColumnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(stmt, index).map { String(cString: $0) }
    }
}
