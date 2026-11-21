import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// Real-machine arm of the engine identity ledger. Split from
/// `EngineIdentityLedgerTests` so the model-free class can run under the P0/P1
/// gate (which requires skipped==0): this arm is gated on a real GGUF engine
/// and skipped whenever `SIMIGO_GGUF_E2E_MODEL` / `SIMIGO_GGUF_E2E_BIN` are
/// not injected.
///
/// Runs only with the isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class EngineIdentityLedgerRealMachineTests: XCTestCase {

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty, home.hasPrefix("/"),
            env["SIMIGO_STATE_GRAPH_STORE"]?.isEmpty == false,
            env["SIMIGO_CACHE_ROOT"]?.isEmpty == false
        else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                    + "so no real user state is touched")
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: EngineIdentityLedger.ledgerURL)
        super.tearDown()
    }

    private func readRows() throws -> [EngineIdentityLedger.Row] {
        let url = EngineIdentityLedger.ledgerURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(separator: "\n").filter { !$0.isEmpty }.map {
            try JSONDecoder().decode(
                EngineIdentityLedger.Row.self, from: Data($0.utf8))
        }
    }

    /// The ledger describes the binary that ACTUALLY launched. Gated on a real
    /// engine and real weights, like the other real-machine arms.
    @MainActor
    func testRealEngineLaunchWritesOneRowWhoseLibrarySetOutweighsTheEntry()
        async throws
    {
        let env = ProcessInfo.processInfo.environment
        guard let model = env["SIMIGO_GGUF_E2E_MODEL"],
            FileManager.default.fileExists(atPath: model)
        else {
            throw XCTSkip("SIMIGO_GGUF_E2E_MODEL not injected")
        }
        guard let binary = env["SIMIGO_GGUF_E2E_BIN"],
            FileManager.default.isExecutableFile(atPath: binary)
        else {
            throw XCTSkip("SIMIGO_GGUF_E2E_BIN not injected")
        }

        let before = try readRows().count

        var config = ModelConfig()
        config.ctxSize = 4096
        config.maxTokens = 128
        let backend = BackendConfig(
            name: "llama.cpp",
            customExecutable: binary,
            args: BackendConfig.llama.args,
            healthEndpoint: "/health",
            startupTimeout: 600,
            kind: .gguf)
        let runtime = ManagedGGUFRuntime(config: config, backendConfig: backend)
        let port = Int(try GGUFRestFixture.freePort())
        try await runtime.start(ModelInfo(path: model, kind: .gguf), port: port)
        addTeardownBlock { await runtime.stop() }

        let rows = try readRows()
        XCTAssertEqual(rows.count, before + 1, "one launch, one row")
        let row = try XCTUnwrap(rows.last)
        // 读数留档：`tearDown` 会删掉账本、隔离根随后也被清掉，所以把真机那一行的
        // 原文打进测试日志（evidence dir 的 log 会留下）。否则「真机那行长什么样」
        // 这句主张跑完即蒸发，只剩一个 passed，无从复核。
        let rawLast = try XCTUnwrap(
            try String(contentsOf: EngineIdentityLedger.ledgerURL, encoding: .utf8)
                .split(separator: "\n").filter { !$0.isEmpty }.last.map(String.init))
        print("ENGINE_LEDGER_ROW \(rawLast)")
        XCTAssertEqual(row.reason, "launch")
        XCTAssertEqual(
            row.resolver, "custom", "customExecutable is the first of the four levels")
        XCTAssertEqual(row.path, binary)
        XCTAssertNotNil(row.versionRaw, "the real engine answers --version")
        XCTAssertNotNil(row.launchArgsSha256)

        // 核心主张：入口不是引擎。49,984 B 的薄壳不可能自己承载 /slots 的实现，
        // 所以库里最大的那枚必须比入口大——否则账本记的还是启动器的身份。
        let entry = try XCTUnwrap(row.entry)
        XCTAssertFalse(row.libs.isEmpty, "a thin-shell engine must record its library set")
        let largest = try XCTUnwrap(row.libs.map(\.size).max())
        XCTAssertGreaterThan(
            largest, entry.size,
            "the engine's code lives in the libraries, not in the entry file")
    }
}