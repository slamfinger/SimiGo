import Darwin
import Foundation
import SQLite3

/// Information Space record writes: chat turns, turn digests, external-provider
/// turns, the MCP turn ledger and project notes, moved verbatim from
/// ESISDatabase.swift to keep the carrier file navigable. Pure file move;
/// no logic changes.
extension ESISDatabase: ISRenderingSnapshotStore {
    // MARK: - 对话落库（Information Space：会话即信息）

    /// Semantic standing of a chat turn. `ordinary` is the user's conversation;
    /// `internalOperation` is client bookkeeping (rollout analysis, title
    /// generation, memory extraction) that is kept as a record but never
    /// becomes a retrieval source or a settled result. Arriving on a wire is
    /// not what grants ordinary standing — the request declares it.
    public enum ChatTurnEligibility: String, Sendable {
        case ordinary
        case internalOperation = "internal"

        /// 记账类请求问的是「这段文本说了什么」，不是「空间里有什么」，所以
        /// 不装配上下文（不检索、不注入、不结算、不记轮次），直接按它带来的
        /// 文本作答。
        ///
        /// 只有 HTTP 会话路径看这个属性。同名的 standing 出现在导入路径上时
        /// （`ExternalTurnSink`、`MultiFormatCollection`）只表示审计存档，那些
        /// 行是直写库的，本来就不经过上下文装配——两处不要互相推断。
        public var skipsContextAssembly: Bool { self == .internalOperation }
    }

    /// Who produced a chat line. Local turns are the app's own conversation;
    /// external turns arrived through an upstream provider and keep that
    /// provenance for as long as the row exists.
    public enum ChatTurnSource: String, Sendable {
        case local
        case external
    }

    /// The standings a line can hold, as stored in `turn_state`. They are
    /// distinct questions: in flight (`pending`), externally recorded
    /// (`recorded`), ended without completion
    /// (`failed`/`cancelled`/`detached`/`abandoned`), internal bookkeeping
    /// (`internal`), and verified/retrievable (`committed`; ordinary retrieval reads
    /// `committed` rows only, further narrowed by request scope).
    public enum ChatTurnState: String, Sendable {
        /// Local input whose own request is still in flight.
        case pending
        /// Persisted with provenance, not yet verified: recorded only.
        case recorded
        /// Verified/settled; eligible for ordinary retrieval.
        case committed
        /// The request ended before the turn completed; never retrieval eligible.
        case failed
        /// The request was cancelled before the turn completed; never retrieval eligible.
        case cancelled
        /// The client detached while generation continued; never retrieval eligible.
        case detached
        /// The process holding the request ended while the turn was in flight, so
        /// no outcome is known. Written only by the launch sweep
        /// (`closeStrandedPendingTurns`); never retrieval eligible.
        case abandoned
        /// Client bookkeeping kept as a record, never ordinary memory.
        case internalOperation = "internal"
    }

    /// Terminal standing for a local request that did not complete.
    public enum ChatTurnTerminal: String, Sendable {
        case failed
        case cancelled
        case detached
    }

    /// Chat write set to commit with an authoritative model settlement.
    public struct ChatTurnCommit: Sendable {
        public let sessionID: String
        public let userMessageID: Int64
        public let assistantText: String
        public let model: String?
        public let createdAt: Date
        public let eligibility: ChatTurnEligibility
        /// Ledger request id shared by this turn's user and assistant rows.
        /// nil keeps the historical unpaired shape (no digest-source join).
        public let requestID: String?

        public init(sessionID: String, userMessageID: Int64, assistantText: String,
                    model: String?, createdAt: Date,
                    eligibility: ChatTurnEligibility = .ordinary,
                    requestID: String? = nil) {
            self.sessionID = sessionID
            self.userMessageID = userMessageID
            self.assistantText = assistantText
            self.model = model
            self.createdAt = createdAt
            self.eligibility = eligibility
            self.requestID = requestID
        }
    }

    /// Append one conversation line. An ordinary user row starts `pending`
    /// and belongs to the request that receives its row id. A retry is another
    /// request, even when its text is byte-identical: sharing a pending row would
    /// let one request's cancellation terminalize another request's turn.
    /// `commitChatTurn` promotes only the row held by its own request.
    /// Other roles are written at completion, so they are eligible at once.
    /// Internal-operation rows are written `internal` and stay there.
    ///
    /// Ordinary user turns always receive a fresh row id. Identical internal
    /// bookkeeping rows may be reused because they never enter ordinary history.
    @discardableResult
    public func appendChatMessage(
        sessionID: String, role: String, content: String, model: String?, createdAt: Date,
        eligibility: ChatTurnEligibility = .ordinary, requestID: String? = nil
    ) throws -> Int64 {
        let data = Data(content.utf8)
        let digest = NativeSHA256.hexDigest(data)
        let state = role == "user"
            ? Self.pendingState(for: eligibility) : Self.completedState(for: eligibility)
        if role == "user", eligibility == .internalOperation,
            let existing = try lastUserMessage(sessionID: sessionID),
            existing.digest == digest,
            existing.state == ChatTurnEligibility.internalOperation.rawValue {
            return existing.messageID
        }
        return try transactionResult {
            try insertChatMessage(
                sessionID: sessionID, role: role, data: data, digest: digest,
                model: model, createdAt: createdAt, state: state, requestID: requestID)
        }
    }

    private static func pendingState(for eligibility: ChatTurnEligibility) -> String {
        eligibility == .internalOperation
            ? eligibility.rawValue : ChatTurnState.pending.rawValue
    }

    private static func completedState(for eligibility: ChatTurnEligibility) -> String {
        eligibility == .internalOperation
            ? eligibility.rawValue : ChatTurnState.committed.rawValue
    }

    /// Commit this turn: store the reply and promote the user row that started
    /// the turn in one transaction, so a reader never sees the answer without
    /// the question it answers, nor the question before the turn is done.
    @discardableResult
    public func commitChatTurn(
        sessionID: String, userMessageID: Int64, assistantText: String,
        model: String?, createdAt: Date,
        eligibility: ChatTurnEligibility = .ordinary, requestID: String? = nil
    ) throws -> Int64 {
        try transactionResult {
            try insertChatTurnRows(.init(
                sessionID: sessionID, userMessageID: userMessageID,
                assistantText: assistantText, model: model, createdAt: createdAt,
                eligibility: eligibility, requestID: requestID))
        }
    }

    /// Caller owns the transaction.
    @discardableResult
    func insertChatTurnRows(_ write: ChatTurnCommit) throws -> Int64 {
        let data = Data(write.assistantText.utf8)
        let digest = NativeSHA256.hexDigest(data)
        let assistantID = try insertChatMessage(
            sessionID: write.sessionID, role: "assistant", data: data, digest: digest,
            model: write.model, createdAt: write.createdAt,
            state: Self.completedState(for: write.eligibility),
            requestID: write.requestID)
        if write.eligibility == .ordinary {
            guard write.userMessageID > 0 else {
                throw DatabaseError.sql(
                    "commitChatTurn: ordinary turn requires a pending local user row")
            }
            let promotedRows = try execBinding("""
            UPDATE chat_messages SET turn_state='committed'
            WHERE id=? AND session_id=? AND role='user'
              AND source_kind='local' AND turn_state='pending';
            """) { stmt in
                try bind(stmt, 1, write.userMessageID)
                try bind(stmt, 2, write.sessionID)
            }
            guard promotedRows == 1 else {
                throw DatabaseError.sql(
                    "commitChatTurn: expected one pending local user row; updated \(promotedRows)")
            }
        }
        return assistantID
    }

    /// Close an uncompleted local user row without promoting it into retrieval
    /// history. This is idempotent and touches only the exact pending user row.
    @discardableResult
    public func closePendingChatTurn(
        sessionID: String,
        userMessageID: Int64,
        terminal: ChatTurnTerminal
    ) throws -> Bool {
        guard userMessageID > 0 else { return false }
        return try transactionResult {
            let changed = try execBinding("""
            UPDATE chat_messages SET turn_state=?
            WHERE id=? AND session_id=? AND role='user' AND source_kind='local'
              AND turn_state='pending';
            """) { stmt in
                try bind(stmt, 1, terminal.rawValue)
                try bind(stmt, 2, userMessageID)
                try bind(stmt, 3, sessionID)
            }
            return changed == 1
        }
    }

    /// Close the rows no live request can ever finish.
    ///
    /// A `pending` row is created and terminalized by one handler of one process.
    /// If that process ends first — quit, crash, suspend — the row keeps saying
    /// "this request is still in flight" for the rest of the database's life.
    /// Ordinary retries always create their own row and cannot adopt this one.
    /// Every row written before this process started therefore belongs to a
    /// request that has already ended; the
    /// outcome is unknown, so it is not promoted (never `committed`) and not
    /// attributed to a cause it did not have (`failed`/`cancelled`/`detached`).
    ///
    /// Bounded to rows strictly older than `launchedAt`, so calling this from a
    /// launch path cannot touch a turn this process is serving. Idempotent.
    ///
    /// Boundary: the database is assumed to have one serving process. Two live
    /// processes sharing it would let the later launch abandon the earlier one's
    /// in-flight rows.
    @discardableResult
    public func closeStrandedPendingTurns(launchedAt: Date) throws -> Int {
        try transactionResult {
            try execBinding("""
            UPDATE chat_messages SET turn_state=?
            WHERE role='user' AND source_kind='local' AND turn_state='pending'
              AND CAST(created_at AS REAL) < CAST(? AS REAL);
            """) { stmt in
                try bind(stmt, 1, ChatTurnState.abandoned.rawValue)
                try bind(stmt, 2, Self.stamp(launchedAt))
            }
        }
    }

