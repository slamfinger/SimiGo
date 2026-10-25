import XCTest
import SimiGoRuntimeContract
import SimiGo2Experimental

/// Pure unit coverage for `CarrierStorageIsolationEvaluator` — the value-only
/// isolation decision that gates whether a freshly adopted carrier may resume a
/// settled Execution State after the old carrier was retired (slice 1's backend
/// tombstone). It drives no runtime, no model and no G3 harness, so it is a
/// model-free regression of the fail-closed rule: shared confirmed storage is
/// refused, an unprovable isolation fails closed, and only a genuinely disjoint
/// (or empty-retired) handoff is accepted.
final class CarrierStorageIsolationEvaluatorTests: XCTestCase {
    func testNothingRetiredIsHonestlyIsolated() {
        // The recompute / no-KV carrier registered no observable mutable storage,
        // so nothing it could still alias — isolated, not a claimed verified
        // isolation over buffers we never saw.
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: [], adopting: []), .isolated)
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: [], adopting: ["x"]), .isolated)
    }

    func testRetiredHeldStorageButAdoptingShowsNoneIsUnproven() {
        // Retired held mutable storage; a new carrier that cannot show its own
        // observable ids cannot prove it is disjoint — fails closed, never "distinct".
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: ["x"], adopting: []), .unobservable)
    }

    func testDisjointConfirmedStorageIsIsolated() {
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: ["a"], adopting: ["b"]), .isolated)
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(retired: ["a", "c"], adopting: ["b"]), .isolated)
    }

    func testSharedConfirmedIdIsRefusedWithExactlyTheOverlap() {
        let shared = CarrierStorageIsolationEvaluator.evaluate(
            retired: ["a", "b"], adopting: ["b", "c"])
        XCTAssertEqual(shared, .shared(["b"]))

        let multiOverlap = CarrierStorageIsolationEvaluator.evaluate(
            retired: ["a", "b", "d"], adopting: ["b", "d", "c"])
        XCTAssertEqual(multiOverlap, .shared(["b", "d"]))
    }

    /// The evidence-carrying form is the only one that can express the honest
    /// third answer: a carrier whose KV could not be observed is UNPROVEN, never
    /// "isolated" from an empty set.
    func testUnobservableStorageIsNeverIsolated() {
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(
                retired: .unobservable("vendor exposes no buffer identity"),
                adopting: .observable(["a"])),
            .unobservable)
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(
                retired: .observable(["a"]),
                adopting: .unobservable("vendor exposes no buffer identity")),
            .unobservable)
        // Nothing observable was retired, so there is nothing to alias.
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(
                retired: .noneObserved,
                adopting: .unobservable("vendor exposes no buffer identity")),
            .isolated)
    }

    /// The evidence form keeps the two decidable answers unchanged.
    func testEvidenceFormKeepsSharedAndDisjointAnswers() {
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(
                retired: .observable(["a", "b"]), adopting: .observable(["b", "c"])),
            .shared(["b"]))
        XCTAssertEqual(
            CarrierStorageIsolationEvaluator.evaluate(
                retired: .observable(["a"]), adopting: .observable(["c"])),
            .isolated)
    }
}
