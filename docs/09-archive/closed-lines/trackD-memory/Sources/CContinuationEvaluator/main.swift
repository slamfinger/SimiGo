import Foundation
import CContinuationSupport
import CContinuationEvaluatorCore

let arguments = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("EVALUATOR_ERROR: \(message)\n".utf8))
    exit(2)
}

do {
    guard arguments.count == 6,
          arguments[0] == "--report",
          arguments[2] == "--evidence",
          arguments[4] == "--output" else {
        fail("usage: CContinuationEvaluator --report REPORT --evidence EVIDENCE --output OUTPUT")
    }
    let report = try StudyJSON.read(ContinuationReport.self, from: URL(fileURLWithPath: arguments[1]))
    let evidence = try StudyJSON.read(Evidence.self, from: URL(fileURLWithPath: arguments[3]))
    let result = FrozenEvaluator.evaluate(report: report, evidence: evidence)
    let output = URL(fileURLWithPath: arguments[5])
    try StudyJSON.write(result, to: output)
    print(String(decoding: try StudyJSON.data(result), as: UTF8.self))
} catch {
    fail(String(describing: error))
}
