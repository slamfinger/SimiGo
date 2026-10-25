import Foundation
import CContinuationSupport

public enum FrozenContinuation {
    public static let schemaVersion = "c-impl-report-v2"
    public static let taskID = "C-T-001"
    public static let beforeState = "alpha=17;mode=quiet"
    public static let afterState = "alpha=42;mode=active"
    public static let directionalChange =
        "changed=true;before=alpha=17;mode=quiet;after=alpha=42;mode=active"
    public static let nextAction = "REQUEST_HEALTH_CHECK"
}

public struct EvaluationResult: Codable, Equatable, Sendable {
    public var x1TaskIdentity: Bool
    public var x2BeforeState: Bool
    public var x3AfterState: Bool
    public var x4DirectionalChange: Bool
    public var x5NextAction: Bool
    public var partialSuccess: Bool
    public var fullContinuationSuccess: Bool
    public var invalidRun: Bool
    public var failedAuditChecks: [String]
}

public enum FrozenEvaluator {
    public static func evaluate(
        report: ContinuationReport,
        evidence: Evidence
    ) -> EvaluationResult {
        let x1 = report.taskID == FrozenContinuation.taskID
        let x2 = report.beforeState == FrozenContinuation.beforeState
        let x3 = report.afterState == FrozenContinuation.afterState
        let x4 = report.directionalChange == FrozenContinuation.directionalChange
        let x5 = report.nextAction == FrozenContinuation.nextAction
        let failedAudit = evidence.auditObservations.filter { !$0.passed }.map(\.check)
        let invalid = !evidence.sourceLegality || !failedAudit.isEmpty
        let passed = [x1, x2, x3, x4, x5]
        return EvaluationResult(
            x1TaskIdentity: x1,
            x2BeforeState: x2,
            x3AfterState: x3,
            x4DirectionalChange: x4,
            x5NextAction: x5,
            partialSuccess: !invalid && passed.contains(true) && !passed.allSatisfy(\.self),
            fullContinuationSuccess: !invalid && passed.allSatisfy(\.self),
            invalidRun: invalid,
            failedAuditChecks: failedAudit
        )
    }
}
