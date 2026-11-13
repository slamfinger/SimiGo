import Foundation
import SimiGoRuntimeContract

/// 回执里每轮要一个 `sessionID#turnIndex`。类型在契约包里不知道回执存在，
/// 键的拼法只有调度器用，放这里。
private extension ESISDatabase.UndigestedTurn {
    var key: String { "\(sessionID)#\(turnIndex)" }
}

private extension ESISDatabase.DigestTurnText {
    var key: String { "\(sessionID)#\(turnIndex)" }
}

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
    /// 测试注入口：回执回归要拦下 HTTP 层（URLProtocol stub）。产品路径
    /// 恒为 shared，与 `model` 同一条规矩：只有测试会写它。
    static var completeSession: URLSession = .shared

    private struct Job: Equatable, Sendable {
        let sessionID: String
        let turnIndex: Int
        let question: String
        let answer: String
        var key: String { "\(sessionID)#\(turnIndex)" }
        var bytes: Int { question.utf8.count + answer.utf8.count }
    }

    /// 错误类型进了契约包（失败分类要在包测试里断言），这里留个别名，
    /// 各 catch 点的写法保持不变。
    private typealias Digestion = DigestRepairReceipt.DigestionError

    /// 让位计数。补录循环是顺序 await，一个带锁的小盒子就够。
    private final class YieldCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func inc() {
            lock.lock(); count += 1; lock.unlock()
        }
        var value: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }
    }

    /// 停止开关。写在主线程、读在后台，所以状态必须过锁——`@unchecked Sendable`
    /// 只豁免编译检查，不提供同步。所有生成路径共用同一个判据：等空窗时轮询它，
    /// 生成时每 300 ms 轮询它，看见就取消这次 HTTP 请求（服务端断连即停生成）。
    final class DigestStop: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock(); cancelled = true; lock.unlock()
        }

        func reset() {
            lock.lock(); cancelled = false; lock.unlock()
        }
    }

    private static let state = DispatchQueue(label: "simigo.turn-digest")
    private static var pending: [Job] = []
    private static var queued = Set<String>()
    private static var working = false
    private static var pendingBytes = 0

    /// 队列上限。持续用引擎、一直等不到空窗时，队里攒的是整段问答原文；
    /// 没有上限就是无界内存。满了就放弃这一轮——缺口还在账上，下次补录能捞回来，
    /// 比悄悄吃满内存好。
    private static let maxPending = 64
    private static let maxPendingBytes = 1 << 20

    /// 记下这一轮要补的东西就走。调用方在这条路上不等模型。
    static func schedule(
        sessionID: String, turnIndex: Int, question: String, answer: String
    ) {
        let job = Job(sessionID: sessionID, turnIndex: turnIndex,
                      question: question, answer: answer)
        let start: Bool = state.sync {
            guard pending.count < maxPending,
                  pendingBytes + job.bytes <= maxPendingBytes else {
                NSLog("[digest] 队列已满（\(pending.count) 轮 / \(pendingBytes) B），"
                      + "\(job.key) 留缺口")
                return false
            }
            guard queued.insert(job.key).inserted else { return false }
            pending.append(job)
            pendingBytes += job.bytes
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

            do {
                let raw = try await generate(
                    TurnDigestText.prompt(question: job.question, answer: job.answer),
                    stop: nil)
                guard let parsed = TurnDigestText.parse(raw) else {
                    NSLog("[digest] \(job.key) 格式不合，留缺口")
                    finish(job)
                    continue
                }
                try write(job, parsed)
                finish(job)
            } catch Digestion.stopped {
                // 任务被取消：把 working 放掉，免得后面没人再起 drain。
                state.sync { working = false }
                return
            } catch {
                NSLog("[digest] \(job.key) 失败"
                      + "（\(DigestRepairReceipt.FailureReason.describe(error))）：\(error)")
                finish(job)
            }
        }
    }

    private static func finish(_ job: Job) {
        state.sync {
            if let index = pending.firstIndex(of: job) { pending.remove(at: index) }
            queued.remove(job.key)
            pendingBytes = max(0, pendingBytes - job.bytes)
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
        // 失败不是一行日志就完了（#187）：进持久化待重试记录，进程重启后
        // 仍在；本轮和后续每一次摘要写入都会顺手重放，直到归属写上或到达
        // 重试上限。
        do {
            try db.assignTurnSpace(sessionID: job.sessionID, turnIndex: job.turnIndex)
        } catch {
            NSLog("[spaces] \(job.key) 进房间失败，进重试队列：\(error)")
            try? db.recordSpaceAssignmentFailure(
                sessionID: job.sessionID, turnIndex: job.turnIndex, error: error)
        }
        // 无论本轮归属成没成，都重放一遍队列：多半为空（一条 SELECT），
        // 有积压时这就是不靠人点的恢复路径。
        if let report = try? db.retryPendingSpaceAssignments(),
           report.retried > 0 {
            NSLog("[spaces] 重放待重试归属：成功 \(report.succeeded)，"
                  + "仍失败 \(report.stillPending)，达上限 \(report.abandoned)")
        }
    }

    /// 等一个干净的空窗：没人跑、没人等，并且安静满 1.5 秒。
    /// 不设上限——排队本身是常态，等到就是等到；进程退出时随 Task 一起走。
    /// 返回 false 只有两种：任务被取消，或者人按了停止。
    private static func waitForIdle(_ stop: DigestStop?) async -> Bool {
        var quietSince: Date?
        while !Task.isCancelled {
            if stop?.isCancelled == true { return false }
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
    private static func completeYielding(_ prompt: String,
                                         stop: DigestStop?) async throws -> String {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { try await complete(prompt) }
            group.addTask {
                while true {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    // 停止优先于让位：被取消的请求不再重排。
                    if stop?.isCancelled == true { return nil }
                    let live = RuntimeStateReporter.shared.admissionLiveness()
                    // 占着的那一格是我们自己，所以 active>1 或有人排队，都是别人要用。
                    if live.active > 1 || live.waiting > 0 { return nil }
                }
            }
            for try await first in group {
                group.cancelAll()
                guard let raw = first else {
                    throw stop?.isCancelled == true ? Digestion.stopped : Digestion.yielded
                }
                return raw
            }
            throw Digestion.badFormat
        }
    }

    /// 三条生成路径唯一的入口：等空窗 → 生成 → 有人要用引擎就让位重来。
    /// 让位不是失败，这一轮留在原地等下一个空窗；停止才是终止。
    /// `onYield` 每让位一次记一笔——回执要能说清「让位 N 次」（#189），
    /// 让位本身不进失败数。
    private static func generate(_ prompt: String,
                                 stop: DigestStop?,
                                 onYield: @escaping @Sendable () -> Void = {}) async throws -> String {
        while true {
            if Task.isCancelled || stop?.isCancelled == true { throw Digestion.stopped }
            guard await waitForIdle(stop) else { throw Digestion.stopped }
            // 等待结束后再查一次：等的时候人可能刚按了停止。
            if stop?.isCancelled == true { throw Digestion.stopped }
            do {
                return try await completeYielding(prompt, stop: stop)
            } catch Digestion.yielded {
                // 让位：不记失败——这不是这一轮的错。
                onYield()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    /// 把「轮号有、摘要没有」的全部补齐。一次一轮、串行——本地模型本来
    /// 也是串行处理的，并发只会把预填挤在一起。
    ///
    /// 每补完一轮就回报一次，调用方据此更新进度；补不上的留在缺口里，并且
    /// 每一轮的失败原因都进回执（#189）：格式、HTTP、写库各有各的名字，
    /// 让位与停止不计入失败、单独报数。
    static func fillMissing(
        limit: Int? = nil,
        stop: DigestStop? = nil,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> DigestRepairReceipt {
        var pending: [ESISDatabase.UndigestedTurn]
        do {
            let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
            defer { db.close() }
            pending = try db.undigestedTurns()
        } catch {
            NSLog("[digest] 读缺口失败：\(error)")
            return .empty
        }
        if let limit, limit < pending.count { pending = Array(pending.prefix(limit)) }
        var done = 0, failed = 0, yielded = 0
        var failures: [DigestRepairReceipt.Failure] = []
        var stoppedAt: String?
        let yieldBox = YieldCounter()
        for (index, turn) in pending.enumerated() {
            if stop?.isCancelled == true {
                stoppedAt = turn.key
                break
            }
            do {
                // 和增量摘要走同一个入口：等空窗、生成中让人、停止能打断。
                let raw = try await generate(TurnDigestText.prompt(
                    question: turn.question, answer: turn.answer), stop: stop,
                    onYield: { yieldBox.inc() })
                guard let parsed = TurnDigestText.parse(raw) else {
                    failed += 1
                    failures.append(DigestRepairReceipt.Failure(
                        key: turn.key, reason: DigestRepairReceipt.FailureReason.badFormat))
                    progress(index + 1, pending.count)
                    continue
                }
                let db = try ESISDatabase(url: ManagedPaths.databaseURL,
                                          createIfNeeded: true)
                defer { db.close() }
                do {
                    try db.recordTurnDigest(
                        sessionID: turn.sessionID, turnIndex: turn.turnIndex,
                        questionMessageID: turn.questionMessageID,
                        answerMessageID: turn.answerMessageID,
                        digest: parsed.digest,
                        keywords: parsed.keywords.joined(separator: " "),
                        model: "local:\(model)")
                    done += 1
                } catch {
                    // 生成成功了、落库失败：这不是 HTTP 的事，不借它的名字。
                    failed += 1
                    failures.append(DigestRepairReceipt.Failure(
                        key: turn.key, reason: "写库：\(error)"))
                    NSLog("[digest] \(turn.sessionID)#\(turn.turnIndex) 写库失败：\(error)")
                }
            } catch Digestion.stopped {
                stoppedAt = turn.key
                break
            } catch {
                failed += 1
                failures.append(DigestRepairReceipt.Failure(
                    key: turn.key,
                    reason: DigestRepairReceipt.FailureReason.describe(error)))
                NSLog("[digest] \(turn.sessionID)#\(turn.turnIndex) 失败：\(error)")
            }
            progress(index + 1, pending.count)
        }
        return DigestRepairReceipt(
            done: done, failed: failed, failures: failures,
            yielded: yielded + yieldBox.value, stoppedAt: stoppedAt)
    }

    /// 只修词，不动摘要。
    ///
    /// 已有的词留着——它们是这一轮被捞出来的入口，删掉就是把口子堵上
    /// （2026-11-12 实测：按「原文里搜不到」删词，别名查询的召回从 177/177
    /// 掉到 54/177）。补进来的词也不再按「原文里有没有」筛：原文里没有、
    /// 讲的却是这件事的说法，正是词表比摘要多出来的入口。
    static func repairKeywords(
        limit: Int? = nil,
        stop: DigestStop? = nil,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> DigestRepairReceipt {
        var pending: [ESISDatabase.DigestTurnText]
        do {
            let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
            defer { db.close() }
            pending = try db.turnsWithThinKeywords(limit: limit)
        } catch {
            NSLog("[digest] 读缺词轮次失败：\(error)")
            return .empty
        }
        var done = 0, failed = 0
        var failures: [DigestRepairReceipt.Failure] = []
        var stoppedAt: String?
        let yieldBox = YieldCounter()
        for (index, turn) in pending.enumerated() {
            if stop?.isCancelled == true {
                stoppedAt = turn.key
                break
            }
            do {
                // 与摘要同一条调度：生成中有人来就取消这次请求，等空窗重来。
                let raw = try await generate(TurnDigestText.keywordPrompt(
                    question: turn.question, answer: turn.answer), stop: stop,
                    onYield: { yieldBox.inc() })
                guard let fresh = TurnDigestText.parseKeywords(raw) else {
                    failed += 1
                    failures.append(DigestRepairReceipt.Failure(
                        key: turn.key, reason: DigestRepairReceipt.FailureReason.badFormat))
                    progress(index + 1, pending.count)
                    continue
                }
                let merged = TurnDigestText.mergeKeywords(turn.keywords, fresh)
                // 模型一个词都没补进来：这一轮算没修成，不写空写。
                guard merged.count > turn.keywords.count else {
                    failed += 1
                    failures.append(DigestRepairReceipt.Failure(
                        key: turn.key, reason: "模型没补出新词"))
                    progress(index + 1, pending.count)
                    continue
                }
                let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                do {
                    try db.replaceTurnKeywords(
                        sessionID: turn.sessionID, turnIndex: turn.turnIndex,
                        keywords: merged)
                    done += 1
                } catch {
                    failed += 1
                    failures.append(DigestRepairReceipt.Failure(
                        key: turn.key, reason: "写库：\(error)"))
                    NSLog("[digest] 修词 \(turn.sessionID)#\(turn.turnIndex) 写库失败：\(error)")
                }
            } catch Digestion.stopped {
                stoppedAt = turn.key
                break
            } catch {
                failed += 1
                failures.append(DigestRepairReceipt.Failure(
                    key: turn.key,
                    reason: DigestRepairReceipt.FailureReason.describe(error)))
                NSLog("[digest] 修词 \(turn.sessionID)#\(turn.turnIndex) 失败：\(error)")
            }
            progress(index + 1, pending.count)
        }
        return DigestRepairReceipt(
            done: done, failed: failed, failures: failures,
            yielded: yieldBox.value, stoppedAt: stoppedAt)
    }

    /// 启动时重放一次待重试的归属（#187）：重试行跨进程持久，恢复不依赖
    /// 人点补录。归属判断只吃关键词与判据词，不碰引擎——宿主与模型模式
    /// 都能跑。
    static func replayPendingRoomAssignmentsAtLaunch() {
        Task.detached(priority: .utility) {
            do {
                let db = try ESISDatabase(url: ManagedPaths.databaseURL,
                                          createIfNeeded: true)
                defer { db.close() }
                let report = try db.retryPendingSpaceAssignments()
                if report.retried > 0 {
                    NSLog("[spaces] 启动重放待重试归属：成功 \(report.succeeded)，"
                          + "仍失败 \(report.stillPending)，达上限 \(report.abandoned)")
                }
            } catch {
                NSLog("[spaces] 启动重放失败：\(error)")
            }
        }
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
        let (data, response) = try await completeSession.data(for: request)
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
