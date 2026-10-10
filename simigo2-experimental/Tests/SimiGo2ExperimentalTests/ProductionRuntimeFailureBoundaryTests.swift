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
    nextInputError: Error? = nil,
    continuationError: Error? = nil
  ) -> ProductionRuntimeModelExecutorStub {
    ProductionRuntimeModelExecutorStub(
      seedTokenError: seedError,
      nextInputError: nextInputError,
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

  func testNextInputTokenizationFailurePersistsBlockedWithoutSwiftLifecycle() async throws {
    let configuration = try makeConfiguration()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: makeExecutor(nextInputError: ProductionRuntimeTestFailure("tokenize next input"))
    )
    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("next-input-failure-\(UUID().uuidString).sqlite")
    try integration.initialize(database: database, validUntil: nil)
    let executionID = ProductionRuntimeInformationIntegration.executionID

    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "next-input-tokenization-failure",
        evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("next-input tokenization failure must propagate")
    } catch let error as ProductionRuntimeInformationError {
      guard case .modelExecutionFailed = error else {
        throw XCTFailure("unexpected error: \(error)")
      }
    }

    XCTAssertEqual(0, integration.runtimeLifecycleRecords(executionID: executionID).count)
    XCTAssertNil(integration.runtimeHandle(executionID: executionID))
    let audit = try integration.audit(database: database)
    XCTAssertEqual("BLOCKED", (audit["execution_state"] as? [String: Any])?["status"] as? String)
    XCTAssertEqual(
      "next-input-tokenization-failure:tokenize_next_input-failed",
      (audit["execution_state"] as? [String: Any])?["state_id"] as? String
    )
  }

  func testInjectedBackendReceivesSeedAndAdvancedRepresentation() async throws {
    let configuration = try makeConfiguration()
    let backend = MLXExecutionStateBackend()
    let executor = ProductionRuntimeModelExecutorStub(representationBackend: backend)
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: executor,
      backend: backend
    )
    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("backend-identity-\(UUID().uuidString).sqlite")
    try integration.initialize(database: database, validUntil: nil)

    let result = try await integration.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "backend-identity-regression",
      evaluatedAtUTC: "2026-10-10T00:00:00Z"
    )

    XCTAssertGreaterThan(try XCTUnwrap(executor.observedBoundPrefixCount), 0)
    let bound = try backend.boundPrefix(for: result.handle)
    XCTAssertEqual(result.handle.position, bound.position)
    XCTAssertEqual([9, 18, 27], bound.prefix)
    XCTAssertEqual(.active, result.handle.lifecycle)
  }

  func testLogicalAdvanceFailurePersistsBlockedAndDiscardsRuntime() async throws {
    let configuration = try makeConfiguration()
    let backend = MLXExecutionStateBackend()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: makeExecutor(),
      backend: backend
    )
    integration.logicalAdvanceFault = ProductionRuntimeTestFailure("logical advance")
    let database = FileManager.default.temporaryDirectory
      .appendingPathComponent("logical-failure-\(UUID().uuidString).sqlite")
    try integration.initialize(database: database, validUntil: nil)
    let executionID = ProductionRuntimeInformationIntegration.executionID

    do {
      _ = try await integration.continueWithRealInformation(
        database: database,
        handle: nil,
        advancementID: "logical-advance-failure",
        evaluatedAtUTC: "2026-10-09T00:00:00Z"
      )
      XCTFail("logical advance failure must propagate")
    } catch let error as ProductionRuntimeInformationError {
      guard case .modelExecutionFailed = error else {
        throw XCTFailure("unexpected error: \(error)")
      }
    }

    let records = integration.runtimeLifecycleRecords(executionID: executionID)
    XCTAssertEqual(3, records.count)
    XCTAssertEqual(.created, records.first?.operation)
    XCTAssertEqual(.discarded, records.last?.operation)
    let audit = try integration.audit(database: database)
    XCTAssertEqual(
      "logical-advance-failure:logical_advance-failed",
      (audit["execution_state"] as? [String: Any])?["state_id"] as? String
    )
    XCTAssertEqual("BLOCKED", (audit["execution_state"] as? [String: Any])?["status"] as? String)
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
    let backend = MLXExecutionStateBackend()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: makeExecutor(),
      backend: backend
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
    XCTAssertEqual(4, records.count)
    XCTAssertEqual(.created, records.first?.operation)
    XCTAssertEqual(.continued, records[1].operation)
    XCTAssertEqual(.restored, records[2].operation)
    XCTAssertEqual(.discarded, records[3].operation)
    let finalHandle = try XCTUnwrap(integration.runtimeHandle(executionID: executionID))
    XCTAssertEqual(.discarded, finalHandle.lifecycle)
    XCTAssertThrowsError(try backend.boundPrefix(for: finalHandle)) { error in
      XCTAssertEqual(
        .noBoundRepresentation(finalHandle.id),
        error as? ExecutionStateBackendError
      )
    }
    let audit = try integration.audit(database: database)
    XCTAssertEqual("BLOCKED", (audit["execution_state"] as? [String: Any])?["status"] as? String)
    XCTAssertEqual(
      "representation-binding-failure:representation_binding-failed",
      (audit["execution_state"] as? [String: Any])?["state_id"] as? String
    )
  }

  func testConfirmationFailurePersistsBlockedAndRollsRuntimeBack() async throws {
    let configuration = try makeConfiguration()
    let backend = MLXExecutionStateBackend()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: makeExecutor(),
      backend: backend
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
    XCTAssertEqual(4, records.count)
    XCTAssertEqual(.created, records.first?.operation)
    XCTAssertEqual(.continued, records[1].operation)
    XCTAssertEqual(.restored, records[2].operation)
    XCTAssertEqual(.discarded, records[3].operation)
    let finalHandle = integration.runtimeHandle(executionID: executionID)
    XCTAssertEqual(.discarded, finalHandle?.lifecycle)
    if let finalHandle {
      XCTAssertThrowsError(try backend.boundPrefix(for: finalHandle)) { error in
        XCTAssertEqual(
          .noBoundRepresentation(finalHandle.id),
          error as? ExecutionStateBackendError
        )
      }
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
