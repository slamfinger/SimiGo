import XCTest
@testable import SimiGoRuntimeContract

final class SimiGoEngineRecipeTests: XCTestCase {

    func testFloatingBranchIsNotLocked() {
        for bad in ["main", "master", "develop", "HEAD", "stable"] {
            let r = EngineRecipe(id: "x", displayName: "x", kind: .sourceBuild,
                                 upstreamURL: "https://example/x.git", pinnedRef: bad)
            XCTAssertFalse(r.isVersionLocked, "\(bad) must not count as locked")
        }
    }

    func testImmutableRefsAreLocked() {
        let commit = String(repeating: "a", count: 40)
        XCTAssertTrue(EngineRecipe(id: "c", displayName: "c", kind: .sourceBuild, pinnedRef: commit).isVersionLocked)
        XCTAssertTrue(EngineRecipe(id: "b", displayName: "b", kind: .sourceBuild, pinnedRef: "b4540").isVersionLocked)
        XCTAssertTrue(EngineRecipe(id: "v", displayName: "v", kind: .sourceBuild, pinnedRef: "v1.2.3").isVersionLocked)
    }

    func testAutomatedDownloadIsFailClosedWithoutChecksum() {
        let unlocked = EngineRecipe(id: "l", displayName: "l", kind: .sourceBuild, pinnedRef: "b4540")
        XCTAssertFalse(unlocked.allowsAutomatedDownload, "no checksum => refuse unattended fetch")

        let fake = EngineRecipe(id: "l", displayName: "l", kind: .sourceBuild,
                                pinnedRef: "b4540", expectedSourceSHA256: "not-a-hash")
        XCTAssertFalse(fake.allowsAutomatedDownload)

        let good = EngineRecipe(id: "l", displayName: "l", kind: .sourceBuild,
                                pinnedRef: "b4540",
                                expectedSourceSHA256: String(repeating: "0f", count: 32))
        XCTAssertTrue(good.allowsAutomatedDownload)
    }

    func testLockedCheckoutNeverPullsFloatingBranch() {
        let r = EngineRecipe(id: "llama.cpp", displayName: "llama", kind: .sourceBuild,
                             upstreamURL: "https://github.com/ggml-org/llama.cpp.git",
                             pinnedRef: "b4540")
        let cmds = r.lockedCheckoutCommands(git: "/usr/bin/git", targetDir: "/tmp/src")
        XCTAssertEqual(cmds.count, 3)
        XCTAssertTrue(cmds.allSatisfy { !$0.contains("pull") }, "no floating git pull allowed")
        XCTAssertTrue(cmds.contains { $0.contains("checkout") && $0.contains("--detach") && $0.contains("b4540") })
        // An unlocked recipe must yield no commands (fail-closed).
        XCTAssertTrue(EngineRecipe(id: "x", displayName: "x", kind: .sourceBuild,
                                   upstreamURL: "u", pinnedRef: "main")
                        .lockedCheckoutCommands(git: "git", targetDir: "t").isEmpty)
    }

    func testThreeDistinctStagesNeverCollapse() {
        let r = EngineRecipe(id: "llama.cpp", displayName: "llama", kind: .sourceBuild, pinnedRef: "b4540")
        // downloaded (source present, no binary)
        XCTAssertEqual(SimiGoEngineRegistry.resolveStage(recipe: r, sourcePresentAtPinnedRef: true,
                     binaryPresent: false, driverAdapted: false, healthChecked: false), .downloaded)
        // built (binary present, not adapted)
        XCTAssertEqual(SimiGoEngineRegistry.resolveStage(recipe: r, sourcePresentAtPinnedRef: true,
                     binaryPresent: true, driverAdapted: false, healthChecked: false), .built)
        // adapted (binary + driver + health)
        XCTAssertEqual(SimiGoEngineRegistry.resolveStage(recipe: r, sourcePresentAtPinnedRef: true,
                     binaryPresent: true, driverAdapted: true, healthChecked: true), .adapted)
        // ordering proves the three are distinct, monotone states
        XCTAssertLessThan(EngineStage.downloaded, EngineStage.built)
        XCTAssertLessThan(EngineStage.built, EngineStage.adapted)
    }

    func testRegistryIsNotHardcodedToLlama_ExternalServersSelectable() {
        let ids = Set(SimiGoEngineRegistry.bundledDefaults.map { $0.id })
        XCTAssertTrue(ids.contains("ollama"))
        XCTAssertTrue(ids.contains("lm-studio"))
        XCTAssertTrue(ids.contains("slang"))
        // external server stage: installed+health => adapted without any source build
        let ollama = SimiGoEngineRegistry.recipe(id: "ollama")!
        XCTAssertEqual(SimiGoEngineRegistry.resolveStage(recipe: ollama, sourcePresentAtPinnedRef: false,
                     binaryPresent: true, driverAdapted: true, healthChecked: true), .adapted)
    }

    func testManifestOverridesAndExtensibility() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-recipes-\(UUID().uuidString).json")
        let extra = EngineRecipe(id: "future-engine", displayName: "Future", kind: .externalServer)
        try JSONEncoder().encode([extra]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let all = SimiGoEngineRegistry.load(manifestURL: url)
        XCTAssertTrue(all.contains { $0.id == "future-engine" }, "new engine addable via manifest, no code change")
        XCTAssertTrue(all.contains { $0.id == "llama.cpp" }, "bundled defaults preserved")
    }

    func testCacheCleanupKeepsOnlyBinary() {
        let r = SimiGoEngineRegistry.recipe(id: "llama.cpp")!
        let toRemove = r.cachePathsToRemoveAfterBuild
        XCTAssertTrue(toRemove.contains("build"))
        XCTAssertTrue(toRemove.contains("sources"))
        XCTAssertFalse(toRemove.contains("bin"), "installed binary directory must be retained")
    }

