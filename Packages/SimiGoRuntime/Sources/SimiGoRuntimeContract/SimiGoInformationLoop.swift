import Foundation

/// The product-side closed loop: ES defines a demand, IS resolves it against the
/// settled physical index and the chat store, the result is settled and bound,
/// and the advancing execution state records the settlement it was derived from.
///
/// This type composes the existing authorities; it does not add a second
/// validation path. Retrieval is digest-verified, settlement of model output
/// still goes through `SimiGoSettlementAuthority`, and every write lands in the
/// same SQLite store the app already treats as authoritative.
public struct SimiGoInformationLoop {

    public let database: SimiGoESISDatabase

    public init(database: SimiGoESISDatabase) {
        self.database = database
    }

    // MARK: - Demand

    public struct Demand: Sendable {
        public var stateID: String?
        public var sessionID: String?
        public var query: String
        /// Empty means every registered root.
        public var rootIDs: [String]
        public var includeChat: Bool
        /// Empty means every stored chat session.
        public var chatSessionIDs: [String]
        /// Items that are already part of the live turn and must not be fed back
        /// as retrieved context (e.g. the user message being answered).
        public var excludeItemIDs: Set<String>
        public var limit: Int

        public init(stateID: String? = nil, sessionID: String? = nil,
                    query: String, rootIDs: [String] = [],
                    includeChat: Bool = true, chatSessionIDs: [String] = [],
                    excludeItemIDs: Set<String> = [], limit: Int = 40) {
            self.stateID = stateID
            self.sessionID = sessionID
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

        public var isEmpty: Bool { hits.isEmpty }

        public init(demandID: String, stateID: String?, reused: Bool,
                    hits: [Item], inputDigest: String, resultSHA256: String,
                    retrievalSettlementID: String, itemIDs: [String],
                    staleItemIDs: [String]) {
            self.demandID = demandID
            self.stateID = stateID
            self.reused = reused
            self.hits = hits
            self.inputDigest = inputDigest
            self.resultSHA256 = resultSHA256
            self.retrievalSettlementID = retrievalSettlementID
            self.itemIDs = itemIDs
            self.staleItemIDs = staleItemIDs
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
    }

    private static let resultSchema = "simigo.information-demand/v1"

    public func resolve(_ demand: Demand) throws -> Resolution {
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
        var itemIDs: [String] = []
        var addresses: [SimiGoESISDatabase.InformationInput] = []
        let keywords = Self.keywords(in: query)

        // Physical information: read the locator, verify the settled digest.
        for row in try database.settledFileRows(rootID: nil) {
            if !demand.rootIDs.isEmpty, !demand.rootIDs.contains(row.rootID) { continue }
            let identity = "file:\(row.rootID)/\(row.relativePath)"
            guard !demand.excludeItemIDs.contains(identity) else { continue }
            guard let text = try database.searchableFileText(row) else {
                stale.append(identity)
                continue
            }
            inputs.append("\(identity)=\(row.digest)")
            itemIDs.append(identity)
            if let address = try database.latestIndexObjectID(identity: identity) {
                addresses.append(.init(itemID: identity, contentAddress: address))
            }
            for (idx, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where !line.isEmpty {
                let score = Self.matchScore(line: line, keywords: keywords)
                guard score > 0 else { continue }
                scored.append((Item(
                    itemID: identity, kind: "file", locator: identity,
                    lineNo: idx + 1, lineText: String(line.prefix(240)),
                    sourceSHA256: row.digest,
                    rootID: row.rootID, relativePath: row.relativePath), score))
            }
        }

        // Chat information: stored messages are entries in the same space.
        if demand.includeChat {
            for row in try database.chatIndexRows(sessionIDs: demand.chatSessionIDs) {
                guard !demand.excludeItemIDs.contains(row.itemID) else { continue }
                guard NativeSHA256.hexDigest(Data(row.content.utf8)) == row.contentSHA256
                else { continue }
                inputs.append("\(row.itemID)=\(row.contentSHA256)")
                itemIDs.append(row.itemID)
                if let address = try database.latestIndexObjectID(identity: row.itemID) {
                    addresses.append(.init(itemID: row.itemID, contentAddress: address))
                }
                for (idx, line) in row.content
                    .split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where !line.isEmpty {
                    let score = Self.matchScore(line: line, keywords: keywords)
                    guard score > 0 else { continue }
                    scored.append((Item(
                        itemID: row.itemID, kind: "chat",
                        locator: "session:\(row.sessionID)#\(row.messageID)",
                        lineNo: idx + 1, lineText: String(line.prefix(240)),
                        sourceSHA256: row.contentSHA256), score))
                }
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
            itemIDs.append(identity)
            if let address = try database.latestIndexObjectID(
                identity: "settlement-summary:\(row.settlementID)")
            {
                addresses.append(.init(itemID: identity, contentAddress: address))
            }
            let haystack = row.query.isEmpty ? row.summary : "\(row.query)\n\(row.summary)"
            let score = Self.matchScore(line: haystack, keywords: keywords)
            guard score > 0 else { continue }
            scored.append((Item(
                itemID: identity, kind: "settlement",
                locator: "settlement:\(row.settlementID)#summary",
                lineNo: 1, lineText: String(row.summary.prefix(240)),
                sourceSHA256: row.summarySHA256,
                derivationType: row.derivationType,
                sourceSettlementID: row.sourceSettlementID), score))
        }

        // Deterministic ranking: more distinct keywords first, then stable
        // identity order. The same inputs therefore always settle the same list.
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.item.itemID != $1.item.itemID { return $0.item.itemID < $1.item.itemID }
            return $0.item.lineNo < $1.item.lineNo
        }
        let items = Array(scored.prefix(limit).map(\.item))

        let canonical = "query=\(query)\n"
            + "keywords=" + keywords.sorted().joined(separator: " ")
            + "\n" + inputs.sorted().joined(separator: "\n")
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
                staleItemIDs: decoded.staleItemIDs)
        }

        let evaluatedAt = Self.utcStamp(Date())
        let payload = try JSONEncoder.sorted.encode(StoredResult(
            schema: Self.resultSchema, query: query, inputDigest: demandID,
            hitCount: items.count, items: items, staleItemIDs: stale,
            includeChat: demand.includeChat, evaluatedAtUTC: evaluatedAt))
        let commit = try database.recordInformationRetrieval(
            .init(
                demandID: demandID, stateID: demand.stateID,
                sessionID: demand.sessionID, query: query,
                rootIDs: demand.rootIDs, includeChat: demand.includeChat,
                inputDigest: demandID, payload: payload,
                hitCount: items.count, itemIDs: itemIDs, inputs: addresses))

        // The retrieval result is derived from these files, so the demand must
        // carry the edge that lets a later content change invalidate it. Without
        // the binding the invalidation closure has nothing to walk and a settled
        // demand would keep being reused after its source moved.
        var boundSources = Set<String>()
        for hit in items where hit.kind == "file" {
            guard let sourceRoot = hit.rootID, let sourcePath = hit.relativePath else { continue }
            guard boundSources.insert("\(sourceRoot)/\(sourcePath)").inserted else { continue }
            try database.linkSettlementToExternalFile(
                settlementID: commit.retrievalSettlementID, binding: "content",
                rootID: sourceRoot, relativePath: sourcePath)
        }

        return Resolution(
            demandID: demandID, stateID: demand.stateID, reused: false,
            hits: items, inputDigest: demandID,
            resultSHA256: commit.resultSHA256,
            retrievalSettlementID: commit.retrievalSettlementID,
            itemIDs: items.map(\.itemID), staleItemIDs: stale)
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

    // MARK: - Query terms

    /// Terms used for line matching. A whole user question rarely appears
    /// verbatim in a document, so ASCII tokens are kept and CJK runs are
    /// expanded into overlapping bigrams. Ranking uses the number of distinct
    /// terms a line contains, which stays deterministic for settlement.
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
        for part in query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
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

    private static func matchScore<S: StringProtocol>(
        line: S, keywords: [String]
    ) -> Int {
        guard !keywords.isEmpty else { return 0 }
        var score = 0
        for keyword in keywords where line.localizedCaseInsensitiveContains(keyword) {
            score += 1
        }
        return score
    }

    // MARK: - Advancement

    public struct TurnSettlement: Equatable, Sendable {
        public let settlementID: String
        public let childStateID: String
        public let advancementID: String
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
    @discardableResult
    public func settleTurn(
        generatedText: String,
        resolution: Resolution?,
        stateID: String,
        parentStateID: String?,
        position: Int,
        modelIdentity: String,
        identity: SimiGoSettlementIdentityBinding.Identity,
        sessionID: String?,
        summaryQuery: String? = nil,
        actions: [String] = ["generate"],
        contractJSON: Data? = nil,
        settledAt: Date = Date()
    ) throws -> TurnSettlement {
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: generatedText,
            contractJSON: contractJSON ?? Self.chatResultContractJSON,
            verifiedBindings: [:],
            settledAt: settledAt)
        let content = Self.content(of: settled)

        let advanced = resolution.flatMap { res -> SimiGoESISDatabase.InformationAdvancementPlan? in
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
            advancement: advanced)
        if let sessionID {
            try database.linkChatSession(
                sessionID: sessionID, stateID: stateID, modelIdentity: modelIdentity)
        }
        // Post-settlement distillation: a separate, additive write. The
        // settlement above is already durable, so a summary failure never
        // invalidates the settled result.
        _ = try? database.recordSettlementSummary(
            settlementID: commit.settlementID.uuidString,
            sessionID: sessionID,
            query: summaryQuery ?? "",
            settledAt: settledAt)
        return TurnSettlement(
            settlementID: commit.settlementID.uuidString,
            childStateID: stateID,
            advancementID: commit.advancementID ?? "")
    }

    static func content(of settled: SimiGoSettlementAuthority.SettledResult) -> String {
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
