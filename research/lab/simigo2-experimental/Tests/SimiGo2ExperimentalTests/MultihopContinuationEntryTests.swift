import Foundation
import os
import XCTest
import SimiGo2Experimental
import SimiGoRuntimeContract

/// Model-free tests for the MULTI-HOP continuation the G round depends on.
///
/// A U3 task declares ONLY its direct dependency U2. Admitting U2 through the
/// ordinary production `resolveTaskInput` / `continueTask` must recursively
/// resolve U2's own signed closure (SOURCE + U1) and verify every settlement in
/// that transitive closure — so U3 is admitted only against a fully verified
/// U2→U1 chain. If the transitively required U1 settlement is missing, the same
/// production entry must refuse BEFORE any tokenization or model generation,
/// leave the Information Space untouched, and create no execution state.
///
/// These fixtures come from the SAME generator the Python admission selftest
/// verifies (`admission_selftest.py --emit-fixture multihop-*`), so the Swift
/// path and the Python path are checked against one authoritative world.
final class MultihopContinuationEntryTests: XCTestCase {
  private let labRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private struct StubStop: Error {}
  private struct FixtureFailure: Error, CustomStringConvertible {
    let description: String
  }

  private final class RecordingExecutor:
    ProductionRuntimeModelContinuationExecutor, @unchecked Sendable
  {
    private struct Counters {
      var tokenizedInputs: [String] = []
      var seedTokenizations = 0
      var continuedStates: [(identity: String, position: Int64)] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: Counters())
    var tokenizedInputs: [String] { state.withLock { $0.tokenizedInputs } }
    var seedTokenizations: Int { state.withLock { $0.seedTokenizations } }
    var continuedStates: [(identity: String, position: Int64)] {
      state.withLock { $0.continuedStates }
    }
    func tokenizeText(_ text: String) async throws -> [Int] {
      state.withLock { $0.tokenizedInputs.append(text) }
      return [1, 2, 3]
    }
    func tokenizeSeedText(_ text: String) async throws -> [Int] {
      state.withLock { $0.seedTokenizations += 1 }
      return [4, 5, 6]
    }
    func continueExecution(
      _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int
    ) async throws -> ExecutionContinuationResult {
      self.state.withLock {
        $0.continuedStates.append((state.id.rawValue, state.position.value))
      }
      throw StubStop()
    }
  }

  // MARK: - fixtures

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

