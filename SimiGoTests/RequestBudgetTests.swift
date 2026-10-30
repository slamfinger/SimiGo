import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

// MARK: - Controller (pure decision logic)

/// W4/A 判定核心：事实 → 决策这一层必须可以在没有模型、没有 HTTP 的情况下
/// 逐条核对。owner 验收 (2) 要求冷/热分桶、样本不足与估算失败有可观测行为、
/// 且不得伪造读数——这里直接断言 `RequestBudgetVerdict` 的每个出口。
///
/// Runs only with the three isolated roots injected, for the same reason as the
/// HTTP suites: the controller persists calibration records under
/// `SimiGoPaths.managedRoot()` and must never write the real user state.
final class RequestBudgetControllerTests: XCTestCase {

    override func setUpWithError() throws {
        try requireIsolatedRoots()
        RequestBudgetController.shared.resetForTesting()
        // A leftover calibration record from an earlier case would turn
        // "no matched samples" into a phantom sample set.
        try? FileManager.default.removeItem(at: RequestBudgetController.calibrationURL)
    }

    override func tearDown() {
        RequestBudgetController.shared.resetForTesting()
        super.tearDown()
    }

    private func requireIsolatedRoots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py")
        }
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(
                URL(fileURLWithPath: home, isDirectory: true).path),
            "authoritative store resolves outside the isolation root")
    }

    /// Every case gets its own identity: samples recorded by one case can never
    /// make the next case look calibrated.
    private func makeIdentity(_ tag: String = UUID().uuidString) -> RequestBudgetIdentity {
        RequestBudgetIdentity(
            model: "model-\(tag)",
            tokenizer: "tokenizer-\(tag)",
            template: "thinking=disabled")
    }

    /// 250 tok/s in both the sample and the observation cases, so the numbers
    /// below stay checkable by hand.
    ///
    /// Seeded through the calibration channel: that is the exact shape §6
    /// calibration hands the gate after a restart, and it does not write to
    /// disk. `prepare()` runs first so the one-time calibration load cannot
    /// overwrite the seeds with whatever an earlier case left behind.
    private func seedSamples(
        _ identity: RequestBudgetIdentity,
        bucket: String = "cold",
        count: Int,
        tokens: Int = 2_000,
        seconds: Double = 8
    ) {
        RequestBudgetController.shared.prepare()
        for index in 0..<count {
            RequestBudgetController.shared.recordCalibrationSampleForTesting(
                identity: identity, bucket: bucket,
                tokens: tokens, seconds: seconds,
                at: Date().addingTimeInterval(-Double(index)))
        }
    }

    private func decide(
        _ identity: RequestBudgetIdentity,
        bucket: String = "cold",
        tokens: Int,
        digest: String = "digest-\(UUID().uuidString)",
        budgetMs: Int = 60_000,
        maxTokens: Int = 4_096,
        memoryMatchedTokens: Int = 0
    ) -> RequestBudgetVerdict {
        RequestBudgetController.shared.decide(
            identity: identity, bucket: bucket, promptDigest: digest,
            tokens: tokens, budgetMs: budgetMs, maxTokens: maxTokens,
            memoryMatchedTokens: memoryMatchedTokens)
    }

    // MARK: Budget math

    func testPrefillBudgetReserveIsBoundedOnBothSides() {
        // max_tokens is an upper bound, not a duration: an unbounded reserve
        // would refuse every ordinary request.
        XCTAssertEqual(
            RequestBudgetController.prefillBudgetMs(budgetMs: 60_000, maxTokens: 0),
            55_000, "floor reserve is 5 s")
        XCTAssertEqual(
            RequestBudgetController.prefillBudgetMs(budgetMs: 60_000, maxTokens: 200),
            50_000, "a small generation reserve scales with max_tokens")
        XCTAssertEqual(
            RequestBudgetController.prefillBudgetMs(budgetMs: 60_000, maxTokens: 100_000),
            45_000, "the reserve is capped at 15 s")
        XCTAssertEqual(
            RequestBudgetController.prefillBudgetMs(budgetMs: 3_000, maxTokens: 4_096),
            0, "a budget smaller than the reserve leaves no prefill room")
    }

    func testP10TakesTheSlowestOfTheRecentWindow() {
        XCTAssertEqual(RequestBudgetController.p10([100, 200, 300, 400]), 100)
        XCTAssertEqual(RequestBudgetController.p10([50]), 50)
        XCTAssertEqual(RequestBudgetController.p10([]), 0)
    }

    // MARK: Inactive outcomes are never reported as refusals

    func testNoMatchedSampleIsInactiveAndNeverARefusal() {
        let verdict = decide(makeIdentity(), tokens: 40_363)
        XCTAssertEqual(verdict.kind, .insufficientSamples)
        XCTAssertFalse(verdict.isReject, "sample scarcity must never refuse a turn")
        XCTAssertFalse(verdict.gateWasActive)
        XCTAssertEqual(verdict.samples, 0)
        XCTAssertNil(verdict.rateTokPerSecond, "no fabricated rate")
        XCTAssertEqual(verdict.estimatedPrefillMs, 0, "no fabricated estimate")
    }

    func testExplicitZeroBudgetIsDisabledNotARefusal() {
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let verdict = decide(identity, tokens: 40_363, budgetMs: 0)
        XCTAssertEqual(verdict.kind, .disabled)
        XCTAssertFalse(verdict.isReject)
        XCTAssertFalse(verdict.gateWasActive)
    }

    func testEmptyDigestIsInactive() {
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let verdict = decide(identity, tokens: 40_363, digest: "")
        XCTAssertEqual(verdict.kind, .emptyTranscript)
        XCTAssertFalse(verdict.isReject)
    }

    // MARK: Cold / hot isolation

    func testColdSamplesNeverProjectAHotPrefill() {
        let identity = makeIdentity()
        seedSamples(identity, bucket: "cold", count: 3) // 250 tok/s
        let verdict = decide(identity, bucket: "hot", tokens: 200_000)
        XCTAssertEqual(
            verdict.kind, .insufficientSamples,
            "a cold full-prefill rate must not estimate a hot delta")
        XCTAssertFalse(verdict.isReject)
    }

    func testSamplesRequireAllThreeIdentityComponents() {
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let otherTemplate = RequestBudgetIdentity(
            model: identity.model,
            tokenizer: identity.tokenizer,
            template: "thinking=enabled")
        XCTAssertEqual(
            decide(otherTemplate, tokens: 40_363).kind, .insufficientSamples,
            "a template mismatch must not borrow the other template's rate")

        let otherTokenizer = RequestBudgetIdentity(
            model: identity.model,
            tokenizer: identity.tokenizer + "-other",
            template: identity.template)
        XCTAssertEqual(
            decide(otherTokenizer, tokens: 40_363).kind, .insufficientSamples,
            "a tokenizer mismatch must not borrow the other tokenizer's rate")
    }

    // MARK: Rate-based decision

    func testMatchedSamplesRejectAnOverBudgetRender() {
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let verdict = decide(identity, tokens: 40_363)
        XCTAssertEqual(verdict.kind, .rejectEstimated)
        XCTAssertTrue(verdict.isReject)
        XCTAssertTrue(verdict.gateWasActive)
        XCTAssertEqual(verdict.samples, 3)
        XCTAssertEqual(verdict.rateTokPerSecond ?? 0, 250, accuracy: 0.001)
        XCTAssertEqual(verdict.prefillBudgetMs, 45_000)
        // 40363 / 250 * 1.25 = 201.8 s
        XCTAssertEqual(verdict.estimatedPrefillMs, 201_815)
        XCTAssertGreaterThan(verdict.estimatedPrefillMs, verdict.prefillBudgetMs)
    }

    func testFewSamplesCarryThePessimisticMargin() {
        // 8 000 tok at 250 tok/s is 32 s: inside the 45 s prefill budget at the
        // steady 1.25 margin (40 s) and outside it at the few-sample 1.5
        // margin (48 s).
        let few = makeIdentity()
        seedSamples(few, count: 1)
        let fewVerdict = decide(few, tokens: 8_000)
        XCTAssertEqual(fewVerdict.kind, .rejectEstimated)
        XCTAssertEqual(fewVerdict.samples, 1)
        XCTAssertEqual(fewVerdict.estimatedPrefillMs, 48_000)

        let steady = makeIdentity()
        seedSamples(steady, count: 3)
        let steadyVerdict = decide(steady, tokens: 8_000)
        XCTAssertEqual(steadyVerdict.kind, .admitWithinBudget)
        XCTAssertEqual(steadyVerdict.estimatedPrefillMs, 40_000)
        XCTAssertFalse(steadyVerdict.isReject)
    }

    func testRepeatedRejectIsServedFromTheTTLCache() {
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let first = decide(identity, tokens: 40_363, digest: "payload-a")
        XCTAssertEqual(first.kind, .rejectEstimated)
        XCTAssertFalse(first.cached)

        let second = decide(identity, tokens: 40_363, digest: "payload-a")
        XCTAssertEqual(second.kind, .rejectEstimated)
        XCTAssertTrue(
            second.cached,
            "the same over-budget payload must not redo render + estimate")
        XCTAssertEqual(second.estimatedPrefillMs, first.estimatedPrefillMs)

        let differentPayload = decide(identity, tokens: 30_000, digest: "payload-b")
        XCTAssertFalse(
            differentPayload.cached, "a different payload is decided, not cached")
    }

    // MARK: #138 — stale refusals are re-decided when the evidence changes

    /// The refusal cache may only replay a verdict while the evidence it was
    /// derived from still stands. A completed attempt that now proves the
    /// payload fits must invalidate the stored refusal immediately, not wait
    /// out the fixed TTL while legitimate retries keep getting 503.
    func testNewObservationInvalidatesTheCachedReject() {
        let controller = RequestBudgetController.shared
        let identity = makeIdentity()
        seedSamples(identity, count: 3) // 250 tok/s
        let digest = "payload-fresh-evidence"
        let first = decide(identity, tokens: 40_363, digest: digest)
        XCTAssertEqual(first.kind, .rejectEstimated)
        XCTAssertFalse(first.cached)
        XCTAssertTrue(decide(identity, tokens: 40_363, digest: digest).cached)

        // Same payload, measured at ~2 000 tok/s: inside the 45 s budget.
        controller.recordObservedAttempt(
            identity: identity, bucket: "cold", promptDigest: digest,
            processed: 40_363, total: 40_363, elapsed: 20,
            requestID: "req-fresh-evidence", completed: true)

        let redecided = decide(identity, tokens: 40_363, digest: digest)
        XCTAssertFalse(
            redecided.cached,
            "a refusal computed before this observation must not be replayed")
        XCTAssertEqual(redecided.kind, .admitPriorAttempt)
        XCTAssertFalse(redecided.isReject)
        XCTAssertEqual(redecided.priorRequestID, "req-fresh-evidence")

        XCTAssertEqual(
            decide(identity, tokens: 40_363, digest: digest).kind, .admitPriorAttempt,
            "the admission follows from the observation, not the old refusal")
    }

    /// A new rate sample also changes the evidence: the stored refusal is
    /// re-derived rather than served for the rest of its TTL.
    func testNewRateSampleInvalidatesTheCachedReject() {
        let controller = RequestBudgetController.shared
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let digest = "payload-sample-evidence"
        XCTAssertEqual(decide(identity, tokens: 40_363, digest: digest).kind, .rejectEstimated)
        XCTAssertTrue(decide(identity, tokens: 40_363, digest: digest).cached)

        controller.recordPrefillSample(
            identity: identity, bucket: "cold", tokens: 1_000, seconds: 2,
            source: "engine")

        let redecided = decide(identity, tokens: 40_363, digest: digest)
        XCTAssertFalse(redecided.cached, "new rate evidence invalidates the refusal")
        // P10 still takes the slowest sample in the window, so the verdict
        // itself stays a refusal — but it is freshly derived, not frozen.
        XCTAssertEqual(redecided.kind, .rejectEstimated)
        XCTAssertTrue(
            decide(identity, tokens: 40_363, digest: digest).cached,
            "the re-derived refusal is cached on the new evidence")
    }

    /// The generation reserve depends on `max_tokens`, so the prefill budget a
    /// refusal was measured against does too. A refusal computed for a
    /// long-generation request must not suppress a short-generation retry of
    /// the same payload, which has more prefill room.
    func testRefusalCacheDistinguishesTheGenerationReserve() {
        let identity = makeIdentity()
        seedSamples(identity, count: 1) // 250 tok/s, few-sample margin 1.5
        let digest = "payload-reserve"
        // 8 000 tok at 250 tok/s × 1.5 = 48 s.
        let longGeneration = decide(
            identity, tokens: 8_000, digest: digest, maxTokens: 4_096)
        XCTAssertEqual(longGeneration.kind, .rejectEstimated)
        XCTAssertEqual(longGeneration.prefillBudgetMs, 45_000)
        XCTAssertTrue(
            decide(identity, tokens: 8_000, digest: digest, maxTokens: 4_096).cached)

        let shortGeneration = decide(
            identity, tokens: 8_000, digest: digest, maxTokens: 200)
        XCTAssertFalse(
            shortGeneration.cached,
            "a different generation reserve is a different budget question")
        XCTAssertEqual(shortGeneration.prefillBudgetMs, 50_000)
        XCTAssertEqual(shortGeneration.kind, .admitWithinBudget)
    }

    // MARK: #138 — post-load warm-up is not throughput evidence

    /// The first completed prefill after a load pays kernel compilation and
    /// weight residency; it is consumed once and never measured. A resume
    /// starts a new cycle.
    func testPostLoadWarmupIsConsumedOncePerLoad() {
        var tracker = PostLoadWarmupTracker()
        XCTAssertTrue(tracker.isWarmupTurn)
        XCTAssertTrue(
            tracker.consumeCompletedPrefill(),
            "the first completed prefill after a load is the warm-up turn")
        XCTAssertFalse(
            tracker.consumeCompletedPrefill(),
            "only one turn per load is exempt")
        XCTAssertFalse(tracker.isWarmupTurn)

        tracker.modelLoaded()
        XCTAssertTrue(tracker.isWarmupTurn, "a resume starts a new warm-up cycle")
        XCTAssertTrue(tracker.consumeCompletedPrefill())
    }

    // MARK: Prior attempts on the exact same payload

    func testIncompleteAttemptProjectsFromMeasuredProgress() {
        let controller = RequestBudgetController.shared
        let identity = makeIdentity()
        controller.recordObservedAttempt(
            identity: identity, bucket: "cold", promptDigest: "payload-cancel",
            processed: 4_000, total: 40_000, elapsed: 20,
            requestID: "req-prior-1", completed: false)

        let verdict = decide(identity, tokens: 40_000, digest: "payload-cancel")
        XCTAssertEqual(verdict.kind, .rejectPriorAttempt)
        XCTAssertTrue(verdict.isReject)
        XCTAssertEqual(verdict.priorProcessed, 4_000)
        XCTAssertEqual(verdict.priorTotal, 40_000)
        XCTAssertEqual(verdict.priorElapsedMs, 20_000)
        XCTAssertEqual(verdict.priorRequestID, "req-prior-1")
        // 20 s for 4000/40000 ⇒ 200 s for the full prefill.
        XCTAssertEqual(verdict.estimatedPrefillMs, 200_000)
        XCTAssertEqual(verdict.rateTokPerSecond ?? 0, 200, accuracy: 0.001)

        XCTAssertTrue(
            decide(identity, tokens: 40_000, digest: "payload-cancel").cached,
            "the repeat is refused from the cache, not re-derived")
    }

    func testObservationIsScopedToTheBucketThatProducedIt() {
        let controller = RequestBudgetController.shared
        let identity = makeIdentity()
        controller.recordObservedAttempt(
            identity: identity, bucket: "hot", promptDigest: "payload-d",
            processed: 1_000, total: 40_000, elapsed: 20,
            requestID: "req-hot", completed: false)
        let cold = decide(identity, bucket: "cold", tokens: 40_000, digest: "payload-d")
        XCTAssertEqual(
            cold.kind, .insufficientSamples,
            "a hot delta observation must not condemn a cold prefill")
    }

    func testObservationIsScopedToItsIdentity() {
        let controller = RequestBudgetController.shared
        let identity = makeIdentity()
        let other = makeIdentity()
        controller.recordObservedAttempt(
            identity: identity, bucket: "cold", promptDigest: "payload-e",
            processed: 1_000, total: 40_000, elapsed: 20,
            requestID: "req-other", completed: false)
        let verdict = decide(other, tokens: 40_000, digest: "payload-e")
        XCTAssertEqual(verdict.kind, .insufficientSamples)
    }

    func testCompletedObservationInsideBudgetAdmits() {
        let controller = RequestBudgetController.shared
        let identity = makeIdentity()
        controller.recordObservedAttempt(
            identity: identity, bucket: "cold", promptDigest: "payload-f",
            processed: 2_000, total: 2_000, elapsed: 4,
            requestID: "req-done", completed: true)
        let verdict = decide(identity, tokens: 2_000, digest: "payload-f")
        XCTAssertEqual(verdict.kind, .admitPriorAttempt)
        XCTAssertTrue(verdict.gateWasActive)
        XCTAssertFalse(verdict.isReject)
        // 2000 tok at 500 tok/s × 1.25 = 5 s
        XCTAssertEqual(verdict.estimatedPrefillMs, 5_000)
    }

    // MARK: #136/W4 — the memory-pool credit is the only thing that shortens an estimate

    /// The loop the owner asked for: a first long prefill gets cancelled mid-way,
    /// the retry would run the SAME payload. Without the credit the prior
    /// attempt's full projection condemns every retry forever; with a boundary
    /// the pool proved, only the remaining tokens are priced.
    func testProvenMemoryBoundaryTurnsADoomedRetryIntoAnAdmit() {
        let controller = RequestBudgetController.shared
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        controller.recordObservedAttempt(
            identity: identity, bucket: "cold", promptDigest: "payload-credit",
            processed: 4_000, total: 40_000, elapsed: 20,
            requestID: "req-cancelled", completed: false)

        let cold = decide(identity, tokens: 40_000, digest: "payload-credit")
        XCTAssertEqual(cold.kind, .rejectPriorAttempt)
        XCTAssertEqual(cold.memoryMatchedTokens, 0)
        XCTAssertEqual(cold.estimatedPrefillMs, 200_000)

        let credited = decide(
            identity, tokens: 40_000, digest: "payload-credit",
            memoryMatchedTokens: 36_000)
        XCTAssertEqual(
            credited.kind, .admitWithinBudget,
            "36k proven tokens are not work this turn pays again")
        XCTAssertFalse(
            credited.cached,
            "a refusal computed with no credit must not suppress the credited decision")
        XCTAssertEqual(credited.memoryMatchedTokens, 36_000)
        XCTAssertEqual(credited.promptTokens, 40_000, "the verdict reports the counted base")
        // 4000 remaining at the observed 200 tok/s ⇒ 20 s.
        XCTAssertEqual(credited.estimatedPrefillMs, 20_000)
    }

    /// Narrow scope, not a blanket pass: a credit that leaves the remaining work
    /// over budget is still refused, and an unproven (too small) credit is
    /// treated on its own numbers instead of inheriting the cold refusal.
    func testSmallCreditStillRefusesOnItsOwnNumbers() {
        let controller = RequestBudgetController.shared
        let identity = makeIdentity()
        controller.recordObservedAttempt(
            identity: identity, bucket: "cold", promptDigest: "payload-partial",
            processed: 4_000, total: 40_000, elapsed: 20,
            requestID: "req-cancelled-2", completed: false)

        let verdict = decide(
            identity, tokens: 40_000, digest: "payload-partial",
            memoryMatchedTokens: 1_000)
        XCTAssertEqual(verdict.kind, .rejectPriorAttempt)
        XCTAssertTrue(verdict.isReject)
        XCTAssertFalse(verdict.cached)
        XCTAssertEqual(verdict.memoryMatchedTokens, 1_000)
        // 39000 remaining at the observed 200 tok/s ⇒ 195 s.
        XCTAssertEqual(verdict.estimatedPrefillMs, 195_000)
    }

    /// A credit can never claim the whole prompt: at least one token is always
    /// priced as work, so the gate cannot be walked through by an over-wide
    /// match coming from a caller bug.
    func testCreditIsCappedBelowTheWholePrompt() {
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let verdict = decide(
            identity, tokens: 1_000, digest: "payload-cap",
            memoryMatchedTokens: 5_000)
        XCTAssertEqual(verdict.memoryMatchedTokens, 999)
        XCTAssertEqual(verdict.kind, .admitWithinBudget)
        XCTAssertGreaterThan(verdict.estimatedPrefillMs, 0, "no zero-work pass")
        let negative = decide(
            identity, tokens: 1_000, digest: "payload-negative",
            memoryMatchedTokens: -700)
        XCTAssertEqual(negative.memoryMatchedTokens, 0, "a negative credit is not a bonus")
        XCTAssertEqual(negative.estimatedPrefillMs, 5_000, "1000 tok at 250 tok/s × 1.25")
    }

    /// The refusal cache keeps the credit it was computed with, in both
    /// directions: keyed separately per credit, and the field survives the
    /// cached round-trip that the `[BUDGET] memMatched=` trace reads.
    func testCachedRejectIsKeyedByAndCarriesItsCredit() {
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let cold = decide(identity, tokens: 40_363, digest: "payload-keyed")
        XCTAssertEqual(cold.kind, .rejectEstimated)
        XCTAssertEqual(cold.memoryMatchedTokens, 0)

        let credited = decide(
            identity, tokens: 40_363, digest: "payload-keyed",
            memoryMatchedTokens: 3_000)
        XCTAssertFalse(credited.cached, "different credit, different key")
        XCTAssertEqual(credited.memoryMatchedTokens, 3_000)
        XCTAssertLessThan(
            credited.estimatedPrefillMs, cold.estimatedPrefillMs,
            "the priced work is 37 363 tokens, not 40 363")
        XCTAssertTrue(credited.isReject, "a small credit must not become a pass")

        let repeatCredited = decide(
            identity, tokens: 40_363, digest: "payload-keyed",
            memoryMatchedTokens: 3_000)
        XCTAssertTrue(repeatCredited.cached)
        XCTAssertEqual(repeatCredited.memoryMatchedTokens, 3_000)
        XCTAssertEqual(repeatCredited.estimatedPrefillMs, credited.estimatedPrefillMs)
    }

    /// Zero credit must reproduce the pre-#136 numbers exactly — the fix is
    /// invisible unless the pool actually proves a boundary.
    func testNoCreditLeavesEveryEstimateUnchanged() {
        let identity = makeIdentity()
        seedSamples(identity, count: 3)
        let withDefault = decide(identity, tokens: 12_000, digest: "payload-zero-a")
        let withZero = decide(
            identity, tokens: 12_000, digest: "payload-zero-b", memoryMatchedTokens: 0)
        XCTAssertEqual(withDefault.kind, .rejectEstimated)
        XCTAssertEqual(withDefault.estimatedPrefillMs, withZero.estimatedPrefillMs)
        XCTAssertEqual(withDefault.memoryMatchedTokens, 0)
    }

    // MARK: Digest

    func testDigestBindsTheModelAndToleratesAnEmptyTokenRange() {
        let emptyA = RequestBudgetDigest.of(tokens: [], model: "model-a")
        let emptyB = RequestBudgetDigest.of(tokens: [], model: "model-b")
        XCTAssertEqual(emptyA.count, 64)
        XCTAssertNotEqual(emptyA, emptyB, "the digest binds the model identity")
        XCTAssertNotEqual(emptyA, RequestBudgetDigest.of(tokens: [1, 2, 3], model: "model-a"))
    }
}

