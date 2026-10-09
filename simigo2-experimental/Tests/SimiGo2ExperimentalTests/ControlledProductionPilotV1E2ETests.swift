import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class ControlledProductionPilotV1E2ETests: XCTestCase {
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

  private let snapshotSource = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite")

  private struct PilotEnvironment {
    let bundle: URL
    let database: URL
    let policy: URL
    let handleFile: URL
    let configuration: ProductionRuntimeLaunchConfiguration
  }

  private func stagePilotBundle() throws -> PilotEnvironment {
    let labRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let bundle = FileManager.default.temporaryDirectory
      .appendingPathComponent("controlled-production-pilot-v1-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: bundle.appendingPathComponent("lib"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: bundle.appendingPathComponent("database-carrier-replication/implementation"),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(
      at: snapshotSource,
      to: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite")
    )
    try Data(contentsOf: labRoot.appendingPathComponent(
      "execution-information-loop/production_runtime_bridge.py"
    )).write(to: bundle.appendingPathComponent("production_runtime_bridge.py"))
    for name in ["carrier_loop.py", "real_palace_loop.py"] {
      try Data(contentsOf: labRoot.appendingPathComponent(
        "execution-information-loop/\(name)"
      )).write(to: bundle.appendingPathComponent("lib/\(name)"))
    }
    try Data(contentsOf: labRoot.appendingPathComponent(
      "database-carrier-replication/implementation/db_is.py"
    )).write(to: bundle.appendingPathComponent(
      "database-carrier-replication/implementation/db_is.py"
    ))

    let policy = bundle.appendingPathComponent("validity-policy-v1.json")
    let policyObject: [String: Any] = [
      "schema_id": "SIMIGO-INFO-VALIDITY-POLICY-V1",
      "policy_version": "controlled-production-pilot-v1",
      "policy_source": "CONTROLLED_PRODUCTION_PILOT_V1",
      "missing_policy": "REJECT",
      "dependency_propagation": "ALL_TRANSITIVE",
      "default_valid_until_utc": "2030-12-31T23:59:59Z",
    ]
    try JSONSerialization.data(
      withJSONObject: policyObject,
      options: [.sortedKeys]
    ).write(to: policy, options: .atomic)

    let configuration = ProductionRuntimeLaunchConfiguration(
      runtimeRoot: bundle,
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite"),
      validityPolicyPath: policy
    )
    return PilotEnvironment(
      bundle: bundle,
      database: bundle.appendingPathComponent("controlled-pilot.sqlite"),
      policy: policy,
      handleFile: bundle.appendingPathComponent("execution-state.json"),
      configuration: configuration
    )
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

  func testControlledProductionPilotV1EndToEnd() async throws {
    let pilot = try stagePilotBundle()
    let firstAuthority = ProductionRuntimeInformationIntegration(
      configuration: pilot.configuration
    )
    try firstAuthority.initialize(database: pilot.database, validUntil: nil)

    let initial = try await firstAuthority.continueWithRealInformation(
      database: pilot.database,
      handle: nil,
      advancementID: "pilot-initial",
      evaluatedAtUTC: "2026-10-09T00:00:00Z"
    )
    XCTAssertEqual(initial.report.state, "ADVANCED")
    XCTAssertEqual(initial.report.computedItemIDs, requiredItems)
    XCTAssertTrue(initial.report.reusedItemIDs.isEmpty)
    try persist(initial.handle, to: pilot.handleFile)

    // Restart the real runtime authority and restore the persisted handle.
    let restarted = ProductionRuntimeInformationIntegration(
      configuration: pilot.configuration
    )
    let recovered = try restore(from: pilot.handleFile)
    let reuse = try await restarted.continueWithRealInformation(
      database: pilot.database,
      handle: recovered,
      advancementID: "pilot-reuse",
      evaluatedAtUTC: "2026-10-09T00:01:00Z"
    )
    XCTAssertEqual(reuse.report.state, "ADVANCED")
    XCTAssertEqual(reuse.report.computedItemIDs, [])
    XCTAssertEqual(reuse.report.reusedItemIDs, requiredItems)
    try persist(reuse.handle, to: pilot.handleFile)

    // A transitive source-window expiration must persist a real BLOCKED
    // state without adding a settlement or advancing the Swift runtime.
    let beforeStaleAudit = try restarted.audit(database: pilot.database)
    try restarted.applyIsolatedSourceRevision(
      database: pilot.database,
      itemID: "REAL-6",
      version: "controlled-pilot-v1-expired-revision",
      validUntil: "2020-01-01T00:00:00Z"
    )
    do {
      _ = try await restarted.continueWithRealInformation(
        database: pilot.database,
        handle: reuse.handle,
        advancementID: "pilot-stale",
        evaluatedAtUTC: "2026-10-09T00:01:30Z"
      )
      XCTFail("expired source validity must block")
    } catch let error as ProductionRuntimeInformationError {
      guard case .blockedInformationDemand(
        "pilot-stale",
        "BLOCKED_STALE_VALIDITY",
        let staleItems
      ) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
      XCTAssertEqual(staleItems, ["REAL-6"])
    }
    let staleDiagnostics = try restarted.diagnostics(
      database: pilot.database,
      evaluatedAtUTC: "2026-10-09T00:01:30Z"
    )
    let staleState = staleDiagnostics["execution_state"] as? [String: Any]
    XCTAssertEqual(staleState?["state_id"] as? String, "pilot-stale")
    XCTAssertEqual(staleState?["status"] as? String, "BLOCKED")
    XCTAssertEqual(staleState?["prior_state_id"] as? String, "pilot-reuse")
    let afterStaleAudit = try restarted.audit(database: pilot.database)
    XCTAssertEqual(
      afterStaleAudit["settlement_dependency_count"] as? Int,
      beforeStaleAudit["settlement_dependency_count"] as? Int
    )

    // Refresh the expired source, then append a lawful recovery state before
    // continuing the remaining pilot phases.
    try restarted.applyIsolatedSourceRevision(
      database: pilot.database,
      itemID: "REAL-6",
      version: "controlled-pilot-v1-refreshed-revision"
    )
    _ = try restarted.rollbackToExecutionState(
      database: pilot.database,
      targetStateID: "pilot-reuse",
      newStateID: "pilot-recovery-before-invalidation"
    )
    let refreshed = try await restarted.continueWithRealInformation(
      database: pilot.database,
      handle: reuse.handle,
      advancementID: "pilot-refresh-expired",
      evaluatedAtUTC: "2026-10-09T00:01:40Z"
    )
    try persist(refreshed.handle, to: pilot.handleFile)

    // REAL-3 invalidation must propagate to dependent REAL-4.
    try restarted.invalidate(
      database: pilot.database,
      itemID: "REAL-3",
      reason: "controlled production pilot invalidation"
    )
    let selective = try await restarted.continueWithRealInformation(
      database: pilot.database,
      handle: refreshed.handle,
      advancementID: "pilot-invalidation",
      evaluatedAtUTC: "2026-10-09T00:02:00Z"
    )
    XCTAssertEqual(selective.report.state, "ADVANCED")
    XCTAssertEqual(selective.report.computedItemIDs, ["REAL-3", "REAL-4"])
    XCTAssertEqual(
      Set(selective.report.reusedItemIDs),
      Set(requiredItems).subtracting(["REAL-3", "REAL-4"])
    )
    try persist(selective.handle, to: pilot.handleFile)

    // REAL-1 source revision affects only REAL-1.
    try restarted.applyIsolatedSourceRevision(
      database: pilot.database,
      itemID: "REAL-1",
      version: "controlled-pilot-v1-revision"
    )
    let revised = try await restarted.continueWithRealInformation(
      database: pilot.database,
      handle: selective.handle,
      advancementID: "pilot-source-revision",
      evaluatedAtUTC: "2026-10-09T00:03:00Z"
    )
    XCTAssertEqual(revised.report.state, "ADVANCED")
    XCTAssertEqual(revised.report.computedItemIDs, ["REAL-1"])
    XCTAssertEqual(revised.report.reusedItemIDs.count, 8)
    try persist(revised.handle, to: pilot.handleFile)

    // A blocked operational state is observable in diagnostics.
    _ = try restarted.recordBlockedExecutionState(
      database: pilot.database,
      stateID: "pilot-blocked",
      priorStateID: "pilot-source-revision",
      reason: "controlled pilot fault observability probe"
    )
    let blockedDiagnostics = try restarted.diagnostics(
      database: pilot.database,
      evaluatedAtUTC: "2026-10-09T00:04:00Z"
    )
    let blockedState = blockedDiagnostics["execution_state"] as? [String: Any]
    XCTAssertEqual(blockedState?["state_id"] as? String, "pilot-blocked")
    XCTAssertEqual(blockedState?["status"] as? String, "BLOCKED")

    // Rollback appends a last-good ADVANCED state; it never rewrites history.
    let rollback = try restarted.rollbackToExecutionState(
      database: pilot.database,
      targetStateID: "pilot-source-revision",
      newStateID: "pilot-rollback-good"
    )
    let rolledBackState = rollback["execution_state"] as? [String: Any]
    XCTAssertEqual(rolledBackState?["state_id"] as? String, "pilot-rollback-good")
    XCTAssertEqual(rolledBackState?["status"] as? String, "ADVANCED")
    XCTAssertEqual(rolledBackState?["prior_state_id"] as? String, "pilot-blocked")
    try persist(revised.handle, to: pilot.handleFile)

    // Missing information fails closed without advancing.
    let missing = try restarted.probeMissingInformation(
      database: pilot.database,
      evaluatedAtUTC: "2026-10-09T00:05:00Z"
    )
    let missingResult = missing["result"] as? [String: Any]
    XCTAssertEqual(missingResult?["state"] as? String, "BLOCKED_MISSING_INFORMATION")
    XCTAssertEqual(missingResult?["advanced"] as? Bool, false)

    // Malformed observation time fails closed.
    let beforeMalformedAudit = try restarted.audit(database: pilot.database)
    do {
      _ = try await restarted.continueWithRealInformation(
        database: pilot.database,
        handle: revised.handle,
        advancementID: "pilot-malformed",
        evaluatedAtUTC: "not-a-time"
      )
      XCTFail("malformed observation time must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .blockedInformationDemand(
        "pilot-malformed",
        "BLOCKED_VALIDITY_FAILURE",
        _
      ) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
      let malformedDiagnostics = try restarted.diagnostics(
        database: pilot.database,
        evaluatedAtUTC: "2026-10-09T00:05:00Z"
      )
      let malformedState = malformedDiagnostics["execution_state"] as? [String: Any]
      XCTAssertEqual(malformedState?["state_id"] as? String, "pilot-malformed")
      XCTAssertEqual(malformedState?["status"] as? String, "BLOCKED")
      let afterMalformedAudit = try restarted.audit(database: pilot.database)
      XCTAssertEqual(
        afterMalformedAudit["settlement_dependency_count"] as? Int,
        beforeMalformedAudit["settlement_dependency_count"] as? Int
      )
    }
    _ = try restarted.rollbackToExecutionState(
      database: pilot.database,
      targetStateID: "pilot-source-revision",
      newStateID: "pilot-post-malformed-good"
    )

    // Corrupted persisted lifecycle cannot be silently restored as active.
    let goodRecord = SerializedProductionExecutionState(handle: revised.handle)
    let corrupted = SerializedProductionExecutionState(
      id: goodRecord.id,
      lineageRoot: goodRecord.lineageRoot,
      lineageParent: goodRecord.lineageParent,
      position: 999,
      nextInput: "corrupted-next",
      continuationID: "corrupted-cont",
      lifecycle: "UNKNOWN_CORRUPTED_LIFECYCLE"
    )
    let corruptedURL = pilot.bundle.appendingPathComponent("corrupted-execution-state.json")
    try JSONEncoder().encode(corrupted).write(to: corruptedURL, options: .atomic)
    do {
      _ = try restore(from: corruptedURL)
      XCTFail("unknown persisted lifecycle must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .invalidPersistedExecutionState = error else {
        return XCTFail("unexpected production error: \(error)")
      }
    }

    let finalAudit = try restarted.audit(database: pilot.database)
    XCTAssertEqual(finalAudit["carrier_all_objects_verify"] as? Bool, true)
    XCTAssertGreaterThan(finalAudit["carrier_object_count"] as? Int ?? 0, 0)
    let finalState = finalAudit["execution_state"] as? [String: Any]
    XCTAssertEqual(finalState?["state_id"] as? String, "pilot-post-malformed-good")
    XCTAssertEqual(finalState?["status"] as? String, "ADVANCED")
  }
}
