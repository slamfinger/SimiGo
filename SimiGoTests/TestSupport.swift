import XCTest

/// 并发测试共用助手（RuntimeLifecycleGate / PrefillScheduler / 集成测试）。
struct TestTimeout: Error {}

/// operation 结果信箱：恰好投递一次（先到者生效），再唤醒等待者。
///
/// 用信箱而非直接 `await operationTask.value`，是为了让「operation 收敛」与
/// 「计时器到点」真正竞速：直接 await value 会一直挂到 operation 收敛为止，
/// 计时器永远没有机会触发，超时形同虚设。
private final class ResultMailbox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<T, Error>?
    let delivered = TestSignal()

    func deliver(_ result: Result<T, Error>) {
        lock.lock()
        let isFirst = (stored == nil)
        if isFirst { stored = result }
        lock.unlock()

        guard isFirst else { return }
        Task { await delivered.fire() }
    }

    func take() -> Result<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// 有界等待：operation 未在时限内完成即抛 TestTimeout，防止测试自身悬挂拖死整个套件。
///
/// 审计 ②：不能用 task group 竞速——group 离开作用域前会 join 全部 child task，
/// 若 operation 不响应 cancellation，`cancelAll()` 后 group 仍卡在 join 上；
/// 也不能直接轮询 `try? await operationTask.value`——await 会挂到收敛，且 `try?`
/// 会吞掉 operation 的真实错误（CancellationError 被误报成 TestTimeout）。
///
/// 这里改为非结构化竞速：operation 与计时器各自完成后向信箱投递（先到者生效），
/// wrapper 只等信箱唤醒。因此无论 operation 是否 cooperative，wrapper 都必然在
/// 时限内返回；operation 的真实结果/错误原样传播（含 CancellationError）。
/// 超时后 operation 被主动 cancel，若仍不收敛则作为僵尸 task 放弃——这是测试环境下
/// 「真实 timeout」的必要取舍。
func withTestTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let mailbox = ResultMailbox<T>()
    let nanoseconds = UInt64(seconds * 1_000_000_000)

    let operationTask = Task {
        do {
            mailbox.deliver(.success(try await operation()))
        } catch {
            mailbox.deliver(.failure(error))
        }
    }

    let timerTask = Task {
        try? await Task.sleep(nanoseconds: nanoseconds)
        operationTask.cancel()
        mailbox.deliver(.failure(TestTimeout()))
    }

    defer {
        timerTask.cancel()
        operationTask.cancel()
    }

    await mailbox.delivered.wait()

    guard let result = mailbox.take() else {
        throw TestTimeout()
    }
    return try result.get()
}

/// 跨并发上下文的握手信号：fire 记录状态（无等待者也不丢），wait 立即或挂起。
actor TestSignal {
    private var signaled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func fire() {
        signaled = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { self.continuation = $0 }
    }

    var fired: Bool { signaled }
}
