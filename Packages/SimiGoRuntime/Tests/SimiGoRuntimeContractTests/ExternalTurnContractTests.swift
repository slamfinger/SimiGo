import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// External-provider turns: keeping the information, settling it and letting a
/// later request consume it are three separate questions. A turn forwarded to
/// an upstream API is recorded with its provenance at arrival, verified as a
/// whole request, and only then becomes retrievable history.
final class ExternalTurnContractTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-external-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private func recordTurn(
        _ db: ESISDatabase, sessionID: String = "s-ext",
        provider: String = "openai-compatible", requestID: String,
        question: String, answer: String
    ) throws {
        try db.recordExternalTurn(
            sessionID: sessionID, provider: provider, requestID: requestID,
            userText: question, model: "gpt-x", createdAt: Date())
        try db.recordExternalResponse(
            sessionID: sessionID, provider: provider, requestID: requestID,
            assistantText: answer, model: "gpt-x", createdAt: Date())
    }

    /// Recorded is not retrievable: the upstream text and its provenance are
    /// in the space as soon as the request arrives, but they are not history
    /// another request may consume.
    func testRecordedExternalTurnIsKeptWithProvenanceButNotRetrievable() throws {
        let (url, db) = try open("recorded")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        let userID = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-1",
            userText: "外部请求：关键线路 节点工期", model: "gpt-x", createdAt: Date())
        try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-1",
            assistantText: "外部回答：节点工期 42 天", model: "gpt-x", createdAt: Date())

        // Recorded: bytes and provenance are readable back.
        let stored = try db.listChatMessages(sessionID: "s-ext")
        XCTAssertEqual(stored.map(\.role), ["user", "assistant"])
        let provenance = try db.chatTurnProvenance(
            sessionID: "s-ext", requestID: "req-1")
        XCTAssertEqual(provenance.map(\.messageID).first, userID)
        XCTAssertEqual(provenance.map(\.turnState), ["recorded", "recorded"])
        XCTAssertEqual(provenance.map(\.sourceKind), ["external", "external"])
        XCTAssertEqual(
            provenance.compactMap(\.sourceProvider),
            ["openai-compatible", "openai-compatible"])
        XCTAssertEqual(provenance.compactMap(\.requestID), ["req-1", "req-1"])
        XCTAssertTrue(provenance.allSatisfy { $0.verifiedAt == nil && !$0.isEligible })

        // Not retrievable: arrival wrote no standing.
        XCTAssertTrue(try db.chatIndexRows(sessionIDs: ["s-ext"]).isEmpty)
        let resolution = try loop.resolve(.init(
            sessionID: "s-ext", query: "节点工期", includeChat: true,
            chatSessionIDs: ["s-ext"]))
        XCTAssertTrue(resolution.hits.isEmpty)
        XCTAssertEqual(loop.contextBlock(resolution), "")
    }

    /// Verification promotes exactly the request's own question/answer pair,
    /// making it ordinary retrievable history.
    func testVerifiedExternalTurnBecomesRetrievableHistory() throws {
        let (url, db) = try open("verified")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        try recordTurn(
            db, requestID: "req-2",
            question: "外部请求：关键线路 节点工期",
            answer: "外部回答：节点工期 42 天")

        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-2", verifiedAt: Date()),
            2)

        let provenance = try db.chatTurnProvenance(
            sessionID: "s-ext", requestID: "req-2")
        XCTAssertEqual(provenance.map(\.turnState), ["committed", "committed"])
        XCTAssertTrue(provenance.allSatisfy { $0.verifiedAt != nil && $0.isEligible })

        let rows = try db.chatIndexRows(sessionIDs: ["s-ext"])
        XCTAssertEqual(rows.map(\.role), ["user", "assistant"])
        let resolution = try loop.resolve(.init(
            sessionID: "s-ext", query: "节点工期", includeChat: true,
            chatSessionIDs: ["s-ext"]))
        XCTAssertEqual(Set(resolution.hits.map(\.itemID)), Set(rows.map(\.itemID)))
    }

    /// A half-turn is never verified: the answer cannot become memory without
    /// the question it answers.
    func testVerificationRequiresBothSidesOfTheRequest() throws {
        let (url, db) = try open("half")
        defer { db.close(); cleanup(url) }

        try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-3",
            userText: "只有问题", model: nil, createdAt: Date())
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-3", verifiedAt: Date()),
            0)
        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-ext", requestID: "req-3")
                .map(\.turnState),
            ["recorded"])

        try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-3",
            assistantText: "现在有答案了", model: nil, createdAt: Date())
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-3", verifiedAt: Date()),
            2)
    }

    /// Two concurrent external requests on one session: verifying one must not
    /// grant standing to the other's still-unanswered input.
    func testVerifyingOneRequestNeverPromotesAnotherInFlightTurn() throws {
        let (url, db) = try open("concurrent")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        try recordTurn(
            db, requestID: "req-a",
            question: "请求 A：关键线路 节点工期", answer: "回答 A：42 天")
        try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-b",
            userText: "请求 B：后台汇总 rollout_summary", model: nil, createdAt: Date())

        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-a", verifiedAt: Date()),
            2)

        // B is recorded, not verified, and never visible to A's retrieval.
        let resolution = try loop.resolve(.init(
            sessionID: "s-ext", query: "rollout_summary", includeChat: true,
            chatSessionIDs: ["s-ext"]))
        XCTAssertTrue(resolution.hits.isEmpty)
        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-ext", requestID: "req-b")
                .map(\.turnState),
            ["recorded"])
        XCTAssertEqual(
            try db.chatIndexRows(sessionIDs: ["s-ext"]).map(\.role),
            ["user", "assistant"])
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-b", verifiedAt: Date()),
            0)
    }

    /// Retries of the same upstream request reuse their rows instead of
    /// appending duplicates.
    func testRepeatingTheSameRequestDoesNotDuplicateRows() throws {
        let (url, db) = try open("idempotent")
        defer { db.close(); cleanup(url) }

        let firstUser = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-4",
            userText: "同一条外部请求", model: nil, createdAt: Date())
        let secondUser = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-4",
            userText: "同一条外部请求", model: nil, createdAt: Date())
        XCTAssertEqual(firstUser, secondUser)

        let firstAssistant = try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-4",
            assistantText: "同一条外部回答", model: nil, createdAt: Date())
        let secondAssistant = try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-4",
            assistantText: "同一条外部回答", model: nil, createdAt: Date())
        XCTAssertEqual(firstAssistant, secondAssistant)

        XCTAssertEqual(try db.listChatMessages(sessionID: "s-ext").count, 2)
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-4", verifiedAt: Date()),
            2)
    }

    /// The idempotency key binds provenance as well as content. Replaying
    /// equal text under a different provider/model/standing is not the same turn.
    func testExternalRetryMustPreserveProviderModelAndEligibility() throws {
        let (url, db) = try open("provenance-idempotency")
        defer { db.close(); cleanup(url) }

        let userID = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "provider-a", requestID: "req-provenance",
            userText: "same request body", model: "model-a", createdAt: Date())
        let replayID = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "provider-a", requestID: "req-provenance",
            userText: "same request body", model: "model-a", createdAt: Date())
        XCTAssertEqual(replayID, userID, "same content and provenance remains idempotent")

        XCTAssertThrowsError(try db.recordExternalTurn(
            sessionID: "s-ext", provider: "provider-b", requestID: "req-provenance",
            userText: "same request body", model: "model-a", createdAt: Date())) { error in
            let conflict = error as? ESISDatabase.ExternalTurnProvenanceConflict
            XCTAssertEqual(conflict?.storedProvider, "provider-a")
            XCTAssertEqual(conflict?.incomingProvider, "provider-b")
        }
        XCTAssertThrowsError(try db.recordExternalTurn(
            sessionID: "s-ext", provider: "provider-a", requestID: "req-provenance",
            userText: "same request body", model: "model-b", createdAt: Date())) { error in
            let conflict = error as? ESISDatabase.ExternalTurnProvenanceConflict
            XCTAssertEqual(conflict?.storedModel, "model-a")
            XCTAssertEqual(conflict?.incomingModel, "model-b")
        }
        XCTAssertThrowsError(try db.recordExternalTurn(
            sessionID: "s-ext", provider: "provider-a", requestID: "req-provenance",
            userText: "same request body", model: "model-a", createdAt: Date(),
            eligibility: .internalOperation)) { error in
            let conflict = error as? ESISDatabase.ExternalTurnProvenanceConflict
            XCTAssertEqual(conflict?.storedEligibility, "ordinary")
            XCTAssertEqual(conflict?.incomingEligibility, "internal")
        }

        let assistantID = try db.recordExternalResponse(
            sessionID: "s-ext", provider: "provider-a", requestID: "req-provenance",
            assistantText: "same response", model: "model-a", createdAt: Date())
        XCTAssertThrowsError(try db.recordExternalResponse(
            sessionID: "s-ext", provider: "provider-a", requestID: "req-provenance",
            assistantText: "same response", model: "model-b", createdAt: Date())) { error in
            let conflict = error as? ESISDatabase.ExternalTurnProvenanceConflict
            // The already-recorded user row is the first provenance anchor
            // checked when an assistant retry arrives with a different model.
            XCTAssertEqual(conflict?.role, "user")
            XCTAssertEqual(conflict?.storedModel, "model-a")
        }
        XCTAssertEqual(try db.listChatMessages(sessionID: "s-ext").count, 2)
        XCTAssertEqual(assistantID, try db.recordExternalResponse(
            sessionID: "s-ext", provider: "provider-a", requestID: "req-provenance",
            assistantText: "same response", model: "model-a", createdAt: Date()))

        // The reverse arrival order is equally constrained: an assistant row
        // cannot be paired later with a user row from another provider/model.
        _ = try db.recordExternalResponse(
            sessionID: "s-ext", provider: "provider-a", requestID: "req-assistant-first",
            assistantText: "answer arrived first", model: "model-a", createdAt: Date())
        XCTAssertThrowsError(try db.recordExternalTurn(
            sessionID: "s-ext", provider: "provider-b", requestID: "req-assistant-first",
            userText: "question arrived second", model: "model-a", createdAt: Date())) { error in
            let conflict = error as? ESISDatabase.ExternalTurnProvenanceConflict
            XCTAssertEqual(conflict?.role, "assistant")
            XCTAssertEqual(conflict?.storedProvider, "provider-a")
            XCTAssertEqual(conflict?.incomingProvider, "provider-b")
        }
        let reverseRows = try db.chatTurnProvenance(
            sessionID: "s-ext", requestID: "req-assistant-first")
        XCTAssertEqual(reverseRows.map(\.role), ["assistant"])
        XCTAssertEqual(reverseRows.map(\.turnState), ["recorded"])
    }
    /// Historical external rows can predate provenance-bound ingestion.
    /// Verification itself must therefore reject a mixed pair instead of
    /// assuming every stored (session, request) pair is internally consistent.
    func testVerificationRejectsLegacyMixedProvenancePair() throws {
        let url = tempURL("legacy-mixed-provenance")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        try recordTurn(
            db, requestID: "req-legacy-mixed",
            question: "legacy question", answer: "legacy answer")
        db.close()
        defer { cleanup(url) }

        // Simulate a database written before the provenance guard existed.
        // The production carrier's immutability triggers are intentionally
        // bypassed only in this isolated fixture; no application write path
        // can create this inconsistent pair after the new guard.
        do {
            var raw: OpaquePointer?
            guard sqlite3_open(url.path, &raw) == SQLITE_OK, let raw else {
                XCTFail("could not open legacy fixture with SQLite")
                return
            }
            defer { _ = sqlite3_close(raw) }

            var statement: OpaquePointer?
            let query = "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='chat_messages';"
            guard sqlite3_prepare_v2(raw, query, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                XCTFail("could not enumerate chat_messages triggers")
                return
            }
            var triggerNames: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let value = sqlite3_column_text(statement, 0) {
                    triggerNames.append(String(cString: value))
                }
            }
            _ = sqlite3_finalize(statement)
            for name in triggerNames {
                let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
                let drop = "DROP TRIGGER IF EXISTS \"\(escaped)\";"
                XCTAssertEqual(sqlite3_exec(raw, drop, nil, nil, nil), SQLITE_OK)
            }
            let corrupt = """
            UPDATE chat_messages
               SET source_provider='provider-b', model='model-b'
             WHERE session_id='s-ext' AND request_id='req-legacy-mixed'
               AND source_kind='external' AND role='assistant';
            """
            XCTAssertEqual(sqlite3_exec(raw, corrupt, nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_changes(raw), 1)
        }

        let reopened = try ESISDatabase(url: url, createIfNeeded: false)
        defer { reopened.close() }
        XCTAssertThrowsError(try reopened.verifyExternalTurn(
            sessionID: "s-ext", requestID: "req-legacy-mixed", verifiedAt: Date()
        )) { error in
            let conflict = error as? ESISDatabase.ExternalTurnProvenanceConflict
            XCTAssertEqual(conflict?.role, "assistant")
            XCTAssertEqual(conflict?.storedProvider, "openai-compatible")
            XCTAssertEqual(conflict?.incomingProvider, "provider-b")
        }
        XCTAssertEqual(
            try reopened.chatTurnProvenance(
                sessionID: "s-ext", requestID: "req-legacy-mixed").map(\.turnState),
            ["recorded", "recorded"])
    }

    /// Verification must inspect and update the exact same set of rows. A
    /// duplicate legacy assistant row cannot hitch a ride on the newest pair.
    func testVerificationRefusesDuplicateExternalRows() throws {
        let url = tempURL("duplicate-external-rows")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        try recordTurn(
            db, requestID: "req-duplicate", question: "question", answer: "answer")
        db.close()
        defer { cleanup(url) }

        do {
            var raw: OpaquePointer?
            guard sqlite3_open(url.path, &raw) == SQLITE_OK, let raw else {
                XCTFail("could not open duplicate fixture with SQLite")
                return
            }
            defer { _ = sqlite3_close(raw) }

            var statement: OpaquePointer?
            let query = "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='chat_messages';"
            guard sqlite3_prepare_v2(raw, query, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                XCTFail("could not enumerate chat_messages triggers")
                return
            }
            var triggerNames: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let value = sqlite3_column_text(statement, 0) {
                    triggerNames.append(String(cString: value))
                }
            }
            _ = sqlite3_finalize(statement)
            for name in triggerNames {
                let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
                let drop = "DROP TRIGGER IF EXISTS \"\(escaped)\";"
                XCTAssertEqual(sqlite3_exec(raw, drop, nil, nil, nil), SQLITE_OK)
            }

            let duplicate = """
            INSERT INTO chat_messages(
                session_id, role, content, model, content_sha256, created_at,
                content_object_id, turn_state, source_kind, source_provider, request_id
            )
            SELECT session_id, role, content, model, content_sha256, created_at,
                   content_object_id, turn_state, source_kind, source_provider, request_id
              FROM chat_messages
             WHERE session_id='s-ext' AND request_id='req-duplicate'
               AND source_kind='external' AND role='assistant';
            """
            XCTAssertEqual(sqlite3_exec(raw, duplicate, nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_changes(raw), 1)
        }

        let reopened = try ESISDatabase(url: url, createIfNeeded: false)
        defer { reopened.close() }
        XCTAssertThrowsError(try reopened.verifyExternalTurn(
            sessionID: "s-ext", requestID: "req-duplicate", verifiedAt: Date()
        )) { error in
            let ambiguous = error as? ESISDatabase.ExternalTurnAmbiguousRows
            XCTAssertEqual(ambiguous?.role, "assistant")
            XCTAssertEqual(ambiguous?.rowCount, 2)
        }
        XCTAssertEqual(
            try reopened.chatTurnProvenance(
                sessionID: "s-ext", requestID: "req-duplicate").map(\.turnState),
            ["recorded", "recorded", "recorded"])
    }

    /// A client-declared internal operation keeps its text but can never be
    /// promoted to retrievable knowledge by verification.
    func testInternalOperationIsKeptButNeverPromoted() throws {
        let (url, db) = try open("internal")
        defer { db.close(); cleanup(url) }

        try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-6",
            userText: "内部记账：会话摘要", model: nil, createdAt: Date(),
            eligibility: .internalOperation)
        try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-6",
            assistantText: "内部答复", model: nil, createdAt: Date(),
            eligibility: .internalOperation)

        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-ext", requestID: "req-6")
                .map(\.turnState),
            ["internal", "internal"])
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-6", verifiedAt: Date()),
            0)
        XCTAssertTrue(try db.chatIndexRows(sessionIDs: ["s-ext"]).isEmpty)
        XCTAssertEqual(try db.listChatMessages(sessionID: "s-ext").count, 2)
    }

    /// Local retry reuse stays inside the local lineage: it must not adopt an
    /// external row, nor promote it by committing the local turn.
    func testLocalRetryReuseNeverAdoptsAnExternalRow() throws {
        let (url, db) = try open("lineage")
        defer { db.close(); cleanup(url) }

        let externalID = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-5",
            userText: "同一句话", model: nil, createdAt: Date())

        let localID = try db.appendChatMessage(
            sessionID: "s-ext", role: "user", content: "同一句话",
            model: nil, createdAt: Date())
        XCTAssertNotEqual(localID, externalID)
        try db.commitChatTurn(
            sessionID: "s-ext", userMessageID: localID,
            assistantText: "本地回答", model: nil, createdAt: Date())

        XCTAssertEqual(
            try db.chatTurnProvenance(sessionID: "s-ext", requestID: "req-5")
                .map(\.turnState),
            ["recorded"])
        XCTAssertEqual(
            try db.chatIndexRows(sessionIDs: ["s-ext"]).map(\.role),
            ["user", "assistant"])
    }

    /// Two identical local requests may overlap after one has opened a pending
    /// row. The retry must own a distinct row so the first request's detach
    /// cannot make the retry's commit fail.
    func testConcurrentIdenticalLocalTurnsKeepPendingRowsRequestScoped() throws {
        let (url, db) = try open("request-scoped-pending")
        defer { db.close(); cleanup(url) }

        let firstID = try db.appendChatMessage(
            sessionID: "s-local", role: "user", content: "同一条本地请求",
            model: nil, createdAt: Date())
        let retryID = try db.appendChatMessage(
            sessionID: "s-local", role: "user", content: "同一条本地请求",
            model: nil, createdAt: Date())

        XCTAssertNotEqual(
            firstID, retryID,
            "a retry must not adopt another request's still-pending user row")

        XCTAssertTrue(try db.closePendingChatTurn(
            sessionID: "s-local", userMessageID: firstID, terminal: .detached))
        try db.commitChatTurn(
            sessionID: "s-local", userMessageID: retryID,
            assistantText: "重试请求完成", model: nil, createdAt: Date())

        let committed = try db.chatIndexRows(sessionIDs: ["s-local"])
        XCTAssertEqual(committed.map(\.role), ["user", "assistant"])
        XCTAssertEqual(
            committed.first?.messageID, retryID,
            "the retry's own user row must remain pending and commit after the older request detaches")
        XCTAssertFalse(try db.closePendingChatTurn(
            sessionID: "s-local", userMessageID: retryID, terminal: .detached),
            "terminalization after commit must not rewrite the committed retry")
    }

    /// The record path writes every withheld answer shape exactly as it writes a
    /// settled one, so standing cannot come from presence, text, or provider —
    /// only from an explicit verification of that request. The settled turn in
    /// the same session and store is the control that turns the withheld rows'
    /// absence of standing into a measurement rather than an empty database.
    func testWithheldAnswerShapesAreKeptWithoutStandingBesideASettledTurn() throws {
        let (url, db) = try open("withheld-shapes")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        // Each entry is one #280 withhold reason; all share the query terms, so
        // any leak into the index or the retrieval result would show as a hit.
        let withheld: [(reason: String, requestID: String, answer: String)] = [
            ("terminated_by_length", "req-length", "被截断的回答：节点工期 42"),
            ("no_completion_semantics", "req-no-term", "无终止语义的回答：节点工期 42"),
            ("conflicting_terminal_signals", "req-conflict", "矛盾终止信号的回答：节点工期 42"),
            ("terminal_non_answer_tool_calls", "req-tool", "工具调用输出：节点工期 42"),
        ]
        var withheldItemIDs: Set<String> = []
        for shape in withheld {
            let userID = try db.recordExternalTurn(
                sessionID: "s-ext", provider: "openai-compatible", requestID: shape.requestID,
                userText: "外部请求：关键线路 节点工期", model: "gpt-x", createdAt: Date())
            let assistantID = try db.recordExternalResponse(
                sessionID: "s-ext", provider: "openai-compatible", requestID: shape.requestID,
                assistantText: shape.answer, model: "gpt-x", createdAt: Date())
            withheldItemIDs.insert("chat:s-ext/\(userID)")
            withheldItemIDs.insert("chat:s-ext/\(assistantID)")
        }

        try recordTurn(
            db, requestID: "req-settled",
            question: "外部请求：关键线路 节点工期",
            answer: "外部回答：节点工期 42 天")
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-settled", verifiedAt: Date()),
            2)

        let withheldProvenance = try db.chatTurnProvenance(sessionID: "s-ext")
            .filter { $0.requestID != "req-settled" }
        XCTAssertEqual(withheldProvenance.count, withheld.count * 2)
        XCTAssertEqual(
            Set(withheldProvenance.compactMap(\.requestID)), Set(withheld.map(\.requestID)))
        XCTAssertTrue(
            withheldProvenance.allSatisfy { $0.turnState == "recorded" },
            "no answer shape can be recorded into a promoted state")
        XCTAssertTrue(
            withheldProvenance.allSatisfy { $0.verifiedAt == nil && !$0.isEligible },
            "verification of another request must not settle these rows")

        // Only the settled request is indexed; the withheld rows keep their bytes.
        let indexedItemIDs = Set(try db.chatIndexRows(sessionIDs: ["s-ext"]).map(\.itemID))
        XCTAssertFalse(indexedItemIDs.isEmpty, "the settled turn must be indexed")
        XCTAssertEqual(indexedItemIDs.count, 2)
        XCTAssertTrue(indexedItemIDs.isDisjoint(with: withheldItemIDs))
        XCTAssertEqual(
            try db.listChatMessages(sessionID: "s-ext").count, withheld.count * 2 + 2,
            "withholding standing must not discard any information")

        let resolution = try loop.resolve(.init(
            sessionID: "s-ext", query: "节点工期", includeChat: true,
            chatSessionIDs: ["s-ext"]))
        XCTAssertFalse(resolution.hits.isEmpty, "the settled turn must be retrievable")
        let hitItemIDs = Set(resolution.hits.map(\.itemID))
        XCTAssertTrue(hitItemIDs.isSubset(of: indexedItemIDs))
        XCTAssertTrue(
            hitItemIDs.isDisjoint(with: withheldItemIDs),
            "a withheld shape sharing the query terms must not read as history")
    }

    /// Internal bookkeeping sits in the same rows as external answers, so its
    /// exclusion is only meaningful beside history that *is* retrievable — and
    /// even a direct verification of its own request must not promote it.
    func testInternalOperationStaysOutOfRetrievalBesideCommittedHistory() throws {
        let (url, db) = try open("internal-beside-committed")
        defer { db.close(); cleanup(url) }
        let loop = InformationLoop(database: db)

        try recordTurn(
            db, requestID: "req-open",
            question: "外部请求：关键线路 节点工期", answer: "外部回答：节点工期 42 天")
        let internalUser = try db.recordExternalTurn(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-bookkeeping",
            userText: "内部记账：rollout 摘要 节点工期", model: nil, createdAt: Date(),
            eligibility: .internalOperation)
        let internalAssistant = try db.recordExternalResponse(
            sessionID: "s-ext", provider: "openai-compatible", requestID: "req-bookkeeping",
            assistantText: "内部摘要：17 条 节点工期", model: nil, createdAt: Date(),
            eligibility: .internalOperation)
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-open", verifiedAt: Date()),
            2)

        let internalProvenance = try db.chatTurnProvenance(
            sessionID: "s-ext", requestID: "req-bookkeeping")
        XCTAssertEqual(internalProvenance.map(\.turnState), ["internal", "internal"])
        XCTAssertTrue(internalProvenance.allSatisfy { $0.verifiedAt == nil && !$0.isEligible })
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: "s-ext", requestID: "req-bookkeeping", verifiedAt: Date()),
            0,
            "verifying an internal request by id must not promote it either")

        let indexedItemIDs = Set(try db.chatIndexRows(sessionIDs: ["s-ext"]).map(\.itemID))
        XCTAssertEqual(indexedItemIDs.count, 2, "only the committed turn is indexed")
        XCTAssertFalse(indexedItemIDs.contains("chat:s-ext/\(internalUser)"))
        XCTAssertFalse(indexedItemIDs.contains("chat:s-ext/\(internalAssistant)"))

        let resolution = try loop.resolve(.init(
            sessionID: "s-ext", query: "节点工期", includeChat: true,
            chatSessionIDs: ["s-ext"]))
        XCTAssertFalse(resolution.hits.isEmpty)
        let hitItemIDs = Set(resolution.hits.map(\.itemID))
        XCTAssertTrue(hitItemIDs.isSubset(of: indexedItemIDs))
        XCTAssertFalse(hitItemIDs.contains("chat:s-ext/\(internalUser)"))
        XCTAssertFalse(hitItemIDs.contains("chat:s-ext/\(internalAssistant)"))
        XCTAssertFalse(
            loop.contextBlock(resolution).contains("内部摘要"),
            "internal bookkeeping must never reach the injected context")
        XCTAssertEqual(
            try db.listChatMessages(sessionID: "s-ext").count, 4,
            "kept for audit means the text stays readable")
    }

    func testLegacyExternalTurnWithoutProviderCannotBePromoted() throws {
        let (url, db) = try open("legacy-provider-missing")
        defer { db.close(); cleanup(url) }
        try recordTurn(
            db, requestID: "legacy-no-provider",
            question: "legacy question", answer: "legacy answer")

        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
        guard let raw else {
            XCTFail("could not open fixture database for legacy-row mutation")
            return
        }
        defer { sqlite3_close(raw) }
        let update = """
        UPDATE chat_messages SET source_provider=NULL
        WHERE session_id='s-ext' AND request_id='legacy-no-provider'
          AND source_kind='external';
        """
        XCTAssertEqual(sqlite3_exec(raw, update, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try db.verifyExternalTurn(
            sessionID: "s-ext", requestID: "legacy-no-provider", verifiedAt: Date())) {
            XCTAssertTrue($0 is ESISDatabase.ExternalTurnProvenanceConflict)
        }
        XCTAssertTrue(try db.chatIndexRows(sessionIDs: ["s-ext"]).isEmpty)
    }
}
