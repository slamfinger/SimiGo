import Foundation
import Testing
import CContinuationSupport
import CContinuationEvaluatorCore

@Suite
struct CContinuationTests {
    @Test
    func executionStateRejectsSmuggledPointers() throws {
        let state = ExecutionState(
            taskID: "C-T-001",
            lifecyclePhase: "POST_CHANGE_OBSERVED",
            runID: UUID().uuidString,
            executorIdentity: "test"
        )
        try state.validate(for: .a)
        var smuggled = state
        smuggled.carrierPointers = ["s0": "one", "s1": "two"]
        #expect(throws: StudyError.self) { try smuggled.validate(for: .a) }
    }

    @Test
    func directionalChangeIsDerivedFromActualSnapshots() {
        let before = EntitySnapshot(entity: "E", alpha: 17, mode: "quiet")
        let after = EntitySnapshot(entity: "E", alpha: 42, mode: "active")
        #expect(
            EntitySnapshot.directionalChange(before: before, after: after) ==
            "changed=true;before=alpha=17;mode=quiet;after=alpha=42;mode=active"
        )
    }

    @Test
    func taskRuleProducesActionFromRecoveredStateOnly() {
        let rule = ContinuationRule(alphaMinimum: 40, requiredMode: "active", action: "REQUEST_HEALTH_CHECK")
        #expect(rule.action(for: EntitySnapshot(entity: "E", alpha: 42, mode: "active")) == "REQUEST_HEALTH_CHECK")
        #expect(rule.action(for: EntitySnapshot(entity: "E", alpha: 17, mode: "quiet")) == "WAIT_FOR_CHANGE")
    }

    @Test
    func frozenEvaluatorUsesExactReportOnly() {
        let report = ContinuationReport(
            schemaVersion: "c-impl-report-v2",
            taskID: "C-T-001",
            beforeState: "alpha=17;mode=quiet",
            afterState: "alpha=42;mode=active",
            directionalChange: "changed=true;before=alpha=17;mode=quiet;after=alpha=42;mode=active",
            nextAction: "REQUEST_HEALTH_CHECK",
            blocker: "none",
            sourceLegality: true
        )
        let evidence = Evidence(
            schemaVersion: "c-impl-evidence-v2",
            invocation: InvocationEvidence(
                command: "continue",
                arm: .c,
                root: "/tmp/unused",
                processID: 1,
                parentProcessID: 0,
                arguments: ["/bin/CContinuationStudyContinue", "continue"],
                workingDirectory: "/tmp",
                environmentNames: [],
                declaredEnvironmentValues: [:],
                timestamp: Date()
            ),
            declaredReadPaths: [],
            carrierReads: [],
            persistenceSources: [],
            sourceLegality: true,
            auditObservations: [AuditObservation(
                check: "undeclared_filesystem_scan",
                method: "declared reads",
                observed: "3",
                passed: true
            )]
        )
        let result = FrozenEvaluator.evaluate(report: report, evidence: evidence)
        #expect(result.fullContinuationSuccess)
        #expect(!result.invalidRun)
    }
}
