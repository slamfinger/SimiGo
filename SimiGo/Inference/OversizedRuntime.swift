import Foundation
import Synchronization
import SimiGo2Experimental

/// v2.0 beta — oversized-model execution runtime.
///
/// Serves models whose representation exceeds comfortable physical memory
/// (e.g. 41.76 GiB weights on a 32 GiB machine) through the verified
/// segmented engine: placeholder-first load, persistent-floor derivation,
/// controller-driven segment residency (INV-1 audited over segments), and
/// a strict Execution State session per conversation (every turn consumes
/// the bound representation, advances the logical position, and rebinds
/// the advanced prefix).
///
/// Beta scope: single oversized conversation at a time (generation is
/// serialized); greedy decoding; tool calls are not interpreted. All other
/// product paths (NativeMLX, llama-server) are untouched.
public final class OversizedRuntime: Runtime, @unchecked Sendable {
    public static func supports(path: String) -> Bool {
        let fm = FileManager.default
        guard
            let configData = fm.contents(atPath: path + "/config.json"),
            let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
            config["model_type"] as? String == "qwen3_next",
            let indexData = fm.contents(atPath: path + "/model.safetensors.index.json"),
            let index = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any],
            let metadata = index["metadata"] as? [String: Any],
            let totalBytes = metadata["total_size"] as? Int
        else { return false }
        return totalBytes >= 20 * 1024 * 1024 * 1024
    }

    private struct State: @unchecked Sendable {
        var loaded = false
        var running = false
        var generating = false
    }

    private let modelDirectory: URL
    private let engine: OversizedSegmentedEngine
    private let state = Mutex(State())
    /// Serializes generation onto the single Execution State session.
    private let generationLock = NSLock()
    private var httpServer: HTTPServer?
    private var servedTranscript: [EngineChatMessage] = []

    public var isRunning: Bool { state.withLock { $0.running } }
    public var isGenerating: Bool { state.withLock { $0.generating } }
    public var isInProcess: Bool { true }

    init(info: ModelInfo) {
        modelDirectory = URL(fileURLWithPath: info.path, isDirectory: true)
        engine = OversizedSegmentedEngine(modelDirectory: modelDirectory)
    }

    // MARK: - Runtime conformance

    public func start(_ info: ModelInfo, port: Int) async throws {
        state.withLock { $0.loaded = false }
        _ = try await engine.load()
        state.withLock { $0.loaded = true }

        let server = HTTPServer(
            port: port,
            modelId: modelDirectory.lastPathComponent
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/"),
            generateHandler: { [weak self] requestId, _, _, _, messages, _, config, onChunk, _ in
                guard let self else { throw RuntError.notLoaded }
                return try await self.handleGenerate(
                    messages: messages, maxTokens: config.maxTokens, onChunk: onChunk
                )
            },
            forkBranchHandler: { _, _, _, _ in
                throw RuntError.notLoaded
            },
            deleteBranchHandler: { _, _, _ in
                // Beta: branching is a no-op for the oversized path.
            },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { [weak self] in
                await (self?.engine.sessionInfo) != nil
            },
            cancelGenerationHandler: { _ in
                // Beta: oversized generation is greedy and non-cancellable.
            },
            capabilitiesProvider: nil,
            baseConfigProvider: { ModelConfig() }
        )
        try await MainActor.run { try server.start() }
        httpServer = server
        state.withLock { $0.running = true }
    }

    public func stop() async {
        try? await engine.newSession()
        httpServer?.stop()
        httpServer = nil
        servedTranscript = []
        state.withLock {
            $0.running = false
            $0.generating = false
        }
    }

    public func checkHealth() async -> Bool {
        await (engine.sessionInfo != nil) || state.withLock { $0.loaded }
    }

    // MARK: - Generation (strict Execution State turn flow)

    public func handleGenerate(
        messages: [JSONValue],
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        generationLock.lock()
        defer { generationLock.unlock() }
        state.withLock { $0.generating = true }
        defer { state.withLock { $0.generating = false } }

        let incoming = Self.sanitized(messages)
        // Conversation continuation semantics: a transcript that extends the
        // served one consumes ONLY the new user turn (raw continuation over
        // the bound prefix); a divergent or fresh transcript discards the
        // session and re-bootstraps from the chat template.
        //
        // servedTranscript is a DERIVED control state (review P1/P2): it is
        // committed only AFTER the turn (physical rebind + logical advance)
        // has succeeded, so a failed generation cannot desynchronize the
        // continuation judgment from the actual Execution State.
        let isContinuation =
            incoming.count > servedTranscript.count
            && Array(incoming.prefix(servedTranscript.count)) == servedTranscript
        if !isContinuation {
            try await engine.newSession()
        }

        let started = ContinuousClock.now
        var firstChunkAt: ContinuousClock.Instant?
        let turn: OversizedEngineTurn
        if isContinuation {
            turn = try await engine.generate(
                messages: [incoming.last!],
                maxNewTokens: maxTokens,
                onToken: { _, text in
                    if firstChunkAt == nil { firstChunkAt = ContinuousClock.now }
                    onChunk(text)
                }
            )
        } else {
            turn = try await engine.generate(
                messages: incoming,
                maxNewTokens: maxTokens,
                onToken: { _, text in
                    if firstChunkAt == nil { firstChunkAt = ContinuousClock.now }
                    onChunk(text)
                }
            )
        }
        servedTranscript = incoming
        servedTranscript.append(EngineChatMessage(role: "assistant", content: turn.text))

        var ttftSeconds: TimeInterval?
        if let first = firstChunkAt {
            let d = started.duration(to: first)
            ttftSeconds = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        let usage = GenerationUsageReport(
            promptTokens: engine.lastInputTokenCount ?? 0,
            generationTokens: turn.tokenIDs.count,
            ttftSeconds: ttftSeconds,
            tokensPerSecond: turn.meanTokenMs > 0 ? 1000 / turn.meanTokenMs : nil
        )
        return GenerationResult(text: turn.text, usage: usage)
    }

    static func sanitized(_ messages: [JSONValue]) -> [EngineChatMessage] {
        var out: [EngineChatMessage] = []
        for message in messages {
            guard case .object(let obj) = message else { continue }
            guard case .string(let role) = obj["role"] else { continue }
            let content: String
            switch obj["content"] {
            case .string(let s): content = s
            case .array(let parts):
                content = parts.compactMap { part in
                    if case .object(let o) = part, case .string(let t) = o["text"] { return t }
                    if case .string(let s) = part { return s }
                    return nil
                }.joined()
            default: content = ""
            }
            guard role == "user" || role == "assistant" || role == "system" else { continue }
            out.append(EngineChatMessage(role: role, content: content))
        }
        return out
    }
}
