import MLX
import MLXNN
import XCTest
@testable import SimiGo2Experimental

private final class ProbeUnary: Module, UnaryLayer {
    let projection = Linear(2, 2)

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        projection(x)
    }
}

private final class ProbeLayer: Module {
    @ModuleInfo(key: "unary") var unary = ProbeUnary()
}

private final class ProbeModel: Module {
    @ModuleInfo(key: "layers") var layers: [ProbeLayer]

    override init() {
        _layers.wrappedValue = [ProbeLayer(), ProbeLayer()]
    }
}

final class RepresentationCaptureAuditTests: XCTestCase {
    func testAuditFindsLayerBoundariesWithoutClaimingActivationCapture() {
        let report = RepresentationCaptureAudit.audit(model: ProbeModel())

        XCTAssertEqual(report.candidateLayerPaths, ["layers.0", "layers.1"])
        XCTAssertFalse(report.stableObservationContract)
        XCTAssertEqual(report.recommendedRoute, .isolatedInstrumentation)
        XCTAssertTrue(report.boundary.contains("NOT_ACTIVATION_CAPTURE"))
    }
}
