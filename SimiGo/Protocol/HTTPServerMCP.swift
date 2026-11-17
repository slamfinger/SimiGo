import Foundation
import CoreFoundation
import SimiGoRuntimeContract

extension Notification.Name {
    /// Posted after an MCP round records a turn index, so the menu can show the
    /// ledger without polling the database.
    static let simigoMCPTurnRecorded = Notification.Name("SimiGoMCPTurnRecorded")
}

/// MCP (JSON-RPC 2.0 over HTTP) facade over the SAME native ES/IS operations
/// the HTTP routes already use. There is no second database, retrieval path or
/// settlement authority here: every tool calls `ESISDatabase` /
/// `InformationLoop`, so an external agent sees exactly the information
/// space the local model executes against.
///
/// Transport: stateless Streamable-HTTP subset. POST /mcp carries one request,
/// a batch, or notifications; GET /mcp is refused (this server opens no
/// server-initiated stream), which the spec allows.
extension HTTPServer {

    enum MCPToolError: Error, CustomStringConvertible {
        case invalidArguments(String)
        case unknownTool(String)

        var description: String {
            switch self {
            case .invalidArguments(let detail):
                return "invalid arguments: \(detail)"
            case .unknownTool(let name):
                return "unknown tool: \(name)"
            }
        }
    }

    var mcpVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    // MARK: - Transport

    func handleMCPRequest(
        _ request: HTTPRequest,
        context: ConnectionContext
    ) async {
        guard request.method == "POST" else {
            _ = sendResponse(
                status: 405,
                headers: corsHeaders(extra: [
                    "Allow": "POST",
                    "Content-Length": "0",
                ]),
                body: Data(),
                on: context.connection,
                context: context,
                close: true)
            return
        }
        guard !request.body.isEmpty,
            let parsed = try? JSONSerialization.jsonObject(with: request.body)
        else {
            sendMCPPayload(
                Self.mcpError(id: NSNull(), code: -32700, message: "Parse error"),
                status: 200, context: context)
            return
        }
        if let batch = parsed as? [Any] {
            guard !batch.isEmpty else {
                sendMCPPayload(
                    Self.mcpError(id: NSNull(), code: -32600, message: "Invalid Request"),
                    status: 200, context: context)
                return
            }
            let responses = batch.compactMap { mcpResponse(for: $0) }
            if responses.isEmpty {
                sendMCPAccepted(context: context)
            } else {
                sendMCPPayload(responses, status: 200, context: context)
            }
            return
        }
        if let response = mcpResponse(for: parsed) {
            sendMCPPayload(response, status: 200, context: context)
        } else {
            sendMCPAccepted(context: context)
        }
    }

