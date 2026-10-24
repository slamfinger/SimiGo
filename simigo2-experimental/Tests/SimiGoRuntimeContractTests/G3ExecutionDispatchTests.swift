import XCTest
@testable import SimiGoRuntimeContract

// CONTROL-FLOW TESTS FOR THE G3 EXECUTION ROUTING FUNNEL.
//
// These prove that the gate is a checkpoint the *call path* must traverse, not
// just a method that exists:
//   * a `.g3` request enters ONLY the gate-protected method (never the ungated
//     `continueExecution`);
//   * a `.standard` request enters ONLY the ungated method (the gate is never
//     consulted, so unrelated inference is unaffected);
//   * with the shipping trust registry empty, a `.g3` request is refused BEFORE
//     generation and its generation-call count stays zero;
//   * a refused `.g3` request does NOT fall back to the standard path or a
//     fixture — the refusal propagates out of the dispatcher unchanged.
//
// The routing spy isolates the dispatch decision; the `G3IsolatedWorker` cases
// run the same gate control flow the production MLX executor uses (both conform
// to `G3RoutableContinuation`), still without loading a model.
final class G3ExecutionDispatchTests: XCTestCase {

    // MARK: Routing spy — records which method the funnel selects

    final class RoutingSpy: G3RoutableContinuation, @unchecked Sendable {
        typealias ContinuationResult = String
        var standardCalls = 0
        var gatedCalls = 0
        var gatedRefuses = false

        func continueExecution(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int
        ) async throws -> String {
            standardCalls += 1
            return "standard:\(nextInputTokens.count):\(maxTokens)"
        }
        func continueExecutionG3(
            _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int,
            provider: any RuntimeAttestationProvider, request: AttestationRequest
        ) async throws -> String {
            gatedCalls += 1
            if gatedRefuses {
                throw RuntimeAttestationError.unregisteredLiveProvider(provider.providerID)
            }
            return "gated:\(provider.providerID)"
        }
    }

    // An untrusted live-kind provider (registry is empty, so it cannot clear).
    struct UntrustedLiveProvider: RuntimeAttestationProvider {
        let providerID = "simigo.g3.dispatch-test.live"
        let providerKind: RuntimeProviderKind = .swiftMLXLiveWorker
        func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
    }

    func request() throws -> AttestationRequest {
        try AttestationRequest(runID: "dispatch-run", challengeNonce: "dispatch-nonce")
    }

    // MARK: Invariant 2 — `.standard` reaches only the ungated method

    func testStandardRouteCallsOnlyUngatedMethod() async throws {
        let spy = RoutingSpy()
        let result = try await G3ExecutionDispatch.run(
            spy, route: .standard, state: .g3RoutingPlaceholder,
            nextInputTokens: [1, 2, 3], maxTokens: 8)
        XCTAssertEqual(spy.standardCalls, 1)
        XCTAssertEqual(spy.gatedCalls, 0)               // gate never entered
        XCTAssertEqual(result, "standard:3:8")
    }

    // MARK: Invariant 1 — `.g3` reaches only the gate-protected method

    func testG3RouteCallsOnlyGatedMethod() async throws {
        let spy = RoutingSpy()
        let provider = UntrustedLiveProvider()
        let result = try await G3ExecutionDispatch.run(
            spy, route: .g3(provider: provider, request: request(), registrar: nil),
            state: .g3RoutingPlaceholder, nextInputTokens: [7], maxTokens: 4)
        XCTAssertEqual(spy.gatedCalls, 1)
        XCTAssertEqual(spy.standardCalls, 0)            // no drop to standard
        XCTAssertEqual(result, "gated:\(provider.providerID)")
    }

    // MARK: Invariant 3 — refused `.g3` propagates without fallback

    func testG3RoutePropagatesRefusalWithoutFallbackToStandard() async throws {
        let spy = RoutingSpy()
        spy.gatedRefuses = true
        let provider = UntrustedLiveProvider()
        do {
            _ = try await G3ExecutionDispatch.run(
                spy, route: .g3(provider: provider, request: request(), registrar: nil),
                state: .g3RoutingPlaceholder, nextInputTokens: [7], maxTokens: 4)
            XCTFail("expected the gate refusal to propagate")
        } catch is RuntimeAttestationError {
            // Expected: the dispatcher re-raised the gated method's error.
        }
        XCTAssertEqual(spy.gatedCalls, 1)
        XCTAssertEqual(spy.standardCalls, 0)            // NO fallback route taken
    }

    // MARK: Invariant 4 — real gated worker refuses before generation (empty registry)

