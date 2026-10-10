import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class ProductionRuntimeFailureBoundaryTests: XCTestCase {
  private func makeConfiguration() throws -> ProductionRuntimeLaunchConfiguration {
    let labRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("production-failure-boundary-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let policy = directory.appendingPathComponent("validity-policy.json")
    let policyObject: [String: Any] = [
      "schema_id": "SIMIGO-INFO-VALIDITY-POLICY-V1",
      "policy_version": "failure-boundary-test",
      "policy_source": "ISOLATED_TEST_ONLY",
      "missing_policy": "REJECT",
      "dependency_propagation": "ALL_TRANSITIVE",
      "default_valid_until_utc": "2030-12-31T23:59:59Z",
      "expired_source_revision_probe": "ISOLATED_E2E_ONLY",
    ]
    try JSONSerialization.data(withJSONObject: policyObject).write(to: policy)
    return ProductionRuntimeLaunchConfiguration(
      runtimeRoot: labRoot.appendingPathComponent("execution-information-loop"),
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: labRoot.appendingPathComponent(
        "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
      ),
      validityPolicyPath: policy
    )
  }

  private func makeExecutor(
    seedError: Error? = nil,
    continuationError: Error? = nil
  ) -> ProductionRuntimeModelExecutorStub {
    ProductionRuntimeModelExecutorStub(
      seedTokenError: seedError,
      continuationError: continuationError
    )
  }

  func testBlockedInformationDoesNotCreateSwiftLifecycle() async throws {
    let configuration = try makeConfiguration()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: makeExecutor()
    )
    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("blocked-\(UUID().uuidString).sqlite")
    try integration.initialize(database: database, validUntil: nil)
    let executionID = ProductionRuntimeInformationIntegration.executionID

    try integration.applyIsolatedSourceRevision(
      database: database,
      itemID: "REAL-6",
      version: "failure-boundary-expired",
      validUntil: "2020-01-01T00:00:00Z"
    )
    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "blocked-boundary",
        evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("stale information must block")
    } catch let error as ProductionRuntimeInformationError {
      guard case .blockedInformationDemand = error else {
        throw XCTFailure("unexpected error: \(error)")
      }
    }

    XCTAssertEqual(0, integration.runtimeLifecycleRecords(executionID: executionID).count)
    XCTAssertNil(integration.runtimeHandle(executionID: executionID))
    let audit = try integration.audit(database: database)
    XCTAssertEqual("BLOCKED", (audit["execution_state"] as? [String: Any])?["status"] as? String)
  }

  func testMissingExecutorPersistsBlockedWithoutSwiftLifecycle() async throws {
    let configuration = try makeConfiguration()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: nil
    )
    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("missing-executor-\(UUID().uuidString).sqlite")
    try integration.initialize(database: database, validUntil: nil)
    let executionID = ProductionRuntimeInformationIntegration.executionID

    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "executor-missing-boundary",
        evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("missing executor must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      XCTAssertEqual(.modelExecutorUnavailable, error)
    }

    XCTAssertEqual(0, integration.runtimeLifecycleRecords(executionID: executionID).count)
    XCTAssertNil(integration.runtimeHandle(executionID: executionID))
    let audit = try integration.audit(database: database)
    XCTAssertEqual("BLOCKED", (audit["execution_state"] as? [String: Any])?["status"] as? String)
    XCTAssertEqual(
      "executor-missing-boundary:executor-missing",
      (audit["execution_state"] as? [String: Any])?["state_id"] as? String
    )
  }

  func testSeedTokenizationFailurePersistsBlockedAndDiscardsRuntime() async throws {
    let configuration = try makeConfiguration()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: makeExecutor(seedError: ProductionRuntimeTestFailure("tokenize seed"))
    )
    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("seed-failure-\(UUID().uuidString).sqlite")
    try integration.initialize(database: database, validUntil: nil)
    let executionID = ProductionRuntimeInformationIntegration.executionID

    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "seed-tokenization-failure",
        evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("seed tokenization failure must propagate")
    } catch let error as ProductionRuntimeInformationError {
      guard case .modelExecutionFailed = error else {
        throw XCTFailure("unexpected error: \(error)")
      }
    }

    let records = integration.runtimeLifecycleRecords(executionID: executionID)
    XCTAssertEqual(0, records.count)
    let audit = try integration.audit(database: database)
    XCTAssertEqual("BLOCKED", (audit["execution_state"] as? [String: Any])?["status"] as? String)
    XCTAssertEqual(
      "seed-tokenization-failure:tokenize_seed-failed",
      (audit["execution_state"] as? [String: Any])?["state_id"] as? String
    )
  }

  func testRepresentationBindingFailurePersistsBlockedAndDiscardsRuntime() async throws {
    let configuration = try makeConfiguration()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: makeExecutor()
    )
    integration.representationBindingFault = ProductionRuntimeTestFailure("representation bind")
    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("binding-failure-\(UUID().uuidString).sqlite")
    try integration.initialize(database: database, validUntil: nil)
    let executionID = ProductionRuntimeInformationIntegration.executionID

    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "representation-binding-failure",
        evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("representation binding failure must propagate")
    } catch let error as ProductionRuntimeInformationError {
      guard case .modelExecutionFailed = error else {
        throw XCTFailure("unexpected error: \(error)")
      }
    }

    let records = integration.runtimeLifecycleRecords(executionID: executionID)
    let audit = try integration.audit(database: database)
    XCTAssertEqual("BLOCKED", (audit["execution_state"] as? [String: Any])?["status"] as? String)
    XCTAssertEqual(
      "representation-binding-failure:representation_binding-failed",
      (audit["execution_state"] as? [String: Any])?["state_id"] as? String
    )
  }

  func testConfirmationFailurePersistsBlockedAndRollsRuntimeBack() async throws {
    let configuration = try makeConfiguration()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: makeExecutor()
    )
    integration.carrierConfirmationFault = ProductionRuntimeTestFailure("confirmation")
    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("confirmation-failure-\(UUID().uuidString).sqlite")
    try integration.initialize(database: database, validUntil: nil)
    let executionID = ProductionRuntimeInformationIntegration.executionID

    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "confirmation-failure",
        evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("confirmation failure must propagate")
    } catch let error as ProductionRuntimeInformationError {
      guard case .modelExecutionFailed = error else {
        throw XCTFailure("unexpected error: \(error)")
      }
    }

    let records = integration.runtimeLifecycleRecords(executionID: executionID)
    print("CONFIRMATION_COUNT", records.count)
    print("CONFIRMATION_RECORDS", records.prefix(8).map { "\($0.operation)-\($0.resultPosition.value)" })
    print("CONFIRMATION_COUNT", records.count)
    for (index, record) in records.enumerated() {
      print("CONFIRMATION_RECORD_\(index)", record.operation, record.resultPosition.value)
    }
    let audit = try integration.audit(database: database)
    XCTAssertEqual("BLOCKED", (audit["execution_state"] as? [String: Any])?["status"] as? String)
    XCTAssertEqual(
      "confirmation-failure:carrier_confirmation-failed",
      (audit["execution_state"] as? [String: Any])?["state_id"] as? String
    )
  }
}

struct ProductionRuntimeTestFailure: Error, Equatable {
  let message: String
  init(_ message: String) { self.message = message }
}
