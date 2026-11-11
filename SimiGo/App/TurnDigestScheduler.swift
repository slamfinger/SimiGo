import Foundation
import SimiGoRuntimeContract

/// 一轮写进空间之后，顺手把它的摘要补上。
///
/// 为什么走回环 HTTP：本地模型已经在 `127.0.0.1:8000` 上按 OpenAI 兼容接口
/// 提供服务，admission、常驻缓存、日志都在那条路上。再在 App 里接一层模型
/// 客户端，等于把同一件事做两遍，还会绕过那些门槛。
///
/// 三件不做的事：不阻塞回复（调用方 fire-and-forget）；失败不写行（缺口留在
/// 「缺摘要」的账上，不假装有摘要）；不重试到成功（一轮失败就是一轮失败）。
enum TurnDigestScheduler {
    private static let queue = DispatchQueue(label: "simigo.turn-digest")
    private static var inFlight = Set<String>()
    private static let endpoint = URL(string: "http://127.0.0.1:8000/v1/chat/completions")!
    static var model = "local"

    static func schedule(
        sessionID: String, turnIndex: Int, question: String, answer: String
    ) {
        let key = "\(sessionID)#\(turnIndex)"
        queue.sync {
            guard inFlight.insert(key).inserted else { return }
        }
        Task.detached(priority: .utility) {
            defer { queue.sync { _ = inFlight.remove(key) } }
            do {
                let raw = try await complete(
                    TurnDigestText.prompt(question: question, answer: answer))
                guard let parsed = TurnDigestText.parse(raw) else {
                    NSLog("[digest] \(key) 输出不合格式，留缺口")
                    return
                }
                let db = try ESISDatabase(url: ManagedPaths.databaseURL,
                                          createIfNeeded: true)
                defer { db.close() }
                try db.recordTurnDigest(
                    sessionID: sessionID, turnIndex: turnIndex,
                    digest: parsed.digest,
                    keywords: parsed.keywords.joined(separator: " "),
                    model: "local:\(model)")
            } catch {
                NSLog("[digest] \(key) 失败：\(error)")
            }
        }
    }

    private static func complete(_ prompt: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 600,
            "temperature": 0.2,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "TurnDigest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "模型返回非 200",
            ])
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw NSError(domain: "TurnDigest", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "模型返回里没有 content",
            ])
        }
        return content
    }
}
