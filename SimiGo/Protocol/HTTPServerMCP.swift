import Foundation
import CoreFoundation
import Security
import Network
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

    struct ClientCredential {
        let token: String
        /// SHA-256 bearer digest; this is the stable ES/IS client_id.
        var digest: String
    }

    /// Issue a Client credential through the local management plane.
    /// Only the digest is persisted; the token is returned exactly once.
    static func issueClientCredential(databaseURL: URL = ManagedPaths.databaseURL) throws -> ClientCredential {
        var random = Data(count: 32)
        let status = random.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw MCPToolError.invalidArguments("could not generate a secure Client credential")
        }
        let token = random.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let digest = SettlementIdentityBinding.digest(token)
        let db = try openESISDatabase(databaseURL)
        defer { db.close() }
        try db.registerClientIdentity(digest)
        return ClientCredential(token: token, digest: digest)
    }

    /// Resolve the shared API/MCP ingress identity. The actual peer endpoint
    /// and trusted TLS state decide remote identity; MCP metadata cannot.
    static func resolveHTTPClientIdentity(
        authorizationHeader: String?,
        isLoopbackPeer: Bool,
        isTLS: Bool,
        databaseURL: URL = ManagedPaths.databaseURL
    ) throws -> String {
        if isLoopbackPeer { return ESISDatabase.ownerNamespace }
        guard isTLS else { throw HTTPServerError.clientTransportNotTrusted }
        guard let header = authorizationHeader,
              let separator = header.firstIndex(of: " ")
        else { throw HTTPServerError.clientAuthenticationRequired }
        let scheme = String(header[..<separator])
        let token = String(header[header.index(after: separator)...])
        guard scheme.caseInsensitiveCompare("Bearer") == .orderedSame,
              token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
        else { throw HTTPServerError.clientAuthenticationRequired }
        let clientID = SettlementIdentityBinding.digest(token)
        let db = try openESISDatabase(databaseURL)
        defer { db.close() }
        guard try db.isActiveClientIdentity(clientID) else {
            throw HTTPServerError.clientCredentialRejected
        }
        return clientID
    }

    /// API and MCP Agent sessions use one stable digest namespace. Owner IDs
    /// remain byte-identical; already-scoped sessions are never prefixed twice.
    static func scopedClientSessionID(_ sessionID: String, clientIdentityID: String) -> String {
        guard clientIdentityID != ESISDatabase.ownerNamespace else { return sessionID }
        let prefix = "mcp-\(clientIdentityID)-"
        return sessionID.hasPrefix(prefix) ? sessionID : prefix + sessionID
    }

    // MARK: - Transport

    func handleMCPRequest(
        _ request: HTTPRequest,
        context: ConnectionContext
    ) async {
        let peerEndpoint = context.connection.endpoint
        let localPeer = Self.isLocalMCPEndpoint(peerEndpoint)
        guard Self.isMCPPeerAllowed(
            endpoint: peerEndpoint,
            isTLS: context.transportSecurity.isTLS
        ) else {
            sendMCPPayload(
                Self.mcpError(
                    id: NSNull(), code: -32003,
                    message: "remote MCP requires a TLS connection"),
                status: 403,
                context: context)
            return
        }
        guard let authenticatedClientID = context.clientIdentityID,
              (localPeer || authenticatedClientID != ESISDatabase.ownerNamespace)
        else {
            sendMCPPayload(
                Self.mcpError(id: NSNull(), code: -32001,
                              message: "MCP request has no authenticated Client identity"),
                status: 401, context: context)
            return
        }
        let clientIdentityID = localPeer ? ESISDatabase.ownerNamespace : authenticatedClientID
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
            let responses = batch.compactMap {
                mcpResponse(for: $0, clientIdentityID: clientIdentityID)
            }
            if responses.isEmpty {
                sendMCPAccepted(context: context)
            } else {
                sendMCPPayload(responses, status: 200, context: context)
            }
            return
        }
        if let response = mcpResponse(for: parsed, clientIdentityID: clientIdentityID) {
            sendMCPPayload(response, status: 200, context: context)
        } else {
            sendMCPAccepted(context: context)
        }
    }

    /// The endpoint is the accepted peer, not the request's Host header.
    /// Loopback MCP calls share the first-party owner namespace. Other peers
    /// use the Client identity bound by the shared HTTP Authorization ingress.
    static func isLocalMCPEndpoint(_ endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return address == .loopback
            case .ipv6(let address):
                return address.isLoopback
            case .name(let name, _):
                return name.caseInsensitiveCompare("localhost") == .orderedSame
            @unknown default:
                return false
            }
        case .unix:
            return true
        default:
            return false
        }
    }

    static func isMCPPeerAllowed(endpoint: NWEndpoint, isTLS: Bool) -> Bool {
        isLocalMCPEndpoint(endpoint) || isTLS
    }

    private static let ownerOnlyMCPToolNames: Set<String> = [
        "simigo_is_status",
        "simigo_roots_list",
        "simigo_root_register",
        "simigo_is_reconcile",
    ]

    private static func isOwnerOnlyMCPTool(_ name: String) -> Bool {
        ownerOnlyMCPToolNames.contains(name)
    }

    /// `nil` means the message was a notification and carries no response.
    func mcpResponse(
        for raw: Any,
        databaseURL: URL = ManagedPaths.databaseURL,
        clientIdentityID: String = ESISDatabase.ownerNamespace
    ) -> [String: Any]? {
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
            do {
                var result: [String: Any] = [
                    "protocolVersion": "2025-06-18",
                    "capabilities": ["tools": [:] as [String: Any]],
                    "serverInfo": ["name": "simigo", "version": mcpVersion],
                ]
                // initialize only negotiates the MCP protocol. Identity is
                // authenticated by HTTP Authorization and is never emitted in _meta.
                result["instructions"] = Self.sessionInstructions(
                    client: clientIdentityID, databaseURL: databaseURL)
                return Self.mcpResult(id: id, result: result)
            } catch {
                return Self.mcpError(id: id, code: -32001, message: String(describing: error))
            }
        case "ping":
            return Self.mcpResult(id: id, result: [:])
        case "tools/list":
            let tools = clientIdentityID == ESISDatabase.ownerNamespace
                ? Self.mcpToolDefinitions
                : Self.mcpToolDefinitions.filter {
                    guard let name = $0["name"] as? String else { return false }
                    return !Self.isOwnerOnlyMCPTool(name)
                }
            return Self.mcpResult(id: id, result: ["tools": tools])
        case "tools/call":
            return mcpToolCall(
                id: id, params: params, databaseURL: databaseURL,
                clientIdentityID: clientIdentityID)
        default:
            return Self.mcpError(
                id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func mcpToolCall(
        id: Any, params: [String: Any], databaseURL: URL,
        clientIdentityID: String
    ) -> [String: Any] {
        guard let name = params["name"] as? String, !name.isEmpty else {
            return Self.mcpError(
                id: id, code: -32602, message: "Missing tool name")
        }
        if clientIdentityID != ESISDatabase.ownerNamespace,
           Self.isOwnerOnlyMCPTool(name) {
            return Self.mcpResult(id: id, result: [
                "content": [[
                    "type": "text",
                    "text": "this MCP tool requires the first-party owner identity",
                ]],
                "isError": true,
            ])
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
            // params._meta, clientInfo, and session_id never select identity.
            var scopedArguments = arguments
            if scopedArguments["provider"] == nil,
               let sessionID = try Self.strictOptionalString(scopedArguments, "session_id") {
                if sessionID.hasPrefix("codex-") {
                    scopedArguments["provider"] = "codex"
                } else if sessionID.hasPrefix("zcode-") {
                    scopedArguments["provider"] = "zcode"
                } else if sessionID.hasPrefix("qoder-") || sessionID.hasPrefix("qoder:") {
                    scopedArguments["provider"] = "qoder"
                }
            }
            if clientIdentityID != ESISDatabase.ownerNamespace {
                if let sessionID = try Self.strictOptionalString(scopedArguments, "session_id") {
                    scopedArguments["session_id"] = Self.scopedClientSessionID(
                        sessionID, clientIdentityID: clientIdentityID)
                }
                if let sessionIDs = try Self.strictOptionalStringArray(scopedArguments, "session_ids") {
                    scopedArguments["session_ids"] = sessionIDs.map {
                        Self.scopedClientSessionID($0, clientIdentityID: clientIdentityID)
                    }
                }
            }
            let result = try Self.runMCPTool(
                name: name, arguments: scopedArguments,
                databaseURL: databaseURL,
                clientIdentityID: clientIdentityID)
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
                    + "repeated identical demand reuses its settled result. "
                    + "Loopback API and MCP clients share owner; LAN API and MCP use the same "
                    + "HTTP Authorization: Bearer Client credential. MCP initialize/_meta never issues identity. "
                    + "`session_id` is "
                    + "only transport/audit provenance. `session_ids`, when supplied, "
                    + "selects a subset of this client's own stored sessions; omitted or empty "
                    + "means all sessions owned by this client. `request_id` is this "
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
                    + "index/dependency entries and integrity counters. Shallow checks "
                    + "are the default; pass deep=true to hash every stored object.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["deep": ["type": "boolean"]],
                ],
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
                "name": "simigo_es_list",
                "description":
                    "List execution states in this authenticated Client identity namespace across Agent sessions. Loopback clients use owner; LAN clients use the HTTP Authorization bearer shared by API and MCP. "
                    + "Use a returned state_id as parent_state_id in simigo_es_begin to continue that history "
                    + "in a new Agent session. Results never cross MCP client identities.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["limit": ["type": "integer"]],
                ],
            ],
            [
                "name": "simigo_es_begin",
                "description":
                    "Start (or resume an unsettled) execution for an agent whose model "
                    + "runs outside SimiGo. Creates an ES but records NO result: an "
                    + "external call that never settles leaves a begun, unsettled state. "
                    + "begin never returns a historical answer and never consumes one. "
                    + "SimiGo binds loopback ES to owner and LAN ES to the HTTP-authenticated Client identity; "
                    + "the same identity spans all Agent sessions. A child ES must name a "
                    + "parent_state_id owned by this client. Use simigo_es_list to discover "
                    + "prior states, and simigo_es_consume explicitly to try zero-call consumption; "
                    + "a miss means begin/generate/settle normally, while a named-source "
                    + "refusal must not be treated as a generation fallback.",
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
                "name": "simigo_es_consume",
                "description":
                    "Explicitly consume the current IS demand for this exact query. "
                    + "current_demand_id must come from simigo_is_search in this request; "
                    + "it is re-validated inside the consumption write transaction. "
                    + "the local owner or HTTP-authenticated LAN Client ID scopes it across Agent sessions. "
                    + "A miss writes nothing and lets the Agent call simigo_es_begin, "
                    + "generate, and simigo_es_settle. A found answer is consumed only "
                    + "through the native transactional SettlementConsumption admission: "
                    + "the source must have an explicit reuse contract, remain valid, and "
                    + "match the current query/root basis and dependencies. A refusal is "
                    + "terminal for this attempt and must not silently fall back to "
                    + "generation. Success returns the verified value, derived consumer "
                    + "ES/settlement IDs, and model_calls=0. request_id makes retries "
                    + "idempotent within this continuity.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "model": ["type": "string"],
                        "tokenizer": ["type": "string"],
                        "session_id": ["type": "string"],
                        "request_id": ["type": "string"],
                        "current_demand_id": ["type": "string"],
                        "query": ["type": "string"],
                        "root_ids": ["type": "array", "items": ["type": "string"]],
                        "parent_state_id": ["type": "string"],
                        "position": ["type": "integer"],
                        "source_settlement_id": ["type": "string"],
                    ],
                    "required": ["model", "tokenizer", "request_id", "current_demand_id", "query"],
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
                    + "not what is true now. `kind` defaults to brief; other readable "
                    + "kinds are digest (rolling context) and contract (consumer protocol). "
                    + "A brief also carries `newer_notes`: notes of ANY kind "
                    + "recorded after it (auto-rolled digests excepted), i.e. "
                    + "material the judgement has not accounted for yet — plus "
                    + "`stale` and `newer_counts`, so an out-of-date judgement "
                    + "reports itself instead of reading as current. The list is "
                    + "handed over, never merged — deciding what it changes is the "
                    + "reader's job, not the server's; loopback calls use brief@owner and digest@owner. "
                    + "Remote TLS calls are scoped to the Client identity authenticated by HTTP Authorization "
                    + "shared by API and MCP; a remote client cannot select another scope.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "kind": [
                            "type": "string", "enum": ["brief", "contract", "digest"],
                        ],
                    ],
                ],
            ],
            [
                "name": "simigo_project_note",
                "description":
                    "Record a judgement about the project and supersede the current "
                    + "one of the same kind. Kinds in use: brief (what the project "
                    + "is and where it stands), digest (rolling context), status, "
                    + "decision, open-question. "
                    + "Append-only: the previous note stays readable, the new one "
                    + "becomes current by being the note nothing supersedes. "
                    + "Recording an identical claim again is a no-op. MCP writes are "
                    + "scoped to owner for loopback calls or to the HTTP-authenticated LAN Client ID; the "
                    + "Agent does not provide or choose an identity string.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string"],
                        "claim": ["type": "string"],
                    ],
                    "required": ["kind", "claim"],
                ],
            ],
        ]
    }

    /// Parse the HTTP search surface into the same argument vocabulary as MCP.
    /// Body values win; repeated query parameters support array-valued scopes.
    static func informationSearchArguments(
        body: Data, requestTarget: String
    ) throws -> [String: Any] {
        var arguments: [String: Any] = [:]
        if !body.isEmpty {
            let decoded: Any
            do {
                decoded = try JSONSerialization.jsonObject(with: body)
            } catch {
                throw MCPToolError.invalidArguments("request body must be valid JSON")
            }
            guard let object = decoded as? [String: Any] else {
                throw MCPToolError.invalidArguments("request body must be a JSON object")
            }
            arguments = object
        }

        let queryItems = URL(string: "http://x" + requestTarget)
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []

        func scalarQueryValue(_ name: String) throws -> String? {
            let matches = queryItems.filter { $0.name == name }
            guard matches.count <= 1 else {
                throw MCPToolError.invalidArguments("\(name) may appear only once")
            }
            guard let item = matches.first else { return nil }
            guard let value = item.value, !value.isEmpty else {
                throw MCPToolError.invalidArguments("\(name) must have a value")
            }
            return value
        }
        func queryValue(_ names: [String]) throws -> String? {
            for name in names {
                if let value = try scalarQueryValue(name) { return value }
            }
            return nil
        }
        func queryBoolean(_ value: String, key: String) throws -> Bool {
            switch value.lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: throw MCPToolError.invalidArguments("\(key) must be a boolean")
            }
        }

        if arguments["query"] == nil {
            if arguments.keys.contains("q") {
                guard let bodyQuery = arguments["q"] as? String else {
                    throw MCPToolError.invalidArguments("q must be a string")
                }
                arguments["query"] = bodyQuery
            } else if let query = try queryValue(["q", "query"]) {
                arguments["query"] = query
            }
        }
        for key in ["session_id", "request_id", "root_id"] where arguments[key] == nil {
            if let value = try queryValue([key]) { arguments[key] = value }
        }
        if arguments["root_ids"] == nil && arguments["root_id"] == nil {
            let matches = queryItems.filter { $0.name == "root_ids" }
            if !matches.isEmpty {
                let values = try matches.map { item -> String in
                    guard let value = item.value, !value.isEmpty else {
                        throw MCPToolError.invalidArguments("root_ids values must be non-empty")
                    }
                    return value
                }
                arguments["root_ids"] = values
            }
        }
        if arguments["session_ids"] == nil {
            let matches = queryItems.filter { $0.name == "session_ids" }
            if !matches.isEmpty {
                let values = try matches.map { item -> String in
                    guard let value = item.value, !value.isEmpty else {
                        throw MCPToolError.invalidArguments("session_ids values must be non-empty")
                    }
                    return value
                }
                arguments["session_ids"] = values
            }
        }
        for key in ["include_chat", "include_brief"] where arguments[key] == nil {
            if let raw = try queryValue([key]) {
                arguments[key] = try queryBoolean(raw, key: key)
            }
        }
        if arguments["limit"] == nil, let raw = try queryValue(["limit"]) {
            guard let limit = Int(raw) else {
                throw MCPToolError.invalidArguments("limit must be an integer")
            }
            arguments["limit"] = limit
        }
        return arguments
    }

    /// Parse the HTTP status query without silently turning malformed deep flags off.
    static func informationStatusArguments(requestTarget: String) throws -> [String: Any] {
        let queryItems = URL(string: "http://x" + requestTarget)
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let matches = queryItems.filter { $0.name == "deep" }
        guard matches.count <= 1 else {
            throw MCPToolError.invalidArguments("deep may appear only once")
        }
        guard let item = matches.first else { return [:] }
        guard let value = item.value, !value.isEmpty else {
            throw MCPToolError.invalidArguments("deep must have a value")
        }
        let deep: Bool
        switch value.lowercased() {
        case "1", "true", "yes", "on": deep = true
        case "0", "false", "no", "off": deep = false
        default: throw MCPToolError.invalidArguments("deep must be a boolean")
        }
        return ["deep": deep]
    }

    /// Canonical IS search operation and wire-independent response payload.
    /// Both HTTP and MCP call this exact implementation.
    static func runInformationSearch(
        arguments: [String: Any], databaseURL: URL,
        clientIdentityID: String? = ESISDatabase.ownerNamespace
    ) throws -> [String: Any] {
        guard let query = arguments["query"] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError.invalidArguments("query is required")
        }
        let sessionID = try strictOptionalString(arguments, "session_id")
        let continuityID = clientIdentityID == nil
            ? try strictOptionalString(arguments, "continuity_id") : nil
        let requestID = try strictOptionalString(arguments, "request_id")
        if clientIdentityID != ESISDatabase.ownerNamespace,
           (arguments.keys.contains("root_ids") || arguments.keys.contains("root_id")) {
            throw MCPToolError.invalidArguments(
                "registered host-file roots are owner-only; Client search is limited to its own chat and settlements")
        }
        let rootIDs: [String]
        if arguments.keys.contains("root_ids") {
            rootIDs = try strictOptionalStringArray(arguments, "root_ids") ?? []
        } else if let rootID = try strictOptionalString(arguments, "root_id") {
            rootIDs = [rootID]
        } else {
            rootIDs = []
        }
        let requestedIncludeChat = try strictOptionalBoolean(arguments, "include_chat") ?? true
        let requestedChatSessionIDs = try strictOptionalStringArray(arguments, "session_ids") ?? []
        let limit = try strictOptionalInteger(arguments, "limit") ?? 40
        let includeBrief = try strictOptionalBoolean(arguments, "include_brief") ?? true

        let db = try openESISDatabase(databaseURL)
        let chatSessionIDs: [String]
        let includeChat: Bool
        if let clientIdentityID {
            if requestedChatSessionIDs.isEmpty {
                // Empty means identity-wide, not "the sessions that happen to
                // exist right now". Keep the logical scope open before its first
                // session; InformationLoop resolves and fingerprints its watermark.
                chatSessionIDs = []
                includeChat = requestedIncludeChat
            } else {
                let owned = Set(try db.chatSessionIDs(clientIdentityID: clientIdentityID))
                chatSessionIDs = requestedChatSessionIDs.filter { owned.contains($0) }
                // A foreign-only explicit subset must not fall back to identity-wide.
                includeChat = requestedIncludeChat && !chatSessionIDs.isEmpty
            }
        } else {
            // Explicit nil is the retained direct/legacy continuity helper path.
            chatSessionIDs = requestedChatSessionIDs
            includeChat = requestedIncludeChat
        }
        let resolution = try InformationLoop(database: db).resolve(.init(
            sessionID: sessionID,
            continuityID: continuityID,
            clientIdentityID: clientIdentityID,
            requestIdentity: requestID,
            query: query,
            rootIDs: rootIDs,
            includeRoots: clientIdentityID == ESISDatabase.ownerNamespace,
            includeChat: includeChat,
            // Reads are constrained to the active owner namespace: first-party local
            // sessions for owner, or bearer-prefixed sessions for external MCP.
            chatSessionIDs: chatSessionIDs,
            limit: limit))
        var response: [String: Any] = [
            "demand_id": resolution.demandID,
            "reused": resolution.reused,
            "status": resolution.reused ? "reused" : "settled",
            "result_sha256": resolution.resultSHA256,
            "retrieval_settlement_id": resolution.retrievalSettlementID,
            "stale_items": resolution.staleItemIDs,
            "index": resolution.unindexedTerms.isEmpty ? "fts5-trigram" : "partial-scan",
            "unindexed_terms": resolution.unindexedTerms,
            "items": resolution.hits.map { hit -> [String: Any] in
                [
                    "item_id": hit.itemID, "kind": hit.kind,
                    "locator": hit.locator, "line": hit.lineNo,
                    "text": hit.lineText, "source_sha256": hit.sourceSHA256,
                ]
            },
            "hits": resolution.hits.filter { $0.kind == "file" }.map { hit -> [String: Any] in
                [
                    "root_id": hit.rootID ?? "", "path": hit.relativePath ?? "",
                    "line": hit.lineNo, "text": hit.lineText,
                ]
            },
        ]
        let briefKind = ESISDatabase.scopedKind("brief", scope: clientIdentityID)
        if includeBrief, let brief = try db.currentProjectNote(kind: briefKind) {
            response["brief"] = [
                "note_id": brief.noteID, "claim": brief.claim,
                "chars": brief.claim.count, "recorded_at": brief.recordedAt,
                "recorded_at_iso": Self.isoProjectStamp(brief.recordedAt),
            ] as [String: Any]
        }
        return response
    }

    /// Carrier status is shallow by default; callers opt into object hashing with deep=true.
    static func runInformationStatus(
        arguments: [String: Any], databaseURL: URL
    ) throws -> [String: Any] {
        let deep = try strictOptionalBoolean(arguments, "deep") ?? false
        let db = try ESISDatabase(url: databaseURL, createIfNeeded: false, readOnly: true)
        let report = try db.carrierReport(deepVerify: deep)
        return [
            "schema_version": report.schemaVersion,
            "object_count": report.objectCount, "objects": report.objectCount,
            "object_bytes": report.objectBytes,
            "index_entries": report.indexEntries,
            "dependency_entries": report.dependencyEntries,
            "unaddressed_file_contents": report.unaddressedFileContents,
            "unaddressed_chat_messages": report.unaddressedChatMessages,
            "unaddressed_retrieval_results": report.unaddressedRetrievalResults,
            "unaddressed_settlements": report.unaddressedSettlements,
            "settlement_summaries": report.settlementSummaries,
            "dangling_references": report.danglingReferences,
            "corrupt_objects": report.corruptObjects,
            "inline_legacy_payloads": report.inlineLegacyPayloads,
            "deep_verified": report.deepVerified,
            "spaces": report.spaces,
            "dependency_intervals_open": report.dependencyIntervalsOpen,
            "dependency_intervals_closed": report.dependencyIntervalsClosed,
            "dependency_interval_breaks": report.dependencyIntervalBreaks,
            "turn_digests": report.turnDigests,
            "turns_without_digest": report.turnsWithoutDigest,
            "vacuum_failure": report.vacuumFailure ?? "",
        ]
    }

    /// The user question of a corrected turn, for digest rescheduling. A missing
    /// row is a legitimate empty question; a SQLite execution failure must
    /// propagate to the MCP error path, never collapse into semantic input (#277).
    static func correctedTurnQuestion(
        db: ESISDatabase, sessionID: String, requestID: String
    ) throws -> String {
        try db.chatMessageText(
            sessionID: sessionID, requestID: requestID, role: "user") ?? ""
    }

    /// In-process/built-in MCP calls are first-party owner operations by default.
    /// Local loopback calls use owner; remote network calls supply the authenticated bearer digest.
    static func runMCPTool(
        name: String, arguments: [String: Any],
        databaseURL: URL = ManagedPaths.databaseURL,
        clientIdentityID: String? = ESISDatabase.ownerNamespace
    ) throws -> [String: Any] {
        switch name {
        case "simigo_is_search":
            return try Self.runInformationSearch(
                arguments: arguments, databaseURL: databaseURL,
                clientIdentityID: clientIdentityID)

        case "simigo_es_list":
            guard let clientIdentityID else {
                throw MCPToolError.invalidArguments("simigo_es_list requires an MCP client identity")
            }
            let limit = try strictOptionalInteger(arguments, "limit") ?? 100
            guard limit > 0 else {
                throw MCPToolError.invalidArguments("limit must be positive")
            }
            let db = try openESISDatabase(databaseURL)
            let states = try db.executionStates(
                clientIdentityID: clientIdentityID, limit: limit)
            return [
                "client_identity_id": clientIdentityID,
                "count": states.count,
                "executions": states.map { state -> [String: Any] in
                    [
                        "state_id": state.stateID,
                        "parent_state_id": state.parentStateID ?? "",
                        "model": state.modelIdentity ?? "",
                        "position": state.position,
                        "lifecycle": state.lifecycle,
                        "created_at": state.createdAt,
                        "settlement_id": state.settlementID ?? "",
                    ]
                },
            ]

        case "simigo_is_status":
            return try Self.runInformationStatus(
                arguments: arguments, databaseURL: databaseURL)

        case "simigo_roots_list":
            let category = try strictOptionalString(arguments, "category") ?? "work"
            let db = try openESISDatabase(databaseURL)
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
            let category = try strictOptionalString(arguments, "category") ?? "work"
            let db = try openESISDatabase(databaseURL)
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
            if let clientIdentityID,
               try db.settlementClientIdentityID(settlementID) != clientIdentityID {
                throw MCPToolError.invalidArguments(
                    "settlement is not owned by this MCP client identity")
            }
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
            if let clientIdentityID {
                let settlementID = try requiredString(arguments, "settlement_id")
                guard try db.settlementClientIdentityID(settlementID) == clientIdentityID else {
                    throw MCPToolError.invalidArguments(
                        "settlement is not owned by this MCP client identity")
                }
            }
            return Self.reuseContractReply(
                try Self.declareReuseContract(db, from: arguments))

        case "simigo_es_consume":
            let model = try requiredString(arguments, "model")
            let tokenizer = try requiredString(arguments, "tokenizer")
            let sessionID = try strictOptionalString(arguments, "session_id")
            let continuityID: String?
            if clientIdentityID == nil {
                continuityID = try requiredString(arguments, "continuity_id")
            } else {
                continuityID = nil
            }
            guard let identityScope = clientIdentityID ?? continuityID else {
                throw MCPToolError.invalidArguments("MCP client identity is required")
            }
            let requestID = try requiredString(arguments, "request_id")
            let currentDemandID = try requiredString(arguments, "current_demand_id")
            let query = try requiredString(arguments, "query")
            let rootIDs = try strictOptionalStringArray(arguments, "root_ids") ?? []
            let requestedSourceID = try strictOptionalString(arguments, "source_settlement_id")
            let requestedParentID = try strictOptionalString(arguments, "parent_state_id")
            let explicitPosition = try strictOptionalInteger(arguments, "position")
            if let explicitPosition, explicitPosition < 0 {
                throw MCPToolError.invalidArguments("position must be a non-negative integer")
            }
            let db = try openESISDatabase(databaseURL)

            // The current demand handle pins this attempt to one owner-scoped
            // retrieval resolved this round. A missing, stale, or foreign handle
            // is a caller error and refuses the attempt; only a valid handle
            // with no matching answer is a miss that writes nothing.
            guard let currentDemand = try db.informationDemand(demandID: currentDemandID),
                  currentDemand.state == "RESOLVED",
                  currentDemand.query == query,
                  currentDemand.inputDigest == currentDemandID,
                  (clientIdentityID != nil
                      ? currentDemand.clientIdentityID == clientIdentityID
                      : currentDemand.continuityID == continuityID)
            else {
                throw MCPToolError.invalidArguments(
                    "current_demand_id \(currentDemandID) is missing, superseded, "
                        + "or does not belong to this identity scope")
            }

            // request_id, not the latest answer, selects an idempotent retry.
            // The key is scoped to this MCP client (or a legacy direct continuity).
            let consumerStateID = "mcp-consume-" + SettlementIdentityBinding.digest(
                identityScope + "\u{0}" + requestID)
            let existingConsumptions = try db.settlementConsumptions(
                consumerStateID: consumerStateID)
            let sourceSettlementID: String
            let sourceStateID: String
            if let existing = existingConsumptions.first {
                guard existingConsumptions.count == 1 else {
                    throw MCPToolError.invalidArguments(
                        "request_id has multiple consumption records; refusing ambiguous retry")
                }
                sourceSettlementID = existing.sourceSettlementID
                guard let receipt = try db.settlementReceipt(sourceSettlementID),
                      let recordedStateID = receipt.stateID else {
                    throw MCPToolError.invalidArguments(
                        "previously consumed source settlement is unavailable")
                }
                sourceStateID = recordedStateID
            } else {
                let answer: ESISDatabase.AnsweredDemand?
                if let clientIdentityID {
                    answer = try db.answeredDemand(
                        clientIdentityID: clientIdentityID, query: query)
                } else if let continuityID {
                    answer = try db.answeredDemand(
                        continuityID: continuityID, query: query)
                } else {
                    answer = nil
                }
                guard let answer else {
                    return [
                        "status": "miss",
                        "candidate_found": false,
                        "client_identity_id": clientIdentityID ?? "",
                        "continuity_id": continuityID ?? "",
                        "session_id": sessionID ?? "",
                        "query": query,
                        "model_calls": 0,
                    ]
                }
                sourceSettlementID = answer.answerSettlementID
                sourceStateID = answer.stateID
            }
            guard requestedSourceID == nil || requestedSourceID == sourceSettlementID else {
                throw MCPToolError.invalidArguments(
                    "source_settlement_id does not match the source pinned by this client/request")
            }
            if let requestedParentID, requestedParentID != sourceStateID {
                throw MCPToolError.invalidArguments(
                    "parent_state_id must be the ES that produced the answer being consumed")
            }
            guard let parentPosition = try db.executionStatePosition(sourceStateID) else {
                throw MCPToolError.invalidArguments(
                    "answer source execution state \(sourceStateID) is missing")
            }
            let consumerPosition = explicitPosition ?? (parentPosition + 1)

            // A repeated request ID resolves to the same consumer ES. Validate
            // immutable parameters before native idempotency admission.
            if try db.executionStatePosition(consumerStateID) != nil {
                let storedContinuity = try db.executionStateContinuityID(consumerStateID)
                let mismatches: [String] = [
                    try db.executionStateModelIdentity(consumerStateID) == model
                        ? nil : "model",
                    try db.executionStateTokenizerIdentity(consumerStateID) == tokenizer
                        ? nil : "tokenizer",
                    try db.executionStateParentID(consumerStateID) == sourceStateID
                        ? nil : "parent_state",
                    try db.executionStateClientIdentityID(consumerStateID)
                        == (clientIdentityID ?? ESISDatabase.ownerNamespace)
                        ? nil : "client_identity",
                    clientIdentityID != nil || storedContinuity == continuityID
                        ? nil : "continuity",
                    try db.executionStatePosition(consumerStateID) == consumerPosition
                        ? nil : "position",
                ].compactMap { $0 }
                guard mismatches.isEmpty else {
                    throw MCPToolError.invalidArguments(
                        "request_id was already used with different consumer ES parameters: "
                            + mismatches.joined(separator: ", "))
                }
            }

            let outcome: SettlementConsumption.Outcome
            do {
                outcome = try SettlementConsumption.consume(
                    db: db,
                    request: .init(
                        sourceSettlementID: sourceSettlementID,
                        consumerStateID: consumerStateID,
                        consumerParentStateID: sourceStateID,
                        consumerPosition: consumerPosition,
                        consumerModelIdentity: model,
                        consumerIdentity: .init(model: model, tokenizer: tokenizer),
                        sessionID: sessionID,
                        continuityID: continuityID,
                        clientIdentityID: clientIdentityID,
                        currentDemandID: currentDemandID,
                        existingDemandID: existingConsumptions.first?.demandID,
                        query: query,
                        rootIDs: rootIDs))
            } catch let refusal as SettlementConsumption.Refusal {
                throw MCPToolError.invalidArguments(
                    "settlement consumption refused: \(refusal)")
            }
            switch outcome {
            case .consumed(let receipt):
                return [
                    "status": "consumed",
                    "candidate_found": true,
                    "client_identity_id": clientIdentityID ?? "",
                    "continuity_id": continuityID ?? "",
                    "session_id": sessionID ?? "",
                    "query": query,
                    "value": receipt.value,
                    "source_settlement_id": receipt.sourceSettlementID,
                    "consumer_es_state_id": receipt.consumerStateID,
                    "consumer_settlement_id": receipt.consumerSettlementID,
                    "demand_id": receipt.demandID,
                    "current_demand_id": currentDemandID,
                    "canonical_digest": receipt.canonicalDigest,
                    "consumption_id": receipt.consumptionID,
                    "model_calls": receipt.modelCalls,
                    "reused_existing": receipt.reusedExisting,
                ]
            case .recompute(let reason):
                return [
                    "status": "recompute",
                    "candidate_found": true,
                    "client_identity_id": clientIdentityID ?? "",
                    "continuity_id": continuityID ?? "",
                    "session_id": sessionID ?? "",
                    "query": query,
                    "reason": reason,
                    "model_calls": 0,
                ]
            }

        case "simigo_es_begin":
            let model = try requiredString(arguments, "model")
            let tokenizer = try requiredString(arguments, "tokenizer")
            let sessionID = try strictOptionalString(arguments, "session_id")
            let requestedContinuityID = clientIdentityID == nil
                ? try strictOptionalString(arguments, "continuity_id") : nil
            let stateID: String
            if arguments.keys.contains("state_id") {
                guard let supplied = try strictOptionalString(arguments, "state_id"),
                      !supplied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPToolError.invalidArguments("state_id must be a non-empty string")
                }
                stateID = supplied
            } else {
                stateID = UUID().uuidString
            }
            let parentStateID = try strictOptionalString(arguments, "parent_state_id")
            let explicitPosition = try strictOptionalInteger(arguments, "position")
            if let explicitPosition, explicitPosition < 0 {
                throw MCPToolError.invalidArguments("position must be a non-negative integer")
            }
            let db = try openESISDatabase(databaseURL)

            // Built-in and loopback MCP calls use owner; remote MCP supplies its
            // authenticated bearer digest. Logical continuity remains lineage metadata,
            // never the cross-client identity boundary.
            let resumedPosition: Int?
            let continuityID: String?
            if let existing = try db.executionStatePosition(stateID) {
                if let clientIdentityID,
                   try db.executionStateClientIdentityID(stateID) != clientIdentityID {
                    throw MCPToolError.invalidArguments(
                        "execution is not owned by this MCP client identity")
                }
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
                if let clientIdentityID {
                    guard try db.executionStateClientIdentityID(stateID) == clientIdentityID else {
                        throw MCPToolError.invalidArguments(
                            "execution \(stateID) is not owned by this MCP client identity")
                    }
                    continuityID = nil
                } else {
                    let recordedContinuity = try db.executionStateContinuityID(stateID)
                    if let requestedContinuityID, let recordedContinuity,
                       requestedContinuityID != recordedContinuity {
                        throw MCPToolError.invalidArguments(
                            "execution \(stateID) belongs to continuity \(recordedContinuity), not \(requestedContinuityID)")
                    }
                    let legacyContinuity = requestedContinuityID ?? recordedContinuity
                        ?? UUID().uuidString.lowercased()
                    try db.bindExecutionStateContinuityID(legacyContinuity, to: stateID)
                    continuityID = legacyContinuity
                }
                resumedPosition = existing
            } else {
                let position: Int
                if let explicitPosition {
                    position = explicitPosition
                } else if let parentStateID,
                    let parentPosition = try db.executionStatePosition(parentStateID)
                {
                    position = parentPosition + 1
                } else {
                    position = 0
                }
                if let parentStateID, let clientIdentityID {
                    guard try db.executionStateClientIdentityID(parentStateID) == clientIdentityID else {
                        throw MCPToolError.invalidArguments(
                            "parent execution is not owned by this MCP client identity")
                    }
                }
                let parentContinuityID: String?
                if clientIdentityID == nil, let parentStateID {
                    parentContinuityID = try db.executionStateContinuityID(parentStateID)
                } else {
                    parentContinuityID = nil
                }
                if let clientIdentityID {
                    continuityID = nil
                } else {
                    let legacyContinuity = requestedContinuityID ?? parentContinuityID
                        ?? UUID().uuidString.lowercased()
                    continuityID = legacyContinuity
                    if let parentStateID {
                        if let parentContinuityID, parentContinuityID != legacyContinuity {
                            throw MCPToolError.invalidArguments(
                                "parent execution belongs to continuity \(parentContinuityID), not \(legacyContinuity)")
                        }
                        if parentContinuityID == nil {
                            try db.bindExecutionStateContinuityID(legacyContinuity, to: parentStateID)
                        }
                    }
                }
                try db.recordExecutionState(
                    id: stateID, parentID: parentStateID, modelIdentity: model,
                    tokenizerIdentity: tokenizer, graphManaged: false,
                    position: position, continuationID: "mcp-" + UUID().uuidString,
                    anchor: "", lifecycle: "active", createdAt: Date(),
                    continuityID: continuityID,
                    clientIdentityID: clientIdentityID)
                resumedPosition = nil
            }

            // Begin remains a lifecycle operation, not an answer lookup. The
            // separate consume tool resolves the current exact demand explicitly.
            return [
                "state_id": stateID,
                "session_id": sessionID ?? "",
                "client_identity_id": clientIdentityID ?? "",
                "continuity_id": continuityID ?? "",
                "parent_state_id": try db.executionStateParentID(stateID) ?? "",
                "position": try db.executionStatePosition(stateID) ?? 0,
                "resumed": resumedPosition != nil,
                "settled": false,
                "reusable_answer": NSNull(),
            ]

        case "simigo_es_settle":
            let stateID = try requiredString(arguments, "state_id")
            let model = try requiredString(arguments, "model")
            let tokenizer = try requiredString(arguments, "tokenizer")
            let output = try requiredString(arguments, "output")
            let sessionID = try strictOptionalString(arguments, "session_id")
            let requestedContinuityID = clientIdentityID == nil
                ? try strictOptionalString(arguments, "continuity_id") : nil
            let query = try strictOptionalString(arguments, "query")
            let parentStateID = try strictOptionalString(arguments, "parent_state_id")
            let operationKey = try strictOptionalString(arguments, "idempotency_key")
            let demandID = try strictOptionalString(arguments, "demand_id") ?? ""
            let retrievalID = try strictOptionalString(arguments, "retrieval_settlement_id") ?? ""
            let actions = try strictOptionalStringArray(arguments, "actions")
                ?? ["external.mcp.settle"]
            let dependencyEntries = try strictOptionalJSONObjectArray(arguments, "dependencies") ?? []
            for entry in dependencyEntries {
                _ = try requiredString(entry, "dependency_id")
                _ = try requiredString(entry, "content_address")
                _ = try strictOptionalString(entry, "reason")
            }
            let reuseContract = try strictOptionalJSONObject(arguments, "reuse_contract")
            let declaredIdentity = try strictDeclaredSourceIdentity(from: arguments)
            let db = try openESISDatabase(databaseURL)
            let continuityID: String?
            if let clientIdentityID {
                guard try db.executionStateClientIdentityID(stateID) == clientIdentityID else {
                    throw MCPToolError.invalidArguments(
                        "execution \(stateID) is not owned by this MCP client identity")
                }
                continuityID = nil
            } else {
                let begunContinuityID = try db.executionStateContinuityID(stateID)
                if let requestedContinuityID, let begunContinuityID,
                   requestedContinuityID != begunContinuityID {
                    throw MCPToolError.invalidArguments(
                        "execution \(stateID) belongs to continuity \(begunContinuityID), not \(requestedContinuityID)")
                }
                if let requestedContinuityID, begunContinuityID == nil {
                    try db.bindExecutionStateContinuityID(requestedContinuityID, to: stateID)
                }
                continuityID = requestedContinuityID ?? begunContinuityID
            }

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
            let hasDeclaration = !declaredIdentity.isAbsent || operationKey != nil
            if !hasDeclaration, let settled = try db.latestSettlementID(forStateID: stateID) {
                throw MCPToolError.invalidArguments(
                    "execution \(stateID) already settled as \(settled); a state settles once")
            }

            guard demandID.isEmpty == retrievalID.isEmpty else {
                throw MCPToolError.invalidArguments(
                    "demand_id and retrieval_settlement_id must be supplied together")
            }
            if !retrievalID.isEmpty {
                if let clientIdentityID,
                   try db.settlementClientIdentityID(retrievalID) != clientIdentityID {
                    throw MCPToolError.invalidArguments(
                        "retrieval settlement is not owned by this MCP client identity")
                }
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
            for entry in dependencyEntries {
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
                    reason: (try strictOptionalString(entry, "reason")) ?? "declared"))
            }

            let effectiveParentStateID: String?
            if let parentStateID {
                effectiveParentStateID = parentStateID
            } else {
                effectiveParentStateID = try db.executionStateParentID(stateID)
            }
            if let effectiveParentStateID, let clientIdentityID {
                let parentOwner = try db.executionStateClientIdentityID(effectiveParentStateID)
                guard parentOwner == clientIdentityID else {
                    throw MCPToolError.invalidArguments(
                        "parent execution is not owned by this MCP client identity")
                }
            }

            let turn = try InformationLoop(database: db).settleTurn(
                generatedText: output,
                resolution: resolution,
                stateID: stateID,
                parentStateID: effectiveParentStateID,
                position: position,
                modelIdentity: model,
                identity: .init(model: model, tokenizer: tokenizer),
                sessionID: sessionID,
                clientIdentityID: clientIdentityID,
                summaryQuery: query,
                actions: actions,
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
                let query,
                sessionID != nil || continuityID != nil || clientIdentityID != nil
            {
                do {
                    publishedDemandID = try db.recordAnsweredDemand(
                        stateID: turn.stateID,
                        sessionID: sessionID ?? "client:\(clientIdentityID ?? continuityID ?? "")",
                        query: query,
                        settlementID: turn.settlementID,
                        actions: actions,
                        continuityID: continuityID,
                        clientIdentityID: clientIdentityID)
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
            if let terms = reuseContract {
                do {
                    reuseReply = Self.reuseContractReply(
                        try Self.declareReuseContract(
                            db, from: terms, settlementID: turn.settlementID,
                            defaultQuery: query))
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
                "client_identity_id": clientIdentityID ?? "",
                "continuity_id": continuityID ?? "",
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
            let executionID = try strictOptionalString(arguments, "execution_id") ?? stateID
            let phaseText = try strictOptionalString(arguments, "phase")
            let phase: ManagedRefusal.Phase
            if let phaseText {
                guard let parsed = ManagedRefusal.Phase(rawValue: phaseText) else {
                    throw MCPToolError.invalidArguments("phase is not a known refusal phase")
                }
                phase = parsed
            } else {
                phase = .g
            }
            let attempt = try strictOptionalInteger(arguments, "attempt") ?? 1
            let modelCalls = try strictOptionalInteger(arguments, "model_calls") ?? 0
            let settlementsWritten = try strictOptionalInteger(arguments, "settlements_written") ?? 0
            guard attempt >= 1, modelCalls >= 0, settlementsWritten >= 0 else {
                throw MCPToolError.invalidArguments(
                    "attempt must be positive and model_calls/settlements_written non-negative")
            }
            let rawEvidence = try strictOptionalJSONObject(arguments, "evidence") ?? [:]
            var evidence: [String: String] = [:]
            for (key, value) in rawEvidence {
                guard let text = value as? String else {
                    throw MCPToolError.invalidArguments(
                        "evidence values must be strings: \(key)")
                }
                evidence[key] = text
            }
            let db = try openESISDatabase(databaseURL)
            let auditClientIdentityID =
                clientIdentityID ?? ESISDatabase.ownerNamespace
            guard try db.executionStateClientIdentityID(stateID) == auditClientIdentityID else {
                throw MCPToolError.invalidArguments(
                    "execution is not owned by this client identity")
            }
            let audit = db.recordFailureAudit(.init(
                executionID: executionID,
                clientIdentityID: auditClientIdentityID,
                attempt: attempt,
                phase: phase,
                cause: nil,
                origin: .request,
                evidence: evidence,
                modelCalls: modelCalls,
                settlementsWritten: settlementsWritten,
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
            let kind = try strictOptionalString(arguments, "kind") ?? "brief"
            guard Self.readableProjectKinds.contains(kind) else {
                throw MCPToolError.invalidArguments(
                    "kind must be one of "
                        + Self.readableProjectKinds.sorted().joined(separator: ", "))
            }
            let requestedScope = try strictOptionalString(arguments, "scope")
            let requestedSessionID = try strictOptionalString(arguments, "session_id")
            let db = try openESISDatabase(databaseURL)
            let scope: String
            if let clientIdentityID {
                if let requestedScope, requestedScope != clientIdentityID {
                    throw MCPToolError.invalidArguments(
                        "MCP project-note scope is fixed to the authenticated client identity")
                }
                scope = clientIdentityID
            } else {
                var legacyScope = requestedScope?.lowercased() ?? ""
                if legacyScope.isEmpty, let session = requestedSessionID {
                    legacyScope = ESISDatabase.clientScope(ofSession: session) ?? ""
                }
                scope = legacyScope
            }
            if clientIdentityID == nil && scope == "all" {
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
            let noteKind = scope.isEmpty ? kind : ESISDatabase.scopedKind(kind, scope: scope)
            var note = try db.currentProjectNote(kind: noteKind)
            if note == nil, !scope.isEmpty, clientIdentityID == nil {
                note = try db.currentProjectNote(kind: kind)
            }
            var response: [String: Any] = [
                "kind": kind,
                "scope": scope.isEmpty ? "shared" : scope,
                // Count the exact scope being read; an empty client brief reports its own
                // empty history and never falls back to shared or another client's notes.
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
            // Brief and digest use the active ES/IS namespace: owner for built-in
            // calls, bearer digest for external MCP. Client display names are not identity.
            // This read only reports newer material and does not rewrite the judgement.
            //
            // 不限 kind（滚动摘要已在库层滤掉）。stale 与 newer_counts 是同一份
            // 数据的账面：有材料没被收进判断，这条判断就是过期的，而过期必须看得
            // 见——「多了个窗口」和「多了条裁定」不是一回事，后者意味着清单可能
            // 已失效，所以按 kind 分开计数，不揉成一个布尔。
            if kind == "brief", let note {
                let newer: [ESISDatabase.ProjectNote]
                if let clientIdentityID {
                    newer = try db.projectNotesNewerThan(
                        than: note.recordedAt, scope: clientIdentityID)
                } else {
                    newer = try db.projectNotesNewerThan(than: note.recordedAt)
                }
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
            // The consumer-contract addendum is app-local configuration, independent
            // of MCP client identity. Only the contract kind exposes this field.
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
            // In-process/built-in writes default to owner. Network MCP calls arrive
            // here with the digest of the validated bearer capability.
            let requestedScope = try strictOptionalString(arguments, "scope")
            let scope: String?
            if let clientIdentityID {
                if let requestedScope, requestedScope != clientIdentityID {
                    throw MCPToolError.invalidArguments(
                        "MCP project-note scope is fixed to the authenticated client identity")
                }
                scope = clientIdentityID
            } else {
                scope = requestedScope
            }
            let kind = ESISDatabase.scopedKind(
                try requiredString(arguments, "kind"),
                scope: scope)
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
            let boundary = try strictOptionalString(arguments, "boundary")
            let model = try strictOptionalString(arguments, "model")
            let declaredProvider = try strictOptionalString(arguments, "provider")
            let turnIndex = try strictOptionalInteger(arguments, "turn_index")
            if let turnIndex, turnIndex < 1 {
                throw MCPToolError.invalidArguments("turn_index must be a positive integer")
            }
            // A boundary is not a courtesy note: a round that states no limit
            // reads as if it had none. It travels with the reply under one
            // heading, and its absence is reported in the result instead of
            // being silently allowed.
            let storedText = ChatRoundText.compose(
                assistant: assistantText, boundary: boundary)
            let boundaryStated = ChatRoundText.statesBoundary(
                assistant: assistantText, boundary: boundary)
            // Provider is provenance metadata, not an owner or reuse credential.
            // mcpToolCall preserves a known provider from the unscoped session id
            // before it adds the opaque client-identity namespace.
            let provider: String
            if let declared = declaredProvider {
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
            if let turnIndex {
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
            let role = try strictOptionalString(arguments, "role") ?? "assistant"
            guard role == "user" || role == "assistant" else {
                throw MCPToolError.invalidArguments("role must be user or assistant")
            }
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
                let question = try Self.correctedTurnQuestion(
                    db: db, sessionID: sessionID, requestID: requestID)
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
        let declaredSettlementID = try strictOptionalString(terms, "settlement_id")
        let target = settlementID ?? declaredSettlementID ?? ""
        guard !target.isEmpty else {
            throw MCPToolError.invalidArguments("settlement_id is required")
        }
        let query = (try strictOptionalString(terms, "query")) ?? defaultQuery ?? ""
        guard !query.isEmpty else {
            throw MCPToolError.invalidArguments(
                "query is required: the canonical input basis is part of the declaration")
        }
        var identity: SettlementIdentityBinding.Identity?
        if let required = try strictOptionalJSONObject(terms, "required_consumer_identity") {
            let model = try requiredString(required, "model")
            let tokenizer = try requiredString(required, "tokenizer")
            // An unnamed engine is not a wildcard: a half-specified restriction
            // would read as "any consumer", the opposite of a restriction.
            identity = SettlementIdentityBinding.Identity(
                model: model, tokenizer: tokenizer)
        }
        return try db.declareSettlementReuseContract(
            settlementID: target,
            contractID: try requiredString(terms, "contract_id"),
            demandClass: try requiredString(terms, "demand_class"),
            contractVersion: try requiredString(terms, "contract_version"),
            query: query,
            rootIDs: try strictOptionalStringArray(terms, "root_ids"),
            extractField: (try strictOptionalString(terms, "extract_field"))
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

    private static func strictOptionalString(
        _ arguments: [String: Any], _ key: String
    ) throws -> String? {
        guard let raw = arguments[key] else { return nil }
        guard let value = raw as? String else {
            throw MCPToolError.invalidArguments("\(key) must be a string")
        }
        return value.isEmpty ? nil : value
    }

    private static func strictOptionalStringArray(
        _ arguments: [String: Any], _ key: String
    ) throws -> [String]? {
        guard let raw = arguments[key] else { return nil }
        guard let values = raw as? [Any] else {
            throw MCPToolError.invalidArguments("\(key) must be an array of strings")
        }
        var result: [String] = []
        result.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            guard let text = value as? String else {
                throw MCPToolError.invalidArguments(
                    "\(key)[\(index)] must be a string")
            }
            result.append(text)
        }
        return result
    }

    private static func strictOptionalBoolean(
        _ arguments: [String: Any], _ key: String
    ) throws -> Bool? {
        guard let raw = arguments[key] else { return nil }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw MCPToolError.invalidArguments("\(key) must be a boolean")
        }
        return number.boolValue
    }

    private static func strictOptionalInteger(
        _ arguments: [String: Any], _ key: String
    ) throws -> Int? {
        guard let raw = arguments[key] else { return nil }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw MCPToolError.invalidArguments("\(key) must be an integer")
        }
        if let exactInteger = Int(number.stringValue) {
            return exactInteger
        }
        var decimal = number.decimalValue
        var integral = Decimal()
        NSDecimalRound(&integral, &decimal, 0, .plain)
        guard integral == decimal,
              let value = Int(NSDecimalNumber(decimal: integral).stringValue) else {
            throw MCPToolError.invalidArguments("\(key) must be an integer")
        }
        return value
    }

    private static func strictOptionalJSONObject(
        _ arguments: [String: Any], _ key: String
    ) throws -> [String: Any]? {
        guard let raw = arguments[key] else { return nil }
        guard let object = raw as? [String: Any] else {
            throw MCPToolError.invalidArguments("\(key) must be an object")
        }
        return object
    }

    private static func strictOptionalJSONObjectArray(
        _ arguments: [String: Any], _ key: String
    ) throws -> [[String: Any]]? {
        guard let raw = arguments[key] else { return nil }
        guard let values = raw as? [Any] else {
            throw MCPToolError.invalidArguments("\(key) must be an array of objects")
        }
        var result: [[String: Any]] = []
        result.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            guard let object = value as? [String: Any] else {
                throw MCPToolError.invalidArguments(
                    "\(key)[\(index)] must be an object")
            }
            result.append(object)
        }
        return result
    }

    private static func strictDeclaredSourceIdentity(
        from arguments: [String: Any]
    ) throws -> ESISDatabase.DeclaredSourceIdentity {
        for key in ["source_type", "source_session_id", "source_turn_id", "source_message_id"] {
            if let raw = arguments[key] {
                guard let value = raw as? String,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPToolError.invalidArguments("\(key) must be a non-empty string")
                }
            }
        }
        let sourceType = try strictOptionalString(arguments, "source_type")
        let sourceSessionID = try strictOptionalString(arguments, "source_session_id")
        let sourceTurnID = try strictOptionalString(arguments, "source_turn_id")
        let sourceMessageID = try strictOptionalString(arguments, "source_message_id")
        let revision = try strictOptionalInteger(arguments, "source_revision")
        if let revision, revision < 1 {
            throw MCPToolError.invalidArguments("source_revision must be a positive integer")
        }
        return .init(
            sourceType: sourceType,
            sourceSessionID: sourceSessionID,
            sourceTurnID: sourceTurnID,
            sourceMessageID: sourceMessageID,
            sourceRevision: revision.map(String.init))
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

    /// One note's external view. Legacy direct callers may still request scope=all;
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
    /// MCP ownership itself is stored in client_identity_id, not inferred from provider names.
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
        let namespace = client.isEmpty ? ESISDatabase.ownerNamespace : client
        do {
            let db = try openESISDatabase(databaseURL)
            defer { db.close() }
            // Loopback API/MCP uses owner; LAN API/MCP supplies its verified
            // Client digest from HTTP ingress. Display names and session IDs never choose scope.
            func ownNote(_ kind: String) throws -> ESISDatabase.ProjectNote? {
                try db.currentProjectNote(
                    kind: ESISDatabase.scopedKind(kind, scope: namespace))
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
                let newer = try db.projectNotesNewerThan(
                    than: brief.recordedAt, scope: namespace)
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
        out += "\n本 SimiGo ES/IS 命名空间：\(namespace)。LAN 客户端身份由 HTTP 接入层的 "
            + "Authorization: Bearer 凭证决定；API 与 MCP 共用同一凭证和 client_id。"
            + "不要把凭证写入 initialize、tools/call、_meta 或工具参数；loopback 本机客户端固定使用 owner。\n"
        out += "brief 和 digest 统一存储在 `brief@\(namespace)` / `digest@\(namespace)`；"
            + "新身份不会继承其他客户端或共享区的简报。\n"
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

    static func openESISDatabase(_ url: URL) throws -> ESISDatabase {
        let db = try ESISDatabase(url: url, createIfNeeded: true)
        try db.runMigrations()
        return db
    }
}
