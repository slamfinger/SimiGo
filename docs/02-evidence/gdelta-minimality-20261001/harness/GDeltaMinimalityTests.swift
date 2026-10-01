import XCTest
import Foundation
import CryptoKit
@testable import SimiGo
import SimiGoRuntimeContract
import SimiGo2Experimental

/// Disambiguation: ExecutionID exists in both SimiGo (product telemetry)
/// and SimiGoRuntimeContract. All G-δ usages are the contract type.
private typealias ContractID = SimiGoRuntimeContract.ExecutionID

/// G-δ Minimality Validation — Execution per the frozen pre-registration
/// (Lab 8151458; criteria upstream 056e283).
///
/// EXECUTION AUTHORIZATION: human 2026-10-01. Relation-removal
/// definition, derivability space, cells, battery, necessity signatures
/// and wording caps are FROZEN — zero modification during execution.
///
/// Core discipline (frozen): relation removal ≠ field removal. Removal
/// = drop the relation's authoritative assertion/binding from the state
/// RECORD; the physical carrier is preserved. Derivability is tested
/// ONLY against remaining relation-record fields — carrier inspection
/// and transcript full-recompute are excluded.
///
/// Invocations (each = one independent xcodebuild process, own R0
/// artifact directory under /tmp/simigo-gdelta/results/replication-gdelta/):
///   form      build two sessions S_A / S_B + placeholder variant
///   full      Gδ-FULL baseline battery (P7-1 structure, fresh run)
///   gdeltaI   identity assertion removed — cross-session conflation
///   gdeltaP   position assertion removed — boundary-integrity probe
///   gdeltaA   anchor assertion removed — same-I/same-P/different-content
///   gdeltaC   continuation binding removed — invariant-assertion probe
///   adjudicate mechanical assembly of per-cell outcomes

final class GDeltaMinimalityTests: XCTestCase {

  // MARK: frozen constants (design §2–§3)

  static let serverURL = URL(string: "http://127.0.0.1:8080")!
  static let work = URL(fileURLWithPath: "/tmp/simigo-gdelta", isDirectory: true)
  static let productRepo = "/Users/mr.simi/Documents/SimiGo"
  static let replicationBase = GDeltaMinimalityTests.work.appendingPathComponent("results/replication-gdelta", isDirectory: true)

  // Session A (P7-1 frozen content)
  static let aInitial = "I am organizing desktop files into a folder called ReferenceFiles containing project management documents."
  static let aTurn = "What folder did I create?"
  static let aEntities = ["ReferenceFiles", "project management"]
  // Session B (different computation, same model)
  static let bInitial = "I am planning a three day trip to Kyoto in November and created an itinerary document called KyotoPlan."
  static let bTurn = "What document did I create?"
  static let bEntities = ["KyotoPlan", "Kyoto"]

  static let deltaP = "What is the name of the folder mentioned?"
  static let deltaC = "Summarize the purpose of the folder mentioned."
  static let deltaR = "What was this folder for again?"

  static let sAFile = GDeltaMinimalityTests.work.appendingPathComponent("checkpoint-sA.json")
  static let sBFile = GDeltaMinimalityTests.work.appendingPathComponent("checkpoint-sB.json")
  static let placeholderFile = GDeltaMinimalityTests.work.appendingPathComponent("placeholder-prefix.json")

  // MARK: types

  struct ModelIdentity: Codable { var modelPath: String; var modelHash: String }
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

