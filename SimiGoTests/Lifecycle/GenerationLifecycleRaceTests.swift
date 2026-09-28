import XCTest
import Foundation
@testable import SimiGo

actor SequenceWitness {
    private var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

/// BETA-AUDIT-3 regression battery: generation owns the same lifecycle gate
/// as save/load/delete, so a lifecycle operation can neither commit nor run
/// physical cleanup until the long generation releases it.
final class GenerationLifecycleRaceTests: XCTestCase {
    private static let defaultModelPath =
        "/Users/mr.simi/.cache/huggingface/hub/models--peculiar-ragdoll--Nail-Qwen3.6-35B-A3B-MLX"
        + "/snapshots/31a0106483c94e9fbb0a6d3360ff122d47377058"

    private static let systemContent =
        "You are a precise assistant. Follow instructions exactly. " +
        "Answer in English without extra words."

    private static let systemMsg = JSONValue.object([
        "role": .string("system"),
        "content": .string(systemContent),
    ])

    private static func user(_ text: String) -> JSONValue {
        .object(["role": .string("user"), "content": .string(text)])
    }

    private static func assistant(_ text: String) -> JSONValue {
        .object(["role": .string("assistant"), "content": .string(text)])
    }

    private static func requireModel() throws -> String {
        let path = ProcessInfo.processInfo.environment["SIMIGO_FORK_MODEL"]
            ?? defaultModelPath
        guard FileManager.default.fileExists(atPath: path + "/config.json") else {
            throw XCTSkip("GenerationLifecycleRaceTests：本机不存在测试权重")
        }
        return path
    }

    private static func config() -> ModelConfig {
        var cfg = ModelConfig()
        cfg.temperature = 0
        cfg.maxTokens = 24
        cfg.disableThinking = true
        cfg.useMTP = false
        return cfg
    }

    private static func longConfig() -> ModelConfig {
        var cfg = Self.config()
        cfg.maxTokens = 128
        return cfg
    }

    private static func baseMessages() -> [JSONValue] {
        [systemMsg, user("Archive: ready. Reply with exactly: OK")]
    }

    private static func longMessages() -> [JSONValue] {
        [systemMsg, user("Count from 1 to 30, one number per line.")]
    }

    private static func makeRuntime(
        modelPath: String, port: Int, config: ModelConfig
    ) async throws -> NativeMLX {
        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(info: info, config: config)
        try await runtime.start(info, port: port)
        return runtime
    }

    private static func makeGenerate(
        _ runtime: NativeMLX, tag: String, config: ModelConfig,
        witness: SequenceWitness? = nil
    ) -> ([JSONValue]) async throws -> GenerationResult {
        { messages in
            let requestId = "b3-\(tag)-\(UUID().uuidString.prefix(8).lowercased())"
            await RuntimeLifecycleCoordinator.shared.register(
                requestID: requestId, sessionID: "race")
            let result = try await runtime.generate(
                requestId: requestId,
                agentId: nil,
                sessionId: "race",
                logicalBranchId: "main",
                messages: messages,
                tools: nil,
                config: config
            ) { _ in }
            await witness?.record("generationEnded")
            return result
        }
    }

    private static func metadata(
        for cacheURL: URL
    ) throws -> SessionCacheMetadata {
        let metaURL = cacheURL.deletingLastPathComponent().appendingPathComponent(
            cacheURL.deletingPathExtension().appendingPathExtension("meta.json")
                .lastPathComponent)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionCacheMetadata.self, from: Data(contentsOf: metaURL))
    }

    func testGenerationGateBlocksSaveUntilGenerationCompletes() async throws {
        let modelPath = try Self.requireModel()
        let runtime = try await Self.makeRuntime(
            modelPath: modelPath, port: 18790, config: Self.longConfig())
        defer { Task { await runtime.stop() } }

        let witness = SequenceWitness()
        let baseGen = Self.makeGenerate(runtime, tag: "save-base", config: Self.longConfig())
        let longGen = Self.makeGenerate(runtime, tag: "save-long", config: Self.longConfig(), witness: witness)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b3-save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        _ = try await baseGen(Self.baseMessages())

        let genTask = Task { try await longGen(Self.longMessages()) }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        await witness.record("saveStarted")
        let saveTask = Task {
            let url = try await runtime.saveSessionCache(
                sessionId: "race", logicalBranchId: "main", to: dir)
            await witness.record("saveEnded")
            return url
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let duringGeneration = await witness.snapshot()
        XCTAssertFalse(
            duringGeneration.contains("saveEnded"),
            "save cannot complete while generation owns the gate")
        XCTAssertEqual(duringGeneration.last, "saveStarted")

        let generation = try await genTask.value
        let cacheURL = try await saveTask.value
        let order = await witness.snapshot()
        XCTAssertEqual(
            try order.map {
                if $0 == "generationEnded" { return 1 }
                if $0 == "saveEnded" { return 2 }
                return 0
            }.filter { $0 > 0 },
            [1, 2],
            "save must be released only after generation")

        let saved = try Self.metadata(for: cacheURL)
        XCTAssertEqual(
            saved.cacheSHA256, try NativeMLX.sha256HexOfFile(at: cacheURL))
        XCTAssertFalse(generation.text.isEmpty)
    }

    func testGenerationGateBlocksLoadCommitUntilGenerationCompletes() async throws {
        let modelPath = try Self.requireModel()
        let runtime = try await Self.makeRuntime(
            modelPath: modelPath, port: 18791, config: Self.longConfig())
        defer { Task { await runtime.stop() } }

        let witness = SequenceWitness()
        let baseGen = Self.makeGenerate(runtime, tag: "load-base", config: Self.longConfig())
        let longGen = Self.makeGenerate(runtime, tag: "load-long", config: Self.longConfig(), witness: witness)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b3-load-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        _ = try await baseGen(Self.baseMessages())
        let checkpoint = try await runtime.saveSessionCache(
            sessionId: "race", logicalBranchId: "main", to: dir)
        let key = try AgentExecutionKey(
            agentId: nil, sessionId: "race", logicalBranchId: "main")
        let identityBefore = runtime.integrationActiveSessionIdentity(
            sessionId: "race", logicalBranchId: "main")
        XCTAssertNotNil(identityBefore)

        let genTask = Task { try await longGen(Self.longMessages()) }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        await witness.record("loadStarted")
        let loadTask = Task {
            let loaded = try await runtime.loadSessionCache(
                sessionId: "race", logicalBranchId: "main", from: dir)
            await witness.record("loadEnded")
            return loaded
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let duringGeneration = await witness.snapshot()
        XCTAssertFalse(
            duringGeneration.contains("loadEnded"),
            "load cannot commit while generation owns the gate")
        XCTAssertEqual(duringGeneration.last, "loadStarted")

        _ = try await genTask.value
        let restored = try await loadTask.value
        XCTAssertEqual(restored.storageKey, key.storageKey)
        let order = await witness.snapshot()
        XCTAssertEqual(
            try order.map {
                if $0 == "generationEnded" { return 1 }
                if $0 == "loadEnded" { return 2 }
                return 0
            }.filter { $0 > 0 },
            [1, 2],
            "load commit must be released only after generation")

        let identityAfter = runtime.integrationActiveSessionIdentity(
            sessionId: "race", logicalBranchId: "main")
        XCTAssertNotEqual(
            identityAfter, identityBefore,
            "active execution must be the restored ManagedSession, not old A")
        XCTAssertTrue(
            runtime.listSessionBranches(sessionId: "race").liveBranches.contains("main"))
    }

    func testGenerationGateBlocksDeleteLifecycleUntilGenerationCompletes() async throws {
        let modelPath = try Self.requireModel()
        let runtime = try await Self.makeRuntime(
            modelPath: modelPath, port: 18792, config: Self.longConfig())
        defer { Task { await runtime.stop() } }

        let witness = SequenceWitness()
        let baseGen = Self.makeGenerate(runtime, tag: "delete-base", config: Self.longConfig())
        let longGen = Self.makeGenerate(runtime, tag: "delete-long", config: Self.longConfig(), witness: witness)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b3-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        _ = try await baseGen(Self.baseMessages())
        let cacheURL = try await runtime.saveSessionCache(
            sessionId: "race", logicalBranchId: "main", to: dir)
        let key = try AgentExecutionKey(
            agentId: nil, sessionId: "race", logicalBranchId: "main")
        XCTAssertNotNil(runtime.integrationActiveSessionIdentity(
            sessionId: "race", logicalBranchId: "main"))
        XCTAssertNotNil(NativeMLXPrefixPool.shared.bindings.currentBinding(
            executionID: key.storageKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        let genTask = Task { try await longGen(Self.longMessages()) }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        await witness.record("deleteStarted")
        let deleteTask = Task {
            try await runtime.deleteSessionBranch(
                sessionId: "race", logicalBranchId: "main", in: dir)
            await witness.record("deleteEnded")
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let duringGeneration = await witness.snapshot()
        XCTAssertFalse(
            duringGeneration.contains("deleteEnded"),
            "delete cannot begin physical cleanup while generation owns the gate")
        XCTAssertEqual(duringGeneration.last, "deleteStarted")

        _ = try await genTask.value
        try await deleteTask.value
        let order = await witness.snapshot()
        XCTAssertEqual(
            try order.map {
                if $0 == "generationEnded" { return 1 }
                if $0 == "deleteEnded" { return 2 }
                return 0
            }.filter { $0 > 0 },
            [1, 2],
            "delete lifecycle must be released only after generation")

        XCTAssertNil(runtime.integrationActiveSessionIdentity(
            sessionId: "race", logicalBranchId: "main"))
        XCTAssertNil(NativeMLXPrefixPool.shared.bindings.currentBinding(
            executionID: key.storageKey))
        let prefix = NativeMLX.cacheFileName(for: key.storageKey)
        let residue = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix(prefix) }
        XCTAssertTrue(residue.isEmpty, "checkpoint cleanup must be complete: \(residue)")
    }
}
