// SPDX-License-Identifier: MIT

// PS1 — THE SETTLEMENT EDGE IS EXECUTABLE EVIDENCE, NOT CODE ORDER
//
// The production `MLXPrefixRecomputeExecutor` cannot be constructed without a
// loaded `ModelContainer`, so the "a terminated arm never consumes its binding"
// claim used to rest only on the ORDER of statements in that method. These tests
// drive the same seam the production executor calls — `G3RunSettlement.settle` —
// together with the REAL `MLXExecutionStateBackend`, which is pure data.
//
// The four properties the reviewer asked to pin:
//   1. terminated  -> the consume body is NOT entered and the binding survives;
//   2. live        -> exactly ONE settle reaches the body; a second is refused;
//   3. a check that throws before the consume leaves the binding unconsumed;
//   4. a failure AFTER the consume is recorded as settled — the backend cannot
//      roll a consume back, so the seam does not pretend it was a transaction.
//
// No model is loaded, no provider is registered, no G3 execution is claimed.

import Foundation
import Testing
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// Stands in for a registration step that fails after the consume already
/// happened (e.g. rebinding the advanced representation).
private struct RegistrationFailed: Error {}

struct G3RunSettlementTests {

    private let runID = ExecutionID("settlement-run")
    private let position = ExecutionPosition(2)

    private func handle() -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: runID,
            lineage: ExecutionLineage(root: runID),
            position: position,
            continuation: ExecutionContinuation(nextInput: "", continuationID: ""),
            lifecycle: .attached)
    }

    private func boundBackend(_ state: ExecutionStateHandle) -> MLXExecutionStateBackend {
        let backend = MLXExecutionStateBackend()
        backend.bind(
            executionID: state.id, position: state.position, tokenPrefix: [1, 2])
        return backend
    }

    // MARK: 1. A terminated arm never reaches the consume

    @Test func aTerminatedArmNeverConsumesItsBinding() throws {
        let state = handle()
        let backend = boundBackend(state)
        let settlement = G3RunSettlement(armID: "ES+IS")
        var consumeCalls = 0

        #expect(throws: G3PerArmCacheError.armTerminated(reason: "kv_write_refused")) {
            try settlement.settle(terminalReason: "kv_write_refused") {
                consumeCalls += 1
                backend.consumeBinding(for: state)
            }
        }

        #expect(consumeCalls == 0, "the consume body must not be entered for a dead arm")
        #expect(settlement.isSettled == false, "a refusal is not a settlement")
        // The binding is still bound: the refusal did not silently consume it.
        let bound = try backend.boundPrefix(for: state)
        #expect(bound.prefix == [1, 2])
    }

    // MARK: 2. A live arm consumes exactly once

    @Test func aLiveArmConsumesExactlyOnce() throws {
        let state = handle()
        let backend = boundBackend(state)
        let settlement = G3RunSettlement(armID: "ES+IS")
        var consumeCalls = 0

        try settlement.settle(terminalReason: nil) {
            consumeCalls += 1
            backend.consumeBinding(for: state)
        }
        #expect(consumeCalls == 1)
        #expect(settlement.isSettled)

        // A second settle is refused BEFORE the body, so the run cannot consume
        // its binding twice (the first consume already made the prefix stale).
        #expect(throws: G3PerArmCacheError.bindingAlreadySettled("ES+IS")) {
            try settlement.settle(terminalReason: nil) {
                consumeCalls += 1
                backend.consumeBinding(for: state)
            }
        }
        #expect(consumeCalls == 1, "a second settle must not reach the consume body")
        #expect(throws: ExecutionStateBackendError.noBoundRepresentation(state.id)) {
            _ = try backend.boundPrefix(for: state)
        }
    }

    // MARK: 3. A pre-consume check that throws leaves the binding unconsumed

    @Test func aThrowingPreConsumeCheckLeavesTheBindingUnconsumed() throws {
        let state = handle()
        let backend = MLXExecutionStateBackend()   // deliberately NOT bound
        let settlement = G3RunSettlement(armID: "ES+IS")
        var consumeCalls = 0

        // The production order is check-then-settle; the check throwing must not
        // burn the one settle or pretend the run was consumed.
        #expect(throws: ExecutionStateBackendError.noBoundRepresentation(state.id)) {
            _ = try backend.boundPrefix(for: state)
            try settlement.settle(terminalReason: nil) {
                consumeCalls += 1
                backend.consumeBinding(for: state)
            }
        }

        #expect(consumeCalls == 0)
        #expect(settlement.isSettled == false)
    }

    // MARK: 4. A post-consume failure is settled, not rolled back

    @Test func aConsumeThatThrowsIsRecordedAsSettledAndIsNotRolledBack() throws {
        let state = handle()
        let backend = boundBackend(state)
        let settlement = G3RunSettlement(armID: "ES+IS")
        var consumeCalls = 0

        #expect(throws: RegistrationFailed.self) {
            try settlement.settle(terminalReason: nil) {
                consumeCalls += 1
                backend.consumeBinding(for: state)   // the consume DID happen
                throw RegistrationFailed()           // registration afterward failed
            }
        }

        #expect(consumeCalls == 1)
        #expect(settlement.isSettled, "a post-consume failure is not a rollback")
        // No second attempt can consume: the write-ahead record is permanent.
        #expect(throws: G3PerArmCacheError.bindingAlreadySettled("ES+IS")) {
            try settlement.settle(terminalReason: nil) { consumeCalls += 1 }
        }
        #expect(consumeCalls == 1)
        #expect(throws: ExecutionStateBackendError.noBoundRepresentation(state.id)) {
            _ = try backend.boundPrefix(for: state)
        }
    }
}
