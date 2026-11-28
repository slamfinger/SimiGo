import Foundation
import CryptoKit
import LOCALBCore
import SimiGoRuntimeContract
import Network

/// SimiGo local management endpoints (database interface), moved verbatim
/// from HTTPServer.swift to keep the transport file navigable. Pure file
/// move; no logic changes.
extension HTTPServer {
    // MARK: - SimiGo local management endpoints (database interface)

    private func handleClientCredentialIssue(context: ConnectionContext) throws {
        guard Self.isLocalMCPEndpoint(context.connection.endpoint) else {
            throw HTTPServerError.clientTransportNotTrusted
        }
        let credential = try Self.issueClientCredential(databaseURL: ManagedPaths.databaseURL)
        sendJSON([
            "client_id": credential.digest,
            "token_type": "Bearer",
            "token": credential.token,
            "warning": "Store this token securely; it is shown only once."
        ], status: 201, on: context.connection, context: context)
    }

    private func handleClientCredentialRevocation(
        _ request: HTTPRequest, context: ConnectionContext
    ) throws {
        guard Self.isLocalMCPEndpoint(context.connection.endpoint) else {
            throw HTTPServerError.clientTransportNotTrusted
        }
        let body = try decodeJSONObject(request.body)
        guard let clientID = body["client_id"] as? String,
              clientID.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        else {
            throw HTTPServerError.badRequest("expected a 64-character client_id")
        }
        let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: false)
        defer { db.close() }
        let revoked = try db.revokeClientIdentity(clientID)
        sendJSON(["client_id": clientID, "revoked": revoked],
                 status: revoked ? 200 : 404,
                 on: context.connection, context: context)
    }

    /// GET/POST /v1/simigo/search?q=... — demand 驱动的信息检索：
    /// 已结算结果直接复用（reused=true），输入变化才重算并落新结算。
    private func handleSimigoSearchRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        do {
            let arguments = try Self.informationSearchArguments(
                body: request.body, requestTarget: request.requestTarget)
            let result = try Self.runInformationSearch(
                arguments: arguments, databaseURL: ManagedPaths.databaseURL,
                clientIdentityID: context.clientIdentityID ?? ESISDatabase.ownerNamespace)
            sendJSON(result, status: 200, on: context.connection, context: context)
        } catch let error as MCPToolError {
            if case .invalidArguments = error {
                sendJSON(
                    ["error": "INVALID_REQUEST", "detail": String(describing: error)],
                    status: 400, on: context.connection, context: context)
            } else {
                sendJSON(
                    ["error": "SEARCH_FAILED", "detail": String(describing: error)],
                    status: 500, on: context.connection, context: context)
            }
        } catch {
            sendJSON(
                ["error": "SEARCH_FAILED", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }
    struct SimigoDatabaseStatus: Equatable {
        let exists: Bool
        let available: Bool
        let schemaVersion: Int?
        let roots: [String]
        let error: String?
    }

    /// Keep filesystem existence separate from SQLite readability. A corrupt or
    /// partially migrated database is present but unavailable, never "missing".
    static func simigoDatabaseStatus(at url: URL) -> SimigoDatabaseStatus {
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard exists else {
            return SimigoDatabaseStatus(
                exists: false, available: false, schemaVersion: nil,
                roots: [], error: nil)
        }

        var schemaVersion: Int?
        do {
            let database = try ESISDatabase(url: url, createIfNeeded: false, readOnly: true)
            schemaVersion = try database.schemaVersion()
            let roots = try database.listRoots().map(\.rootID)
            return SimigoDatabaseStatus(
                exists: true, available: true, schemaVersion: schemaVersion,
                roots: roots, error: nil)
        } catch {
            return SimigoDatabaseStatus(
                exists: true, available: false, schemaVersion: schemaVersion,
                roots: [], error: String(describing: error))
        }
    }

    /// Read registered roots without converting SQLite failures into an empty
    /// successful registry. The caller owns the HTTP error mapping.
    static func simigoRegisteredRoots(at url: URL) throws -> [ESISDatabase.RootRow] {
        let database = try ESISDatabase(url: url, createIfNeeded: false, readOnly: true)
        return try database.listRoots()
    }

    /// GET /v1/simigo/brief — direct non-MCP Brief access for Agents.
    /// The default response is a bounded section index; section/query fetches
    /// return exact stored text and its note identity.
    private func handleSimigoBriefRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        do {
            guard let components = URLComponents(
                string: "http://simigo.local" + request.requestTarget) else {
                throw MCPToolError.invalidArguments("invalid request target")
            }
            let items = components.queryItems ?? []
            func single(_ name: String) throws -> String? {
                let matches = items.filter { $0.name == name }
                guard matches.count <= 1 else {
                    throw MCPToolError.invalidArguments("\(name) may appear only once")
                }
                guard let item = matches.first else { return nil }
                guard let value = item.value, !value.isEmpty else {
                    throw MCPToolError.invalidArguments("\(name) must have a value")
                }
                return value
            }
            let section = try single("section")
            let query = try single("query")
            guard section == nil || query == nil else {
                throw MCPToolError.invalidArguments("pass either section or query, not both")
            }
            func briefISOStamp(_ stored: String) -> String {
                guard let seconds = Double(stored) else { return stored }
                return ISO8601DateFormatter().string(
                    from: Date(timeIntervalSinceReferenceDate: seconds))
            }
            let scope = context.clientIdentityID ?? ESISDatabase.ownerNamespace
            let db = try Self.openESISDatabase(ManagedPaths.databaseURL)
            defer { db.close() }
            let kind = ESISDatabase.scopedKind("brief", scope: scope)
            guard let note = try db.currentProjectNote(kind: kind), !note.claim.isEmpty else {
                sendJSON([
                    "error": "BRIEF_NOT_FOUND",
                    "scope": scope,
                    "kind": "brief",
                ], status: 404, on: context.connection, context: context)
                return
            }
            let allSections = Self.parseBriefSections(note.claim)
            let selected: [HTTPServer.BriefSection]
            if let section {
                selected = try Self.selectBriefSections(section, sections: allSections)
            } else if let query {
                selected = Self.briefSections(matching: query, in: note.claim, sections: allSections)
                guard !selected.isEmpty else {
                    throw MCPToolError.invalidArguments("query matched no brief section")
                }
            } else {
                selected = allSections
            }
            let exactRead = section != nil || query != nil
            var sections: [[String: Any]] = []
            var indexChars = 0
            var indexTruncated = false
            for item in selected {
                let body = String(note.claim[item.textRange])
                var value: [String: Any] = [
                    "ordinal": item.ordinal,
                    "label": item.label,
                    "title": item.title,
                    "chars": body.count,
                ]
                if exactRead {
                    value["text"] = body
                } else {
                    value["first_line"] = item.firstLine
                    let cost = item.label.count + item.title.count + item.firstLine.count
                    if sections.count >= 200 || indexChars + cost > 22_000 {
                        indexTruncated = true
                        break
                    }
                    indexChars += cost
                }
                sections.append(value)
            }
            sendJSON([
                "kind": "brief",
                "scope": scope,
                "note_id": note.noteID,
                "recorded_at": note.recordedAt,
                "recorded_at_iso": briefISOStamp(note.recordedAt),
                "brief_chars": note.claim.count,
                "read_mode": exactRead ? "exact_sections" : "section_index",
                "index_truncated": !exactRead && indexTruncated,
                "sections": sections,
                "fetch_hint": "GET /v1/simigo/brief?section=<section-number>",
            ], status: 200, on: context.connection, context: context)
        } catch let error as MCPToolError {
            sendJSON([
                "error": "INVALID_REQUEST",
                "detail": String(describing: error),
            ], status: 400, on: context.connection, context: context)
        } catch {
            sendJSON([
                "error": "BRIEF_READ_FAILED",
                "detail": String(describing: error),
            ], status: 500, on: context.connection, context: context)
        }
    }

    /// GET /v1/simigo/env — generation-environment status: managed root,
    /// llama-server, hf, database, registered roots, LOCALB resolution.
    /// Read-only; every field is derived from the managed root at call time.
    private func handleSimigoEnvRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        let fm = FileManager.default
        let root = ManagedPaths.managedRoot()
        let llama = EnvManager.findTool("llama-server")
            ?? (fm.isExecutableFile(atPath: ManagedPaths.bin.appendingPathComponent("llama-server").path)
                ? ManagedPaths.bin.appendingPathComponent("llama-server").path : nil)
        let hf = EnvManager.findTool("hf")
            ?? (fm.isExecutableFile(atPath: ManagedPaths.bin.appendingPathComponent("hf").path)
                ? ManagedPaths.bin.appendingPathComponent("hf").path : nil)
        let databaseStatus = Self.simigoDatabaseStatus(at: ManagedPaths.databaseURL)
        var db: [String: Any] = [
            "path": ManagedPaths.databaseURL.path,
            "exists": databaseStatus.exists,
            "available": databaseStatus.available,
            "roots": databaseStatus.roots,
        ]
        if let version = databaseStatus.schemaVersion {
            db["schema_version"] = version
        }
        if let error = databaseStatus.error {
            db["error"] = error
        }
        let localb: String
        switch try? LOCALBHostRuntime.resolveOperational(
            hostDirectory: LOCALBHostRuntime.defaultHostDirectory()
        ) {
        case .operational: localb = "operational"
        case .notInitialized: localb = "not_initialized"
        default: localb = "unresolvable"
        }
        sendJSON(
            [
                "managed_root": root.path,
                "llama_server": llama ?? NSNull(),
                "hf": hf ?? NSNull(),
                "database": db,
                "localb": localb,
                // 引擎身份账本的最新一行。挂既有路由、既有权限位
                // （`.informationRead`）：账本是读数，不是新的写入面（spec §4）。
                "engine_ledger": EngineIdentityLedger.latestRow() ?? NSNull(),
            ],
            status: 200,
            on: context.connection,
            context: context
        )
    }

    /// GET /v1/simigo/roots — list registered external roots.
    private func handleSimigoRootsRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        do {
            let rows = try Self.simigoRegisteredRoots(at: ManagedPaths.databaseURL)
            sendJSON(
                ["roots": rows.map { [
                    "root_id": $0.rootID,
                    "category": $0.category,
                    "display_name": $0.displayName,
                    "locator_type": $0.locatorType,
                    "status": $0.status,
                ] }],
                status: 200,
                on: context.connection,
                context: context
            )
        } catch {
            sendJSON(
                ["error": "DATABASE_READ_FAILED", "detail": String(describing: error)],
                status: 503,
                on: context.connection,
                context: context
            )
        }
    }

    /// GET /v1/simigo/is/status[?deep=1] — physical Information-Space carrier
    /// health: object store size, append-only index/dependency history, rows not
    /// yet addressed to an object, dangling references, and (with `deep=1`)
    /// per-object hash verification. Read-only and fail-closed: a database that
    /// cannot be read returns 503 instead of a healthy-looking empty report.
    private func handleSimigoCarrierStatusRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        do {
            let arguments = try Self.informationStatusArguments(
                requestTarget: request.requestTarget)
            let result = try Self.runInformationStatus(
                arguments: arguments, databaseURL: ManagedPaths.databaseURL)
            sendJSON(result, status: 200, on: context.connection, context: context)
        } catch let error as MCPToolError {
            if case .invalidArguments = error {
                sendJSON(
                    ["error": "INVALID_REQUEST", "detail": String(describing: error)],
                    status: 400, on: context.connection, context: context)
            } else {
                sendJSON(
                    ["error": "CARRIER_UNREADABLE", "detail": String(describing: error)],
                    status: 503, on: context.connection, context: context)
            }
        } catch {
            sendJSON(
                ["error": "CARRIER_UNREADABLE", "detail": String(describing: error)],
                status: 503, on: context.connection, context: context)
        }
    }
    /// SQLite execution faults are 500, an unusable store 503, content-verification failures 409.
    private func simigoReadFailure(
        _ error: Error, contentCode: String, readCode: String
    ) -> (status: Int, body: [String: Any]) {
        if let dbError = error as? ESISDatabase.DatabaseError {
            switch dbError {
            case .executionFailure:
                return (500, ["error": readCode, "detail": "\(error)"])
            case .cannotOpen, .notADatabase:
                return (503, ["error": "DATABASE_UNAVAILABLE", "detail": "\(error)"])
            default:
                return (409, ["error": contentCode, "detail": "\(error)"])
            }
        }
        return (500, ["error": readCode, "detail": "\(error)"])
    }

    private func simigoQueryItem(_ request: HTTPRequest, _ name: String) -> String? {
        guard let url = URL(string: "http://x" + request.requestTarget),
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems
        else { return nil }
        return items.first(where: { $0.name == name })?.value
    }

    private func simigoOptionalJSON(_ value: String?) -> Any {
        value ?? NSNull()
    }

    /// Text when the bytes are UTF-8, base64 otherwise — never lossy.
    private func simigoPayloadFields(_ data: Data) -> [String: Any] {
        let size = data.count
        if let text = String(data: data, encoding: .utf8) {
            return ["encoding": "utf8", "payload": text, "payload_size": size]
        }
        return [
            "encoding": "base64", "payload": data.base64EncodedString(),
            "payload_size": size,
        ]
    }

    private func simigoDependencyJSON(
        _ entry: ESISDatabase.DependencyEntry
    ) -> [String: Any] {
        [
            "dependency_id": entry.dependencyID,
            "content_address": entry.contentAddress,
            "revision": entry.revision,
            "reason": entry.reason,
            "recorded_at": entry.recordedAt,
            "append_order": entry.appendOrder,
        ]
    }

    /// GET /v1/simigo/is/settlement?id=... — read a settled result back with its
    /// verified payload, producer bindings, validity, and dependency revisions.
    private func handleSimigoSettlementRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let id = simigoQueryItem(request, "id"), !id.isEmpty else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected id=<settlement_id>"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? ESISDatabase(
            url: ManagedPaths.databaseURL, createIfNeeded: false, readOnly: true)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            guard let receipt = try db.settlementReceipt(id) else {
                sendJSON(
                    ["error": "SETTLEMENT_NOT_FOUND", "detail": id],
                    status: 404, on: context.connection, context: context)
                return
            }
            let requestedClientID = context.clientIdentityID ?? ESISDatabase.ownerNamespace
            let storedClientID = try db.settlementClientIdentityID(id)
            guard Self.settlementIsVisible(
                to: requestedClientID, storedClientIdentityID: storedClientID,
                settlementExists: try db.settlementRecordExists(id))
            else {
                sendJSON(["error": "SETTLEMENT_NOT_FOUND", "detail": id],
                         status: 404, on: context.connection, context: context)
                return
            }
            var body: [String: Any] = [
                "settlement_id": receipt.settlementID,
                "state_id": simigoOptionalJSON(receipt.stateID),
                "payload_object_id": simigoOptionalJSON(receipt.payloadObjectID),
                "payload_sha256": receipt.payloadSHA256,
                "schema_version": simigoOptionalJSON(receipt.schemaVersion),
                "contract_version": simigoOptionalJSON(receipt.contractVersion),
                "settled_at": simigoOptionalJSON(receipt.settledAt),
                "validation_status": simigoOptionalJSON(receipt.validationStatus),
                "validity": receipt.validity,
                "invalidated_at": simigoOptionalJSON(receipt.invalidatedAt),
                "bindings": receipt.bindings,
                "dependencies": receipt.dependencies.map(simigoDependencyJSON),
                "risk_notices": receipt.riskNotices.map { notice -> [String: Any] in
                    [
                        "code": notice.code,
                        "settlement_id": notice.settlementID,
                        "detail": notice.detail,
                    ]
                },
            ]
            body.merge(simigoPayloadFields(receipt.payload)) { _, new in new }
            sendJSON(body, status: 200, on: context.connection, context: context)
        } catch {
            let failure = simigoReadFailure(
                error, contentCode: "SETTLEMENT_PAYLOAD_UNVERIFIED",
                readCode: "SETTLEMENT_READ_FAILED")
            sendJSON(
                failure.body, status: failure.status,
                on: context.connection, context: context)
        }
    }

    /// GET /v1/simigo/is/dependency?id=... — current revision plus full history.
    private func handleSimigoDependencyRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let id = simigoQueryItem(request, "id"), !id.isEmpty else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected id=<dependency_id>"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? ESISDatabase(
            url: ManagedPaths.databaseURL, createIfNeeded: false, readOnly: true)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            let history = try db.dependencyHistory(id)
            guard let current = history.last else {
                sendJSON(
                    ["error": "DEPENDENCY_NOT_FOUND", "detail": id],
                    status: 404, on: context.connection, context: context)
                return
            }
            sendJSON(
                [
                    "dependency_id": id,
                    "current": simigoDependencyJSON(current),
                    "history": history.map(simigoDependencyJSON),
                ],
                status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "DEPENDENCY_READ_FAILED", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    /// GET /v1/simigo/is/file?root_id=...&path=... — settled file content,
    /// read back through its content address.
    private func handleSimigoFileRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let rootID = simigoQueryItem(request, "root_id"), !rootID.isEmpty,
            let path = simigoQueryItem(request, "path"), !path.isEmpty
        else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected root_id=<id>&path=<relative>"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? ESISDatabase(
            url: ManagedPaths.databaseURL, createIfNeeded: false, readOnly: true)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            guard let content = try db.carriedFileContent(
                rootID: rootID, relativePath: path)
            else {
                sendJSON(
                    ["error": "FILE_NOT_SETTLED", "detail": "\(rootID)/\(path)"],
                    status: 404, on: context.connection, context: context)
                return
            }
            var body: [String: Any] = [
                "root_id": content.rootID,
                "path": content.relativePath,
                "content_sha256": content.contentSHA256,
                "object_id": simigoOptionalJSON(content.objectID),
                "settled_at": content.settledAt,
                "status": simigoOptionalJSON(content.status),
            ]
            body.merge(simigoPayloadFields(content.content)) { _, new in new }
            sendJSON(body, status: 200, on: context.connection, context: context)
        } catch {
            let failure = simigoReadFailure(
                error, contentCode: "FILE_CONTENT_UNVERIFIED",
                readCode: "FILE_READ_FAILED")
            sendJSON(
                failure.body, status: failure.status,
                on: context.connection, context: context)
        }
    }

    /// GET /v1/simigo/is/object?id=... — verify and return one stored object.
    private func handleSimigoObjectRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let id = simigoQueryItem(request, "id"), !id.isEmpty else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected id=<sha256>"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? ESISDatabase(
            url: ManagedPaths.databaseURL, createIfNeeded: false, readOnly: true)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            guard let row = try db.objectRow(id) else {
                sendJSON(
                    ["error": "OBJECT_NOT_FOUND", "detail": id],
                    status: 404, on: context.connection, context: context)
                return
            }
            guard try db.verifyObject(id) else {
                sendJSON(
                    ["error": "OBJECT_CORRUPT", "detail": id],
                    status: 409, on: context.connection, context: context)
                return
            }
            var body: [String: Any] = [
                "object_id": row.objectID,
                "created_order": row.createdOrder,
                "verified": true,
            ]
            body.merge(simigoPayloadFields(row.content)) { _, new in new }
            sendJSON(body, status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "OBJECT_READ_FAILED", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    /// POST /v1/simigo/is/declare-reuse — declare the reuse terms of one settled
    /// result, so it becomes consumable verbatim. Body:
    /// `{"settlement_id": "...", "contract_id": "...", "demand_class": "...",
    /// "contract_version": "...", "query": "...", "root_ids": [...],
    /// "extract_field": "content", "required_consumer_identity": {"model": "...",
    /// "tokenizer": "..."}}`. Runs the SAME library call as the MCP tool
    /// `simigo_is_declare_reuse` (`Self.declareReuseContract`), so there is no
    /// second declaration authority. A missing term, an unknown settlement or a
    /// changed re-declaration is a 400 with the refusal in `detail` — never a
    /// silent success, and never a declaration the product made by itself.
    private func handleSimigoDeclareReuseRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard !request.body.isEmpty,
            let terms = try? JSONSerialization.jsonObject(with: request.body)
                as? [String: Any]
        else {
            sendJSON(
                ["error": "INVALID_BODY",
                 "detail": "a JSON object of reuse terms is required"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? ESISDatabase(
            url: ManagedPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            if let settlementID = terms["settlement_id"] as? String {
                let requestedClientID = context.clientIdentityID ?? ESISDatabase.ownerNamespace
                let storedClientID = try db.settlementClientIdentityID(settlementID)
                guard Self.settlementIsVisible(
                    to: requestedClientID, storedClientIdentityID: storedClientID,
                    settlementExists: try db.settlementRecordExists(settlementID))
                else {
                    sendJSON(["error": "REUSE_DECLARATION_REFUSED",
                              "detail": "settlement is not in this Client namespace"],
                             status: 404, on: context.connection, context: context)
                    return
                }
            }
            sendJSON(
                Self.reuseContractReply(
                    try Self.declareReuseContract(db, from: terms)),
                status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "REUSE_DECLARATION_REFUSED", "detail": "\(error)"],
                status: 400, on: context.connection, context: context)
        }
    }

    /// POST /v1/simigo/is/reconcile — re-derive validity for registered roots.
    /// Body is optional: {"category": "work", "max_age_seconds": 0}.
    private func handleSimigoReconcileRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        var category = "work"
        var maxAge: Double = 0
        if !request.body.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: request.body)
                as? [String: Any]
        {
            if let value = object["category"] as? String, !value.isEmpty {
                category = value
            }
            if let value = object["max_age_seconds"] as? Double, value > 0 {
                maxAge = value
            }
        }
        guard let db = try? ESISDatabase(
            url: ManagedPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            let result = try db.reconcileRegisteredRoots(
                category: category, minAgeSeconds: maxAge)
            sendJSON(
                [
                    "category": category,
                    "root_count": result.rootCount,
                    "settled_roots": result.settledRoots,
                    "fresh_roots": result.freshRoots,
                    "missing_roots": result.missingRoots,
                    "unlocatable_roots": result.unlocatableRoots,
                    "failed_roots": result.failedRoots,
                    "scanned": result.scanned,
                    "reused": result.reused,
                    "changed": result.changed,
                    "removed": result.removed,
                    "invalidated_settlements": result.invalidatedSettlements,
                ],
                status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "RECONCILE_FAILED", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    /// PUT/POST /v1/simigo/roots {"path": "/abs/work/dir"} — register (or
    /// refresh) a work root in the authoritative database. Absolute paths
    /// only; the directory must exist. Idempotent.
    private func handleSimigoRootsPutRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        let body = request.body
        guard !body.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let rawPath = object["path"] as? String,
            !rawPath.isEmpty, rawPath.hasPrefix("/")
        else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected a JSON body like {\"path\": \"/absolute/dir\"}"],
                status: 400, on: context.connection, context: context)
            return
        }
        let standardized = (rawPath as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir),
            isDir.boolValue
        else {
            sendJSON(
                ["error": "WORK_ROOT_NOT_FOUND", "detail": standardized],
                status: 422, on: context.connection, context: context)
            return
        }
        do {
            let db = try ESISDatabase(url: ManagedPaths.databaseURL, createIfNeeded: true)
            try db.runMigrations()
            let rootID = "work-" + EnvManager.stableRootID(forPath: standardized)
            try db.upsertRoot(
                rootID: rootID, category: "work", displayName: standardized,
                locatorType: "path", status: "registered")
            let settle = try db.settleWorkRootContents(
                rootID: rootID, rootURL: URL(fileURLWithPath: standardized),
                carryText: false)
            sendJSON(
                [
                    "root_id": rootID, "path": standardized, "registered": true,
                    "content_settle": [
                        "scanned": settle.scanned, "reused": settle.reused,
                        "settled": settle.settled, "skipped": settle.skippedBinaryOrLarge,
                        "changed": settle.changed, "removed": settle.removed,
                        "invalidated_settlements": settle.invalidatedSettlements,
                        "objects_created": settle.objectsCreated,
                        "deduplicated": settle.deduplicated,
                    ],
                ],
                status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "DATABASE_ERROR", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    private func handleLOCALBChallengeRequest(
        _ request: HTTPRequest,
        context: ConnectionContext
    ) async throws {
        guard context.transportSecurity.eligibleForLOCALBPairingBinding else {
            throw HTTPServerError.localbTransportNotTrusted
        }
        guard let authorization = localbRequestAuthorization else {
            throw HTTPServerError.localbAuthorizationUnavailable
        }
        guard let clientKeyID = request.headers["x-simigo-localb-client-key-id"]
        else {
            throw HTTPServerError.badRequest("Missing LOCALB client key id")
        }
        guard let body = try? JSONSerialization.jsonObject(with: request.body)
            as? [String: Any],
            let method = body["method"] as? String,
            let target = body["requestTarget"] as? String
        else {
            throw HTTPServerError.badRequest("Malformed challenge request body")
        }
        guard HTTPRequestHeadParser.isCanonicalMethodToken(method),
              target.hasPrefix("/"),
              !target.contains("#"),
              target.utf8.count <= HTTPRequestHeadParser.maxTargetBytes
        else {
            throw HTTPServerError.badRequest("Non-canonical challenge request")
        }
        let routePath = String(
            target.split(
                separator: "?",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first ?? ""
        )
        let routePolicy = Self.localbRoutePolicy(
            forMethod: method,
            routePath: routePath
        )
        guard case .protected(let permission) = routePolicy else {
            // Open routes are not protected (no challenge to issue);
            // denied routes — including branch operations — are refused
            // with an explicit denial, never a fallback to open access.
            if case .denied(let reason) = routePolicy {
                throw HTTPServerError.localbRouteDenied(reason: reason)
            }
            throw HTTPServerError.badRequest(
                "No protected route for the given method and target"
            )
        }
        let challenge: [UInt8]
        do {
            // Issuance performs the same registry validation as
            // authorization (unknown/revoked/under-privileged clients are
            // refused before consuming ledger capacity) plus per-client
            // pending and rate limits.
            challenge = try authorization.coordinator.issueRequestChallenge(
                clientKeyID: clientKeyID,
                permission: permission,
                checkpoint: try authorization.trustedCheckpoint()
            )
        } catch let status as LOCALBStatus {
            throw HTTPServerError.badRequest(status.rawValue)
        }
        sendJSON(
            [
                "challenge": Self.encodeLowerHex(challenge),
                "permission": permission.rawValue
            ],
            status: 200,
            on: context.connection,
            context: context
        )
    }

    /// One `/v1/models` entry. The list and the single-model route share it so
    /// a client sees the same window wherever it looks; `context_length` is the
    /// OpenAI-compatible alias of the effective (gate-admitted) window.
    private func modelEntryDocument() -> [String: Any] {
        var entry: [String: Any] = [
            "id": modelId,
            "object": "model",
            "created": Int(Date().timeIntervalSince1970),
            "owned_by": "simigo",
        ]
        // P1-1 能力契约：声明 + 实测 + 配置约束的三态透出
        //（未实测保持 unverified，不以无证据推断）。
        if let caps = capabilitiesProvider?(),
           let data = try? JSONEncoder().encode(caps),
           let obj = try? JSONSerialization.jsonObject(with: data)
               as? [String: Any] {
            for key in ["backend", "architecture", "contextLength",
                        "effectiveContextLength", "capabilities", "runtime",
                        "protocolEndpoints"] {
                if let value = obj[key] { entry[key] = value }
            }
            if let window = obj["effectiveContextLength"] as? Int
                ?? obj["contextLength"] as? Int {
                entry["context_length"] = window
            }
        }
        return entry
    }

    /// Bootstrap metadata served as the top-level `simigo` object of
    /// `/v1/models` (#149).
    ///
    /// This is a discovery declaration, not a second authority: nothing here
    /// is read from ES/IS, and no counter from it may be cited as one. It
    /// deliberately contains no filesystem paths, database location, process
    /// ids or calibration constants — only the public surface an agent needs
    /// to know that this endpoint is SimiGo, what it can retain, and how to
    /// declare a request's scope. `runtime_status` carries its observation
    /// time so a caller cannot mistake a stale probe for a live one.
    static func simigoBootstrapDocument(
        health: Bool,
        observedAt: Date,
        authorities: RuntimeAuthorityStatus = RuntimeAuthorityStatus()
    ) -> [String: Any] {
        let capabilities: [String: Any] = [
            "es": ["state": "supported"] as [String: Any],
            "is": [
                "state": "supported",
                "search": ["methods": ["GET", "POST"], "path": "/v1/simigo/search"] as [String: Any],
                "mcp": ["method": "POST", "path": "/mcp"] as [String: Any],
            ] as [String: Any],
            "memory_kv_cache": ["state": "supported"] as [String: Any],
            // The continuation surface is the same routes everywhere, so the
            // difference between backends has to be stated, not discovered by a
            // failed call. Values come from the handlers this server was built
            // with; a backend that exports no KV representation says so.
            "execution_continuation": [
                "admission": ["state": authorities.continuationAdmission.rawValue],
                "settlement": ["state": authorities.continuationSettlement.rawValue],
                "kv_representation": ["state": authorities.kvRepresentation.rawValue],
                "settlement_consumption": [
                    "state": authorities.settlementConsumption.rawValue,
                ],
                "managed_continuation": [
                    "state": authorities.managedContinuation.rawValue,
                ],
            ] as [String: Any],
            "external_api_intake": [
                "state": "supported",
                "channels": ["mcp_settle"],
            ] as [String: Any],
        ]
        let requestScopes: [String: Any] = [
            "declaration": [
                "json_keys": [
                    "metadata.simigo_request_scope",
                    "client_metadata.simigo_request_scope",
                ],
                "headers": ["X-SimiGo-Request-Scope"],
                "internal_values": ["internal", "internal_operation", "internal-op"],
                "default": "ordinary",
            ] as [String: Any],
            "surfaces": [
                [
                    "path": "/v1/chat/completions",
                    "managed": true,
                    "identifiers": ["session_id", "conversation_id"],
                    "fallback": "message_prefix_digest",
                ] as [String: Any],
                [
                    "path": "/v1/responses",
                    "managed": true,
                    "identifiers": ["session_id", "thread_id", "previous_response_id"],
                    "fallback": "message_prefix_digest",
                ] as [String: Any],
                [
                    "path": "/v1/completions",
                    "managed": false,
                    "reason": "legacy_text_completions",
                ] as [String: Any],
            ],
        ]
        let carrier: [String: Any] = [
            "kv_cache": [
                "mode": "memory",
                "disk_persistence":
                    RuntimeTuning.prefixPoolEnabled
                    || RuntimeTuning.branchCheckpointsEnabled,
            ] as [String: Any],
            "information_space": [
                "mode": "content_addressed_object_store",
                "durability": "disk",
            ] as [String: String],
        ]
        return [
            "schema_version": 1,
            "capabilities": capabilities,
            "request_scopes": requestScopes,
            "carrier": carrier,
            "runtime_status": [
                "health": health ? "ok" : "unavailable",
                "observed_at": ISO8601DateFormatter().string(from: observedAt),
            ],
        ]
    }

    func route(
        _ request: HTTPRequest,
        context: ConnectionContext
    ) async throws {
        // LOCALB B3 gate: protected routes are dispatched ONLY after proof
        // verification, and only the verified request object (routePath for
        // routing, bodyRaw for the body, allowlisted headers) reaches the
        // switch below. Denied routes are refused here — before any handler
        // and regardless of proof material — and open routes are exactly
        // the enumerated set in localbRoutePolicy, so no route can bypass
        // this gate by being absent from the table.
        // CORS preflight is itself an explicitly open OPTIONS route in the
        // LOCALB policy table. Browsers must send Origin on that request, so
        // do not apply the ordinary cross-origin API rejection to preflight.
        // The actual follow-up request still passes this guard and the full
        // route-specific LOCALB proof gate below.
        guard request.method == "OPTIONS" || !Self.hasBrowserOriginHeader(request.headers) else {
            throw HTTPServerError.localbRouteDenied(
                reason: "SIMGIO_CROSS_ORIGIN_REQUEST_DENIED")
        }
        var request = request
        // Establish the shared API/MCP Client identity before LOCALB rebuilds
        // the signed request from its allowlisted headers. LOCALB remains a
        // separate request-permission check and never selects client_id.
        if Self.requiresClientIdentity(method: request.method, routePath: request.path) {
            let clientID = try Self.resolveHTTPClientIdentity(
                authorizationHeader: request.headers["authorization"],
                isLoopbackPeer: Self.isLocalMCPEndpoint(context.connection.endpoint),
                isTLS: context.transportSecurity.isTLS,
                databaseURL: ManagedPaths.databaseURL)
            context.bindClientIdentity(clientID)
        }
        if context.clientIdentityID != nil,
           context.clientIdentityID != ESISDatabase.ownerNamespace,
           Self.isOwnerOnlyInformationRoute(method: request.method, path: request.path) {
            throw HTTPServerError.localbRouteDenied(
                reason: "SIMGIO_ROUTE_REQUIRES_OWNER_IDENTITY")
        }
        // Owner ruling 2026-10-26: the PLAINTEXT loopback listener is the
        // product's local developer/tool surface — protected routes are
        // served on it without the LOCALB proof ceremony (responses carry
        // "unprotected-by-LOCALB"). The TLS listener keeps the full B3
        // proof gate unchanged.
        // Owner ruling 2026-11-05 (S2): the exemption is now an explicit
        // allowlist (localbPlaintextLoopbackPermissions). Permissions off
        // the allowlist — P-BRANCH-CONTROL first — fall through to the
        // full proof ceremony even on plaintext loopback.
        let plaintextLoopback =
            !context.transportSecurity.isTLS
        switch Self.localbRoutePolicy(
            forMethod: request.method,
            routePath: request.path
        ) {
        case .open:
            break
        case .protected(let permission):
            if plaintextLoopback,
               Self.localbPlaintextLoopbackPermissions.contains(permission) {
                break
            }
            request = try verifyLOCALBProtectedRequest(
                request,
                tablePermission: permission,
                context: context
            )
        case .denied(let reason):
            throw HTTPServerError.localbRouteDenied(reason: reason)
        }

        switch (request.method, request.path) {

        case ("OPTIONS", _):
            _ = sendResponse(
                status: 204,
                headers: corsHeaders(
                    extra: [
                        "Content-Length": "0"
                    ]
                ),
                body: Data(),
                on: context.connection,
                context: context,
                close: true
            )

        case ("POST", "/localb/auth/challenge"):
            try await handleLOCALBChallengeRequest(
                request,
                context: context
            )

        case ("POST", "/v1/simigo/clients"):
            try handleClientCredentialIssue(context: context)

        case ("POST", "/v1/simigo/clients/revoke"):
            try handleClientCredentialRevocation(request, context: context)

        case ("GET", "/v1/simigo/search"),
             ("POST", "/v1/simigo/search"):
            try await handleSimigoSearchRequest(request, context: context)

        case ("GET", "/v1/simigo/brief"):
            try await handleSimigoBriefRequest(request, context: context)

        case ("GET", "/v1/simigo/env"):
            try await handleSimigoEnvRequest(request, context: context)

        case ("GET", "/v1/simigo/roots"):
            try await handleSimigoRootsRequest(request, context: context)

        case ("GET", "/v1/simigo/is/status"):
            try await handleSimigoCarrierStatusRequest(request, context: context)

        case ("GET", "/v1/simigo/is/settlement"):
            try await handleSimigoSettlementRequest(request, context: context)

        case ("GET", "/v1/simigo/is/dependency"):
            try await handleSimigoDependencyRequest(request, context: context)

        case ("GET", "/v1/simigo/is/file"):
            try await handleSimigoFileRequest(request, context: context)

        case ("GET", "/v1/simigo/is/object"):
            try await handleSimigoObjectRequest(request, context: context)

        case ("POST", "/v1/simigo/is/reconcile"):
            try await handleSimigoReconcileRequest(request, context: context)

        case ("POST", "/v1/simigo/is/declare-reuse"):
            try await handleSimigoDeclareReuseRequest(request, context: context)

        case ("POST", "/mcp"), ("GET", "/mcp"):
            await handleMCPRequest(request, context: context)

        case ("PUT", "/v1/simigo/roots"), ("POST", "/v1/simigo/roots"):
            try await handleSimigoRootsPutRequest(request, context: context)

        case ("GET", "/health"):
            let ok =
                await checkHealthHandler()

            sendJSON(
                [
                    "status": ok ? "ok" : "unavailable",
                    "model": modelId
                ],
                status: ok ? 200 : 503,
                on: context.connection,
                context: context
            )

        case ("HEAD", "/health"):
            let ok =
                await checkHealthHandler()

            let response: [String: Any] = [
                "status": ok ? "ok" : "unavailable",
                "model": modelId
            ]

            let body =
                (try? JSONSerialization.data(
                    withJSONObject: response
                )) ?? Data()

            _ = sendResponse(
                status: ok ? 200 : 503,
                headers: corsHeaders(
                    extra: [
                        "Content-Type":
                            "application/json; charset=utf-8",
                        "Content-Length":
                            "\(body.count)"
                    ]
                ),
                body: Data(),
                on: context.connection,
                context: context,
                close: true
            )

        case ("GET", "/v1/models"),
             ("GET", "/models"):

            let entry = modelEntryDocument()
            let additionalEntries = additionalModelEntriesProvider().filter {
                ($0["id"] as? String) != modelId
            }

            // Discovery only (#149): what this endpoint serves and how a
            // request declares its scope. Built from static declarations plus
            // a liveness probe — it never reads ES/IS rows and is never an
            // authority for either. Clients that ignore the key see the same
            // `data` list as before.
            let health = await checkHealthHandler()
            let bootstrap = Self.simigoBootstrapDocument(
                health: health,
                observedAt: Date(),
                authorities: authorityStatus)

            sendJSON(
                [
                    "object": "list",
                    "data": [entry] + additionalEntries,
                    "simigo": bootstrap,
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("GET", let path) where path.hasPrefix("/v1/models/"):
            let requestedID = String(path.dropFirst("/v1/models/".count))
            let entry = requestedID == modelId
                ? modelEntryDocument()
                : additionalModelEntriesProvider().first {
                    ($0["id"] as? String) == requestedID
                }
            guard let entry else {
                sendError("Unknown model: \(requestedID)", status: 404,
                          on: context.connection, context: context)
                return
            }
            sendJSON(entry, status: 200, on: context.connection, context: context)

        case ("POST", "/v1/branches/fork"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            guard
                let sessionId =
                    normalizeIdentifier(
                        json["session_id"] as? String
                    ),
                let sourceBranch =
                    normalizeIdentifier(
                        json["fork_from_branch"] as? String
                    ),
                let targetBranch =
                    normalizeIdentifier(
                        json["branch_id"] as? String
                    )
            else {
                sendError(
                    "branches/fork requires session_id, fork_from_branch, branch_id",
                    status: 400,
                    on: context.connection,
                    context: context
                )
                return
            }

            let metadata =
                try await forkBranchHandler(
                    resolveExplicitAgentId(
                        from: json,
                        headers: request.headers
                    ),
                    sessionId,
                    sourceBranch,
                    targetBranch
                )

            sendJSON(
                [
                    "ok": true,
                    "session_id": sessionId,
                    "fork_from_branch": sourceBranch,
                    "branch_id": targetBranch,
                    "history_messages": metadata.history.count,
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("POST", "/v1/branches/delete"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            guard
                let sessionId =
                    normalizeIdentifier(
                        json["session_id"] as? String
                    ),
                let branchId =
                    normalizeIdentifier(
                        json["branch_id"] as? String
                    )
            else {
                sendError(
                    "branches/delete requires session_id, branch_id",
                    status: 400,
                    on: context.connection,
                    context: context
                )
                return
            }
            // S3-A: optional staleness guard — a client holding a stale view
            // of the branch gets an explicit 409 instead of a silent delete.
            let expectedGeneration = (json["expected_generation"] as? NSNumber)?.uint64Value

            let outcome: BranchDeletionOutcome
            do {
                outcome = try await deleteBranchHandler(
                    resolveExplicitAgentId(
                        from: json,
                        headers: request.headers
                    ),
                    sessionId,
                    branchId,
                    expectedGeneration
                )
            } catch let error as BranchLifecycleError {
                // Owner ruling 2026-11-05 (S3-A): unknown / cross-session /
                // generation-mismatch deletions fail OBSERVABLY — a typed
                // error with its own status, never an `ok:true` body.
                switch error {
                case .branchUnknown(let unknownSession, let unknownBranch):
                    sendError(
                        "branch_unknown: no live session or checkpoint for "
                            + "\(unknownSession)/\(unknownBranch)",
                        status: 404,
                        on: context.connection,
                        context: context
                    )
                case .branchGenerationMismatch(let expected, let actual):
                    sendError(
                        "branch_generation_mismatch: expected \(expected), "
                            + "actual \(actual)",
                        status: 409,
                        on: context.connection,
                        context: context
                    )
                }
                return
            }

            // The outcome carries the post-deletion listing (A.3): the
            // caller verifies the target is gone without a second read.
            // generation is reported only when the runtime tracks one
            // (reserved for the llama.cpp ES integration).
            var body: [String: Any] = [
                "ok": true,
                "session_id": sessionId,
                "deleted_branch": outcome.deletedBranch,
                "remaining_live": outcome.remainingLiveBranches,
                "remaining_checkpoints": outcome.remainingCheckpointBranches,
            ]
            if let generation = outcome.generation {
                body["generation"] = generation
            }
            sendJSON(
                body,
                status: 200,
                on: context.connection,
                context: context
            )

        case ("POST", "/v1/branches/list"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            guard
                let sessionId =
                    normalizeIdentifier(
                        json["session_id"] as? String
                    )
            else {
                sendError(
                    "branches/list requires session_id",
                    status: 400,
                    on: context.connection,
                    context: context
                )
                return
            }

            let branches = listBranchesHandler(
                resolveExplicitAgentId(
                    from: json,
                    headers: request.headers
                ),
                sessionId
            )

            sendJSON(
                [
                    "ok": true,
                    "session_id": sessionId,
                    "live_branches": branches.live,
                    "checkpoint_branches": branches.checkpoints,
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("POST", "/v1/chat/completions"),
             ("POST", "/chat/completions"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            let diagnosticIdentity = MessageSignatureDiagnostics.enabled
                ? resolveExecutionIdentity(from: json, headers: request.headers)
                : nil
            let handleChat: () async -> Void = {
                if (json["stream"] as? Bool) == true {
                    await self.handleStreaming(
                        json,
                        headers: request.headers,
                        context: context,
                        resolvedIdentity: diagnosticIdentity)
                } else {
                    await self.handleNonStreaming(
                        json,
                        headers: request.headers,
                        context: context,
                        resolvedIdentity: diagnosticIdentity)
                }
            }
            if let diagnosticIdentity {
                await MessageSignatureDiagnostics.scoped(
                    requestID: context.requestId,
                    sessionID: diagnosticIdentity.sessionId,
                    operation: {
                        MessageSignatureDiagnostics.record(
                            stage: "B0",
                            requestID: context.requestId,
                            sessionID: diagnosticIdentity.sessionId,
                            messages: (json["messages"] as? [Any] ?? []).map(JSONValue.any),
                            tools: (json["tools"] as? [Any])?.map(JSONValue.any),
                            fields: [
                                "endpoint": "chat.completions",
                                "stream": (json["stream"] as? Bool) == true,
                                "client_request_fingerprint": resolveClientRequestId(
                                    from: json, headers: request.headers
                                ).map(MessageSignatureDiagnostics.fingerprint) ?? NSNull(),
                            ])
                        await handleChat()
                    })
            } else {
                await handleChat()
            }

        case ("POST", "/v1/completions"),
             ("POST", "/completions"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            if (json["stream"] as? Bool) == true {
                await handleTextCompletionsStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            } else {
                await handleTextCompletionsNonStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            }

        case ("POST", "/v1/responses"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            if (json["stream"] as? Bool) == true {
                await handleResponsesStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            } else {
                await handleResponsesNonStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            }

        default:
            sendError(
                "Endpoint not found",
                status: 404,
                on: context.connection,
                context: context
            )
        }
    }

}
