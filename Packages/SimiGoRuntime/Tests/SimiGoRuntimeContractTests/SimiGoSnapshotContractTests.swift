import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// C-10c/d style coverage for the snapshot primitives: immutability encoding,
/// capacity limits, `used ⊆ declared`, and the `replayable` conjunction.
final class SimiGoSnapshotContractTests: XCTestCase {
    private typealias Snapshot = SimiGoSnapshotContract

    private let capturedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func fileEntry(
        _ path: String,
        bytes: String,
        embedded: Bool = true,
        rootID: String = "root-1"
    ) throws -> Snapshot.DeclaredEntry {
        let data = Data(bytes.utf8)
        return try Snapshot.DeclaredEntry(
            fileRootID: rootID,
            relativePath: path,
            sha256: Snapshot.sha256Hex(data),
            byteSource: embedded ? .embedded(data) : .unretainedDiskRead,
            size: data.count,
            modified: "2026-10-27T00:00:00.000Z",
            statIdentity: .init(device: "1", inode: "2", modificationNanoseconds: "3"))
    }

    private func makeDeclared(
        entries: [Snapshot.DeclaredEntry],
        capturedAt: Date? = nil,
        idempotencyKey: String? = "idem-1",
        recomputePolicy: String? = "allow_safe_recompute",
        contractJSON: Data = Data(#"{"schema_version":"simigo.result-contract/v1","fields":{}}"#.utf8)
    ) -> Snapshot.Declared {
        Snapshot.Declared(
            capturedAt: capturedAt ?? self.capturedAt,
            request: Snapshot.Request(
                kind: "chat",
                rootIDs: ["root-1"],
                contractJSON: contractJSON,
                recomputePolicy: recomputePolicy,
                idempotencyKey: idempotencyKey),
            anchor: Snapshot.Anchor(
                stateID: "state-1",
                settlementID: "settlement-1",
                payloadDigest: Snapshot.sha256Hex(Data("payload".utf8))),
            entries: entries)
    }

    private func errorCode(_ block: () throws -> Void) -> String? {
        do {
            try block()
            return nil
        } catch let error as Snapshot.SnapshotError {
            return error.code
        } catch {
            return String(describing: error)
        }
    }

    // MARK: - Encoding and immutability

    func testDeclaredRoundTripsByteIdentically() throws {
        let declared = makeDeclared(entries: [
            try fileEntry("Sources/A.swift", bytes: "let a = 1\n"),
            try fileEntry("Sources/B.swift", bytes: "let b = 2\n", embedded: false)
        ])
        let first = try declared.encoded()
        let second = try declared.encoded()
        XCTAssertEqual(first, second, "encoding must be deterministic")

        let decoded = try Snapshot.Declared.decode(first)
        XCTAssertEqual(decoded, declared)
        XCTAssertEqual(try decoded.encoded(), first)
        XCTAssertFalse(decoded.replayable, "an unretained disk read is forensic, not replayable")
    }

    func testPerItemReplayableFollowsByteSource() throws {
        let embedded = try fileEntry("a.txt", bytes: "a")
        let disk = try fileEntry("b.txt", bytes: "b", embedded: false)
        let referenced = try Snapshot.DeclaredEntry(
            fileRootID: "root-1", relativePath: "c.txt",
            sha256: Snapshot.sha256Hex(Data("c".utf8)),
            byteSource: .objectReference(objectID: Snapshot.sha256Hex(Data("c".utf8))))
        XCTAssertTrue(embedded.replayable)
        XCTAssertTrue(referenced.replayable)
        XCTAssertFalse(disk.replayable)

        let mixed = makeDeclared(entries: [embedded, disk])
        XCTAssertFalse(mixed.replayable)
        XCTAssertEqual(mixed.embeddedRawByteCount, Data("a".utf8).count)
    }

    func testEmbeddedBytesMustHashToDeclaredDigest() {
        let code = errorCode {
            _ = try Snapshot.DeclaredEntry(
                fileRootID: "root-1", relativePath: "a.txt",
                sha256: Snapshot.sha256Hex(Data("other".utf8)),
                byteSource: .embedded(Data("a".utf8)))
        }
        XCTAssertEqual(code, "snapshot_field_invalid")
    }

    func testDeclaredInputDigestExcludesForensicFields() throws {
        let entries = [try fileEntry("a.txt", bytes: "a")]
        let base = makeDeclared(entries: entries)
        let replay = makeDeclared(
            entries: entries,
            capturedAt: capturedAt.addingTimeInterval(3600),
            idempotencyKey: "idem-2",
            recomputePolicy: "never")
        XCTAssertEqual(try base.computeDeclaredInputDigest(),
                       try replay.computeDeclaredInputDigest(),
                       "captured_at, idempotency_key and recompute_policy are not part of the fingerprint")

        let changedContract = makeDeclared(
            entries: entries,
            contractJSON: Data(#"{"schema_version":"simigo.result-contract/v1","fields":{"x":{"type":"string"}}}"#.utf8))
        XCTAssertNotEqual(try base.computeDeclaredInputDigest(),
                          try changedContract.computeDeclaredInputDigest())

        let changedBytes = makeDeclared(entries: [try fileEntry("a.txt", bytes: "A")])
        XCTAssertNotEqual(try base.computeDeclaredInputDigest(),
                          try changedBytes.computeDeclaredInputDigest())
    }

    // MARK: - Capacity limits (fail-closed)

    func testEmbeddedRawBytesOverLimitAreRefused() throws {
        let oversized = Data(repeating: 0x41, count: Snapshot.embeddedRawByteLimit + 1)
        let entry = try Snapshot.DeclaredEntry(
            fileRootID: "root-1", relativePath: "big.bin",
            sha256: Snapshot.sha256Hex(oversized), byteSource: .embedded(oversized))
        let declared = makeDeclared(entries: [entry])
        XCTAssertEqual(errorCode { _ = try declared.encoded() }, "snapshot_unrepresentable")
    }

    func testEmbeddedRawBytesAtLimitAreAccepted() throws {
        let atLimit = Data(repeating: 0x42, count: Snapshot.embeddedRawByteLimit)
        let entry = try Snapshot.DeclaredEntry(
            fileRootID: "root-1", relativePath: "limit.bin",
            sha256: Snapshot.sha256Hex(atLimit), byteSource: .embedded(atLimit))
        let data = try makeDeclared(entries: [entry]).encoded()
        XCTAssertGreaterThan(data.count, Snapshot.embeddedRawByteLimit)
        XCTAssertLessThanOrEqual(data.count, Snapshot.serializedObjectByteLimit)
    }

    func testSerializedObjectOverLimitIsRefused() throws {
        let declared = makeDeclared(entries: [try fileEntry("a.txt", bytes: "a")])
        XCTAssertEqual(
            errorCode { _ = try declared.encoded(objectByteLimit: 256) },
            "snapshot_unrepresentable")
    }

    // MARK: - used ⊆ declared and the replayable conjunction (O2)

    func testConjunctiveReplayableTrueWhenDeclaredAndUsedAgree() throws {
        let entry = try fileEntry("a.txt", bytes: "alpha")
        let declared = makeDeclared(entries: [entry])
        let used = [Snapshot.UsedItem.from(declared: entry, injectedAs: "context[0]")]

        let evaluation = Snapshot.evaluateReplayable(declared: declared, used: used)
        XCTAssertTrue(evaluation.value)
        XCTAssertTrue(evaluation.subsetViolations.isEmpty)

        let final = try Snapshot.Final.make(
            declared: declared,
            declaredSnapshotID: Snapshot.sha256Hex(Data("snapshot".utf8)),
            used: used,
            verifiedAsOf: capturedAt,
            recheck: ["closure": "ok"],
            capturedAt: capturedAt)
        XCTAssertTrue(final.replayable)
        XCTAssertNoThrow(try final.verify(against: declared))
    }

    func testReplayableFalseWhenUsedIsMissing() throws {
        let declared = makeDeclared(entries: [try fileEntry("a.txt", bytes: "alpha")])
        let evaluation = Snapshot.evaluateReplayable(declared: declared, used: nil)
        XCTAssertFalse(evaluation.value, "a crash during G loses used; nothing may claim replayability")
        XCTAssertFalse(evaluation.usedPresent)
    }

    func testReplayableFalseWhenUsedContainsUndeclaredItem() throws {
        let declared = makeDeclared(entries: [try fileEntry("a.txt", bytes: "alpha")])
        let stray = Snapshot.UsedItem(
            identity: .file(rootID: "root-1", relativePath: "stray.txt"),
            digest: Snapshot.sha256Hex(Data("stray".utf8)),
            provenance: .embedded,
            injectedAs: "context[1]")
        let evaluation = Snapshot.evaluateReplayable(declared: declared, used: [stray])
        XCTAssertFalse(evaluation.value)
        XCTAssertEqual(evaluation.subsetViolations.map(\.kind), [.undeclared])
    }

    func testReplayableFalseWhenUsedDigestDiffers() throws {
        let entry = try fileEntry("a.txt", bytes: "alpha")
        let declared = makeDeclared(entries: [entry])
        let tampered = Snapshot.UsedItem(
            identity: entry.identity,
            digest: Snapshot.sha256Hex(Data("alpha-v2".utf8)),
            provenance: .embedded,
            injectedAs: "context[0]")
        let evaluation = Snapshot.evaluateReplayable(declared: declared, used: [tampered])
        XCTAssertFalse(evaluation.value, "same identity, different version must not count as covered")
        XCTAssertEqual(evaluation.subsetViolations.map(\.kind), [.digestMismatch])
    }

    func testReplayableFalseWhenUsedReliesOnUnretainedBytes() throws {
        let entry = try fileEntry("a.txt", bytes: "alpha", embedded: false)
        let declared = makeDeclared(entries: [entry])
        let final = try Snapshot.Final.make(
            declared: declared,
            declaredSnapshotID: Snapshot.sha256Hex(Data("snapshot".utf8)),
            used: [Snapshot.UsedItem.from(declared: entry, injectedAs: "context[0]")],
            verifiedAsOf: capturedAt,
            recheck: [:],
            capturedAt: capturedAt)
        XCTAssertFalse(final.replayable)
        XCTAssertNoThrow(try final.verify(against: declared))
    }

    func testFinalMakeRejectsUndeclaredAndMismatchedUsed() throws {
        let entry = try fileEntry("a.txt", bytes: "alpha")
        let declared = makeDeclared(entries: [entry])
        let snapshotID = Snapshot.sha256Hex(Data("snapshot".utf8))

        let strayCode = errorCode {
            _ = try Snapshot.Final.make(
                declared: declared,
                declaredSnapshotID: snapshotID,
                used: [Snapshot.UsedItem(identity: .file(rootID: "root-1", relativePath: "stray.txt"),
                                         digest: Snapshot.sha256Hex(Data("s".utf8)),
                                         provenance: .embedded, injectedAs: "c")],
                verifiedAsOf: capturedAt, recheck: [:], capturedAt: capturedAt)
        }
        XCTAssertEqual(strayCode, "snapshot_used_undeclared")

        let mismatchCode = errorCode {
            _ = try Snapshot.Final.make(
                declared: declared,
                declaredSnapshotID: snapshotID,
                used: [Snapshot.UsedItem(identity: entry.identity,
                                         digest: Snapshot.sha256Hex(Data("alpha-v2".utf8)),
                                         provenance: .embedded, injectedAs: "c")],
                verifiedAsOf: capturedAt, recheck: [:], capturedAt: capturedAt)
        }
        XCTAssertEqual(mismatchCode, "snapshot_used_mismatch")
    }

    // MARK: - Final encoding and fail-closed decoding

    func testFinalRoundTripsAndRechecksAgainstDeclared() throws {
        let entry = try fileEntry("a.txt", bytes: "alpha")
        let declared = makeDeclared(entries: [entry])
        let final = try Snapshot.Final.make(
            declared: declared,
            declaredSnapshotID: Snapshot.sha256Hex(Data("snapshot".utf8)),
            used: [Snapshot.UsedItem.from(declared: entry, injectedAs: "context[0]")],
            verifiedAsOf: capturedAt,
            recheck: ["sources": "unchanged", "closure": "unchanged"],
            capturedAt: capturedAt)

        let data = try final.encoded()
        let decoded = try Snapshot.Final.decode(data)
        XCTAssertEqual(decoded, final)
        XCTAssertEqual(try decoded.encoded(), data)
        XCTAssertNoThrow(try decoded.verify(against: declared))
    }

    func testFinalOverObjectLimitIsRefused() throws {
        let entry = try fileEntry("a.txt", bytes: "alpha")
        let declared = makeDeclared(entries: [entry])
        let final = try Snapshot.Final.make(
            declared: declared,
            declaredSnapshotID: Snapshot.sha256Hex(Data("snapshot".utf8)),
            used: [Snapshot.UsedItem.from(declared: entry, injectedAs: "context[0]")],
            verifiedAsOf: capturedAt, recheck: [:], capturedAt: capturedAt)
        XCTAssertEqual(errorCode { _ = try final.encoded(objectByteLimit: 256) },
                       "snapshot_unrepresentable")
    }

    func testDecodeRejectsUnknownPartAndVersion() throws {
        let declared = makeDeclared(entries: [try fileEntry("a.txt", bytes: "a")])
        let data = try declared.encoded()

        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["part"] = "final-v2"
        let unknownPart = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertEqual(errorCode { _ = try Snapshot.Declared.decode(unknownPart) },
                       "snapshot_part_unknown")

        var versioned = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        versioned["canonical_version"] = "c-snapshot-v2"
        let unknownVersion = try JSONSerialization.data(withJSONObject: versioned, options: [.sortedKeys])
        XCTAssertEqual(errorCode { _ = try Snapshot.Declared.decode(unknownVersion) },
                       "snapshot_schema_unknown")

        XCTAssertEqual(errorCode { _ = try Snapshot.Final.decode(data) }, "snapshot_part_unknown")
    }

    func testDecodeDetectsTamperedDeclaredContent() throws {
        let declared = makeDeclared(entries: [try fileEntry("a.txt", bytes: "alpha")])
        let data = try declared.encoded()
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var sources = try XCTUnwrap(object["sources"] as? [[String: Any]])
        sources[0]["relative_path"] = "b.txt"
        object["sources"] = sources
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertEqual(errorCode { _ = try Snapshot.Declared.decode(tampered) },
                       "snapshot_digest_mismatch")
    }

    func testDecodeRejectsReplayableClaimedWithoutEvidence() throws {
        let entry = try fileEntry("a.txt", bytes: "alpha")
        let declared = makeDeclared(entries: [entry])
        let final = try Snapshot.Final.make(
            declared: declared,
            declaredSnapshotID: Snapshot.sha256Hex(Data("snapshot".utf8)),
            used: [Snapshot.UsedItem.from(declared: entry, injectedAs: "context[0]")],
            verifiedAsOf: capturedAt, recheck: [:], capturedAt: capturedAt)

        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: final.encoded()) as? [String: Any])
        var used = try XCTUnwrap(object["used"] as? [[String: Any]])
        used[0]["byte_source"] = "disk"
        used[0]["replayable"] = true
        object["used"] = used
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertEqual(errorCode { _ = try Snapshot.Final.decode(tampered) },
                       "snapshot_replayable_mismatch")
    }
}
