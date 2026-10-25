import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class ProductionReadinessDeploymentPreparationTests: XCTestCase {
  private let snapshotSource = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite")

  private func stageRuntimeBundle() throws -> (bundle: URL, policy: URL) {
    let labRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let bundle = FileManager.default.temporaryDirectory
      .appendingPathComponent("simigo-production-runtime-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: bundle.appendingPathComponent("lib"),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: snapshotSource, to: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite"))
    try FileManager.default.createDirectory(
      at: bundle.appendingPathComponent("database-carrier-replication/implementation"),
      withIntermediateDirectories: true
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

    let policy = bundle.appendingPathComponent("validity-policy.json")
    let policyObject: [String: Any] = [
      "schema_id": "SIMIGO-INFO-VALIDITY-POLICY-V1",
      "policy_version": "production-readiness-v1",
      "policy_source": "DEPLOYMENT_VALIDITY_POLICY",
      "missing_policy": "REJECT",
      "dependency_propagation": "ALL_TRANSITIVE",
      "default_valid_until_utc": "2030-12-31T23:59:59Z",
    ]
    try JSONSerialization.data(
      withJSONObject: policyObject,
      options: [.sortedKeys]
    ).write(to: policy, options: .atomic)
    return (bundle, policy)
  }

  func testPackagedRuntimeRunsWithoutDevelopmentBuildLayout() async throws {
    let (bundle, policy) = try stageRuntimeBundle()
    let database = bundle.appendingPathComponent("runtime.sqlite")
    let configuration = ProductionRuntimeLaunchConfiguration(
      runtimeRoot: bundle,
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite"),
      validityPolicyPath: policy
    )
    let integration = ProductionRuntimeInformationIntegration(configuration: configuration)
    integration.attachModelExecutor(ProductionRuntimeModelExecutorStub())

    XCTAssertFalse(
      configuration.pythonExecutable.path.contains(".build/mp-venv312"),
      "deployment launch must not depend on the development virtualenv"
    )
    XCTAssertTrue(bundle.path.hasPrefix(NSTemporaryDirectory()))
    XCTAssertFalse(bundle.path.hasPrefix(#filePath.dropLast(4)), "bundle must not be the source lab")

    try integration.initialize(database: database, validUntil: nil)
    let first = try await integration.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "production-initial",
      evaluatedAtUTC: "2026-10-09T00:00:00Z"
    )
    XCTAssertEqual(first.report.state, "ADVANCED")
    XCTAssertEqual(first.report.computedItemIDs.count, 9)
    try FileManager.default.copyItem(
      at: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite"),
      to: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite.copy")
    )
  }

  func testPackagedRuntimeMissingLaunchFileFailsClosed() throws {
    let (bundle, policy) = try stageRuntimeBundle()
    let configuration = ProductionRuntimeLaunchConfiguration(
      runtimeRoot: bundle,
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite"),
      validityPolicyPath: policy
    )
    try FileManager.default.removeItem(
      at: configuration.runtimeRoot.appendingPathComponent("production_runtime_bridge.py")
    )
    let integration = ProductionRuntimeInformationIntegration(configuration: configuration)
    integration.attachModelExecutor(ProductionRuntimeModelExecutorStub())

    do {
      _ = try integration.initialize(database: bundle.appendingPathComponent("runtime.sqlite"), validUntil: nil)
      XCTFail("missing launch file must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .launchConfigurationInvalid(_, let message) = error else {
        return XCTFail("unexpected production error: \(error)")
      }
      XCTAssertTrue(message.contains("required production runtime file"))
    }
  }

  func testPackagedRuntimeRejectsIncompleteValidityPolicyIdentity() throws {
    let (bundle, policy) = try stageRuntimeBundle()
    let configuration = ProductionRuntimeLaunchConfiguration(
      runtimeRoot: bundle,
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite"),
      validityPolicyPath: policy
    )
    let integration = ProductionRuntimeInformationIntegration(configuration: configuration)
    integration.attachModelExecutor(ProductionRuntimeModelExecutorStub())

    let basePolicyObject = try JSONSerialization.jsonObject(
      with: Data(contentsOf: policy)
    ) as! [String: Any]
    for missingField in ["policy_version", "policy_source"] {
      var policyObject = basePolicyObject
      policyObject.removeValue(forKey: missingField)
      try JSONSerialization.data(
        withJSONObject: policyObject,
        options: [.sortedKeys]
      ).write(to: policy, options: .atomic)

      do {
        try integration.initialize(
          database: bundle.appendingPathComponent("runtime.sqlite"),
          validUntil: nil
        )
        XCTFail("\(missingField) must be required")
      } catch let error as ProductionRuntimeInformationError {
        guard case .bridgeFailed(_, _, let message) = error else {
          return XCTFail("unexpected production error: \(error)")
        }
        XCTAssertTrue(
          message.contains(missingField),
          "missing \(missingField) produced: \(message)"
        )
      }
    }
  }

  func testPackagedRuntimeDiagnosticsAndAppendOnlyRollbackAreOperable() async throws {
    let (bundle, policy) = try stageRuntimeBundle()
    let database = bundle.appendingPathComponent("runtime.sqlite")
    let configuration = ProductionRuntimeLaunchConfiguration(
      runtimeRoot: bundle,
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: bundle.appendingPathComponent("PALACE_SNAPSHOT.sqlite"),
      validityPolicyPath: policy
    )
    let integration = ProductionRuntimeInformationIntegration(configuration: configuration)
    integration.attachModelExecutor(ProductionRuntimeModelExecutorStub())
    try integration.initialize(database: database, validUntil: nil)
    let good = try await integration.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "production-good",
      evaluatedAtUTC: "2026-10-09T00:00:00Z"
    )

    _ = try integration.recordBlockedExecutionState(
      database: database,
      stateID: "production-blocked-bad",
      priorStateID: good.handle.id.rawValue,
      reason: "operator injected blocked production state"
    )
    let blockedDiagnostics = try integration.diagnostics(
      database: database,
      evaluatedAtUTC: "2026-10-09T00:01:00Z"
    )
    let blockedState = blockedDiagnostics["execution_state"] as? [String: Any]
    XCTAssertEqual(blockedState?["state_id"] as? String, "production-blocked-bad")
    XCTAssertEqual(blockedState?["status"] as? String, "BLOCKED")
    XCTAssertEqual(blockedDiagnostics["carrier_all_objects_verify"] as? Bool, true)
    XCTAssertEqual(
      blockedDiagnostics["rollback_policy"] as? String,
      "APPEND_LAST_GOOD_ADVANCED_STATE; never mutate or delete history"
    )

    let rollback = try integration.rollbackToExecutionState(
      database: database,
      targetStateID: "production-good",
      newStateID: "production-rollback-good"
    )
    let rolledBackState = rollback["execution_state"] as? [String: Any]
    XCTAssertEqual(rolledBackState?["state_id"] as? String, "production-rollback-good")
    XCTAssertEqual(rolledBackState?["status"] as? String, "ADVANCED")
    XCTAssertEqual(rolledBackState?["prior_state_id"] as? String, "production-blocked-bad")

    let goodDiagnostics = try integration.diagnostics(
      database: database,
      evaluatedAtUTC: "2026-10-09T00:02:00Z"
    )
    let goodState = goodDiagnostics["execution_state"] as? [String: Any]
    XCTAssertEqual(goodState?["state_id"] as? String, "production-rollback-good")
    XCTAssertEqual(goodDiagnostics["database_integrity"] as? String, "ok")
    XCTAssertEqual(goodDiagnostics["carrier_all_objects_verify"] as? Bool, true)

    // The append-only rollback record remains compatible with the accepted
    // Execution State continuation path: the next production demand advances.
    let rollbackHandle = good.handle
    let continuation = try await integration.continueWithRealInformation(
      database: database,
      handle: rollbackHandle,
      advancementID: "production-after-rollback",
      evaluatedAtUTC: "2026-10-09T00:03:00Z"
    )
    XCTAssertEqual(continuation.report.state, "ADVANCED")
    XCTAssertEqual(continuation.report.computedItemIDs, [])
    XCTAssertEqual(continuation.report.reusedItemIDs.count, 9)
  }
}

