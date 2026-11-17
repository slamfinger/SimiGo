import Foundation
import LOCALBCore
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
nonisolated public final class OversizedRuntime: Runtime, @unchecked Sendable {
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
        var stopping = false
        var generating = false
        // Monotonic stop intents prevent a start that wins the lock race from
        // erasing a stop request made just before it acquired lifecycleLock.
        var stopGeneration: UInt64 = 0
        var completedStopGeneration: UInt64 = 0
    }

    private let modelDirectory: URL
    private let engine: OversizedSegmentedEngine
    private let state = Mutex(State())
    /// Serializes lifecycle transitions (load/start/stop) against one another.
    private let lifecycleLock = AsyncLock()
    /// Serializes generation and prevents engine reset while a turn is active.
    private let generationLock = AsyncLock()
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

    /// Protocol witness (Runtime). Defaults to the shared transport-policy
    /// decision with no caller-supplied LOCALB configuration.
    public func start(_ info: ModelInfo, port: Int) async throws {
        try await startWithLOCALB(
            info, port: port,
            localbTransportIdentity: nil,
            localbRequestAuthorization: nil
        )
    }

    /// Start with an EXPLICIT caller-supplied LOCALB configuration
    /// (test/management-plane injection). Never a fallback and never a
    /// default open rule: when both arguments are nil this is exactly the
    /// default-resolution path (operational LOCALB host → transport +
    /// authorization; otherwise transport-only fail-closed).
    public func startWithLOCALB(
        _ info: ModelInfo,
        port: Int,
        localbTransportIdentity: LOCALBTransportIdentityHandle?,
        localbRequestAuthorization: (coordinator: LOCALBPairingCoordinator,
                                     trustedCheckpoint: () throws -> LOCALBRegistryCheckpoint)?,
        localbHostDirectory: URL? = nil,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) async throws {
        // A start owns both lifecycle and engine access until its listener is
        // published. stop() marks admission closed before waiting for these
        // locks, so a stop requested during load cannot be overwritten.
        await lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        let startGeneration = state.withLock { state -> UInt64? in
            guard state.stopGeneration == state.completedStopGeneration else {
                return nil
            }
            state.loaded = false
            state.running = false
            state.stopping = false
            return state.stopGeneration
        }
        guard let startGeneration else { throw RuntError.notLoaded }

        await generationLock.lock()
        defer { generationLock.unlock() }
        guard state.withLock({
            !$0.stopping
                && $0.stopGeneration == startGeneration
                && $0.completedStopGeneration == startGeneration
        }) else {
            throw RuntError.notLoaded
        }
        // A repeated start replaces the listener owned by this runtime rather
        // than trying to bind a second listener to the same port.
        httpServer?.stop()
        httpServer = nil
        _ = try await engine.load()

        // Same IS producer identity as the contiguous-model path: a pure
        // re-derivation from the snapshot, so an oversized turn settles under
        // the model revision that actually produced it.
        let informationSeeds = ProducerIdentity.identities(
            fromPath: modelDirectory.path)
        let informationProducer = InformationTurnProducer(
            modelIdentity: informationSeeds.model,
            identity: informationSeeds.producer)

        let server = HTTPServer(
            port: port,
            modelId: modelDirectory.lastPathComponent
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/"),
            generateHandler: { [weak self] requestId, _, _, _, messages, _, config, onChunk, _, _ in
                guard let self else { throw RuntError.notLoaded }
                return try await self.handleGenerate(
                    messages: messages, maxTokens: config.maxTokens, onChunk: onChunk
                )
            },
            forkBranchHandler: { _, _, _, _ in
                throw RuntError.notLoaded
            },
            deleteBranchHandler: { _, _, _, _ in
                // Beta: branching is a no-op for the oversized path — the
                // S3-A contract turns that into an explicit failure, never
                // a silent ok.
                throw RuntError.generationFailed("oversized 路径不提供分支生命周期")
            },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { [weak self] in
                (self?.engine.sessionInfo) != nil
            },
            cancelGenerationHandler: { _ in
                // Beta: oversized generation is greedy and non-cancellable.
            },
            capabilitiesProvider: nil,
            baseConfigProvider: { ModelConfig() },
            informationTurnProducer: { informationProducer }
        )
        // LOCALB B1: one shared transport-policy decision for every listener
        // site. Secure by default; LAN binds can never fall back to
        // plaintext; legacy plaintext only via explicit loopback opt-in
        // (SIMIGO_TRANSPORT=legacy-http). Fail-closed decisions surface as
        // typed start() errors.
        if let localbTransportIdentity {
            // Explicit caller-supplied configuration (test/management-plane
            // injection): a fully verified transport identity plus,
            // optionally, the LOCALB request-authorization host. This is an
            // explicit configuration — never a fallback and never a default
            // open rule; the policy path below stays the default.
            server.configureLOCALBTransport(identity: localbTransportIdentity)
            if let localbRequestAuthorization {
                server.configureLOCALBRequestAuthorization(
                    coordinator: localbRequestAuthorization.coordinator,
                    trustedCheckpoint: localbRequestAuthorization
                        .trustedCheckpoint
                )
            }
        } else {
            // Default resolution: an activated LOCALB host supplies BOTH
            // the transport identity and request authorization from one
            // verified context; before activation this stays
            // transport-only and protected routes remain fail-closed.
            try LOCALBHostRuntime.applyDefault(
                to: server,
                bindHost: "127.0.0.1",
                hostDirectory: localbHostDirectory,
                keychainStore: keychainStore,
                transportIdentityStore: transportIdentityStore
            )
        }
        guard !state.withLock({ $0.stopping }) else {
            throw RuntError.notLoaded
        }
        try await MainActor.run { try server.start() }
        let published = state.withLock { state -> Bool in
            guard !state.stopping,
                  state.stopGeneration == startGeneration,
                  state.completedStopGeneration == startGeneration else {
                return false
            }
            state.loaded = true
            state.running = true
            return true
        }
        guard published else {
            server.stop()
            try? await engine.newSession()
            throw RuntError.notLoaded
        }
        httpServer = server
    }

    public func stop() async {
        // Close admission synchronously, then serialize against start/load.
        // startWithLOCALB uses the same lock order (lifecycle -> generation).
        let stopGeneration = state.withLock { state -> UInt64 in
            state.stopGeneration &+= 1
            state.stopping = true
            state.running = false
            return state.stopGeneration
        }
        await lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        await generationLock.lock()
        defer { generationLock.unlock() }
        httpServer?.stop()
        httpServer = nil
        try? await engine.newSession()
        servedTranscript = []
        state.withLock {
            $0.generating = false
            $0.loaded = false
            $0.completedStopGeneration = max(
                $0.completedStopGeneration, stopGeneration)
            $0.stopping = $0.stopGeneration != $0.completedStopGeneration
        }
    }

    public func checkHealth() async -> Bool {
        state.withLock { $0.running && !$0.stopping && $0.loaded }
    }

    // MARK: - Generation (strict Execution State turn flow)

    public func handleGenerate(
        messages: [JSONValue],
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        guard state.withLock({ $0.running && !$0.stopping }) else {
            throw RuntError.notLoaded
        }
        await generationLock.lock()
        defer { generationLock.unlock() }
        // stop() may have closed admission while this request waited.
        guard state.withLock({ $0.running && !$0.stopping }) else {
            throw RuntError.notLoaded
        }
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
        let firstChunkAt = Mutex<ContinuousClock.Instant?>(nil)
        let turn: OversizedEngineTurn
        if isContinuation {
            turn = try await engine.generate(
                messages: [incoming.last!],
                maxNewTokens: maxTokens,
                onToken: { _, text in
                    if firstChunkAt.withLock({ $0 }) == nil {
                        firstChunkAt.withLock { $0 = ContinuousClock.now }
                    }
                    onChunk(text)
                }
            )
        } else {
            turn = try await engine.generate(
                messages: incoming,
                maxNewTokens: maxTokens,
                onToken: { _, text in
                    if firstChunkAt.withLock({ $0 }) == nil {
                        firstChunkAt.withLock { $0 = ContinuousClock.now }
                    }
                    onChunk(text)
                }
            )
        }
        servedTranscript = incoming
        servedTranscript.append(EngineChatMessage(role: "assistant", content: turn.text))

        var ttftSeconds: TimeInterval?
        if let first = firstChunkAt.withLock({ $0 }) {
            let d = started.duration(to: first)
            ttftSeconds = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        let usage = GenerationUsageReport(
            promptTokens: engine.lastInputTokenCount ?? 0,
            generationTokens: turn.tokenIDs.count,
            ttftSeconds: ttftSeconds,
            tokensPerSecond: turn.meanTokenMs > 0 ? 1000 / turn.meanTokenMs : nil
        )
        return GenerationResult(
            text: turn.text, usage: usage,
            // The segmented engine runs the whole budget with no stop set and
            // reports no termination reason, so it cannot attest that the
            // answer finished: T-1 makes that an explicit `unconfirmed` rather
            // than an inherited "stop".
            completion: .unconfirmed)
    }

    static func sanitized(_ messages: [JSONValue]) -> [EngineChatMessage] {
        var out: [EngineChatMessage] = []
        for message in messages {
            guard case .object(let obj) = message else { continue }
            guard case .string(let role) = obj["role"] else { continue }
            let content = obj["content"]?.messageText ?? ""
            guard role == "user" || role == "assistant" || role == "system" else { continue }
            out.append(EngineChatMessage(role: role, content: content))
        }
        return out
    }
}
