import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// G2 — SQLite Information-Space BEHAVIORAL experiments (not just structural
/// integrity). Per the revised plan, passing `integrity_check=ok` is NOT enough:
/// the IS must carry TWO sources (external work files + agent sessions), link
/// settled information objects to their sources and to each other, and support
/// LOCAL dynamic invalidation — a source change flips only the affected
/// dependency closure to invalid while unrelated valid results survive. It must
/// also prove: repeat-scan idempotency, reconciliation of lost watcher events,
/// transaction atomicity, and data ownership (no external file bytes copied in).
///
/// These are the PRODUCT G2 acceptance experiments; they are distinct from any
/// same-named narrow experiment inside SimiGo-Lab.
final class ESISDatabaseG2Tests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-\(UUID().uuidString)-\(name).sqlite3")
    }
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private static let contract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#

    /// Create a real gate-authorized settlement through the production authority
    /// path and record it as the write authority. Returns its settlement id.
    @discardableResult
    private func mkSettlement(_ db: ESISDatabase, stateID: String, value: String) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "RESULT=\(value)", contractJSON: Data(Self.contract.utf8),
            verifiedBindings: ["next_input": .string(value)]
        )
        XCTAssertEqual(settled.trace.validationStatus, "VALID")
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    // MARK: - Bounded root settlement scans

    func testRootSettlementGlobalLimitsAbortWithoutChangingInventoryOrSettlementState() throws {
        let (databaseURL, db) = try open("scan-limits")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-scan-limits-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootURL) }
        try Data("0123456789".utf8).write(to: rootURL.appendingPathComponent("a.txt"))

        defer { db.close(); cleanup(databaseURL) }
        _ = try db.settleWorkRootContents(
            rootID: "bounded-scan-root", rootURL: rootURL,
            maxObservedFiles: 4, maxTotalBytesRead: 32)
        let baselineInventory = try db.listExternalFiles(rootID: "bounded-scan-root")
        XCTAssertEqual(baselineInventory.map(\.relativePath), ["a.txt"])

        let settlement = try mkSettlement(db, stateID: "S-SCAN-LIMIT", value: "ok")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "bounded-scan-root", relativePath: "a.txt")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)

        try Data("abcdefghij".utf8).write(to: rootURL.appendingPathComponent("b.txt"))

        // The second regular file exceeds the root-wide count cap. The scan
        // must roll back the root upsert and leave both inventories untouched.
        XCTAssertThrowsError(try db.settleWorkRootContents(
            rootID: "bounded-scan-root", rootURL: rootURL,
            maxObservedFiles: 1, maxTotalBytesRead: 32))
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "bounded-scan-root"), baselineInventory)
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)

        // Each file is 10 bytes; the aggregate 15-byte cap allows one and
        // rejects the next. No partial invalidation or inventory update may commit.
        XCTAssertThrowsError(try db.settleWorkRootContents(
            rootID: "bounded-scan-root", rootURL: rootURL,
            maxObservedFiles: 4, maxTotalBytesRead: 15))
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "bounded-scan-root"), baselineInventory)
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)

        // Empty directories are still visited while holding the writer lock.
        // The entry cap must bound them too, not only regular files and bytes.
        for name in ["empty-1", "empty-2", "empty-3"] {
            try fm.createDirectory(
                at: rootURL.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: false)
        }
        XCTAssertThrowsError(try db.settleWorkRootContents(
            rootID: "bounded-scan-root", rootURL: rootURL,
            maxObservedFiles: 4, maxVisitedEntries: 2, maxTotalBytesRead: 32))
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "bounded-scan-root"), baselineInventory)
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)
    }

    func testRootReadRejectsSameInodeRewriteWithRestoredMtime() throws {
        let (databaseURL, db) = try open("root-read-ctime")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-root-ctime-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootURL) }
        defer { db.close(); cleanup(databaseURL) }

        let fileURL = rootURL.appendingPathComponent("source.txt")
        let original = Data(repeating: 0x41, count: 128 * 1024)
        let replacement = Data(repeating: 0x42, count: original.count)
        try original.write(to: fileURL)

        var before = stat()
        XCTAssertEqual(fileURL.path.withCString { Darwin.fstatat(AT_FDCWD, $0, &before, 0) }, 0)
        var didMutate = false
        var restoredMTime = false
        var changedCTime = false
        var mutationError: Error?
        db.beforeRootFileVerificationForTesting = {
            didMutate = true
            do {
                let writer = try FileHandle(forWritingTo: fileURL)
                try writer.seek(toOffset: 0)
                try writer.write(contentsOf: replacement)
                try writer.close()

                var times = [
                    timespec(tv_sec: before.st_atimespec.tv_sec,
                             tv_nsec: before.st_atimespec.tv_nsec),
                    timespec(tv_sec: before.st_mtimespec.tv_sec,
                             tv_nsec: before.st_mtimespec.tv_nsec),
                ]
                let restoreResult = times.withUnsafeBufferPointer { buffer in
                    fileURL.path.withCString {
                        Darwin.utimensat(AT_FDCWD, $0, buffer.baseAddress, 0)
                    }
                }
                guard restoreResult == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }

                var after = stat()
                guard fileURL.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &after, 0) }) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                restoredMTime =
                    before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
                    && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
                changedCTime =
                    before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec
                    || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec
            } catch {
                mutationError = error
            }
        }

        XCTAssertThrowsError(try db.settleWorkRootContents(
            rootID: "root-read-ctime", rootURL: rootURL,
            fileByteCap: 256 * 1024, maxDepth: 1))
        XCTAssertTrue(didMutate)
        XCTAssertNil(mutationError)
        XCTAssertTrue(restoredMTime, "the probe must restore the original mtime")
        XCTAssertTrue(changedCTime, "the same inode rewrite must change ctime")
        XCTAssertNil(db.beforeRootFileVerificationForTesting)
        XCTAssertEqual(try db.count("external_files"), 0)
        XCTAssertEqual(try db.count("file_contents"), 0)
    }

    /// A rename or a move does not touch the bytes but does bump ctime, so the
    /// ctime clause alone cannot tell it apart from a same-size rewrite. Reading
    /// must accept it: a working root is renamed constantly, and refusing here
    /// would turn ordinary editing into collection failure.
    func testRootReadAcceptsRenameDuringReadWithoutInvalidatingContent() throws {
        let (databaseURL, db) = try open("root-read-rename")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-root-rename-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootURL) }
        defer { db.close(); cleanup(databaseURL) }

        let fileURL = rootURL.appendingPathComponent("source.txt")
        let movedURL = rootURL.appendingPathComponent("moved.txt")
        try Data(repeating: 0x41, count: 4096).write(to: fileURL)

        _ = try db.settleWorkRootContents(
            rootID: "root-read-rename", rootURL: rootURL,
            fileByteCap: 256 * 1024, maxDepth: 1)
        let baselineDigest = try XCTUnwrap(
            try db.externalFileDigest(rootID: "root-read-rename", relativePath: "source.txt"))
        let settlement = try mkSettlement(db, stateID: "S-RENAME", value: "renamed-source")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "root-read-rename", relativePath: "source.txt")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")

        var before = stat()
        XCTAssertEqual(fileURL.path.withCString { Darwin.fstatat(AT_FDCWD, $0, &before, 0) }, 0)
        var didRename = false
        var changedCTime = false
        var mtimeHeld = false
        var mutationError: Error?
        db.beforeRootFileVerificationForTesting = {
            didRename = true
            do {
                let result = fileURL.path.withCString { from in
                    movedURL.path.withCString { to in Darwin.rename(from, to) }
                }
                guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                var after = stat()
                guard movedURL.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &after, 0) }) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                mtimeHeld = before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
                    && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
                changedCTime = before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec
                    || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec
            } catch {
                mutationError = error
            }
        }

        _ = try db.settleWorkRootContents(
            rootID: "root-read-rename", rootURL: rootURL,
            fileByteCap: 256 * 1024, maxDepth: 1)
        XCTAssertTrue(didRename)
        XCTAssertNil(mutationError)
        XCTAssertTrue(changedCTime, "the probe must show a rename changes ctime")
        XCTAssertTrue(mtimeHeld, "a rename must leave mtime alone")
        XCTAssertEqual(
            try db.externalFileDigest(rootID: "root-read-rename", relativePath: "source.txt"),
            baselineDigest, "renamed bytes are the same bytes")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)
    }

    /// Creating a hard link adds a name to the same inode: ctime and nlink move,
    /// content does not. Same judgement as the rename case.
    func testRootReadAcceptsHardLinkCreationDuringRead() throws {
        let (databaseURL, db) = try open("root-read-hardlink")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-root-hardlink-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootURL) }
        defer { db.close(); cleanup(databaseURL) }

        let fileURL = rootURL.appendingPathComponent("source.txt")
        let twinURL = rootURL.appendingPathComponent("twin.txt")
        try Data(repeating: 0x43, count: 4096).write(to: fileURL)

        _ = try db.settleWorkRootContents(
            rootID: "root-read-hardlink", rootURL: rootURL,
            fileByteCap: 256 * 1024, maxDepth: 1)
        let baselineDigest = try XCTUnwrap(
            try db.externalFileDigest(rootID: "root-read-hardlink", relativePath: "source.txt"))
        let settlement = try mkSettlement(db, stateID: "S-HARDLINK", value: "linked-source")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "root-read-hardlink", relativePath: "source.txt")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")

        var before = stat()
        XCTAssertEqual(fileURL.path.withCString { Darwin.fstatat(AT_FDCWD, $0, &before, 0) }, 0)
        var didLink = false
        var linkCountChanged = false
        var changedCTime = false
        var mutationError: Error?
        db.beforeRootFileVerificationForTesting = {
            didLink = true
            do {
                let result = fileURL.path.withCString { existing in
                    twinURL.path.withCString { fresh in Darwin.link(existing, fresh) }
                }
                guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                var after = stat()
                guard fileURL.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &after, 0) }) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                linkCountChanged = after.st_nlink > before.st_nlink
                changedCTime = before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec
                    || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec
            } catch {
                mutationError = error
            }
        }

        _ = try db.settleWorkRootContents(
            rootID: "root-read-hardlink", rootURL: rootURL,
            fileByteCap: 256 * 1024, maxDepth: 1)
        XCTAssertTrue(didLink)
        XCTAssertNil(mutationError)
        XCTAssertTrue(linkCountChanged, "the probe must add a second link")
        XCTAssertTrue(changedCTime, "linking changes ctime")
        XCTAssertEqual(
            try db.externalFileDigest(rootID: "root-read-hardlink", relativePath: "source.txt"),
            baselineDigest)
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
    }

    /// The other half of the boundary: an atomic replace moves the name off the
    /// inode being read. Whether the read keeps the detached snapshot or fails
    /// closed, the record must never claim the new path's version while carrying
    /// the old bytes — the next quiescent scan has to disagree with it.
    func testRootReadNeverStampsReplacedPathWithTheDetachedSnapshot() throws {
        let (databaseURL, db) = try open("root-read-replaced")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-root-replaced-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootURL) }
        defer { db.close(); cleanup(databaseURL) }

        let fileURL = rootURL.appendingPathComponent("source.txt")
        let original = Data(repeating: 0x41, count: 4096)
        let replacement = Data(repeating: 0x42, count: original.count)
        try original.write(to: fileURL)

        _ = try db.settleWorkRootContents(
            rootID: "root-read-replaced", rootURL: rootURL,
            fileByteCap: 256 * 1024, maxDepth: 1)
        let baselineDigest = try XCTUnwrap(
            try db.externalFileDigest(rootID: "root-read-replaced", relativePath: "source.txt"))
        let settlement = try mkSettlement(db, stateID: "S-REPLACED", value: "replaced-source")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "root-read-replaced", relativePath: "source.txt")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")

        var didReplace = false
        var mutationError: Error?
        db.beforeRootFileVerificationForTesting = {
            didReplace = true
            do {
                try replacement.write(to: fileURL, options: .atomic)
            } catch {
                mutationError = error
            }
        }

        let raced = try? db.settleWorkRootContents(
            rootID: "root-read-replaced", rootURL: rootURL,
            fileByteCap: 256 * 1024, maxDepth: 1)
        XCTAssertTrue(didReplace)
        XCTAssertNil(mutationError)
        XCTAssertNotNil(
            raced, "a replacement mid-read must not abort the settle; the name moved, "
                + "the bytes on the descriptor stayed whole")

        let racedDigest = try db.externalFileDigest(
            rootID: "root-read-replaced", relativePath: "source.txt")
        if let racedDigest {
            XCTAssertEqual(racedDigest, baselineDigest,
                "a snapshot taken through the descriptor is the version it read, never the successor's")
        }

        // The guarantee that makes the above acceptable: the next quiescent scan
        // reports the successor and retires anything bound to the older content.
        _ = try db.settleWorkRootContents(
            rootID: "root-read-replaced", rootURL: rootURL,
            fileByteCap: 256 * 1024, maxDepth: 1)
        let currentDigest = try XCTUnwrap(
            try db.externalFileDigest(rootID: "root-read-replaced", relativePath: "source.txt"))
        XCTAssertNotEqual(currentDigest, baselineDigest)
        XCTAssertEqual(try db.settlementValidity(settlement), "invalid")
        XCTAssertEqual(try db.validSettlementCount(), 0)
    }

    /// A zero-depth walk cannot observe any child entry. It must be refused
    /// before removal reconciliation, otherwise an unobservable inventory is
    /// misreported as an empty root and every dependent settlement is invalidated.
    /// The directory descriptor pins the old root, but enumeration uses its path.
    /// Replacing that path with an empty directory after enumeration must not make
    /// the old inventory look deleted or invalidate results bound to it.
    func testRootReplacementAfterPinnedOpenCannotMarkOldInventoryMissing() throws {
        let (databaseURL, db) = try open("root-replaced-after-enumeration")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-root-pinned-\(UUID().uuidString)", isDirectory: true)
        let movedRoot = rootURL.deletingLastPathComponent()
            .appendingPathComponent("simigo-g2-root-moved-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: rootURL)
            try? fm.removeItem(at: movedRoot)
            db.close()
            cleanup(databaseURL)
        }
        let source = rootURL.appendingPathComponent("source.txt")
        try Data("old pinned root content".utf8).write(to: source)
        _ = try db.settleWorkRootContents(rootID: "root-pinned", rootURL: rootURL)
        let baselineInventory = try db.listExternalFiles(rootID: "root-pinned")
        let baselineDigest = try XCTUnwrap(
            try db.externalFileDigest(rootID: "root-pinned", relativePath: "source.txt"))
        let settlement = try mkSettlement(db, stateID: "S-PINNED-ROOT", value: "stable")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "root-pinned", relativePath: "source.txt")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")

        var didReplace = false
        var mutationError: Error?
        db.afterRootEnumerationForTesting = {
            didReplace = true
            do {
                try fm.moveItem(at: rootURL, to: movedRoot)
                try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
            } catch {
                mutationError = error
            }
        }

        XCTAssertThrowsError(try db.settleWorkRootContents(
            rootID: "root-pinned", rootURL: rootURL))
        XCTAssertTrue(didReplace, "the replacement must occur after the scan observed the old root")
        XCTAssertNil(mutationError)
        XCTAssertEqual(try db.listExternalFiles(rootID: "root-pinned"), baselineInventory)
        XCTAssertEqual(
            try db.externalFileDigest(rootID: "root-pinned", relativePath: "source.txt"),
            baselineDigest)
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)
    }

    func testRootReplacementImmediatelyBeforeCommitRollsBackInventoryWrites() throws {
        let (databaseURL, db) = try open("root-replaced-before-commit")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-root-commit-\(UUID().uuidString)", isDirectory: true)
        let movedRoot = rootURL.deletingLastPathComponent()
            .appendingPathComponent("simigo-g2-root-commit-moved-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: rootURL)
            try? fm.removeItem(at: movedRoot)
            db.close()
            cleanup(databaseURL)
        }
        let source = rootURL.appendingPathComponent("source.txt")
        try Data("old committed content".utf8).write(to: source)
        _ = try db.settleWorkRootContents(rootID: "root-commit-pinned", rootURL: rootURL)
        let baselineInventory = try db.listExternalFiles(rootID: "root-commit-pinned")
        let baselineDigest = try XCTUnwrap(
            try db.externalFileDigest(rootID: "root-commit-pinned", relativePath: "source.txt"))
        let settlement = try mkSettlement(
            db, stateID: "S-COMMIT-PINNED-ROOT", value: "stable")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "root-commit-pinned", relativePath: "source.txt")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")

        try Data("new content read before commit".utf8).write(to: source)
        var didReplace = false
        var mutationError: Error?
        db.beforeRootScanCommitForTesting = {
            didReplace = true
            do {
                try fm.moveItem(at: rootURL, to: movedRoot)
                try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
            } catch {
                mutationError = error
            }
        }

        XCTAssertThrowsError(try db.settleWorkRootContents(
            rootID: "root-commit-pinned", rootURL: rootURL))
        XCTAssertTrue(didReplace, "the replacement must occur after writes but before commit")
        XCTAssertNil(mutationError)
        XCTAssertEqual(try db.listExternalFiles(rootID: "root-commit-pinned"), baselineInventory)
        XCTAssertEqual(
            try db.externalFileDigest(rootID: "root-commit-pinned", relativePath: "source.txt"),
            baselineDigest)
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)
    }

    func testZeroDepthRootScanCannotInvalidateExistingInventory() throws {
        let (databaseURL, db) = try open("zero-depth")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-zero-depth-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootURL) }
        try Data("stable source".utf8).write(to: rootURL.appendingPathComponent("source.txt"))

        defer { db.close(); cleanup(databaseURL) }
        _ = try db.settleWorkRootContents(rootID: "zero-depth-root", rootURL: rootURL)
        let baselineInventory = try db.listExternalFiles(rootID: "zero-depth-root")
        XCTAssertEqual(baselineInventory.map(\.relativePath), ["source.txt"])

        let settlement = try mkSettlement(db, stateID: "S-ZERO-DEPTH", value: "stable")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "zero-depth-root", relativePath: "source.txt")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)

        XCTAssertThrowsError(try db.settleWorkRootContents(
            rootID: "zero-depth-root", rootURL: rootURL, maxDepth: 0))

        XCTAssertEqual(
            try db.listExternalFiles(rootID: "zero-depth-root"), baselineInventory)
        XCTAssertEqual(try db.count("file_contents"), 1)
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)
    }

    // MARK: - Local invalidation preserves unrelated valid results

    func testG2LocalInvalidationOnlyAffectsClosurePreservesUnrelated() throws {
        let (url, db) = try open("local")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "report.md", kind: "md",
                                 size: 10, modifiedAt: nil, contentDigest: "d1")
        try db.indexExternalFile(rootID: "work", relativePath: "other.md", kind: "md",
                                 size: 10, modifiedAt: nil, contentDigest: "o1")
        let sa = try mkSettlement(db, stateID: "S-A", value: "alpha")
        let sb = try mkSettlement(db, stateID: "S-B", value: "beta")
        try db.linkSettlementToExternalFile(settlementID: sa, binding: "content",
                                            rootID: "work", relativePath: "report.md")
        try db.linkSettlementToExternalFile(settlementID: sb, binding: "content",
                                            rootID: "work", relativePath: "other.md")

        XCTAssertEqual(try db.validSettlementCount(), 2)

        // report.md changes; only SA's closure must go invalid, SB stays valid.
        let changed = try db.reindexExternalFile(rootID: "work", relativePath: "report.md",
                                                 kind: "md", size: 12, modifiedAt: nil,
                                                 contentDigest: "d2")
        XCTAssertTrue(changed)
        let invalidated = try db.invalidateSourceFile(rootID: "work", relativePath: "report.md")
        XCTAssertEqual(Set(invalidated), [sa])
        XCTAssertEqual(try db.settlementValidity(sa), "invalid")
        XCTAssertEqual(try db.settlementValidity(sb), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1, "unrelated valid result preserved")
    }

    // MARK: - Transitive dependency closure

    func testG2TransitiveDependencyClosureInvalidatesDownstream() throws {
        let (url, db) = try open("closure")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "src", kind: "txt",
                                 size: 1, modifiedAt: nil, contentDigest: "s1")
        let sa = try mkSettlement(db, stateID: "S-A", value: "a")   // bound to src
        let sb = try mkSettlement(db, stateID: "S-B", value: "b")   // depends on SA
        let sc = try mkSettlement(db, stateID: "S-C", value: "c")   // depends on SB
        let sd = try mkSettlement(db, stateID: "S-D", value: "d")   // unrelated
        try db.linkSettlementToExternalFile(settlementID: sa, binding: "content",
                                            rootID: "work", relativePath: "src")
        try db.addDependency(fromSettlement: sb, toSettlement: sa)
        try db.addDependency(fromSettlement: sc, toSettlement: sb)

        let invalidated = try db.invalidateSourceFile(rootID: "work", relativePath: "src")
        XCTAssertEqual(Set(invalidated), Set([sa, sb, sc]), "transitive closure A→B→C")
        XCTAssertEqual(try db.settlementValidity(sd), "valid", "unrelated D survives")
        XCTAssertEqual(try db.validSettlementCount(), 1)
    }

    // MARK: - Repeat-scan idempotency

    func testG2RepeatScanIdempotentNoInvalidationWhenUnchanged() throws {
        let (url, db) = try open("idempotent")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "f", kind: "txt",
                                 size: 5, modifiedAt: nil, contentDigest: "x")
        let s = try mkSettlement(db, stateID: "S", value: "v")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "f")

        // Re-scan the SAME digest: not a change → caller triggers no invalidation.
        let changedAgain = try db.reindexExternalFile(rootID: "work", relativePath: "f",
                                                      kind: "txt", size: 5, modifiedAt: nil,
                                                      contentDigest: "x")
        XCTAssertFalse(changedAgain, "unchanged digest must report no change")
        XCTAssertEqual(try db.settlementValidity(s), "valid", "no spurious invalidation")
        XCTAssertEqual(try db.count("external_files"), 1, "repeat scan does not duplicate rows")
        XCTAssertEqual(try db.count("settlements"), 1)
    }

    // MARK: - Reconciliation of lost watcher events

    func testG2ReconcileMissingWatcherEventInvalidatesRemovedFile() throws {
        let (url, db) = try open("reconcile")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "gone.md", kind: "md",
                                 size: 1, modifiedAt: nil, contentDigest: "g1")
        try db.indexExternalFile(rootID: "work", relativePath: "keep.md", kind: "md",
                                 size: 1, modifiedAt: nil, contentDigest: "k1")
        let sa = try mkSettlement(db, stateID: "S-A", value: "a")
        let sb = try mkSettlement(db, stateID: "S-B", value: "b")
        try db.linkSettlementToExternalFile(settlementID: sa, binding: "content",
                                            rootID: "work", relativePath: "gone.md")
        try db.linkSettlementToExternalFile(settlementID: sb, binding: "content",
                                            rootID: "work", relativePath: "keep.md")

        // A watcher event for gone.md was lost; a rescan sees only keep.md.
        let invalidated = try db.reconcileRoot(rootID: "work", seenRelativePaths: ["keep.md"])
        XCTAssertEqual(Set(invalidated), [sa])
        XCTAssertEqual(try db.settlementValidity(sa), "invalid")
        XCTAssertEqual(try db.settlementValidity(sb), "valid")
        XCTAssertTrue(try db.listExternalFiles(rootID: "work")
                        .contains(where: { $0.relativePath == "gone.md" && $0.status == "missing" }))
    }

    // MARK: - Transaction atomicity for local-update writes

    func testG2LocalUpdateWritesAreAtomicUnderFailure() throws {
        let (url, db) = try open("atomic")
        defer { db.close(); cleanup(url) }

        let before = try db.count("settlements")
        XCTAssertThrowsError(try db.transaction {
            try db.recordExecutionState(id: "S-X", parentID: nil, modelIdentity: "m",
                                        position: 1, continuationID: "C", anchor: "a",
                                        lifecycle: "active", createdAt: Date())
            struct Boom: Error {}
            throw Boom()
        })
        XCTAssertEqual(try db.count("execution_states"), 0,
                       "aborted transaction must leave no half-written authority")
        XCTAssertEqual(try db.count("settlements"), before)
    }

    // MARK: - Dual-source coexistence (work files + agent sessions)

    func testG2DualSourceCoexistenceWorkAndSession() throws {
        let (url, db) = try open("dualsource")
        defer { db.close(); cleanup(url) }

        // Source 1: an external work file.
        try db.indexExternalFile(rootID: "work", relativePath: "spec.md", kind: "md",
                                 size: 3, modifiedAt: nil, contentDigest: "w1")
        let sWork = try mkSettlement(db, stateID: "S-W", value: "w")
        try db.linkSettlementToExternalFile(settlementID: sWork, binding: "content",
                                            rootID: "work", relativePath: "spec.md")

        // Source 2: an agent session (no external file row), linked by root only.
        try db.upsertRoot(rootID: "sessroot", category: "session", displayName: nil,
                          locatorType: "path", status: "present")
        try db.indexAgentSession(sessionID: "sess-1", adapterID: "adapter-a",
                                 sourceRootID: "sessroot", metadataDigest: "m1")
        let sSess = try mkSettlement(db, stateID: "S-S", value: "s")
        let sDerived = try mkSettlement(db, stateID: "S-D", value: "d") // depends on the session-sourced one
        try db.addDependency(fromSettlement: sDerived, toSettlement: sSess)

        // Both sources coexist and are individually queryable.
        XCTAssertEqual(try db.listExternalFiles(rootID: "work").count, 1)
        XCTAssertEqual(try db.validSettlementCount(), 3)

        // Session version change → invalidate the session-sourced settlement;
        // its dependent cascades; the work-file settlement is untouched.
        let invalidated = try db.invalidateSettlement(sSess)
        XCTAssertEqual(Set(invalidated), Set([sSess, sDerived]))
        XCTAssertEqual(try db.settlementValidity(sWork), "valid", "other source preserved")
    }

    // MARK: - Data ownership: no external file bytes copied into the DB

    func testG2ExternalFileIndexStoresNoBytes() throws {
        let (url, db) = try open("ownership")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "a.md", kind: "md",
                                 size: 42, modifiedAt: nil, contentDigest: "digest-abc")
        XCTAssertFalse(try db.tableHasBlobColumn("external_files"),
                       "external file index must never hold file bytes")
        XCTAssertEqual(try db.externalFileDigest(rootID: "work", relativePath: "a.md"), "digest-abc")
    }
}
