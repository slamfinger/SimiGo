import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// ES → IS → ES seam: a demand resolves against a physical index that does not
/// copy entity bytes plus stored chat, the resolution is settled and reusable,
/// and the advancing settlement depends on the retrieval it consumed.
final class InformationLoopTests: XCTestCase {

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

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private func rawText(_ url: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
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

    // MARK: - Index without entity copies

    /// The chat keyword prefilter is a necessary condition, never a filter: a
    /// row it drops could not have produced a citation, and the scope
    /// projection must keep seeing every committed line digest for digest.
    func testChatPrefilterDropsOnlyRowsThatCannotBeCited() throws {
        let (url, db) = try open("chat-prefilter")
        defer { cleanup(url) }
        let turns: [(String, String)] = [
            ("MLX prefill 度量", "MLX 预填 1731 token"),
            ("内存压力", "黄色持续 28 s"),
            ("50% 命中率", "a_b 变量名"),
            ("nothing here", "also nothing"),
        ]
        for (index, turn) in turns.enumerated() {
            let stamp = Date(timeIntervalSince1970: Double(index))
            let userID = try db.appendChatMessage(
                sessionID: "s", role: "user", content: turn.0,
                model: nil, createdAt: stamp)
            try db.commitChatTurn(
                sessionID: "s", userMessageID: userID, assistantText: turn.1,
                model: nil, createdAt: stamp)
        }
        let all = try db.chatIndexRows(sessionIDs: ["s"])
        XCTAssertEqual(all.count, 8)

        let scope = try db.chatScopeRows(sessionIDs: ["s"])
        XCTAssertEqual(scope.map(\.messageID), all.map(\.messageID))
        XCTAssertEqual(scope.map(\.contentSHA256), all.map(\.contentSHA256))

        // Case, CJK and LIKE metacharacters: the prefilter keeps exactly the
        // rows a case-insensitive substring scan would keep.
        for term in ["mlx", "MLX", "预填", "50%", "a_b", "zzz"] {
            let kept = try db.chatIndexRows(sessionIDs: ["s"], matchingAny: [term])
            let expected = all.filter {
                $0.content.lowercased().contains(term.lowercased())
            }
            XCTAssertEqual(kept.map(\.itemID), expected.map(\.itemID), "term \(term)")
        }
    }

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
        XCTAssertThrowsError(
            try db.carriedFileContent(rootID: "work", relativePath: "doc.md")
        ) { error in
            guard case .staleExternalSource(let rootID, let relativePath)? =
                    error as? ESISDatabase.DatabaseError else {
                return XCTFail("expected staleExternalSource, got: \(error)")
            }
            XCTAssertEqual(rootID, "work")
            XCTAssertEqual(relativePath, "doc.md")
        }
    }

    func testSettledFileRowsAppliesMultiRootScopeBeforeMaterializingRows() throws {
        let (url, db) = try open("settled-file-root-scope")
        let rootA = try makeWorkRoot()
        let rootB = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        try write("alpha needle", to: rootA, name: "a.md")
        try write("beta needle", to: rootB, name: "b.md")
        _ = try db.settleWorkRootContents(
            rootID: "root-a", rootURL: rootA, carryText: true)
        _ = try db.settleWorkRootContents(
            rootID: "root-b", rootURL: rootB, carryText: true)

        let scoped = try db.settledFileRows(rootIDs: ["root-b", "root-a", "root-b"])
        XCTAssertEqual(scoped.map(\.rootID), ["root-a", "root-b"])
        XCTAssertEqual(scoped.map(\.relativePath), ["a.md", "b.md"])
        var streamedPaths: [String] = []
        try db.forEachSettledFileRow(rootIDs: ["root-b", "root-a", "root-b"]) { row in
            streamedPaths.append("\(row.rootID)/\(row.relativePath)")
        }
        XCTAssertEqual(streamedPaths, ["root-a/a.md", "root-b/b.md"])

        // Empty scope remains the established all-roots contract.
        let all = try db.settledFileRows(rootIDs: [])
        XCTAssertEqual(Set(all.map(\.rootID)), Set(["root-a", "root-b"]))
        XCTAssertTrue(try db.settledFileRows(rootIDs: ["not-registered"]).isEmpty)
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

        let loop = InformationLoop(database: db)
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

    func testExternalClientDemandReadsOwnChatButNotHostFileRoots() throws {
        let (url, db) = try open("external-client-root-isolation")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("private host file secret needle", to: root, name: "private.md")
        _ = try db.settleWorkRootContents(
            rootID: "owner-work", rootURL: root, carryText: true)

        let clientID = String(repeating: "a", count: 64)
        let sessionID = "mcp-\(clientID)-agent-session"
        let userID = try db.appendChatMessage(
            sessionID: sessionID, role: "user", content: "client needle",
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: sessionID, userMessageID: userID,
            assistantText: "client-owned result", model: nil, createdAt: Date())

        let result = try InformationLoop(database: db).resolve(.init(
            sessionID: sessionID,
            clientIdentityID: clientID,
            query: "needle",
            includeRoots: false,
            includeChat: true,
            chatSessionIDs: []))
        XCTAssertTrue(result.hits.contains { $0.kind == "chat" })
        XCTAssertFalse(result.hits.contains { $0.kind == "file" })
        XCTAssertFalse(result.hits.contains {
            $0.lineText.contains("private host file secret")
        })
    }

    func testDemandCacheIdentityIncludesEffectiveLimitAndExplicitRootScope() throws {
        let (url, db) = try open("demand-cache-limit-scope")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle alpha", to: root, name: "a.md")
        try write("needle beta", to: root, name: "b.md")
        _ = try db.settleWorkRootContents(
            rootID: "limit-root", rootURL: root, carryText: false)

        let loop = InformationLoop(database: db)
        let one = try loop.resolve(.init(
            sessionID: "s-limit", requestIdentity: "request-limit",
            query: "needle", rootIDs: ["limit-root"],
            includeChat: false, limit: 1))
        XCTAssertEqual(one.hits.count, 1)
        XCTAssertFalse(one.reused)

        let two = try loop.resolve(.init(
            sessionID: "s-limit", requestIdentity: "request-limit",
            query: "needle", rootIDs: ["limit-root"],
            includeChat: false, limit: 2))
        XCTAssertEqual(two.hits.count, 2)
        XCTAssertNotEqual(two.demandID, one.demandID)
        XCTAssertFalse(two.reused)

        let twoAgain = try loop.resolve(.init(
            sessionID: "s-limit", requestIdentity: "request-limit",
            query: "needle", rootIDs: ["limit-root"],
            includeChat: false, limit: 2))
        XCTAssertTrue(twoAgain.reused)
        XCTAssertEqual(twoAgain.hits, two.hits)

        // Explicit root scopes with no current file rows still differ. The
        // current source inventory cannot erase the scope the caller named.
        let emptyA = try loop.resolve(.init(
            sessionID: "s-scope", requestIdentity: "request-scope",
            query: "needle", rootIDs: ["empty-a"],
            includeChat: false, limit: 1))
        let emptyB = try loop.resolve(.init(
            sessionID: "s-scope", requestIdentity: "request-scope",
            query: "needle", rootIDs: ["empty-b"],
            includeChat: false, limit: 1))
        XCTAssertTrue(emptyA.hits.isEmpty)
        XCTAssertTrue(emptyB.hits.isEmpty)
        XCTAssertFalse(emptyA.reused)
        XCTAssertFalse(emptyB.reused)
        XCTAssertNotEqual(emptyA.demandID, emptyB.demandID)
    }

    func testResolveBoundsTopKAndKeepsLateHigherScoreCandidate() throws {
        let (url, db) = try open("retrieval-bounded-top-k")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }

        let lowScoreLines = (0..<1_200).map { "needle filler-\($0)" }
        try write((lowScoreLines + ["needle alpha"]).joined(separator: "\n"),
                  to: root, name: "many-matches.md")
        _ = try db.settleWorkRootContents(
            rootID: "top-k-root", rootURL: root, carryText: true)

        let resolution = try InformationLoop(database: db).resolve(.init(
            sessionID: "top-k-session", requestIdentity: "top-k-request",
            query: "needle alpha", rootIDs: ["top-k-root"],
            includeChat: false, limit: 3))

        XCTAssertEqual(resolution.hits.count, 3)
        XCTAssertEqual(resolution.hits.map(\.lineNo), [1_201, 1, 2])
        XCTAssertTrue(resolution.hits[0].lineText.contains("alpha"),
                      "the higher-scoring late candidate must displace earlier lower-scoring matches")
    }

    func testExcludedChatRowsChangeDemandBasisAndReuseOnlyWithinSameScope() throws {
        let (url, db) = try open("chat-exclusion-basis")
        defer { db.close(); cleanup(url) }

        let firstMessageID = try db.appendChatMessage(
            sessionID: "source-chat", role: "assistant",
            content: "needle first row", model: nil, createdAt: Date())
        let secondMessageID = try db.appendChatMessage(
            sessionID: "source-chat", role: "assistant",
            content: "needle second row", model: nil, createdAt: Date())
        let rows = try db.chatIndexRows(sessionIDs: ["source-chat"])
        let first = try XCTUnwrap(rows.first { $0.messageID == firstMessageID })
        let second = try XCTUnwrap(rows.first { $0.messageID == secondMessageID })

        let loop = InformationLoop(database: db)
        let all = try loop.resolve(.init(
            sessionID: "consumer", requestIdentity: "same-request",
            query: "needle", chatSessionIDs: ["source-chat"], limit: 10))
        XCTAssertEqual(Set(all.hits.map(\.itemID)), Set([first.itemID, second.itemID]))

        let filtered = try loop.resolve(.init(
            sessionID: "consumer", requestIdentity: "same-request",
            query: "needle", chatSessionIDs: ["source-chat"],
            excludeItemIDs: [first.itemID], limit: 10))
        XCTAssertNotEqual(filtered.demandID, all.demandID)
        XCTAssertEqual(filtered.hits.map(\.itemID), [second.itemID])
        XCTAssertFalse(filtered.reused)

        let repeated = try loop.resolve(.init(
            sessionID: "consumer", requestIdentity: "same-request",
            query: "needle", chatSessionIDs: ["source-chat"],
            excludeItemIDs: [first.itemID], limit: 10))
        XCTAssertTrue(repeated.reused)
        XCTAssertEqual(repeated.hits, filtered.hits)
    }

    // MARK: - P1/P2: retrieval boundary (measured 2026-10-30)

    // MARK: - Chat turn terminal standing

