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
    return record.handle
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
      evaluatedAtUTC: "not-a-time"
      )
      XCTFail("expired information demand must block")
    } catch let error as ProductionRuntimeInformationError {
      guard case .blockedInformationDemand(_, let state) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
      XCTAssertEqual(state, "BLOCKED_VALIDITY_FAILURE")
    }

    let status = try integration.status(database: database)
    XCTAssertEqual(status["execution_state"] as? String ?? "null", "null")
  }
}
