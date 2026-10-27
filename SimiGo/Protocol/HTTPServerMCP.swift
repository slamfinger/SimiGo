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
                    + "repeated identical demand reuses its settled result.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
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

        default:
            throw MCPToolError.unknownTool(name)
        }
    }

    private static func openESISDatabase(_ url: URL) throws -> SimiGoESISDatabase {
        let db = try SimiGoESISDatabase(url: url, createIfNeeded: true)
        try db.runMigrations()
        return db
    }
}
