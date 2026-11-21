import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// Engine identity ledger: what a reading is able to attribute itself to.
/// Spec: `ES-IS-research/docs/research/ENGINE_IDENTITY_LEDGER_SPEC_V0.1_20261116.md`
/// (anomaly A-13 — the commit → build → digest chain had no file-level link).
///
/// The model-free arms run in CI with only the three isolated roots. The last arm
/// is gated on a real engine, because "the ledger describes the binary that
/// actually launched" is not a claim a stand-in can prove.
///
/// Runs only with the isolated roots injected (`SIMIGO_HOME`, `SIMIGO_CACHE_ROOT`,
/// `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class EngineIdentityLedgerTests: XCTestCase {

    private var isolationRoot: URL!
    private var fixtureDirs: [URL] = []

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
        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
    }

    override func tearDown() {
        for dir in fixtureDirs { try? FileManager.default.removeItem(at: dir) }
        fixtureDirs.removeAll()
        try? FileManager.default.removeItem(at: EngineIdentityLedger.ledgerURL)
        super.tearDown()
    }

    // MARK: - Fixture

    /// A stand-in "engine" with the shape `installSharedLibraries` leaves behind:
    /// an executable that answers `--version`, two real dylibs, and one
    /// `libX.dylib -> libX.0.dylib` alias.
    ///
    /// - Parameter counterFile: when set, the stand-in appends one line per
    ///   invocation, so an arm can COUNT how many times the engine was probed
    ///   (spec §3.1: the install path must not spawn `--version` twice).
    private func makeFakeEngine(
        name: String, versionLine: String, payload: String, counterFile: URL? = nil
    ) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "EngineLedger-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        fixtureDirs.append(dir)

        let bin = dir.appendingPathComponent("llama-server")
        let countLine = counterFile.map { "echo x >> \"\($0.path)\"\n" } ?? ""
        // The payload goes INTO the entry script, not only beside it. Two builds
        // that differ must differ in the binary itself — an earlier version of
        // this fixture varied only the dylibs, so two "different" engines had
        // byte-identical entries and the discriminating arm proved nothing.
        try Data("#!/bin/sh\n# \(payload)\n\(countLine)echo \"\(versionLine)\"\n".utf8)
            .write(to: bin)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: bin.path)

        try Data(payload.utf8).write(to: dir.appendingPathComponent("libimpl.0.dylib"))
        try Data((payload + "-second").utf8)
            .write(to: dir.appendingPathComponent("libggml.0.dylib"))
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("libimpl.dylib"),
            withDestinationURL: dir.appendingPathComponent("libimpl.0.dylib"))
        return bin.path
    }

    private func readRows() throws -> [EngineIdentityLedger.Row] {
        guard let text = try? String(
            contentsOf: EngineIdentityLedger.ledgerURL, encoding: .utf8)
        else { return [] }
        return try text.split(separator: "\n").filter { !$0.isEmpty }.map {
            try JSONDecoder().decode(
                EngineIdentityLedger.Row.self, from: Data($0.utf8))
        }
    }

    // MARK: - Arms

    /// One launch event writes one row, and every field in it is either
    /// recomputable or verbatim: the entry digest can be re-derived from the
    /// file, the library set is the real files beside it (aliases excluded), and
    /// the self-report is parsed rather than trusted.
    func testLaunchRowRecordsEntryLibrariesAndSelfReport() throws {
        let bin = try makeFakeEngine(
            name: "launch",
            versionLine: "version: 9.9.9-dev (build 42, commit abc1234)",
            payload: "impl-bytes")

        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.launch,
            executablePath: bin,
            resolver: "custom",
            launchArgs: ["--port", "8080", "--cache-type-k", "q4_0"])

        let url = EngineIdentityLedger.ledgerURL
        XCTAssertTrue(
            url.path.hasPrefix(isolationRoot.path),
            "the ledger must land in the injected SIMIGO_HOME, never the real one")

        let rows = try readRows()
        XCTAssertEqual(rows.count, 1, "one event, one row")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.reason, "launch")
        XCTAssertEqual(row.resolver, "custom")
        XCTAssertEqual(row.path, bin)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: row.realpath),
            "realpath must resolve to a real file")
        XCTAssertEqual(row.versionRaw, "version: 9.9.9-dev (build 42, commit abc1234)")
        XCTAssertEqual(row.version?.version, "9.9.9-dev")
        XCTAssertEqual(row.version?.build, "42")
        XCTAssertEqual(row.version?.commit, "abc1234")
        XCTAssertNil(row.pinnedRef, "a launch row carries no pin unless one was supplied")
        XCTAssertNotNil(row.launchArgsSha256)

        // 入口摘要可独立复算，不是账本自说自话。
        let entry = try XCTUnwrap(row.entry)
        XCTAssertEqual(
            entry.sha256,
            try NativeMLX.sha256HexOfFile(at: URL(fileURLWithPath: row.realpath)))
        // size 与 mtime 同样可独立复算：账本写的就是文件系统上的值，不是自说自话。
        let attrsOnDisk = try FileManager.default.attributesOfItem(atPath: row.realpath)
        XCTAssertEqual(
            entry.size, attrsOnDisk[.size] as? Int, "entry size is the file's size")
        let modifiedOnDisk = try XCTUnwrap(attrsOnDisk[.modificationDate] as? Date)
        XCTAssertEqual(entry.mtime, EngineIdentityLedger.timestamp(modifiedOnDisk))

        // 库集合：两枚真文件，按名排序；symlink 别名不重复计。
        XCTAssertEqual(row.libs.map(\.name), ["libggml.0.dylib", "libimpl.0.dylib"])
        XCTAssertNotEqual(
            row.libs.first?.sha256, row.libs.last?.sha256,
            "different bytes must produce different digests")
        XCTAssertTrue(
            row.libs.allSatisfy { $0.mtime == nil },
            "library rows keep the {name, size, sha256} shape the spec names (spec §2)")
    }

    /// The point of the ledger: two binaries with an IDENTICAL self-report are
    /// still told apart. `--version` alone cannot carry identity.
    func testLedgerDiscriminatesTwoBinariesWithTheSameSelfReport() throws {
        let same = "version: 1.0.0-dev (build 1, commit aaa1111)"
        let a = try makeFakeEngine(name: "a", versionLine: same, payload: "AAA")
        let b = try makeFakeEngine(name: "b", versionLine: same, payload: "BBB")

        // spec §5.2：指向另一枚二进制 → entry.sha256 与 resolver 都变。
        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.launch, executablePath: a, resolver: "custom")
        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.launch, executablePath: b, resolver: "system")

        let rows = try readRows()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(
            rows[0].versionRaw, rows[1].versionRaw,
            "the self-report is identical, which is exactly why it is not the key")
        XCTAssertNotEqual(
            rows[0].entry?.sha256, rows[1].entry?.sha256,
            "different bytes must produce different entry digests")
        XCTAssertNotEqual(
            rows[0].resolver, rows[1].resolver, "spec §5.2: the fallback level changes too")
        XCTAssertNotEqual(
            rows[0].libs.map(\.sha256), rows[1].libs.map(\.sha256),
            "and so does the library set beside it")
    }

    /// The install row is where commit → build → digest closes: it is the only
    /// event that holds the pin and the freshly landed artifacts together.
    func testInstallVerifyRowCarriesThePinnedRefAndIsReadableFromEnv() throws {
        let bin = try makeFakeEngine(
            name: "install", versionLine: "version: 2.0.0-dev (build 7, commit bbb2222)",
            payload: "installed")
        let pin = "0878f7c304cc13915c831ae17694534c94940176"

        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.installVerify,
            executablePath: bin, pinnedRef: pin)

        let row = try XCTUnwrap(try readRows().first)
        XCTAssertEqual(row.reason, "install-verify")
        XCTAssertEqual(row.pinnedRef, pin, "the pin is recorded verbatim")
        XCTAssertNil(row.launchArgsSha256, "an install event has no launch args")
        XCTAssertNil(
            row.resolver,
            "install does not go through the four fallback levels, so it names none (spec §2)")

        // 可见性挂在既有 env 载荷上，不新开路由。
        let latest = try XCTUnwrap(EngineIdentityLedger.latestRow())
        XCTAssertEqual(latest["reason"] as? String, "install-verify")
        XCTAssertEqual(latest["pinned_ref"] as? String, pin)
        XCTAssertEqual(
            (latest["entry"] as? [String: Any])?["sha256"] as? String, row.entry?.sha256)
    }

    /// Absence is recorded as absence. A binary that does not answer `--version`
    /// yields no self-report and no parsed triple — never a value guessed from a
    /// path or a filename. A missing file still produces a row (the ledger must
    /// not become a new failure mode).
    func testMissingSelfReportIsNeverGuessed() throws {
        let silent = try makeFakeEngine(name: "silent", versionLine: "", payload: "quiet")
        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.probe, executablePath: silent)

        let missing = "/nonexistent/llama-server-\(UUID().uuidString)"
        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.probe, executablePath: missing)

        let rows = try readRows()
        XCTAssertEqual(rows.count, 2, "recording never throws away the event")

        XCTAssertNil(rows[0].versionRaw)
        XCTAssertNil(rows[0].version)
        XCTAssertFalse(rows[0].libs.isEmpty, "the libraries are still measurable")

        XCTAssertEqual(rows[1].path, missing)
        XCTAssertNil(rows[1].entry, "a file that is not there has no digest")
        XCTAssertTrue(rows[1].libs.isEmpty)
        XCTAssertNil(rows[1].versionRaw)

        // 解析器同样不猜：没有 version/build/commit 字样就是 nil。
        XCTAssertNil(EngineIdentityLedger.parseVersion("no self-report here"))
        let partial = try XCTUnwrap(EngineIdentityLedger.parseVersion("commit deadbeef only"))
        XCTAssertNil(partial.version)
        XCTAssertNil(partial.build)
        XCTAssertEqual(partial.commit, "deadbeef")
    }

    /// Appends accumulate: a second event may not rewrite the first row. The
    /// previous seekToEnd+write path fell back to an overwriting write when the
    /// file handle failed to open, which could erase the recorded history.
    func testAppendKeepsEarlierRowsOnDisk() throws {
        let a = try makeFakeEngine(name: "keep-a", versionLine: "version: 1.0.0", payload: "A")
        let b = try makeFakeEngine(name: "keep-b", versionLine: "version: 1.0.0", payload: "B")
        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.launch, executablePath: a, resolver: "custom")
        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.launch, executablePath: b, resolver: "custom")

        let rows = try readRows()
        XCTAssertEqual(rows.count, 2, "two events, two rows — nothing overwritten")
        XCTAssertEqual(rows.first?.path, a)
        XCTAssertEqual(rows.last?.path, b)
    }

    /// A crash between "wrote half a line" and "wrote the newline" leaves a
    /// torn trailing row. The reader must fall back to the newest complete row
    /// instead of reporting that nothing was ever recorded.
    func testLatestRowFallsBackPastATornTrailingLine() throws {
        let bin = try makeFakeEngine(
            name: "torn", versionLine: "version: 1.0.0", payload: "T")
        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.launch, executablePath: bin, resolver: "custom")

        let url = EngineIdentityLedger.ledgerURL
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"truncated\":".utf8))
        try handle.close()

        let row = try XCTUnwrap(
            EngineIdentityLedger.latestRow(),
            "a torn tail must not erase the history behind it")
        XCTAssertEqual(row["reason"] as? String, "launch")
        XCTAssertEqual(try readRows().count, 1)
    }

    /// Spec §3.1 reduced to one number: an install asks the engine what it is
    /// EXACTLY ONCE. `llamaServerRuns` already spawned `--version` to decide
    /// whether the install starts, and used to throw that output into
    /// `nullDevice`; the ledger now takes the same output instead of re-probing.
    @MainActor
    func testInstallVerifyProbesTheEngineExactlyOnce() throws {
        let counter = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineLedger-probes-\(UUID().uuidString).txt")
        fixtureDirs.append(counter)
        try Data("".utf8).write(to: counter)
        let report = "version: 3.0.0-dev (build 9, commit ccc3333)"
        let bin = try makeFakeEngine(
            name: "counted", versionLine: report, payload: "counted",
            counterFile: counter)

        let probe = EnvManager.probeLlamaServerVersion(bin)
        XCTAssertTrue(probe.ran, "exit 0 ⇒ the install check would pass")
        XCTAssertEqual(probe.text, report)

        EngineIdentityLedger.record(
            reason: EngineIdentityLedger.Reason.installVerify,
            executablePath: bin,
            pinnedRef: "0878f7c304cc13915c831ae17694534c94940176",
            selfReport: .probed(probe.text))

        let probes = try XCTUnwrap(String(contentsOf: counter, encoding: .utf8))
            .split(separator: "\n").filter { !$0.isEmpty }.count
        XCTAssertEqual(probes, 1, "one install, one `--version` — not two")

        let row = try XCTUnwrap(try readRows().first)
        XCTAssertEqual(
            row.versionRaw, probe.text, "the ledger carries the caller's probe verbatim")
    }

    /// Spec §5.2's resolver half, plus §7.2's "judge from measurement, not from a
    /// guess": the four fallback levels are named, and `executable` keeps the exact
    /// meaning it had before the ledger existed.
    @MainActor
    func testExecutableResolutionNamesTheFallbackLevelThatProducedIt() throws {
        let bin = try makeFakeEngine(
            name: "resolver", versionLine: "version: 1.2.3-dev (build 5, commit ddd4444)",
            payload: "resolver")

        // 第一级：customExecutable 非空 → "custom"。
        let custom = BackendConfig(
            name: "llama.cpp", customExecutable: bin, args: BackendConfig.llama.args,
            healthEndpoint: "/health", startupTimeout: 60, kind: .gguf)
        XCTAssertEqual(custom.executableResolution.resolver, "custom")
        XCTAssertEqual(custom.executableResolution.path, bin)
        XCTAssertEqual(custom.executable, bin, "`executable` must keep its old meaning")

        // 非 GGUF：没有引擎可解析，path 为空 ⇒ ProcessRuntime 不写账本行。
        let mlx = BackendConfig(
            name: "mlx", args: BackendConfig.llama.args,
            healthEndpoint: "/health", startupTimeout: 60, kind: .mlx)
        XCTAssertEqual(mlx.executableResolution.path, "")
        XCTAssertEqual(mlx.executable, "")

        // 第二~四级取决于这台机器上的实际状态（spec §7.2），所以只断言取值在枚举内。
        // 断言「一定落到某一级」就是把没测的事写成结论。
        let fallback = BackendConfig(
            name: "llama.cpp", args: BackendConfig.llama.args,
            healthEndpoint: "/health", startupTimeout: 60, kind: .gguf)
        XCTAssertTrue(
            ["app-config", "system", "default"].contains(fallback.executableResolution.resolver),
            "resolver must be one of the spec's four levels, got \(fallback.executableResolution.resolver)")
        XCTAssertFalse(
            fallback.executableResolution.path.isEmpty,
            "the last level is a constant path, so resolution never comes up empty")
        XCTAssertEqual(
            fallback.executable, fallback.executableResolution.path,
            "two views of one value cannot drift apart")
    }
}
