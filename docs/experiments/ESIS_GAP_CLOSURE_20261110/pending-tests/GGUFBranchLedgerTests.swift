import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// Phase 1 — logical ES continuity over the external llama.cpp engine.
///
/// No engine is involved here. These pin the ledger and the runtime surface a
/// fork, a restore and a context reconstruction are built from: the transcript
/// copy, the fork point, the refusal paths, and the fact that nothing claims a
/// shared KV or a saved prefill.
final class GGUFBranchLedgerTests: XCTestCase {

    private func message(_ role: String, _ text: String) -> JSONValue {
        .object(["role": .string(role), "content": .string(text)])
    }

    private func record(
        _ ledger: GGUFBranchLedger,
        _ key: String,
        _ turns: [JSONValue],
        tokens: Int? = 17,
        identity: String? = "engine-A"
    ) {
        ledger.record(
            storageKey: key, history: turns,
            engineTokens: tokens, engineIdentity: identity)
    }

    // MARK: fork

    func testForkCopiesTranscriptAndRecordsForkPoint() throws {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/s/main", [message("user", "问"), message("assistant", "答")])

        let child = try ledger.fork(
            source: "default/s/main", target: "default/s/whatif",
            currentEngineIdentity: "engine-A")

        XCTAssertEqual(child.storageKey, "default/s/whatif")
        XCTAssertEqual(child.history, [message("user", "问"), message("assistant", "答")])
        XCTAssertEqual(child.forkPoint?.sourceStorageKey, "default/s/main")
        XCTAssertEqual(child.forkPoint?.atMessage, 2)
        // The token position is the engine-reported one, not an estimate.
        XCTAssertEqual(child.forkPoint?.atToken, 17)
        XCTAssertEqual(child.engineIdentity, "engine-A")
    }

    func testForkLeavesSourceFreeToAdvance() throws {
        let ledger = GGUFBranchLedger()
        let two = [message("user", "问"), message("assistant", "答")]
        record(ledger, "default/s/main", two)
        _ = try ledger.fork(
            source: "default/s/main", target: "default/s/whatif",
            currentEngineIdentity: "engine-A")

        record(
            ledger, "default/s/main",
            two + [message("user", "再问"), message("assistant", "再答")], tokens: 41)

        XCTAssertEqual(ledger.branch(at: "default/s/main")?.history.count, 4)
        XCTAssertEqual(ledger.branch(at: "default/s/whatif")?.history.count, 2)
        XCTAssertEqual(
            ledger.branch(at: "default/s/whatif")?.engineTokens, 17,
            "the child keeps the position it branched at")
    }

    func testForkOfForkKeepsItsOwnProvenance() throws {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/s/main", [message("user", "问")])
        _ = try ledger.fork(
            source: "default/s/main", target: "default/s/a",
            currentEngineIdentity: "engine-A")
        let grandchild = try ledger.fork(
            source: "default/s/a", target: "default/s/a/b",
            currentEngineIdentity: "engine-A")

        XCTAssertEqual(grandchild.forkPoint?.sourceStorageKey, "default/s/a")
        XCTAssertEqual(ledger.branch(at: "default/s/a")?.forkPoint?.sourceStorageKey,
                       "default/s/main")
    }

    // MARK: refusal (the negative half of the isolation claim)

    func testForkRefusesBranchTheEngineNeverProduced() {
        let ledger = GGUFBranchLedger()
        XCTAssertThrowsError(
            try ledger.fork(
                source: "default/s/ghost", target: "default/s/x",
                currentEngineIdentity: "engine-A")) { error in
            guard case GGUFBranchLedger.Failure.unknownSource = error else {
                return XCTFail("expected unknownSource, got \(error)")
            }
        }
        XCTAssertNil(ledger.branch(at: "default/s/x"), "a refused fork must not register a child")
    }

    func testForkRefusesTranscriptRenderedByADifferentEngine() {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/s/main", [message("user", "问")])
        XCTAssertThrowsError(
            try ledger.fork(
                source: "default/s/main", target: "default/s/x",
                currentEngineIdentity: "engine-B")) { error in
            guard case GGUFBranchLedger.Failure.identityMismatch = error else {
                return XCTFail("expected identityMismatch, got \(error)")
            }
        }
        XCTAssertNil(ledger.branch(at: "default/s/x"))
    }

