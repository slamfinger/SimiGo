import Foundation
import CryptoKit
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import SimiGo2Experimental

// G2 batch model host.
//
// One process, one model start, one arm step. The runner sends a JSON request
// (path in G2_HOST_REQUEST) and reads a single write-once record
// (host_record.json) from the evidence root. Phase-2 processes refuse any U1
// payload: the restore path must come from the Information Space, not from a
// re-injected source.

struct HostError: Error, CustomStringConvertible {
    let description: String
}

enum Env {
    static func string(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw HostError(description: "missing environment: \(name)")
        }
        return value
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func writeExclusiveJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(
        withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
    guard descriptor >= 0 else {
        throw HostError(description: "exclusive create failed for \(url.path) errno=\(errno)")
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: data)
}

func isoNow() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
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

struct Request: Decodable {
    let mode: String
    let modelDir: String
    let storeBase: String
    let instructions: String?
    let u1Prompt: String?
    let u2Template: String?
    let u2Prompt: String?
    let maxTokensU1: Int
    let maxTokensU2: Int
    let stride: Int
    let idleAfterRecordSeconds: Int?
}

func parameters(maxTokens: Int, stride: Int) -> GenerateParameters {
    var parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
    parameters.prefill.chunking = .remainder
    parameters.prefill.stepSize = stride
    return parameters
}

func renderTokens(
    messages: [[String: String]], modelDirectory: URL, tokenizer: MLXLMCommon.Tokenizer
) async throws -> [Int] {
    let templateURL = modelDirectory.appendingPathComponent("chat_template.jinja")
    if FileManager.default.fileExists(atPath: templateURL.path) {
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        let checkpoint = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
        return try checkpoint.applyChatTemplate(
            messages: messages,
            chatTemplate: .literal(template),
            addGenerationPrompt: true,
            truncation: false,
            maxLength: nil,
            tools: nil,
            additionalContext: ["enable_thinking": false])
    }
    if let configured = tokenizer as? Tokenizers.PreTrainedTokenizer, configured.hasChatTemplate {
        return try configured.applyChatTemplate(
            messages: messages, tools: nil, additionalContext: ["enable_thinking": false])
    }
    return try tokenizer.applyChatTemplate(messages: messages)
}

func generationRecord(
    session: ChatSession, prompt: String, messages: [[String: String]],
    modelDirectory: URL, container: ModelContainer
) async throws -> [String: Any] {
    let start = Date()
    let tokenIDs = try await container.perform { context in
        try await renderTokens(
            messages: messages, modelDirectory: modelDirectory, tokenizer: context.tokenizer)
    }
    var chunks: [String] = []
    var tokenCount: Int?
    for try await generation in session.streamDetails(to: prompt) {
        if let chunk = generation.chunk { chunks.append(chunk) }
        if let info = generation.info { tokenCount = info.generationTokenCount }
    }
    let text = chunks.joined()
    return [
        "request_text": prompt,
        "request_sha256": sha256Hex(Data(prompt.utf8)),
        "request_messages": messages,
        "rendered_message_count": messages.count,
        "prompt_token_count": tokenIDs.count,
        "prompt_token_ids_sha256": sha256Hex(Data(
            tokenIDs.map(String.init).joined(separator: ",").utf8)),
        "chunk_sequence": chunks,
        "chunk_count": chunks.count,
        "completion_token_count": tokenCount.map { $0 as Any } ?? NSNull(),
        "text": text,
        "text_sha256": sha256Hex(Data(text.utf8)),
        "duration_seconds": Date().timeIntervalSince(start),
    ]
}

/// Extract the first balanced JSON object from model text.
func extractJSONObject(_ text: String) -> (canonical: String, object: [String: Any])? {
    let characters = Array(text)
    guard let startIndex = characters.firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var escaped = false
    for index in startIndex..<characters.count {
        let character = characters[index]
        if inString {
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { inString = false }
            continue
        }
        if character == "\"" { inString = true; continue }
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 {
                let slice = String(characters[startIndex...index])
                guard let data = slice.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                guard let canonical = try? JSONSerialization.data(
                    withJSONObject: object, options: [.sortedKeys]),
                    let canonicalText = String(data: canonical, encoding: .utf8)
                else { return nil }
                return (canonicalText, object)
            }
        }
    }
    return nil
}

