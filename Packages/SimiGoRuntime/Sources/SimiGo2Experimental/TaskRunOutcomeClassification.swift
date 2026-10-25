import Foundation

/// Keeps input-admission failures distinct from failures after a successful
/// admission, especially a native producer result-contract refusal.
public enum TaskRunOutcomeClassification {
  public static func inputAdmissionStatus(
    admitted: Bool,
    refusalKind: String?
  ) -> String {
    if admitted {
      return "ADMITTED"
    }
    if let refusalKind, !refusalKind.isEmpty {
      return refusalKind
    }
    return "NOT_ATTEMPTED"
  }

  public static func terminalState(
    settled: Bool,
    inputAdmissionRefused: Bool
  ) -> String {
    if settled {
      return "TASK_SETTLED"
    }
    return inputAdmissionRefused ? "INPUT_ADMISSION_REFUSED" : "TASK_FAILED"
  }
}