    func testForkRefusesSilentlyReplacingALiveBranch() {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/s/main", [message("user", "问")])
        record(ledger, "default/s/whatif", [message("user", "别的上下文")])
        XCTAssertThrowsError(
            try ledger.fork(
                source: "default/s/main", target: "default/s/whatif",
                currentEngineIdentity: "engine-A")) { error in
            guard case GGUFBranchLedger.Failure.targetInUse = error else {
                return XCTFail("expected targetInUse, got \(error)")
            }
        }
        XCTAssertEqual(
            ledger.branch(at: "default/s/whatif")?.history, [message("user", "别的上下文")],
            "the refusal leaves the live branch alone")
    }

    func testMissingIdentitySideIsNotTreatedAsMismatch() throws {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/s/main", [message("user", "问")], identity: nil)
        // The probe never answered: identity is unknown on both sides, which is
        // not evidence that the engine changed.
        let child = try ledger.fork(
            source: "default/s/main", target: "default/s/x", currentEngineIdentity: nil)
        XCTAssertEqual(child.history, [message("user", "问")])
    }

    // MARK: restore / delete / list

    func testRestoreReturnsTheRecordedContextForTheSameEngine() throws {
        let ledger = GGUFBranchLedger()
        let two = [message("user", "问"), message("assistant", "答")]
        record(ledger, "default/s/main", two)
        XCTAssertEqual(
            try ledger.restore("default/s/main", currentEngineIdentity: "engine-A").history, two)
    }

    func testRestoreRefusesAStaleBranch() {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/s/main", [message("user", "问")])
        XCTAssertThrowsError(
            try ledger.restore("default/s/main", currentEngineIdentity: "engine-Z"))
    }

    func testDeleteRemovesOnlyTheNamedBranch() throws {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/s/main", [message("user", "问")])
        record(ledger, "default/s/whatif", [message("user", "问")])
        XCTAssertTrue(ledger.delete("default/s/main"))
        XCTAssertFalse(ledger.delete("default/s/main"))
        XCTAssertNil(ledger.branch(at: "default/s/main"))
        XCTAssertNotNil(ledger.branch(at: "default/s/whatif"))
    }

    func testLiveBranchListingIsScopedToItsSession() throws {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/one/main", [message("user", "问")])
        record(ledger, "default/one/whatif", [message("user", "问")])
        record(ledger, "default/two/main", [message("user", "问")])
        let scope = try AgentExecutionKey(
            agentId: nil, sessionId: "one", logicalBranchId: "main").scope

        XCTAssertEqual(ledger.liveBranches(scope: scope), ["main", "whatif"])
    }

    func testClearDropsEveryBranch() {
        let ledger = GGUFBranchLedger()
        record(ledger, "default/one/main", [message("user", "问")])
        ledger.clear()
        XCTAssertTrue(ledger.snapshot.isEmpty)
    }
}

/// The runtime-facing half: what `ManagedGGUFRuntime` records from a turn, what
/// it hands back for a fork, and when it rewrites the context of a turn.
final class ManagedGGUFBranchTests: XCTestCase {

    private func message(_ role: String, _ text: String) -> JSONValue {
        .object(["role": .string(role), "content": .string(text)])
    }

    private func runtime() -> ManagedGGUFRuntime {
        let backend = BackendConfig(
            name: "llama.cpp",
            customExecutable: nil,
            args: { _, _, _ in [] },
            healthEndpoint: "/health",
            startupTimeout: 1,
            kind: .gguf)
        return ManagedGGUFRuntime(config: ModelConfig(), backendConfig: backend)
    }

    private func turn(_ text: String, prompt: Int, generated: Int) -> GenerationResult {
        GenerationResult(
            text: text,
            usage: GenerationUsageReport(promptTokens: prompt, generationTokens: generated),
            completion: .complete)
    }

    func testObservedTurnBecomesAForkableTranscriptWithNoCacheClaims() throws {
        let runtime = runtime()
        let history = [message("user", "问"), message("assistant", "答")]
        runtime.observe(
            agentId: nil, sessionId: "s", branchId: "main",
            messages: [message("user", "问")],
            result: turn("答", prompt: 11, generated: 6),
            engineIdentity: "engine-A")

        let metadata = try runtime.forkBranch(
            agentId: nil, sessionId: "s",
            sourceBranch: "main", targetBranch: "whatif", modelId: "m")

        XCTAssertEqual(metadata.storageKey, "default/s/whatif")
        XCTAssertEqual(metadata.history, history)
        XCTAssertEqual(metadata.forkPoint?.atMessage, 2)
        // The position comes from the engine's own usage report.
        XCTAssertEqual(metadata.forkPoint?.atToken, 17)
        XCTAssertNil(metadata.kvFingerprint, "there is no KV behind a logical fork")
        XCTAssertNil(metadata.cacheSHA256, "there are no cache bytes to checksum")
        XCTAssertNil(metadata.checkpointGeneration, "there is no checkpoint file")
    }

