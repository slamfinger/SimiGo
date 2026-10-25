import XCTest
@testable import SimiGoRuntimeContract

// G3/G5 AT THE REPORT LEVEL — the runner no longer infers `settled` from
// `!session.isTerminated`.
//
// These cases drive the REAL `G3DualArmRunner` and read the REAL per-arm ledger
// the production executor writes. They pin the three report-level facts the
// second review asked for:
//   * a pre-settlement refusal has settleEntered=false / bindingConsumed=false;
//   * a post-settlement cancellation has settleEntered=true / bindingConsumed=true
//     and is STILL not a settled delivery (the old report could not say both);
//   * an independent gateway latch is reported as its own source, not as a
//     session tombstone, and it makes the run unsettled even when the session
//     never wrote `abortReason`.
final class G3SettlementAxesReportTests: XCTestCase {

    // MARK: Fakes

    final class Boundary: G3ArmCacheBoundary {
        var gatewayReason: String?
        func beginStep() {}
        var isolationAborted: Bool { false }
        var isolationAbortReason: String? { nil }
        var terminatedReason: String? { gatewayReason }
    }

    struct Provider: RuntimeAttestationProvider {
        let providerID = "simigo.g3.settlement-axes"
        let providerKind: RuntimeProviderKind = .swiftMLXLiveWorker
        func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
    }

    enum Mode {
        case delivered
        case refusedBeforeSettlement
        case consumedThenCancelled
        case deliveredThenGatewayLatch
    }

    /// A model-free executor that writes the axes exactly where the production
    /// executor does: generation -> settlement gate -> consume -> decode ->
    /// registration -> commit. It never routes to the standard path.
    final class LedgerExecutor: G3RoutableContinuation, G3CacheSessionInstalling,
        @unchecked Sendable
    {
        typealias ContinuationResult = G3GateOutcome
        let mode: Mode
        private(set) var session: G3ArmCacheSession?
        private(set) var standardCalls = 0
        private(set) var gatedCalls = 0

        init(mode: Mode) { self.mode = mode }

        @discardableResult
        func installG3CacheSession(_ session: G3ArmCacheSession) -> Bool {
            if let existing = self.session { return existing === session }
            self.session = session
            return true
        }

        func continueExecution(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int
        ) async throws -> G3GateOutcome {
            standardCalls += 1
            return outcome(stage: "standard", passed: false, count: 1)
        }

        func continueExecutionG3(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int,
            provider: any RuntimeAttestationProvider, request: AttestationRequest
        ) async throws -> G3GateOutcome {
            try await continueExecutionG3(
                state, nextInputTokens: nextInputTokens, maxTokens: maxTokens,
                provider: provider, request: request, registrar: nil)
        }

        func continueExecutionG3(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int,
            provider: any RuntimeAttestationProvider, request: AttestationRequest,
            registrar: G3AllocationRegistrar?
        ) async throws -> G3GateOutcome {
            gatedCalls += 1
            guard let session else {
                throw G3PerArmCacheError.missingCacheSession("axes-spy")
            }
            let ledger = session.runLedger
            switch mode {
            case .delivered:
                complete(ledger)
                return outcome(stage: "cleared", passed: true, count: 1)

            case .refusedBeforeSettlement:
                ledger.recordPhase(.generation, .failed("kv_write_refused"))
                throw G3PerArmCacheError.armTerminated(reason: "kv_write_refused")

            case .consumedThenCancelled:
                // The settlement gate WAS entered and the binding WAS consumed;
                // the cancellation lands afterwards. The report must keep both
                // facts instead of collapsing them into "not settled".
                ledger.recordPhase(.generation, .succeeded("committed=1"))
                ledger.markSettleEntered()
                ledger.markBindingConsumed()
                ledger.recordCancellation(.afterSettlement)
                ledger.recordPhase(.commit, .failed("cancelled_after_settlement"))
                throw CancellationError()

            case .deliveredThenGatewayLatch:
                complete(ledger)
                (session.boundary as? Boundary)?.gatewayReason = "gateway_stop"
                ledger.markPostSettlementTermination("gateway_stop")
                return outcome(stage: "cleared", passed: true, count: 1)
            }
        }

        private func complete(_ ledger: G3RunLedger) {
            ledger.recordPhase(.generation, .succeeded("committed=1"))
            ledger.markSettleEntered()
            ledger.markBindingConsumed()
            ledger.recordPhase(.decode, .succeeded("tokens=1"))
            ledger.recordPhase(.registration, .skipped("no_registrar"))
            ledger.recordPhase(.commit, .succeeded("result_delivered"))
        }

        private func outcome(
            stage: String, passed: Bool, count: Int
        ) -> G3GateOutcome {
            G3GateOutcome(
                gate: "axes-spy", stage: stage, passed: passed,
                eligibleForRuntimeEvidence: passed, evidenceClass: "axes_spy",
                generationCallCount: count, modelGenerationStartedByGate: false,
                isExecutionEvidence: false, reason: "", failedChecks: [],
                runID: "", challengeNonce: "", providerID: "", providerKind: "",
                trustedLiveProviderCount: 0)
        }
    }

