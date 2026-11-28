import Foundation
import SQLite3

public enum TopicAssignmentKind: String, Codable, Sendable {
    case assigned
    case nonTopic = "non-topic"
    case unassigned
    case ambiguous
}

public struct TopicSourceReference: Codable, Equatable, Sendable {
    public let kind: String
    public let identifier: String
    public let sha256: String?

    public init(kind: String, identifier: String, sha256: String? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.sha256 = sha256
    }
}

public struct TopicGenesis: Codable, Equatable, Sendable {
    public let topicID: String
    public let scope: String
    public let clientIdentityID: String
    public let genesisKey: String
    public let title: String
    public let definingParagraph: String
    public let initialQuestion: String?
    public let reconstructed: Bool
    public let createdAt: String
    public let definingParagraphObjectID: String
}

public struct TopicAliasRecord: Codable, Equatable, Sendable {
    public let aliasID: String
    public let topicID: String
    public let aliasKey: String
    public let alias: String
    public let recordedAt: String
}

public struct TopicSegmentRecord: Codable, Equatable, Sendable {
    public let segmentID: String
    public let topicID: String
    public let parentSegmentID: String?
    public let segmentOrdinal: Int
    public let openingEventKey: String
    public let openedAt: String
}

public struct TopicEventRecord: Codable, Equatable, Sendable {
    public let eventID: String
    public let topicID: String
    public let segmentID: String
    public let eventKey: String
    public let kind: String
    public let payloadObjectID: String?
    public let recordedAt: String
}

public struct TopicDeltaRecord: Codable, Equatable, Sendable {
    public let deltaID: String
    public let topicID: String
    public let segmentID: String
    public let deltaKey: String
    public let sequence: Int
    public let kind: String
    public let payload: [String: String]
    public let sourceReferences: [TopicSourceReference]
    public let approximateSemantics: String?
    public let recordedAt: String
}

public struct TopicAssignmentRecord: Codable, Equatable, Sendable {
    public let assignmentID: String
    public let topicID: String?
    public let segmentID: String?
    public let scope: String
    public let clientIdentityID: String
    public let assignmentKey: String
    public let sessionID: String
    public let requestID: String?
    public let stateID: String?
    public let settlementID: String?
    public let windowID: String?
    public let approximateSemantics: String
    public let assignment: TopicAssignmentKind
    public let method: String
    public let sourceReferences: [TopicSourceReference]
    public let recordedAt: String
}

public struct TopicChainSnapshot: Codable, Equatable, Sendable {
    public let genesis: TopicGenesis
    public let aliases: [TopicAliasRecord]
    public let segments: [TopicSegmentRecord]
    public let events: [TopicEventRecord]
    public let deltas: [TopicDeltaRecord]
    public let assignments: [TopicAssignmentRecord]
}

