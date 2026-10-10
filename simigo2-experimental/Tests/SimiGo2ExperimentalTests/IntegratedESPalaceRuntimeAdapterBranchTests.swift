import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

final class IntegratedESPalaceRuntimeAdapterBranchTests: XCTestCase {

  private struct FixtureCase {
    let caseID: String
    let manifestURL: URL
    let manifestSHA256: String
    let opaqueLocator: String
  }

  private let labRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private func fixtureCases() throws -> [FixtureCase] {
    let packageURL = labRoot.appendingPathComponent(
      "integrated-es-palace/integration-fixture-v1/FIXTURE_PACKAGE_MANIFEST.json"
    )
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: packageURL))
    guard let fixture = object as? [String: Any],
          let cases = fixture["cases"] as? [[String: Any]] else {
      throw XCTFailureForAdapterBranchTests("fixture package is malformed")
    }
    return try cases.map { item in
      guard let caseID = item["case_id"] as? String,
            let root = item["fixture_root"] as? String,
            let manifestSHA256 = item["manifest_sha256"] as? String else {
        throw XCTFailureForAdapterBranchTests("fixture case is malformed")
      }
      let manifestURL = labRoot.appendingPathComponent(
        "integrated-es-palace/integration-fixture-v1/\(root)/fixture-manifest.json"
      )
      let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
      guard let manifestObject = manifest as? [String: Any],
            let opaqueLocator = manifestObject["opaque_locator"] as? String else {
        throw XCTFailureForAdapterBranchTests("fixture manifest is malformed")
      }
      return FixtureCase(
        caseID: caseID,
        manifestURL: manifestURL,
        manifestSHA256: manifestSHA256,
        opaqueLocator: opaqueLocator
      )
    }
  }

  private func makeDecision(
    _ adapter: IntegratedESPalaceRuntimeAdapter,
    _ fixture: FixtureCase
  ) async throws -> IntegratedRuntimeDecision {
    let inventory = try adapter.loadInventory(
      fixtureManifestURL: fixture.manifestURL,
      expectedManifestSHA256: fixture.manifestSHA256,
      opaqueLocator: fixture.opaqueLocator
    )
    guard let sourceRecordDigest = stringValue(inventory.provenance["record_digest"]) else {
      throw XCTFailureForAdapterBranchTests("provenance digest is missing")
    }
    return try adapter.makeDecision(
      inventory: inventory,
      sourceRecordDigest: sourceRecordDigest
    )
  }

  func testContinueAdvancesRealRuntimeExactlyOnceAndBindsRepresentation() async throws {
    let backend = MLXExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let adapter = IntegratedESPalaceRuntimeAdapter(
      coordinator: coordinator,
      backend: backend
    )
    let fixture = try fixtureCases().first { $0.caseID == "P-LAWFUL" }
    let decision = try await makeDecision(adapter, fixture!)
    let receipt = try await adapter.applyToRealRuntime(
      executionID: ExecutionID("INTEGRATED-CONTINUE"),
      decision: decision
    )

    XCTAssertTrue(receipt.advanced)
    XCTAssertTrue(receipt.executionCreated)
    XCTAssertTrue(receipt.representationBound)
    XCTAssertNil(receipt.positionBefore)
    XCTAssertEqual(Int64(1), receipt.positionAfter)
    XCTAssertEqual(2, receipt.lifecycleRecordsAfter - receipt.lifecycleRecordsBefore)
    XCTAssertEqual(receipt.handle?.position.value, 1)
    XCTAssertEqual(receipt.representationPosition, receipt.handle?.position)
    XCTAssertEqual(
      try backend.boundPrefix(for: receipt.handle!).prefix,
      receipt.representationPrefix
    )
  }

  func testReusePerformsReadOnlyVerificationWithoutAdvancingOrRebinding() async throws {
    let backend = MLXExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let adapter = IntegratedESPalaceRuntimeAdapter(
      coordinator: coordinator,
      backend: backend
    )
    let fixture = try fixtureCases().first { $0.caseID == "P-SETTLED" }
    let decision = try await makeDecision(adapter, fixture!)
    let handle = try await coordinator.create(
      id: ExecutionID("INTEGRATED-REUSE"),
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(
        nextInput: decision.inputDigest,
        continuationID: decision.continuationIdentityDigest
      )
    )
    backend.bind(executionID: handle.id, position: handle.position, tokenPrefix: [7, 11])
    let beforeCount = coordinator.recordCount
    let beforePrefix = try backend.boundPrefix(for: handle)
    let receipt = try await adapter.applyToRealRuntime(
      executionID: handle.id,
      decision: decision
    )

    XCTAssertFalse(receipt.advanced)
    XCTAssertFalse(receipt.executionCreated)
    XCTAssertFalse(receipt.representationBound)
    XCTAssertEqual(beforeCount, receipt.lifecycleRecordsAfter)
    XCTAssertEqual(0, receipt.lifecycleRecordsAfter - receipt.lifecycleRecordsBefore)
    XCTAssertEqual(handle, receipt.handle)
    XCTAssertEqual(Int64(0), receipt.positionAfter)
    XCTAssertEqual(beforePrefix.prefix, receipt.representationPrefix)
    XCTAssertEqual(beforePrefix.position, receipt.representationPosition)
  }

  func testBlockWithExistingExecutionReturnsNoHandleAndPreservesState() async throws {
    let backend = MLXExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let adapter = IntegratedESPalaceRuntimeAdapter(
      coordinator: coordinator,
      backend: backend
    )
    let fixture = try fixtureCases().first { $0.caseID == "N-ILLEGAL" }
    let decision = try await makeDecision(adapter, fixture!)
    let handle = try await coordinator.create(
      id: ExecutionID("INTEGRATED-BLOCK-EXISTING"),
      position: ExecutionPosition(3),
      continuation: ExecutionContinuation(
        nextInput: decision.inputDigest,
        continuationID: decision.continuationIdentityDigest
      )
    )
    backend.bind(executionID: handle.id, position: handle.position, tokenPrefix: [31, 37])
    let beforeCount = coordinator.recordCount
    let beforePrefix = try backend.boundPrefix(for: handle)
    let receipt = try await adapter.applyToRealRuntime(
      executionID: handle.id,
      decision: decision
    )

    XCTAssertNil(receipt.handle)
    XCTAssertFalse(receipt.advanced)
    XCTAssertFalse(receipt.executionCreated)
    XCTAssertFalse(receipt.representationBound)
    XCTAssertEqual(beforeCount, receipt.lifecycleRecordsAfter)
    XCTAssertEqual(0, receipt.lifecycleRecordsAfter - receipt.lifecycleRecordsBefore)
    XCTAssertEqual(Int64(3), receipt.positionBefore)
    XCTAssertEqual(Int64(3), receipt.positionAfter)
    XCTAssertEqual(handle, coordinator.handle(handle.id))
    XCTAssertEqual(handle.position, coordinator.handle(handle.id)?.position)
    XCTAssertEqual(beforePrefix.prefix, try backend.boundPrefix(for: handle).prefix)
    XCTAssertEqual(beforePrefix.position, try backend.boundPrefix(for: handle).position)
  }

  func testReuseIdentityMismatchFailsClosedWithoutLifecycleOrRebind() async throws {
    let backend = MLXExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let adapter = IntegratedESPalaceRuntimeAdapter(
      coordinator: coordinator,
      backend: backend
    )
    let fixture = try fixtureCases().first { $0.caseID == "P-SETTLED" }
    let decision = try await makeDecision(adapter, fixture!)
    let mismatched = IntegratedRuntimeDecision(
      decision: decision.decision,
      continuationClass: decision.continuationClass,
      precedenceReason: decision.precedenceReason,
      inputDigest: decision.inputDigest + "-mismatch",
      outputDigest: decision.outputDigest,
      continuationIdentityDigest: decision.continuationIdentityDigest + "-mismatch"
    )
    let handle = try await coordinator.create(
      id: ExecutionID("INTEGRATED-REUSE-MISMATCH"),
      position: ExecutionPosition(2),
      continuation: ExecutionContinuation(
        nextInput: "unrelated-next-input",
        continuationID: "unrelated-continuation-id"
      )
    )
    backend.bind(executionID: handle.id, position: handle.position, tokenPrefix: [41, 43])
    let beforeCount = coordinator.recordCount
    let beforePrefix = try backend.boundPrefix(for: handle)

    do {
      _ = try await adapter.applyToRealRuntime(
        executionID: handle.id,
        decision: mismatched
      )
      XCTFail("reuse identity mismatch must fail closed")
    } catch let error as IntegratedESPalaceAdapterError {
      XCTAssertEqual(.reuseIdentityMismatch, error)
    }

    XCTAssertEqual(beforeCount, coordinator.recordCount)
    XCTAssertEqual(handle, coordinator.handle(handle.id))
    XCTAssertEqual(Int64(2), coordinator.handle(handle.id)?.position.value)
    XCTAssertEqual(beforePrefix.prefix, try backend.boundPrefix(for: handle).prefix)
    XCTAssertEqual(beforePrefix.position, try backend.boundPrefix(for: handle).position)
  }

  func testAllNegativeDecisionsDoNotCreateAdvanceOrBindRealRuntime() async throws {
    let backend = MLXExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let adapter = IntegratedESPalaceRuntimeAdapter(
      coordinator: coordinator,
      backend: backend
    )
    let negativeCases = try fixtureCases().filter { $0.caseID.hasPrefix("N-") }
    XCTAssertEqual(4, negativeCases.count)
    let beforeCount = coordinator.recordCount

    for fixture in negativeCases {
      let decision = try await makeDecision(adapter, fixture)
      XCTAssertEqual("BLOCK", decision.decision)
      let executionID = ExecutionID("INTEGRATED-BLOCK-\(fixture.caseID)")
      let receipt = try await adapter.applyToRealRuntime(
        executionID: executionID,
        decision: decision
      )
      XCTAssertNil(receipt.handle, fixture.caseID)
      XCTAssertFalse(receipt.advanced, fixture.caseID)
      XCTAssertFalse(receipt.executionCreated, fixture.caseID)
      XCTAssertFalse(receipt.representationBound, fixture.caseID)
      XCTAssertNil(receipt.representationPrefix, fixture.caseID)
      XCTAssertNil(coordinator.handle(executionID), fixture.caseID)
    }
    XCTAssertEqual(beforeCount, coordinator.recordCount)
  }
}

private func stringValue(_ value: AnyCodableValue?) -> String? {
  if case .string(let string)? = value { return string }
  return nil
}

func XCTFailureForAdapterBranchTests(_ message: String) -> Error {
  NSError(domain: "IntegratedESPalaceRuntimeAdapterBranchTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
