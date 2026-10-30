import Foundation
import SimiGoRuntimeContract

/// External-provider turns inside the Information Space.
///
/// Forwarding to an upstream API used to be a hole: the request and its answer
/// left no trace in the IS, so information produced through the external API
/// could never be recalled. The same three questions the local path answers are
/// now answered here: the turn is *recorded* with its provenance when the
/// request arrives, *verified* only when this very request produced a complete
/// answer, and only then *retrievable* by later eligible requests.
extension HTTPServer {

    enum ExternalWire: String {
        case chat
        case completions
        case responses
    }

    struct ExternalTurnCapture {
        let sessionID: String
        let provider: String
        let requestID: String
        let model: String?
        let eligibility: SimiGoESISDatabase.ChatTurnEligibility
        let userMessageID: Int64
    }

    static func externalWire(forPath path: String) -> ExternalWire? {
        switch path {
        case "/v1/chat/completions", "/chat/completions": return .chat
        case "/v1/completions", "/completions": return .completions
        case "/v1/responses": return .responses
        default: return nil
        }
    }

    /// The question a forwarded request carries. Chat bodies resend the whole
    /// conversation, so this is the last user turn.
    static func externalRequestUserText(
        wire: ExternalWire, json: [String: Any]
    ) -> String? {
        switch wire {
        case .chat:
            for message in JSONValue.any(json["messages"]).reversedArray {
                guard let object = message.object,
                    object["role"]?.string == "user"
                else { continue }
                let text = object["content"]?.messageText ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
            return nil
        case .completions:
            switch json["prompt"] {
            case let value as String: return value
            case let values as [String]: return values.joined()
            default: return nil
            }
        case .responses:
            if let text = json["input"] as? String { return text }
            for item in JSONValue.any(json["input"]).reversedArray {
                guard let object = item.object else { continue }
                if let role = object["role"]?.string, role != "user" { continue }
                let text = object["content"]?.messageText ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
            return nil
        }
    }

    /// Text and termination a non-streaming upstream body carries.
    static func externalResponseExtract(
        wire: ExternalWire, json: [String: Any]
    ) -> (text: String, complete: Bool) {
        switch wire {
        case .chat, .completions:
            guard let choice = JSONValue.any(json["choices"]).firstObject?.object
            else { return ("", false) }
            let text = wire == .chat
                ? (choice["message"]?.object?["content"]?.messageText ?? "")
                : (choice["text"]?.messageText ?? "")
            let finish = choice["finish_reason"]?.string
            // `length` is a truncated answer: it exists, but it is not a
            // verified result another request may build on.
            return (text, finish != "length")
        case .responses:
            var text = ""
            for item in JSONValue.any(json["output"]).arrayValues {
                for part in item.object?["content"]?.arrayValues ?? [] {
                    guard let part = part.object else { continue }
                    if let type = part["type"]?.string, type != "output_text" { continue }
                    text += part["text"]?.string ?? ""
                }
            }
            let status = json["status"] as? String
            return (text, status == nil || status == "completed")
        }
    }

    /// Text and termination accumulated from an SSE byte stream.
    static func externalStreamExtract(
        wire: ExternalWire, raw: Data
    ) -> (text: String, complete: Bool) {
        var text = ""
        var complete = false
        for line in raw.split(separator: UInt8(ascii: "\n")) {
            guard line.starts(with: Data("data:".utf8)) else { continue }
            let payload = String(
                decoding: line.dropFirst(5), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                complete = true
                continue
            }
            guard let data = payload.data(using: .utf8),
                let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            switch wire {
            case .chat:
                guard let choice = JSONValue.any(event["choices"]).firstObject?.object
                else { continue }
                text += choice["delta"]?.object?["content"]?.messageText ?? ""
                if let finish = choice["finish_reason"]?.string {
                    complete = finish != "length"
                }
            case .completions:
                guard let choice = JSONValue.any(event["choices"]).firstObject?.object
                else { continue }
                text += choice["text"]?.messageText ?? ""
                if let finish = choice["finish_reason"]?.string {
                    complete = finish != "length"
                }
            case .responses:
                switch event["type"] as? String {
                case "response.output_text.delta":
                    text += event["delta"] as? String ?? ""
                case "response.completed":
                    complete = true
                case "response.incomplete", "response.failed", "error":
                    complete = false
                default:
                    break
                }
            }
        }
        return (text, complete)
    }

    /// Record the forwarded turn before it leaves for the upstream. Failure to
    /// record never blocks the client's request — it only costs recall, and the
    /// trace says so.
    func beginExternalTurn(
        request: HTTPRequest,
        context: ConnectionContext
    ) -> ExternalTurnCapture? {
        guard request.method == "POST",
            let wire = Self.externalWire(forPath: request.path),
            let backend = remoteBackend,
            let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        else { return nil }
        guard let userText = Self.externalRequestUserText(wire: wire, json: json),
            !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let agent = request.headers["x-agent-id"]
            ?? request.headers["x-simigo-agent"]
        let sessionID = resolveExplicitSession(from: json, headers: request.headers)
            ?? Self.informationScope(
                agentId: agent,
                messages: wire == .chat
                    ? JSONValue.any(json["messages"]).arrayValues : [])
        let eligibility = Self.turnEligibility(from: json, headers: request.headers)
        let provider = backend.configuration.provider.rawValue
        let model = backend.configuration.model
        let requestID = context.requestId

        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: true)
        else {
            RuntimeTraceLogger.shared.trace(
                "[REMOTE_IS] record_failed=open_db request=\(requestID)")
            return nil
        }
        try? db.runMigrations()
        do {
            let userMessageID = try db.recordExternalTurn(
                sessionID: sessionID, provider: provider, requestID: requestID,
                userText: userText, model: model, createdAt: Date(),
                eligibility: eligibility)
            RuntimeTraceLogger.shared.trace(
                "[REMOTE_IS] recorded=user request=\(requestID) " +
                "session=\(sessionID) provider=\(provider) " +
                "role=\(eligibility.rawValue) row=\(userMessageID) " +
                "path=\(request.path)")
            return ExternalTurnCapture(
                sessionID: sessionID, provider: provider, requestID: requestID,
                model: model, eligibility: eligibility, userMessageID: userMessageID)
        } catch {
            RuntimeTraceLogger.shared.trace(
                "[REMOTE_IS] record_failed=user request=\(requestID) " +
                "error=\(error)")
            return nil
        }
    }

    /// Store the answer under the same request and promote the pair only when
    /// the upstream reported a complete answer. A partial or failed turn stays
    /// recorded and unretrievable.
    func finishExternalTurn(
        _ capture: ExternalTurnCapture?,
        text: String,
        completed: Bool
    ) {
        guard let capture else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            RuntimeTraceLogger.shared.trace(
                "[REMOTE_IS] recorded=answer_absent request=\(capture.requestID) " +
                "session=\(capture.sessionID)")
            return
        }
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: true)
        else {
            RuntimeTraceLogger.shared.trace(
                "[REMOTE_IS] record_failed=open_db request=\(capture.requestID)")
            return
        }
        try? db.runMigrations()
        do {
            let assistantID = try db.recordExternalResponse(
                sessionID: capture.sessionID, provider: capture.provider,
                requestID: capture.requestID, assistantText: body,
                model: capture.model, createdAt: Date(),
                eligibility: capture.eligibility)
            guard completed else {
                RuntimeTraceLogger.shared.trace(
                    "[REMOTE_IS] recorded=answer_unverified request=\(capture.requestID) " +
                    "session=\(capture.sessionID) row=\(assistantID)")
                return
            }
            let promoted = try db.verifyExternalTurn(
                sessionID: capture.sessionID, requestID: capture.requestID,
                verifiedAt: Date())
            RuntimeTraceLogger.shared.trace(
                "[REMOTE_IS] verified=\(promoted > 0 ? 1 : 0) " +
                "request=\(capture.requestID) session=\(capture.sessionID) " +
                "rows=\(promoted) row=\(assistantID)")
        } catch {
            RuntimeTraceLogger.shared.trace(
                "[REMOTE_IS] record_failed=answer request=\(capture.requestID) " +
                "error=\(error)")
        }
    }
}

private extension JSONValue {
    var arrayValues: [JSONValue] {
        guard case .array(let values) = self else { return [] }
        return values
    }

    var reversedArray: ReversedCollection<[JSONValue]> {
        arrayValues.reversed()
    }

    var firstObject: JSONValue? {
        arrayValues.first
    }
}
