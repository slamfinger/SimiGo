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

    /// 把「轮号有、摘要没有」的全部补齐。一次一轮、串行——本地模型本来
    /// 也是串行处理的，并发只会把预填挤在一起。
    ///
    /// 每补完一轮就回报一次，调用方据此更新进度；补不上的留在缺口里。
    static func fillMissing(
        limit: Int? = nil,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> (done: Int, failed: Int) {
        var pending: [ESISDatabase.UndigestedTurn]
        do {
            let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
            defer { db.close() }
            pending = try db.undigestedTurns()
        } catch {
            NSLog("[digest] 读缺口失败：\(error)")
            return (0, 0)
        }
        if let limit, limit < pending.count { pending = Array(pending.prefix(limit)) }
        var done = 0, failed = 0
        for (index, turn) in pending.enumerated() {
            do {
                let raw = try await complete(TurnDigestText.prompt(
                    question: turn.question, answer: turn.answer))
                guard let parsed = TurnDigestText.parse(raw) else {
                    failed += 1
                    progress(index + 1, pending.count)
                    continue
                }
                let db = try ESISDatabase(url: ManagedPaths.databaseURL,
                                          createIfNeeded: true)
                defer { db.close() }
                try db.recordTurnDigest(
                    sessionID: turn.sessionID, turnIndex: turn.turnIndex,
                    questionMessageID: turn.questionMessageID,
                    answerMessageID: turn.answerMessageID,
                    digest: parsed.digest,
                    keywords: parsed.keywords.joined(separator: " "),
                    model: "local:\(model)")
                done += 1
            } catch {
                failed += 1
                NSLog("[digest] \(turn.sessionID)#\(turn.turnIndex) 失败：\(error)")
            }
            progress(index + 1, pending.count)
        }
        return (done, failed)
    }

    /// 只修词，不动摘要。
    ///
    /// 已有的词留着——它们是这一轮被捞出来的入口，删掉就是把口子堵上
    /// （2026-11-12 实测：按「原文里搜不到」删词，别名查询的召回从 177/177
    /// 掉到 54/177）。只补不够的：向本地模型要词，再按原文筛一遍——
    /// 词表是检索入口，原文里没有的字面搜不到，也不该白占一格。
    static func repairKeywords(
        limit: Int? = nil,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> (done: Int, failed: Int) {
        var pending: [ESISDatabase.DigestTurnText]
        do {
            let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
            defer { db.close() }
            pending = try db.turnsWithThinKeywords(limit: limit)
        } catch {
            NSLog("[digest] 读缺词轮次失败：\(error)")
            return (0, 0)
        }
        var done = 0, failed = 0
        for (index, turn) in pending.enumerated() {
            do {
                let raw = try await complete(TurnDigestText.keywordPrompt(
                    question: turn.question, answer: turn.answer))
                guard let fresh = TurnDigestText.parseKeywords(raw) else {
                    failed += 1
                    progress(index + 1, pending.count)
                    continue
                }
                let text = turn.question + "\n" + turn.answer
                var merged = turn.keywords
                var seen = Set(merged)
                for term in fresh
                where text.contains(term) && seen.insert(term).inserted {
                    merged.append(term)
                    if merged.count == TurnDigestText.maxKeywords { break }
                }
                // 一个能落地的词都没拿到：这一轮算没修成，不写空写。
                guard merged.count > turn.keywords.count else {
                    failed += 1
                    progress(index + 1, pending.count)
                    continue
                }
                let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                try db.replaceTurnKeywords(
                    sessionID: turn.sessionID, turnIndex: turn.turnIndex,
                    keywords: merged)
                done += 1
            } catch {
                failed += 1
                NSLog("[digest] 修词 \(turn.sessionID)#\(turn.turnIndex) 失败：\(error)")
            }
            progress(index + 1, pending.count)
        }
        return (done, failed)
    }

    private static func complete(_ prompt: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 摘要只看这一段文本：声明成内部动作，服务端就不做检索、不注上下文、
        // 也不把它落成会话。不声明的话每条摘要都要多付一次冷预填（实测
        // 7,550 B 上下文 + 2 s 检索），还会在 chat_messages 里留一对假问答。
        request.setValue("internal", forHTTPHeaderField: "X-SimiGo-Request-Scope")
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
