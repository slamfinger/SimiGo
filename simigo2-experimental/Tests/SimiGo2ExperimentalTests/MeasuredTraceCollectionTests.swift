import XCTest
@testable import SimiGo2Experimental

final class MeasuredTraceCollectionTests: XCTestCase {
    func testOperationPromptCoverageMatchesCatalog() throws {
        // Every registered workload step must have a scenario prompt, and
        // every prompt entry must belong to a registered trace operation.
        try MeasuredTraceCollection.validatePromptCoverage()

        for trace in WorkloadTraceCatalog.traces {
            let prompts = try XCTUnwrap(MeasuredTraceCollection.operationPrompts[trace.id])
            for step in trace.steps {
                let prompt = try XCTUnwrap(prompts[step.operation])
                XCTAssertFalse(prompt.isEmpty)
            }
        }

        XCTAssertEqual(MeasuredTraceCollection.operationPrompts.count, 4)
    }

    func testProtocolAndControlAreRegistered() {
        XCTAssertEqual(MeasuredTraceCollection.protocolVersion, "G1.9-C.COLLECT.V1")
        XCTAssertEqual(MeasuredTraceCollection.controlPrompt, "Return exactly one word: ping")
    }

    func testStepRecordKeepsDeclaredAndMeasuredLinesSeparate() throws {
        // The declared line (scenario groups) and the measured line (observed
        // groups) live in distinct fields; no field asserts their equality or
        // merges them into a demand claim.
        let declared = ["SWITCH_MLP_L00_15"]
        let measured = ["SWITCH_MLP_L00_15", "SWITCH_MLP_L16_31", "SWITCH_MLP_L32_47"]
        let record = MeasuredStepRecord(
            traceID: "T1_DOCUMENT_SESSION",
            stepIndex: 1,
            operation: "SUMMARIZE_DOCUMENT",
            executionState: "STATE_AB",
            prompt: "p",
            declaredOptionalGroupIDs: declared,
            measuredGroupIDs: measured,
            measuredGroupEventCounts: [:],
            passCount: 3,
            eventCount: 144,
            generatedTokenCount: 3,
            generationMilliseconds: 10
        )
        let data = try JSONEncoder().encode(record)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("declaredOptionalGroupIDs"))
        XCTAssertTrue(json.contains("measuredGroupIDs"))
        XCTAssertFalse(json.contains("\"demand\""))
        XCTAssertFalse(json.contains("\"priority\""))
        XCTAssertFalse(json.contains("\"probability\""))
        // divergence is representable but never collapsed
        XCTAssertNotEqual(record.declaredOptionalGroupIDs, record.measuredGroupIDs)
    }
}
