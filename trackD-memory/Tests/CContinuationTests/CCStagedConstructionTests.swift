import Foundation
import Testing
import CContinuationSupport

@Suite
struct CCStagedConstructionTests {
    private func state(pointers: [String: String], phase: String = "OLD_PROCESS_STARTED") -> ExecutionState {
        ExecutionState(
            taskID: "C-T-001",
            lifecyclePhase: phase,
            carrierPointers: pointers,
            runID: UUID().uuidString,
            executorIdentity: "test"
        )
    }

    @Test
    func cCAcceptsTheFrozenStagedConstructionSequence() throws {
        let states: [[String: String]] = [
            [:],
            ["task": "one"],
            ["task": "one", "s0": "two"],
            ["task": "one", "s0": "two", "s1": "three"],
            ["task": "one", "s0": "two", "s1": "three", "progress": "four"],
            ["task": "one", "s0": "two", "s1": "three", "progress": "four", "relation": "five"],
        ]

        for pointers in states {
            try state(pointers: pointers).validate(for: .c, stage: .construction)
        }
    }

    @Test
    func cCAllowsRelationOnlyAfterCompleteBase() throws {
        let completeBase = state(
            pointers: ["task": "one", "s0": "two", "s1": "three", "progress": "four"]
        )
        let completeWithRelation = state(
            pointers: [
                "task": "one",
                "s0": "two",
                "s1": "three",
                "progress": "four",
                "relation": "five",
            ]
        )

        try completeBase.validate(for: .c, stage: .construction)
        try completeWithRelation.validate(for: .c, stage: .construction)
        try completeWithRelation.validate(for: .c, stage: .final)
    }

    @Test
    func cCRejectsCorruptOrPrematureRelationStates() {
        let invalidStates: [[String: String]] = [
            ["relation": "five"],
            ["task": "one", "relation": "five"],
            ["task": "one", "s0": "two", "relation": "five"],
            ["task": "one", "s0": "two", "s1": "three", "relation": "five"],
            ["task": "one", "s0": "two", "s1": "three", "progress": "four", "extra": "six"],
        ]

        for pointers in invalidStates {
            #expect(throws: StudyError.self) {
                try state(pointers: pointers).validate(for: .c, stage: .construction)
            }
            #expect(throws: StudyError.self) {
                try state(pointers: pointers).validate(for: .c, stage: .final)
            }
        }
    }
}