    /// `nil` means the message was a notification and carries no response.
    func mcpResponse(for raw: Any) -> [String: Any]? {
        guard let message = raw as? [String: Any] else {
            return Self.mcpError(id: NSNull(), code: -32600, message: "Invalid Request")
        }

        let id = message["id"] ?? NSNull()
        if let rawID = message["id"], !Self.isValidMCPRequestID(rawID) {
            return Self.mcpError(id: NSNull(), code: -32600, message: "Invalid Request")
        }
        guard message["jsonrpc"] as? String == "2.0",
              let method = message["method"] as? String,
              !method.isEmpty else {
            return Self.mcpError(id: id, code: -32600, message: "Invalid Request")
        }

        // A notification has no id and must not produce a response. The MCP
        // methods implemented below are request methods; protocol notifications
        // (for example notifications/initialized) are intentionally response-free.
        guard message.keys.contains("id") else { return nil }

        let params: [String: Any]
        if let rawParams = message["params"] {
            guard let object = rawParams as? [String: Any] else {
                return Self.mcpError(
                    id: id, code: -32602,
                    message: "Invalid params: this endpoint requires named parameters")
            }
            params = object
        } else {
            params = [:]
        }

        switch method {
        case "initialize":
            // 会话入口在服务端，不在每个客户端的 SessionStart 钩子里：钩子每接
            // 一个客户端就要抄一遍（Codex 一份、zcode 一份、Qoder 一份），换客户
            // 端就断。instructions 是 MCP 自己的入口，谁连上来都拿得到。
            return Self.mcpResult(id: id, result: [
                "protocolVersion": "2025-06-18",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "simigo", "version": mcpVersion],
                "instructions": Self.sessionInstructions(
                    client: Self.clientPrefix(params)),
            ])
        case "ping":
            return Self.mcpResult(id: id, result: [:])
        case "tools/list":
            return Self.mcpResult(id: id, result: ["tools": Self.mcpToolDefinitions])
        case "tools/call":
            return mcpToolCall(id: id, params: params)
        default:
            return Self.mcpError(
                id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func mcpToolCall(id: Any, params: [String: Any]) -> [String: Any] {
        guard let name = params["name"] as? String, !name.isEmpty else {
            return Self.mcpError(
                id: id, code: -32602, message: "Missing tool name")
        }
        let arguments: [String: Any]
        if let rawArguments = params["arguments"] {
            guard let object = rawArguments as? [String: Any] else {
                return Self.mcpError(
                    id: id, code: -32602,
                    message: "Invalid params: tool arguments must be a JSON object")
            }
            arguments = object
        } else {
            arguments = [:]
        }
        do {
            let result = try Self.runMCPTool(name: name, arguments: arguments)
            let text = (try? JSONSerialization.data(
                withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return Self.mcpResult(id: id, result: [
                "content": [["type": "text", "text": text]],
                "isError": false,
            ])
        } catch {
            return Self.mcpResult(id: id, result: [
                "content": [["type": "text", "text": String(describing: error)]],
                "isError": true,
            ])
        }
    }

    private func sendMCPPayload(
        _ payload: Any, status: Int, context: ConnectionContext
    ) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        var headers = corsHeaders()
        headers["Content-Type"] = "application/json; charset=utf-8"
        headers["Content-Length"] = "\(data.count)"
        _ = sendResponse(
            status: status, headers: headers, body: data,
            on: context.connection, context: context, close: true)
    }

    private func sendMCPAccepted(context: ConnectionContext) {
        _ = sendResponse(
            status: 202,
            headers: corsHeaders(extra: ["Content-Length": "0"]),
            body: Data(),
            on: context.connection,
            context: context,
            close: true)
    }

    /// JSON-RPC ids are strings, numbers, or null. JSONSerialization bridges
    /// booleans through NSNumber too, so exclude CFBoolean explicitly.
    private static func isValidMCPRequestID(_ value: Any) -> Bool {
        if value is NSNull { return true }
        if value is String { return true }
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }

    static func mcpResult(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func mcpError(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    // MARK: - Tools

    static var mcpToolDefinitions: [[String: Any]] {
        [
            [
                "name": "simigo_is_search",
                "description":
                    "Resolve an information demand against the settled physical index "
                    + "and stored chat. Returns digest-verified citable fragments; a "
                    + "repeated identical demand reuses its settled result. `session_id` "
                    + "is the session this retrieval belongs to and only sets the "
                    + "demand's ownership; `session_ids` selects which stored chat "
                    + "sessions are searched (omitted or empty means every eligible "
                    + "committed session in this personal space). `request_id` is this "
                    + "call's request identity: a retry with the same request_id reuses "
                    + "the same demand, while a call without one owns a fresh demand "
                    + "lifecycle — knowledge is shared across requests, request state "
                    + "is not. The answer also carries the current project brief in a "
                    + "`brief` field outside `items`: it is not a candidate and is not "
                    + "ranked, so a similar paragraph cannot push it out. Pass "
                    + "`include_brief: false` to leave it out.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "session_id": ["type": "string"],
                        "request_id": ["type": "string"],
                        "root_ids": ["type": "array", "items": ["type": "string"]],
                        "include_chat": ["type": "boolean"],
                        "session_ids": ["type": "array", "items": ["type": "string"]],
                        "limit": ["type": "integer"],
                        "include_brief": ["type": "boolean"],
                    ],
                    "required": ["query"],
                ],
            ],
            [
                "name": "simigo_is_status",
                "description":
                    "Information Space carrier status: schema version, stored objects, "
                    + "index/dependency entries and integrity counters.",
                "inputSchema": ["type": "object", "properties": [:]],
            ],
            [
                "name": "simigo_roots_list",
                "description": "List registered external work roots.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["category": ["type": "string"]],
                ],
            ],
            [
                "name": "simigo_root_register",
                "description":
                    "Register an absolute directory as a work root and index it. "
                    + "Only locator + digest + size are stored; file bytes are never copied.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["path": ["type": "string"]],
                    "required": ["path"],
                ],
            ],
            [
                "name": "simigo_is_reconcile",
                "description":
                    "Re-derive validity for registered roots: changed files force a new "
                    + "settlement, missing roots are marked without clearing the index.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["category": ["type": "string"]],
                ],
            ],
            [
                "name": "simigo_is_settlement",
                "description":
                    "Read one settled result back with its digest-verified payload and "
                    + "dependency revisions.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["settlement_id": ["type": "string"]],
                    "required": ["settlement_id"],
                ],
            ],
            [
                "name": "simigo_is_declare_reuse",
                "description":
                    "Declare the reuse terms under which ONE settled result may be "
                    + "consumed verbatim. Reusability is a declared property of the "
                    + "settled result, never inferred from text similarity: without "
                    + "this declaration a settlement is not consumable however "
                    + "identical its text, and consumption refuses "
                    + "`contract_undeclared`. The terms name the canonical input "
                    + "basis (the query plus the roots the demand named), so a "
                    + "consumer whose basis differs is refused rather than served. "
                    + "Re-declaring the same terms is idempotent; changing them is "
                    + "refused, because terms a consumer may already have relied on "
                    + "are never silently rewritten. This is the product-side door "
                    + "for a declaration the settle path can also carry inline "
                    + "(`simigo_es_settle` `reuse_contract`); both doors run the "
                    + "same library call, and neither makes the product declare on "
                    + "its own.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "settlement_id": ["type": "string"],
                        "contract_id": ["type": "string"],
                        "demand_class": ["type": "string"],
                        "contract_version": ["type": "string"],
                        "query": ["type": "string"],
                        "root_ids": ["type": "array", "items": ["type": "string"]],
                        "extract_field": ["type": "string"],
                        "required_consumer_identity": [
                            "type": "object",
                            "properties": [
                                "model": ["type": "string"],
                                "tokenizer": ["type": "string"],
                            ],
                            "required": ["model", "tokenizer"],
                        ],
                    ],
                    "required": [
                        "settlement_id", "contract_id", "demand_class",
                        "contract_version", "query",
                    ],
                ],
            ],
            [
                "name": "simigo_es_begin",
                "description":
                    "Start (or resume an unsettled) execution for an agent whose model "
                    + "runs outside SimiGo. Creates an ES but records NO result: an "
                    + "external call that never settles leaves a begun, unsettled state. "
                    + "begin never returns a historical answer and never consumes one — "
                    + "query + session_id only scope the execution. A zero-model-call "
                    + "consumption path (explicit settlement consumption driving a "
                    + "derived settlement and a new ES) is a designed future operation; "
                    + "until it exists, settle this ES through simigo_es_settle.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "model": ["type": "string"],
                        "tokenizer": ["type": "string"],
                        "state_id": ["type": "string"],
                        "parent_state_id": ["type": "string"],
                        "position": ["type": "integer"],
                        "session_id": ["type": "string"],
                        "query": ["type": "string"],
                        "request_id": ["type": "string"],
                        "root_ids": ["type": "array", "items": ["type": "string"]],
                        "include_chat": ["type": "boolean"],
                        "session_ids": ["type": "array", "items": ["type": "string"]],
                        "limit": ["type": "integer"],
                    ],
                    "required": ["model", "tokenizer"],
                ],
            ],
            [
                "name": "simigo_es_settle",
                "description":
                    "Submit an externally generated result as an authoritative "
                    + "settlement. The output passes the same result contract the local "
                    + "chat path uses, is sealed by payload digest, and is bound to the "
                    + "declared model + tokenizer identity. Supplying demand_id + "
                    + "retrieval_settlement_id declares the sources this result drew on; "
                    + "`dependencies` declares further sources and commits with the "
                    + "settlement — each content_address must be an object id already "
                    + "sealed in the carrier (for example a prior settlement's "
                    + "payload_sha256), and an unsealed address refuses the whole settle. "
                    + "Declaring all five source_* fields (or idempotency_key) makes the "
                    + "call idempotent: the same source at the same revision with the "
                    + "same content returns the existing settlement with reused=true; "
                    + "the same revision with different content is refused; a new, "
                    + "explicitly declared revision creates a linked new version and is "
                    + "never inferred. Carrying `reuse_contract` declares, in the same "
                    + "call, the reuse terms under which this result may later be "
                    + "consumed verbatim; without it the settlement stays "
                    + "non-consumable until declared through "
                    + "`simigo_is_declare_reuse`. A refused declaration is reported "
                    + "in `reuse_contract_error` next to the settlement that did "
                    + "commit, never as a failed settle.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "state_id": ["type": "string"],
                        "model": ["type": "string"],
                        "tokenizer": ["type": "string"],
                        "output": ["type": "string"],
                        "session_id": ["type": "string"],
                        "query": ["type": "string"],
                        "demand_id": ["type": "string"],
                        "retrieval_settlement_id": ["type": "string"],
                        "parent_state_id": ["type": "string"],
                        "actions": ["type": "array", "items": ["type": "string"]],
                        "source_type": ["type": "string"],
                        "source_session_id": ["type": "string"],
                        "source_turn_id": ["type": "string"],
                        "source_message_id": ["type": "string"],
                        "source_revision": ["type": "integer", "minimum": 1],
                        "idempotency_key": ["type": "string"],
                        "dependencies": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "dependency_id": ["type": "string"],
                                    "content_address": ["type": "string"],
                                    "reason": ["type": "string"],
                                ],
                                "required": ["dependency_id"],
                            ],
                        ],
                        "reuse_contract": [
                            "type": "object",
                            "properties": [
                                "contract_id": ["type": "string"],
                                "demand_class": ["type": "string"],
                                "contract_version": ["type": "string"],
                                "query": ["type": "string"],
                                "root_ids": ["type": "array", "items": ["type": "string"]],
                                "extract_field": ["type": "string"],
                                "required_consumer_identity": [
                                    "type": "object",
                                    "properties": [
                                        "model": ["type": "string"],
                                        "tokenizer": ["type": "string"],
                                    ],
                                    "required": ["model", "tokenizer"],
                                ],
                            ],
                            "required": [
                                "contract_id", "demand_class", "contract_version",
                            ],
                        ],
                    ],
                    "required": ["state_id", "model", "tokenizer", "output"],
                ],
            ],
            [
                "name": "simigo_es_fail",
                "description":
                    "Record the terminal failure of an execution attempt in the "
                    + "append-only audit. A failure never creates a settlement: the "
                    + "execution stays visible as begun-but-unsettled.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "state_id": ["type": "string"],
                        "detail": ["type": "string"],
                        "execution_id": ["type": "string"],
                        "attempt": ["type": "integer"],
                        "phase": ["type": "string"],
                        "evidence": ["type": "object"],
                        "model_calls": ["type": "integer"],
                        "settlements_written": ["type": "integer"],
                    ],
                    "required": ["state_id", "detail"],
                ],
            ],
            [
                "name": "simigo_chat_round",
                "description":
                    "Append one complete conversation round (question + reply) "
                    + "produced outside SimiGo, e.g. by a coding agent's own model. "
                    + "`assistant` is the reply as it was given to the user, not a "
                    + "condensed version of it: what is not written here is lost, "
                    + "because the space keeps the text and nothing else. Carry the "
                    + "boundary of the round in `boundary` (what must not be read as "
                    + "fact: unrun arms, single-path coverage, figures that move). "
                    + "The reply reports `boundary_stated`, so a round written "
                    + "without one is visible in the result rather than assumed. "
                    + "Both lines carry external provenance and are promoted to "
                    + "committed in the same call, so the round enters the personal "
                    + "information space and is retrievable by later searches. "
                    + "Idempotent: the same (session_id, request_id) returns the rows "
                    + "already written instead of appending duplicates — but only when "
                    + "the text is the same. A retry that carries different text is "
                    + "refused as a content conflict: the stored line is not overwritten "
                    + "and the later text is not reported as recorded. Amend a wrong "
                    + "line with `simigo_chat_correct`, which keeps the original. "
                    + "Pass `turn_index` (1-based, consecutive) to make every round "
                    + "accounted for: the reply carries `turn_ledger` with the count "
                    + "entered and the indices that never arrived.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string"],
                        "request_id": ["type": "string"],
                        "user": ["type": "string"],
                        "assistant": ["type": "string"],
                        "model": ["type": "string"],
                        "provider": ["type": "string"],
                        "turn_index": ["type": "integer"],
                        "boundary": ["type": "string"],
                    ],
                    "required": ["session_id", "request_id", "user", "assistant"],
                ],
            ],
            [
                "name": "simigo_chat_correct",
                "description":
                    "Amend one already-recorded line of a round (default role "
                    + "assistant). Use this only when the stored text is wrong — a "
                    + "placeholder written by mistake, a truncated body, a line that "
                    + "never was what the user saw. It is not a way to overwrite "
                    + "history: the original line stays, its bytes stay in the object "
                    + "store, and the correction is recorded with the previous digest, "
                    + "the new digest, a required reason and a required actor. Reads "
                    + "and searches then see the corrected text. Retrying the same "
                    + "correction (same message, same text, same reason) is idempotent; "
                    + "different text or a different reason is a separate correction.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string"],
                        "request_id": ["type": "string"],
                        "role": ["type": "string", "enum": ["user", "assistant"]],
                        "text": ["type": "string"],
                        "reason": ["type": "string"],
                        "actor": ["type": "string"],
                    ],
                    "required": ["session_id", "request_id", "text", "reason", "actor"],
                ],
            ],
            [
                "name": "simigo_project_brief",
                "description":
                    "Read the current project brief: what this project is, how far "
                    + "it has got, and what is still open. A brief is a judgement, "
                    + "not a document — it is written by `simigo_project_note` and "
                    + "each new brief supersedes the previous one without erasing "
                    + "it. Read this before answering questions about the project's "
                    + "state: search over the corpus returns what was written when, "
                    + "not what is true now. `kind` defaults to brief; the only "
                    + "other readable kind is contract (the consumer protocol). "
                    + "A brief also carries `newer_notes`: notes of ANY kind "
                    + "recorded after it (auto-rolled digests excepted), i.e. "
                    + "material the judgement has not accounted for yet — plus "
                    + "`stale` and `newer_counts`, so an out-of-date judgement "
                    + "reports itself instead of reading as current. The list is "
                    + "handed over, never merged — deciding what it changes is the "
                    + "reader's job, not the server's. The "
                    + "default view is one client's own notes: pass `session_id` "
                    + "and you get `brief@codex`/`digest@codex` for that prefix, "
                    + "falling back to the shared note when the client has none. "
                    + "Pass `scope: all` to read every client's current notes in "
                    + "one call — crossing clients is an explicit act, not the "
                    + "default. Reading as codex is the exception: it also returns "
                    + "`all_clients`, every client's current brief, because that "
                    + "is the client which has to line the judgements up.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "kind": [
                            "type": "string", "enum": ["brief", "contract", "digest"],
                        ],
                        "scope": ["type": "string"],
                        "session_id": ["type": "string"],
                    ],
                ],
            ],
            [
                "name": "simigo_project_note",
                "description":
                    "Record a judgement about the project and supersede the current "
                    + "one of the same kind. Kinds in use: brief (what the project "
                    + "is and where it stands), status, decision, open-question. "
                    + "Append-only: the previous note stays readable, the new one "
                    + "becomes current by being the note nothing supersedes. "
                    + "Recording an identical claim again is a no-op. `scope` "
                    + "writes a client's own copy (`brief` + scope=codex becomes "
                    + "`brief@codex`) instead of the shared note; omit it for a "
                    + "judgement that holds for the whole project.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string"],
                        "claim": ["type": "string"],
                        "scope": ["type": "string"],
                    ],
                    "required": ["kind", "claim"],
                ],
            ],
        ]
    }

    static func runMCPTool(
        name: String, arguments: [String: Any],
        databaseURL: URL = ManagedPaths.databaseURL
    ) throws -> [String: Any] {
        switch name {
        case "simigo_is_search":
            guard let query = arguments["query"] as? String,
                !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw MCPToolError.invalidArguments("query is required")
            }
            let db = try openESISDatabase(databaseURL)
            let loop = InformationLoop(database: db)
            let resolution = try loop.resolve(.init(
                sessionID: optionalString(arguments, "session_id"),
                requestIdentity: optionalString(arguments, "request_id"),
                query: query,
                rootIDs: arguments["root_ids"] as? [String] ?? [],
                includeChat: (arguments["include_chat"] as? Bool) ?? true,
                chatSessionIDs: arguments["session_ids"] as? [String] ?? [],
                limit: (arguments["limit"] as? Int) ?? 40))
            var response: [String: Any] = [
                "demand_id": resolution.demandID,
                "reused": resolution.reused,
                "status": resolution.reused ? "reused" : "settled",
                "result_sha256": resolution.resultSHA256,
                "retrieval_settlement_id": resolution.retrievalSettlementID,
                "stale_items": resolution.staleItemIDs,
                // 路况：1–2 字的关键词走不了 trigram 索引，回落 LIKE 全扫。
                // 放在返回里，是为了让"这次快/慢"有据可查，而不是靠感觉。
                "index": resolution.unindexedTerms.isEmpty
                    ? "fts5-trigram" : "partial-scan",
                "unindexed_terms": resolution.unindexedTerms,
                "items": resolution.hits.map { hit -> [String: Any] in
                    [
                        "item_id": hit.itemID,
                        "kind": hit.kind,
                        "locator": hit.locator,
                        "line": hit.lineNo,
                        "text": hit.lineText,
                        "source_sha256": hit.sourceSHA256,
                    ]
                },
            ]
            // The brief rides along with every search, outside the item list.
            // It is not a candidate: it never takes a slot and is never ranked,
            // because a judgement that a similar paragraph can outrank is not a
            // time authority. A caller that has never heard the word "brief"
            // still gets the current judgement on its first search.
            if (arguments["include_brief"] as? Bool) ?? true,
                let brief = try db.currentProjectNote(kind: "brief")
            {
                response["brief"] = [
                    "note_id": brief.noteID,
                    "claim": brief.claim,
                    "chars": brief.claim.count,
                    "recorded_at": brief.recordedAt,
                    "recorded_at_iso": Self.isoProjectStamp(brief.recordedAt),
                ] as [String: Any]
            }
            return response

        case "simigo_is_status":
            let db = try openESISDatabase(databaseURL)
            let report = try db.carrierReport(deepVerify: true)
            return [
                "schema_version": report.schemaVersion,
                "objects": report.objectCount,
                "object_bytes": report.objectBytes,
                "index_entries": report.indexEntries,
                "dependency_entries": report.dependencyEntries,
                "settlement_summaries": report.settlementSummaries,
                "unaddressed_file_contents": report.unaddressedFileContents,
                "dangling_references": report.danglingReferences,
                "corrupt_objects": report.corruptObjects,
                "inline_legacy_payloads": report.inlineLegacyPayloads,
                "spaces": report.spaces,
                "dependency_intervals_open": report.dependencyIntervalsOpen,
                "dependency_intervals_closed": report.dependencyIntervalsClosed,
                "dependency_interval_breaks": report.dependencyIntervalBreaks,
                "turn_digests": report.turnDigests,
                "turns_without_digest": report.turnsWithoutDigest,
                "vacuum_failure": report.vacuumFailure ?? "",
            ]

        case "simigo_roots_list":
            let db = try openESISDatabase(databaseURL)
            let category = arguments["category"] as? String ?? "work"
            return [
                "roots": try db.listRoots(category: category).map { row -> [String: Any] in
                    [
                        "root_id": row.rootID,
                        "category": row.category,
                        "display_name": row.displayName ?? "",
                        "locator_type": row.locatorType ?? "",
                        "status": row.status,
                    ]
                }
            ]

        case "simigo_root_register":
            guard let rawPath = arguments["path"] as? String,
                rawPath.hasPrefix("/"), !rawPath.isEmpty
            else {
                throw MCPToolError.invalidArguments("path must be an absolute directory")
            }
            let standardized = (rawPath as NSString).standardizingPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: standardized, isDirectory: &isDir), isDir.boolValue
            else {
                throw MCPToolError.invalidArguments("not a directory: \(standardized)")
            }
            let db = try openESISDatabase(databaseURL)
            let rootID = "work-" + EnvManager.stableRootID(forPath: standardized)
            try db.upsertRoot(
                rootID: rootID, category: "work", displayName: standardized,
                locatorType: "path", status: "registered")
            let settle = try db.settleWorkRootContents(
                rootID: rootID, rootURL: URL(fileURLWithPath: standardized),
                carryText: false)
            let names = try db.importDirectoryNames(
                rootID: rootID, rootURL: URL(fileURLWithPath: standardized))
            return [
                "root_id": rootID,
                "path": standardized,
                "registered": true,
                "name_import": [
                    "files": names.files,
                    "inserted": names.inserted,
                    "refreshed": names.refreshed,
                    "missing": names.missing,
                ],
                "content_settle": [
                    "scanned": settle.scanned,
                    "reused": settle.reused,
                    "settled": settle.settled,
                    "skipped": settle.skippedBinaryOrLarge,
                    "removed": settle.removed,
                    "index_only": settle.indexOnly,
                ],
            ]

        case "simigo_is_reconcile":
            let db = try openESISDatabase(databaseURL)
            let category = arguments["category"] as? String ?? "work"
            let report = try db.reconcileRegisteredRoots(category: category)
            return [
                "root_count": report.rootCount,
                "settled_roots": report.settledRoots,
                "fresh_roots": report.freshRoots,
                "missing_roots": report.missingRoots,
                "failed_roots": report.failedRoots,
                "scanned": report.scanned,
                "reused": report.reused,
                "changed": report.changed,
                "removed": report.removed,
                "invalidated_settlements": report.invalidatedSettlements,
            ]

        case "simigo_is_settlement":
            guard let settlementID = arguments["settlement_id"] as? String,
                !settlementID.isEmpty
            else {
                throw MCPToolError.invalidArguments("settlement_id is required")
            }
            let db = try openESISDatabase(databaseURL)
            guard let receipt = try db.settlementReceipt(settlementID) else {
                throw MCPToolError.invalidArguments(
                    "no such settlement: \(settlementID)")
            }
            return [
                "settlement_id": receipt.settlementID,
                "state_id": receipt.stateID ?? "",
                "payload": String(decoding: receipt.payload, as: UTF8.self),
                "payload_sha256": receipt.payloadSHA256,
                "validity": receipt.validity,
                "settled_at": receipt.settledAt ?? "",
                "summary": receipt.summary.map { summary -> [String: Any] in
                    [
                        "text": summary.summary,
                        "sha256": summary.summarySHA256,
                        "object_id": summary.summaryObjectID,
                        "query": summary.query,
                        "source_payload_digest": summary.sourcePayloadDigest,
                    ]
                } ?? NSNull(),
                "bindings": receipt.bindings,
                "dependencies": receipt.dependencies.map { entry -> [String: Any] in
                    [
                        "dependency_id": entry.dependencyID,
                        "revision": entry.revision,
                        "reason": entry.reason,
                    ]
                },
                "risk_notices": receipt.riskNotices.map { notice -> [String: Any] in
                    [
                        "code": notice.code,
                        "settlement_id": notice.settlementID,
                        "detail": notice.detail,
                    ]
                },
            ]

        case "simigo_is_declare_reuse":
            let db = try openESISDatabase(databaseURL)
            return Self.reuseContractReply(
                try Self.declareReuseContract(db, from: arguments))

        case "simigo_es_begin":
            let model = try requiredString(arguments, "model")
            let tokenizer = try requiredString(arguments, "tokenizer")
            let db = try openESISDatabase(databaseURL)
            let stateID = optionalString(arguments, "state_id") ?? UUID().uuidString
            let sessionID = optionalString(arguments, "session_id")

            // Resuming a state is not a rewrite: an existing execution keeps the
            // model and position it was begun under, and a settled one is closed.
            let resumedPosition: Int?
            if let existing = try db.executionStatePosition(stateID) {
                if let settled = try db.latestSettlementID(forStateID: stateID) {
                    throw MCPToolError.invalidArguments(
                        "execution \(stateID) already settled as \(settled); begin a new state")
                }
                let begunModel = try db.executionStateModelIdentity(stateID) ?? ""
                guard begunModel == model else {
                    throw MCPToolError.invalidArguments(
                        "execution \(stateID) was begun by \(begunModel); a different model needs a new state")
                }
                let begunTokenizer = try db.executionStateTokenizerIdentity(stateID) ?? ""
                guard !begunTokenizer.isEmpty, begunTokenizer == tokenizer else {
                    throw MCPToolError.invalidArguments(
                        "execution \(stateID) was begun with tokenizer \(begunTokenizer); a different or unrecorded tokenizer cannot resume this state")
                }
                resumedPosition = existing
            } else {
                let parentStateID = optionalString(arguments, "parent_state_id")
                let position: Int
                if let explicit = arguments["position"] as? Int, explicit >= 0 {
                    position = explicit
                } else if let parentStateID,
                    let parentPosition = try db.executionStatePosition(parentStateID)
                {
                    position = parentPosition + 1
                } else {
                    position = 0
                }
                try db.recordExecutionState(
                    id: stateID, parentID: parentStateID, modelIdentity: model,
                    tokenizerIdentity: tokenizer, graphManaged: false,
                    position: position, continuationID: "mcp-" + UUID().uuidString,
                    anchor: "", lifecycle: "active", createdAt: Date())
                resumedPosition = nil
            }

            // MCP begin does not resolve the current Information-Space demand.
            // It must not expose a historical answer as if it satisfied this
            // newly begun ES. A future MCP reuse path must resolve and bind the
            // current demand, then use explicit settlement consumption.
            let reusable: [String: Any] = [:]
            return [
                "state_id": stateID,
                "parent_state_id": try db.executionStateParentID(stateID) ?? "",
                "position": try db.executionStatePosition(stateID) ?? 0,
                "resumed": resumedPosition != nil,
                "settled": false,
                "reusable_answer": reusable.isEmpty ? NSNull() : reusable,
            ]

        case "simigo_es_settle":
            let stateID = try requiredString(arguments, "state_id")
            let model = try requiredString(arguments, "model")
            let tokenizer = try requiredString(arguments, "tokenizer")
            let output = try requiredString(arguments, "output")
            let db = try openESISDatabase(databaseURL)

            guard let position = try db.executionStatePosition(stateID) else {
                throw MCPToolError.invalidArguments(
                    "execution \(stateID) was never begun; call simigo_es_begin first")
            }
            if let begunModel = try db.executionStateModelIdentity(stateID),
                begunModel != model
            {
                throw MCPToolError.invalidArguments(
                    "execution \(stateID) was begun by \(begunModel); a settlement cannot be recorded under a different model identity")
            }
            let begunTokenizer = try db.executionStateTokenizerIdentity(stateID) ?? ""
            guard !begunTokenizer.isEmpty, begunTokenizer == tokenizer else {
                throw MCPToolError.invalidArguments(
                    "execution \(stateID) was begun with tokenizer \(begunTokenizer); a different or unrecorded tokenizer cannot settle this state")
            }
            // Cross-path declarations make a retry idempotent: the common
            // entrance decides whether this submission reuses the existing
            // settlement, creates an explicitly declared new revision, or is
            // refused. Without a declaration the legacy rule stands — one
            // state settles once.
            let declaredIdentity = declaredSourceIdentity(from: arguments)
            let operationKey = optionalString(arguments, "idempotency_key")
            let hasDeclaration = !declaredIdentity.isAbsent || operationKey != nil
            if !hasDeclaration, let settled = try db.latestSettlementID(forStateID: stateID) {
                throw MCPToolError.invalidArguments(
                    "execution \(stateID) already settled as \(settled); a state settles once")
            }

            let demandID = optionalString(arguments, "demand_id") ?? ""
            let retrievalID = optionalString(arguments, "retrieval_settlement_id") ?? ""
            guard demandID.isEmpty == retrievalID.isEmpty else {
                throw MCPToolError.invalidArguments(
                    "demand_id and retrieval_settlement_id must be supplied together")
            }
            if !retrievalID.isEmpty {
                guard let receipt = try db.settlementReceipt(retrievalID) else {
                    throw MCPToolError.invalidArguments(
                        "no such retrieval settlement: \(retrievalID)")
                }
                guard receipt.validity == "valid" else {
                    throw MCPToolError.invalidArguments(
                        "retrieval settlement \(retrievalID) is \(receipt.validity); a new result cannot cite it")
                }
            }
            let resolution = demandID.isEmpty
                ? nil
                : InformationLoop.Resolution(
                    demandID: demandID, stateID: stateID, reused: false,
                    hits: [], inputDigest: "", resultSHA256: "",
                    retrievalSettlementID: retrievalID, itemIDs: [],
                    staleItemIDs: [])

            // Declared sources are part of the settlement contract, so they are
            // validated before anything is written and committed in the same
            // transaction as the result: a settle never succeeds while dropping
            // a source it claims. An address must already be a sealed object —
            // the FK enforces it, and this turns that into a clear refusal.
            var declaredDependencies: [ESISDatabase.DeclaredDependency] = []
            for entry in arguments["dependencies"] as? [[String: Any]] ?? [] {
                guard let dependencyID = entry["dependency_id"] as? String,
                    !dependencyID.isEmpty
                else {
                    throw MCPToolError.invalidArguments(
                        "every dependency needs a non-empty dependency_id")
                }
                let address = (entry["content_address"] as? String) ?? ""
                guard !address.isEmpty else {
                    throw MCPToolError.invalidArguments(
                        "dependency \(dependencyID) has no content_address; cite the sealed object it relies on")
                }
                guard try db.objectRow(address) != nil else {
                    throw MCPToolError.invalidArguments(
                        "dependency \(dependencyID) cites \(address), which is not a sealed object; cite an existing object id such as a prior settlement's payload_sha256")
                }
                declaredDependencies.append(.init(
                    dependencyID: dependencyID, contentAddress: address,
                    reason: entry["reason"] as? String ?? "declared"))
            }

            let turn = try InformationLoop(database: db).settleTurn(
                generatedText: output,
                resolution: resolution,
                stateID: stateID,
                parentStateID: optionalString(arguments, "parent_state_id")
                    ?? (try db.executionStateParentID(stateID)),
                position: position,
                modelIdentity: model,
                identity: .init(model: model, tokenizer: tokenizer),
                sessionID: optionalString(arguments, "session_id"),
                summaryQuery: optionalString(arguments, "query"),
                actions: arguments["actions"] as? [String]
                    ?? ["external.mcp.settle"],
                declaredDependencies: declaredDependencies,
                sourceIdentity: declaredIdentity.isAbsent ? nil : declaredIdentity,
                operationKey: operationKey)

            // Publish the demand this result answers, so an exact repeat of the
            // same question in the same session can be served from the
            // settlement. Additive like the summary: the settlement above is
            // already authoritative, so a publish failure is reported instead
            // of turned into a false "settle failed". A settle that already
            // advanced a retrieval demand needs no publish.
            var publishedDemandID = ""
            var demandError = ""
            if turn.advancementID.isEmpty,
                let sessionID = optionalString(arguments, "session_id"),
                let query = optionalString(arguments, "query")
            {
                do {
                    publishedDemandID = try db.recordAnsweredDemand(
                        stateID: turn.stateID, sessionID: sessionID, query: query,
                        settlementID: turn.settlementID,
                        actions: arguments["actions"] as? [String]
                            ?? ["external.mcp.settle"])
                } catch {
                    demandError = String(describing: error)
                }
            }

            // Owner ruling 2026-11-16, shape (iii): the settle request may carry
            // the reuse terms inline, so a caller that already knows them
            // declares in one step instead of two. Additive like the demand
            // publish above — the settlement is already authoritative, so a
            // refused declaration is reported beside it instead of turning into
            // a false "settle failed".
            var reuseReply: [String: Any] = [:]
            var reuseError = ""
            if let terms = arguments["reuse_contract"] as? [String: Any] {
                do {
                    reuseReply = Self.reuseContractReply(
                        try Self.declareReuseContract(
                            db, from: terms, settlementID: turn.settlementID,
                            defaultQuery: optionalString(arguments, "query")))
                } catch {
                    reuseError = String(describing: error)
                }
            }

            // Read the dependencies back from the store: the reply reports what
            // was committed with the settlement, not what the caller asked for.
            let dependencyRows = try db.settlementDependencies(
                settlementID: turn.settlementID)
            return [
                "settlement_id": turn.settlementID,
                "state_id": turn.stateID,
                "advancement_id": turn.advancementID,
                "reused": turn.reused,
                "demand_id": publishedDemandID,
                "demand_error": demandError,
                "payload_sha256": try db.settlementPayloadDigest(turn.settlementID) ?? "",
                "validity": try db.settlementValidity(turn.settlementID),
                "summary_recorded": try db.settlementSummary(
                    settlementID: turn.settlementID) != nil,
                "reuse_contract": reuseReply.isEmpty ? NSNull() : reuseReply,
                "reuse_contract_error": reuseError,
                "dependencies": dependencyRows.map { entry -> [String: Any] in
                    [
                        "dependency_id": entry.dependencyID,
                        "revision": entry.revision,
                        "content_address": entry.contentAddress,
                    ]
                },
            ]

        case "simigo_es_fail":
            let stateID = try requiredString(arguments, "state_id")
            let detail = try requiredString(arguments, "detail")
            let db = try openESISDatabase(databaseURL)
            var evidence: [String: String] = [:]
            for (key, value) in arguments["evidence"] as? [String: Any] ?? [:] {
                guard let text = value as? String else {
                    throw MCPToolError.invalidArguments(
                        "evidence values must be strings: \(key)")
                }
                evidence[key] = text
            }
            let phase = (arguments["phase"] as? String)
                .flatMap(ManagedRefusal.Phase.init(rawValue:)) ?? .g
            let executionID = optionalString(arguments, "execution_id") ?? stateID
            let audit = db.recordFailureAudit(.init(
                executionID: executionID,
                attempt: arguments["attempt"] as? Int ?? 1,
                phase: phase,
                cause: nil,
                origin: .request,
                evidence: evidence,
                modelCalls: arguments["model_calls"] as? Int ?? 0,
                settlementsWritten: arguments["settlements_written"] as? Int ?? 0,
                detail: detail))
            return [
                "execution_id": executionID,
                "audit_persisted": audit.auditPersisted,
                "object_id": audit.objectID ?? "",
                "failure_class": audit.failureClass ?? "",
                "settlement_id": try db.latestSettlementID(forStateID: stateID) ?? "",
            ]

        case "simigo_project_brief":
            // 读取面只开放明确列举的类型：底层 kind 是自由字符串（status、
            // window、open-question 都在用），会话入口不能因此把每种都暴露出去。
            let kind = Self.optionalString(arguments, "kind") ?? "brief"
            guard Self.readableProjectKinds.contains(kind) else {
                throw MCPToolError.invalidArguments(
                    "kind must be one of "
                        + Self.readableProjectKinds.sorted().joined(separator: ", "))
            }
            let db = try openESISDatabase(databaseURL)
            // 默认视图本来就分客户端：`brief@codex` / `digest@zcode` 各存各的，
            // 跨端看是显式动作（scope=all），不是默认行为。
            var scope = (Self.optionalString(arguments, "scope") ?? "").lowercased()
            // 带了 session_id 就按它的前缀取，客户端不必另报一遍自己是谁。
            if scope.isEmpty,
                let session = Self.optionalString(arguments, "session_id") {
                scope = ESISDatabase.clientScope(ofSession: session) ?? ""
            }
            if scope == "all" {
                var notes = try db.currentProjectNotes(kindPrefix: kind)
                if kind == "brief" {
                    notes += try db.currentProjectNotes(kindPrefix: "digest")
                }
                return [
                    "kind": kind,
                    "scope": "all",
                    "notes": notes.map { Self.projectNoteView($0) },
                ]
            }
            var note = try db.currentProjectNote(
                kind: ESISDatabase.scopedKind(kind, scope: scope))
            if note == nil, !scope.isEmpty {
                note = try db.currentProjectNote(kind: kind)
            }
            var response: [String: Any] = [
                "kind": kind,
                "scope": scope.isEmpty ? "shared" : scope,
                // 分端读取报自己那条链的长度：拿共享链的 25 条去描述 brief@codex
                // 的第 1 条，是把两本不同的账混成一个数。取不到任何条目时按请求的
                // scoped kind 报，空视图也该说清是哪条链空着。
                "history": try db.projectNoteCount(
                    kind: note?.kind ?? ESISDatabase.scopedKind(kind, scope: scope)),
            ]
            if let note {
                response["note_id"] = note.noteID
                response["claim"] = note.claim
                response["recorded_at"] = note.recordedAt
                response["recorded_at_iso"] = Self.isoProjectStamp(note.recordedAt)
                response["supersedes"] = note.supersedes ?? ""
            } else {
                response["claim"] = ""
                response["hint"] =
                    "no \(kind) recorded; call simigo_project_note with kind=\(kind)"
            }
            // 简报之后的新材料随简报一起交付。这条链原先由各客户端的 SessionStart
            // 钩子各实现一遍（Codex 一个、zcode 一个），换客户端就断。产品这一层
            // 只列不加：把「这条判断写完之后库里又多了什么」交到读者手上，判断仍
            // 归读者——材料是过程，brief 是判断。
            //
            // 不限 kind（滚动摘要已在库层滤掉）。stale 与 newer_counts 是同一份
            // 数据的账面：有材料没被收进判断，这条判断就是过期的，而过期必须看得
            // 见——「多了个窗口」和「多了条裁定」不是一回事，后者意味着清单可能
            // 已失效，所以按 kind 分开计数，不揉成一个布尔。
            if kind == "brief", let note {
                let newer = try db.projectNotesNewerThan(than: note.recordedAt)
                response["newer_notes"] = newer.map { newer in
                    [
                        "kind": newer.kind,
                        "note_id": newer.noteID,
                        "recorded_at": newer.recordedAt,
                        "recorded_at_iso": Self.isoProjectStamp(newer.recordedAt),
                        "chars": newer.claim.count,
                        "head": newer.claim.split(separator: "\n").first.map(String.init)
                            ?? "",
                    ] as [String: Any]
                }
                response["stale"] = !newer.isEmpty
                response["newer_counts"] = Dictionary(
                    grouping: newer, by: { $0.kind }
                ).mapValues { $0.count }
            }
            // codex 端读自己那份时，一并看到所有端的现行简报（owner 裁定
            // 3E8F11CF）：它是把各端判断对齐的那一端，不该每次显式发 scope=all。
            // 别的端仍只看自己那份——跨端对它们是显式动作，不是默认。
            if kind == "brief", scope == "codex" {
                response["all_clients"] = try db.currentProjectNotes(kindPrefix: kind)
                    .map { Self.projectNoteView($0) }
            }
            // 设置页那格「自定义追加」跟着契约一起交付，否则它只是摆设。只有
            // contract 有这一格：别的 kind 是项目判断，不该被一段自由文本改写。
            if kind == "contract" {
                let extra = (UserDefaults.standard.string(
                    forKey: AppKey.isContractAddendum.rawValue) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !extra.isEmpty {
                    response["addendum"] = extra
                    response["claim"] = ((response["claim"] as? String) ?? "")
                        + "\n\n## 自定义追加（设置里手填，不属于 note 正文）\n" + extra
                }
            }
            return response

        case "simigo_project_note":
            // 写共享判断不传 scope；写本客户端那份传 scope=<前缀>，读写用同一
            // 条约定，免得有人发明 `brief/codex` 这种第二种写法。
            let kind = ESISDatabase.scopedKind(
                try requiredString(arguments, "kind"),
                scope: optionalString(arguments, "scope"))
            let claim = try requiredString(arguments, "claim")
            let db = try openESISDatabase(databaseURL)
            let result = try db.recordProjectNote(kind: kind, claim: claim)
            return [
                "note_id": result.note.noteID,
                "kind": kind,
                "supersedes": result.superseded ?? "",
                "created": result.created,
                "recorded_at": result.note.recordedAt,
                "recorded_at_iso": Self.isoProjectStamp(result.note.recordedAt),
                "current_is_this": try db.currentProjectNote(kind: kind)?.noteID
                    == result.note.noteID,
                "history": try db.projectNoteCount(kind: kind),
            ]

        case "simigo_chat_round":
            // A round written by somebody else's model: recorded with external
            // provenance, then verified in the same call. The two steps are kept
            // separate because only (session, request) pairs that carry BOTH
            // sides may be promoted — verification is not a caller argument.
            let sessionID = try requiredString(arguments, "session_id")
            let requestID = try requiredString(arguments, "request_id")
            let userText = try requiredString(arguments, "user")
            let assistantText = try requiredString(arguments, "assistant")
            // A boundary is not a courtesy note: a round that states no limit
            // reads as if it had none. It travels with the reply under one
            // heading, and its absence is reported in the result instead of
            // being silently allowed.
            let boundary = optionalString(arguments, "boundary")
            let storedText = ChatRoundText.compose(
                assistant: assistantText, boundary: boundary)
            let boundaryStated = ChatRoundText.statesBoundary(
                assistant: assistantText, boundary: boundary)
            let model = optionalString(arguments, "model")
            // Provider 是调用者声明的来源元数据（不构成语义复用准入，也不证明
            // 模型服务商）。缺失时不得伪造一个确定的 codex 身份：先按规范的
            // 会话前缀推断，推不出就记 unknown，让按 provider 的统计自己显形。
            let provider: String
            if let declared = optionalString(arguments, "provider") {
                provider = declared
            } else if sessionID.hasPrefix("codex-") {
                provider = "codex"
            } else if sessionID.hasPrefix("zcode-") {
                provider = "zcode"
            } else if sessionID.hasPrefix("qoder-") || sessionID.hasPrefix("qoder:") {
                provider = "qoder"
            } else {
                provider = "unknown"
            }
            let createdAt = Date()
            let db = try openESISDatabase(databaseURL)
            let userID = try db.recordExternalTurn(
                sessionID: sessionID, provider: provider, requestID: requestID,
                userText: userText, model: model, createdAt: createdAt)
            let assistantID = try db.recordExternalResponse(
                sessionID: sessionID, provider: provider, requestID: requestID,
                assistantText: storedText, model: model, createdAt: createdAt)
            let promoted = try db.verifyExternalTurn(
                sessionID: sessionID, requestID: requestID, verifiedAt: createdAt)
            let rows = try db.chatTurnProvenance(
                sessionID: sessionID, requestID: requestID)
            // The ledger is the only place that can say a round never arrived:
            // the caller chooses the numbers, so a gap is its own statement.
            var ledger: [String: Any]?
            if let turnIndex = arguments["turn_index"] as? Int {
                let report = try db.recordTurnIndex(
                    sessionID: sessionID, turnIndex: turnIndex,
                    requestID: requestID, at: createdAt)
                ledger = [
                    "turn_index": report.turnIndex,
                    "entered": report.entered,
                    "highest": report.highest,
                    "missing": report.missing,
                    "continuous": report.isContinuous,
                    "conflict": report.conflict ?? "",
                ]
                NotificationCenter.default.post(
                    name: .simigoMCPTurnRecorded, object: nil)
                // 摘要不在这条回复里等：轮次先落盘，摘要在后台补。补不上就
                // 留在「缺摘要」的账上，面板看得见。
                TurnDigestScheduler.schedule(
                    sessionID: sessionID, turnIndex: turnIndex,
                    question: userText, answer: storedText)
            }
            var response: [String: Any] = [
                "session_id": sessionID,
                "request_id": requestID,
                "provider": provider,
                "message_ids": [userID, assistantID],
                "rows_promoted": promoted,
                "boundary_stated": boundaryStated,
                "rows": rows.map { row -> [String: Any] in
                    [
                        "message_id": row.messageID,
                        "role": row.role,
                        "turn_state": row.turnState,
                        "source_kind": row.sourceKind,
                        "source_provider": row.sourceProvider ?? "",
                        "content_sha256": row.contentSHA256,
                        "eligible": row.isEligible,
                    ]
                },
            ]
            if let ledger { response["turn_ledger"] = ledger }
            return response

        case "simigo_chat_correct":
            // 拒绝冲突只保护「不许覆盖」，正确内容还需要一个合法出口：否则一个
            // 写错的正文会让这条请求永久停在错误状态，因为任何再提交都会被拒。
            let sessionID = try requiredString(arguments, "session_id")
            let requestID = try requiredString(arguments, "request_id")
            let role = optionalString(arguments, "role") ?? "assistant"
            let text = try requiredString(arguments, "text")
            let reason = try requiredString(arguments, "reason")
            let actor = try requiredString(arguments, "actor")
            let db = try openESISDatabase(databaseURL)
            let correction = try db.correctChatMessage(
                sessionID: sessionID, requestID: requestID, role: role,
                correctedText: text, reason: reason, actor: actor)
            // 更正让这一轮的派生摘要失效（DB 层已删）。立刻排一次补算，别把它
            // 停在「缺摘要」的账上等人手动点：正文已经换了，旧摘要还留在发现
            // 路径里，等于同一轮有两个互相矛盾的表示。
            if let turn = correction.invalidatedTurnIndex {
                let question = (try? db.chatMessageText(
                    sessionID: sessionID, requestID: requestID, role: "user")) ?? ""
                TurnDigestScheduler.schedule(
                    sessionID: sessionID, turnIndex: turn,
                    question: question, answer: text)
            }
            let rows = try db.chatTurnProvenance(
                sessionID: sessionID, requestID: requestID)
            var response: [String: Any] = [
                "session_id": sessionID,
                "request_id": requestID,
                "role": role,
                "correction_id": correction.correctionID,
                "message_id": correction.messageID,
                "previous_sha256": correction.previousSHA256,
                "corrected_sha256": correction.correctedSHA256,
                "reason": correction.reason,
                "actor": correction.actor,
                "corrected_at": correction.correctedAt,
                "corrections": try db.chatCorrections(
                    sessionID: sessionID, requestID: requestID, role: role).count,
                "rows": rows.map { row -> [String: Any] in
                    [
                        "message_id": row.messageID,
                        "role": row.role,
                        "turn_state": row.turnState,
                        "source_kind": row.sourceKind,
                        "content_sha256": row.contentSHA256,
                        "eligible": row.isEligible,
                    ]
                },
            ]
            // 只有真的删了一轮摘要才报这个字段：没删就是没有，不拿 0 冒充轮号。
            if let turn = correction.invalidatedTurnIndex {
                response["digest_invalidated_turn"] = turn
            }
            return response

        default:
            throw MCPToolError.unknownTool(name)
        }
    }

    // MARK: - Reuse declaration: three entrances, one door

    /// Declare the reuse terms of one settled result. Owner ruling 2026-11-16
    /// opened three entrances — the MCP tool `simigo_is_declare_reuse`, the HTTP
    /// route `POST /v1/simigo/is/declare-reuse`, and `reuse_contract` carried on
    /// `simigo_es_settle` — and all three land here, so what counts as a
    /// declaration cannot drift between doors. Terms are required, never
    /// defaulted: reusability is a declared property of the settled result, so
    /// an unstated term is a refusal rather than a guess. `settlementID` and
    /// `defaultQuery` are the settle path's inline shape — the settlement it just
    /// wrote, and the query the result was produced for.
    @discardableResult
    static func declareReuseContract(
        _ db: ESISDatabase,
        from terms: [String: Any],
        settlementID: String? = nil,
        defaultQuery: String? = nil
    ) throws -> ESISDatabase.SettlementReuseDeclaration {
        let target = settlementID ?? optionalString(terms, "settlement_id") ?? ""
        guard !target.isEmpty else {
            throw MCPToolError.invalidArguments("settlement_id is required")
        }
        let query = optionalString(terms, "query") ?? defaultQuery ?? ""
        guard !query.isEmpty else {
            throw MCPToolError.invalidArguments(
                "query is required: the canonical input basis is part of the declaration")
        }
        var identity: SettlementIdentityBinding.Identity?
        if let required = terms["required_consumer_identity"] as? [String: Any] {
            let model = (required["model"] as? String) ?? ""
            let tokenizer = (required["tokenizer"] as? String) ?? ""
            // An unnamed engine is not a wildcard: a half-specified restriction
            // would read as "any consumer", the opposite of a restriction.
            guard !model.isEmpty, !tokenizer.isEmpty else {
                throw MCPToolError.invalidArguments(
                    "required_consumer_identity needs both model and tokenizer")
            }
            identity = SettlementIdentityBinding.Identity(
                model: model, tokenizer: tokenizer)
        }
        return try db.declareSettlementReuseContract(
            settlementID: target,
            contractID: try requiredString(terms, "contract_id"),
            demandClass: try requiredString(terms, "demand_class"),
            contractVersion: try requiredString(terms, "contract_version"),
            query: query,
            rootIDs: terms["root_ids"] as? [String],
            extractField: optionalString(terms, "extract_field")
                ?? SettlementConsumption.Contract.defaultExtractField,
            requiredConsumerIdentity: identity)
    }

    /// The reply reports the terms as committed, not as requested: the canonical
    /// digest and the recorded identity constraint are computed by the library
    /// inside its own write transaction.
    static func reuseContractReply(
        _ declaration: ESISDatabase.SettlementReuseDeclaration
    ) -> [String: Any] {
        [
            "settlement_id": declaration.settlementID,
            "contract_id": declaration.contractID,
            "demand_class": declaration.demandClass,
            "contract_version": declaration.contractVersion,
            "query": declaration.query,
            "root_ids": declaration.rootIDs,
            "canonical_digest": declaration.canonicalDigest,
            "extract_field": declaration.extractField,
            "required_identity_json": declaration.requiredIdentityJSON,
            "declared_at": declaration.declaredAt,
        ]
    }

    private static func requiredString(
        _ arguments: [String: Any], _ key: String
    ) throws -> String {
        guard let value = arguments[key] as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw MCPToolError.invalidArguments("\(key) is required")
        }
        return value
    }

    private static func optionalString(
        _ arguments: [String: Any], _ key: String
    ) -> String? {
        guard let value = arguments[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    /// 会话入口可读的 note 类型。新增一种之前先想清楚它是否该进入每个会话的
    /// 上下文——这份清单是白名单，不是 kind 全集的投影。
    /// `digest` 也在这里：它已经随每次握手交付，读不到才是怪事，而且分客户端
    /// 存了几份，只有让它可读才谈得上「看各自的那份 / 看全部的」。
    private static let readableProjectKinds: Set<String> = [
        "brief", "contract", "digest",
    ]

    /// 一条 note 的对外视图。跨端列举（scope=all）与 codex 的全端视图共用同一份
    /// 字段，免得两处各写一遍再各自漂移。
    private static func projectNoteView(
        _ note: ESISDatabase.ProjectNote
    ) -> [String: Any] {
        [
            "kind": note.kind,
            "note_id": note.noteID,
            "chars": note.claim.count,
            "recorded_at_iso": isoProjectStamp(note.recordedAt),
            "claim": note.claim,
        ]
    }

    /// Stored timestamps are reference-date seconds (the same codec the
    /// settlement rows use). Show both: the raw value is what a caller compares
    /// against, the ISO form is what a reader reads.
    private static func isoProjectStamp(_ stored: String) -> String {
        guard let seconds = Double(stored) else { return stored }
        return ISO8601DateFormatter().string(
            from: Date(timeIntervalSinceReferenceDate: seconds))
    }

    /// 客户端自报的名字（MCP 握手 `clientInfo.name`）→ 会话前缀。
    /// 每家保留自己的前缀：全都写 `codex-` 会让来源元数据和 provider 推断一起失真。
    static func clientPrefix(_ params: [String: Any]) -> String {
        let info = params["clientInfo"] as? [String: Any]
        let name = ((info?["name"] as? String) ?? "").lowercased()
        if name.contains("zcode") { return "zcode" }
        if name.contains("qoder") { return "qoder" }
        if name.contains("codex") { return "codex" }
        let slug = String(name.filter { $0.isLetter || $0.isNumber }.prefix(12))
        return slug.isEmpty ? "unknown" : slug
    }

    /// 握手时交付的判断：简报、比简报新的窗口材料、消费协议。
    ///
    /// 只交付，不合并：窗口材料是一张清单，写不写进简报仍由读的人决定。读库失败
    /// 也要留下可见的回执要求——静默是这个环节最大的漏洞。
    static func sessionInstructions(
        client: String, databaseURL: URL = ManagedPaths.databaseURL
    ) -> String {
        func stamp(_ stored: String) -> String {
            guard let seconds = Double(stored) else { return stored }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(
                from: Date(timeIntervalSinceReferenceDate: seconds))
        }
        func clock() -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: Date())
        }
        var out = ""
        do {
            let db = try openESISDatabase(databaseURL)
            // 默认只交付本客户端那份：`brief@codex` / `digest@codex`。没有就回
            // 落到共享条目——回落到共享，不是把别家那份端上来。
            func ownNote(_ kind: String) throws -> ESISDatabase.ProjectNote? {
                if client != "unknown",
                    let scoped = try db.currentProjectNote(
                        kind: ESISDatabase.scopedKind(kind, scope: client)),
                    !scoped.claim.isEmpty {
                    return scoped
                }
                return try db.currentProjectNote(kind: kind)
            }
            if let brief = try ownNote("brief"),
               !brief.claim.isEmpty {
                let short = String(brief.noteID.prefix(8))
                out += "## SimiGo 项目简报（IS · kind=\(brief.kind)，随 MCP 握手交付；"
                    + "数字均为旧值，须回仓重取）\n\n"
                out += "回执：本条回复第一行写「简报已注入 · \(short) · 记录 "
                    + "\(stamp(brief.recordedAt)) · \(brief.claim.count) 字 · \(clock())」，\n"
                out += "第二行写「brief 原文·未决第一条：<照抄>」（照抄，不当结论用）。\n"
                out += "只写一次，其余回答照常。\n\n" + brief.claim + "\n"
                let newer = try db.projectNotesNewerThan(than: brief.recordedAt)
                if !newer.isEmpty {
                    out += "\n## 简报之后的新材料（比 brief 新；未采纳，不是简报）\n"
                    out += "以下 \(newer.count) 条均须分别评估，不得以最新一条代替中间条目：\n"
                    for note in newer.suffix(10) {
                        let head = note.claim.split(separator: "\n")
                            .first.map(String.init) ?? ""
                        out += "- \(stamp(note.recordedAt)) · \(note.kind) · note="
                            + "\(String(note.noteID.prefix(8))) · \(head)\n"
                    }
                    out += "- 未读或无法核验时，不得推进 brief 的 supersede 时间。\n"
                }
            } else {
                out += "## 简报未注入（IS 里没有 kind=brief 的当前条目）\n\n"
                out += "回执：本条回复第一行写「简报未注入」。\n"
            }
            // 动态交接：自动摘录的最近若干轮，和 brief 分开写、分开读。
            // 摘录里有旧值，时刻在行首，读的人自己打折。
            if let rolling = try ownNote("digest"),
               !rolling.claim.isEmpty {
                out += "\n" + rolling.claim + "\n"
            }
            if let contract = try db.currentProjectNote(kind: "contract"),
               !contract.claim.isEmpty {
                let short = String(contract.noteID.prefix(8))
                out += "\n## IS 消费协议（kind=contract；这是消费纪律，不是研究成果）\n"
                out += "回执：本条回复第三行写「协议已注入 · \(short) · 记录 "
                    + "\(stamp(contract.recordedAt))」，并按协议第 5 条执行："
                    + "引用 note_id，不把协议正文抄进回复。\n\n" + contract.claim + "\n"
            }
        } catch {
            out += "## 简报未注入（服务端读库失败：\(error)）\n\n"
            out += "回执：本条回复第一行写「简报未注入」。\n"
        }
        out += "\n本客户端前缀：\(client)-（写入信息空间时 session_id 用这个前缀，"
            + "不要借用别家的前缀）。\n"
        out += "视图：上面是本客户端那份（`brief@\(client)`/`digest@\(client)`，"
            + "没有则共享条目）。要看所有客户端的现行 brief 与 digest，"
            + "调 `simigo_project_brief` 并传 `scope=all`；那不是默认行为。\n"
        return out
    }

    /// Source identity exactly as the common settlement entrance expects it.
    /// The revision is accepted as either text or a JSON number so a numeric
    /// declaration is not silently treated as missing and refused as incomplete.
    static func declaredSourceIdentity(
        from arguments: [String: Any]
    ) -> ESISDatabase.DeclaredSourceIdentity {
        func text(_ key: String) -> String? {
            if let value = arguments[key] as? String { return value }
            if let value = arguments[key] as? Int { return String(value) }
            if let value = arguments[key] as? NSNumber { return value.stringValue }
            return nil
        }
        return .init(
            sourceType: text("source_type"),
            sourceSessionID: text("source_session_id"),
            sourceTurnID: text("source_turn_id"),
            sourceMessageID: text("source_message_id"),
            sourceRevision: text("source_revision"))
    }

    private static func openESISDatabase(_ url: URL) throws -> ESISDatabase {
        let db = try ESISDatabase(url: url, createIfNeeded: true)
        try db.runMigrations()
        return db
    }
}