    // MARK: Builders

    private func resource(
        _ role: G3ResourceRole, id: String, arm: String
    ) -> OwnedResource {
        OwnedResource(
            role: role, ownerLabel: arm, access: .armExclusiveMutable,
            storage: .confirmed(id))
    }

    private func makeOwner(_ arm: String, writeRoot: String) -> G3ArmResourceOwner {
        G3ArmResourceOwner(
            armID: RuntimeArmID(arm), isolationUnitID: "iso-\(arm)",
            modelWeights: OwnedResource(
                role: .modelWeights, ownerLabel: arm, access: .sharedReadOnly,
                storage: .confirmed("weights-\(arm)")),
            modelContentSHA256: String(repeating: "a", count: 64),
            tokenizerData: OwnedResource(
                role: .tokenizerData, ownerLabel: arm, access: .sharedReadOnly,
                storage: .indeterminate),
            tokenizerContentSHA256: String(repeating: "b", count: 64),
            kvCache: resource(.kvCache, id: "kv-\(arm)", arm: arm),
            prefixCache: resource(.prefixCache, id: "prefix-\(arm)", arm: arm),
            runtimeScratch: resource(.runtimeScratch, id: "scratch-\(arm)", arm: arm),
            mutableResources: [resource(.extraMutable, id: "extra-\(arm)", arm: arm)],
            writeRoot: writeRoot)
    }

    private func execution(
        _ owner: G3ArmResourceOwner, _ executor: LedgerExecutor
    ) throws -> G3ArmExecution<LedgerExecutor> {
        G3ArmExecution(
            owner: owner, executor: executor, provider: Provider(),
            request: try AttestationRequest(
                runID: "axes-run", challengeNonce: "axes-nonce"),
            state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 1)
    }

    private func sessions() -> G3PerArmCacheSessionFactory {
        { armID, _ in
            G3ArmCacheSession(armID: armID.rawValue, boundary: Boundary())
        }
    }

    private func record(
        _ report: G3DualArmRunReport, _ armID: String
    ) throws -> G3ArmRunRecord {
        try XCTUnwrap(report.arms.first { $0.armID == armID })
    }

    // MARK: 1. A delivered run records all three axes

    func testDeliveredRunRecordsAllThreeAxes() async throws {
        let report = try await G3DualArmRunner.run(
            try execution(makeOwner("ES+IS", writeRoot: "/tmp/g3/axes/es"), LedgerExecutor(mode: .delivered)),
            try execution(makeOwner("IS-only", writeRoot: "/tmp/g3/axes/is"), LedgerExecutor(mode: .delivered)),
            makeCacheSession: sessions())

        for armID in ["ES+IS", "IS-only"] {
            let arm = try record(report, armID)
            XCTAssertTrue(arm.settled)
            XCTAssertTrue(arm.settleEntered)
            XCTAssertTrue(arm.bindingConsumed)
            XCTAssertTrue(arm.delivery.completed)
            XCTAssertEqual(arm.cancellation, .notCancelled)
            XCTAssertFalse(arm.terminal.isTerminated)
        }
        XCTAssertTrue(report.eachArmSettled)
        XCTAssertTrue(report.armTerminations.isEmpty)
    }

