import Foundation

/// The product-side closed loop: ES defines a demand, IS resolves it against the
/// settled physical index and the chat store, the result is settled and bound,
/// and the advancing execution state records the settlement it was derived from.
///
/// This type composes the existing authorities; it does not add a second
/// validation path. Retrieval is digest-verified, settlement of model output
/// still goes through `SettlementAuthority`, and every write lands in the
/// same SQLite store the app already treats as authoritative.
public struct InformationLoop {

    public let database: ESISDatabase

    public init(database: ESISDatabase) {
        self.database = database
    }

    // MARK: - Demand

    public struct Demand: Sendable {
        public var stateID: String?
        public var sessionID: String?
        /// The request this retrieval belongs to. It decides the demand's
        /// lifecycle, never what is retrievable: an identical question asked by
        /// two requests is two demands over the same shared knowledge.
        public var requestIdentity: String?
        public var query: String
        /// Empty means every registered root.
        public var rootIDs: [String]
        public var includeChat: Bool
        /// Empty means every eligible committed session in this personal space.
        public var chatSessionIDs: [String]
        /// Items that are already part of the live turn and must not be fed back
        /// as retrieved context (e.g. the user message being answered).
        public var excludeItemIDs: Set<String>
        public var limit: Int

        public init(stateID: String? = nil, sessionID: String? = nil,
                    requestIdentity: String? = nil, query: String,
                    rootIDs: [String] = [],
                    includeChat: Bool = true, chatSessionIDs: [String] = [],
                    excludeItemIDs: Set<String> = [], limit: Int = 40) {
            self.stateID = stateID
            self.sessionID = sessionID
            self.requestIdentity = requestIdentity
            self.query = query
            self.rootIDs = rootIDs
            self.includeChat = includeChat
            self.chatSessionIDs = chatSessionIDs
            self.excludeItemIDs = excludeItemIDs
            self.limit = limit
        }
    }

    public struct Item: Codable, Equatable, Sendable {
        public let itemID: String
        public let kind: String
        public let locator: String
        public let lineNo: Int
        public let lineText: String
        public let sourceSHA256: String
        public let rootID: String?
        public let relativePath: String?
        /// Set only for a summary distilled from a derived consumption. The item
        /// is citable, but not as independent generation evidence.
        public let derivationType: String?
        public let sourceSettlementID: String?

        public init(itemID: String, kind: String, locator: String,
                    lineNo: Int, lineText: String, sourceSHA256: String,
                    rootID: String? = nil, relativePath: String? = nil,
                    derivationType: String? = nil,
                    sourceSettlementID: String? = nil) {
            self.itemID = itemID
            self.kind = kind
            self.locator = locator
            self.lineNo = lineNo
            self.lineText = lineText
            self.sourceSHA256 = sourceSHA256
            self.rootID = rootID
            self.relativePath = relativePath
            self.derivationType = derivationType
            self.sourceSettlementID = sourceSettlementID
        }
    }

    public struct Resolution: Equatable, Sendable {
        public let demandID: String
        public let stateID: String?
        public let reused: Bool
        public let hits: [Item]
        public let inputDigest: String
        public let resultSHA256: String
        public let retrievalSettlementID: String
        public let itemIDs: [String]
        /// Settled rows whose source bytes no longer match their digest. They are
        /// excluded from hits and force a new demand instead of a silent reuse.
        public let staleItemIDs: [String]
        /// 这些关键词没走索引：trigram 需要 3 个字符，1–2 字的词回落 LIKE 全扫。
        /// 空数组 = 本次全部关键词都走了索引。它是给人看的路况，不是命中质量。
        public let unindexedTerms: [String]

        public var isEmpty: Bool { hits.isEmpty }

        public init(demandID: String, stateID: String?, reused: Bool,
                    hits: [Item], inputDigest: String, resultSHA256: String,
                    retrievalSettlementID: String, itemIDs: [String],
                    staleItemIDs: [String], unindexedTerms: [String] = []) {
            self.demandID = demandID
            self.stateID = stateID
            self.reused = reused
            self.hits = hits
            self.inputDigest = inputDigest
            self.resultSHA256 = resultSHA256
            self.retrievalSettlementID = retrievalSettlementID
            self.itemIDs = itemIDs
            self.staleItemIDs = staleItemIDs
            self.unindexedTerms = unindexedTerms
        }
    }

    private struct StoredResult: Codable {
        let schema: String
        let query: String
        let inputDigest: String
        let hitCount: Int
        let items: [Item]
        let staleItemIDs: [String]
        let includeChat: Bool
        let evaluatedAtUTC: String
        /// 可选：老结果没有这个字段，解码成 nil（不改动既有结果的 digest）。
        let unindexedTerms: [String]?
    }

    private static let resultSchema = "simigo.information-demand/v1"

