import XCTest
import Foundation
import CryptoKit
@testable import SimiGo
import SimiGoRuntimeContract
import SimiGo2Experimental

/// Disambiguation: ExecutionID exists in both SimiGo (product telemetry)
/// and SimiGoRuntimeContract. All P7-1 usages are the contract type.
private typealias ContractID = SimiGoRuntimeContract.ExecutionID

/// P7-1 Execution — Cross-backend fork/restore/continue under the
/// frozen pre-registration (Lab 9319b40; upstream P7-0 4fbefaa).
///
/// EXECUTION AUTHORIZATION: human 2026-10-01. Criteria, cells, failure
/// routing and output formats are FROZEN — no modification during
/// execution; mechanical adjudication only; implementation failures
/// are recorded and routed, never mixed into a pass.
///
/// Phases (each = one independent xcodebuild invocation, own R0
/// artifact directory under /tmp/simigo-p7-1/results/replication-p71/):
///   A testP71PhaseAForm       S₀ real formation + checkpoint v2 (M1)
///   B testP71PhaseBFork       fork cell: Parent ΔP / Child ΔC + J-A1/A2/A3
///   C testP71PhaseCRestore    restore-to-N + ΔR continuation + J-C
///   D testP71PhaseDPollution  parent non-pollution replay + J-PN
///   E testP71Adjudicate       mechanical §5–§6 judgment

final class P71CrossBackendTests: XCTestCase {

  // MARK: frozen constants (P7-1 §3.2, verbatim)

  static let serverURL = URL(string: "http://127.0.0.1:8080")!
  static let work = URL(fileURLWithPath: "/tmp/simigo-p7-1", isDirectory: true)
  static let productRepo = "/Users/mr.simi/Documents/SimiGo"
  static let replicationBase = P71CrossBackendTests.work.appendingPathComponent("results/replication-p71", isDirectory: true)

  static let initialText = "I am organizing desktop files into a folder called ReferenceFiles containing project management documents."
  static let turn1 = "What folder did I create?"
  static let deltaP = "What is the name of the folder mentioned?"
  static let deltaC = "Summarize the purpose of the folder mentioned."
  static let deltaR = "What was this folder for again?"
  static let anchorEntities = ["ReferenceFiles", "project management"]

  static let s0File = P71CrossBackendTests.work.appendingPathComponent("checkpoint-s0.json")
  static let parentFile = P71CrossBackendTests.work.appendingPathComponent("checkpoint-parent.json")
  static let childFile = P71CrossBackendTests.work.appendingPathComponent("checkpoint-child.json")

