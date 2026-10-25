import XCTest
@testable import SimiGo2Experimental

final class WorkloadTraceTests: XCTestCase {
    /// Same group geometry as the Qwen3-Coder catalog: one core group and
    /// three equal-size optional groups; total 400 bytes.
    private func inventory() -> LayerInventory {
        LayerInventory(
            groups: [
                LayerGroup(id: "CORE_NON_SWITCH", title: "Core", layerRangeDescription: "core", tensorCount: 1, byteCount: 100, alwaysResident: true),
                LayerGroup(id: "SWITCH_MLP_L00_15", title: "A", layerRangeDescription: "0-15", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "SWITCH_MLP_L16_31", title: "B", layerRangeDescription: "16-31", tensorCount: 1, byteCount: 100),
                LayerGroup(id: "SWITCH_MLP_L32_47", title: "C", layerRangeDescription: "32-47", tensorCount: 1, byteCount: 100)
            ],
            tensors: [],
            totalByteCount: 400
        )
    }

    private func trace(
        _ id: String,
        _ states: [ExecutionStateLabel]
    ) -> WorkloadTrace {
        WorkloadTrace(
            id: id,
            kind: "TEST",
            summary: "test trace",
            steps: states.enumerated().map { index, state in
                WorkloadTraceStep(
                    operation: "OP_\(index)",
                    executionState: state,
                    mappingReason: "declared test mapping"
                )
            }
        )
    }

    func testCatalogHasFourTracesWithDeclaredMappings() throws {
        XCTAssertEqual(WorkloadTraceCatalog.traces.count, 4)
        XCTAssertEqual(Set(WorkloadTraceCatalog.traces.map(\.id)).count, 4)

        for trace in WorkloadTraceCatalog.traces {
            XCTAssertFalse(trace.steps.isEmpty)
            XCTAssertFalse(trace.summary.isEmpty)
            for step in trace.steps {
                XCTAssertFalse(step.operation.isEmpty)
                XCTAssertFalse(step.mappingReason.isEmpty)
            }
        }

        XCTAssertEqual(try WorkloadTraceCatalog.named("T3_AGENTIC_MULTI_TURN").steps.count, 9)
        XCTAssertThrowsError(try WorkloadTraceCatalog.named("NO_SUCH_TRACE"))
    }

    func testReplayRecordsHitOnRepeatedState() throws {
        let repeated = trace("REP_A", [.stateA, .stateA, .stateA])
        let report = try WorkloadTraceReplay.run(
            inventory: inventory(),
            traces: [repeated],
            budgetPercents: [100]
        )

        let run = try XCTUnwrap(report.runs.first)
        XCTAssertEqual(run.traceID, "REP_A")
        XCTAssertEqual(run.budgetPercent, 100)

        // Step 0 misses A (cold start) and loads every optional group because
        // the 100% budget retains them; steps 1 and 2 fully hit.
        XCTAssertEqual(run.stepRecords[0].requiredMissBytes, 100)
        XCTAssertEqual(run.stepRecords[0].requiredHitBytes, 100)
        XCTAssertEqual(run.stepRecords[0].loadedBytes, 300)
        XCTAssertEqual(run.stepRecords[1].requiredMissBytes, 0)
        XCTAssertEqual(run.stepRecords[1].requiredHitBytes, 200)
        XCTAssertEqual(run.stepRecords[2].requiredMissBytes, 0)

        XCTAssertEqual(run.requiredMissBytesTotal, 100)
        XCTAssertEqual(run.zeroRetentionMissBytesTotal, 300)
        XCTAssertEqual(run.reloadReductionVsZeroRetentionBytes, 200)
        XCTAssertEqual(
            run.optionalGroupLoadCounts,
            [
                "SWITCH_MLP_L00_15": 1,
                "SWITCH_MLP_L16_31": 1,
                "SWITCH_MLP_L32_47": 1
            ]
        )
        XCTAssertEqual(run.overflowStepCount, 0)
    }

    func testRecencyHintRetainsRecentlyUsedGroupUnderBudgetPressure() throws {
        // core(100) + required B(100) = 200; 75% of 400 = 300 leaves room for
        // exactly one optional group. The prior step used A, so A must win the
        // slot over C (baseline priority).
        let alternating = trace("ALT", [.stateA, .stateB])
        let report = try WorkloadTraceReplay.run(
            inventory: inventory(),
            traces: [alternating],
            budgetPercents: [75]
        )

        let run = try XCTUnwrap(report.runs.first)
        let second = run.stepRecords[1]
        XCTAssertEqual(second.executionState, .stateB)
        XCTAssertTrue(
            second.residentAfterGroupIDs.contains("SWITCH_MLP_L00_15"),
            "recently used group A should be retained by the recency hint"
        )
        XCTAssertFalse(
            second.residentAfterGroupIDs.contains("SWITCH_MLP_L32_47"),
            "never-used group C should not be retained over A"
        )
        // A was retained and B was already required-resident, so step 1
        // neither loads nor evicts.
        XCTAssertEqual(second.loadedBytes, 0)
        XCTAssertEqual(second.evictedBytes, 0)
        XCTAssertEqual(second.requiredMissBytes, 0)
    }