    /// Enforce "构建完成后删除缓存只保留二进制" end-to-end on disk: after a build the
    /// produced binary is relocated under bin/<id>/ and the source/build/staging
    /// caches are removed. An incomplete build (no binary) prunes NOTHING.
    func testPruneCacheKeepingBinaryRunsAndIsFailSafe() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("simigo-engine-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func touch(_ rel: String, _ bytes: [UInt8] = [1,2,3]) throws {
            let u = root.appendingPathComponent(rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(bytes).write(to: u)
        }
        let r = SimiGoEngineRegistry.recipe(id: "llama.cpp")!   // producedBinaryRelPath = build/bin/llama-server

        // Fail-safe: caches exist but the binary was never produced -> nothing removed.
        try touch("sources/README")
        try touch("staging/draft")
        XCTAssertNil(try r.pruneCacheKeepingBinary(engineRoot: root, fm: fm))
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("sources").path), "incomplete build must NOT prune")

        // Completed build: binary appears -> relocate it, then drop caches.
        let fake = [UInt8](0x7f..<0x84).map { UInt8($0) }
        try touch(r.producedBinaryRelPath!, fake)
        let retained = try r.pruneCacheKeepingBinary(engineRoot: root, fm: fm)
        XCTAssertNotNil(retained)
        XCTAssertEqual(retained!.lastPathComponent, "llama-server")
        XCTAssertTrue(fm.fileExists(atPath: retained!.path), "the one binary must survive")
        XCTAssertEqual(try Data(contentsOf: retained!), Data(fake), "binary bytes preserved")
        for cache in r.cachePathsToRemoveAfterBuild {
            XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(cache).path), "\(cache) must be deleted")
        }
        // Old in-place binary path is gone (moved, not copied-and-left).
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(r.producedBinaryRelPath!).path))
    }

    // MARK: - requirement② adoption endpoints (external servers)

    /// Selecting an external server must resolve to a concrete OpenAI-compatible
    /// endpoint, so the picker actually drives the runtime rather than being inert.
    func testExternalServersResolveConcreteAdoptEndpoint() {
        let byID = Dictionary(uniqueKeysWithValues: SimiGoEngineRegistry.bundledDefaults.map { ($0.id, $0) })
        let ollama = SimiGoEngineRegistry.adoptedEndpoint(for: byID["ollama"]!)
        XCTAssertEqual(ollama?.baseURL, "http://127.0.0.1:11434/v1")
        XCTAssertNotNil(ollama?.defaultModel, "ollama ships a default served model")

        let lm = SimiGoEngineRegistry.adoptedEndpoint(for: byID["lm-studio"]!)
        XCTAssertEqual(lm?.baseURL, "http://127.0.0.1:1234/v1")
    }

    /// Source-build engines (llama.cpp) and the bundled native MLX runtime are NOT
    /// adopted over an endpoint — they must resolve to nil so a selection can never
    /// silently mis-route inference to a bogus local URL.
    func testSourceBuildAndNativeNeverAdoptOverEndpoint() {
        let byID = Dictionary(uniqueKeysWithValues: SimiGoEngineRegistry.bundledDefaults.map { ($0.id, $0) })
        XCTAssertNil(SimiGoEngineRegistry.adoptedEndpoint(for: byID["llama.cpp"]!),
                     "llama.cpp is source-built, never endpoint-adopted")
        XCTAssertNil(SimiGoEngineRegistry.adoptedEndpoint(for: byID["mlx-native"]!),
                     "native MLX is in-process, not an external endpoint")
    }

    /// Adoption is fail-closed: an external server with no declared endpoint
    /// (SGLang has no fixed local port) resolves to nil until an operator supplies one.
    func testExternalServerWithoutEndpointIsFailClosed() {
        let byID = Dictionary(uniqueKeysWithValues: SimiGoEngineRegistry.bundledDefaults.map { ($0.id, $0) })
        XCTAssertNil(SimiGoEngineRegistry.adoptedEndpoint(for: byID["slang"]!),
                     "SGLang has no default endpoint; must not invent one")
    }

    /// An operator manifest can supply the missing endpoint, which then adopts.
    func testManifestSuppliesAdoptEndpoint() throws {
        let json = """
        [{"id":"slang","displayName":"SGLang","kind":"externalServer",
          "endpointBaseURL":"http://127.0.0.1:30000/v1","defaultModel":"glm-4"}]
        """
        let decoded = try JSONDecoder().decode([EngineRecipe].self, from: Data(json.utf8))
        let slang = decoded.first { $0.id == "slang" }!
        let ep = SimiGoEngineRegistry.adoptedEndpoint(for: slang)
        XCTAssertEqual(ep?.baseURL, "http://127.0.0.1:30000/v1")
        XCTAssertEqual(ep?.defaultModel, "glm-4")
    }

    /// Backward compatibility: pre-existing manifests without the new optional
    /// keys still decode (endpoint absent => adoption fail-closed, not a crash).
    func testRecipeDecodesWithoutEndpointKeys() throws {
        let json = """
        [{"id":"ollama","displayName":"Ollama","kind":"externalServer",
          "serveCommand":["ollama","serve"]}]
        """
        let decoded = try JSONDecoder().decode([EngineRecipe].self, from: Data(json.utf8))
        XCTAssertNil(decoded.first?.endpointBaseURL)
        XCTAssertNil(SimiGoEngineRegistry.adoptedEndpoint(for: decoded.first!))
    }
}
