import Foundation
import SQLite3
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

    /// Mutate only a disposable test database to reproduce its exact pre-v42
    /// SQLite shape. Production migrations still run through ESISDatabase.
    private func executeRawSQLite(_ url: URL, sql: String) throws {
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard openResult == SQLITE_OK, let handle else {
            let detail = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite open failed with code \(openResult)"
            if let handle { sqlite3_close_v2(handle) }
            throw NSError(
                domain: "ESISDatabaseG2Tests.SQLite",
                code: Int(openResult),
                userInfo: [NSLocalizedDescriptionKey: detail])
        }
        defer { sqlite3_close_v2(handle) }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let detail = errorPointer.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(handle))
            if let errorPointer { sqlite3_free(errorPointer) }
            throw NSError(
                domain: "ESISDatabaseG2Tests.SQLite",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: detail])
        }
    }

    /// Read a single text scalar from the disposable test database.
    private func sqliteScalarText(_ url: URL, sql: String) throws -> String {
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let handle else {
            let detail = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite open failed with code \(openResult)"
            if let handle { sqlite3_close_v2(handle) }
            throw NSError(domain: "ESISDatabaseG2Tests.SQLite", code: Int(openResult),
                          userInfo: [NSLocalizedDescriptionKey: detail])
        }
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw NSError(domain: "ESISDatabaseG2Tests.SQLite", code: Int(prepareResult),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            throw NSError(domain: "ESISDatabaseG2Tests.SQLite", code: Int(sqlite3_errcode(handle)),
                          userInfo: [NSLocalizedDescriptionKey: "Expected a non-null text scalar"])
        }
        return String(cString: text)
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

    func testFileReplacementImmediatelyBeforeCommitRollsBackNoOpScan() throws {
        let (databaseURL, db) = try open("file-replaced-before-commit")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-file-commit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            db.close()
            cleanup(databaseURL)
        }

        let source = rootURL.appendingPathComponent("source.txt")
        try Data("stable source bytes".utf8).write(to: source)
        _ = try db.settleWorkRootContents(
            rootID: "file-commit-pinned", rootURL: rootURL)
        let baselineDigest = try XCTUnwrap(
            try db.externalFileDigest(rootID: "file-commit-pinned", relativePath: "source.txt"))
        let settlement = try mkSettlement(
            db, stateID: "S-COMMIT-PINNED-FILE", value: "stable")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "file-commit-pinned", relativePath: "source.txt")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")

        // This is deliberately a no-op scan: the first read matches the stored
        // digest, so no pending settlement or invalidation would otherwise occur.
        var didReplace = false
        var mutationError: Error?
        db.beforeRootScanCommitForTesting = {
            didReplace = true
            do {
                try Data("replacement bytes".utf8).write(to: source, options: .atomic)
            } catch {
                mutationError = error
            }
        }

        let report = try db.settleWorkRootContents(
            rootID: "file-commit-pinned", rootURL: rootURL)
        XCTAssertTrue(didReplace, "the replacement must occur after the no-op scan read")
        XCTAssertNil(mutationError)
        XCTAssertNil(db.beforeRootScanCommitForTesting)
        XCTAssertEqual(try Data(contentsOf: source), Data("replacement bytes".utf8))

        // The raced first snapshot is rolled back, then the bounded retry
        // settles the new bytes and invalidates the old dependent settlement.
        XCTAssertEqual(report.scanned, 1)
        XCTAssertEqual(report.changed, 1)
        XCTAssertEqual(report.invalidatedSettlements, 1)
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "file-commit-pinned").map(\.relativePath),
            ["source.txt"])
        XCTAssertEqual(
            try db.externalFileDigest(rootID: "file-commit-pinned", relativePath: "source.txt"),
            NativeSHA256.hexDigest(Data("replacement bytes".utf8)))
        XCTAssertEqual(
            try db.carriedFileContent(
                rootID: "file-commit-pinned", relativePath: "source.txt")?.content,
            Data("replacement bytes".utf8))
        XCTAssertNotEqual(
            try db.externalFileDigest(rootID: "file-commit-pinned", relativePath: "source.txt"),
            baselineDigest)
        XCTAssertEqual(try db.settlementValidity(settlement), "invalid")
        XCTAssertEqual(try db.validSettlementCount(), 0)
    }

    func testSameInodeRewriteWithRestoredMtimeImmediatelyBeforeCommitIsResettled() throws {
        let (databaseURL, db) = try open("same-inode-rewrite-before-commit")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-same-inode-commit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            db.close()
            cleanup(databaseURL)
        }

        let source = rootURL.appendingPathComponent("source.txt")
        let original = Data("original same length".utf8)
        let replacement = Data("modified same length".utf8)
        XCTAssertEqual(original.count, replacement.count)
        try original.write(to: source)
        _ = try db.settleWorkRootContents(
            rootID: "same-inode-commit-root", rootURL: rootURL)
        let baselineDigest = try XCTUnwrap(
            try db.externalFileDigest(
                rootID: "same-inode-commit-root", relativePath: "source.txt"))
        let settlement = try mkSettlement(
            db, stateID: "S-SAME-INODE-COMMIT", value: "old source")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "same-inode-commit-root", relativePath: "source.txt")

        var before = stat()
        XCTAssertEqual(
            source.path.withCString { Darwin.fstatat(AT_FDCWD, $0, &before, 0) }, 0)
        var didRewrite = false
        var sameIdentityAndSize = false
        var mtimeRestored = false
        var ctimeChanged = false
        var mutationError: Error?
        db.beforeRootScanCommitForTesting = {
            didRewrite = true
            do {
                let writer = try FileHandle(forWritingTo: source)
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
                    source.path.withCString {
                        Darwin.utimensat(AT_FDCWD, $0, buffer.baseAddress, 0)
                    }
                }
                guard restoreResult == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                var after = stat()
                guard source.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &after, 0) }) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                sameIdentityAndSize = before.st_dev == after.st_dev
                    && before.st_ino == after.st_ino
                    && before.st_size == after.st_size
                mtimeRestored = before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
                    && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
                ctimeChanged = before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec
                    || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec
            } catch {
                mutationError = error
            }
        }

        let report = try db.settleWorkRootContents(
            rootID: "same-inode-commit-root", rootURL: rootURL)
        XCTAssertTrue(didRewrite)
        XCTAssertNil(mutationError)
        XCTAssertTrue(sameIdentityAndSize, "the probe must preserve inode and size")
        XCTAssertTrue(mtimeRestored, "the probe must restore the original mtime")
        XCTAssertTrue(ctimeChanged, "the in-place rewrite must change ctime")
        XCTAssertEqual(report.changed, 1)
        XCTAssertEqual(report.invalidatedSettlements, 1)
        XCTAssertEqual(
            try db.externalFileDigest(
                rootID: "same-inode-commit-root", relativePath: "source.txt"),
            NativeSHA256.hexDigest(replacement))
        XCTAssertNotEqual(
            try db.externalFileDigest(
                rootID: "same-inode-commit-root", relativePath: "source.txt"),
            baselineDigest)
        XCTAssertEqual(
            try db.carriedFileContent(
                rootID: "same-inode-commit-root", relativePath: "source.txt")?.content,
            replacement)
        XCTAssertEqual(try db.settlementValidity(settlement), "invalid")
    }

    func testDetachedSnapshotRevalidatesItsOriginalInodeBeforeCommit() throws {
        let (databaseURL, db) = try open("detached-snapshot-rewrite-before-commit")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-detached-commit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            db.close()
            cleanup(databaseURL)
        }

        let source = rootURL.appendingPathComponent("source.txt")
        let moved = rootURL.appendingPathComponent("moved.txt")
        let original = Data("original same length".utf8)
        let replacement = Data("modified same length".utf8)
        try original.write(to: source)
        _ = try db.settleWorkRootContents(
            rootID: "detached-commit-root", rootURL: rootURL)
        let settlement = try mkSettlement(
            db, stateID: "S-DETACHED-COMMIT", value: "old source")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "detached-commit-root", relativePath: "source.txt")

        var beforeRename = stat()
        XCTAssertEqual(
            source.path.withCString { Darwin.fstatat(AT_FDCWD, $0, &beforeRename, 0) }, 0)
        var afterRename = stat()
        var didRename = false
        var didRewrite = false
        var ctimeChangedAfterRead = false
        var mutationError: Error?
        db.beforeRootFileVerificationForTesting = {
            didRename = true
            do {
                let result = source.path.withCString { from in
                    moved.path.withCString { to in Darwin.rename(from, to) }
                }
                guard result == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                guard moved.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &afterRename, 0) }) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
            } catch {
                mutationError = error
            }
        }
        db.beforeRootScanCommitForTesting = {
            didRewrite = true
            do {
                let writer = try FileHandle(forWritingTo: moved)
                try writer.seek(toOffset: 0)
                try writer.write(contentsOf: replacement)
                try writer.close()
                var times = [
                    timespec(tv_sec: beforeRename.st_atimespec.tv_sec,
                             tv_nsec: beforeRename.st_atimespec.tv_nsec),
                    timespec(tv_sec: beforeRename.st_mtimespec.tv_sec,
                             tv_nsec: beforeRename.st_mtimespec.tv_nsec),
                ]
                let restoreResult = times.withUnsafeBufferPointer { buffer in
                    moved.path.withCString {
                        Darwin.utimensat(AT_FDCWD, $0, buffer.baseAddress, 0)
                    }
                }
                guard restoreResult == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                var afterRewrite = stat()
                guard moved.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &afterRewrite, 0) }) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                ctimeChangedAfterRead =
                    afterRename.st_ctimespec.tv_sec != afterRewrite.st_ctimespec.tv_sec
                    || afterRename.st_ctimespec.tv_nsec != afterRewrite.st_ctimespec.tv_nsec
            } catch {
                mutationError = error
            }
        }

        let report = try db.settleWorkRootContents(
            rootID: "detached-commit-root", rootURL: rootURL)
        XCTAssertTrue(didRename)
        XCTAssertTrue(didRewrite)
        XCTAssertNil(mutationError)
        XCTAssertTrue(ctimeChangedAfterRead)
        XCTAssertEqual(report.removed, 0,
                       "the scan cannot infer that the old path was deleted")
        XCTAssertEqual(report.invalidatedSettlements, 0,
                       "a new path is not implicitly the old source identity")
        XCTAssertEqual(
            try db.externalFileDigest(
                rootID: "detached-commit-root", relativePath: "moved.txt"),
            NativeSHA256.hexDigest(replacement))
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
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

    func testG2ReconcileDoesNotInferDeletionFromDirectoryAbsence() throws {
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
        XCTAssertTrue(invalidated.isEmpty)
        XCTAssertEqual(try db.settlementValidity(sa), "valid")
        XCTAssertEqual(try db.settlementValidity(sb), "valid")
        XCTAssertTrue(try db.listExternalFiles(rootID: "work")
                        .contains(where: { $0.relativePath == "gone.md" && $0.status == "present" }))
    }

    func testExplicitSourceMoveDoesNotTreatDifferentFileDigestAsContentRevision() throws {
        let (url, db) = try open("explicit-move-different-file-digest")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(
            rootID: "move-root", relativePath: "old.md", kind: "md",
            size: 100, modifiedAt: nil, contentDigest: "container-digest-v1")
        let dependencyID = try db.externalSourceDependencyID(
            rootID: "move-root", relativePath: "old.md")
        let settlement = try mkSettlement(
            db, stateID: "S-MOVE-DIFFERENT-FILE-DIGEST", value: "pinned item")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "move-root", relativePath: "old.md")
        // Dependency history addresses must reference a real immutable IS object.
        // Reuse this settlement's stored payload object rather than a made-up address.
        let pinnedObjectID = try sqliteScalarText(
            url,
            sql: """
            SELECT payload_object_id FROM settlements
             WHERE settlement_id='\(settlement)';
            """)
        XCTAssertFalse(pinnedObjectID.isEmpty)
        XCTAssertEqual(
            try db.appendDependency(
                dependencyID: dependencyID, contentAddress: pinnedObjectID,
                reason: "initial-item-observation"),
            1)

        // The agent has declared that this is the same source at a new location.
        // The container bytes changed (e.g. format/save metadata), so the file
        // digest differs. Only the next actual item read may decide whether the
        // pinned item changed; relocating the dependency must not invalidate it.
        try db.indexExternalFile(
            rootID: "move-root", relativePath: "new.md", kind: "md",
            size: 140, modifiedAt: nil, contentDigest: "container-digest-v2")
        try db.moveExternalSourceDependency(
            dependencyID: dependencyID, toRootID: "move-root",
            toRelativePath: "new.md", reason: "agent-confirmed-same-source-move")

        XCTAssertEqual(
            try db.externalSourceDependencyID(rootID: "move-root", relativePath: "new.md"),
            dependencyID)
        let history = try db.externalSourceLocationHistory(dependencyID: dependencyID)
        XCTAssertEqual(history.map { $0.action }, ["attach", "detach", "attach"])
        XCTAssertEqual(history.map { $0.relativePath }, ["old.md", "old.md", "new.md"])
        let revisions = try db.dependencyHistory(dependencyID)
        XCTAssertEqual(revisions.map { $0.revision }, [1])
        XCTAssertEqual(revisions.last?.contentAddress, "pinned-item-address")
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
    }

    func testRemoveRootPreservesSourceBoundSettlementValidityAndHistory() throws {
        let (url, db) = try open("remove-root-dependencies")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-remove-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            db.close()
            cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }

        let source = root.appendingPathComponent("source.md")
        try Data("needle in original source".utf8).write(to: source)
        _ = try db.settleWorkRootContents(
            rootID: "remove-root", rootURL: root, carryText: false)
        let sourceDependencyID = try db.externalSourceDependencyID(
            rootID: "remove-root", relativePath: "source.md")
        let digest = try XCTUnwrap(
            try db.externalFileDigest(rootID: "remove-root", relativePath: "source.md"))

        let sourceSettlement = try mkSettlement(
            db, stateID: "S-REMOVE-ROOT-SOURCE", value: "source")
        try db.linkSettlementToExternalFile(
            settlementID: sourceSettlement, binding: "content",
            rootID: "remove-root", relativePath: "source.md")

        let retrieval = try db.recordInformationRetrieval(.init(
            demandID: "demand-remove-root",
            stateID: nil,
            sessionID: "session-remove-root",
            requestIdentity: "request-remove-root",
            query: "needle",
            rootIDs: ["remove-root"],
            includeChat: false,
            inputDigest: "basis-remove-root",
            payload: Data("retrieval result".utf8),
            hitCount: 1,
            itemIDs: ["file:remove-root/source.md"],
            inputs: [],
            sourceBindings: [.init(
                rootID: "remove-root", relativePath: "source.md",
                expectedDigest: digest)]))

        let downstream = try mkSettlement(
            db, stateID: "S-REMOVE-ROOT-DOWNSTREAM", value: "downstream")
        try db.addDependency(
            fromSettlement: downstream,
            toSettlement: retrieval.retrievalSettlementID)
        let unrelated = try mkSettlement(
            db, stateID: "S-REMOVE-ROOT-UNRELATED", value: "unrelated")

        XCTAssertEqual(try db.validSettlementCount(), 4)
        try db.removeRoot(rootID: "remove-root")

        XCTAssertTrue(try db.listRoots().isEmpty)
        XCTAssertTrue(try db.listExternalFiles(rootID: "remove-root").isEmpty)
        XCTAssertEqual(try db.settlementValidity(sourceSettlement), "valid")
        XCTAssertEqual(
            try db.settlementValidity(retrieval.retrievalSettlementID), "valid")
        XCTAssertEqual(try db.settlementValidity(downstream), "valid")
        XCTAssertEqual(try db.settlementValidity(unrelated), "valid")
        XCTAssertEqual(
            try db.informationRetrievalPayload(demandID: "demand-remove-root"),
            Data("retrieval result".utf8))
        XCTAssertEqual(
            try db.externalSourceLocationHistory(dependencyID: sourceDependencyID).last?.action,
            "detach", "root removal leaves a source-location tombstone")
        XCTAssertEqual(try db.count("settlements"), 4, "root removal preserves settlement history")

        // Re-registering the root creates a new source observation; it does not
        // rewrite the historical dependency pinned by the old settlements.
        try Data("changed source after re-registration".utf8).write(to: source)
        _ = try db.settleWorkRootContents(
            rootID: "remove-root", rootURL: root, carryText: false)
        XCTAssertEqual(try db.settlementValidity(sourceSettlement), "valid")
        XCTAssertEqual(
            try db.settlementValidity(retrieval.retrievalSettlementID), "valid")
        XCTAssertEqual(try db.settlementValidity(downstream), "valid")
    }

    func testV42MigrationInvalidatesAmbiguousV41RootScopeAndDependencyClosure() throws {
        let (url, db) = try open("v42-legacy-root-scope-migration")
        defer {
            db.close()
            cleanup(url)
        }

        let ambiguousRootID = #"json-v1:["archive"]"#
        try db.upsertRoot(
            rootID: ambiguousRootID, category: "work",
            displayName: nil, locatorType: "path", status: "present")

        let retrieval = try db.recordInformationRetrieval(.init(
            demandID: "demand-v41-prefix-migration",
            stateID: nil,
            sessionID: "session-v41-prefix-migration",
            requestIdentity: "request-v41-prefix-migration",
            query: "legacy prefix migration",
            rootIDs: [ambiguousRootID],
            includeChat: false,
            inputDigest: "basis-v41-prefix-migration",
            payload: Data("legacy ambiguous retrieval".utf8),
            hitCount: 0,
            itemIDs: [],
            inputs: []))
        let downstream = try mkSettlement(
            db, stateID: "S-V42-MIGRATION-DOWNSTREAM", value: "downstream")
        try db.addDependency(
            fromSettlement: downstream,
            toSettlement: retrieval.retrievalSettlementID)

        let unrelated = try db.recordInformationRetrieval(.init(
            demandID: "demand-v41-unaffected-migration",
            stateID: nil,
            sessionID: "session-v41-unaffected-migration",
            requestIdentity: "request-v41-unaffected-migration",
            query: "unaffected legacy migration",
            rootIDs: ["ordinary-root"],
            includeChat: false,
            inputDigest: "basis-v41-unaffected-migration",
            payload: Data("unambiguous retrieval remains valid".utf8),
            hitCount: 0,
            itemIDs: [],
            inputs: []))

        XCTAssertEqual(try db.schemaVersion(), ESISDatabase.currentSchemaVersion)
        XCTAssertEqual(try db.settlementValidity(retrieval.retrievalSettlementID), "valid")
        XCTAssertEqual(try db.settlementValidity(downstream), "valid")
        XCTAssertEqual(try db.settlementValidity(unrelated.retrievalSettlementID), "valid")

        // Rewind the v42-specific shape and every later version marker on this
        // disposable database. Keeping v43 in the migration ledger would make
        // MAX(version) stay above 42 and skip the v42 repair gate entirely.
        // All remaining tables and data were produced by the real v41+ path.
        let escapedRootID = ambiguousRootID.replacingOccurrences(of: "'", with: "''")
        db.close()
        try executeRawSQLite(url, sql: """
            UPDATE retrieval_settlements
               SET root_ids = '\(escapedRootID)',
                   root_ids_json = NULL,
                   bridged_settlement_id = '\(retrieval.retrievalSettlementID)'
             WHERE demand_id = 'demand-v41-prefix-migration';
            ALTER TABLE retrieval_settlements DROP COLUMN root_ids_json;
            DELETE FROM schema_migrations WHERE version >= 42;
            """)

        let upgraded = try ESISDatabase(url: url, createIfNeeded: false)
        defer { upgraded.close() }
        try upgraded.runMigrations()

        XCTAssertEqual(try upgraded.schemaVersion(), ESISDatabase.currentSchemaVersion)
        XCTAssertEqual(ESISDatabase.currentSchemaVersion, 51)
        XCTAssertEqual(
            try upgraded.settlementValidity(retrieval.retrievalSettlementID), "invalid",
            "ambiguous v41 root-scope cache must be invalidated during migration")
        XCTAssertEqual(
            try upgraded.settlementValidity(downstream), "invalid",
            "the bridged settlement dependency closure must also be invalidated")
        XCTAssertEqual(
            try upgraded.settlementValidity(unrelated.retrievalSettlementID), "valid",
            "unambiguous v41 retrieval rows must remain valid")
        XCTAssertNil(
            try upgraded.informationRetrievalPayload(demandID: "demand-v41-prefix-migration"))
    }

    func testRemoveRootMatchesCommaContainingRootIDsExactly() throws {
        let (url, db) = try open("remove-root-comma-id")
        defer { db.close(); cleanup(url) }

        // Legacy CSV cannot distinguish one delimiter-bearing root from
        // two adjacent roots. The compatibility path must fail closed for the
        // full comma-token sequence (over-invalidation is preferable to stale IS).
        XCTAssertTrue(ESISDatabase.retrievalScopeIncludesRoot(
            "project,archive", rootID: "project,archive"))
        XCTAssertTrue(ESISDatabase.retrievalScopeIncludesRoot(
            "project,archive", rootID: "archive"))
        XCTAssertTrue(ESISDatabase.retrievalScopeIncludesRoot(
            #"["archive"]"#, rootID: #"["archive"]"#))
        XCTAssertFalse(ESISDatabase.retrievalScopeIncludesRoot(
            "project,archive", rootID: "projected"))

        // A legacy opaque root ID may collide with the former JSON version
        // prefix and still be a literal CSV value, not an encoded scope.
        let prefixedRootID = #"json-v1:["archive"]"#
        XCTAssertTrue(ESISDatabase.retrievalScopeIncludesRoot(
            prefixedRootID, rootID: prefixedRootID))
        XCTAssertFalse(ESISDatabase.retrievalScopeIncludesRoot(
            prefixedRootID, rootID: "archive"))

        // The explicit JSON column is unambiguous even when IDs contain commas.
        XCTAssertTrue(ESISDatabase.retrievalScopeIncludesRoot(
            legacyStoredRootIDs: "", jsonStoredRootIDs: #"["project,archive"]"#,
            rootID: "project,archive"))
        XCTAssertFalse(ESISDatabase.retrievalScopeIncludesRoot(
            legacyStoredRootIDs: "", jsonStoredRootIDs: #"["project,archive"]"#,
            rootID: "archive"))

        let jsonLookingRootID = #"["archive"]"#
        try db.upsertRoot(
            rootID: "project,archive", category: "work",
            displayName: nil, locatorType: "path", status: "present")
        try db.upsertRoot(
            rootID: jsonLookingRootID, category: "work",
            displayName: nil, locatorType: "path", status: "present")
        try db.upsertRoot(
            rootID: "archive", category: "work",
            displayName: nil, locatorType: "path", status: "present")
        try db.upsertRoot(
            rootID: prefixedRootID, category: "work",
            displayName: nil, locatorType: "path", status: "present")

        let commaRetrieval = try db.recordInformationRetrieval(.init(
            demandID: "demand-comma-root-id",
            stateID: nil,
            sessionID: "session-comma-root-id",
            requestIdentity: "request-comma-root-id",
            query: "comma root",
            rootIDs: ["project,archive"],
            includeChat: false,
            inputDigest: "basis-comma-root-id",
            payload: Data("result scoped to one opaque root ID".utf8),
            hitCount: 0,
            itemIDs: [],
            inputs: []))
        let jsonLookingRetrieval = try db.recordInformationRetrieval(.init(
            demandID: "demand-json-looking-root-id",
            stateID: nil,
            sessionID: "session-json-looking-root-id",
            requestIdentity: "request-json-looking-root-id",
            query: "json-looking root",
            rootIDs: [jsonLookingRootID],
            includeChat: false,
            inputDigest: "basis-json-looking-root-id",
            payload: Data("result scoped to a JSON-looking legacy ID".utf8),
            hitCount: 0,
            itemIDs: [],
            inputs: []))
        let prefixedRetrieval = try db.recordInformationRetrieval(.init(
            demandID: "demand-version-prefix-root-id",
            stateID: nil,
            sessionID: "session-version-prefix-root-id",
            requestIdentity: "request-version-prefix-root-id",
            query: "version prefix root",
            rootIDs: [prefixedRootID],
            includeChat: false,
            inputDigest: "basis-version-prefix-root-id",
            payload: Data("result scoped to a literal version-prefix root ID".utf8),
            hitCount: 0,
            itemIDs: [],
            inputs: []))

        // Removing a different root whose text is a CSV suffix must not
        // invalidate a result scoped only to "project,archive". Nor may a
        // legacy ID that happens to look like a JSON array be parsed as JSON.
        try db.removeRoot(rootID: "archive")
        XCTAssertEqual(
            try db.settlementValidity(commaRetrieval.retrievalSettlementID), "valid")
        XCTAssertEqual(
            try db.settlementValidity(jsonLookingRetrieval.retrievalSettlementID), "valid")
        XCTAssertEqual(
            try db.settlementValidity(prefixedRetrieval.retrievalSettlementID), "valid",
            "the literal prefixed root is distinct from the root ID inside its JSON-looking text")

        // Removing complete opaque identifiers still preserves historical
        // retrievals; reachability is not a content revision.
        try db.removeRoot(rootID: "project,archive")
        XCTAssertEqual(
            try db.settlementValidity(commaRetrieval.retrievalSettlementID), "valid")
        try db.removeRoot(rootID: jsonLookingRootID)
        XCTAssertEqual(
            try db.settlementValidity(jsonLookingRetrieval.retrievalSettlementID), "valid")
        try db.removeRoot(rootID: prefixedRootID)
        XCTAssertEqual(
            try db.settlementValidity(prefixedRetrieval.retrievalSettlementID), "valid",
            "a literal version-prefix root ID must invalidate only its own result")
    }

    func testRemoveRootRollsBackInvalidationWhenAgentSessionRestrictsDelete() throws {
        let (url, db) = try open("remove-root-rollback")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(
            rootID: "blocked-root", relativePath: "source.md", kind: "md",
            size: 6, modifiedAt: nil, contentDigest: "digest-v1")
        let settlement = try mkSettlement(
            db, stateID: "S-REMOVE-ROOT-BLOCKED", value: "stable")
        try db.linkSettlementToExternalFile(
            settlementID: settlement, binding: "content",
            rootID: "blocked-root", relativePath: "source.md")
        try db.indexAgentSession(
            sessionID: "blocking-session", adapterID: "test",
            sourceRootID: "blocked-root", metadataDigest: "session-v1")

        XCTAssertThrowsError(try db.removeRoot(rootID: "blocked-root"))
        XCTAssertTrue(
            try db.listRoots().contains(where: { $0.rootID == "blocked-root" }))
        XCTAssertEqual(
            try db.listExternalFiles(rootID: "blocked-root").map(\.relativePath),
            ["source.md"])
        XCTAssertEqual(try db.settlementValidity(settlement), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1)
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
