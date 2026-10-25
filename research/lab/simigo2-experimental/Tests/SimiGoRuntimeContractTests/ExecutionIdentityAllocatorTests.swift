import XCTest
@testable import SimiGoRuntimeContract

final class ExecutionIdentityAllocatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("execution-identity-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRequestedReservationIsIdempotentAcrossRestart() throws {
        let first = try DurableExecutionIdentityAllocator(directory: root)
        let id = ExecutionID("session-A")
        XCTAssertEqual(try first.reserve(token: "create:A", requestedID: id), id)
        XCTAssertEqual(try first.reserve(token: "create:A", requestedID: id), id)
        XCTAssertTrue(first.hasReserved(id))

        XCTAssertThrowsError(
            try first.reserve(token: "fork:A:B", requestedID: id)
        ) { error in
            XCTAssertEqual(
                error as? ExecutionIdentityAllocatorError,
                .executionIDReserved(
                    token: "fork:A:B", requestedID: id, existingToken: "create:A"))
        }

        let restarted = try DurableExecutionIdentityAllocator(directory: root)
        XCTAssertEqual(try restarted.reserve(token: "create:A", requestedID: id), id)
        XCTAssertTrue(restarted.hasReserved(id))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".jsonl") }.count,
            1)
    }

    func testGeneratedReservationsRemainUniqueAcrossRestart() throws {
        let first = try DurableExecutionIdentityAllocator(directory: root)
        let a = try first.reserve(token: "create:A", requestedID: nil)
        let b = try first.reserve(token: "create:B", requestedID: nil)
        XCTAssertNotEqual(a, b)

        let restarted = try DurableExecutionIdentityAllocator(directory: root)
        XCTAssertEqual(try restarted.reserve(token: "create:A", requestedID: nil), a)
        XCTAssertEqual(try restarted.reserve(token: "create:B", requestedID: nil), b)
    }

    /// Two independently opened views model two processes that both
    /// initialized before either committed: neither in-memory map can see the
    /// other's reservation, so the ledger under the exclusive flock must
    /// arbitrate — exactly one reservation for the requested ID survives.
    func testStaleViewsArbitrateConflictingRequestedIDAgainstLedger() throws {
        let stale = try DurableExecutionIdentityAllocator(directory: root)
        let winner = try DurableExecutionIdentityAllocator(directory: root)
        let id = ExecutionID("race-A")
        XCTAssertEqual(try winner.reserve(token: "create:A", requestedID: id), id)
        XCTAssertThrowsError(
            try stale.reserve(token: "create:B", requestedID: id)
        ) { error in
            XCTAssertEqual(
                error as? ExecutionIdentityAllocatorError,
                .executionIDReserved(
                    token: "create:B", requestedID: id, existingToken: "create:A"))
        }
        // The losing view folded the committed ledger in before failing, so
        // it must now observe the reservation that beat it.
        XCTAssertTrue(stale.hasReserved(id))
        XCTAssertEqual(stale.reservationCount, 1)

        let replayed = try DurableExecutionIdentityAllocator(directory: root)
        XCTAssertEqual(replayed.reservationCount, 1)
        XCTAssertEqual(try replayed.reserve(token: "create:A", requestedID: id), id)
    }

    /// A view that opened before another process committed its reservation
    /// must recover the committed identity when it retries the same operation
    /// token — not allocate a second identity under that token.
    func testStaleViewTokenRetryReturnsCommittedIdentity() throws {
        let stale = try DurableExecutionIdentityAllocator(directory: root)
        let writer = try DurableExecutionIdentityAllocator(directory: root)
        let committed = try writer.reserve(token: "create:A", requestedID: nil)
        XCTAssertEqual(try stale.reserve(token: "create:A", requestedID: nil), committed)
        XCTAssertEqual(stale.reservationCount, 1)

        let replayed = try DurableExecutionIdentityAllocator(directory: root)
        XCTAssertEqual(replayed.reservationCount, 1)
        XCTAssertEqual(try replayed.reserve(token: "create:A", requestedID: nil), committed)
    }

    func testCorruptLedgerFailsClosed() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{not-json\n".utf8).write(
            to: root.appendingPathComponent("execution-ids.jsonl"))

        XCTAssertThrowsError(try DurableExecutionIdentityAllocator(directory: root)) {
            error in
            guard case .ledgerCorrupt(_, line: 1) = error as? ExecutionIdentityAllocatorError else {
                return XCTFail("unexpected allocator error: \(error)")
            }
        }
    }
}
