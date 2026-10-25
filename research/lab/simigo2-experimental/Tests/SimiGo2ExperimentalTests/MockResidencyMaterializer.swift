import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// Shared test infrastructure for residency controller verification
/// (L2 contract tests and L3 fault injection). Test-only: no production use.

final class MockResidencyMaterializer: ResidencyMaterializer, @unchecked Sendable {
    enum MockError: Error, Equatable {
        case io
    }

    var failLoadsOf: Set<String> = []
    var failReleasesOf: Set<String> = []
    private(set) var calls: [String] = []

    func materialize(groupID: String) throws {
        calls.append("load:\(groupID)")
        if failLoadsOf.contains(groupID) {
            throw MockError.io
        }
    }

    func release(groupID: String) throws {
        calls.append("release:\(groupID)")
        if failReleasesOf.contains(groupID) {
            throw MockError.io
        }
    }
}

/// Thread-safe counter for cancellation-token timing in tests.
final class CheckCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
