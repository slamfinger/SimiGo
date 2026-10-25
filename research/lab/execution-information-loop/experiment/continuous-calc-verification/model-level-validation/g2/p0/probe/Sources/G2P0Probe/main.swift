import Foundation
import CryptoKit
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import SimiGo2Experimental

// G2 P0 — model load and observation capability probe.
//
// One process, one model start, no retry. Everything this process observes is
// written once: P0_PROBE.json (facts) and terminal.json (PASS/FAIL). The parent
// runner re-derives the verdict independently and never rewrites these files.
//
// Scope guards are structural, not advisory: this executable has no U1/U2
// payload, no fixture, no carrier handle and no arm logic. It cannot produce a
// G2 batch artifact even if asked.

struct ProbeError: Error, CustomStringConvertible {
    let description: String
}

enum Env {
    static func string(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw ProbeError(description: "missing environment: \(name)")
        }
        return value
    }

    static func int(_ name: String, fallback: Int) -> Int {
        guard let raw = ProcessInfo.processInfo.environment[name], let value = Int(raw) else {
            return fallback
        }
        return value
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func streamingSHA256(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
        let chunk = handle.readData(ofLength: 1 << 20)
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func writeExclusiveJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(
        withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
    guard descriptor >= 0 else {
        throw ProbeError(description: "exclusive create failed for \(url.path) errno=\(errno)")
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: data)
}

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func inventory(_ root: URL) -> [String] {
    guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey])
    else { return [] }
    var paths: [String] = []
    for case let url as URL in enumerator {
        if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            paths.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
        }
    }
    return paths.sorted()
}

func generationRecord(session: ChatSession, prompt: String) async throws -> [String: Any] {
    var chunks: [String] = []
    var tokenCount: Int?
    for try await generation in session.streamDetails(to: prompt) {
        if let chunk = generation.chunk { chunks.append(chunk) }
        if let info = generation.info { tokenCount = info.generationTokenCount }
    }
    return [
        "chunk_sequence": chunks,
        "chunk_count": chunks.count,
        "completion_token_count": tokenCount.map { $0 as Any } ?? NSNull(),
        "text": chunks.joined(),
    ]
}

