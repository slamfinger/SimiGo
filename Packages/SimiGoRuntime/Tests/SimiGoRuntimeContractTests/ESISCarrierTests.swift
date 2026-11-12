import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// v8 physical carrier: content-addressed objects, append-only identity and
/// dependency history, and the guarantee that every carried IS row points at
/// verified bytes instead of an inline copy.
final class ESISCarrierTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-carrier-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeWorkRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-carrier-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Enumerator URLs use the /private/var form; resolve the root so the
        // relative-path prefix check matches.
        return root.resolvingSymlinksInPath()
    }

    private func write(_ text: String, to root: URL, name: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(name))
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private static let contract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#

    @discardableResult
    private func mkSettlement(_ db: ESISDatabase, stateID: String, value: String) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "RESULT=\(value)", contractJSON: Data(Self.contract.utf8),
            verifiedBindings: ["next_input": .string(value)])
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    func testCarrierTablesRejectUpdateAndDelete() throws {
        let (url, db) = try open("append-only")
        defer { db.close(); cleanup(url) }

        let id = try db.writeObject(Data("immutable".utf8))
        try db.appendIndexEntry(identity: "x", objectID: id)
        try db.appendDependency(dependencyID: "d", contentAddress: id, reason: "r")
        XCTAssertThrowsError(try rawExec(url, "UPDATE is_objects SET byte_size=0 WHERE object_id='\(id)';"))
        XCTAssertThrowsError(try rawExec(url, "DELETE FROM is_objects WHERE object_id='\(id)';"))
        XCTAssertThrowsError(try rawExec(url, "DELETE FROM is_index_entries;"))
        XCTAssertThrowsError(try rawExec(url, "UPDATE is_dependency_entries SET reason='x';"))
        XCTAssertEqual(try db.count("is_objects"), 1)
    }

    private func rawExec(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(message)
            throw ESISDatabase.DatabaseError.sql(detail)
        }
    }

    private func rawText(_ url: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ESISDatabase.DatabaseError.sql(sql)
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    // MARK: - Objects

    func testObjectStoreIsContentAddressedAndVerified() throws {
        let (url, db) = try open("objects")
        defer { db.close(); cleanup(url) }

        let data = Data("hello carrier".utf8)
        let id = try db.writeObject(data)
        XCTAssertEqual(id, NativeSHA256.hexDigest(data))
        XCTAssertEqual(try db.writeObject(data), id, "identical bytes must dedup")

        XCTAssertEqual(try db.readObject(id), data)
        let row = try db.objectRow(id)
        XCTAssertEqual(row?.objectID, id)
        XCTAssertEqual(row?.byteSize, data.count)
        XCTAssertEqual(row?.content, data)
        XCTAssertEqual(row?.createdOrder, 1)

        let report = try db.carrierReport(deepVerify: true)
        XCTAssertEqual(report.schemaVersion, ESISDatabase.currentSchemaVersion)
        XCTAssertEqual(report.objectCount, 1)
        XCTAssertEqual(report.objectBytes, Int64(data.count))
        XCTAssertEqual(report.corruptObjects, 0)
        XCTAssertEqual(report.deepVerified, true)
    }

    func testCorruptObjectFailsClosedAndIsReported() throws {
        let (url, db) = try open("corrupt")
        defer { db.close(); cleanup(url) }

        let id = try db.writeObject(Data("hello".utf8))
        // The carrier rejects UPDATE at the SQL layer; drop the guard to
        // simulate out-of-band corruption (bit rot) and prove reads still fail
        // closed. Same length, different bytes: the CHECK constraints also pass.
        try rawExec(url, """
        DROP TRIGGER is_objects_append_only_update;
        UPDATE is_objects SET content=CAST('HELLO' AS BLOB) WHERE object_id='\(id)';
        """)

        XCTAssertThrowsError(try db.readObject(id))
        XCTAssertEqual(try db.carrierReport().corruptObjects, 0,
                       "cheap report does not re-hash bytes")
        XCTAssertEqual(try db.carrierReport(deepVerify: true).corruptObjects, 1)
    }

    // MARK: - Work-root content settlement

    func testSettleWorkRootCarriesContentAndDeduplicates() throws {
        let (url, db) = try open("settle")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("alpha", to: root, name: "a.md")
        try write("alpha", to: root, name: "b.md")
        try write("beta", to: root, name: "c.md")

        let first = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        XCTAssertEqual(first.scanned, 3)
        XCTAssertEqual(first.settled, 3)
        XCTAssertEqual(first.changed, 0, "first settlement has no prior version")
        XCTAssertEqual(first.objectsCreated, 2, "identical bytes stored once")
        XCTAssertEqual(first.deduplicated, 1)
        XCTAssertEqual(first.bytesAddressed, 14)

        let report = try db.carrierReport(deepVerify: true)
        XCTAssertEqual(report.unaddressedFileContents, 0)
        XCTAssertEqual(report.inlineLegacyPayloads, 0)
        XCTAssertEqual(report.danglingReferences, 0)
        XCTAssertEqual(report.corruptObjects, 0)

        let a = try XCTUnwrap(db.resolveIndexIdentity("file:work/a.md"))
        let b = try XCTUnwrap(db.resolveIndexIdentity("file:work/b.md"))
        XCTAssertEqual(a.objectID, b.objectID, "dedup keeps one content address")
        XCTAssertEqual(String(data: try db.readObject(a.objectID), encoding: .utf8), "alpha")

        let hits = try db.searchSettledContent(query: "alpha")
        XCTAssertEqual(Set(hits.map { $0.relativePath }), ["a.md", "b.md"])

        let second = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        XCTAssertEqual(second.reused, 3)
        XCTAssertEqual(second.settled, 0)
        XCTAssertEqual(second.objectsCreated, 0)
        XCTAssertEqual(try db.carrierReport().indexEntries, 3,
                       "unchanged rescan appends nothing new")
    }

    func testChangedAndRemovedFilesInvalidateAndAppendHistory() throws {
        let (url, db) = try open("changes")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("keep", to: root, name: "keep.md")
        try write("v1", to: root, name: "change.md")
        try write("gone", to: root, name: "gone.md")
        let settle = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        XCTAssertEqual(settle.settled, 3)

        let sChange = try mkSettlement(db, stateID: "S-CHANGE", value: "c")
        let sGone = try mkSettlement(db, stateID: "S-GONE", value: "g")
        try db.linkSettlementToExternalFile(settlementID: sChange, binding: "content",
                                            rootID: "work", relativePath: "change.md")
        try db.linkSettlementToExternalFile(settlementID: sGone, binding: "content",
                                            rootID: "work", relativePath: "gone.md")
        XCTAssertEqual(try db.currentDependency(
            "settlement:\(sChange) -> file:work/change.md")?.reason, "source-binding:content")

        let oldAddress = try XCTUnwrap(db.resolveIndexIdentity("file:work/change.md")).objectID
        try write("v2", to: root, name: "change.md")
        try FileManager.default.removeItem(at: root.appendingPathComponent("gone.md"))

        let update = try db.settleWorkRootContents(rootID: "work", rootURL: root)
        XCTAssertEqual(update.removed, 1)
        XCTAssertEqual(update.changed, 1)
        XCTAssertEqual(update.invalidatedSettlements, 2)
        XCTAssertEqual(try db.settlementValidity(sChange), "invalid")
        XCTAssertEqual(try db.settlementValidity(sGone), "invalid")

        let newAddress = try XCTUnwrap(db.resolveIndexIdentity("file:work/change.md")).objectID
        XCTAssertNotEqual(newAddress, oldAddress)
        XCTAssertEqual(String(data: try db.readObject(newAddress), encoding: .utf8), "v2")
        XCTAssertEqual(String(data: try db.readObject(oldAddress), encoding: .utf8), "v1",
                       "write-once history keeps the superseded bytes addressable")

        let history = try db.dependencyHistory("file:work/change.md")
        XCTAssertEqual(history.map { $0.reason }, ["content-settle", "content-update"])
        XCTAssertEqual(history.map { $0.revision }, [1, 2])

        let files = try db.listExternalFiles(rootID: "work")
        XCTAssertEqual(Set(files.map { $0.relativePath }), ["keep.md", "change.md", "gone.md"])
        XCTAssertEqual(files.first { $0.relativePath == "gone.md" }?.status, "missing")
        XCTAssertEqual(
            try db.count("file_contents"), 3,
            "removed content is kept: a vanished source is unreachable, not gone")

        let report = try db.carrierReport(deepVerify: true)
        XCTAssertEqual(report.unaddressedFileContents, 0)
        XCTAssertEqual(report.danglingReferences, 0)
        XCTAssertEqual(report.inlineLegacyPayloads, 0)
    }

    // MARK: - Chat and settlement payloads

    func testChatMessagesAreContentAddressed() throws {
        let (url, db) = try open("chat")
        defer { db.close(); cleanup(url) }

        try db.appendChatMessage(sessionID: "s", role: "user", content: "same",
                                 model: nil, createdAt: Date())
        try db.appendChatMessage(sessionID: "s", role: "assistant", content: "same",
                                 model: "m", createdAt: Date())

        let rows = try db.listChatMessages(sessionID: "s")
        XCTAssertEqual(rows.map { $0.content }, ["same", "same"])
        XCTAssertEqual(rows.map { $0.role }, ["user", "assistant"])

        let report = try db.carrierReport()
        XCTAssertEqual(report.objectCount, 1, "identical chat text dedups")
        XCTAssertEqual(report.unaddressedChatMessages, 0)
        XCTAssertEqual(report.inlineLegacyPayloads, 0)

        let first = try XCTUnwrap(db.resolveIndexIdentity("chat:s/1"))
        let second = try XCTUnwrap(db.resolveIndexIdentity("chat:s/2"))
        XCTAssertEqual(first.objectID, second.objectID)
    }

    func testSettlementPayloadsAndDependencyLedger() throws {
        let (url, db) = try open("settlements")
        defer { db.close(); cleanup(url) }

        let sa = try mkSettlement(db, stateID: "S-A", value: "a")
        let sb = try mkSettlement(db, stateID: "S-B", value: "b")
        let receipts = try db.readSettlementReceipts()
        XCTAssertEqual(receipts.count, 2)
        XCTAssertTrue(receipts.allSatisfy { !$0.payload.isEmpty })

        let payloadAddress = try XCTUnwrap(
            db.resolveIndexIdentity("settlement:\(sa)")).objectID
        try db.addDependency(fromSettlement: sb, toSettlement: sa)
        let dependency = try XCTUnwrap(
            db.currentDependency("settlement:\(sb) -> settlement:\(sa)"))
        XCTAssertEqual(dependency.contentAddress, payloadAddress)
        XCTAssertEqual(dependency.reason, "depends")
        XCTAssertEqual(dependency.revision, 1)

        let report = try db.carrierReport(deepVerify: true)
        XCTAssertEqual(report.unaddressedSettlements, 0)
        XCTAssertEqual(report.danglingReferences, 0)
        XCTAssertEqual(report.corruptObjects, 0)
    }

    // MARK: - Upgrade from a pre-carrier (v7) database

    func testV8BackfillMovesLegacyInlinePayloads() throws {
        let (url, db) = try open("backfill")
        // Seed inline rows the way a v7 database wrote them, then roll the
        // migration head back so the v8 backfill runs on this same file.
        try rawExec(url, """
        INSERT INTO roots(root_id, category, display_name, locator_type, status, created_at, last_scanned_at)
            VALUES('work','work',NULL,'path','present','2026-11-06T00:00:00Z','2026-11-06T00:00:00Z');
        INSERT INTO file_contents(root_id, relative_path, content_sha256, content, settled_at)
            VALUES('work','a.md','stale-digest','legacy file','2026-11-06T00:00:00Z');
        INSERT INTO external_files(
            root_id, relative_path, kind, size, modified_at, content_digest,
            indexed_at, last_seen_at, status)
            VALUES('work','a.md','md',11,NULL,'stale-digest','2026-11-06T00:00:00Z','2026-11-06T00:00:00Z','present');
        INSERT INTO chat_messages(session_id, role, content, model, content_sha256, created_at)
            VALUES('s','user','legacy chat',NULL,'stale-digest','2026-11-06T00:00:00Z');
        INSERT INTO retrieval_settlements(
            demand_id, query, root_ids, inputs_digest, result_sha256, result_json,
            hit_count, status, settled_at)
            VALUES('d','q','work','i','stale-digest',
                   '[{"rootID":"work","relativePath":"a.md","lineNo":1,"lineText":"legacy file"}]',
                   1,'valid','2026-11-06T00:00:00Z');
        INSERT INTO settlements(
            settlement_id, state_id, schema_version, payload, payload_digest, signature,
            contract_version, settled_at, validation_status)
            VALUES('11111111-1111-1111-1111-111111111111', NULL, 'v1', X'7061796C6F6164',
                   'stale-digest', NULL, 'v', '2026-11-06T00:00:00Z', 'VALID');
        DELETE FROM schema_migrations WHERE version >= 8;
        """)
        XCTAssertEqual(try db.schemaVersion(), 7)

        try db.runMigrations()
        // v8 backfill re-applies on top of the rolled-back head, then the chain
        // runs through to the current head.
        XCTAssertEqual(try db.schemaVersion(), ESISDatabase.currentSchemaVersion)

        let report = try db.carrierReport(deepVerify: true)
        XCTAssertEqual(report.unaddressedFileContents, 0)
        XCTAssertEqual(report.unaddressedChatMessages, 0)
        XCTAssertEqual(report.unaddressedRetrievalResults, 0)
        XCTAssertEqual(report.unaddressedSettlements, 0)
        XCTAssertEqual(report.inlineLegacyPayloads, 0)
        XCTAssertEqual(report.danglingReferences, 0)
        XCTAssertEqual(report.corruptObjects, 0)
        XCTAssertEqual(report.objectCount, 5)  // payload + backed-up summary object
        XCTAssertEqual(report.dependencyEntries, 1, "file backfill appends a provenance revision")

        XCTAssertEqual(try db.searchSettledContent(query: "legacy").first?.relativePath, "a.md")
        XCTAssertEqual(try db.listChatMessages(sessionID: "s").first?.content, "legacy chat")
        XCTAssertEqual(String(data: try db.readSettlementReceipts().first!.payload,
                              encoding: .utf8), "payload")
        let demand = try XCTUnwrap(db.resolveIndexIdentity("demand:d"))
        let hits = try JSONDecoder().decode([ESISDatabase.ContentHit].self,
                                            from: try db.readObject(demand.objectID))
        XCTAssertEqual(hits.first?.lineText, "legacy file")
        XCTAssertEqual(try db.resolveIndexIdentity("file:work/a.md")?.objectID,
                       try db.externalFileDigest(rootID: "work", relativePath: "a.md"))
        db.close()
        cleanup(url)
    }

    // MARK: - Demand results

    func testDemandCacheDoesNotReuseAStalePhysicalLocatorResult() throws {
        let url = tempURL("stale-physical-cache")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-stale-physical-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            cleanup(url)
        }
        try Data("needle is initially here".utf8).write(
            to: root.appendingPathComponent("source.md"))
        let db = try ESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()
        _ = try db.settleWorkRootContents(rootID: "stale-cache-root", rootURL: root, carryText: false)
        let first = try db.executeInformationDemand(
            query: "needle", rootID: "stale-cache-root", limit: 10)
        XCTAssertEqual(first.hits.count, 1)
        XCTAssertFalse(first.reused)

        // Change physical bytes without advancing the settled root revision.
        try Data("different content".utf8).write(
            to: root.appendingPathComponent("source.md"))
        XCTAssertThrowsError(
            try db.executeInformationDemand(
                query: "needle", rootID: "stale-cache-root", limit: 10),
            "a stale physical source must fail closed before publishing a new retrieval")
        XCTAssertEqual(
            try db.count("retrieval_settlements"), 1,
            "the stale demand must not append or replace a retrieval settlement")
    }

    func testDemandResultIsCarriedAndReused() throws {
        let (url, db) = try open("demand")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle body", to: root, name: "doc.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let first = try db.executeInformationDemand(query: "needle", rootID: "work")
        XCTAssertFalse(first.reused)
        XCTAssertEqual(first.hits.count, 1)
        XCTAssertEqual(first.status, "settled")

        let second = try db.executeInformationDemand(query: "needle", rootID: "work")
        XCTAssertTrue(second.reused)
        XCTAssertEqual(second.demandID, first.demandID)
        XCTAssertEqual(second.resultSHA256, first.resultSHA256)
        XCTAssertEqual(second.hits, first.hits)

        let entry = try XCTUnwrap(db.resolveIndexIdentity("demand:\(first.demandID)"))
        let resultData = try db.readObject(entry.objectID)
        XCTAssertEqual(NativeSHA256.hexDigest(resultData), first.resultSHA256)
        // 候选不写依赖表：一条 demand 的 canonical input 是整个根的文件清单
        // （实测约 700 条），把它们写进依赖边，184k 条里 99% 都是候选清单。
        XCTAssertNil(
            try db.currentDependency("demand:\(first.demandID) -> file:work/doc.md"))

        let report = try db.carrierReport(deepVerify: true)
        XCTAssertEqual(report.unaddressedRetrievalResults, 0)
        XCTAssertEqual(report.inlineLegacyPayloads, 0)

        try write("different body", to: root, name: "doc.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root)
        XCTAssertEqual(try rawText(url,
            "SELECT status FROM retrieval_settlements WHERE demand_id='\(first.demandID)';"),
            "invalidated")

        let third = try db.executeInformationDemand(query: "needle", rootID: "work")
        XCTAssertNotEqual(third.demandID, first.demandID)
        XCTAssertFalse(third.reused, "a changed input digest forces a new demand")
    }

    // MARK: - Read-back and reconciliation

    func testRegisteredRootPathAndScanEvidenceSurviveSettlement() throws {
        let (url, db) = try open("root-evidence")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("evidence", to: root, name: "a.md")
        try db.upsertRoot(rootID: "work", category: "work",
                          displayName: root.path, locatorType: "path", status: "present")
        try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let row = try XCTUnwrap(db.listRoots(category: "work").first)
        XCTAssertEqual(row.displayName, root.path,
                       "settlement must not erase the registered locator")
        XCTAssertEqual(row.status, "present")
        XCTAssertFalse(try rawText(url,
            "SELECT last_scanned_at FROM roots WHERE root_id='work';").isEmpty)
        XCTAssertFalse(try rawText(url,
            "SELECT modified_at FROM external_files WHERE root_id='work' AND relative_path='a.md';").isEmpty,
            "source version evidence is recorded")
    }

    func testReconcileSkipsFreshRootsAndDetectsChanges() throws {
        let (url, db) = try open("reconcile")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("one", to: root, name: "a.md")
        try db.upsertRoot(rootID: "work", category: "work",
                          displayName: root.path, locatorType: "path", status: "present")
        try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let fresh = try db.reconcileRegisteredRoots(minAgeSeconds: 600)
        XCTAssertEqual(fresh.freshRoots, 1)
        XCTAssertEqual(fresh.settledRoots, 0)

        try write("two", to: root, name: "a.md")
        let forced = try db.reconcileRegisteredRoots()
        XCTAssertEqual(forced.settledRoots, 1)
        XCTAssertEqual(forced.changed, 1)
        XCTAssertEqual(forced.scanned, 1)
    }

    func testReconcileConvertsCarriedRowsToIndexOnly() throws {
        let (url, db) = try open("reconcile-index-only")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle bytes", to: root, name: "a.md")
        try db.upsertRoot(rootID: "work", category: "work",
                          displayName: root.path, locatorType: "path", status: "present")
        let carried = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: true)
        XCTAssertGreaterThan(carried.bytesAddressed, 0)

        let report = try db.reconcileRegisteredRoots()
        XCTAssertEqual(report.settledRoots, 1)
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM file_contents WHERE object_id IS NOT NULL;"), "0",
            "reconcile settles index-only by default and drops the copied bytes")

        // The locator still answers: the digest is re-verified on every read.
        let hits = try db.searchSettledContent(query: "needle", rootID: "work")
        XCTAssertEqual(hits.map { $0.relativePath }, ["a.md"])
        XCTAssertEqual(try db.carrierReport().unaddressedFileContents, 0,
                       "index-only rows are addressed by their metadata record")
    }

    func testReconcileMarksMissingRootWithoutClearingContent() throws {
        let (url, db) = try open("missing-root")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("keep me", to: root, name: "a.md")
        try db.upsertRoot(rootID: "work", category: "work",
                          displayName: root.path, locatorType: "path", status: "present")
        try db.settleWorkRootContents(rootID: "work", rootURL: root)

        try FileManager.default.removeItem(at: root)
        let report = try db.reconcileRegisteredRoots()
        XCTAssertEqual(report.missingRoots, 1)
        XCTAssertEqual(report.settledRoots, 0)
        XCTAssertEqual(try db.listRoots(category: "work").first?.status, "missing")

        // An unmounted root must not read as mass deletion: carried bytes stay.
        XCTAssertEqual(try db.carriedFileContent(rootID: "work", relativePath: "a.md")?
                        .content, Data("keep me".utf8))
        XCTAssertEqual(try db.count("file_contents"), 1)
    }

    func testSettlementReceiptReturnsVerifiedPayloadAndDependencies() throws {
        let (url, db) = try open("receipt")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("source body", to: root, name: "src.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let settlementID = try mkSettlement(db, stateID: "S-1", value: "answer")
        try db.linkSettlementToExternalFile(
            settlementID: settlementID, binding: "source",
            rootID: "work", relativePath: "src.md")

        let receipt = try XCTUnwrap(db.settlementReceipt(settlementID))
        let payloadJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: receipt.payload) as? [String: Any])
        XCTAssertEqual(payloadJSON["content"] as? String, "answer")
        XCTAssertEqual(receipt.payloadSHA256, NativeSHA256.hexDigest(receipt.payload))
        XCTAssertNotNil(receipt.payloadObjectID)
        XCTAssertEqual(receipt.validity, "valid")
        XCTAssertEqual(receipt.stateID, "S-1")
        XCTAssertEqual(receipt.bindings["source"], "source")
        let dependency = try XCTUnwrap(receipt.dependencies.first)
        XCTAssertTrue(dependency.dependencyID.hasPrefix("settlement:\(settlementID) -> file:work/src.md"))
        XCTAssertEqual(dependency.revision, 1)

        XCTAssertNil(try db.settlementReceipt("no-such-settlement"))
    }

    func testSettlementReceiptFailsClosedWhenPayloadObjectIsCorrupt() throws {
        let (url, db) = try open("receipt-corrupt")
        defer { db.close(); cleanup(url) }

        let settlementID = try mkSettlement(db, stateID: "S-1", value: "answer")
        let receipt = try XCTUnwrap(db.settlementReceipt(settlementID))
        let objectID = try XCTUnwrap(receipt.payloadObjectID)
        // Same length as the stored payload so the CHECK constraints still pass
        // and only the address check can catch the tampering.
        let tamper = String(repeating: "X", count: receipt.payload.count)
        try rawExec(url, """
        DROP TRIGGER is_objects_append_only_update;
        UPDATE is_objects SET content=CAST('\(tamper)' AS BLOB) WHERE object_id='\(objectID)';
        """)
        XCTAssertThrowsError(try db.settlementReceipt(settlementID),
                             "a receipt must not carry bytes that fail hash verification")
        XCTAssertFalse(try db.verifyObject(objectID))
    }

    func testCarriedFileContentReadsBackAndVerifies() throws {
        let (url, db) = try open("file-readback")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("read me", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root)

        let content = try XCTUnwrap(
            db.carriedFileContent(rootID: "work", relativePath: "a.md"))
        XCTAssertEqual(String(data: content.content, encoding: .utf8), "read me")
        XCTAssertEqual(content.contentSHA256, NativeSHA256.hexDigest(content.content))
        XCTAssertEqual(content.status, "present")
        XCTAssertTrue(try db.verifyObject(try XCTUnwrap(content.objectID)))
        XCTAssertNil(try db.carriedFileContent(rootID: "work", relativePath: "missing.md"))
    }

    // MARK: - Goal step 4 / injection (a): dependency change is a LOCAL closure

    /// Append bytes to file A, re-settle, and prove the invalidation closure is
    /// exactly A's dependents: A's dependency revision for `file:<root>/A`
    /// increments (append-only history), only A-linked settlements flip to
    /// invalid, and the unchanged sibling B keeps revision 1, the same content
    /// address and the same verified settled bytes. The changed settlement is
    /// then refused (not reused) by the IS read paths.
    func testAppendToDependencyFileIncrementsRevisionAndLeavesUnchangedSiblingIntact() throws {
        let (url, db) = try open("append-sibling")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("A-v1", to: root, name: "A")
        try write("B-stable", to: root, name: "B")
        try db.upsertRoot(rootID: "workA", category: "work",
                          displayName: root.path, locatorType: "path", status: "present")
        _ = try db.settleWorkRootContents(rootID: "workA", rootURL: root)

        let sA = try mkSettlement(db, stateID: "S-APP-A", value: "a")
        let sB = try mkSettlement(db, stateID: "S-APP-B", value: "b")
        try db.linkSettlementToExternalFile(settlementID: sA, binding: "content",
                                            rootID: "workA", relativePath: "A")
        try db.linkSettlementToExternalFile(settlementID: sB, binding: "content",
                                            rootID: "workA", relativePath: "B")

        let depA = "file:workA/A", depB = "file:workA/B"
        XCTAssertEqual(try db.dependencyHistory(depA).map { $0.revision }, [1])
        XCTAssertEqual(try db.dependencyHistory(depA).first?.reason, "content-settle")
        let bHistoryBefore = try db.dependencyHistory(depB)
        XCTAssertEqual(bHistoryBefore.map { $0.revision }, [1])
        let bObjectBefore = try XCTUnwrap(db.resolveIndexIdentity(depB)).objectID
        let oldAAddress = try XCTUnwrap(db.resolveIndexIdentity(depA)).objectID

        // Dependency change: append bytes to A only.
        let aURL = root.appendingPathComponent("A")
        var appended = try Data(contentsOf: aURL)
        appended.append(Data("-appended".utf8))
        try appended.write(to: aURL)

        let update = try db.settleWorkRootContents(rootID: "workA", rootURL: root)
        XCTAssertEqual(update.changed, 1, "only A re-settled")
        XCTAssertEqual(update.reused, 1, "unchanged B is reused, never re-settled")
        XCTAssertEqual(update.invalidatedSettlements, 1,
                       "invalidation closure reports exactly the affected settlement")
        XCTAssertEqual(try db.settlementValidity(sA), "invalid")
        XCTAssertEqual(try db.settlementValidity(sB), "valid",
                       "B's settlement survives: the closure does not leak")

        // A: append-only history, revision incremented.
        let aHistory = try db.dependencyHistory(depA)
        XCTAssertEqual(aHistory.map { $0.revision }, [1, 2])
        XCTAssertEqual(aHistory.map { $0.reason }, ["content-settle", "content-update"])
        let newAAddress = try XCTUnwrap(db.resolveIndexIdentity(depA)).objectID
        XCTAssertNotEqual(newAAddress, oldAAddress)

        // B: untouched dependency revision AND untouched settled content.
        XCTAssertEqual(try db.dependencyHistory(depB), bHistoryBefore,
                       "B's ledger row is byte-for-byte unchanged")
        XCTAssertEqual(try XCTUnwrap(db.resolveIndexIdentity(depB)).objectID, bObjectBefore)
        let carriedB = try XCTUnwrap(
            db.carriedFileContent(rootID: "workA", relativePath: "B"))
        XCTAssertEqual(carriedB.content, Data("B-stable".utf8))
        XCTAssertEqual(carriedB.contentSHA256, NativeSHA256.hexDigest(carriedB.content))
        XCTAssertTrue(try db.verifyObject(bObjectBefore))

        // The stale result is refused, not reused: the retrieval settlement
        // citing the old A revision is invalidated and the demand re-executes.
        XCTAssertEqual(try rawText(url, """
        SELECT status FROM retrieval_settlements;
        """), "", "no retrieval settlement exists before any demand")
        let demand1 = try db.executeInformationDemand(query: "A-v1", rootID: "workA")
        XCTAssertEqual(demand1.hits.count, 1)
        XCTAssertEqual(try rawText(url, """
        SELECT status FROM retrieval_settlements WHERE demand_id='\(demand1.demandID)';
        """), "valid")

        // Re-settle with A unchanged again: no new revision, nothing invalidated;
        // the settled demand result is still reusable (valid revision).
        let repeat1 = try db.settleWorkRootContents(rootID: "workA", rootURL: root)
        XCTAssertEqual(repeat1.changed, 0)
        XCTAssertEqual(repeat1.invalidatedSettlements, 0)
        let demand2 = try db.executeInformationDemand(query: "A-v1", rootID: "workA")
        XCTAssertTrue(demand2.reused,
                      "a current-revision settlement is reused exactly once more")

        // Now change A again: the demand's dependency revision goes stale and
        // the retrieval settlement is invalidated, so the old result must NOT
        // be served as valid.
        try write("A-v3", to: root, name: "A")
        _ = try db.settleWorkRootContents(rootID: "workA", rootURL: root)
        XCTAssertEqual(try rawText(url, """
        SELECT status FROM retrieval_settlements WHERE demand_id='\(demand1.demandID)';
        """), "invalidated")
        let demand3 = try db.executeInformationDemand(query: "A-v1", rootID: "workA")
        XCTAssertFalse(demand3.reused,
                       "a stale-settlement result is never reused as valid")
        XCTAssertTrue(demand3.hits.isEmpty,
                      "the stale bytes are not cited as a valid settlement")

        XCTAssertTrue(try db.integrityCheck())
    }

    /// v29：一次性清掉 demand-input 候选行，其他 reason 保留，append-only
    /// 触发器装回去——清理是一次显式维护，不是把保护拆掉。
    func testMigrationTwentyNineDropsOnlyDemandInputCandidates() throws {
        let (url, db) = try open("v29-drop-candidates")
        defer { cleanup(url) }
        db.close()

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        var message: UnsafeMutablePointer<CChar>?
        let seed = """
        INSERT INTO is_dependency_entries(
            dependency_id, content_address, revision, reason, recorded_at)
        VALUES('demand:d1 -> file:a', 'aa', 1, 'demand-input', '2026-11-11T00:00:00Z'),
              ('demand:d1 -> file:b', 'bb', 1, 'demand-input', '2026-11-11T00:00:00Z'),
              ('file:a', 'aa', 1, 'content-settle', '2026-11-11T00:00:00Z');
        DELETE FROM schema_migrations WHERE version >= 29;
        """
        XCTAssertEqual(sqlite3_exec(handle, seed, nil, nil, &message), SQLITE_OK,
                       message.map { String(cString: $0) } ?? "")
        sqlite3_close(handle)

        let reopened = try ESISDatabase(url: url)
        defer { reopened.close() }
        try reopened.runMigrations()
        XCTAssertEqual(try reopened.count("is_dependency_entries"), 1,
                       "只留 content-settle 那一条")
        XCTAssertEqual(
            try rawText(url, "SELECT reason FROM is_dependency_entries;"), "content-settle")
        XCTAssertThrowsError(try rawExec(url, "DELETE FROM is_dependency_entries;"),
                             "清理之后 append-only 触发器必须还在")
    }

    /// v30：query 列只存问题开头（200 字），全文留在摘要对象里。
    /// 落盘的行变短，读回来的仍是完整问题。
    func testLongSummaryQueryIsShortenedOnDiskAndRestoredOnRead() throws {
        let (url, db) = try open("v30-query-excerpt")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        let longQuery = String(repeating: "合同额与考核管理要逐条核对，", count: 40)
        XCTAssertGreaterThan(longQuery.count, SettlementSummaryPolicy.queryExcerptCharacters)
        let turn = try loop.settleTurn(
            generatedText: "施工组织设计应覆盖关键线路与节点工期。",
            resolution: nil,
            stateID: "S-Q-1",
            parentStateID: nil,
            position: 0,
            modelIdentity: "model-a",
            identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-q",
            summaryQuery: longQuery,
            actions: ["chat.completion"])

        // 落盘：200 字 + 截断标记。
        XCTAssertEqual(
            try rawText(url, "SELECT LENGTH(query) FROM settlement_summaries;"), "200")
        XCTAssertEqual(
            try rawText(url, "SELECT query_truncated FROM settlement_summaries;"), "1")
        XCTAssertEqual(
            try rawText(url, "SELECT substr(query,1,200) FROM settlement_summaries;"),
            String(longQuery.prefix(SettlementSummaryPolicy.queryExcerptCharacters)))

        // 读回：全文，且两条读路径一致。
        let summary = try XCTUnwrap(
            try db.settlementSummary(settlementID: turn.settlementID))
        XCTAssertEqual(summary.query, longQuery)
        XCTAssertTrue(summary.queryTruncated)
        let cited = try db.citableSettlementSummaries(sessionID: "elsewhere")
        XCTAssertEqual(cited.first?.query, longQuery)
    }

    /// v30 迁移：已有的长 query 被截短并标记，短的逐字不动。
    func testMigrationThirtyShortensExistingQueryRows() throws {
        let (url, db) = try open("v30-migrate")
        defer { cleanup(url) }
        db.close()

        let long = String(repeating: "长问题", count: 300)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        var message: UnsafeMutablePointer<CChar>?
        let seed = """
        INSERT INTO settlement_summaries(
            settlement_id, session_id, query, summary, summary_sha256,
            summary_object_id, source_payload_digest, created_at)
        VALUES('s-long', 's', '\(long)', 'ok', 'h',
               '\(String(repeating: "a", count: 64))', 'd', '2026-11-11T00:00:00Z'),
              ('s-short', 's', '短问题', 'ok', 'h',
               '\(String(repeating: "b", count: 64))', 'd', '2026-11-11T00:00:01Z');
        DELETE FROM schema_migrations WHERE version >= 30;
        """
        XCTAssertEqual(sqlite3_exec(handle, seed, nil, nil, &message), SQLITE_OK,
                       message.map { String(cString: $0) } ?? "")
        sqlite3_close(handle)

        let reopened = try ESISDatabase(url: url)
        defer { reopened.close() }
        try reopened.runMigrations()
        XCTAssertEqual(
            try rawText(url, "SELECT LENGTH(query) FROM settlement_summaries WHERE settlement_id='s-long';"),
            "200")
        XCTAssertEqual(
            try rawText(url, "SELECT query_truncated FROM settlement_summaries WHERE settlement_id='s-long';"),
            "1")
        XCTAssertEqual(
            try rawText(url, "SELECT query FROM settlement_summaries WHERE settlement_id='s-short';"),
            "短问题",
            "短问题不动，也不打标记")
        XCTAssertEqual(
            try rawText(url, "SELECT query_truncated FROM settlement_summaries WHERE settlement_id='s-short';"),
            "0")
    }

    /// v31：一轮摘要落一行摘要 + 一组词；同一轮重写是覆盖，不是写第二行；
    /// 有轮号没摘要的轮次一眼能数出来。
    func testRecordTurnDigestKeepsOneRowPerTurn() throws {
        let (url, db) = try open("turn-digest")
        defer { db.close(); cleanup(url) }

        try rawExec(url, """
        INSERT INTO chat_turn_ledger(session_id, turn_index, request_id, seen_at)
            VALUES('s',1,'t1','2026-11-11T00:00:00Z'),
                  ('s',2,'t2','2026-11-11T00:00:01Z'),
                  ('s',3,'t3','2026-11-11T00:00:02Z');
        """)

        let first = try db.recordTurnDigest(
            sessionID: "s", turnIndex: 1,
            digest: "  用户问前台为什么没有输出，结论是模型卡在工具调用死循环  ",
            keywords: "日志分析 工具调用死循环 日志分析", model: "gemma-4-12b")
        XCTAssertEqual(first.digest, "用户问前台为什么没有输出，结论是模型卡在工具调用死循环")
        XCTAssertEqual(first.keywords, ["日志分析", "工具调用死循环"], "同一轮重复的词只留一次")
        XCTAssertEqual(try db.count("keywords"), 2)
        XCTAssertEqual(try db.count("turn_keywords"), 2)

        // 同一轮重写：覆盖那一行；这一轮只挂当前的词，旧词解绑，词表本身
        // 全库共用、不删。
        try db.recordTurnDigest(
            sessionID: "s", turnIndex: 1,
            digest: "用户问前台为什么没有输出，结论是工具调用死循环导致上下文膨胀。",
            keywords: "工具调用死循环 上下文膨胀")
        XCTAssertEqual(try db.count("turn_digests"), 1)
        XCTAssertEqual(try db.count("keywords"), 3)
        XCTAssertEqual(try rawText(url, "SELECT COUNT(*) FROM turn_keywords;"), "2")

        let reread = try XCTUnwrap(try db.turnDigest(sessionID: "s", turnIndex: 1))
        XCTAssertEqual(reread.keywords, ["工具调用死循环", "上下文膨胀"])
        XCTAssertEqual(reread.model, "gemma-4-12b", "重写没带 model 时不把原来的擦掉")

        XCTAssertEqual(try db.turnsWithoutDigest(sessionID: "s"), [2, 3])
        XCTAssertEqual(try db.recentTurnDigests(sessionID: "s").count, 1)
        XCTAssertThrowsError(
            try db.recordTurnDigest(sessionID: "s", turnIndex: 2, digest: "   ", keywords: "x"),
            "空摘要不许落库")
    }

    /// v31 迁移：三张辅助表建起来；已有标题的行标成 filename，
    /// 没标题的行不标（占位标题和真标题要分得开）。
    func testMigrationThirtyOneCreatesTurnDigestTables() throws {
        let (url, db) = try open("v31-migrate")
        defer { cleanup(url) }
        db.close()

        try rawExec(url, """
        DROP TABLE IF EXISTS turn_keywords;
        DROP TABLE IF EXISTS keywords;
        DROP TABLE IF EXISTS turn_digests;
        ALTER TABLE external_files DROP COLUMN title_source;
        INSERT INTO roots(root_id, category, display_name, locator_type, status)
            VALUES('work','work',NULL,'path','present');
        INSERT INTO external_files(root_id, relative_path, title, status)
            VALUES('work','a.md','甲文件','present'),
                  ('work','b.md',NULL,'present');
        DELETE FROM schema_migrations WHERE version >= 31;
        """)

        let reopened = try ESISDatabase(url: url)
        defer { reopened.close() }
        try reopened.runMigrations()
        XCTAssertEqual(try reopened.schemaVersion(), ESISDatabase.currentSchemaVersion)
        XCTAssertEqual(try reopened.count("turn_digests"), 0)
        XCTAssertEqual(try reopened.count("keywords"), 0)
        XCTAssertEqual(
            try rawText(url, "SELECT title_source FROM external_files WHERE relative_path='a.md';"),
            "filename")
        XCTAssertEqual(
            try rawText(url, "SELECT COALESCE(title_source,'-') FROM external_files WHERE relative_path='b.md';"),
            "-", "没标题的行不该被标成 filename")
    }

    /// v32：同一份字节挂在两个空间下结算，边的地址必须相同，只有标签不同。
    /// 这条断言就是「依赖的是信息，不是来源」在代码里的样子。
    func testSpaceNeverEntersDependencyAddress() throws {
        let (url, db) = try open("space-address")
        let rootA = try makeWorkRoot()
        let rootB = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        try write("同一份内容", to: rootA, name: "a.md")
        try write("同一份内容", to: rootB, name: "a.md")

        _ = try db.settleWorkRootContents(rootID: "rootA", rootURL: rootA)
        _ = try db.settleWorkRootContents(rootID: "rootB", rootURL: rootB)
        let spaceA = try db.createSpace(
            title: "项目甲", kind: "directory", titleSource: "human")
        let spaceB = try db.createSpace(
            title: "项目乙", kind: "directory", titleSource: "human")
        try db.setRootSpace(rootID: "rootA", spaceID: spaceA.spaceID)
        try db.setRootSpace(rootID: "rootB", spaceID: spaceB.spaceID)

        let depA = try XCTUnwrap(try db.currentDependency("file:rootA/a.md"))
        let depB = try XCTUnwrap(try db.currentDependency("file:rootB/a.md"))
        XCTAssertEqual(depA.contentAddress, depB.contentAddress,
                       "同一个字节串只有一个地址，跟它挂在哪个空间下无关")
        XCTAssertEqual(try db.count("is_objects"), 1, "两个空间同一份内容只存一份")
        XCTAssertNotEqual(spaceA.spaceID, spaceB.spaceID)
        XCTAssertEqual(try db.space(forRoot: "rootA")?.title, "项目甲")
    }

    /// v32 迁移：现有每个 root 补一个空间，标题取路径最后一段，标成占位。
    func testMigrationThirtyTwoBackfillsOneSpacePerRoot() throws {
        let (url, db) = try open("v32-migrate")
        defer { cleanup(url) }
        db.close()

        try rawExec(url, """
        INSERT INTO roots(root_id, category, display_name, locator_type, status)
            VALUES('work-a','work','/srv/Desktop/项目甲','path','present'),
                  ('work-b','work','/srv/Desktop/项目乙','path','present');
        DELETE FROM schema_migrations WHERE version >= 32;
        DROP TABLE spaces;
        """)

        let reopened = try ESISDatabase(url: url)
        defer { reopened.close() }
        try reopened.runMigrations()
        XCTAssertEqual(try reopened.schemaVersion(), ESISDatabase.currentSchemaVersion)
        XCTAssertEqual(try reopened.count("spaces"), 2)
        XCTAssertEqual(try reopened.listSpaces().map(\.title).sorted(),
                       ["项目乙", "项目甲"])
        let space = try XCTUnwrap(try reopened.space(forRoot: "work-a"))
        XCTAssertEqual(space.titleSource, "filename", "占位标题，人还没改过")
        XCTAssertEqual(space.kind, "directory")
    }

    /// 甲：加目录这个人的动作定空间身份，标题默认是文件夹名。
    func testImportDirectoryNamesCreatesSpaceFromFolderName() throws {
        let (url, db) = try open("space-import")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("x", to: root, name: "a.md")

        _ = try db.importDirectoryNames(rootID: "work-import", rootURL: root)
        let space = try XCTUnwrap(try db.space(forRoot: "work-import"))
        XCTAssertEqual(space.title, root.lastPathComponent)
        XCTAssertEqual(space.titleSource, "filename")
        XCTAssertEqual(space.kind, "directory")

        // 再导入一次：不新建空间，也不动已有标题。
        _ = try db.importDirectoryNames(rootID: "work-import", rootURL: root)
        XCTAssertEqual(try db.count("spaces"), 1)
        XCTAssertEqual(try db.space(forRoot: "work-import")?.spaceID, space.spaceID)
    }

    /// 同一个路径换了目录（挂载被替换 / bind mount / 换卷）：看不见文件
    /// 不是删除。不许清账、不许标 missing、不许作废结算。
    func testReplacedDirectoryDoesNotInvalidateSources() throws {
        let (url, db) = try open("locator-inode")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("alpha", to: root, name: "a.md")
        let first = try db.settleWorkRootContents(rootID: "w", rootURL: root)
        XCTAssertEqual(first.settled, 1)
        XCTAssertFalse(first.locatorIdentityChanged)

        // 整个目录换掉：同一个路径，另一个 inode。
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("beta", to: root, name: "b.md")

        let second = try db.settleWorkRootContents(rootID: "w", rootURL: root)
        XCTAssertTrue(second.locatorIdentityChanged, "同路径换了 inode = 不是同一个目录")
        XCTAssertEqual(second.removed, 0, "不许把「看不到」当成删除")
        XCTAssertEqual(
            try rawText(url, "SELECT COALESCE(status,'-') FROM external_files WHERE relative_path='a.md';"),
            "present", "旧文件的行不许被标 missing")
        XCTAssertEqual(try db.count("settlement_validity_events"), 0,
                       "不许因此作废任何结算")

        // 人确认「还是同一个目录，只是换了挂载」之后，接上。
        try db.adoptRootLocatorIdentity(rootID: "w")
        let third = try db.settleWorkRootContents(rootID: "w", rootURL: root)
        XCTAssertFalse(third.locatorIdentityChanged)
        XCTAssertEqual(third.removed, 1, "认了之后，旧清单才算数")
    }

    /// v34：一条依赖两个时钟。valid_from 是这一版的诞生（文件自己的时间），
    /// valid_to 是下一版的诞生；known_from / known_to 才是 ES 的执行时间。
    func testDependencyIntervalsSeparateWorldClockFromRecordClock() throws {
        let (url, db) = try open("dependency-intervals")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("a.md")
        let birth1 = Date(timeIntervalSince1970: 1_760_000_000)
        let birth2 = birth1.addingTimeInterval(3600)

        try write("第一版", to: root, name: "a.md")
        try FileManager.default.setAttributes(
            [.modificationDate: birth1], ofItemAtPath: file.path)
        _ = try db.settleWorkRootContents(rootID: "w", rootURL: root)

        try write("第二版", to: root, name: "a.md")
        try FileManager.default.setAttributes(
            [.modificationDate: birth2], ofItemAtPath: file.path)
        _ = try db.settleWorkRootContents(rootID: "w", rootURL: root)

        let intervals = try db.dependencyIntervals(dependencyID: "file:w/a.md")
        XCTAssertEqual(intervals.count, 2)
        XCTAssertNotEqual(intervals[0].contentAddress, intervals[1].contentAddress)
        XCTAssertTrue(intervals[0].validFromIsSourceTime, "源时间在手就不用回落")
        XCTAssertEqual(intervals[1].validTo, nil, "最新那一版没有终点")
        XCTAssertEqual(intervals[0].validTo, intervals[1].validFrom,
                       "世界时间是连续区间：下一版的诞生就是上一版的终点")

        // 世界时间查询：那一刻为真的是哪一版。
        XCTAssertEqual(
            try db.dependencyAddress(
                dependencyID: "file:w/a.md", validAt: birth1.addingTimeInterval(60)),
            intervals[0].contentAddress)
        XCTAssertEqual(
            try db.dependencyAddress(
                dependencyID: "file:w/a.md", validAt: birth2.addingTimeInterval(60)),
            intervals[1].contentAddress)
        XCTAssertNil(
            try db.dependencyAddress(
                dependencyID: "file:w/a.md", validAt: birth1.addingTimeInterval(-60)),
            "还没出生那一刻，没有记录在案的版本")
    }

    /// 状态面板读的数要对：区间的开/闭/断点、摘要覆盖，都是面板上直接给人看的。
    func testCarrierReportCountsIntervalsAndDigestCoverage() throws {
        let (url, db) = try open("carrier-report-v34")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        let birth1 = Date(timeIntervalSince1970: 1_760_000_000)

        try write("第一版", to: root, name: "b.md")
        try FileManager.default.setAttributes(
            [.modificationDate: birth1], ofItemAtPath: root.appendingPathComponent("b.md").path)
        _ = try db.settleWorkRootContents(rootID: "w", rootURL: root)
        try write("第二版", to: root, name: "b.md")
        try FileManager.default.setAttributes(
            [.modificationDate: birth1.addingTimeInterval(60)],
            ofItemAtPath: root.appendingPathComponent("b.md").path)
        _ = try db.settleWorkRootContents(rootID: "w", rootURL: root)

        let report = try db.carrierReport()
        XCTAssertEqual(report.dependencyIntervalsClosed, 1, "两版之间那一段是闭合的")
        XCTAssertEqual(report.dependencyIntervalsOpen, 1, "最新一版没有终点")
        XCTAssertEqual(report.dependencyIntervalBreaks, 0, "世界时间轴上相邻两版必须首尾相接")
        XCTAssertEqual(report.turnDigests, 0)

        try db.recordTurnDigest(
            sessionID: "s", turnIndex: 1, digest: "这一轮做了什么", keywords: "区间 双时钟")
        XCTAssertEqual(try db.carrierReport().turnDigests, 1)
    }

    /// VACUUM 失败必须留痕：写在库同目录的 simigo.maintenance.json，
    /// carrierReport 把它带出来，成功回收后文件消失。
    func testVacuumFailureIsRecordedNextToStore() throws {
        let (url, db) = try open("vacuum-failure-note")
        defer { db.close(); cleanup(url) }
        let note = url.deletingLastPathComponent()
            .appendingPathComponent("simigo.maintenance.json")
        defer { try? FileManager.default.removeItem(at: note) }

        XCTAssertNil(db.lastVacuumFailure, "没失败过就没这个文件")
        XCTAssertNil(try db.carrierReport().vacuumFailure)

        let payload: [String: Any] = [
            "at": "2026-11-11T07:41:00Z",
            "freedPages": 772,
            "reason": "database is locked",
        ]
        try JSONSerialization.data(withJSONObject: payload)
            .write(to: note, options: .atomic)

        let reported = try XCTUnwrap(db.lastVacuumFailure)
        XCTAssertTrue(reported.contains("772"), reported)
        XCTAssertTrue(reported.contains("database is locked"), reported)
        XCTAssertEqual(
            try db.carrierReport().vacuumFailure, reported,
            "状态接口要和文件说同一句话")
    }
}
