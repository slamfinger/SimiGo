import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// ES → IS → ES seam: a demand resolves against a physical index that does not
/// copy entity bytes plus stored chat, the resolution is settled and reusable,
/// and the advancing settlement depends on the retrieval it consumed.
final class SimiGoInformationLoopTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-loop-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func makeWorkRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-loop-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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

    private func rawText(_ url: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
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

    // MARK: - Index without entity copies

    func testIndexOnlySettlementReadsVerifiedBytesFromLocator() throws {
        let (url, db) = try open("index-only")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("line one\nneedle body\n", to: root, name: "doc.md")

        let report = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        XCTAssertTrue(report.indexOnly)
        XCTAssertEqual(report.bytesAddressed, 0, "entity bytes must not be copied")
        XCTAssertGreaterThan(report.entityBytesRead, 0)
        XCTAssertEqual(
            try rawText(url, "SELECT COUNT(*) FROM file_contents WHERE object_id IS NOT NULL;"),
            "0")

        let hits = try db.searchSettledContent(query: "needle", rootID: "work")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.lineNo, 2)

        let carried = try db.carriedFileContent(rootID: "work", relativePath: "doc.md")
        XCTAssertEqual(carried?.content, Data("line one\nneedle body\n".utf8))

        // A changed file no longer matches the settled digest and is not a hit.
        try write("different\n", to: root, name: "doc.md")
        XCTAssertTrue(try db.searchSettledContent(query: "needle", rootID: "work").isEmpty)
        XCTAssertNil(try db.carriedFileContent(rootID: "work", relativePath: "doc.md"))
    }

    // MARK: - Demand over physical and chat information

    func testDemandResolvesFilesAndChatThenReusesSettlement() throws {
        let (url, db) = try open("demand")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle in file", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        try db.appendChatMessage(
            sessionID: "s1", role: "user", content: "needle in chat",
            model: nil, createdAt: Date())

        let loop = SimiGoInformationLoop(database: db)
        let first = try loop.resolve(.init(
            sessionID: "s1", query: "needle", includeChat: true,
            chatSessionIDs: ["s1"]))
        XCTAssertFalse(first.reused)
        XCTAssertEqual(Set(first.hits.map(\.kind)), ["file", "chat"])
        XCTAssertEqual(try rawText(url,
            "SELECT state FROM information_demands WHERE demand_id='\(first.demandID)';"),
            "RESOLVED")
        XCTAssertFalse(first.retrievalSettlementID.isEmpty)
        XCTAssertEqual(try rawText(url,
            "SELECT validation_status FROM settlements WHERE settlement_id='\(first.retrievalSettlementID)';"),
            "IS_RETRIEVAL")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM information_advancements;"), "0")

        let second = try loop.resolve(.init(
            sessionID: "s1", query: "needle", includeChat: true,
            chatSessionIDs: ["s1"]))
        XCTAssertTrue(second.reused)
        XCTAssertEqual(second.demandID, first.demandID)
        XCTAssertEqual(second.resultSHA256, first.resultSHA256)
        XCTAssertEqual(second.hits, first.hits)

        let payload = try XCTUnwrap(
            try db.informationRetrievalPayload(demandID: first.demandID))
        XCTAssertEqual(NativeSHA256.hexDigest(payload), first.resultSHA256)
    }

    // MARK: - Goal step 4: a settled demand's file dependency is real

    /// The demand that cited a physical file must carry a source binding, so a
    /// later content change of that file invalidates exactly that demand's
    /// settlement — and nothing a sibling file produced.
    func testSettledDemandIsInvalidatedOnlyByTheFileItCited() throws {
        let (url, db) = try open("demand-closure")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("omega appears here", to: root, name: "a.md")
        try write("zeta appears here", to: root, name: "b.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)

        let loop = SimiGoInformationLoop(database: db)
        let omega = try loop.resolve(.init(query: "omega", includeChat: false))
        let zeta = try loop.resolve(.init(query: "zeta", includeChat: false))
        XCTAssertEqual(omega.hits.map(\.itemID), ["file:work/a.md"])
        XCTAssertEqual(zeta.hits.map(\.itemID), ["file:work/b.md"])

        func bindings(_ settlementID: String, _ file: String) -> String {
            (try? rawText(url, """
            SELECT COUNT(*) FROM settlement_bindings b \
            JOIN external_files f ON f.file_id=b.source_file_id AND f.root_id=b.source_root_id \
            WHERE b.settlement_id='\(settlementID)' AND f.relative_path='\(file)';
            """)) ?? "ERR"
        }
        // The edge exists, and it is local: omega cites a.md only.
        XCTAssertEqual(bindings(omega.retrievalSettlementID, "a.md"), "1")
        XCTAssertEqual(bindings(omega.retrievalSettlementID, "b.md"), "0")

        // Dependency unchanged → the settled retrieval is legitimately reused.
        let again = try loop.resolve(.init(query: "omega", includeChat: false))
        XCTAssertTrue(again.reused)
        XCTAssertEqual(again.demandID, omega.demandID)

        // Upstream dependency changed → its closure alone is invalidated.
        try write("omega appears here, revised", to: root, name: "a.md")
        let report = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        XCTAssertEqual(report.invalidatedSettlements, 1)
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlements WHERE settlement_id='\(omega.retrievalSettlementID)';
        """), "invalid")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlements WHERE settlement_id='\(zeta.retrievalSettlementID)';
        """), "valid", "an unrelated settled result keeps its validity")

        // The stale result is refused, not replayed.
        XCTAssertNil(try db.informationRetrievalPayload(demandID: omega.demandID))
        let after = try loop.resolve(.init(query: "omega", includeChat: false))
        XCTAssertFalse(after.reused)
        XCTAssertNotEqual(after.demandID, omega.demandID)
        XCTAssertEqual(after.hits.first?.lineText, "omega appears here, revised")
    }

    /// A model turn that consumed a settled retrieval is downstream of that
    /// retrieval, so a source-file change must invalidate the turn's own
    /// settlement too — otherwise the next ES would restore a conclusion whose
    /// evidence no longer exists.
    func testModelTurnDerivedFromCitedFileIsInvalidatedByTransitiveClosure() throws {
        let (url, db) = try open("closure-transitive")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("omega distance 5.6m", to: root, name: "a.md")
        try write("zeta distance 9.1m", to: root, name: "b.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)

        let loop = SimiGoInformationLoop(database: db)
        func turn(query: String, text: String, state: String) throws -> (String, String) {
            let resolution = try loop.resolve(.init(query: query, includeChat: false))
            let id = try loop.settleTurn(
                generatedText: text, resolution: resolution, stateID: state,
                parentStateID: nil, position: 0, modelIdentity: "model-a",
                identity: .init(model: "m", tokenizer: "t"), sessionID: "s1",
                summaryQuery: query).settlementID
            return (id, resolution.demandID)
        }
        let (omegaTurn, omegaDemand) = try turn(
            query: "omega", text: "omega is 5.6m", state: "S-omega")
        let (zetaTurn, zetaDemand) = try turn(
            query: "zeta", text: "zeta is 9.1m", state: "S-zeta")
        let omegaRetrieval = try rawText(url, """
        SELECT retrieval_settlement_id FROM information_advancements \
        WHERE settlement_id='\(omegaTurn)';
        """)
        XCTAssertFalse(omegaRetrieval.isEmpty)

        XCTAssertEqual(
            try db.citableSettlementSummaries(sessionID: nil).map(\.settlementID)
                .filter { $0 == omegaTurn || $0 == zetaTurn }.count, 2)
        XCTAssertNotNil(try db.informationRetrievalPayload(demandID: omegaDemand))
        XCTAssertNotNil(try db.informationRetrievalPayload(demandID: zetaDemand))

        try write("omega distance 7.2m", to: root, name: "a.md")
        let report = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)

        // Closure = the retrieval settlement plus the turn that consumed it.
        XCTAssertEqual(report.invalidatedSettlements, 2)
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlements WHERE settlement_id='\(omegaRetrieval)';
        """), "invalid")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlements WHERE settlement_id='\(omegaTurn)';
        """), "invalid", "a conclusion built from stale evidence does not stay citable")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlements WHERE settlement_id='\(zetaTurn)';
        """), "valid", "an unrelated turn keeps its validity")

        // The demand-side view has to flip with the authoritative row: readers
        // that key on retrieval_settlements.status alone must not keep
        // advertising the invalidated demand as reusable.
        XCTAssertEqual(try rawText(url, """
        SELECT status FROM retrieval_settlements \
        WHERE bridged_settlement_id='\(omegaRetrieval)';
        """), "invalidated")
        let zetaRetrieval = try rawText(url, """
        SELECT retrieval_settlement_id FROM information_advancements \
        WHERE settlement_id='\(zetaTurn)';
        """)
        XCTAssertEqual(try rawText(url, """
        SELECT status FROM retrieval_settlements \
        WHERE bridged_settlement_id='\(zetaRetrieval)';
        """), "valid", "an unrelated demand stays reusable")

        XCTAssertNil(
            try db.informationRetrievalPayload(demandID: omegaDemand),
            "an invalidated demand must not hand its payload to a reuser")
        XCTAssertNotNil(try db.informationRetrievalPayload(demandID: zetaDemand))

        XCTAssertFalse(
            try db.citableSettlementSummaries(sessionID: nil).map(\.settlementID)
                .contains(omegaTurn))
        XCTAssertTrue(
            try db.citableSettlementSummaries(sessionID: nil).map(\.settlementID)
                .contains(zetaTurn))
    }

    func testStalePhysicalInputForcesNewDemandAndIsNotCited() throws {
        let (url, db) = try open("stale")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)

        let loop = SimiGoInformationLoop(database: db)
        let first = try loop.resolve(.init(query: "needle", includeChat: false))
        XCTAssertEqual(first.hits.count, 1)

        try write("needle changed but unsettled", to: root, name: "a.md")
        let second = try loop.resolve(.init(query: "needle", includeChat: false))
        XCTAssertNotEqual(second.demandID, first.demandID)
        XCTAssertEqual(second.staleItemIDs, ["file:work/a.md"])
        XCTAssertTrue(second.hits.isEmpty, "stale bytes must never be cited")
        XCTAssertFalse(second.reused)
    }

    // MARK: - Advancement

    func testSettleTurnLinksSettlementAndAdvancesDemand() throws {
        let (url, db) = try open("advance")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(.init(
            sessionID: "s1", query: "needle", includeChat: false))

        let turn = try loop.settleTurn(
            generatedText: "the answer",
            resolution: resolution,
            stateID: "S-2",
            parentStateID: nil,
            position: 0,
            modelIdentity: "model-a",
            identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s1")

        XCTAssertFalse(turn.advancementID.isEmpty)
        XCTAssertEqual(try rawText(url,
            "SELECT next_input FROM execution_states WHERE state_id='S-2';"), "the answer")
        XCTAssertEqual(try rawText(url,
            "SELECT validation_status FROM settlements WHERE settlement_id='\(turn.settlementID)';"),
            "VALID")

        let edge = try rawText(url, """
        SELECT from_settlement || '>' || to_settlement || ':' || kind
        FROM dependency_edges;
        """)
        XCTAssertEqual(edge, "\(turn.settlementID)>\(resolution.retrievalSettlementID):information-demand")
        XCTAssertEqual(try rawText(url,
            "SELECT state FROM information_demands WHERE demand_id='\(resolution.demandID)';"),
            "ADVANCED")
        XCTAssertEqual(try db.currentChatStateID(sessionID: "s1"), "S-2")

        let bindings = try db.settlementBindings(settlementID: turn.settlementID)
        let expected = SimiGoSettlementIdentityBinding.bindings(
            for: .init(model: "m", tokenizer: "t"))
        XCTAssertEqual(
            bindings[SimiGoSettlementIdentityBinding.modelKey],
            expected[SimiGoSettlementIdentityBinding.modelKey])
        XCTAssertEqual(
            bindings[SimiGoSettlementIdentityBinding.tokenizerKey],
            expected[SimiGoSettlementIdentityBinding.tokenizerKey])
    }

    func testSettlementSummaryIsRecordedAndCitedByLaterDemand() throws {
        let (url, db) = try open("summary-cite")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        let turn = try loop.settleTurn(
            generatedText: "秦沈项目的施工组织设计应覆盖关键线路与节点工期，并配置相应生产资源。",
            resolution: nil,
            stateID: "S-SUM-1",
            parentStateID: nil,
            position: 0,
            modelIdentity: "model-a",
            identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-alpha",
            summaryQuery: "施工组织设计要求",
            actions: ["chat.completion"])

        let summary = try XCTUnwrap(
            try db.settlementSummary(settlementID: turn.settlementID))
        XCTAssertEqual(summary.query, "施工组织设计要求")
        XCTAssertEqual(summary.sessionID, "s-alpha")
        XCTAssertTrue(summary.summary.contains("关键线路"))
        XCTAssertEqual(
            summary.summarySHA256, NativeSHA256.hexDigest(Data(summary.summary.utf8)))
        XCTAssertEqual(try rawText(url, "SELECT COUNT(*) FROM settlement_summaries;"), "1")
        XCTAssertEqual(
            try rawText(url, "SELECT source_payload_digest FROM settlement_summaries;"),
            try rawText(url, "SELECT payload_digest FROM settlements;"))

        // A demand raised in a different conversation cites the distilled
        // conclusion without touching the sources it came from.
        let other = try loop.resolve(.init(
            sessionID: "s-beta", query: "关键线路 节点工期", includeChat: false))
        let hit = try XCTUnwrap(other.hits.first { $0.kind == "settlement" })
        XCTAssertEqual(hit.itemID, "settlement:\(turn.settlementID)")
        XCTAssertEqual(hit.locator, "settlement:\(turn.settlementID)#summary")
        XCTAssertEqual(hit.lineText, String(summary.summary.prefix(240)))
        XCTAssertEqual(hit.sourceSHA256, summary.summarySHA256)
        XCTAssertTrue(other.itemIDs.contains("settlement:\(turn.settlementID)"))

        // The settlement's own conversation already carries the turn as chat;
        // repeating it as a settlement hit would echo the live thread.
        let own = try loop.resolve(.init(
            sessionID: "s-alpha", query: "关键线路 节点工期", includeChat: false))
        XCTAssertTrue(own.hits.allSatisfy { $0.kind != "settlement" })
    }

    func testInvalidatedSettlementSummaryIsNotCited() throws {
        let (url, db) = try open("summary-invalid")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        let turn = try loop.settleTurn(
            generatedText: "关键线路应作为节点工期考核依据。",
            resolution: nil, stateID: "S-SUM-2", parentStateID: nil, position: 0,
            modelIdentity: "model-a",
            identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-alpha", summaryQuery: "节点工期",
            actions: ["chat.completion"])
        XCTAssertNotNil(try db.citableSettlementSummaries(sessionID: "s-beta").first)

        _ = try db.invalidateSettlement(turn.settlementID)

        XCTAssertTrue(
            try db.citableSettlementSummaries(sessionID: "s-beta").isEmpty)
        // Invalidation changes citation eligibility, not the stored record.
        XCTAssertNotNil(try db.settlementSummary(settlementID: turn.settlementID))
        let after = try loop.resolve(.init(
            sessionID: "s-beta", query: "关键线路 节点工期", includeChat: false))
        XCTAssertTrue(after.hits.allSatisfy { $0.kind != "settlement" })
    }

    func testSettlementSummaryDistillationIsDeterministicAndBounded() throws {
        let long = String(repeating: "施工组织设计覆盖关键线路。", count: 60)
        let first = SettlementSummaryPolicy.distill(long)
        XCTAssertEqual(first, SettlementSummaryPolicy.distill(long))
        XCTAssertLessThanOrEqual(first.count, SettlementSummaryPolicy.maxCharacters)
        XCTAssertTrue(first.hasSuffix("。"))
        XCTAssertEqual(
            SettlementSummaryPolicy.distill("  \n\n "), "",
            "an empty payload must not settle an empty summary")

        // Structured results distill through their scalar fields, keys sorted.
        let payload = try JSONSerialization.data(
            withJSONObject: ["route_key": "NORTH>EAST", "priority": 5],
            options: [.sortedKeys])
        XCTAssertEqual(
            SettlementSummaryPolicy.text(fromPayload: payload),
            "priority=5；route_key=NORTH>EAST")
        let chat = try JSONSerialization.data(withJSONObject: ["content": "已结算结论"])
        XCTAssertEqual(SettlementSummaryPolicy.text(fromPayload: chat), "已结算结论")
    }

    func testBackfillRestoresMissingSettlementSummary() throws {
        let (url, db) = try open("summary-backfill")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        let turn = try loop.settleTurn(
            generatedText: "结算结论：以实施性施工组织设计为纲。",
            resolution: nil, stateID: "S-SUM-3", parentStateID: nil, position: 0,
            modelIdentity: "model-a",
            identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-alpha", summaryQuery: "施工组织设计",
            actions: ["chat.completion"])

        // Simulate a settlement written before v10.
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(
            sqlite3_exec(handle, "DELETE FROM settlement_summaries;", nil, nil, nil),
            SQLITE_OK)
        XCTAssertNil(try db.settlementSummary(settlementID: turn.settlementID))

        XCTAssertEqual(try db.backfillSettlementSummaries(), 1)

        let restored = try XCTUnwrap(
            try db.settlementSummary(settlementID: turn.settlementID))
        XCTAssertTrue(restored.summary.contains("实施性施工组织设计"))
        // The query is recovered from the advancement that consumed this
        // settlement; without one (as here) the summary carries none rather
        // than inventing a question.
        XCTAssertEqual(restored.query, "")
        XCTAssertEqual(try db.backfillSettlementSummaries(), 0, "backfill is idempotent")
    }

    func testChatMessageIsIndexedAsInformationItem() throws {
        let (url, db) = try open("chat-item")
        defer { db.close(); cleanup(url) }
        try db.appendChatMessage(
            sessionID: "s9", role: "assistant", content: "remember this",
            model: "m", createdAt: Date())

        let itemID = try rawText(url, """
        SELECT item_id || '|' || kind || '|' || state FROM information_items;
        """)
        XCTAssertTrue(itemID.hasPrefix("chat:s9/"))
        XCTAssertTrue(itemID.hasSuffix("|chat|AVAILABLE"))
        XCTAssertEqual(try db.searchChatMessages(query: "remember").count, 1)
    }
}