    func testFailedAndCancelledTurnsAreTerminalAndSameTextRetriesCreateNewRows() throws {
        let (url, db) = try open("chat-turn-terminal-standing")
        defer { db.close(); cleanup(url) }

        let failedText = "terminal-marker-failed-" + UUID().uuidString
        let failedID = try db.appendChatMessage(
            sessionID: "terminal-session", role: "user",
            content: failedText, model: nil, createdAt: Date())
        XCTAssertTrue(
            try db.searchChatMessages(query: "terminal-marker-failed").isEmpty,
            "pending input must never be searchable before the request completes")
        XCTAssertTrue(try db.closePendingChatTurn(
            sessionID: "terminal-session", userMessageID: failedID, terminal: .failed))
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(failedID) + ";"),
            "failed")
        XCTAssertTrue(
            try db.searchChatMessages(query: "terminal-marker-failed").isEmpty,
            "failed user input must not be offered as completed conversation history")

        let failedRetryID = try db.appendChatMessage(
            sessionID: "terminal-session", role: "user",
            content: failedText, model: nil, createdAt: Date())
        XCTAssertNotEqual(failedRetryID, failedID,
                          "a retry after failure needs a fresh pending user row")
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(failedRetryID) + ";"),
            "pending")

        let cancelledText = "terminal-marker-cancelled-" + UUID().uuidString
        let cancelledID = try db.appendChatMessage(
            sessionID: "terminal-session", role: "user",
            content: cancelledText, model: nil, createdAt: Date())
        XCTAssertTrue(try db.closePendingChatTurn(
            sessionID: "terminal-session", userMessageID: cancelledID, terminal: .cancelled))
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(cancelledID) + ";"),
            "cancelled")
        XCTAssertTrue(
            try db.searchChatMessages(query: "terminal-marker-cancelled").isEmpty,
            "cancelled user input must not be offered as completed conversation history")
        XCTAssertFalse(try db.closePendingChatTurn(
            sessionID: "terminal-session", userMessageID: failedID, terminal: .cancelled),
            "a terminal row cannot be rewritten by a later cleanup pass")

        let detachedText = "terminal-marker-detached-" + UUID().uuidString
        let detachedID = try db.appendChatMessage(
            sessionID: "terminal-session", role: "user",
            content: detachedText, model: nil, createdAt: Date())
        XCTAssertTrue(try db.closePendingChatTurn(
            sessionID: "terminal-session", userMessageID: detachedID, terminal: .detached))
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(detachedID) + ";"),
            "detached")
        XCTAssertTrue(
            try db.searchChatMessages(query: "terminal-marker-detached").isEmpty,
            "detached generation input is preserved as non-retrievable history")
        let detachedRetryID = try db.appendChatMessage(
            sessionID: "terminal-session", role: "user",
            content: detachedText, model: nil, createdAt: Date())
        XCTAssertNotEqual(detachedRetryID, detachedID,
                          "a retry after detach starts a new semantic turn")
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(detachedRetryID) + ";"),
            "pending")
    }

    /// A turn whose process ended mid-request leaves a `pending` row that says
    /// "still in flight" forever. The launch sweep is the only thing that can
    /// close it, and it must not reach a row this process is serving.
    func testStrandedPendingTurnsCloseAtLaunchAndLiveTurnsSurvive() throws {
        let (url, db) = try open("chat-turn-stranded")
        defer { db.close(); cleanup(url) }

        let launchedAt = Date()
        let strandedID = try db.appendChatMessage(
            sessionID: "stranded-session", role: "user",
            content: "question from the killed process", model: nil,
            createdAt: launchedAt.addingTimeInterval(-600))
        let liveID = try db.appendChatMessage(
            sessionID: "live-session", role: "user",
            content: "question this process is still answering", model: nil,
            createdAt: launchedAt.addingTimeInterval(60))

        XCTAssertEqual(try db.closeStrandedPendingTurns(launchedAt: launchedAt), 1)
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(strandedID) + ";"),
            "abandoned")
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(liveID) + ";"),
            "pending", "a row written after launch belongs to a live request")
        XCTAssertEqual(try db.closeStrandedPendingTurns(launchedAt: launchedAt), 0,
                       "the sweep is idempotent")

        XCTAssertTrue(
            try db.searchChatMessages(query: "question from the killed process").isEmpty,
            "an abandoned question is not completed conversation history")
        let retryID = try db.appendChatMessage(
            sessionID: "stranded-session", role: "user",
            content: "question from the killed process", model: nil, createdAt: Date())
        XCTAssertNotEqual(retryID, strandedID,
                          "a retry must not adopt a row whose request already ended")
    }

    func testCommittedTurnWithSameTextStartsANewSemanticTurn() throws {
        let (url, db) = try open("chat-turn-committed-dedupe")
        defer { db.close(); cleanup(url) }
        let text = "same words after a completed answer"
        let firstID = try db.appendChatMessage(
            sessionID: "completed-session", role: "user",
            content: text, model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: "completed-session", userMessageID: firstID,
            assistantText: "first answer", model: nil, createdAt: Date())
        let secondID = try db.appendChatMessage(
            sessionID: "completed-session", role: "user",
            content: text, model: nil, createdAt: Date())
        XCTAssertNotEqual(secondID, firstID,
                          "completed turns are history, not pending retry rows")
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(firstID) + ";"),
            "committed")
        XCTAssertEqual(
            try rawText(url, "SELECT turn_state FROM chat_messages WHERE id=" + String(secondID) + ";"),
            "pending")
    }

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

        let loop = InformationLoop(database: db)
        let resolution = try loop.resolve(.init(query: "needle-tail", includeChat: false))
        let hit = try XCTUnwrap(resolution.hits.first { $0.itemID == "file:work/a.md" })
        XCTAssertTrue(hit.lineText.contains("needle-tail"))
        XCTAssertLessThanOrEqual(hit.lineText.count, 242)
        XCTAssertTrue(
            hit.lineText.hasPrefix("…"),
            "the window starts near the match, not at the line's beginning")
    }

    /// A settled source that disappears must be reported stale, not abort the
    /// retrieval. Measured 2026-11-10 on the live space: one deleted Codex
    /// rollout made every `simigo_is_search` call fail with the raw open error,
    /// so no local agent could read the space at all — while the code already
    /// carried a stale list that nothing could reach.
    ///
    /// A path that now leads elsewhere is a different statement: it stays a
    /// loud refusal, because silently reading the new target is exactly the
    /// redirection the no-follow reader exists to stop.
    func testUnavailableSettledSourceIsTransientNotFatal() throws {
        let (url, db) = try open("stale-source")
        let root = try makeWorkRoot()
        defer {
            db.close()
            cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle survives in this file", to: root, name: "a.md")
        try write("this file is about to vanish", to: root, name: "b.md")
        try write("this file is about to be redirected", to: root, name: "c.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)

        let loop = InformationLoop(database: db)
        try FileManager.default.removeItem(at: root.appendingPathComponent("b.md"))
        let resolution = try loop.resolve(.init(
            sessionID: "s", query: "needle", includeChat: false))
        XCTAssertTrue(resolution.unavailableSourceIDs.contains("file:work/b.md"))
        XCTAssertFalse(resolution.changedSourceIDs.contains("file:work/b.md"))
        XCTAssertEqual(
            try rawText(url, """
            SELECT status FROM external_files
             WHERE root_id='work' AND relative_path='b.md';
            """), "present", "unavailability is not persisted as a source status")
        let stored = try XCTUnwrap(
            db.informationRetrievalPayload(demandID: resolution.demandID))
        let storedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: stored) as? [String: Any])
        XCTAssertEqual(storedJSON["staleItemIDs"] as? [String], [])
        XCTAssertNil(storedJSON["unavailableSourceIDs"],
                     "the unavailable verdict belongs to this call only")
        let repeated = try loop.resolve(.init(
            sessionID: "s", query: "needle", includeChat: false))
        XCTAssertTrue(repeated.reused)
        XCTAssertEqual(repeated.unavailableSourceIDs, ["file:work/b.md"])
        XCTAssertTrue(
            resolution.hits.contains { $0.itemID == "file:work/a.md" },
            "the readable source still answers")

        // Redirected, not gone: still refused.
        try FileManager.default.removeItem(at: root.appendingPathComponent("c.md"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("c.md"),
            withDestinationURL: root.appendingPathComponent("a.md"))
        XCTAssertThrowsError(
            try loop.resolve(.init(
                sessionID: "s", query: "needle again", includeChat: false)),
            "a symlinked source must refuse rather than follow")

        // The whole root going away is the same statement, one level up.
        try FileManager.default.removeItem(at: root)
        let gone = try loop.resolve(.init(
            sessionID: "s", query: "needle a third time", includeChat: false))
        XCTAssertTrue(gone.hits.isEmpty)
        XCTAssertEqual(
            gone.unavailableSourceIDs.sorted(),
            ["file:work/a.md", "file:work/b.md", "file:work/c.md"])
        XCTAssertTrue(gone.changedSourceIDs.isEmpty)
    }

    /// A user line whose own request has not completed is not history. Measured
    /// 2026-10-30: four Codex requests shared one session and the greeting
    /// retrieved a background rollout prompt that was still in flight.
    func testInFlightUserTextIsNotRetrievable() throws {
        let (url, db) = try open("in-flight")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

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
        let loop = InformationLoop(database: db)

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
        let loop = InformationLoop(database: db)

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

        let loop = InformationLoop(database: db)
        // The request identity is the demand's lifecycle: without one, each
        // call is its own request even though the knowledge stays shared.
        let omega = try loop.resolve(.init(
            requestIdentity: "omega-request", query: "omega", includeChat: false))
        let zeta = try loop.resolve(.init(
            requestIdentity: "zeta-request", query: "zeta", includeChat: false))
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
        let again = try loop.resolve(.init(
            requestIdentity: "omega-request", query: "omega", includeChat: false))
        XCTAssertTrue(again.reused)
        XCTAssertEqual(again.demandID, omega.demandID)

        // A root scan observes changed file bytes, but item validity is not
        // guessed from the whole-file digest. The old result remains available
        // until the agent re-reads the query scope and compares the consumed item.
        try write("omega appears here, revised", to: root, name: "a.md")
        let report = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        XCTAssertEqual(report.invalidatedSettlements, 0)
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlement_current_validity WHERE settlement_id='\(omega.retrievalSettlementID)';
        """), "valid")
        XCTAssertNotNil(try db.informationRetrievalPayload(demandID: omega.demandID))

        let after = try loop.resolve(.init(
            requestIdentity: "omega-request", query: "omega", includeChat: false))
        XCTAssertFalse(after.reused)
        XCTAssertNotEqual(after.demandID, omega.demandID)
        XCTAssertEqual(after.hits.first?.lineText, "omega appears here, revised")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlement_current_validity WHERE settlement_id='\(omega.retrievalSettlementID)';
        """), "invalid", "only the item re-observation invalidates the pinned result")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlement_current_validity WHERE settlement_id='\(zeta.retrievalSettlementID)';
        """), "valid", "an unrelated item remains valid")
        XCTAssertNil(try db.informationRetrievalPayload(demandID: omega.demandID))
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

        let loop = InformationLoop(database: db)
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

        // Root scan only observed file-level bytes; it did not re-extract the
        // consumed keyword item, so it cannot yet classify the item as changed.
        XCTAssertEqual(report.invalidatedSettlements, 0)
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlement_current_validity WHERE settlement_id='\(omegaRetrieval)';
        """), "valid")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlement_current_validity WHERE settlement_id='\(omegaTurn)';
        """), "valid")
        XCTAssertNotNil(try db.informationRetrievalPayload(demandID: omegaDemand))

        // A successful re-read of that keyword scope observes the changed item
        // and invalidates its retrieval plus the model turn that consumed it.
        let omegaReobserved = try loop.resolve(.init(
            requestIdentity: "omega-after-source-update",
            query: "omega", includeChat: false))
        XCTAssertEqual(omegaReobserved.hits.first?.lineText, "omega distance 7.2m")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlement_current_validity WHERE settlement_id='\(omegaRetrieval)';
        """), "invalid")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlement_current_validity WHERE settlement_id='\(omegaTurn)';
        """), "invalid", "a conclusion built from changed evidence does not stay citable")
        XCTAssertEqual(try rawText(url, """
        SELECT validity FROM settlement_current_validity WHERE settlement_id='\(zetaTurn)';
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

        let loop = InformationLoop(database: db)
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

        let loop = InformationLoop(database: db)
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
        let expected = SettlementIdentityBinding.bindings(
            for: .init(model: "m", tokenizer: "t"))
        XCTAssertEqual(
            bindings[SettlementIdentityBinding.modelKey],
            expected[SettlementIdentityBinding.modelKey])
        XCTAssertEqual(
            bindings[SettlementIdentityBinding.tokenizerKey],
            expected[SettlementIdentityBinding.tokenizerKey])
    }


    func testInformationRetrievalReplayIsIdempotentAndCannotReplacePayload() throws {
        let (url, db) = try open("retrieval-payload-identity")
        defer { db.close(); cleanup(url) }

        let write = ESISDatabase.InformationRetrievalWrite(
            demandID: "demand-retrieval-identity",
            stateID: nil,
            sessionID: "s-retrieval-identity",
            requestIdentity: "request-retrieval-identity",
            query: "same question",
            rootIDs: [],
            includeChat: false,
            inputDigest: "basis-v1",
            payload: Data("original retrieval result".utf8),
            hitCount: 1,
            itemIDs: ["settlement:source"],
            inputs: [])
        let first = try db.recordInformationRetrieval(write)

        func persistedCounts() throws -> [String: Int] {
            let tables = [
                "settlements", "retrieval_settlements", "information_demands",
                "settlement_validity_events", "is_objects", "is_index_entries",
            ]
            return try Dictionary(uniqueKeysWithValues: tables.map { ($0, try db.count($0)) })
        }
        let countsAfterFirstWrite = try persistedCounts()

        // An exact retry returns the original commit and is a write-free no-op.
        let replay = try db.recordInformationRetrieval(write)
        XCTAssertEqual(replay, first)
        XCTAssertEqual(try persistedCounts(), countsAfterFirstWrite)

        // The same demand ID cannot acquire a different settled result: downstream
        // settlement dependencies point at this stable retrieval settlement ID.
        let replacement = ESISDatabase.InformationRetrievalWrite(
            demandID: write.demandID,
            stateID: write.stateID,
            sessionID: write.sessionID,
            requestIdentity: write.requestIdentity,
            query: write.query,
            rootIDs: write.rootIDs,
            includeChat: write.includeChat,
            inputDigest: write.inputDigest,
            payload: Data("replacement retrieval result".utf8),
            hitCount: write.hitCount,
            itemIDs: write.itemIDs,
            inputs: write.inputs)
        XCTAssertThrowsError(try db.recordInformationRetrieval(replacement)) { error in
            XCTAssertEqual(
                error as? ESISDatabase.InformationDemandError,
                .retrievalPayloadConflict(
                    demandID: write.demandID,
                    existingSHA256: first.resultSHA256,
                    requestedSHA256: NativeSHA256.hexDigest(replacement.payload)))
        }
        XCTAssertEqual(
            try db.informationRetrievalPayload(demandID: write.demandID), write.payload)
        XCTAssertEqual(
            try db.settlementReceipt(first.retrievalSettlementID)?.payloadObjectID,
            first.resultObjectID)
        XCTAssertEqual(try persistedCounts(), countsAfterFirstWrite)
    }

    /// Invalidation closes the payload's validity window but does not walk
    /// `information_demands.state` back, so a settled demand can keep its
    /// RESOLVED row and still have no readable payload. That is not a cache
    /// miss: the id is immutable, so the write would refuse anyway. The refusal
    /// must name the settlement, not claim the demand was never settled.
    ///
    /// Boundary: this pins the error identity and the state invariant only. The
    /// evaluation still runs first — the demand id is derived from it — so the
    /// test says nothing about scan cost.
    func testInvalidatedRetrievalSettlementIsRefusedWithSettlementIdentity() throws {
        let (url, db) = try open("retrieval-invalidated-cache")
        defer { db.close(); cleanup(url) }
        _ = try db.appendChatMessage(
            sessionID: "source-chat", role: "assistant",
            content: "needle survives only while the settlement does",
            model: nil, createdAt: Date())
        let loop = InformationLoop(database: db)
        let demand = InformationLoop.Demand(
            sessionID: "consumer-invalidated",
            requestIdentity: "request-invalidated",
            query: "needle",
            includeChat: true,
            chatSessionIDs: ["source-chat"])
        let first = try loop.resolve(demand)
        XCTAssertFalse(first.reused)

        _ = try db.invalidateSettlement(first.retrievalSettlementID)
        XCTAssertNil(try db.informationRetrievalPayload(demandID: first.demandID))
        XCTAssertEqual(
            try db.informationDemand(demandID: first.demandID)?.state, "RESOLVED",
            "invalidation must not rewrite the demand row, which is why the state"
                + " alone cannot tell a lost payload from a never-settled demand")

        XCTAssertThrowsError(try loop.resolve(demand)) { error in
            guard let demandError = error as? ESISDatabase.InformationDemandError,
                  case .retrievalSettlementUnavailable(let settlementID) = demandError
            else {
                return XCTFail("expected settlement-unavailable refusal, got: \(error)")
            }
            XCTAssertEqual(settlementID, first.retrievalSettlementID)
        }
    }

    /// A demand id only says "same query basis", and the basis does not observe
    /// every way a stored result can stop being the truth. Rewriting chat bytes
    /// out of band leaves the scope watermark and the demand id untouched, so
    /// reuse keyed on the id alone would answer with a result the current
    /// evaluation no longer produces. The cache must be refused, not served,
    /// and the settled payload stays exactly as it was.
    func testCachedRetrievalDoesNotSurviveChatContentDigestMismatch() throws {
        let (url, db) = try open("chat-cache-digest-mismatch")
        defer { db.close(); cleanup(url) }
        let messageID = try db.appendChatMessage(
            sessionID: "source-chat", role: "assistant",
            content: "needle is in the original note",
            model: nil, createdAt: Date())
        let loop = InformationLoop(database: db)
        let demand = InformationLoop.Demand(
            sessionID: "consumer",
            requestIdentity: "request-chat-cache",
            query: "needle",
            includeChat: true,
            chatSessionIDs: ["source-chat"])
        let first = try loop.resolve(demand)
        XCTAssertEqual(first.hits.map(\.itemID), ["chat:source-chat/\(messageID)"])
        XCTAssertFalse(first.reused)
        let originalPayload = try XCTUnwrap(
            try db.informationRetrievalPayload(demandID: first.demandID))

        // The mutation keeps the row's identity and stored digest and only moves
        // the bytes the result cited.
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
        defer { sqlite3_close(raw) }
        let mutation = "UPDATE chat_messages SET content_object_id=NULL, "
            + "content='changed bytes' WHERE id=\(messageID);"
        XCTAssertEqual(sqlite3_exec(raw, mutation, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try loop.resolve(demand)) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .sql(let detail) = databaseError else {
                return XCTFail("expected cached-result divergence refusal, got: \(error)")
            }
            XCTAssertTrue(detail.contains("cached retrieval result diverges"), detail)
        }
        XCTAssertEqual(
            try db.informationRetrievalPayload(demandID: first.demandID),
            originalPayload,
            "a refused cache read must not rewrite the settled retrieval")
    }

    func testAdvancedDemandCannotBeReopenedAsResolved() throws {
        let (url, db) = try open("demand-no-regression")
        let root = try makeWorkRoot()
        defer { db.close(); cleanup(url); try? FileManager.default.removeItem(at: root) }
        try write("needle", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        let loop = InformationLoop(database: db)
        let resolution = try loop.resolve(.init(
            sessionID: "s-demand", requestIdentity: "request-1",
            query: "needle", includeChat: false))
        let settled = try loop.settleTurn(
            generatedText: "answer", resolution: resolution,
            stateID: "S-demand", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-demand")
        XCTAssertEqual(try db.informationDemand(demandID: resolution.demandID)?.state, "ADVANCED")

        let replay = ESISDatabase.InformationRetrievalWrite(
            demandID: resolution.demandID, stateID: nil,
            sessionID: "s-demand", requestIdentity: "request-1",
            query: "needle", rootIDs: ["work"], includeChat: false,
            inputDigest: resolution.inputDigest,
            payload: Data("replacement retrieval".utf8),
            hitCount: 0, itemIDs: [], inputs: [])
        XCTAssertThrowsError(try db.recordInformationRetrieval(replay)) { error in
            XCTAssertEqual(
                error as? ESISDatabase.InformationDemandError,
                .invalidTransition(
                    demandID: resolution.demandID, from: "ADVANCED", to: "RESOLVED"))
        }
        XCTAssertEqual(try db.informationDemand(demandID: resolution.demandID)?.state, "ADVANCED")
        XCTAssertEqual(try db.count("information_advancements"), 1)
        XCTAssertEqual(try db.settlementValidity(settled.settlementID), "valid")
    }

    func testSupersededOrMissingDemandCannotBeAdvanced() throws {
        let (url, db) = try open("demand-advance-guards")
        defer { db.close(); cleanup(url) }
        func retrieval(_ id: String) throws {
            _ = try db.recordInformationRetrieval(.init(
                demandID: id, stateID: nil, sessionID: "s-supersede",
                requestIdentity: "request-shared", query: "same question",
                rootIDs: [], includeChat: false, inputDigest: id,
                payload: Data("{\"result\":\"ok\"}".utf8),
                hitCount: 0, itemIDs: [], inputs: []))
        }
        try retrieval("demand-old")
        try retrieval("demand-new")
        XCTAssertEqual(try db.informationDemand(demandID: "demand-old")?.state, "SUPERSEDED")
        XCTAssertEqual(try db.informationDemand(demandID: "demand-new")?.state, "RESOLVED")

        let producer = try InformationLoop(database: db).settleTurn(
            generatedText: "answer", resolution: nil,
            stateID: "S-advance-guard", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: nil)
        let oldWrite = ESISDatabase.InformationAdvancementWrite(
            demandID: "demand-old", stateID: "S-advance-guard",
            settlementID: producer.settlementID,
            retrievalSettlementID: "is-retrieval:demand-old",
            actions: ["chat.completion"], result: Data("answer".utf8))
        XCTAssertThrowsError(try db.recordInformationAdvancement(oldWrite)) { error in
            XCTAssertEqual(
                error as? ESISDatabase.InformationDemandError,
                .invalidTransition(
                    demandID: "demand-old", from: "SUPERSEDED", to: "ADVANCED"))
        }
        let missingWrite = ESISDatabase.InformationAdvancementWrite(
            demandID: "does-not-exist", stateID: "S-advance-guard",
            settlementID: producer.settlementID,
            retrievalSettlementID: "is-retrieval:does-not-exist",
            actions: ["chat.completion"], result: Data("answer".utf8))
        XCTAssertThrowsError(try db.recordInformationAdvancement(missingWrite)) { error in
            XCTAssertEqual(
                error as? ESISDatabase.InformationDemandError,
                .missingDemand("does-not-exist"))
        }
        XCTAssertEqual(try db.count("information_advancements"), 0)

        let newWrite = ESISDatabase.InformationAdvancementWrite(
            demandID: "demand-new", stateID: "S-advance-guard",
            settlementID: producer.settlementID,
            retrievalSettlementID: "is-retrieval:demand-new",
            actions: ["chat.completion"], result: Data("answer".utf8))
        _ = try db.recordInformationAdvancement(newWrite)
        XCTAssertEqual(try db.informationDemand(demandID: "demand-new")?.state, "ADVANCED")
    }


    func testSettleTurnCommitsChatAndESISAtomically() throws {
        let (url, db) = try open("atomic-chat-settlement")
        let root = try makeWorkRoot()
        defer { db.close(); cleanup(url); try? FileManager.default.removeItem(at: root) }
        try write("needle", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        let userID = try db.appendChatMessage(
            sessionID: "s-atomic", role: "user", content: "needle?", model: nil, createdAt: Date())
        let loop = InformationLoop(database: db)
        let resolution = try loop.resolve(.init(
            sessionID: "s-atomic", query: "needle", includeChat: false))
        let turn = try loop.settleTurn(
            generatedText: "the answer", resolution: resolution,
            stateID: "S-atomic", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-atomic",
            chatTurn: .init(
                sessionID: "s-atomic", userMessageID: userID,
                assistantText: "the answer", model: "model-a", createdAt: Date()))
        XCTAssertEqual(try rawText(url,
            "SELECT turn_state FROM chat_messages WHERE id=" + String(userID) + ";"), "committed")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM settlements WHERE settlement_id='" + turn.settlementID + "';"), "1")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM information_advancements WHERE settlement_id='" + turn.settlementID + "';"), "1")
        XCTAssertEqual(try db.currentChatStateID(sessionID: "s-atomic"), "S-atomic")
    }

    func testSettlementRefusesChatCommitWhenUserRowIsNotOwnedBySession() throws {
        let (url, db) = try open("atomic-chat-user-row-mismatch")
        let root = try makeWorkRoot()
        defer { db.close(); cleanup(url); try? FileManager.default.removeItem(at: root) }
        try write("needle", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        let foreignUserID = try db.appendChatMessage(
            sessionID: "s-foreign", role: "user", content: "needle?",
            model: nil, createdAt: Date())
        let resolution = try InformationLoop(database: db).resolve(
            .init(sessionID: "s-atomic", query: "needle", includeChat: false))

        XCTAssertThrowsError(try InformationLoop(database: db).settleTurn(
            generatedText: "the answer", resolution: resolution,
            stateID: "S-atomic-user-row-mismatch", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-atomic",
            chatTurn: .init(
                sessionID: "s-atomic", userMessageID: foreignUserID,
                assistantText: "the answer", model: "model-a", createdAt: Date())))

        XCTAssertEqual(try rawText(url,
            "SELECT turn_state FROM chat_messages WHERE id=" + String(foreignUserID) + ";"),
            "pending")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM chat_messages WHERE session_id='s-atomic' AND role='assistant';"),
            "0")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM execution_states WHERE state_id='S-atomic-user-row-mismatch';"),
            "0")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM settlements WHERE state_id='S-atomic-user-row-mismatch';"),
            "0")
    }

    func testSettlementRefusesChatCommitWhenPendingUserRowIsMissing() throws {
        let (url, db) = try open("atomic-chat-user-row-missing")
        let root = try makeWorkRoot()
        defer { db.close(); cleanup(url); try? FileManager.default.removeItem(at: root) }
        try write("needle", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        let resolution = try InformationLoop(database: db).resolve(
            .init(sessionID: "s-missing", query: "needle", includeChat: false))

        XCTAssertThrowsError(try InformationLoop(database: db).settleTurn(
            generatedText: "the answer", resolution: resolution,
            stateID: "S-atomic-user-row-missing", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-missing",
            chatTurn: .init(
                sessionID: "s-missing", userMessageID: -1,
                assistantText: "the answer", model: "model-a", createdAt: Date())))

        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM chat_messages WHERE session_id='s-missing' AND role='assistant';"),
            "0")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM execution_states WHERE state_id='S-atomic-user-row-missing';"),
            "0")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM settlements WHERE state_id='S-atomic-user-row-missing';"),
            "0")
    }

    func testReusedChatTurnAndReuseEventCommitAtomically() throws {
        let (url, db) = try open("atomic-chat-reuse")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)
        let source = try loop.settleTurn(
            generatedText: "previous settled answer", resolution: nil,
            stateID: "S-reuse-source", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: nil)
        let userID = try db.appendChatMessage(
            sessionID: "s-reuse", role: "user", content: "repeat question",
            model: nil, createdAt: Date())

        var handle: OpaquePointer?
        let openRC = sqlite3_open(url.path, &handle)
        XCTAssertEqual(openRC, SQLITE_OK)
        let sqlite = try XCTUnwrap(handle)
        defer { sqlite3_close(sqlite) }
        let trigger = """
        CREATE TRIGGER abort_atomic_reuse_event
        BEFORE INSERT ON information_reuse_events
        BEGIN SELECT RAISE(ABORT, 'injected reuse event failure'); END;
        """
        XCTAssertEqual(sqlite3_exec(sqlite, trigger, nil, nil, nil), SQLITE_OK)

        let chatTurn = ESISDatabase.ChatTurnCommit(
            sessionID: "s-reuse", userMessageID: userID,
            assistantText: "previous settled answer", model: "model-a",
            createdAt: Date())
        XCTAssertThrowsError(try db.commitReusedChatTurn(
            chatTurn, sourceSettlementID: source.settlementID,
            sourceStateID: "S-reuse-source", demandID: "D-reuse",
            query: "repeat question"))
        XCTAssertEqual(try rawText(url,
            "SELECT turn_state FROM chat_messages WHERE id=" + String(userID) + ";"),
            "pending")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM chat_messages WHERE session_id='s-reuse' AND role='assistant';"),
            "0")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM information_reuse_events WHERE demand_id='D-reuse';"),
            "0")

        XCTAssertEqual(sqlite3_exec(sqlite, "DROP TRIGGER abort_atomic_reuse_event;", nil, nil, nil), SQLITE_OK)
        _ = try db.commitReusedChatTurn(
            chatTurn, sourceSettlementID: source.settlementID,
            sourceStateID: "S-reuse-source", demandID: "D-reuse",
            query: "repeat question")
        let transcript = try db.listChatMessages(sessionID: "s-reuse")
        XCTAssertEqual(transcript.count, 2)
        XCTAssertEqual(transcript[0].content, "repeat question")
        XCTAssertEqual(try rawText(url,
            "SELECT turn_state FROM chat_messages WHERE id=" + String(userID) + ";"),
            "committed")
        XCTAssertEqual(transcript[1].content, "previous settled answer")
        XCTAssertEqual(try db.informationReuseEvent(demandID: "D-reuse")?.sourceSettlementID,
                       source.settlementID)
    }

    func testSettlementFailureRollsBackChatPromotionAndAssistantRow() throws {
        let (url, db) = try open("atomic-chat-rollback")
        let root = try makeWorkRoot()
        defer { db.close(); cleanup(url); try? FileManager.default.removeItem(at: root) }
        try write("needle", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        let userID = try db.appendChatMessage(
            sessionID: "s-rollback", role: "user", content: "needle?", model: nil, createdAt: Date())
        let resolution = try InformationLoop(database: db).resolve(
            .init(sessionID: "s-rollback", query: "needle", includeChat: false))
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        let trigger = """
        CREATE TRIGGER abort_atomic_settlement_binding
        BEFORE INSERT ON settlement_bindings
        BEGIN SELECT RAISE(ABORT, 'injected settlement binding failure'); END;
        """
        XCTAssertEqual(sqlite3_exec(handle, trigger, nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try InformationLoop(database: db).settleTurn(
            generatedText: "the answer", resolution: resolution,
            stateID: "S-rollback", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-rollback",
            chatTurn: .init(
                sessionID: "s-rollback", userMessageID: userID,
                assistantText: "the answer", model: "model-a", createdAt: Date())))
        XCTAssertEqual(try rawText(url,
            "SELECT turn_state FROM chat_messages WHERE id=" + String(userID) + ";"), "pending")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM chat_messages WHERE session_id='s-rollback' AND role='assistant';"), "0")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM execution_states WHERE state_id='S-rollback';"), "0")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM settlements WHERE state_id='S-rollback';"), "0")
    }

    func testExistingContinuationSettlementCommitsResponsesChatAndAdvancementAtomically() throws {
        let (url, db) = try open("atomic-existing-settlement")
        let root = try makeWorkRoot()
        defer { db.close(); cleanup(url); try? FileManager.default.removeItem(at: root) }
        try write("needle", to: root, name: "a.md")
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        let loop = InformationLoop(database: db)
        let resolution = try loop.resolve(.init(
            sessionID: "s-existing", query: "needle", includeChat: false))
        let producer = try loop.settleTurn(
            generatedText: "continuation result", resolution: nil,
            stateID: "S-existing", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: nil, summaryQuery: "continuation result")
        let userID = try db.appendChatMessage(
            sessionID: "s-existing", role: "user", content: "needle?", model: nil, createdAt: Date())
        _ = try db.commitChatTurnWithExistingSettlement(
            .init(
                sessionID: "s-existing", userMessageID: userID,
                assistantText: "continuation result", model: "model-a", createdAt: Date()),
            settlementID: producer.settlementID, stateID: "S-existing",
            modelIdentity: "model-a", demandID: resolution.demandID,
            retrievalSettlementID: resolution.retrievalSettlementID,
            actions: ["responses.completion"], query: "needle")
        XCTAssertEqual(try rawText(url,
            "SELECT turn_state FROM chat_messages WHERE id=" + String(userID) + ";"), "committed")
        XCTAssertEqual(try rawText(url,
            "SELECT COUNT(*) FROM information_advancements WHERE settlement_id='" + producer.settlementID + "';"), "1")
        XCTAssertEqual(try db.currentChatStateID(sessionID: "s-existing"), "S-existing")
        XCTAssertNotNil(try db.settlementSummary(settlementID: producer.settlementID))
    }

    func testSettlementSummaryIsRecordedAndCitedByLaterDemand() throws {
        let (url, db) = try open("summary-cite")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        let turn = try loop.settleTurn(
            generatedText: "跨江大桥项目的施工组织设计应覆盖关键线路与节点工期，并配置相应生产资源。",
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

    func testCitableSettlementSummariesPropagatesSQLiteObjectReadFailure() throws {
        let (url, db) = try open("summary-object-read-failure")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)
        let longQuery = String(repeating: "q", count: 4_096)

        let turn = try loop.settleTurn(
            generatedText: "A settled conclusion with enough detail to be summarized.",
            resolution: nil,
            stateID: "S-SUM-READ-FAILURE",
            parentStateID: nil,
            position: 0,
            modelIdentity: "model-a",
            identity: .init(model: "m", tokenizer: "t"),
            sessionID: "s-alpha",
            summaryQuery: longQuery,
            actions: ["chat.completion"])
        XCTAssertNotNil(try db.settlementSummary(settlementID: turn.settlementID))

        // The table stores only a 200-character query excerpt, while the sealed
        // content-addressed object retains the full query. Keep the summary row
        // readable but make its object exceed SQLite's configured value limit.
        let previousLimit = db.setSQLiteLengthLimitForTesting(1_024)
        defer { _ = db.setSQLiteLengthLimitForTesting(previousLimit) }

        XCTAssertThrowsError(
            try db.citableSettlementSummaries(sessionID: "s-beta")
        ) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .executionFailure(let primary, let extended, _) = databaseError
            else {
                return XCTFail("expected a typed SQLite object-read failure, got: \(error)")
            }
            XCTAssertEqual(primary, SQLITE_TOOBIG)
            XCTAssertEqual(extended, SQLITE_TOOBIG)
        }
    }

    func testInvalidatedSettlementSummaryIsNotCited() throws {
        let (url, db) = try open("summary-invalid")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

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
        let loop = InformationLoop(database: db)

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

    /// Identical text is not a request identity. A retry is a distinct request
    /// and must receive its own pending row so another request cannot terminalize it.
    func testRepeatedOrdinaryUserTurnsRemainRequestScoped() throws {
        let (url, db) = try open("chat-request-scoped")
        defer { db.close(); cleanup(url) }
        let question = "查找跟“合同”相关的文件"
        try db.appendChatMessage(
            sessionID: "s10", role: "user", content: question, model: "m", createdAt: Date())
        try db.appendChatMessage(
            sessionID: "s10", role: "assistant", content: "…", model: "m", createdAt: Date())
        try db.appendChatMessage(
            sessionID: "s10", role: "user", content: question, model: "m", createdAt: Date())
        XCTAssertEqual(
            try db.listChatMessages(sessionID: "s10").filter { $0.role == "user" }.count, 2)

        // A later identical question is another request as well.
        try db.appendChatMessage(
            sessionID: "s10", role: "user", content: "另一个问题", model: "m", createdAt: Date())
        try db.appendChatMessage(
            sessionID: "s10", role: "user", content: question, model: "m", createdAt: Date())
        XCTAssertEqual(
            try db.listChatMessages(sessionID: "s10").filter { $0.role == "user" }.count, 4)
    }

    func testIdenticalInternalOperationRowsRemainDeduplicated() throws {
        let (url, db) = try open("internal-dedupe")
        defer { db.close(); cleanup(url) }
        let content = "Generate a concise title for this conversation"
        let first = try db.appendChatMessage(
            sessionID: "s-internal", role: "user", content: content,
            model: nil, createdAt: Date(), eligibility: .internalOperation)
        let duplicate = try db.appendChatMessage(
            sessionID: "s-internal", role: "user", content: content,
            model: nil, createdAt: Date(), eligibility: .internalOperation)
        XCTAssertEqual(first, duplicate,
                       "identical internal bookkeeping rows retain their suppression")

        let ordinary = try db.appendChatMessage(
            sessionID: "s-internal", role: "user", content: content,
            model: nil, createdAt: Date())
        XCTAssertNotEqual(ordinary, first,
                          "an ordinary request must never adopt an internal row")
        XCTAssertEqual(try db.listChatMessages(sessionID: "s-internal").filter {
            $0.role == "user"
        }.count, 2)
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
        let question = "查找跟“合同”相关的文件"
        XCTAssertEqual(
            InformationLoop.retrievalQuery(from: Self.clientEnvelope + question),
            question)
        XCTAssertEqual(
            InformationLoop.retrievalQuery(from: question + "\n" + Self.clientEnvelope),
            question,
            "removal is by block, not by position")
    }

    func testRetrievalQueryKeepsPlainQuestionAndDropsUnclosedTail() {
        XCTAssertEqual(
            InformationLoop.retrievalQuery(from: "  查看跟合同管理相关的资料 \n"),
            "查看跟合同管理相关的资料")
        XCTAssertEqual(
            InformationLoop.retrievalQuery(
                from: "查看合同资料\n<system-reminder>\nskills…"),
            "查看合同资料")
    }

    /// A wrapper the sanitizer does not know still must not own the term list:
    /// terms are read from the tail, where the question is.
    func testKeywordsComeFromTheQuestionNotTheEnvelope() {
        let noise = String(
            repeating: "system reminder following skills available ", count: 40)
        let keywords = InformationLoop.keywords(
            in: noise + "查找跟“合同”相关的文件")
        XCTAssertTrue(
            keywords.contains("合同"), "question term must survive: \(keywords)")
        XCTAssertTrue(keywords.contains("文件"))
    }

    /// Two turns whose envelopes differ but whose question is the same are one
    /// demand. That is what makes an exact repeat serveable from the IS instead
    /// of paying a model call.
    func testSameQuestionInDifferentEnvelopesIsOneDemand() throws {
        let (url, db) = try open("envelope-demand")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)
        let question = "查找跟“合同”相关的文件"
        let first = try loop.resolve(.init(
            sessionID: "s-env",
            query: InformationLoop.retrievalQuery(
                from: Self.clientEnvelope + question),
            includeChat: true, chatSessionIDs: ["s-env"], limit: 30))
        let second = try loop.resolve(.init(
            sessionID: "s-env",
            query: InformationLoop.retrievalQuery(
                from: "<system-reminder>\ndate 2026-10-30\n</system-reminder>\n"
                    + question),
            includeChat: true, chatSessionIDs: ["s-env"], limit: 30))
        XCTAssertFalse(first.demandID.isEmpty)
        XCTAssertEqual(first.demandID, second.demandID)
        XCTAssertTrue(second.reused)
    }

    /// A hyphenated identifier is one term. Splitting `ES-IS` on the hyphen used
    /// to leave `is` behind, and `is` is a substring of most English text — the
    /// demand then dragged almost the whole space into the line scan instead of
    /// the rows that share the identifier.
    func testHyphenatedIdentifierStaysOneTerm() throws {
        let terms = InformationLoop.keywords(in: "ES-IS 论文 实验")
        XCTAssertTrue(terms.contains("es-is"), "terms: \(terms)")
        XCTAssertFalse(terms.contains("is"), "terms: \(terms)")
        XCTAssertFalse(terms.contains("es"), "terms: \(terms)")
    }

    // MARK: - The retrieval commit is one atomic claim

    /// A source that moves between the read and the write refuses the whole
    /// retrieval. The binding cannot be written afterwards: the invalidation
    /// pass that already ran would never see it, and the stale answer would be
    /// advertised as valid permanently.
    func testRetrievalRefusesSourceThatMovedBeforeTheCommit() throws {
        let (url, dbRead) = try open("atomic-refusal")
        let root = try makeWorkRoot()
        // A second connection to the same store: the interleaving under test is
        // between two writers, not between two calls on one handle.
        let dbWrite = try ESISDatabase(url: url)
        defer {
            dbRead.close(); dbWrite.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("omega revision one", to: root, name: "a.md")
        try dbRead.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        let readDigest = try XCTUnwrap(
            try dbRead.settledFileRows(rootID: "work").first?.digest)

        try write("omega revision two", to: root, name: "a.md")
        try dbWrite.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        XCTAssertNotEqual(
            try dbRead.settledFileRows(rootID: "work").first?.digest, readDigest,
            "the second connection must have committed a new revision")

        let demandID = "demand-atomic-refusal"
        let write = ESISDatabase.InformationRetrievalWrite(
            demandID: demandID, stateID: nil, sessionID: nil,
            requestIdentity: "refusal", query: "omega",
            rootIDs: [], includeChat: false, inputDigest: demandID,
            payload: Data("{}".utf8), hitCount: 1, itemIDs: ["file:work/a.md"],
            inputs: [],
            sourceBindings: [.init(
                rootID: "work", relativePath: "a.md",
                expectedDigest: readDigest)])
        XCTAssertThrowsError(try dbRead.recordInformationRetrieval(write)) { error in
            guard case .sourceRevisionChanged(
                let rootID, let relativePath, let expected, _)
                = error as? ESISDatabase.InformationDemandError
            else { return XCTFail("unexpected error: \(error)") }
            XCTAssertEqual(rootID, "work")
            XCTAssertEqual(relativePath, "a.md")
            XCTAssertEqual(expected, readDigest)
        }
        // Refused means rolled back, not partly recorded.
        XCTAssertEqual(try rawText(url, """
        SELECT COUNT(*) FROM settlements WHERE settlement_id='is-retrieval:\(demandID)';
        """), "0")
        XCTAssertEqual(try rawText(url, """
        SELECT COUNT(*) FROM settlement_bindings WHERE settlement_id='is-retrieval:\(demandID)';
        """), "0")
        XCTAssertEqual(try rawText(url, """
        SELECT COUNT(*) FROM information_demands WHERE demand_id='\(demandID)';
        """), "0")
    }

    /// The other order: the binding commits first, then the new revision lands
    /// on a different connection. The invalidation closure has to reach the
    /// result written by the first connection, and the demand-side row must
    /// flip with it.
    func testBindingCommittedFirstIsInvalidatedByAnotherConnection() throws {
        let (url, dbRead) = try open("atomic-invalidate")
        let root = try makeWorkRoot()
        let dbWrite = try ESISDatabase(url: url)
        defer {
            dbRead.close(); dbWrite.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("omega appears here", to: root, name: "a.md")
        try dbRead.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)

        let loop = InformationLoop(database: dbRead)
        let resolution = try loop.resolve(.init(
            requestIdentity: "binding-first", query: "omega", includeChat: false))
        XCTAssertEqual(resolution.hits.map(\.itemID), ["file:work/a.md"])
        XCTAssertNotNil(try dbRead.informationRetrievalPayload(demandID: resolution.demandID))

        try write("omega appears here, revised", to: root, name: "a.md")
        let report = try dbWrite.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        XCTAssertEqual(report.invalidatedSettlements, 0)
        XCTAssertNotNil(
            try dbRead.informationRetrievalPayload(demandID: resolution.demandID),
            "whole-file scan cannot guess the old item's new value")

        let reobserved = try InformationLoop(database: dbRead).resolve(.init(
            requestIdentity: "binding-second-observation",
            query: "omega", includeChat: false))
        XCTAssertEqual(reobserved.hits.first?.lineText, "omega appears here, revised")
        XCTAssertNil(
            try dbRead.informationRetrievalPayload(demandID: resolution.demandID),
            "the item re-observation invalidates the first connection's settlement")
        XCTAssertEqual(try rawText(url, """
        SELECT status FROM retrieval_settlements
        WHERE bridged_settlement_id='\(resolution.retrievalSettlementID)';
        """), "invalidated")
    }

    func testResolveRetriesWhenSourceChangesDuringRead() throws {
        let (url, dbRead) = try open("read-race-retry")
        let root = try makeWorkRoot()
        defer {
            dbRead.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("omega revision 0", to: root, name: "a.md")
        try dbRead.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)

        var didMutate = false
        var mutationError: Error?
        dbRead.beforeRootFileVerificationForTesting = {
            didMutate = true
            do {
                let file = root.appendingPathComponent("a.md")
                let writer = try FileHandle(forWritingTo: file)
                try writer.seek(toOffset: 0)
                try writer.write(contentsOf: Data("omega revision 1".utf8))
                try writer.close()
            } catch {
                mutationError = error
            }
        }

        let resolution = try InformationLoop(database: dbRead).resolve(.init(
            requestIdentity: "read-race-retry", query: "omega", includeChat: false))

        XCTAssertTrue(didMutate)
        XCTAssertNil(mutationError)
        XCTAssertNil(dbRead.beforeRootFileVerificationForTesting)
        XCTAssertTrue(resolution.hits.isEmpty)
        XCTAssertEqual(resolution.staleItemIDs, ["file:work/a.md"])
        XCTAssertEqual(try rawText(url, """
            SELECT COUNT(*) FROM settlement_bindings
            WHERE settlement_id='\(resolution.retrievalSettlementID)'
              AND source_root_id='work';
            """), "0", "the retry must not bind the stale source revision")
    }

    /// Resolves and source updates racing on two connections. After a final
    /// revision, no retrieval that cited the file may still be valid — whatever
    /// the interleaving was, the outcome is the same.
    func testConcurrentResolveAndSourceUpdateLeavesNoStaleResultValid() throws {
        let (url, dbRead) = try open("atomic-race")
        let root = try makeWorkRoot()
        let dbWrite = try ESISDatabase(url: url)
        defer {
            dbRead.close(); dbWrite.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("omega revision 0", to: root, name: "a.md")
        try dbRead.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)

        let loop = InformationLoop(database: dbRead)
        let lock = NSLock()
        var failures: [String] = []
        func record(_ failure: String) {
            lock.lock(); failures.append(failure); lock.unlock()
        }
        for round in 1...12 {
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    _ = try loop.resolve(.init(
                        requestIdentity: "race-\(round)", query: "omega",
                        includeChat: false))
                } catch {
                    record("resolve \(round): \(error)")
                }
            }
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    // Atomic replace: a reader sees the old or the new file,
                    // never a truncated one.
                    try Data("omega revision \(round)".utf8).write(
                        to: root.appendingPathComponent("a.md"), options: .atomic)
                    _ = try dbWrite.settleWorkRootContents(
                        rootID: "work", rootURL: root, carryText: false)
                } catch {
                    record("settle \(round): \(error)")
                }
            }
            group.wait()
        }
        XCTAssertTrue(failures.isEmpty, "concurrent rounds failed: \(failures)")

        // One more revision after both lanes stopped: anything that cited the
        // file before this point must have been invalidated by it.
        try Data("omega final revision".utf8).write(
            to: root.appendingPathComponent("a.md"), options: .atomic)
        _ = try dbWrite.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)

        XCTAssertEqual(try rawText(url, """
        SELECT COUNT(*) FROM retrieval_settlements r
        JOIN settlement_bindings b ON b.settlement_id=r.bridged_settlement_id
        WHERE r.status='valid';
        """), "0", "a retrieval that cited the changed file survived as valid")
    }

    func testStreamingChatScopeIncludesRowsBeyondTopK() throws {
        let (url, db) = try open("streaming-chat-scope")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        for index in 0..<220 {
            let userID = try db.appendChatMessage(
                sessionID: "source", role: "user",
                content: "needle in source row \(index)",
                model: nil, createdAt: Date())
            try db.commitChatTurn(
                sessionID: "source", userMessageID: userID,
                assistantText: "acknowledged \(index)", model: nil, createdAt: Date())
        }

        var scopeRows = 0
        try db.forEachChatScopeRow(sessionIDs: ["source"]) { _ in scopeRows += 1 }
        XCTAssertEqual(scopeRows, 440)
        var candidateRows = 0
        try db.forEachChatIndexRow(sessionIDs: ["source"], matchingAny: ["needle"]) {
            _ in candidateRows += 1
        }
        XCTAssertEqual(candidateRows, 220)

        let demand = InformationLoop.Demand(
            sessionID: "consumer", query: "needle", includeChat: true,
            chatSessionIDs: ["source"], limit: 1)
        let first = try loop.resolve(demand)
        XCTAssertEqual(first.hits.count, 1)

        let laterUserID = try db.appendChatMessage(
            sessionID: "source", role: "user",
            content: "needle appended after the first resolution",
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: "source", userMessageID: laterUserID,
            assistantText: "acknowledged later", model: nil, createdAt: Date())
        let second = try loop.resolve(demand)
        XCTAssertNotEqual(first.demandID, second.demandID,
                          "a matching row beyond top-K still changes the complete chat scope")
        XCTAssertEqual(second.hits.count, 1)
    }

    func testInformationLoopStreamsOlderCitableSummariesBeyondSnapshotLimit() throws {
        let (url, db) = try open("summary-stream-window")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)
        var oldestSettlementID = ""

        for index in 0..<201 {
            let content = index == 0
                ? "The oldestmarker conclusion remains useful to later execution states."
                : "Recent conclusion number \(index) contains no matching marker."
            let turn = try loop.settleTurn(
                generatedText: content, resolution: nil,
                stateID: "S-summary-window-\(index)", parentStateID: nil,
                position: 0, modelIdentity: "model-a",
                identity: .init(model: "m", tokenizer: "t"),
                sessionID: "producer", summaryQuery: "summary \(index)",
                actions: ["chat.completion"],
                settledAt: Date(timeIntervalSince1970: Double(index + 1)))
            if index == 0 { oldestSettlementID = turn.settlementID }
        }

        let boundedSnapshot = try db.citableSettlementSummaries(sessionID: "consumer")
        XCTAssertEqual(boundedSnapshot.count, 200)
        XCTAssertFalse(boundedSnapshot.contains { $0.settlementID == oldestSettlementID },
                       "the legacy snapshot is intentionally bounded newest-first")

        let resolution = try loop.resolve(.init(
            sessionID: "consumer", query: "oldestmarker", includeChat: false))
        XCTAssertTrue(
            resolution.hits.contains { $0.itemID == "settlement:\(oldestSettlementID)" },
            "InformationLoop must not hide a valid older summary behind the snapshot cap")
    }

    func testCancelledResolveStopsDuringSQLiteScanWithoutPublishingRetrieval() async throws {
        let (url, db) = try open("cancelled-scan")
        let root = try makeWorkRoot()
        defer {
            db.close()
            cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle in a settled file", to: root, name: "a.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)

        db.beforeInformationScanRowForTesting = {
            withUnsafeCurrentTask(body: { task in task?.cancel() })
        }
        let loop = InformationLoop(database: db)
        let task = Task {
            try loop.resolve(.init(
                sessionID: "cancelled", requestIdentity: "cancelled-scan",
                query: "needle", rootIDs: ["work"], includeChat: false))
        }

        do {
            _ = try await task.value
            XCTFail("a cancelled retrieval scan must not complete")
        } catch is CancellationError {
            // Expected: cancellation escapes without publishing a partial result.
        }
        XCTAssertEqual(try db.count("information_demands"), 0)
        XCTAssertEqual(try db.count("retrieval_settlements"), 0)
    }

    /// 同一 demand、同一父项（retrieval settlement）下的第二个子项不是「替换」，
    /// 是工具续接在 ES 里的分叉：追加一条 advancement，读取方取最新一条。
    /// 完全相同的重放仍然幂等，不新增行。
    func testInformationAdvancementReplayIsIdempotentAndForkAppendsChild() throws {
        let (url, db) = try open("demand-advance-idempotent")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)
        let resolution = try loop.resolve(.init(
            sessionID: "s-idempotent", requestIdentity: "request-idempotent",
            query: "a question", includeChat: false))
        let first = try loop.settleTurn(
            generatedText: "answer one", resolution: nil,
            stateID: "S-answer-one", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: nil)
        let write = ESISDatabase.InformationAdvancementWrite(
            demandID: resolution.demandID, stateID: "S-answer-one",
            settlementID: first.settlementID,
            retrievalSettlementID: resolution.retrievalSettlementID,
            actions: ["chat.completion"], result: Data("answer one".utf8))
        let advancementID = try db.recordInformationAdvancement(write)
        let replayID = try db.recordInformationAdvancement(write)
        XCTAssertEqual(replayID, advancementID)
        XCTAssertEqual(try db.count("information_advancements"), 1)

        let second = try loop.settleTurn(
            generatedText: "answer two", resolution: nil,
            stateID: "S-answer-two", parentStateID: nil, position: 0,
            modelIdentity: "model-a", identity: .init(model: "m", tokenizer: "t"),
            sessionID: nil)
        let replacement = ESISDatabase.InformationAdvancementWrite(
            demandID: resolution.demandID, stateID: "S-answer-two",
            settlementID: second.settlementID,
            retrievalSettlementID: resolution.retrievalSettlementID,
            actions: ["chat.completion"], result: Data("answer two".utf8))
        let forkID = try db.recordInformationAdvancement(replacement)
        XCTAssertNotEqual(forkID, advancementID)
        XCTAssertEqual(try db.count("information_advancements"), 2)
        XCTAssertEqual(try db.informationDemand(demandID: resolution.demandID)?.state, "ADVANCED")
        XCTAssertEqual(
            try db.answeredDemand(
                sessionID: "s-idempotent", query: "a question")?.answerSettlementID,
            second.settlementID,
            "分叉后最新一条才是当前答案")
    }

    /// R-17②：换卷/迁移之后 device+inode 变了，但已结算字节还在原地。旗标本身
    /// 有理由（不能默认还是同一个目录），没有理由的是「清旗只能人工」——内容
    /// 自己就能作证，于是自动采纳、落审计行，检索无缝继续。
    ///
    /// 取代旧的 `testIndexOnlyRetrievalRefusesReplacementRootBeforePublishing`：
    /// 那条用例断言的正是「字节相同的替代根不得绕过显式采纳」，已被 R-17② 推翻。
    func testIndexOnlyRetrievalAutoAdoptsRootWhoseSettledContentProvesSame() throws {
        let (url, db) = try open("index-only-root-autoadopt")
        let root = try makeWorkRoot()
        defer {
            db.close()
            cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("needle in the indexed source", to: root, name: "a.md")
        // 换卷/迁移的真实形状是「库里记的旧、文件系统报的新」。所以结算时用探针
        // 记下上一卷的 pair，随后撤掉探针：从这一刻起库里那一对就是过期的，而
        // lstat 与 fstat 报的是同一个真身。反过来让探针一直撒谎会造出
        // 「探针说 A、fstat 说 B」的不可能世界，验不到采纳之后的读取。
        let actual = try ESISDatabase.directoryIdentity(atPath: root.path)
        db.rootDirectoryIdentityProbeForTesting = { _ in
            ESISDatabase.RootDirectoryIdentity(
                device: actual.device - 1, inode: actual.inode)
        }
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        db.rootDirectoryIdentityProbeForTesting = nil

        // 钉桩照旧 fail-closed：旗标不会因为「有检索要跑」就被悄悄绕过。
        XCTAssertThrowsError(try db.rootLocatorSnapshot(rootID: "work"))
        XCTAssertThrowsError(try db.carriedFileContent(
            rootID: "work", relativePath: "a.md"))

        let loop = InformationLoop(database: db)
        let demand = InformationLoop.Demand(
            sessionID: "consumer",
            requestIdentity: "index-only-auto-adopt",
            query: "needle",
            rootIDs: ["work"],
            includeChat: false)
        let resolved = try loop.resolve(demand)
        XCTAssertEqual(resolved.hits.map(\.itemID), ["file:work/a.md"])
        XCTAssertEqual(resolved.staleItemIDs, [])

        // 采纳是显式动作、留痕：同一个事务里清旗 + 落 append-only 审计行。
        XCTAssertNoThrow(try db.rootLocatorSnapshot(rootID: "work"))
        let audit = try XCTUnwrap(db.resolveIndexIdentity(
            ESISDatabase.rootIdentityAdoptionIdentity(rootID: "work"), policy: .first))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try db.readObject(audit.objectID)) as? [String: Any])
        XCTAssertEqual(
            payload["schema_version"] as? String,
            ESISDatabase.rootIdentityAdoptionSchema)
        XCTAssertEqual(payload["root_id"] as? String, "work")
        XCTAssertEqual(payload["proved_index_only_files"] as? Int, 1)

        // 采纳之后定向读取也通了：清的是同一面旗，不是检索侧的局部豁免。
        let carried = try XCTUnwrap(try db.carriedFileContent(
            rootID: "work", relativePath: "a.md"))
        XCTAssertEqual(carried.content, Data("needle in the indexed source".utf8))
    }

    /// R-17①：证不出来就只降级这一条 root，不整库 fail。两条 root 同时在库里——
    /// 一条身份有缺口且内容对不上（降级、旗标保留、不留审计行），另一条健康
    /// （照常命中）。降级不是静默丢弃：需求侧把它记进 `staleItemIDs`。
    func testUnprovableRootDegradesAloneAndLeavesOtherRootsSearchable() throws {
        let (url, db) = try open("index-only-root-degrade")
        let rootA = try makeWorkRoot()
        let rootB = try makeWorkRoot()
        defer {
            db.close()
            cleanup(url)
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        try write("needle replaced after settling", to: rootA, name: "a.md")
        try write("needle in the healthy source", to: rootB, name: "b.md")
        // 同上：只让 work-a 的库内记录停在上一卷，work-b 记的是真身。
        db.rootDirectoryIdentityProbeForTesting = { path in
            let identity = try ESISDatabase.directoryIdentity(atPath: path)
            guard path == rootA.path else { return identity }
            return ESISDatabase.RootDirectoryIdentity(
                device: identity.device - 1, inode: identity.inode)
        }
        _ = try db.settleWorkRootContents(
            rootID: "work-a", rootURL: rootA, carryText: false)
        _ = try db.settleWorkRootContents(
            rootID: "work-b", rootURL: rootB, carryText: false)
        db.rootDirectoryIdentityProbeForTesting = nil
        // 结算之后才改字节：身份缺口 + 内容对不上，自证必然失败。
        try write("needle rewritten behind the settled digest", to: rootA, name: "a.md")

        let hits = try db.searchSettledContent(query: "needle")
        XCTAssertEqual(hits.map(\.rootID), ["work-b"])

        // 降级不等于采纳：旗标还在，也没有审计行。
        XCTAssertThrowsError(try db.rootLocatorSnapshot(rootID: "work-a"))
        XCTAssertNil(try db.resolveIndexIdentity(
            ESISDatabase.rootIdentityAdoptionIdentity(rootID: "work-a")))

        let loop = InformationLoop(database: db)
        let resolved = try loop.resolve(InformationLoop.Demand(
            sessionID: "consumer",
            requestIdentity: "index-only-degrade",
            query: "needle",
            rootIDs: ["work-a", "work-b"],
            includeChat: false))
        XCTAssertEqual(resolved.hits.map(\.itemID), ["file:work-b/b.md"])
        XCTAssertEqual(resolved.staleItemIDs, ["file:work-a/a.md"])
    }

    /// The inverse of the existing digest-mismatch regression: a row that did
    /// not match at first is rewritten to contain the query while its stored
    /// digest stays unchanged. It must not be silently dropped and let the old
    /// empty retrieval be reused.
    func testCachedEmptyRetrievalRefusesChatRowThatBecomesMatchWithStaleDigest() throws {
        let (url, db) = try open("chat-cache-new-match-stale-digest")
        defer { db.close(); cleanup(url) }
        let messageID = try db.appendChatMessage(
            sessionID: "source-chat", role: "assistant",
            content: "ordinary text without the target",
            model: nil, createdAt: Date())
        let loop = InformationLoop(database: db)
        let demand = InformationLoop.Demand(
            sessionID: "consumer",
            requestIdentity: "request-chat-cache-new-match",
            query: "needle",
            includeChat: true,
            chatSessionIDs: ["source-chat"])
        let first = try loop.resolve(demand)
        XCTAssertTrue(first.hits.isEmpty)
        XCTAssertFalse(first.reused)
        let originalPayload = try XCTUnwrap(
            try db.informationRetrievalPayload(demandID: first.demandID))

        // Keep identity and content_sha256 fixed while making the current bytes
        // a SQL candidate. The chat-scope watermark therefore stays unchanged.
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
        defer { sqlite3_close(raw) }
        let mutation = "UPDATE chat_messages SET content_object_id=NULL, "
            + "content='needle appears in rewritten bytes' WHERE id=\(messageID);"
        XCTAssertEqual(sqlite3_exec(raw, mutation, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try loop.resolve(demand)) { error in
            guard let databaseError = error as? ESISDatabase.DatabaseError,
                  case .sourceChangedWhileBeingRead(let path) = databaseError else {
                return XCTFail("expected bounded source-change refusal, got: \(error)")
            }
            XCTAssertEqual(path, "chat:source-chat/\(messageID)")
        }
        XCTAssertEqual(
            try db.informationRetrievalPayload(demandID: first.demandID),
            originalPayload,
            "a corrupt candidate must not revive or rewrite the old empty retrieval")
    }
}


extension InformationLoopTests {
    /// Two different two-file inventories can serialize to the same newline-joined
    /// source stream when POSIX relative paths themselves contain LF. A stable
    /// matching file keeps the cached hit list identical, so the old basis would
    /// incorrectly reuse the previous empty-or-same-hit result.
    func testDemandBasisLengthPrefixesNewlineBearingFileIdentities() throws {
        let (url, db) = try open("stream-basis-newline-collision")
        let root = try makeWorkRoot()
        defer {
            db.close()
            cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }

        let digestA = NativeSHA256.hexDigest(Data("alpha".utf8))
        let digestB = NativeSHA256.hexDigest(Data("beta".utf8))
        let digestC = NativeSHA256.hexDigest(Data("gamma".utf8))

        // Inventory A:
        //   a=<digestB>\nfile:work/b  -> digestA
        //   c                         -> digestC
        let directoryA = root.appendingPathComponent(
            "a=\(digestB)\nfile:work", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryA, withIntermediateDirectories: true)
        try write("alpha", to: directoryA, name: "b")
        try write("gamma", to: root, name: "c")
        try write("needle stable match", to: root, name: "z.txt")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: true)

        let loop = InformationLoop(database: db)
        let demand = InformationLoop.Demand(
            sessionID: "s-stream",
            requestIdentity: "stable-request",
            query: "needle",
            rootIDs: ["work"],
            includeChat: false)
        let first = try loop.resolve(demand)
        XCTAssertEqual(first.hits.map(\.itemID), ["file:work/z.txt"])
        XCTAssertFalse(first.reused)

        // Inventory B:
        //   a                         -> digestB
        //   b=<digestA>\nfile:work/c  -> digestC
        // Together with the unchanged z.txt row, the old newline-joined stream
        // has the same bytes and the same record count as inventory A.
        try FileManager.default.removeItem(at: directoryA)
        try FileManager.default.removeItem(at: root.appendingPathComponent("c"))
        try write("beta", to: root, name: "a")
        let directoryB = root.appendingPathComponent(
            "b=\(digestA)\nfile:work", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryB, withIntermediateDirectories: true)
        try write("gamma", to: directoryB, name: "c")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: true)

        let second = try loop.resolve(demand)
        XCTAssertEqual(second.hits, first.hits)
        XCTAssertFalse(second.reused,
                       "a changed full source inventory must not alias the prior demand")
        XCTAssertNotEqual(second.demandID, first.demandID)
    }

}


