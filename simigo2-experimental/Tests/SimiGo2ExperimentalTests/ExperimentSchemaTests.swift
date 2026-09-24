import XCTest
@testable import SimiGo2Experimental

final class ExperimentSchemaTests: XCTestCase {
    func testObservationRoundTrip() throws {
        let manifest = LayerDemandExperimentManifest(
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
                ExperimentGroup(
                    id: "SWITCH_MLP_L00_15",
                    layerStart: 0,
                    layerEnd: 15,
                    byteCount: 123,
                    alwaysResident: false
                )
            ],
            createdAt: "2026-01-01T00:00:00Z"
        )
        let sample = LayerDemandSample(
            experimentID: "pilot-001",
            sampleID: "CODE-001",
            category: "CODE",
            taskForm: "generation",
            lengthBucket: "medium",
            promptHash: "hash",
            promptText: "test"
        )
        let observation = LayerDemandObservation(
            experimentID: "pilot-001",
            sampleID: "CODE-001",
            groupID: "SWITCH_MLP_L00_15",
            evidenceKind: .ablation,
            baselineMetric: 1,
            interventionMetric: 0.5,
            demandMetric: 0.5,
            runtimeMilliseconds: 10,
            restored: true,
            timestamp: "2026-01-01T00:00:01Z"
        )
        let record = LayerDemandRunRecord(
            manifest: manifest,
            samples: [sample],
            observations: [observation]
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(LayerDemandRunRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    func testJSONLProducesOneObjectPerLine() throws {
        let samples = [
            LayerDemandSample(
                experimentID: "pilot",
                sampleID: "A",
                category: "GENERAL",
                taskForm: "question",
                lengthBucket: "short",
                promptHash: "a",
                promptText: "a"
            ),
            LayerDemandSample(
                experimentID: "pilot",
                sampleID: "B",
                category: "MATH",
                taskForm: "calculation",
                lengthBucket: "short",
                promptHash: "b",
                promptText: "b"
            )
        ]
        let data = try LayerDemandJSONL.encode(samples)
        XCTAssertEqual(data.split(separator: 0x0A).count, 2)
    }
}
