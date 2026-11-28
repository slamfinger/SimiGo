import Foundation

public struct TopicGenesisRecord: Codable, Sendable, Equatable {
    public let topicID: String
    public let definingParagraph: String
    public let title: String
    public let seedRefs: [String]
    public let reconstructed: Bool
    public let createdAt: String

    public init(
        topicID: String,
        definingParagraph: String,
        title: String,
        seedRefs: [String],
        reconstructed: Bool,
        createdAt: String
    ) throws {
        let topicID = topicID.trimmingCharacters(in: .whitespacesAndNewlines)
        let definingParagraph = definingParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let seedRefs = seedRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let createdAt = createdAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topicID.isEmpty else { throw TopicSemanticError.emptyTopicID }
        guard !definingParagraph.isEmpty else { throw TopicSemanticError.emptyDefiningParagraph }
        guard !title.isEmpty else { throw TopicSemanticError.emptyTitle }
        guard !seedRefs.isEmpty else { throw TopicSemanticError.emptySeedRefs }
        guard !createdAt.isEmpty else { throw TopicSemanticError.emptyCreatedAt }
        self.topicID = topicID
        self.definingParagraph = definingParagraph
        self.title = title
        self.seedRefs = seedRefs
        self.reconstructed = reconstructed
        self.createdAt = createdAt
    }
}

public struct TopicScopeClarificationRecord: Codable, Sendable, Equatable {
    public let clarificationID: String
    public let topicID: String
    public let clarification: String
    public let sourceRefs: [String]
    public let createdAt: String

    public init(
        clarificationID: String,
        topicID: String,
        clarification: String,
        sourceRefs: [String],
        createdAt: String
    ) throws {
        let clarificationID = clarificationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let topicID = topicID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clarification = clarification.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceRefs = sourceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let createdAt = createdAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clarificationID.isEmpty else { throw TopicSemanticError.emptyClarificationID }
        guard !topicID.isEmpty else { throw TopicSemanticError.emptyTopicID }
        guard !clarification.isEmpty else { throw TopicSemanticError.emptyClarification }
        guard !sourceRefs.isEmpty else { throw TopicSemanticError.emptySourceRefs }
        guard !createdAt.isEmpty else { throw TopicSemanticError.emptyCreatedAt }
        self.clarificationID = clarificationID
        self.topicID = topicID
        self.clarification = clarification
        self.sourceRefs = sourceRefs
        self.createdAt = createdAt
    }
}

public struct TurnSemanticObservation: Codable, Sendable, Equatable {
    public let turnRef: String
    public let approximateSemantics: String
    public let contextRefs: [String]

    public init(turnRef: String, approximateSemantics: String, contextRefs: [String]) throws {
        let turnRef = turnRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let approximateSemantics = approximateSemantics.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextRefs = contextRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !turnRef.isEmpty else { throw TopicSemanticError.emptyTurnRef }
        guard !approximateSemantics.isEmpty else { throw TopicSemanticError.emptyApproximateSemantics }
        self.turnRef = turnRef
        self.approximateSemantics = approximateSemantics
        self.contextRefs = contextRefs
    }
}

public enum TopicAssignmentStatus: String, Codable, Sendable, CaseIterable {
    case assigned
    case newTopic = "new-topic"
    case nonTopic = "non-topic"
    case ambiguous
}

public struct TopicAssignmentRecord: Codable, Sendable, Equatable {
    public let assignmentID: String
    public let turnRef: String
    public let topicID: String?
    public let status: TopicAssignmentStatus
    public let candidateTopicIDs: [String]
    public let evidenceRefs: [String]
    public let createdAt: String

