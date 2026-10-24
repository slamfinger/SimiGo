import CryptoKit
import Foundation
import SimiGoRuntimeContract
import LOCALBCore
import SimiGo2Experimental

// MARK: - G1/G3 controlled headless production entry (A | V1)
//
// Reuses the EXISTING production implementation. It does NOT define a second
// model loader, KV manager, settlement protocol, or recovery algorithm:
//   * inference  -> the same public `NativeMLX.start` / `NativeMLX.generate`
//                   that HTTPServer's generateHandler wraps,
//   * settlement -> the same `ExecutionStateGraphStore.settleProducerResult`
//                   (native result-contract gate -> SimiGoSettlementAuthority
//                   -> authoritative SQLite IS commit),
//   * model path -> `ModelInfo(kind: .mlx)` resolved by the caller / driver.
//
// RESTRICTED PRODUCTION PATH (explicit, per the task's honesty requirement):
// generation is driven by calling NativeMLX directly instead of going through the
// full Service/HTTPServer socket layer. Bypassed behaviors:
//   - HTTP request parsing and OpenAI-schema response encoding,
//   - the LOCALB request-authorization gate that lives on the wire.
// NOT bypassed: model loading (LLMModelFactory), KV / prefix-pool lifecycle,
// the native settlement gate, digest verification, and the SQLite IS commit.
// Evidence produced here is therefore labeled `restricted_production_path`.

/// Semantic KV-cache identity, tied to a single in-process NativeMLX instance
/// (its ModelContainer / KV ownership), NOT to a raw memory address.
/// Recorded per process so ES1 and ES2 cache identities can be compared.

enum SimiGoHeadlessRole: String {
    case produce
    case consume
    /// G3 memory-tier probe: runs the production generate, then the production
    /// idle-suspend lifecycle (via the DEBUG suspendIdleTimeoutOverride test seam),
    /// observing reference-release / resource-reclaim / resume events + footprint.
    case memprobe
    /// G1.9-A layer-forward trace driver: runs the ALREADY-SHIPPED
    /// `ExecutionTracePilot` (Packages/SimiGoRuntime .../Instrumentation) which
    /// installs passive observation modules on the decoder MLP down-projection
    /// and records one `layerEntered` event per (pass, decoder layer). This role
    /// only drives that existing instrumentation and writes its report; it adds
    /// no instrumentation of its own and changes no model behaviour.
    case tracepilot
}

/// Minimal injectable cache-root resolver so KV carriers honor `SIMIGO_HOME`
/// exactly like `SimiGoPaths.databaseURL` already does. DEFAULT BEHAVIOR IS
/// UNCHANGED: with no `SIMIGO_HOME`, both resolve to `<home>/.simigo/...`, the
/// same locations used before. This exists so an isolated experiment root can
/// control prefix-pool / branch-checkpoints and prove ES2 does not read ES1's
/// old KV (the `old_kv_unreachable` negative control).
enum SimiGoRuntimeCachePaths {
    nonisolated static var prefixPoolRoot: URL { root(appending: "prefix-pool") }
    nonisolated static var branchCheckpointsRoot: URL { root(appending: "branch-checkpoints") }

    nonisolated private static func root(appending: String) -> URL {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        // SIMIGO_CACHE_ROOT lets the IS (SIMIGO_HOME) stay shared while the KV
        // carriers (prefix-pool / branch-checkpoints) point at a distinct, empty
        // root — the disk-level basis for old_kv_unreachable. With neither set,
        // DEFAULT behavior is unchanged (<home>/.simigo/...).
        if let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty {
            base = URL(fileURLWithPath: (cache as NSString).standardizingPath, isDirectory: true)
        } else if let home = env["SIMIGO_HOME"], !home.isEmpty {
            base = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".simigo", isDirectory: true)
        }
        return base.appendingPathComponent(appending, isDirectory: true)
    }
}

enum SimiGoG1G3Entry {

    // MARK: - Env evaluation (fail closed)

    struct Decision {
        let requested: Bool
        let role: SimiGoHeadlessRole?
        let error: String?
    }

