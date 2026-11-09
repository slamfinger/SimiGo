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