extension InformationLoopTests {
    func testStableExternalSourceIDSurvivesExplicitMoveAndCopyGetsNewID() throws {
        let (url, db) = try open("stable-source-move-copy")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("same bytes", to: root, name: "old.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)

        let originalID = try db.externalSourceDependencyID(
            rootID: "work", relativePath: "old.md")

        // Same bytes at a new path are a copy unless the agent explicitly
        // declares the existing identity to have moved there.
        try write("same bytes", to: root, name: "copy.md")
        try write("same bytes", to: root, name: "renamed.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        let copyID = try db.externalSourceDependencyID(
            rootID: "work", relativePath: "copy.md")
        let provisionalRenameID = try db.externalSourceDependencyID(
            rootID: "work", relativePath: "renamed.md")
        XCTAssertNotEqual(copyID, originalID,
                          "a byte-identical copy must not inherit source identity")
        XCTAssertNotEqual(provisionalRenameID, originalID,
                          "a newly observed path starts with its own provisional identity")

        try db.moveExternalSourceDependency(
            dependencyID: originalID,
            toRootID: "work",
            toRelativePath: "renamed.md",
            reason: "agent-confirmed-rename")
        XCTAssertEqual(
            try db.externalSourceDependencyID(
                rootID: "work", relativePath: "renamed.md"),
            originalID,
            "an explicitly confirmed move preserves dependency identity")

        let history = try db.externalSourceLocationHistory(dependencyID: originalID)
        XCTAssertEqual(history.map(\.action), ["attach", "detach", "attach"])
        XCTAssertEqual(history.last?.relativePath, "renamed.md")
        XCTAssertEqual(history.last?.reason, "agent-confirmed-rename")
        let provisionalHistory = try db.externalSourceLocationHistory(
            dependencyID: provisionalRenameID)
        XCTAssertEqual(provisionalHistory.map(\.action), ["attach", "detach"])
        XCTAssertTrue(provisionalHistory.last?.reason.contains("superseded-by-explicit-move") == true)

        // Root removal records a detach snapshot, but does not delete source
        // identity/location history. Re-registering that path is a new source;
        // only an explicit move can carry the previous dependency ID forward.
        try db.removeRoot(rootID: "work")
        let afterRemoval = try db.externalSourceLocationHistory(dependencyID: originalID)
        XCTAssertEqual(afterRemoval.last?.action, "detach")
        XCTAssertEqual(afterRemoval.last?.relativePath, "renamed.md")
        try db.indexExternalFile(
            rootID: "work", relativePath: "renamed.md", kind: "md",
            size: 10, modifiedAt: nil,
            contentDigest: NativeSHA256.hexDigest(Data("same bytes".utf8)))
        let reintroducedID = try db.externalSourceDependencyID(
            rootID: "work", relativePath: "renamed.md")
        XCTAssertNotEqual(reintroducedID, originalID)
        XCTAssertEqual(
            try db.externalSourceLocationHistory(dependencyID: originalID).count, 4,
            "the removed root must not erase the previous location history")
    }

    func testInformationRetrievalRecordsIndependentConsumedItemRevisions() throws {
        let (url, db) = try open("source-item-revisions")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write(
            "contract amount 100\ncontract term 12 months\n",
            to: root, name: "contract.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        let fileDependencyID = try db.externalSourceDependencyID(
            rootID: "work", relativePath: "contract.md")
        XCTAssertEqual(try db.dependencyHistory(fileDependencyID).count, 1)
        XCTAssertEqual(
            try db.dependencyHistory("file:work/contract.md"), [],
            "new file observations must not append path-derived dependency IDs")
        let loop = InformationLoop(database: db)

        let first = try loop.resolve(.init(
            requestIdentity: "source-item-first",
            query: "contract",
            includeChat: false))
        XCTAssertEqual(first.hits.count, 2)
        let firstBindings = try db.settlementSourceItemBindings(
            settlementID: first.retrievalSettlementID)
        XCTAssertEqual(firstBindings.count, 2)
        XCTAssertEqual(Set(firstBindings.map(\.dependencyID)), Set([fileDependencyID]))
        XCTAssertEqual(Set(firstBindings.map(\.sourceItemID)).count, 2)
        XCTAssertEqual(Set(firstBindings.map(\.itemKeyword)), Set(["[\"contract\"]"]))
        XCTAssertEqual(try rawText(url, """
        SELECT COUNT(*) FROM settlement_bindings
         WHERE settlement_id='\(first.retrievalSettlementID)'
           AND source_dependency_id='\(fileDependencyID)';
        """), "2", "each consumed item binding must retain the stable file dependency ID")
        let firstHitByDigest = Dictionary(
            uniqueKeysWithValues: first.hits.map {
                (NativeSHA256.hexDigest(Data($0.lineText.utf8)), $0.lineText)
            })
        for binding in firstBindings {
            let consumedText = try XCTUnwrap(firstHitByDigest[binding.itemDigest])
            XCTAssertEqual(try db.readObject(binding.itemContentAddress), Data(consumedText.utf8))
            XCTAssertEqual(binding.revision, 1)
            XCTAssertEqual(
                try db.dependencyHistory("source-item:\(binding.sourceItemID)").count, 1)
        }

        // A second, independent retrieval of the same item content reuses the
        // source_item_id and does not append a redundant dependency revision.
        let repeated = try loop.resolve(.init(
            requestIdentity: "source-item-repeat",
            query: "contract",
            includeChat: false))
        let repeatedBindings = try db.settlementSourceItemBindings(
            settlementID: repeated.retrievalSettlementID)
        XCTAssertEqual(Set(repeatedBindings.map(\.sourceItemID)),
                       Set(firstBindings.map(\.sourceItemID)))
        for binding in firstBindings {
            XCTAssertEqual(
                try db.dependencyHistory("source-item:\(binding.sourceItemID)").count, 1)
        }

        // Only the second consumed item changes. Its stable item identity advances
        // to revision 2; the first item's identical snippet remains revision 1.
        try write(
            "contract amount 100\ncontract term 18 months\n",
            to: root, name: "contract.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        let changed = try loop.resolve(.init(
            requestIdentity: "source-item-changed",
            query: "contract",
            includeChat: false))
        let changedBindings = try db.settlementSourceItemBindings(
            settlementID: changed.retrievalSettlementID)
        XCTAssertEqual(try db.dependencyHistory(fileDependencyID).count, 2,
                       "the file-level dependency revision remains path-independent")
        XCTAssertEqual(Set(changedBindings.map(\.sourceItemID)),
                       Set(firstBindings.map(\.sourceItemID)))
        for binding in changedBindings {
            let history = try db.dependencyHistory("source-item:\(binding.sourceItemID)")
            let firstBinding = try XCTUnwrap(
                firstBindings.first { $0.sourceItemID == binding.sourceItemID })
            let expectedCount = binding.itemDigest == firstBinding.itemDigest ? 1 : 2
            XCTAssertEqual(history.count, expectedCount)
            XCTAssertEqual(binding.revision, expectedCount)
        }
    }
}


