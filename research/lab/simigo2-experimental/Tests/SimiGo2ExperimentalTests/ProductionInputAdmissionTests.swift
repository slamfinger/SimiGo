import Crypto
import Foundation
import XCTest
import SimiGo2Experimental
import SimiGoRuntimeContract

/// Proves the ORDINARY production task entry refuses an inadmissible
/// settlement BEFORE tokenization, seed tokenization or model generation, and
/// leaves the Information Space database and the execution-state directory
/// untouched. The entry under test is `continueTask`, the same call a normal
/// task scheduler makes; no handoff-specific orchestration is involved.
///
/// The fixtures are produced by `execution-information-loop/admission_selftest.py`
/// so the mutations here are the same code the Python admission selftest
/// verifies, not a second hand-written copy.
final class ProductionInputAdmissionTests: XCTestCase {
  private let labRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private final class CountingExecutor:
    ProductionRuntimeModelContinuationExecutor, @unchecked Sendable
  {
    private let lock = NSLock()
    private var tokenizeTextCalls = 0
    private var tokenizeSeedCalls = 0
    private var continuationCalls = 0

    var snapshot: [String: Int] {
      lock.lock()
      defer { lock.unlock() }
      return [
        "tokenize_text_calls": tokenizeTextCalls,
        "tokenize_seed_calls": tokenizeSeedCalls,
        "model_continuation_calls": continuationCalls,
      ]
    }

    func tokenizeText(_ text: String) async throws -> [Int] {
      lock.lock()
      tokenizeTextCalls += 1
      lock.unlock()
      return [1, 2, 3]
    }

    func tokenizeSeedText(_ text: String) async throws -> [Int] {
      lock.lock()
      tokenizeSeedCalls += 1
      lock.unlock()
      return [4, 5, 6]
    }

    func continueExecution(
      _ state: ExecutionStateHandle,
      nextInputTokens: [Int],
      maxTokens: Int
    ) async throws -> ExecutionContinuationResult {
      lock.lock()
      continuationCalls += 1
      lock.unlock()
      return ExecutionContinuationResult(
        executionID: state.id,
        consumedPrefixLength: 0,
        nextInputTokenCount: nextInputTokens.count,
        generatedTokenIDs: [9],
        generatedText: "STUB",
        updatedPayload: MLXPrefixPayload(tokenPrefix: [9])
      )
    }
  }

  private struct FixtureFailure: Error, CustomStringConvertible {
    let description: String
  }

  private func emitFixture(
    _ condition: String, to directory: URL
  ) throws -> (database: URL, trustAnchorPath: String) {
    let database = directory.appendingPathComponent("\(condition).sqlite")
    let script = labRoot.appendingPathComponent(
      "execution-information-loop/admission_selftest.py")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [
      script.path, "--emit-fixture", condition, "--out-database", database.path,
    ]
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let payload = try JSONSerialization.jsonObject(with: outputData) as? [String: Any],
          payload["ok"] as? Bool == true,
          let anchorPath = payload["trust_anchor_path"] as? String else {
      throw FixtureFailure(description: "fixture \(condition) failed: "
        + String(decoding: errorData, as: UTF8.self)
        + String(decoding: outputData, as: UTF8.self))
    }
    return (database, anchorPath)
  }

