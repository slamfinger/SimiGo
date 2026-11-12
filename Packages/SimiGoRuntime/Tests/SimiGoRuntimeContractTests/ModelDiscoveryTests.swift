import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// Covers the portable model-reference layer (item B): the durable identity is
/// (root_id + relative_path) and the absolute locator is only ever resolved from
/// the external Hugging Face cache at runtime — never stored, never copied.
final class ModelDiscoveryTests: XCTestCase {

    private func makeHub() throws -> (hub: URL, modelURL: URL, rel: String, env: [String: String]) {
        let hub = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfhub-\(UUID().uuidString)", isDirectory: true)
        let rev = hub.appendingPathComponent("models--Foo--Bar/snapshots/rev1", isDirectory: true)
        try FileManager.default.createDirectory(at: rev, withIntermediateDirectories: true)
        let modelURL = rev.appendingPathComponent("model.gguf")
        try Data("weights".utf8).write(to: modelURL)
        let rel = "models--Foo--Bar/snapshots/rev1/model.gguf"
        return (hub, modelURL, rel, ["HF_HUB_CACHE": hub.path])
    }

    private func teardown(_ hub: URL) { try? FileManager.default.removeItem(at: hub) }

    func testResolveFindsModelUnderExternalCache() throws {
        let (hub, _, rel, env) = try makeHub()
        defer { teardown(hub) }
        let url = ModelDiscovery.resolve(
            ModelReference(rootID: ModelDiscovery.cacheRootID, relativePath: rel), env: env)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.path, hub.appendingPathComponent(rel).standardizedFileURL.path)
    }

    func testResolveFailsClosedWhenAbsent() throws {
        let (hub, _, _, env) = try makeHub()
        defer { teardown(hub) }
        let url = ModelDiscovery.resolve(
            ModelReference(rootID: ModelDiscovery.cacheRootID,
                           relativePath: "models--Missing--Repo/snapshots/r/x.gguf"), env: env)
        XCTAssertNil(url, "must not invent a path")
    }

    func testResolveRejectsUnknownRoot() throws {
        let (hub, _, rel, env) = try makeHub()
        defer { teardown(hub) }
        let url = ModelDiscovery.resolve(
            ModelReference(rootID: "simigo-models", relativePath: rel), env: env)
        XCTAssertNil(url, "only external cache roots are resolvable; never .simigo/models")
    }

    func testResolveRejectsPathEscape() throws {
        let (hub, _, _, env) = try makeHub()
        defer { teardown(hub) }
        let url = ModelDiscovery.resolve(
            ModelReference(rootID: ModelDiscovery.cacheRootID,
                           relativePath: "../../etc/passwd"), env: env)
        XCTAssertNil(url)
    }

    func testResolveRejectsPathAliasesInsteadOfNormalizingThem() throws {
        let (hub, _, _, env) = try makeHub()
        defer { teardown(hub) }
        // Every normalized target below exists. These must still be refused:
        // the reference syntax itself is ambiguous and must not be rewritten.
        let aliases = [
            "models--Foo--Bar/snapshots/rev1/model.gguf/..",
            "models--Foo--Bar/snapshots/rev1/./model.gguf",
            "models--Foo--Bar//snapshots/rev1/model.gguf",
        ]
        for alias in aliases {
            XCTAssertNil(
                ModelDiscovery.resolve(
                    ModelReference(rootID: ModelDiscovery.cacheRootID, relativePath: alias),
                    env: env),
                "must reject non-canonical relative path: \\(alias)")
        }
    }

    func testResolveAndAbsoluteReferenceRejectExternalSnapshotSymlink() throws {
        let (hub, modelURL, _, env) = try makeHub()
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-model-\\(UUID().uuidString).gguf")
        let alias = modelURL.deletingLastPathComponent()
            .appendingPathComponent("external.gguf")
        try Data("outside weights".utf8).write(to: outside)
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: outside)
            teardown(hub)
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)

        let relative = "models--Foo--Bar/snapshots/rev1/external.gguf"
        XCTAssertNil(
            ModelDiscovery.resolve(
                ModelReference(rootID: ModelDiscovery.cacheRootID, relativePath: relative),
                env: env))
        XCTAssertNil(ModelDiscovery.reference(forAbsolutePath: alias.path, env: env))
        XCTAssertFalse(
            ModelDiscovery.discover(env: env).contains {
                $0.fileURL.standardizedFileURL.path == alias.standardizedFileURL.path
            },
            "discovery must not emit a durable reference to an external symlink target")
    }

    func testResolvePreservesInCacheSnapshotToBlobSymlink() throws {
        let (hub, modelURL, rel, env) = try makeHub()
        let blobDirectory = hub.appendingPathComponent(
            "models--Foo--Bar/blobs", isDirectory: true)
        let blobURL = blobDirectory.appendingPathComponent("sha256-test")
        let bytes = Data("in-cache blob weights".utf8)
        try FileManager.default.createDirectory(
            at: blobDirectory, withIntermediateDirectories: true)
        try bytes.write(to: blobURL)
        try FileManager.default.removeItem(at: modelURL)
        try FileManager.default.createSymbolicLink(
            at: modelURL, withDestinationURL: blobURL)
        defer { teardown(hub) }

        let reference = ModelReference(rootID: ModelDiscovery.cacheRootID, relativePath: rel)
        let resolved = try XCTUnwrap(ModelDiscovery.resolve(reference, env: env))
        XCTAssertEqual(
            resolved.standardizedFileURL.path,
            modelURL.standardizedFileURL.path,
            "resolve should preserve the snapshot locator rather than return the blob path")
        XCTAssertEqual(try Data(contentsOf: resolved), bytes)
        XCTAssertEqual(
            ModelDiscovery.reference(forAbsolutePath: modelURL.path, env: env),
            reference)
    }

    func testAbsoluteToReferenceRoundTrips() throws {
        let (hub, modelURL, rel, env) = try makeHub()
        defer { teardown(hub) }
        let ref = ModelDiscovery.reference(forAbsolutePath: modelURL.path, env: env)
        XCTAssertEqual(ref, ModelReference(rootID: ModelDiscovery.cacheRootID, relativePath: rel))
        // The reference re-resolves to the very same machine path.
        XCTAssertEqual(ModelDiscovery.resolve(ref!, env: env)?.path, modelURL.standardizedFileURL.path)
    }

    func testAbsoluteOutsideAnyRootYieldsNoReference() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("elsewhere-\(UUID().uuidString).gguf")
        try Data("x".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        // env with an unrelated hub so `outside` is not under any candidate root.
        let ref = ModelDiscovery.reference(forAbsolutePath: outside.path,
                                                 env: ["HF_HUB_CACHE": NSTemporaryDirectory() + "no-\(UUID().uuidString)"])
        XCTAssertNil(ref, "a bare absolute path outside cache roots must not be stored as identity")
    }
}