func runProbe() async throws -> (facts: [String: Any], checks: [String: Bool]) {
    let startedAt = isoNow()
    let start = Date()
    let environment = ProcessInfo.processInfo.environment

    let evidenceRoot = URL(fileURLWithPath: try Env.string("G2P0_EVIDENCE_ROOT"), isDirectory: true)
    guard FileManager.default.fileExists(atPath: evidenceRoot.path) else {
        throw ProbeError(description: "evidence root must pre-exist (created by the runner)")
    }
    let modelDirectory = URL(fileURLWithPath: try Env.string("G2P0_MODEL_DIR"), isDirectory: true)
    let storeBase = URL(fileURLWithPath: try Env.string("G2P0_STORE_BASE"), isDirectory: true)
    let expectedWeights = try Env.string("G2P0_EXPECTED_WEIGHTS_DIGEST")
    let expectedAggregate = try Env.string("G2P0_EXPECTED_AGGREGATE")
    let maxTokens = Env.int("G2P0_PROBE_MAX_TOKENS", fallback: 16)
    let stride = Env.int("G2P0_PREFILL_STRIDE", fallback: 256)
    let prompt = environment["G2P0_PROMPT"] ?? "Reply with exactly one word: ready."

    var facts: [String: Any] = [
        "schema_id": "SIMIGO-G2-P0-PROBE-V1",
        "started_at_utc": startedAt,
        "pid": Int(getpid()),
        "parent_pid": Int(getppid()),
        "process_group": Int(getpgrp()),
        "model_directory": modelDirectory.path,
        "store_base": storeBase.path,
        "prompt": prompt,
        "probe_generation_settings": [
            "decoding": "greedy (temperature = 0)",
            "max_tokens": maxTokens,
            "prefill_chunking": "remainder",
            "prefill_step_size": stride,
        ],
        "host": [
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "active_processor_count": ProcessInfo.processInfo.activeProcessorCount,
        ],
    ]
    var checks: [String: Bool] = [:]

    // ---- artifact, as recorded by the parent's independent file check --------
    let artifactCheckURL = evidenceRoot.appendingPathComponent("artifact_check.json")
    let artifactCheck = (try? Data(contentsOf: artifactCheckURL))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
    let artifactOk = (artifactCheck?["all_match"] as? Bool) ?? false
    let artifactAggregate = artifactCheck?["aggregate_sha256"] as? String
    checks["artifact_rows_match_binding"] = artifactOk
    checks["artifact_aggregate_matches_binding"] = (artifactAggregate == expectedAggregate)
    facts["artifact_check"] = [
        "source": artifactCheckURL.path,
        "all_match": artifactOk,
        "aggregate_sha256": artifactAggregate.map { $0 as Any } ?? NSNull(),
        "expected_aggregate_sha256": expectedAggregate,
    ]

    // ---- engine content identity (public accessor -> EngineModelIdentity) ----
    let identityStart = Date()
    let identity = MLXPrefixCrossSessionCache.contentIdentity(modelDirectory: modelDirectory)
    facts["engine_content_identity"] = [
        "weights_digest": identity.weightsDigest,
        "tokenizer_digest": identity.tokenizerDigest,
        "combined_digest": identity.combinedDigest,
        "expected_weights_digest_from_binding": expectedWeights,
        "weights_digest_matches_binding": identity.weightsDigest == expectedWeights,
        "tokenizer_digest_note":
            "order-sensitive over the tokenizer-like file contents; not derivable from the "
            + "binding's per-file digests, recorded here as the P0 baseline that P1/P2 must reproduce",
        "duration_seconds": Date().timeIntervalSince(identityStart),
    ]
    checks["weights_digest_matches_binding"] = identity.weightsDigest == expectedWeights

    // ---- load, once ----------------------------------------------------------
    let loadStart = Date()
    let container = try await MLXLLM.LLMModelFactory.shared.loadContainer(
        from: modelDirectory, using: #huggingFaceTokenizerLoader())
    facts["load"] = ["ok": true, "duration_seconds": Date().timeIntervalSince(loadStart)]
    checks["container_loaded"] = true

    // ---- prompt render -------------------------------------------------------
    let renderStart = Date()
    let promptTokenIDs = try await container.perform { context in
        try await ChatTemplateGeneration.promptTokenIDs(
            tokenizer: context.tokenizer,
            modelDirectory: modelDirectory,
            prompt: prompt)
    }
    facts["prompt_render"] = [
        "token_count": promptTokenIDs.count,
        "token_ids_sha256": sha256Hex(Data(
            promptTokenIDs.map(String.init).joined(separator: ",").utf8)),
        "first_tokens": Array(promptTokenIDs.prefix(8)),
        "duration_seconds": Date().timeIntervalSince(renderStart),
    ]
    checks["prompt_rendered"] = promptTokenIDs.count > 0

    func parameters() -> GenerateParameters {
        var parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
        parameters.prefill.chunking = .remainder
        parameters.prefill.stepSize = stride
        return parameters
    }

    // ---- generation 1: baseline, no hook installed ---------------------------
    let baselineStart = Date()
    let baseline = try await generationRecord(
        session: ChatSession(container, generateParameters: parameters()), prompt: prompt)
    facts["generation_baseline"] = baseline.merging([
        "hook_installed": false,
        "duration_seconds": Date().timeIntervalSince(baselineStart),
    ]) { _, new in new }
    checks["baseline_generation_completed"] =
        (baseline["chunk_count"] as? Int ?? 0) > 0
        && (baseline["completion_token_count"] is Int)

    // ---- generation 2: hook installed, empty store ---------------------------
    try FileManager.default.createDirectory(at: storeBase, withIntermediateDirectories: true)
    let preExisting = inventory(storeBase)
    guard preExisting.isEmpty else {
        throw ProbeError(description: "store base must be empty before install: \(preExisting)")
    }
    let namespace = MLXPrefixCrossSessionCache.namespace(
        modelDirectory: modelDirectory, contentIdentity: identity)
    let storeRoot = MLXPrefixCrossSessionCache.hostRoot(base: storeBase, namespace: namespace)
    try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
    let store = PrefixSnapshotStore(
        root: storeRoot,
        pool: ExecutionStatePrefixPool(tokenBudget: 100_000_000))
    let rescanCount = try store.rescan()
    facts["store"] = [
        "namespace_model_id": namespace.modelID,
        "namespace_kv_fingerprint": namespace.kvFingerprint,
        "root": storeRoot.path,
        "rescan_registered_artifacts": rescanCount,
        "inventory_before": preExisting,
    ]
    checks["store_initially_empty"] = rescanCount == 0 && preExisting.isEmpty

    let runtime = MLXPrefixCrossSessionCache(store: store, namespace: namespace)
    try runtime.install()
    let hookedStart = Date()
    let hooked = try await generationRecord(
        session: ChatSession(container, generateParameters: parameters()), prompt: prompt)
    let observations = runtime.observations
    let uninstalled = runtime.uninstall()
    facts["generation_hooked"] = hooked.merging([
        "hook_installed": true,
        "hook_uninstalled": uninstalled,
        "duration_seconds": Date().timeIntervalSince(hookedStart),
    ]) { _, new in new }
    facts["hook_observations"] = [
        "calls": observations.calls,
        "hits": observations.hits,
        "matched_token_counts": observations.matchedTokenCounts,
        "interface": "MLXPrefixCrossSessionCache.observations",
    ]
    checks["hooked_generation_completed"] =
        (hooked["chunk_count"] as? Int ?? 0) > 0
        && (hooked["completion_token_count"] is Int)
    checks["hook_consulted"] = observations.calls > 0
    checks["hook_missed_on_empty_store"] = observations.hits == 0
    checks["hook_released"] = uninstalled

    let inventoryAfter = inventory(storeBase)
    facts["store_inventory_after"] = inventoryAfter
    checks["store_still_empty_after"] = inventoryAfter.isEmpty

    facts["generation_outputs_identical"] =
        (baseline["chunk_sequence"] as? [String]) == (hooked["chunk_sequence"] as? [String])
        && (baseline["completion_token_count"] as? Int)
            == (hooked["completion_token_count"] as? Int)

    facts["executable_path"] = Bundle.main.executablePath ?? CommandLine.arguments[0]
    if let path = facts["executable_path"] as? String {
        facts["executable_sha256"] = streamingSHA256(URL(fileURLWithPath: path)) ?? NSNull()
    }
    facts["completed_at_utc"] = isoNow()
    facts["duration_seconds"] = Date().timeIntervalSince(start)
    return (facts, checks)
}

let evidenceRootPath = ProcessInfo.processInfo.environment["G2P0_EVIDENCE_ROOT"] ?? ""

do {
    let result = try await runProbe()
    var facts = result.facts
    let checks = result.checks
    facts["checks"] = checks
    facts["all_checks_pass"] = checks.values.allSatisfy { $0 }
    try writeExclusiveJSON(facts, to: URL(fileURLWithPath: evidenceRootPath)
        .appendingPathComponent("P0_PROBE.json"))
    let terminal: [String: Any] = [
        "schema_id": "SIMIGO-G2-P0-TERMINAL-V1",
        "terminal_state": checks.values.allSatisfy { $0 } ? "PASS" : "FAIL",
        "failed_checks": checks.filter { !$0.value }.keys.sorted(),
        "probe_record": "P0_PROBE.json",
        "completed_at_utc": isoNow(),
    ]
    try writeExclusiveJSON(terminal, to: URL(fileURLWithPath: evidenceRootPath)
        .appendingPathComponent("terminal.json"))
    if !checks.values.allSatisfy({ $0 }) { exit(2) }
} catch {
    let failure: [String: Any] = [
        "schema_id": "SIMIGO-G2-P0-TERMINAL-V1",
        "terminal_state": "FAIL",
        "failed_checks": ["probe_threw"],
        "failure": String(describing: error),
        "completed_at_utc": isoNow(),
        "probe_record": NSNull(),
    ]
    try? writeExclusiveJSON(failure, to: URL(fileURLWithPath: evidenceRootPath)
        .appendingPathComponent("terminal.json"))
    FileHandle.standardError.write(Data("P0 probe failed: \(error)\n".utf8))
    exit(3)
}
