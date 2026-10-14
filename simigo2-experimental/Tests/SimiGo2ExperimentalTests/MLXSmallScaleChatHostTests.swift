import XCTest
import MLXLMCommon
@testable import SimiGo2Experimental

/// Host error paths run without a model (the container loader is injected);
/// the happy-path lifecycle is covered by the real-model acceptance probe,
/// which is where the five GUI-promotion acceptance items are evidenced.
final class MLXSmallScaleChatHostTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("small-scale-host-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func makeEmptyModelDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("host-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testActivateMissingModelDirectoryFailsClosed() async throws {
        let host = MLXSmallScaleChatHost(base: base, containerLoader: { _ in
            XCTFail("loader must not run for a missing directory")
            throw TestLoaderError.unavailable
        })
        let missing = base.appendingPathComponent("nonexistent-model")
        do {
            _ = try await host.activate(modelDirectory: missing)
            XCTFail("activation must fail for a missing directory")
        } catch let error as MLXSmallScaleChatHost.HostError {
            XCTAssertEqual(error, .modelDirectoryMissing(missing))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertNil(host.activeModelDirectory)
        XCTAssertNil(host.activeStore)
        XCTAssertNil(host.activeNamespace)
        XCTAssertNil(MLXPrefixCrossSessionCache.activeInstance)
        XCTAssertNil(ChatSession.crossSessionPrefixLookup)
        XCTAssertThrowsError(try host.makeSession()) { error in
            XCTAssertEqual(error as? MLXSmallScaleChatHost.HostError, .notActive)
        }
    }

    /// A loader failure during activation must leave the global hook exactly
    /// unowned — no cache was installed, so no adoption can happen.
    func testActivateLoaderFailureLeavesHookUnowned() async throws {
        let modelDirectory = try makeEmptyModelDirectory()
        defer { try? FileManager.default.removeItem(at: modelDirectory) }

        struct LoadFailed: Error, Equatable {}
        let host = MLXSmallScaleChatHost(base: base, containerLoader: { _ in
            throw LoadFailed()
        })
        do {
            _ = try await host.activate(modelDirectory: modelDirectory)
            XCTFail("activation must fail when the loader fails")
        } catch is LoadFailed {}
        XCTAssertNil(host.activeModelDirectory)
        XCTAssertNil(MLXPrefixCrossSessionCache.activeInstance)
        XCTAssertNil(ChatSession.crossSessionPrefixLookup)
    }

    /// Deactivating a never-activated host must be a safe no-op.
    func testDeactivateWithoutActivationIsNoop() {
        let host = MLXSmallScaleChatHost(base: base, containerLoader: { _ in
            throw TestLoaderError.unavailable
        })
        host.deactivate()
        XCTAssertNil(host.activeModelDirectory)
        XCTAssertNil(ChatSession.crossSessionPrefixLookup)
    }
}

private enum TestLoaderError: Error {
    case unavailable
}
