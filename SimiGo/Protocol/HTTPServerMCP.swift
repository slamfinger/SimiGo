import Foundation
import SimiGoRuntimeContract

/// MCP (JSON-RPC 2.0 over HTTP) facade over the SAME native ES/IS operations
/// the HTTP routes already use. There is no second database, retrieval path or
/// settlement authority here: every tool calls `SimiGoESISDatabase` /
/// `SimiGoInformationLoop`, so an external agent sees exactly the information
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
        guard let method = message["method"] as? String else {
            return Self.mcpError(
                id: message["id"] ?? NSNull(), code: -32600,
                message: "Invalid Request")
        }
        guard message.keys.contains("id") else { return nil }
        let id = message["id"] ?? NSNull()
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return Self.mcpResult(id: id, result: [
                "protocolVersion": "2025-06-18",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "simigo", "version": mcpVersion],
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
        let arguments = params["arguments"] as? [String: Any] ?? [:]
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
                    + "sessions are searched.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "session_id": ["type": "string"],
                        "root_ids": ["type": "array", "items": ["type": "string"]],
                        "include_chat": ["type": "boolean"],
                        "session_ids": ["type": "array", "items": ["type": "string"]],
                        "limit": ["type": "integer"],
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
                "name": "simigo_es_begin",
                "description":
                    "Start (or resume an unsettled) execution for an agent whose model "
                    + "runs outside SimiGo. Creates an ES but records NO result: an "
                    + "external call that never settles leaves a begun, unsettled state. "
                    + "When query + session_id are supplied, the answer already settled "
                    + "for that same question in that same session is returned as "
                    + "`reusable_answer` — a read, so the agent may skip its own model "
                    + "call when the producer identity also matches.",
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
                    + "payload_sha256), and an unsealed address refuses the whole settle.",
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
        ]
    }

    static func runMCPTool(
        name: String, arguments: [String: Any],
        databaseURL: URL = SimiGoPaths.databaseURL
    ) throws -> [String: Any] {
        switch name {
        case "simigo_is_search":
            guard let query = arguments["query"] as? String,
                !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw MCPToolError.invalidArguments("query is required")
            }
            let db = try openESISDatabase(databaseURL)
            let loop = SimiGoInformationLoop(database: db)
            let resolution = try loop.resolve(.init(
                sessionID: optionalString(arguments, "session_id"),
                query: query,
                rootIDs: arguments["root_ids"] as? [String] ?? [],
                includeChat: (arguments["include_chat"] as? Bool) ?? true,
                chatSessionIDs: arguments["session_ids"] as? [String] ?? [],
                limit: (arguments["limit"] as? Int) ?? 40))
            return [
                "demand_id": resolution.demandID,
                "reused": resolution.reused,
                "status": resolution.reused ? "reused" : "settled",
                "result_sha256": resolution.resultSHA256,
                "retrieval_settlement_id": resolution.retrievalSettlementID,
                "stale_items": resolution.staleItemIDs,
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
            return [
                "root_id": rootID,
                "path": standardized,
                "registered": true,
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
            ]

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
                    position: position, continuationID: "mcp-" + UUID().uuidString,
                    anchor: "", lifecycle: "active", createdAt: Date())
                resumedPosition = nil
            }

            // Reuse is reported here as a READ of the settled answer; the caller
            // still owns the decision, and nothing is written for asking.
            var reusable: [String: Any] = [:]
            if let sessionID, let query = optionalString(arguments, "query") {
                let loop = SimiGoInformationLoop(database: db)
                if let answer = loop.reusableAnswer(
                    sessionID: sessionID, query: query,
                    identity: .init(model: model, tokenizer: tokenizer))
                {
                    reusable = [
                        "text": answer.text,
                        "settlement_id": answer.settlementID,
                        "demand_id": answer.demandID,
                        "source_state_id": answer.sourceStateID,
                        "model_calls": 0,
                    ]
                }
            }
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
            if let settled = try db.latestSettlementID(forStateID: stateID) {
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
                : SimiGoInformationLoop.Resolution(
                    demandID: demandID, stateID: stateID, reused: false,
                    hits: [], inputDigest: "", resultSHA256: "",
                    retrievalSettlementID: retrievalID, itemIDs: [],
                    staleItemIDs: [])

            // Declared sources are part of the settlement contract, so they are
            // validated before anything is written and committed in the same
            // transaction as the result: a settle never succeeds while dropping
            // a source it claims. An address must already be a sealed object —
            // the FK enforces it, and this turns that into a clear refusal.
            var declaredDependencies: [SimiGoESISDatabase.DeclaredDependency] = []
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

            let turn = try SimiGoInformationLoop(database: db).settleTurn(
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
                declaredDependencies: declaredDependencies)

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
                        stateID: turn.childStateID, sessionID: sessionID, query: query,
                        settlementID: turn.settlementID,
                        actions: arguments["actions"] as? [String]
                            ?? ["external.mcp.settle"])
                } catch {
                    demandError = String(describing: error)
                }
            }

            // Read the dependencies back from the store: the reply reports what
            // was committed with the settlement, not what the caller asked for.
            let dependencyRows = try db.settlementDependencies(
                settlementID: turn.settlementID)
            return [
                "settlement_id": turn.settlementID,
                "state_id": turn.childStateID,
                "advancement_id": turn.advancementID,
                "demand_id": publishedDemandID,
                "demand_error": demandError,
                "payload_sha256": try db.settlementPayloadDigest(turn.settlementID) ?? "",
                "validity": try db.settlementValidity(turn.settlementID),
                "summary_recorded": try db.settlementSummary(
                    settlementID: turn.settlementID) != nil,
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
                .flatMap(SimiGoManagedRefusal.Phase.init(rawValue:)) ?? .g
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

        default:
            throw MCPToolError.unknownTool(name)
        }
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

    private static func openESISDatabase(_ url: URL) throws -> SimiGoESISDatabase {
        let db = try SimiGoESISDatabase(url: url, createIfNeeded: true)
        try db.runMigrations()
        return db
    }
}
