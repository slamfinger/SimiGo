import XCTest
import Foundation
import SimiGoRuntimeContract

@testable import SimiGo

/// P2 from the second code review: a local MLX directory outside the Hugging
/// Face cache used to fingerprint to the digest of three nulls (repo, revision,
/// root all absent), so two different models with the same tokenizer shared a
/// producer identity and could restore each other's physical KV.
///
/// These tests pin the two halves of the fix:
///  - different weights => different identity (and the bind verdict refuses),
///  - weights that cannot be hashed => no identity at all (fail closed).
final class ProducerIdentityWeightsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "producer-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Same basename, same tokenizer, different weight bytes — the exact
    /// collision the review describes (`/models/A/my-model` vs
    /// `/models/B/my-model`).
    @discardableResult
    private func makeModel(
        _ name: String, tokenizer: String, weights: Data,
        shards: [String: Data] = [:]
    ) throws -> String {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(tokenizer.utf8).write(to: dir.appendingPathComponent("tokenizer.json"))
        try weights.write(to: dir.appendingPathComponent("model.safetensors"))
        for (file, data) in shards {
            try data.write(to: dir.appendingPathComponent(file))
        }
        return dir.path
    }

    func testSameTokenizerDifferentWeightsDoNotShareIdentity() throws {
        let a = try makeModel("A/my-model", tokenizer: "{\"vocab\":1}", weights: Data("weights-a".utf8))
        let b = try makeModel("B/my-model", tokenizer: "{\"vocab\":1}", weights: Data("weights-b".utf8))

        let idA = ProducerIdentity.identity(fromPath: a)
        let idB = ProducerIdentity.identity(fromPath: b)

        XCTAssertTrue(idA.isSpecified)
        XCTAssertTrue(idB.isSpecified)
        XCTAssertNotEqual(idA.model, idB.model,
                          "two local directories with different weight bytes must not share a model identity")

        // The gate itself: a KV row produced by A must not bind under B.
        let verdict = SettlementIdentityBinding.evaluate(
            recorded: SettlementIdentityBinding.bindings(for: idA), consumer: idB)
        XCTAssertEqual(verdict.status, .blocked)
        XCTAssertEqual(verdict.code, SettlementIdentityBinding.Refusal.modelMismatch.rawValue)
    }

    func testSameWeightsRelocatedShareIdentity() throws {
        let a = try makeModel("A/my-model", tokenizer: "{\"vocab\":1}", weights: Data("same".utf8))
        let b = try makeModel("B/my-model", tokenizer: "{\"vocab\":1}", weights: Data("same".utf8))

        XCTAssertEqual(ProducerIdentity.identity(fromPath: a).model,
                       ProducerIdentity.identity(fromPath: b).model,
                       "identity is the weight bytes, not the path")
    }

    func testShardChangeChangesIdentity() throws {
        let a = try makeModel(
            "A/my-model", tokenizer: "{\"vocab\":1}", weights: Data("index".utf8),
            shards: ["model-00001-of-00002.safetensors": Data("one".utf8)])
        let b = try makeModel(
            "B/my-model", tokenizer: "{\"vocab\":1}", weights: Data("index".utf8),
            shards: ["model-00001-of-00002.safetensors": Data("two".utf8)])

        XCTAssertNotEqual(ProducerIdentity.identity(fromPath: a).model,
                          ProducerIdentity.identity(fromPath: b).model,
                          "a single shard byte change must move the identity")
    }

    func testSameSizeRewriteWithRestoredModificationDateChangesIdentity() throws {
        let path = try makeModel(
            "rewrite/model", tokenizer: "{\\"vocab\\":1}", weights: Data("same-size-A".utf8))
        let weight = URL(fileURLWithPath: path).appendingPathComponent("model.safetensors")
        // Set a whole-second timestamp first. APFS can expose subsecond values
        // through stat but FileManager.setAttributes may round them when
        // restoring; this keeps the regression about content/ctime, not Date
        // representation precision.
        let initial = try FileManager.default.attributesOfItem(atPath: weight.path)
        let initialDate = try XCTUnwrap(initial[.modificationDate] as? Date)
        let restoredModificationDate = Date(
            timeIntervalSince1970: floor(initialDate.timeIntervalSince1970))
        try FileManager.default.setAttributes(
            [.modificationDate: restoredModificationDate], ofItemAtPath: weight.path)
        let before = try FileManager.default.attributesOfItem(atPath: weight.path)
        let originalModificationDate = try XCTUnwrap(before[.modificationDate] as? Date)
        let originalSize = try XCTUnwrap(before[.size] as? NSNumber).int64Value
        let originalIdentity = ProducerIdentity.identity(fromPath: path)

        let handle = try FileHandle(forWritingTo: weight)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("same-size-B".utf8))
        try handle.synchronize()
        try handle.close()
        try FileManager.default.setAttributes(
            [.modificationDate: originalModificationDate], ofItemAtPath: weight.path)

        let after = try FileManager.default.attributesOfItem(atPath: weight.path)
        XCTAssertEqual(try XCTUnwrap(after[.size] as? NSNumber).int64Value, originalSize)
        XCTAssertEqual(after[.modificationDate] as? Date, originalModificationDate)

        let rewrittenIdentity = ProducerIdentity.identity(fromPath: path)
        XCTAssertNotEqual(
            originalIdentity.model, rewrittenIdentity.model,
            "same path, size and restored mtime must not preserve a stale weight digest")
    }

    func testModelDiscoveryDoesNotMatchSiblingWithSharedPathPrefix() throws {
        let hub = root.appendingPathComponent("hub", isDirectory: true)
        let requestedRepo = hub.appendingPathComponent("models--org--demo", isDirectory: true)
        let siblingSnapshot = hub.appendingPathComponent(
            "models--org--demolition/snapshots/rev-1", isDirectory: true)
        try FileManager.default.createDirectory(
            at: requestedRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: siblingSnapshot, withIntermediateDirectories: true)
        try Data("sibling-weights".utf8).write(
            to: siblingSnapshot.appendingPathComponent("model.safetensors"))

        let fields = ProducerIdentity.modelIdentity(fromPath: requestedRepo.path, hubs: [hub])
        XCTAssertNil(fields["model_repo_id"] as? String,
                     "a sibling whose path merely shares the directory prefix is not inside this model")
        XCTAssertNil(fields["model_weights_identity"],
                     "the requested directory has no local weight files")
    }

    func testDirectoryWithoutWeightsHasNoIdentity() throws {
        let dir = root.appendingPathComponent("tokenizer-only", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{\"vocab\":1}".utf8).write(to: dir.appendingPathComponent("tokenizer.json"))

        let identity = ProducerIdentity.identity(fromPath: dir.path)
        XCTAssertFalse(identity.isSpecified,
                       "a directory whose weights cannot be hashed must not claim an identity")

        let verdict = SettlementIdentityBinding.evaluate(
            recorded: [SettlementIdentityBinding.modelKey: "x"],
            consumer: identity)
        XCTAssertEqual(verdict.status, .blocked)
        XCTAssertEqual(verdict.code, SettlementIdentityBinding.Refusal.consumerAbsent.rawValue)
    }

    func testMissingDirectoryHasNoIdentity() throws {
        let identity = ProducerIdentity.identity(
            fromPath: root.appendingPathComponent("nope").path)
        XCTAssertFalse(identity.isSpecified)
    }
}
