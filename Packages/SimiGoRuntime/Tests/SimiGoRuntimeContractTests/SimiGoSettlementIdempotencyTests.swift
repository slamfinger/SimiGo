import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// Cross-path idempotency at the common settlement entrance. Every path
/// (chat, responses, MCP) settles through `settleTurn` →
/// `recordNativeSettlementWithIdentityAndAdvancement`, so these are the
/// semantics every path inherits: a declared source identity is the authority,
/// a replay returns the existing settlement, and anything that could be an
/// update must say so with an explicit revision.
final class SimiGoSettlementIdempotencyTests: XCTestCase {

    private var url: URL!
    private var db: SimiGoESISDatabase!
    private var loop: SimiGoInformationLoop!

    private let identity = SimiGoSettlementIdentityBinding.Identity(
        model: "idem-model", tokenizer: "idem-tokenizer")

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-idem-\(UUID().uuidString).sqlite3")
        db = try SimiGoESISDatabase(url: url)
        loop = SimiGoInformationLoop(database: db)
        try db.runMigrations()
    }

    override func tearDownWithError() throws {
        db?.close()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: url.path + suffix))
        }
        db = nil; loop = nil; url = nil
    }

    private func rawText(_ sql: String) throws -> String {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        guard let handle else { return "" }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &stmt, nil), SQLITE_OK)
        guard let stmt else { return "" }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    private func counterSnapshot() throws -> [String: Int] {
        var out: [String: Int] = [:]
        for table in [
            "settlements", "execution_states", "is_objects", "is_index_entries",
            "dependency_edges", "settlement_summaries",
            "settlement_source_identities", "settlement_operation_keys",
            "information_demands", "information_advancements",
        ] {
            out[table] = try db.count(table)
        }
        return out
    }

    private func source(
        type: String = "chat", session: String = "s1", turn: String = "t1",
        message: String = "m1", revision: String = "1"
    ) -> SimiGoESISDatabase.DeclaredSourceIdentity {
        .init(
            sourceType: type, sourceSessionID: session, sourceTurnID: turn,
            sourceMessageID: message, sourceRevision: revision)
    }

    @discardableResult
    private func settle(
        _ text: String, state: String, session: String? = "s1",
        source: SimiGoESISDatabase.DeclaredSourceIdentity? = nil,
        operationKey: String? = nil
    ) throws -> SimiGoInformationLoop.TurnSettlement {
        try loop.settleTurn(
            generatedText: text, resolution: nil, stateID: state,
            parentStateID: nil, position: 0, modelIdentity: identity.model,
            identity: identity, sessionID: session, summaryQuery: "idem query",
            sourceIdentity: source, operationKey: operationKey)
    }

    private func assertRejected(
        _ expected: (SimiGoESISDatabase.SettlementIdentityError) -> Bool,
        _ label: String,
        _ body: () throws -> Void
    ) throws {
        do {
            try body()
            XCTFail("\(label) was accepted")
        } catch let error as SimiGoESISDatabase.SettlementIdentityError {
            XCTAssertTrue(expected(error), "\(label): unexpected \(error)")
        }
    }

    // MARK: - Same source, same revision, same content

    func testReplayReturnsTheExistingSettlementAndWritesNothing() throws {
        let first = try settle("answer one", state: "S-1", source: source())
        XCTAssertFalse(first.reused)
        let before = try counterSnapshot()

        let replay = try settle("answer one", state: "S-2", source: source())
        XCTAssertTrue(replay.reused)
        XCTAssertEqual(replay.settlementID, first.settlementID)
        XCTAssertEqual(replay.stateID, "S-1", "a replay never adopts the requested state")
        XCTAssertEqual(replay.advancementID, first.advancementID)

        XCTAssertEqual(try counterSnapshot(), before)
        XCTAssertNil(
            try db.executionStateModelIdentity("S-2"),
            "a replay must not manufacture a second execution")
        XCTAssertEqual(
            try db.settlementValidity(first.settlementID), "valid")
        XCTAssertNotNil(
            try db.settlementSummary(settlementID: first.settlementID))
    }

    // MARK: - Same source, same revision, different content

    func testSameRevisionWithDifferentContentIsRejectedAtomically() throws {
        let first = try settle("answer one", state: "S-1", source: source())
        let before = try counterSnapshot()

        try assertRejected({ err in
            if case .identityConflict = err { return true }
            return false
        }, "same revision with new content") {
            _ = try self.settle("answer two", state: "S-2", source: self.source())
        }

        XCTAssertEqual(try counterSnapshot(), before)
        XCTAssertNil(try db.executionStateModelIdentity("S-2"))
        XCTAssertEqual(try db.settlementValidity(first.settlementID), "valid")
        XCTAssertEqual(
            try rawText("""
            SELECT payload_digest FROM settlement_source_identities
            WHERE source_message_id='m1' AND source_revision=1;
            """),
            try db.settlementPayloadDigest(first.settlementID))
    }

    // MARK: - Declared new revision

    func testDeclaredNewRevisionCreatesAVersionLink() throws {
        let first = try settle("answer one", state: "S-1", source: source())
        let second = try settle(
            "answer two", state: "S-2", source: source(revision: "2"))

        XCTAssertFalse(second.reused)
        XCTAssertNotEqual(second.settlementID, first.settlementID)
        XCTAssertEqual(try rawText("""
        SELECT previous_settlement_id FROM settlement_source_identities
        WHERE source_message_id='m1' AND source_revision=2;
        """), first.settlementID)
        XCTAssertEqual(try rawText("""
        SELECT COUNT(*) FROM settlement_source_identities
        WHERE source_message_id='m1';
        """), "2")
        XCTAssertEqual(try db.settlementValidity(first.settlementID), "valid")
        XCTAssertEqual(try db.settlementValidity(second.settlementID), "valid")

        let citable = try db.citableSettlementSummaries(sessionID: nil)
            .map(\.settlementID)
        XCTAssertTrue(citable.contains(first.settlementID))
        XCTAssertTrue(citable.contains(second.settlementID))
        XCTAssertEqual(try db.count("settlement_summaries"), 2)
    }

    func testRevisionTransitionsMustBeExplicitAndContiguous() throws {
        // No predecessor: the first declared revision is 1.
        try assertRejected({ err in
            if case .revisionConflict = err { return true }
            return false
        }, "first declared revision 2") {
            _ = try self.settle("answer one", state: "S-1", source: self.source(revision: "2"))
        }
        XCTAssertEqual(try db.count("settlements"), 0)

        let first = try settle("answer one", state: "S-1", source: source())

        // A gap in the version chain.
        try assertRejected({ err in
            if case .revisionConflict = err { return true }
            return false
        }, "revision gap 1 -> 3") {
            _ = try self.settle("answer two", state: "S-2", source: self.source(revision: "3"))
        }
        // A new revision must carry new content: a retry can never be
        // mistaken for an update.
        try assertRejected({ err in
            if case .revisionConflict = err { return true }
            return false
        }, "revision 2 repeating revision 1 content") {
            _ = try self.settle("answer one", state: "S-2", source: self.source(revision: "2"))
        }

        XCTAssertEqual(try db.count("settlements"), 1)
        XCTAssertEqual(try db.count("settlement_source_identities"), 1)
        XCTAssertNil(try db.executionStateModelIdentity("S-2"))
        XCTAssertEqual(try db.settlementValidity(first.settlementID), "valid")
    }

    // MARK: - No source identity

    func testAbsentSourceIdentityStaysOnTheOrdinaryWritePath() throws {
        let first = try settle("same text", state: "S-1", source: nil)
        let second = try settle("same text", state: "S-2", source: nil)

        XCTAssertFalse(first.reused)
        XCTAssertFalse(second.reused)
        XCTAssertNotEqual(first.settlementID, second.settlementID)
        XCTAssertEqual(try db.count("settlements"), 2)
        XCTAssertEqual(try db.count("settlement_source_identities"), 0)
        XCTAssertEqual(try db.count("settlement_operation_keys"), 0)
    }

    func testDifferentSourcesWithIdenticalTextAreBothKept() throws {
        let first = try settle(
            "same text", state: "S-1", source: source(message: "m1"))
        let second = try settle(
            "same text", state: "S-2", source: source(message: "m2"))

        XCTAssertFalse(first.reused)
        XCTAssertFalse(second.reused)
        XCTAssertNotEqual(first.settlementID, second.settlementID)
        XCTAssertEqual(try db.count("settlements"), 2)
        XCTAssertEqual(try db.count("settlement_source_identities"), 2)
        XCTAssertEqual(
            try db.citableSettlementSummaries(sessionID: nil).count, 2)
    }

    // MARK: - Incomplete declarations

    func testPartialSourceIdentityIsRefusedInsteadOfMergedByText() throws {
        try assertRejected({ err in
            err == .incompleteSourceIdentity(
                missing: ["source_turn_id", "source_message_id", "source_revision"])
        }, "partial declaration") {
            _ = try self.settle(
                "answer one", state: "S-1",
                source: .init(sourceType: "chat", sourceSessionID: "s1"))
        }
        XCTAssertEqual(try db.count("settlements"), 0)
        XCTAssertEqual(try db.count("settlement_source_identities"), 0)
        XCTAssertNil(try db.executionStateModelIdentity("S-1"))
    }

    func testInvalidRevisionIsRefused() throws {
        for value in ["0", "-1", "abc", "1.5"] {
            try assertRejected({ err in
                err == .invalidRevision(value)
            }, "revision '\(value)'") {
                _ = try self.settle(
                    "answer one", state: "S-1", source: self.source(revision: value))
            }
        }
        XCTAssertEqual(try db.count("settlements"), 0)
    }

    // MARK: - Operation key

    func testOperationKeyMakesASingleCallReplayable() throws {
        let first = try settle(
            "answer one", state: "S-1", source: nil, operationKey: "op-1")
        let replay = try settle(
            "answer one", state: "S-2", source: nil, operationKey: "op-1")

        XCTAssertTrue(replay.reused)
        XCTAssertEqual(replay.settlementID, first.settlementID)
        XCTAssertEqual(replay.stateID, "S-1")
        XCTAssertEqual(try db.count("settlements"), 1)
        XCTAssertEqual(
            try rawText("""
            SELECT settlement_id FROM settlement_operation_keys
            WHERE operation_key='op-1';
            """), first.settlementID)

        try assertRejected({ err in
            if case .operationKeyConflict = err { return true }
            return false
        }, "operation key with new content") {
            _ = try self.settle(
                "answer two", state: "S-3", source: nil, operationKey: "op-1")
        }
        XCTAssertEqual(try db.count("settlements"), 1)
    }

    func testOperationKeyNeverAdoptsADeclaredSourceAfterTheFact() throws {
        let first = try settle(
            "answer one", state: "S-1", source: nil, operationKey: "op-1")

        try assertRejected({ err in
            if case .operationKeyConflict = err { return true }
            return false
        }, "identity declared after a key-only settle") {
            _ = try self.settle(
                "answer one", state: "S-2", source: self.source(),
                operationKey: "op-1")
        }
        XCTAssertEqual(try db.count("settlements"), 1)
        XCTAssertEqual(try db.count("settlement_source_identities"), 0)
        XCTAssertEqual(try db.settlementValidity(first.settlementID), "valid")
    }

    func testOperationKeyBindsToTheIdentitySettlementOnAnIdentityHit() throws {
        let first = try settle("answer one", state: "S-1", source: source())

        // The identity is the authority; the key only makes this call
        // replayable and must bind to the identity's settlement.
        let withKey = try settle(
            "answer one", state: "S-2", source: source(), operationKey: "op-1")
        XCTAssertTrue(withKey.reused)
        XCTAssertEqual(withKey.settlementID, first.settlementID)

        // A replay by the key alone lands on the same settlement.
        let byKey = try settle(
            "answer one", state: "S-3", source: nil, operationKey: "op-1")
        XCTAssertTrue(byKey.reused)
        XCTAssertEqual(byKey.settlementID, first.settlementID)
        XCTAssertEqual(try db.count("settlements"), 1)
        XCTAssertEqual(try db.count("settlement_operation_keys"), 1)
    }

    // MARK: - Execution state

    func testADeclaredWriteCannotSettleAnAlreadySettledStateTwice() throws {
        _ = try settle("answer one", state: "S-1", source: source(message: "m1"))

        try assertRejected({ err in
            if case .stateAlreadySettled = err { return true }
            return false
        }, "second source on a settled state") {
            _ = try self.settle(
                "answer two", state: "S-1", source: self.source(message: "m2"))
        }
        XCTAssertEqual(try db.count("settlements"), 1)
        XCTAssertEqual(try db.count("settlement_source_identities"), 1)
    }

    // MARK: - Demand lifecycle is per request

    func testNoSessionDemandsAreIndependentWhileKnowledgeStaysShared() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-idem-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("shared needle knowledge\n".utf8)
            .write(to: root.appendingPathComponent("a.md"))
        try db.settleWorkRootContents(
            rootID: "work", rootURL: root, carryText: false)

        let first = try loop.resolve(.init(query: "needle", includeChat: false))
        let second = try loop.resolve(.init(query: "needle", includeChat: false))
        XCTAssertFalse(first.reused)
        XCTAssertFalse(second.reused)
        XCTAssertNotEqual(first.demandID, second.demandID)
        XCTAssertEqual(first.hits.map(\.itemID), second.hits.map(\.itemID))
        XCTAssertEqual(
            try rawText("""
            SELECT state FROM information_demands WHERE demand_id='\(first.demandID)';
            """), "RESOLVED", "one request's demand must not supersede another's")

        // A declared request identity makes retries land on one demand.
        let retried = try loop.resolve(.init(
            requestIdentity: "req-1", query: "needle", includeChat: false))
        let retryAgain = try loop.resolve(.init(
            requestIdentity: "req-1", query: "needle", includeChat: false))
        XCTAssertTrue(retryAgain.reused)
        XCTAssertEqual(retried.demandID, retryAgain.demandID)
        XCTAssertNotEqual(retried.demandID, first.demandID)

        // A session is its own request identity, shared by the same session.
        let bySession = try loop.resolve(.init(
            sessionID: "s-chat", query: "needle", includeChat: false))
        let bySessionAgain = try loop.resolve(.init(
            sessionID: "s-chat", query: "needle", includeChat: false))
        XCTAssertTrue(bySessionAgain.reused)
        XCTAssertEqual(bySession.demandID, bySessionAgain.demandID)
        XCTAssertEqual(
            try rawText("""
            SELECT request_identity FROM information_demands
            WHERE demand_id='\(bySession.demandID)';
            """), "session:s-chat")
    }

    // MARK: - Shared personal space, eligible rows only

    func testChatRetrievalCoversThePersonalSpaceAndOnlyEligibleRows() throws {
        let userID = try db.appendChatMessage(
            sessionID: "chat-a", role: "user", content: "shared chat needle",
            model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: "chat-a", userMessageID: userID,
            assistantText: "committed needle reply", model: nil,
            createdAt: Date())
        _ = try db.appendChatMessage(
            sessionID: "chat-a", role: "user", content: "pending needle",
            model: nil, createdAt: Date())
        _ = try db.appendChatMessage(
            sessionID: "chat-b", role: "user", content: "internal needle",
            model: nil, createdAt: Date(), eligibility: .internalOperation)

        // No session, no session filter: the whole personal space, regardless
        // of which session wrote the row. Only committed ordinary rows qualify.
        let shared = try loop.resolve(.init(query: "needle", includeChat: true))
        let cited = shared.hits.filter { $0.kind == "chat" }
        XCTAssertEqual(
            Set(cited.map(\.locator)),
            ["session:chat-a#1", "session:chat-a#2"])
        XCTAssertFalse(cited.contains { $0.lineText.contains("pending") })
        XCTAssertFalse(cited.contains { $0.lineText.contains("internal") })

        // A different session still reads the same shared knowledge.
        let otherSession = try loop.resolve(.init(
            sessionID: "chat-z", query: "needle", includeChat: true))
        XCTAssertEqual(
            otherSession.hits.filter { $0.kind == "chat" }.count, 2)

        // Narrowing to an internal session never makes internal rows citable.
        let narrowed = try loop.resolve(.init(
            query: "needle", includeChat: true, chatSessionIDs: ["chat-b"]))
        XCTAssertTrue(narrowed.hits.filter { $0.kind == "chat" }.isEmpty)
    }

    // MARK: - Concurrent duplicate submissions

    func testConcurrentDuplicateSettlesProduceExactlyOneSettlement() throws {
        let declaration = source()
        let results = NSMutableArray()
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let outcome: SwiftyResult
            do {
                let handle = try SimiGoESISDatabase(url: url)
                defer { handle.close() }
                let settlement = try SimiGoInformationLoop(database: handle)
                    .settleTurn(
                        generatedText: "answer one",
                        resolution: nil,
                        stateID: index == 0 ? "S-A" : "S-B",
                        parentStateID: nil, position: 0,
                        modelIdentity: identity.model, identity: identity,
                        sessionID: "s1", summaryQuery: "idem query",
                        sourceIdentity: declaration)
                outcome = .success(settlement)
            } catch {
                outcome = .failure(error)
            }
            lock.lock()
            results.add(outcome)
            lock.unlock()
        }

        let settlements = results.compactMap { ($0 as? SwiftyResult)?.settlement }
        XCTAssertEqual(settlements.count, 2, "neither concurrent settle may fail")
        XCTAssertEqual(Set(settlements.map(\.settlementID)).count, 1)
        XCTAssertEqual(settlements.filter { !$0.reused }.count, 1)
        XCTAssertEqual(settlements.filter(\.reused).count, 1)
        XCTAssertEqual(try db.count("settlements"), 1)
        XCTAssertEqual(try db.count("settlement_source_identities"), 1)
        XCTAssertEqual(try db.count("settlement_summaries"), 1)
        XCTAssertEqual(
            try db.count("execution_states"), 1,
            "only the winning submission creates an execution state")
    }

    private enum SwiftyResult {
        case success(SimiGoInformationLoop.TurnSettlement)
        case failure(Error)

        var settlement: SimiGoInformationLoop.TurnSettlement? {
            if case .success(let value) = self { return value }
            return nil
        }
    }
}