extension ESISDatabase {
    private func topicRequired(_ value: String, _ field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DatabaseError.sql("topic \(field) must not be empty")
        }
        return trimmed
    }

    private func topicEncode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func topicText(_ objectID: String) throws -> String {
        String(decoding: try readObject(objectID), as: UTF8.self)
    }

    private func topicEvent(_ stmt: OpaquePointer) -> TopicEventRecord {
        func text(_ index: Int32) -> String {
            sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
        }
        func optionalText(_ index: Int32) -> String? {
            sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : text(index)
        }
        return TopicEventRecord(
            eventID: text(0), topicID: text(1), segmentID: text(2),
            eventKey: text(3), kind: text(4), payloadObjectID: optionalText(5),
            recordedAt: text(6))
    }

    private func topicSegment(_ stmt: OpaquePointer) -> TopicSegmentRecord {
        func text(_ index: Int32) -> String {
            sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
        }
        return TopicSegmentRecord(
            segmentID: text(0), topicID: text(1),
            parentSegmentID: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : text(2),
            segmentOrdinal: Int(sqlite3_column_int64(stmt, 3)),
            openingEventKey: text(4), openedAt: text(5))
    }

    private func topicOpenSegment(topicID: String) throws -> TopicSegmentRecord? {
        let stmt = try prepare("""
        SELECT s.segment_id, s.topic_id, s.parent_segment_id, s.segment_ordinal,
               s.opening_event_key, s.opened_at
          FROM topic_segments s
         WHERE s.topic_id=?
           AND NOT EXISTS (
               SELECT 1 FROM topic_events e
                WHERE e.segment_id=s.segment_id AND e.kind='fork_point')
         ORDER BY s.segment_ordinal DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, topicID)
        return try stepRowOrDone(stmt) ? topicSegment(stmt) : nil
    }

    @discardableResult
    public func beginTopic(
        scope: String = ESISDatabase.ownerNamespace,
        clientIdentityID: String,
        genesisKey: String,
        topicID: String = UUID().uuidString.lowercased(),
        title: String,
        definingParagraph: String,
        initialQuestion: String? = nil,
        reconstructed: Bool = false,
        createdAt: Date = Date()
    ) throws -> TopicGenesis {
        let scope = try topicRequired(scope, "scope")
        let clientIdentityID = try topicRequired(clientIdentityID, "client_identity_id")
        let genesisKey = try topicRequired(genesisKey, "genesis_key")
        let topicID = try topicRequired(topicID, "topic_id")
        let title = try topicRequired(title, "title")
        let definingParagraph = try topicRequired(definingParagraph, "defining_paragraph")
        let createdAt = Self.stamp(createdAt)

        return try transactionResult {
            let existing = try prepare("""
            SELECT topic_id, scope, client_identity_id, genesis_key, title,
                   defining_paragraph_object_id, initial_question, reconstructed, created_at
              FROM topic_chains WHERE scope=? AND client_identity_id=? AND genesis_key=?;
            """)
            defer { sqlite3_finalize(existing) }
            try bind(existing, 1, scope)
            try bind(existing, 2, clientIdentityID)
            try bind(existing, 3, genesisKey)
            if try stepRowOrDone(existing) {
                func text(_ index: Int32) -> String {
                    sqlite3_column_text(existing, index).map { String(cString: $0) } ?? ""
                }
                let storedQuestion = sqlite3_column_type(existing, 6) == SQLITE_NULL ? nil : text(6)
                let storedParagraphObjectID = text(5)
                let storedParagraph = try self.topicText(storedParagraphObjectID)
                guard text(4) == title,
                      storedParagraph == definingParagraph,
                      storedQuestion == initialQuestion,
                      (text(7) == "1") == reconstructed else {
                    throw DatabaseError.sql("topic genesis key conflicts with existing genesis")
                }
                return TopicGenesis(
                    topicID: text(0), scope: text(1), clientIdentityID: text(2),
                    genesisKey: text(3), title: text(4), definingParagraph: storedParagraph,
                    initialQuestion: storedQuestion, reconstructed: text(7) == "1",
                    createdAt: text(8), definingParagraphObjectID: storedParagraphObjectID)
            }

            let objectID = try ensureObject(Data(definingParagraph.utf8))
            try execBinding("""
            INSERT INTO topic_chains(
                topic_id, scope, client_identity_id, genesis_key, title,
                defining_paragraph_object_id, initial_question, reconstructed, created_at)
            VALUES(?,?,?,?,?,?,?,?,?);
            """) { stmt in
                try self.bind(stmt, 1, topicID)
                try self.bind(stmt, 2, scope)
                try self.bind(stmt, 3, clientIdentityID)
                try self.bind(stmt, 4, genesisKey)
                try self.bind(stmt, 5, title)
                try self.bind(stmt, 6, objectID)
                try self.bind(stmt, 7, initialQuestion)
                try self.bind(stmt, 8, reconstructed ? 1 : 0)
                try self.bind(stmt, 9, createdAt)
            }

            let segmentID = UUID().uuidString.lowercased()
            try execBinding("""
            INSERT INTO topic_segments(
                segment_id, topic_id, parent_segment_id, segment_ordinal,
                opening_event_key, opened_at)
            VALUES(?,?,NULL,1,?,?);
            """) { stmt in
                try self.bind(stmt, 1, segmentID)
                try self.bind(stmt, 2, topicID)
                try self.bind(stmt, 3, "\(genesisKey):open")
                try self.bind(stmt, 4, createdAt)
            }
            for (kind, key) in [("genesis", "\(genesisKey):genesis"),
                                ("segment_opened", "\(genesisKey):open")] {
                try execBinding("""
                INSERT INTO topic_events(
                    event_id, topic_id, segment_id, event_key, kind,
                    payload_object_id, recorded_at)
                VALUES(?,?,?,?,?,?,?);
                """) { stmt in
                    try self.bind(stmt, 1, UUID().uuidString.lowercased())
                    try self.bind(stmt, 2, topicID)
                    try self.bind(stmt, 3, segmentID)
                    try self.bind(stmt, 4, key)
                    try self.bind(stmt, 5, kind)
                    try self.bind(stmt, 6, objectID)
                    try self.bind(stmt, 7, createdAt)
                }
            }
            return TopicGenesis(
                topicID: topicID, scope: scope, clientIdentityID: clientIdentityID,
                genesisKey: genesisKey, title: title, definingParagraph: definingParagraph,
                initialQuestion: initialQuestion, reconstructed: reconstructed,
                createdAt: createdAt, definingParagraphObjectID: objectID)
        }
    }

    @discardableResult
    public func appendTopicAlias(
        topicID: String,
        aliasKey: String,
        alias: String,
        recordedAt: Date = Date()
    ) throws -> TopicAliasRecord {
        let topicID = try topicRequired(topicID, "topic_id")
        let aliasKey = try topicRequired(aliasKey, "alias_key")
        let alias = try topicRequired(alias, "alias")
        let recordedAt = Self.stamp(recordedAt)
        return try transactionResult {
            let existing = try prepare("""
            SELECT alias_id, topic_id, alias_key, alias, recorded_at
              FROM topic_aliases WHERE topic_id=? AND alias_key=?;
            """)
            defer { sqlite3_finalize(existing) }
            try self.bind(existing, 1, topicID)
            try self.bind(existing, 2, aliasKey)
            if try self.stepRowOrDone(existing) {
                let storedAlias = sqlite3_column_text(existing, 3).map { String(cString: $0) } ?? ""
                guard storedAlias == alias else {
                    throw DatabaseError.sql("topic alias key conflicts with existing alias")
                }
                return TopicAliasRecord(
                    aliasID: sqlite3_column_text(existing, 0).map { String(cString: $0) } ?? "",
                    topicID: topicID, aliasKey: aliasKey, alias: storedAlias,
                    recordedAt: sqlite3_column_text(existing, 4).map { String(cString: $0) } ?? "")
            }
            let chain = try prepare("SELECT 1 FROM topic_chains WHERE topic_id=?;")
            defer { sqlite3_finalize(chain) }
            try self.bind(chain, 1, topicID)
            guard try self.stepRowOrDone(chain) else {
                throw DatabaseError.sql("unknown topic \(topicID)")
            }
            let aliasID = UUID().uuidString.lowercased()
            try execBinding("""
            INSERT INTO topic_aliases(alias_id, topic_id, alias_key, alias, recorded_at)
            VALUES(?,?,?,?,?);
            """) { stmt in
                try self.bind(stmt, 1, aliasID)
                try self.bind(stmt, 2, topicID)
                try self.bind(stmt, 3, aliasKey)
                try self.bind(stmt, 4, alias)
                try self.bind(stmt, 5, recordedAt)
            }
            return TopicAliasRecord(
                aliasID: aliasID, topicID: topicID, aliasKey: aliasKey,
                alias: alias, recordedAt: recordedAt)
        }
    }

    @discardableResult
    public func leaveTopic(
        topicID: String,
        eventKey: String,
        recordedAt: Date = Date()
    ) throws -> TopicEventRecord {
        let topicID = try topicRequired(topicID, "topic_id")
        let eventKey = try topicRequired(eventKey, "event_key")
        let recordedAt = Self.stamp(recordedAt)
        return try transactionResult {
            let existing = try prepare("""
            SELECT event_id, topic_id, segment_id, event_key, kind,
                   payload_object_id, recorded_at
              FROM topic_events WHERE topic_id=? AND event_key=?;
            """)
            defer { sqlite3_finalize(existing) }
            try self.bind(existing, 1, topicID)
            try self.bind(existing, 2, eventKey)
            if try self.stepRowOrDone(existing) {
                let event = self.topicEvent(existing)
                guard event.kind == "fork_point" else {
                    throw DatabaseError.sql("topic event key conflicts with existing event")
                }
                return event
            }
            guard let segment = try self.topicOpenSegment(topicID: topicID) else {
                throw DatabaseError.sql("topic \(topicID) has no open segment")
            }
            let payloadObjectID = try ensureObject(try self.topicEncode([
                "closedAt": recordedAt,
                "segmentID": segment.segmentID,
            ]))
            let event = TopicEventRecord(
                eventID: UUID().uuidString.lowercased(), topicID: topicID,
                segmentID: segment.segmentID, eventKey: eventKey, kind: "fork_point",
                payloadObjectID: payloadObjectID, recordedAt: recordedAt)
            try execBinding("""
            INSERT INTO topic_events(
                event_id, topic_id, segment_id, event_key, kind,
                payload_object_id, recorded_at)
            VALUES(?,?,?,?,?,?,?);
            """) { stmt in
                try self.bind(stmt, 1, event.eventID)
                try self.bind(stmt, 2, event.topicID)
                try self.bind(stmt, 3, event.segmentID)
                try self.bind(stmt, 4, event.eventKey)
                try self.bind(stmt, 5, event.kind)
                try self.bind(stmt, 6, event.payloadObjectID)
                try self.bind(stmt, 7, event.recordedAt)
            }
            return event
        }
    }

    @discardableResult
    public func returnToTopic(
        topicID: String,
        openingEventKey: String,
        recordedAt: Date = Date()
    ) throws -> TopicSegmentRecord {
        let topicID = try topicRequired(topicID, "topic_id")
        let openingEventKey = try topicRequired(openingEventKey, "opening_event_key")
        let recordedAt = Self.stamp(recordedAt)
        return try transactionResult {
            let existing = try prepare("""
            SELECT segment_id, topic_id, parent_segment_id, segment_ordinal,
                   opening_event_key, opened_at
              FROM topic_segments WHERE topic_id=? AND opening_event_key=?;
            """)
            defer { sqlite3_finalize(existing) }
            try self.bind(existing, 1, topicID)
            try self.bind(existing, 2, openingEventKey)
            if try self.stepRowOrDone(existing) {
                return self.topicSegment(existing)
            }
            guard try self.topicOpenSegment(topicID: topicID) == nil else {
                throw DatabaseError.sql("topic \(topicID) already has an open segment")
            }
            let tail = try prepare("""
            SELECT segment_id, segment_ordinal FROM topic_segments
             WHERE topic_id=? ORDER BY segment_ordinal DESC LIMIT 1;
            """)
            defer { sqlite3_finalize(tail) }
            try self.bind(tail, 1, topicID)
            guard try self.stepRowOrDone(tail) else {
                throw DatabaseError.sql("unknown topic \(topicID)")
            }
            let parentID = sqlite3_column_text(tail, 0).map { String(cString: $0) } ?? ""
            let ordinal = Int(sqlite3_column_int64(tail, 1)) + 1
            let segment = TopicSegmentRecord(
                segmentID: UUID().uuidString.lowercased(), topicID: topicID,
                parentSegmentID: parentID, segmentOrdinal: ordinal,
                openingEventKey: openingEventKey, openedAt: recordedAt)
            try execBinding("""
            INSERT INTO topic_segments(
                segment_id, topic_id, parent_segment_id, segment_ordinal,
                opening_event_key, opened_at)
            VALUES(?,?,?,?,?,?);
            """) { stmt in
                try self.bind(stmt, 1, segment.segmentID)
                try self.bind(stmt, 2, segment.topicID)
                try self.bind(stmt, 3, segment.parentSegmentID)
                try self.bind(stmt, 4, Int64(segment.segmentOrdinal))
                try self.bind(stmt, 5, segment.openingEventKey)
                try self.bind(stmt, 6, segment.openedAt)
            }
            try execBinding("""
            INSERT INTO topic_events(
                event_id, topic_id, segment_id, event_key, kind,
                payload_object_id, recorded_at)
            VALUES(?,?,?,?,?,NULL,?);
            """) { stmt in
                try self.bind(stmt, 1, UUID().uuidString.lowercased())
                try self.bind(stmt, 2, topicID)
                try self.bind(stmt, 3, segment.segmentID)
                try self.bind(stmt, 4, openingEventKey)
                try self.bind(stmt, 5, "segment_opened")
                try self.bind(stmt, 6, recordedAt)
            }
            return segment
        }
    }

    @discardableResult
    public func appendTopicDelta(
        topicID: String,
        segmentID: String,
        deltaKey: String,
        kind: String = "progress",
        payload: [String: String],
        sourceReferences: [TopicSourceReference] = [],
        approximateSemantics: String? = nil,
        recordedAt: Date = Date()
    ) throws -> TopicDeltaRecord {
        let topicID = try topicRequired(topicID, "topic_id")
        let segmentID = try topicRequired(segmentID, "segment_id")
        let deltaKey = try topicRequired(deltaKey, "delta_key")
        let kind = try topicRequired(kind, "kind")
        let recordedAt = Self.stamp(recordedAt)
        return try transactionResult {
            let payloadObjectID = try ensureObject(try self.topicEncode(payload))
            let sourceRefsObjectID = sourceReferences.isEmpty
                ? nil : try ensureObject(try self.topicEncode(sourceReferences))
            let semanticsObjectID = try approximateSemantics.map {
                try ensureObject(Data($0.utf8))
            }
            let existing = try prepare("""
            SELECT delta_id, topic_id, segment_id, delta_key, sequence, kind,
                   payload_object_id, source_refs_object_id, semantics_object_id, recorded_at
              FROM topic_deltas WHERE topic_id=? AND delta_key=?;
            """)
            defer { sqlite3_finalize(existing) }
            try self.bind(existing, 1, topicID)
            try self.bind(existing, 2, deltaKey)
            if try self.stepRowOrDone(existing) {
                func text(_ index: Int32) -> String {
                    sqlite3_column_text(existing, index).map { String(cString: $0) } ?? ""
                }
                func optionalText(_ index: Int32) -> String? {
                    sqlite3_column_type(existing, index) == SQLITE_NULL ? nil : text(index)
                }
                guard text(2) == segmentID, text(5) == kind,
                      text(6) == payloadObjectID,
                      optionalText(7) == sourceRefsObjectID,
                      optionalText(8) == semanticsObjectID else {
                    throw DatabaseError.sql("topic delta key conflicts with existing delta")
                }
                return TopicDeltaRecord(
                    deltaID: text(0), topicID: topicID, segmentID: segmentID,
                    deltaKey: deltaKey, sequence: Int(sqlite3_column_int64(existing, 4)),
                    kind: kind, payload: payload, sourceReferences: sourceReferences,
                    approximateSemantics: approximateSemantics, recordedAt: text(9))
            }
            let segment = try prepare("""
            SELECT segment_id FROM topic_segments
             WHERE topic_id=? AND segment_id=?
               AND NOT EXISTS (
                   SELECT 1 FROM topic_events e
                    WHERE e.segment_id=topic_segments.segment_id AND e.kind='fork_point');
            """)
            defer { sqlite3_finalize(segment) }
            try self.bind(segment, 1, topicID)
            try self.bind(segment, 2, segmentID)
            guard try self.stepRowOrDone(segment) else {
                throw DatabaseError.sql("topic segment \(segmentID) is not open for \(topicID)")
            }
            let sequenceStmt = try prepare("""
            SELECT COALESCE(MAX(sequence),0)+1 FROM topic_deltas WHERE topic_id=?;
            """)
            defer { sqlite3_finalize(sequenceStmt) }
            try self.bind(sequenceStmt, 1, topicID)
            guard try self.stepRowOrDone(sequenceStmt) else {
                throw DatabaseError.sql("could not allocate topic delta sequence")
            }
            let sequence = Int(sqlite3_column_int64(sequenceStmt, 0))
            let deltaID = UUID().uuidString.lowercased()
            try execBinding("""
            INSERT INTO topic_deltas(
                delta_id, topic_id, segment_id, delta_key, sequence, kind,
                payload_object_id, source_refs_object_id, semantics_object_id, recorded_at)
            VALUES(?,?,?,?,?,?,?,?,?,?);
            """) { stmt in
                try self.bind(stmt, 1, deltaID)
                try self.bind(stmt, 2, topicID)
                try self.bind(stmt, 3, segmentID)
                try self.bind(stmt, 4, deltaKey)
                try self.bind(stmt, 5, Int64(sequence))
                try self.bind(stmt, 6, kind)
                try self.bind(stmt, 7, payloadObjectID)
                try self.bind(stmt, 8, sourceRefsObjectID)
                try self.bind(stmt, 9, semanticsObjectID)
                try self.bind(stmt, 10, recordedAt)
            }
            return TopicDeltaRecord(
                deltaID: deltaID, topicID: topicID, segmentID: segmentID,
                deltaKey: deltaKey, sequence: sequence, kind: kind, payload: payload,
                sourceReferences: sourceReferences,
                approximateSemantics: approximateSemantics, recordedAt: recordedAt)
        }
    }

    @discardableResult
    public func assignTurnToTopic(
        topicID: String? = nil,
        segmentID: String? = nil,
        scope: String = ESISDatabase.ownerNamespace,
        clientIdentityID: String,
        assignmentKey: String,
        sessionID: String,
        requestID: String? = nil,
        stateID: String? = nil,
        settlementID: String? = nil,
        windowID: String? = nil,
        approximateSemantics: String,
        assignment: TopicAssignmentKind,
        method: String,
        sourceReferences: [TopicSourceReference] = [],
        recordedAt: Date = Date()
    ) throws -> TopicAssignmentRecord {
        let scope = try topicRequired(scope, "scope")
        let clientIdentityID = try topicRequired(clientIdentityID, "client_identity_id")
        let assignmentKey = try topicRequired(assignmentKey, "assignment_key")
        let sessionID = try topicRequired(sessionID, "session_id")
        let approximateSemantics = try topicRequired(approximateSemantics, "approximate_semantics")
        let method = try topicRequired(method, "method")
        let recordedAt = Self.stamp(recordedAt)
        if topicID != nil || segmentID != nil {
            guard let topicID, !topicID.isEmpty else {
                throw DatabaseError.sql("topic assignment requires topic_id with segment_id")
            }
            guard let segmentID, !segmentID.isEmpty else {
                throw DatabaseError.sql("topic assignment requires segment_id with topic_id")
            }
        }
        if assignment == .assigned {
            guard topicID != nil else {
                throw DatabaseError.sql("assigned topic assignment requires topic_id")
            }
            guard segmentID != nil else {
                throw DatabaseError.sql("assigned topic assignment requires segment_id")
            }
        }
        return try transactionResult {
            let semanticsObjectID = try ensureObject(Data(approximateSemantics.utf8))
            let sourceRefsObjectID = sourceReferences.isEmpty
                ? nil : try ensureObject(try self.topicEncode(sourceReferences))
            let existing = try prepare("""
            SELECT assignment_id, topic_id, segment_id, scope, client_identity_id,
                   assignment_key, session_id, request_id, state_id, settlement_id,
                   window_id, semantics_object_id, assignment, method,
                   source_refs_object_id, recorded_at
              FROM topic_assignments
             WHERE scope=? AND client_identity_id=? AND assignment_key=?;
            """)
            defer { sqlite3_finalize(existing) }
            try self.bind(existing, 1, scope)
            try self.bind(existing, 2, clientIdentityID)
            try self.bind(existing, 3, assignmentKey)
            if try self.stepRowOrDone(existing) {
                func text(_ index: Int32) -> String {
                    sqlite3_column_text(existing, index).map { String(cString: $0) } ?? ""
                }
                func optionalText(_ index: Int32) -> String? {
                    sqlite3_column_type(existing, index) == SQLITE_NULL ? nil : text(index)
                }
                guard optionalText(1) == topicID, optionalText(2) == segmentID,
                      text(6) == sessionID, optionalText(7) == requestID,
                      optionalText(8) == stateID, optionalText(9) == settlementID,
                      optionalText(10) == windowID, text(11) == semanticsObjectID,
                      text(12) == assignment.rawValue, text(13) == method,
                      optionalText(14) == sourceRefsObjectID else {
                    throw DatabaseError.sql("topic assignment key conflicts with existing assignment")
                }
                return TopicAssignmentRecord(
                    assignmentID: text(0), topicID: optionalText(1), segmentID: optionalText(2),
                    scope: scope, clientIdentityID: clientIdentityID,
                    assignmentKey: assignmentKey, sessionID: sessionID,
                    requestID: optionalText(7), stateID: optionalText(8),
                    settlementID: optionalText(9), windowID: optionalText(10),
                    approximateSemantics: approximateSemantics, assignment: assignment,
                    method: method, sourceReferences: sourceReferences, recordedAt: text(15))
            }
            if let topicID, let segmentID {
                let segment = try prepare("""
                SELECT segment_id FROM topic_segments
                 WHERE topic_id=? AND segment_id=?
                   AND NOT EXISTS (
                       SELECT 1 FROM topic_events e
                        WHERE e.segment_id=topic_segments.segment_id AND e.kind='fork_point');
                """)
                defer { sqlite3_finalize(segment) }
                try self.bind(segment, 1, topicID)
                try self.bind(segment, 2, segmentID)
                guard try self.stepRowOrDone(segment) else {
                    throw DatabaseError.sql("topic segment \(segmentID) is not open for \(topicID)")
                }
            } else if assignment == .assigned {
                throw DatabaseError.sql("assigned topic assignment requires topic and segment")
            }
            let assignmentID = UUID().uuidString.lowercased()
            try execBinding("""
            INSERT INTO topic_assignments(
                assignment_id, topic_id, segment_id, scope, client_identity_id,
                assignment_key, session_id, request_id, state_id, settlement_id,
                window_id, semantics_object_id, assignment, method,
                source_refs_object_id, recorded_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """) { stmt in
                try self.bind(stmt, 1, assignmentID)
                try self.bind(stmt, 2, topicID)
                try self.bind(stmt, 3, segmentID)
                try self.bind(stmt, 4, scope)
                try self.bind(stmt, 5, clientIdentityID)
                try self.bind(stmt, 6, assignmentKey)
                try self.bind(stmt, 7, sessionID)
                try self.bind(stmt, 8, requestID)
                try self.bind(stmt, 9, stateID)
                try self.bind(stmt, 10, settlementID)
                try self.bind(stmt, 11, windowID)
                try self.bind(stmt, 12, semanticsObjectID)
                try self.bind(stmt, 13, assignment.rawValue)
                try self.bind(stmt, 14, method)
                try self.bind(stmt, 15, sourceRefsObjectID)
                try self.bind(stmt, 16, recordedAt)
            }
            return TopicAssignmentRecord(
                assignmentID: assignmentID, topicID: topicID, segmentID: segmentID,
                scope: scope, clientIdentityID: clientIdentityID,
                assignmentKey: assignmentKey, sessionID: sessionID, requestID: requestID,
                stateID: stateID, settlementID: settlementID, windowID: windowID,
                approximateSemantics: approximateSemantics, assignment: assignment,
                method: method, sourceReferences: sourceReferences, recordedAt: recordedAt)
        }
    }

    public func topicSnapshot(topicID: String) throws -> TopicChainSnapshot? {
        let genesisStmt = try prepare("""
        SELECT topic_id, scope, client_identity_id, genesis_key, title,
               defining_paragraph_object_id, initial_question, reconstructed, created_at
          FROM topic_chains WHERE topic_id=?;
        """)
        defer { sqlite3_finalize(genesisStmt) }
        try bind(genesisStmt, 1, topicID)
        guard try stepRowOrDone(genesisStmt) else { return nil }
        func genesisText(_ index: Int32) -> String {
            sqlite3_column_text(genesisStmt, index).map { String(cString: $0) } ?? ""
        }
        let genesisObjectID = genesisText(5)
        let genesis = TopicGenesis(
            topicID: genesisText(0), scope: genesisText(1),
            clientIdentityID: genesisText(2), genesisKey: genesisText(3),
            title: genesisText(4), definingParagraph: try topicText(genesisObjectID),
            initialQuestion: sqlite3_column_type(genesisStmt, 6) == SQLITE_NULL ? nil : genesisText(6),
            reconstructed: genesisText(7) == "1", createdAt: genesisText(8),
            definingParagraphObjectID: genesisObjectID)

        let aliasStmt = try prepare("""
        SELECT alias_id, topic_id, alias_key, alias, recorded_at
          FROM topic_aliases WHERE topic_id=? ORDER BY rowid;
        """)
        defer { sqlite3_finalize(aliasStmt) }
        try bind(aliasStmt, 1, topicID)
        var aliases: [TopicAliasRecord] = []
        while try stepRowOrDone(aliasStmt) {
            func text(_ index: Int32) -> String {
                sqlite3_column_text(aliasStmt, index).map { String(cString: $0) } ?? ""
            }
            aliases.append(TopicAliasRecord(
                aliasID: text(0), topicID: text(1), aliasKey: text(2),
                alias: text(3), recordedAt: text(4)))
        }

        let segmentStmt = try prepare("""
        SELECT segment_id, topic_id, parent_segment_id, segment_ordinal,
               opening_event_key, opened_at
          FROM topic_segments WHERE topic_id=? ORDER BY segment_ordinal;
        """)
        defer { sqlite3_finalize(segmentStmt) }
        try bind(segmentStmt, 1, topicID)
        var segments: [TopicSegmentRecord] = []
        while try stepRowOrDone(segmentStmt) {
            segments.append(topicSegment(segmentStmt))
        }

        let eventStmt = try prepare("""
        SELECT event_id, topic_id, segment_id, event_key, kind,
               payload_object_id, recorded_at
          FROM topic_events WHERE topic_id=? ORDER BY rowid;
        """)
        defer { sqlite3_finalize(eventStmt) }
        try bind(eventStmt, 1, topicID)
        var events: [TopicEventRecord] = []
        while try stepRowOrDone(eventStmt) {
            events.append(topicEvent(eventStmt))
        }

        let deltaStmt = try prepare("""
        SELECT delta_id, topic_id, segment_id, delta_key, sequence, kind,
               payload_object_id, source_refs_object_id, semantics_object_id, recorded_at
          FROM topic_deltas WHERE topic_id=? ORDER BY sequence;
        """)
        defer { sqlite3_finalize(deltaStmt) }
        try bind(deltaStmt, 1, topicID)
        var deltas: [TopicDeltaRecord] = []
        while try stepRowOrDone(deltaStmt) {
            func text(_ index: Int32) -> String {
                sqlite3_column_text(deltaStmt, index).map { String(cString: $0) } ?? ""
            }
            func optionalText(_ index: Int32) -> String? {
                sqlite3_column_type(deltaStmt, index) == SQLITE_NULL ? nil : text(index)
            }
            let payloadObjectID = text(6)
            let payloadData = try readObject(payloadObjectID)
            let payload = try JSONDecoder().decode([String: String].self, from: payloadData)
            let sourceRefsObjectID = optionalText(7)
            let sourceRefsData = try sourceRefsObjectID.map(readObject)
            let sourceRefs = try sourceRefsData.map {
                try JSONDecoder().decode([TopicSourceReference].self, from: $0)
            } ?? []
            let semantics = try optionalText(8).map(topicText)
            deltas.append(TopicDeltaRecord(
                deltaID: text(0), topicID: text(1), segmentID: text(2),
                deltaKey: text(3), sequence: Int(sqlite3_column_int64(deltaStmt, 4)),
                kind: text(5), payload: payload, sourceReferences: sourceRefs,
                approximateSemantics: semantics, recordedAt: text(9)))
        }

        let assignmentStmt = try prepare("""
        SELECT assignment_id, topic_id, segment_id, scope, client_identity_id,
               assignment_key, session_id, request_id, state_id, settlement_id,
               window_id, semantics_object_id, assignment, method,
               source_refs_object_id, recorded_at
          FROM topic_assignments WHERE topic_id=? ORDER BY rowid;
        """)
        defer { sqlite3_finalize(assignmentStmt) }
        try bind(assignmentStmt, 1, topicID)
        var assignments: [TopicAssignmentRecord] = []
        while try stepRowOrDone(assignmentStmt) {
            func text(_ index: Int32) -> String {
                sqlite3_column_text(assignmentStmt, index).map { String(cString: $0) } ?? ""
            }
            func optionalText(_ index: Int32) -> String? {
                sqlite3_column_type(assignmentStmt, index) == SQLITE_NULL ? nil : text(index)
            }
            guard let assignment = TopicAssignmentKind(rawValue: text(12)) else {
                throw DatabaseError.sql("unknown topic assignment kind \(text(12))")
            }
            let sourceRefsObjectID = optionalText(14)
            let sourceRefsData = try sourceRefsObjectID.map(readObject)
            let sourceRefs = try sourceRefsData.map {
                try JSONDecoder().decode([TopicSourceReference].self, from: $0)
            } ?? []
            assignments.append(TopicAssignmentRecord(
                assignmentID: text(0), topicID: optionalText(1), segmentID: optionalText(2),
                scope: text(3), clientIdentityID: text(4), assignmentKey: text(5),
                sessionID: text(6), requestID: optionalText(7), stateID: optionalText(8),
                settlementID: optionalText(9), windowID: optionalText(10),
                approximateSemantics: try topicText(text(11)), assignment: assignment,
                method: text(13), sourceReferences: sourceRefs, recordedAt: text(15)))
        }
        return TopicChainSnapshot(
            genesis: genesis, aliases: aliases, segments: segments,
            events: events, deltas: deltas, assignments: assignments)
    }

    public func renderTopicBrief(topicID: String) throws -> String? {
        guard let snapshot = try topicSnapshot(topicID: topicID) else { return nil }
        var current = [
            "completed": "", "achievements": "", "problems": "", "plan": "",
        ]
        var scopeClarifications: [String] = []
        var notes: [String] = []
        for delta in snapshot.deltas {
            for key in current.keys.sorted() {
                if let value = delta.payload[key] { current[key] = value }
            }
            if let clarification = delta.payload["scope_clarification"] {
                scopeClarifications.append(clarification)
            }
            for key in delta.payload.keys.sorted() where !current.keys.contains(key) && key != "scope_clarification" {
                notes.append("\(key): \(delta.payload[key] ?? "")")
            }
        }
        var sections = [
            "①项目简介\n\(snapshot.genesis.definingParagraph)",
            "②已完成什么\n\(current["completed"] ?? "")",
            "③取得的成绩\n\(current["achievements"] ?? "")",
            "④存在的问题\n\(current["problems"] ?? "")",
            "⑤后期的计划\n\(current["plan"] ?? "")",
        ]
        if !scopeClarifications.isEmpty {
            sections.append("范围澄清\n" + scopeClarifications.joined(separator: "\n"))
        }
        if !notes.isEmpty {
            sections.append("补充记录\n" + notes.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }
}