extension InformationLoopTests {
    func testChangedConsumedItemInvalidatesOnlyItsOwnSettlementClosure() throws {
        let (url, db) = try open("source-item-local-invalidation")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write(
            "contract amount 100\ncontract term 12 months\n",
            to: root, name: "contract.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        let loop = InformationLoop(database: db)

        let amount = try loop.resolve(.init(
            requestIdentity: "amount-reference", query: "amount", includeChat: false))
        let term = try loop.resolve(.init(
            requestIdentity: "term-reference", query: "term", includeChat: false))
        XCTAssertEqual(amount.hits.count, 1)
        XCTAssertEqual(term.hits.count, 1)
        let amountItem = try XCTUnwrap(
            db.settlementSourceItemBindings(settlementID: amount.retrievalSettlementID).first)
        let termItem = try XCTUnwrap(
            db.settlementSourceItemBindings(settlementID: term.retrievalSettlementID).first)
        XCTAssertNotEqual(amountItem.sourceItemID, termItem.sourceItemID)
        XCTAssertEqual(
            try rawText(url, """
            SELECT validity FROM settlement_current_validity
             WHERE settlement_id='\(amount.retrievalSettlementID)';
            """), "valid")
        XCTAssertEqual(
            try rawText(url, """
            SELECT validity FROM settlement_current_validity
             WHERE settlement_id='\(term.retrievalSettlementID)';
            """), "valid")

        // The file bytes changed, but the amount item did not. File-level
        // reconciliation must not invalidate either new item-scoped binding.
        try write(
            "contract amount 100\ncontract term 18 months\n",
            to: root, name: "contract.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        XCTAssertEqual(
            try rawText(url, """
            SELECT validity FROM settlement_current_validity
             WHERE settlement_id='\(amount.retrievalSettlementID)';
            """), "valid")
        XCTAssertEqual(
            try rawText(url, """
            SELECT validity FROM settlement_current_validity
             WHERE settlement_id='\(term.retrievalSettlementID)';
            """), "valid")

        // The actual retrieval observes the changed term item. Only the
        // term-pinned settlement and its dependents are invalidated.
        let termUpdated = try loop.resolve(.init(
            requestIdentity: "term-reference-updated", query: "term", includeChat: false))
        let updatedItem = try XCTUnwrap(
            db.settlementSourceItemBindings(settlementID: termUpdated.retrievalSettlementID).first)
        XCTAssertEqual(updatedItem.sourceItemID, termItem.sourceItemID)
        XCTAssertEqual(updatedItem.revision, 2)
        XCTAssertEqual(
            try rawText(url, """
            SELECT validity FROM settlement_current_validity
             WHERE settlement_id='\(term.retrievalSettlementID)';
            """), "invalid")
        XCTAssertEqual(
            try rawText(url, """
            SELECT validity FROM settlement_current_validity
             WHERE settlement_id='\(amount.retrievalSettlementID)';
            """), "valid")
    }
}


extension InformationLoopTests {
    func testVerifiedSourceReReadMarksPreviouslyConsumedItemAbsent() throws {
        let (url, db) = try open("source-item-absent")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        try write("contract term 12 months\n", to: root, name: "contract.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        let loop = InformationLoop(database: db)

        let first = try loop.resolve(.init(
            requestIdentity: "term-consumer-first",
            query: "term",
            includeChat: false))
        XCTAssertEqual(first.hits.count, 1)
        let firstBinding = try XCTUnwrap(
            db.settlementSourceItemBindings(settlementID: first.retrievalSettlementID).first)
        let itemDependencyID = "source-item:\(firstBinding.sourceItemID)"
        XCTAssertEqual(try db.dependencyHistory(itemDependencyID).count, 1)
        XCTAssertEqual(
            try db.settlementValidity(first.retrievalSettlementID), "valid")

        // The file is readable and its changed bytes are explicitly observed.
        // The next query scope contains no matching item, so only the old item
        // receives an ABSENT revision and its settlement closure is revoked.
        try write("contract amount 100\n", to: root, name: "contract.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        let second = try loop.resolve(.init(
            requestIdentity: "term-consumer-after-absence",
            query: "term",
            includeChat: false))
        XCTAssertTrue(second.hits.isEmpty)
        XCTAssertEqual(second.changedSourceIDs, [])
        XCTAssertEqual(second.unavailableSourceIDs, [])

        let history = try db.dependencyHistory(itemDependencyID)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.last?.reason, "source-item-absent")
        XCTAssertEqual(try db.settlementValidity(first.retrievalSettlementID), "invalid")
        XCTAssertEqual(try db.settlementValidity(second.retrievalSettlementID), "valid")
        XCTAssertNotNil(try db.informationRetrievalPayload(demandID: second.demandID))
    }

