import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class IntegratedSimigoProofE2ETests: XCTestCase {
  override func setUpWithError() throws {
    // The proof run settles through the production bridge, which requires the
    // deployment trust root under the `required` provenance policy.
    try SettlementTrustFixture.install()
  }

  private let requiredItems = [
    "REAL-COLLECTION",
    "REAL-SEGMENT",
    "REAL-1",
    "REAL-2",
    "REAL-3",
    "REAL-4",
    "REAL-5",
    "REAL-6",
    "REAL-7",
  ]

  private func makeTemporaryDatabase() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("integrated-simigo-proof-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("integrated_proof.sqlite")
  }

  private func persist(_ handle: ExecutionStateHandle, to url: URL) throws {
    try JSONEncoder().encode(
      SerializedProductionExecutionState(handle: handle)
    ).write(to: url, options: .atomic)
  }

  private func restore(from url: URL) throws -> ExecutionStateHandle {
    let record = try JSONDecoder().decode(
      SerializedProductionExecutionState.self,
      from: Data(contentsOf: url)
    )
    return try record.validatedHandle()
  }

  private func actions(_ report: ProductionRuntimeBridgeReport) -> [String: String] {
    var value = Dictionary(
      uniqueKeysWithValues: report.computedItemIDs.map { ($0, "COMPUTE") }
    )
    for item in report.reusedItemIDs { value[item] = "REUSE" }
    return value
  }

  private func makeIsolatedConfiguration() throws -> (
    configuration: ProductionRuntimeLaunchConfiguration,
    directory: URL
  ) {
    let labRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("integrated-proof-policy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let policy = directory.appendingPathComponent("validity-policy.json")
    let policyObject: [String: Any] = [
      "schema_id": "SIMIGO-INFO-VALIDITY-POLICY-V1",
      "policy_version": "integrated-proof-test",
      "policy_source": "ISOLATED_TEST_ONLY",
      "missing_policy": "REJECT",
      "dependency_propagation": "ALL_TRANSITIVE",
      "default_valid_until_utc": "2030-12-31T23:59:59Z",
      "expired_source_revision_probe": "ISOLATED_E2E_ONLY",
    ]
    try JSONSerialization.data(withJSONObject: policyObject).write(to: policy)
    let configuration = ProductionRuntimeLaunchConfiguration(
      runtimeRoot: labRoot.appendingPathComponent("execution-information-loop"),
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: labRoot.appendingPathComponent(
        "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
      ),
      validityPolicyPath: policy
    )
    return (configuration, directory)
  }

  func testIsolatedRealSimiGoExecutionInformationProof() async throws {
    let database = try makeTemporaryDatabase()
    let handleURL = database.deletingLastPathComponent()
      .appendingPathComponent("integrated-proof-execution-state.json")
    let isolated = try makeIsolatedConfiguration()
    let firstAuthority = ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration
    )
    firstAuthority.attachModelExecutor(ProductionRuntimeModelExecutorStub())
    try firstAuthority.initialize(
      database: database,
      validUntil: "2030-12-31T23:59:59Z"
    )

    let initial = try await firstAuthority.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "proof-initial",
      evaluatedAtUTC: "2026-10-09T00:00:00Z"
    )
    XCTAssertEqual(initial.report.state, "ADVANCED")
    XCTAssertEqual(initial.report.computedItemIDs, requiredItems)
    XCTAssertTrue(initial.report.reusedItemIDs.isEmpty)
    XCTAssertEqual(initial.handle.lifecycle, .active)
    try persist(initial.handle, to: handleURL)

    // Restart the real coordinator authority and recover from the persisted
    // Execution State. All valid real-source settlements must be reused.
    let restarted = ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration
    )
    restarted.attachModelExecutor(ProductionRuntimeModelExecutorStub())
    let recovered = try restore(from: handleURL)
    let reuse = try await restarted.continueWithRealInformation(
      database: database,
      handle: recovered,
      advancementID: "proof-reuse",
      evaluatedAtUTC: "2026-10-09T00:01:00Z"
    )
    XCTAssertEqual(reuse.report.state, "ADVANCED")
    XCTAssertEqual(reuse.report.computedItemIDs, [])
    XCTAssertEqual(reuse.report.reusedItemIDs, requiredItems)
    try persist(reuse.handle, to: handleURL)

    // Explicit settlement invalidation propagates through the real dependent.
    try restarted.invalidate(
      database: database,
      itemID: "REAL-3",
      reason: "integrated proof explicit invalidation"
    )
    let invalidated = try await restarted.continueWithRealInformation(
      database: database,
      handle: reuse.handle,
      advancementID: "proof-invalidation",
      evaluatedAtUTC: "2026-10-09T00:02:00Z"
    )
    XCTAssertEqual(invalidated.report.state, "ADVANCED")
    XCTAssertEqual(invalidated.report.computedItemIDs, ["REAL-3", "REAL-4"])
    XCTAssertEqual(
      Set(invalidated.report.reusedItemIDs),
      Set(requiredItems).subtracting(["REAL-3", "REAL-4"])
    )
    try persist(invalidated.handle, to: handleURL)

    // A source revision affects only the changed source. Its downstream had
    // no dependent in this real graph, so the other eight remain reusable.
    try restarted.applyIsolatedSourceRevision(
      database: database,
      itemID: "REAL-1",
      version: "2026-10-09T00:03:00.000000"
    )
    let revised = try await restarted.continueWithRealInformation(
      database: database,
      handle: invalidated.handle,
      advancementID: "proof-source-revision",
      evaluatedAtUTC: "2026-10-09T00:03:00Z"
    )
    XCTAssertEqual(revised.report.state, "ADVANCED")
    XCTAssertEqual(revised.report.computedItemIDs, ["REAL-1"])
    XCTAssertEqual(revised.report.reusedItemIDs.count, 8)
    try persist(revised.handle, to: handleURL)

    // An expired validity window is a production preflight rejection: no
    // calculator runs, no settlement is created, and ES does not advance.
    try restarted.applyIsolatedSourceRevision(
      database: database,
      itemID: "REAL-2",
      version: "2026-10-09T00:04:00.000000",
      validUntil: "2020-01-01T00:00:00Z"
    )
    do {
      _ = try await restarted.continueWithRealInformation(
        database: database,
        handle: revised.handle,
        advancementID: "proof-stale",
        evaluatedAtUTC: "2026-10-09T00:04:30Z"
      )
      XCTFail("expired validity must block")
    } catch let error as ProductionRuntimeInformationError {
      guard case .blockedInformationDemand(
        "proof-stale",
        "BLOCKED_STALE_VALIDITY",
        ["REAL-2"]
      ) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
    }

    // Missing required information fails closed without guessing.
    let missing = try restarted.probeMissingInformation(
      database: database,
      evaluatedAtUTC: "2026-10-09T00:05:00Z"
    )
    let missingResult = missing["result"] as? [String: Any]
    XCTAssertEqual(missingResult?["state"] as? String, "BLOCKED_MISSING_INFORMATION")
    XCTAssertEqual(
      missingResult?["missing_item_ids"] as? [String],
      ["MISSING-REAL-SOURCE"]
    )
    XCTAssertEqual(missingResult?["advanced"] as? Bool, false)

    // Malformed observation time is rejected by the bridge boundary.
    do {
      _ = try await restarted.continueWithRealInformation(
        database: database,
        handle: revised.handle,
        advancementID: "proof-malformed",
        evaluatedAtUTC: "not-a-time"
      )
      XCTFail("malformed observation time must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .bridgeFailed = error else {
        return XCTFail("unexpected production error: \(error)")
      }
    }

    // A corrupted persisted lifecycle cannot silently become `.active`.
    let goodRecord = SerializedProductionExecutionState(handle: revised.handle)
    let corrupted = SerializedProductionExecutionState(
      id: goodRecord.id,
      lineageRoot: goodRecord.lineageRoot,
      lineageParent: goodRecord.lineageParent,
      position: 99,
      nextInput: "corrupted-next",
      continuationID: "corrupted-cont",
      lifecycle: "UNKNOWN_CORRUPTED_LIFECYCLE"
    )
    let corruptedURL = database.deletingLastPathComponent()
      .appendingPathComponent("corrupted-execution-state.json")
    try JSONEncoder().encode(corrupted).write(to: corruptedURL, options: .atomic)
    do {
      _ = try restore(from: corruptedURL)
      XCTFail("unknown persisted lifecycle must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .invalidPersistedExecutionState(
        lifecycle: "UNKNOWN_CORRUPTED_LIFECYCLE"
      ) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
    }

    // The same persistent carrier must retain and verify every object.
    let audit = try restarted.audit(database: database)
    XCTAssertEqual(audit["carrier_all_objects_verify"] as? Bool, true)
    XCTAssertGreaterThan(audit["carrier_object_count"] as? Int ?? 0, 0)
    let state = audit["execution_state"] as? [String: Any]
    XCTAssertEqual(state?["state_id"] as? String, "proof-stale")
    XCTAssertEqual(state?["status"] as? String, "BLOCKED")
  }
}