// MARK: - HTTP gate

/// W4/A 验收 (3)(4)(5) 的历史契约：门发生在「IS 注入之后、任何 SSE 流头与
/// 模型生成启动之前」。ADR 2026-10-30 撤销了这条路线：判定位置与输入不变，
/// 但拒绝出口不再执行（503 不再出现），因此本套件断言的是「判定仍被取得、
/// 请求照常准入」。
///
/// The budget handler is injected: this suite proves the protocol-layer contract
/// (where the verdict is taken, that enforcement is off, what the turn looks
/// like). The rendered-prompt counting itself is the runtime's job and is
/// covered by the controller tests above.
final class RequestBudgetGateHTTPTests: XCTestCase {

    private let port = 59_380

    private var isolationRoot: URL!
    private var modelPath: String!
    private var host: LOCALBAuthorizedE2E.Host!
    private var stub: Stub!
    private var gate: Gate!

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        nonisolated(unsafe) var text = "BUDGET-GATE-OK"
        func bump() { lock.withLock { _generate += 1 } }
        var generate: Int { lock.withLock { _generate } }
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var _reject: Bool
        private var _budgetHeaders: [Int?] = []
        private var _promptSizes: [Int] = []

        init(reject: Bool) { _reject = reject }

        var reject: Bool {
            get { lock.withLock { _reject } }
            set { lock.withLock { _reject = newValue } }
        }
        var calls: Int { lock.withLock { _budgetHeaders.count } }
        var budgetHeaders: [Int?] { lock.withLock { _budgetHeaders } }
        var promptSizes: [Int] { lock.withLock { _promptSizes } }