    /// Resolve a demand against the current information space.
    ///
    /// A source can move between the read and the settlement commit. When that
    /// happens the database refuses the whole write (no result, no bindings),
    /// because a binding written after the invalidation pass would never be
    /// reached by it. The refusal is not repaired here by compensation: the
    /// request is simply re-executed against the revision that is now there.
    public func resolve(_ demand: Demand) throws -> Resolution {
        var attempt = 0
        while true {
            do {
                return try resolveOnce(demand)
            } catch let error as ESISDatabase.InformationDemandError {
                guard case .sourceRevisionChanged = error, attempt < 2 else { throw error }
                attempt += 1
            } catch let error as ESISDatabase.DatabaseError {
                // A source can be atomically replaced or edited while its bytes
                // are being read. The database refuses that read; replay the
                // complete demand against the new source, at most twice. If it
                // remains unstable, surface the typed error rather than serving
                // a partial or unverified result.
                guard case .sourceChangedWhileBeingRead = error, attempt < 2 else {
                    throw error
                }
                attempt += 1
            }
        }
    }

    private func resolveOnce(_ demand: Demand) throws -> Resolution {
        let query = demand.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(demand.limit, 200))
        guard !query.isEmpty else {
            return Resolution(
                demandID: "", stateID: demand.stateID, reused: false, hits: [],
                inputDigest: "", resultSHA256: "", retrievalSettlementID: "",
                itemIDs: [], staleItemIDs: [])
        }

        var inputs: [String] = []
        var stale: [String] = []
        var scored: [(item: Item, score: Int)] = []
        var addresses: [ESISDatabase.InformationInput] = []

        // Retain only a bounded top-K set while still scanning every source for
        // the complete demand/dependency basis. Sorting the whole candidate
        // population before prefix(limit) made a single match-heavy file able
        // to allocate millions of Item values even though at most 200 escape.
        func outranks(
            _ lhs: (item: Item, score: Int),
            _ rhs: (item: Item, score: Int)
        ) -> Bool {
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.item.itemID != rhs.item.itemID {
                return lhs.item.itemID < rhs.item.itemID
            }
            return lhs.item.lineNo < rhs.item.lineNo
        }
        func appendScored(_ item: Item, score: Int) {
            scored.append((item, score))
            // Compact in batches to keep append overhead low. The retained
            // population never exceeds 2 * limit + 1, and final ordering is
            // identical to sorting the complete population.
            if scored.count > limit * 2 {
                scored.sort(by: outranks)
                if scored.count > limit {
                    scored.removeLast(scored.count - limit)
                }
            }
        }
        let keywords = Self.keywords(in: query)
        // 路况：哪些关键词用不上 trigram 索引（1–2 字）。它只描述这一次查询
        // 走了哪条路，不进 demand 身份——同一 query 的命中不会因为这条路而变。
        let unindexedTerms = keywords.filter { !ESISDatabase.isFTSEligible($0) }
        // Every citation below is a line that must mention a keyword, and the
        // case-insensitive Unicode scan that decides it is the most expensive
        // thing in this function: measured 2026-11-09 on the live space, 38 MB
        // of chat over 806k lines cost 36 s with it and 0.2 s baselined by the
        // byte-level skip. The skip folds ASCII only, so it is exact for
        // caseless scripts (CJK, the bulk here) and for ASCII text; the citation
        // itself is still sliced by `citationSnippet`.
        let foldedKeywords = keywords.map { Array($0.utf8).map(Self.foldedASCII) }
        let requestedRootIDs = Array(Set(demand.rootIDs)).sorted()
        let requestedChatSessionIDs = Array(Set(demand.chatSessionIDs)).sorted()
        let rootScopeJSON = String(
            decoding: try JSONEncoder.sorted.encode(requestedRootIDs), as: UTF8.self)
        // The demand's lifecycle identity. A retry of the same request must land
        // on the same demand; two unrelated requests without a session must not,
        // or one would supersede the other. Knowledge itself stays shared: this
        // only keys the demand row, never what is retrievable.
        let declaredRequest = demand.requestIdentity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestIdentity: String
        if let declaredRequest, !declaredRequest.isEmpty {
            requestIdentity = "explicit:\(declaredRequest)"
        } else if let session = demand.sessionID, !session.isEmpty {
            requestIdentity = "session:\(session)"
        } else if let state = demand.stateID, !state.isEmpty {
            requestIdentity = "state:\(state)"
        } else {
            requestIdentity = "call:\(UUID().uuidString.lowercased())"
        }

