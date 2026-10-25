import XCTest
import SimiGo2Experimental

@testable import SimiGo

/// Unit coverage for ``MLXRuntimeCarrierOwner`` — the object actually wired into
/// the product's HTTP server — over the SAME seam the production conformer
/// (`NativeMLX`) satisfies. The pool is a fake so no model weights are loaded, but
/// the owner's mapping, its refusal to report a release that did not take, and its
/// address discipline are the real code.
///
/// What this CANNOT prove: that a real `ChatSession`'s KV was freed. The runtime
/// exposes no buffer identity, so the report carries `.unobservable`; "release
/// invoked", "references gone" and "pages returned" stay three separate facts
/// (G3 D1 NO-GO).
final class MLXRuntimeCarrierOwnerTests: XCTestCase {

    /// A stand-in for the runtime session pool, addressed exactly like the real
    /// one: (agent, session, branch).
    private final class FakeSessionPool: SessionBranchReleasing, @unchecked Sendable {
        private let lock = NSLock()
        private var sessions: [String: Int]
        /// Simulates a pool whose removal does not stick (a carrier that survives).
        private let ignoresRelease: Bool
        private(set) var releasedAddresses: [String] = []

        init(addresses: [String: Int] = [:], ignoresRelease: Bool = false) {
            self.sessions = addresses
            self.ignoresRelease = ignoresRelease
        }

        private func address(_ agentId: String?, _ sessionId: String, _ branch: String) -> String {
            "\(agentId ?? "-")/\(sessionId)/\(branch)"
        }

        func releaseSessionBranch(
            agentId: String?,
            sessionId: String,
            logicalBranchId: String,
            in storeDirectory: URL?
        ) async throws -> SessionBranchRelease {
            let key = address(agentId, sessionId, logicalBranchId)
            return lock.withLock {
                releasedAddresses.append(key)
                let count = ignoresRelease
                    ? (sessions[key] ?? 0)
                    : (sessions.removeValue(forKey: key) ?? 0)
                return SessionBranchRelease(
                    carrierWasLive: count > 0,
                    clearIssued: count > 0,
                    sessionsReleased: count,
                    bindingDetached: true,
                    checkpointFilesDeleted: 0,
                    // Re-read INSIDE the same critical section: this is the
                    // "did it actually go" fact, not a copy of the intent.
                    stillLiveAfterwards: sessions[key] != nil,
                    retiredStorage: .unobservable("fake pool: no buffer identity"))
            }
        }

        func hasLiveSessionBranch(
            agentId: String?,
            sessionId: String,
            logicalBranchId: String
        ) -> Bool {
            lock.withLock { sessions[address(agentId, sessionId, logicalBranchId)] != nil }
        }

        var addressesReleased: [String] { lock.withLock { releasedAddresses } }
    }

    private func ref(_ branch: String = "es-child") -> ExecutionCarrierRef {
        ExecutionCarrierRef(agentID: "agent-1", sessionID: "sess-1", branchID: branch)
    }

    /// The live case: the release reports exactly the operations it performed and
    /// the address stops resolving afterwards.
    func testReleaseOfLiveCarrierReportsOperationsAndAddressStopsResolving() async throws {
        let pool = FakeSessionPool(addresses: ["agent-1/sess-1/es-child": 2])
        let owner = MLXRuntimeCarrierOwner(pool: pool)

        let report = try await owner.releaseExecutionCarrier(ref())

        XCTAssertEqual(pool.addressesReleased, ["agent-1/sess-1/es-child"],
                       "the owner must address the pool with the ref, not a guess")
        XCTAssertTrue(report.carrierWasLive)
        XCTAssertTrue(report.clearIssued)
        XCTAssertEqual(report.sessionsReleased, 2,
                       "both client shards of the same branch must be released")
        XCTAssertFalse(report.stillLiveAfterwards)
        XCTAssertEqual(report.retiredStorage,
                       .unobservable("fake pool: no buffer identity"),
                       "an unobserved KV stays UNOBSERVED, never an empty confirmed set")
        XCTAssertNoThrow(try owner.verifyCarrierUnusable(ref()))
    }

