import MLX
import MLXNN
import XCTest
@testable import SimiGo2Experimental

final class InstrumentationIdentityProbeTests: XCTestCase {
    func testSupportedObservationPathsAreSortedAndLayerScoped() {
        let paths = InstrumentationIdentityProbe.supportedObservationPaths(
            model: ProbeInstrumentationModel(),
            layerIndices: [24, 0]
        )

        XCTAssertEqual(
            paths,
            [
                "model.layers.0.mlp.down_proj",
                "model.layers.24.mlp.down_proj",
            ]
        )
    }

    func testIdentityComparisonUsesChecksum() {
        let array = MLXArray([1, 2, 3])
        let value = InstrumentationCaptureValue(
            kind: .outputLogits,
            array: array
        )
        let comparison = InstrumentationIdentityProbe.compare(
            baseline: value,
            instrumented: value,
            baselineArray: array,
            instrumentedArray: array
        )

        XCTAssertTrue(comparison.exactlyEqual)
        XCTAssertEqual(comparison.maxAbsoluteDifference, 0)
    }
}

private final class ProbeInstrumentationModel: MLXNN.Module {}