func runHost() async throws -> Int {
    let startedAt = isoNow()
    let requestURL = URL(fileURLWithPath: try Env.string("G2_HOST_REQUEST"))
    let evidenceRoot = URL(fileURLWithPath: try Env.string("G2_HOST_EVIDENCE"), isDirectory: true)
    guard FileManager.default.fileExists(atPath: evidenceRoot.path) else {
        throw HostError(description: "evidence root must pre-exist")
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let request = try decoder.decode(Request.self, from: Data(contentsOf: requestURL))

    let phase2 = request.mode == "phase2"
    if phase2 && (request.u1Prompt != nil || request.instructions != nil) {
        throw HostError(description: "phase2 must not receive U1 source or old-stage instructions")
    }
    if !phase2 && request.u1Prompt == nil {
        throw HostError(description: "\(request.mode) requires u1_prompt")
    }

    let modelDirectory = URL(fileURLWithPath: request.modelDir, isDirectory: true)
    let storeBase = URL(fileURLWithPath: request.storeBase, isDirectory: true)
    let recordURL = evidenceRoot.appendingPathComponent("host_record.json")

    var record: [String: Any] = [
        "schema_id": "SIMIGO-G2-HOST-RECORD-V1",
        "mode": request.mode,
        "started_at_utc": startedAt,
        "pid": Int(getpid()),
        "parent_pid": Int(getppid()),
        "process_group": Int(getpgrp()),
        "model_directory": modelDirectory.path,
        "store_base": storeBase.path,
        "host": [
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "active_processor_count": ProcessInfo.processInfo.activeProcessorCount,
        ],
    ]
    var checks: [String: Bool] = [:]
    var exitCode = 0

    let identity = MLXPrefixCrossSessionCache.contentIdentity(modelDirectory: modelDirectory)
    record["engine_content_identity"] = [
        "weights_digest": identity.weightsDigest,
        "tokenizer_digest": identity.tokenizerDigest,
        "combined_digest": identity.combinedDigest,
    ]

    let loadStart = Date()
    let container = try await MLXLLM.LLMModelFactory.shared.loadContainer(
        from: modelDirectory, using: #huggingFaceTokenizerLoader())
    record["load"] = ["ok": true, "duration_seconds": Date().timeIntervalSince(loadStart)]

    var runtime: MLXPrefixCrossSessionCache?
    if phase2 {
        let scoped = MLXPrefixCrossSessionCache.namespace(
            modelDirectory: modelDirectory, contentIdentity: identity)
        let storeRoot = MLXPrefixCrossSessionCache.hostRoot(base: storeBase, namespace: scoped)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let store = PrefixSnapshotStore(
            root: storeRoot, pool: ExecutionStatePrefixPool(tokenBudget: 100_000_000))
        let scan = try store.rescan()
        let cacheRuntime = MLXPrefixCrossSessionCache( store: store, namespace: scoped)
        try cacheRuntime.install()
        runtime = cacheRuntime
        record["store"] = [
            "namespace_model_id": scoped.modelID,
            "namespace_kv_fingerprint": scoped.kvFingerprint,
            "root": storeRoot.path,
            "rescan_registered_artifacts": scan,
            "inventory_before": inventory(storeRoot),
        ]
        checks["hook_installed"] = true
    }

    let systemMessage: [[String: String]] = request.instructions.map {
        [["role": "system", "content": $0]]
    } ?? []

    if !phase2 {
        let prompt = request.u1Prompt ?? ""
        let session = ChatSession(
            container, instructions: request.instructions,
            generateParameters: parameters(maxTokens: request.maxTokensU1, stride: request.stride))
        let u1 = try await generationRecord(
            session: session, prompt: prompt,
            messages: systemMessage + [["role": "user", "content": prompt]],
            modelDirectory: modelDirectory, container: container)
        var u1Record = u1
        if let parsed = extractJSONObject(u1["text"] as? String ?? "") {
            u1Record["r1_canonical"] = parsed.canonical
            u1Record["r1_sha256"] = sha256Hex(Data(parsed.canonical.utf8))
            u1Record["r1_parsed"] = true
        } else {
            u1Record["r1_canonical"] = NSNull()
            u1Record["r1_sha256"] = NSNull()
            u1Record["r1_parsed"] = false
            exitCode = 4
        }
        record["u1"] = u1Record
        checks["u1_generated"] = (u1["chunk_count"] as? Int ?? 0) > 0
        checks["u1_parsed"] = u1Record["r1_parsed"] as? Bool ?? false

        if request.mode == "continuous", exitCode == 0 {
            let r1 = u1Record["r1_canonical"] as? String ?? ""
            let template = request.u2Template ?? "{{R1}}"
            let u2Prompt = template.replacingOccurrences(of: "{{R1}}", with: r1)
            var u2Parameters = session.generateParameters
            u2Parameters.maxTokens = request.maxTokensU2
            session.generateParameters = u2Parameters
            let u2 = try await generationRecord(
                session: session, prompt: u2Prompt,
                messages: systemMessage + [
                    ["role": "user", "content": prompt],
                    ["role": "assistant", "content": u1["text"] as? String ?? ""],
                    ["role": "user", "content": u2Prompt],
                ],
                modelDirectory: modelDirectory, container: container)
            record["u2"] = u2
            checks["u2_generated"] = (u2["chunk_count"] as? Int ?? 0) > 0
        }
    } else {
        let prompt = request.u2Prompt ?? ""
        let session = ChatSession(
            container,
            generateParameters: parameters(maxTokens: request.maxTokensU2, stride: request.stride))
        let u2 = try await generationRecord(
            session: session, prompt: prompt,
            messages: [["role": "user", "content": prompt]],
            modelDirectory: modelDirectory, container: container)
        record["u2"] = u2
        checks["u2_generated"] = (u2["chunk_count"] as? Int ?? 0) > 0
    }

    if let runtime {
        let observations = runtime.observations
        record["hook_observations"] = [
            "calls": observations.calls,
            "hits": observations.hits,
            "matched_token_counts": observations.matchedTokenCounts,
            "interface": "MLXPrefixCrossSessionCache.observations",
        ]
        checks["hook_consulted"] = observations.calls > 0
        checks["hook_missed_on_empty_store"] = observations.hits == 0
        let released = runtime.uninstall()
        checks["hook_released"] = released
        if let base = record["store"] as? [String: Any],
           let root = base["root"] as? String {
            let storeRoot = URL(fileURLWithPath: root, isDirectory: true)
            let after = inventory(storeRoot)
            record["store"] = base.merging([
                "inventory_after": after,
                "artifact_root_path": storeRoot.path,
            ]) { _, new in new }
            checks["store_still_empty_after"] = after.isEmpty
        }
    }

    record["checks"] = checks
    record["finished_at_utc"] = isoNow()
    record["exit_code"] = exitCode
    try writeExclusiveJSON(record, to: recordURL)

    if request.mode == "phase1" {
        // Stay alive so the runner can terminate this host and record the
        // lifecycle (SIGTERM, then SIGKILL, then ESRCH).
        let idle = request.idleAfterRecordSeconds ?? 600
        fflush(stdout)
        let deadline = Date().addingTimeInterval(Double(idle))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    return exitCode
}

do {
    let code = try await runHost()
    exit(Int32(code))
} catch {
    // Best-effort failure record; never overwrites a successful one.
    if let root = ProcessInfo.processInfo.environment["G2_HOST_EVIDENCE"] {
        let url = URL(fileURLWithPath: root).appendingPathComponent("host_record.json")
        let payload: [String: Any] = [
            "schema_id": "SIMIGO-G2-HOST-RECORD-V1",
            "error": String(describing: error),
            "pid": Int(getpid()),
            "process_group": Int(getpgrp()),
            "finished_at_utc": isoNow(),
        ]
        try? writeExclusiveJSON(payload, to: url)
    }
    FileHandle.standardError.write(Data("G2Host error: \(error)\n".utf8))
    exit(3)
}
