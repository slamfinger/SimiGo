import XCTest
@testable import SimiGo2Experimental

final class TaskRunOutcomeClassificationTests: XCTestCase {
  func testContractRefusalAfterAdmissionIsNotAnAdmissionRefusal() {
    XCTAssertEqual(
      TaskRunOutcomeClassification.inputAdmissionStatus(
        admitted: true,
        refusalKind: "PRODUCER_RESULT_CONTRACT_REFUSAL"
      ),
      "ADMITTED"
    )
    XCTAssertEqual(
      TaskRunOutcomeClassification.terminalState(
        settled: false,
        inputAdmissionRefused: false
      ),
      "TASK_FAILED"
    )
  }

  func testActualAdmissionRefusalKeepsAdmissionFailureClassification() {
    XCTAssertEqual(
      TaskRunOutcomeClassification.inputAdmissionStatus(
        admitted: false,
        refusalKind: "ADMISSION_REFUSED"
      ),
      "ADMISSION_REFUSED"
    )
    XCTAssertEqual(
      TaskRunOutcomeClassification.terminalState(
        settled: false,
        inputAdmissionRefused: true
      ),
      "INPUT_ADMISSION_REFUSED"
    )
  }

  func testSuccessfulSettlementTakesPrecedence() {
    XCTAssertEqual(
      TaskRunOutcomeClassification.terminalState(
        settled: true,
        inputAdmissionRefused: false
      ),
      "TASK_SETTLED"
    )
  }

  func testUnclassifiedFailureIsNotMisreportedAsAdmissionRefusal() {
    XCTAssertEqual(
      TaskRunOutcomeClassification.inputAdmissionStatus(
        admitted: false,
        refusalKind: nil
      ),
      "NOT_ATTEMPTED"
    )
    XCTAssertEqual(
      TaskRunOutcomeClassification.terminalState(
        settled: false,
        inputAdmissionRefused: false
      ),
      "TASK_FAILED"
    )
  }
}
