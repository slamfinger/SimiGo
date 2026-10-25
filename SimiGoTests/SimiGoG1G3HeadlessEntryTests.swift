import XCTest
@testable import SimiGo

/// Unit coverage for the G1/G3 controlled headless entry's fail-closed gating.
/// These exercise only the pure `evaluate(env:)` decision, NOT any model run.
final class SimiGoG1G3HeadlessEntryTests: XCTestCase {

    private let full: [String: String] = [
        "SIMIGO_HEADLESS_ROLE": "produce",
        "SIMIGO_EXPERIMENT_ROOT": "/tmp/x",
        "SIMIGO_RUN_ID": "r1",
        "SIMIGO_HEADLESS_MODEL_PATH": "/tmp/model",
        "SIMIGO_HEADLESS_TARGET_VALUE": "v1",
    ]

    func testAbsentRoleDoesNotEngageHeadless() {
        let d = SimiGoG1G3Entry.evaluate(env: [:])
        XCTAssertFalse(d.requested, "default GUI path must remain untouched")
        XCTAssertNil(d.role)
    }

    func testEmptyRoleStringDoesNotEngage() {
        let d = SimiGoG1G3Entry.evaluate(env: ["SIMIGO_HEADLESS_ROLE": ""])
        XCTAssertFalse(d.requested)
    }

    func testUnknownRoleFailsClosed() {
        var e = full; e["SIMIGO_HEADLESS_ROLE"] = "destroy"
        let d = SimiGoG1G3Entry.evaluate(env: e)
        XCTAssertTrue(d.requested)
        XCTAssertNil(d.role)
        XCTAssertNotNil(d.error)
    }

    func testMissingRequiredParamFailsClosed() {
        var e = full; e.removeValue(forKey: "SIMIGO_EXPERIMENT_ROOT")
        let d = SimiGoG1G3Entry.evaluate(env: e)
        XCTAssertTrue(d.requested); XCTAssertNil(d.role); XCTAssertNotNil(d.error)

        var c: [String: String] = [
            "SIMIGO_HEADLESS_ROLE": "consume", "SIMIGO_EXPERIMENT_ROOT": "/tmp/x",
            "SIMIGO_RUN_ID": "r1", "SIMIGO_HEADLESS_MODEL_PATH": "/tmp/model",
        ]
        let cd = SimiGoG1G3Entry.evaluate(env: c)   // consume without STATE_ID
        XCTAssertTrue(cd.requested); XCTAssertNil(cd.role); XCTAssertNotNil(cd.error)
        c["SIMIGO_HEADLESS_STATE_ID"] = "s1"
        let ok = SimiGoG1G3Entry.evaluate(env: c)
        XCTAssertEqual(ok.role, .consume); XCTAssertNil(ok.error)
    }

    func testValidProduceResolves() {
        let d = SimiGoG1G3Entry.evaluate(env: full)
        XCTAssertTrue(d.requested); XCTAssertEqual(d.role, .produce); XCTAssertNil(d.error)
    }

    /// The G1.9-A trace role drives the shipped `ExecutionTracePilot`, so it needs
    /// a model but no target value: it produces a report, not a settlement.
    func testTracepilotResolvesWithoutTargetValue() {
        var e = full; e["SIMIGO_HEADLESS_ROLE"] = "tracepilot"
        e.removeValue(forKey: "SIMIGO_HEADLESS_TARGET_VALUE")
        let d = SimiGoG1G3Entry.evaluate(env: e)
        XCTAssertTrue(d.requested); XCTAssertEqual(d.role, .tracepilot); XCTAssertNil(d.error)
    }

    /// ...but it must still fail closed before any model work when the model
    /// path is absent, exactly like every other role.
    func testTracepilotFailsClosedWithoutModelPath() {
        var e = full; e["SIMIGO_HEADLESS_ROLE"] = "tracepilot"
        e.removeValue(forKey: "SIMIGO_HEADLESS_MODEL_PATH")
        let d = SimiGoG1G3Entry.evaluate(env: e)
        XCTAssertTrue(d.requested); XCTAssertNil(d.role); XCTAssertNotNil(d.error)
    }
}
