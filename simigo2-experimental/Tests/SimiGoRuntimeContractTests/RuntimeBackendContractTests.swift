import XCTest
import SimiGoRuntimeContract

/// B2: proves the Backend/Materializer contract surface is exercisable
/// WITHOUT MLX. This test target has no MLX dependency in the package
/// graph — compilation of this file is itself part of the gate evidence
/// (gate §2.6 / §9: contract and Controller-facing surface are MLX-free).

private final class MockBackend: RuntimeResidencyBackend, @unchecked Sendable {
    enum BackendError: Error, Equatable {
        case deviceLost
        case groupNotResident
    }

    let observation: BackendMemoryObservation
    var failMaterializeOf: Set<String> = []
    var failReleaseOf: Set<String> = []
    private(set) var materializeCalls: [String] = []
    private(set) var releaseCalls: [String] = []
    private(set) var purgeCount = 0

    init(observation: BackendMemoryObservation) {
        self.observation = observation
    }

    func materialize(groupID: String) throws {
        materializeCalls.append(groupID)
        if failMaterializeOf.contains(groupID) {
            throw BackendError.deviceLost
        }
    }

    func release(groupID: String) throws {
        releaseCalls.append(groupID)
        if failReleaseOf.contains(groupID) {
            throw BackendError.groupNotResident
        }
    }

    func memoryObservation() throws -> BackendMemoryObservation {
        observation
    }

    func purgeTransientCaches() throws {
        purgeCount += 1
    }
}

final class RuntimeBackendContractTests: XCTestCase {
    func testMemoryObservationPropagatesVerbatim() throws {
        let backend = MockBackend(
            observation: BackendMemoryObservation(
                activeBytes: 1_718_091_366,
                cacheBytes: 0,
                peakBytes: 2_000_000_000
            )
        )

        let observation = try backend.memoryObservation()

        XCTAssertEqual(
            observation,
            BackendMemoryObservation(
                activeBytes: 1_718_091_366,
                cacheBytes: 0,
                peakBytes: 2_000_000_000
            )
        )
    }

    func testMaterializeAndReleasePropagateSuccessAndFailure() throws {
        let backend = MockBackend(
            observation: BackendMemoryObservation(activeBytes: 0, cacheBytes: 0, peakBytes: 0)
        )
        backend.failMaterializeOf = ["B"]
        backend.failReleaseOf = ["A"]

        try backend.materialize(groupID: "A")
        XCTAssertThrowsError(try backend.materialize(groupID: "B")) { error in
            XCTAssertEqual(error as? MockBackend.BackendError, .deviceLost)
        }

        try backend.release(groupID: "B")
        XCTAssertThrowsError(try backend.release(groupID: "A")) { error in
            XCTAssertEqual(error as? MockBackend.BackendError, .groupNotResident)
        }

        XCTAssertEqual(backend.materializeCalls, ["A", "B"])
        XCTAssertEqual(backend.releaseCalls, ["B", "A"])
    }

    func testBackendSatisfiesTheControllerFacingMaterializerSurface() {
        // The Controller depends only on ResidencyMaterializer; a full
        // RuntimeResidencyBackend must be usable wherever that surface is
        // required — the boundary holds without narrowing.
        let backend: RuntimeResidencyBackend = MockBackend(
            observation: BackendMemoryObservation(activeBytes: 1, cacheBytes: 2, peakBytes: 3)
        )
        let materializer: any ResidencyMaterializer = backend

        XCTAssertNoThrow(try materializer.materialize(groupID: "G"))
        XCTAssertNoThrow(try materializer.release(groupID: "G"))
    }

    func testPurgeIsAnExplicitRuntimeOperation() throws {
        let backend = MockBackend(
            observation: BackendMemoryObservation(activeBytes: 0, cacheBytes: 0, peakBytes: 0)
        )

        XCTAssertEqual(backend.purgeCount, 0)
        try backend.purgeTransientCaches()
        try backend.purgeTransientCaches()
        XCTAssertEqual(backend.purgeCount, 2)
    }
}