    func testUnavailableSourceDoesNotCreateItemAbsentRevision() throws {
        let (url, db) = try open("source-item-unavailable-no-absence")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("contract.md")
        try write("contract term 12 months\n", to: root, name: "contract.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        let loop = InformationLoop(database: db)
        let first = try loop.resolve(.init(
            requestIdentity: "term-before-unavailable",
            query: "term", includeChat: false))
        let firstBinding = try XCTUnwrap(
            db.settlementSourceItemBindings(settlementID: first.retrievalSettlementID).first)
        let itemDependencyID = "source-item:\(firstBinding.sourceItemID)"

        try FileManager.default.removeItem(at: file)
        let unavailable = try loop.resolve(.init(
            requestIdentity: "term-during-unavailable",
            query: "term", includeChat: false))
        XCTAssertTrue(unavailable.hits.isEmpty)
        XCTAssertEqual(unavailable.unavailableSourceIDs, ["file:work/contract.md"])
        XCTAssertTrue(unavailable.changedSourceIDs.isEmpty)
        XCTAssertEqual(try db.dependencyHistory(itemDependencyID).count, 1)
        XCTAssertEqual(try db.settlementValidity(first.retrievalSettlementID), "valid")
    }
}


extension InformationLoopTests {
    func testReadableNonTextReplacementMarksPriorTextItemsAbsent() throws {
        let (url, db) = try open("source-became-binary")
        let root = try makeWorkRoot()
        defer {
            db.close(); cleanup(url)
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("contract.md")
        try write("contract term 12 months\n", to: root, name: "contract.md")
        _ = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)

        let loop = InformationLoop(database: db)
        let first = try loop.resolve(.init(
            requestIdentity: "term-before-binary",
            query: "term", includeChat: false))
        XCTAssertEqual(first.hits.count, 1)
        let itemBinding = try XCTUnwrap(
            db.settlementSourceItemBindings(settlementID: first.retrievalSettlementID).first)
        let sourceDependencyID = itemBinding.dependencyID
        let itemDependencyID = "source-item:\(itemBinding.sourceItemID)"
        XCTAssertEqual(try db.dependencyHistory(itemDependencyID).count, 1)

        // This is a successful full-file read, but the new bytes are no longer
        // UTF-8 text. Every previously consumed textual item from this source is
        // therefore absent; this is not the same as a missing/unavailable file.
        try Data([0xFF, 0xFE, 0x00, 0x7F]).write(to: file)
        let report = try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)
        XCTAssertEqual(report.invalidatedSettlements, 1)
        XCTAssertEqual(try db.settlementValidity(first.retrievalSettlementID), "invalid")

        let fileHistory = try db.dependencyHistory(sourceDependencyID)
        XCTAssertEqual(fileHistory.count, 2)
        let itemHistory = try db.dependencyHistory(itemDependencyID)
        XCTAssertEqual(itemHistory.count, 2)
        XCTAssertEqual(itemHistory.last?.reason, "source-became-non-text")
    }
}
