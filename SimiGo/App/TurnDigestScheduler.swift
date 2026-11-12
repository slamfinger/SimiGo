import Foundation
import SimiGoRuntimeContract

/// 一轮写进空间之后，顺手把它的摘要补上。
///
/// 为什么走回环 HTTP：本地模型已经在 `127.0.0.1:8000` 上按 OpenAI 兼容接口
/// 提供服务，admission、常驻缓存、日志都在那条路上。再在 App 里接一层模型
/// 客户端，等于把同一件事做两遍，还会绕过那些门槛。
///
/// 三件不做的事：不阻塞回复（调用方写完就走，活排在后面）；失败不写行（缺口
/// 留在「缺摘要」的账上，不假装有摘要）；不重试到成功（一轮失败就是一轮失败）。
///
/// 一条硬规矩：**不跟人的推理抢引擎**。引擎同一时刻只跑一段生成，所以「异步」
/// 只解决调用方不等待，解决不了车型排队。这里做两层：
///   1 没人用、且空了 1.5 秒才开工；
///   2 跑着的时候只要有人排队（waiting>0），立刻取消这次请求让位——服务端看到
///     客户端断开就会停掉这一轮。让出去的活留在队里，等下一个空窗重来。
enum TurnDigestScheduler {
    private static let endpoint = URL(string: "http://127.0.0.1:8000/v1/chat/completions")!
    static var model = "local"

    private struct Job: Equatable, Sendable {
        let sessionID: String
        let turnIndex: Int
        let question: String
        let answer: String
        var key: String { "\(sessionID)#\(turnIndex)" }
    }

    private enum Digestion: Error {
        /// 有人要用引擎，这一轮让位，等空窗重来。
        case yielded
        case badFormat
    }

    private static let state = DispatchQueue(label: "simigo.turn-digest")
    private static var pending: [Job] = []
    private static var queued = Set<String>()
    private static var working = false

    /// 记下这一轮要补的东西就走。调用方在这条路上不等模型。
    static func schedule(
        sessionID: String, turnIndex: Int, question: String, answer: String
    ) {
        let job = Job(sessionID: sessionID, turnIndex: turnIndex,
                      question: question, answer: answer)
        let start: Bool = state.sync {
            guard queued.insert(job.key).inserted else { return false }
            pending.append(job)
            guard !working else { return false }
            working = true
            return true
        }
        guard start else { return }
        Task.detached(priority: .utility) { await drain() }
    }

    /// 单线程取活。永远只有一份摘要任务在引擎上，且随时给人让路。
    private static func drain() async {
        while true {
            let job: Job? = state.sync {
                guard let head = pending.first else {
                    working = false
                    return nil
                }
                return head
            }
            guard let job else { return }

            guard await waitForIdle() else {
                state.sync { working = false }
                return
            }
            do {
                let raw = try await completeYielding(
                    TurnDigestText.prompt(question: job.question, answer: job.answer))
                guard let parsed = TurnDigestText.parse(raw) else {
                    NSLog("[digest] \(job.key) 输出不合格式，留缺口")
                    finish(job)
                    continue
                }
                try write(job, parsed)
                finish(job)
            } catch Digestion.yielded {
                // 让位：留在队里，空下来再试。不记失败——这不是这一轮的错。
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                NSLog("[digest] \(job.key) 失败：\(error)")
                finish(job)
            }
        }
    }

    private static func finish(_ job: Job) {
        state.sync {
            if let index = pending.firstIndex(of: job) { pending.remove(at: index) }
            queued.remove(job.key)
        }
    }

    private static func write(_ job: Job, _ parsed: (digest: String, keywords: [String])) throws {
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        defer { db.close() }
        try db.recordTurnDigest(
            sessionID: job.sessionID, turnIndex: job.turnIndex,
            digest: parsed.digest,
            keywords: parsed.keywords.joined(separator: " "),
            model: "local:\(model)")
        // 增量：这一轮现在就有词了，当场判它进哪个房间。
        // 不归属的轮次等于素材进来了没人认识它——下一次检索找不到。
        // 失败只记日志：摘要已经写进去了，房间留给下一次「补录」兜。
        do {
            try db.assignTurnSpace(sessionID: job.sessionID, turnIndex: job.turnIndex)
        } catch {
            NSLog("[spaces] \(job.key) 进房间失败：\(error)")
        }
    }

    /// 等一个干净的空窗：没人跑、没人等，并且安静满 1.5 秒。
    /// 不设上限——排队本身是常态，等到就是等到；进程退出时随 Task 一起走。
    private static func waitForIdle() async -> Bool {
        var quietSince: Date?
        while !Task.isCancelled {
            let live = RuntimeStateReporter.shared.admissionLiveness()
            if live.active == 0 && live.waiting == 0 {
                if let since = quietSince {
                    if Date().timeIntervalSince(since) >= 1.5 { return true }
                } else {
                    quietSince = Date()
                }
            } else {
                quietSince = nil
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    /// 发一次补录请求；跑着的时候有人排队就让位。
    ///
    /// 让位靠取消这次 HTTP 请求：服务端在生成中监听客户端断连，断开即停这一轮
    /// 生成。留半截没有意义（摘要要么整轮有一句，要么留在缺口里）。
    ///
    /// 判据是「active>1 或 waiting>0」。自己占一格，所以超过一格就是别人；
    /// 只看 waiting 会漏掉并发槽位大于一时直接放行的请求。
    private static func completeYielding(_ prompt: String) async throws -> String {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { try await complete(prompt) }
            group.addTask {
                while true {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    let live = RuntimeStateReporter.shared.admissionLiveness()
                    // 占着的那一格是我们自己，所以 active>1 或有人排队，都是别人要用。
                    if live.active > 1 || live.waiting > 0 { return nil }
                }
            }
            for try await first in group {
                group.cancelAll()
                guard let raw = first else { throw Digestion.yielded }
                return raw
            }
            throw Digestion.badFormat
        }
    }

    /// 把「轮号有、摘要没有」的全部补齐。一次一轮、串行——本地模型本来
    /// 也是串行处理的，并发只会把预填挤在一起。
    ///
    /// 每补完一轮就回报一次，调用方据此更新进度；补不上的留在缺口里。
    static func fillMissing(
        limit: Int? = nil,
        shouldStop: @Sendable () -> Bool = { false },
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
            if shouldStop() { break }
            // 一轮跑完再看引擎空不空：补录可以慢，但不能把人的下一轮挤在后面。
            // 人一直不停手，补录就一直停着——这批活本来就是等人不在时做的。
            _ = await waitForIdle()
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
    /// 掉到 54/177）。补进来的词也不再按「原文里有没有」筛：原文里没有、
    /// 讲的却是这件事的说法，正是词表比摘要多出来的入口。
    static func repairKeywords(
        limit: Int? = nil,
        shouldStop: @Sendable () -> Bool = { false },
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
            if shouldStop() { break }
            _ = await waitForIdle()
            do {
                let raw = try await complete(TurnDigestText.keywordPrompt(
                    question: turn.question, answer: turn.answer))
                guard let fresh = TurnDigestText.parseKeywords(raw) else {
                    failed += 1
                    progress(index + 1, pending.count)
                    continue
                }
                let merged = TurnDigestText.mergeKeywords(turn.keywords, fresh)
                // 模型一个词都没补进来：这一轮算没修成，不写空写。
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