  private func makeIntegration(
    executor: RecordingExecutor, stateDirectory: URL, executionID: ExecutionID
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
      resetToFreshBaseline: false,
      executionID: executionID
    )
  }

  private func fileManifest(_ directory: URL) throws -> [String: String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
      at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []
    ) else { return [:] }
    var manifest: [String: String] = [:]
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else { continue }
      manifest[url.lastPathComponent] =
        String(data: try Data(contentsOf: url), encoding: .utf8) ?? "<binary>"
    }
    return manifest
  }

  private func signatureItemIDs(_ admission: ProductionTaskInputAdmission) -> Set<String> {
    Set(admission.settlementSignatures.map { $0.itemID })
  }

  // MARK: - happy: full transitive closure admitted

  /// U3 declares only U2, yet the ordinary production admission must resolve and
  /// verify the FULL transitive closure (SOURCE + U1 + U2) before handing U3's
  /// input to the model, and must reach the model with U2's settled answer bound.
  func testMultihopU3AdmitsFullTransitiveClosureAndReachesModel() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("simigo-multihop-happy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      unsetenv(SettlementTrustFixture.anchorEnvironment)
      try? FileManager.default.removeItem(at: root)
    }
    let fixture = try emitFixture("multihop-happy", to: root)
    setenv(SettlementTrustFixture.anchorEnvironment, fixture.trustAnchorPath, 1)

    let observer = try makeIntegration(
      executor: RecordingExecutor(),
      stateDirectory: root.appendingPathComponent("observer", isDirectory: true),
      executionID: ExecutionID("MULTIHOP-OBSERVER"))
    let admission = try observer.resolveTaskInput(
      database: fixture.database,
      taskItemID: "TASK-U3",
      evaluatedAtUTC: "2026-10-23T00:00:00Z")

    // Declared edge is U2 alone; the verified closure must reach transitively
    // through U2 to U1 and the source.
    XCTAssertEqual(admission.declaredDependencies, ["TASK-U2"],
                   "U3 must declare only its direct dependency U2")
    let closure = signatureItemIDs(admission)
    XCTAssertTrue(closure.contains("TASK-U2"),
                  "closure must include the direct dependency U2, got \(closure)")
    XCTAssertTrue(closure.contains("TASK-U1"),
                  "closure must include the transitive dependency U1, got \(closure)")
    // The binding the model input materializes must come from U2's settled value.
    let answerBinding = admission.bindings.first { $0.itemID == "TASK-U2" }
    XCTAssertNotNil(answerBinding, "U3 input must bind U2's settled answer")
    XCTAssertFalse(answerBinding?.value.isEmpty ?? true)
    XCTAssertFalse(answerBinding?.settlementObjectID.isEmpty ?? true)

    // Then the ordinary continueTask path reaches the model with the admitted
    // input, entering at position 0 under a fresh, per-instance identity.
    let stateDirectory = root.appendingPathComponent("state", isDirectory: true)
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    XCTAssertTrue(try fileManifest(stateDirectory).isEmpty)
    let executor = RecordingExecutor()
    let integration = try makeIntegration(
      executor: executor, stateDirectory: stateDirectory,
      executionID: ExecutionID("MULTIHOP-U3-PRODUCER"))
    do {
      _ = try await integration.continueTask(
        database: fixture.database,
        handle: nil,
        advancementID: "multihop-u3",
        evaluatedAtUTC: "2026-10-23T00:00:00Z",
        demandID: "handoff-u3",
        taskItemID: "TASK-U3",
        seedText: "multihop cold seed",
        provenance: ProductionTaskProvenance(
          runID: "multihop-u3",
          buildSHA256: ProductionTaskProvenance.buildIdentity(
            runtimeRoot: labRoot.appendingPathComponent("execution-information-loop")),
          modelSnapshotRevision: "multihop-test-model",
          weightsManifestSHA256: "multihop-test-weights"),
        maxTokens: 4
      ) { _, _ in [:] }
      XCTFail("the stub model was supposed to stop the run")
    } catch let error as ProductionRuntimeInformationError {
      guard case .modelExecutionFailed(let reason) = error,
            reason.contains("model_execution") else { throw error }
    }
    XCTAssertEqual(executor.continuedStates.count, 1)
    XCTAssertEqual(executor.continuedStates.first?.position, 0,
                   "a multi-hop continuation must enter at position 0")
    XCTAssertEqual(executor.continuedStates.first?.identity, "MULTIHOP-U3-PRODUCER")
    let modelInput = executor.tokenizedInputs.first ?? ""
    XCTAssertTrue(modelInput.contains(admission.inputText),
                  "the admitted Information Space input must reach the tokenizer")
    XCTAssertTrue(modelInput.contains(answerBinding?.value ?? "#never#"),
                  "the settled U2 answer must be inside the model input")
  }

  // MARK: - negative: missing transitive dependency refuses before the model

  /// Removing U1 from the closure U2 depends on must make the ordinary U3
  /// admission refuse before tokenizing or generating, with no IS write and no
  /// execution state created.
  func testMultihopU3RefusesBeforeModelWhenTransitiveU1Missing() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("simigo-multihop-refuse-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      unsetenv(SettlementTrustFixture.anchorEnvironment)
      try? FileManager.default.removeItem(at: root)
    }
    let fixture = try emitFixture("multihop-missing-u1", to: root)
    setenv(SettlementTrustFixture.anchorEnvironment, fixture.trustAnchorPath, 1)

    let stateDirectory = root.appendingPathComponent("state", isDirectory: true)
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    let executor = RecordingExecutor()
    let integration = try makeIntegration(
      executor: executor, stateDirectory: stateDirectory,
      executionID: ExecutionID("MULTIHOP-REFUSED"))
    let databaseBefore = try Data(contentsOf: fixture.database)

    do {
      _ = try await integration.continueTask(
        database: fixture.database,
        handle: nil,
        advancementID: "multihop-refused-u3",
        evaluatedAtUTC: "2026-10-23T00:00:00Z",
        demandID: "handoff-u3",
        taskItemID: "TASK-U3",
        seedText: "multihop cold seed",
        provenance: ProductionTaskProvenance(
          runID: "multihop-refused-u3",
          buildSHA256: ProductionTaskProvenance.buildIdentity(
            runtimeRoot: labRoot.appendingPathComponent("execution-information-loop")),
          modelSnapshotRevision: "multihop-test-model",
          weightsManifestSHA256: "multihop-test-weights"),
        maxTokens: 4
      ) { _, _ in [:] }
      XCTFail("expected a pre-model refusal for an incomplete transitive closure")
    } catch let error as ProductionRuntimeInformationError {
      switch error {
      case .informationSpaceInputAdmissionRefused(let itemID, let stage, _):
        XCTAssertEqual(itemID, "TASK-U1",
                       "the refusal must name the missing transitive dependency")
        XCTAssertFalse(stage.isEmpty)
      case .informationSpaceInputBindingMismatch(let field):
        // A dependency-closure refusal may also surface as a binding mismatch;
        // either way it happens before the model, asserted below.
        XCTAssertFalse(field.isEmpty)
      default:
        throw error
      }
    }
    XCTAssertEqual(executor.tokenizedInputs.count, 0,
                   "an incomplete closure must refuse before tokenizing text")
    XCTAssertEqual(executor.seedTokenizations, 0,
                   "an incomplete closure must refuse before tokenizing the seed")
    XCTAssertEqual(executor.continuedStates.count, 0,
                   "an incomplete closure must refuse before generating")
    XCTAssertEqual(try Data(contentsOf: fixture.database), databaseBefore,
                   "a pre-admission refusal must not write to the Information Space")
    XCTAssertEqual(try fileManifest(stateDirectory), [:],
                   "a pre-admission refusal must not create execution state")
  }

  // MARK: - executable level (the model-free entry the experiment uses)

  /// `SimiGoTaskRun --admission-probe` on U3 admits on the happy world (with the
  /// full transitive closure) and refuses on the missing-U1 world, in both cases
  /// with zero model work by construction.
  func testOrdinaryExecutableProbeOnU3AdmitsAndRefusesWithoutModelWork() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("simigo-multihop-probe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      unsetenv(SettlementTrustFixture.anchorEnvironment)
      try? FileManager.default.removeItem(at: root)
    }

    for (condition, expectedStatus, expectedExit) in [
      ("multihop-happy", "ADMITTED", Int32(0)),
      ("multihop-missing-u1", "ADMISSION_REFUSED", Int32(1)),
    ] {
      let fixture = try emitFixture(condition, to: root)
      setenv(SettlementTrustFixture.anchorEnvironment, fixture.trustAnchorPath, 1)
      let stateDirectory = root.appendingPathComponent(
        "probe-state-\(condition)", isDirectory: true)
      let output = root.appendingPathComponent("probe-\(condition).json")
      let result = try runExecutable(
        "SimiGoTaskRun",
        arguments: [
          "--database", fixture.database.path,
          "--model-dir", root.path,
          "--lab-root", labRoot.path,
          "--state-dir", stateDirectory.path,
          "--out", output.path,
          "--item", "TASK-U3",
          "--demand", "handoff-u3",
          "--advancement", "probe-\(condition)",
          "--evaluated-at", "2026-10-23T00:00:00Z",
          "--execution-id", "PROBE-\(condition.uppercased())",
          "--admission-probe",
        ])
      XCTAssertEqual(result.exitCode, expectedExit, "\(condition): \(result.stderr)")
      let record = try JSONSerialization.jsonObject(
        with: try Data(contentsOf: output)) as? [String: Any] ?? [:]
      XCTAssertEqual(record["input_admission_status"] as? String, expectedStatus, condition)
      XCTAssertEqual(record["model_loaded"] as? Bool, false, condition)
      XCTAssertEqual(record["generation_entered"] as? Bool, false, condition)
      let counters = record["counters"] as? [String: Int] ?? [:]
      XCTAssertEqual(counters["tokenize_text_calls"], 0, condition)
      XCTAssertEqual(counters["tokenize_seed_calls"], 0, condition)
      XCTAssertEqual(counters["model_continuation_calls"], 0, condition)
      XCTAssertEqual(record["database_unchanged"] as? Bool, true, condition)
      if condition == "multihop-happy" {
        let signatures = record["settlement_signatures"] as? [[String: Any]] ?? []
        let items = Set(signatures.compactMap { $0["item_id"] as? String })
        XCTAssertTrue(items.contains("TASK-U1"),
                      "happy probe must verify the transitive U1, got \(items)")
        XCTAssertTrue(items.contains("TASK-U2"),
                      "happy probe must verify the direct U2, got \(items)")
      }
    }
  }

  // MARK: - driver refuses a non-empty THIRD (P3) state directory

  /// The experiment driver must refuse to run when the U3 state directory is not
  /// empty, before it spawns anything, so P3 can never reuse stale state.
  func testDetachedDriverRefusesNonEmptyThirdStateDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("simigo-multihop-driver-\(UUID().uuidString)", isDirectory: true)
    let world = root.appendingPathComponent("world", isDirectory: true)
    let u3State = world.appendingPathComponent("u3-state", isDirectory: true)
    try FileManager.default.createDirectory(at: u3State, withIntermediateDirectories: true)
    try Data("leftover prefix".utf8).write(
      to: u3State.appendingPathComponent("execution-state.json"))
    defer { try? FileManager.default.removeItem(at: root) }

    let arguments = [
      "--binary", root.appendingPathComponent("unused-task-run").path,
      "--lab-root", labRoot.path,
      "--model-dir", root.path,
      "--database", root.appendingPathComponent("unused.sqlite").path,
      "--world-dir", world.path,
      "--run-id", "multihop-driver-refusal",
      "--evaluated-at-u1", "2026-10-23T00:00:00Z",
      "--evaluated-at-u2", "2026-10-23T00:00:00Z",
      "--evaluated-at-u3", "2026-10-23T00:00:00Z",
      "--u1-item", "TASK-U1", "--u1-demand", "handoff-u1",
      "--u1-advancement", "multihop-driver-refusal-u1",
      "--u2-item", "TASK-U2", "--u2-demand", "handoff-u2",
      "--u2-advancement", "multihop-driver-refusal-u2",
      "--u3-item", "TASK-U3", "--u3-demand", "handoff-u3",
      "--u3-advancement", "multihop-driver-refusal-u3",
      "--u1-execution-id", "MDR-U1", "--u2-execution-id", "MDR-U2",
      "--u3-execution-id", "MDR-U3",
      "--u1-out", root.appendingPathComponent("u1.json").path,
      "--u2-out", root.appendingPathComponent("u2.json").path,
      "--u3-out", root.appendingPathComponent("u3.json").path,
      "--out", root.appendingPathComponent("lifecycle.json").path,
      "--max-tokens", "4",
    ]
    let result = try runExecutable("SimiGoDetachedDriver", arguments: arguments)
    XCTAssertEqual(result.exitCode, 1, result.stderr)
    XCTAssertTrue(result.stderr.contains("is not empty; refusing to reuse state"),
                  result.stderr)
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: root.appendingPathComponent("lifecycle.json").path),
      "the driver must refuse before writing any run evidence")
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: world.appendingPathComponent("process-logs").path),
      "the driver must refuse before spawning processes")
  }

  // MARK: - helper

  private struct ChildResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
  }

  private func runExecutable(
    _ name: String, arguments: [String], environment: [String: String]? = nil
  ) throws -> ChildResult {
    let executable = labRoot.appendingPathComponent(
      "simigo2-experimental/.build/debug/\(name)")
    try XCTSkipIf(!FileManager.default.fileExists(atPath: executable.path),
                  "\(name) is not built; run `swift build` first")
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    if let environment { process.environment = environment }
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ChildResult(
      exitCode: process.terminationStatus,
      stdout: String(decoding: outData, as: UTF8.self),
      stderr: String(decoding: errData, as: UTF8.self))
  }
}