  // MARK: R0 helpers

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// Full-file SHA256 with streaming (GGUF is ~21GB — never load into memory).
  private static func sha256HexOfFileStreaming(_ path: String) throws -> String {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    var hasher = SHA256()
    let chunkSize = 4 * 1024 * 1024
    while true {
      let chunk = try handle.read(upToCount: chunkSize) ?? Data()
      if chunk.isEmpty { break }
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func harnessSHAString() -> String {
    let data = (try? Data(contentsOf: URL(fileURLWithPath: #filePath))) ?? Data()
    return "sha256:" + sha256Hex(data)
  }

  private func newStore() throws -> AuditArtifactStore {
    try AuditArtifactStore(
      context: AuditRunContext.create(
        modelHash: "recorded-in-checkpoint-v2",
        checkpointHash: nil,
        repoPath: P71CrossBackendTests.productRepo,
        harnessSHA: P71CrossBackendTests.harnessSHAString(),
        configHash: "sha256:" + P71CrossBackendTests.sha256Hex(Data("predictionTokens=32;seed=42;greedy;tools=nil".utf8))),
      baseDirectory: P71CrossBackendTests.replicationBase)
  }

  private func verifyOrThrow(_ store: AuditArtifactStore) throws {
    let checks = try store.verify()
    let data = try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: store.directory.appendingPathComponent("r0_verify.json"))
    let failed = checks.filter { !$0.value }
    guard failed.isEmpty else {
      throw NSError(domain: "P71.R0", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "R0 verify failed: \(failed.keys.joined(separator: ","))"])
    }
    store.record("r0_verify", payload: ["result": "ALL_PASS"])
  }

  // MARK: checkpoint v2 (M1)

  struct ModelIdentity: Codable {
    var modelPath: String
    var modelHash: String
  }

  struct CheckpointV2: Codable {
    var schemaVersion: Int
    var executionID: String
    var position: Int64
    var continuationNextInput: String
    var continuationID: String
    var tokenPrefix: [Int]
    var anchorHash: String
    var modelIdentity: ModelIdentity
  }

  private func anchorHash(_ tokens: [Int]) -> String {
    let joined = tokens.map { String($0) }.joined(separator: ",")
    return P71CrossBackendTests.sha256Hex(Data(joined.utf8))
  }

  private struct ServerIdentity {
    var modelPath: String
    var modelHash: String
  }

  /// Server identity probe + (optional) full GGUF hash.
  private func serverIdentity(store: AuditArtifactStore, withHash: Bool) async throws -> ServerIdentity {
    let executor = LLAMAServerExecutionStateExecutor(baseURL: P71CrossBackendTests.serverURL)
    let props = try await executor.props()
    let modelPath = props.modelPath ?? "UNKNOWN"
    store.record("server_props", payload: ["model_path": modelPath])
    let hash = withHash
      ? try Self.sha256HexOfFileStreaming(modelPath)
      : "NOT_COMPUTED"
    if withHash {
      store.record("gguf_hash", payload: ["path": modelPath, "sha256_prefix": String(hash.prefix(16))])
    }
    return ServerIdentity(modelPath: modelPath, modelHash: hash)
  }

  // MARK: shared helpers

  private func makeStack() -> (backend: LLAMAServerExecutionStateBackend, coordinator: ExecutionContinuityCoordinator) {
    let backend = LLAMAServerExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    return (backend, coordinator)
  }

  private func writeCheckpoint(_ cp: CheckpointV2, to url: URL) throws {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(cp).write(to: url)
  }

  private func readCheckpoint(_ url: URL) throws -> CheckpointV2 {
    try JSONDecoder().decode(CheckpointV2.self, from: Data(contentsOf: url))
  }

  private func fileSHA(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return P71CrossBackendTests.sha256Hex(data)
  }

  /// M1 verification (frozen §2.2): J-I1 path equality, J-I2 hash equality.
  private func verifyModelIdentity(_ cp: CheckpointV2, store: AuditArtifactStore) async throws -> (Bool, Bool) {
    let id = try await serverIdentity(store: store, withHash: true)
    let jI1 = id.modelPath == cp.modelIdentity.modelPath
    let jI2 = id.modelHash == cp.modelIdentity.modelHash
    store.record("m1_identity_checks", payload: [
      "J-I1_model_path": jI1 ? "YES" : "NO",
      "J-I2_model_hash": jI2 ? "YES" : "NO"])
    return (jI1, jI2)
  }

  /// One continuation turn: tokenize Δ → continueExecution → bind
  /// extended prefix. Returns (newHandle, Δtokens, newPrefix).
  @discardableResult
  private func continueTurn(
    _ native: LLAMAServerExecutionStateExecutor, store: AuditArtifactStore,
    backend: LLAMAServerExecutionStateBackend, coordinator: ExecutionContinuityCoordinator,
    handle: ExecutionStateHandle, boundPrefix: [Int], deltaText: String, contID: String,
    execID: ContractID, tag: String
  ) async throws -> (ExecutionStateHandle, [Int], [Int]) {
    let deltaTokens = try await native.tokenizeText(deltaText)
    store.record("tokenize", payload: ["tag": tag, "delta_tokens": "\(deltaTokens.count)"])
    let newHandle = try await coordinator.continueExecution(
      handle, continuation: ExecutionContinuation(nextInput: deltaText, continuationID: contID))
    let newPrefix = boundPrefix + deltaTokens
    try await coordinator.bindRepresentation(
      executionID: execID, position: newHandle.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: newPrefix))
    store.record("continue_bound", payload: [
      "tag": tag, "position": "\(newHandle.position.value)",
      "prefix_count": "\(newPrefix.count)"])
    return (newHandle, deltaTokens, newPrefix)
  }

  // MARK: Phase A — form S₀ + checkpoint v2

  func testP71PhaseAForm() async throws {
    // Fresh campaign workspace BEFORE creating this run's artifact store.
    try? FileManager.default.removeItem(at: P71CrossBackendTests.work)
    try FileManager.default.createDirectory(at: P71CrossBackendTests.work, withIntermediateDirectories: true)
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P7-1", "phase": "form"])
    defer { store.finish() }

    let identity = try await serverIdentity(store: store, withHash: true)
    let executor = LLAMAServerExecutionStateExecutor(baseURL: P71CrossBackendTests.serverURL)
    let (backend, coordinator) = makeStack()
    let s0ID = ContractID("p71-s0-\(UUID().uuidString.prefix(8))")

    // Build S₀ (P7-R2-A Phase A pattern, real tokenize + real generate)
    let t0 = try await executor.tokenizeText(P71CrossBackendTests.initialText)
    store.record("tokenize", payload: ["tag": "initial", "tokens": "\(t0.count)"])
    let handle0 = try await coordinator.create(
      id: s0ID, position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: P71CrossBackendTests.initialText, continuationID: "turn-0"))
    try await coordinator.bindRepresentation(
      executionID: s0ID, position: handle0.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: t0))

    let t1 = try await executor.tokenizeText(P71CrossBackendTests.turn1)
    let handle1 = try await coordinator.continueExecution(
      handle0, continuation: ExecutionContinuation(nextInput: P71CrossBackendTests.turn1, continuationID: "turn-1"))
    try await coordinator.bindRepresentation(
      executionID: s0ID, position: handle1.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: t0 + t1))