        // Physical information: read the locator, verify the settled digest.
        for row in try database.settledFileRows(rootIDs: requestedRootIDs) {
            let identity = "file:\(row.rootID)/\(row.relativePath)"
            guard !demand.excludeItemIDs.contains(identity) else { continue }
            let text: String
            do {
                text = try database.searchableFileText(row)
            } catch ESISDatabase.DatabaseError.staleExternalSource {
                stale.append(identity)
                continue
            }
            inputs.append("\(identity)=\(row.digest)")
            if let address = try database.latestIndexObjectID(identity: identity) {
                addresses.append(.init(itemID: identity, contentAddress: address))
            }
            // One byte scan over the whole file decides whether it can cite at
            // all. Splitting 7 MB of settled text into 54k lines cost more than
            // the scan itself (measured 2026-11-10 on the live space: split
            // 69 ms against 14 ms of scanning), and most files cannot cite a
            // given query — so they are not split. 54k scanned lines became
            // 15k inside the same resolve.
            guard Self.firstMatch(in: text[...], foldedKeywords) != nil else { continue }
            for (idx, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
            where !line.isEmpty {
                guard let snippet = Self.citationSnippet(
                    in: line, folded: foldedKeywords, keywords: keywords)
                else { continue }
                appendScored(Item(
                    itemID: identity, kind: "file", locator: identity,
                    lineNo: idx + 1, lineText: snippet.text,
                    sourceSHA256: row.digest,
                    rootID: row.rootID, relativePath: row.relativePath), score: snippet.score)
            }
        }

        // Chat information: stored messages are entries in the same space. The
        // scope is represented by one watermark instead of one dependency per
        // row — the personal space holds thousands of committed rows, and a
        // per-row edge would append thousands of revisions on every new demand
        // while chat bytes themselves never change. The watermark still makes
        // a changed scope produce a different demand instead of a silent reuse.
        var chatScope = "chat-scope=off"
        if demand.includeChat {
            // Excluded rows are outside this demand input basis, not merely
            // outside rendered snippets. An answer's own question/answer rows
            // must not make its exact repeat look stale.
            //
            // The scope is a digest over every eligible row's identity and
            // settled digest, not a count/tail watermark: two exclusion sets
            // can drop different older rows while leaving both the count and
            // the tail identical, and those are different retrieval scopes.
            // Measured on identity and digest alone, so the demand's identity
            // field still sees every committed line while the chat bytes stay
            // in SQLite.
            let scopedChatRows = try database.chatScopeRows(
                sessionIDs: requestedChatSessionIDs)
                .filter { !demand.excludeItemIDs.contains($0.itemID) }
            let scopeSessions = requestedChatSessionIDs.isEmpty
                ? "all" : requestedChatSessionIDs.joined(separator: ",")
            let chatBasis = scopedChatRows
                .map { "\($0.itemID)=\($0.contentSHA256)" }
                .sorted()
                .joined(separator: "\n")
            chatScope = "chat-scope=sessions=\(scopeSessions)"
                + ";count=\(scopedChatRows.count)"
                + ";basis=\(NativeSHA256.hexDigest(Data(chatBasis.utf8)))"
            // Candidates, not filters: a row that mentions no term is dropped in
            // C before its bytes are ever materialized. Every row kept still has
            // to be sliced by `citationSnippet` below.
            for row in try database.chatIndexRows(
                sessionIDs: requestedChatSessionIDs, matchingAny: keywords)
            {
                guard !demand.excludeItemIDs.contains(row.itemID) else { continue }
                guard NativeSHA256.hexDigest(Data(row.content.utf8)) == row.contentSHA256
                else { continue }
                for (idx, line) in row.content
                    .split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where !line.isEmpty {
                    // The SQL filter admits a message, not a line: a long
                    // message keeps every line it has and `citationSnippet`
                    // copies each one before it decides. The byte scan below
                    // decides the same question and is what the snippet builder
                    // starts with, so a line dropped here could not have cited
                    // anyway.
                    guard Self.firstMatch(in: line, foldedKeywords) != nil
                    else { continue }
                    guard let snippet = Self.citationSnippet(
                        in: line, folded: foldedKeywords, keywords: keywords)
                    else { continue }
                    appendScored(Item(
                        itemID: row.itemID, kind: "chat",
                        locator: "session:\(row.sessionID)#\(row.messageID)",
                        lineNo: idx + 1, lineText: snippet.text,
                        sourceSHA256: row.contentSHA256), score: snippet.score)
                }
            }
        }

        // Turn digests: one line per round saying what the round was for. They
        // are an index over chat, so they follow the same switch: a caller that
        // asked for no chat does not get chat digests either. The cited bytes
        // stay the round's own text — the digest only decides that this round
        // is worth opening.
        if demand.includeChat {
            for row in try database.turnDigestRows(matchingAny: keywords) {
                let identity = "turn:\(row.sessionID)/\(row.turnIndex)"
                guard !demand.excludeItemIDs.contains(identity) else { continue }
                let digestSHA = NativeSHA256.hexDigest(Data(row.digest.utf8))
                inputs.append("\(identity)=\(digestSHA)")
                if let address = row.answerObjectID {
                    addresses.append(.init(itemID: identity, contentAddress: address))
                }
                guard let snippet = Self.citationSnippet(
                    in: row.digest[...], folded: foldedKeywords, keywords: keywords)
                else { continue }
                appendScored(Item(
                    itemID: identity, kind: "turn",
                    locator: "session:\(row.sessionID)#t\(row.turnIndex)",
                    lineNo: 1, lineText: snippet.text,
                    sourceSHA256: digestSHA), score: snippet.score)
            }
        }

        // Settled conclusions: the distilled summary of a still-valid settlement
        // is information in its own right. This is how a later execution state
        // reuses an earlier result without re-reading the sources it came from;
        // invalidated or retrieval-only settlements are never citable here.
        for row in try database.citableSettlementSummaries(sessionID: demand.sessionID) {
            let identity = "settlement:\(row.settlementID)"
            guard !demand.excludeItemIDs.contains(identity) else { continue }
            inputs.append("\(identity)=\(row.summarySHA256)")
            if let address = try database.latestIndexObjectID(
                identity: "settlement-summary:\(row.settlementID)")
            {
                addresses.append(.init(itemID: identity, contentAddress: address))
            }
            // Match and cite the settled summary itself: the demand's query is
            // metadata about what was asked, not part of the settled payload,
            // so a query-only term must not pull in an unrelated summary.
            guard let snippet = Self.citationSnippet(
                in: row.summary[...], folded: foldedKeywords, keywords: keywords)
            else { continue }
            appendScored(Item(
                itemID: identity, kind: "settlement",
                locator: "settlement:\(row.settlementID)#summary",
                lineNo: 1, lineText: snippet.text,
                sourceSHA256: row.summarySHA256,
                derivationType: row.derivationType,
                sourceSettlementID: row.sourceSettlementID), score: snippet.score)
        }

        // Deterministic ranking: more distinct keywords first, then stable
        // identity order. The same inputs therefore always settle the same list.
        scored.sort(by: outranks)
        let items = Array(scored.prefix(limit).map(\.item))

        let rootScope = requestedRootIDs.isEmpty ? "all" : rootScopeJSON
        let canonical = "query=\(query)\n"
            + "request=\(requestIdentity)\n"
            + "limit=\(limit)\n"
            + "root-scope=\(rootScope)\n"
            + "keywords=" + keywords.sorted().joined(separator: " ")
            + "\n" + inputs.sorted().joined(separator: "\n")
            + "\n" + chatScope
            + "\nstale=" + stale.sorted().joined(separator: "\n")
        let demandID = NativeSHA256.hexDigest(Data(canonical.utf8))

        if let row = try database.informationDemand(demandID: demandID),
            row.state == "RESOLVED" || row.state == "ADVANCED",
            let stored = try database.informationRetrievalPayload(demandID: demandID),
            let decoded = try? JSONDecoder().decode(StoredResult.self, from: stored),
            decoded.inputDigest == demandID
        {
            return Resolution(
                demandID: demandID, stateID: demand.stateID, reused: true,
                hits: decoded.items,
                inputDigest: demandID,
                resultSHA256: NativeSHA256.hexDigest(stored),
                retrievalSettlementID: row.retrievalSettlementID ?? "",
                itemIDs: decoded.items.map(\.itemID),
                staleItemIDs: decoded.staleItemIDs,
                unindexedTerms: decoded.unindexedTerms ?? unindexedTerms)
        }

        let evaluatedAt = Self.utcStamp(Date())
        let payload = try JSONEncoder.sorted.encode(StoredResult(
            schema: Self.resultSchema, query: query, inputDigest: demandID,
            hitCount: items.count, items: items, staleItemIDs: stale,
            includeChat: demand.includeChat, evaluatedAtUTC: evaluatedAt,
            unindexedTerms: unindexedTerms))

        // Only a source that can change in place gets a binding. A demand
        // resolved from chat turns or from the collection bridge has nothing to
        // bind, and that absence is a property of the source, not a gap in the
        // evidence: chat rows are append-only and enter the basis through the
        // scope watermark, so a changed conversation produces a different demand
        // instead of a stale one. An information result and its settlement are
        // therefore independent of where they came from; identity is a separate
        // question, asked only where the artefact is model-specific.
        var sourceBindings: [ESISDatabase.SourceBinding] = []
        var boundSources = Set<String>()
        for hit in items where hit.kind == "file" {
            guard let sourceRoot = hit.rootID, let sourcePath = hit.relativePath else {
                // A file hit without a locator cannot be bound, so no later
                // change could ever withdraw it. Fail here rather than leave a
                // result that is silently permanent.
                throw ESISDatabase.DatabaseError.sql(
                    "information-loop: file hit without a locator: \(hit.itemID)")
            }
            guard boundSources.insert("\(sourceRoot)/\(sourcePath)").inserted else { continue }
            // The digest the citation was verified against, not the digest the
            // index holds at commit time: the write must prove the two are the
            // same, and refuse the result when they are not.
            sourceBindings.append(.init(
                rootID: sourceRoot, relativePath: sourcePath,
                binding: "content", expectedDigest: hit.sourceSHA256))
        }

        // A cited settlement is a dependency, not a source: it carries no bytes
        // to bind, but if the cited result stops being eligible then this answer
        // no longer follows from it. Without the edge a settlement-to-settlement
        // citation is invisible to the invalidation closure.
        var citedSettlements: [String] = []
        var seenCitations = Set<String>()
        for hit in items where hit.kind == "settlement" {
            // `sourceSettlementID` is only set for derived consumptions; a plain
            // summary leaves it empty, and an empty string would otherwise stop
            // the fallback below from ever running.
            let declared = hit.sourceSettlementID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cited = (declared?.isEmpty == false)
                ? declared!
                : String(hit.itemID.dropFirst("settlement:".count))
            guard !cited.isEmpty, seenCitations.insert(cited).inserted else { continue }
            citedSettlements.append(cited)
        }

        // One transaction records the result, every source binding and every
        // citation edge, re-verifying each source revision and each upstream
        // settlement under the same write lock. Splitting these three writes
        // left a window where a source update could invalidate an empty closure
        // and the bindings would land behind it.
        let commit = try database.recordInformationRetrieval(
            .init(
                demandID: demandID, stateID: demand.stateID,
                sessionID: demand.sessionID, requestIdentity: requestIdentity,
                query: query,
                rootIDs: demand.rootIDs, includeChat: demand.includeChat,
                inputDigest: demandID, payload: payload,
                hitCount: items.count, itemIDs: items.map(\.itemID),
                inputs: addresses,
                sourceBindings: sourceBindings,
                citedSettlements: citedSettlements))

        return Resolution(
            demandID: demandID, stateID: demand.stateID, reused: false,
            hits: items, inputDigest: demandID,
            resultSHA256: commit.resultSHA256,
            retrievalSettlementID: commit.retrievalSettlementID,
            itemIDs: items.map(\.itemID), staleItemIDs: stale,
            unindexedTerms: unindexedTerms)
    }

