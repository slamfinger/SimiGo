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