    /// Only enters headless mode when `SIMIGO_HEADLESS_ROLE` is present and
    /// non-empty. Absent/empty => the normal GUI launch path is untouched.
    static func evaluate(env: [String: String] = ProcessInfo.processInfo.environment) -> Decision {
        guard let raw = env["SIMIGO_HEADLESS_ROLE"], !raw.isEmpty else {
            return Decision(requested: false, role: nil, error: nil)
        }
        guard let role = SimiGoHeadlessRole(rawValue: raw) else {
            return Decision(requested: true, role: nil,
                            error: "unsupported SIMIGO_HEADLESS_ROLE '\(raw)' (allowed: produce|consume|memprobe|tracepilot)")
        }
        // Fail closed on missing required parameters BEFORE any model work.
        func need(_ key: String) -> String? {
            guard let v = env[key], !v.isEmpty else { return nil }
            return v
        }
        guard need("SIMIGO_EXPERIMENT_ROOT") != nil else {
            return Decision(requested: true, role: nil, error: "SIMIGO_EXPERIMENT_ROOT missing")
        }
        guard need("SIMIGO_RUN_ID") != nil else {
            return Decision(requested: true, role: nil, error: "SIMIGO_RUN_ID missing")
        }
        guard need("SIMIGO_HEADLESS_MODEL_PATH") != nil else {
            return Decision(requested: true, role: nil, error: "SIMIGO_HEADLESS_MODEL_PATH missing")
        }
        switch role {
        case .produce, .memprobe:
            guard need("SIMIGO_HEADLESS_TARGET_VALUE") != nil else {
                return Decision(requested: true, role: nil, error: "SIMIGO_HEADLESS_TARGET_VALUE missing (produce|memprobe)")
            }
        case .consume:
            guard need("SIMIGO_HEADLESS_STATE_ID") != nil else {
                return Decision(requested: true, role: nil, error: "SIMIGO_HEADLESS_STATE_ID missing (consume)")
            }
        case .tracepilot:
            // Model path, experiment root and run id are already required above.
            break
        }
        return Decision(requested: true, role: role, error: nil)
    }

    // MARK: - Evidence helpers

    private static func env(_ key: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? ""
    }

