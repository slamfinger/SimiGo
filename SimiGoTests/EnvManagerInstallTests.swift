import XCTest
@testable import SimiGo

/// 安装器自检：`bin/llama-server` 是薄壳，真正干活的是它旁边那批
/// `libllama*.dylib`。只拷壳、再把 `build/` 剪掉，壳就死在 dyld 上（2026-11-10 实测：
/// 同名 49_984 字节的文件，`--version` 报 `Library not loaded:
/// @rpath/libllama-server-impl.dylib`）。这两件事因此各自需要一条测试：
///
/// 1. 动态库要跟着二进制一起落到 `bin/`；
/// 2. "文件在、权限在" 不等于 "能起来"，所以可以起不来的二进制不能被当成已安装。
final class EnvManagerInstallTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("envmanager-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - shared libraries travel with the binary

    @MainActor
    func testSharedLibrariesAreCopiedNextToTheBinary() throws {
        let buildBin = root.appendingPathComponent("build/bin", isDirectory: true)
        let installBin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: buildBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installBin, withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: buildBin.appendingPathComponent("llama-server"))
        try Data("impl".utf8).write(to: buildBin.appendingPathComponent("libllama-server-impl.dylib"))
        try Data("llama".utf8).write(to: buildBin.appendingPathComponent("libllama.0.dylib"))
        try Data("readme".utf8).write(to: buildBin.appendingPathComponent("README.md"))

        let copied = EnvManager.installSharedLibraries(
            from: buildBin.appendingPathComponent("llama-server").path,
            into: installBin.path)

        XCTAssertEqual(copied, ["libllama-server-impl.dylib", "libllama.0.dylib"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: installBin.appendingPathComponent("libllama-server-impl.dylib").path),
            "the library the shell loads must land in bin/, or pruning build/ kills it")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: installBin.appendingPathComponent("README.md").path),
            "only dylibs are installed beside the binary")
    }

    @MainActor
    func testStaleLibraryWithTheSameNameIsReplaced() throws {
        let buildBin = root.appendingPathComponent("build/bin", isDirectory: true)
        let installBin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: buildBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installBin, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: buildBin.appendingPathComponent("libllama.0.dylib"))
        try Data("old".utf8).write(to: installBin.appendingPathComponent("libllama.0.dylib"))

        EnvManager.installSharedLibraries(
            from: buildBin.appendingPathComponent("llama-server").path,
            into: installBin.path)

        let installed = try Data(contentsOf: installBin.appendingPathComponent("libllama.0.dylib"))
        XCTAssertEqual(String(decoding: installed, as: UTF8.self), "new",
                       "an upgrade must overwrite the previous build's library")
    }

    // MARK: - "can it start" is a question about running, not about the file

    @MainActor
    func testProbeAcceptsAZeroExitAndRejectsAFailure() throws {
        let ok = try script(named: "ok", body: "exit 0")
        let bad = try script(named: "bad", body: "exit 1")

        XCTAssertTrue(EnvManager.llamaServerRuns(ok.path))
        XCTAssertFalse(EnvManager.llamaServerRuns(bad.path))
    }

    @MainActor
    func testProbeRejectsMissingAndNonExecutableFiles() throws {
        let missing = root.appendingPathComponent("absent/llama-server")
        XCTAssertFalse(EnvManager.llamaServerRuns(missing.path))

        let plain = root.appendingPathComponent("llama-server")
        try Data("not executable".utf8).write(to: plain)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: plain.path)
        XCTAssertFalse(EnvManager.llamaServerRuns(plain.path),
                       "an executable bit is required before the probe even runs")
    }

    private func script(named name: String, body: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
