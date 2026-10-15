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


    /// A model-directory revision change between the initial metadata capture
    /// and content-identity completion must fail activation before loading or
    /// installing a hook. The injected sequence makes the race deterministic.
    func testActivationRejectsRevisionChangeDuringIdentityAndPreservesHooks() async throws {
        let modelDirectory = try makeEmptyModelDirectory()
        defer { try? FileManager.default.removeItem(at: modelDirectory) }

        let priorOwner = MLXPrefixCrossSessionCache.activeInstance
        let legacySlotWasOccupied = ChatSession.crossSessionPrefixLookup != nil
        let contextSlotWasOccupied = ChatSession.crossSessionPrefixLookupWithContext != nil
        let revisions = RevisionSequence(["revision-before-hash", "revision-after-hash"])
        let loaderCalls = LockedCallCounter()

        let host = MLXSmallScaleChatHost(
            base: base,
            containerLoader: { _ in
                loaderCalls.increment()
                throw TestLoaderError.unavailable
            },
            revisionProvider: { _ in revisions.next() })

        do {
            _ = try await host.activate(modelDirectory: modelDirectory)
            XCTFail("activation must fail when the model revision changes during identity computation")
        } catch let error as MLXSmallScaleChatHost.HostError {
            XCTAssertEqual(error, .modelDirectoryChangedDuringActivation(modelDirectory))
        } catch {
            XCTFail("unexpected error: \\(error)")
        }

        XCTAssertEqual(revisions.callCount, 2)
        XCTAssertEqual(loaderCalls.count, 0, "a drift detected after hashing must stop before container loading")
        XCTAssertNil(host.activeModelDirectory)
        XCTAssertNil(host.activeStore)
        XCTAssertNil(host.activeNamespace)
        XCTAssertTrue(MLXPrefixCrossSessionCache.activeInstance === priorOwner)
        XCTAssertEqual(ChatSession.crossSessionPrefixLookup != nil, legacySlotWasOccupied)
        XCTAssertEqual(ChatSession.crossSessionPrefixLookupWithContext != nil, contextSlotWasOccupied)
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


/// Thread-safe scripted revision source used only by host activation tests.
private final class RevisionSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]
    private var index = 0

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return nil }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return index
    }
}

private final class LockedCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
