import Foundation
import XCTest
import SimiGoRuntimeContract
import SimiGo2Experimental
import LOCALBCore

@testable import SimiGo

/// Model-free HTTP regression for the explicit CARRIER contract (source/target).
///
/// The bug this pins down: a settle-continuation used to pick its fork source
/// from the client's `logical_branch_id`. When that branch had been released the
/// request silently degraded to a cold rebuild and the 200 response looked
/// identical to a warm reuse.
///
/// Now three things are separate and asserted one by one:
///
///   * SOURCE  resolved from the verified parent ES row
///             (`verifiedCarrierBranchID`), never from the client's branch;
///   * TARGET  the admitted child ES id (unchanged);
///   * OUTCOME `continuation_carrier.{mode,resolution,source_origin,...}` is
///             published in the completed response, and a declared `warm`
///             request is REFUSED before generation when it cannot be honoured.
///
/// Everything below runs through the real product HTTP route (LOCALB-authorized
/// POST /v1/responses), the real IS admission, and the real settlement
/// adapter + authoritative SQLite commit. The only substituted components are
/// the token generator (fixed text) and the fork/ownership primitives (a stub
/// that records the source/target pair it was asked for and can simulate "no
/// live source session"). No model is loaded and no user state is written: the
/// class XCTSkips unless the three isolated roots are injected.
final class ContinuationCarrierContractTests: XCTestCase {

    private let port = 59_359
    private var isolationRoot: URL!
    private var modelPath: String!
    private var host: LOCALBAuthorizedE2E.Host!

    // MARK: - Recording stub

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _admission = 0
        private var _generate = 0
        private var _settlement = 0
        private var _forkPairs: [(source: String, target: String)] = []
        private var _forkPolicies: [BranchForkPolicy] = []
        private var _releases: [String] = []
        private var _generateBranches: [String] = []

        func bumpAdmission() { lock.withLock { _admission += 1 } }
        func bumpGenerate(branch: String) {
            lock.withLock { _generate += 1; _generateBranches.append(branch) }
        }
        func bumpSettlement() { lock.withLock { _settlement += 1 } }
        func bumpFork(source: String, target: String, policy: BranchForkPolicy) {
            lock.withLock {
                _forkPairs.append((source, target))
                _forkPolicies.append(policy)
            }
        }
        func bumpRelease(_ branch: String) { lock.withLock { _releases.append(branch) } }

