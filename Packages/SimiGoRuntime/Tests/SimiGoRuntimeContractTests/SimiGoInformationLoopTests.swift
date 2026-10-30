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
        let chatUserID = try db.appendChatMessage(
            sessionID: "s1", role: "user", content: "needle in chat",
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: "s1", userMessageID: chatUserID,
            assistantText: "记下了", model: nil, createdAt: Date())

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

    // MARK: - P1/P2: retrieval boundary (measured 2026-10-30)

    /// A cited fragment must contain the match that produced it. Measured
    /// 2026-10-30: a 2,447-character rollout line matched on a term at
    /// character 566 while the injected citation was that line's first 240
    /// characters — text that never contained the query at all.
    func testCitationWindowContainsTheMatchThatSelectedIt() throws {
        let (url, db) = try open("snippet")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        let preamble = String(repeating: "background line ", count: 70)
        try write(preamble + " needle-tail", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(.init(query: "needle-tail", includeChat: false))
        let hit = try XCTUnwrap(resolution.hits.first { $0.itemID == "file:work/a.md" })
        XCTAssertTrue(hit.lineText.contains("needle-tail"))
        XCTAssertLessThanOrEqual(hit.lineText.count, 242)
        XCTAssertTrue(
            hit.lineText.hasPrefix("…"),
            "the window starts near the match, not at the line's beginning")
    }

    /// A user line whose own request has not completed is not history. Measured
    /// 2026-10-30: four Codex requests shared one session and the greeting
    /// retrieved a background rollout prompt that was still in flight.
    func testInFlightUserTextIsNotRetrievable() throws {
        let (url, db) = try open("in-flight")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        let inFlight = try db.appendChatMessage(
            sessionID: "s", role: "user",
            content: "Analyze this rollout and produce rollout_summary",
            model: nil, createdAt: Date())
        let greeting = try loop.resolve(.init(
            sessionID: "s", query: "你好", includeChat: true, chatSessionIDs: ["s"]))
        XCTAssertTrue(greeting.hits.isEmpty)
        XCTAssertEqual(loop.contextBlock(greeting), "")

        // Completion — not arrival order — is what makes the line history.
        try db.commitChatTurn(
            sessionID: "s", userMessageID: inFlight,
            assistantText: "已完成后台分析", model: nil, createdAt: Date())
        let later = try loop.resolve(.init(
            sessionID: "s", query: "rollout", includeChat: true, chatSessionIDs: ["s"]))
        XCTAssertEqual(later.hits.map(\.itemID), ["chat:s/\(inFlight)"])
        XCTAssertTrue(try XCTUnwrap(later.hits.first).lineText.contains("rollout_summary"))
    }

    /// Four concurrent requests on one session, the Codex shape: the visible
    /// turn plus background rollout analysis, title generation and memory
    /// extraction. None of them may read another's in-flight input, and a
    /// request that never commits never becomes ordinary memory.
    func testFourConcurrentTurnsNeverSeeEachOthersInFlightInput() throws {
        let (url, db) = try open("concurrent")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        let greetingID = try db.appendChatMessage(
            sessionID: "s", role: "user", content: "你好",
            model: nil, createdAt: Date())
        let rolloutID = try db.appendChatMessage(
            sessionID: "s", role: "user",
            content: "Analyze this rollout and produce JSON with rollout_summary",
            model: nil, createdAt: Date(), eligibility: .internalOperation)
        let titleID = try db.appendChatMessage(
            sessionID: "s", role: "user",
            content: "Generate a concise title for this conversation",
            model: nil, createdAt: Date(), eligibility: .internalOperation)
        let memoryID = try db.appendChatMessage(
            sessionID: "s", role: "user",
            content: "raw_memory extraction for the previous rollout",
            model: nil, createdAt: Date(), eligibility: .internalOperation)

        // Every request resolves while all four turns are still in flight.
        for query in ["你好", "rollout", "title", "raw_memory"] {
            let resolution = try loop.resolve(.init(
                sessionID: "s", query: query, includeChat: true,
                chatSessionIDs: ["s"]))
            XCTAssertTrue(
                resolution.hits.isEmpty,
                "query \(query) retrieved another request's in-flight line")
            XCTAssertEqual(loop.contextBlock(resolution), "")
        }

        // Only the greeting completes. Its turn becomes history; the three
        // background requests stay pending and stay invisible.
        try db.commitChatTurn(
            sessionID: "s", userMessageID: greetingID,
            assistantText: "你好！有什么可以帮你？", model: nil, createdAt: Date())
        let afterGreeting = try loop.resolve(.init(
            sessionID: "s", query: "rollout", includeChat: true,
            chatSessionIDs: ["s"]))
        XCTAssertTrue(afterGreeting.hits.isEmpty)

        // A background request that completes is still not ordinary memory:
        // provenance decides eligibility, not completion.
        try db.commitChatTurn(
            sessionID: "s", userMessageID: rolloutID,
            assistantText: "{\"rollout_summary\":\"background analysis\"}",
            model: nil, createdAt: Date(), eligibility: .internalOperation)
        let afterInternal = try loop.resolve(.init(
            sessionID: "s", query: "rollout", includeChat: true,
            chatSessionIDs: ["s"]))
        XCTAssertTrue(afterInternal.hits.isEmpty)

        let visible = try db.chatIndexRows(sessionIDs: ["s"])
        XCTAssertEqual(visible.map(\.role), ["user", "assistant"])
        XCTAssertEqual(visible.map(\.content), ["你好", "你好！有什么可以帮你？"])
        XCTAssertFalse(visible.contains { $0.messageID == rolloutID })
        XCTAssertFalse(visible.contains { $0.messageID == titleID })
        XCTAssertFalse(visible.contains { $0.messageID == memoryID })
    }

    /// A request that declares itself an internal operation is kept as a record
    /// but never gains ordinary semantic standing, even after it completes:
    /// passing through the API is not what makes text conversation memory.
    func testInternalOperationIsRecordedButNeverRetrievable() throws {
        let (url, db) = try open("internal-op")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)

        let rollout = try db.appendChatMessage(
            sessionID: "s-op", role: "user",
            content: "Analyze this rollout and produce rollout_summary for 关键线路",
            model: nil, createdAt: Date(), eligibility: .internalOperation)
        try db.commitChatTurn(
            sessionID: "s-op", userMessageID: rollout,
            assistantText: "{\"rollout_summary\":\"关键线路 节点工期\"}",
            model: nil, createdAt: Date(), eligibility: .internalOperation)

        // Kept for audit ...
        XCTAssertEqual(try db.listChatMessages(sessionID: "s-op").count, 2)
        // ... with no ordinary standing.
        XCTAssertTrue(try db.chatIndexRows(sessionIDs: ["s-op"]).isEmpty)
        let resolution = try loop.resolve(.init(
            sessionID: "s-op", query: "关键线路 节点工期", includeChat: true,
            chatSessionIDs: ["s-op"]))
        XCTAssertTrue(resolution.hits.isEmpty)
        XCTAssertEqual(loop.contextBlock(resolution), "")

        // An ordinary turn with the same text must not adopt the internal row:
        // that would promote client bookkeeping into conversation memory.
        let ordinary = try db.appendChatMessage(
            sessionID: "s-op", role: "user",
            content: "Analyze this rollout and produce rollout_summary for 关键线路",
            model: nil, createdAt: Date())
        XCTAssertNotEqual(ordinary, rollout)
        try db.commitChatTurn(
            sessionID: "s-op", userMessageID: ordinary,
            assistantText: "已收到", model: nil, createdAt: Date())

        let later = try loop.resolve(.init(
            sessionID: "s-op", query: "关键线路 节点工期", includeChat: true,
            chatSessionIDs: ["s-op"]))
        XCTAssertEqual(later.hits.map(\.itemID), ["chat:s-op/\(ordinary)"])
        XCTAssertTrue(try XCTUnwrap(later.hits.first).lineText.contains("关键线路"))
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

    /// A re-sent trailing user turn is one turn. Measured 2026-10-29: a real
    /// session had accumulated twelve byte-identical user rows because every
    /// retry of a cancelled turn appended another copy, and those copies came
    /// back as competing retrieval hits.
    func testRepeatedUserTurnIsRecordedOnce() throws {
        let (url, db) = try open("chat-dedupe")
        defer { db.close(); cleanup(url) }
        let question = "查找跟“分包”相关的文件"
        try db.appendChatMessage(
            sessionID: "s10", role: "user", content: question, model: "m", createdAt: Date())
        try db.appendChatMessage(
            sessionID: "s10", role: "assistant", content: "…", model: "m", createdAt: Date())
        try db.appendChatMessage(
            sessionID: "s10", role: "user", content: question, model: "m", createdAt: Date())
        XCTAssertEqual(try db.listChatMessages(sessionID: "s10").filter { $0.role == "user" }.count, 1)

        // After a different question, the same words are a new turn again.
        try db.appendChatMessage(
            sessionID: "s10", role: "user", content: "另一个问题", model: "m", createdAt: Date())
        try db.appendChatMessage(
            sessionID: "s10", role: "user", content: question, model: "m", createdAt: Date())
        XCTAssertEqual(try db.listChatMessages(sessionID: "s10").filter { $0.role == "user" }.count, 3)
    }

    // MARK: - The client envelope is not information (measured 2026-10-29)    /// The observed managed-request shape: a skills list, the memory index, the
    /// date, then the question on the last line. The envelope is client-side
    /// boilerplate that repeats on every turn; only the question is information.
    private static let clientEnvelope = """
        <system-reminder>
        The following skills are available with the Skill tool:

        - skill-creator: Guide for creating effective skills.
        - qoder-canvas:canvas: Create interactive visuals in conversation.

        # autoMemory
        - [代码修改须先获明确授权](user-behavior-4a1ca91f.md) — 准备修改实验脚本时

        # currentDate
        Today's date is 2026-10-29.

        IMPORTANT: this context may or may not be relevant to your tasks.
        </system-reminder>

        """

    func testRetrievalQueryDropsClientEnvelope() {
        let question = "查找跟“分包”相关的文件"
        XCTAssertEqual(
            SimiGoInformationLoop.retrievalQuery(from: Self.clientEnvelope + question),
            question)
        XCTAssertEqual(
            SimiGoInformationLoop.retrievalQuery(from: question + "\n" + Self.clientEnvelope),
            question,
            "removal is by block, not by position")
    }

    func testRetrievalQueryKeepsPlainQuestionAndDropsUnclosedTail() {
        XCTAssertEqual(
            SimiGoInformationLoop.retrievalQuery(from: "  查看跟分包管理相关的资料 \n"),
            "查看跟分包管理相关的资料")
        XCTAssertEqual(
            SimiGoInformationLoop.retrievalQuery(
                from: "查看分包资料\n<system-reminder>\nskills…"),
            "查看分包资料")
    }

    /// A wrapper the sanitizer does not know still must not own the term list:
    /// terms are read from the tail, where the question is.
    func testKeywordsComeFromTheQuestionNotTheEnvelope() {
        let noise = String(
            repeating: "system reminder following skills available ", count: 40)
        let keywords = SimiGoInformationLoop.keywords(
            in: noise + "查找跟“分包”相关的文件")
        XCTAssertTrue(
            keywords.contains("分包"), "question term must survive: \(keywords)")
        XCTAssertTrue(keywords.contains("文件"))
    }

    /// Two turns whose envelopes differ but whose question is the same are one
    /// demand. That is what makes an exact repeat serveable from the IS instead
    /// of paying a model call.
    func testSameQuestionInDifferentEnvelopesIsOneDemand() throws {
        let (url, db) = try open("envelope-demand")
        defer { db.close(); cleanup(url) }
        let loop = SimiGoInformationLoop(database: db)
        let question = "查找跟“分包”相关的文件"
        let first = try loop.resolve(.init(
            sessionID: "s-env",
            query: SimiGoInformationLoop.retrievalQuery(
                from: Self.clientEnvelope + question),
            includeChat: true, chatSessionIDs: ["s-env"], limit: 30))
        let second = try loop.resolve(.init(
            sessionID: "s-env",
            query: SimiGoInformationLoop.retrievalQuery(
                from: "<system-reminder>\ndate 2026-10-30\n</system-reminder>\n"
                    + question),
            includeChat: true, chatSessionIDs: ["s-env"], limit: 30))
        XCTAssertFalse(first.demandID.isEmpty)
        XCTAssertEqual(first.demandID, second.demandID)
        XCTAssertTrue(second.reused)
    }
}
