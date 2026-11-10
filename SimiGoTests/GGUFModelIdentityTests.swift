import XCTest
import Darwin
import Foundation
import SimiGoRuntimeContract

@testable import SimiGo

/// I1: the GGUF producer identity must be the model BYTES, not the file name or
/// size, and must be resolved the same way everywhere it is consumed.
final class GGUFModelIdentityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "gguf-model-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // The verified-blob ledger is a real file under the managed root; tests
        // must never write into the user's copy.
        GGUFModelIdentity.blobLedgerURLOverride =
            root.appendingPathComponent("model-content-digests.json")
    }

    override func tearDownWithError() throws {
        GGUFModelIdentity.blobLedgerURLOverride = nil
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ bytes: Data, at relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url.path
    }

    func testSameNameAndSizeWithDifferentBytesResolveToDifferentIdentities() throws {
        let first = Data("GGUF-placeholder-bytes-A".utf8)
        let second = Data("GGUF-placeholder-bytes-B".utf8)
        XCTAssertEqual(first.count, second.count, "the probe must keep the size equal")

        let a = try GGUFModelIdentity.resolve(
            path: try write(first, at: "a/model.gguf"))
        let b = try GGUFModelIdentity.resolve(
            path: try write(second, at: "b/model.gguf"))

        XCTAssertEqual(a.byteCount, b.byteCount)
        XCTAssertEqual(a.contentSource, .fileContents)
        XCTAssertNotEqual(a.contentSHA256, b.contentSHA256)
        XCTAssertNotEqual(a.modelIdentity, b.modelIdentity)
        XCTAssertNotEqual(a.producer.model, b.producer.model)
        XCTAssertNotEqual(a.producer.tokenizer, b.producer.tokenizer)

        // The streamed digest is the production digest, not a private variant.
        XCTAssertEqual(a.contentSHA256, SettlementAuthority.payloadDigest(first))
        XCTAssertEqual(b.contentSHA256, SettlementAuthority.payloadDigest(second))
    }

    func testHuggingFaceBlobSymlinkUsesVerifiedBlobContentAddress() throws {
        let hub = root.appendingPathComponent("hub", isDirectory: true)
        let repo = hub.appendingPathComponent("models--org--demo", isDirectory: true)
        let blobs = repo.appendingPathComponent("blobs", isDirectory: true)
        let snapshot = repo.appendingPathComponent("snapshots/rev-1", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)

        let bytes = Data("gguf-weights-through-the-hub".utf8)
        let sha = SettlementAuthority.payloadDigest(bytes)
        try bytes.write(to: blobs.appendingPathComponent(sha))
        let link = snapshot.appendingPathComponent("demo.gguf")
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: "../../blobs/\(sha)")

        let identity = try GGUFModelIdentity.resolve(path: link.path, hubs: [hub])

        XCTAssertEqual(identity.contentSource, .huggingFaceCacheBlob)
        XCTAssertEqual(identity.contentSHA256, sha)
        XCTAssertEqual(identity.byteCount, Int64(bytes.count))
        XCTAssertTrue(
            identity.resolvedPath.hasSuffix("/blobs/\(sha)"),
            "the symlink must resolve to the blob: \(identity.resolvedPath)")
        // Provenance is recorded, but it is evidence — the digest above is the
        // identity.
        XCTAssertEqual(identity.repository, "org/demo")
        XCTAssertEqual(identity.revision, "rev-1")
        XCTAssertEqual(identity.rootID, "huggingface-cache")
    }

    /// The blob name is a claim about the bytes, and the claim is checked. Same
    /// name, different bytes: the identity must be the bytes', so a rewritten
    /// blob cannot inherit the settlements of the bytes it replaced.
    func testBlobWhoseBytesDisagreeWithItsNameIsIdentifiedByItsBytes() throws {
        let hub = root.appendingPathComponent("hub", isDirectory: true)
        let blobs = hub.appendingPathComponent("models--org--demo/blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)

        let claimed = Data("weights-the-name-was-derived-from".utf8)
        let blobName = SettlementAuthority.payloadDigest(claimed)
        let blob = blobs.appendingPathComponent(blobName)
        try claimed.write(to: blob)

        let original = try GGUFModelIdentity.resolve(path: blob.path, hubs: [hub])
        XCTAssertEqual(original.contentSource, .huggingFaceCacheBlob)
        XCTAssertEqual(original.contentSHA256, blobName)

        // The name stays; the bytes do not.
        let replaced = Data("different-weights-under-the-old-name".utf8)
        try replaced.write(to: blob)

        let changed = try GGUFModelIdentity.resolve(path: blob.path)
        XCTAssertEqual(
            changed.contentSHA256, SettlementAuthority.payloadDigest(replaced),
            "the resolved digest must be the bytes' digest, not the file name")
        XCTAssertNotEqual(
            changed.contentSHA256, blobName,
            "the stale blob name must not survive a content change")
        XCTAssertEqual(
            changed.contentSource, .fileContents,
            "a name that no longer describes the bytes is not a content address")
        XCTAssertNotEqual(changed.modelIdentity, original.modelIdentity)
        XCTAssertNotEqual(changed.producer, original.producer)
    }

    func testBlobDigestCachesDetectSameInodeRewriteWithRestoredMtime() throws {
        let hub = root.appendingPathComponent("hub", isDirectory: true)
        let blobs = hub.appendingPathComponent("models--org--demo/blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)

        let originalBytes = Data("same-size-original".utf8)
        let replacementBytes = Data("same-size-replaced".utf8)
        XCTAssertEqual(originalBytes.count, replacementBytes.count)
        let claimedName = SettlementAuthority.payloadDigest(originalBytes)
        let blob = blobs.appendingPathComponent(claimedName)
        try originalBytes.write(to: blob)

        let originalIdentity = try GGUFModelIdentity.resolve(path: blob.path)
        XCTAssertEqual(originalIdentity.contentSHA256, claimedName)

        var before = stat()
        XCTAssertEqual(blob.path.withCString { Darwin.stat($0, &before) }, 0)
        let handle = try FileHandle(forWritingTo: blob)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: replacementBytes)
        try handle.synchronize()
        try handle.close()

        // Restore the exact mtime. The inode and size are also unchanged; ctime
        // is the only stat field that records this in-place rewrite.
        var times = [
            timespec(tv_sec: before.st_atimespec.tv_sec, tv_nsec: before.st_atimespec.tv_nsec),
            timespec(tv_sec: before.st_mtimespec.tv_sec, tv_nsec: before.st_mtimespec.tv_nsec),
        ]
        let timeResult = blob.path.withCString { path in
            times.withUnsafeMutableBufferPointer { buffer in
                Darwin.utimensat(AT_FDCWD, path, buffer.baseAddress, 0)
            }
        }
        XCTAssertEqual(timeResult, 0, "restore the original mtime for the cache regression")

        var after = stat()
        XCTAssertEqual(blob.path.withCString { Darwin.stat($0, &after) }, 0)
        XCTAssertEqual(before.st_dev, after.st_dev)
        XCTAssertEqual(before.st_ino, after.st_ino)
        XCTAssertEqual(before.st_size, after.st_size)
        XCTAssertEqual(before.st_mtimespec.tv_sec, after.st_mtimespec.tv_sec)
        XCTAssertEqual(before.st_mtimespec.tv_nsec, after.st_mtimespec.tv_nsec)
        XCTAssertTrue(
            before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec
                || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec,
            "ctime must expose the in-place rewrite even when mtime is restored")

        // Supplying hubs bypasses the in-memory resolved cache and exercises the
        // durable blob ledger first. The ordinary call then exercises the
        // in-memory cache key left by the original resolution.
        let ledgerResolution = try GGUFModelIdentity.resolve(path: blob.path, hubs: [hub])
        XCTAssertEqual(ledgerResolution.contentSHA256, SettlementAuthority.payloadDigest(replacementBytes))
        XCTAssertEqual(ledgerResolution.contentSource, .fileContents)

        let memoryResolution = try GGUFModelIdentity.resolve(path: blob.path)
        XCTAssertEqual(memoryResolution.contentSHA256, SettlementAuthority.payloadDigest(replacementBytes))
        XCTAssertNotEqual(memoryResolution.modelIdentity, originalIdentity.modelIdentity)
    }

    func testUnreadableSameSizeCheckpointsDoNotShareFallbackIdentity() throws {
        let first = try write(Data("same-size-A".utf8), at: "unreadable-a/model.gguf")
        let second = try write(Data("same-size-B".utf8), at: "unreadable-b/model.gguf")
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: first)).count,
            try Data(contentsOf: URL(fileURLWithPath: second)).count)

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: first)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: second)
        do {
            _ = try GGUFModelIdentity.resolve(path: first)
            throw XCTSkip("this test process can still read a mode-000 fixture")
        } catch GGUFModelIdentityError.unreadable {
            // Expected: both regular files are unreadable to this process.
        }

        let a = ProducerIdentity.identities(fromPath: first)
        let b = ProducerIdentity.identities(fromPath: second)
        XCTAssertNotEqual(a.model, b.model)
        XCTAssertNotEqual(a.producer.tokenizer, b.producer.tokenizer)
        XCTAssertEqual(a.model, a.producer.model)
        XCTAssertEqual(b.model, b.producer.model)
    }

    func testContentAddressLikeNameOutsideBlobLayoutIsNotTrusted() throws {
        let fakeName = String(repeating: "a", count: 64)
        let bytes = Data("ordinary-local-gguf".utf8)
        let identity = try GGUFModelIdentity.resolve(
            path: try write(bytes, at: "local/\(fakeName)"))

        XCTAssertEqual(identity.contentSource, .fileContents)
        XCTAssertEqual(identity.contentSHA256, SettlementAuthority.payloadDigest(bytes))
        XCTAssertNotEqual(
            identity.contentSHA256, fakeName,
            "a 64-hex file name outside the hub layout must not be taken as content")
    }

    func testSameBytesUnderDifferentNamesShareContentIdentity() throws {
        let bytes = Data("same-model-different-file-name".utf8)
        let one = try GGUFModelIdentity.resolve(path: try write(bytes, at: "one.gguf"))
        let two = try GGUFModelIdentity.resolve(
            path: try write(bytes, at: "renamed/model-two.gguf"))

        XCTAssertEqual(one.modelIdentity, two.modelIdentity)
        XCTAssertEqual(one.producer, two.producer)
    }

    func testTokenizerIdentityIsModelFileBound() throws {
        let identity = try GGUFModelIdentity.resolve(
            path: try write(Data("tokenizer-source".utf8), at: "m.gguf"))
        XCTAssertEqual(
            identity.producer.tokenizer,
            GGUFModelIdentity.tokenizerFingerprint(
                modelContentSHA256: identity.contentSHA256))

        let other = try GGUFModelIdentity.resolve(
            path: try write(Data("different-tokenizer-source".utf8), at: "n.gguf"))
        XCTAssertNotEqual(identity.producer.tokenizer, other.producer.tokenizer)
    }

    func testDirectoryIsRefused() throws {
        let directory = root.appendingPathComponent("model-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertThrowsError(try GGUFModelIdentity.resolve(path: directory.path)) { error in
            guard case GGUFModelIdentityError.notAFile = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    /// The wiring this type exists for: every admission, settlement and
    /// consumption asks `ProducerIdentity` who produced the model. Two local
    /// checkpoints that share a path name and a byte count must not answer the
    /// same thing.
    func testProducerIdentityFollowsTheBytesOfALocalCheckpoint() throws {
        let first = try write(Data("same-length-A".utf8), at: "a/model.gguf")
        let second = try write(Data("same-length-B".utf8), at: "b/model.gguf")
        XCTAssertEqual(
            URL(fileURLWithPath: first).lastPathComponent,
            URL(fileURLWithPath: second).lastPathComponent)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: first)).count,
            try Data(contentsOf: URL(fileURLWithPath: second)).count,
            "the probe must keep name and size equal")

        let a = ProducerIdentity.identity(fromPath: first)
        let b = ProducerIdentity.identity(fromPath: second)
        XCTAssertNotEqual(a.model, b.model, "same name and size, different bytes")
        XCTAssertNotEqual(a.tokenizer, b.tokenizer)
        XCTAssertEqual(
            a, try GGUFModelIdentity.resolve(path: first).producer,
            "the runtime identity must be the resolver's identity, not a re-derivation")

        // The same bytes under another file name are the same producer.
        let renamed = try write(Data("same-length-A".utf8), at: "c/other-name.gguf")
        XCTAssertEqual(ProducerIdentity.identity(fromPath: renamed), a)

        // The execution state's durable model identity moves with the content too.
        XCTAssertNotEqual(
            ProducerIdentity.canonicalModelIdentity(fromPath: first),
            ProducerIdentity.canonicalModelIdentity(fromPath: second))
    }
}
