import MLX
import XCTest

@testable import SimiGo

/// MLX reports errors through a process-wide handler whose default body is
/// `fatalError`. That is how a Metal library build failure turned into "the app
/// quits when I send a message" on 2026-11-09: nothing in the process claimed
/// the error, so the default handler ended it.
///
/// These tests pin the contract `MLXErrorBoundary` exists for: the fault becomes
/// a Swift error that a turn can fail on, not a process exit.
final class MLXErrorBoundaryTests: XCTestCase {

    /// Deliberately raises one MLX error (a broadcast mismatch) inside the
    /// boundary. MLX state after a fault is not promised to be reusable, so this
    /// test stays last in spirit: it asserts propagation only.
    func testMLXFailureSurfacesAsThrownError() async {
        do {
            _ = try await MLXErrorBoundary.run {
                let a = MLXArray(0 ..< 10, [2, 5])
                let b = MLXArray(0 ..< 15, [3, 5])
                return a + b
            }
            XCTFail("the broadcast error should have been thrown")
        } catch {
            let message = String(describing: error).lowercased()
            XCTAssertTrue(
                message.contains("broadcast") || message.contains("shape"),
                "unexpected error text: \(error)")
        }
    }

    /// The boundary must not change results on the happy path.
    func testResultPassesThroughUnchanged() async throws {
        let sum = try await MLXErrorBoundary.run {
            MLXArray([1, 2, 3, 4]).sum()
        }
        XCTAssertEqual(sum.item(Float.self), 10)
    }
}