        var admission: Int { lock.withLock { _admission } }
        var generate: Int { lock.withLock { _generate } }
        var settlement: Int { lock.withLock { _settlement } }
        var forkPairs: [(source: String, target: String)] { lock.withLock { _forkPairs } }
        var forkPolicies: [BranchForkPolicy] { lock.withLock { _forkPolicies } }
        var releases: [String] { lock.withLock { _releases } }
        var lastGenerateBranch: String? { lock.withLock { _generateBranches.last } }
    }

    /// Reports an UNOBSERVED KV on purpose: nothing in this file may be read as
    /// proof that a physical buffer was freed.
    private final class CarrierOwnerStub: ExecutionCarrierReleasing, @unchecked Sendable {
        private let stub: Stub
        init(stub: Stub) { self.stub = stub }

        func releaseExecutionCarrier(
            _ ref: ExecutionCarrierRef
        ) async throws -> CarrierReleaseReport {
            stub.bumpRelease(ref.branchID)
            return CarrierReleaseReport(
                carrierWasLive: true,
                clearIssued: true,
                sessionsReleased: 1,
                bindingDetached: true,
                checkpointFilesDeleted: 0,
                stillLiveAfterwards: false,
                retiredStorage: .unobservable("stub owner: no buffer identity"))
        }

        func verifyCarrierUnusable(_ ref: ExecutionCarrierRef) throws {}
    }

    private struct Outcome {
        let status: Int
        let body: [String: Any]
        let raw: Data
        let generate: Int
        let settlement: Int
        let generateBranch: String?
        let forkPairs: [(source: String, target: String)]
        let forkPolicies: [BranchForkPolicy]
        let releases: [String]

        var carrier: [String: Any] { body["continuation_carrier"] as? [String: Any] ?? [:] }
        var settlementPayload: [String: Any] {
            body["continuation_settlement"] as? [String: Any] ?? [:]
        }
        var errorKind: String? {
            (body["error"] as? [String: Any])?["error_kind"] as? String
        }
        var reasonCode: String? {
            (body["error"] as? [String: Any])?["reason_code"] as? String
        }
        var text: String { String(decoding: raw, as: UTF8.self) }
    }

    // MARK: - Setup

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py")
        }
        isolationRoot = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
                      "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoCarrierContract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"carrier-contract-model-free"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        host = try LOCALBAuthorizedE2E.makeHost()
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        host = nil
        super.tearDown()
    }

    // MARK: - Real-store helpers

    /// A ROOT (parentID == nil) settled anchor: IS holds no carrier relation for
    /// it, because it was never produced by the fork path.
    @MainActor
    private func stageRootSettledAnchor(value: String) throws -> String {
        let store = ExecutionStateGraphStore()
        let producer = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let root = try store.create()
        try store.continueState(root, input: value)
        let state = try XCTUnwrap(store.state(root.id))
        _ = try store.settleProducerResult(
            generatedText: "RESULT=\(value)", boundToState: state, producerIdentity: producer)
        return state.id
    }

    @MainActor
    private func totalExecutionStates() throws -> Int {
        try XCTUnwrap(ExecutionStateGraphStore().esis).count("execution_states")
    }

    @MainActor
    private func totalSettlements() throws -> Int {
        try XCTUnwrap(ExecutionStateGraphStore().esis).readSettlementReceipts().count
    }

    // MARK: - Server (real product wiring, text-only generation)

    /// What the substituted fork primitive does when it is asked for a fork.
    private enum ForkBehavior {
        /// Honour the requested policy: a `detached` fork answers with the
        /// isolation record a verified copy would produce.
        case honourPolicy
        /// Throw, as a runtime with no live source session does.
        case fail
        /// Succeed WITHOUT answering the policy — the shape a runtime that
        /// ignored the 5th argument (or predates it) returns.
        case ignorePolicy
    }

    /// The shape of a verified 2-leaf / 4-array copy. Fixed on purpose: these
    /// counters are the STUB's, and the assertions that use them only check that
    /// the gate and the wire carry them — never that a real copy happened.
    private static let stubIsolation = BranchForkStorageIsolation(
        leaves: 2,
        arrays: 4,
        bytes: 16_384,
        valuesMatched: 4,
        addressesSeparated: 4,
        processedTokenCount: 11,
        cacheKinds: ["KVCacheSimple"])

    private func makeServer(stub: Stub, fork: ForkBehavior) -> HTTPServer {
        let mp = modelPath!
        let admission: ContinuationAdmissionHandler = { esStateID in
            stub.bumpAdmission()
            // The REAL admission, including the verified carrier source.
            let recovered = try await MainActor.run {
                try SimiGoProducerIdentity.recoverContinuation(
                    stateID: esStateID, modelPath: mp)
            }
            return ContinuationAdmissionOutcome(
                esStateID: esStateID,
                recoveredValue: recovered.admitted.recoveredValue,
                verifiedBindings: recovered.admitted.verifiedBindings,
                carrierSourceBranchID: recovered.carrierSourceBranchID)
        }
        let inner = makeNativeMLXContinuationSettlementHandler(modelPath: mp)
        let settlement: ContinuationSettlementHandler = { request in
            stub.bumpSettlement()
            return try await inner(request)
        }

        return HTTPServer(
            port: port,
            modelId: "carrier-contract-test",
            generateHandler: { _, _, _, branch, _, _, _, onChunk, _ in
                stub.bumpGenerate(branch: branch)
                onChunk("RESULT=7143")
                return GenerationResult(text: "RESULT=7143", usage: nil)
            },
            forkBranchHandler: { _, _, source, target, policy in
                // The policy is recorded as RECEIVED, so "the request's policy
                // reached the fork operation" is asserted, not assumed.
                stub.bumpFork(source: source, target: target, policy: policy)
                switch fork {
                case .fail:
                    throw RuntError.generationFailed(
                        "no live source session for s/\(source); cannot fork")
                case .ignorePolicy:
                    return SessionCacheMetadata(
                        storageKey: "s/\(target)", modelId: "carrier-contract-test",
                        savedAt: Date(), history: [],
                        forkPoint: BranchForkPoint(
                            sourceStorageKey: "s/\(source)", atMessage: 3, atToken: 11))
                case .honourPolicy:
                    return SessionCacheMetadata(
                        storageKey: "s/\(target)", modelId: "carrier-contract-test",
                        savedAt: Date(), history: [],
                        forkPoint: BranchForkPoint(
                            sourceStorageKey: "s/\(source)", atMessage: 3, atToken: 11),
                        forkIsolation: policy == .detached ? Self.stubIsolation : nil)
                }
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            continuationAdmission: admission,
            continuationSettlement: settlement,
            carrierOwner: CarrierOwnerStub(stub: stub))
    }

    private func dispatch(
        body: [String: Any],
        fork: ForkBehavior = .honourPolicy
    ) async throws -> Outcome {
        let stub = Stub()
        let server = makeServer(stub: stub, fork: fork)
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator, trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer { server.stop() }

        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        var data: Data?
        var response: HTTPURLResponse?
        for _ in 0..<3 {
            do {
                let result = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST", path: "/v1/responses",
                    contentType: "application/json", body: payload)
                data = result.0
                response = result.1
                break
            } catch let error as URLError
            where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let sent = try XCTUnwrap(
            response, "authorized request never reached the server: \(String(describing: lastError))")
        let raw = data ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
        return Outcome(
            status: sent.statusCode,
            body: json,
            raw: raw,
            generate: stub.generate,
            settlement: stub.settlement,
            generateBranch: stub.lastGenerateBranch,
            forkPairs: stub.forkPairs,
            forkPolicies: stub.forkPolicies,
            releases: stub.releases)
    }

    private func continuationBody(
        anchor: String,
        carrier: String?,
        branch: String? = nil,
        requireDetached: Bool? = nil
    ) -> [String: Any] {
        var json: [String: Any] = [
            "model": "carrier-contract-test",
            "input": [[
                "role": "system",
                "content": "You are a precise assistant. Answer with one line: RESULT=<number>",
            ], [
                "role": "user",
                "content": "The number is 7143.",
            ]],
            "stream": false,
            "session_id": "carrier-" + UUID().uuidString.prefix(8).lowercased(),
            "previous_es_state_id": anchor,
            "continuation_settle": true,
            "temperature": 0,
            "max_tokens": 16,
        ]
        if let carrier { json["continuation_carrier"] = carrier }
        if let branch { json["logical_branch_id"] = branch }
        if let requireDetached { json["require_detached_kv"] = requireDetached }
        return json
    }

    /// Produce a CHILD ES through the real product path (declared cold). Its id
    /// is, by construction, the branch its carrier was registered under — which
    /// is exactly what makes it a VERIFIED carrier source for the next hop.
    @MainActor
    private func makeVerifiedChildAnchor(value: String = "7143") async throws -> String {
        let root = try stageRootSettledAnchor(value: value)
        let o = try await dispatch(body: continuationBody(anchor: root, carrier: "cold"))
        XCTAssertEqual(o.status, 200, o.text)
        return try XCTUnwrap(o.settlementPayload["child_es_state_id"] as? String)
    }

    // MARK: - 1) warm: no verified source ⇒ refuse BEFORE generation

    @MainActor
    func testWarmContinuationWithoutVerifiedSourceRefusesBeforeGeneration() async throws {
        let anchor = try stageRootSettledAnchor(value: "7143")
        let statesBefore = try totalExecutionStates()
        let settlementsBefore = try totalSettlements()

        let o = try await dispatch(body: continuationBody(anchor: anchor, carrier: "warm"))

        XCTAssertEqual(o.status, 422, o.text)
        XCTAssertEqual(o.errorKind, "CARRIER_SOURCE_UNVERIFIED")
        XCTAssertEqual(o.reasonCode, "source_unverified")
        XCTAssertEqual(o.generate, 0, "a warm request that cannot be honoured must not generate")
        XCTAssertEqual(o.settlement, 0, "nothing may settle for a refused continuation")
        XCTAssertTrue(o.forkPairs.isEmpty, "no fork may be attempted without a verified source")
        // Hoisted: XCTest autoclosures are not main-actor isolated.
        let statesAfter = try totalExecutionStates()
        let settlementsAfter = try totalSettlements()
        XCTAssertEqual(statesAfter, statesBefore, "no orphan child ES may be created")
        XCTAssertEqual(settlementsAfter, settlementsBefore)
    }

    // MARK: - 2) cold: explicitly allowed, no fork, still settles

    @MainActor
    func testColdContinuationSkipsForkAndStillSettles() async throws {
        let anchor = try stageRootSettledAnchor(value: "7143")
        let o = try await dispatch(body: continuationBody(anchor: anchor, carrier: "cold"))

        XCTAssertEqual(o.status, 200, o.text)
        XCTAssertEqual(o.generate, 1)
        XCTAssertEqual(o.settlement, 1)
        XCTAssertTrue(o.forkPairs.isEmpty, "cold mode must not fork")
        XCTAssertEqual(o.carrier["mode"] as? String, "cold")
        XCTAssertEqual(o.carrier["resolution"] as? String, "cold")
        XCTAssertEqual(o.carrier["source_origin"] as? String, "none")
        XCTAssertEqual(o.carrier["verified_warm_reuse"] as? Bool, false)
        XCTAssertEqual(o.carrier["source_branch_id"] as? String, "-")

        let childID = try XCTUnwrap(o.settlementPayload["child_es_state_id"] as? String)
        XCTAssertEqual(o.carrier["target_branch_id"] as? String, childID)
        XCTAssertEqual(o.generateBranch, childID)
    }

    // MARK: - 3) warm: forks from the VERIFIED source, not the client's branch

    @MainActor
    func testWarmContinuationForksFromVerifiedSourceNotClientBranch() async throws {
        let childAnchor = try await makeVerifiedChildAnchor()

        // The client keeps sending its conversation branch; that must NOT select
        // the KV source.
        let o = try await dispatch(body: continuationBody(
            anchor: childAnchor, carrier: "warm", branch: "main"))

        XCTAssertEqual(o.status, 200, o.text)
        let targetID = try XCTUnwrap(o.settlementPayload["child_es_state_id"] as? String)
        XCTAssertEqual(o.carrier["mode"] as? String, "warm")
        XCTAssertEqual(o.carrier["resolution"] as? String, "forked")
        XCTAssertEqual(o.carrier["source_origin"] as? String, "es_lineage")
        XCTAssertEqual(o.carrier["source_branch_id"] as? String, childAnchor)
        XCTAssertEqual(o.carrier["target_branch_id"] as? String, targetID)
        XCTAssertEqual(o.carrier["client_branch_id"] as? String, "main")
        XCTAssertEqual(o.carrier["client_branch_mismatch"] as? Bool, true)
        XCTAssertEqual(o.carrier["verified_warm_reuse"] as? Bool, true)
        // The runtime's own answer to "where did the KV come from".
        XCTAssertEqual(o.carrier["runtime_fork_source"] as? String, "s/\(childAnchor)")
        XCTAssertEqual(o.carrier["fork_token_count"] as? Int, 11)
        // Nothing was asked about storage, so the request must not claim any:
        // the default is the shared fork, and it is PUBLISHED as such.
        XCTAssertEqual(o.carrier["fork_policy"] as? String, "shared_cow")
        XCTAssertEqual(o.carrier["detached_storage_verified"] as? Bool, false)
        XCTAssertNil(o.carrier["storage_isolation"])
        XCTAssertEqual(o.forkPolicies, [.sharedCOW])

        XCTAssertEqual(o.forkPairs.count, 1)
        XCTAssertEqual(o.forkPairs.first?.source, childAnchor,
                       "the fork source must be the verified parent ES carrier")
        XCTAssertEqual(o.forkPairs.first?.target, targetID)
        XCTAssertEqual(o.generateBranch, targetID)
    }

    // MARK: - 4) warm: verified source gone ⇒ refuse + release the target

    @MainActor
    func testWarmContinuationWithReleasedSourceRefusesAndReleasesTarget() async throws {
        let childAnchor = try await makeVerifiedChildAnchor()
        let statesBefore = try totalExecutionStates()
        let settlementsBefore = try totalSettlements()

        let o = try await dispatch(
            body: continuationBody(anchor: childAnchor, carrier: "warm"),
            fork: .fail)

        XCTAssertEqual(o.status, 422, o.text)
        XCTAssertEqual(o.errorKind, "CARRIER_FORK_FAILED")
        XCTAssertEqual(o.reasonCode, "fork_failed")
        XCTAssertEqual(o.forkPairs.count, 1, "the fork was attempted exactly once")
        XCTAssertEqual(o.forkPairs.first?.source, childAnchor)
        XCTAssertEqual(o.generate, 0, "a warm request must not fall back to a rebuild")
        XCTAssertEqual(o.settlement, 0)
        // Nothing will ever name the target branch: it must not stay live.
        XCTAssertEqual(o.releases, [try XCTUnwrap(o.forkPairs.first?.target)])
        let statesAfter = try totalExecutionStates()
        let settlementsAfter = try totalSettlements()
        XCTAssertEqual(statesAfter, statesBefore)
        XCTAssertEqual(settlementsAfter, settlementsBefore)
    }

    // MARK: - 5) auto: client-asserted source is labelled, never claimed verified

    @MainActor
    func testAutoContinuationWithoutVerifiedSourceLabelsClientAsserted() async throws {
        let anchor = try stageRootSettledAnchor(value: "7143")
        let o = try await dispatch(body: continuationBody(anchor: anchor, carrier: nil))

        XCTAssertEqual(o.status, 200, o.text)
        XCTAssertEqual(o.carrier["mode"] as? String, "auto")
        XCTAssertEqual(o.carrier["resolution"] as? String, "forked")
        XCTAssertEqual(o.carrier["source_origin"] as? String, "client_asserted")
        XCTAssertEqual(o.carrier["source_branch_id"] as? String, "main")
        XCTAssertEqual(o.carrier["verified_warm_reuse"] as? Bool, false)
        XCTAssertEqual(o.forkPairs.first?.source, "main")
        XCTAssertEqual(o.settlement, 1)
    }

    // MARK: - 6) auto: a failed fork is published, not hidden

    @MainActor
    func testAutoForkFailureIsPublishedAndStillSettles() async throws {
        let anchor = try stageRootSettledAnchor(value: "7143")
        let o = try await dispatch(
            body: continuationBody(anchor: anchor, carrier: nil), fork: .fail)

        XCTAssertEqual(o.status, 200, o.text)
        XCTAssertEqual(o.carrier["resolution"] as? String, "degraded_fork_failed")
        XCTAssertEqual(o.carrier["reason"] as? String, "fork_failed")
        XCTAssertEqual(o.carrier["verified_warm_reuse"] as? Bool, false)
        XCTAssertEqual(o.generate, 1)
        XCTAssertEqual(o.settlement, 1, "correctness does not depend on the carrier")
    }

    // MARK: - 7) an unknown declared mode is a malformed request

    @MainActor
    func testUnknownCarrierModeIsRejectedWithoutGenerating() async throws {
        let anchor = try stageRootSettledAnchor(value: "7143")
        let o = try await dispatch(body: continuationBody(anchor: anchor, carrier: "lukewarm"))

        XCTAssertEqual(o.status, 400, o.text)
        XCTAssertEqual(o.generate, 0)
        XCTAssertTrue(o.forkPairs.isEmpty)
    }

    // MARK: - 8) strict storage: the policy is CARRIED and the claim published

    @MainActor
    func testDetachedPolicyReachesTheForkAndIsPublishedAsVerified() async throws {
        let childAnchor = try await makeVerifiedChildAnchor()
        let o = try await dispatch(
            body: continuationBody(
                anchor: childAnchor, carrier: "warm", requireDetached: true))

        XCTAssertEqual(o.status, 200, o.text)
        // The request's policy reached the fork operation as an ARGUMENT; it
        // was not inferred by the runtime from `warm` (a warm request without
        // the flag above asserts `shared_cow`).
        XCTAssertEqual(o.forkPolicies, [.detached])
        XCTAssertEqual(o.carrier["fork_policy"] as? String, "detached")
        XCTAssertEqual(o.carrier["detached_storage_verified"] as? Bool, true)
        let isolation = try XCTUnwrap(
            o.carrier["storage_isolation"] as? [String: Any])
        XCTAssertEqual(isolation["arrays"] as? Int, 4)
        XCTAssertEqual(isolation["addresses_separated"] as? Int, 4)
        XCTAssertEqual(isolation["values_matched"] as? Int, 4)
        XCTAssertEqual(isolation["storage_separated"] as? Bool, true)
        XCTAssertEqual(isolation["values_preserved"] as? Bool, true)
        XCTAssertEqual(isolation["cache_kinds"] as? [String], ["KVCacheSimple"])
        XCTAssertEqual(o.generate, 1)
        XCTAssertEqual(o.settlement, 1)
    }

    // MARK: - 9) strict storage: a fork that did not answer the policy is refused

    @MainActor
    func testDetachedRequestRefusedWhenForkIgnoresPolicy() async throws {
        let childAnchor = try await makeVerifiedChildAnchor()
        let statesBefore = try totalExecutionStates()
        let settlementsBefore = try totalSettlements()

        // The runtime forks and returns ordinary metadata: exactly what a
        // shared fork (or a runtime without the detached API) produces.
        let o = try await dispatch(
            body: continuationBody(
                anchor: childAnchor, carrier: "warm", requireDetached: true),
            fork: .ignorePolicy)

        XCTAssertEqual(o.status, 422, o.text)
        XCTAssertEqual(o.errorKind, "CARRIER_DETACHED_UNAVAILABLE")
        XCTAssertEqual(o.reasonCode, "detached_unavailable")
        XCTAssertEqual(o.forkPolicies, [.detached], "the policy was asked for")
        XCTAssertEqual(o.generate, 0, "an unverified copy must not generate")
        XCTAssertEqual(o.settlement, 0)
        // The target branch was created and will never be named: released.
        XCTAssertEqual(o.releases, [try XCTUnwrap(o.forkPairs.first?.target)])
        let statesAfter = try totalExecutionStates()
        let settlementsAfter = try totalSettlements()
        XCTAssertEqual(statesAfter, statesBefore, "no orphan child ES may be created")
        XCTAssertEqual(settlementsAfter, settlementsBefore)
    }

    // MARK: - 10) strict storage: fork failure refuses instead of degrading

    @MainActor
    func testDetachedForkFailureRefusesEvenInAutoMode() async throws {
        let childAnchor = try await makeVerifiedChildAnchor()
        let o = try await dispatch(
            body: continuationBody(
                anchor: childAnchor, carrier: "auto", requireDetached: true),
            fork: .fail)

        XCTAssertEqual(o.status, 422, o.text)
        XCTAssertEqual(o.errorKind, "CARRIER_DETACHED_UNAVAILABLE")
        XCTAssertEqual(o.reasonCode, "detached_unavailable")
        // Strict storage never degrades: `auto` would have settled on a rebuild
        // without the flag.
        XCTAssertEqual(o.generate, 0)
        XCTAssertEqual(o.settlement, 0)
        XCTAssertEqual(o.releases, [try XCTUnwrap(o.forkPairs.first?.target)])
    }

    // MARK: - 11) strict storage: a declared `cold` cannot be honoured

    @MainActor
    func testDetachedWithColdIsRefusedBeforeGeneration() async throws {
        let anchor = try stageRootSettledAnchor(value: "7143")
        let o = try await dispatch(
            body: continuationBody(
                anchor: anchor, carrier: "cold", requireDetached: true))

        XCTAssertEqual(o.status, 422, o.text)
        XCTAssertEqual(o.errorKind, "CARRIER_DETACHED_REQUIRES_FORK")
        XCTAssertEqual(o.reasonCode, "detached_requires_fork")
        XCTAssertEqual(o.generate, 0)
        XCTAssertEqual(o.settlement, 0)
        XCTAssertTrue(o.forkPairs.isEmpty, "cold never forks, so nothing to detach")
    }

    // MARK: - 12) strict storage: no fork is scheduled at all

    @MainActor
    func testDetachedWithoutAnyForkIsRefused() async throws {
        // No anchor and no settle flag: the request will not fork, so the flag
        // is refused rather than accepted and silently ignored.
        var body = continuationBody(anchor: "", carrier: nil, requireDetached: true)
        body.removeValue(forKey: "previous_es_state_id")
        body.removeValue(forKey: "continuation_settle")

        let o = try await dispatch(body: body)

        XCTAssertEqual(o.status, 422, o.text)
        XCTAssertEqual(o.reasonCode, "detached_requires_fork")
        XCTAssertEqual(o.generate, 0)
        XCTAssertTrue(o.forkPairs.isEmpty)
    }

    // MARK: - 13) strict storage: a non-boolean flag is malformed

    @MainActor
    func testNonBooleanDetachedFlagIsMalformed() async throws {
        var body = continuationBody(anchor: "es-placeholder", carrier: nil)
        body["require_detached_kv"] = "yes"

        let o = try await dispatch(body: body)

        XCTAssertEqual(o.status, 400, o.text)
        XCTAssertEqual(o.generate, 0)
        XCTAssertTrue(o.forkPairs.isEmpty)
    }
}