    // MARK: 2. A pre-settlement refusal leaves both axes false

    func testPreSettlementRefusalLeavesBothAxesNotEntered() async throws {
        let report = try await G3DualArmRunner.run(
            try execution(makeOwner("ES+IS", writeRoot: "/tmp/g3/axes/es"), LedgerExecutor(mode: .refusedBeforeSettlement)),
            try execution(makeOwner("IS-only", writeRoot: "/tmp/g3/axes/is"), LedgerExecutor(mode: .delivered)),
            makeCacheSession: sessions())

        let es = try record(report, "ES+IS")
        XCTAssertFalse(es.settled)
        XCTAssertFalse(es.settleEntered)
        XCTAssertFalse(es.bindingConsumed)
        XCTAssertEqual(es.delivery.generation.state, .failed)
        XCTAssertEqual(es.delivery.commit.state, .notEntered)
        XCTAssertEqual(es.cancellation, .notCancelled)

        let peer = try record(report, "IS-only")
        XCTAssertTrue(peer.settled, "the peer arm is unaffected")
        XCTAssertFalse(report.eachArmSettled)
    }

    // MARK: 3. Post-settlement cancellation: consumed, but not a settled delivery

    func testPostSettlementCancellationKeepsConsumedAxisVisible() async throws {
        let report = try await G3DualArmRunner.run(
            try execution(makeOwner("ES+IS", writeRoot: "/tmp/g3/axes/es"), LedgerExecutor(mode: .consumedThenCancelled)),
            try execution(makeOwner("IS-only", writeRoot: "/tmp/g3/axes/is"), LedgerExecutor(mode: .delivered)),
            makeCacheSession: sessions())

        let es = try record(report, "ES+IS")
        XCTAssertFalse(es.settled)
        XCTAssertTrue(es.settleEntered, "the gate was entered before the cancellation")
        XCTAssertTrue(es.bindingConsumed, "the cancellation cannot undo the consume")
        XCTAssertEqual(es.cancellation, .afterSettlement)
        XCTAssertEqual(es.delivery.commit.state, .failed)
        XCTAssertFalse(es.delivery.completed)
        XCTAssertFalse(report.eachArmSettled)
    }

    // MARK: 4. G5: an independent gateway latch is its own reported source

    func testGatewayOnlyTerminationIsReportedSeparatelyFromTheTombstone() async throws {
        let report = try await G3DualArmRunner.run(
            try execution(makeOwner("ES+IS", writeRoot: "/tmp/g3/axes/es"), LedgerExecutor(mode: .deliveredThenGatewayLatch)),
            try execution(makeOwner("IS-only", writeRoot: "/tmp/g3/axes/is"), LedgerExecutor(mode: .delivered)),
            makeCacheSession: sessions())

        XCTAssertEqual(report.gatewayTerminations["ES+IS"], "gateway_stop")
        XCTAssertNil(
            report.sessionTombstones["ES+IS"],
            "the session never wrote a tombstone; only the gateway latch fired")
        XCTAssertEqual(report.armTerminations["ES+IS"], "gateway_stop")

        let es = try record(report, "ES+IS")
        XCTAssertEqual(es.terminal.gatewayTerminationReason, "gateway_stop")
        XCTAssertNil(es.terminal.sessionTombstoneReason)
        XCTAssertFalse(es.settled, "a post-settlement termination stops delivery")
        XCTAssertTrue(es.bindingConsumed, "but it does not undo the consume")

        let peer = try record(report, "IS-only")
        XCTAssertTrue(peer.settled)
        XCTAssertFalse(report.eachArmSettled)
    }
}
