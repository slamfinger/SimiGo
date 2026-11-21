import Foundation
import SQLite3
import XCTest
import Network
import SimiGoRuntimeContract
@testable import SimiGo

/// App-level proof for the MCP facade: every tool runs the SAME native ES/IS
/// operations (settled index, locator reads, demand reuse) over an isolated
/// temporary store, and registering a root indexes it WITHOUT copying bytes.
final class MCPInformationSpaceTests: XCTestCase {

    private var dir: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-is-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("simigo.sqlite3")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeServer() -> HTTPServer {
        HTTPServer(
            port: 0,
            modelId: "test-model",
            generateHandler: { _, _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "test-model",
                    savedAt: Date(),
                    history: [])
            },
            deleteBranchHandler: { _, _, _, _ in
                BranchDeletionOutcome(
                    deletedBranch: "", hadLiveSession: false,
                    hadCheckpointFile: false, generation: 1,
                    remainingLiveBranches: [],
                    remainingCheckpointBranches: [])
            },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )
    }

    func testSearchScopeAndPayloadAreSharedAcrossHTTPAndMCP() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        for sessionID in ["chat-a", "chat-b"] {
            let userID = try db.appendChatMessage(
                sessionID: sessionID, role: "user", content: "shared needle question",
                model: nil, createdAt: Date())
            try db.commitChatTurn(
                sessionID: sessionID, userMessageID: userID,
                assistantText: "shared needle answer", model: nil, createdAt: Date())
        }
        db.close()

        let body: [String: Any] = [
            "query": "needle",
            "session_id": "retrieval-owner",
            "session_ids": [String](),
            "include_chat": true,
            "limit": 40,
            "include_brief": false,
        ]
        let parsed = try HTTPServer.informationSearchArguments(
            body: try JSONSerialization.data(withJSONObject: body),
            requestTarget: "/v1/simigo/search?root_ids=work-a&root_ids=work-b")
        XCTAssertEqual(parsed["session_id"] as? String, "retrieval-owner")
        XCTAssertEqual(parsed["session_ids"] as? [String], [String](),
                       "explicit empty array must remain all-session scope")
        XCTAssertEqual(parsed["root_ids"] as? [String], ["work-a", "work-b"])
        XCTAssertEqual(parsed["limit"] as? Int, 40)
        XCTAssertEqual(parsed["include_brief"] as? Bool, false)

        let mcp = try HTTPServer.runMCPTool(
            name: "simigo_is_search", arguments: body, databaseURL: dbURL)
        let http = try HTTPServer.runInformationSearch(
            arguments: body, databaseURL: dbURL)
        XCTAssertEqual(Set(mcp.keys), Set(http.keys),
                       "both transports expose the same search payload contract")
        let mcpIDs = (mcp["items"] as? [[String: Any]])?.compactMap { $0["item_id"] as? String } ?? []
        let httpIDs = (http["items"] as? [[String: Any]])?.compactMap { $0["item_id"] as? String } ?? []
        XCTAssertEqual(mcpIDs, httpIDs)
        XCTAssertTrue(mcpIDs.contains(where: { $0.contains("chat-a") }))
        XCTAssertTrue(mcpIDs.contains(where: { $0.contains("chat-b") }),
                      "session_id owns the demand; it does not implicitly narrow chat search")
        XCTAssertEqual(mcp["index"] as? String, http["index"] as? String)
        XCTAssertEqual(mcp["unindexed_terms"] as? [String], http["unindexed_terms"] as? [String])
    }

    func testOwnerIdentityWideSearchSurvivesInitiallyEmptyChatScope() throws {
        let query = "owner identity scope probe"
        let arguments: [String: Any] = [
            "query": query,
            "request_id": "owner-identity-wide-search",
            "include_chat": true,
            "include_brief": false,
        ]

        let initiallyEmpty = try HTTPServer.runMCPTool(
            name: "simigo_is_search", arguments: arguments, databaseURL: dbURL)
        XCTAssertEqual(initiallyEmpty["reused"] as? Bool, false)
        let repeatedEmpty = try HTTPServer.runMCPTool(
            name: "simigo_is_search", arguments: arguments, databaseURL: dbURL)
        XCTAssertEqual(repeatedEmpty["reused"] as? Bool, true)
        XCTAssertEqual(repeatedEmpty["demand_id"] as? String,
                       initiallyEmpty["demand_id"] as? String)

        var disabledArguments = arguments
        disabledArguments["include_chat"] = false
        let chatDisabled = try HTTPServer.runMCPTool(
            name: "simigo_is_search", arguments: disabledArguments, databaseURL: dbURL)
        XCTAssertNotEqual(chatDisabled["demand_id"] as? String,
                          initiallyEmpty["demand_id"] as? String,
                          "an empty identity-wide chat scope is not disabled chat")

        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        let firstUser = try db.appendChatMessage(
            sessionID: "codex-owner-scope-a", role: "user",
            content: query + " from session A", model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: "codex-owner-scope-a", userMessageID: firstUser,
            assistantText: "Owner session A response", model: nil, createdAt: Date())
        let secondUser = try db.appendChatMessage(
            sessionID: "qoder-owner-scope-b", role: "user",
            content: query + " from session B", model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: "qoder-owner-scope-b", userMessageID: secondUser,
            assistantText: "Owner session B response", model: nil, createdAt: Date())
        db.close()

        let withSessions = try HTTPServer.runMCPTool(
            name: "simigo_is_search", arguments: arguments, databaseURL: dbURL)
        XCTAssertNotEqual(withSessions["demand_id"] as? String,
                          initiallyEmpty["demand_id"] as? String)
        let items = try XCTUnwrap(withSessions["items"] as? [[String: Any]])
        XCTAssertTrue(items.contains {
            ($0["text"] as? String)?.contains("session A") == true
        })
        XCTAssertTrue(items.contains {
            ($0["text"] as? String)?.contains("session B") == true
        })
    }

    func testISStatusIsShallowByDefaultAndDeepVerificationIsOptIn() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        db.close()

        let shallow = try HTTPServer.runMCPTool(
            name: "simigo_is_status", arguments: [:], databaseURL: dbURL)
        XCTAssertEqual(shallow["deep_verified"] as? Bool, false)
        XCTAssertEqual(shallow["object_count"] as? Int, shallow["objects"] as? Int)

        let deepMCP = try HTTPServer.runMCPTool(
            name: "simigo_is_status", arguments: ["deep": true], databaseURL: dbURL)
        let deepHTTP = try HTTPServer.runInformationStatus(
            arguments: ["deep": true], databaseURL: dbURL)
        XCTAssertEqual(deepMCP["deep_verified"] as? Bool, true)
        XCTAssertEqual(Set(deepMCP.keys), Set(deepHTTP.keys))
        XCTAssertEqual(deepMCP["deep_verified"] as? Bool, deepHTTP["deep_verified"] as? Bool)
    }
    func testInformationSearchQueryParametersRejectMalformedFilters() throws {
        XCTAssertThrowsError(try HTTPServer.informationSearchArguments(
            body: Data(), requestTarget: "/v1/simigo/search?q=needle&include_chat=maybe"))
        XCTAssertThrowsError(try HTTPServer.informationSearchArguments(
            body: Data(), requestTarget: "/v1/simigo/search?q=needle&limit=not-an-integer"))
        XCTAssertThrowsError(try HTTPServer.informationSearchArguments(
            body: Data(), requestTarget: "/v1/simigo/search?q=needle&root_ids="))
        XCTAssertThrowsError(try HTTPServer.informationSearchArguments(
            body: Data("{".utf8), requestTarget: "/v1/simigo/search?q=needle"))
        XCTAssertThrowsError(try HTTPServer.informationStatusArguments(
            requestTarget: "/v1/simigo/is/status?deep=maybe"))
        XCTAssertThrowsError(try HTTPServer.informationStatusArguments(
            requestTarget: "/v1/simigo/is/status?deep=true&deep=false"))
    }

    /// The brief is read through the same database the search reads, so an
    /// agent can ask "where does this project stand" and get the note that is
    /// current — not the most similar paragraph ever written.
    func testProjectBriefIsReadBackAndSupersededInPlace() throws {
        let empty = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:], databaseURL: dbURL)
        XCTAssertEqual(empty["claim"] as? String, "")
        XCTAssertNotNil(empty["hint"], "an absent brief says so instead of looking blank")

        let first = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "brief", "claim": "v1: what the project is"],
            databaseURL: dbURL)
        XCTAssertEqual(first["created"] as? Bool, true)
        XCTAssertEqual(first["supersedes"] as? String, "")

        let read = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:], databaseURL: dbURL)
        XCTAssertEqual(read["claim"] as? String, "v1: what the project is")
        XCTAssertEqual(read["note_id"] as? String, first["note_id"] as? String)

        let second = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "brief", "claim": "v2: where it stands"],
            databaseURL: dbURL)
        XCTAssertEqual(second["supersedes"] as? String, first["note_id"] as? String)
        XCTAssertEqual(second["current_is_this"] as? Bool, true)
        XCTAssertEqual(second["history"] as? Int, 2)

        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM project_notes WHERE kind='brief@owner';"), "2",
            "the superseded judgement stays in the ledger")
        let current = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:], databaseURL: dbURL)
        XCTAssertEqual(current["claim"] as? String, "v2: where it stands")

        // The brief must reach a caller that never asks for it and never uses
        // the word: it rides outside the ranked items, so it cannot be pushed
        // out of the answer by a similar paragraph.
        let search = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": "anything at all", "include_chat": false],
            databaseURL: dbURL)
        let brief = search["brief"] as? [String: Any]
        XCTAssertEqual(brief?["claim"] as? String, "v2: where it stands")
        XCTAssertEqual(brief?["note_id"] as? String, second["note_id"] as? String)
        XCTAssertEqual(
            (search["items"] as? [[String: Any]])?.isEmpty, true,
            "the brief is not counted as a retrieved item")

        // A caller that wants the corpus alone can refuse the prior. The field
        // is declared, so refusing it is a choice rather than a workaround.
        let without = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "anything at all", "include_chat": false,
                "include_brief": false,
            ],
            databaseURL: dbURL)
        XCTAssertNil(without["brief"], "include_brief=false leaves the prior out")
    }

    /// Material captured after the judgement is handed over with it, so a
    /// client that never heard of a hook still learns what landed after the
    /// brief was written. 不限 kind：裁定与状态同样是材料，只带窗口留档的那版让
    /// 读简报的窗口继续拿着已失效的「仍未关」清单走。滚动摘要每五分钟自动刷一
    /// 版，是过程噪声，不入交接清单。Listing it must not rewrite the brief:
    /// what the material changes is still the reader's decision.
    func testProjectBriefHandsOverMaterialRecordedAfterIt() throws {
        _ = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "window", "claim": "上下文窗口 1 压缩留档\n旧材料"],
            databaseURL: dbURL)
        let brief = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "brief", "claim": "v1: where it stands"],
            databaseURL: dbURL)
        let accounted = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:], databaseURL: dbURL)
        XCTAssertEqual(
            (accounted["newer_notes"] as? [[String: Any]])?.isEmpty, true,
            "a window older than the brief is already accounted for")
        XCTAssertEqual(
            accounted["stale"] as? Bool, false,
            "没有新材料就不算过期")

        let window = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "window", "claim": "上下文窗口 2 压缩留档\n摘要正文"],
            databaseURL: dbURL)
        let decision = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "decision", "claim": "R11 关闭裁定\n正文"],
            databaseURL: dbURL)
        let digest = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "digest", "claim": "23:09 那一轮的滚动摘要"],
            databaseURL: dbURL)
        let read = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:], databaseURL: dbURL)
        let newer = read["newer_notes"] as? [[String: Any]]
        XCTAssertEqual(newer?.count, 2, "窗口与裁定都交接，滚动摘要不交接")
        XCTAssertEqual(
            newer?.compactMap { $0["note_id"] as? String },
            [window["note_id"] as? String, decision["note_id"] as? String],
            "按记录时刻升序，不按文本序")
        XCTAssertEqual(newer?.first?["kind"] as? String, "window@owner")
        XCTAssertEqual(newer?.last?["kind"] as? String, "decision@owner")
        XCTAssertEqual(newer?.first?["head"] as? String, "上下文窗口 2 压缩留档")
        XCTAssertEqual(
            newer?.first?["chars"] as? Int, "上下文窗口 2 压缩留档\n摘要正文".count)
        XCTAssertEqual(
            newer?.compactMap { $0["note_id"] as? String }
                .contains(digest["note_id"] as? String ?? ""), false,
            "自动刷新的滚动摘要不入交接清单")
        XCTAssertEqual(read["stale"] as? Bool, true)
        XCTAssertEqual(
            read["newer_counts"] as? [String: Int],
            ["window@owner": 1, "decision@owner": 1],
            "过期账按 kind 分开：多了个窗口和多了条裁定不是一回事")
        XCTAssertEqual(
            read["claim"] as? String, "v1: where it stands",
            "listing the material does not rewrite the judgement")
        XCTAssertEqual(brief["current_is_this"] as? Bool, true)
    }

    func testBuiltInMCPAndNativeExecutionUseOwnerWhileExternalBearerStaysSeparate() throws {
        let ownerWrite = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "brief", "claim": "built-in API owner brief"],
            databaseURL: dbURL)
        XCTAssertEqual(ownerWrite["kind"] as? String, "brief@owner")

        let externalIdentity = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let externalWrite = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "brief", "claim": "external bearer brief"],
            databaseURL: dbURL,
            clientIdentityID: externalIdentity.digest)
        XCTAssertEqual(
            externalWrite["kind"] as? String, "brief@\(externalIdentity.digest)")

        let ownerRead = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:], databaseURL: dbURL)
        let externalRead = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:], databaseURL: dbURL,
            clientIdentityID: externalIdentity.digest)
        XCTAssertEqual(ownerRead["scope"] as? String, "owner")
        XCTAssertEqual(ownerRead["claim"] as? String, "built-in API owner brief")
        let localInstructions = HTTPServer.sessionInstructions(
            client: "", databaseURL: dbURL)
        XCTAssertTrue(localInstructions.contains("built-in API owner brief"))
        XCTAssertTrue(localInstructions.contains("brief@owner"))
        XCTAssertEqual(externalRead["scope"] as? String, externalIdentity.digest)
        XCTAssertEqual(externalRead["claim"] as? String, "external bearer brief")

        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        let localResolution = try InformationLoop(database: db).resolve(.init(
            sessionID: "codex-local-session",
            query: "owner namespace inference demand",
            includeChat: false))
        let localDemand = try XCTUnwrap(
            db.informationDemand(demandID: localResolution.demandID))
        XCTAssertEqual(localDemand.clientIdentityID, "owner")

        let externalResolution = try InformationLoop(database: db).resolve(.init(
            sessionID: "mcp-\(externalIdentity.digest)-external-session",
            clientIdentityID: externalIdentity.digest,
            query: "bearer namespace inference demand",
            includeChat: false))
        let externalDemand = try XCTUnwrap(
            db.informationDemand(demandID: externalResolution.demandID))
        XCTAssertEqual(externalDemand.clientIdentityID, externalIdentity.digest)
        XCTAssertNotEqual(localResolution.demandID, externalResolution.demandID)

        try db.recordExecutionState(
            id: "native-owner-es", parentID: nil, modelIdentity: "local-model",
            position: 0, continuationID: "native-owner-continuation", anchor: "",
            lifecycle: "active", createdAt: Date())
        try db.recordExecutionState(
            id: "external-client-es", parentID: nil, modelIdentity: "external-model",
            position: 0, continuationID: "external-client-continuation", anchor: "",
            lifecycle: "active", createdAt: Date(),
            clientIdentityID: externalIdentity.digest)
        XCTAssertEqual(try db.executionStateClientIdentityID("native-owner-es"), "owner")
        XCTAssertEqual(
            try db.executionStateClientIdentityID("external-client-es"),
            externalIdentity.digest)

        // A global state_id collision must not let either namespace overwrite
        // the other's ES through the lower-level carrier or the app graph writer.
        XCTAssertThrowsError(try db.recordExecutionState(
            id: "external-client-es", parentID: nil, modelIdentity: "local-model",
            position: 1, continuationID: "attempted-owner-overwrite", anchor: "",
            lifecycle: "active", createdAt: Date()))
        XCTAssertThrowsError(try db.recordExecutionState(
            id: "native-owner-es", parentID: nil, modelIdentity: "external-model",
            position: 1, continuationID: "attempted-client-overwrite", anchor: "",
            lifecycle: "active", createdAt: Date(),
            clientIdentityID: externalIdentity.digest))
        let graphStates = [
            ESISDatabase.GraphState(
                id: "native-owner-es", parentID: nil, modelIdentity: "local-model",
                createdAt: Date(), position: 0, continuationID: "native-owner-continuation",
                nextInput: "", anchor: "", prefix: [], lifecycle: "active", checkpointIDs: []),
            ESISDatabase.GraphState(
                id: "external-client-es", parentID: nil, modelIdentity: "local-model",
                createdAt: Date(), position: 0, continuationID: "attempted-graph-overwrite",
                nextInput: "", anchor: "", prefix: [], lifecycle: "active", checkpointIDs: []),
        ]
        XCTAssertThrowsError(try db.writeGraph(states: graphStates, checkpoints: []))
        XCTAssertEqual(try db.executionStateClientIdentityID("native-owner-es"), "owner")
        XCTAssertEqual(
            try db.executionStateClientIdentityID("external-client-es"),
            externalIdentity.digest)

        let ownerGraph = try db.readGraph()
        XCTAssertTrue(ownerGraph.states.contains { $0.id == "native-owner-es" })
        XCTAssertFalse(ownerGraph.states.contains { $0.id == "external-client-es" },
                        "external bearer ES must not appear in the local owner graph")
        XCTAssertTrue(try db.hasExecutionStates())
        db.close()
    }

    /// MCP initialize carries a SimiGo-issued identity; the Hook replays it on reconnect.
    func testInitializeInstructionsUseThePersistedClientIdentity() throws {
        let identity = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        _ = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "brief", "claim": "v1: where it stands"],
            databaseURL: dbURL,
            clientIdentityID: identity.digest)
        let text = HTTPServer.sessionInstructions(
            client: identity.digest, databaseURL: dbURL)
        XCTAssertTrue(text.contains("v1: where it stands"))
        XCTAssertTrue(text.contains("简报已注入"))
        XCTAssertTrue(text.contains("本 SimiGo ES/IS 命名空间：\(identity.digest)"))
        XCTAssertTrue(text.contains("brief@\(identity.digest)"))
    }

    func testRollingDigestRollsFromTurnDigestsAndThrottles() throws {
        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        try db.recordTurnDigest(
            sessionID: "codex-rolling", turnIndex: 1,
            digest: "第一轮：把 provider 的缺省值修掉了", keywords: "provider")
        let first = try XCTUnwrap(try db.currentProjectNote(kind: "digest@owner"))
        XCTAssertTrue(first.claim.contains("codex-rolling t1"))
        XCTAssertTrue(first.claim.contains("不得当现值"))

        try db.recordTurnDigest(
            sessionID: "codex-rolling", turnIndex: 2,
            digest: "第二轮：部署探针三条全过", keywords: "探针")
        XCTAssertEqual(
            try db.currentProjectNote(kind: "digest@owner")?.noteID, first.noteID,
            "within the throttle window the digest is not rewritten")

        let rolled = try XCTUnwrap(
            try db.refreshRollingDigest(scope: "owner", at: Date().addingTimeInterval(600)))
        XCTAssertNotEqual(rolled.noteID, first.noteID)
        XCTAssertTrue(rolled.claim.contains("t1") && rolled.claim.contains("t2"))
        XCTAssertTrue(rolled.claim.contains("部署探针三条全过"))
    }

    func testLocalAgentTurnDigestsConvergeIntoOwnerScope() throws {
        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()

        for provider in ["codex", "zcode", "qoder"] {
            XCTAssertEqual(
                ESISDatabase.clientScope(ofSession: "\(provider)-legacy-session"), "owner")
            try db.recordTurnDigest(
                sessionID: "\(provider)-legacy-session",
                turnIndex: 1,
                digest: "rolling digest for \(provider)",
                keywords: provider)
        }

        let note = try XCTUnwrap(
            db.refreshRollingDigest(scope: "owner", at: Date().addingTimeInterval(600)))
        for provider in ["codex", "zcode", "qoder"] {
            XCTAssertTrue(note.claim.contains("rolling digest for \(provider)"))
        }
        for provider in ["codex", "zcode", "qoder"] {
            XCTAssertNil(try db.currentProjectNote(kind: "digest@\(provider)"))
        }
        db.close()
    }

    func testEmptyBearerChatScopeCannotFallBackToAllClientSessions() throws {
        let ownerA = String(repeating: "c", count: 64)
        let ownerB = String(repeating: "d", count: 64)
        let foreignSession = "mcp-\(ownerA)-private-session"
        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        let now = Date()
        _ = try db.recordExternalTurn(
            sessionID: foreignSession, provider: "external", requestID: "private-turn",
            userText: "bearer private marker", model: "external-model", createdAt: now)
        _ = try db.recordExternalResponse(
            sessionID: foreignSession, provider: "external", requestID: "private-turn",
            assistantText: "bearer private marker answer", model: "external-model", createdAt: now)
        XCTAssertEqual(
            try db.verifyExternalTurn(
                sessionID: foreignSession, requestID: "private-turn", verifiedAt: now), 2)
        try db.recordTurnDigest(
            sessionID: foreignSession, turnIndex: 1,
            digest: "bearer private marker digest", keywords: "bearer private marker")

        // This bearer has no sessions. The carrier's low-level [] convention means
        // "unfiltered", so InformationLoop must disable chat before reaching those APIs.
        let resolution = try InformationLoop(database: db).resolve(.init(
            sessionID: "mcp-\(ownerB)-empty-session",
            clientIdentityID: ownerB,
            query: "bearer private marker",
            includeChat: true))
        XCTAssertFalse(resolution.hits.contains { $0.kind == "chat" })
        XCTAssertFalse(resolution.hits.contains { $0.kind == "turn" })
        XCTAssertTrue(resolution.hits.isEmpty, "an empty bearer scope must see no foreign chat data")
        db.close()
    }
    func testMCPClientTurnDigestRefreshesOnlyItsBearerIdentityScope() throws {
        let identity = String(repeating: "a", count: 64)
        let sessionID = "mcp-\(identity)-agent-session"
        XCTAssertEqual(ESISDatabase.clientScope(ofSession: sessionID), identity)

        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        try db.recordTurnDigest(
            sessionID: sessionID, turnIndex: 1,
            digest: "MCP 私有轮次摘要，不应进入共享动态交接",
            keywords: "MCP 私有摘要")

        let scoped = try XCTUnwrap(
            db.currentProjectNote(kind: "digest@\(identity)"))
        XCTAssertTrue(scoped.claim.contains("MCP 私有轮次摘要"))
        XCTAssertNil(
            try db.currentProjectNote(kind: "digest"),
            "MCP bearer-owned turns must not leak into the identity-less shared digest")
        XCTAssertNil(
            try db.currentProjectNote(kind: "digest@owner"),
            "MCP bearer-owned turns must not leak into the first-party owner scope")
        db.close()
    }

    func testV48MigrationConvergesLegacyAgentNotesAndExecutionStatesIntoOwner() throws {
        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        let legacyBearer = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let revokedBearer = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let stateOnlyBearer = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        XCTAssertTrue(try db.revokeMCPClientIdentity(revokedBearer.digest))
        try db.recordExecutionState(
            id: "legacy-local-es", parentID: nil, modelIdentity: "local-model",
            position: 0, continuationID: "legacy-local-continuation", anchor: "",
            lifecycle: "active", createdAt: Date())
        // This old client has a persisted ES but no information-demand row yet.
        try db.recordExecutionState(
            id: "legacy-state-only-es", parentID: nil, modelIdentity: "external-model",
            position: 0, continuationID: "legacy-state-only-continuation", anchor: "",
            lifecycle: "active", createdAt: Date(),
            clientIdentityID: stateOnlyBearer.digest)

        // Simulate pre-v48 bearer-owned demands whose explicit identity columns
        // were absent but whose server-generated session prefixes prove scope.
        let legacyExternalDigest = legacyBearer.digest
        let legacyExternalSession = "mcp-\(legacyExternalDigest)-legacy-agent-session"
        try db.recordExecutionState(
            id: "legacy-external-es", parentID: nil, modelIdentity: "external-model",
            position: 0, continuationID: "legacy-external-continuation", anchor: "",
            lifecycle: "active", createdAt: Date(), clientIdentityID: nil)
        _ = try db.recordInformationRetrieval(.init(
            demandID: "legacy-external-demand",
            stateID: "legacy-external-es",
            sessionID: legacyExternalSession,
            continuityID: nil,
            clientIdentityID: nil,
            requestIdentity: "legacy-external-request",
            query: "legacy external query",
            rootIDs: [],
            includeChat: false,
            inputDigest: "legacy-external-basis",
            payload: Data("{}".utf8),
            hitCount: 0,
            itemIDs: [],
            inputs: []))

        let revokedSession = "mcp-\(revokedBearer.digest)-revoked-agent-session"
        try db.recordExecutionState(
            id: "legacy-revoked-es", parentID: nil, modelIdentity: "external-model",
            position: 0, continuationID: "legacy-revoked-continuation", anchor: "",
            lifecycle: "active", createdAt: Date(), clientIdentityID: nil)
        _ = try db.recordInformationRetrieval(.init(
            demandID: "legacy-revoked-demand",
            stateID: "legacy-revoked-es",
            sessionID: revokedSession,
            continuityID: nil,
            clientIdentityID: nil,
            requestIdentity: "legacy-revoked-request",
            query: "legacy revoked query",
            rootIDs: [],
            includeChat: false,
            inputDigest: "legacy-revoked-basis",
            payload: Data("{}".utf8),
            hitCount: 0,
            itemIDs: [],
            inputs: []))

        // Provider names are provenance only: Codex/Zcode/Qoder local sessions
        // all converge on the first-party owner namespace.
        for provider in ["codex", "zcode", "qoder"] {
            let session = "\(provider)-legacy-agent-session"
            let userID = try db.appendChatMessage(
                sessionID: session, role: "user",
                content: "\(provider) legacy owner migration", model: nil, createdAt: Date())
            try db.commitChatTurn(
                sessionID: session, userMessageID: userID,
                assistantText: "\(provider) local answer", model: nil, createdAt: Date())
            XCTAssertEqual(ESISDatabase.clientScope(ofSession: session), "owner")
        }

        _ = try db.recordProjectNote(kind: "brief@codex", claim: "Codex 本机简报")
        _ = try db.recordProjectNote(kind: "brief@zcode", claim: "Zcode 本机简报")
        _ = try db.recordProjectNote(kind: "digest@qoder", claim: "Qoder 本机摘要")
        _ = try db.recordProjectNote(kind: "digest@codex", claim: "Codex 本机摘要")
        db.close()

        try rawExecute("""
        DELETE FROM schema_migrations WHERE version >= 48;
        DELETE FROM mcp_client_identities
         WHERE client_identity_id IN ('\(legacyExternalDigest)', '\(stateOnlyBearer.digest)');
        UPDATE mcp_client_identities
           SET revoked_at=CURRENT_TIMESTAMP
         WHERE client_identity_id='\(revokedBearer.digest)';
        UPDATE execution_states SET client_identity_id=NULL
         WHERE state_id IN ('legacy-local-es', 'legacy-external-es', 'legacy-revoked-es');
        """)

        let migrated = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try migrated.runMigrations()
        XCTAssertEqual(
            try migrated.executionStateClientIdentityID("legacy-local-es"), "owner")
        XCTAssertEqual(
            try migrated.executionStateClientIdentityID("legacy-external-es"),
            legacyExternalDigest,
            "a historical mcp-<bearer-digest>- session must not be merged into owner")
        let migratedExternalDemand = try XCTUnwrap(
            try migrated.informationDemand(demandID: "legacy-external-demand"))
        XCTAssertEqual(migratedExternalDemand.clientIdentityID, legacyExternalDigest)
        XCTAssertEqual(
            try migrated.settlementClientIdentityID("is-retrieval:legacy-external-demand"),
            legacyExternalDigest)
        XCTAssertEqual(
            try migrated.executionStateClientIdentityID("legacy-revoked-es"),
            revokedBearer.digest)
        XCTAssertEqual(
            try migrated.informationDemand(demandID: "legacy-revoked-demand")?.clientIdentityID,
            revokedBearer.digest)
        XCTAssertEqual(
            try migrated.executionStateClientIdentityID("legacy-state-only-es"),
            stateOnlyBearer.digest,
            "a bearer identity recorded on ES must survive even without an IS demand")
        let expectedLocalSessions: Set<String> = [
            "codex-legacy-agent-session", "zcode-legacy-agent-session",
            "qoder-legacy-agent-session",
        ]
        XCTAssertEqual(
            Set(try migrated.chatSessionIDs(clientIdentityID: "owner"))
                .intersection(expectedLocalSessions),
            expectedLocalSessions,
            "provider sessions are local owner data, not separate identity spaces")
        XCTAssertTrue(try migrated.isActiveClientIdentity(legacyExternalDigest),
                      "v48 restores historical Client digests without changing their identity")
        XCTAssertTrue(try migrated.isActiveClientIdentity(stateOnlyBearer.digest),
                      "v48 restores identities found only on historical execution states")
        XCTAssertFalse(try migrated.isActiveClientIdentity(revokedBearer.digest),
                       "migration must not reactivate a deliberately revoked Client")
        let brief = try XCTUnwrap(migrated.currentProjectNote(kind: "brief@owner"))
        XCTAssertTrue(brief.claim.contains("Codex 本机简报"))
        XCTAssertTrue(brief.claim.contains("Zcode 本机简报"))
        let digest = try XCTUnwrap(migrated.currentProjectNote(kind: "digest@owner"))
        XCTAssertTrue(digest.claim.contains("Qoder 本机摘要"))
        XCTAssertTrue(digest.claim.contains("Codex 本机摘要"))
        XCTAssertNil(try migrated.currentProjectNote(kind: "brief@codex"),
                     "v49 retires the per-provider twins once their judgement is folded into owner")
        XCTAssertNil(try migrated.currentProjectNote(kind: "digest@qoder"))
        try migrated.runMigrations()
        XCTAssertEqual(try migrated.projectNoteCount(kind: "brief@owner"), 1,
                       "the migration must be idempotent")
        migrated.close()
    }

    /// v49 leaves exactly two note namespaces: `@owner` for first-party local
    /// work and `@<64-hex bearer digest>` for an external client. The scope-less
    /// kinds and per-provider twins are pre-release residue — each base kind's
    /// newest judgement is folded into owner, the legacy rows are retired, and
    /// chat/digest history plus bearer namespaces are deliberately untouched.
    func testV49KeepsOnlyOwnerAndBearerNoteNamespaces() throws {
        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        let bearer = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let old = Date(timeIntervalSinceNow: -7200)
        let older = Date(timeIntervalSinceNow: -3600)
        try db.recordProjectNote(kind: "status", claim: "scopeless status", at: old)
        try db.recordProjectNote(kind: "status@qoder", claim: "newest qoder status", at: older)
        try db.recordProjectNote(kind: "decision", claim: "scopeless decision", at: old)
        try db.recordProjectNote(kind: "window", claim: "scopeless window", at: old)
        try db.recordProjectNote(kind: "brief@codex", claim: "codex twin brief", at: old)
        try db.recordProjectNote(kind: "digest@zcode", claim: "zcode twin digest", at: old)
        try db.recordProjectNote(
            kind: "decision@owner", claim: "current owner decision", at: Date())
        try db.recordProjectNote(
            kind: "brief@\(bearer.digest)", claim: "external client brief", at: old)
        let userID = try db.appendChatMessage(
            sessionID: "qoder-v49-session", role: "user",
            content: "v49 keeps chat history", model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: "qoder-v49-session", userMessageID: userID,
            assistantText: "local answer", model: nil, createdAt: Date())
        try db.recordTurnDigest(
            sessionID: "qoder-v49-session", turnIndex: 1,
            digest: "v49 keeps digest history", keywords: "v49")
        let chatBefore = try rawText("SELECT COUNT(*) FROM chat_messages;")
        let digestBefore = try rawText("SELECT COUNT(*) FROM turn_digests;")
        db.close()

        try rawExecute("DELETE FROM schema_migrations WHERE version=49;")
        let migrated = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try migrated.runMigrations()

        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM project_notes WHERE kind NOT LIKE '%@%';"),
            "0", "no scope-less kind survives v49")
        for suffix in ["@codex", "@zcode", "@qoder"] {
            XCTAssertEqual(
                try rawText(
                    "SELECT COUNT(*) FROM project_notes WHERE kind LIKE '%\(suffix)';"),
                "0", "the per-provider twin \(suffix) is retired")
        }
        XCTAssertEqual(
            try migrated.currentProjectNote(kind: "decision@owner")?.claim,
            "current owner decision",
            "a newer owner judgement is not overwritten by older residue")
        XCTAssertEqual(
            try migrated.currentProjectNote(kind: "status@owner")?.claim,
            "newest qoder status",
            "the newest legacy claim is folded into owner rather than dropped")
        XCTAssertEqual(
            try migrated.currentProjectNote(kind: "window@owner")?.claim,
            "scopeless window")
        XCTAssertEqual(
            try migrated.currentProjectNote(kind: "brief@\(bearer.digest)")?.claim,
            "external client brief", "a bearer namespace is not touched by the fold")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM chat_messages;"), chatBefore,
                       "v49 corrects note namespaces, not development history")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM turn_digests;"), digestBefore)
        let notesBefore = try rawText("SELECT COUNT(*) FROM project_notes;")
        try migrated.runMigrations()
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM project_notes;"), notesBefore,
                       "the migration must be idempotent")
        migrated.close()
    }

    func testScopedKindNeverReturnsAScopelessKind() throws {
        for scope in [nil, "", "all"] as [String?] {
            XCTAssertEqual(ESISDatabase.scopedKind("brief", scope: scope), "brief@owner")
        }
        XCTAssertEqual(ESISDatabase.scopedKind("brief", scope: "owner"), "brief@owner")
        let digest = String(repeating: "b", count: 64)
        XCTAssertEqual(
            ESISDatabase.scopedKind("brief", scope: digest), "brief@\(digest)")
    }

    func testMCPNoteWritesAlwaysLandInANamespace() throws {
        for kind in ["brief", "contract", "status", "decision", "window",
                     "open-question", "resume", "digest"] {
            let written = try HTTPServer.runMCPTool(
                name: "simigo_project_note",
                arguments: ["kind": kind, "claim": "namespaced \(kind)"],
                databaseURL: dbURL)
            XCTAssertEqual(written["kind"] as? String, "\(kind)@owner")
        }
        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM project_notes WHERE kind NOT LIKE '%@%';"),
            "0", "the session entry point cannot create a scope-less judgement")
        let read = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:], databaseURL: dbURL)
        XCTAssertEqual(read["scope"] as? String, "owner")
    }

    private func rawExecute(_ sql: String) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK)
        guard let handle else { throw NSError(domain: "MCPInformationSpaceTests", code: 1) }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &message)
        if status != SQLITE_OK {
            let detail = message.map { String(cString: $0) } ?? "SQLite error \(status)"
            sqlite3_free(message)
            throw NSError(domain: "MCPInformationSpaceTests", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: detail])
        }
    }

    private func rawText(_ sql: String) throws -> String {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK)
        guard let handle else { return "" }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &stmt, nil), SQLITE_OK)
        guard let stmt else { return "" }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    // MARK: - Protocol shape

    func testInitializeToolsListAndNotificationShape() throws {
        let server = makeServer()
        let credential = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let initResponse = server.mcpResponse(
            for: [
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": ["clientInfo": ["name": "lan-agent"],
                           "_meta": ["com.simigo/client-identity": "forged"]],
            ],
            databaseURL: dbURL,
            clientIdentityID: credential.digest)
        let initResult = initResponse?["result"] as? [String: Any]
        XCTAssertEqual(initResult?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil(initResult?["capabilities"])
        XCTAssertNil(initResult?["_meta"], "MCP initialize never transports identity")
        XCTAssertTrue((initResult?["instructions"] as? String)?.contains("brief@\(credential.digest)") == true)

        let reconnect = server.mcpResponse(
            for: ["jsonrpc": "2.0", "id": 11, "method": "initialize"],
            databaseURL: dbURL,
            clientIdentityID: credential.digest)
        XCTAssertNil((reconnect?["result"] as? [String: Any])?["_meta"])
        let listResponse = server.mcpResponse(
            for: ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            databaseURL: dbURL)
        let tools = (listResponse?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
        let declared = Set(HTTPServer.mcpToolDefinitions.compactMap { $0["name"] as? String })
        XCTAssertEqual(names, declared, "served tools must equal declared tools")
        let call = server.mcpResponse(
            for: ["jsonrpc": "2.0", "id": 12, "method": "tools/call",
                  "params": ["name": "simigo_es_list", "arguments": [:]]],
            databaseURL: dbURL, clientIdentityID: credential.digest)
        XCTAssertEqual((call?["result"] as? [String: Any])?["isError"] as? Bool, false,
                       "HTTP-authenticated identity works without params._meta")
        XCTAssertNil(server.mcpResponse(for: [
            "jsonrpc": "2.0", "method": "notifications/initialized",
        ]), "a notification carries no response")
        let unknown = server.mcpResponse(for: [
            "jsonrpc": "2.0", "id": 3, "method": "does/not/exist",
        ])
        XCTAssertEqual((unknown?["error"] as? [String: Any])?["code"] as? Int, -32601)
    }
    func testLocalAndRemoteMCPUseSharedHTTPIdentityContext() throws {
        let server = makeServer()
        let credential = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        func response(_ method: String, id: Int, params: [String: Any],
                      clientIdentityID: String) throws -> [String: Any] {
            try XCTUnwrap(server.mcpResponse(
                for: ["jsonrpc": "2.0", "id": id, "method": method, "params": params],
                databaseURL: dbURL, clientIdentityID: clientIdentityID))
        }
        func assertSuccessfulToolCall(_ reply: [String: Any]) throws {
            let result = try XCTUnwrap(reply["result"] as? [String: Any])
            XCTAssertEqual(result["isError"] as? Bool, false, "\(result)")
        }
        let localInit = try response("initialize", id: 1, params: [
            "_meta": ["com.simigo/client-identity": credential.token],
            "clientInfo": ["name": "qoder"],
        ], clientIdentityID: ESISDatabase.ownerNamespace)
        let localResult = try XCTUnwrap(localInit["result"] as? [String: Any])
        XCTAssertNil(localResult["_meta"])
        XCTAssertTrue((localResult["instructions"] as? String)?.contains("brief@owner") == true)
        for (index, provider) in ["qoder", "codex", "zcode"].enumerated() {
            try assertSuccessfulToolCall(response(
                "tools/call", id: index + 2, params: [
                    "name": "simigo_chat_round",
                    "arguments": [
                        "session_id": "\(provider)-local-session",
                        "request_id": "local-round-\(index + 1)",
                        "user": "local shared identity", "assistant": "\(provider) response",
                        "boundary": "local MCP provider identity test",
                    ],
                    "_meta": ["com.simigo/client-identity": credential.token],
                ], clientIdentityID: ESISDatabase.ownerNamespace))
        }
        let remoteInit = try response("initialize", id: 10, params: [
            "clientInfo": ["name": "remote-agent"],
            "_meta": ["com.simigo/client-identity": "forged"],
        ], clientIdentityID: credential.digest)
        let remoteResult = try XCTUnwrap(remoteInit["result"] as? [String: Any])
        XCTAssertNil(remoteResult["_meta"])
        XCTAssertTrue((remoteResult["instructions"] as? String)?.contains("brief@\(credential.digest)") == true)
        try assertSuccessfulToolCall(response("tools/call", id: 11, params: [
            "name": "simigo_chat_round",
            "arguments": [
                "session_id": "remote-session", "request_id": "remote-round-1",
                "user": "remote identity", "assistant": "remote response",
                "boundary": "remote shared HTTP Client test",
            ],
        ], clientIdentityID: credential.digest))
        try assertSuccessfulToolCall(response("tools/call", id: 12, params: [
            "name": "simigo_chat_round",
            "arguments": [
                "session_id": "remote-session-2", "request_id": "remote-round-2",
                "user": "remote identity two", "assistant": "remote response two",
                "boundary": "metadata does not choose identity",
            ],
            "_meta": ["com.simigo/client-identity": "forged"],
        ], clientIdentityID: credential.digest))
        try assertSuccessfulToolCall(response("tools/call", id: 13, params: [
            "name": "simigo_es_list", "arguments": [:],
            "_meta": ["com.simigo/client-identity": credential.token],
        ], clientIdentityID: ESISDatabase.ownerNamespace))
        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        let ownerSessions = Set(try db.chatSessionIDs(clientIdentityID: ESISDatabase.ownerNamespace))
        let clientSessions = Set(try db.chatSessionIDs(clientIdentityID: credential.digest))
        for provider in ["qoder", "codex", "zcode"] {
            XCTAssertTrue(ownerSessions.contains("\(provider)-local-session"))
        }
        XCTAssertTrue(clientSessions.contains("mcp-\(credential.digest)-remote-session"))
        XCTAssertTrue(clientSessions.contains("mcp-\(credential.digest)-remote-session-2"))
        XCTAssertFalse(ownerSessions.contains("mcp-\(credential.digest)-remote-session"))
        db.close()
    }
    func testLANClientCannotEnumerateOrInvokeOwnerOnlyMCPTools() throws {
        let server = makeServer()
        let credential = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let listing = try XCTUnwrap(server.mcpResponse(
            for: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"],
            databaseURL: dbURL, clientIdentityID: credential.digest))
        let tools = ((listing["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        let names = Set(tools.compactMap { $0["name"] as? String })
        for name in [
            "simigo_is_status", "simigo_roots_list",
            "simigo_root_register", "simigo_is_reconcile",
        ] {
            XCTAssertFalse(names.contains(name), "\(name) is owner-only")
            let denied = try XCTUnwrap(server.mcpResponse(
                for: [
                    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": ["name": name, "arguments": [:]],
                ],
                databaseURL: dbURL, clientIdentityID: credential.digest))
            XCTAssertEqual(
                (denied["result"] as? [String: Any])?["isError"] as? Bool,
                true, "\(name) must reject direct invocation")
        }
    }

    func testLANClientCannotReadOwnerOnlyHTTPInformationRoutes() {
        let ownerOnly = [
            ("GET", "/v1/simigo/env"),
            ("GET", "/v1/simigo/roots"),
            ("GET", "/v1/simigo/is/status"),
            ("GET", "/v1/simigo/is/dependency"),
            ("GET", "/v1/simigo/is/file"),
            ("GET", "/v1/simigo/is/object"),
            ("POST", "/v1/simigo/is/reconcile"),
            ("PUT", "/v1/simigo/roots"),
            ("POST", "/v1/simigo/roots"),
            ("POST", "/v1/branches/fork"),
            ("POST", "/v1/branches/delete"),
            ("POST", "/v1/branches/list"),
        ]
        for (method, path) in ownerOnly {
            XCTAssertTrue(HTTPServer.isOwnerOnlyInformationRoute(
                method: method, path: path), "\(method) \(path)")
        }
        XCTAssertFalse(HTTPServer.isOwnerOnlyInformationRoute(
            method: "GET", path: "/v1/simigo/is/settlement"))
        XCTAssertFalse(HTTPServer.isOwnerOnlyInformationRoute(
            method: "POST", path: "/v1/simigo/is/declare-reuse"))
    }

    func testRemoteMCPRequiresTLSWhileLoopbackCanUsePlainHTTP() {
        let port = NWEndpoint.Port(rawValue: 8000)!
        let loopbackV4 = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
        let loopbackV6 = NWEndpoint.hostPort(host: .ipv6(.loopback), port: port)
        let remote = NWEndpoint.hostPort(
            host: .ipv4(IPv4Address("192.0.2.10")!), port: port)

        XCTAssertTrue(HTTPServer.isMCPPeerAllowed(endpoint: loopbackV4, isTLS: false))
        XCTAssertTrue(HTTPServer.isMCPPeerAllowed(endpoint: loopbackV6, isTLS: false))
        XCTAssertFalse(HTTPServer.isMCPPeerAllowed(endpoint: remote, isTLS: false))
        XCTAssertTrue(HTTPServer.isMCPPeerAllowed(endpoint: remote, isTLS: true))
    }

    func testJSONRPCEnvelopeAndToolArgumentShapesFailClosed() {
        let server = makeServer()

        let missingVersion = server.mcpResponse(for: [
            "id": 10, "method": "tools/list",
        ])
        XCTAssertEqual(
            (missingVersion?["error"] as? [String: Any])?["code"] as? Int,
            -32600,
            "JSON-RPC requests must declare the exact 2.0 version")

        let wrongVersion = server.mcpResponse(for: [
            "jsonrpc": "1.0", "id": 11, "method": "tools/list",
        ])
        XCTAssertEqual(
            (wrongVersion?["error"] as? [String: Any])?["code"] as? Int,
            -32600)

        let scalarParams = server.mcpResponse(for: [
            "jsonrpc": "2.0", "id": 12,
            "method": "tools/list", "params": "not-an-object",
        ])
        XCTAssertEqual(
            (scalarParams?["error"] as? [String: Any])?["code"] as? Int,
            -32602,
            "scalar params must not silently become an empty dictionary")

        let malformedArguments = server.mcpResponse(for: [
            "jsonrpc": "2.0", "id": 13, "method": "tools/call",
            "params": [
                "name": "simigo_project_brief",
                "arguments": "not-an-object",
            ],
        ])
        XCTAssertEqual(
            (malformedArguments?["error"] as? [String: Any])?["code"] as? Int,
            -32602,
            "malformed tool arguments must be rejected before dispatch")
        XCTAssertNil(malformedArguments?["result"])

        let booleanID = server.mcpResponse(for: [
            "jsonrpc": "2.0", "id": true, "method": "tools/list",
        ])
        XCTAssertEqual(
            (booleanID?["error"] as? [String: Any])?["code"] as? Int,
            -32600,
            "a JSON boolean is not a JSON-RPC string/number/null id")
        XCTAssertTrue(booleanID?["id"] is NSNull)
    }

    func testInformationSearchRejectsMalformedScopeFiltersBeforeOpeningDatabase() throws {
        let malformed: [[String: Any]] = [
            ["session_id": 7],
            ["request_id": false],
            ["root_ids": "root-1"],
            ["root_ids": ["root-1", 7]],
            ["session_ids": "one-session"],
            ["session_ids": ["session-a", NSNull()]],
            ["include_chat": "false"],
            ["include_brief": 0],
            ["limit": true],
            ["limit": 1.5],
        ]

        for invalidFields in malformed {
            var arguments: [String: Any] = ["query": "needle"]
            for (key, value) in invalidFields {
                arguments[key] = value
            }
            XCTAssertThrowsError(
                try HTTPServer.runMCPTool(
                    name: "simigo_is_search",
                    arguments: arguments,
                    databaseURL: dbURL),
                "malformed search scope must be refused: \(invalidFields)")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: dbURL.path),
                "invalid filters must be rejected before opening the IS database")
        }
    }

    func testBeginRejectsMalformedExecutionIdentityBeforeOpeningDatabase() throws {
        let malformed: [[String: Any]] = [
            ["state_id": 42],
            ["state_id": ""],
            ["parent_state_id": ["not", "an", "id"]],
            ["position": true],
            ["position": -1],
            ["position": 1.5],
        ]

        for invalidFields in malformed {
            var arguments: [String: Any] = [
                "model": "external-model", "tokenizer": "external-tokenizer",
            ]
            for (key, value) in invalidFields {
                arguments[key] = value
            }
            XCTAssertThrowsError(
                try HTTPServer.runMCPTool(
                    name: "simigo_es_begin",
                    arguments: arguments,
                    databaseURL: dbURL),
                "malformed execution identity must be refused: \(invalidFields)")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: dbURL.path),
                "invalid begin arguments must not create an ES or open the IS database")
        }
    }

    func testBeginAcceptsIntegralNSNumberValuesIncludingIntBoundaries() throws {
        let positions: [(String, Any, Int)] = [
            ("position-int", 1, 1),
            ("position-integral-double", 1.0, 1),
            ("position-int-max", Int.max, Int.max),
        ]

        for (stateID, rawPosition, expected) in positions {
            let result = try HTTPServer.runMCPTool(
                name: "simigo_es_begin",
                arguments: [
                    "model": "external-model",
                    "tokenizer": "external-tokenizer",
                    "state_id": stateID,
                    "position": rawPosition,
                ],
                databaseURL: dbURL)
            XCTAssertEqual(result["position"] as? Int, expected)
        }
    }

    func testSettleRejectsMalformedSourceAndDependencyFieldsWithoutSettlement() throws {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "external-model", "tokenizer": "external-tokenizer"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)

        let malformed: [[String: Any]] = [
            ["dependencies": "missing-array"],
            ["dependencies": [["dependency_id": "dep-1"], "not-an-object"]],
            ["actions": "not-an-array"],
            ["source_type": 7],
            ["source_revision": true],
            ["source_revision": 1.5],
            ["session_id": false],
            ["reuse_contract": "not-an-object"],
        ]

        for invalidFields in malformed {
            var arguments: [String: Any] = [
                "state_id": stateID,
                "model": "external-model",
                "tokenizer": "external-tokenizer",
                "output": "must not settle",
            ]
            for (key, value) in invalidFields {
                arguments[key] = value
            }
            XCTAssertThrowsError(
                try HTTPServer.runMCPTool(
                    name: "simigo_es_settle",
                    arguments: arguments,
                    databaseURL: dbURL),
                "malformed settle input must be refused: \(invalidFields)")
            XCTAssertEqual(
                try rawText("SELECT COUNT(*) FROM settlements;"), "0",
                "refusing malformed provenance must not leave a settlement")
        }

        // A refusal does not consume the begun ES; a correctly shaped settle
        // remains possible afterwards.
        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID, "model": "external-model",
                "tokenizer": "external-tokenizer", "output": "valid result",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(settled["validity"] as? String, "valid")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "1")
    }

    func testMCPWriteSelectorsAndAuditFieldsRejectMalformedValuesBeforeDatabaseOpen() throws {
        let malformed: [(String, [String: Any])] = [
            ("simigo_roots_list", ["category": false]),
            ("simigo_is_reconcile", ["category": 7]),
            ("simigo_project_note", [
                "kind": "brief", "claim": "must not write shared brief", "scope": 42,
            ]),
            ("simigo_project_brief", ["kind": ["not-a-kind"]]),
            ("simigo_project_brief", ["scope": false]),
            ("simigo_project_brief", ["session_id": 17]),
            ("simigo_chat_correct", [
                "session_id": "codex-a", "request_id": "r1",
                "role": "system", "text": "wrong target",
                "reason": "test", "actor": "test",
            ]),
            ("simigo_chat_round", [
                "session_id": "codex-a", "request_id": "r2",
                "user": "question", "assistant": "answer", "turn_index": true,
            ]),
            ("simigo_es_fail", [
                "state_id": "s1", "detail": "failed", "phase": "unknown",
            ]),
            ("simigo_es_fail", [
                "state_id": "s1", "detail": "failed", "attempt": 0,
            ]),
            ("simigo_es_fail", [
                "state_id": "s1", "detail": "failed", "evidence": "not-an-object",
            ]),
        ]

        for (tool, arguments) in malformed {
            XCTAssertThrowsError(
                try HTTPServer.runMCPTool(
                    name: tool, arguments: arguments, databaseURL: dbURL),
                "\(tool) must refuse malformed selector/audit fields: \(arguments)")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: dbURL.path),
                "invalid \(tool) arguments must not open or mutate the IS database")
        }
    }

    // MARK: - Same native operations

    func testRootRegisterIsIndexOnlyAndSearchResolvesIt() throws {
        let root = dir.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("alpha\nneedle body\n".utf8)
            .write(to: root.appendingPathComponent("doc.md"))

        let registered = try HTTPServer.runMCPTool(
            name: "simigo_root_register",
            arguments: ["path": root.path], databaseURL: dbURL)
        XCTAssertEqual(registered["registered"] as? Bool, true)
        let settle = registered["content_settle"] as? [String: Any]
        XCTAssertEqual(settle?["index_only"] as? Bool, true)
        XCTAssertEqual(settle?["settled"] as? Int, 1)

        XCTAssertEqual(try rawText(
            "SELECT COUNT(*) FROM file_contents WHERE object_id IS NOT NULL;"), "0",
            "the index stores a locator + digest, never the entity bytes")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM file_contents;"), "1")

        let search = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "needle", "include_chat": false,
                "request_id": "mcp-needle-1",
            ],
            databaseURL: dbURL)
        let items = search["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?["text"] as? String, "needle body")
        XCTAssertEqual(items?.first?["kind"] as? String, "file")
        XCTAssertEqual(search["reused"] as? Bool, false)

        // The same declared request reuses its settled result, reading no new
        // bytes.
        let again = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "needle", "include_chat": false,
                "request_id": "mcp-needle-1",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(again["reused"] as? Bool, true)
        XCTAssertEqual(again["demand_id"] as? String, search["demand_id"] as? String)

        // Without a request identity two calls are independent requests: the
        // shared retrieval is reused as knowledge, never fused into one demand
        // lifecycle.
        let unrelated = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": "needle", "include_chat": false],
            databaseURL: dbURL)
        XCTAssertEqual(unrelated["reused"] as? Bool, false)
        XCTAssertNotEqual(
            unrelated["demand_id"] as? String, search["demand_id"] as? String)

        // A changed file fails digest verification and stops being cited.
        try Data("different\n".utf8)
            .write(to: root.appendingPathComponent("doc.md"))
        let afterChange = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "needle", "include_chat": false,
                "request_id": "mcp-needle-1",
            ],
            databaseURL: dbURL)
        XCTAssertEqual((afterChange["items"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(
            (afterChange["stale_items"] as? [String])?.count, 1)
        XCTAssertEqual((afterChange["changed_sources"] as? [String])?.count, 1)
        XCTAssertEqual(afterChange["unavailable_sources"] as? [String], [])
    }

    func testUnavailableIndexedSourceIsTransientAndDoesNotInvalidateRetrievals() throws {
        let root = dir.appendingPathComponent("unavailable-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("available.md")
        try Data("needle in a physical source".utf8).write(to: source)
        let registered = try HTTPServer.runMCPTool(
            name: "simigo_root_register", arguments: ["path": root.path], databaseURL: dbURL)
        XCTAssertEqual((registered["content_settle"] as? [String: Any])?["index_only"] as? Bool, true)

        let first = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": "needle", "include_chat": false, "request_id": "availability-check"],
            databaseURL: dbURL)
        let firstItems = try XCTUnwrap(first["items"] as? [[String: Any]])
        XCTAssertEqual(firstItems.count, 1)
        let itemID = try XCTUnwrap(firstItems.first?["item_id"] as? String)
        let firstDemandID = try XCTUnwrap(first["demand_id"] as? String)
        let firstSettlementID = try XCTUnwrap(first["retrieval_settlement_id"] as? String)

        // ENOENT is an unavailable result for this call, not a validity event.
        try FileManager.default.removeItem(at: source)
        let unavailable = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": "needle", "include_chat": false, "request_id": "availability-check"],
            databaseURL: dbURL)
        XCTAssertEqual((unavailable["items"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(unavailable["unavailable_sources"] as? [String], [itemID])
        XCTAssertEqual(unavailable["changed_sources"] as? [String], [])
        XCTAssertEqual(unavailable["stale_items"] as? [String], [])
        XCTAssertNotEqual(unavailable["demand_id"] as? String, firstDemandID)
        XCTAssertEqual(
            try rawText("SELECT validity FROM settlement_current_validity WHERE settlement_id='" + firstSettlementID + "';"),
            "valid")
        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM settlement_risk_notices WHERE settlement_id='" + firstSettlementID + "';"),
            "0")
    }

    func testUnknownToolAndMissingSettlementFailClosed() throws {
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_no_such_tool",
            arguments: [:], databaseURL: dbURL))

        do {
            _ = try HTTPServer.runMCPTool(
                name: "simigo_is_settlement",
                arguments: ["settlement_id": "missing"], databaseURL: dbURL)
            XCTFail("an unknown settlement must not resolve")
        } catch {
            XCTAssertTrue(
                String(describing: error).contains("not owned by this MCP client identity"),
                "ownership is checked before settlement existence to avoid an existence oracle")
        }
    }

    // MARK: - Post-settlement distillation

    func testSettlementSummaryIsReadableAndCitableOverMCP() throws {
        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        let loop = InformationLoop(database: db)
        let turn = try loop.settleTurn(
            generatedText: "施工组织设计以实施性方案为纲，覆盖关键线路与节点工期。",
            resolution: nil, stateID: "S-MCP-1", parentStateID: nil, position: 0,
            modelIdentity: "test-model",
            identity: .init(model: "m", tokenizer: "t"),
            sessionID: "mcp-alpha", summaryQuery: "施工组织设计要点",
            actions: ["chat.completion"])
        db.close()

        let receipt = try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": turn.settlementID], databaseURL: dbURL)
        let summary = try XCTUnwrap(receipt["summary"] as? [String: Any])
        XCTAssertEqual(summary["query"] as? String, "施工组织设计要点")
        XCTAssertTrue((summary["text"] as? String ?? "").contains("关键线路"))
        XCTAssertEqual(
            summary["source_payload_digest"] as? String,
            receipt["payload_sha256"] as? String,
            "a summary names the payload digest it distilled")

        let status = try HTTPServer.runMCPTool(
            name: "simigo_is_status", arguments: [:], databaseURL: dbURL)
        XCTAssertEqual(status["settlement_summaries"] as? Int, 1)

        let search = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "关键线路 节点工期",
                "include_chat": false,
                "session_ids": ["mcp-beta"],
            ],
            databaseURL: dbURL)
        let items = try XCTUnwrap(search["items"] as? [[String: Any]])
        let cited = try XCTUnwrap(items.first { $0["kind"] as? String == "settlement" })
        XCTAssertEqual(cited["item_id"] as? String, "settlement:\(turn.settlementID)")
        XCTAssertEqual(cited["source_sha256"] as? String, summary["sha256"] as? String)
    }

    // MARK: - Execution lifecycle wiring
    //
    // The point of these tests is NOT that JSON-RPC answers. A cloud agent's
    // model call happens outside SimiGo, so "MCP connected" says nothing about
    // whether anything was recorded: these assert what the tool call actually
    // wrote into the authoritative store.

    func testBeginSettleRecordsAuthoritativeSettlement() throws {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)
        XCTAssertEqual(begun["settled"] as? Bool, false)
        XCTAssertTrue(begun["reusable_answer"] is NSNull)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0",
                       "beginning an execution records no result")

        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "output": "the exit is north",
                "session_id": "cloud-a",
                "query": "where is the exit",
            ],
            databaseURL: dbURL)
        // Printed before any assertion: a failure here symbolicates through a
        // dSYM and can stall the report, so the raw reply must reach the log.
        print("[MCP-SETTLE] \(settled)")
        let settlementID = try XCTUnwrap(settled["settlement_id"] as? String)
        let payloadSHA = try XCTUnwrap(settled["payload_sha256"] as? String)
        XCTAssertEqual(settled["state_id"] as? String, stateID)
        XCTAssertEqual(settled["validity"] as? String, "valid")
        XCTAssertEqual(settled["summary_recorded"] as? Bool, true)
        XCTAssertEqual((settled["dependencies"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "1")

        // A declared source must already be sealed in the carrier: the follow-up
        // turn cites the first result's payload object, and that dependency row
        // commits with the settlement instead of after it.
        let begunFollowUp = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-b", "query": "what did you just say",
            ],
            databaseURL: dbURL)
        let followUpState = try XCTUnwrap(begunFollowUp["state_id"] as? String)
        let followUp = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": followUpState, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "output": "I said the exit is north",
                "session_id": "cloud-b", "query": "what did you just say",
                "dependencies": [[
                    "dependency_id": "prior-result",
                    "content_address": payloadSHA,
                    "reason": "restates the prior answer",
                ]],
            ],
            databaseURL: dbURL)
        print("[MCP-SETTLE-DEP] \(followUp)")
        let followUpID = try XCTUnwrap(followUp["settlement_id"] as? String)
        let declared = followUp["dependencies"] as? [[String: Any]]
        XCTAssertEqual(declared?.count, 1, "settle=\(followUp)")
        XCTAssertEqual(declared?.first?["content_address"] as? String, payloadSHA)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM is_dependency_entries;"), "1",
                       "the declared source is a row in the authoritative store")

        // The producer identity is in the table, not only in the reply — this is
        // what stops another engine from inheriting the answer.
        let receipt = try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": followUpID], databaseURL: dbURL)
        print("[MCP-SETTLE-RECEIPT] \(receipt)")
        let bindings = try XCTUnwrap(receipt["bindings"] as? [String: String])
        XCTAssertNotNil(bindings[SettlementIdentityBinding.modelKey])
        XCTAssertNotNil(bindings[SettlementIdentityBinding.tokenizerKey])
        XCTAssertEqual(
            (receipt["dependencies"] as? [[String: Any]])?.count, 1,
            "the declared dependency is readable back from the settlement: \(receipt)")

        // A declared source that is not a sealed object refuses the whole
        // settle: nothing is recorded, and the state is still settleable after.
        let unsealedState = try XCTUnwrap(
            try HTTPServer.runMCPTool(
                name: "simigo_es_begin",
                arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
                databaseURL: dbURL)["state_id"] as? String)
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": unsealedState, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": "unsourced",
                "dependencies": [["dependency_id": "doc-1", "content_address": "abc"]],
            ],
            databaseURL: dbURL))
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2",
                       "an unsealed dependency leaves no settlement behind")
        let rescued = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": unsealedState, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": "unsourced",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(rescued["validity"] as? String, "valid",
                       "the refused settle did not consume the state: \(rescued)")

        // One state settles once, and only under the engine it was begun with.
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": "again",
            ],
            databaseURL: dbURL))
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "3")
    }

    func testSettleWithoutBeginAndWrongModelFailClosed() throws {
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": "never-begun", "model": "m",
                "tokenizer": "t", "output": "text",
            ],
            databaseURL: dbURL), "a settlement cannot precede its execution")

        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "model-a", "tokenizer": "tok"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)

        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID, "model": "model-b",
                "tokenizer": "tok", "output": "text",
            ],
            databaseURL: dbURL), "two engines are not interchangeable on one state")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0")
    }

    func testBeginDoesNotServeSettledAnswerWithoutCurrentDemand() throws {
        let first = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-a", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        let firstState = try XCTUnwrap(first["state_id"] as? String)
        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": firstState, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": "the exit is north",
                "session_id": "cloud-a", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        XCTAssertTrue(
            (settled["demand_id"] as? String)?.isEmpty == false,
            "the answer is published, but without a resolved retrieval basis")

        let again = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-a", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        XCTAssertNotEqual(again["state_id"] as? String, firstState)
        // begin resolves no current demand, so it has no identity to gate a
        // historical answer on and must not serve one.
        XCTAssertTrue(again["reusable_answer"] is NSNull)

        // The answer is still recorded; only the unverified begin path refuses.
        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        let answered = try XCTUnwrap(
            try db.answeredDemand(sessionID: "cloud-a", query: "where is the exit"))
        XCTAssertFalse(answered.answerSettlementID.isEmpty)
        db.close()

        // The same lack of a retrieval basis also fails closed across engines
        // and scopes; neither should be handed a historical answer as reusable.
        let otherModel = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "other-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-a", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        XCTAssertTrue(otherModel["reusable_answer"] is NSNull)
        let otherScope = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-b", "query": "where is the exit",
            ],
            databaseURL: dbURL)
        XCTAssertTrue(otherScope["reusable_answer"] is NSNull)

        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "1")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM information_reuse_events;"), "0")
    }

    func testFailureIsAuditedAndNeverBecomesASettlement() throws {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)

        let failed = try HTTPServer.runMCPTool(
            name: "simigo_es_fail",
            arguments: [
                "state_id": stateID, "detail": "cloud API returned 529",
                "evidence": ["status": "529"],
            ],
            databaseURL: dbURL)
        XCTAssertEqual(failed["audit_persisted"] as? Bool, true)
        XCTAssertEqual(failed["settlement_id"] as? String, "",
                       "a failure never fabricates a settlement")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0")

        // The audit is append-only: a second attempt under the same execution id
        // is reported as a duplicate instead of overwriting the first record.
        let retry = try HTTPServer.runMCPTool(
            name: "simigo_es_fail",
            arguments: ["state_id": stateID, "detail": "again"],
            databaseURL: dbURL)
        XCTAssertEqual(retry["audit_persisted"] as? Bool, false)
        XCTAssertEqual(retry["failure_class"] as? String, "duplicate_execution_id")
    }

    // MARK: - Sourced settlement (D-2)
    //
    // The documented cloud-agent loop is search → settle citing that retrieval →
    // begin. Before D-2 the retrieval demand carried no session, so the settled
    // answer was authoritative but unfindable by `reusable_answer`.

    /// Registers a root, searches it under `session`, then settles the answer
    /// WITH the retrieval settlement as its source — the exact loop that used to
    /// skip the session-demand publish.
    @discardableResult
    private func settleSourcedAnswer(
        session: String, query: String, answer: String,
        includeChat: Bool = false
    ) throws -> [String: Any] {
        let root = dir.appendingPathComponent("sourced-\(session)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("alpha\nneedle body\n".utf8)
            .write(to: root.appendingPathComponent("doc.md"))
        _ = try HTTPServer.runMCPTool(
            name: "simigo_root_register",
            arguments: ["path": root.path], databaseURL: dbURL)

        let search = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: ["query": query, "include_chat": includeChat, "session_id": session],
            databaseURL: dbURL)
        let demandID = try XCTUnwrap(search["demand_id"] as? String)
        let retrievalID = try XCTUnwrap(search["retrieval_settlement_id"] as? String)
        XCTAssertFalse(retrievalID.isEmpty, "search=\(search)")
        // The demand row names its session in the existing schema: no migration.
        XCTAssertEqual(try rawText(
            "SELECT session_id FROM information_demands WHERE demand_id='\(demandID)';"),
            session)

        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)
        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID, "model": "cloud-model",
                "tokenizer": "cloud-tokenizer", "output": answer,
                "session_id": session, "query": query,
                "demand_id": demandID, "retrieval_settlement_id": retrievalID,
            ],
            databaseURL: dbURL)
        print("[MCP-SOURCED-SETTLE] demand=\(demandID) retrieval=\(retrievalID) "
            + "advancement=\(settled["advancement_id"] as? String ?? "") "
            + "reply=\(settled)")
        XCTAssertFalse(
            (settled["advancement_id"] as? String ?? "").isEmpty,
            "a sourced settle advances the retrieval demand: \(settled)")
        XCTAssertEqual(
            settled["demand_id"] as? String, "",
            "no session demand is published when the retrieval demand advanced")
        return [
            "demand_id": demandID,
            "retrieval_settlement_id": retrievalID,
            "settlement_id": settled["settlement_id"] as? String ?? "",
        ]
    }

    func testSourcedSettleIsRecordedButNotServedByBegin() throws {
        let query = "needle"
        let session = "cloud-sourced-a"
        let settled = try settleSourcedAnswer(
            session: session, query: query, answer: "the vault is behind the stairs")

        let again = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": session, "query": query, "include_chat": false,
            ],
            databaseURL: dbURL)
        print("[MCP-SOURCED-REUSE] \(again["reusable_answer"] ?? "null")")
        XCTAssertTrue(
            again["reusable_answer"] is NSNull,
            "begin resolves no current demand and must not serve the answer: \(again)")

        // Same store, same schema: reopening it still finds the recorded answer.
        let reopened = try ESISDatabase(url: dbURL, createIfNeeded: false)
        let answered = try XCTUnwrap(
            try reopened.answeredDemand(sessionID: session, query: query))
        XCTAssertEqual(
            answered.answerSettlementID, settled["settlement_id"] as? String)
        reopened.close()
    }

    func testSourcedSettleIsNotReusableFromAnotherSession() throws {
        let query = "needle"
        try settleSourcedAnswer(
            session: "cloud-sourced-b", query: query, answer: "behind the stairs")

        let other = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "session_id": "cloud-sourced-c", "query": query,
            ],
            databaseURL: dbURL)
        XCTAssertTrue(
            other["reusable_answer"] is NSNull,
            "another session is another question: \(other)")
    }

    // MARK: - Cross-path source identity (裁定 2)
    //
    // A retry, a second entry point, and a genuine update all reach the same
    // entrance. The declared source identity decides which one this call is:
    // the same source at the same revision is not a new settlement, and only an
    // explicit new revision may create a version.

    private func declaredSource(
        _ message: String, revision: Int = 1, turn: String = "turn-7",
        session: String = "qoder-window-1"
    ) -> [String: Any] {
        [
            "source_type": "agent_turn",
            "source_session_id": session,
            "source_turn_id": turn,
            "source_message_id": message,
            "source_revision": revision,
        ]
    }

    private func beginMCPState() throws -> String {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        return try XCTUnwrap(begun["state_id"] as? String)
    }

    @discardableResult
    private func settleMCP(
        state: String, output: String, source: [String: Any] = [:],
        session: String = "cloud-identity", query: String = "where is the vault"
    ) throws -> [String: Any] {
        var arguments = source
        arguments["state_id"] = state
        arguments["model"] = "cloud-model"
        arguments["tokenizer"] = "cloud-tokenizer"
        arguments["output"] = output
        arguments["session_id"] = session
        arguments["query"] = query
        return try HTTPServer.runMCPTool(
            name: "simigo_es_settle", arguments: arguments, databaseURL: dbURL)
    }

    /// Every table an identical resubmission must leave untouched. Objects,
    /// summaries and indexes are included on purpose: an idempotent hit that
    /// only skipped `settlements` would still be a duplicate write elsewhere.
    private func writeCounters() throws -> [String: String] {
        var counts: [String: String] = [:]
        for table in [
            "settlements", "execution_states", "is_objects", "is_index_entries",
            "is_dependency_entries", "settlement_summaries",
            "settlement_source_identities", "settlement_operation_keys",
            "information_demands", "information_advancements",
        ] {
            counts[table] = try rawText("SELECT COUNT(*) FROM \(table);")
        }
        return counts
    }

    func testDeclaredSourceReplayReturnsTheExistingSettlement() throws {
        let source = declaredSource("msg-1")
        let first = try settleMCP(
            state: try beginMCPState(), output: "the vault is behind the stairs",
            source: source)
        print("[MCP-IDENTITY-FIRST] \(first)")
        let firstID = try XCTUnwrap(first["settlement_id"] as? String)
        let firstState = try XCTUnwrap(first["state_id"] as? String)
        XCTAssertEqual(first["reused"] as? Bool, false)

        // The retry's own execution state is begun BEFORE the baseline: an
        // execution state is per-request ES bookkeeping, not a settlement
        // write, so only the IS tables are expected to stay frozen.
        let replayState = try beginMCPState()
        let before = try writeCounters()

        // A retry through a fresh execution carries the same declared source:
        // it returns the existing settlement and writes nothing new.
        let replay = try settleMCP(
            state: replayState, output: "the vault is behind the stairs",
            source: source)
        print("[MCP-IDENTITY-REPLAY] \(replay)")
        XCTAssertEqual(replay["reused"] as? Bool, true)
        XCTAssertEqual(replay["settlement_id"] as? String, firstID)
        XCTAssertEqual(replay["state_id"] as? String, firstState,
                       "a replay returns the state that produced the result")
        XCTAssertEqual(try writeCounters(), before,
                       "an idempotent hit writes no settlement, object, index, summary or demand row")

        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM settlement_source_identities WHERE source_message_id='msg-1';"),
            "1")
    }

    func testSameRevisionWithDifferentOutputIsRefusedAtomically() throws {
        let source = declaredSource("msg-2")
        _ = try settleMCP(
            state: try beginMCPState(), output: "first answer", source: source)

        // Begin the refused attempt first, for the same reason as the replay
        // test: its execution state is allowed, its IS writes are not.
        let refusedState = try beginMCPState()
        let before = try writeCounters()
        XCTAssertThrowsError(try settleMCP(
            state: refusedState, output: "a different answer", source: source)
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("different payload digest"),
                "got: \(error)")
        }
        XCTAssertEqual(try writeCounters(), before,
                       "a refused identity conflict leaves no partial write")

        // The refusal did not consume the execution: it can still settle, and
        // the retry was never mistaken for an update.
        let rescued = try settleMCP(
            state: refusedState, output: "a different answer")
        XCTAssertEqual(rescued["reused"] as? Bool, false)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2")
    }

    func testExplicitRevisionTwoCreatesALinkedVersion() throws {
        let first = try settleMCP(
            state: try beginMCPState(), output: "revision one answer",
            source: declaredSource("msg-3"))
        let firstID = try XCTUnwrap(first["settlement_id"] as? String)

        // Same source, explicitly declared new revision, new content: a new
        // version linked to the one it supersedes.
        let second = try settleMCP(
            state: try beginMCPState(), output: "revision two answer",
            source: declaredSource("msg-3", revision: 2))
        print("[MCP-IDENTITY-REV2] \(second)")
        XCTAssertEqual(second["reused"] as? Bool, false)
        let secondID = try XCTUnwrap(second["settlement_id"] as? String)
        XCTAssertNotEqual(secondID, firstID)
        XCTAssertEqual(try rawText("""
        SELECT previous_settlement_id FROM settlement_source_identities
        WHERE source_message_id='msg-3' AND source_revision=2;
        """), firstID)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2")

        // Version numbers are never inferred or skipped...
        XCTAssertThrowsError(try settleMCP(
            state: try beginMCPState(), output: "revision four answer",
            source: declaredSource("msg-3", revision: 4))
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("next declared revision is 3"),
                "got: \(error)")
        }
        // ...and a declared update must actually change the result.
        XCTAssertThrowsError(try settleMCP(
            state: try beginMCPState(), output: "revision two answer",
            source: declaredSource("msg-3", revision: 3))
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("must change the result"),
                "got: \(error)")
        }
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2")
    }

    func testDifferentSourceMessagesWithIdenticalTextAreBothKept() throws {
        let text = "the same words from two different turns"
        let first = try settleMCP(
            state: try beginMCPState(), output: text,
            source: declaredSource("msg-a"))
        let second = try settleMCP(
            state: try beginMCPState(), output: text,
            source: declaredSource("msg-b"))
        XCTAssertEqual(first["reused"] as? Bool, false)
        XCTAssertEqual(second["reused"] as? Bool, false,
                       "different sources are never merged by text equality")
        XCTAssertNotEqual(
            first["settlement_id"] as? String, second["settlement_id"] as? String)
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "2")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlement_source_identities;"), "2")
        XCTAssertEqual(try rawText("""
        SELECT COUNT(DISTINCT payload_digest) FROM settlement_source_identities;
        """), "1", "the payloads are identical; only the declared sources differ")
    }

    // MARK: - Chat grouping

    func testInformationScopeGroupsByConversationOpening() {
        func scope(_ opening: String, _ lastUser: String) -> String {
            HTTPServer.informationScope(agentId: "agent", messages: [
                .object(["role": .string("system"), "content": .string("sys")]),
                .object(["role": .string("user"), "content": .string(opening)]),
                .object(["role": .string("assistant"), "content": .string("a")]),
                .object(["role": .string("user"), "content": .string(lastUser)]),
            ])
        }
        XCTAssertEqual(scope("first", "one"), scope("first", "two"),
                       "later turns stay in the same information scope")
        XCTAssertNotEqual(scope("first", "one"), scope("second", "one"),
                          "a different conversation is a different scope")
        XCTAssertTrue(scope("first", "one").hasPrefix("info-"))
    }

    func testBeginTokenizerIdentityIsFixedAcrossResumeAndSettle() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        defer { db.close() }
        let stateID = "tokenizer-bound-state"
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-a",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(begun["state_id"] as? String, stateID)
        XCTAssertEqual(
            try db.executionStateTokenizerIdentity(stateID), "tokenizer-a")

        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-b",
            ],
            databaseURL: dbURL),
            "resuming with a different tokenizer must fail closed")

        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-b",
                "output": "wrong tokenizer",
            ],
            databaseURL: dbURL),
            "settlement identity must match the tokenizer fixed at begin")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0")

        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-a",
                "output": "correct tokenizer",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(settled["validity"] as? String, "valid")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "1")
    }

    func testMCPStateSurvivesNativeGraphReconciliationAndKeepsTokenizerBinding() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        let stateID = "mcp-graph-isolation-\(UUID().uuidString)"
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-a",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(begun["state_id"] as? String, stateID)
        XCTAssertEqual(
            try rawText("SELECT graph_managed FROM execution_states WHERE state_id='\(stateID)';"),
            "0", "MCP-created ES is external to the native graph")

        // An empty native graph may remove native-owned states, but must not
        // erase an unsettled MCP execution it does not own.
        try db.writeGraph(states: [], checkpoints: [])
        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM execution_states WHERE state_id='\(stateID)';"),
            "1", "graph reconciliation must leave external MCP ES intact")
        db.close()

        // Reopen from SQLite alone, then prove the begin-time tokenizer remains
        // authoritative: a different tokenizer cannot claim the surviving ES.
        let reopened = try ESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertEqual(try reopened.executionStateTokenizerIdentity(stateID), "tokenizer-a")
        reopened.close()

        let resumed = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-a",
            ],
            databaseURL: dbURL)
        XCTAssertEqual(resumed["resumed"] as? Bool, true)
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "state_id": stateID,
                "model": "cloud-model",
                "tokenizer": "tokenizer-b",
            ],
            databaseURL: dbURL),
            "native graph sync must not make the MCP state look newly created")
        XCTAssertEqual(
            try rawText("SELECT tokenizer_identity FROM execution_states WHERE state_id='\(stateID)';"),
            "tokenizer-a")
    }

    func testLegacyMCPStateWithoutTokenizerCannotSettle() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        defer { db.close() }
        try db.recordExecutionState(
            id: "legacy-no-tokenizer", parentID: nil,
            modelIdentity: "cloud-model", position: 0,
            continuationID: "legacy", anchor: "",
            lifecycle: "active", createdAt: Date())

        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": "legacy-no-tokenizer",
                "model": "cloud-model",
                "tokenizer": "caller-asserted",
                "output": "must refuse",
            ],
            databaseURL: dbURL),
            "an absent begin-time tokenizer is not a wildcard")
        XCTAssertEqual(try rawText("SELECT COUNT(*) FROM settlements;"), "0")
    }

    // MARK: - Reuse declaration entry (owner ruling 2026-11-16)

    /// Begin + settle one external execution through the MCP facade, optionally
    /// carrying reuse terms inline (shape iii). Returns the whole settle reply so
    /// a caller can assert on what the settle reported, not only on the store.
    private func settleOne(
        session: String, query: String, output: String,
        reuseContract: [String: Any]? = nil
    ) throws -> (settlementID: String, reply: [String: Any]) {
        let begun = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "cloud-model", "tokenizer": "cloud-tokenizer"],
            databaseURL: dbURL)
        let stateID = try XCTUnwrap(begun["state_id"] as? String)
        var arguments: [String: Any] = [
            "state_id": stateID,
            "model": "cloud-model",
            "tokenizer": "cloud-tokenizer",
            "output": output,
            "session_id": session,
            "query": query,
        ]
        if let reuseContract { arguments["reuse_contract"] = reuseContract }
        let reply = try HTTPServer.runMCPTool(
            name: "simigo_es_settle", arguments: arguments, databaseURL: dbURL)
        return (try XCTUnwrap(reply["settlement_id"] as? String), reply)
    }

    /// Consumption reads `settlement_reuse_contracts` before anything else
    /// (`SettlementConsumption.consume`), and until this door existed only tests,
    /// rig CLIs and hand-written SQL could write that row — so zero-call
    /// consumption was unreachable from the product side even with the
    /// consumption authority wired. Declaring is still the caller's act: an
    /// undeclared settlement stays non-consumable however identical its text,
    /// re-declaring the same terms is idempotent, and changing them is refused
    /// rather than silently rewritten.
    func testReuseDeclarationEntryIsTheOnlyWayToBecomeConsumable() throws {
        let (settlementID, _) = try settleOne(
            session: "decl-a", query: "where is the exit",
            output: "the exit is north")
        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)

        // (a) undeclared: the row consumption reads first is absent.
        XCTAssertNil(try db.settlementReuseContract(settlementID: settlementID))
        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM settlement_reuse_contracts;"), "0",
            "the product never declares by itself")

        // (b) shape (i): the MCP door writes exactly the terms declared.
        let terms: [String: Any] = [
            "settlement_id": settlementID,
            "contract_id": SettlementConsumption.Contract.contractID,
            "demand_class": SettlementConsumption.Contract.demandClass,
            "contract_version": SettlementConsumption.Contract.version,
            "query": "where is the exit",
            "root_ids": ["root-a"],
        ]
        let declared = try HTTPServer.runMCPTool(
            name: "simigo_is_declare_reuse", arguments: terms, databaseURL: dbURL)
        print("[MCP-DECLARE-REUSE] \(declared)")
        XCTAssertEqual(declared["settlement_id"] as? String, settlementID)
        XCTAssertEqual(
            declared["contract_id"] as? String,
            SettlementConsumption.Contract.contractID)
        XCTAssertEqual(declared["root_ids"] as? [String], ["root-a"])
        XCTAssertEqual(
            declared["required_identity_json"] as? String, "{}",
            "engine identity is provenance until a caller declares it material")
        let digest = try XCTUnwrap(declared["canonical_digest"] as? String)
        XCTAssertFalse(digest.isEmpty)
        let row = try XCTUnwrap(
            try db.settlementReuseContract(settlementID: settlementID))
        XCTAssertEqual(row.query, "where is the exit")
        XCTAssertEqual(row.canonicalDigest, digest,
                       "the reply reports the committed basis, not the request")

        // (c) re-declaring the same terms is idempotent: one row, same basis.
        let again = try HTTPServer.runMCPTool(
            name: "simigo_is_declare_reuse", arguments: terms, databaseURL: dbURL)
        XCTAssertEqual(again["canonical_digest"] as? String, digest)
        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM settlement_reuse_contracts;"), "1")

        // (d) changed terms are refused, and the refused change is not written.
        var changed = terms
        changed["root_ids"] = ["root-a", "root-b"]
        XCTAssertThrowsError(
            try HTTPServer.runMCPTool(
                name: "simigo_is_declare_reuse", arguments: changed,
                databaseURL: dbURL),
            "terms a consumer may already rely on are never silently rewritten")
        XCTAssertEqual(
            try XCTUnwrap(
                try db.settlementReuseContract(settlementID: settlementID)).rootIDs,
            ["root-a"])

        // (e) an unstated term fails closed instead of defaulting into a
        //     declaration, and an unknown settlement is refused, not declared.
        var partial = terms
        partial.removeValue(forKey: "contract_version")
        XCTAssertThrowsError(
            try HTTPServer.runMCPTool(
                name: "simigo_is_declare_reuse", arguments: partial,
                databaseURL: dbURL))
        var unknown = terms
        unknown["settlement_id"] = "no-such-settlement"
        XCTAssertThrowsError(
            try HTTPServer.runMCPTool(
                name: "simigo_is_declare_reuse", arguments: unknown,
                databaseURL: dbURL))
        XCTAssertEqual(
            try rawText("SELECT COUNT(*) FROM settlement_reuse_contracts;"), "1",
            "a refused declaration leaves the store as it was")
    }

    /// Shape (iii): a settle may carry its terms, so a caller that already knows
    /// them declares in one step. The query defaults to the query the result was
    /// produced for — the basis this settlement was actually generated against.
    /// A refused declaration is reported beside the settlement that DID commit:
    /// additive like the demand publish, never a false "settle failed".
    func testSettleCarriedReuseContractDeclaresInOneStep() throws {
        let (plain, plainReply) = try settleOne(
            session: "decl-b", query: "which way out", output: "north")
        XCTAssertTrue(plainReply["reuse_contract"] is NSNull)
        XCTAssertEqual(plainReply["reuse_contract_error"] as? String, "")

        let (carried, carriedReply) = try settleOne(
            session: "decl-c", query: "which way out", output: "north",
            reuseContract: [
                "contract_id": SettlementConsumption.Contract.contractID,
                "demand_class": SettlementConsumption.Contract.demandClass,
                "contract_version": SettlementConsumption.Contract.version,
            ])
        print("[MCP-SETTLE-REUSE] \(carriedReply)")
        let inline = try XCTUnwrap(carriedReply["reuse_contract"] as? [String: Any])
        XCTAssertEqual(inline["settlement_id"] as? String, carried)
        XCTAssertEqual(inline["query"] as? String, "which way out",
                       "the basis defaults to the query the result answers")
        XCTAssertEqual(carriedReply["reuse_contract_error"] as? String, "")

        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertNil(try db.settlementReuseContract(settlementID: plain),
                     "a settle without terms declares nothing")
        let row = try XCTUnwrap(try db.settlementReuseContract(settlementID: carried))
        XCTAssertEqual(row.contractID, SettlementConsumption.Contract.contractID)
        XCTAssertEqual(row.extractField, SettlementConsumption.Contract.defaultExtractField)

        // A bad declaration does not undo the settlement it rode in on.
        let (broken, brokenReply) = try settleOne(
            session: "decl-d", query: "which way out", output: "north",
            reuseContract: ["demand_class": "exact-repeat"])
        XCTAssertEqual(brokenReply["validity"] as? String, "valid")
        XCTAssertTrue(brokenReply["reuse_contract"] is NSNull)
        XCTAssertFalse(
            (brokenReply["reuse_contract_error"] as? String ?? "").isEmpty,
            "the refusal is reported, not swallowed")
        XCTAssertNil(try db.settlementReuseContract(settlementID: broken))
    }

    func testInformationSearchCacheUsesContinuityAcrossRotatedSessions() throws {
        let continuityID = "search-thread-" + UUID().uuidString.lowercased()
        // Reuse the exact same demand basis while rotating only the transport session.
        let query = "continuity cache probe " + UUID().uuidString
        let initial = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": query,
                "session_id": "search-session-A",
                "continuity_id": continuityID,
                "request_id": "search-request-2",
                "include_chat": false,
                "include_brief": false,
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        let rotated = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": query,
                "session_id": "search-session-B",
                "continuity_id": continuityID,
                "request_id": "search-request-2",
                "include_chat": false,
                "include_brief": false,
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        XCTAssertEqual(initial["demand_id"] as? String, rotated["demand_id"] as? String)
        XCTAssertEqual(initial["reused"] as? Bool, false)
        XCTAssertEqual(rotated["reused"] as? Bool, true)

        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        let demandID = try XCTUnwrap(rotated["demand_id"] as? String)
        let row = try XCTUnwrap(try db.informationDemand(demandID: demandID))
        XCTAssertEqual(row.continuityID, continuityID)
        XCTAssertEqual(row.sessionID, "search-session-A",
                       "the original transport session remains audit provenance")
        db.close()
    }

    func testMCPContinuitySurvivesSessionRotationAndConsumptionRetry() throws {
        let continuityID = "agent-thread-" + UUID().uuidString.lowercased()
        let firstSession = "client-session-A"
        let firstBegin = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": firstSession,
                "continuity_id": continuityID,
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        let sourceStateID = try XCTUnwrap(firstBegin["state_id"] as? String)
        XCTAssertEqual(firstBegin["continuity_id"] as? String, continuityID)

        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": sourceStateID,
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "output": "the exit is north",
                "session_id": firstSession,
                "continuity_id": continuityID,
                "query": "where is the exit",
                "reuse_contract": [
                    "contract_id": SettlementConsumption.Contract.contractID,
                    "demand_class": SettlementConsumption.Contract.demandClass,
                    "contract_version": SettlementConsumption.Contract.version,
                ],
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        let sourceSettlementID = try XCTUnwrap(settled["settlement_id"] as? String)
        XCTAssertEqual(settled["continuity_id"] as? String, continuityID)
        XCTAssertEqual(settled["reuse_contract_error"] as? String, "")
        XCTAssertNotNil(settled["demand_id"] as? String)

        // Resolve this turn's current demand in the new MCP session. Its opaque
        // ID, not the repeated query string alone, authorizes the consume attempt.
        let currentSearch = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "where is the exit",
                "session_id": "client-session-B",
                "continuity_id": continuityID,
                "request_id": "consumer-demand-1",
                "include_chat": false,
                "include_brief": false,
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        let currentDemandID = try XCTUnwrap(currentSearch["demand_id"] as? String)

        // A current-demand handle cannot be paired with a different root scope.
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_consume",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": "client-session-B",
                "continuity_id": continuityID,
                "request_id": "consume-request-wrong-roots",
                "current_demand_id": currentDemandID,
                "query": "where is the exit",
                "root_ids": ["not-the-searched-root"],
            ],
            databaseURL: dbURL, clientIdentityID: nil))

        // A different MCP session uses the same durable continuity and consumes
        // the previously settled result without creating a model-generated answer.
        let consumed = try HTTPServer.runMCPTool(
            name: "simigo_es_consume",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": "client-session-B",
                "continuity_id": continuityID,
                "request_id": "consume-request-1",
                "current_demand_id": currentDemandID,
                "query": "where is the exit",
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        XCTAssertEqual(consumed["status"] as? String, "consumed", "\(consumed)")
        XCTAssertEqual(consumed["value"] as? String, "the exit is north")
        XCTAssertEqual(consumed["source_settlement_id"] as? String, sourceSettlementID)
        XCTAssertEqual(consumed["model_calls"] as? Int, 0)
        XCTAssertEqual(consumed["reused_existing"] as? Bool, false)
        let consumerStateID = try XCTUnwrap(
            consumed["consumer_es_state_id"] as? String)

        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertEqual(try db.executionStateContinuityID(consumerStateID), continuityID)
        XCTAssertEqual(try db.executionStateParentID(consumerStateID), sourceStateID)
        let recorded = try db.settlementConsumptions(consumerStateID: consumerStateID)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.sourceSettlementID, sourceSettlementID)
        XCTAssertEqual(recorded.first?.modelCalls, 0)
        db.close()

        // The derived settlement is now the continuity's newest answer. A retry
        // must use request_id's original consumption row, not try to consume the
        // derived settlement as a new source.
        let retry = try HTTPServer.runMCPTool(
            name: "simigo_es_consume",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": "client-session-C",
                "continuity_id": continuityID,
                "request_id": "consume-request-1",
                "current_demand_id": currentDemandID,
                "query": "where is the exit",
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        XCTAssertEqual(retry["status"] as? String, "consumed", "\(retry)")
        XCTAssertEqual(retry["source_settlement_id"] as? String, sourceSettlementID)
        XCTAssertEqual(retry["consumer_es_state_id"] as? String, consumerStateID)
        XCTAssertEqual(retry["model_calls"] as? Int, 0)
        XCTAssertEqual(retry["reused_existing"] as? Bool, true)

        // A demand handle from one continuity cannot be used in another.
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_consume",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": "client-session-Z",
                "continuity_id": "unrelated-thread",
                "request_id": "consume-request-wrong-scope",
                "current_demand_id": currentDemandID,
                "query": "where is the exit",
            ],
            databaseURL: dbURL, clientIdentityID: nil))

        // A separate current demand in another continuity has no matching answer.
        let otherSearch = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "where is the exit",
                "session_id": "client-session-Z",
                "continuity_id": "unrelated-thread",
                "request_id": "other-thread-demand",
                "include_chat": false,
                "include_brief": false,
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        let otherDemandID = try XCTUnwrap(otherSearch["demand_id"] as? String)
        let isolated = try HTTPServer.runMCPTool(
            name: "simigo_es_consume",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": "client-session-Z",
                "continuity_id": "unrelated-thread",
                "request_id": "consume-request-other",
                "current_demand_id": otherDemandID,
                "query": "where is the exit",
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        XCTAssertEqual(isolated["status"] as? String, "miss")
        XCTAssertEqual(isolated["candidate_found"] as? Bool, false)

        // A child ES defaults to its explicit parent's continuity when a client
        // starts another logical turn without re-sending the continuity handle.
        let followup = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": "client-session-D",
                "parent_state_id": consumerStateID,
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        XCTAssertEqual(followup["continuity_id"] as? String, continuityID)
    }

    func testSettlementConsumptionDemandAndAnswersAreIsolatedAcrossMCPClients() throws {
        let identityA = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let identityB = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let query = "identical cross-client consumption basis"
        let reuseContract: [String: Any] = [
            "contract_id": SettlementConsumption.Contract.contractID,
            "demand_class": SettlementConsumption.Contract.demandClass,
            "contract_version": SettlementConsumption.Contract.version,
        ]

        func settleForClient(_ identity: String, suffix: String) throws -> String {
            let session = "mcp-\(identity)-\(suffix)"
            let begun = try HTTPServer.runMCPTool(
                name: "simigo_es_begin",
                arguments: [
                    "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                    "session_id": session,
                ],
                databaseURL: dbURL,
                clientIdentityID: identity)
            let stateID = try XCTUnwrap(begun["state_id"] as? String)
            let settled = try HTTPServer.runMCPTool(
                name: "simigo_es_settle",
                arguments: [
                    "state_id": stateID,
                    "model": "cloud-model",
                    "tokenizer": "cloud-tokenizer",
                    "output": "the same reusable value",
                    "session_id": session,
                    "query": query,
                    "reuse_contract": reuseContract,
                ],
                databaseURL: dbURL,
                clientIdentityID: identity)
            XCTAssertEqual(settled["reuse_contract_error"] as? String, "")
            return try XCTUnwrap(settled["settlement_id"] as? String)
        }

        let sourceA = try settleForClient(identityA.digest, suffix: "session-A")
        let sourceB = try settleForClient(identityB.digest, suffix: "session-B")
        XCTAssertNotEqual(sourceA, sourceB)

        func searchForClient(_ identity: String, session: String, request: String) throws -> String {
            let search = try HTTPServer.runMCPTool(
                name: "simigo_is_search",
                arguments: [
                    "query": query,
                    "session_id": session,
                    "request_id": request,
                    "include_chat": false,
                    "include_brief": false,
                ],
                databaseURL: dbURL,
                clientIdentityID: identity)
            return try XCTUnwrap(search["demand_id"] as? String)
        }

        let demandA = try searchForClient(
            identityA.digest, session: "mcp-\(identityA.digest)-session-A",
            request: "search-A")
        let demandB = try searchForClient(
            identityB.digest, session: "mcp-\(identityB.digest)-session-B",
            request: "search-B")
        XCTAssertNotEqual(demandA, demandB)

        // A prior answer is searched under the same identity-wide scope before
        // and after a later chat turn. Reuse is not tied to chat watermark.
        let stableSearchArgs: [String: Any] = [
            "query": query,
            "session_id": "mcp-\(identityA.digest)-consumer-session",
            "request_id": "search-A-chat-watermark",
            "include_chat": true,
            "include_brief": false,
        ]
        let beforeChat = try HTTPServer.runMCPTool(
            name: "simigo_is_search", arguments: stableSearchArgs,
            databaseURL: dbURL, clientIdentityID: identityA.digest)
        let beforeChatDemand = try XCTUnwrap(beforeChat["demand_id"] as? String)
        let chatSessionA = "mcp-\(identityA.digest)-later-agent-session"
        _ = try HTTPServer.runMCPTool(
            name: "simigo_chat_round",
            arguments: [
                "session_id": chatSessionA,
                "request_id": "post-answer-chat-fact",
                "user": query + " fresh chat fact",
                "assistant": "A fresh chat fact is now available after the older answer.",
                "boundary": "This chat turn is later context, not a settlement invalidation.",
            ],
            databaseURL: dbURL,
            clientIdentityID: identityA.digest)
        let afterChat = try HTTPServer.runMCPTool(
            name: "simigo_is_search", arguments: stableSearchArgs,
            databaseURL: dbURL, clientIdentityID: identityA.digest)
        let currentChatDemand = try XCTUnwrap(afterChat["demand_id"] as? String)
        XCTAssertNotEqual(currentChatDemand, beforeChatDemand,
                          "the new chat watermark must create a new current demand")
        XCTAssertTrue(
            (afterChat["items"] as? [[String: Any]] ?? []).contains {
                ($0["text"] as? String)?.contains("fresh chat fact") == true
            },
            "the new current demand must include the later chat fact")

        // Even if a caller supplies a foreign source settlement directly to the
        // native consumption authority, owner admission must refuse it in-transaction.
        let ownerCheckDB = try ESISDatabase(url: dbURL, createIfNeeded: false)
        let foreignSourceRequest = SettlementConsumption.Request(
            sourceSettlementID: sourceB,
            consumerStateID: "foreign-source-must-not-write",
            consumerParentStateID: "foreign-source-parent",
            consumerPosition: 1,
            consumerModelIdentity: "cloud-model",
            consumerIdentity: .init(model: "cloud-model", tokenizer: "cloud-tokenizer"),
            clientIdentityID: identityA.digest,
            currentDemandID: demandA,
            query: query)
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: ownerCheckDB, request: foreignSourceRequest)) { error in
            XCTAssertEqual(
                error as? SettlementConsumption.Refusal,
                .sourceOwnershipMismatch(sourceB))
        }
        ownerCheckDB.close()

        func consumeForClient(_ identity: String, currentDemand: String) throws -> [String: Any] {
            try HTTPServer.runMCPTool(
                name: "simigo_es_consume",
                arguments: [
                    "model": "cloud-model",
                    "tokenizer": "cloud-tokenizer",
                    "session_id": "consumer-session",
                    "request_id": "same-request-id",
                    "current_demand_id": currentDemand,
                    "query": query,
                ],
                databaseURL: dbURL,
                clientIdentityID: identity)
        }

        // The same MCP bearer identity spans source, later-chat, and consumer sessions;
        // the old same-query answer remains eligible under its declared reuse contract.
        let consumedA = try consumeForClient(
            identityA.digest, currentDemand: currentChatDemand)
        let consumedB = try consumeForClient(identityB.digest, currentDemand: demandB)
        XCTAssertEqual(consumedA["status"] as? String, "consumed")
        XCTAssertEqual(consumedB["status"] as? String, "consumed")
        XCTAssertEqual(consumedA["source_settlement_id"] as? String, sourceA)
        XCTAssertEqual(consumedB["source_settlement_id"] as? String, sourceB)
        let consumerSettlementA = try XCTUnwrap(consumedA["consumer_settlement_id"] as? String)
        let consumerSettlementB = try XCTUnwrap(consumedB["consumer_settlement_id"] as? String)
        XCTAssertNotEqual(consumerSettlementA, consumerSettlementB)

        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertEqual(
            try db.answeredDemand(clientIdentityID: identityA.digest, query: query)?.answerSettlementID,
            consumerSettlementA)
        XCTAssertEqual(
            try db.answeredDemand(clientIdentityID: identityB.digest, query: query)?.answerSettlementID,
            consumerSettlementB)
        XCTAssertEqual(try db.settlementClientIdentityID(consumerSettlementA), identityA.digest)
        XCTAssertEqual(try db.settlementClientIdentityID(consumerSettlementB), identityB.digest)
        db.close()
    }

    func testMCPBeginRejectsResumingExecutionUnderDifferentContinuity() throws {
        let first = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "continuity_id": "thread-A",
            ],
            databaseURL: dbURL, clientIdentityID: nil)
        let stateID = try XCTUnwrap(first["state_id"] as? String)
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model", "tokenizer": "cloud-tokenizer",
                "state_id": stateID,
                "continuity_id": "thread-B",
                "session_id": "rotated-session",
            ],
            databaseURL: dbURL, clientIdentityID: nil))
    }

    func testOwnerCanReadLegacySettlementWithoutClientIdentityAcrossMCP() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        let stateID = "legacy-owner-settlement-" + UUID().uuidString.lowercased()
        try db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: "legacy-model",
            position: 0, continuationID: UUID().uuidString,
            anchor: "legacy-anchor", lifecycle: "active", createdAt: Date())
        let authorized = try SettlementAuthority.authorize(
            generatedText: "RESULT=legacy owner result",
            contractJSON: InformationLoop.chatResultContractJSON,
            verifiedBindings: [:])
        let settlementID = try db.recordNativeSettlement(authorized, stateID: stateID)
        db.close()

        // Reproduce a pre-identity historical row with a NULL owner column.
        var rawDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &rawDB), SQLITE_OK)
        guard let rawDB else { return XCTFail("could not reopen SQLite for legacy fixture") }
        let sql = "UPDATE execution_states SET client_identity_id=NULL WHERE state_id='\(stateID)';"
        let updateResult = sql.withCString { sqlite3_exec(rawDB, $0, nil, nil, nil) }
        XCTAssertEqual(updateResult, SQLITE_OK)
        XCTAssertEqual(sqlite3_close(rawDB), SQLITE_OK)

        let verify = try ESISDatabase(url: dbURL, createIfNeeded: false, readOnly: true)
        XCTAssertNil(try verify.settlementClientIdentityID(settlementID))
        XCTAssertTrue(try verify.settlementRecordExists(settlementID))
        XCTAssertFalse(try verify.settlementRecordExists("missing"))
        verify.close()

        let ownerRead = try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": settlementID],
            databaseURL: dbURL,
            clientIdentityID: ESISDatabase.ownerNamespace)
        XCTAssertEqual(ownerRead["settlement_id"] as? String, settlementID)

        let external = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": settlementID],
            databaseURL: dbURL,
            clientIdentityID: external.digest))

        let terms: [String: Any] = [
            "settlement_id": settlementID,
            "contract_id": SettlementConsumption.Contract.contractID,
            "demand_class": SettlementConsumption.Contract.demandClass,
            "contract_version": SettlementConsumption.Contract.version,
            "query": "legacy owner result",
            "root_ids": [String](),
        ]
        let declared = try HTTPServer.runMCPTool(
            name: "simigo_is_declare_reuse", arguments: terms,
            databaseURL: dbURL, clientIdentityID: ESISDatabase.ownerNamespace)
        XCTAssertEqual(declared["settlement_id"] as? String, settlementID)
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_is_declare_reuse", arguments: terms,
            databaseURL: dbURL, clientIdentityID: external.digest))
        XCTAssertTrue(HTTPServer.settlementIsVisible(
            to: ESISDatabase.ownerNamespace, storedClientIdentityID: nil,
            settlementExists: true))
        XCTAssertFalse(HTTPServer.settlementIsVisible(
            to: external.digest, storedClientIdentityID: nil,
            settlementExists: true))
    }

    func testSettlementReadSurfacesFreshnessRiskNotices() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        let stateID = "mcp-risk-" + UUID().uuidString.lowercased()
        try db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: "mcp-risk-model",
            position: 1, continuationID: UUID().uuidString,
            anchor: "mcp-risk-anchor", lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "RESULT=historical value",
            contractJSON: InformationLoop.chatResultContractJSON,
            verifiedBindings: [:])
        let settlementID = try db.recordNativeSettlement(settled, stateID: stateID)
        _ = try db.invalidateSettlement(settlementID)
        db.close()

        let reply = try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": settlementID],
            databaseURL: dbURL)
        XCTAssertEqual(reply["validity"] as? String, "invalid")
        XCTAssertEqual(reply["payload_sha256"] as? String, settled.payloadDigest)
        let notices = try XCTUnwrap(reply["risk_notices"] as? [[String: Any]])
        XCTAssertEqual(notices.first?["code"] as? String, SettlementRiskNotice.invalidated)
        XCTAssertEqual(notices.first?["settlement_id"] as? String, settlementID)
    }

    // #277: the corrected-turn digest question lookup must propagate SQLite read
    // failures to the MCP error path, not collapse them into an empty question.
    func testCorrectedTurnQuestionMapsMissingRowToEmpty() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        defer { db.close() }
        let question = try HTTPServer.correctedTurnQuestion(
            db: db, sessionID: "mcp-correct-q", requestID: "t1")
        XCTAssertEqual(question, "")
    }

    func testCorrectedTurnQuestionPropagatesReadFailureOnClosedHandle() throws {
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        db.close()
        XCTAssertThrowsError(
            try HTTPServer.correctedTurnQuestion(
                db: db, sessionID: "mcp-correct-q", requestID: "t1"))
    }

    func testClientCredentialIsIssuedOutsideMCPAndLoopbackAlwaysResolvesOwner() throws {
        let credential = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        XCTAssertEqual(credential.token.count, 43)
        XCTAssertEqual(credential.digest.count, 64)
        XCTAssertEqual(try HTTPServer.resolveHTTPClientIdentity(
            authorizationHeader: "Bearer \(credential.token)",
            isLoopbackPeer: false, isTLS: true, databaseURL: dbURL), credential.digest)
        XCTAssertEqual(try HTTPServer.resolveHTTPClientIdentity(
            authorizationHeader: "Bearer \(credential.token)",
            isLoopbackPeer: true, isTLS: false, databaseURL: dbURL),
            ESISDatabase.ownerNamespace, "loopback always resolves owner")
        XCTAssertThrowsError(try HTTPServer.resolveHTTPClientIdentity(
            authorizationHeader: nil, isLoopbackPeer: false, isTLS: true, databaseURL: dbURL))
        XCTAssertThrowsError(try HTTPServer.resolveHTTPClientIdentity(
            authorizationHeader: "Bearer \(credential.token)",
            isLoopbackPeer: false, isTLS: false, databaseURL: dbURL))
        let apiSession = HTTPServer.scopedClientSessionID(
            "api-session", clientIdentityID: credential.digest)
        XCTAssertEqual(ESISDatabase.clientScope(ofSession: apiSession), credential.digest)
        XCTAssertEqual(HTTPServer.scopedClientSessionID(
            apiSession, clientIdentityID: credential.digest), apiSession)
    }
    func testMCPCallsConsumeTheHTTPAuthenticatedIdentityWithoutMetaReplay() throws {
        let server = makeServer()
        let credential = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let initialized = try XCTUnwrap(server.mcpResponse(
            for: ["jsonrpc": "2.0", "id": 1, "method": "initialize"],
            databaseURL: dbURL, clientIdentityID: credential.digest))
        XCTAssertNil((initialized["result"] as? [String: Any])?["_meta"])
        let begin = try XCTUnwrap(server.mcpResponse(
            for: ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": [
                "name": "simigo_es_begin",
                "arguments": ["model": "cloud-model", "tokenizer": "cloud-tokenizer",
                              "session_id": "agent-session-A"],
            ]],
            databaseURL: dbURL, clientIdentityID: credential.digest))
        let result = try XCTUnwrap(begin["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let payload = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertEqual(state["client_identity_id"] as? String, credential.digest)
        let reconnect = server.mcpResponse(
            for: ["jsonrpc": "2.0", "id": 3, "method": "initialize"],
            databaseURL: dbURL, clientIdentityID: credential.digest)
        XCTAssertNil((reconnect?["result"] as? [String: Any])?["_meta"])
    }
    func testUnknownAndRevokedClientCredentialsFailClosedAtSharedIngress() throws {
        let credential = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let unknownToken = String(repeating: "a", count: 43)
        XCTAssertThrowsError(try HTTPServer.resolveHTTPClientIdentity(
            authorizationHeader: "Bearer \(unknownToken)",
            isLoopbackPeer: false, isTLS: true, databaseURL: dbURL))
        XCTAssertThrowsError(try HTTPServer.resolveHTTPClientIdentity(
            authorizationHeader: "Basic \(credential.token)",
            isLoopbackPeer: false, isTLS: true, databaseURL: dbURL))
        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertTrue(try db.revokeClientIdentity(credential.digest))
        XCTAssertFalse(try db.isActiveClientIdentity(credential.digest))
        db.close()
        XCTAssertThrowsError(try HTTPServer.resolveHTTPClientIdentity(
            authorizationHeader: "Bearer \(credential.token)",
            isLoopbackPeer: false, isTLS: true, databaseURL: dbURL))
    }
    func testMCPClientIdentityPersistsAcrossAgentSessionsAndIsolatesESISAndNotes() throws {
        let clientA = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let clientAReconnect = clientA
        let clientB = try HTTPServer.issueClientCredential(databaseURL: dbURL)

        XCTAssertEqual(clientAReconnect.token, clientA.token)
        XCTAssertEqual(clientAReconnect.digest, clientA.digest)
        XCTAssertNotEqual(clientB.token, clientA.token)
        XCTAssertNotEqual(clientB.digest, clientA.digest)

        let firstSession = "mcp-\(clientA.digest)-agent-session-A"
        let secondSession = "mcp-\(clientA.digest)-agent-session-B"
        let first = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": firstSession,
            ],
            databaseURL: dbURL,
            clientIdentityID: clientA.digest)
        let firstStateID = try XCTUnwrap(first["state_id"] as? String)
        XCTAssertEqual(first["client_identity_id"] as? String, clientA.digest)

        // A new Agent session uses the same Hook identity and continues the same
        // client-owned ES history without passing or knowing a continuity string.
        let child = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "session_id": secondSession,
                "parent_state_id": firstStateID,
            ],
            databaseURL: dbURL,
            clientIdentityID: clientA.digest)
        let childStateID = try XCTUnwrap(child["state_id"] as? String)
        XCTAssertEqual(child["client_identity_id"] as? String, clientA.digest)
        XCTAssertEqual(child["parent_state_id"] as? String, firstStateID)

        // The same state_id is not enough to resume or inspect another client's ES.
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: [
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "state_id": firstStateID,
                "session_id": "mcp-\(clientB.digest)-agent-session-X",
            ],
            databaseURL: dbURL,
            clientIdentityID: clientB.digest))

        let listA = try HTTPServer.runMCPTool(
            name: "simigo_es_list", arguments: [:],
            databaseURL: dbURL, clientIdentityID: clientA.digest)
        let ownedStates = try XCTUnwrap(listA["executions"] as? [[String: Any]])
        XCTAssertEqual(Set(ownedStates.compactMap { $0["state_id"] as? String }),
                       Set([firstStateID, childStateID]))

        let listB = try HTTPServer.runMCPTool(
            name: "simigo_es_list", arguments: [:],
            databaseURL: dbURL, clientIdentityID: clientB.digest)
        XCTAssertEqual(listB["count"] as? Int, 0)

        // A client-wide answer and its settlement remain available across sessions,
        // but reading the settlement by its public ID does not cross the owner scope.
        let settled = try HTTPServer.runMCPTool(
            name: "simigo_es_settle",
            arguments: [
                "state_id": childStateID,
                "model": "cloud-model",
                "tokenizer": "cloud-tokenizer",
                "output": "Client A private result",
                "session_id": secondSession,
                "query": "client identity private result",
            ],
            databaseURL: dbURL,
            clientIdentityID: clientA.digest)
        let settlementID = try XCTUnwrap(settled["settlement_id"] as? String)
        XCTAssertEqual(settled["client_identity_id"] as? String, clientA.digest)
        XCTAssertThrowsError(try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": settlementID],
            databaseURL: dbURL,
            clientIdentityID: clientB.digest))
        let ownSettlement = try HTTPServer.runMCPTool(
            name: "simigo_is_settlement",
            arguments: ["settlement_id": settlementID],
            databaseURL: dbURL,
            clientIdentityID: clientA.digest)
        XCTAssertEqual(ownSettlement["settlement_id"] as? String, settlementID)

        // Brief and rolling digest share the same identity-derived namespace.
        _ = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "brief", "claim": "Client A private brief"],
            databaseURL: dbURL,
            clientIdentityID: clientA.digest)
        _ = try HTTPServer.runMCPTool(
            name: "simigo_project_note",
            arguments: ["kind": "digest", "claim": "Client A rolling digest"],
            databaseURL: dbURL,
            clientIdentityID: clientA.digest)

        let briefA = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:],
            databaseURL: dbURL, clientIdentityID: clientA.digest)
        let briefB = try HTTPServer.runMCPTool(
            name: "simigo_project_brief", arguments: [:],
            databaseURL: dbURL, clientIdentityID: clientB.digest)
        XCTAssertEqual(briefA["claim"] as? String, "Client A private brief")
        XCTAssertEqual(briefB["claim"] as? String, "")

        let instructionsA = HTTPServer.sessionInstructions(
            client: clientA.digest, databaseURL: dbURL)
        let instructionsB = HTTPServer.sessionInstructions(
            client: clientB.digest, databaseURL: dbURL)
        XCTAssertTrue(instructionsA.contains("Client A private brief"))
        XCTAssertTrue(instructionsA.contains("Client A rolling digest"))
        XCTAssertFalse(instructionsB.contains("Client A private brief"))
        XCTAssertFalse(instructionsB.contains("Client A rolling digest"))

        // The Hook's opaque token is revocable; revocation invalidates reconnect.
        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertTrue(try db.revokeMCPClientIdentity(clientA.digest))
        db.close()
        XCTAssertFalse(try ESISDatabase(url: dbURL, createIfNeeded: false)
            .isActiveClientIdentity(clientA.digest))
    }

    func testFailureAuditExecutionIDsAreIsolatedByMCPClientIdentity() throws {
        let clientA = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let clientB = try HTTPServer.issueClientCredential(databaseURL: dbURL)

        let stateA = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "remote-model", "tokenizer": "remote-tokenizer"],
            databaseURL: dbURL, clientIdentityID: clientA.digest)
        let stateB = try HTTPServer.runMCPTool(
            name: "simigo_es_begin",
            arguments: ["model": "remote-model", "tokenizer": "remote-tokenizer"],
            databaseURL: dbURL, clientIdentityID: clientB.digest)
        let stateAID = try XCTUnwrap(stateA["state_id"] as? String)
        let stateBID = try XCTUnwrap(stateB["state_id"] as? String)

        let auditA = try HTTPServer.runMCPTool(
            name: "simigo_es_fail",
            arguments: [
                "state_id": stateAID,
                "execution_id": "shared-execution-key",
                "detail": "client A failure",
            ],
            databaseURL: dbURL, clientIdentityID: clientA.digest)
        let auditB = try HTTPServer.runMCPTool(
            name: "simigo_es_fail",
            arguments: [
                "state_id": stateBID,
                "execution_id": "shared-execution-key",
                "detail": "client B failure",
            ],
            databaseURL: dbURL, clientIdentityID: clientB.digest)

        XCTAssertEqual(auditA["audit_persisted"] as? Bool, true)
        XCTAssertEqual(auditB["audit_persisted"] as? Bool, true,
                       "one client cannot pre-empt another client's audit key")
        let db = try ESISDatabase(url: dbURL, createIfNeeded: false)
        XCTAssertEqual(
            db.failureAudit(
                executionID: "shared-execution-key",
                clientIdentityID: clientA.digest)?.detail,
            "client A failure")
        XCTAssertEqual(
            db.failureAudit(
                executionID: "shared-execution-key",
                clientIdentityID: clientB.digest)?.detail,
            "client B failure")
        XCTAssertNil(db.failureAudit(executionID: "shared-execution-key"),
                     "external audits do not appear in the first-party owner namespace")
        db.close()
    }

    func testMCPClientSearchReadsOnlyItsOwnAgentSessions() throws {
        let clientA = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let clientB = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let sessionA = "mcp-\(clientA.digest)-chat-A"

        _ = try HTTPServer.runMCPTool(
            name: "simigo_chat_round",
            arguments: [
                "session_id": sessionA,
                "request_id": "agent-round-1",
                "user": "client-scope-probe-unique-needle",
                "assistant": "Only client A can retrieve this sentence",
                "boundary": "A single recorded test turn",
            ],
            databaseURL: dbURL,
            clientIdentityID: clientA.digest)

        let searchA = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "client-scope-probe-unique-needle",
                "session_id": "mcp-\(clientA.digest)-new-agent-session",
                "include_chat": true,
                "include_brief": false,
            ],
            databaseURL: dbURL,
            clientIdentityID: clientA.digest)
        let itemsA = try XCTUnwrap(searchA["items"] as? [[String: Any]])
        XCTAssertTrue(itemsA.contains {
            ($0["text"] as? String)?.contains("client-scope-probe-unique-needle") == true
        })

        let searchB = try HTTPServer.runMCPTool(
            name: "simigo_is_search",
            arguments: [
                "query": "client-scope-probe-unique-needle",
                "session_id": "mcp-\(clientB.digest)-new-agent-session",
                "include_chat": true,
                "include_brief": false,
            ],
            databaseURL: dbURL,
            clientIdentityID: clientB.digest)
        let itemsB = try XCTUnwrap(searchB["items"] as? [[String: Any]])
        XCTAssertFalse(itemsB.contains {
            ($0["text"] as? String)?.contains("client-scope-probe-unique-needle") == true
        })
    }


    func testISConsumptionContractIsSharedFromOwnerAcrossAgentClients() throws {
        let client = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let ownerClaim = "OWNER IS CONSUMPTION RULE - exact source and dependency validation"
        let clientClaim = "CLIENT PRIVATE CONTRACT MUST NEVER REPLACE OWNER RULE"

        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        _ = try db.recordProjectNote(
            kind: ESISDatabase.scopedKind("contract", scope: ESISDatabase.ownerNamespace),
            claim: ownerClaim)
        // A stale per-client contract row must not shadow the shared Agent rule.
        _ = try db.recordProjectNote(
            kind: ESISDatabase.scopedKind("contract", scope: client.digest),
            claim: clientClaim)
        db.close()

        let instructions = HTTPServer.sessionInstructions(
            client: client.digest, databaseURL: dbURL)
        XCTAssertTrue(instructions.contains(ownerClaim))
        XCTAssertTrue(instructions.contains("contract@owner"))
        XCTAssertFalse(instructions.contains(clientClaim))

        let contract = try HTTPServer.runMCPTool(
            name: "simigo_project_brief",
            arguments: ["kind": "contract"],
            databaseURL: dbURL,
            clientIdentityID: client.digest)
        XCTAssertEqual(contract["scope"] as? String, ESISDatabase.ownerNamespace)
        XCTAssertEqual(contract["claim"] as? String, ownerClaim)
        XCTAssertFalse((contract["claim"] as? String ?? "").contains(clientClaim))

        XCTAssertThrowsError(
            try HTTPServer.runMCPTool(
                name: "simigo_project_note",
                arguments: ["kind": "contract", "claim": "attacker replacement"],
                databaseURL: dbURL,
                clientIdentityID: client.digest),
            "remote Agents may read the owner contract but may not replace it")
    }

    func testMissingOwnerConsumptionContractIsExplicitAndFailsClosed() throws {
        let client = try HTTPServer.issueClientCredential(databaseURL: dbURL)
        let db = try ESISDatabase(url: dbURL, createIfNeeded: true)
        try db.runMigrations()
        _ = try db.recordProjectNote(
            kind: ESISDatabase.scopedKind("contract", scope: client.digest),
            claim: "private note is not the global consumption protocol")
        db.close()

        let instructions = HTTPServer.sessionInstructions(
            client: client.digest, databaseURL: dbURL)
        XCTAssertTrue(instructions.contains("IS 消费协议未注入"))
        XCTAssertTrue(instructions.contains("禁止执行零模型调用"))
        XCTAssertFalse(instructions.contains("private note is not the global consumption protocol"))

        let contract = try HTTPServer.runMCPTool(
            name: "simigo_project_brief",
            arguments: ["kind": "contract"],
            databaseURL: dbURL,
            clientIdentityID: client.digest)
        XCTAssertEqual(contract["claim"] as? String, "")
        XCTAssertTrue((contract["hint"] as? String ?? "").contains("contract@owner"))
    }

}