    private static func writeEvidence(_ obj: [String: Any], role: SimiGoHeadlessRole) {
        let rootURL = URL(fileURLWithPath: env("SIMIGO_EXPERIMENT_ROOT"), isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let runID = env("SIMIGO_RUN_ID")
        let url = rootURL.appendingPathComponent("\(role.rawValue)_\(runID).json")
        var mutable = obj
        mutable["role"] = role.rawValue
        mutable["run_id"] = runID
        mutable["pid"] = ProcessInfo.processInfo.processIdentifier
        mutable["simigo_home"] = env("SIMIGO_HOME")
        mutable["is_database_url"] = SimiGoPaths.databaseURL.path
        mutable["prefix_pool_root"] = SimiGoRuntimeCachePaths.prefixPoolRoot.path
        mutable["branch_checkpoints_root"] = SimiGoRuntimeCachePaths.branchCheckpointsRoot.path
        if let data = try? JSONSerialization.data(withJSONObject: mutable, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
            FileHandle.standardError.write("wrote evidence \(url.path)\n".data(using: .utf8)!)
        }
    }

    // MARK: - Entry point

    static func run(role: SimiGoHeadlessRole) async -> Int32 {
        switch role {
        case .produce: return await produce()
        case .consume: return await consume()
        case .memprobe: return await memprobe()
        case .tracepilot: return await tracePilot()
        }
    }

    // MARK: - tracepilot (G1.9-A layer-forward trace)

    /// Drive the shipped `ExecutionTracePilot` and persist its report verbatim.
    ///
    /// What the numbers are: the pilot installs passive observation modules on
    /// each decoder layer's MLP down-projection and records one `layerEntered`
    /// event per (forward pass, layer). A forward pass is delimited where layer 0
    /// is entered again. Nothing here counts a demand, a prediction, or an
    /// estimate; a layer that does not execute emits no event.
    ///
    /// Honesty boundary (also written into the evidence): the observed scope is
    /// DECODER_MLP_DOWN_PROJ - the decoder core is not directly observed - and
    /// the path is the restricted production path (NativeMLX / MLXLMCommon
    /// generation below HTTPServer), not the Service/HTTP wire path.
    private static func tracePilot() async -> Int32 {
        let modelPath = env("SIMIGO_HEADLESS_MODEL_PATH")
        let rootURL = URL(fileURLWithPath: env("SIMIGO_EXPERIMENT_ROOT"), isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let runID = env("SIMIGO_RUN_ID")

        var evidence: [String: Any] = [
            "model_path": modelPath,
            "model_identity": modelIdentity(fromPath: modelPath),
            "path_class": "restricted_production_path",
            "runtime_identity": runtimeIdentity(),
            "driver": "SimiGoHeadlessRole=tracepilot -> ExecutionTracePilot.run (shipped instrumentation)",
            "observed_scope": "DECODER_MLP_DOWN_PROJ",
            "observation_kind": "OBSERVED_LAYER_ENTERED_ONLY",
        ]

        do {
            let report = try await ExecutionTracePilot.run(
                modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true),
                repetitions: 2,
                maxTokens: 16
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            let reportURL = rootURL.appendingPathComponent("layerforwardtrace_\(runID).json")
            try data.write(to: reportURL, options: .atomic)

            // Derived bookkeeping only: aggregate the OBSERVED events by decoder
            // layer and by forward pass. No estimate is produced for a layer
            // that emitted no event.
            var cases: [[String: Any]] = []
            for pilotCase in report.cases {
                var perLayer: [String: Int] = [:]
                var eventTotal = 0
                var stepTotal = 0
                for trace in pilotCase.traces {
                    stepTotal += trace.steps.count
                    for event in trace.events {
                        perLayer["L\(event.decoderLayer)", default: 0] += 1
                        eventTotal += 1
                    }
                }
                cases.append([
                    "prompt_id": pilotCase.promptID,
                    "repetitions": pilotCase.repetitions,
                    "pass_counts_per_repetition": pilotCase.passCounts,
                    "forward_passes_total": stepTotal,
                    "layer_entered_events_total": eventTotal,
                    "layer_entered_events_per_decoder_layer": perLayer,
                    "distinct_decoder_layers_observed": perLayer.count,
                    "token_sequence_identical": pilotCase.identity.tokenSequenceIdentical,
                    "logits_bitwise_identical": pilotCase.identity.logitsBitwiseIdentical,
                    "trace_stable_across_repetitions": pilotCase.traceStableAcrossRepetitions,
                    "g19a1_baseline_identity_pass": pilotCase.g19a1BaselineIdentityPass,
                    "g19a2_trace_stability_pass": pilotCase.g19a2TraceStabilityPass,
                ])
            }

            evidence["status"] = report.status == "PASS" ? "OK" : "FAIL"
            evidence["pilot_status"] = report.status
            evidence["protocol_version"] = report.protocolVersion
            evidence["pilot_boundary"] = report.boundary
            evidence["model_type"] = report.modelType
            evidence["instrumented_module_count"] = report.instrumentedModuleCount
            evidence["g19a1_baseline_identity_pass"] = report.g19a1BaselineIdentityPass
            evidence["g19a2_trace_stability_pass"] = report.g19a2TraceStabilityPass
            evidence["overhead_summary"] = report.g19a3OverheadSummary
            evidence["cases"] = cases
            evidence["report_file"] = reportURL.path
            evidence["report_sha256"] = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
        } catch {
            evidence["status"] = "BLOCKED"
            evidence["stage"] = "trace_pilot"
            evidence["error"] = String(describing: error)
            writeEvidence(evidence, role: .tracepilot)
            return 3
        }

        writeEvidence(evidence, role: .tracepilot)
        return (evidence["status"] as? String) == "OK" ? 0 : 4
    }

    // MARK: - produce (ES1)

    private static func produce() async -> Int32 {
        let modelPath = env("SIMIGO_HEADLESS_MODEL_PATH")
        let targetValue = env("SIMIGO_HEADLESS_TARGET_VALUE")
        var evidence: [String: Any] = [
            "model_path": modelPath,
            "target_value": targetValue,
            "target_value_source": "env SIMIGO_HEADLESS_TARGET_VALUE (no in-binary constant)",
            "path_class": "restricted_production_path",
            "runtime_identity": runtimeIdentity(),
            "model_identity": modelIdentity(fromPath: modelPath),
            "tokenizer_identity": tokenizerIdentity(fromPath: modelPath),
        ]

        let store = await MainActor.run { ExecutionStateGraphStore() }
        let state: ExecutionStateRecord
        do {
            state = try await MainActor.run { () throws -> ExecutionStateRecord in
                let created = try store.create()
                return try store.continueState(created, input: targetValue)
            }
        } catch {
            evidence["status"] = "BLOCKED"
            evidence["stage"] = "state_setup"
            evidence["error"] = String(describing: error)
            writeEvidence(evidence, role: .produce)
            return 4
        }
        evidence["state_id"] = state.id
        evidence["is_settlement_expected_value"] = state.nextInput

        let runtime = NativeMLX(info: ModelInfo(path: modelPath, kind: .mlx), config: samplingConfig(modelPath))
        evidence["cache_identity"] = runtime.cacheIdentity

        do {
            try await startIsolated(runtime, modelPath: modelPath)
            evidence["reached_stage"] = "start_ok"
            writeEvidence(evidence, role: .produce)
            let producePrompt = "Output exactly one line and nothing else: RESULT=\(targetValue)"
            evidence["produce_prompt_text"] = producePrompt
            let result = await MainActor.run { () -> [JSONValue] in
                [ .object([ "role": .string("user"), "content": .string(producePrompt) ]) ]
            }
            // Production HTTP-client protocol: register the request in the
            // lifecycle ledger (QUEUED/CREATED) before NativeMLX.generate, which
            // transitions it to RUNNING. Without register, generate fails closed
            // with CancellationError (see RESEARCH_STATE 15080). This is the same
            // step the HTTPServer request dispatch performs, not a bypass.
            let produceRequestID = "g1-produce-\(env("SIMIGO_RUN_ID"))"
            await RuntimeLifecycleCoordinator.shared.register(requestID: produceRequestID, sessionID: "es1-produce")
            let gen = try await runtime.generate(
                requestId: produceRequestID,
                sessionId: "es1-produce",
                messages: result,
                tools: nil,
                config: samplingConfig(modelPath)
            ) { _ in }
            await RuntimeLifecycleCoordinator.shared.finish(requestID: produceRequestID, success: true, reason: "g1g3-produce")
            let settled = try await MainActor.run {
                try store.settleProducerResult(generatedText: gen.text, boundToState: state)
            }
            evidence["generated_text"] = gen.text
            evidence["prompt_tokens"] = gen.usage?.promptTokens ?? NSNull()
            evidence["generation_tokens"] = gen.usage?.generationTokens ?? NSNull()
            evidence["settlement_payload_digest"] = settled.payloadDigest
            // Read back from the authoritative SQLite IS to prove the write landed.
            let receipts = await MainActor.run { () -> [String] in
                guard let db = try? SimiGoESISDatabase(url: SimiGoPaths.databaseURL) else { return [] }
                _ = try? db.runMigrations()
                return (try? db.readSettlementReceipts().filter { $0.stateID == state.id }
                        .map { $0.payloadDigest }) ?? []
            }
            evidence["is_settlement_restored_readback"] = receipts.contains(settled.payloadDigest)
            evidence["observation"] = runtime.observation.snapshot()
            evidence["status"] = "OK"
            writeEvidence(evidence, role: .produce)
            // handoff for the driver / ES2
            // The handoff deliberately does NOT carry the produced value: the only
            // cross-process value channel is the settled IS row (audit 1). The
            // driver consumes only state_id + cache identity from this file.
            handoff([
                "run_id": env("SIMIGO_RUN_ID"),
                "state_id": state.id,
                "payload_digest": settled.payloadDigest,
                "cache_identity_es1": runtime.cacheIdentity,
            ])
            return 0
        } catch {
            evidence["status"] = "FAIL"
            evidence["stage"] = "generate_or_settle"
            evidence["error"] = String(describing: error)
            if let le = error as? LocalizedError {
                evidence["error_desc"] = le.errorDescription ?? ""
                evidence["recovery"] = le.recoverySuggestion ?? ""
            }
            writeEvidence(evidence, role: .produce)
            return 5
        }
    }

    // MARK: - consume (ES2, fresh process / fresh KV)

    private static func consume() async -> Int32 {
        let modelPath = env("SIMIGO_HEADLESS_MODEL_PATH")
        let stateID = env("SIMIGO_HEADLESS_STATE_ID")
        var evidence: [String: Any] = [
            "model_path": modelPath,
            "reading_state_id": stateID,
            "path_class": "restricted_production_path",
            "runtime_identity": runtimeIdentity(),
            "model_identity": modelIdentity(fromPath: modelPath),
            "tokenizer_identity": tokenizerIdentity(fromPath: modelPath),
        ]

        // Audit 1 (causal source): the ONLY sanctioned source of U1's value is the
        // settled IS row. Record the SIMIGO_* input channels actually present, and
        // refuse to run if the target value was leaked into this process's env.
        evidence["input_env_keys"] = ProcessInfo.processInfo.environment.keys
            .filter { $0.hasPrefix("SIMIGO_") }.sorted()
        // Any env var that carries the produced value is a bypass channel, even if
        // this process would never read it: the claim is about the channel existing.
        let valueChannels = ["SIMIGO_HEADLESS_TARGET_VALUE", "SIMIGO_EXPERIMENT_TARGET"]
            .filter { !env($0).isEmpty }
        evidence["value_carrying_env_channels"] = valueChannels
        if !valueChannels.isEmpty {
            evidence["status"] = "BLOCKED"
            evidence["stage"] = "input_channel_guard"
            evidence["reason"] = "value-carrying env channel(s) present in consume env: "
                + valueChannels.joined(separator: ",")
            evidence["generation_call_count"] = 0
            writeEvidence(evidence, role: .consume)
            return 7
        }

        // Recover U1's already-settled semantic value from the shared SQLite IS and
        // verify it through PRODUCTION APIs before any model work: source + digest
        // integrity (SimiGoSettlementAuthority.payloadDigestMatches, the same hashing
        // that sealed it) and dynamic validity (settlementValidity). Any failure is
        // fail-closed BEFORE a NativeMLX instance is created or generate is called,
        // so the model-generation call count for these controls is provably zero.
        enum Recovery {
            case ok(digest: String, value: String)
            case missing
            case digestMismatch
            case invalidated
            case emptyValue
        }
        let recovery: Recovery = await MainActor.run {
            guard let db = try? SimiGoESISDatabase(url: SimiGoPaths.databaseURL),
                  (try? db.runMigrations()) != nil else { return .missing }
            let rows = (try? db.readSettlementReceipts()) ?? []
            guard let row = rows.first(where: { $0.stateID == stateID }) else { return .missing }
            guard SimiGoSettlementAuthority.payloadDigestMatches(row.payload, recordedDigest: row.payloadDigest) else {
                return .digestMismatch
            }
            if let validity = try? db.settlementValidity(row.id.uuidString), validity != "valid" {
                return .invalidated
            }
            let value = extractContent(from: row.payload) ?? ""
            if value.isEmpty { return .emptyValue }
            return .ok(digest: row.payloadDigest, value: value)
        }
        // generation_call_count is zero on every fail-closed branch below (no
        // NativeMLX.generate has run at this point).
        switch recovery {
        case .missing, .digestMismatch, .invalidated, .emptyValue:
            evidence["status"] = "BLOCKED"
            evidence["stage"] = "is_verify_u1"
            switch recovery {
            case .missing: evidence["reason"] = "no settled U1 for state \(stateID) in IS"
            case .digestMismatch: evidence["reason"] = "settlement payload/digest verification failed (tamper)"
            case .invalidated: evidence["reason"] = "settled U1 dependency invalidated"
            case .emptyValue: evidence["reason"] = "settled U1 value empty"
            case .ok: break
            }
            evidence["generation_call_count"] = 0
            writeEvidence(evidence, role: .consume)
            return 6
        case .ok(let digest, let value):
            evidence["u1_payload_digest_from_is"] = digest
            evidence["u1_recovered_value"] = value
            evidence["settlement_digest_verified"] = true
            evidence["settlement_validity_valid"] = true
            evidence["result_reuse_via_IS"] = true
        }
        let u1value: String
        if case .ok(_, let v) = recovery { u1value = v } else { u1value = "" }

        // Continue: U2 commits to a value DERIVED from the recovered U1 result.
        let u2Value = u1value + "-U2"
        let u2Prompt = "Recovered prior result: \(u1value). Output exactly one line and nothing else: RESULT=\(u2Value)"
        evidence["u2_prompt_text"] = u2Prompt
        evidence["u2_value_derivation"] = "u2_expected = u1_recovered_value + \"-U2\""
        evidence["u1_recovery_api"] = "SimiGoESISDatabase.readSettlementReceipts() filtered by stateID, then SimiGoSettlementAuthority.payloadDigestMatches + settlementValidity"
        let promptCarriesRecovered = !u1value.isEmpty && u2Prompt.contains(u1value)
        evidence["u2_prompt_contains_recovered_value"] = promptCarriesRecovered
        let baseline = env("SIMIGO_COUNTERFACTUAL_BASELINE_VALUE")
        if !baseline.isEmpty {
            evidence["counterfactual_baseline_value"] = baseline
            evidence["u1_value_differs_from_baseline"] = (u1value != baseline)
        }
        if !promptCarriesRecovered {
            // Defensive: the generation request must carry the IS-recovered value.
            // Never reached when recovery succeeded; kept fail-closed before model work.
            evidence["status"] = "BLOCKED"
            evidence["stage"] = "prompt_construction"
            evidence["generation_call_count"] = 0
            writeEvidence(evidence, role: .consume)
            return 6
        }
        let store = await MainActor.run { ExecutionStateGraphStore() }
        let state2Made: ExecutionStateRecord? = await MainActor.run {
            guard let created = try? store.create() else { return nil }
            return try? store.continueState(created, input: u2Value)
        }
        guard let state2 = state2Made else {
            evidence["status"] = "BLOCKED"
            evidence["stage"] = "state_setup"
            writeEvidence(evidence, role: .consume)
            return 4
        }
        evidence["u2_state_id"] = state2.id
        evidence["u2_expected_value"] = u2Value

        // Fresh NativeMLX in this process => its own new KV / cache identity.
        let runtime = NativeMLX(info: ModelInfo(path: modelPath, kind: .mlx), config: samplingConfig(modelPath))
        let es1CacheEnv = env("SIMIGO_HEADLESS_ES1_CACHE_IDENTITY")
        evidence["cache_identity_es2"] = runtime.cacheIdentity
        evidence["es1_cache_identity_from_env"] = es1CacheEnv
        evidence["cache_identity_env_present"] = !es1CacheEnv.isEmpty
        // Requires a non-empty ES1 identity from the driver, so this can never be
        // trivially true by comparing against an empty string.
        evidence["cache_identity_differs_from_es1"] =
            !es1CacheEnv.isEmpty && (runtime.cacheIdentity != es1CacheEnv)

        do {
            try await startIsolated(runtime, modelPath: modelPath)
            let messages: [JSONValue] = await MainActor.run {
                [ .object([ "role": .string("user"), "content": .string(u2Prompt) ]) ]
            }
            let consumeRequestID = "g1-consume-\(env("SIMIGO_RUN_ID"))"
            await RuntimeLifecycleCoordinator.shared.register(requestID: consumeRequestID, sessionID: "es2-consume")
            let gen = try await runtime.generate(
                requestId: consumeRequestID,
                sessionId: "es2-consume",
                messages: messages,
                tools: nil,
                config: samplingConfig(modelPath)
            ) { _ in }
            await RuntimeLifecycleCoordinator.shared.finish(requestID: consumeRequestID, success: true, reason: "g1g3-consume")
            let settled = try await MainActor.run {
                try store.settleProducerResult(generatedText: gen.text, boundToState: state2)
            }
            evidence["generated_text_u2"] = gen.text
            evidence["u2_prompt_tokens"] = gen.usage?.promptTokens ?? NSNull()
            evidence["u2_generation_tokens"] = gen.usage?.generationTokens ?? NSNull()
            // §5: actual prefill/cache/reuse metrics are now observed from the
            // engine via NativeMLXObservation (see evidence["observation"]).
            // Per-forward (layer-level) call counts remain NOT_INSTRUMENTED;
            // generation_tokens_engine_reported is the labelled token-granularity proxy.
            evidence["prefill_forward_calls"] = "PARTIAL_SEE_OBSERVATION_SNAPSHOT"
            evidence["u2_settlement_payload_digest"] = settled.payloadDigest
            evidence["real_model_continuation"] = (gen.usage?.generationTokens ?? 0) > 0
            // Output-level causal link (audit 1): the generated text must contain
            // the IS-recovered value, not just the prompt.
            evidence["u2_output_contains_recovered_value"] = gen.text.contains(u1value)
            evidence["u2_output_contains_expected_u2"] = gen.text.contains(u2Value)
            evidence["observation"] = runtime.observation.snapshot()
            evidence["status"] = "OK"
            writeEvidence(evidence, role: .consume)
            return 0
        } catch {
            evidence["status"] = "FAIL"
            evidence["stage"] = "generate_or_settle"
            evidence["error"] = String(describing: error)
            writeEvidence(evidence, role: .consume)
            return 5
        }
    }

    // MARK: - memprobe (G3 memory-tier lifecycle observation)

    /// Mach task memory footprint (phys_footprint, bytes), if obtainable.
    private static func footprintBytes() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint)
    }

