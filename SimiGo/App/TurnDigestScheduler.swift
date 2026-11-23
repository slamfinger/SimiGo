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

/// FIFO async admission shared by incremental digest, backfill, and keyword repair.
/// Waiters suspend; this does not dedicate or block an OS thread. The current MLX
/// runtime intentionally serializes generation because concurrent dynamic-kernel
/// compilation previously deadlocked. Only relax this limit after real-model proof.
private actor DigestGenerationGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if active < limit && waiters.isEmpty {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { active -= 1 }
        else { waiters.removeFirst().resume() }
    }
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
        var questionSHA256: String {
            TurnDigestText.sourceSHA256(question)
        }
        var answerSHA256: String {
            TurnDigestText.sourceSHA256(answer)
        }
    }

    private enum BackfillOutcome: Sendable {
        case alreadySettled
        case written
        case badFormat
        case staleSource
        case writeFailed(String)
    }

    private enum KeywordRepairOutcome: Sendable {
        case written
        case badFormat
        case noNewWords
        case writeFailed(String)
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
    /// Shared FIFO admission prevents two background clients from self-cancelling.
    /// Current MLX generation is deliberately single-flight; this gate is async,
    /// so drain/backfill/keyword workers do not occupy a dedicated thread.
    private static let generationGate = DigestGenerationGate(limit: 1)
    private static var pending: [Job] = []
    private static var queued = Set<String>()
    private static var activeKey: String?
    private static var working = false
    private static var pendingBytes = 0
    /// 每一轮试过几次。**只作诊断**：不设上限、不到点丢弃——暂时性失败
    /// （模型还没起来）如果被当成这一轮做完，缺口就永远等不到自动补。
    private static var attempts: [String: Int] = [:]
    /// Terminal failures are deferred for this process lifetime; the durable IS gap
    /// remains available for a later launch or explicit repair.
    private static var deferredKeys = Set<String>()
    /// Test-only override; nil preserves the production idle quiet period.
    static var idleQuietPeriodForTesting: TimeInterval?
    /// Isolates scheduler tests from admission counters left by unrelated app tests.
    /// Production leaves this nil and reads the live runtime reporter.
    static var admissionLivenessForTesting: (@Sendable () -> (active: Int, waiting: Int))?

    private static func admissionLiveness() -> (active: Int, waiting: Int) {
        admissionLivenessForTesting?() ?? RuntimeStateReporter.shared.admissionLiveness()
    }
    /// 最近一次暂时失败。队列里躺着的活没有别的可见面（日志在 Console），
    /// 出问题时要能回答「是哪一轮、为什么、试了几次」。
    private static var transientFailure: (key: String, reason: String, tries: Int)?

    /// 队里还剩几轮（诊断与测试用）。
    static var pendingDepth: Int { state.sync { pending.count } }

    /// 最近一次暂时失败（诊断与测试用）。成功或永久失败不清空它——它记的是
    /// 「上一次为什么没成」，不是「现在还有没有活」。
    static var lastTransientFailure: (key: String, reason: String, tries: Int)? {
        state.sync { transientFailure }
    }

    /// Tests that swap SIMIGO_HOME or remove an isolated database must wait for
    /// the detached drain task to relinquish its worker ownership first.
    /// A zero queue depth alone is insufficient: the worker can still be in its
    /// final durable-ledger refill/exit path.
    static func waitForDrainToBecomeIdleForTesting(
        timeout: TimeInterval = 15
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let idle = state.sync { !working && activeKey == nil }
            if idle { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return state.sync { !working && activeKey == nil }
    }

    /// 清空内存队列。队里没做完的活没有落库，重启语义下本来就由缺口重建
    /// (`replayPendingDigestsAtLaunch`)。只有测试会写它。
    static func resetQueueForTesting() {
        state.sync {
            pending = []; queued = []; pendingBytes = 0
            activeKey = nil
            working = false; attempts = [:]; deferredKeys = []; transientFailure = nil
        }
    }

    /// 退避到点要有人叫醒：只靠启动和下一次摘要写入，一条到期的欠账在空闲的
    /// 进程里可以躺到天亮。监视器每 `interval` 秒看一眼队列，判断「到没到时间」
    /// 仍然由 `retryPendingSpaceAssignments` 按 `next_attempt_at` 自己做。
    ///
    /// 它只是 SimiGo 的运行时协助，不是让 IS 自己跑起来：结算归 ES，IS 接收并
    /// 保存（`put`），`ESISDatabase` 是被调用、被读写的存储实现。谁欠一次归属
    /// 由 SimiGo 记账，什么时候重判也由 SimiGo 的进程决定。
    private final class RoomAssignmentRetryTimer: @unchecked Sendable {
        private let lock = NSLock()
        private var source: DispatchSourceTimer?
        /// 每一次「请继续盯着」都推进这个代数——包括定时器已经在走的时候。
        /// 心跳收尾要停表时拿它比对：中途有人叫过醒，就不许停。
        private var wakeGeneration: UInt64 = 0

        func start(interval: TimeInterval, handler: @escaping @Sendable () -> Void) {
            lock.lock()
            wakeGeneration &+= 1
            guard source == nil else {
                lock.unlock()
                return
            }
            let queue = DispatchQueue(
                label: "simigo.room-assignment-retry", qos: .utility)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now() + interval,
                repeating: interval,
                leeway: .milliseconds(100))
            timer.setEventHandler(handler: handler)
            source = timer
            lock.unlock()
            timer.resume()
        }

        func generationSnapshot() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            return wakeGeneration
        }

        /// 空闲心跳只有在「它开始之后没人再叫过醒」时才允许停表——这一条
        /// 堵的是「入队/起表」与「停表」交错：新欠账落了库、也叫了醒，心跳却
        /// 拿着一秒前的空队列把它关掉，那一行就要等到下一次写入才动。
        func stop(ifGeneration expected: UInt64) {
            lock.lock()
            defer { lock.unlock() }
            guard wakeGeneration == expected else { return }
            source?.cancel()
            source = nil
            wakeGeneration &+= 1
        }

        func stop() {
            lock.lock()
            defer { lock.unlock() }
            wakeGeneration &+= 1
            source?.cancel()
            source = nil
        }

        var isRunning: Bool {
            lock.lock()
            defer { lock.unlock() }
            return source != nil
        }
    }

    private static let roomAssignmentRetryTimer = RoomAssignmentRetryTimer()

    /// 监视间隔。测试把它压到 0.2 秒，跑完还原；产品路径一直是 30 秒。
    static var retryMonitorInterval: TimeInterval = 30

    /// 竞态注入口（只测试写）：在心跳拿到空队列快照之后、真正尝试停表之前调用。
    /// 往这里塞一次「写欠账 + 叫醒」，就能确定性地复现上面那个交错。
    static var retryMonitorIdleStopHookForTesting: (@Sendable () -> Void)?

    /// 起一次监视（幂等：已经在走不另起第二张表，但会登记一次新的唤醒请求）。
    static func startRoomAssignmentRetryMonitor() {
        roomAssignmentRetryTimer.start(interval: retryMonitorInterval) {
            runScheduledRoomAssignmentRetry()
        }
    }

    /// 停掉监视。产品里不调用（跟随进程）；测试用完要停，否则它会带着
    /// 出厂节奏接着打真实库。
    static func stopRoomAssignmentRetryMonitor() {
        roomAssignmentRetryTimer.stop()
    }

    /// 监视器在不在走（诊断与测试用）。
    static var isRoomAssignmentRetryMonitorRunning: Bool {
        roomAssignmentRetryTimer.isRunning
    }

    /// 队列上限。内存只保留有限批次；满了不丢 IS 账，drain 排空一批后会从
    /// 持久化缺口中取下一批，避免启动时超过上限的轮次永久等到下一次重放。
    private static let maxPending = 64
    private static let maxPendingBytes = 1 << 20
    /// badFormat 有界重试上限（owner 2026-11-23 裁定 ②+①）：本机随机退化模型
    /// （coder 模型做中文摘要）同一段正文再喂一遍可能换个格式就过（实测复现
    /// 3/3 过），故格式不合不再一律永久出队，而是重试至多本数仍不合才留缺口。
    /// 与无上限的暂时性失败（引擎没起/连接拒）区分：格式错是这一轮自己的错，
    /// 必须有界，避免退化模型无限自旋。
    private static let maxFormatAttempts = 3

    /// 记下这一轮要补的东西就走。调用方在这条路上不等模型。
    static func schedule(
        sessionID: String, turnIndex: Int, question: String, answer: String
    ) {
        let job = Job(sessionID: sessionID, turnIndex: turnIndex,
                      question: question, answer: answer)
        let start: Bool = state.sync {
            // A fresh committed write re-arms a previously deferred turn.
            deferredKeys.remove(job.key)
            if queued.contains(job.key) {
                // The drain owns its local in-flight value. The queue entry is
                // separately replaceable: after the source guard rejects the old
                // value, the same key can immediately continue with this snapshot.
                if let index = pending.firstIndex(where: { $0.key == job.key }) {
                    let nextBytes = pendingBytes + job.bytes - pending[index].bytes
                    guard job.bytes <= maxPendingBytes, nextBytes <= maxPendingBytes else {
                        Service.log("[digest] 更新后的正文超出内存队列预算，保留既有待办：\(job.key)",
                                    level: .warning)
                        return false
                    }
                    pendingBytes = nextBytes
                    pending[index] = job
                }
                guard !working else { return false }
                working = true
                return true
            }
            guard pending.count < maxPending,
                  pendingBytes + job.bytes <= maxPendingBytes else {
                Service.log("[digest] 队列已满（\(pending.count) 轮 / \(pendingBytes) B），"
                            + "\(job.key) 留在 IS 缺口账，排空后自动补入", level: .warning)
                // If a previous transient failure left a full queue dormant, the
                // rejected new turn still wakes that existing durable backlog.
                guard !working, !pending.isEmpty else { return false }
                working = true
                return true
            }
            queued.insert(job.key)
            pending.append(job)
            pendingBytes += job.bytes
            guard !working else { return false }
            working = true
            return true
        }
        guard start else { return }
        Task.detached(priority: .utility) { await drain() }
    }

    /// Drain a bounded in-memory batch, then refill it from the durable IS gap ledger.
    /// Queue saturation is backpressure, not loss: undigested turns remain discoverable.
    private static func drain() async {
        while true {
            var job: Job? = state.sync {
                guard let head = pending.first else { return nil }
                activeKey = head.key
                return head
            }
            if job == nil {
                _ = refillPendingFromLedger()
                let shouldStop = state.sync {
                    guard pending.isEmpty else { return false }
                    working = false
                    return true
                }
                if shouldStop { return }
                job = state.sync {
                    guard let head = pending.first else { return nil }
                    activeKey = head.key
                    return head
                }
            }
            guard let job else { continue }

            // 过程要能事后还原：库里只证明结果，日志证明这一次是怎么走到结果的。
            // 第几次由失败计数得出——暂时失败的轮还躺在队里，下一次被调度捞起来
            // 就是第 n+1 次。
            let (tries, depth): (Int, Int) = state.sync {
                ((attempts[job.key] ?? 0) + 1, pending.count)
            }
            Service.log("[digest] 尝试开始 \(job.key)，第 \(tries) 次，队里 \(depth) 轮")

            do {
                let wrote: Bool = try await generate(
                    TurnDigestText.prompt(
                        question: job.question, answer: job.answer,
                        background: briefBackground()),
                    stop: nil,
                    undigestedTurn: (sessionID: job.sessionID, turnIndex: job.turnIndex)
                ) { raw in
                    guard let raw else { return false }
                    guard let parsed = TurnDigestText.parse(raw) else {
                        throw Digestion.badFormat
                    }
                    try write(job, parsed)
                    return true
                }
                finish(job)
                if wrote {
                    Service.log("[digest] 完成 \(job.key)，摘要已落库")
                }
                continue
            } catch Digestion.stopped {
                // 任务被取消：把当前任务与 worker 标记放掉，后续调度可重启。
                state.sync { activeKey = nil; working = false }
                return
            } catch Digestion.staleSource {
                // The active generation was based on a message version that no
                // longer exists. Prefer the latest durable turn snapshot, then
                // release the old active job; finish() preserves the replacement.
                enqueueLatestUndigestedTurn(
                    sessionID: job.sessionID, turnIndex: job.turnIndex)
                finish(job)
                Service.log(
                    "[digest] \(job.key) 源正文已变化，拒绝旧摘要并重新排队当前版本")
                continue
            } catch {
                let hasReplacement = state.sync {
                    pending.first(where: { $0.key == job.key }).map { $0 != job } ?? false
                }
                if hasReplacement {
                    // A newer source snapshot superseded this job while it was
                    // in flight. Do not defer or rotate the replacement because
                    // the old snapshot failed.
                    finish(job)
                    continue
                }
                let reason = DigestRepairReceipt.FailureReason.describe(error)
                let priorTries = state.sync { attempts[job.key] ?? 0 }
                guard isRetryable(error, attempts: priorTries) else {
                    // 不可恢复的错（格式不合且已超有界重试上限）：出队、留缺口，
                    // 原因单独报，不跟「模型还没起来」混成一句。
                    Service.log("[digest] 永久失败 \(job.key)（\(reason)），出队留缺口：\(error)",
                                level: .warning)
                    finish(job, permanentlyDefer: true)
                    continue
                }
                // 暂时性失败（引擎没起、连接被拒、非 200、撞锁）：这一轮**不出队**，
                // 挪到队尾，这一轮到此为止，等下一次独立触发再试（下一次
                // `schedule` 落新轮，或启动时的重建）。不在这里自旋重试、不设上限。
                let (tries, depth): (Int, Int) = state.sync {
                    let n = (attempts[job.key] ?? 0) + 1
                    attempts[job.key] = n
                    transientFailure = (job.key, reason, n)
                    if let index = pending.firstIndex(of: job) {
                        pending.append(pending.remove(at: index))
                    }
                    activeKey = nil
                    working = false
                    return (n, pending.count)
                }
                Service.log("[digest] 暂时失败 \(job.key)（\(reason)），第 \(tries) 次，"
                            + "不出队，队里共 \(depth) 轮等下一次调度：\(error)",
                            level: .warning)
                return
            }
        }
    }

    private static func finish(_ job: Job, permanentlyDefer: Bool = false) {
        state.sync {
            if let index = pending.firstIndex(where: { $0.key == job.key }) {
                if pending[index] == job {
                    pending.remove(at: index)
                    queued.remove(job.key)
                    pendingBytes = max(0, pendingBytes - job.bytes)
                    if permanentlyDefer { deferredKeys.insert(job.key) }
                }
                // Otherwise this key now belongs to a newer queued snapshot.
                // Keep its queue membership and byte accounting intact.
            } else {
                queued.remove(job.key)
            }
            if activeKey == job.key { activeKey = nil }
            attempts.removeValue(forKey: job.key)
        }
    }

    /// Reload the current durable source after an in-flight digest was invalidated.
    /// A correction deletes the old digest and updates the message object/hash in
    /// one transaction, so undigestedTurns() is the authoritative replacement.
    private static func enqueueLatestUndigestedTurn(
        sessionID: String, turnIndex: Int
    ) {
        let latest: ESISDatabase.UndigestedTurn?
        do {
            let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
            defer { db.close() }
            latest = try db.undigestedTurns().first {
                $0.sessionID == sessionID && $0.turnIndex == turnIndex
            }
        } catch {
            Service.log(
                "[digest] \(sessionID)#\(turnIndex) 读取更正后的轮次失败：\(error)",
                level: .error)
            return
        }
        guard let latest else { return }
        schedule(
            sessionID: latest.sessionID, turnIndex: latest.turnIndex,
            question: latest.question, answer: latest.answer)
    }

    /// Read the next bounded batch after the current one is settled. Successful rows
    /// have disappeared from undigestedTurns(); permanent failures are skipped until
    /// the next process launch, but their durable gap records are not deleted.
    @discardableResult
    private static func refillPendingFromLedger() -> Bool {
        let gaps: [ESISDatabase.UndigestedTurn]
        do {
            let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
            defer { db.close() }
            gaps = try db.undigestedTurns()
        } catch {
            Service.log("[digest] 从 IS 缺口账补入队列失败：\(error)", level: .error)
            return false
        }

        return state.sync {
            for turn in gaps {
                let key = turn.key
                guard !queued.contains(key), !deferredKeys.contains(key) else { continue }
                let job = Job(
                    sessionID: turn.sessionID, turnIndex: turn.turnIndex,
                    question: turn.question, answer: turn.answer)
                guard job.bytes <= maxPendingBytes else {
                    deferredKeys.insert(key)
                    Service.log("[digest] 单轮正文超过内存队列预算，留在 IS 缺口账：\(key)",
                                level: .warning)
                    continue
                }
                if pending.count >= maxPending { break }
                guard pendingBytes + job.bytes <= maxPendingBytes else { continue }
                queued.insert(key)
                pending.append(job)
                pendingBytes += job.bytes
            }
            return !pending.isEmpty
        }
    }

    /// 重试有没有意义。引擎没起、连接被拒、非 200、撞锁都是外面的状态，过
    /// 一会儿就会变，无上限重试。「模型输出格式不合」对确定性差法重试无益，
    /// 但本机随机退化模型同一段正文再喂一遍可能换个格式就过（实测复现 3/3
    /// 过）——故 badFormat 改为**有界**重试（owner 2026-11-23 裁定 ②+①）：
    /// attempts < maxFormatAttempts 时仍可重试，超过才永久出队留缺口。
    /// 回填路径（repairLoop）不传计数，默认 .max 保持原语义：格式不合照样
    /// 记缺口延迟——缺口下次 fillMissing 会从库里重读，跨重启天然再试。
    private static func isRetryable(_ error: Error, attempts: Int = .max) -> Bool {
        if let digestion = error as? Digestion, digestion == .badFormat {
            return attempts < maxFormatAttempts
        }
        return true
    }

    /// 归属判定这一步本身。测试注入口：用例换成必失败，验证「失败 → 待办已在
    /// 库 → 重放补上」这条链；产品路径恒为 `db.assignTurnSpace`，与
    /// `model` / `completeSession` 同一条规矩——只有测试会写它。
    static var assignRoom: @Sendable (ESISDatabase, String, Int) throws -> Void = { db, session, turn in
        _ = try db.assignTurnSpace(sessionID: session, turnIndex: turn)
    }

    /// 一轮摘要落库，随后判归属。抽出来是为了让测试走同一段代码。
    ///
    /// 摘要与「还欠一次归属判断」写在**同一个事务**里（#187）：撞锁时必须先
    /// 有据可查。上一版是先判再补记录，那次补记录自己也可能撞锁，`try?` 一
    /// 吞，摘要落了、归属没了、连待办都没留。现在顺序反过来——先记欠账，再
    /// 判；判失败只剩「补原因与退避」这件事，它失败也不影响那一轮还会被重放。
    @discardableResult
    static func recordDigestAndAssign(
        sessionID: String, turnIndex: Int, digest: String, keywords: [String],
        expectedQuestionSHA256: String? = nil,
        expectedAnswerSHA256: String? = nil
    ) throws -> ESISDatabase.TurnDigestRecord {
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        defer { db.close() }
        let record = try db.recordTurnDigest(
            sessionID: sessionID, turnIndex: turnIndex,
            digest: digest, keywords: keywords.joined(separator: " "),
            model: "local:\(model)", requestSpaceAssignment: true,
            expectedQuestionSHA256: expectedQuestionSHA256,
            expectedAnswerSHA256: expectedAnswerSHA256)
        // Render-side memory: the settled digest is fed to inference from process
        // memory, not re-read from IS every turn. Memory stays a subset of the
        // durable row just written; a cold process fails open to the IS read.
        ISContextLedger.shared.rememberDigest(
            scope: sessionID, turnIndex: turnIndex, digest: record.digest)
        // Zero-call fold fill (forward): a reuse turn that settled BEFORE this
        // digest landed inherits it now, instead of waiting for the async drain
        // (build20 no_coverage: turn 2 settled ~13s before turn 1's warm write).
        // Fail-open: a fill error never invalidates the primary digest just written.
        let filled = (try? db.fillFoldedReuseDigests(sessionID: sessionID)) ?? []
        for copy in filled {
            ISContextLedger.shared.rememberDigest(
                scope: sessionID, turnIndex: copy.turn, digest: copy.digest)
        }
        if !filled.isEmpty {
            RuntimeTraceLogger.shared.trace(
                "[DIGEST_COPY] session=\(RuntimeTraceLogger.short(sessionID)) "
                    + "from=\(turnIndex) turns=\(filled.map { String($0.turn) }.joined(separator: ",")) "
                    + "model_calls=0")
        }
        do {
            try assignRoom(db, sessionID, turnIndex)
            // 判上了，欠账销掉；销不掉也只是下次再判一遍（重放幂等）。
            try? db.clearSpaceAssignmentPending(
                sessionID: sessionID, turnIndex: turnIndex)
        } catch {
            do {
                try db.recordSpaceAssignmentFailure(
                    sessionID: sessionID, turnIndex: turnIndex, error: error)
                Service.log("[spaces] \(sessionID)#\(turnIndex) 进房间失败，已在重试队列：\(error)", level: .error)
            } catch {
                // 待办本身早在摘要事务里落的，这里丢的只是「为什么失败」。
                Service.log("[spaces] \(sessionID)#\(turnIndex) 进房间失败，"
                      + "失败原因也没写进库：\(error)", level: .error)
            }
        }
        return record
    }

    private static func write(_ job: Job, _ parsed: (digest: String, keywords: [String])) throws {
        do {
            try recordDigestAndAssign(
                sessionID: job.sessionID, turnIndex: job.turnIndex,
                digest: parsed.digest, keywords: parsed.keywords,
                expectedQuestionSHA256: job.questionSHA256,
                expectedAnswerSHA256: job.answerSHA256)
        } catch let error as ESISDatabase.DatabaseError {
            if case .staleTurnDigestSource = error {
                throw Digestion.staleSource
            }
            throw error
        }
        // 无论本轮归属成没成，都重放一遍队列：多半为空（一条 SELECT），
        // 有积压时这就是不靠人点的恢复路径。
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
        defer { db.close() }
        replayPendingAssignments(db, label: "摘要写入后")
    }

    /// The owner brief shapes what the local summarizer understands before its
    /// output lands in ES/IS. Read per job so a rewritten brief applies to the
    /// next digest; any failure degrades to no background instead of blocking.
    /// Internal (not private): the warm-digest path in the chat handler builds
    /// the same prompt with the same background, one source of truth.
    static func briefBackground() -> String? {
        guard let db = try? ESISDatabase(
            url: ManagedPaths.databaseURL, createIfNeeded: false) else { return nil }
        defer { db.close() }
        let kind = ESISDatabase.scopedKind("brief", scope: ESISDatabase.ownerNamespace)
        guard let note = try? db.currentProjectNote(kind: kind) else { return nil }
        let claim = note.claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !claim.isEmpty else { return nil }
        return "note \(note.noteID.prefix(8)) · 记录 \(note.recordedAt)\n\(claim)"
    }

    /// 重放一次待办，并把结果写进日志。**放弃的也要报**：`abandoned` 的行不会
    /// 再自己动，只在 `retried > 0` 时才打日志等于把它们藏起来（审核 2026-11-13）。
    private static func replayPendingAssignments(
        _ db: ESISDatabase, label: String, startMonitor: Bool = true
    ) {
        // 普通入口负责确保监视器存在；监视器自己的心跳不能把自己的
        // generation 递增，否则它永远无法在真正空闲时停下来。
        if startMonitor { startRoomAssignmentRetryMonitor() }
        do {
            let report = try db.retryPendingSpaceAssignments()
            if !report.isEmpty {
                Service.log("[spaces] \(label)重放待重试归属：试 \(report.retried)，"
                      + "成 \(report.succeeded)，源已失效丢弃 \(report.staleDiscarded)，"
                      + "仍失败 \(report.stillPending)，没到时间 \(report.deferred)，"
                      + "已放弃 \(report.abandoned)")
            }
            if report.abandoned > 0 {
                Service.log("[spaces] ⚠️ \(report.abandoned) 轮归属已达重试上限，不再自动重试；"
                      + "设置页「重放」可重新武装", level: .warning)
            }
        } catch {
            Service.log("[spaces] \(label)重放待重试归属失败：\(error)", level: .error)
        }
    }

    /// 监视器的一次心跳：还有没放弃的欠账就去重放一次；**重放完没有可再试的
    /// 欠账就停表**——队列清空（或只剩已放弃的行）之后，没有理由留一个每 30
    /// 秒空转的表。下一次有欠账会由启动、摘要写入或设置页「重放」重新把它起来。
    private static func stopRetryMonitorIfStillIdle(generation: UInt64) {
        retryMonitorIdleStopHookForTesting?()
        roomAssignmentRetryTimer.stop(ifGeneration: generation)
    }

    private static func runScheduledRoomAssignmentRetry() {
        let generation = roomAssignmentRetryTimer.generationSnapshot()
        do {
            let db = try ESISDatabase(
                url: ManagedPaths.databaseURL, createIfNeeded: true)
            defer { db.close() }
            let status = try db.spaceAssignmentRetryStatus()
            guard status.pending > status.abandoned else {
                stopRetryMonitorIfStillIdle(generation: generation)
                return
            }
            replayPendingAssignments(db, label: "定时", startMonitor: false)
            let after = try db.spaceAssignmentRetryStatus()
            if after.pending <= after.abandoned {
                stopRetryMonitorIfStillIdle(generation: generation)
            }
        } catch {
            Service.log("[spaces] 定时重试检查失败：\(error)", level: .error)
        }
    }

    /// 等一个干净的空窗：没人跑、没人等，并且安静满 1.5 秒。
    /// 不设上限——排队本身是常态，等到就是等到；进程退出时随 Task 一起走。
    /// 返回 false 只有两种：任务被取消，或者人按了停止。
    private static func waitForIdle(_ stop: DigestStop?) async -> Bool {
        var quietSince: Date?
        let quietPeriod = max(0, idleQuietPeriodForTesting ?? 1.5)
        while !Task.isCancelled {
            if stop?.isCancelled == true { return false }
            let live = admissionLiveness()
            if live.active == 0 && live.waiting == 0 {
                if quietPeriod == 0 { return true }
                if let since = quietSince {
                    if Date().timeIntervalSince(since) >= quietPeriod { return true }
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
                    let live = admissionLiveness()
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
    /// All generation entry points share one FIFO async admission point. In the old
    /// design drain and fillMissing could both observe idle, submit at once, see
    /// active > 1, and cancel themselves in sync. The gate removes background
    /// self-contention before either client starts polling admission liveness.
    private static func generate<T: Sendable>(
        _ prompt: String,
        stop: DigestStop?,
        undigestedTurn: (sessionID: String, turnIndex: Int)? = nil,
        onYield: @escaping @Sendable () -> Void = {},
        consume: @escaping @Sendable (String?) throws -> T
    ) async throws -> T {
        try await generationGate.withPermit {
            if Task.isCancelled || stop?.isCancelled == true { throw Digestion.stopped }
            if let turn = undigestedTurn {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                if try db.turnDigest(sessionID: turn.sessionID, turnIndex: turn.turnIndex) != nil {
                    return try consume(nil)
                }
            }
            let raw = try await generateWhileAdmitted(prompt, stop: stop, onYield: onYield)
            // Re-check after the idle wait: the warm path (Q2) writes while the
            // chat handler still holds the permit, so a job that passed the
            // pre-wait check may find its digest already written by the time
            // the engine is free. Skip the duplicate generation; the consume
            // closure treats nil as "already settled".
            if let turn = undigestedTurn {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                if try db.turnDigest(sessionID: turn.sessionID, turnIndex: turn.turnIndex) != nil {
                    return try consume(nil)
                }
            }
            // Keep the admission permit until parsing and the durable IS write finish.
            // Otherwise the next waiter could observe the row before its commit and
            // issue a duplicate generation for the same turn.
            return try consume(raw)
        }
    }

    private static func generateWhileAdmitted(
        _ prompt: String,
        stop: DigestStop?,
        onYield: @escaping @Sendable () -> Void
    ) async throws -> String {
        while true {
            if Task.isCancelled || stop?.isCancelled == true { throw Digestion.stopped }
            guard await waitForIdle(stop) else { throw Digestion.stopped }
            if stop?.isCancelled == true { throw Digestion.stopped }
            do {
                return try await completeYielding(prompt, stop: stop)
            } catch Digestion.yielded {
                onYield()
                // Avoid synchronizing retries with a periodic external request stream.
                let retryDelay = Double.random(in: 1.2...2.1)
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
    }

    /// 把「轮号有、摘要没有」的全部补齐。一次一轮、串行——本地模型本来
    /// 也是串行处理的，并发只会把预填挤在一起。
    ///
    /// 每补完一轮就回报一次，调用方据此更新进度；补不上的留在缺口里，并且
    /// 每一轮的失败原因都进回执（#189）：格式、HTTP、写库各有各的名字，
    /// 让位与停止不计入失败、单独报数。
    /// 一次修复步骤的账目结论。生成/解析/写库与各自的 outcome 枚举留在调用方
    /// 闭包里；循环骨架（计数、deferredKeys、重排、停止、进度、回执）在这里。
    private enum RepairStep {
        /// 这轮补上了（written / alreadySettled）。
        case done
        /// 失败，只记账。
        case failed(reason: String)
        /// 失败且不再重试：出队留缺口（deferredKeys）。
        case failedFinal(reason: String)
        /// 失败且当前版本重新排队（staleSource：正文已更正）。
        case failedRequeue(
            reason: String, requeue: (sessionID: String, turnIndex: Int))
    }

    /// 两个修复循环共用的骨架：逐项——停止检查、一次共享准入区间内的
    /// generate（解析与写库由调用方闭包完成）、账目结论落账、停止异常、
    /// 普通失败（可按需 deferredKeys）、进度回报——以及同一份回执装配。
    /// 差异全部在 `step`：pending 是什么、prompt 是什么、outcome 枚举是
    /// 什么，都不在这里复制第二份。
    private static func repairLoop<Item>(
        _ items: [Item],
        key: (Item) -> String,
        stop: DigestStop?,
        deferOnNonRetryable: Bool,
        logLabel: @Sendable (Item) -> String,
        progress: @escaping @Sendable (Int, Int) -> Void,
        step: (Item, YieldCounter) async throws -> RepairStep
    ) async -> DigestRepairReceipt {
        var done = 0, failed = 0
        var failures: [DigestRepairReceipt.Failure] = []
        var stoppedAt: String?
        let yieldBox = YieldCounter()
        for (index, item) in items.enumerated() {
            if stop?.isCancelled == true {
                stoppedAt = key(item)
                break
            }
            do {
                switch try await step(item, yieldBox) {
                case .done:
                    done += 1
                case .failed(let reason):
                    failed += 1
                    failures.append(DigestRepairReceipt.Failure(
                        key: key(item), reason: reason))
                case .failedFinal(let reason):
                    failed += 1
                    failures.append(DigestRepairReceipt.Failure(
                        key: key(item), reason: reason))
                    state.sync { deferredKeys.insert(key(item)) }
                case .failedRequeue(let reason, let requeue):
                    failed += 1
                    enqueueLatestUndigestedTurn(
                        sessionID: requeue.sessionID, turnIndex: requeue.turnIndex)
                    failures.append(DigestRepairReceipt.Failure(
                        key: key(item), reason: reason))
                }
            } catch Digestion.stopped {
                stoppedAt = key(item)
                break
            } catch {
                failed += 1
                failures.append(DigestRepairReceipt.Failure(
                    key: key(item),
                    reason: DigestRepairReceipt.FailureReason.describe(error)))
                if deferOnNonRetryable, !isRetryable(error) {
                    state.sync { deferredKeys.insert(key(item)) }
                }
                Service.log(
                    "[digest] \(logLabel(item))失败：\(error)", level: .error)
            }
            progress(index + 1, items.count)
        }
        return DigestRepairReceipt(
            done: done, failed: failed, failures: failures,
            yielded: yieldBox.value, stoppedAt: stoppedAt)
    }

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
            Service.log("[digest] 读缺口失败：\(error)", level: .error)
            return .empty
        }
        if let limit, limit < pending.count { pending = Array(pending.prefix(limit)) }
        return await repairLoop(
            pending, key: { $0.key }, stop: stop, deferOnNonRetryable: true,
            logLabel: { "\($0.sessionID)#\($0.turnIndex) " }, progress: progress
        ) { turn, yieldBox in
            // 生成、解析和写库在同一个共享准入区间内完成。
            let outcome: BackfillOutcome = try await generate(
                TurnDigestText.prompt(
                    question: turn.question, answer: turn.answer,
                    background: briefBackground()),
                stop: stop,
                undigestedTurn: (sessionID: turn.sessionID, turnIndex: turn.turnIndex),
                onYield: { yieldBox.inc() }
            ) { raw in
                guard let raw else { return .alreadySettled }
                guard let parsed = TurnDigestText.parse(raw) else { return .badFormat }
                do {
                    let db = try ESISDatabase(
                        url: ManagedPaths.databaseURL, createIfNeeded: true)
                    defer { db.close() }
                    try db.recordTurnDigest(
                        sessionID: turn.sessionID, turnIndex: turn.turnIndex,
                        questionMessageID: turn.questionMessageID,
                        answerMessageID: turn.answerMessageID,
                        digest: parsed.digest,
                        keywords: parsed.keywords.joined(separator: " "),
                        model: "local:\(model)",
                        expectedQuestionSHA256: TurnDigestText.sourceSHA256(turn.question),
                        expectedAnswerSHA256: TurnDigestText.sourceSHA256(turn.answer))
                    return .written
                } catch let error as ESISDatabase.DatabaseError {
                    if case .staleTurnDigestSource = error { return .staleSource }
                    return .writeFailed(String(describing: error))
                } catch {
                    return .writeFailed(String(describing: error))
                }
            }
            switch outcome {
            case .alreadySettled, .written:
                return .done
            case .badFormat:
                return .failedFinal(
                    reason: DigestRepairReceipt.FailureReason.badFormat)
            case .staleSource:
                return .failedRequeue(
                    reason: "源正文已更正；旧摘要未提交，当前版本已重新排队",
                    requeue: (sessionID: turn.sessionID, turnIndex: turn.turnIndex))
            case .writeFailed(let detail):
                // 生成成功但持久化失败：明确归类，不借用 HTTP 错误名。
                Service.log(
                    "[digest] \(turn.sessionID)#\(turn.turnIndex) 写库失败：\(detail)",
                    level: .error)
                return .failed(reason: "写库：\(detail)")
            }
        }
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
            Service.log("[digest] 读缺词轮次失败：\(error)", level: .error)
            return .empty
        }
        return await repairLoop(
            pending, key: { $0.key }, stop: stop, deferOnNonRetryable: false,
            logLabel: { "修词 \($0.sessionID)#\($0.turnIndex) " }, progress: progress
        ) { turn, yieldBox in
            // 解析、合并与写词也在同一准入区间完成，避免修词入口彼此重叠。
            let outcome: KeywordRepairOutcome = try await generate(
                TurnDigestText.keywordPrompt(
                    question: turn.question, answer: turn.answer),
                stop: stop,
                onYield: { yieldBox.inc() }
            ) { raw in
                guard let raw,
                      let fresh = TurnDigestText.parseKeywords(raw) else {
                    return .badFormat
                }
                let merged = TurnDigestText.mergeKeywords(turn.keywords, fresh)
                guard merged.count > turn.keywords.count else { return .noNewWords }
                do {
                    let db = try ESISDatabase(
                        url: ManagedPaths.databaseURL, createIfNeeded: true)
                    defer { db.close() }
                    try db.replaceTurnKeywords(
                        sessionID: turn.sessionID, turnIndex: turn.turnIndex,
                        keywords: merged)
                    return .written
                } catch {
                    return .writeFailed(String(describing: error))
                }
            }
            switch outcome {
            case .written:
                return .done
            case .badFormat:
                return .failed(reason: DigestRepairReceipt.FailureReason.badFormat)
            case .noNewWords:
                return .failed(reason: "模型没补出新词")
            case .writeFailed(let detail):
                Service.log(
                    "[digest] 修词 \(turn.sessionID)#\(turn.turnIndex) 写库失败：\(detail)",
                    level: .error)
                return .failed(reason: "写库：\(detail)")
            }
        }
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
                replayPendingAssignments(db, label: "启动时")
            } catch {
                Service.log("[spaces] 启动重放失败：\(error)", level: .error)
            }
        }
    }

    /// 启动时把「轮号有、摘要没有」的轮次重新排进队列。
    ///
    /// `pending` 只在内存里：进程退出，队里没做完的那几轮就没了。但缺口是库里
    /// 的账（`undigestedTurns()` 读的就是它），所以重启照账重建待办，不靠人点
    /// 「开始」。模型这时可能还没起——这一轮会暂时失败、留在队里，等下一次
    /// 写入触发，这正是 R11 要的行为。
    static func replayPendingDigestsAtLaunch() {
        Task.detached(priority: .utility) {
            do {
                let db = try ESISDatabase(url: ManagedPaths.databaseURL,
                                          createIfNeeded: true)
                defer { db.close() }
                let gaps = try db.undigestedTurns()
                guard !gaps.isEmpty else { return }
                Service.log("[digest] 启动重建恢复 \(gaps.count) 轮缺口；先装入有界批次，其余由账本续取")
                for turn in gaps.prefix(maxPending) {
                    schedule(sessionID: turn.sessionID, turnIndex: turn.turnIndex,
                             question: turn.question, answer: turn.answer)
                }
            } catch {
                Service.log("[digest] 启动重建待办失败：\(error)", level: .error)
            }
        }
    }

    /// 启动时补一次轮账与时间。这两步不吃模型——它们只是把库里已经有的东西
    /// 对齐，所以不该等人点「开始」：缺的时间轮是每次打开都看得见的那一格。
    /// 摘要与关键词要模型，仍留在补录里（人点了才开始）。
    static func backfillSourceTimesAtLaunch() {
        Task.detached(priority: .utility) {
            do {
                let db = try ESISDatabase(url: ManagedPaths.databaseURL,
                                          createIfNeeded: true)
                defer { db.close() }
                try db.runMigrations()
                let export = SourceTimeExport.directory
                let ledger = try db.backfillImportedTurnLedger()
                let report = try db.backfillSourceTimes(
                    deepseekJSON: export.flatMap(SourceTimeExport.deepseekFile),
                    aistudioDirectories: export.map(SourceTimeExport.subdirectories) ?? [])
                Service.log(
                    "[time] 启动补时间：轮账补 \(ledger.turnsInserted) 轮，"
                        + "时间命中 \(report.updated) 轮，缺 \(report.missing) 轮")
            } catch {
                Service.log("[time] 启动补时间失败：\(error)", level: .error)
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
            // ② 防关键词退化（owner 2026-11-23）：coder 模型做摘要时关键词行
            // 重复循环填满 600 token、耗尽预算致缺标签 badFormat。repeat_penalty
            // 抑制重复（服务端解析 repeat_penalty→config.repeatPenalty→引擎
            // repetitionPenalty）。1.15 较短结构化输出的平衡值。
            "repeat_penalty": 1.15,
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
