import CryptoKit
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
        /// Stable logical Agent thread/task identity. Unlike sessionID this
        /// survives reconnects and is supplied by legacy clients on each call.
        public var continuityID: String?
        /// Stable ES/IS namespace: owner for first-party paths, bearer digest for external MCP.
        public var clientIdentityID: String?
        /// The request this retrieval belongs to. It decides the demand's
        /// lifecycle, never what is retrievable: an identical question asked by
        /// two requests is two demands over the same shared knowledge.
        public var requestIdentity: String?
        public var query: String
        /// Empty means every registered root.
        public var rootIDs: [String]
        /// Host-file roots are owner-only unless an explicit future grant exists.
        public var includeRoots: Bool
        public var includeChat: Bool
        /// Empty means every eligible committed session in this personal space.
        public var chatSessionIDs: [String]
        /// Items that are already part of the live turn and must not be fed back
        /// as retrieved context (e.g. the user message being answered).
        public var excludeItemIDs: Set<String>
        public var limit: Int

        public init(stateID: String? = nil, sessionID: String? = nil,
                    continuityID: String? = nil,
                    clientIdentityID: String? = ESISDatabase.ownerNamespace,
                    requestIdentity: String? = nil, query: String,
                    rootIDs: [String] = [], includeRoots: Bool = true,
                    includeChat: Bool = true, chatSessionIDs: [String] = [],
                    excludeItemIDs: Set<String> = [], limit: Int = 40) {
            self.stateID = stateID
            self.sessionID = sessionID
            self.continuityID = continuityID
            self.clientIdentityID = clientIdentityID
            self.requestIdentity = requestIdentity
            self.query = query
            self.rootIDs = rootIDs
            self.includeRoots = includeRoots
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
        public let sourceItemKey: String?
        public let sourceItemKeyword: String?
        /// Set only for a summary distilled from a derived consumption. The item
        /// is citable, but not as independent generation evidence.
        public let derivationType: String?
        public let sourceSettlementID: String?

        public init(itemID: String, kind: String, locator: String,
                    lineNo: Int, lineText: String, sourceSHA256: String,
                    rootID: String? = nil, relativePath: String? = nil,
                    sourceItemKey: String? = nil, sourceItemKeyword: String? = nil,
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
            self.sourceItemKey = sourceItemKey
            self.sourceItemKeyword = sourceItemKeyword
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
        /// Sources that could not be opened for this call. This is transient:
        /// it is not part of the settled payload or dependency validity ledger.
        public let unavailableSourceIDs: [String]
        /// Sources whose current bytes no longer match the settled file revision.
        /// Their current value must be re-indexed/observed before being cited.
        public let changedSourceIDs: [String]
        /// Compatibility projection for callers that used the previous name.
        public var staleItemIDs: [String] { changedSourceIDs }
        /// 这些关键词没走索引：trigram 需要 3 个字符，1–2 字的词回落 LIKE 全扫。
        /// 空数组 = 本次全部关键词都走了索引。它是给人看的路况，不是命中质量。
        public let unindexedTerms: [String]

        public var isEmpty: Bool { hits.isEmpty }

        public init(demandID: String, stateID: String?, reused: Bool,
                    hits: [Item], inputDigest: String, resultSHA256: String,
                    retrievalSettlementID: String, itemIDs: [String],
                    unavailableSourceIDs: [String] = [],
                    changedSourceIDs: [String] = [],
                    staleItemIDs: [String]? = nil,
                    unindexedTerms: [String] = []) {
            self.demandID = demandID
            self.stateID = stateID
            self.reused = reused
            self.hits = hits
            self.inputDigest = inputDigest
            self.resultSHA256 = resultSHA256
            self.retrievalSettlementID = retrievalSettlementID
            self.itemIDs = itemIDs
            self.unavailableSourceIDs = unavailableSourceIDs
            self.changedSourceIDs = staleItemIDs ?? changedSourceIDs
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

    private static let resultSchema = "simigo.information-demand/v3"

    /// Resolve a demand against the current information space.
    ///
    /// A source can move between the read and the settlement commit. When that
    /// happens the database refuses the whole write (no result, no bindings),
    /// because a binding written after the invalidation pass would never be
    /// reached by it. The refusal is not repaired here by compensation: the
    /// request is simply re-executed against the revision that is now there.
    private static func checkCancellation() throws {
        if withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) {
            throw CancellationError()
        }
    }

    public func resolve(_ demand: Demand) throws -> Resolution {
        try Self.checkCancellation()
        var scopedDemand = demand
        // Empty means every session inside the authenticated identity space.
        // Keep that logical scope stable in the demand basis, while resolving
        // its currently authorized concrete sessions for the carrier reads.
        // Explicit session lists are intersected with the same owner boundary.
        let chatScopeIsIdentityWide =
            scopedDemand.includeChat
            && scopedDemand.clientIdentityID != nil
            && scopedDemand.chatSessionIDs.isEmpty
        if scopedDemand.includeChat, let identity = scopedDemand.clientIdentityID {
            let ownedSessions = Set(try database.chatSessionIDs(clientIdentityID: identity))
            scopedDemand.chatSessionIDs = chatScopeIsIdentityWide
                ? Array(ownedSessions)
                : scopedDemand.chatSessionIDs.filter { ownedSessions.contains($0) }
        }
        var attempt = 0
        while true {
            try Self.checkCancellation()
            do {
                return try resolveOnce(
                    scopedDemand, chatScopeIsIdentityWide: chatScopeIsIdentityWide)
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

    private func resolveOnce(
        _ demand: Demand, chatScopeIsIdentityWide: Bool
    ) throws -> Resolution {
        try Self.checkCancellation()
        let query = demand.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(demand.limit, 200))
        guard !query.isEmpty else {
            return Resolution(
                demandID: "", stateID: demand.stateID, reused: false, hits: [],
                inputDigest: "", resultSHA256: "", retrievalSettlementID: "",
                itemIDs: [], staleItemIDs: [])
        }

        var fileInputs = StreamingSHA256()
        var chatScopeInputs = StreamingSHA256()
        var turnInputs = StreamingSHA256()
        var settlementInputs = StreamingSHA256()
        var changedInputs = StreamingSHA256()
        var unavailableSources: [String] = []
        var changedSources: [String] = []
        var scored: [(item: Item, score: Int)] = []

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
        let requestedRootIDs = demand.includeRoots
            ? Array(Set(demand.rootIDs)).sorted() : []
        let requestedChatSessionIDs = Array(Set(demand.chatSessionIDs)).sorted()
        // Empty arrays mean "all" to legacy carrier APIs. A scoped request with
        // no authorized sessions must therefore skip those APIs entirely.
        let shouldReadChat = demand.includeChat
            && (!requestedChatSessionIDs.isEmpty || demand.clientIdentityID == nil)
        // The demand's lifecycle identity. A retry of the same request must land
        // on the same demand; two unrelated requests without a session must not,
        // or one would supersede the other. Knowledge itself stays shared: this
        // only keys the demand row, never what is retrievable.
        let declaredRequest = demand.requestIdentity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestIdentity: String
        if let declaredRequest, !declaredRequest.isEmpty {
            requestIdentity = "explicit:\(declaredRequest)"
        } else if let continuity = demand.continuityID, !continuity.isEmpty {
            requestIdentity = "continuity:\(continuity)"
        } else if let session = demand.sessionID, !session.isEmpty {
            requestIdentity = "session:\(session)"
        } else if let state = demand.stateID, !state.isEmpty {
            requestIdentity = "state:\(state)"
        } else {
            requestIdentity = "call:\(UUID().uuidString.lowercased())"
        }

        // Item identity is scoped to this complete query keyword set, not
        // to the subset that happens to survive in an individual snippet. That
        // lets a verified re-read observe when an earlier item is no longer present.
        let sourceItemKeywordData = try JSONSerialization.data(
            withJSONObject: keywords.sorted(),
            options: [.sortedKeys, .withoutEscapingSlashes])
        let sourceItemKeywordJSON = String(
            decoding: sourceItemKeywordData, as: UTF8.self)
        let sourceItemKeywordIdentity = NativeSHA256.hexDigest(sourceItemKeywordData)
        // Ordinals disambiguate repeated matches for the same keyword scope in one source.
        var sourceItemOccurrences: [String: Int] = [:]
        var sourceItemScopes: [ESISDatabase.SourceItemScopeObservation] = []

        // Physical information: read one settled locator at a time, verify its
        // digest, and fold the complete source basis without retaining all rows.
        if demand.includeRoots {
            try database.forEachSettledFileRow(rootIDs: requestedRootIDs) { row in
                try Self.checkCancellation()
                let identity = "file:\(row.rootID)/\(row.relativePath)"
                guard !demand.excludeItemIDs.contains(identity) else { return }
                let text: String
                do {
                    text = try database.searchableFileText(row)
                } catch ESISDatabase.DatabaseError.sourceUnavailable {
                    unavailableSources.append(identity)
                    return
                } catch ESISDatabase.DatabaseError.staleExternalSource {
                    changedSources.append(identity)
                    changedInputs.appendRecord(identity)
                    return
                }
                fileInputs.appendRecord("\(identity)=\(row.digest)")
                var presentItemKeys: [String] = []
                // One byte scan over the whole file decides whether any item in
                // this keyword scope is present. A successful read with zero
                // matches is meaningful; unlike a missing/unavailable read it
                // can establish item absence in the write transaction.
                if Self.firstMatch(in: text[...], foldedKeywords) != nil {
                    for (idx, line) in text.split(
                        separator: "\n", omittingEmptySubsequences: false)
                        .enumerated()
                    where !line.isEmpty {
                        guard let snippet = Self.citationSnippet(
                            in: line, folded: foldedKeywords, keywords: keywords)
                        else { continue }
                        let occurrenceScope = NativeSHA256.hexDigest(Data(
                            "\(row.rootID)\n\(row.relativePath)\n\(sourceItemKeywordIdentity)".utf8))
                        let occurrence = sourceItemOccurrences[occurrenceScope, default: 0]
                        sourceItemOccurrences[occurrenceScope] = occurrence + 1
                        let itemKey = "scope-v2:\(sourceItemKeywordIdentity):\(occurrence)"
                        presentItemKeys.append(itemKey)
                        appendScored(Item(
                            itemID: identity, kind: "file", locator: identity,
                            lineNo: idx + 1, lineText: snippet.text,
                            sourceSHA256: row.digest,
                            rootID: row.rootID, relativePath: row.relativePath,
                            sourceItemKey: itemKey,
                            sourceItemKeyword: sourceItemKeywordJSON), score: snippet.score)
                    }
                }
                sourceItemScopes.append(.init(
                    rootID: row.rootID, relativePath: row.relativePath,
                    expectedDigest: row.digest,
                    keywordIdentity: sourceItemKeywordIdentity,
                    itemKeyword: sourceItemKeywordJSON,
                    presentItemKeys: presentItemKeys))
            }
    
        }

        // Chat information: stored messages are entries in the same space. The
        // scope is represented by one watermark instead of one dependency per
        // row — the personal space holds thousands of committed rows, and a
        // per-row edge would append thousands of revisions on every new demand
        // while chat bytes themselves never change. The watermark still makes
        // a changed scope produce a different demand instead of a silent reuse.
        var chatScopeCount = 0
        if shouldReadChat {
            // Hash the complete eligible identity/digest scope one row at a time.
            // Session identifiers remain an array in the final structured basis;
            // they are never joined with a delimiter.
            try database.forEachChatScopeRow(sessionIDs: requestedChatSessionIDs) { row in
                try Self.checkCancellation()
                guard !demand.excludeItemIDs.contains(row.itemID) else { return }
                chatScopeCount += 1
                chatScopeInputs.appendRecord("\(row.itemID)=\(row.contentSHA256)")
            }

            // Candidate message bodies are materialized one at a time. The SQL
            // predicate is still only a prefilter; the byte-level scan decides
            // whether a line can be cited.
            try database.forEachChatIndexRow(
                sessionIDs: requestedChatSessionIDs, matchingAny: keywords)
            { row in
                try Self.checkCancellation()
                guard !demand.excludeItemIDs.contains(row.itemID) else { return }
                guard NativeSHA256.hexDigest(Data(row.content.utf8)) == row.contentSHA256
                else {
                    // A candidate whose bytes disagree with its stored digest is
                    // not an ordinary non-match. Dropping it could preserve an
                    // old empty cache result when out-of-band bytes now contain
                    // the query but the scope watermark still carries the old hash.
                    throw ESISDatabase.DatabaseError.sourceChangedWhileBeingRead(
                        path: row.itemID)
                }
                for (idx, line) in row.content
                    .split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where !line.isEmpty {
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
        if shouldReadChat {
            try database.forEachTurnDigestRow(
                matchingAny: keywords,
                sessionIDs: demand.clientIdentityID == nil ? nil : requestedChatSessionIDs) { row in
                try Self.checkCancellation()
                let identity = "turn:\(row.sessionID)/\(row.turnIndex)"
                guard !demand.excludeItemIDs.contains(identity) else { return }
                let digestSHA = NativeSHA256.hexDigest(Data(row.digest.utf8))
                turnInputs.appendRecord("\(identity)=\(digestSHA)")
                guard let snippet = Self.citationSnippet(
                    in: row.digest[...], folded: foldedKeywords, keywords: keywords)
                else { return }
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
        // Every valid model-produced summary participates in the basis. Stream
        // without the legacy 200-row snapshot cap so an older matching conclusion
        // cannot disappear merely because newer summaries were added.
        try database.forEachCitableSettlementSummary(
            sessionID: demand.sessionID, clientIdentityID: demand.clientIdentityID) { row in
            try Self.checkCancellation()
            let identity = "settlement:\(row.settlementID)"
            guard !demand.excludeItemIDs.contains(identity) else { return }
            // A summary whose provenance no longer matches the observed bytes
            // is dropped here rather than refused at the citation edge: this
            // demand's own commit invalidates it, so citing it would turn the
            // evaluation into a self-refusal and serve a stale line besides.
            guard try database.summaryProvenanceMatchesCurrentSources(
                settlementID: row.settlementID) else { return }
            settlementInputs.appendRecord("\(identity)=\(row.summarySHA256)")
            guard let snippet = Self.citationSnippet(
                in: row.summary[...], folded: foldedKeywords, keywords: keywords)
            else { return }
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

        // Every component is represented as a JSON value, not interpolated into
        // a delimiter grammar. The stream digests below are independently
        // length-prefixed, so a newline or separator inside a path/session ID
        // cannot repartition two different source inventories into the same basis.
        let chatScopeMode: String
        if !demand.includeChat {
            chatScopeMode = "disabled"
        } else if demand.clientIdentityID != nil {
            chatScopeMode = chatScopeIsIdentityWide ? "identity-wide" : "explicit-sessions"
        } else {
            chatScopeMode = requestedChatSessionIDs.isEmpty ? "legacy-all" : "explicit-sessions"
        }
        let canonicalObject: [String: Any] = [
            "schema": "simigo.information-demand/basis-v8",
            "query": query,
            "request_identity": requestIdentity,
            "continuity_id": demand.continuityID ?? "",
            "client_identity_id": demand.clientIdentityID ?? "",
            "limit": limit,
            "root_scope": [
                "included": demand.includeRoots,
                "all_roots": demand.includeRoots && requestedRootIDs.isEmpty,
                "root_ids": requestedRootIDs,
            ],
            "keywords": keywords.sorted(),
            "file_inputs": [
                "count": fileInputs.count,
                "sha256": fileInputs.finalizeHex(),
            ],
            "chat_scope": [
                "included": demand.includeChat,
                "mode": chatScopeMode,
                // Identity-wide means all sessions owned by client_identity_id;
                // concrete session IDs are represented by the content watermark,
                // not by a volatile list of session IDs.
                "session_ids": demand.includeChat && !chatScopeIsIdentityWide
                    ? requestedChatSessionIDs : [],
                "count": shouldReadChat ? chatScopeCount : 0,
                "sha256": chatScopeInputs.finalizeHex(),
            ],
            "turn_inputs": [
                "count": turnInputs.count,
                "sha256": turnInputs.finalizeHex(),
            ],
            "settlement_inputs": [
                "count": settlementInputs.count,
                "sha256": settlementInputs.finalizeHex(),
            ],
            "changed_inputs": [
                "count": changedInputs.count,
                "sha256": changedInputs.finalizeHex(),
            ],
        ]
        let canonicalData = try JSONSerialization.data(
            withJSONObject: canonicalObject,
            options: [.sortedKeys, .withoutEscapingSlashes])
        let demandID = NativeSHA256.hexDigest(canonicalData)

        // The cache is consulted only now, because `demandID` is derived from
        // what the evaluation read (`inputs`, `stale`). A hit therefore saves
        // the payload encode and the write, never the reads. By this point the
        // settled file bodies have been opened and digest-verified, the
        // candidate chat messages have been read and re-hashed against their
        // stored digest, and the turn digests and citable settlement summaries
        // have been read; the chat scope was measured on identity plus stored
        // digest, without opening the message bodies. Checking the cache earlier
        // would need a second, coarser key that cannot see content changes.
        try Self.checkCancellation()
        if let cached = try cachedResolution(
            demandID: demandID, stateID: demand.stateID, sessionID: demand.sessionID,
            continuityID: demand.continuityID, clientIdentityID: demand.clientIdentityID,
            query: query, items: items,
            unavailableSourceIDs: unavailableSources.sorted(),
            changedSourceIDs: changedSources.sorted(),
            includeChat: demand.includeChat, unindexedTerms: unindexedTerms) {
            return cached
        }

        let evaluatedAt = Self.utcStamp(Date())
        let payload = try JSONEncoder.sorted.encode(StoredResult(
            schema: Self.resultSchema, query: query, inputDigest: demandID,
            hitCount: items.count, items: items, staleItemIDs: [],
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
        var boundLegacySources = Set<String>()
        for hit in items where hit.kind == "file" {
            guard let sourceRoot = hit.rootID, let sourcePath = hit.relativePath else {
                throw ESISDatabase.DatabaseError.sql(
                    "information-loop: file hit without a locator: \(hit.itemID)")
            }
            if let itemKey = hit.sourceItemKey,
               let itemKeyword = hit.sourceItemKeyword {
                // One binding per actual snippet delivered to the model. The
                // whole-file digest remains a commit-time race check only.
                sourceBindings.append(.init(
                    rootID: sourceRoot, relativePath: sourcePath,
                    binding: "source-item", expectedDigest: hit.sourceSHA256,
                    itemKey: itemKey, itemKeyword: itemKeyword,
                    itemContent: hit.lineText,
                    itemLocator: "\(hit.locator)#line:\(hit.lineNo)"))
            } else {
                // Older cached results have no item key. Keep their former
                // one-binding-per-file semantics rather than inventing identity.
                guard boundLegacySources.insert("\(sourceRoot)/\(sourcePath)").inserted
                else { continue }
                sourceBindings.append(.init(
                    rootID: sourceRoot, relativePath: sourcePath,
                    binding: "content", expectedDigest: hit.sourceSHA256))
            }
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
        let commit: ESISDatabase.InformationRetrievalCommit
        do {
            try Self.checkCancellation()
            commit = try database.recordInformationRetrieval(
                .init(
                    demandID: demandID, stateID: demand.stateID,
                    sessionID: demand.sessionID, continuityID: demand.continuityID,
                    clientIdentityID: demand.clientIdentityID,
                    requestIdentity: requestIdentity,
                    query: query,
                    rootIDs: demand.rootIDs, includeChat: demand.includeChat,
                    inputDigest: demandID, payload: payload,
                    hitCount: items.count, itemIDs: items.map(\.itemID),
                    inputs: [],
                    sourceBindings: sourceBindings,
                    sourceItemScopes: sourceItemScopes,
                    citedSettlements: citedSettlements))
        } catch let error as ESISDatabase.InformationDemandError {
            func cachedIfStillCurrent() throws -> Resolution? {
                try cachedResolution(
                    demandID: demandID, stateID: demand.stateID,
                    sessionID: demand.sessionID, continuityID: demand.continuityID,
                    clientIdentityID: demand.clientIdentityID,
                    query: query, items: items,
                    unavailableSourceIDs: unavailableSources.sorted(),
                    changedSourceIDs: changedSources.sorted(),
                    includeChat: demand.includeChat,
                    unindexedTerms: unindexedTerms)
            }
            switch error {
            case .retrievalPayloadConflict:
                // Two identical resolves can race after both miss the cache.
                // The writer refuses to replace the stable demand identity; a
                // loser may reuse the winner only when the stored result
                // matches its own current evaluation field by field.
                guard let cached = try cachedIfStillCurrent() else { throw error }
                return cached
            case .invalidTransition(_, let from, _) where from == "ADVANCED":
                // A demand advanced by an earlier answer stays resolvable: the
                // retrieval settlement is immutable and another answer may
                // advance from the same parent. Reuse it only when the current
                // evaluation still matches; otherwise surface the refusal.
                if let cached = try cachedIfStillCurrent() { return cached }
                throw error
            default:
                throw error
            }
        }

        return Resolution(
            demandID: demandID, stateID: demand.stateID, reused: false,
            hits: items, inputDigest: demandID,
            resultSHA256: commit.resultSHA256,
            retrievalSettlementID: commit.retrievalSettlementID,
            itemIDs: items.map(\.itemID),
            unavailableSourceIDs: unavailableSources.sorted(),
            changedSourceIDs: changedSources.sorted(),
            unindexedTerms: unindexedTerms)
    }

    /// The cache is only usable while it still stands for *this* evaluation.
    ///
    /// A demand id is a hash of the query basis, and the basis does not observe
    /// every way a stored result can stop being the truth — chat content can be
    /// rewritten out of band while the scope watermark stays put. Reusing on the
    /// id alone therefore answers with a result the current evaluation does not
    /// produce. The row is immutable by design (its settlement has dependants),
    /// so a divergence cannot be repaired here: it is refused, and the caller
    /// never receives the older answer.
    private func cachedResolution(
        demandID: String,
        stateID: String?,
        sessionID: String?,
        continuityID: String?,
        clientIdentityID: String?,
        query: String,
        items: [Item],
        unavailableSourceIDs: [String],
        changedSourceIDs: [String],
        includeChat: Bool,
        unindexedTerms: [String]
    ) throws -> Resolution? {
        guard let row = try database.informationDemand(demandID: demandID),
              row.state == "RESOLVED" || row.state == "ADVANCED" else {
            return nil
        }
        // A row in a settled state whose payload is unreadable is not a cache
        // miss. The payload read joins `settlement_current_validity`, so it goes
        // nil both when nothing was ever settled under this id and when the
        // settlement was published and then invalidated — and invalidation does
        // not walk `information_demands.state` back from RESOLVED/ADVANCED.
        // Neither case can be settled again: the id is immutable, so the write
        // would refuse with the same error after the result had been encoded.
        // Raise it here instead, and never describe an invalidated settlement as
        // one that never existed. This does NOT avoid the evaluation: it runs
        // before this function is reached (see the note at the call site).
        guard let stored = try database.informationRetrievalPayload(demandID: demandID) else {
            if let settlementID = row.retrievalSettlementID {
                throw ESISDatabase.InformationDemandError.retrievalSettlementUnavailable(
                    settlementID)
            }
            // An advancement-only row (settlement consumption) has no retrieval
            // settlement at all; its state already forbids reopening it.
            throw ESISDatabase.InformationDemandError.invalidTransition(
                demandID: demandID, from: row.state, to: "RESOLVED")
        }
        guard row.query == query,
              row.continuityID == continuityID,
              row.clientIdentityID == clientIdentityID,
              clientIdentityID != nil || continuityID != nil || row.sessionID == sessionID,
              row.inputDigest == demandID,
              row.retrievalSettlementID == "is-retrieval:\(demandID)" else {
            throw ESISDatabase.DatabaseError.sql(
                "information-loop: cached demand metadata diverges for \(demandID)")
        }
        guard let decoded = try? JSONDecoder().decode(StoredResult.self, from: stored),
              decoded.schema == Self.resultSchema,
              decoded.inputDigest == demandID,
              decoded.query == query,
              decoded.hitCount == items.count,
              decoded.items == items,
              decoded.staleItemIDs.isEmpty,
              decoded.includeChat == includeChat,
              (decoded.unindexedTerms ?? unindexedTerms) == unindexedTerms else {
            throw ESISDatabase.DatabaseError.sql(
                "information-loop: cached retrieval result diverges from current"
                    + " evaluation for demand \(demandID)")
        }
        return Resolution(
            demandID: demandID, stateID: stateID, reused: true,
            hits: decoded.items,
            inputDigest: demandID,
            resultSHA256: NativeSHA256.hexDigest(stored),
            retrievalSettlementID: row.retrievalSettlementID ?? "",
            itemIDs: decoded.items.map(\.itemID),
            unavailableSourceIDs: unavailableSourceIDs,
            changedSourceIDs: changedSourceIDs,
            unindexedTerms: decoded.unindexedTerms ?? unindexedTerms)
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
            guard receipt.stateID == row.stateID else {
                throw ESISDatabase.DatabaseError.sql(
                    "answerReuseExclusions: demand \(row.demandID) and settlement are bound to different states")
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
    ) throws -> ReusableAnswer? {
        // A historical answer is reusable only for the exact demand resolved
        // for this turn. Callers without a current resolution fail closed.
        guard let expectedDemandID, !expectedDemandID.isEmpty,
              let answered = try database.answeredDemand(
                sessionID: sessionID, query: query),
              answered.demandID == expectedDemandID
        else { return nil }
        // Persistence failures are not cache misses. Surface them to the
        // transport so it can refuse the request rather than silently generate.
        guard let receipt = try database.settlementReceipt(answered.answerSettlementID),
              receipt.validity == "valid" else { return nil }
        guard receipt.stateID == answered.stateID else {
            throw ESISDatabase.DatabaseError.sql(
                "reusableAnswer: demand \(answered.demandID) and settlement are bound to different states")
        }
        if let retrievalID = answered.retrievalSettlementID, !retrievalID.isEmpty {
            guard let retrieval = try database.settlementReceipt(retrievalID),
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
        let stripped = envelopeStripped(text)
        return stripped.isEmpty
            ? text.trimmingCharacters(in: .whitespacesAndNewlines) : stripped
    }

    /// The question left after stripping client envelope blocks, with NO fallback.
    /// Empty means the message is pure envelope — a tool-loop continuation reminder
    /// (system-reminder / user_info / environment_context), not an information need.
    /// Callers use this to retarget a continuation back to the genuine question
    /// instead of fabricating a demand from the envelope.
    /// See docs/decisions/ADR_IS_RENDERING_KV_DECOUPLING_20261121.md.
    public static func envelopeStripped(_ text: String) -> String {
        var out = text
        for tag in ["system-reminder", "user_info", "environment_context"] {
            out = removingBlock(tag: tag, from: out)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
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
        clientIdentityID: String? = ESISDatabase.ownerNamespace,
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
            chatModelIdentity: modelIdentity,
            clientIdentityID: clientIdentityID)
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

private struct StreamingSHA256 {
    private var hasher = SHA256()
    private(set) var count = 0

    /// Fixed-width big-endian byte length followed by the exact UTF-8 record.
    /// Unlike newline joining, this encoding is injective even when a source
    /// identity itself contains LF or other separator characters.
    mutating func appendRecord(_ value: String) {
        let bytes = Data(value.utf8)
        var byteCount = UInt64(bytes.count).bigEndian
        let lengthPrefix = withUnsafeBytes(of: &byteCount) { Data($0) }
        hasher.update(data: lengthPrefix)
        hasher.update(data: bytes)
        count += 1
    }

    mutating func finalizeHex() -> String {
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", Int($0)) }.joined()
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
