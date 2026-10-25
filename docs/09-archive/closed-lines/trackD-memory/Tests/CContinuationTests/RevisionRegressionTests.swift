import Foundation
import Testing
import CContinuationSupport

@Suite
struct CImplRevisionRegressionTests {
    private func state(
        phase: String,
        pointers: [String: String],
        taskID: String = "C-T-001"
    ) -> ExecutionState {
        ExecutionState(
            taskID: taskID,
            lifecyclePhase: phase,
            carrierPointers: pointers,
            runID: UUID().uuidString,
            executorIdentity: "test"
        )
    }

    @Test
    func parserModelsContinueLifecycleWithoutOptionAmbiguity() throws {
        let invocation = try LifecycleInvocationParser.parse([
            "continue",
            "--arm",
            "C-C",
            "--workspace",
            "/tmp/workspace",
            "--task-id",
            "C-T-001",
        ])
        #expect(invocation.command == .continue)
        #expect(invocation.options["--arm"] == "C-C")
    }

    @Test
    func parserModelsOldLifecycleAndRejectsAmbiguousGrammar() {
        let invocation = try? LifecycleInvocationParser.parse(["old", "--arm", "C-A"])
        #expect(invocation?.command == .old)
        #expect(throws: StudyError.self) {
            try LifecycleInvocationParser.parse(["continue", "--arm"])
        }
        #expect(throws: StudyError.self) {
            try LifecycleInvocationParser.parse(["--arm", "C-A"])
        }
        #expect(throws: StudyError.self) {
            try LifecycleInvocationParser.parse(["continue", "--arm", "C-A", "--arm", "C-B"])
        }
    }

    @Test
    func cBAllowsLegalConstructionStatesButRejectsPrematureFinalValidation() throws {
        let checkpoints = [
            state(phase: "OLD_PROCESS_STARTED", pointers: [:]),
            state(phase: "OLD_PROCESS_STARTED", pointers: ["task": "one"]),
            state(phase: "S0_OBSERVED", pointers: ["task": "one", "s0": "two"]),
            state(phase: "S1_OBSERVED", pointers: ["task": "one", "s0": "two", "s1": "three"]),
            state(
                phase: "S1_OBSERVED",
                pointers: ["task": "one", "s0": "two", "s1": "three", "progress": "four"]
            ),
        ]

        for checkpoint in checkpoints {
            try checkpoint.validate(for: .b, stage: .construction)
            if checkpoint.carrierPointers.count < 4 {
                #expect(throws: StudyError.self) {
                    try checkpoint.validate(for: .b, stage: .final)
                }
            }
        }

        try checkpoints[4].validate(for: .b, stage: .final)
    }

    @Test
    func cBRejectsInvalidConstructionSequences() {
        let missingTask = state(phase: "S0_OBSERVED", pointers: ["s0": "one"])
        let missingS0 = state(phase: "S1_OBSERVED", pointers: ["task": "one", "s1": "two"])
        let extra = state(
            phase: "POST_CHANGE_OBSERVED",
            pointers: ["task": "one", "s0": "two", "s1": "three", "progress": "four", "relation": "five"]
        )
        #expect(throws: StudyError.self) { try missingTask.validate(for: .b, stage: .construction) }
        #expect(throws: StudyError.self) { try missingS0.validate(for: .b, stage: .construction) }
        #expect(throws: StudyError.self) { try extra.validate(for: .b, stage: .construction) }
        #expect(throws: StudyError.self) { try extra.validate(for: .b, stage: .final) }
    }

    @Test
    func cCRequiresCompleteBaseBeforeRelation() throws {
        let base = state(
            phase: "S1_OBSERVED",
            pointers: ["task": "one", "s0": "two", "s1": "three", "progress": "four"]
        )
        let complete = state(
            phase: "S1_OBSERVED",
            pointers: [
                "task": "one",
                "s0": "two",
                "s1": "three",
                "progress": "four",
                "relation": "five",
            ]
        )
        let relationOnly = state(phase: "S1_OBSERVED", pointers: ["relation": "five"])
        let incompleteWithRelation = state(
            phase: "S1_OBSERVED",
            pointers: ["task": "one", "s1": "three", "progress": "four", "relation": "five"]
        )

        try base.validate(for: .c, stage: .construction)
        try complete.validate(for: .c, stage: .construction)
        try complete.validate(for: .c, stage: .final)
        #expect(throws: StudyError.self) { try relationOnly.validate(for: .c, stage: .construction) }
        #expect(throws: StudyError.self) { try incompleteWithRelation.validate(for: .c, stage: .construction) }
    }
}