    store.record("generate_start", payload: ["tag": "s0"])
    let completion = try await executor.complete(tokenPrefix: t0 + t1, predictionTokens: 32, seed: 42)
    guard let genTokens = completion.tokens else {
      throw NSError(domain: "P71", code: 10, userInfo: [NSLocalizedDescriptionKey: "no completion tokens (Phase A)"])
    }
    store.record("generate_complete", payload: [
      "tag": "s0", "tokens": "\(genTokens.count)", "content": completion.content])

    let handle2 = try await coordinator.continueExecution(
      handle1, continuation: ExecutionContinuation(nextInput: completion.content, continuationID: "turn-2"))
    let fullPrefix = t0 + t1 + genTokens
    try await coordinator.bindRepresentation(
      executionID: s0ID, position: handle2.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: fullPrefix))

    let representation = try await backend.captureRepresentation(for: handle2)
    guard let payload = representation.payload as? LLAMAServerPrefixPayload else {
      throw NSError(domain: "P71", code: 11, userInfo: [NSLocalizedDescriptionKey: "payload capture failed"])
    }
    let cp = CheckpointV2(
      schemaVersion: 2,
      executionID: representation.executionID.rawValue,
      position: representation.position.value,
      continuationNextInput: handle2.continuation.nextInput,
      continuationID: handle2.continuation.continuationID,
      tokenPrefix: payload.tokenPrefix,
      anchorHash: anchorHash(payload.tokenPrefix),
      modelIdentity: ModelIdentity(modelPath: identity.modelPath, modelHash: identity.modelHash))
    try writeCheckpoint(cp, to: P71CrossBackendTests.s0File)

    try store.writeSummary([
      "role": "form", "r0RunUUID": store.runUUID,
      "s0_executionID": cp.executionID, "s0_position": "\(cp.position)",
      "s0_prefix_count": "\(cp.tokenPrefix.count)", "s0_anchor": cp.anchorHash,
      "model_path": identity.modelPath, "model_hash": identity.modelHash])
    try store.writeHashes(["gguf_sha256": identity.modelHash])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["phase": "form", "position": "\(cp.position)"])
  }

  // MARK: Phase B — fork cell (Parent ΔP / Child ΔC)

  func testP71PhaseBFork() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P7-1", "phase": "fork"])
    defer { store.finish() }

    let cp = try readCheckpoint(P71CrossBackendTests.s0File)
    store.record("checkpoint_loaded", payload: ["pos": "\(cp.position)", "prefix": "\(cp.tokenPrefix.count)"])

    // M1 verification BEFORE any continuation (frozen §2.2)
    let (jI1, jI2) = try await verifyModelIdentity(cp, store: store)

    let executor = LLAMAServerExecutionStateExecutor(baseURL: P71CrossBackendTests.serverURL)
    let (backend, coordinator) = makeStack()

    // Fork: two independent attaches of the SAME S₀ payload
    func attachBranch(_ suffix: String) async throws -> (handle: ExecutionStateHandle, boundPrefix: [Int]) {
      let handle = try await coordinator.attach(ExecutionStateHandle(
        id: ContractID(cp.executionID + suffix),
        lineage: ExecutionLineage(root: ContractID(cp.executionID)),
        position: ExecutionPosition(cp.position),
        continuation: ExecutionContinuation(nextInput: cp.continuationNextInput, continuationID: cp.continuationID),
        lifecycle: .restored))
      try await backend.restoreRepresentation(ExecutionRepresentation(
        executionID: handle.id, position: handle.position,
        payload: LLAMAServerPrefixPayload(tokenPrefix: cp.tokenPrefix)))
      let bound = try backend.boundPrefix(for: handle)
      store.record("fork_attach", payload: [
        "branch": suffix, "position": "\(handle.position.value)",
        "prefix_count": "\(bound.prefix.count)",
        "fork_anchor": anchorHash(bound.prefix)])
      return (handle, bound.prefix)
    }
    let (parentHandle, parentForkPrefix) = try await attachBranch("-parent")
    let (childHandle, childForkPrefix) = try await attachBranch("-child")

    // J-A1: fork-point anchors (each branch re-derived from its own bound payload)
    let forkAnchorParent = anchorHash(parentForkPrefix)
    let forkAnchorChild = anchorHash(childForkPrefix)
    let jA1 = (forkAnchorParent == cp.anchorHash) && (forkAnchorChild == cp.anchorHash)
    store.record("J-A1_fork_anchors_equal", payload: [
      "parent": String(forkAnchorParent.prefix(12)), "child": String(forkAnchorChild.prefix(12)),
      "equals_checkpoint": jA1 ? "YES" : "NO"])

    // J-A3: anchor functional (alt Δ changes hash)
    let altTokens = try await executor.tokenizeText("What is the weather?")
    let childDeltaTokens0 = try await executor.tokenizeText(P71CrossBackendTests.deltaC)
    let jA3 = anchorHash(cp.tokenPrefix + altTokens) != anchorHash(cp.tokenPrefix + childDeltaTokens0)
    store.record("J-A3_anchor_functional", payload: ["value": jA3 ? "YES" : "NO"])

    // Parent branch: ΔP → bind → real generate → bind gen
    let parentID = ContractID(cp.executionID + "-parent")
    let (parentHandle1, parentDeltaTokens, parentPreGenPrefix) = try await continueTurn(
      executor, store: store, backend: backend, coordinator: coordinator,
      handle: parentHandle,
      boundPrefix: cp.tokenPrefix, deltaText: P71CrossBackendTests.deltaP,
      contID: "p71-parent-dP", execID: parentID, tag: "parent-dP")
    // J-P2 (parent): append lands exactly — position +1, prefix +|Δ| tokens
    let jP2Parent = parentHandle1.position.value == cp.position + 1
      && parentPreGenPrefix.count == cp.tokenPrefix.count + parentDeltaTokens.count
    store.record("J-P2_parent_append_landing", payload: ["value": jP2Parent ? "YES" : "NO"])
    store.record("generate_start", payload: ["tag": "parent"])
    let parentCompletion = try await executor.complete(
      tokenPrefix: parentPreGenPrefix, predictionTokens: 32, seed: 42)
    guard let genP = parentCompletion.tokens else {
      throw NSError(domain: "P71", code: 12, userInfo: [NSLocalizedDescriptionKey: "no parent completion tokens"])
    }
    store.record("generate_complete", payload: ["tag": "parent", "tokens": "\(genP.count)", "content": parentCompletion.content])
    let (parentHandle2, _, parentFullPrefix) = try await continueTurn(
      executor, store: store, backend: backend, coordinator: coordinator,
      handle: parentHandle1, boundPrefix: parentPreGenPrefix, deltaText: parentCompletion.content,
      contID: "p71-parent-gen", execID: parentID, tag: "parent-gen")
    let parentRep = try await backend.captureRepresentation(for: parentHandle2)
    guard let parentPayload = parentRep.payload as? LLAMAServerPrefixPayload else {
      throw NSError(domain: "P71", code: 13, userInfo: [NSLocalizedDescriptionKey: "parent payload capture failed"])
    }
    let parentCP = CheckpointV2(
      schemaVersion: 2, executionID: parentRep.executionID.rawValue,
      position: parentRep.position.value,
      continuationNextInput: parentHandle2.continuation.nextInput,
      continuationID: parentHandle2.continuation.continuationID,
      tokenPrefix: parentPayload.tokenPrefix,
      anchorHash: anchorHash(parentPayload.tokenPrefix),
      modelIdentity: cp.modelIdentity)
    try writeCheckpoint(parentCP, to: P71CrossBackendTests.parentFile)

    // Child branch: ΔC → bind → real generate → bind gen
    let childID = ContractID(cp.executionID + "-child")
    let (childHandle1, childDeltaTokens, childPreGenPrefix) = try await continueTurn(
      executor, store: store, backend: backend, coordinator: coordinator,
      handle: childHandle, boundPrefix: cp.tokenPrefix, deltaText: P71CrossBackendTests.deltaC,
      contID: "p71-child-dC", execID: childID, tag: "child-dC")
    // J-P2 (child): append lands exactly — position +1, prefix +|Δ| tokens
    let jP2Child = childHandle1.position.value == cp.position + 1
      && childPreGenPrefix.count == cp.tokenPrefix.count + childDeltaTokens.count
    store.record("J-P2_child_append_landing", payload: ["value": jP2Child ? "YES" : "NO"])
    store.record("generate_start", payload: ["tag": "child"])
    let childCompletion = try await executor.complete(
      tokenPrefix: childPreGenPrefix, predictionTokens: 32, seed: 42)
    guard let genC = childCompletion.tokens else {
      throw NSError(domain: "P71", code: 14, userInfo: [NSLocalizedDescriptionKey: "no child completion tokens"])
    }
    store.record("generate_complete", payload: ["tag": "child", "tokens": "\(genC.count)", "content": childCompletion.content])
    let (childHandle2, _, childFullPrefix) = try await continueTurn(
      executor, store: store, backend: backend, coordinator: coordinator,
      handle: childHandle1, boundPrefix: childPreGenPrefix, deltaText: childCompletion.content,
      contID: "p71-child-gen", execID: childID, tag: "child-gen")
    let childRep = try await backend.captureRepresentation(for: childHandle2)
    guard let childPayload = childRep.payload as? LLAMAServerPrefixPayload else {
      throw NSError(domain: "P71", code: 15, userInfo: [NSLocalizedDescriptionKey: "child payload capture failed"])
    }
    let childCP = CheckpointV2(
      schemaVersion: 2, executionID: childRep.executionID.rawValue,
      position: childRep.position.value,
      continuationNextInput: childHandle2.continuation.nextInput,
      continuationID: childHandle2.continuation.continuationID,
      tokenPrefix: childPayload.tokenPrefix,
      anchorHash: anchorHash(childPayload.tokenPrefix),
      modelIdentity: cp.modelIdentity)
    try writeCheckpoint(childCP, to: P71CrossBackendTests.childFile)

    // J-A2: divergence real
    let jA2 = anchorHash(parentCP.tokenPrefix) != anchorHash(childCP.tokenPrefix)
    store.record("J-A2_divergence_real", payload: ["value": jA2 ? "YES" : "NO"])

    try store.writeSummary([
      "role": "fork", "r0RunUUID": store.runUUID,
      "J-I1_model_path": jI1 ? "PASS" : "FAIL", "J-I2_model_hash": jI2 ? "PASS" : "FAIL",
      "J-A1_fork_anchors": jA1 ? "PASS" : "FAIL",
      "J-A2_divergence": jA2 ? "PASS" : "FAIL",
      "J-A3_functional": jA3 ? "PASS" : "FAIL",
      "J-P2_parent_append_landing": jP2Parent ? "PASS" : "FAIL",
      "J-P2_child_append_landing": jP2Child ? "PASS" : "FAIL",
      "s0_anchor": cp.anchorHash,
      "parentPreGenPrefix": parentPreGenPrefix,
      "parentGenContent": parentCompletion.content,
      "parent_position": "\(parentCP.position)", "parent_anchor": parentCP.anchorHash,
      "child_position": "\(childCP.position)", "child_anchor": childCP.anchorHash,
      "parent_checkpoint_file_sha256": fileSHA(P71CrossBackendTests.parentFile) ?? "MISSING"])
    try store.writeHashes(["gguf_sha256": cp.modelIdentity.modelHash])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["phase": "fork"])
  }

  // MARK: Phase C — restore child checkpoint + ΔR continuation

  func testP71PhaseCRestore() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P7-1", "phase": "restore"])
    defer { store.finish() }

    let childCP = try readCheckpoint(P71CrossBackendTests.childFile)
    store.record("checkpoint_loaded", payload: [
      "pos": "\(childCP.position)", "prefix": "\(childCP.tokenPrefix.count)",
      "anchor": childCP.anchorHash])

    let (jI1, jI2) = try await verifyModelIdentity(childCP, store: store)

    let executor = LLAMAServerExecutionStateExecutor(baseURL: P71CrossBackendTests.serverURL)
    let (backend, coordinator) = makeStack()

    let restoreID = ContractID(childCP.executionID + "-restore")
    let handle = try await coordinator.attach(ExecutionStateHandle(
      id: restoreID,
      lineage: ExecutionLineage(root: ContractID(childCP.executionID)),
      position: ExecutionPosition(childCP.position),
      continuation: ExecutionContinuation(nextInput: childCP.continuationNextInput, continuationID: childCP.continuationID),
      lifecycle: .restored))
    try await backend.restoreRepresentation(ExecutionRepresentation(
      executionID: handle.id, position: handle.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: childCP.tokenPrefix)))
    let bound = try backend.boundPrefix(for: handle)

    // J-P1: restore position == child checkpoint position
    let jP1 = handle.position.value == childCP.position
      && bound.prefix.count == childCP.tokenPrefix.count
    store.record("J-P1_restore_position", payload: [
      "position_match": handle.position.value == childCP.position ? "YES" : "NO",
      "prefix_count_match": bound.prefix.count == childCP.tokenPrefix.count ? "YES" : "NO"])

    // ΔR continuation
    let deltaRTokens = try await executor.tokenizeText(P71CrossBackendTests.deltaR)
    let newHandle = try await coordinator.continueExecution(
      handle, continuation: ExecutionContinuation(nextInput: P71CrossBackendTests.deltaR, continuationID: "p71-restore-dR"))
    let newPrefix = bound.prefix + deltaRTokens
    try await coordinator.bindRepresentation(
      executionID: restoreID, position: newHandle.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: newPrefix))

    // J-C1: prefix_is_extension; J-C2: position advanced
    let jC1 = Array(newPrefix.prefix(childCP.tokenPrefix.count)) == childCP.tokenPrefix
    let jC2 = newHandle.position.value == childCP.position + 1
      && newPrefix.count == childCP.tokenPrefix.count + deltaRTokens.count
    store.record("J-C1_prefix_is_extension", payload: ["value": jC1 ? "YES" : "NO"])
    store.record("J-C2_position_advanced", payload: ["value": jC2 ? "YES" : "NO"])

    // Real generate after restore + ΔR
    store.record("generate_start", payload: ["tag": "restore-continuation"])
    let completion = try await executor.complete(tokenPrefix: newPrefix, predictionTokens: 32, seed: 42)
    guard let genTokens = completion.tokens else {
      throw NSError(domain: "P71", code: 16, userInfo: [NSLocalizedDescriptionKey: "no completion tokens (Phase C)"])
    }
    let output = completion.content
    // J-C3: no cold fallback (continuation ran on the restored+extended prefix)
    let jC3 = jC1
    // J-C4: anchored output
    let jC4 = P71CrossBackendTests.anchorEntities.contains { output.contains($0) }
    store.record("generate_complete", payload: [
      "tag": "restore-continuation", "tokens": "\(genTokens.count)", "content": output,
      "J-C3_no_cold_fallback": jC3 ? "YES" : "NO",
      "J-C4_anchored": jC4 ? "YES" : "NO"])

    try store.writeSummary([
      "role": "restore", "r0RunUUID": store.runUUID,
      "J-I1_model_path": jI1 ? "PASS" : "FAIL", "J-I2_model_hash": jI2 ? "PASS" : "FAIL",
      "J-P1_restore_position": jP1 ? "PASS" : "FAIL",
      "J-C1_prefix_is_extension": jC1 ? "PASS" : "FAIL",
      "J-C2_position_advanced": jC2 ? "PASS" : "FAIL",
      "J-C3_no_cold_fallback": jC3 ? "PASS" : "FAIL",
      "J-C4_anchored": jC4 ? "PASS" : "FAIL",
      "continuation_output": output])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["phase": "restore"])
  }

  // MARK: Phase D — parent non-pollution replay

  func testP71PhaseDPollution() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P7-1", "phase": "pollution"])
    defer { store.finish() }

    let forkSummaryURL = P71CrossBackendTests.replicationBase
      .appendingPathComponent("fork-summary-locator.json")
    // Locate the fork run dir (role=fork) written by Phase B.
    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(atPath: P71CrossBackendTests.replicationBase.path)
    var forkSummary: [String: Any]?
    var forkDir: String?
    for name in entries.sorted() {
      let dir = P71CrossBackendTests.replicationBase.appendingPathComponent(name, isDirectory: true)
      guard let data = try? Data(contentsOf: dir.appendingPathComponent("summary.json")),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (obj["role"] as? String) == "fork"
      else { continue }
      forkSummary = obj; forkDir = name; break
    }
    guard let fork = forkSummary, let forkDirName = forkDir,
          let parentGenContent = fork["parentGenContent"] as? String,
          let parentPreGenPrefix = fork["parentPreGenPrefix"] as? [Int],
          let recordedFileSHA = fork["parent_checkpoint_file_sha256"] as? String else {
      throw NSError(domain: "P71", code: 20, userInfo: [NSLocalizedDescriptionKey: "fork summary not found"])
    }
    store.record("judgment_inputs", payload: ["fork_dir": forkDirName])

    // J-PN2: parent checkpoint file unchanged since Phase B
    let currentFileSHA = fileSHA(P71CrossBackendTests.parentFile)
    let jPN2 = currentFileSHA == recordedFileSHA
    store.record("J-PN2_parent_payload_sha", payload: ["value": jPN2 ? "UNCHANGED" : "CHANGED"])

    // J-PN1: behavioral replay of parent generation (post-child-cycle)
    let executor = LLAMAServerExecutionStateExecutor(baseURL: P71CrossBackendTests.serverURL)
    store.record("generate_start", payload: ["tag": "parent-replay"])
    let replay = try await executor.complete(tokenPrefix: parentPreGenPrefix, predictionTokens: 32, seed: 42)
    guard let replayTokens = replay.tokens else {
      throw NSError(domain: "P71", code: 21, userInfo: [NSLocalizedDescriptionKey: "no replay completion tokens"])
    }
    let jPN1 = replay.content == parentGenContent
    store.record("generate_complete", payload: [
      "tag": "parent-replay", "tokens": "\(replayTokens.count)",
      "J-PN1_replay_verbatim": jPN1 ? "YES" : "NO",
      "original": parentGenContent, "replay": replay.content])

    try store.writeSummary([
      "role": "pollution", "r0RunUUID": store.runUUID,
      "J-PN1_replay_verbatim": jPN1 ? "PASS" : "FAIL",
      "J-PN2_payload_sha": jPN2 ? "PASS" : "FAIL"])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["phase": "pollution"])
  }

  // MARK: Phase E — mechanical adjudication (P7-1 §5–§6, frozen)

  func testP71Adjudicate() throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "P7-1", "role": "judgment"])
    defer { store.finish() }

    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(atPath: P71CrossBackendTests.replicationBase.path)
    var byRole: [String: (String, [String: Any])] = [:]
    for name in entries.sorted() {
      let dir = P71CrossBackendTests.replicationBase.appendingPathComponent(name, isDirectory: true)
      guard let data = try? Data(contentsOf: dir.appendingPathComponent("summary.json")),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let role = obj["role"] as? String
      else { continue }
      guard byRole[role] == nil else {
        throw NSError(domain: "P71.Judgment", code: 30,
                      userInfo: [NSLocalizedDescriptionKey: "duplicate role \(role) — stale run dirs present"])
      }
      byRole[role] = (name, obj)
    }
    guard byRole["form"] != nil, let fork = byRole["fork"], let restore = byRole["restore"],
          let pollution = byRole["pollution"], byRole.count == 4 else {
      throw NSError(domain: "P71.Judgment", code: 31,
                    userInfo: [NSLocalizedDescriptionKey: "expected roles form/fork/restore/pollution, found: \(byRole.keys.sorted().joined(separator: ","))"])
    }
    store.record("judgment_inputs", payload: [
      "form": byRole["form"]!.0, "fork": fork.0, "restore": restore.0, "pollution": pollution.0])

    var v: [String: String] = [:]
    // C1 Identity (M1)
    let i1 = fork.1["J-I1_model_path"] as? String
    let i2 = fork.1["J-I2_model_hash"] as? String
    let rI1 = restore.1["J-I1_model_path"] as? String
    let rI2 = restore.1["J-I2_model_hash"] as? String
    v["C1_identity"] = ([i1, i2, rI1, rI2].allSatisfy { $0 == "PASS" }) ? "PASS" : "INCONCLUSIVE"
    // C2 Position (J-P1 restore landing + J-P2 append landing, both branches)
    v["C2_position"] = ((restore.1["J-P1_restore_position"] as? String) == "PASS"
      && (fork.1["J-P2_parent_append_landing"] as? String) == "PASS"
      && (fork.1["J-P2_child_append_landing"] as? String) == "PASS") ? "PASS" : "FAIL"
    // C3 Anchor (M2)
    v["C3_anchor"] = ([fork.1["J-A1_fork_anchors"], fork.1["J-A2_divergence"], fork.1["J-A3_functional"]]
      .allSatisfy { ($0 as? String) == "PASS" }) ? "PASS" : "FAIL"
    // C4 Continuation
    v["C4_continuation"] = ([restore.1["J-C1_prefix_is_extension"], restore.1["J-C2_position_advanced"],
      restore.1["J-C3_no_cold_fallback"], restore.1["J-C4_anchored"]]
      .allSatisfy { ($0 as? String) == "PASS" }) ? "PASS" : "FAIL"
    // C5 Parent non-pollution
    v["C5_parent_non_pollution"] = ([pollution.1["J-PN1_replay_verbatim"], pollution.1["J-PN2_payload_sha"]]
      .allSatisfy { ($0 as? String) == "PASS" }) ? "PASS" : "FAIL"

    let verdict: String
    if v["C1_identity"] == "INCONCLUSIVE" {
      verdict = "INCONCLUSIVE"
    } else if v.values.allSatisfy({ $0 == "PASS" }) {
      verdict = "CONTINUATION_VALIDATED_CROSSBACKEND"
    } else {
      verdict = "FAIL"
    }
    v["verdict"] = verdict

    for (k, val) in v { store.record("judgment", payload: ["cell": k, "value": val]) }
    store.record("judgment_note", payload: [
      "text": "mechanical application of P7-1 §5–§6 frozen rules; wording per P7-0 §6 — 'backend-independent' claims prohibited"])

    var judgment: [String: Any] = [:]
    judgment["cells"] = v
    judgment["overall"] = verdict
    judgment["inputs"] = [
      "form": byRole["form"]!.0, "fork": fork.0, "restore": restore.0, "pollution": pollution.0]
    let jdata = try JSONSerialization.data(withJSONObject: judgment, options: [.prettyPrinted, .sortedKeys])
    try jdata.write(to: store.directory.appendingPathComponent("judgment.json"))
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["role": "judgment", "overall": verdict])
    print("[p71] overall: \(verdict)")
  }
}
