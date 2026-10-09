import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class ProductionRuntimeInformationIntegrationTests: XCTestCase {
  private func makeTemporaryDatabase() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("simigo-production-runtime-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("production_runtime.sqlite")
  }

  private func persist(_ handle: ExecutionStateHandle, to url: URL) throws {
    let record = SerializedProductionExecutionState(handle: handle)
    try JSONEncoder().encode(record).write(to: url, options: .atomic)
  }

  private func restore(from url: URL) throws -> ExecutionStateHandle {
    let record = try JSONDecoder().decode(
      SerializedProductionExecutionState.self,
      from: Data(contentsOf: url)
    )
    return try record.validatedHandle()
  }

  func testRealSimiGoRuntimeDrivesAcceptedRealPalaceInformationLoop() async throws {
    let database = try makeTemporaryDatabase()
    let handleURL = database.deletingLastPathComponent()
      .appendingPathComponent("production-execution-state.json")
    let integration = ProductionRuntimeInformationIntegration()
    try integration.initialize(
      database: database,
      validUntil: "2030-12-31T23:59:59Z"
    )

    let first = try await integration.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "phase-001",
      evaluatedAtUTC: "2026-10-09T00:00:00Z"
    )
    XCTAssertEqual(first.report.state, "ADVANCED")
    XCTAssertEqual(first.report.computedItemIDs.count, 9)
    XCTAssertTrue(first.report.reusedItemIDs.isEmpty)
    XCTAssertEqual(first.handle.lifecycle, .active)
    try persist(first.handle, to: handleURL)

    // Restart the production runtime authority. The persisted handle is
    // reattached through the real ExecutionContinuityCoordinator lifecycle.
    let restarted = ProductionRuntimeInformationIntegration()
    let persisted = try restore(from: handleURL)
    let second = try await restarted.continueWithRealInformation(
      database: database,
      handle: persisted,
      advancementID: "phase-002",
      evaluatedAtUTC: "2026-10-09T00:01:00Z"
    )
    XCTAssertEqual(second.report.state, "ADVANCED")
    XCTAssertEqual(second.report.computedItemIDs, [])
    XCTAssertEqual(second.report.reusedItemIDs.count, 9)
    try persist(second.handle, to: handleURL)

    // Explicit settlement invalidation propagates to the real dependent,
    // while the seven unaffected real records remain reusable.
    let invalidated = restarted
    try invalidated.invalidate(
      database: database,
      itemID: "REAL-3",
      reason: "bounded production integration invalidation"
    )
    let third = try await invalidated.continueWithRealInformation(
      database: database,
      handle: second.handle,
      advancementID: "phase-003",
      evaluatedAtUTC: "2026-10-09T00:02:00Z"
    )
    XCTAssertEqual(third.report.state, "ADVANCED")
    XCTAssertEqual(third.report.computedItemIDs, ["REAL-3", "REAL-4"])
    XCTAssertEqual(third.report.reusedItemIDs.count, 7)
    try persist(third.handle, to: handleURL)

    // An isolated source revision recomputes only the changed source; the
    // canonical PALACE snapshot remains untouched.
    try invalidated.applyIsolatedSourceRevision(
      database: database,
      itemID: "REAL-1",
      version: "2026-10-09T00:03:00.000000"
    )
    let fourth = try await invalidated.continueWithRealInformation(
      database: database,
      handle: third.handle,
      advancementID: "phase-004",
      evaluatedAtUTC: "2026-10-09T00:04:00Z"
    )
    XCTAssertEqual(fourth.report.state, "ADVANCED")
    XCTAssertEqual(fourth.report.computedItemIDs, ["REAL-1"])
    XCTAssertEqual(fourth.report.reusedItemIDs.count, 8)

    XCTAssertEqual(fourth.report.state, "ADVANCED")
  }

  func testInvalidValidityBlocksRealRuntimeWithoutAdvancingState() async throws {
    let expectedStaleItems = [
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
    let database = try makeTemporaryDatabase()
    let integration = ProductionRuntimeInformationIntegration()
    try integration.initialize(
      database: database,
      validUntil: "2020-01-01T00:00:00Z"
    )

    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "blocked-phase",
      evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("expired information demand must block")
    } catch let error as ProductionRuntimeInformationError {
      guard case .blockedInformationDemand(
        _,
        let state,
        let validityFailureItemIDs
      ) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
      XCTAssertEqual(state, "BLOCKED_STALE_VALIDITY")
      XCTAssertEqual(validityFailureItemIDs, expectedStaleItems)
      XCTAssertEqual(validityFailureItemIDs.count, Set(validityFailureItemIDs).count)
    }

    let status = try integration.status(database: database)
    XCTAssertEqual(status["execution_state"] as? String ?? "null", "null")
  }

  func testMissingValidityPolicyBlocksRealRuntimeWithoutExecution() async throws {
    let database = try makeTemporaryDatabase()
    let integration = ProductionRuntimeInformationIntegration()
    try integration.initialize(database: database, validUntil: nil)

    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "missing-validity-phase",
        evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("undefined validity policy must block")
    } catch let error as ProductionRuntimeInformationError {
      guard case .blockedInformationDemand(
        _,
        let state,
        let validityFailureItemIDs
      ) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
      XCTAssertEqual(state, "BLOCKED_VALIDITY_POLICY_MISSING")
      XCTAssertEqual(validityFailureItemIDs.count, 9)
      XCTAssertEqual(validityFailureItemIDs.count, Set(validityFailureItemIDs).count)
    }

    let status = try integration.status(database: database)
    XCTAssertEqual(status["execution_state"] as? String ?? "null", "null")
  }

  func testUnknownPersistedLifecycleFailsClosedWithoutAdvanceOrSettlement() async throws {
    let database = try makeTemporaryDatabase()
    let handleURL = database.deletingLastPathComponent()
      .appendingPathComponent("corrupt-production-execution-state.json")
    let integration = ProductionRuntimeInformationIntegration()
    try integration.initialize(
      database: database,
      validUntil: "2030-12-31T23:59:59Z"
    )

    let first = try await integration.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "known-lifecycle-phase",
      evaluatedAtUTC: "2026-10-09T00:00:00Z"
    )
    let goodRecord = SerializedProductionExecutionState(handle: first.handle)
    let baseline = try integration.audit(database: database)

    // A corrupted archive must not be silently converted into `.active`.
    let corrupted = SerializedProductionExecutionState(
      id: goodRecord.id,
      lineageRoot: goodRecord.lineageRoot,
      lineageParent: goodRecord.lineageParent,
      position: 99,
      nextInput: "corrupted-next",
      continuationID: "corrupted-cont",
      lifecycle: "UNKNOWN_CORRUPTED_LIFECYCLE"
    )
    try JSONEncoder().encode(corrupted).write(
      to: handleURL,
      options: .atomic
    )

    do {
      _ = try restore(from: handleURL)
      XCTFail("unknown persisted lifecycle must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .invalidPersistedExecutionState(
        lifecycle: "UNKNOWN_CORRUPTED_LIFECYCLE"
      ) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
    }

    let after = try integration.audit(database: database)
    let baselineState = baseline["execution_state"] as? [String: Any] ?? [:]
    let afterState = after["execution_state"] as? [String: Any] ?? [:]
    XCTAssertEqual(
      afterState["state_id"] as? String,
      baselineState["state_id"] as? String
    )
    XCTAssertEqual(
      afterState["status"] as? String,
      baselineState["status"] as? String
    )
    XCTAssertEqual(
      afterState["result_digest"] as? String,
      baselineState["result_digest"] as? String
    )
    XCTAssertEqual(
      after["execution_state_dependency_count"] as? Int,
      baseline["execution_state_dependency_count"] as? Int
    )
    XCTAssertEqual(
      after["settlement_dependency_count"] as? Int,
      baseline["settlement_dependency_count"] as? Int
    )
    XCTAssertEqual(
      after["current_settlement_states"] as? [String: String],
      baseline["current_settlement_states"] as? [String: String]
    )
  }
}
