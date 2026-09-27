import XCTest
@testable import SimiGo2Experimental

final class MeasuredExecutionTracePilotTests: XCTestCase {
    /// One core group plus three optional groups covering layers 0-15,
    /// 16-31, 32-47 — the Qwen3-Coder geometry.
    private func inventory() -> LayerInventory {
        LayerInventory(
            groups: [
                LayerGroup(id: "CORE_NON_SWITCH", title: "Core", layerRangeDescription: "all", tensorCount: 1, byteCount: 100, alwaysResident: true),
                LayerGroup(id: "SWITCH_MLP_L00_15", title: "A", layerRangeDescription: "0-15", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "SWITCH_MLP_L16_31", title: "B", layerRangeDescription: "16-31", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "SWITCH_MLP_L32_47", title: "C", layerRangeDescription: "32-47", tensorCount: 1, byteCount: 100)
            ],
            tensors: [],
            totalByteCount: 400
        )
    }

    private func event(_ sequence: Int, _ layer: Int) -> ExecutionTraceEvent {
        ExecutionTraceEvent(
            kind: .layerEntered,
            sequence: sequence,
            modulePath: "model.layers.\(layer).mlp.switch_mlp.down_proj",
            decoderLayer: layer
        )
    }

    private func stream(layersPerPass: [Range<Int>], modulesPerPass: Int = 16) -> [ExecutionTraceEvent] {
        var events: [ExecutionTraceEvent] = []
        var sequence = 0
        for range in layersPerPass {
            for layer in range {
                sequence += 1
                events.append(event(sequence, layer))
            }
        }
        return events
    }

    func testGroupJoinMapsLayersToDeclaredGroups() {
        let inventory = inventory()
        XCTAssertEqual(ExecutionTracePilot.groupID(forLayer: 0, inventory: inventory), "SWITCH_MLP_L00_15")
        XCTAssertEqual(ExecutionTracePilot.groupID(forLayer: 15, inventory: inventory), "SWITCH_MLP_L00_15")
        XCTAssertEqual(ExecutionTracePilot.groupID(forLayer: 16, inventory: inventory), "SWITCH_MLP_L16_31")
        XCTAssertEqual(ExecutionTracePilot.groupID(forLayer: 47, inventory: inventory), "SWITCH_MLP_L32_47")
        // a 40-layer model: layer 39 still joins the L32_47 partition
        XCTAssertEqual(ExecutionTracePilot.groupID(forLayer: 39, inventory: inventory), "SWITCH_MLP_L32_47")
        XCTAssertNil(ExecutionTracePilot.groupID(forLayer: 60, inventory: inventory))
    }

    func testParseLayerRange() {
        XCTAssertEqual(ExecutionTracePilot.parseLayerRange("0-15"), 0...15)
        XCTAssertEqual(ExecutionTracePilot.parseLayerRange("32-47"), 32...47)
        XCTAssertNil(ExecutionTracePilot.parseLayerRange("all"))
        XCTAssertNil(ExecutionTracePilot.parseLayerRange("bad"))
    }

    func testMeasuredTraceSegmentsStepsAndCountsGroups() {
        // two passes over all 48 layers: 16 events per group per pass
        let events = stream(layersPerPass: [0..<48, 0..<48])
        let trace = ExecutionTracePilot.measuredTrace(
            traceID: "TRACE/P1/rep0",
            modelID: "model",
            events: events,
            inventory: inventory()
        )

        XCTAssertEqual(trace.events.count, 96)
        XCTAssertEqual(trace.steps.count, 2)
        XCTAssertEqual(trace.steps[0].stepID, 0)
        XCTAssertEqual(trace.steps[1].stepID, 1)

        for step in trace.steps {
            XCTAssertEqual(step.observedGroupOrder, [
                "SWITCH_MLP_L00_15", "SWITCH_MLP_L16_31", "SWITCH_MLP_L32_47",
            ])
            XCTAssertEqual(step.groupExecutionCounts, [
                "SWITCH_MLP_L00_15": 16, "SWITCH_MLP_L16_31": 16, "SWITCH_MLP_L32_47": 16,
            ])
            XCTAssertEqual(step.eventCount, 48)
        }
        XCTAssertEqual(trace.boundary.contains("NOT_DEMAND"), true)
    }

    func testMeasuredTraceIsPureObservationJoin() {
        // No field may assert demand: only layerEntered events and group
        // count bookkeeping. The boundary string states NOT_DEMAND, but no
        // demand/priority/probability field may exist.
        let events = stream(layersPerPass: [0..<4])
        let data = try! JSONEncoder().encode(
            ExecutionTracePilot.measuredTrace(
                traceID: "T", modelID: "M", events: events, inventory: inventory()
            )
        )
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("NOT_DEMAND"))
        XCTAssertFalse(json.contains("\"demand\""))
        XCTAssertFalse(json.contains("\"priority\""))
        XCTAssertFalse(json.contains("\"probability\""))
        XCTAssertFalse(json.contains("\"layerDemand\""))
    }

    func testPilotRejectsTooFewRepetitions() async {
        // The guard fires before any model access, so a nonexistent directory
        // proves the guard ordering.
        do {
            _ = try await ExecutionTracePilot.run(
                modelDirectory: URL(fileURLWithPath: "/nonexistent"),
                repetitions: 1
            )
            XCTFail("expected insufficientRepetitions error")
        } catch {
            // expected
        }
    }

    func testPromptSetIsRegisteredAndFixed() {
        XCTAssertEqual(ExecutionTracePilot.prompts.count, 3)
        XCTAssertEqual(ExecutionTracePilot.prompts.map(\.id), ["P1", "P2", "P3"])
        XCTAssertTrue(ExecutionTracePilot.prompts.allSatisfy { !$0.text.isEmpty })
    }
}
