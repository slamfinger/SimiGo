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

  private func makeIsolatedConfiguration(
    defaultValidity: String = "2030-12-31T23:59:59Z"
  ) throws -> (
    configuration: ProductionRuntimeLaunchConfiguration,
    directory: URL
  ) {
    let labRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("simigo-isolated-policy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let policy = directory.appendingPathComponent("validity-policy.json")
    let policyObject: [String: Any] = [
      "schema_id": "SIMIGO-INFO-VALIDITY-POLICY-V1",
      "policy_version": "production-runtime-integration-test",
      "policy_source": "ISOLATED_TEST_ONLY",
      "missing_policy": "REJECT",
      "dependency_propagation": "ALL_TRANSITIVE",
      "default_valid_until_utc": defaultValidity,
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

  func testRealSimiGoRuntimeDrivesAcceptedRealPalaceInformationLoop() async throws {
    let database = try makeTemporaryDatabase()
    let handleURL = database.deletingLastPathComponent()
      .appendingPathComponent("production-execution-state.json")
    let isolated = try makeIsolatedConfiguration()
    let integration = ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration
    )
    integration.attachModelExecutor(ProductionRuntimeModelExecutorStub())
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
    let restarted = ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration
    )
    restarted.attachModelExecutor(ProductionRuntimeModelExecutorStub())
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

  // ES recovery from IS + durable state, with no side-channel handle file.
  // The old authority (and its backend) is destroyed; a brand-new ES on a fresh
  // backend recovers the settled execution state, reuses IS results, and proves
  // it did NOT fabricate the prefix by re-tokenizing the seed.
  func testNewExecutionStateRecoversSettledWorkFromInformationSpaceWithoutBypassFile() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateDirectory = isolated.directory.appendingPathComponent("es-state", isDirectory: true)

    // Phase 001: the first authority settles real PALACE work under the durable
    // store. Its backend is a distinct instance we can later discard.
    let firstBackend = MLXExecutionStateBackend()
    let firstExecutor = ProductionRuntimeModelExecutorStub()
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: firstExecutor,
      backend: firstBackend,
      semanticStateDirectory: stateDirectory
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    let phaseOne = try await first.continueWithRealInformation(
      database: database,
      handle: nil,
      advancementID: "rec-001",
      evaluatedAtUTC: "2026-10-09T00:00:00Z"
    )
    XCTAssertEqual(phaseOne.report.computedItemIDs.count, 9)
    XCTAssertTrue(phaseOne.report.reusedItemIDs.isEmpty)
    XCTAssertEqual(phaseOne.handle.position, ExecutionPosition(1))
    // The first-ever bind legitimately tokenized the seed exactly once.
    XCTAssertEqual(firstExecutor.tokenizeSeedCallCount, 1)

    // A NEW integration over a FRESH backend (no prior binding) recovers the ES.
    // No SerializedProductionExecutionState sidecar file was written on this
    // path: the ES identity comes from the durable store, the resume authority
    // from the Information Space.
    let recoveredBackend = MLXExecutionStateBackend()
    XCTAssertThrowsError(try recoveredBackend.boundPrefix(for: phaseOne.handle))
    let recoveredExecutor = ProductionRuntimeModelExecutorStub()
    let second = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: recoveredExecutor,
      backend: recoveredBackend,
      semanticStateDirectory: stateDirectory
    )
    let recovered = try await second.recoverExecutionState(database: database)
    XCTAssertEqual(recovered.id, ProductionRuntimeInformationIntegration.executionID)
    XCTAssertEqual(recovered.position, ExecutionPosition(1))
    XCTAssertEqual(recovered.lifecycle, .active)
    // The recovered physical prefix is the SETTLed post-generation payload
    // persisted under the store ([9,18,27]) — not a re-tokenized seed.
    let recoveredBound = try recoveredBackend.boundPrefix(for: recovered)
    XCTAssertEqual(recoveredBound.prefix, [9, 18, 27])

    // Continue the NEW ES: IS independently reuses all settled results, and this
    // recovered run NEVER re-tokenizes the seed → proven reuse, not recompute.
    let phaseTwo = try await second.continueWithRealInformation(
      database: database,
      handle: recovered,
      advancementID: "rec-002",
      evaluatedAtUTC: "2026-10-09T00:01:00Z"
    )
    XCTAssertEqual(phaseTwo.report.state, "ADVANCED")
    XCTAssertTrue(phaseTwo.report.computedItemIDs.isEmpty)
    XCTAssertEqual(phaseTwo.report.reusedItemIDs.count, 9)
    XCTAssertEqual(recoveredExecutor.tokenizeSeedCallCount, 0)
    XCTAssertEqual(recoveredExecutor.continueExecutionCallCount, 1)

    // Selective invalidation on the recovered ES recomputes only what broke.
    try second.invalidate(
      database: database,
      itemID: "REAL-3",
      reason: "selective invalidation after recovery"
    )
    let phaseThree = try await second.continueWithRealInformation(
      database: database,
      handle: phaseTwo.handle,
      advancementID: "rec-003",
      evaluatedAtUTC: "2026-10-09T00:02:00Z"
    )
    XCTAssertEqual(phaseThree.report.computedItemIDs, ["REAL-3", "REAL-4"])
    XCTAssertEqual(phaseThree.report.reusedItemIDs.count, 7)
    // Still never rebuilt the prefix from a seed across the recovered session.
    XCTAssertEqual(recoveredExecutor.tokenizeSeedCallCount, 0)
  }

  // IS is the recovery authority: an execution space that has settled nothing
  // cannot authorize recovering an ES, even if a durable handle existed.
  func testRecoveryFailsClosedWhenInformationSpaceHasNoSettledWork() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateDirectory = isolated.directory
      .appendingPathComponent("es-state-empty-\(UUID().uuidString)", isDirectory: true)
    let integration = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub(),
      semanticStateDirectory: stateDirectory
    )
    try integration.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    do {
      _ = try await integration.recoverExecutionState(database: database)
      XCTFail("recovery must fail closed when IS has no settled execution state")
    } catch let error as ProductionRuntimeInformationError {
      guard case .informationSpaceHasNoSettledExecution = error else {
        return XCTFail("unexpected recovery error: \(error)")
      }
    }
  }

  // A stateless production runtime has no durable ES to recover from.
  func testRecoveryRequiresDurableStoreConfiguration() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateless = ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub()
    )
    do {
      _ = try await stateless.recoverExecutionState(database: database)
      XCTFail("stateless runtime must refuse ES recovery")
    } catch let error as ProductionRuntimeInformationError {
      XCTAssertEqual(.durableRecoveryNotConfigured, error)
    }
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
    let isolated = try makeIsolatedConfiguration(defaultValidity: "2020-01-01T00:00:00Z")
    let integration = ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration
    )
    integration.attachModelExecutor(ProductionRuntimeModelExecutorStub())
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
    let staleStatus = status["execution_state"] as? [String: Any]
    XCTAssertEqual(staleStatus?["state_id"] as? String, "blocked-phase")
    XCTAssertEqual(staleStatus?["status"] as? String, "BLOCKED")
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
      XCTAssertEqual(state, "BLOCKED_MISSING_VALIDITY")
      XCTAssertEqual(validityFailureItemIDs.count, 9)
      XCTAssertEqual(validityFailureItemIDs.count, Set(validityFailureItemIDs).count)
    }

    let status = try integration.status(database: database)
    let missingStatus = status["execution_state"] as? [String: Any]
    XCTAssertEqual(missingStatus?["state_id"] as? String, "missing-validity-phase")
    XCTAssertEqual(missingStatus?["status"] as? String, "BLOCKED")
  }

  func testUnknownPersistedLifecycleFailsClosedWithoutAdvanceOrSettlement() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let handleURL = database.deletingLastPathComponent()
      .appendingPathComponent("corrupt-production-execution-state.json")
    let integration = ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration
    )
    integration.attachModelExecutor(ProductionRuntimeModelExecutorStub())
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

  // MARK: - ES ↔ IS settlement-checkpoint cross-validation

  private func openStore(at directory: URL) -> DurableExecutionStateStore {
    DurableExecutionStateStore(
      directory: directory,
      payloadCodec: MLXPrefixPayloadPersistence(
        backendIdentity: ProductionRuntimeInformationIntegration.prefixBackendIdentity))
  }

  private func latestExecutionState(
    _ integration: ProductionRuntimeInformationIntegration,
    database: URL
  ) throws -> [String: Any]? {
    try integration.status(database: database)["execution_state"] as? [String: Any]
  }

  private func makeStateDirectory(
    in isolated: (configuration: ProductionRuntimeLaunchConfiguration, directory: URL),
    _ name: String
  ) -> URL {
    isolated.directory.appendingPathComponent("es-state-\(name)-\(UUID().uuidString)", isDirectory: true)
  }

  // Positive proof that the trap is handled: after confirmation IS's latest
  // record is `<advancement>:runtime-applied`, NOT the raw advancement id, so a
  // correctly recovered ES whose checkpoint links the confirmation (via its
  // prior_state_id back to the advancement) must be ACCEPTED, not rejected.
  func testRecoveryAcceptsConfirmationRecordNotRawAdvancementID() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateDirectory = makeStateDirectory(in: isolated, "accept")
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub(),
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    _ = try await first.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "cross-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

    // IS's latest is the completion confirmation, not the raw advancement id.
    let isState = try XCTUnwrap(latestExecutionState(first, database: database))
    XCTAssertEqual(isState["state_id"] as? String, "cross-001:runtime-applied")
    XCTAssertEqual(isState["prior_state_id"] as? String, "cross-001")
    XCTAssertEqual(isState["runtime_application_status"] as? String, "APPLIED_SWIFT")

    let checkpoint = try XCTUnwrap(
      openStore(at: stateDirectory).load().settlementCheckpoints[
        ProductionRuntimeInformationIntegration.executionID])
    // The checkpoint keeps the two ids distinct and the ES advancement differs
    // from the latest state id — a naive equality check would wrongly reject.
    XCTAssertEqual(checkpoint.isConfirmationStateID, "cross-001:runtime-applied")
    XCTAssertEqual(checkpoint.isOriginalStateID, "cross-001")
    XCTAssertEqual(checkpoint.lastSettledAdvancementID, "cross-001")
    XCTAssertNotEqual(checkpoint.lastSettledAdvancementID, isState["state_id"] as? String)

    // A brand-new ES over a fresh backend recovers WITHOUT being wrongly denied.
    let recoverExecutor = ProductionRuntimeModelExecutorStub()
    let second = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: recoverExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    let recovered = try await second.recoverExecutionState(database: database)
    XCTAssertEqual(recovered.position, ExecutionPosition(1))
    XCTAssertEqual(recovered.lifecycle, .active)
    // Recovery is a pure read/rebind: no model work was performed.
    XCTAssertEqual(recoverExecutor.tokenizeSeedCallCount, 0)
    XCTAssertEqual(recoverExecutor.tokenizeTextCallCount, 0)
    XCTAssertEqual(recoverExecutor.continueExecutionCallCount, 0)
  }

  // ES checkpoint points at an OLD advancement while IS has advanced: recovery
  // must reject (confirmation record no longer matches), with no model calls and
  // no extra IS settlement produced.
  func testRecoveryFailsClosedWhenInformationSpaceAdvancedBeyondESCheckpoint() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let staleStoreDirectory = makeStateDirectory(in: isolated, "stale-es")

    // ES settles rec-001 under its durable store.
    let firstExecutor = ProductionRuntimeModelExecutorStub()
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: firstExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: staleStoreDirectory
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    _ = try await first.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "rec-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

    // IS independently advances to rec-002 via a separate authority/store, so
    // the first ES's checkpoint now lags the Information Space.
    let advancer = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub(),
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: makeStateDirectory(in: isolated, "advancer")
    )
    _ = try await advancer.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "rec-002", evaluatedAtUTC: "2026-10-09T00:01:00Z")
    let isLatest = try XCTUnwrap(latestExecutionState(advancer, database: database))
    XCTAssertEqual(isLatest["state_id"] as? String, "rec-002:runtime-applied")

    // Recovering the stale ES must fail closed on the confirmation mismatch.
    let recoverExecutor = ProductionRuntimeModelExecutorStub()
    let stale = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: recoverExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: staleStoreDirectory
    )
    do {
      _ = try await stale.recoverExecutionState(database: database)
      XCTFail("stale ES checkpoint must be rejected against advanced IS")
    } catch let error as ProductionRuntimeInformationError {
      guard case .settlementCheckpointMismatch(_, let field) = error else {
        return XCTFail("unexpected recovery error: \(error)")
      }
      XCTAssertEqual(field, "confirmation_state_id")
    }
    // Rejection performed no model work and did not advance/settle IS further.
    XCTAssertEqual(recoverExecutor.tokenizeSeedCallCount, 0)
    XCTAssertEqual(recoverExecutor.tokenizeTextCallCount, 0)
    XCTAssertEqual(recoverExecutor.continueExecutionCallCount, 0)
    let after = try XCTUnwrap(latestExecutionState(stale, database: database))
    XCTAssertEqual(after["state_id"] as? String, "rec-002:runtime-applied")
  }

  // Continuing a stale ES is rejected BEFORE the execute side effect: no new
  // model call, no extra advancement, and no new (wrongly settled/blocked) IS
  // state is recorded.
  func testContinueFailsClosedWhenESCheckpointStaleBeforeAnyAdvance() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let staleStoreDirectory = makeStateDirectory(in: isolated, "stale-continue")

    let firstExecutor = ProductionRuntimeModelExecutorStub()
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: firstExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: staleStoreDirectory
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    let phaseOne = try await first.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "rec-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")
    let seedCallsAfterOne = firstExecutor.tokenizeSeedCallCount
    let textCallsAfterOne = firstExecutor.tokenizeTextCallCount
    let continueCallsAfterOne = firstExecutor.continueExecutionCallCount

    // IS advances past the ES's checkpoint via an independent authority.
    let advancer = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub(),
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: makeStateDirectory(in: isolated, "advancer")
    )
    _ = try await advancer.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "rec-002", evaluatedAtUTC: "2026-10-09T00:01:00Z")

    // Now the SAME ES authority tries to continue: it must be rejected first.
    do {
      _ = try await first.continueWithRealInformation(
        database: database, handle: phaseOne.handle,
        advancementID: "rec-003", evaluatedAtUTC: "2026-10-09T00:02:00Z")
      XCTFail("stale ES must not continue over an advanced IS")
    } catch let error as ProductionRuntimeInformationError {
      guard case .settlementCheckpointMismatch(_, let field) = error else {
        return XCTFail("unexpected continue error: \(error)")
      }
      XCTAssertEqual(field, "confirmation_state_id")
    }

    // No new model call was issued for the rejected attempt.
    XCTAssertEqual(firstExecutor.tokenizeSeedCallCount, seedCallsAfterOne)
    XCTAssertEqual(firstExecutor.tokenizeTextCallCount, textCallsAfterOne)
    XCTAssertEqual(firstExecutor.continueExecutionCallCount, continueCallsAfterOne)
    // IS did not advance or get wrongly settled/blocked by the rejection: the
    // latest settled state is still rec-002's confirmation and rec-003 never
    // appears anywhere in the execution-state lineage.
    let afterAudit = try first.audit(database: database)
    XCTAssertEqual(
      (afterAudit["execution_state"] as? [String: Any])?["state_id"] as? String,
      "rec-002:runtime-applied")
    let afterLatest = try XCTUnwrap(latestExecutionState(first, database: database))
    XCTAssertFalse((afterLatest["state_id"] as? String ?? "").contains("rec-003"))
  }

  // A tampered result digest in the persisted ES checkpoint is rejected.
  func testRecoveryFailsClosedWhenESCheckpointResultDigestTampered() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateDirectory = makeStateDirectory(in: isolated, "digest")
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub(),
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    _ = try await first.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "cross-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

    let store = openStore(at: stateDirectory)
    let loaded = try store.load()
    let id = ProductionRuntimeInformationIntegration.executionID
    let original = try XCTUnwrap(loaded.settlementCheckpoints[id])
    let tampered = ExecutionContinuityCoordinator.SettlementCheckpoint(
      executionID: original.executionID,
      position: original.position,
      lastSettledAdvancementID: original.lastSettledAdvancementID,
      isOriginalStateID: original.isOriginalStateID,
      isConfirmationStateID: original.isConfirmationStateID,
      resultDigest: "TAMPERED-DIGEST",
      validityBasis: original.validityBasis)
    try store.replace(
      handles: loaded.handles,
      lifecycleRecords: loaded.lifecycleRecords,
      representations: loaded.representations,
      settlementCheckpoints: [id: tampered])

    let recoverExecutor = ProductionRuntimeModelExecutorStub()
    let second = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: recoverExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    do {
      _ = try await second.recoverExecutionState(database: database)
      XCTFail("tampered result digest must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .settlementCheckpointMismatch(_, let field) = error else {
        return XCTFail("unexpected recovery error: \(error)")
      }
      XCTAssertEqual(field, "result_digest")
    }
    XCTAssertEqual(recoverExecutor.continueExecutionCallCount, 0)
  }

  // A durable ES handle with NO settlement checkpoint cannot be proven to match
  // IS, so recovery fails closed rather than resuming an unlinked ES.
  func testRecoveryFailsClosedWhenESCarriesNoSettlementCheckpoint() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateDirectory = makeStateDirectory(in: isolated, "no-checkpoint")
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub(),
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    _ = try await first.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "cross-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

    // Drop the checkpoint while KEEPING the durable handle/representations.
    let store = openStore(at: stateDirectory)
    let loaded = try store.load()
    XCTAssertFalse(loaded.settlementCheckpoints.isEmpty)
    try store.replace(
      handles: loaded.handles,
      lifecycleRecords: loaded.lifecycleRecords,
      representations: loaded.representations,
      settlementCheckpoints: [:])

    let recoverExecutor = ProductionRuntimeModelExecutorStub()
    let second = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: recoverExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    XCTAssertNotNil(second.runtimeHandle(executionID: ProductionRuntimeInformationIntegration.executionID))
    do {
      _ = try await second.recoverExecutionState(database: database)
      XCTFail("ES without a settlement checkpoint must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .settlementCheckpointMissing = error else {
        return XCTFail("unexpected recovery error: \(error)")
      }
    }
    XCTAssertEqual(recoverExecutor.continueExecutionCallCount, 0)
  }

  // Only IS has settled state: with no durable ES handle, recovery is denied.
  func testRecoveryFailsClosedWhenESDurableHandleMissingDespiteSettledIS() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let settledStore = makeStateDirectory(in: isolated, "settled")
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub(),
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: settledStore
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    _ = try await first.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "cross-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

    // A recovery authority over an EMPTY durable store has settled IS but no ES.
    let recoverExecutor = ProductionRuntimeModelExecutorStub()
    let orphan = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: recoverExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: makeStateDirectory(in: isolated, "empty-es")
    )
    do {
      _ = try await orphan.recoverExecutionState(database: database)
      XCTFail("settled IS with no durable ES must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .durableExecutionStateMissing = error else {
        return XCTFail("unexpected recovery error: \(error)")
      }
    }
    XCTAssertEqual(recoverExecutor.continueExecutionCallCount, 0)
  }

  // Only the ES has persisted state: against an execution space that settled
  // nothing, recovery is denied even though a durable ES + checkpoint exist.
  func testRecoveryFailsClosedWhenESHasCheckpointButISHasNoSettledExecution() async throws {
    let settledDatabase = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateDirectory = makeStateDirectory(in: isolated, "es-only")
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: ProductionRuntimeModelExecutorStub(),
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    try first.initialize(database: settledDatabase, validUntil: "2030-12-31T23:59:59Z")
    _ = try await first.continueWithRealInformation(
      database: settledDatabase, handle: nil,
      advancementID: "cross-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

    // Fresh database has settled nothing; recover the ES store against it.
    let emptyDatabase = try makeTemporaryDatabase()
    let recoverExecutor = ProductionRuntimeModelExecutorStub()
    let second = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: recoverExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    try second.initialize(database: emptyDatabase, validUntil: "2030-12-31T23:59:59Z")
    do {
      _ = try await second.recoverExecutionState(database: emptyDatabase)
      XCTFail("ES with an unsettled IS must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .informationSpaceHasNoSettledExecution = error else {
        return XCTFail("unexpected recovery error: \(error)")
      }
    }
    XCTAssertEqual(recoverExecutor.continueExecutionCallCount, 0)
  }

  // The objective's central invariant, made directly testable: ES recovery must
  // NOT depend on a side-channel handle file to know WHICH ES to restore. A
  // stale bypass JSON that points at a wrong position/identity must be ignored,
  // and recovery must still succeed (identically) once that file is deleted —
  // proving the durable store + Information Space are the sole recovery basis.
  func testRecoveryDependsOnlyOnDurableStateAndISNotBypassHandleFile() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateDirectory = makeStateDirectory(in: isolated, "bypass-independent")

    // Settle rec-001 under the durable store on a backend we then abandon.
    let firstExecutor = ProductionRuntimeModelExecutorStub()
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: firstExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    _ = try await first.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "rec-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

    // Plant a STALE bypass handle file that misleads a naive recovery: wrong
    // position and continuation, but the correct execution id.
    let handleURL = database.deletingLastPathComponent()
      .appendingPathComponent("production-execution-state.json")
    let stale = SerializedProductionExecutionState(
      id: ProductionRuntimeInformationIntegration.executionID.rawValue,
      lineageRoot: ProductionRuntimeInformationIntegration.executionID.rawValue,
      lineageParent: nil,
      position: 42,
      nextInput: "stale-bypass-next-input",
      continuationID: "stale-bypass-cont",
      lifecycle: ExecutionBranchLifecycle.active.rawValue)
    try JSONEncoder().encode(stale).write(to: handleURL, options: .atomic)

    // Recovery with the stale file PRESENT must reflect the durable store (the
    // settled position 1) and the persisted prefix — never the file's position 42.
    let executorA = ProductionRuntimeModelExecutorStub()
    let backendA = MLXExecutionStateBackend()
    let recoverA = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: executorA,
      backend: backendA,
      semanticStateDirectory: stateDirectory
    )
    let recoveredA = try await recoverA.recoverExecutionState(database: database)
    XCTAssertEqual(recoveredA.position, ExecutionPosition(1))
    XCTAssertNotEqual(recoveredA.position, ExecutionPosition(42))
    XCTAssertEqual(recoveredA.continuation.nextInput, "\(ProductionRuntimeInformationIntegration.continuationPoint):rec-001")
    XCTAssertEqual(try backendA.boundPrefix(for: recoveredA).prefix, [9, 18, 27])
    XCTAssertEqual(executorA.tokenizeSeedCallCount, 0)

    // Now DELETE the bypass file entirely and recover AGAIN from a fresh backend:
    // the result is identical, proving recovery never needed the side-channel.
    try FileManager.default.removeItem(at: handleURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: handleURL.path))
    let executorB = ProductionRuntimeModelExecutorStub()
    let backendB = MLXExecutionStateBackend()
    let recoverB = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: executorB,
      backend: backendB,
      semanticStateDirectory: stateDirectory
    )
    let recoveredB = try await recoverB.recoverExecutionState(database: database)
    XCTAssertEqual(recoveredB.position, ExecutionPosition(1))
    XCTAssertEqual(try backendB.boundPrefix(for: recoveredB).prefix, [9, 18, 27])
    XCTAssertEqual(executorB.tokenizeSeedCallCount, 0)

    // The recovered ES continues purely from IS: all settled results reuse, no
    // recompute, no re-tokenization — real reuse, not prefix recreation.
    let phaseTwo = try await recoverB.continueWithRealInformation(
      database: database, handle: recoveredB,
      advancementID: "rec-002", evaluatedAtUTC: "2026-10-09T00:01:00Z")
    XCTAssertEqual(phaseTwo.report.state, "ADVANCED")
    XCTAssertTrue(phaseTwo.report.computedItemIDs.isEmpty)
    XCTAssertEqual(phaseTwo.report.reusedItemIDs.count, 9)
    XCTAssertEqual(executorB.tokenizeSeedCallCount, 0)
    XCTAssertEqual(executorB.continueExecutionCallCount, 1)
  }

  // req2 hardening: a durable resume whose SETTLED PHYSICAL CARRIER is missing
  // must fail closed BEFORE advancing the Information Space — it must NOT
  // silently re-tokenize a seed prefix (fabricating "recovered work") and must
  // not leave IS one advancement further than the ES can prove. The pre-execute
  // recoverability guard enforces this at the production (durable) path.
  func testDurableResumeFailsClosedWhenSettledCarrierUnavailableBeforeAnyAdvance() async throws {
    let database = try makeTemporaryDatabase()
    let isolated = try makeIsolatedConfiguration()
    let stateDirectory = makeStateDirectory(in: isolated, "carrier-missing")

    // Settle rec-001 under the durable store (creates handle, representation,
    // checkpoint at position 1).
    let firstExecutor = ProductionRuntimeModelExecutorStub()
    let first = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: firstExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
    let phaseOne = try await first.continueWithRealInformation(
      database: database, handle: nil,
      advancementID: "rec-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

    // Drop the persisted REPRESENTATIONS only, keeping the handle, lifecycle
    // records and settlement checkpoint — so the ES↔IS checkpoint still matches
    // IS, but the physical carrier cannot be recovered.
    let store = openStore(at: stateDirectory)
    let loaded = try store.load()
    XCTAssertFalse(loaded.representations.isEmpty)
    XCTAssertFalse(loaded.settlementCheckpoints.isEmpty)
    try store.replace(
      handles: loaded.handles,
      lifecycleRecords: loaded.lifecycleRecords,
      representations: [],
      settlementCheckpoints: loaded.settlementCheckpoints)

    let resumeExecutor = ProductionRuntimeModelExecutorStub()
    let second = try ProductionRuntimeInformationIntegration(
      configuration: isolated.configuration,
      modelExecutor: resumeExecutor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory
    )
    do {
      _ = try await second.continueWithRealInformation(
        database: database, handle: phaseOne.handle,
        advancementID: "rec-002", evaluatedAtUTC: "2026-10-09T00:01:00Z")
      XCTFail("durable resume over an unrecoverable carrier must fail closed")
    } catch let error as ProductionRuntimeInformationError {
      guard case .persistedRepresentationUnavailable = error else {
        return XCTFail("unexpected resume error: \(error)")
      }
    }

    // No model work was performed (no seed recompute, no next-input tokenize).
    XCTAssertEqual(resumeExecutor.tokenizeSeedCallCount, 0)
    XCTAssertEqual(resumeExecutor.tokenizeTextCallCount, 0)
    XCTAssertEqual(resumeExecutor.continueExecutionCallCount, 0)
    // Fail-closed BEFORE execute: IS did not advance — latest is still rec-001's
    // confirmation and rec-002 never appears in the execution-state lineage.
    let latest = try XCTUnwrap(latestExecutionState(second, database: database))
    XCTAssertEqual(latest["state_id"] as? String, "rec-001:runtime-applied")
    XCTAssertFalse((latest["state_id"] as? String ?? "").contains("rec-002"))
  }
}
