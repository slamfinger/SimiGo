import XCTest

/// 并发测试共用助手（RuntimeLifecycleGate / PrefillScheduler / 集成测试）。
struct TestTimeout: Error {}

/// 有界等待：block 未在时限内完成即抛错，防止测试自身悬挂拖死整个套件。
func withTestTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TestTimeout()
        }

        guard let result = try await group.next() else {
            throw TestTimeout()
        }

        group.cancelAll()
        return result
    }
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