    func testForkOfUnobservedBranchRefusesThroughTheRuntime() {
        let runtime = runtime()
        XCTAssertThrowsError(
            try runtime.forkBranch(
                agentId: nil, sessionId: "s",
                sourceBranch: "ghost", targetBranch: "x", modelId: "m"))
    }

    func testForkedBranchUnderSupplyingItsContextGetsTheRecordedOneBack() throws {
        let runtime = runtime()
        runtime.observe(
            agentId: nil, sessionId: "s", branchId: "main",
            messages: [message("user", "问")],
            result: turn("答", prompt: 11, generated: 6),
            engineIdentity: nil)
        _ = try runtime.forkBranch(
            agentId: nil, sessionId: "s",
            sourceBranch: "main", targetBranch: "whatif", modelId: "m")

        let context = runtime.contextForTurn(
            agentId: nil, sessionId: "s", branchId: "whatif",
            incoming: [message("user", "那然后呢")])

        XCTAssertEqual(
            context,
            [message("user", "问"), message("assistant", "答"), message("user", "那然后呢")],
            "a forked branch continues from its recorded execution point")
    }

    func testOrdinaryBranchKeepsTheCallersMessagesUntouched() {
        let runtime = runtime()
        runtime.observe(
            agentId: nil, sessionId: "s", branchId: "main",
            messages: [message("user", "问")],
            result: turn("答", prompt: 11, generated: 6),
            engineIdentity: nil)

        // Same under-supply as the forked case, on a branch that was never
        // derived: reconstruction must stay off, or every trimmed client would
        // silently inherit an old transcript.
        let context = runtime.contextForTurn(
            agentId: nil, sessionId: "s", branchId: "main",
            incoming: [message("user", "那然后呢")])

        XCTAssertEqual(context, [message("user", "那然后呢")])
    }

    func testForkedBranchSuppliedFullTranscriptIsNotRewritten() throws {
        let runtime = runtime()
        runtime.observe(
            agentId: nil, sessionId: "s", branchId: "main",
            messages: [message("user", "问")],
            result: turn("答", prompt: 11, generated: 6),
            engineIdentity: nil)
        _ = try runtime.forkBranch(
            agentId: nil, sessionId: "s",
            sourceBranch: "main", targetBranch: "whatif", modelId: "m")

        let full = [message("user", "问"), message("assistant", "答"), message("user", "新问")]
        XCTAssertEqual(
            runtime.contextForTurn(
                agentId: nil, sessionId: "s", branchId: "whatif", incoming: full),
            full)
    }

    func testDeletedBranchIsGoneFromListingAndFork() throws {
        let runtime = runtime()
        runtime.observe(
            agentId: nil, sessionId: "s", branchId: "main",
            messages: [message("user", "问")],
            result: turn("答", prompt: 1, generated: 1),
            engineIdentity: nil)
        _ = try runtime.forkBranch(
            agentId: nil, sessionId: "s",
            sourceBranch: "main", targetBranch: "whatif", modelId: "m")
        XCTAssertEqual(runtime.liveBranches(agentId: nil, sessionId: "s"), ["main", "whatif"])

        runtime.deleteBranch(agentId: nil, sessionId: "s", branchId: "whatif")

        XCTAssertEqual(runtime.liveBranches(agentId: nil, sessionId: "s"), ["main"])
        XCTAssertThrowsError(
            try runtime.forkBranch(
                agentId: nil, sessionId: "s",
                sourceBranch: "whatif", targetBranch: "again", modelId: "m"))
    }

    func testMergeContinuationDropsOnlyTheReplayedTail() {
        let known = [
            message("system", "s"), message("user", "a"), message("assistant", "b"),
        ]
        XCTAssertEqual(
            ManagedGGUFRuntime.mergeContinuation(known: known, incoming: [message("user", "c")]),
            known + [message("user", "c")])
        XCTAssertEqual(
            ManagedGGUFRuntime.mergeContinuation(
                known: known, incoming: [message("assistant", "b"), message("user", "c")]),
            known + [message("user", "c")])
        XCTAssertEqual(
            ManagedGGUFRuntime.mergeContinuation(known: known, incoming: known), known)
    }
}