    private static func memprobe() async -> Int32 {
        let modelPath = env("SIMIGO_HEADLESS_MODEL_PATH")
        let targetValue = env("SIMIGO_HEADLESS_TARGET_VALUE")
        var evidence: [String: Any] = [
            "model_path": modelPath, "target_value": targetValue,
            "path_class": "restricted_production_path", "probe": "g3_memory_tiers",
            "runtime_identity": runtimeIdentity(),
            "model_identity": modelIdentity(fromPath: modelPath),
            "tokenizer_identity": tokenizerIdentity(fromPath: modelPath),
        ]
        let store = await MainActor.run { ExecutionStateGraphStore() }
        let state: ExecutionStateRecord
        do {
            state = try await MainActor.run { () throws -> ExecutionStateRecord in
                let created = try store.create()
                return try store.continueState(created, input: targetValue)
            }
        } catch {
            evidence["status"] = "BLOCKED"; evidence["stage"] = "state_setup"
            writeEvidence(evidence, role: .memprobe); return 4
        }
        let runtime = NativeMLX(info: ModelInfo(path: modelPath, kind: .mlx), config: samplingConfig(modelPath))
        let rid = env("SIMIGO_RUN_ID")
        let reqID = "g1-memprobe-\(rid)"
        do {
            try await startIsolated(runtime, modelPath: modelPath)
            await RuntimeLifecycleCoordinator.shared.register(requestID: reqID, sessionID: "memprobe")
            let warm = try await runtime.generate(
                requestId: reqID, sessionId: "memprobe",
                messages: [ .object([ "role": .string("user"),
                    "content": .string("Output exactly one line and nothing else: RESULT=\(targetValue)") ]) ],
                tools: nil, config: samplingConfig(modelPath)) { _ in }
            await RuntimeLifecycleCoordinator.shared.finish(requestID: reqID, success: true, reason: "g1g3-memprobe-warm")
            let pre = footprintBytes()
            let snapPre = await MainActor.run { runtime.observation.snapshot() }
            #if DEBUG
            RuntimeTuning.suspendIdleTimeoutOverrideSeconds = 0
            #endif
            let suspended = await runtime.suspendIfIdle()
            let post = footprintBytes()
            let snapSuspend = await MainActor.run { runtime.observation.snapshot() }
            // Resume: the next generate must reload the model container (lifecycle resume event).
            let reqID2 = "g1-memprobe-\(rid)-resume"
            await RuntimeLifecycleCoordinator.shared.register(requestID: reqID2, sessionID: "memprobe")
            let warm2 = try await runtime.generate(
                requestId: reqID2, sessionId: "memprobe",
                messages: [ .object([ "role": .string("user"),
                    "content": .string("Output exactly one line and nothing else: RESULT=\(targetValue)") ]) ],
                tools: nil, config: samplingConfig(modelPath)) { _ in }
            await RuntimeLifecycleCoordinator.shared.finish(requestID: reqID2, success: true, reason: "g1g3-memprobe-resume")
            let snapEnd = await MainActor.run { runtime.observation.snapshot() }
            let evSuspend = (snapSuspend["events"] as? [String: Any]) ?? [:]
            let evEnd = (snapEnd["events"] as? [String: Any]) ?? [:]
            let preTotal = (snapPre["events"] as? [String: Any])?["reference_release"] as? Int ?? 0
            let preRes = (snapPre["events"] as? [String: Any])?["resource_reclaim"] as? Int ?? 0
            let preSus = (snapPre["events"] as? [String: Any])?["lifecycle_suspend"] as? Int ?? 0
            // Delta must be measured against the PRE-suspend snapshot; taking it from
            // snapEnd would compare the value with itself and always yield 0.
            let preRes2 = (snapPre["events"] as? [String: Any])?["lifecycle_resume"] as? Int ?? 0
            evidence["warm_generated"] = warm.text
            evidence["post_resume_generated"] = warm2.text
            evidence["suspend_returned_true"] = suspended
            evidence["reference_release_observed"] = ((evSuspend["reference_release"] as? Int ?? 0) > preTotal)
            evidence["sessions_released"] = evSuspend["sessions_released_at_release"] ?? NSNull()
            evidence["model_container_ref_dropped"] = evSuspend["model_container_ref_dropped"] ?? NSNull()
            evidence["sessions_after_release"] = evSuspend["sessions_after_release"] ?? NSNull()
            evidence["model_container_present_before"] = evSuspend["model_container_present_before"] ?? NSNull()
            evidence["model_container_absent_after"] = evSuspend["model_container_absent_after"] ?? NSNull()
            evidence["suspend_events_ordered"] = snapSuspend["events_ordered"] ?? NSNull()
            evidence["resource_reclaim_level"] = "OPERATION_INVOKED (not bytes; not physical pages)"
            evidence["resource_reclaim_observed"] = ((evSuspend["resource_reclaim"] as? Int ?? 0) > preRes)
            evidence["lifecycle_suspend_delta"] = (evSuspend["lifecycle_suspend"] as? Int ?? 0) - preSus
            evidence["lifecycle_resume_delta"] = (evEnd["lifecycle_resume"] as? Int ?? 0) - preRes2
            evidence["footprint_pre_bytes"] = pre ?? NSNull()
            evidence["footprint_post_suspend_bytes"] = post ?? NSNull()
            evidence["footprint_delta_bytes"] = (pre != nil && post != nil) ? (pre! - post!) : NSNull()
            evidence["physical_page_return_note"] = "footprint delta recorded as SUPPORTING only; per gate def RSS/footprint/exit alone cannot PASS physical_page_return (malloc relief is a hint, no independent OS page-reclaim proof)."
            evidence["observation_end"] = snapEnd
            evidence["status"] = "OK"
            writeEvidence(evidence, role: .memprobe)
            return 0
        } catch {
            evidence["status"] = "FAIL"; evidence["stage"] = "memprobe_lifecycle"
            evidence["error"] = String(describing: error)
            writeEvidence(evidence, role: .memprobe)
            return 5
        }
    }

