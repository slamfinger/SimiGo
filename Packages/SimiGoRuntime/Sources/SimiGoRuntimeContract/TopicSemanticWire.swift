import Foundation

public enum TopicSemanticWireError: Error, Equatable {
    case malformedJSON
    case missingField(String)
    case unknownTopic(String)
    case invalidRoute
    case missingNewTopicDefinition
    case invalidClarification
}

public enum TopicSemanticWire {
    public static func prompt(_ request: TopicSemanticRequest) throws -> String {
        let payload = try JSONEncoder().encode(Payload(
            turnRef: request.turnRef,
            userText: request.currentText,
            assistantText: request.responseText,
            context: request.context.map { Context(turnRef: $0.turnRef, text: $0.text) },
            topics: request.topics.map {
                Topic(topicID: $0.topicID, title: $0.title, definition: $0.renderedParagraph)
            }))
        guard let json = String(data: payload, encoding: .utf8) else {
            throw TopicSemanticWireError.malformedJSON
        }
        return """
        你是会话话题路由器。只依据给定 JSON 中的当前轮次和不晚于它的上下文判断。
        输出必须是一个裸 JSON 对象，不要 Markdown 围栏或额外文字。字段：
        approximate_semantics: string，粗略说明本轮在做什么，不抽取精确事实；
        status: assigned|new-topic|non-topic|ambiguous；
        topic_id: string|null，assigned/new-topic 必填，其余必须 null；
        candidate_topic_ids: string[]，只能引用输入 topics 中的 topic_id；
        defining_paragraph: string|null，仅 new-topic 必填，写话题开头的自然语言定义；
        title: string|null，仅 new-topic 必填；
        clarification: string|null，只有需要追加话题边界澄清时填写，不得改写 genesis。
        “你好”等纯问候用 non-topic。无法确定归属用 ambiguous，不得强猜。
        输入数据：
        \(json)
        """
    }

    public static func parse(_ raw: String, topics: [EffectiveTopicDefinition]) throws -> TopicSemanticInterpretation {
        guard let data = raw.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            throw TopicSemanticWireError.malformedJSON
        }
        let wire: Response
        do {
            wire = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TopicSemanticWireError.malformedJSON
        }
        let known = Set(topics.map(\.topicID))
        for candidate in wire.candidateTopicIDs where !known.contains(candidate) {
            throw TopicSemanticWireError.unknownTopic(candidate)
        }
        guard let status = TopicAssignmentStatus(rawValue: wire.status) else {
            throw TopicSemanticWireError.invalidRoute
        }
        let topicID: String?
        switch status {
        case .assigned:
            guard let value = wire.topicID, known.contains(value) else {
                if let value = wire.topicID { throw TopicSemanticWireError.unknownTopic(value) }
                throw TopicSemanticWireError.invalidRoute
            }
            topicID = value
        case .newTopic:
            topicID = wire.topicID ?? "pending-new-topic"
        case .nonTopic, .ambiguous:
            guard wire.topicID == nil else { throw TopicSemanticWireError.invalidRoute }
            topicID = nil
        }
        let newTopic: TopicSemanticNewTopic?
        if status == .newTopic {
            guard let paragraph = wire.definingParagraph, let title = wire.title else {
                throw TopicSemanticWireError.missingNewTopicDefinition
            }
            newTopic = try TopicSemanticNewTopic(definingParagraph: paragraph, title: title)
        } else {
            guard wire.definingParagraph == nil, wire.title == nil else {
                throw TopicSemanticWireError.invalidRoute
            }
            newTopic = nil
        }
        if let clarification = wire.clarification, status != .assigned || topicID == nil {
            throw TopicSemanticWireError.invalidClarification
        }
        return try TopicSemanticInterpretation(
            approximateSemantics: wire.approximateSemantics,
            route: TopicSemanticRoute(
                status: status, topicID: topicID, candidateTopicIDs: wire.candidateTopicIDs),
            clarification: wire.clarification,
            newTopic: newTopic)
    }

    private struct Payload: Encodable {
        let turnRef: String
        let userText: String
        let assistantText: String?
        let context: [Context]
        let topics: [Topic]
    }

    private struct Context: Encodable {
        let turnRef: String
        let text: String
    }

    private struct Topic: Encodable {
        let topicID: String
        let title: String
        let definition: String
    }

    private struct Response: Decodable {
        let approximateSemantics: String
        let status: String
        let topicID: String?
        let candidateTopicIDs: [String]
        let definingParagraph: String?
        let title: String?
        let clarification: String?

        enum CodingKeys: String, CodingKey {
            case approximateSemantics = "approximate_semantics"
            case status
            case topicID = "topic_id"
            case candidateTopicIDs = "candidate_topic_ids"
            case definingParagraph = "defining_paragraph"
            case title
            case clarification
        }
    }
}