        func handler() -> HTTPServer.RequestBudgetHandler {
            { [self] _, _, _, _, messages, _, _, budgetHeaderMs in
                lock.withLock {
                    _budgetHeaders.append(budgetHeaderMs)
                    _promptSizes.append(messages.count)
                }
                let reject = lock.withLock { _reject }
                return RequestBudgetVerdict(
                    kind: reject ? .rejectEstimated : .admitWithinBudget,
                    promptTokens: 40_363,
                    estimatedPrefillMs: reject ? 201_815 : 30_000,
                    budgetMs: 60_000,
                    prefillBudgetMs: 45_000,
                    samples: 3,
                    bucket: "cold",
                    promptDigest: "gate-stub-digest",
                    rateTokPerSecond: 250,
                    priorProcessed: nil,
                    priorTotal: nil,
                    priorElapsedMs: nil,
                    priorRequestID: nil,
                    cached: false,
                    memoryMatchedTokens: 0)
            }
        }
    }

    private struct Outcome {
        let status: Int
        let raw: Data
        let headers: [AnyHashable: Any]
        let generate: Int

        var body: [String: Any] {
            (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
        }
        var error: [String: Any] { body["error"] as? [String: Any] ?? [:] }
        var sse: String { String(decoding: raw, as: UTF8.self) }
        var retryAfter: String? { headers["Retry-After"] as? String }
        var retryPolicy: String? { headers["X-Simigo-Retry-Policy"] as? String }
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "so no real model or user state is touched")
        }
        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoBudgetGate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"budget-gate-http-model-free-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        host = try LOCALBAuthorizedE2E.makeHost()
        let stub = Stub()
        self.stub = stub
        gate = Gate(reject: true)
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        stub = nil
        host = nil
        gate = nil
        super.tearDown()
    }

    // MARK: Server + real authorized requests

    @MainActor
    private func withServer(_ run: () async throws -> Void) async throws {
        let stub = stub!
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let server = HTTPServer(
            port: port,
            modelId: "budget-gate-http-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _ in
                stub.bump()
                onChunk(stub.text)
                return GenerationResult(text: stub.text, usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "budget-gate-http-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            informationTurnProducer: {
                InformationTurnProducer(
                    modelIdentity: identity.model, identity: identity)
            },
            requestBudget: gate.handler()
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer { server.stop() }
        try await run()
    }

    @MainActor
    private func dispatch(
        path: String,
        body: [String: Any],
        extraHeaders: [String: String] = [:]
    ) async throws -> Outcome {
        let stub = self.stub!
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        for _ in 0..<3 {
            do {
                let outcome = try await send(
                    path: path, payload: payload, extraHeaders: extraHeaders)
                return Outcome(
                    status: outcome.status, raw: outcome.data,
                    headers: outcome.headers, generate: stub.generate)
            } catch let error as URLError
            where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw XCTSkip(
            "authorized request never reached the server: \(String(describing: lastError))")
    }

    /// The shared helper signs (method, target, content type, body) and carries
    /// no extra headers, so a deadline-header case builds the same signed
    /// request with the extra header attached after signing.
    @MainActor
    private func send(
        path: String, payload: Data, extraHeaders: [String: String]
    ) async throws -> (status: Int, data: Data, headers: [AnyHashable: Any]) {
        let proof = try await LOCALBAuthorizedE2E.proofHeaders(
            host: host, port: port, method: "POST", target: path,
            contentType: "application/json", body: payload)
        var request = URLRequest(
            url: URL(string: "https://127.0.0.1:\(port)\(path)")!,
            timeoutInterval: 900)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in proof {
            request.setValue(value, forHTTPHeaderField: name)
        }
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = payload
        let (data, response) = try await host.session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http.statusCode, data, http.allHeaderFields)
    }

    private func chatBody(
        session: String, input: String, stream: Bool
    ) -> [String: Any] {
        [
            "model": "budget-gate-http-test",
            "messages": [["role": "user", "content": input]],
            "session_id": session,
            "stream": stream,
        ]
    }

    private func completionBody(
        session: String, prompt: String, stream: Bool
    ) -> [String: Any] {
        [
            "model": "budget-gate-http-test",
            "prompt": prompt,
            "session_id": session,
            "stream": stream,
        ]
    }

    private func responsesBody(
        session: String, input: String, stream: Bool
    ) -> [String: Any] {
        [
            "model": "budget-gate-http-test",
            "input": input,
            "session_id": session,
            "stream": stream,
        ]
    }

    // MARK: Observation-only admission (ADR 2026-10-30)

    // The verdict is still taken at the same place (after IS injection, before
    // any SSE head or model work) with the same inputs, but admission no longer
    // consults it: `RequestBudgetController.admissionEnforcementEnabled` is
    // false, so a reject verdict is an observation, never a 503.

    @MainActor
    func testStreamingChatRejectVerdictIsObservedAndAdmitted() async throws {
        try await withServer {
            let outcome = try await dispatch(
                path: "/v1/chat/completions",
                body: chatBody(
                    session: "budget-observed-stream-\(UUID().uuidString)",
                    input: "冷预填任务",
                    stream: true))

            XCTAssertEqual(outcome.status, 200, outcome.sse)
            XCTAssertEqual(
                outcome.generate, 1,
                "a reject verdict no longer stops the model work")
            XCTAssertTrue(outcome.sse.contains(stub.text))
            XCTAssertNotEqual(
                outcome.error["code"] as? String, "prefill_budget_exceeded")
            XCTAssertNil(outcome.retryAfter)
            XCTAssertEqual(gate.calls, 1)
            XCTAssertEqual(
                gate.promptSizes.first, 1,
                "the gate still sees the prepared turn's messages")
        }
    }

    @MainActor
    func testNonStreamingChatRejectVerdictIsAdmitted() async throws {
        try await withServer {
            let outcome = try await dispatch(
                path: "/v1/chat/completions",
                body: chatBody(
                    session: "budget-observed-json-\(UUID().uuidString)",
                    input: "冷预填任务",
                    stream: false))
            XCTAssertEqual(outcome.status, 200)
            XCTAssertEqual(outcome.generate, 1)
            XCTAssertNotEqual(
                outcome.error["code"] as? String, "prefill_budget_exceeded")
        }
    }

    @MainActor
    func testCompletionsRejectVerdictIsAdmittedOnBothWireForms() async throws {
        try await withServer {
            for stream in [true, false] {
                let outcome = try await dispatch(
                    path: "/v1/completions",
                    body: completionBody(
                        session: "budget-observed-completions-\(UUID().uuidString)",
                        prompt: "continue this text",
                        stream: stream))
                XCTAssertEqual(outcome.status, 200, "stream=\(stream) \(outcome.sse)")
                XCTAssertTrue(
                    outcome.sse.contains(stub.text), "stream=\(stream)")
                XCTAssertNotEqual(
                    outcome.error["code"] as? String, "prefill_budget_exceeded",
                    "stream=\(stream)")
            }
        }
    }

    /// The streaming Responses path still takes its verdict ABOVE the SSE head,
    /// which now only records the estimate: the turn proceeds as an ordinary
    /// 200 SSE response.
    @MainActor
    func testStreamingResponsesRejectVerdictIsAdmittedBeforeTheSSEHead() async throws {
        try await withServer {
            let outcome = try await dispatch(
                path: "/v1/responses",
                body: responsesBody(
                    session: "budget-observed-responses-\(UUID().uuidString)",
                    input: "冷预填任务",
                    stream: true))
            XCTAssertEqual(outcome.status, 200, outcome.sse)
            XCTAssertEqual(outcome.generate, 1, "the turn runs")
            XCTAssertTrue(outcome.sse.contains("data:"))
            XCTAssertTrue(outcome.sse.contains(stub.text))
            XCTAssertNotEqual(
                outcome.error["code"] as? String, "prefill_budget_exceeded")
            XCTAssertEqual(gate.calls, 1)
        }
    }

    @MainActor
    func testNonStreamingResponsesRejectVerdictIsAdmitted() async throws {
        try await withServer {
            let outcome = try await dispatch(
                path: "/v1/responses",
                body: responsesBody(
                    session: "budget-observed-responses-json-\(UUID().uuidString)",
                    input: "冷预填任务",
                    stream: false))
            XCTAssertEqual(outcome.status, 200)
            XCTAssertEqual(outcome.generate, 1)
            XCTAssertNotEqual(
                outcome.error["code"] as? String, "prefill_budget_exceeded")
        }
    }

    // MARK: Admission is still the ordinary path

    @MainActor
    func testAdmittedVerdictRunsTheTurnUnchanged() async throws {
        gate.reject = false
        try await withServer {
            let outcome = try await dispatch(
                path: "/v1/chat/completions",
                body: chatBody(
                    session: "budget-admit-\(UUID().uuidString)",
                    input: "普通请求",
                    stream: true))
            XCTAssertEqual(outcome.status, 200, outcome.sse)
            XCTAssertEqual(outcome.generate, 1)
            XCTAssertTrue(outcome.sse.contains(stub.text))
            XCTAssertEqual(gate.calls, 1)
        }
    }

    /// The reuse short-circuit sits BEFORE the budget gate: a settled answer is
    /// served with zero model calls and the gate is never consulted. Otherwise
    /// a cache hit could be refused for a prefill it will never run.
    @MainActor
    func testReusedAnswerNeverReachesTheBudgetGate() async throws {
        gate.reject = false
        let session = "budget-reuse-\(UUID().uuidString)"
        try await withServer {
            let first = try await dispatch(
                path: "/v1/chat/completions",
                body: chatBody(session: session, input: "where is the vault", stream: true))
            XCTAssertEqual(first.status, 200, first.sse)
            XCTAssertEqual(first.generate, 1)
            XCTAssertEqual(gate.calls, 1)

            gate.reject = true
            let second = try await dispatch(
                path: "/v1/chat/completions",
                body: chatBody(session: session, input: "where is the vault", stream: true))
            XCTAssertEqual(second.status, 200, second.sse)
            XCTAssertEqual(second.generate, 1, "the reuse serves without a model call")
            XCTAssertTrue(second.sse.contains(stub.text))
            XCTAssertEqual(
                gate.calls, 1,
                "the budget gate must not run for a turn that serves a reused answer")
        }
    }

    // MARK: Header plumbing

    func testDeadlineHeaderParsingAcceptsOnlyPositiveValues() {
        typealias Server = HTTPServer
        XCTAssertEqual(
            Server.requestBudgetDeadlineMS(
                headers: ["x-simigo-deadline-ms": "12345"]), 12_345)
        XCTAssertEqual(
            Server.requestBudgetDeadlineMS(
                headers: ["x-simigo-deadline-ms": "  777 "]), 777)
        XCTAssertNil(
            Server.requestBudgetDeadlineMS(headers: [:]),
            "a missing header falls back to the local setting; it never disables it")
        XCTAssertNil(
            Server.requestBudgetDeadlineMS(
                headers: ["x-simigo-deadline-ms": "0"]),
            "0 must not read as 'no budget'")
        XCTAssertNil(
            Server.requestBudgetDeadlineMS(
                headers: ["x-simigo-deadline-ms": "-5"]))
        XCTAssertNil(
            Server.requestBudgetDeadlineMS(
                headers: ["x-simigo-deadline-ms": "soon"]))
    }

    /// The LOCALB-authorized route rebuilds its header map from the signed
    /// request (`localbDispatchHeaders`), so an unsigned deadline header is
    /// dropped before any handler sees it. The gate is still consulted for
    /// observation (owner ruling Q1 header parsing), and the turn proceeds:
    /// the admission-rejection exit is offline (ADR 2026-10-30).
    @MainActor
    func testAuthorizedRouteDropsTheUnsignedDeadlineHeaderAndStillGoverns() async throws {
        try await withServer {
            let outcome = try await dispatch(
                path: "/v1/chat/completions",
                body: chatBody(
                    session: "budget-header-\(UUID().uuidString)",
                    input: "带预算头", stream: true),
                extraHeaders: ["X-Simigo-Deadline-Ms": "12345"])

            XCTAssertEqual(outcome.status, 200, outcome.sse)
            XCTAssertEqual(
                gate.budgetHeaders, [Int?.none],
                "an unsigned header cannot cross the signed-request boundary")
            XCTAssertEqual(
                gate.calls, 1,
                "the gate still ran: a missing header is not a disabled budget")
            XCTAssertEqual(outcome.generate, 1, "the turn is admitted")
            XCTAssertNotEqual(
                outcome.error["code"] as? String, "prefill_budget_exceeded")
        }
    }

    // MARK: Refusal write boundary

    /// Owner's write-boundary table predates the withdrawal of the
    /// admission-rejection exit (ADR 2026-10-30): with the gate in observe-only
    /// mode no turn can be refused, so this instrument only applies to a
    /// pre-ADR binary and is retired by default.
    @MainActor
    func testRejectAddsNoAnswerSideState() async throws {
        guard ProcessInfo.processInfo.environment["W4_MEASURE_ENFORCEMENT"] == "1" else {
            throw XCTSkip(
                "refusal write boundary retired: W4 admission rejection is offline "
                    + "(gate=withdrawn); set W4_MEASURE_ENFORCEMENT=1 only to replay "
                    + "this instrument against a pre-ADR binary")
        }
        try await withServer {
            let before = await ESISSweep.stable()
            let outcome = try await dispatch(
                path: "/v1/chat/completions",
                body: chatBody(
                    session: "budget-write-\(UUID().uuidString)",
                    input: "被拒绝的任务", stream: true))
            XCTAssertEqual(outcome.status, 503)
            let after = await ESISSweep.stable()

            XCTAssertEqual(
                ESISSweep.newAnswerSettlementIDs(before: before, after: after), [],
                "a refused turn settles nothing")
            XCTAssertEqual(
                ESISSweep.newAnswerBindingIDs(before: before, after: after), [],
                "a refused turn binds nothing")
            XCTAssertEqual(
                ESISSweep.newChatStateIDs(before: before, after: after), [],
                "a refused turn advances no chat state")
            XCTAssertTrue(
                ESISSweep.added("information_advancements", before: before, after: after)
                    .isEmpty,
                "a refused turn records no successful advancement")
            XCTAssertEqual(outcome.generate, 0)

            // Prepare-stage writes are allowed and recorded, not asserted away.
            let demands = ESISSweep.added(
                "information_demands", before: before, after: after)
            let rows = ESISSweep.added(
                "chat_messages", before: before, after: after)
            let removals = ESISSweep.removed(
                "information_demands", before: before, after: after)
            print(
                "[BUDGET-WRITE] prepare_demands=\(demands.count) "
                + "chat_messages=\(rows.count) demand_removals=\(removals.count)")
            XCTAssertTrue(
                removals.isEmpty,
                "a refusal never removes a demand prepare already wrote")
        }
    }
}