    // MARK: - model / tokenizer identity (task §5)

    /// Resolve durable model identity (repoID + revision=snapshot hash) via the
    /// PRODUCTION SimiGoModelDiscovery, matching the resolved weight file under the
    /// given snapshot path. Records model instance + revision, NOT just a path.
    private static func modelIdentity(fromPath path: String) -> [String: Any] {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let match = SimiGoModelDiscovery.discover().first {
            $0.fileURL.standardizedFileURL.path.hasPrefix(url.path)
        }
        var out: [String: Any] = ["model_path": path]
        if let m = match {
            out["model_repo_id"] = m.repoID
            out["model_revision"] = m.revision ?? NSNull()
            out["model_root_id"] = m.rootID
        } else {
            out["model_repo_id"] = NSNull(); out["model_revision"] = NSNull()
        }
        return out
    }

    /// Tokenizer identity: name + content SHA-256 (production digest) of each
    /// tokenizer artifact present in the snapshot. Content-addressed, so identity
    /// is auditable, not just a filename.
    private static func tokenizerIdentity(fromPath path: String) -> [[String: Any]] {
        let dir = URL(fileURLWithPath: path).standardizedFileURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.lastPathComponent.lowercased().contains("tokenizer")
                       || $0.lastPathComponent.lowercased().contains("vocab") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { f in
                guard let data = try? Data(contentsOf: f) else { return nil }
                return ["file": f.lastPathComponent,
                        "sha256": SimiGoSettlementAuthority.payloadDigest(data)]
            }
    }