  // MARK: R0 helpers

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func harnessSHAString() -> String {
    let data = (try? Data(contentsOf: URL(fileURLWithPath: #filePath))) ?? Data()
    return "sha256:" + sha256Hex(data)
  }

  /// Full-file streaming SHA256 (GGUF ~21GB — never load into memory).
  private static func sha256HexOfFileStreaming(_ path: String) throws -> String {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func newStore() throws -> AuditArtifactStore {
    try AuditArtifactStore(
      context: AuditRunContext.create(
        modelHash: "Cyber-Tiel-GGUF@llama-server-8080",
        checkpointHash: nil,
        repoPath: GDeltaMinimalityTests.productRepo,
        harnessSHA: GDeltaMinimalityTests.harnessSHAString(),
        configHash: "sha256:" + GDeltaMinimalityTests.sha256Hex(Data("predictionTokens=32;seed=42;greedy;tools=nil".utf8))),
      baseDirectory: GDeltaMinimalityTests.replicationBase)
  }

  private func verifyOrThrow(_ store: AuditArtifactStore) throws {
    let checks = try store.verify()
    let data = try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: store.directory.appendingPathComponent("r0_verify.json"))
    let failed = checks.filter { !$0.value }
    guard failed.isEmpty else {
      throw NSError(domain: "GDelta.R0", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "R0 verify failed: \(failed.keys.joined(separator: ","))"])
    }
    store.record("r0_verify", payload: ["result": "ALL_PASS"])
  }

  // MARK: shared helpers

  private func makeStack() -> (LLAMAServerExecutionStateBackend, ExecutionContinuityCoordinator) {
    let backend = LLAMAServerExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    return (backend, coordinator)
  }

  private func anchorHash(_ tokens: [Int]) -> String {
    GDeltaMinimalityTests.sha256Hex(Data(tokens.map { String($0) }.joined(separator: ",").utf8))
  }

  private func writeCheckpoint(_ cp: CheckpointV2, to url: URL) throws {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(cp).write(to: url)
  }

  private func readCheckpoint(_ url: URL) throws -> CheckpointV2 {
    try JSONDecoder().decode(CheckpointV2.self, from: Data(contentsOf: url))
  }

  private func fileSHA(_ url: URL) -> String? {
    guard let d = try? Data(contentsOf: url) else { return nil }
    return GDeltaMinimalityTests.sha256Hex(d)
  }

  private func makeExecutor() -> LLAMAServerExecutionStateExecutor {
    LLAMAServerExecutionStateExecutor(baseURL: GDeltaMinimalityTests.serverURL)
  }

  /// Build one session S₀ by real tokenize + real generate.
  /// Returns the captured checkpoint v2.
  private func buildSession(
    store: AuditArtifactStore, execTag: String,
    initial: String, turn: String
  ) async throws -> CheckpointV2 {
    let executor = makeExecutor()
    let (backend, coordinator) = makeStack()
    let id = ContractID("gdelta-\(execTag)-\(UUID().uuidString.prefix(8))")

    let t0 = try await executor.tokenizeText(initial)
    let handle0 = try await coordinator.create(
      id: id, position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: initial, continuationID: "\(execTag)-turn-0"))
    try await coordinator.bindRepresentation(
      executionID: id, position: handle0.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: t0))

    let t1 = try await executor.tokenizeText(turn)
    let handle1 = try await coordinator.continueExecution(
      handle0, continuation: ExecutionContinuation(nextInput: turn, continuationID: "\(execTag)-turn-1"))
    try await coordinator.bindRepresentation(
      executionID: id, position: handle1.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: t0 + t1))

    store.record("generate_start", payload: ["tag": execTag])
    let completion = try await executor.complete(tokenPrefix: t0 + t1, predictionTokens: 32, seed: 42)
    guard let gen = completion.tokens else {
      throw NSError(domain: "GDelta", code: 10, userInfo: [NSLocalizedDescriptionKey: "no tokens (\(execTag))"])
    }
    store.record("generate_complete", payload: ["tag": execTag, "tokens": "\(gen.count)", "content": completion.content])

