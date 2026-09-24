import XCTest
@testable import SimiGo2Experimental

final class GroupExecutionTraceProbeTests: XCTestCase {
    private func event(
        _ sequence: Int,
        _ path: String,
        _ layer: Int,
        _ shape: [Int],
        _ ms: Double = 0
    ) -> ExecutionTraceEvent {
        ExecutionTraceEvent(
            sequence: sequence,
            modulePath: path,
            decoderLayer: layer,
            outputShape: shape,
            millisecondsSinceStart: ms
        )
    }

    private func syntheticTrace(passes: Int, modules: Int) -> [ExecutionTraceEvent] {
        var events: [ExecutionTraceEvent] = []
        var sequence = 0
        for _ in 0..<passes {
            for layer in 0..<modules {
                sequence += 1
                events.append(
                    event(
                        sequence,
                        "model.layers.\(layer).mlp.switch_mlp.down_proj",
                        layer,
                        [1, 1, 4096],
                        Double(sequence) * 0.5
                    )
                )
            }
        }
        return events
    }

    func testDecoderLayerParsing() {
        XCTAssertEqual(
            GroupExecutionTraceProbe.decoderLayer(
                fromPath: "model.layers.17.mlp.switch_mlp.down_proj"
            ),
            17
        )
        XCTAssertEqual(
            GroupExecutionTraceProbe.decoderLayer(fromPath: "model.layers.0.mlp.down_proj"),
            0
        )
        XCTAssertEqual(
            GroupExecutionTraceProbe.decoderLayer(fromPath: "model.embed_tokens"),
            -1
        )
    }

    func testPassCountCountsLayerZeroEvents() {
        let trace = syntheticTrace(passes: 3, modules: 4)
        XCTAssertEqual(GroupExecutionTraceProbe.passCount(events: trace), 3)
        XCTAssertEqual(GroupExecutionTraceProbe.passCount(events: []), 0)

        var missingLayerZero = syntheticTrace(passes: 2, modules: 4)
        missingLayerZero.removeAll { $0.decoderLayer == 0 }
        XCTAssertEqual(GroupExecutionTraceProbe.passCount(events: missingLayerZero), 0)
    }

    func testTraceStabilityIgnoresTimestampsAndSequences() {
        let a = syntheticTrace(passes: 2, modules: 3)
        var b = a
        // identical modulo timestamps/sequence numbers
        b = b.enumerated().map { index, e in
            ExecutionTraceEvent(
                sequence: e.sequence + 100,
                modulePath: e.modulePath,
                decoderLayer: e.decoderLayer,
                outputShape: e.outputShape,
                millisecondsSinceStart: e.millisecondsSinceStart + 42
            )
        }
        XCTAssertTrue(GroupExecutionTraceProbe.tracesStable(a, b))
        XCTAssertTrue(GroupExecutionTraceProbe.tracesStable(a, a))

        // shape change breaks stability
        var c = a
        c[1] = ExecutionTraceEvent(
            sequence: c[1].sequence,
            modulePath: c[1].modulePath,
            decoderLayer: c[1].decoderLayer,
            outputShape: [1, 2, 4096],
            millisecondsSinceStart: c[1].millisecondsSinceStart
        )
        XCTAssertFalse(GroupExecutionTraceProbe.tracesStable(a, c))

        // length change breaks stability
        XCTAssertFalse(GroupExecutionTraceProbe.tracesStable(a, Array(a.dropLast())))
    }

    func testEventBoxAppendsAndClears() {
        let box = ExecutionTraceEventBox()
        box.append(modulePath: "model.layers.0.mlp.down_proj", decoderLayer: 0, outputShape: [1])
        box.append(modulePath: "model.layers.1.mlp.down_proj", decoderLayer: 1, outputShape: [2])
        XCTAssertEqual(box.snapshot().count, 2)
        XCTAssertEqual(box.snapshot().map(\.sequence), [1, 2])
        box.clear()
        XCTAssertEqual(box.snapshot().count, 0)
    }
}
