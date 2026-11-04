import XCTest
import SimiGo2Experimental

/// Slice 4 regression: a stale loader must not evict a replaced cache entry.
///
/// A same-content re-export replaces an entry's PHYSICAL artifact while its
/// semantic identity (namespace, tokenCount, boundaryHash) is unchanged, so the
/// pool's `==` cannot tell the OLD handle from the NEW one. The store's async
/// (`load`) and sync (`loadSync`) paths, on a loud artifact failure, now remove
/// by ARTIFACT match, so a request still holding the superseded handle cannot
/// drop the freshly installed entry.
///
/// Model-free: the failure path never reads KV bytes — a missing sidecar throws
/// `artifactUnreadable` before `loadPromptCacheSnapshot`, so no model, no real
/// snapshot file, no disk format is exercised.
final class StaleAdmissionCacheEvictionTests: XCTestCase {
    private let ns = PrefixPoolNamespace(modelID: "slice4-model", kvFingerprint: "slice4-kv")
    private let tokens = [11, 22, 33, 44]

    private func makePoolAndStore() -> (ExecutionStatePrefixPool, PrefixSnapshotStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("slice4-\(UUID().uuidString)", isDirectory: true)
        let pool = ExecutionStatePrefixPool(tokenBudget: 1000)
        return (pool, PrefixSnapshotStore(root: root, pool: pool))
    }

    private func artifact(_ pool: ExecutionStatePrefixPool) -> DiskPrefixArtifact? {
        pool.admit(namespace: ns, promptTokens: tokens)?.entry.artifact as? DiskPrefixArtifact
    }

    /// Slice 6: the public explicit `store.remove(_:)` now funnels through the
    /// same artifact guard, so removing a STALE handle (same content, superseded
    /// artifact) must not evict the replacement.
    func testExplicitRemoveOfStaleEntryKeepsReplacement() throws {
        let (pool, store) = makePoolAndStore()
        let a = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-absent/a.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-absent/a.json"))
        let entryA = pool.export(namespace: ns, tokens: tokens, artifact: a)
        let b = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-live/b.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-live/b.json"))
        _ = pool.export(namespace: ns, tokens: tokens, artifact: b)

        store.remove(entryA)   // stale handle
        XCTAssertEqual(artifact(pool), b, "stale explicit remove must not evict B")
    }

    /// Acceptance: removing the entry that IS live still evicts it (normal
    /// explicit invalidation is preserved).
    func testExplicitRemoveOfLiveEntryEvictsIt() throws {
        let (pool, store) = makePoolAndStore()
        let a = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-absent/a.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-absent/a.json"))
        let entryA = pool.export(namespace: ns, tokens: tokens, artifact: a)
        XCTAssertEqual(artifact(pool), a, "precondition: A live")
        store.remove(entryA)
        XCTAssertNil(artifact(pool), "removing the live entry still evicts it")
    }

    /// Async path: request A (unreadable artifact) fails loudly, the replaced
    /// entry B must survive the cleanup.
    func testStaleAsyncLoadFailureKeepsReplacedEntry() async throws {
        let (pool, store) = makePoolAndStore()
        let a = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-absent/a.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-absent/a.json"))
        _ = pool.export(namespace: ns, tokens: tokens, artifact: a)
        let staleA = try XCTUnwrap(pool.admit(namespace: ns, promptTokens: tokens))
        XCTAssertEqual(staleA.entry.artifact as? DiskPrefixArtifact, a)

        // Same content re-exported: artifact B replaces A in the live pool.
        let b = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-live/b.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-live/b.json"))
        _ = pool.export(namespace: ns, tokens: tokens, artifact: b)
        XCTAssertEqual(artifact(pool), b, "B is the live artifact")

        do {
            _ = try await store.load(staleA)
            XCTFail("stale artifact A must fail to load")
        } catch {
            XCTAssertTrue(String(reflecting: error).contains("artifactUnreadable"),
                          "expected loud artifactUnreadable, got \(String(reflecting: error))")
        }
        XCTAssertEqual(artifact(pool), b, "stale A must NOT evict the replaced entry B")
    }

    /// Sync twin of the async race.
    func testStaleSyncLoadFailureKeepsReplacedEntry() throws {
        let (pool, store) = makePoolAndStore()
        let a = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-absent/a.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-absent/a.json"))
        _ = pool.export(namespace: ns, tokens: tokens, artifact: a)
        let staleA = try XCTUnwrap(pool.admit(namespace: ns, promptTokens: tokens))

        let b = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-live/b.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-live/b.json"))
        _ = pool.export(namespace: ns, tokens: tokens, artifact: b)

        do {
            _ = try store.loadSync(staleA)
            XCTFail("stale artifact A must fail to loadSync")
        } catch {
            XCTAssertTrue(String(reflecting: error).contains("artifactUnreadable"),
                          "expected loud artifactUnreadable, got \(String(reflecting: error))")
        }
        XCTAssertEqual(artifact(pool), b, "sync stale A must NOT evict B")
    }

    /// Acceptance: a genuine failure on the entry that IS live still evicts it
    /// (the fix does not disable self-healing).
    func testGenuineFailureOnLiveArtifactStillEvicts() async throws {
        let (pool, store) = makePoolAndStore()
        let a = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-absent/a.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-absent/a.json"))
        _ = pool.export(namespace: ns, tokens: tokens, artifact: a)
        let liveA = try XCTUnwrap(pool.admit(namespace: ns, promptTokens: tokens))
        XCTAssertEqual(artifact(pool), a, "precondition: A live")

        do {
            _ = try await store.load(liveA)
            XCTFail("unreadable artifact must throw")
        } catch {
            XCTAssertTrue(String(reflecting: error).contains("artifactUnreadable"))
        }
        XCTAssertNil(artifact(pool), "genuine failure on the live artifact must still evict")
    }

    /// Documents the hazard the fix closes, as a direct contrast at the pool
    /// boundary: artifact-matched remove is a no-op on a stale handle, while
    /// content-only remove would drop the replaced entry.
    func testArtifactMatchedRemoveSparesReplacementWhileContentOnlyWouldNot() throws {
        let (pool, _) = makePoolAndStore()
        let a = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-absent/a.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-absent/a.json"))
        _ = pool.export(namespace: ns, tokens: tokens, artifact: a)
        let staleA = try XCTUnwrap(pool.admit(namespace: ns, promptTokens: tokens))

        let b = DiskPrefixArtifact(
            snapshotURL: URL(fileURLWithPath: "/slice4-live/b.safetensors"),
            metadataURL: URL(fileURLWithPath: "/slice4-live/b.json"))
        _ = pool.export(namespace: ns, tokens: tokens, artifact: b)

        XCTAssertFalse(pool.remove(staleA.entry, artifact: a),
                       "artifact-matched remove must not match the replaced entry B")
        XCTAssertEqual(artifact(pool), b)
        XCTAssertTrue(pool.remove(staleA.entry),
                      "content equality alone matches (and would evict) the replaced entry")
        XCTAssertNil(artifact(pool), "records why content-only cleanup is unsafe")
    }
}
