import Foundation
import XCTest
import SimiGo2Experimental
import SimiGoRuntimeContract

@testable import SimiGo

/// Exercises the on-disk prefix-pool path rather than only the namespace helper:
/// two physical model identities write separate sidecars, restart rescans both,
/// and a sidecar copied under the other identity is rejected at loadSync.
final class PrefixPoolDiskNamespaceIdentityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "simigo-prefix-identity-disk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testRescanKeepsDiskSnapshotsSeparatedByPhysicalModelIdentity() async throws {
        let modelA = SettlementIdentityBinding.Identity(
            model: "weights-digest-A", tokenizer: "tokenizer-digest-1")
        let modelB = SettlementIdentityBinding.Identity(
            model: "weights-digest-B", tokenizer: "tokenizer-digest-1")
        let namespaceA = try XCTUnwrap(NativeMLXPrefixPool.namespace(
            modelID: "same-repository-name", kvFingerprint: "same-kv-layout",
            thinkingDisabled: false, engineIdentity: modelA))
        let namespaceB = try XCTUnwrap(NativeMLXPrefixPool.namespace(
            modelID: "same-repository-name", kvFingerprint: "same-kv-layout",
            thinkingDisabled: false, engineIdentity: modelB))
        XCTAssertNotEqual(namespaceA, namespaceB)

        let promptTokens = [11, 22, 33, 44]
        let originalPool = ExecutionStatePrefixPool(
            tokenBudget: 1024, physicalByteBudget: 1_048_576)
        let originalStore = PrefixSnapshotStore(root: root, pool: originalPool)
        let entryA = try await originalStore.export(
            namespace: namespaceA, tokens: promptTokens
        ) { url in
            try Data("physical-kv-snapshot-A".utf8).write(to: url)
        }
        let entryB = try await originalStore.export(
            namespace: namespaceB, tokens: promptTokens
        ) { url in
            try Data("physical-kv-snapshot-B".utf8).write(to: url)
        }
        let artifactA = try XCTUnwrap(entryA.artifact as? DiskPrefixArtifact)
        let artifactB = try XCTUnwrap(entryB.artifact as? DiskPrefixArtifact)
        XCTAssertNotEqual(artifactA.snapshotURL, artifactB.snapshotURL)

        // New process: both on-disk sidecars are discovered and re-registered.
        let restartedPool = ExecutionStatePrefixPool(
            tokenBudget: 1024, physicalByteBudget: 1_048_576)
        let restartedStore = PrefixSnapshotStore(root: root, pool: restartedPool)
        XCTAssertEqual(try restartedStore.rescan(), 2)

        let admittedA = try XCTUnwrap(
            restartedPool.admit(namespace: namespaceA, promptTokens: promptTokens))
        let admittedB = try XCTUnwrap(
            restartedPool.admit(namespace: namespaceB, promptTokens: promptTokens))
        XCTAssertEqual((admittedA.entry.artifact as? DiskPrefixArtifact)?.snapshotURL,
                       artifactA.snapshotURL)
        XCTAssertEqual((admittedB.entry.artifact as? DiskPrefixArtifact)?.snapshotURL,
                       artifactB.snapshotURL)

        // Simulate an incorrect cross-model pool registration: the B namespace
        // is pointed at A's physical file. The disk sidecar is the final check.
        _ = restartedPool.register(
            namespace: namespaceB,
            tokenCount: entryA.tokenCount,
            boundaryHash: entryA.boundaryHash,
            artifact: artifactA)
        let crossModel = try XCTUnwrap(
            restartedPool.admit(namespace: namespaceB, promptTokens: promptTokens))
        XCTAssertThrowsError(try restartedStore.loadSync(crossModel)) { error in
            XCTAssertEqual(
                error as? PrefixSnapshotStoreError,
                .namespaceMismatch(expected: namespaceB, snapshot: namespaceA))
        }
    }
}