    public init(
        assignmentID: String,
        turnRef: String,
        topicID: String?,
        status: TopicAssignmentStatus,
        candidateTopicIDs: [String],
        evidenceRefs: [String],
        createdAt: String
    ) throws {
        let assignmentID = assignmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let turnRef = turnRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let topicID = topicID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateTopicIDs = candidateTopicIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let evidenceRefs = evidenceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let createdAt = createdAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assignmentID.isEmpty else { throw TopicSemanticError.emptyAssignmentID }
        guard !turnRef.isEmpty else { throw TopicSemanticError.emptyTurnRef }
        guard !createdAt.isEmpty else { throw TopicSemanticError.emptyCreatedAt }
        switch status {
        case .assigned, .newTopic:
            guard let topicID, !topicID.isEmpty else { throw TopicSemanticError.missingAssignedTopicID }
            self.topicID = topicID
        case .nonTopic, .ambiguous:
            self.topicID = nil
        }
        self.assignmentID = assignmentID
        self.turnRef = turnRef
        self.status = status
        self.candidateTopicIDs = candidateTopicIDs
        self.evidenceRefs = evidenceRefs
        self.createdAt = createdAt
    }
}

public struct EffectiveTopicDefinition: Codable, Sendable, Equatable {
    public let topicID: String
    public let title: String
    public let genesisParagraph: String
    public let clarifications: [TopicScopeClarificationRecord]
    public let renderedParagraph: String

    public init(genesis: TopicGenesisRecord, clarifications: [TopicScopeClarificationRecord]) throws {
        guard clarifications.allSatisfy({ $0.topicID == genesis.topicID }) else {
            throw TopicSemanticError.crossTopicClarification
        }
        self.topicID = genesis.topicID
        self.title = genesis.title
        self.genesisParagraph = genesis.definingParagraph
        self.clarifications = clarifications
        self.renderedParagraph = ([genesis.definingParagraph] + clarifications.map(\.clarification)).joined(separator: "\n")
    }
}

public struct TopicSemanticPublication: Sendable, Equatable {
    public let genesis: TopicGenesisRecord?
    public let clarification: TopicScopeClarificationRecord?
    public let observation: TurnSemanticObservation
    public let assignment: TopicAssignmentRecord

    public init(
        genesis: TopicGenesisRecord? = nil,
        clarification: TopicScopeClarificationRecord? = nil,
        observation: TurnSemanticObservation,
        assignment: TopicAssignmentRecord
    ) throws {
        guard assignment.turnRef == observation.turnRef else {
            throw TopicSemanticError.publicationTurnMismatch
        }
        if let genesis {
            guard assignment.status == .newTopic else {
                throw TopicSemanticError.unexpectedGenesis
            }
            guard genesis.topicID == assignment.topicID else {
                throw TopicSemanticError.publicationTopicMismatch
            }
        }
        if let clarification {
            guard assignment.status == .assigned, let topicID = assignment.topicID else {
                throw TopicSemanticError.invalidClarification
            }
            guard clarification.topicID == topicID else {
                throw TopicSemanticError.publicationTopicMismatch
            }
        }
        self.genesis = genesis
        self.clarification = clarification
        self.observation = observation
        self.assignment = assignment
    }
}

public struct TopicSemanticSource: Sendable, Equatable {
    public let sessionID: String
    public let turnIndex: Int
    public let expectedQuestionSHA256: String
    public let expectedAnswerSHA256: String

    public init(
        sessionID: String,
        turnIndex: Int,
        expectedQuestionSHA256: String,
        expectedAnswerSHA256: String
    ) throws {
        let sessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedQuestionSHA256 = expectedQuestionSHA256.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedAnswerSHA256 = expectedAnswerSHA256.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty, turnIndex > 0,
              !expectedQuestionSHA256.isEmpty, !expectedAnswerSHA256.isEmpty else {
            throw TopicSemanticError.invalidSource
        }
        self.sessionID = sessionID
        self.turnIndex = turnIndex
        self.expectedQuestionSHA256 = expectedQuestionSHA256
        self.expectedAnswerSHA256 = expectedAnswerSHA256
    }

    public var turnRef: String { "\(sessionID)#\(turnIndex)" }
}

public enum TopicSemanticError: Error, Equatable {
    case emptyTopicID
    case emptyDefiningParagraph
    case emptyTitle
    case emptySeedRefs
    case emptyCreatedAt
    case emptyClarificationID
    case emptyClarification
    case emptySourceRefs
    case emptyTurnRef
    case emptyApproximateSemantics
    case emptyAssignmentID
    case missingAssignedTopicID
    case crossTopicClarification
    case publicationTurnMismatch
    case publicationTopicMismatch
    case unexpectedGenesis
    case invalidClarification
    case invalidSource
}
