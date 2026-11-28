import Foundation

public struct TopicSemanticRequest: Sendable, Equatable {
    public let turnRef: String
    public let currentText: String
    public let responseText: String?
    public let context: [TopicSemanticContext]
    public let topics: [EffectiveTopicDefinition]

    public init(
        turnRef: String,
        currentText: String,
        context: [TopicSemanticContext],
        topics: [EffectiveTopicDefinition],
        responseText: String? = nil
    ) throws {
        let turnRef = turnRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !turnRef.isEmpty, !currentText.isEmpty else {
            throw TopicSemanticError.invalidSource
        }
        self.turnRef = turnRef
        self.currentText = currentText
        self.responseText = responseText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.context = context
        self.topics = topics
    }
}

public struct TopicSemanticContext: Sendable, Equatable {
    public let turnRef: String
    public let text: String

    public init(turnRef: String, text: String) throws {
        let turnRef = turnRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !turnRef.isEmpty, !text.isEmpty else {
            throw TopicSemanticError.invalidSource
        }
        self.turnRef = turnRef
        self.text = text
    }
}

public struct TopicSemanticRoute: Sendable, Equatable {
    public let status: TopicAssignmentStatus
    public let topicID: String?
    public let candidateTopicIDs: [String]

    public init(
        status: TopicAssignmentStatus,
        topicID: String?,
        candidateTopicIDs: [String] = []
    ) throws {
        switch status {
        case .assigned, .newTopic:
            guard let topicID, !topicID.isEmpty else {
                throw TopicSemanticError.missingAssignedTopicID
            }
            self.topicID = topicID
        case .nonTopic, .ambiguous:
            self.topicID = nil
        }
        self.status = status
        self.candidateTopicIDs = Array(Set(candidateTopicIDs)).sorted()
    }
}

public struct TopicSemanticNewTopic: Sendable, Equatable {
    public let definingParagraph: String
    public let title: String

    public init(definingParagraph: String, title: String) throws {
        let definingParagraph = definingParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !definingParagraph.isEmpty, !title.isEmpty else {
            throw TopicSemanticError.invalidSource
        }
        self.definingParagraph = definingParagraph
        self.title = title
    }
}

public struct TopicSemanticInterpretation: Sendable, Equatable {
    public let approximateSemantics: String
    public let route: TopicSemanticRoute
    public let clarification: String?
    public let newTopic: TopicSemanticNewTopic?

    public init(
        approximateSemantics: String,
        route: TopicSemanticRoute,
        clarification: String? = nil,
        newTopic: TopicSemanticNewTopic? = nil
    ) throws {
        let approximateSemantics = approximateSemantics.trimmingCharacters(in: .whitespacesAndNewlines)
        let clarification = clarification?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !approximateSemantics.isEmpty else {
            throw TopicSemanticError.emptyApproximateSemantics
        }
        guard route.status != .newTopic || newTopic != nil else {
            throw TopicSemanticError.invalidSource
        }
        self.approximateSemantics = approximateSemantics
        self.route = route
        self.clarification = clarification
        self.newTopic = newTopic
    }
}

public protocol TopicSemanticInterpreter: Sendable {
    func interpret(_ request: TopicSemanticRequest) async throws -> TopicSemanticInterpretation
}

/// Resolves explicit topic references without inventing semantic similarity.
/// Unmatched and multi-match inputs stay ambiguous; a real interpreter supplies
/// open-ended semantic judgments.
public struct ExplicitTopicReferenceRouter: TopicSemanticInterpreter, Sendable {
    private let greetings: Set<String>
    private let normalizedGreetings: Set<String>

    public init(greetings: Set<String> = ["你好", "您好", "嗨", "hello", "hi", "早上好", "下午好", "晚上好"]) {
        self.greetings = greetings
        self.normalizedGreetings = Set(greetings.map(Self.normalized))
    }

    public func interpret(_ request: TopicSemanticRequest) async throws -> TopicSemanticInterpretation {
        let text = normalized(request.currentText)
        if normalizedGreetings.contains(text) {
            return try TopicSemanticInterpretation(
                approximateSemantics: "简单问候或寒暄，没有具体工作话题",
                route: TopicSemanticRoute(status: .nonTopic, topicID: nil))
        }
        let semanticText = normalized(
            [request.currentText, request.context.map(\.text).joined(separator: " ")].joined(separator: " "))
        let matches = request.topics.filter { topic in
            referenceTerms(topic.renderedParagraph).contains { semanticText.contains($0) }
        }.map(\.topicID).sorted()
        let semantics = "围绕“\(request.currentText)”的请求"
        if matches.count == 1 {
            return try TopicSemanticInterpretation(
                approximateSemantics: semantics,
                route: TopicSemanticRoute(
                    status: .assigned, topicID: matches[0], candidateTopicIDs: matches))
        }
        return try TopicSemanticInterpretation(
            approximateSemantics: semantics,
            route: TopicSemanticRoute(
                status: .ambiguous, topicID: nil, candidateTopicIDs: matches))
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func normalized(_ text: String) -> String { Self.normalized(text) }

    private func referenceTerms(_ text: String) -> [String] {
        let latin = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        return Array(Set(latin.map(Self.normalized))).sorted()
    }
}
