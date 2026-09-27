import Foundation
import Testing
import SimiGo2Experimental

struct MLXParameterSwapGateTests {
  @Test func qwen3ParameterSwapGate() async throws {
    // ponytail: opt-in because the real 30B checkpoint is too heavy for swift test.
    guard let modelDirectory = ProcessInfo.processInfo.environment["SIMIGO2_QWEN3_MODEL_DIR"] else {
      return
    }

    let report = try await MLXParameterSwapGate.run(
      modelDirectory: URL(fileURLWithPath: modelDirectory),
      prompt: "Return exactly one word: ping",
      maxTokens: 24
    )

    #expect(report.restoredParameterMatchesBaseline)
    #expect(report.targetWasLoadBearing)
    #expect(report.baselineEqualsRestored)
  }
}