    /// A bounded, citable context block. Only verified line fragments are
    /// injected; source digests stay in the IS, not in the prompt.
    public func contextBlock(_ resolution: Resolution, maxCharacters: Int = 4000) -> String {
        guard !resolution.hits.isEmpty, maxCharacters > 0 else { return "" }
        var lines = [
            "[Information Space]",
            "已结算并逐条校验摘要的来源片段"
                + "（file = 注册目录定位符，chat = 已落库会话，settlement = 已结算结论）:",
        ]
        for hit in resolution.hits {
            let provenance = hit.derivationType == "DERIVED_CONSUMPTION"
                ? " [derived:"
                    + (hit.sourceSettlementID.map { "settlement:\($0)" } ?? "unknown")
                    + "]"
                : ""
            let line = "- \(hit.itemID)\(provenance):\(hit.lineNo): \(hit.lineText)"
            if lines.joined(separator: "\n").count + line.count > maxCharacters { break }
            lines.append(line)
        }
        return lines.count > 2 ? lines.joined(separator: "\n") : ""
    }

    // MARK: - Answer reuse gate

    public struct ReusableAnswer: Equatable, Sendable {
        public let text: String
        public let settlementID: String
        public let demandID: String
        public let sourceStateID: String
        public let sessionID: String
        public let query: String
    }