    func testOverflowIsRecordedPerStepAtLowBudget() throws {
        let report = try WorkloadTraceReplay.run(
            inventory: inventory(),
            traces: [try WorkloadTraceCatalog.named("T4_LONG_CONTEXT")],
            budgetPercents: [10]
        )

        let run = try XCTUnwrap(report.runs.first)
        XCTAssertEqual(run.stepCount, 5)
        XCTAssertEqual(run.overflowStepCount, 5)
        XCTAssertTrue(run.stepRecords.allSatisfy(\.overflow))
        // Mandatory sets are still planned even when they overflow.
        let contextLoad = run.stepRecords[0]
        XCTAssertEqual(contextLoad.requiredGroupIDs.count, 4)
    }

    func testReplayRunsOneRunPerTraceAndBudget() throws {
        let report = try WorkloadTraceReplay.run(
            inventory: inventory(),
            traces: nil,
            budgetPercents: [40, 100]
        )

        XCTAssertEqual(report.runs.count, 8)
        XCTAssertTrue(report.boundary.contains("NOT_PREDICTION"))
        XCTAssertTrue(report.boundary.contains("DECLARED_TRACE_STATE_MAPPING"))
        XCTAssertEqual(Set(report.runs.map(\.traceID)).count, 4)

        for run in report.runs {
            XCTAssertEqual(run.stepRecords.count, run.stepCount)
            XCTAssertEqual(run.stepRecords.map(\.stepIndex), Array(0..<run.stepCount))
        }

        // T3 ends with STATE_ALL: at 40% (160 bytes) core+ALL = 400 overflows,
        // at 100% it fits exactly.
        let t3 = report.runs.filter { $0.traceID == "T3_AGENTIC_MULTI_TURN" }
        XCTAssertEqual(t3.map(\.budgetPercent), [40, 100])
        XCTAssertEqual(t3.map(\.overflowStepCount), [9, 0])
    }

    func testExplicitPolicyMatchesDefaultOnQwenGeometry() throws {
        // The contiguous policy must reproduce the default Qwen3CoderStatePolicy
        // mapping on the Qwen group geometry, so model-aware replay is a
        // non-regression for the registered simulator results.
        let defaultReport = try WorkloadTraceReplay.run(
            inventory: inventory(),
            traces: nil,
            budgetPercents: [70]
        )
        let contiguousReport = try WorkloadTraceReplay.run(
            inventory: inventory(),
            traces: nil,
            budgetPercents: [70],
            policy: ContiguousLayerStatePolicy(inventory: inventory())
        )

        XCTAssertEqual(defaultReport.runs.count, contiguousReport.runs.count)
        for (a, b) in zip(defaultReport.runs, contiguousReport.runs) {
            XCTAssertEqual(a, b)
        }
    }

    func testHintsAreBuiltFromPriorStepsOnly() {
        let policy = Qwen3CoderStatePolicy(inventory: inventory())
        let optional = Set(["SWITCH_MLP_L00_15", "SWITCH_MLP_L16_31", "SWITCH_MLP_L32_47"])

        let empty = WorkloadTraceReplay.recencyHints(
            priorStates: [], policy: policy, optionalGroupIDs: optional
        )
        XCTAssertTrue(empty.allSatisfy { $0.priority == 0.1 })

        let afterA = WorkloadTraceReplay.recencyHints(
            priorStates: [.stateA], policy: policy, optionalGroupIDs: optional
        )
        let byGroup = Dictionary(uniqueKeysWithValues: afterA.map { ($0.groupID, $0.priority) })
        XCTAssertEqual(byGroup["SWITCH_MLP_L00_15"], 1.0)
        XCTAssertEqual(byGroup["SWITCH_MLP_L16_31"], 0.1)
        XCTAssertEqual(byGroup["SWITCH_MLP_L32_47"], 0.1)
    }

    func testReplayRejectsInvalidBudgets() {
        XCTAssertThrowsError(
            try WorkloadTraceReplay.run(inventory: inventory(), budgetPercents: [])
        )
        XCTAssertThrowsError(
            try WorkloadTraceReplay.run(inventory: inventory(), budgetPercents: [0, 40])
        )
    }
}