    private func insertChatMessage(
        sessionID: String, role: String, data: Data, digest: String,
        model: String?, createdAt: Date, state: String,
        sourceKind: ChatTurnSource = .local, sourceProvider: String? = nil,
        requestID: String? = nil
    ) throws -> Int64 {
        let objectID = try ensureObject(data)
        try execBinding("""
        INSERT INTO chat_messages(
            session_id, role, content, model, content_sha256, created_at,
            content_object_id, turn_state, source_kind, source_provider, request_id)
        VALUES(?,?,?,?,?,?,?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, role)
            try bind(stmt, 3, "")
            if let model { try bind(stmt, 4, model) } else { try bindNull(stmt, 4) }
            try bind(stmt, 5, digest)
            try bind(stmt, 6, Self.stamp(createdAt))
            try bind(stmt, 7, objectID)
            try bind(stmt, 8, state)
            try bind(stmt, 9, sourceKind.rawValue)
            try bind(stmt, 10, sourceProvider)
            try bind(stmt, 11, requestID)
        }
        let rowID = sqlite3_last_insert_rowid(handle)
        _ = try appendIndexEntryInTransaction(
            identity: "chat:\(sessionID)/\(rowID)", objectID: objectID)
        // Chat is information in the same space as files: one item registry,
        // one content-addressed payload, no second copy.
        try execBinding("""
        INSERT INTO information_items(
            item_id, kind, locator, source_version, source_payload_sha256, state, updated_at)
        VALUES(?,?,?,?,?,'AVAILABLE',?)
        ON CONFLICT(item_id) DO UPDATE SET
            source_version=excluded.source_version,
            source_payload_sha256=excluded.source_payload_sha256,
            state='AVAILABLE', updated_at=excluded.updated_at;
        """) { stmt in
            try bind(stmt, 1, "chat:\(sessionID)/\(rowID)")
            try bind(stmt, 2, "chat")
            try bind(stmt, 3, "session:\(sessionID)#\(rowID)")
            try bind(stmt, 4, Self.stamp(createdAt))
            try bind(stmt, 5, digest)
            try bind(stmt, 6, Self.stamp(createdAt))
        }
        return rowID
    }

    // MARK: - Turn digests（每轮问了什么、答出什么，供以后直接读）

    /// 一轮会话的精编结果。正文不在这里：问题与回答在 `is_objects` 里，
    /// 经 `chat_messages.content_object_id` 取回。
    public struct TurnDigestRecord: Equatable, Sendable {
        public let sessionID: String
        public let turnIndex: Int
        public let questionMessageID: Int64?
        public let answerMessageID: Int64?
        public let digest: String
        public let keywords: [String]
        public let model: String?
        /// `model`（模型档）或 `mechanical`（机械档）。旧行为 NULL。
        public let lane: String?
        /// 这一轮回答的来源路由：`local:<model>` 或 `cloud:<model>`。旧行为 NULL。
        public let sourceRoute: String?
        public let createdAt: String
    }

    /// 写一轮摘要，同时把关键字拆进 `keywords` / `turn_keywords`。
    ///
    /// 同一轮重复写是覆盖，不是新增：摘要是派生内容（模型再跑一次结果不同），
    /// 只留一行最新那次，才核得上 `chat_turn_ledger` 的轮号账。
    /// Persist source fingerprints for newly-written turn digests. This
    /// idempotent DDL is independent of numbered migrations so this PR remains
    /// migration-order independent from the concurrent MCP identity change.
    /// Legacy digest rows have no receipt and are treated as stale on replay.
    private func ensureTurnDigestSourceSchema() throws {
        try rawExec( """
        CREATE TABLE IF NOT EXISTS turn_digest_sources(
            session_id TEXT NOT NULL,
            turn_index INTEGER NOT NULL,
            question_sha256 TEXT NOT NULL,
            answer_sha256 TEXT NOT NULL,
            PRIMARY KEY(session_id, turn_index));
        """)
    }

    @discardableResult
    public func recordTurnDigest(
        sessionID: String, turnIndex: Int,
        questionMessageID: Int64? = nil, answerMessageID: Int64? = nil,
        digest: String, keywords: String, model: String? = nil,
        lane: String? = nil, sourceRoute: String? = nil,
        createdAt: Date = Date(),
        requestSpaceAssignment: Bool = false,
        expectedQuestionSHA256: String? = nil,
        expectedAnswerSHA256: String? = nil
    ) throws -> TurnDigestRecord {
        let text = digest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DatabaseError.sql("recordTurnDigest: digest is empty")
        }
        var seen = Set<String>()
        let terms = keywords.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let now = Self.stamp(createdAt)

        try ensureTurnDigestSourceSchema()

        // 建表放在事务外：DDL 回滚了却记着「已建好」，这个连接后面每次
        // 查房间表都会撞「no such table」。已在连接上建过时这一步是空的。
        if requestSpaceAssignment { try ensureRoomSchema() }

        let stored: TurnDigestRecord = try transactionResult {
            // Validate the exact source snapshot in the same write transaction as
            // the UPSERT. A correction either commits first and makes this stale,
            // or runs after this write and deletes the derived digest itself.
            try verifyTurnDigestSource(
                sessionID: sessionID, turnIndex: turnIndex,
                expectedQuestionSHA256: expectedQuestionSHA256,
                expectedAnswerSHA256: expectedAnswerSHA256)
            try execBinding("""
            INSERT INTO turn_digests(
                session_id, turn_index, question_message_id, answer_message_id,
                digest, keywords, model, lane, source_route, created_at)
            VALUES(?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(session_id, turn_index) DO UPDATE SET
                question_message_id=excluded.question_message_id,
                answer_message_id=excluded.answer_message_id,
                digest=excluded.digest, keywords=excluded.keywords,
                model=COALESCE(excluded.model, turn_digests.model),
                lane=COALESCE(excluded.lane, turn_digests.lane),
                source_route=COALESCE(excluded.source_route, turn_digests.source_route),
                created_at=excluded.created_at;
            """) { stmt in
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, Int64(turnIndex))
                try bind(stmt, 3, questionMessageID)
                try bind(stmt, 4, answerMessageID)
                try bind(stmt, 5, text)
                try bind(stmt, 6, terms.joined(separator: " "))
                try bind(stmt, 7, model)
                try bind(stmt, 8, lane)
                try bind(stmt, 9, sourceRoute)
                try bind(stmt, 10, now)
            }
            try storeKeywordTerms(
                terms, sessionID: sessionID, turnIndex: turnIndex, now: now)
            // Replace the source-version receipt atomically with the derived digest.
            // A legacy standalone write without fingerprints must not inherit an
            // older row's source proof.
            try execBinding("""
            DELETE FROM turn_digest_sources WHERE session_id=? AND turn_index=?;
            """) { stmt in
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, Int64(turnIndex))
            }
            if let expectedQuestionSHA256, let expectedAnswerSHA256 {
                try execBinding("""
                INSERT INTO turn_digest_sources(
                    session_id, turn_index, question_sha256, answer_sha256)
                VALUES(?,?,?,?);
                """) { stmt in
                    try bind(stmt, 1, sessionID)
                    try bind(stmt, 2, Int64(turnIndex))
                    try bind(stmt, 3, expectedQuestionSHA256)
                    try bind(stmt, 4, expectedAnswerSHA256)
                }
            }
            if requestSpaceAssignment {
                // 待判归属与摘要同生共死（#187）：摘要落了、归属没落是常态
                // （撞锁），但「摘要落了、连待办都没有」不该存在——那条路
                // 上没人会再来判这一轮。
                try markSpaceAssignmentPending(
                    sessionID: sessionID, turnIndex: turnIndex, now: createdAt)
            }
            // 返回落盘的那一行，而不是入参：覆盖写之后调用方看到的应当
            // 就是库里现在的内容。
            guard let stored = try turnDigest(sessionID: sessionID, turnIndex: turnIndex)
            else { throw DatabaseError.sql("recordTurnDigest: row missing after write") }
            return stored
        }
        // 轮摘要落库就是「有消息」这件事的节流点：动态交接跟着刷新一次，
        // 但自带时间闸（默认五分钟一版），不会一轮刷两遍。刷新失败不许影响
        // 摘要本身——那是派生物，派生失败是小事，丢一轮摘要是大事。
        if let scope = Self.clientScope(ofSession: sessionID) {
            // Local Agent sessions converge on owner; MCP sessions remain
            // isolated by the digest of their persisted bearer capability.
            _ = try? refreshRollingDigest(scope: scope)
        }
        return stored
    }

    /// Compare a captured digest job with the current message hashes owned by
    /// this turn. The missing-ledger case is retained for legacy/test callers
    /// that write standalone digests without a chat-turn ledger; all normal
    /// scheduled and backfill jobs originate from ledger rows.
    private func verifyTurnDigestSource(
        sessionID: String, turnIndex: Int,
        expectedQuestionSHA256: String?,
        expectedAnswerSHA256: String?
    ) throws {
        guard (expectedQuestionSHA256 == nil) == (expectedAnswerSHA256 == nil) else {
            throw DatabaseError.sql(
                "recordTurnDigest: both expected source hashes must be supplied")
        }
        let stmt = try prepare("""
        SELECT
            (SELECT COUNT(*) FROM chat_messages m
              WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                AND m.role='user'),
            (SELECT m.content_sha256 FROM chat_messages m
              WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                AND m.role='user' ORDER BY m.id DESC LIMIT 1),
            (SELECT COUNT(*) FROM chat_messages m
              WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                AND m.role='assistant'),
            (SELECT m.content_sha256 FROM chat_messages m
              WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                AND m.role='assistant' ORDER BY m.id DESC LIMIT 1),
            (SELECT COUNT(*) FROM chat_messages m
               JOIN is_objects o ON o.object_id=m.content_object_id
              WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                AND m.role='user'),
            (SELECT COUNT(*) FROM chat_messages m
               JOIN is_objects o ON o.object_id=m.content_object_id
              WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                AND m.role='assistant')
          FROM chat_turn_ledger l
         WHERE l.session_id=? AND l.turn_index=?
         LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        // A standalone legacy digest may not have a ledger owner. Preserve its
        // historical API behavior; every ledger-backed digest must provide both
        // fingerprints so a caller cannot bypass the source-version contract.
        guard try stepRowOrDone(stmt) else { return }
        guard let expectedQuestionSHA256, let expectedAnswerSHA256 else {
            throw DatabaseError.sql(
                "recordTurnDigest: ledger-backed digest requires both expected source hashes")
        }

        let userRows = Int(sqlite3_column_int64(stmt, 0))
        let currentQuestion = sqlite3_column_text(stmt, 1)
            .map { String(cString: $0) }
        let assistantRows = Int(sqlite3_column_int64(stmt, 2))
        let currentAnswer = sqlite3_column_text(stmt, 3)
            .map { String(cString: $0) }
        let readableQuestionRows = Int(sqlite3_column_int64(stmt, 4))
        let readableAnswerRows = Int(sqlite3_column_int64(stmt, 5))

        // Exactly one row per role is required. A missing counterpart must not
        // be normalized to SHA256(empty): an actually empty message is valid
        // only when its row and content-addressed object both exist.
        guard userRows == 1, assistantRows == 1,
              readableQuestionRows == 1, readableAnswerRows == 1,
              let currentQuestion, let currentAnswer else {
            throw DatabaseError.sql(
                "recordTurnDigest: ledger-backed digest requires exactly one readable user and assistant source")
        }
        guard currentQuestion == expectedQuestionSHA256,
              currentAnswer == expectedAnswerSHA256 else {
            throw DatabaseError.staleTurnDigestSource(
                sessionID: sessionID, turnIndex: turnIndex)
        }
    }

    /// 一轮的词表落盘：先摘旧关联，再把词写进 `keywords` 并挂回这一轮。
    /// 词只增不删——`turn_keywords` 对 `keywords` 是级联删除，删词会牵连别的轮。
    private func storeKeywordTerms(
        _ terms: [String], sessionID: String, turnIndex: Int, now: String
    ) throws {
        // 这一轮的词换过一次，旧关联就得摘掉：否则改过摘要之后，旧词
        // 还能把这一轮捞出来。
        try execBinding("""
        DELETE FROM turn_keywords WHERE session_id=? AND turn_index=?;
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, Int64(turnIndex))
        }
        for term in terms {
            try execBinding("""
            INSERT INTO keywords(term, created_at) VALUES(?,?)
            ON CONFLICT(term) DO NOTHING;
            """) { stmt in
                try bind(stmt, 1, term)
                try bind(stmt, 2, now)
            }
            let keywordID: Int64 = try {
                let stmt = try prepare("SELECT keyword_id FROM keywords WHERE term=?;")
                defer { sqlite3_finalize(stmt) }
                try bind(stmt, 1, term)
                guard try stepRowOrDone(stmt) else {
                    throw DatabaseError.sql("recordTurnDigest: keyword row missing")
                }
                return sqlite3_column_int64(stmt, 0)
            }()
            try execBinding("""
            INSERT OR IGNORE INTO turn_keywords(session_id, turn_index, keyword_id)
            VALUES(?,?,?);
            """) { stmt in
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, Int64(turnIndex))
                try bind(stmt, 3, keywordID)
            }
        }
    }

    /// 只换关键词：`digest`、`model`、`created_at` 一个字都不动。
    ///
    /// 为什么不复用 `recordTurnDigest`：那是整轮覆盖，换一套词会把「谁写的、
    /// 什么时候写的」一并抹掉，事后分不清这批词是原摘要作者给的还是后来补的。
    @discardableResult
    public func replaceTurnKeywords(
        sessionID: String, turnIndex: Int, keywords: [String],
        createdAt: Date = Date()
    ) throws -> [String] {
        var seen = Set<String>()
        let terms = keywords
            .flatMap { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !terms.isEmpty else {
            throw DatabaseError.sql("replaceTurnKeywords: keywords is empty")
        }
        let now = Self.stamp(createdAt)
        return try transactionResult {
            guard try turnDigest(sessionID: sessionID, turnIndex: turnIndex) != nil else {
                throw DatabaseError.sql("replaceTurnKeywords: no digest row for this turn")
            }
            try execBinding("""
            UPDATE turn_digests SET keywords=? WHERE session_id=? AND turn_index=?;
            """) { stmt in
                try bind(stmt, 1, terms.joined(separator: " "))
                try bind(stmt, 2, sessionID)
                try bind(stmt, 3, Int64(turnIndex))
            }
            try storeKeywordTerms(
                terms, sessionID: sessionID, turnIndex: turnIndex, now: now)
            return terms
        }
    }

    /// 已经有摘要、但词不够的轮次，只带「修词」要的东西。
    public struct DigestTurnText: Sendable {
        public let sessionID: String
        public let turnIndex: Int
        public let keywords: [String]
        public let question: String
        public let answer: String
    }

    /// 词不够的轮次。`minimum` 是「一行少于几个词就该补」，与缺摘要那本账
    /// 无关——缺摘要由 `undigestedTurns()` 报。
    ///
    /// 计数版给状态刷新用。判定必须与挑选版同一口径（含「正文为空就不算」），
    /// 否则按钮上的数字会和真正要修的轮数对不上——所以直接复用挑选版。
    public func turnsWithThinKeywordsCount(minimum: Int = 5) throws -> Int {
        try turnsWithThinKeywords(minimum: minimum).count
    }

    public func turnsWithThinKeywords(
        minimum: Int = 5, limit: Int? = nil
    ) throws -> [DigestTurnText] {
        let stmt = try prepare("""
        SELECT d.session_id, d.turn_index, d.keywords,
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.id=d.question_message_id),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.id=d.answer_message_id)
          FROM turn_digests d
         ORDER BY d.session_id, d.turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        var rows: [DigestTurnText] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            let words = (text(2) ?? "").split(whereSeparator: { $0.isWhitespace })
            guard words.count < minimum else { continue }
            let question = text(3) ?? ""
            let answer = text(4) ?? ""
            if question.isEmpty && answer.isEmpty { continue }
            rows.append(DigestTurnText(
                sessionID: text(0) ?? "",
                turnIndex: Int(sqlite3_column_int64(stmt, 1)),
                keywords: words.map(String.init),
                question: question, answer: answer))
            if let limit, rows.count >= limit { break }
        }
        return rows
    }

    private static let turnDigestColumns = """
    session_id, turn_index, question_message_id, answer_message_id,
    digest, keywords, model, lane, source_route, created_at
    """

    private func turnDigestRecord(_ stmt: OpaquePointer) -> TurnDigestRecord {
        TurnDigestRecord(
            sessionID: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
            turnIndex: Int(sqlite3_column_int64(stmt, 1)),
            questionMessageID: sqlite3_column_type(stmt, 2) == SQLITE_NULL
                ? nil : sqlite3_column_int64(stmt, 2),
            answerMessageID: sqlite3_column_type(stmt, 3) == SQLITE_NULL
                ? nil : sqlite3_column_int64(stmt, 3),
            digest: sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "",
            keywords: (sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "")
                .split(whereSeparator: { $0.isWhitespace }).map(String.init),
            model: sqlite3_column_text(stmt, 6).map { String(cString: $0) },
            lane: sqlite3_column_text(stmt, 7).map { String(cString: $0) },
            sourceRoute: sqlite3_column_text(stmt, 8).map { String(cString: $0) },
            createdAt: sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? "")
    }

