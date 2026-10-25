import XCTest
@testable import SimiGo2Experimental

final class LayerDemandExperimentRunnerTests: XCTestCase {
    private func manifest() -> LayerDemandExperimentManifest {
        LayerDemandExperimentManifest(
            experimentID: "pilot-001",
            datasetVersion: "v0.1",
            modelID: "qwen3-coder-30b-a3b",
            checkpointHash: "sha256:test",
            runtime: RuntimeMetadata(
                hardware: "Apple Silicon",
                os: "macOS",
                swiftVersion: "unknown",
                mlxVersion: "unknown"
            ),
            groups: [
                ExperimentGroup(id: "G0", layerStart: 0, layerEnd: 15, byteCount: 100, alwaysResident: false)
            ],
            createdAt: "2026-01-01T00:00:00Z"
        )
    }

    private func sample() -> LayerDemandSample {
        LayerDemandSample(
            experimentID: "pilot-001",
            sampleID: "S1",
            category: "CODE",
            taskForm: "generation",
            lengthBucket: "short",
            promptHash: "hash",
            promptText: "test"
        )
    }

    func testValidationAcceptsValidRecord() throws {
        let runner = LayerDemandExperimentRunner()
        XCTAssertNoThrow(try runner.validate(manifest: manifest(), samples: [sample()]))
    }

    func testValidationRejectsDuplicateSampleID() {
        let runner = LayerDemandExperimentRunner()
        XCTAssertThrowsError(try runner.validate(manifest: manifest(), samples: [sample(), sample()]))
    }

    func testObservationRequiresRestore() {
        let runner = LayerDemandExperimentRunner()
        let observation = LayerDemandObservation(
            experimentID: "pilot-001",
            sampleID: "S1",
            groupID: "G0",
            evidenceKind: .ablation,
            baselineMetric: 1,
            interventionMetric: 0.5,
            demandMetric: 0.5,
            runtimeMilliseconds: 10,
            restored: false,
            timestamp: "2026-01-01T00:00:01Z"
        )
        XCTAssertThrowsError(
            try runner.validateObservation(
                observation,
                manifest: manifest(),
                sampleIDs: ["S1"]
            )
        )
    }
}
