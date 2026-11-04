import XCTest

@testable import SimiGo

/// Route 04 request admission: levels 1/2/4 bound how many turns may be in
/// flight, while generation ordering stays with the runtime gate. These tests
/// pin the scheduler's own contract:
///
/// - capacity is exactly the configured level (1, 2, or 4),
/// - admission is FIFO once the level is saturated,
/// - the wait queue is bounded (saturation is refused, never unbounded),
/// - cancellation removes a waiter without leaking a slot,
/// - a ticket can be released once, by its owner only.
///
/// Isolation and settlement semantics under interleaving are covered by the
/// existing HTTP/DB suites; this file does not duplicate them.
final class RequestAdmissionSchedulerTests: XCTestCase {

    // MARK: - Helpers

    private func waitFor(
        _ scheduler: RequestAdmissionScheduler,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping (RequestAdmissionScheduler.Snapshot) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(await scheduler.debugSnapshot()) {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let last = await scheduler.debugSnapshot()
        XCTFail(
            "scheduler did not reach expected state; last=\(last)",
            file: file,
            line: line)
    }

    private func admitted(
        _ result: RequestAdmissionScheduler.AcquireResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> RequestAdmissionScheduler.Ticket? {
        guard case .admitted(let ticket) = result else {
            XCTFail("expected admitted, got \(result)", file: file, line: line)
            return nil
        }
        return ticket
    }

    // MARK: - Capacity per level

    func testLevelOneAdmitsExactlyOneUntilReleased() async throws {
        let scheduler = RequestAdmissionScheduler(limit: 1, queueCapacity: 8)
        guard let first = admitted(await scheduler.acquire(requestId: "a")) else { return }

        let second = Task { await scheduler.acquire(requestId: "b") }
        try await waitFor(scheduler) { $0.active == 1 && $0.waiting == 1 }

        scheduler.release(first)

        guard let secondTicket = admitted(await second.value) else { return }
        XCTAssertEqual(secondTicket.requestId, "b")
        let snapshot = await scheduler.debugSnapshot()
        XCTAssertEqual(snapshot.active, 1)
        XCTAssertEqual(snapshot.waiting, 0)
        scheduler.release(secondTicket)
    }

    func testLevelTwoAdmitsTwoAndQueuesTheThird() async throws {
        let scheduler = RequestAdmissionScheduler(limit: 2, queueCapacity: 8)

        guard let a = admitted(await scheduler.acquire(requestId: "a")),
              let b = admitted(await scheduler.acquire(requestId: "b")) else { return }

        let third = Task { await scheduler.acquire(requestId: "c") }
        try await waitFor(scheduler) { $0.active == 2 && $0.waiting == 1 }

        scheduler.release(a)
        guard let cTicket = admitted(await third.value) else { return }
        XCTAssertEqual(cTicket.requestId, "c")
        let snapshot = await scheduler.debugSnapshot()
        XCTAssertEqual(snapshot.active, 2)
        XCTAssertEqual(snapshot.waiting, 0)

        scheduler.release(b)
        scheduler.release(cTicket)
    }

    func testLevelFourAdmitsFourAndQueuesTheFifth() async throws {
        let scheduler = RequestAdmissionScheduler(limit: 4, queueCapacity: 16)

        var tickets: [RequestAdmissionScheduler.Ticket] = []
        for index in 0..<4 {
            guard let ticket = admitted(await scheduler.acquire(requestId: "r\(index)")) else { return }
            tickets.append(ticket)
        }

        let fifth = Task { await scheduler.acquire(requestId: "r4") }
        try await waitFor(scheduler) { $0.active == 4 && $0.waiting == 1 }

        scheduler.release(tickets[0])
        guard let fifthTicket = admitted(await fifth.value) else { return }
        XCTAssertEqual(fifthTicket.requestId, "r4")
        let snapshot = await scheduler.debugSnapshot()
        XCTAssertEqual(snapshot.active, 4)
        XCTAssertEqual(snapshot.waiting, 0)

        for ticket in tickets.dropFirst() {
            scheduler.release(ticket)
        }
        scheduler.release(fifthTicket)
    }

    // MARK: - FIFO

    func testQueuedRequestsAreGrantedInArrivalOrder() async throws {
        let scheduler = RequestAdmissionScheduler(limit: 1, queueCapacity: 4)
        guard let first = admitted(await scheduler.acquire(requestId: "first")) else { return }

        let second = Task { await scheduler.acquire(requestId: "second") }
        try await waitFor(scheduler) { $0.waiting == 1 }
        let third = Task { await scheduler.acquire(requestId: "third") }
        try await waitFor(scheduler) { $0.waiting == 2 }

        scheduler.release(first)
        guard let secondTicket = admitted(await second.value) else { return }
        XCTAssertEqual(secondTicket.requestId, "second")

        scheduler.release(secondTicket)
        guard let thirdTicket = admitted(await third.value) else { return }
        XCTAssertEqual(thirdTicket.requestId, "third")
        scheduler.release(thirdTicket)
    }

    // MARK: - Bounded queue

    func testQueueIsBoundedAndSaturationIsRefused() async throws {
        let scheduler = RequestAdmissionScheduler(limit: 1, queueCapacity: 2)
        guard let first = admitted(await scheduler.acquire(requestId: "first")) else { return }

        let second = Task { await scheduler.acquire(requestId: "second") }
        try await waitFor(scheduler) { $0.waiting == 1 }
        let third = Task { await scheduler.acquire(requestId: "third") }
        try await waitFor(scheduler) { $0.waiting == 2 }

        let overflow = await scheduler.acquire(requestId: "overflow")
        guard case .queueFull = overflow else {
            return XCTFail("expected queueFull, got \(overflow)")
        }

        second.cancel()
        third.cancel()
        _ = await second.value
        _ = await third.value
        scheduler.release(first)
        try await waitFor(scheduler) { $0.active == 0 && $0.waiting == 0 }
    }

    // MARK: - Cancellation

    func testCancellingAQueuedRequestDoesNotLeakASlot() async throws {
        let scheduler = RequestAdmissionScheduler(limit: 1, queueCapacity: 4)
        guard let first = admitted(await scheduler.acquire(requestId: "first")) else { return }

        let cancelled = Task { await scheduler.acquire(requestId: "cancelled") }
        try await waitFor(scheduler) { $0.waiting == 1 }

        cancelled.cancel()
        let cancelledResult = await cancelled.value
        guard case .cancelled = cancelledResult else {
            return XCTFail("expected cancelled, got \(cancelledResult)")
        }
        try await waitFor(scheduler) { $0.active == 1 && $0.waiting == 0 }

        scheduler.release(first)
        guard let next = admitted(await scheduler.acquire(requestId: "next")) else { return }
        scheduler.release(next)
    }

    // MARK: - Ownership

    func testReleaseIsOwnerOnlyAndIdempotent() async throws {
        let scheduler = RequestAdmissionScheduler(limit: 1, queueCapacity: 4)
        guard let first = admitted(await scheduler.acquire(requestId: "first")) else { return }
        scheduler.release(first)
        guard let second = admitted(await scheduler.acquire(requestId: "second")) else { return }

        // A stale release of the first ticket must not free the second slot.
        scheduler.release(first)
        let snapshot = await scheduler.debugSnapshot()
        XCTAssertEqual(snapshot.active, 1)

        let third = Task { await scheduler.acquire(requestId: "third") }
        try await waitFor(scheduler) { $0.waiting == 1 }

        // Duplicate release of the live owner is a no-op after the first one.
        scheduler.release(second)
        guard let thirdTicket = admitted(await third.value) else { return }
        scheduler.release(second)
        scheduler.release(thirdTicket)
    }

    // MARK: - Shutdown

    func testShutdownReleasesWaitersAsShuttingDown() async throws {
        let scheduler = RequestAdmissionScheduler(limit: 1, queueCapacity: 4)
        guard let first = admitted(await scheduler.acquire(requestId: "first")) else { return }

        let waiting = Task { await scheduler.acquire(requestId: "waiting") }
        try await waitFor(scheduler) { $0.waiting == 1 }

        scheduler.beginShutdown()

        let result = await waiting.value
        guard case .shuttingDown = result else {
            return XCTFail("expected shuttingDown, got \(result)")
        }

        let after = await scheduler.acquire(requestId: "after")
        guard case .shuttingDown = after else {
            return XCTFail("expected shuttingDown for new acquire, got \(after)")
        }

        scheduler.release(first)
    }

    // MARK: - Queue default is derived from the level

    func testDefaultQueueCapacityScalesWithLevel() async {
        for level in [1, 2, 4] {
            let scheduler = RequestAdmissionScheduler(limit: level)
            let snapshot = await scheduler.debugSnapshot()
            XCTAssertEqual(snapshot.capacity, level)
            XCTAssertEqual(snapshot.queueCapacity, max(4, level * 4))
        }
    }
}