    public func turnDigest(sessionID: String, turnIndex: Int) throws -> TurnDigestRecord? {
        let stmt = try prepare("""
        SELECT \(Self.turnDigestColumns) FROM turn_digests
         WHERE session_id=? AND turn_index=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        guard try stepRowOrDone(stmt) else { return nil }
        return turnDigestRecord(stmt)
    }

    /// 这一轮回答的来源路由。会话行的 `model` 存的就是请求选中的模型 id：
    /// 云路由形如 `cloud:<provider-model>`，本地模型补 `local:` 前缀。
    /// 旧库或外部轮次可能没记模型，返回 nil 由调用方兜底。
    public func turnDigestSourceRoute(
        sessionID: String, turnIndex: Int
    ) throws -> String? {
        guard try tableExists("chat_turn_ledger"),
              try tableExists("chat_messages") else { return nil }
        let stmt = try prepare("""
        SELECT m.model FROM chat_turn_ledger l
          JOIN chat_messages m
            ON m.session_id=l.session_id AND m.request_id=l.request_id
         WHERE l.session_id=? AND l.turn_index=?
           AND m.role='assistant' AND m.model IS NOT NULL AND m.model<>''
         ORDER BY m.id DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        guard try stepRowOrDone(stmt),
              let raw = sqlite3_column_text(stmt, 0) else { return nil }
        let model = String(cString: raw)
        return model.hasPrefix("cloud:") ? model : "local:\(model)"
    }

    /// Folded reuse turns (identical Q+A source) are one round seen twice; the
    /// coverage gate still requires a digest ROW per constituent ledger turn.
    /// A reuse turn has no generation leg to warm-digest, so its row is copied
    /// zero-call from the earliest digested turn with the same source. This
    /// heals BOTH orderings: a reuse turn that settled after its source digest
    /// (backward, called at settle) and one that settled before the source
    /// digest landed (forward, called when that digest is written). Idempotent:
    /// turns that already have a digest are skipped, and a different-answer
    /// repeat has a different source key so it is never folded. Returns the
    /// turns filled so the caller can feed render-side memory. Room assignment
    /// stays with the primary write path; a copied row exists for coverage and
    /// its search indexing heals via the normal pending/backfill route.
    @discardableResult
    public func fillFoldedReuseDigests(sessionID: String) throws -> [(turn: Int, digest: String)] {
        let hashes = try turnSourceHashes(sessionID: sessionID)
        var source: [String: TurnDigestRecord] = [:]   // question|answer -> earliest digested
        var filled: [(turn: Int, digest: String)] = []
        for (idx, hash) in hashes.sorted(by: { $0.key < $1.key }) {
            let key = hash.question + "|" + hash.answer
            if let existing = try turnDigest(sessionID: sessionID, turnIndex: idx) {
                if source[key] == nil { source[key] = existing }
                continue
            }
            guard let src = source[key] else { continue }
            _ = try recordTurnDigest(
                sessionID: sessionID, turnIndex: idx,
                digest: src.digest, keywords: src.keywords.joined(separator: " "),
                model: src.model, lane: src.lane, sourceRoute: src.sourceRoute,
                expectedQuestionSHA256: hash.question,
                expectedAnswerSHA256: hash.answer)
            filled.append((idx, src.digest))
        }
        return filled
    }

    /// 最近的摘要，`sessionID` 传 nil 就是全库。按写入时间倒序：检索要的是
    /// 最新那一版说法。
    public func recentTurnDigests(sessionID: String? = nil, limit: Int = 50)
        throws -> [TurnDigestRecord]
    {
        let stmt = try prepare("""
        SELECT \(Self.turnDigestColumns) FROM turn_digests
         WHERE (? IS NULL OR session_id = ?)
         ORDER BY created_at DESC, session_id DESC, turn_index DESC
         LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, sessionID)
        try bind(stmt, 3, Int64(limit))
        var rows: [TurnDigestRecord] = []
        while try stepRowOrDone(stmt) { rows.append(turnDigestRecord(stmt)) }
        return rows
    }

    /// 轮号有、摘要没有的轮次。和菜单栏的轮号缺口是同一份账：一处漏写，
    /// 另一处就能看见。
    /// 补一轮摘要要的全部东西：轮号、那两行消息的 id、问题与回答的正文。
    public struct UndigestedTurn: Sendable {
        public let sessionID: String
        public let turnIndex: Int
        public let questionMessageID: Int64?
        public let answerMessageID: Int64?
        public let question: String
        public let answer: String
    }

    /// A repairable digest source has exactly one user row and one assistant
    /// row for this ledger request, with both content-addressed objects readable.
    /// Incomplete or ambiguous source pairs remain ledger evidence, not digest jobs.
    static let digestableTurnSourcePredicate = """
        (SELECT COUNT(*) FROM chat_messages m
          WHERE m.session_id=l.session_id AND m.request_id=l.request_id
            AND m.role='user') = 1
        AND EXISTS (
            SELECT 1 FROM chat_messages m
              JOIN is_objects o ON o.object_id=m.content_object_id
             WHERE m.session_id=l.session_id AND m.request_id=l.request_id
               AND m.role='user')
        AND (SELECT COUNT(*) FROM chat_messages m
          WHERE m.session_id=l.session_id AND m.request_id=l.request_id
            AND m.role='assistant') = 1
        AND EXISTS (
            SELECT 1 FROM chat_messages m
              JOIN is_objects o ON o.object_id=m.content_object_id
             WHERE m.session_id=l.session_id AND m.request_id=l.request_id
               AND m.role='assistant')
        """

    /// 全库口径的「来源完整、轮号有、摘要没有」。补摘要按这个跑。
    /// `carrierReport().turnsWithoutDigest` 是否归零。
    public func undigestedTurns() throws -> [UndigestedTurn] {
        let stmt = try prepare("""
        SELECT l.session_id, l.turn_index,
               (SELECT m.id FROM chat_messages m
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='user' LIMIT 1),
               (SELECT m.id FROM chat_messages m
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='assistant' LIMIT 1),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='user' LIMIT 1),
               (SELECT CAST(o.content AS TEXT) FROM chat_messages m
                  JOIN is_objects o ON o.object_id=m.content_object_id
                 WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                   AND m.role='assistant' LIMIT 1)
          FROM chat_turn_ledger l
         WHERE \(Self.digestableTurnSourcePredicate)
           AND NOT EXISTS (SELECT 1 FROM turn_digests d
                            WHERE d.session_id=l.session_id
                              AND d.turn_index=l.turn_index)
         ORDER BY l.session_id, l.turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        var rows: [UndigestedTurn] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            // Empty text is a valid source value. Completeness is determined
            // by the paired rows and readable objects in the SQL predicate above.
            let question = text(4) ?? ""
            let answer = text(5) ?? ""
            rows.append(UndigestedTurn(
                sessionID: text(0) ?? "",
                turnIndex: Int(sqlite3_column_int64(stmt, 1)),
                questionMessageID: sqlite3_column_type(stmt, 2) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 2),
                answerMessageID: sqlite3_column_type(stmt, 3) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 3),
                question: question, answer: answer))
        }
        return rows
    }

    public func turnsWithoutDigest(sessionID: String) throws -> [Int] {
        let stmt = try prepare("""
        SELECT l.turn_index FROM chat_turn_ledger l
         WHERE l.session_id=?
           AND \(Self.digestableTurnSourcePredicate)
           AND NOT EXISTS (SELECT 1 FROM turn_digests d
                            WHERE d.session_id=l.session_id
                              AND d.turn_index=l.turn_index)
         ORDER BY l.turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        var rows: [Int] = []
        while try stepRowOrDone(stmt) { rows.append(Int(sqlite3_column_int64(stmt, 0))) }
        return rows
    }

    /// 身份锚定门的问句哈希账：轮号 → 问题正文 SHA-256。正文取 settle 时
    /// 落库的同一份 canonical 文本（chat_messages ⋈ is_objects，用户行唯一
    /// 且对象可读——与补摘要同一判据），哈希与 TurnDigestScheduler 的
    /// sourceSHA256 同口径。来源不完整的轮不出现在账上：锚不到就不替换，
    /// fail-closed。渲染门用它把 ledger 轮锚到真实用户消息，客户端噪声
    /// 注入不再按位置虚增轮数（2026-11-23 复核：21 轮零放行的根因）。
    /// Per-turn question AND answer content hashes for the substitution gate's
    /// identity anchoring. The answer hash lets the gate fold consecutive
    /// ledger turns that are provably the SAME round (identical question and
    /// answer — an ES zero-call reuse of a retried question, `IS_REUSE
    /// model_calls=0`) into one effective anchor, because the client may show
    /// that question only once while the ledger records both rounds. A repeat
    /// with a DIFFERENT answer is not foldable and stays a distinct turn.
    public struct TurnSourceHashes: Equatable, Sendable {
        public let question: String
        public let answer: String
        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    public func turnSourceHashes(sessionID: String) throws -> [Int: TurnSourceHashes] {
        let stmt = try prepare("""
        SELECT l.turn_index, CAST(qo.content AS TEXT), CAST(ao.content AS TEXT)
          FROM chat_turn_ledger l
          JOIN chat_messages qm
            ON qm.session_id=l.session_id AND qm.request_id=l.request_id
           AND qm.role='user'
          JOIN is_objects qo ON qo.object_id=qm.content_object_id
          JOIN chat_messages am
            ON am.session_id=l.session_id AND am.request_id=l.request_id
           AND am.role='assistant'
          JOIN is_objects ao ON ao.object_id=am.content_object_id
         WHERE l.session_id=?
           AND \(Self.digestableTurnSourcePredicate)
         ORDER BY l.turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        var hashes: [Int: TurnSourceHashes] = [:]
        while try stepRowOrDone(stmt) {
            let turnIndex = Int(sqlite3_column_int64(stmt, 0))
            let question = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let answer = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            hashes[turnIndex] = TurnSourceHashes(
                question: TurnDigestText.sourceSHA256(question),
                answer: TurnDigestText.sourceSHA256(answer))
        }
        return hashes
    }

    /// 「缺什么」的五个数。它是**动作的入口**，不是报表：每个数都对应一次补录，
    /// 补完归零；没有对应动作的数（对象数、未寻址、损坏数）不放这里——那些要
    /// 看就去问代理，摆在按钮旁边只会让人以为按钮干完了这件事。
    public struct TurnGapCounts: Equatable, Sendable {
        /// 采集桥导进来了，但一行轮次账都没有的会话数。
        public let ledgerSessions: Int
        /// 来源完整（问题与回答均唯一且对象可读）、账上有而摘要没有的轮数。
        public let digests: Int
        /// 有摘要、词不够的轮数。
        public let keywords: Int
        /// 账上有、来源时间为空的轮数。
        public let times: Int
        /// 有摘要、但没有任何房间归属的轮数。归属完整性是独立缺口：增量
        /// `assignTurnSpace` 撞锁失败时摘要已经落库，四项都看不到这次失败
        /// （#188）。口径排除「既无摘要也无归属」的轮次——那种轮次该由
        /// `digests` 说话。
        public let rooms: Int

        public var total: Int { ledgerSessions + digests + keywords + times + rooms }
    }

    func scalarCount(_ sql: String) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    public func turnGapCounts() throws -> TurnGapCounts {
        var ledgerSessions = 0
        var digests = 0
        var times = 0
        if try tableExists("chat_turn_ledger") {
            ledgerSessions = try scalarCount("""
            SELECT COUNT(DISTINCT session_id) FROM chat_messages
             WHERE request_id IS NOT NULL
               AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger);
            """)
            digests = try scalarCount("""
            SELECT COUNT(*) FROM chat_turn_ledger l
             WHERE \(Self.digestableTurnSourcePredicate)
               AND NOT EXISTS (SELECT 1 FROM turn_digests d
                                WHERE d.session_id=l.session_id
                                  AND d.turn_index=l.turn_index);
            """)
            if try columnExists("chat_turn_ledger", "source_time") {
                times = try scalarCount(
                    "SELECT COUNT(*) FROM chat_turn_ledger WHERE source_time IS NULL;")
            } else {
                // 列都没有，就是一条都没回填过——这本身就是要补的那一格。
                times = try scalarCount("SELECT COUNT(*) FROM chat_turn_ledger;")
            }
        }
        return TurnGapCounts(
            ledgerSessions: ledgerSessions, digests: digests,
            keywords: try turnsWithThinKeywordsCount(), times: times,
            rooms: try digestsWithoutRoomCount())
    }

    /// 有摘要、但没有任何房间归属的轮数（#188 的第五项）。
    /// 口径与人工对照 SQL 一致：既无摘要也无归属的轮次不进这个数。
    private func digestsWithoutRoomCount() throws -> Int {
        // 摘要表都没有，就没有「有摘要无归属」这回事。
        guard try tableExists("turn_digests") else { return 0 }
        // 房间表是惰性建的。它还没建出来，不等于「归属都齐了」——恰恰相反：
        // 每条带摘要的轮都还没有归属。这里数全部摘要轮，不数 0（#188）。
        guard try tableExists("space_turns") else {
            return try scalarCount("SELECT COUNT(*) FROM turn_digests;")
        }
        return try scalarCount("""
        SELECT COUNT(*) FROM turn_digests d
         WHERE NOT EXISTS (SELECT 1 FROM space_turns st
                            WHERE st.session_id=d.session_id
                              AND st.turn_index=d.turn_index);
        """)
    }

    // MARK: - External-provider turns (recorded → verified → retrievable)

    /// Record an upstream-API turn's question as soon as its request arrives.
    /// The row keeps its provenance but stays `recorded`: an in-flight external
    /// request is information the space holds, not history another request may
    /// retrieve. Repeating the same request id returns the row already written
    /// instead of appending a duplicate.
    @discardableResult
    public func recordExternalTurn(
        sessionID: String, provider: String, requestID: String,
        userText: String, model: String?, createdAt: Date,
        eligibility: ChatTurnEligibility = .ordinary
    ) throws -> Int64 {
        let data = Data(userText.utf8)
        let digest = NativeSHA256.hexDigest(data)
        return try transactionResult {
            try validateExternalTurnMetadata(
                sessionID: sessionID, requestID: requestID,
                provider: provider, model: model, eligibility: eligibility)
            if let existing = try externalRowEntry(
                sessionID: sessionID, requestID: requestID, role: "user")
            {
                // 同一个幂等键只说明「这是同一次提交」，不说明「这一格可以换成
                // 任何正文」。digest 相同才是重试；不同就是另一份内容——拒绝，
                // 不能静默把后来的文本丢掉。
                guard existing.digest == digest else {
                    throw ExternalTurnConflict(
                        sessionID: sessionID, requestID: requestID, role: "user",
                        messageID: existing.id, storedDigest: existing.digest,
                        incomingDigest: digest)
                }
                return existing.id
            }
            return try insertChatMessage(
                sessionID: sessionID, role: "user", data: data, digest: digest,
                model: model, createdAt: createdAt,
                state: Self.externalState(for: eligibility),
                sourceKind: .external, sourceProvider: provider, requestID: requestID)
        }
    }

    /// Record the upstream reply under the same provenance. Still `recorded`:
    /// a complete-looking body is evidence about the turn, not yet standing.
    @discardableResult
    public func recordExternalResponse(
        sessionID: String, provider: String, requestID: String,
        assistantText: String, model: String?, createdAt: Date,
        eligibility: ChatTurnEligibility = .ordinary
    ) throws -> Int64 {
        let data = Data(assistantText.utf8)
        let digest = NativeSHA256.hexDigest(data)
        return try transactionResult {
            try validateExternalTurnMetadata(
                sessionID: sessionID, requestID: requestID,
                provider: provider, model: model, eligibility: eligibility)
            if let existing = try externalRowEntry(
                sessionID: sessionID, requestID: requestID, role: "assistant")
            {
                guard existing.digest == digest else {
                    throw ExternalTurnConflict(
                        sessionID: sessionID, requestID: requestID, role: "assistant",
                        messageID: existing.id, storedDigest: existing.digest,
                        incomingDigest: digest)
                }
                return existing.id
            }
            return try insertChatMessage(
                sessionID: sessionID, role: "assistant", data: data, digest: digest,
                model: model, createdAt: createdAt,
                state: Self.externalState(for: eligibility),
                sourceKind: .external, sourceProvider: provider, requestID: requestID)
        }
    }

    /// A client that declares its call an internal operation keeps that status
    /// across the external path too: the turn is recorded for audit and no
    /// later verification can promote it.
    private static func externalState(for eligibility: ChatTurnEligibility) -> String {
        eligibility == .internalOperation
            ? eligibility.rawValue : ChatTurnState.recorded.rawValue
    }

    /// Promote one external turn from `recorded` to `committed`. Verification is
    /// keyed by (session, request id) and requires both sides of that request to
    /// be present, so an answer never becomes memory without the question it
    /// answers (nor the reverse). Rows of every other request are untouched.
    /// Returns the number of rows promoted; 0 means the turn is incomplete or
    /// already verified.
    @discardableResult
    public func verifyExternalTurn(
        sessionID: String, requestID: String, verifiedAt: Date
    ) throws -> Int {
        try transactionResult {
            let userRows = try externalRowEntries(
                sessionID: sessionID, requestID: requestID, role: "user")
            let assistantRows = try externalRowEntries(
                sessionID: sessionID, requestID: requestID, role: "assistant")
            guard !userRows.isEmpty, !assistantRows.isEmpty else { return 0 }

            // The write set must be exactly the set that was inspected. A
            // legacy database may contain duplicate rows for one idempotency
            // key; looking at only the newest row and promoting every recorded
            // row would bless unverified history. Fail closed until that
            // historical ambiguity is explicitly repaired.
            guard userRows.count == 1 else {
                throw ExternalTurnAmbiguousRows(
                    sessionID: sessionID, requestID: requestID,
                    role: "user", rowCount: userRows.count)
            }
            guard assistantRows.count == 1 else {
                throw ExternalTurnAmbiguousRows(
                    sessionID: sessionID, requestID: requestID,
                    role: "assistant", rowCount: assistantRows.count)
            }
            let user = userRows[0]
            let assistant = assistantRows[0]

            // A complete pair is not sufficient by itself: both rows must
            // still be ordinary external records. Internal bookkeeping and
            // terminal/unknown states never grant retrieval standing.
            let promotableStates = [
                ChatTurnState.recorded.rawValue,
                ChatTurnState.committed.rawValue,
            ]
            guard promotableStates.contains(user.turnState),
                  promotableStates.contains(assistant.turnState) else {
                return 0
            }

            // Legacy rows may predate provenance-bound retry validation. Do
            // not promote a mixed-provider/model pair merely because its
            // session/request identifiers happen to match.
            guard let userProvider = user.provider,
                  !userProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  userProvider == assistant.provider,
                  user.model == assistant.model else {
                throw ExternalTurnProvenanceConflict(
                    sessionID: sessionID, requestID: requestID, role: "assistant",
                    messageID: assistant.id,
                    storedProvider: user.provider,
                    incomingProvider: assistant.provider ?? "<missing>",
                    storedModel: user.model,
                    incomingModel: assistant.model,
                    storedEligibility: ChatTurnEligibility.ordinary.rawValue,
                    incomingEligibility: ChatTurnEligibility.ordinary.rawValue)
            }

            // Update precisely the two ids whose provenance was checked.
            // The explicit id set is deliberate defense in depth if the query
            // or schema ever changes to admit additional rows.
            let promoted = try execBinding("""
            UPDATE chat_messages SET turn_state='committed', verified_at=?
            WHERE session_id=? AND request_id=? AND source_kind='external'
              AND turn_state='recorded' AND id IN (?,?);
            """) { stmt in
                try bind(stmt, 1, Self.stamp(verifiedAt))
                try bind(stmt, 2, sessionID)
                try bind(stmt, 3, requestID)
                try bind(stmt, 4, user.id)
                try bind(stmt, 5, assistant.id)
            }
            guard promoted <= 2 else {
                throw DatabaseError.sql(
                    "verifyExternalTurn: updated \(promoted) rows after validating exactly two")
            }
            return promoted
        }
    }

    /// 同一 (session, request, role) 上已经记过一行时，把它连同正文 digest
    /// 一起取回：只有 digest 才能回答「这是同一次提交的重试，还是另一份内容」。
    private func externalRowEntries(
        sessionID: String, requestID: String, role: String
    ) throws -> [(id: Int64, digest: String, provider: String?, model: String?, turnState: String)] {
        let stmt = try prepare("""
        SELECT id, content_sha256, model, source_provider, turn_state FROM chat_messages
        WHERE session_id=? AND request_id=? AND source_kind='external' AND role=?
        ORDER BY id ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, requestID)
        try bind(stmt, 3, role)
        var rows: [(id: Int64, digest: String, provider: String?, model: String?, turnState: String)] = []
        while try stepRowOrDone(stmt) {
            let digest = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let model = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                ? nil : sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let provider = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                ? nil : sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let turnState = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            rows.append((
                sqlite3_column_int64(stmt, 0), digest, provider, model, turnState))
        }
        return rows
    }

    /// Idempotent write paths require a unique historical row for this key.
    /// Duplicate legacy rows are not silently reduced to the newest one.
    private func externalRowEntry(
        sessionID: String, requestID: String, role: String
    ) throws -> (id: Int64, digest: String, provider: String?, model: String?, turnState: String)? {
        let rows = try externalRowEntries(
            sessionID: sessionID, requestID: requestID, role: role)
        guard rows.count <= 1 else {
            throw ExternalTurnAmbiguousRows(
                sessionID: sessionID, requestID: requestID,
                role: role, rowCount: rows.count)
        }
        return rows.first
    }

    /// Validate both rows of the external round, if either has already arrived.
    /// This prevents a request from pairing a question from provider A/model A
    /// with an answer from provider B/model B, regardless of arrival order.
    private func validateExternalTurnMetadata(
        sessionID: String, requestID: String, provider: String,
        model: String?, eligibility: ChatTurnEligibility
    ) throws {
        guard !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DatabaseError.sql("external turn provider must be non-empty")
        }
        for role in ["user", "assistant"] {
            if let existing = try externalRowEntry(
                sessionID: sessionID, requestID: requestID, role: role) {
                try validateExternalRetryMetadata(
                    existing: existing, sessionID: sessionID, requestID: requestID,
                    role: role, provider: provider, model: model, eligibility: eligibility)
            }
        }
    }

    /// An idempotent retry must preserve both the payload and its declared
    /// provenance. Provider/model are audit fields, and eligibility decides
    /// whether the external row may ever become retrievable; none can silently
    /// change while reusing the same (session, request, role) identity.
    private func validateExternalRetryMetadata(
        existing: (id: Int64, digest: String, provider: String?, model: String?, turnState: String),
        sessionID: String, requestID: String, role: String,
        provider: String, model: String?, eligibility: ChatTurnEligibility
    ) throws {
        let storedEligibility = existing.turnState == ChatTurnState.internalOperation.rawValue
            ? ChatTurnEligibility.internalOperation.rawValue : ChatTurnEligibility.ordinary.rawValue
        let incomingEligibility = eligibility.rawValue == ChatTurnEligibility.internalOperation.rawValue
            ? ChatTurnEligibility.internalOperation.rawValue : ChatTurnEligibility.ordinary.rawValue
        guard existing.provider == provider,
              existing.model == model,
              storedEligibility == incomingEligibility else {
            throw ExternalTurnProvenanceConflict(
                sessionID: sessionID, requestID: requestID, role: role,
                messageID: existing.id,
                storedProvider: existing.provider, incomingProvider: provider,
                storedModel: existing.model, incomingModel: model,
                storedEligibility: storedEligibility, incomingEligibility: incomingEligibility)
        }
    }
    private func externalRowID(
        sessionID: String, requestID: String, role: String
    ) throws -> Int64? {
        try externalRowEntry(sessionID: sessionID, requestID: requestID, role: role)?.id
    }

    /// Same idempotency identity, but the producer/model/standing metadata changed.
    /// This is distinct from a content conflict: provenance cannot be rewritten by retry.
    public struct ExternalTurnProvenanceConflict: Error, Equatable, CustomStringConvertible {
        public let sessionID: String
        public let requestID: String
        public let role: String
        public let messageID: Int64
        public let storedProvider: String?
        public let incomingProvider: String
        public let storedModel: String?
        public let incomingModel: String?
        public let storedEligibility: String
        public let incomingEligibility: String

        public var description: String {
            "provenance-conflict: \(sessionID)/\(requestID) \(role) " +
                "already recorded with provider=\(storedProvider ?? "unknown"), " +
                "model=\(storedModel ?? "unknown"), eligibility=\(storedEligibility); " +
                "retry carries provider=\(incomingProvider), " +
                "model=\(incomingModel ?? "unknown"), eligibility=\(incomingEligibility). " +
                "Use a new request id for a different upstream execution."
        }
    }
    /// Historical data can contain more than one external row for a single
    /// (session, request, role) identity. The verifier refuses to guess which
    /// row owns the turn or to promote rows it did not individually inspect.
    public struct ExternalTurnAmbiguousRows: Error, Equatable, CustomStringConvertible {
        public let sessionID: String
        public let requestID: String
        public let role: String
        public let rowCount: Int

        public var description: String {
            "ambiguous-external-turn: \(sessionID)/\(requestID) has \(rowCount) \(role) rows; "
                + "repair the duplicate history before verification"
        }
    }

    /// 同一幂等键上提交了不同正文。
    ///
    /// 幂等键标识的是「这一次提交」，不是「这一格可以随便改」。已有行按 digest
    /// 比对：相同才算重试；不同就是另一份内容——拒绝，既不覆盖旧行，也不假装
    /// 后来的文本记进过库。正确内容只能走 `correctChatMessage`，那条路会留下
    /// 更正记录，原行与原对象都还在。
    public struct ExternalTurnConflict: Error, Equatable, CustomStringConvertible {
        public let sessionID: String
        public let requestID: String
        public let role: String
        public let messageID: Int64
        public let storedDigest: String
        public let incomingDigest: String

        public var description: String {
            "content-conflict: \(sessionID)/\(requestID) \(role) already recorded as "
                + "\(storedDigest.prefix(12)) (message \(messageID)); this retry carries "
                + "\(incomingDigest.prefix(12)). Refusing to overwrite the stored text "
                + "or to report the later text as recorded. Amend it explicitly with "
                + "simigo_chat_correct (reason + actor) if the stored text is wrong."
        }
    }

    /// 一条更正记录：哪一行、从什么正文改成了什么正文、为什么、谁改的。
    public struct ChatCorrectionRecord: Equatable, Sendable {
        public let correctionID: String
        public let messageID: Int64
        public let previousSHA256: String
        public let correctedSHA256: String
        public let reason: String
        public let actor: String
        public let correctedAt: String
        /// 这次更正让哪一轮的摘要失效（该轮摘要已删，等重算）；没有轮账映射时为 nil。
        public let invalidatedTurnIndex: Int?
    }

    public enum ChatCorrectionError: Error, Equatable, CustomStringConvertible {
        case unknownMessage(sessionID: String, requestID: String, role: String)
        case emptyReason
        case emptyActor

        public var description: String {
            switch self {
            case .unknownMessage(let sessionID, let requestID, let role):
                return "no \(role) line recorded for \(sessionID)/\(requestID)"
            case .emptyReason:
                return "a correction needs a reason: without one it is an overwrite"
            case .emptyActor:
                return "a correction needs an actor: somebody has to be accountable"
            }
        }
    }

    /// 显式更正已记录的一行正文。
    ///
    /// 拒绝冲突解决了「不许静默覆盖」，但错误内容需要一个合法入口，否则它只能
    /// 被掩盖、不能被纠正。这条路做三件事，且都不抹历史：
    ///
    /// 1. 原行不删；`is_objects` 不可变，原对象仍在库里，并记进更正行的
    ///    `previous_object_id` / `previous_sha256`（原文可原样读回）。
    /// 2. 更正事件本身留痕：新 digest、原因、执行者、时间。
    /// 3. 行内指针移到新对象，于是读取与检索看到的是更正后的正文。
    ///
    /// 事件身份 = sha256(message_id | 新 digest | 原因)：同一次更正重试幂等；
    /// 正文或原因不同就是另一次更正，不会伪装成同一条。
    @discardableResult
    public func correctChatMessage(
        sessionID: String, requestID: String, role: String,
        correctedText: String, reason: String, actor: String, at: Date = Date()
    ) throws -> ChatCorrectionRecord {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedActor = actor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw ChatCorrectionError.emptyReason }
        guard !trimmedActor.isEmpty else { throw ChatCorrectionError.emptyActor }
        let data = Data(correctedText.utf8)
        let digest = NativeSHA256.hexDigest(data)
        try ensureTurnDigestSourceSchema()
        return try transactionResult {
            let stmt = try prepare("""
            SELECT id, content_sha256, content_object_id FROM chat_messages
            WHERE session_id=? AND request_id=? AND role=?
            ORDER BY id DESC LIMIT 1;
            """)
            var found: (id: Int64, digest: String, objectID: String?)?
            do {
                defer { sqlite3_finalize(stmt) }
                try bind(stmt, 1, sessionID)
                try bind(stmt, 2, requestID)
                try bind(stmt, 3, role)
                if try stepRowOrDone(stmt) {
                    found = (
                        sqlite3_column_int64(stmt, 0),
                        sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
                        sqlite3_column_text(stmt, 2).map { String(cString: $0) })
                }
            }
            guard let row = found else {
                throw ChatCorrectionError.unknownMessage(
                    sessionID: sessionID, requestID: requestID, role: role)
            }
            let correctionID = NativeSHA256.hexDigest(
                Data("\(row.id)|\(digest)|\(trimmedReason)".utf8))
            let stamp = Self.stamp(at)
            if let existing = try correctionRecord(
                correctionID, sessionID: sessionID, requestID: requestID, role: role)
            {
                // Replay the persisted event, not a new receipt assembled from
                // the already-corrected message row or this retry's actor/time.
                // Derived digest invalidation remains idempotent.
                _ = try invalidateTurnDigestIfSourceChanged(
                    sessionID: sessionID, requestID: requestID)
                return ChatCorrectionRecord(
                    correctionID: existing.correctionID,
                    messageID: existing.messageID,
                    previousSHA256: existing.previousSHA256,
                    correctedSHA256: existing.correctedSHA256,
                    reason: existing.reason,
                    actor: existing.actor,
                    correctedAt: existing.correctedAt,
                    invalidatedTurnIndex: existing.invalidatedTurnIndex)
            }
            // 已经是这份正文：不制造一次「把 A 改成 A」的事件。
            if digest == row.digest {
                // 但这行若是更正来的，它的摘要就可能仍由更正前的正文派生（实测
                // t54：正文已更正 8,878 B，turn 摘要还是占位符时代的结论）。
                // 没更正过的行进这里不动任何派生行。
                let wasCorrected = try messageHasCorrection(row.id)
                return ChatCorrectionRecord(
                    correctionID: correctionID, messageID: row.id,
                    previousSHA256: row.digest, correctedSHA256: digest,
                    reason: trimmedReason, actor: trimmedActor, correctedAt: stamp,
                    invalidatedTurnIndex: wasCorrected
                        ? try invalidateTurnDigestIfSourceChanged(
                            sessionID: sessionID, requestID: requestID)
                        : nil)
            }
            let objectID = try ensureObject(data)
            try execBinding("""
            INSERT INTO chat_message_corrections(
                correction_id, message_id, previous_object_id, previous_sha256,
                corrected_object_id, corrected_sha256, reason, actor, corrected_at)
            VALUES(?,?,?,?,?,?,?,?,?);
            """) { s in
                try bind(s, 1, correctionID)
                try bind(s, 2, row.id)
                if let previous = row.objectID {
                    try bind(s, 3, previous)
                } else {
                    try bindNull(s, 3)
                }
                try bind(s, 4, row.digest)
                try bind(s, 5, objectID)
                try bind(s, 6, digest)
                try bind(s, 7, trimmedReason)
                try bind(s, 8, trimmedActor)
                try bind(s, 9, stamp)
            }
            try execBinding("""
            UPDATE chat_messages SET content_sha256=?, content_object_id=? WHERE id=?;
            """) { s in
                try bind(s, 1, digest)
                try bind(s, 2, objectID)
                try bind(s, 3, row.id)
            }
            // 索引是追加的：旧条目仍指向原对象，新条目指向更正后的正文。
            _ = try appendIndexEntryInTransaction(
                identity: "chat:\(sessionID)/\(row.id)", objectID: objectID)
            // 摘要是从正文派生出来的：正文换了，旧摘要就不再代表这一轮。留着它，
            // 发现路径会继续端出一份「看起来还有效」的旧表示（实测 t54：正文
            // 8,878 B 已更正，turn 摘要仍是 604 B 占位符时代的结论）。派生行不是
            // 历史——正文与更正记录才是——所以这里删掉它，由调用方补算。
            let invalidatedTurn = try invalidateTurnDigest(
                sessionID: sessionID, requestID: requestID)
            return ChatCorrectionRecord(
                correctionID: correctionID, messageID: row.id,
                previousSHA256: row.digest, correctedSHA256: digest,
                reason: trimmedReason, actor: trimmedActor, correctedAt: stamp,
                invalidatedTurnIndex: invalidatedTurn)
        }
    }

    /// 删掉这一轮的派生摘要、关键词及失效的房间归属/重试意图，返回轮号。
    /// 没有轮账映射时返回 nil。
    private func invalidateTurnDigest(
        sessionID: String, requestID: String
    ) throws -> Int? {
        let stmt = try prepare("""
        SELECT turn_index FROM chat_turn_ledger WHERE session_id=? AND request_id=? LIMIT 1;
        """)
        var turn: Int?
        do {
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, requestID)
            if try stepRowOrDone(stmt) {
                turn = Int(sqlite3_column_int64(stmt, 0))
            }
        }
        guard let turn else { return nil }
        try deleteTurnDigest(sessionID: sessionID, turnIndex: turn)
        // These tables are lazily created. Clear them when present, but do not make
        // a first-time correction fail by assuming the room subsystem was opened.
        try clearSpaceAssignmentArtifacts(sessionID: sessionID, turnIndex: turn)
        return turn
    }

    /// Replaying a correction is a no-op for a digest that was regenerated from
    /// the exact current question and answer. Legacy digests without a receipt,
    /// and digests whose source hashes no longer match, are removed fail-closed.
    private func invalidateTurnDigestIfSourceChanged(
        sessionID: String, requestID: String
    ) throws -> Int? {
        var turn: Int?
        var sourceStillMatches = false
        do {
            let stmt = try prepare("""
            SELECT l.turn_index,
                   (SELECT s.question_sha256 FROM turn_digest_sources s
                     WHERE s.session_id=l.session_id AND s.turn_index=l.turn_index),
                   (SELECT s.answer_sha256 FROM turn_digest_sources s
                     WHERE s.session_id=l.session_id AND s.turn_index=l.turn_index),
                   (SELECT COUNT(*) FROM chat_messages m
                     WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                       AND m.role='user'),
                   (SELECT m.content_sha256 FROM chat_messages m
                     WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                       AND m.role='user' ORDER BY m.id DESC LIMIT 1),
                   (SELECT COUNT(*) FROM chat_messages m
                     WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                       AND m.role='assistant'),
                   (SELECT m.content_sha256 FROM chat_messages m
                     WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                       AND m.role='assistant' ORDER BY m.id DESC LIMIT 1),
                   (SELECT COUNT(*) FROM chat_messages m
                      JOIN is_objects o ON o.object_id=m.content_object_id
                     WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                       AND m.role='user'),
                   (SELECT COUNT(*) FROM chat_messages m
                      JOIN is_objects o ON o.object_id=m.content_object_id
                     WHERE m.session_id=l.session_id AND m.request_id=l.request_id
                       AND m.role='assistant')
              FROM chat_turn_ledger l
             WHERE l.session_id=? AND l.request_id=?
             LIMIT 1;
            """)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, requestID)
            if try stepRowOrDone(stmt) {
                turn = Int(sqlite3_column_int64(stmt, 0))
                func text(_ index: Int32) -> String? {
                    sqlite3_column_text(stmt, index).map { String(cString: $0) }
                }
                let sourceQuestion = text(1)
                let sourceAnswer = text(2)
                let questionRows = Int(sqlite3_column_int64(stmt, 3))
                let currentQuestion = text(4)
                let answerRows = Int(sqlite3_column_int64(stmt, 5))
                let currentAnswer = text(6)
                let readableQuestionRows = Int(sqlite3_column_int64(stmt, 7))
                let readableAnswerRows = Int(sqlite3_column_int64(stmt, 8))
                sourceStillMatches =
                    sourceQuestion != nil && sourceAnswer != nil
                    && questionRows == 1 && answerRows == 1
                    && readableQuestionRows == 1 && readableAnswerRows == 1
                    && sourceQuestion == currentQuestion
                    && sourceAnswer == currentAnswer
            }
        }
        guard let turn else { return nil }
        if sourceStillMatches { return nil }
        // The read statement is finalized before deleting on this connection.
        try deleteTurnDigest(sessionID: sessionID, turnIndex: turn)
        return turn
    }

    private func deleteTurnDigest(sessionID: String, turnIndex: Int) throws {
        try execBinding("""
        DELETE FROM turn_digests WHERE session_id=? AND turn_index=?;
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, Int64(turnIndex))
        }
        try execBinding("""
        DELETE FROM turn_keywords WHERE session_id=? AND turn_index=?;
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, Int64(turnIndex))
        }
        try execBinding("""
        DELETE FROM turn_digest_sources WHERE session_id=? AND turn_index=?;
        """) { stmt in
            try bind(stmt, 1, sessionID)
            try bind(stmt, 2, Int64(turnIndex))
        }
    }

    /// 某一行的当前正文（更正后读到的就是更正后的）。给更正后的摘要补算用。
    public func chatMessageText(
        sessionID: String, requestID: String, role: String
    ) throws -> String? {
        let stmt = try prepare("""
        SELECT COALESCE(CAST(o.content AS TEXT), c.content)
        FROM chat_messages c
        LEFT JOIN is_objects o ON o.object_id = c.content_object_id
        WHERE c.session_id=? AND c.request_id=? AND c.role=?
        ORDER BY c.id DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, requestID)
        try bind(stmt, 3, role)
        guard try stepRowOrDone(stmt) else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// 这一行改过几次、都改了什么。原记录与更正记录一起读，历史不会只有一半。
    public func chatCorrections(
        sessionID: String, requestID: String, role: String
    ) throws -> [ChatCorrectionRecord] {
        let stmt = try prepare("""
        SELECT k.correction_id, k.message_id, k.previous_sha256, k.corrected_sha256,
               k.reason, k.actor, k.corrected_at,
               (SELECT l.turn_index FROM chat_turn_ledger l
                 WHERE l.session_id = c.session_id AND l.request_id = c.request_id
                 LIMIT 1)
        FROM chat_message_corrections k
        JOIN chat_messages c ON c.id = k.message_id
        WHERE c.session_id=? AND c.request_id=? AND c.role=?
        ORDER BY k.corrected_at ASC, k.correction_id ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, requestID)
        try bind(stmt, 3, role)
        var rows: [ChatCorrectionRecord] = []
        while try stepRowOrDone(stmt) {
            func text(_ index: Int32) -> String {
                sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
            }
            // 轮号不随更正行存（v37 表已冻结）：它由轮账决定，读时现查同一答案。
            rows.append(ChatCorrectionRecord(
                correctionID: text(0), messageID: sqlite3_column_int64(stmt, 1),
                previousSHA256: text(2), correctedSHA256: text(3),
                reason: text(4), actor: text(5), correctedAt: text(6),
                invalidatedTurnIndex: sqlite3_column_type(stmt, 7) == SQLITE_NULL
                    ? nil : Int(sqlite3_column_int64(stmt, 7))))
        }
        return rows
    }

    private func correctionRecord(
        _ correctionID: String, sessionID: String, requestID: String, role: String
    ) throws -> ChatCorrectionRecord? {
        let stmt = try prepare("""
        SELECT k.correction_id, k.message_id, k.previous_sha256, k.corrected_sha256,
               k.reason, k.actor, k.corrected_at,
               (SELECT l.turn_index FROM chat_turn_ledger l
                 WHERE l.session_id=c.session_id AND l.request_id=c.request_id
                 LIMIT 1)
          FROM chat_message_corrections k
          JOIN chat_messages c ON c.id=k.message_id
         WHERE k.correction_id=? AND c.session_id=? AND c.request_id=? AND c.role=?
         LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, correctionID)
        try bind(stmt, 2, sessionID)
        try bind(stmt, 3, requestID)
        try bind(stmt, 4, role)
        guard try stepRowOrDone(stmt) else { return nil }
        func text(_ index: Int32) -> String {
            sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
        }
        return ChatCorrectionRecord(
            correctionID: text(0),
            messageID: sqlite3_column_int64(stmt, 1),
            previousSHA256: text(2),
            correctedSHA256: text(3),
            reason: text(4),
            actor: text(5),
            correctedAt: text(6),
            invalidatedTurnIndex: sqlite3_column_type(stmt, 7) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(stmt, 7)))
    }

    /// 这一行是不是被更正过（决定它的派生摘要还能不能代表现在的正文）。
    private func messageHasCorrection(_ messageID: Int64) throws -> Bool {
        let stmt = try prepare(
            "SELECT 1 FROM chat_message_corrections WHERE message_id=? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, messageID)
        return try stepRowOrDone(stmt)
    }

    public struct ChatTurnProvenance: Equatable, Sendable {
        public let messageID: Int64
        public let sessionID: String
        public let role: String
        public let turnState: String
        public let sourceKind: String
        public let sourceProvider: String?
        public let requestID: String?
        public let verifiedAt: String?
        public let contentSHA256: String
        /// Ordinary standing is this row's own fact; whether a given request
        /// may consume it also depends on that request's scope.
        public var isEligible: Bool { turnState == "committed" }
    }

    /// Read back every line a request produced, with provenance and standing.
    /// Recorded rows are readable here without being eligible anywhere else.
    public func chatTurnProvenance(
        sessionID: String, requestID: String
    ) throws -> [ChatTurnProvenance] {
        try provenanceRows(
            where: "session_id=? AND request_id=?", sessionID, requestID)
    }

    /// Every line of a session in arrival order. Audit surfaces use this when
    /// the request id is not known in advance.
    public func chatTurnProvenance(
        sessionID: String
    ) throws -> [ChatTurnProvenance] {
        try provenanceRows(where: "session_id=?", sessionID)
    }

    private func provenanceRows(
        where clause: String, _ arguments: String...
    ) throws -> [ChatTurnProvenance] {
        let stmt = try prepare("""
        SELECT id, session_id, role, turn_state, source_kind, source_provider,
               request_id, verified_at, content_sha256
        FROM chat_messages
        WHERE \(clause) ORDER BY id;
        """)
        defer { sqlite3_finalize(stmt) }
        for (offset, argument) in arguments.enumerated() {
            try bind(stmt, Int32(offset + 1), argument)
        }
        var rows: [ChatTurnProvenance] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            rows.append(ChatTurnProvenance(
                messageID: sqlite3_column_int64(stmt, 0),
                sessionID: text(1) ?? "", role: text(2) ?? "",
                turnState: text(3) ?? "", sourceKind: text(4) ?? "",
                sourceProvider: text(5), requestID: text(6),
                verifiedAt: text(7), contentSHA256: text(8) ?? ""))
        }
        return rows
    }

    /// One completed external turn as text, for cross-carrier content dedupe.
    public struct ExternalTurnText: Sendable, Equatable {
        public let sessionID: String
        public let prompt: String
        public let answer: String
    }

    /// Whether this (session, request) pair already has its user row. The
    /// recorder is idempotent, so the caller needs this only to report an
    /// existing row as skipped rather than as newly written.
    public func externalTurnExists(sessionID: String, requestID: String) throws -> Bool {
        try externalRowID(sessionID: sessionID, requestID: requestID, role: "user") != nil
    }

    /// Every completed external turn whose session id begins with one of
    /// `prefixes`. The body is read back through `is_objects` because a
    /// committed row's inline `content` is emptied once it is object-addressed;
    /// comparing the emptied column would make every turn look different.
    ///
    /// This is a read-only aid for a carrier that re-describes history another
    /// carrier already delivered (an export of a session the native collector
    /// owns): identity by request id cannot see that duplication, only content
    /// can.
    public func externalTurnTexts(sessionPrefixes: [String]) throws -> [ExternalTurnText] {
        guard !sessionPrefixes.isEmpty else { return [] }
        let clause = sessionPrefixes.map { _ in "u.session_id LIKE ?" }
            .joined(separator: " OR ")
        let stmt = try prepare("""
        SELECT u.session_id,
               COALESCE(CAST(ou.content AS TEXT), u.content),
               COALESCE(CAST(oa.content AS TEXT), a.content)
        FROM chat_messages u
        JOIN chat_messages a
          ON a.session_id=u.session_id AND a.request_id=u.request_id
         AND a.role='assistant'
        LEFT JOIN is_objects ou ON ou.object_id=u.content_object_id
        LEFT JOIN is_objects oa ON oa.object_id=a.content_object_id
        WHERE u.role='user' AND u.source_kind='external' AND (\(clause));
        """)
        defer { sqlite3_finalize(stmt) }
        for (offset, prefix) in sessionPrefixes.enumerated() {
            try bind(stmt, Int32(offset + 1), prefix + "%")
        }
        var rows: [ExternalTurnText] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            rows.append(
                ExternalTurnText(sessionID: text(0), prompt: text(1), answer: text(2)))
        }
        return rows
    }

    // MARK: - MCP turn ledger

    /// What the ledger knows after recording one round number.
    ///
    /// `missing` is the number of round indices below the highest seen index
    /// that never arrived. It is a fact about calls, not about the agent's
    /// internals: a gap means the caller skipped a number it itself chose.
    public struct TurnLedgerReport: Sendable, Equatable {
        public let sessionID: String
        public let turnIndex: Int
        public let entered: Int
        public let highest: Int
        public let missing: [Int]
        /// Set when this round number already belongs to a different request.
        /// The ledger keeps the first owner; the second one is not silently
        /// merged, because two agents sharing a session id would otherwise
        /// lose a round each time their numbers collided.
        public let conflict: String?

        public var isContinuous: Bool { missing.isEmpty }

        func withConflict(_ owner: String) -> TurnLedgerReport {
            TurnLedgerReport(
                sessionID: sessionID, turnIndex: turnIndex, entered: entered,
                highest: highest, missing: missing, conflict: owner)
        }
    }

    /// Record that `turnIndex` arrived for `sessionID`, then report the ledger.
    /// Re-recording the same index is a no-op; the request id is kept from the
    /// first arrival so a retry cannot rewrite the round it named.
    public func recordTurnIndex(
        sessionID: String, turnIndex: Int, requestID: String, at: Date = Date()
    ) throws -> TurnLedgerReport {
        try transactionResult {
            if let owner = try turnLedgerOwner(sessionID: sessionID, turnIndex: turnIndex),
                owner != requestID
            {
                // Same slot, different owner. Refusing is the only honest
                // outcome: overwriting would rewrite history, and ignoring
                // would drop a round while the count still looked right.
                return try turnLedger(sessionID: sessionID, turnIndex: turnIndex)
                    .withConflict(owner)
            }
            // source_time 是回填工具加的列（不是迁移建的），新库里可能还没有。
            // 有就顺手写上，没有就退回四列——迁移版本不因为一行时间而改。
            if try columnExists("chat_turn_ledger", "source_time") {
                try execBinding("""
                INSERT OR IGNORE INTO chat_turn_ledger(
                    session_id, turn_index, request_id, seen_at, source_time
                ) VALUES(?,?,?,?,?);
                """) { stmt in
                    try bind(stmt, 1, sessionID)
                    try bind(stmt, 2, Int64(turnIndex))
                    try bind(stmt, 3, requestID)
                    try bind(stmt, 4, Self.stamp(at))
                    // 记这一轮的人就是知道它什么时候发生的人：时间随写入一起
                    // 落，不必等事后从源文件里捞。口径与回填工具一致（UTC ISO）：
                    // seen_at 是给图重建的位精确编码，source_time 是给人看的时刻，
                    // 一列两种写法的话，下一次回填就会把实时行改写成另一种。
                    try bind(stmt, 5, Self.isoUTC(at))
                }
                // 历史归一不在这里做。写一轮就写自己那一行：每写入都全表扫一
                // 遍，是拿正常路径的代价去还历史的账，而且越积越贵。历史那笔
                // 账归 `backfillSourceTimes`（启动一次 / 人手点一次），那里已经
                // 按每行自己的 seen_at 重写实时行。
            } else {
                try execBinding("""
                INSERT OR IGNORE INTO chat_turn_ledger(
                    session_id, turn_index, request_id, seen_at) VALUES(?,?,?,?);
                """) { stmt in
                    try bind(stmt, 1, sessionID)
                    try bind(stmt, 2, Int64(turnIndex))
                    try bind(stmt, 3, requestID)
                    try bind(stmt, 4, Self.stamp(at))
                }
            }
            return try turnLedger(sessionID: sessionID, turnIndex: turnIndex)
        }
    }

    private func turnLedgerOwner(sessionID: String, turnIndex: Int) throws -> String? {
        let stmt = try prepare("""
        SELECT request_id FROM chat_turn_ledger
        WHERE session_id=? AND turn_index=? LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        guard try stepRowOrDone(stmt), let text = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: text)
    }

    /// Read-only ledger state for one session and the round just recorded.
    public func turnLedger(
        sessionID: String, turnIndex: Int = 0
    ) throws -> TurnLedgerReport {
        let stmt = try prepare("""
        SELECT turn_index FROM chat_turn_ledger
        WHERE session_id=? ORDER BY turn_index;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        var seen: [Int] = []
        while try stepRowOrDone(stmt) {
            seen.append(Int(sqlite3_column_int64(stmt, 0)))
        }
        let highest = seen.last ?? 0
        let present = Set(seen)
        let missing = (1...max(highest, 1)).filter { !present.contains($0) }
        return TurnLedgerReport(
            sessionID: sessionID, turnIndex: turnIndex, entered: seen.count,
            highest: highest, missing: missing, conflict: nil)
    }

    /// 导入的会话补轮次账的结果。
    public struct ImportedLedgerReport: Sendable, Equatable {
        /// 这次补进去的会话数（有候选、补之前一行账都没有的）。
        public let sessionsFilled: Int
        /// 这次补进去的轮数。
        public let turnsInserted: Int
        /// 已经有轮号、整会话跳过的外部会话数。
        public let sessionsKept: Int
        /// 没有 request_id、这次补不了的会话数与消息数。
        public let sessionsUnkeyed: Int
        public let messagesUnkeyed: Int
        /// 补完之后导入轮的总数（不只这次）。
        public let importedTurnsTotal: Int
    }

    /// 采集桥导入的历史会话，按到达序补一本轮次账。
    ///
    /// 只补「一行账都没有」的外部会话。已经有轮号的会话整会话跳过：MCP 的
    /// 轮号是调用方自己选的，导入的轮号是排出来的，两种编号混在一个 session
    /// 里，缺号就不再表示漏写。这条规矩靠 origin 列写进数据，不靠前缀去猜。
    ///
    /// 轮号 = 同一 request_id 的首条消息按 (时间, id) 排出的序。写在事务里，
    /// 重复调用是空操作。
    @discardableResult
    public func backfillImportedTurnLedger() throws -> ImportedLedgerReport {
        try transactionResult {
            func count(_ sql: String) throws -> Int {
                let stmt = try prepare(sql)
                defer { sqlite3_finalize(stmt) }
                return try stepRowOrDone(stmt) ? Int(sqlite3_column_int64(stmt, 0)) : 0
            }
            let kept = try count("""
            SELECT COUNT(DISTINCT m.session_id) FROM chat_messages m
             WHERE m.source_kind='external'
               AND EXISTS (SELECT 1 FROM chat_turn_ledger l
                            WHERE l.session_id=m.session_id);
            """)
            let unkeyedSessions = try count("""
            SELECT COUNT(DISTINCT session_id) FROM chat_messages
             WHERE request_id IS NULL
               AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger);
            """)
            let unkeyedMessages = try count("""
            SELECT COUNT(*) FROM chat_messages
             WHERE request_id IS NULL
               AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger);
            """)
            let fillable = try count("""
            SELECT COUNT(DISTINCT session_id) FROM chat_messages
             WHERE source_kind='external' AND request_id IS NOT NULL
               AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger);
            """)
            try rawExec( """
            INSERT INTO chat_turn_ledger(
                session_id, turn_index, request_id, seen_at, origin)
            SELECT b.session_id,
                   ROW_NUMBER() OVER (
                       PARTITION BY b.session_id ORDER BY b.first_at, b.first_id),
                   b.request_id,
                   (SELECT m.created_at FROM chat_messages m WHERE m.id=b.first_id),
                   'import'
              FROM (SELECT session_id, request_id,
                           MIN(CAST(created_at AS REAL)) AS first_at,
                           MIN(id) AS first_id
                      FROM chat_messages
                     WHERE source_kind='external' AND request_id IS NOT NULL
                       AND session_id NOT IN (SELECT session_id FROM chat_turn_ledger)
                     GROUP BY session_id, request_id) b;
            """)
            return ImportedLedgerReport(
                sessionsFilled: fillable,
                turnsInserted: Int(sqlite3_changes(handle)),
                sessionsKept: kept,
                sessionsUnkeyed: unkeyedSessions,
                messagesUnkeyed: unkeyedMessages,
                importedTurnsTotal: try count(
                    "SELECT COUNT(*) FROM chat_turn_ledger WHERE origin='import';"))
        }
    }

    /// 某轮在账上记的 request id。导入的轮和 MCP 的轮都从这里读，
    /// 调用方不需要知道它是怎么排出来的。
    public func turnLedgerRequestID(sessionID: String, turnIndex: Int) throws -> String? {
        let stmt = try prepare("""
        SELECT request_id FROM chat_turn_ledger
         WHERE session_id=? AND turn_index=? LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        try bind(stmt, 2, Int64(turnIndex))
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    /// The session whose round arrived most recently, for a status display.
    public func latestTurnLedgerSessionID() throws -> String? {
        let stmt = try prepare("""
        SELECT session_id FROM chat_turn_ledger ORDER BY seen_at DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        guard try stepRowOrDone(stmt), let text = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: text)
    }

    // MARK: - Project notes

    /// One recorded judgement. The row is immutable: a later note may supersede
    /// it, but nothing edits it, so the claim that was believed at a time stays
    /// readable after that time has passed.
    public struct ProjectNote: Equatable, Sendable {
        public let noteID: String
        public let kind: String
        public let claim: String
        public let supersedes: String?
        public let objectID: String
        public let recordedAt: String
    }

    /// Append a judgement of `kind` and supersede the current one of the same
    /// kind. "Current" is derived from the supersede pointers, never stored as a
    /// flag: a status bit is a second place that can disagree with the history.
    ///
    /// Recording a byte-identical claim again is a no-op — the object is already
    /// the current answer, so a second pointer would add history without adding
    /// a claim.
    @discardableResult
    public func recordProjectNote(
        kind: String, claim: String, at: Date = Date()
    ) throws -> (note: ProjectNote, superseded: String?, created: Bool) {
        let text = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DatabaseError.sql("project note claim is empty")
        }
        let trimmedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKind.isEmpty else {
            throw DatabaseError.sql("project note kind is empty")
        }
        return try transactionResult {
            let current = try currentProjectNote(kind: trimmedKind)
            let objectID = try ensureObject(Data(text.utf8))
            if let current, current.objectID == objectID {
                return (current, nil, false)
            }
            let noteID = UUID().uuidString
            let recordedAt = Self.stamp(at)
            try execBinding("""
            INSERT INTO project_notes(
                note_id, kind, claim, supersedes, object_id, recorded_at)
            VALUES(?,?,?,?,?,?);
            """) { stmt in
                try bind(stmt, 1, noteID)
                try bind(stmt, 2, trimmedKind)
                try bind(stmt, 3, text)
                try bind(stmt, 4, current?.noteID)
                try bind(stmt, 5, objectID)
                try bind(stmt, 6, recordedAt)
            }
            let note = ProjectNote(
                noteID: noteID, kind: trimmedKind, claim: text,
                supersedes: current?.noteID, objectID: objectID,
                // The row keeps exactly what `stamp(at)` produced; the value
                // handed back obeys the same epoch contract every read does, so
                // a write and the read that follows cannot disagree.
                recordedAt: ProjectNoteEpoch.normalizedStamp(recordedAt))
            return (note, current?.noteID, true)
        }
    }

    /// The note of `kind` that nothing later supersedes, if one was recorded.
    public func currentProjectNote(kind: String) throws -> ProjectNote? {
        let stmt = try prepare("""
        SELECT note_id, kind, claim, supersedes, object_id, recorded_at
          FROM project_notes
         WHERE kind = ?
           AND note_id NOT IN (
               SELECT supersedes FROM project_notes WHERE supersedes IS NOT NULL)
         ORDER BY rowid DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, kind)
        guard try stepRowOrDone(stmt) else { return nil }
        return projectNote(from: stmt)
    }

    /// Newest first. The whole history of a kind is what makes a changed
    /// judgement visible as a change instead of as a fact that was always so.
    public func projectNoteHistory(
        kind: String, limit: Int = 20
    ) throws -> [ProjectNote] {
        let stmt = try prepare("""
        SELECT note_id, kind, claim, supersedes, object_id, recorded_at
          FROM project_notes WHERE kind = ? ORDER BY rowid DESC LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, kind)
        try bind(stmt, 2, Int64(max(limit, 1)))
        var notes: [ProjectNote] = []
        while try stepRowOrDone(stmt) { notes.append(projectNote(from: stmt)) }
        return notes
    }

    public func projectNoteCount(kind: String) throws -> Int {
        let stmt = try prepare("SELECT COUNT(*) FROM project_notes WHERE kind = ?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, kind)
        guard try stepRowOrDone(stmt) else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// 以 `prefix` 开头的那些 kind 的现行条目（`brief`、`brief@codex`…）。
    /// 只给「明确要看全部」的调用方用：默认视图按客户端取，跨端是显式动作。
    public func currentProjectNotes(kindPrefix: String) throws -> [ProjectNote] {
        let stmt = try prepare("""
        SELECT note_id, kind, claim, supersedes, object_id, recorded_at
          FROM project_notes
         WHERE kind LIKE ? || '%'
           AND note_id NOT IN (
               SELECT supersedes FROM project_notes WHERE supersedes IS NOT NULL)
         ORDER BY kind;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, kindPrefix)
        var notes: [ProjectNote] = []
        while try stepRowOrDone(stmt) { notes.append(projectNote(from: stmt)) }
        return notes
    }

    /// 判断写完之后又落库的材料，最旧的在前。
    ///
    /// This is the material a judgement has not accounted for yet. 不限 kind：
    /// 交接要回答的是「这条判断还没算进什么」，裁定（decision）、状态（status）、
    /// 窗口留档（window）都算材料——只带 window 的那版让裁定绕过了交接，读者于
    /// 是拿着已失效的清单继续走。滚动摘要（`digest*`）除外：它每五分钟自动刷一
    /// 版，是过程噪声，混进来会把「有新裁定」淹掉。
    ///
    /// It is returned as a list and never merged into the judgement: the reader
    /// still has to decide what, if anything, the new material changes.
    /// `recorded_at` is Core Data seconds, so both sides are compared as REAL
    /// rather than as text — through `ProjectNoteEpoch.recordedAtSQL()`, because
    /// rows written out-of-band in Unix seconds would otherwise outrank every
    /// well-formed row forever and pin `stale` to true (defect FDC884A7).
    public func projectNotesNewerThan(
        than recordedAt: String, scope: String
    ) throws -> [ProjectNote] {
        let stmt = try prepare("""
        SELECT note_id, kind, claim, supersedes, object_id, recorded_at
          FROM project_notes
         WHERE kind LIKE '%@' || ?
           AND kind NOT LIKE 'digest%'
           AND \(ProjectNoteEpoch.recordedAtSQL()) > CAST(? AS REAL)
         ORDER BY \(ProjectNoteEpoch.recordedAtSQL()) ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, scope)
        try bind(stmt, 2, ProjectNoteEpoch.normalizedStamp(recordedAt))
        var notes: [ProjectNote] = []
        while try stepRowOrDone(stmt) { notes.append(projectNote(from: stmt)) }
        return notes
    }

    public func projectNotesNewerThan(than recordedAt: String) throws -> [ProjectNote] {
        let stmt = try prepare("""
        SELECT note_id, kind, claim, supersedes, object_id, recorded_at
          FROM project_notes
         WHERE kind NOT LIKE 'digest%'
           AND \(ProjectNoteEpoch.recordedAtSQL()) > CAST(? AS REAL)
         ORDER BY \(ProjectNoteEpoch.recordedAtSQL()) ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, ProjectNoteEpoch.normalizedStamp(recordedAt))
        var notes: [ProjectNote] = []
        while try stepRowOrDone(stmt) { notes.append(projectNote(from: stmt)) }
        return notes
    }

    /// 动态交接：最近若干轮的摘要拼成一张会滚动的摘录。
    ///
    /// 它不是判断，也不替代 brief。brief 说「现在是什么状态」，这张单子只说
    /// 「最近发生过什么」，每条带时刻，旧的自动滚出。素材是 IS 自己的
    /// `turn_digests`（已经压过一遍），所以不需要解析任何客户端的转写文件。
    ///
    /// 时间闸是节流不是精度：一轮里 user/assistant 各落一次摘要，不设闸会把
    /// 同一件事刷两遍。内容没变就不写，免得 supersede 链上多一条空记录。
    @discardableResult
    public func refreshRollingDigest(
        scope: String? = nil, limit: Int = 10,
        minimumInterval: TimeInterval = 300, at now: Date = Date()
    ) throws -> ProjectNote? {
        let kind = Self.scopedKind("digest", scope: scope)
        let current = try currentProjectNote(kind: kind)
        if let current, let recorded = Double(current.recordedAt),
           now.timeIntervalSinceReferenceDate - recorded < minimumInterval {
            return nil
        }
        let rows = try recentDigests(limit: max(limit, 1), scope: scope)
        guard !rows.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        var lines = ["动态交接 · 最近 \(rows.count) 轮 · 自动摘录，含时刻，不得当现值"]
        for row in rows {
            let when = Double(row.createdAt).map {
                formatter.string(from: Date(timeIntervalSinceReferenceDate: $0))
            } ?? row.createdAt
            let head = String(
                (row.digest.split(separator: "\n").first.map(String.init) ?? "")
                    .prefix(120))
            lines.append("- \(when) \(row.sessionID) t\(row.turnIndex) · \(head)")
        }
        let claim = lines.joined(separator: "\n")
        if claim == current?.claim { return nil }
        return try recordProjectNote(kind: kind, claim: claim, at: now).note
    }

    /// Every note lives in a namespace: `owner` for all first-party/local work,
    /// the 64-hex bearer digest for an external MCP client. There is no
    /// scope-less shared note and no per-provider twin — an absent scope is the
    /// local owner, not a third place a judgement can hide.
    public static func scopedKind(_ kind: String, scope: String?) -> String {
        let effectiveScope: String
        if let scope, !scope.isEmpty, scope != "all" {
            effectiveScope = scope
        } else {
            effectiveScope = ownerNamespace
        }
        let baseKind = kind.split(separator: "@", maxSplits: 1).first.map(String.init) ?? kind
        return "\(baseKind)@\(effectiveScope)"
    }

    func normalizeProjectNoteKindsV52() throws {
        struct DirtyKind {
            let noteID: String
            let kind: String
            let normalizedKind: String
            let claimSHA256: String
            let objectID: String
            let supersedes: String?
            let recordedAt: String
        }

        let stmt = try prepare("""
        SELECT note_id, kind, claim, object_id, supersedes, recorded_at
          FROM project_notes
         WHERE length(kind) - length(replace(kind, '@', '')) > 1
         ORDER BY rowid;
        """)
        defer { sqlite3_finalize(stmt) }
        var rows: [DirtyKind] = []
        while try stepRowOrDone(stmt) {
            let noteID = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let kind = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let claim = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let objectID = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let supersedes = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let recordedAt = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
            let parts = kind.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[1] == parts[2], !parts[0].isEmpty,
                  !parts[1].isEmpty
            else {
                throw DatabaseError.migrationMismatch(
                    "unsupported project note kind shape: \(kind) (\(noteID))")
            }
            rows.append(DirtyKind(
                noteID: noteID, kind: kind,
                normalizedKind: "\(parts[0])@\(parts[1])",
                claimSHA256: NativeSHA256.hexDigest(Data(claim.utf8)),
                objectID: objectID, supersedes: supersedes,
                recordedAt: recordedAt))
        }

        let beforeJSON = try Self.canonicalJSON(rows.map {
            [
                "note_id": $0.noteID, "kind": $0.kind,
                "claim_sha256": $0.claimSHA256, "object_id": $0.objectID,
                "supersedes": $0.supersedes ?? "", "recorded_at": $0.recordedAt,
            ]
        })
        let bodyJSON = try Self.canonicalJSON(rows.map {
            [
                "note_id": $0.noteID, "claim_sha256": $0.claimSHA256,
                "object_id": $0.objectID, "supersedes": $0.supersedes ?? "",
                "recorded_at": $0.recordedAt,
            ]
        })
        let beforeSHA256 = NativeSHA256.hexDigest(Data(beforeJSON.utf8))
        let bodySHA256 = NativeSHA256.hexDigest(Data(bodyJSON.utf8))

        for row in rows {
            let changed = try execBinding(
                "UPDATE project_notes SET kind=? WHERE note_id=? AND kind=?;"
            ) { stmt in
                try bind(stmt, 1, row.normalizedKind)
                try bind(stmt, 2, row.noteID)
                try bind(stmt, 3, row.kind)
            }
            guard changed == 1 else {
                throw DatabaseError.migrationMismatch(
                    "project note kind update changed \(changed) rows: \(row.noteID)")
            }
        }

        let remaining = try prepare("""
        SELECT COUNT(*) FROM project_notes
         WHERE length(kind) - length(replace(kind, '@', '')) > 1;
        """)
        defer { sqlite3_finalize(remaining) }
        guard try stepRowOrDone(remaining) else {
            throw DatabaseError.migrationMismatch("project note kind count missing")
        }
        let afterCount = Int(sqlite3_column_int64(remaining, 0))
        guard afterCount == 0 else {
            throw DatabaseError.migrationMismatch(
                "project note kinds still contain multiple suffixes: \(afterCount)")
        }
        let result = try Self.canonicalJSON([
            "before_count": rows.count, "after_count": afterCount,
            "before_sha256": beforeSHA256, "body_sha256": bodySHA256,
        ])
        try execBinding("""
        INSERT INTO migration_receipts(
            source_kind, source_digest, result, rows_imported, completed_at)
        VALUES(?,?,?,?,?);
        """) { stmt in
            try bind(stmt, 1, "project_note_kind_normalization_v52")
            try bind(stmt, 2, beforeSHA256)
            try bind(stmt, 3, result)
            try bind(stmt, 4, Int64(rows.count))
            try bind(stmt, 5, Self.stamp(Date()))
        }
    }

    /// MCP session resolves to its bearer digest; every first-party non-MCP session resolves to owner.
    public static func clientScope(ofSession sessionID: String) -> String? {
        // MCP sessions are namespaced as mcp-<64-char bearer digest>-<agent session>.
        if sessionID.hasPrefix("mcp-") {
            let remainder = sessionID.dropFirst("mcp-".count)
            guard let separator = remainder.firstIndex(of: "-") else { return nil }
            let identity = String(remainder[..<separator])
            guard identity.range(
                of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
            else { return nil }
            return identity
        }
        // Every non-MCP session is first-party/local and belongs to owner.
        // Agent product names are provenance, not identity boundaries.
        return Self.ownerNamespace
    }

    private struct RecentDigest {
        let sessionID: String
        let turnIndex: Int
        let digest: String
        let createdAt: String
    }

    private func recentDigests(
        limit: Int, scope: String?
    ) throws -> [RecentDigest] {
        let sessionPrefix: String?
        if let scope {
            if scope == Self.ownerNamespace {
                // Local owner includes all first-party sessions, never MCP.
                sessionPrefix = "__owner__"
            } else if scope.range(
                of: "^[0-9a-f]{64}$", options: .regularExpression) != nil {
                sessionPrefix = "mcp-\(scope)-%"
            } else {
                return []
            }
        } else {
            sessionPrefix = nil
        }
        let filtered = sessionPrefix == "__owner__"
            ? "WHERE session_id NOT LIKE 'mcp-%'"
            : (sessionPrefix == nil ? "" : "WHERE session_id LIKE ?")
        let stmt = try prepare("""
        SELECT session_id, turn_index, digest, created_at FROM turn_digests
         \(filtered)
         ORDER BY CAST(created_at AS REAL) DESC LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        var slot: Int32 = 1
        if let sessionPrefix, sessionPrefix != "__owner__" {
            try bind(stmt, slot, sessionPrefix)
            slot += 1
        }
        try bind(stmt, slot, Int64(limit))
        var rows: [RecentDigest] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            rows.append(RecentDigest(
                sessionID: text(0), turnIndex: Int(sqlite3_column_int64(stmt, 1)),
                digest: text(2), createdAt: text(3)))
        }
        return rows.reversed()
    }

    private func projectNote(from stmt: OpaquePointer) -> ProjectNote {
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        let supersedes = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        return ProjectNote(
            noteID: text(0), kind: text(1), claim: text(2), supersedes: supersedes,
            // The one place a stored `recorded_at` becomes a `ProjectNote`:
            // normalizing here fixes every reader (display, `newer_notes`,
            // the digest throttle) without rewriting the append-only row.
            objectID: text(4),
            recordedAt: ProjectNoteEpoch.normalizedStamp(text(5)))
    }

    /// Most recent local user row of a session, if it has one. This is used
    /// only for identical internal-operation bookkeeping suppression; ordinary
    /// local turns never adopt a row created by another request.
    private func lastUserMessage(
        sessionID: String
    ) throws -> (messageID: Int64, digest: String, state: String)? {
        let stmt = try prepare("""
        SELECT id, content_sha256, turn_state FROM chat_messages
        WHERE session_id=? AND role='user' AND source_kind='local'
        ORDER BY id DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, sessionID)
        guard try stepRowOrDone(stmt),
            let text = sqlite3_column_text(stmt, 1)
        else { return nil }
        let state = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
        return (sqlite3_column_int64(stmt, 0), String(cString: text), state)
    }

    public struct ChatMessageRow: Equatable, Sendable {
        public let sessionID: String
        public let role: String
        public let content: String
        public let model: String?
        public let contentSHA256: String
        public let createdAt: String
    }

    public func listChatMessages(sessionID: String? = nil, limit: Int = 500) throws -> [ChatMessageRow] {
        let base = """
        SELECT c.session_id, c.role,
               COALESCE(CAST(o.content AS TEXT), c.content),
               c.model, c.content_sha256, c.created_at
        FROM chat_messages c
        LEFT JOIN is_objects o ON o.object_id=c.content_object_id
        """
        let sql = sessionID == nil
            ? base + " ORDER BY c.id DESC LIMIT \(limit);"
            : base + " WHERE c.session_id="
                + Self.sqlQuotedLiteral(sessionID!)
                + " ORDER BY c.id ASC LIMIT \(limit);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var rows: [ChatMessageRow] = []
        while try stepRowOrDone(stmt) {
            func col(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            rows.append(ChatMessageRow(
                sessionID: col(0), role: col(1), content: col(2),
                model: col(3).isEmpty ? nil : col(3),
                contentSHA256: col(4), createdAt: col(5)))
        }
        return rows
    }

    public struct ChatHit: Equatable, Sendable, Codable {
        public let sessionID: String
        public let messageID: Int64
        public let role: String
        public let lineNo: Int
        public let lineText: String
        public let contentSHA256: String
        public let createdAt: String
    }

    /// 对话检索：聊天信息一经落库即属信息空间，可按关键词作为 demand 的
    /// 一项输入被检索、结算与复用。只读已落库消息，不回放模型。
    public func searchChatMessages(
        query: String, sessionID: String? = nil, limit: Int = 200
    ) throws -> [ChatHit] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var sql = """
        SELECT c.session_id, c.id, c.role,
               COALESCE(CAST(o.content AS TEXT), c.content),
               c.content_sha256, c.created_at
        FROM chat_messages c
        LEFT JOIN is_objects o ON o.object_id=c.content_object_id
        WHERE c.turn_state='committed'
        """
        if let sessionID {
            sql += " AND c.session_id=" + Self.sqlQuotedLiteral(sessionID)
        }
        sql += " ORDER BY c.session_id, c.id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var hits: [ChatHit] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            let session = text(0) ?? ""
            let messageID = sqlite3_column_int64(stmt, 1)
            let role = text(2) ?? ""
            guard let body = text(3),
                NativeSHA256.hexDigest(Data(body.utf8)) == (text(4) ?? "")
            else { continue }
            for (idx, line) in body.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.localizedCaseInsensitiveContains(query) {
                hits.append(ChatHit(
                    sessionID: session, messageID: messageID, role: role,
                    lineNo: idx + 1, lineText: String(line.prefix(200)),
                    contentSHA256: text(4) ?? "", createdAt: text(5) ?? ""))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    public struct ChatIndexRow: Equatable, Sendable {
        public let sessionID: String
        public let messageID: Int64
        public let role: String
        public let content: String
        public let contentSHA256: String
        public let createdAt: String
        public var itemID: String { "chat:\(sessionID)/\(messageID)" }
    }

    /// Session scoping shared by every chat projection below. Ids are inlined
    /// as quoted literals, matching the rest of this file.
    /// SQL string literal with the single quote doubled — the one escaping rule
    /// for the few dynamic fragments that bind() cannot express.
    static func sqlQuotedLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func sessionClause(_ sessionIDs: [String]?) -> String {
        guard let sessionIDs, !sessionIDs.isEmpty else { return "" }
        let quoted = sessionIDs.map(Self.sqlQuotedLiteral)
        return " AND c.session_id IN (\(quoted.joined(separator: ",")))"
    }

    /// Eligible chat messages as demand inputs, with their settled digest.
    /// Eligibility is the turn's own completion (`commitChatTurn`), not mere
    /// presence in the live table: another request's in-flight user text and a
    /// cancelled turn's input are conversation lines without semantic standing.
    ///
    /// `matchingAny` is a prefilter, never a filter: it drops rows that cannot
    /// mention any term, so every row kept here still has to survive the
    /// per-line `citationSnippet` byte scan. SQLite's default LIKE folds
    /// exactly the ASCII bytes `foldedASCII` folds and leaves every other byte
    /// alone, so the dropped set is provably empty of citations. It exists
    /// because materializing the space's 39.9 MB (5,720 rows over 806k lines)
    /// into Swift strings to find a few hundred hits costs 0.85 s, and the same
    /// predicate in C costs 0.02 s — measured 2026-11-09, 6 keywords,
    /// set-equal to the byte scan on the live space.
    ///
    /// 3 字以上的词走 `is_objects_fts`（trigram）索引；1–2 字的词 trigram 建不出
    /// 片段，回落原来的 LIKE 全扫。两条路的命中集合相同：索引只覆盖挂在
    /// is_objects 上的行，没有对象的行仍走 LIKE，两者的并集就是原来的 LIKE 结果。
    /// trigram 索引吃得下的关键词：至少 3 个字符（trigram 按 3 字片段建索引，
    /// 「合同」两个字的片段根本不存在）。按 Character 计，一个汉字算一个字符。
    static func isFTSEligible(_ term: String) -> Bool {
        term.count >= 3
    }

    /// FTS5 的字符串字面量：整串加双引号 = 短语，内部双引号翻倍。
    /// 加了引号，`%`、`_`、括号、冒号都只是普通字符，不会被当成查询语法。
    static func ftsPhrase(_ term: String) -> String {
        "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// LIKE 的转义（配合 `ESCAPE '\'`）。通配符在这里只是字面量。
    static func likeEscaped(_ term: String) -> String {
        term
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// 一轮摘要的检索行。摘要是索引、不是原文：命中之后用来定位的是
    /// `sessionID + turnIndex`，引用的字节仍是那一轮的原文对象
    /// （`answerObjectID`），给人看的那一行是摘要本身。
    struct TurnDigestIndexRow: Sendable {
        let sessionID: String
        let turnIndex: Int
        let digest: String
        let keywords: String
        let answerObjectID: String?
    }

    /// 摘要与关键词都参与匹配。行数是个人的轮次量级（今天 382 行），
    /// 所以走 LIKE，不另建索引——真上到十万轮再谈。
    func turnDigestRows(matchingAny: [String]?) throws -> [TurnDigestIndexRow] {
        var rows: [TurnDigestIndexRow] = []
        try forEachTurnDigestRow(matchingAny: matchingAny) { rows.append($0) }
        return rows
    }

    /// Visit matching turn digests one row at a time; SQL errors propagate at the
    /// exact cursor boundary instead of being converted into a partial result.
    func forEachTurnDigestRow(
        matchingAny: [String]?, sessionIDs: [String]? = nil,
        _ body: (TurnDigestIndexRow) throws -> Void
    ) throws {
        let terms = (matchingAny ?? []).filter { !$0.isEmpty }
        var sql = """
        SELECT d.session_id, d.turn_index, d.digest, d.keywords, c.content_object_id
        FROM turn_digests d
        LEFT JOIN chat_messages c ON c.id = d.answer_message_id
        """
        var binds: [String] = []
        if !terms.isEmpty {
            var alternatives: [String] = []
            for term in terms {
                alternatives.append(
                    "(d.digest LIKE ? ESCAPE '\\' OR d.keywords LIKE ? ESCAPE '\\')")
                binds.append("%" + Self.likeEscaped(term) + "%")
                binds.append("%" + Self.likeEscaped(term) + "%")
            }
            sql += " WHERE " + alternatives.joined(separator: " OR ")
        }
        if let sessionIDs, !sessionIDs.isEmpty {
            let quoted = sessionIDs.map(Self.sqlQuotedLiteral)
            sql += terms.isEmpty
                ? " WHERE d.session_id IN (\(quoted.joined(separator: ",")))"
                : " AND d.session_id IN (\(quoted.joined(separator: ",")))"
        }
        sql += " ORDER BY d.session_id COLLATE BINARY, d.turn_index;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (idx, value) in binds.enumerated() {
            try bind(stmt, Int32(idx + 1), value)
        }
        while try stepRowOrDone(stmt) {
            try checkInformationScanCancellation()
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            try body(TurnDigestIndexRow(
                sessionID: text(0) ?? "",
                turnIndex: Int(sqlite3_column_int64(stmt, 1)),
                digest: text(2) ?? "",
                keywords: text(3) ?? "",
                answerObjectID: text(4)))
        }
    }

    /// 已提交的对话行（只读）。App 侧的回归要断言「结算失败之后没有留下 assistant
    /// 行」，用的就是这条读口；它返回的类型已经是 public，方法本身也一并公开。
    public func chatIndexRows(
        sessionIDs: [String]?, matchingAny: [String]? = nil
    ) throws -> [ChatIndexRow] {
        var rows: [ChatIndexRow] = []
        try forEachChatIndexRow(sessionIDs: sessionIDs, matchingAny: matchingAny) {
            rows.append($0)
        }
        return rows
    }

    /// Visit committed chat candidates one at a time. The SQL predicate remains
    /// a prefilter only; callers still verify bytes and build citations in Swift.
    func forEachChatIndexRow(
        sessionIDs: [String]?, matchingAny: [String]? = nil,
        _ body: (ChatIndexRow) throws -> Void
    ) throws {
        var sql = """
        SELECT c.session_id, c.id, c.role,
               COALESCE(CAST(o.content AS TEXT), c.content),
               c.content_sha256, c.created_at
        FROM chat_messages c
        LEFT JOIN is_objects o ON o.object_id=c.content_object_id
        WHERE c.turn_state='committed'
        """
        sql += sessionClause(sessionIDs)
        let terms = (matchingAny ?? []).filter { !$0.isEmpty }
        var binds: [String] = []
        if !terms.isEmpty {
            var alternatives: [String] = []
            for term in terms {
                if Self.isFTSEligible(term) {
                    alternatives.append(
                        "(o.rowid IN (SELECT rowid FROM is_objects_fts"
                            + " WHERE is_objects_fts MATCH ?)"
                            + " OR ((o.rowid IS NULL"
                            + " OR o.rowid NOT IN (SELECT object_rowid FROM is_search_indexed))"
                            + " AND CAST(COALESCE(o.content, c.content) AS TEXT)"
                            + " LIKE ? ESCAPE '\\'))")
                    binds.append(Self.ftsPhrase(term))
                    binds.append("%" + Self.likeEscaped(term) + "%")
                } else {
                    alternatives.append(
                        "CAST(COALESCE(o.content, c.content) AS TEXT) LIKE ? ESCAPE '\\'")
                    binds.append("%" + Self.likeEscaped(term) + "%")
                }
            }
            sql += " AND (" + alternatives.joined(separator: " OR ") + ")"
        }
        sql += " ORDER BY c.session_id COLLATE BINARY, c.id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (idx, value) in binds.enumerated() {
            try bind(stmt, Int32(idx + 1), value)
        }
        while try stepRowOrDone(stmt) {
            try checkInformationScanCancellation()
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            try body(ChatIndexRow(
                sessionID: text(0) ?? "", messageID: sqlite3_column_int64(stmt, 1),
                role: text(2) ?? "", content: text(3) ?? "",
                contentSHA256: text(4) ?? "", createdAt: text(5) ?? ""))
        }
    }

    public struct ChatScopeRow: Equatable, Sendable {
        public let sessionID: String
        public let messageID: Int64
        public let contentSHA256: String
        public var itemID: String { "chat:\(sessionID)/\(messageID)" }
    }

    /// The same rows `chatIndexRows` selects, reduced to identity and digest.
    /// A demand fingerprint built from these is byte-identical to one built
    /// from the full rows — same WHERE, same ORDER BY, same digest column — so
    /// scoping still sees every committed line while the chat bytes stay in
    /// SQLite.
    func chatScopeRows(sessionIDs: [String]?) throws -> [ChatScopeRow] {
        var rows: [ChatScopeRow] = []
        try forEachChatScopeRow(sessionIDs: sessionIDs) { rows.append($0) }
        return rows
    }

    /// Visit every committed chat identity/digest pair in stable database order.
    /// The caller can fold this stream into a fingerprint without retaining the
    /// complete conversation scope in memory.
    func forEachChatScopeRow(
        sessionIDs: [String]?, _ body: (ChatScopeRow) throws -> Void
    ) throws {
        var sql = """
        SELECT c.session_id, c.id, c.content_sha256
        FROM chat_messages c
        WHERE c.turn_state='committed'
        """
        sql += sessionClause(sessionIDs)
        sql += " ORDER BY c.session_id COLLATE BINARY, c.id;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        while try stepRowOrDone(stmt) {
            try checkInformationScanCancellation()
            try body(ChatScopeRow(
                sessionID: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
                messageID: sqlite3_column_int64(stmt, 1),
                contentSHA256: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""))
        }
    }

    /// The carrier object currently addressed by an index identity. Index-only
    /// file rows point here at their metadata record, not at file bytes.
    public func latestIndexObjectID(identity: String) throws -> String? {
        let stmt = try prepare("""
        SELECT record_object FROM is_index_entries
        WHERE srs_identity=? ORDER BY append_order DESC LIMIT 1;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, identity)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        return String(cString: c)
    }

    // MARK: - 渲染快照持久化（ADR_IS_RENDERING_SNAPSHOT_PERSISTENCE_20261122）

    /// FIFO row budget for durable rendering snapshots. Eviction only sends an
    /// occurrence back to a cold rebuild; it never renders wrong content.
    /// ponytail: global FIFO budget; per-scope LRU if measured churn demands it.
    static let renderSnapshotRowBudget = 2048

    /// Idempotent DDL, independent of numbered migrations (same pattern as
    /// `ensureTurnDigestSourceSchema`): this table ships migration-order free.
    private func ensureRenderSnapshotSchema() throws {
        try rawExec("""
        CREATE TABLE IF NOT EXISTS is_render_snapshots(
            scope TEXT NOT NULL,
            msg_index INTEGER NOT NULL,
            user_text_sha256 TEXT NOT NULL,
            block TEXT NOT NULL,
            resolution_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY(scope, msg_index, user_text_sha256));
        """)
    }

    /// Write-through of one frozen occurrence. The block is the verbatim
    /// rendered original (stale hits included); re-rendering from current IS
    /// items would fork the chain. UPSERT: `refresh` replaces the same key.
    public func saveRenderSnapshot(
        scope: String, index: Int, userTextSHA256: String,
        block: String, resolutionJSON: String
    ) throws {
        try ensureRenderSnapshotSchema()
        try execBinding("""
        INSERT INTO is_render_snapshots(
            scope, msg_index, user_text_sha256, block, resolution_json, created_at)
        VALUES(?,?,?,?,?,?)
        ON CONFLICT(scope, msg_index, user_text_sha256) DO UPDATE SET
            block=excluded.block, resolution_json=excluded.resolution_json,
            created_at=excluded.created_at;
        """) { stmt in
            try bind(stmt, 1, scope)
            try bind(stmt, 2, Int64(index))
            try bind(stmt, 3, userTextSHA256)
            try bind(stmt, 4, block)
            try bind(stmt, 5, resolutionJSON)
            try bind(stmt, 6, Self.stamp(Date()))
        }
        // ponytail: trim on every save; O(budget) scan at research-mode write rate.
        try execBinding("""
        DELETE FROM is_render_snapshots WHERE rowid NOT IN (
            SELECT rowid FROM is_render_snapshots
            ORDER BY rowid DESC LIMIT ?);
        """) { stmt in
            try bind(stmt, 1, Int64(Self.renderSnapshotRowBudget))
        }
    }

    /// The durable row for one occurrence, or nil. A missing table (no write
    /// ever happened) throws and the ledger treats it as a miss: fail-open.
    public func loadRenderSnapshot(
        scope: String, index: Int, userTextSHA256: String
    ) throws -> (block: String, resolutionJSON: String)? {
        let stmt = try prepare("""
        SELECT block, resolution_json FROM is_render_snapshots
        WHERE scope=? AND msg_index=? AND user_text_sha256=?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, scope)
        try bind(stmt, 2, Int64(index))
        try bind(stmt, 3, userTextSHA256)
        guard try stepRowOrDone(stmt),
            let block = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
            let json = sqlite3_column_text(stmt, 1).map({ String(cString: $0) })
        else { return nil }
        return (block, json)
    }
}
