import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// v8 physical carrier: content-addressed objects, append-only identity and
/// dependency history, and the guarantee that every carried IS row points at
/// verified bytes instead of an inline copy.
final class SimiGoESISCarrierTests: XCTestCase {

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

    private func open(_ name: String) throws -> (URL, SimiGoESISDatabase) {
        let url = tempURL(name)
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private static let contract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#

    @discardableResult
    private func mkSettlement(_ db: SimiGoESISDatabase, stateID: String, value: String) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let settled = try SimiGoSettlementAuthority.authorize(
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
            throw SimiGoESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(message)
            throw SimiGoESISDatabase.DatabaseError.sql(detail)
        }
    }

    private func rawText(_ url: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw SimiGoESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SimiGoESISDatabase.DatabaseError.sql(sql)
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
        XCTAssertEqual(report.schemaVersion, 8)
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
        XCTAssertEqual(try db.count("file_contents"), 2, "removed content row is cleared")

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
            VALUES('work','work',NULL,'path','present','t','t');
        INSERT INTO file_contents(root_id, relative_path, content_sha256, content, settled_at)
            VALUES('work','a.md','stale-digest','legacy file','t');
        INSERT INTO external_files(
            root_id, relative_path, kind, size, modified_at, content_digest,
            indexed_at, last_seen_at, status)
            VALUES('work','a.md','md',11,NULL,'stale-digest','t','t','present');
        INSERT INTO chat_messages(session_id, role, content, model, content_sha256, created_at)
            VALUES('s','user','legacy chat',NULL,'stale-digest','t');
        INSERT INTO retrieval_settlements(
            demand_id, query, root_ids, inputs_digest, result_sha256, result_json,
            hit_count, status, settled_at)
            VALUES('d','q','work','i','stale-digest',
                   '[{"rootID":"work","relativePath":"a.md","lineNo":1,"lineText":"legacy file"}]',
                   1,'valid','t');
        INSERT INTO settlements(
            settlement_id, state_id, schema_version, payload, payload_digest, signature,
            contract_version, settled_at, validation_status)
            VALUES('11111111-1111-1111-1111-111111111111', NULL, 'v1', X'7061796C6F6164',
                   'stale-digest', NULL, 'v', 't', 'VALID');
        DELETE FROM schema_migrations WHERE version >= 8;
        """)
        XCTAssertEqual(try db.schemaVersion(), 7)

        try db.runMigrations()
        XCTAssertEqual(try db.schemaVersion(), 8)

        let report = try db.carrierReport(deepVerify: true)
        XCTAssertEqual(report.unaddressedFileContents, 0)
        XCTAssertEqual(report.unaddressedChatMessages, 0)
        XCTAssertEqual(report.unaddressedRetrievalResults, 0)
        XCTAssertEqual(report.unaddressedSettlements, 0)
        XCTAssertEqual(report.inlineLegacyPayloads, 0)
        XCTAssertEqual(report.danglingReferences, 0)
        XCTAssertEqual(report.corruptObjects, 0)
        XCTAssertEqual(report.objectCount, 4)
        XCTAssertEqual(report.dependencyEntries, 1, "file backfill appends a provenance revision")

        XCTAssertEqual(try db.searchSettledContent(query: "legacy").first?.relativePath, "a.md")
        XCTAssertEqual(try db.listChatMessages(sessionID: "s").first?.content, "legacy chat")
        XCTAssertEqual(String(data: try db.readSettlementReceipts().first!.payload,
                              encoding: .utf8), "payload")
        let demand = try XCTUnwrap(db.resolveIndexIdentity("demand:d"))
        let hits = try JSONDecoder().decode([SimiGoESISDatabase.ContentHit].self,
                                            from: try db.readObject(demand.objectID))
        XCTAssertEqual(hits.first?.lineText, "legacy file")
        XCTAssertEqual(try db.resolveIndexIdentity("file:work/a.md")?.objectID,
                       try db.externalFileDigest(rootID: "work", relativePath: "a.md"))
        db.close()
        cleanup(url)
    }

    // MARK: - Demand results

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
        let fileEntry = try XCTUnwrap(db.resolveIndexIdentity("file:work/doc.md"))
        let input = try XCTUnwrap(
            db.currentDependency("demand:\(first.demandID) -> file:work/doc.md"))
        XCTAssertEqual(input.contentAddress, fileEntry.objectID)
        XCTAssertEqual(input.reason, "demand-input")

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
        XCTAssertFalse(db.verifyObject(objectID))
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
        XCTAssertTrue(db.verifyObject(try XCTUnwrap(content.objectID)))
        XCTAssertNil(try db.carriedFileContent(rootID: "work", relativePath: "missing.md"))
    }
}