    /// Inputs written by a published answer are not new knowledge. Exclude
    /// every exact answer summary and only paired question/answer rows that
    /// correspond to a settled payload. Other sessions remain in the watermark.
    public func answerReuseExclusions(sessionID: String, query: String) throws -> Set<String> {
        let answered = try database.answeredDemands(sessionID: sessionID, query: query)
        guard !answered.isEmpty else { return [] }

        var excluded = Set(answered.map { "settlement:\($0.answerSettlementID)" })
        var answerTexts: Set<String> = []
        for row in answered {
            guard let receipt = try database.settlementReceipt(row.answerSettlementID) else {
                throw ESISDatabase.DatabaseError.sql(
                    "answerReuseExclusions: answered demand references a missing settlement receipt")
            }
            let value = try JSONSerialization.jsonObject(with: receipt.payload)
            guard let object = value as? [String: Any],
                  let content = object["content"] as? String,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ESISDatabase.DatabaseError.sql(
                    "answerReuseExclusions: settlement receipt has no non-empty answer content")
            }
            answerTexts.insert(content)
        }

        var matchingQuestionID: String?
        for row in try database.chatIndexRows(sessionIDs: [sessionID]) {
            if row.role == "user" {
                matchingQuestionID = row.content == query ? row.itemID : nil
            } else if row.role == "assistant",
                let questionID = matchingQuestionID,
                answerTexts.contains(row.content)
            {
                // A turn may contain intermediate assistant/tool messages before
                // the published final text. Keep the question candidate until an
                // assistant row actually matches a settled answer payload or the
                // next user row starts a different turn.
                excluded.insert(questionID)
                excluded.insert(row.itemID)
            }
        }
        return excluded
    }
    /// Fail-closed gate for serving a turn without a model call. Every condition
    /// is required; any miss returns nil, which means "generate", never a
    /// best-effort answer:
    /// 1. this exact question was already ANSWERED in this information scope;
    /// 2. the answering settlement is still `valid`;
    /// 3. the retrieval settlement behind that demand is still `valid` — the
    ///    answer row carries no file edges of its own, so this dependency check
    ///    is what catches a source that moved since the answer was settled;
    ///
    /// Producer identity is deliberately NOT one of them. A settled answer is a
    /// semantic result, and the standing ruling (P2 §5.32) puts identity outside
    /// the universal admission condition: `producer.*` bindings are provenance,
    /// recorded for audit, and compared only when a task explicitly declares
    /// identity as a semantic dependency. Serving settled text to a different —
    /// or unnamed — engine is therefore allowed; the consuming model is recorded
    /// on the reuse row itself. `identity` stays in the signature because callers
    /// still carry it, not because this path consults it.
    public func reusableAnswer(
        sessionID: String,
        query: String,
        expectedDemandID: String? = nil,
        identity: SettlementIdentityBinding.Identity
    ) -> ReusableAnswer? {
        // A historical answer is reusable only for the exact demand resolved
        // for this turn. Callers without a current resolution fail closed.
        guard let expectedDemandID,
            !expectedDemandID.isEmpty,
            let answered = try? database.answeredDemand(
                sessionID: sessionID, query: query),
            answered.demandID == expectedDemandID
        else { return nil }
        guard let receipt = try? database.settlementReceipt(answered.answerSettlementID),
            receipt.validity == "valid" else { return nil }
        if let retrievalID = answered.retrievalSettlementID, !retrievalID.isEmpty {
            guard let retrieval = try? database.settlementReceipt(retrievalID),
                retrieval.validity == "valid" else { return nil }
        }
        guard let object = try? JSONSerialization.jsonObject(with: receipt.payload)
            as? [String: Any],
            let content = object["content"] as? String,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return ReusableAnswer(
            text: content, settlementID: answered.answerSettlementID,
            demandID: answered.demandID, sourceStateID: answered.stateID,
            sessionID: sessionID, query: query)
    }

    // MARK: - Query terms

    /// The question carried inside an agent request.
    ///
    /// Agent clients prepend their own envelope to the user turn — skills list,
    /// memory index, date — inside tagged blocks. Measured 2026-10-29 on a real
    /// managed request: the trailing user message was 16,276 bytes, the actual
    /// question was its last line, and term extraction read the envelope's first
    /// 12 tokens ("system", "reminder", "following", "skills", …). The top-30
    /// hits were greeting settlements and LUA sources; the question's own
    /// subject never contributed a term. The envelope is not information: it
    /// repeats on every turn of every session.
    ///
    /// Removal is by block, not by position, so a client that appends its
    /// envelope after the question is handled the same way. An unclosed block
    /// drops its tail, which is what the observed envelope does when truncated.
    public static func retrievalQuery(from text: String) -> String {
        var out = text
        for tag in ["system-reminder", "user_info", "environment_context"] {
            out = removingBlock(tag: tag, from: out)
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? text.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    private static func removingBlock(tag: String, from text: String) -> String {
        var out = text
        while let open = out.range(of: "<\(tag)", options: .caseInsensitive) {
            guard
                let close = out.range(
                    of: "</\(tag)>", options: .caseInsensitive,
                    range: open.lowerBound..<out.endIndex)
            else {
                out.removeSubrange(open.lowerBound..<out.endIndex)
                break
            }
            out.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return out
    }

    /// Terms used for line matching. A whole user question rarely appears
    /// verbatim in a document, so ASCII tokens are kept and CJK runs are
    /// expanded into overlapping bigrams. Ranking uses the number of distinct
    /// terms a line contains, which stays deterministic for settlement.
    ///
    /// The question sits at the END of a client envelope (measured 2026-10-29:
    /// a 16,276-byte user turn, the question on its last line), so terms are
    /// taken from the tail first. A wrapper that survives `retrievalQuery` then
    /// cannot own the term list. Ordering only decides which terms survive the
    /// limit — the canonical demand string sorts them, so settlement stays
    /// deterministic.
    static func keywords(in query: String, limit: Int = 12) -> [String] {
        let stop: Set<String> = [
            "什么", "是什", "怎么", "如何", "为什", "哪些", "多少", "是否",
            "可以", "我们", "这个", "那个", "请问", "以及", "然后", "就是",
            "the", "and", "for", "what", "how", "is", "are", "with",
        ]
        var out: [String] = []
        func add(_ value: String) {
            guard !value.isEmpty, !stop.contains(value), !out.contains(value) else { return }
            out.append(value)
        }
        // Terms break on punctuation, except the three separators that make a
        // written identifier one word: `ES-IS`, `PAPER_V1`, `a/b`. Splitting on
        // them used to turn `ES-IS` into `es` and `is`, and `is` matched most
        // English in the space — a six-term demand over the live space dragged
        // 38.8 MB of chat into the line scan and cost 12.7 s, with 130k lines
        // reaching the snippet builder (measured 2026-11-10). The same term set
        // over the same query keeps 7.0 MB.
        var separators = CharacterSet.whitespacesAndNewlines
        separators.formUnion(.punctuationCharacters)
        separators.remove(charactersIn: "-_/")
        for part in query.lowercased()
            .components(separatedBy: separators)
            .reversed()
        where !part.isEmpty {
            let chars = Array(part)
            if part.unicodeScalars.allSatisfy({ $0.isASCII }) || chars.count <= 2 {
                if chars.count >= 2 { add(part) }
            } else {
                add(part)
                var start = 0
                while start + 2 <= chars.count, out.count < limit {
                    add(String(chars[start..<(start + 2)]))
                    start += 1
                }
            }
            if out.count >= limit { break }
        }
        if out.isEmpty, !query.isEmpty {
            out.append(query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Array(out.prefix(limit))
    }

    /// ASCII-only case fold over raw UTF-8 bytes. Byte folding never inserts or
    /// removes a byte, so a match found here has the same offsets as the text
    /// the citation is sliced from.
    @inline(__always)
    private static func foldedASCII(_ byte: UInt8) -> UInt8 {
        (byte >= 0x41 && byte <= 0x5A) ? byte &+ 0x20 : byte
    }

    /// Byte offset of the earliest position where any keyword can match, or nil
    /// when the line mentions none. This is the only scan a line pays before the
    /// citation is built: 806k chat lines over 38 MB cost 0.9 s here and 36 s
    /// when the same question is asked of ICU per line (measured 2026-11-09).
    ///
    /// Boundary: this folds ASCII case and nothing else. A non-ASCII character
    /// that case-folds onto an ASCII letter (Kelvin sign onto `k`, long s onto
    /// `s`) is not found here, so a line whose only match would be such a
    /// character yields no citation. The failure mode is a missing citation,
    /// never a fabricated one.
    private static func firstMatch(in line: Substring, _ foldedKeywords: [[UInt8]]) -> Int? {
        line.utf8.withContiguousStorageIfAvailable {
            Self.firstMatch($0, foldedKeywords)
        } ?? Self.firstMatch(Array(line.utf8), foldedKeywords)
    }

    /// The byte scan itself. `C.Index == Int` keeps the inner arithmetic free of
    /// collection index overhead on both the contiguous view and the fallback.
    private static func firstMatch<C: RandomAccessCollection>(
        _ bytes: C, _ foldedKeywords: [[UInt8]]
    ) -> Int? where C.Element == UInt8, C.Index == Int {
        let start = bytes.startIndex
        var best: Int?
        for keyword in foldedKeywords {
            guard let first = keyword.first, keyword.count <= bytes.count else { continue }
            let last = start + bytes.count - keyword.count
            var cursor = start
            while cursor <= last, best.map({ cursor < $0 }) ?? true {
                if Self.foldedASCII(bytes[cursor]) == first {
                    var probe = cursor + 1
                    var matched = 1
                    while matched < keyword.count,
                        Self.foldedASCII(bytes[probe]) == keyword[matched] {
                        probe += 1
                        matched += 1
                    }
                    if matched == keyword.count {
                        best = cursor
                        break
                    }
                }
                cursor += 1
            }
        }
        return best
    }

    /// A citation must contain the match that justified it, so scoring and the
    /// quoted text come from the same bounded window: the snippet is centred on
    /// the first keyword occurrence and every counted keyword is visible in it.
    /// Measured 2026-10-30: matching the whole 2,447-character rollout line and
    /// quoting its 240-character prefix injected text that never contained the
    /// query term at all.
    private static func citationSnippet(
        in line: Substring, folded: [[UInt8]], keywords: [String], maxLength: Int = 240
    ) -> (text: String, score: Int)? {
        let text = String(line)
        // The match is located on UTF-8 bytes and only then mapped back to a
        // character offset: asking ICU for it cost 1.68 s on 405 surviving file
        // lines (2.25 MB) where the byte scan costs nothing next to the slicing.
        guard let byteHit = Self.firstMatch(in: line, folded),
            let utf8Index = text.utf8.index(
                text.utf8.startIndex, offsetBy: byteHit, limitedBy: text.utf8.endIndex),
            let hit = String.Index(utf8Index, within: text)
        else { return nil }
        let total = text.count
        let hitOffset = text.distance(from: text.startIndex, to: hit)
        // Context before the match, clamped so the window never runs past the end.
        let startOffset = max(0, min(hitOffset - 80, max(0, total - maxLength)))
        let endOffset = min(total, startOffset + maxLength)
        var snippet = String(text[
            text.index(text.startIndex, offsetBy: startOffset)
                ..< text.index(text.startIndex, offsetBy: endOffset)])
        if startOffset > 0 { snippet = "…" + snippet }
        if endOffset < total { snippet += "…" }
        let score = keywords.reduce(0) {
            $0 + (snippet.localizedCaseInsensitiveContains($1) ? 1 : 0)
        }
        return (snippet, score)
    }

    // MARK: - Advancement

    public struct TurnSettlement: Equatable, Sendable {
        public let settlementID: String
        /// The execution state the settlement belongs to. On an idempotent reuse
        /// this is the existing state: the requested state was never created,
        /// because a replay must not manufacture a second execution.
        public let stateID: String
        public let advancementID: String
        public let reused: Bool
    }

    /// The contract used for a chat turn: the whole generated message is the
    /// result. It declares structure, not semantics — the gate still normalizes
    /// and rejects empty output, and the payload is digest-sealed.
    public static let chatResultContractJSON = Data("""
    {"schema_version":"simigo.result-contract/v1",\
    "fields":{"content":{"pattern":"(?s)^([\\\\s\\\\S]+)$","capture_group":1,\
    "type":"string","normalize":"trim","nonempty":true}},\
    "constraints":[]}
    """.utf8)

    /// Settle a model turn, create its execution state, and record the
    /// advancement — one authoritative transaction. `resolution` may be nil when
    /// the turn ran without retrieved information. `summaryQuery` is the demand
    /// text this turn answered: it is recorded with the post-settlement summary
    /// so a later demand can find the distilled conclusion.
    ///
    /// `sourceIdentity` and `operationKey` are forwarded to the common
    /// settlement entrance: a replay of the same declared submission returns the
    /// existing settlement instead of creating a second one, and no demand is
    /// advanced twice.
    @discardableResult
    public func settleTurn(
        generatedText: String,
        resolution: Resolution?,
        stateID: String,
        parentStateID: String?,
        position: Int,
        modelIdentity: String,
        identity: SettlementIdentityBinding.Identity,
        sessionID: String?,
        summaryQuery: String? = nil,
        actions: [String] = ["generate"],
        contractJSON: Data? = nil,
        declaredDependencies: [ESISDatabase.DeclaredDependency] = [],
        sourceIdentity: ESISDatabase.DeclaredSourceIdentity? = nil,
        operationKey: String? = nil,
        settledAt: Date = Date(),
        chatTurn: ESISDatabase.ChatTurnCommit? = nil
    ) throws -> TurnSettlement {
        let settled = try SettlementAuthority.authorize(
            generatedText: generatedText,
            contractJSON: contractJSON ?? Self.chatResultContractJSON,
            verifiedBindings: [:],
            settledAt: settledAt)
        let content = Self.content(of: settled)

        let advanced = resolution.flatMap { res -> ESISDatabase.InformationAdvancementPlan? in
            guard !res.demandID.isEmpty, !res.retrievalSettlementID.isEmpty else { return nil }
            return .init(
                demandID: res.demandID, stateID: stateID,
                retrievalSettlementID: res.retrievalSettlementID,
                actions: actions, result: settled.validatedPayload)
        }
        let commit = try database.recordNativeSettlementWithIdentityAndAdvancement(
            settled,
            stateID: stateID,
            identity: identity,
            childState: .init(
                id: stateID, parentID: parentStateID, modelIdentity: modelIdentity,
                position: position, continuationID: UUID().uuidString,
                anchor: settled.payloadDigest, createdAt: settledAt,
                nextInput: content),
            advancement: advanced,
            declaredDependencies: declaredDependencies,
            sourceIdentity: sourceIdentity,
            operationKey: operationKey,
            chatTurn: chatTurn,
            chatSessionID: sessionID,
            chatModelIdentity: modelIdentity)
        // Post-settlement distillation: a separate, additive write. The
        // settlement above is already durable, so a summary failure never
        // invalidates the settled result. A reused settlement already has its
        // summary from the original settle; it is healed only when missing, so
        // a replay never rewrites the original distillation.
        let settlementUUID = commit.settlementID.uuidString
        let hasSummary = (try? database.settlementSummary(settlementID: settlementUUID))
            .flatMap { $0 } != nil
        if !commit.reused || !hasSummary {
            _ = try? database.recordSettlementSummary(
                settlementID: settlementUUID,
                sessionID: sessionID,
                query: summaryQuery ?? "",
                settledAt: settledAt)
        }
        return TurnSettlement(
            settlementID: settlementUUID,
            stateID: commit.stateID,
            advancementID: commit.advancementID ?? "",
            reused: commit.reused)
    }

    static func content(of settled: SettlementAuthority.SettledResult) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: settled.validatedPayload)
            as? [String: Any] else { return "" }
        if let direct = obj["content"] as? String { return direct }
        return ""
    }

    private static func utcStamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