  private func directoryIdentity(_ directory: URL) throws -> [String: String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: []
    ) else {
      return [:]
    }
    let base = directory.standardizedFileURL.path
    var identity: [String: String] = [:]
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else { continue }
      let path = url.standardizedFileURL.path
      let relative = path.hasPrefix(base + "/")
        ? String(path.dropFirst(base.count + 1))
        : path
      let data = try Data(contentsOf: url)
      identity[relative] = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }.joined()
    }
    return identity
  }

  private func makeIntegration(
    executor: CountingExecutor,
    stateDirectory: URL
  ) throws -> ProductionRuntimeInformationIntegration {
    let configuration = ProductionRuntimeLaunchConfiguration(
      runtimeRoot: labRoot.appendingPathComponent("execution-information-loop"),
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
      snapshotPath: labRoot.appendingPathComponent(
        "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"),
      validityPolicyPath: labRoot.appendingPathComponent(
        "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json")
    )
    return try ProductionRuntimeInformationIntegration(
      configuration: configuration,
      modelExecutor: executor,
      backend: MLXExecutionStateBackend(),
      semanticStateDirectory: stateDirectory,
      resetToFreshBaseline: false
    )
  }

  func testOrdinaryTaskEntryRefusesInadmissibleSettlementBeforeGeneration() async throws {
    let expectations: [(condition: String, stage: String, itemID: String)] = [
      ("missing-settlement", "SETTLEMENT_NOT_ADMITTED", "TASK-U1"),
      ("tampered-object-bytes", "SETTLEMENT_OBJECT_UNREADABLE", "TASK-U1"),
      ("dependency-mismatch", "INPUT_BINDING_DEPENDENCY_NOT_DECLARED", "TASK-U2"),
      ("forged-u1-settlement", "SETTLEMENT_SIGNATURE_INVALID", "TASK-U1"),
    ]
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("simigo-admission-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // Each case exports its own fixture anchor. The root is deleted at the end
    // of the test, so the export must be cleared too: a dangling anchor path in
    // the process environment would otherwise fail closed for every later suite.
    defer {
      unsetenv(SettlementTrustFixture.anchorEnvironment)
      try? FileManager.default.removeItem(at: root)
    }

    for expectation in expectations {
      let fixture = try emitFixture(expectation.condition, to: root)
      let database = fixture.database
      setenv(SettlementTrustFixture.anchorEnvironment, fixture.trustAnchorPath, 1)
      let stateDirectory = root.appendingPathComponent(
        "state-\(expectation.condition)", isDirectory: true)
      try FileManager.default.createDirectory(
        at: stateDirectory, withIntermediateDirectories: true)
      let executor = CountingExecutor()
      let integration = try makeIntegration(
        executor: executor, stateDirectory: stateDirectory)

      let databaseBefore = try Data(contentsOf: database)
      let stateBefore = try directoryIdentity(stateDirectory)
      var modelValueBuilderCalls = 0
      var observed: ProductionRuntimeInformationError?

      do {
        _ = try await integration.continueTask(
          database: database,
          handle: nil,
          advancementID: "admission-test-\(expectation.condition)",
          evaluatedAtUTC: "2026-10-23T00:00:00Z",
          demandID: "handoff-u2",
          taskItemID: "TASK-U2",
          seedText: "admission test seed",
          provenance: ProductionTaskProvenance(
            runID: "admission-test-\(expectation.condition)",
            buildSHA256: ProductionTaskProvenance.buildIdentity(
              runtimeRoot: labRoot.appendingPathComponent("execution-information-loop")),
            modelSnapshotRevision: "admission-test-model",
            weightsManifestSHA256: "admission-test-weights"),
          maxTokens: 8
        ) { _, _ in
          modelValueBuilderCalls += 1
          return [:]
        }
        XCTFail("\(expectation.condition): expected a pre-generation refusal")
      } catch let error as ProductionRuntimeInformationError {
        observed = error
      } catch {
        XCTFail("\(expectation.condition): unexpected error \(error)")
      }

      if case let .informationSpaceInputAdmissionRefused(itemID, stage, _)? = observed {
        XCTAssertEqual(stage, expectation.stage, expectation.condition)
        XCTAssertEqual(itemID, expectation.itemID, expectation.condition)
      } else {
        XCTFail("\(expectation.condition): expected informationSpaceInputAdmissionRefused, got \(String(describing: observed))")
      }
      XCTAssertEqual(executor.snapshot["tokenize_text_calls"], 0, expectation.condition)
      XCTAssertEqual(executor.snapshot["tokenize_seed_calls"], 0, expectation.condition)
      XCTAssertEqual(executor.snapshot["model_continuation_calls"], 0, expectation.condition)
      XCTAssertEqual(modelValueBuilderCalls, 0, expectation.condition)
      let databaseAfter = try Data(contentsOf: database)
      let stateAfter = try directoryIdentity(stateDirectory)
      XCTAssertEqual(databaseAfter, databaseBefore, expectation.condition)
      XCTAssertEqual(stateAfter, stateBefore, expectation.condition)
    }
  }
}