    // MARK: - helpers

    /// Reuses the PRODUCTION `NativeMLX.startWithLOCALB` with a one-time,
    /// isolated transport identity so a standalone headless process can drive
    /// `runtime.generate` directly (not over a protected HTTP route, so no
    /// request-authorization coordinator is required). This is the same public
    /// production entry the management plane uses; it does NOT bypass model
    /// loading, KV lifecycle, or the settlement gate.
    private static func startIsolated(_ runtime: NativeMLX, modelPath: String) async throws {
        let idStore = LOCALBTransportIdentityStore(
            service: "com.simigo.headless.g1g3.\(env("SIMIGO_RUN_ID")).\(UUID().uuidString.prefix(8))",
            account: "tls")
        let identity = try idStore.loadOrCreate()
        try await runtime.startWithLOCALB(
            ModelInfo(path: modelPath, kind: .mlx),
            port: 0,
            localbTransportIdentity: identity,
            localbRequestAuthorization: nil)
    }

    private static func samplingConfig(_ path: String) -> ModelConfig {
        var cfg = ModelConfig.fromModel(path)
        cfg.temperature = 0.0
        cfg.maxTokens = 64
        cfg.disableThinking = true
        return cfg
    }

    /// Identity of the binary that produced this evidence: absolute path +
    /// content SHA-256 of the running executable + OS/build configuration. Ties a
    /// claim to a concrete build instead of a build "feeling".
    private static func runtimeIdentity() -> [String: Any] {
        var out: [String: Any] = [:]
        let exe = Bundle.main.executableURL?.resolvingSymlinksInPath()
        out["executable_path"] = exe?.path ?? NSNull()
        // Debug builds link the real code as @rpath/SimiGo.debug.dylib (~162 MB);
        // the 40 KB launcher alone does NOT identify the build, so the build id
        // covers every Mach-O image inside the bundle.
        var images: [[String: Any]] = []
        var buildIDInput = ""
        if let macosDir = exe?.deletingLastPathComponent() {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: macosDir, includingPropertiesForKeys: nil)) ?? []
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = f.lastPathComponent
                guard f == exe || name.hasSuffix(".dylib") else { continue }
                guard let data = try? Data(contentsOf: f) else { continue }
                let digest = SimiGoSettlementAuthority.payloadDigest(data)
                images.append(["file": name, "sha256": digest, "bytes": data.count])
                buildIDInput += "\(name):\(digest)\n"
            }
        }
        out["bundle_macho_images"] = images
        out["build_id_sha256"] = buildIDInput.isEmpty
            ? NSNull()
            : SimiGoSettlementAuthority.payloadDigest(Data(buildIDInput.utf8))
        if let exe, let data = try? Data(contentsOf: exe) {
            out["executable_sha256"] = SimiGoSettlementAuthority.payloadDigest(data)
            out["executable_bytes"] = data.count
        } else {
            out["executable_sha256"] = NSNull()
        }
        out["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
        #if DEBUG
        out["build_configuration"] = "DEBUG"
        #else
        out["build_configuration"] = "RELEASE"
        #endif
        return out
    }

    private static func extractContent(from payload: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) else { return nil }
        if let dict = obj as? [String: Any], let c = dict["content"] as? String { return c }
        if let dict = obj as? [String: Any],
           let inner = dict["values"] as? [String: Any],
           let c = inner["content"] as? String { return c }
        if let dict = obj as? [String: Any],
           let inner = dict["values"] as? [String: Any],
           let c = (inner["content"] as? [String: Any])?["value"] as? String { return c }
        return nil
    }

    private static func handoff(_ obj: [String: Any]) {
        let rootURL = URL(fileURLWithPath: env("SIMIGO_EXPERIMENT_ROOT"), isDirectory: true)
        let url = rootURL.appendingPathComponent("produce_handoff_\(env("SIMIGO_RUN_ID")).json")
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