    let handle2 = try await coordinator.continueExecution(
      handle1, continuation: ExecutionContinuation(nextInput: completion.content, continuationID: "\(execTag)-turn-2"))
    let full = t0 + t1 + gen
    try await coordinator.bindRepresentation(
      executionID: id, position: handle2.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: full))

    let rep = try await backend.captureRepresentation(for: handle2)
    guard let payload = rep.payload as? LLAMAServerPrefixPayload else {
      throw NSError(domain: "GDelta", code: 11, userInfo: [NSLocalizedDescriptionKey: "capture failed (\(execTag))"])
    }
    let executor2 = makeExecutor()
    let props = try await executor2.props()
    let modelPath = props.modelPath ?? "UNKNOWN"
    let modelHash = try Self.sha256HexOfFileStreaming(modelPath)
    store.record("gguf_hash", payload: ["path": modelPath, "sha256_prefix": String(modelHash.prefix(16))])
    let cp = CheckpointV2(
      schemaVersion: 2,
      executionID: rep.executionID.rawValue,
      position: rep.position.value,
      continuationNextInput: handle2.continuation.nextInput,
      continuationID: handle2.continuation.continuationID,
      tokenPrefix: payload.tokenPrefix,
      anchorHash: anchorHash(payload.tokenPrefix),
      modelIdentity: ModelIdentity(modelPath: modelPath, modelHash: modelHash))
    store.record("session_built", payload: [
      "tag": execTag, "position": "\(cp.position)",
      "prefix_count": "\(cp.tokenPrefix.count)", "anchor": cp.anchorHash])
    return cp
  }

  /// Same-length placeholder surgery (Gδ-A carrier construction):
  /// replace the token span of the entity "ReferenceFiles" with the
  /// same count of placeholder tokens; fallback = replace even-index
  /// tokens. Length strictly preserved; surgery recorded (D6).
  private func placeholderVariant(of tokens: [Int], executor: LLAMAServerExecutionStateExecutor, store: AuditArtifactStore) async throws -> [Int] {
    let entityTokens = try await executor.tokenizeText("ReferenceFiles")
    let filler = try await executor.tokenizeText("PlaceholderXX")
    guard let fillerToken = filler.first else {
      throw NSError(domain: "GDelta", code: 40, userInfo: [NSLocalizedDescriptionKey: "no filler token"])
    }
    var out = tokens
    var replaced = 0
    if !entityTokens.isEmpty, entityTokens.count <= tokens.count {
      var i = 0
      while i <= tokens.count - entityTokens.count {
        if Array(tokens[i..<(i + entityTokens.count)]) == entityTokens {
          for j in 0..<entityTokens.count { out[i + j] = fillerToken }
          replaced += entityTokens.count
          i += entityTokens.count
        } else { i += 1 }
      }
    }
    if replaced == 0 {
      for i in stride(from: 0, to: out.count, by: 2) { out[i] = fillerToken }
      store.record("placeholder_surgery", payload: ["method": "even-index-filler", "length": "\(out.count)"])
    } else {
      store.record("placeholder_surgery", payload: [
        "method": "entity-span", "replaced_tokens": "\(replaced)", "length": "\(out.count)"])
    }
    precondition(out.count == tokens.count, "placeholder surgery must preserve length")
    return out
  }

  /// Restore a payload under an anonymous identity (identity relation
  /// removed): fresh random ID, lineage root = itself, no model check.
  private func attachAnonymous(
    _ backend: LLAMAServerExecutionStateBackend, _ coordinator: ExecutionContinuityCoordinator,
    tag: String, prefix: [Int], position: Int64
  ) async throws -> ExecutionStateHandle {
    let anonID = ContractID("gdelta-anon-\(tag)-\(UUID().uuidString.prefix(6))")
    let handle = try await coordinator.attach(ExecutionStateHandle(
      id: anonID,
      lineage: ExecutionLineage(root: anonID),
      position: ExecutionPosition(position),
      continuation: ExecutionContinuation(nextInput: "", continuationID: "anon"),
      lifecycle: .restored))
    try await backend.restoreRepresentation(ExecutionRepresentation(
      executionID: handle.id, position: handle.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: prefix)))
    return handle
  }

  // MARK: form — two sessions + placeholder variant

  func testGDeltaForm() async throws {
    try? FileManager.default.removeItem(at: GDeltaMinimalityTests.work)
    try FileManager.default.createDirectory(at: GDeltaMinimalityTests.work, withIntermediateDirectories: true)
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "G-delta", "phase": "form"])
    defer { store.finish() }

    let cpA = try await buildSession(store: store, execTag: "sA", initial: Self.aInitial, turn: Self.aTurn)
    let cpB = try await buildSession(store: store, execTag: "sB", initial: Self.bInitial, turn: Self.bTurn)
    try writeCheckpoint(cpA, to: Self.sAFile)
    try writeCheckpoint(cpB, to: Self.sBFile)

    let executor = makeExecutor()
    let phPrefix = try await placeholderVariant(of: cpA.tokenPrefix, executor: executor, store: store)
    let phRecord: [String: Any] = [
      "base_executionID": cpA.executionID, "base_position": "\(cpA.position)",
      "base_anchorHash": cpA.anchorHash, "base_prefix_count": "\(cpA.tokenPrefix.count)",
      "placeholder_prefix_count": "\(phPrefix.count)",
      "placeholder_anchorHash": anchorHash(phPrefix),
      "anchor_differs": anchorHash(phPrefix) != cpA.anchorHash ? "YES" : "NO"]
    let phData = try JSONSerialization.data(withJSONObject: phRecord, options: [.prettyPrinted, .sortedKeys])
    try phData.write(to: Self.placeholderFile)

    try store.writeSummary([
      "role": "form", "r0RunUUID": store.runUUID,
      "sA_executionID": cpA.executionID, "sA_position": "\(cpA.position)",
      "sA_prefix_count": "\(cpA.tokenPrefix.count)", "sA_anchor": cpA.anchorHash,
      "sB_executionID": cpB.executionID, "sB_position": "\(cpB.position)",
      "sB_prefix_count": "\(cpB.tokenPrefix.count)", "sB_anchor": cpB.anchorHash,
      "same_position_A_B": cpA.position == cpB.position ? "YES" : "NO",
      "placeholder_anchor_differs": phRecord["anchor_differs"] as! String])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["phase": "form"])
  }

  // MARK: Gδ-FULL — baseline battery (P7-1 structure, fresh run)

  func testGDeltaFull() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "G-delta", "cell": "FULL"])
    defer { store.finish() }
    let cp = try readCheckpoint(Self.sAFile)
    let executor = makeExecutor()
    let (backend, coordinator) = makeStack()

    // M1: model identity verified (GGUF hash recomputed once)
    let props = try await executor.props()
    let jI1 = props.modelPath == cp.modelIdentity.modelPath
    var jI2 = false
    if let path = props.modelPath {
      let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
      defer { try? handle.close() }
      var hasher = SHA256()
      while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
      jI2 = hasher.finalize().map { String(format: "%02x", $0) }.joined() == cp.modelIdentity.modelHash
    }
    store.record("m1_identity", payload: ["J-I1": jI1 ? "YES" : "NO", "J-I2": jI2 ? "YES" : "NO"])

    // fork: two independent attaches + divergent continuations
    func attach(_ suffix: String) async throws -> (ExecutionStateHandle, [Int]) {
      let h = try await coordinator.attach(ExecutionStateHandle(
        id: ContractID(cp.executionID + suffix),
        lineage: ExecutionLineage(root: ContractID(cp.executionID)),
        position: ExecutionPosition(cp.position),
        continuation: ExecutionContinuation(nextInput: cp.continuationNextInput, continuationID: cp.continuationID),
        lifecycle: .restored))
      try await backend.restoreRepresentation(ExecutionRepresentation(
        executionID: h.id, position: h.position,
        payload: LLAMAServerPrefixPayload(tokenPrefix: cp.tokenPrefix)))
      return (h, try backend.boundPrefix(for: h).prefix)
    }
    let (parentHandle, parentForkPrefix) = try await attach("-parent")
    let (childHandle, childForkPrefix) = try await attach("-child")
    let jA1 = anchorHash(parentForkPrefix) == cp.anchorHash && anchorHash(childForkPrefix) == cp.anchorHash

    let parentID = ContractID(cp.executionID + "-parent")
    let dPTokens = try await executor.tokenizeText(Self.deltaP)
    let pH1 = try await coordinator.continueExecution(
      parentHandle, continuation: ExecutionContinuation(nextInput: Self.deltaP, continuationID: "gdelta-full-dP"))
    let preGenP = parentForkPrefix + dPTokens
    try await coordinator.bindRepresentation(executionID: parentID, position: pH1.position,
                                             payload: LLAMAServerPrefixPayload(tokenPrefix: preGenP))
    let jP2Parent = pH1.position.value == cp.position + 1 && preGenP.count == cp.tokenPrefix.count + dPTokens.count
    let genP = try await executor.complete(tokenPrefix: preGenP, predictionTokens: 32, seed: 42)
    guard let genPTokens = genP.tokens else { throw NSError(domain: "GDelta", code: 12) }
    let pH2 = try await coordinator.continueExecution(
      pH1, continuation: ExecutionContinuation(nextInput: genP.content, continuationID: "gdelta-full-genP"))
    let fullP = preGenP + genPTokens
    try await coordinator.bindRepresentation(executionID: parentID, position: pH2.position,
                                             payload: LLAMAServerPrefixPayload(tokenPrefix: fullP))
    let parentRep = try await backend.captureRepresentation(for: pH2)
    guard let parentPayload = parentRep.payload as? LLAMAServerPrefixPayload else { throw NSError(domain: "GDelta", code: 13) }
    let parentCP = CheckpointV2(schemaVersion: 2, executionID: parentRep.executionID.rawValue,
                                position: parentRep.position.value,
                                continuationNextInput: pH2.continuation.nextInput,
                                continuationID: pH2.continuation.continuationID,
                                tokenPrefix: parentPayload.tokenPrefix,
                                anchorHash: anchorHash(parentPayload.tokenPrefix),
                                modelIdentity: cp.modelIdentity)
    try writeCheckpoint(parentCP, to: GDeltaMinimalityTests.work.appendingPathComponent("gdelta-full-parent.json"))

    // restore-to-N + divergent continuation on child side
    let childID = ContractID(cp.executionID + "-child")
    let dCTokens = try await executor.tokenizeText(Self.deltaC)
    let cH1 = try await coordinator.continueExecution(
      childHandle,
      continuation: ExecutionContinuation(nextInput: Self.deltaC, continuationID: "gdelta-full-dC"))
    let preGenC = childForkPrefix + dCTokens
    try await coordinator.bindRepresentation(executionID: childID, position: cH1.position,
                                             payload: LLAMAServerPrefixPayload(tokenPrefix: preGenC))
    let genC = try await executor.complete(tokenPrefix: preGenC, predictionTokens: 32, seed: 42)
    guard let genCTokens = genC.tokens else { throw NSError(domain: "GDelta", code: 14) }
    // Child branch continues with its generated turn (P7-1 battery structure:
    // branch state ends after the assistant response, not mid-exchange).
    let cH2 = try await coordinator.continueExecution(
      cH1, continuation: ExecutionContinuation(nextInput: genC.content, continuationID: "gdelta-full-genC"))
    let childFullPrefix = preGenC + genCTokens
    try await coordinator.bindRepresentation(executionID: childID, position: cH2.position,
                                             payload: LLAMAServerPrefixPayload(tokenPrefix: childFullPrefix))
    let jA2 = anchorHash(fullP) != anchorHash(childFullPrefix)

    // restore child checkpoint → ΔR continuation → anchored output
    let childCP = CheckpointV2(schemaVersion: 2, executionID: ContractID(cp.executionID + "-child").rawValue,
                               position: cH2.position.value,
                               continuationNextInput: cH2.continuation.nextInput,
                               continuationID: cH2.continuation.continuationID,
                               tokenPrefix: childFullPrefix, anchorHash: anchorHash(childFullPrefix),
                               modelIdentity: cp.modelIdentity)
    try writeCheckpoint(childCP, to: GDeltaMinimalityTests.work.appendingPathComponent("gdelta-full-child.json"))
    let (rBackend, rCoordinator) = makeStack()
    let rHandle = try await rCoordinator.attach(ExecutionStateHandle(
      id: ContractID(childCP.executionID + "-restore"),
      lineage: ExecutionLineage(root: ContractID(childCP.executionID)),
      position: ExecutionPosition(childCP.position),
      continuation: ExecutionContinuation(nextInput: childCP.continuationNextInput, continuationID: childCP.continuationID),
      lifecycle: .restored))
    try await rBackend.restoreRepresentation(ExecutionRepresentation(
      executionID: rHandle.id, position: rHandle.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: childCP.tokenPrefix)))
    let rBound = try rBackend.boundPrefix(for: rHandle)
    let jP1 = rHandle.position.value == childCP.position && rBound.prefix.count == childCP.tokenPrefix.count
    let dRTokens = try await executor.tokenizeText(Self.deltaR)
    let rH1 = try await rCoordinator.continueExecution(
      rHandle, continuation: ExecutionContinuation(nextInput: Self.deltaR, continuationID: "gdelta-full-dR"))
    let rPrefix = rBound.prefix + dRTokens
    try await rCoordinator.bindRepresentation(executionID: rHandle.id, position: rH1.position,
                                              payload: LLAMAServerPrefixPayload(tokenPrefix: rPrefix))
    let jC1 = Array(rPrefix.prefix(childCP.tokenPrefix.count)) == childCP.tokenPrefix
    let genR = try await executor.complete(tokenPrefix: rPrefix, predictionTokens: 32, seed: 42)
    let jC4 = GDeltaMinimalityTests.aEntities.contains { genR.content.contains($0) }

    // parent non-pollution replay
    let replay = try await executor.complete(tokenPrefix: preGenP, predictionTokens: 32, seed: 42)
    let jPN1 = replay.content == genP.content

    let cells: [String: String] = [
      "C1_identity": (jI1 && jI2) ? "PASS" : "INCONCLUSIVE",
      "C2_position": jP2Parent ? "PASS" : "FAIL",
      "C3_anchor": jA1 ? "PASS" : "FAIL",
      "C4_continuation": (jP1 && jC1 && jC4) ? "PASS" : "FAIL",
      "C5_parent_non_pollution": jPN1 ? "PASS" : "FAIL",
      "J-A2_divergence": jA2 ? "PASS" : "FAIL"]
    let allPass = cells.values.dropLast().allSatisfy { $0 == "PASS" } && cells["J-A2_divergence"] == "PASS"
    try store.writeSummary([
      "role": "full", "r0RunUUID": store.runUUID,
      "cells": cells,
      "baseline_consistent": allPass ? "YES" : "NO",
      "verdict_local": allPass ? "CONTINUATION_VALIDATED_CROSSBACKEND" : "DEVIATION",
      "restore_output": genR.content])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["cell": "FULL", "consistent": allPass ? "YES" : "NO"])
  }

  // MARK: Gδ-I — identity assertion removed

  func testGDeltaI() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "G-delta", "cell": "I"])
    defer { store.finish() }
    let cpA = try readCheckpoint(Self.sAFile)
    let cpB = try readCheckpoint(Self.sBFile)
    let executor = makeExecutor()
    let (backend, coordinator) = makeStack()

    // Probe 1 (whole-record conflation): each identity-stripped record is
    // self-consistent — restored anonymously, both proceed without any
    // remaining relation distinguishing which computation they belong to.
    var conflationResults: [String] = []
    for (tag, cp) in [("anon-A", cpA), ("anon-B", cpB)] {
      do {
        let h = try await attachAnonymous(backend, coordinator, tag: tag,
                                          prefix: cp.tokenPrefix, position: cp.position)
        let bound = try backend.boundPrefix(for: h)
        let dT = try await executor.tokenizeText(Self.deltaP)
        let h2 = try await coordinator.continueExecution(
          h, continuation: ExecutionContinuation(nextInput: Self.deltaP, continuationID: "anon-cont"))
        try await coordinator.bindRepresentation(
          executionID: h.id, position: h2.position,
          payload: LLAMAServerPrefixPayload(tokenPrefix: bound.prefix + dT))
        conflationResults.append("\(tag):ACCEPTED_NO_DETECTION")
      } catch {
        conflationResults.append("\(tag):REJECTED(\(error))")
      }
    }
    let conflation = conflationResults.allSatisfy { $0.hasSuffix("ACCEPTED_NO_DETECTION") }

    // Probe 2 (cross-payload swap): record A's non-carrier assertions
    // paired with payload B — does ANY remaining relation detect?
    var crossDetected = false
    do {
      let h = try await attachAnonymous(backend, coordinator, tag: "cross",
                                        prefix: cpB.tokenPrefix, position: cpA.position)
      let bound = try backend.boundPrefix(for: h)
      // A assertion (retained in Gδ-I) checked against the swapped carrier:
      crossDetected = anchorHash(bound.prefix) != cpA.anchorHash
      store.record("cross_swap_probe", payload: [
        "record": "A", "carrier": "B",
        "anchor_detects_mismatch": crossDetected ? "YES" : "NO"])
    } catch {
      crossDetected = true
      store.record("cross_swap_probe", payload: ["rejected": "\(error)"])
    }

    // Outcome assembly (frozen §3): probe 1 undetected ⇒ provenance
    // conflation ⇒ I necessity ("which computation state" unassertable).
    // Probe 2 detected ⇒ content-mismatch sub-function compensated by A
    // (partial subsumption, Layer 2 registered). Model binding:
    // structurally uncompensated (no remaining field references model).
    let outcome: String
    if conflation && crossDetected {
      outcome = "NECESSITY_EVIDENCE(provenance conflation + model-binding uncompensated; content-mismatch sub-function compensated by A — partial subsumption registered, Layer 2 noted)"
    } else if conflation {
      outcome = "NECESSITY_EVIDENCE(provenance conflation; content-mismatch not compensated either — full necessity)"
    } else {
      outcome = "COMPENSATED(remaining relations refused anonymous restore — Layer 2)"
    }

    try store.writeSummary([
      "role": "gdeltaI", "r0RunUUID": store.runUUID,
      "conflation_results": conflationResults.joined(separator: " | "),
      "cross_swap_detected_by_A": crossDetected ? "YES" : "NO",
      "removed_relation": "identity(modelIdentity + executionID/lineage binding)",
      "remaining_relations": "P/A/C",
      "outcome": outcome,
      "structural_note": "model-binding function: without modelIdentity no remaining field references the model — wrong-model restore structurally undetectable (single-GGUF behavioral test deferred)"])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["cell": "I", "outcome": outcome])
  }

  // MARK: Gδ-P — position assertion removed

  func testGDeltaP() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "G-delta", "cell": "P"])
    defer { store.finish() }
    let cp = try readCheckpoint(Self.sAFile)
    let executor = makeExecutor()
    let (backend, coordinator) = makeStack()

    // (a) Derivability: position from remaining record fields?
    //     anchorHash is a preimage-free hash ⇒ position NOT derivable
    //     from {I,A,C} record fields. Carrier counting is EXCLUDED
    //     (carrier inspection). → recorded, not testable further.
    store.record("derivability", payload: [
      "position_from_remaining_fields": "NOT_DERIVABLE (hash has no preimage; carrier counting excluded)"])

    // (b) Boundary-integrity probe: restore with a TRUNCATED carrier
    //     under the position-free record. Does any remaining relation
    //     detect the progress mismatch?
    let truncated = Array(cp.tokenPrefix.dropLast(8))
    var truncationDetected = false
    do {
      let h = try await attachAnonymous(backend, coordinator, tag: "P-trunc",
                                        prefix: truncated, position: cp.position)
      let bound = try backend.boundPrefix(for: h)
      // Remaining-relation check that IS still available: the record's
      // anchor assertion vs the (truncated) carrier.
      truncationDetected = anchorHash(bound.prefix) != cp.anchorHash
      store.record("truncation_probe", payload: [
        "carrier_count": "\(truncated.count)", "original_count": "\(cp.tokenPrefix.count)",
        "anchor_detects_mismatch": truncationDetected ? "YES" : "NO"])
      // continuation proceeds mechanically on the truncated carrier
      let dT = try await executor.tokenizeText(Self.deltaP)
      let h2 = try await coordinator.continueExecution(
        h, continuation: ExecutionContinuation(nextInput: Self.deltaP, continuationID: "anon-cont"))
      try await coordinator.bindRepresentation(
        executionID: h.id, position: h2.position,
        payload: LLAMAServerPrefixPayload(tokenPrefix: bound.prefix + dT))
      store.record("truncated_continuation", payload: ["proceeded": "YES"])
    } catch {
      store.record("truncation_probe", payload: ["rejected_by_remaining_relation": "\(error)"])
      truncationDetected = true
    }

    // Frozen §3 preregistered outcome: full-prefix anchor MAY subsume P
    // on this representation (anchor changes ⇒ truncation exposed by A).
    let outcome = truncationDetected
      ? "COMPENSATED(A ⊇ P for boundary integrity on full-prefix-anchor representation) — closure revision gate"
      : "NECESSITY_EVIDENCE"
    try store.writeSummary([
      "role": "gdeltaP", "r0RunUUID": store.runUUID,
      "removed_relation": "position assertion",
      "remaining_relations": "I/A/C",
      "derivability_from_remaining_fields": "NOT_DERIVABLE",
      "truncation_detected_by_remaining": truncationDetected ? "YES(A)" : "NO",
      "outcome": outcome,
      "carrier_dependence_note": "MLX KV carrier: P NOT derivable from A (S1: processedTokenCount 31712 ≠ renderable) — if llama compensates, register carrier-dependence of P necessity"])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["cell": "P", "outcome": outcome])
  }

  // MARK: Gδ-A — anchor assertion removed

  func testGDeltaA() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "G-delta", "cell": "A"])
    defer { store.finish() }
    let cp = try readCheckpoint(Self.sAFile)
    let phData = try Data(contentsOf: Self.placeholderFile)
    let ph = try JSONSerialization.jsonObject(with: phData) as! [String: Any]
    guard let phCountStr = ph["placeholder_prefix_count"] as? String, let phCount = Int(phCountStr),
          phCount == cp.tokenPrefix.count else {
      throw NSError(domain: "GDelta", code: 41, userInfo: [NSLocalizedDescriptionKey: "placeholder length mismatch"])
    }
    let executor = makeExecutor()
    let (backend, coordinator) = makeStack()
    let filler = try await executor.tokenizeText("PlaceholderXX")[0]
    // Reconstruct the placeholder carrier with the SAME surgery rule as form.
    let phPrefix = try await placeholderVariant(of: cp.tokenPrefix, executor: executor, store: store)
    precondition(phPrefix.count == cp.tokenPrefix.count, "same-P construction")

    // Two records: SAME I (same execution binding), SAME P (same position,
    // same token count), SAME C — different content (original vs placeholder).
    // With the anchor assertion REMOVED, the records are indistinguishable
    // at relation level; only the carrier bytes differ (excluded from
    // derivability checks).
    func recordWithoutAnchor(_ prefix: [Int]) -> [String: Any] {
      [
        "executionID": cp.executionID,       // same I
        "position": "\(cp.position)",        // same P
        "continuation": cp.continuationID,   // same C
        "prefix_count": "\(prefix.count)",   // same P (token count)
        "anchor": "REMOVED"                  // anchor assertion removed
      ]
    }
    let recOrig = recordWithoutAnchor(cp.tokenPrefix)
    let recPh = recordWithoutAnchor(phPrefix)
    let relationLevelEqual = (recOrig as! [String: String]) == (recPh as! [String: String])
    store.record("same_I_P_C_records", payload: [
      "relation_level_equal": relationLevelEqual ? "YES" : "NO",
      "carrier_bytes_differ": anchorHash(cp.tokenPrefix) != anchorHash(phPrefix) ? "YES" : "NO"])

    // Swap test: restore the PLACEHOLDER carrier under the original
    // record's I/P/C — no remaining relation can flag the substitution.
    let h = try await attachAnonymous(backend, coordinator, tag: "A-ph",
                                      prefix: phPrefix, position: cp.position)
    let dT = try await executor.tokenizeText(Self.deltaP)
    let h2 = try await coordinator.continueExecution(
      h, continuation: ExecutionContinuation(nextInput: Self.deltaP, continuationID: "anon-cont"))
    try await coordinator.bindRepresentation(
      executionID: h.id, position: h2.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: phPrefix + dT))
    store.record("generate_start", payload: ["tag": "placeholder-continuation"])
    let genPh = try await executor.complete(tokenPrefix: phPrefix + dT, predictionTokens: 32, seed: 42)
    // Contrast: continuation on the ORIGINAL content (same record minus carrier)
    let genOrig = try await executor.complete(tokenPrefix: cp.tokenPrefix + dT, predictionTokens: 32, seed: 42)
    let outputsDiffer = genPh.content != genOrig.content
    let origAnchored = GDeltaMinimalityTests.aEntities.contains { genOrig.content.contains($0) }
    store.record("generate_complete", payload: [
      "tag": "same-I-P-two-contents",
      "original_output": genOrig.content,
      "placeholder_output": genPh.content,
      "outputs_differ": outputsDiffer ? "YES" : "NO",
      "original_anchored": origAnchored ? "YES" : "NO"])

    // Necessity signature (frozen §3): same I/P, different content,
    // anchor-free records indistinguishable — two logically different
    // continuation points conflated ⇒ A necessity evidence.
    let outcome = (relationLevelEqual && outputsDiffer) ? "NECESSITY_EVIDENCE" : "INCONCLUSIVE(构造未成立——按预登记路由)"
    try store.writeSummary([
      "role": "gdeltaA", "r0RunUUID": store.runUUID,
      "removed_relation": "anchor binding",
      "remaining_relations": "I/P/C",
      "relation_level_records_equal": relationLevelEqual ? "YES" : "NO",
      "outputs_differ": outputsDiffer ? "YES" : "NO",
      "original_anchored": origAnchored ? "YES" : "NO",
      "outcome": outcome])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["cell": "A", "outcome": outcome])
  }

  // MARK: Gδ-C — continuation binding removed

  func testGDeltaC() async throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "G-delta", "cell": "C"])
    defer { store.finish() }
    let cp = try readCheckpoint(Self.sAFile)
    let executor = makeExecutor()
    let (backend, coordinator) = makeStack()

    // Record with I/P/A intact, continuation binding REMOVED (empty
    // nextInput + empty continuationID — no legal-attachment assertion).
    let h = try await coordinator.attach(ExecutionStateHandle(
      id: ContractID(cp.executionID + "-anonC"),
      lineage: ExecutionLineage(root: ContractID(cp.executionID)),
      position: ExecutionPosition(cp.position),
      continuation: ExecutionContinuation(nextInput: "", continuationID: ""),
      lifecycle: .restored))
    try await backend.restoreRepresentation(ExecutionRepresentation(
      executionID: h.id, position: h.position,
      payload: LLAMAServerPrefixPayload(tokenPrefix: cp.tokenPrefix)))
    let bound = try backend.boundPrefix(for: h)

    // Two DIFFERENT appends both accepted — no contract distinguishes a
    // legitimate continuation from an arbitrary one.
    let d1 = try await executor.tokenizeText(Self.deltaP)
    let d2 = try await executor.tokenizeText("What is the weather?")
    var accepts: [String] = []
    for (tag, dT) in [("Δ1", d1), ("Δ2", d2)] {
      let h2 = try await coordinator.continueExecution(
        h, continuation: ExecutionContinuation(nextInput: "", continuationID: ""))
      try await coordinator.bindRepresentation(
        executionID: h.id, position: h2.position,
        payload: LLAMAServerPrefixPayload(tokenPrefix: bound.prefix + dT))
      let g = try await executor.complete(tokenPrefix: bound.prefix + dT, predictionTokens: 32, seed: 42)
      accepts.append("\(tag):ACCEPTED(\(g.tokens?.count ?? 0)tok)")
    }
    store.record("two_appends_accepted", payload: ["results": accepts.joined(separator: " | ")])

    // Invariant-assertion probe (frozen §3): with the continuation
    // binding removed, the record provides NO basis to assert that a
    // given output is the continuation of THAT state (vs a fresh
    // computation on the same text) — the INV-C assertion is
    // unconstructible from {I,P,A}.
    let outcome = "NECESSITY_EVIDENCE(invariant-assertion level: continuation-of-THIS-state unconstructible from I/P/A; both divergent appends accepted without a legitimizing contract)"
    try store.writeSummary([
      "role": "gdeltaC", "r0RunUUID": store.runUUID,
      "removed_relation": "continuation binding",
      "remaining_relations": "I/P/A",
      "two_appends_accepted": "YES",
      "outcome": outcome,
      "note": "no crash-testing: judgment at the invariant-assertion level per frozen design"])
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["cell": "C", "outcome": outcome])
  }

  // MARK: adjudication — mechanical assembly (frozen §5)

  func testGDeltaAdjudicate() throws {
    let store = try newStore()
    store.record("run_start", payload: ["experiment": "G-delta", "role": "judgment"])
    defer { store.finish() }

    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(atPath: GDeltaMinimalityTests.replicationBase.path)
    var byRole: [String: (String, [String: Any])] = [:]
    for name in entries.sorted() {
      let dir = GDeltaMinimalityTests.replicationBase.appendingPathComponent(name, isDirectory: true)
      guard let data = try? Data(contentsOf: dir.appendingPathComponent("summary.json")),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let role = obj["role"] as? String
      else { continue }
      guard byRole[role] == nil else {
        throw NSError(domain: "GDelta.Judgment", code: 50,
                      userInfo: [NSLocalizedDescriptionKey: "duplicate role \(role)"])
      }
      byRole[role] = (name, obj)
    }
    guard let full = byRole["full"], let gI = byRole["gdeltaI"], let gP = byRole["gdeltaP"],
          let gA = byRole["gdeltaA"], let gC = byRole["gdeltaC"],
          byRole.count == 6, byRole["form"] != nil else {
      throw NSError(domain: "GDelta.Judgment", code: 51,
                    userInfo: [NSLocalizedDescriptionKey: "expected roles form+full/gdeltaI/gdeltaP/gdeltaA/gdeltaC, found: \(byRole.keys.sorted().joined(separator: ","))"])
    }
    store.record("judgment_inputs", payload: [
      "full": full.0, "I": gI.0, "P": gP.0, "A": gA.0, "C": gC.0])

    var v: [String: String] = [:]
    // FULL baseline consistency (prerequisite per execution discipline #1)
    v["FULL_baseline_consistent"] = (full.1["baseline_consistent"] as? String) == "YES" ? "PASS" : "FAIL"
    // Layer 1 per-cell outcomes (verbatim from mechanical cell runs)
    v["Gδ-I_outcome"] = gI.1["outcome"] as? String ?? "MISSING"
    v["Gδ-P_outcome"] = gP.1["outcome"] as? String ?? "MISSING"
    v["Gδ-A_outcome"] = gA.1["outcome"] as? String ?? "MISSING"
    v["Gδ-C_outcome"] = gC.1["outcome"] as? String ?? "MISSING"

    let outcomes = [v["Gδ-I_outcome"]!, v["Gδ-P_outcome"]!, v["Gδ-A_outcome"]!, v["Gδ-C_outcome"]!]
    let allNecessity = outcomes.allSatisfy { $0.hasPrefix("NECESSITY_EVIDENCE") }
    let anyCompensated = outcomes.contains { $0.hasPrefix("COMPENSATED") }
    let anyInconclusive = outcomes.contains { $0.hasPrefix("INCONCLUSIVE") }

    let overall: String
    if v["FULL_baseline_consistent"] != "PASS" {
      overall = "INCONCLUSIVE(FULL baseline deviated — battery invalid)"
    } else if anyInconclusive {
      overall = "INCONCLUSIVE"
    } else if allNecessity {
      // Wording cap (frozen §5): this label, and nothing stronger.
      overall = "CANDIDATE_CLOSURE_WITH_EXPERIMENTALLY_SUPPORTED_NECESSITY_OF_EACH_RELATION"
    } else if anyCompensated {
      overall = "CLOSURE_REVISION_REQUIRED(subsumption registered — see per-cell outcomes)"
    } else {
      overall = "MIXED"
    }
    v["overall"] = overall

    for (k, val) in v { store.record("judgment", payload: ["cell": k, "value": val]) }
    store.record("judgment_note", payload: [
      "text": "mechanical assembly of frozen G-δ §5; wording cap enforced — 'minimal proven' is not a legal output; compensated outcomes route to the closure revision gate"])

    var judgment: [String: Any] = [:]
    judgment["cells"] = v
    judgment["overall"] = overall
    judgment["inputs"] = ["full": full.0, "I": gI.0, "P": gP.0, "A": gA.0, "C": gC.0]
    let jdata = try JSONSerialization.data(withJSONObject: judgment, options: [.prettyPrinted, .sortedKeys])
    try jdata.write(to: store.directory.appendingPathComponent("judgment.json"))
    try verifyOrThrow(store)
    store.record("run_complete", payload: ["role": "judgment", "overall": overall])
    print("[gdelta] overall: \(overall)")
  }
}