    func testWorkerG3RouteRefusesBeforeGenerationWithEmptyRegistry() async throws {
        var generated = 0
        let worker = G3IsolatedWorker(generate: { generated += 1 })
        do {
            _ = try await G3ExecutionDispatch.run(
                worker, route: .g3(provider: UntrustedLiveProvider(), request: request(), registrar: nil),
                state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 1)
            XCTFail("expected refusal under the empty trust registry")
        } catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
            XCTAssertEqual(generated, 0)                        // forward never ran
            XCTAssertEqual(outcome.generationCallCount, 0)
            XCTAssertEqual(outcome.stage, "provider_trust")
            XCTAssertFalse(outcome.passed)
            XCTAssertFalse(outcome.isExecutionEvidence)
            XCTAssertEqual(outcome.trustedLiveProviderCount, 0)
        }
    }

    // MARK: Contrast — the same worker's `.standard` route is ungated (normal path intact)

    func testWorkerStandardRouteGeneratesUngatedWhileG3RouteRefuses() async throws {
        // Normal inference through the funnel: no gate consulted, generation runs.
        var standardGenerated = 0
        let w1 = G3IsolatedWorker(generate: { standardGenerated += 1 })
        let standard = try await G3ExecutionDispatch.run(
            w1, route: .standard, state: .g3RoutingPlaceholder,
            nextInputTokens: [], maxTokens: 0)
        XCTAssertEqual(standardGenerated, 1)                    // ungated
        XCTAssertEqual(standard.stage, "standard_ungated")
        XCTAssertFalse(standard.passed)                         // not a cleared gate
        XCTAssertFalse(standard.eligibleForRuntimeEvidence)

        // G3 inference through the same funnel: refused, zero generation.
        var g3Generated = 0
        let w2 = G3IsolatedWorker(generate: { g3Generated += 1 })
        do {
            _ = try await G3ExecutionDispatch.run(
                w2, route: .g3(provider: UntrustedLiveProvider(), request: request(), registrar: nil),
                state: .g3RoutingPlaceholder, nextInputTokens: [], maxTokens: 0)
            XCTFail("expected the .g3 route to refuse under the empty registry")
        } catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
            XCTAssertEqual(outcome.generationCallCount, 0)
        }
        XCTAssertEqual(g3Generated, 0)                          // gate refused first
    }

    // MARK: Placeholder handle carries no gate authority

    func testRoutingPlaceholderIsValidButDistinct() throws {
        XCTAssertEqual(ExecutionStateHandle.g3RoutingPlaceholder.id.rawValue,
                       "g3-routing-placeholder")
        XCTAssertNotEqual(ExecutionStateHandle.g3RoutingPlaceholder.id,
                          ExecutionID("real-state"))
    }

    // MARK: Invariant 5 — the allocation channel reaches the gated method

    func testRegistrarReachesGatedMethodButOnlyAfterTheGateClears() async throws {
        // Under the empty registry the gate refuses, so the worker's
        // during-generation step never runs: a refused arm cannot register an
        // allocation, and an admitted one must go through the sealed owner.
        var sawRegistrar = false
        var hookRan = false
        let worker = G3IsolatedWorker(
            generate: {},
            allocateDuringGeneration: { registrar in
                sawRegistrar = (registrar != nil)
                hookRan = true
            })
        do {
            _ = try await G3ExecutionDispatch.run(
                worker,
                route: .g3(provider: UntrustedLiveProvider(), request: request(), registrar: nil),
                state: .g3RoutingPlaceholder, nextInputTokens: [], maxTokens: 0)
            XCTFail("expected refusal under the empty trust registry")
        } catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
            XCTAssertEqual(outcome.generationCallCount, 0)
        }
        XCTAssertFalse(hookRan, "generation-time registration must not run on a refused gate")
        XCTAssertFalse(sawRegistrar)
    }

    // A conformer that only implements the gate-only form still routes: the
    // registrar-aware default forwards to it, so adding the registration channel
    // does not silently reroute or drop existing executors' behavior.
    func testRegistrarAwareDefaultFallsThroughToGateOnlyMethod() async throws {
        let spy = RoutingSpy()
        let result = try await G3ExecutionDispatch.run(
            spy,
            route: .g3(provider: UntrustedLiveProvider(), request: request(), registrar: nil),
            state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 2)
        XCTAssertEqual(spy.gatedCalls, 1)
        XCTAssertEqual(spy.standardCalls, 0)
        XCTAssertFalse(result.isEmpty)
    }
}