    /// A branch that was never live: nothing is claimed. Reporting `clearIssued`
    /// here would invent an operation that never happened.
    func testReleaseOfAbsentCarrierClaimsNothing() async throws {
        let pool = FakeSessionPool()
        let owner = MLXRuntimeCarrierOwner(pool: pool)

        let report = try await owner.releaseExecutionCarrier(ref())

        XCTAssertFalse(report.carrierWasLive)
        XCTAssertFalse(report.clearIssued)
        XCTAssertEqual(report.sessionsReleased, 0)
        XCTAssertEqual(report.checkpointFilesDeleted, 0)
        XCTAssertNoThrow(try owner.verifyCarrierUnusable(ref()))
    }

    /// The decisive fail-closed case: the release ran and the carrier SURVIVED.
    /// "clear() was issued" must not be handed back as a release.
    func testSurvivingCarrierIsRefusedNotReportedAsReleased() async throws {
        let pool = FakeSessionPool(
            addresses: ["agent-1/sess-1/es-child": 1], ignoresRelease: true)
        let owner = MLXRuntimeCarrierOwner(pool: pool)

        do {
            _ = try await owner.releaseExecutionCarrier(ref())
            XCTFail("a branch still live afterwards must be refused, not reported released")
        } catch {
            XCTAssertTrue(String(reflecting: error).contains("releaseIncomplete"), "got \(error)")
            XCTAssertTrue(String(reflecting: error).contains("still live after release"),
                          "the refusal must name the surviving branch: \(error)")
        }
        // And the stronger check independently refuses it too.
        XCTAssertThrowsError(try owner.verifyCarrierUnusable(ref())) { error in
            XCTAssertTrue(String(reflecting: error).contains("carrierStillUsable"), "got \(error)")
            XCTAssertTrue(String(reflecting: error).contains("es-child"), "got \(error)")
        }
    }

    /// The pool-key rule both release and verification share. Model-free, and the
    /// only place the "exact + shards, never bare prefix" decision exists.
    func testBranchPoolKeysMatchExactAndShardsButNotPrefixNeighbours() {
        let keys = [
            "agent/s/session/es-a",
            "agent/s/session/es-a#fp1",
            "agent/s/session/es-a#fp2",
            "agent/s/session/es-ab#fp1",
            "agent/s/session/es-b",
        ]
        XCTAssertEqual(
            NativeMLX.branchPoolKeys(in: keys, for: "agent/s/session/es-a").sorted(),
            ["agent/s/session/es-a", "agent/s/session/es-a#fp1", "agent/s/session/es-a#fp2"],
            "the branch is the exact key plus its own shards — and NOT the prefix neighbour")
        XCTAssertEqual(
            NativeMLX.branchPoolKeys(in: keys, for: "agent/s/session/es-ab"),
            ["agent/s/session/es-ab#fp1"])
        XCTAssertTrue(
            NativeMLX.branchPoolKeys(in: keys, for: "agent/s/session/es-c").isEmpty,
            "an unrelated branch owns none of these keys")
    }

    /// Ownership is per address: releasing one branch leaves a sibling live.
    func testReleaseIsScopedToOneBranchAddress() async throws {
        let pool = FakeSessionPool(addresses: [
            "agent-1/sess-1/es-child": 1,
            "agent-1/sess-1/main": 1,
        ])
        let owner = MLXRuntimeCarrierOwner(pool: pool)

        _ = try await owner.releaseExecutionCarrier(ref())

        XCTAssertFalse(pool.hasLiveSessionBranch(
            agentId: "agent-1", sessionId: "sess-1", logicalBranchId: "es-child"))
        XCTAssertTrue(pool.hasLiveSessionBranch(
            agentId: "agent-1", sessionId: "sess-1", logicalBranchId: "main"),
                      "the client's own branch must not be touched by a child release")
    }
}
