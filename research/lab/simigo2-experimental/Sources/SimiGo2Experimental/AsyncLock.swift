import Foundation

/// Minimal async lock for the controller's admission serialization (R3.18).
/// FIFO hand-off preserves admission order; the lock is held across awaits
/// (an admission runs to completion or failure as a whole — R2.2).
public final class AsyncLock: @unchecked Sendable {
    private let mutex = NSLock()
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func lock() async {
        let shouldWait = mutex.withLock { () -> Bool in
            if locked {
                return true
            }
            locked = true
            return false
        }
        guard shouldWait else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let lockBecameFree = mutex.withLock { () -> Bool in
                if !locked {
                    // The holder unlocked between our check and this
                    // registration: take the lock directly.
                    locked = true
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if lockBecameFree {
                continuation.resume()
            }
        }
        // Resumption is a lock hand-off: this task now holds the lock.
    }

    public func unlock() {
        let resumed: CheckedContinuation<Void, Never>? = mutex.withLock {
            if let next = waiters.first {
                waiters.removeFirst()
                return next
            }
            locked = false
            return nil
        }
        // Resume outside the mutex: the woken task acquires by hand-off.
        resumed?.resume()
    }
}
