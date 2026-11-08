import CryptoKit
import Foundation
import LOCALBCore
import SQLite3
import SimiGoRuntimeContract
import XCTest

@testable import SimiGo

/// Owner acceptance for the independent ES/IS HTTP host (Item 1 of the
/// 2026-11-03 cloud-proxy removal ruling). Every call below is a REAL HTTP
/// request to a listener started by `InformationSpaceRuntime` — never an
/// in-process `HTTPServer.runMCPTool` call. The suite runs only inside an
/// injected isolation root because the MCP handler writes
/// `SimiGoPaths.databaseURL`.
///
/// Rows covered:
///  (1) no model loaded — no MLX, no llama-server, no cloud backend config;
///  (3) real HTTP access to `/mcp`;
///  (4) begin → settle → readback (MCP tool + direct SQLite);
///  (5) begin → fail leaves a failure audit and no settlement;
///  (6) auth stays on the existing LOCALB policy: default loopback plaintext
///      tool surface marks responses `unprotected-by-LOCALB`; the secure
///      listener keeps `/mcp` on `.protected(.srsWrite)` and stays
///      fail-closed before activation and for clients without that permission;
///  (7) no upstream/cloud request and no model generation path — every
///      inference route is the host's explicit refusal.
final class InformationSpaceHostE2ETests: LOCALBTestCase {

    private let modelIdentity = "agent-owned-remote-model"
    private let tokenizerIdentity = "agent-owned-remote-tokenizer"

    // MARK: - Isolation

    /// This suite writes the IS database through the HTTP MCP handler, which
    /// resolves `SimiGoPaths.databaseURL` at call time. Without an injected
    /// isolated `SIMIGO_HOME` the run would touch the real `~/.simigo`.
    private func requireIsolatedHome() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard let home = environment["SIMIGO_HOME"], !home.isEmpty,
            home.hasPrefix("/")
        else {
            throw XCTSkip(
                "SIMIGO_HOME not injected; the real-HTTP MCP E2E writes the IS "
                    + "database and must run inside an isolation root")
        }
        let standardized = (home as NSString).standardizingPath
        let realRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo", isDirectory: true)
            .standardizedFileURL.path
        guard standardized != realRoot else {
            throw XCTSkip("SIMIGO_HOME points at the real ~/.simigo; refusing")
        }
        let url = URL(fileURLWithPath: standardized, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    /// The runtime binds and advertises from the shared node configuration.
    /// Pin a loopback node for the duration of the test; Bonjour stays off so
    /// the test never competes with the installed product's advertisement.
    private func useLoopbackNode() {
        let saved = InferenceNodeConfiguration.shared.snapshot()
        InferenceNodeConfiguration.configure(
            bindHost: "127.0.0.1",
            advertisedHost: "127.0.0.1",
            port: saved.port,
            bonjourEnabled: false
        )
        addTeardownBlock {
            InferenceNodeConfiguration.configure(
                bindHost: saved.bindHost,
                advertisedHost: saved.advertisedHost,
                port: saved.port,
                bonjourEnabled: saved.bonjourEnabled
            )
        }
    }

    private func setTransportEnvironment(_ value: String?) {
        let previous = ProcessInfo.processInfo.environment["SIMIGO_TRANSPORT"]
        if let value {
            setenv("SIMIGO_TRANSPORT", value, 1)
        } else {
            unsetenv("SIMIGO_TRANSPORT")
        }
        addTeardownBlock {
            if let previous {
                setenv("SIMIGO_TRANSPORT", previous, 1)
            } else {
                unsetenv("SIMIGO_TRANSPORT")
            }
        }
    }

    // MARK: - Runtime lifecycle

    private func startHost(
        port: UInt16,
        hostDirectory: URL? = nil,
        keychain: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transport: LOCALBTransportIdentityStore = LOCALBTransportIdentityStore()
    ) async throws -> InformationSpaceRuntime {
        let runtime = InformationSpaceRuntime()
        try await runtime.startWithLOCALB(
            port: Int(port),
            localbHostDirectory: hostDirectory,
            keychainStore: keychain,
            transportIdentityStore: transport
        )
        addTeardownBlock {
            let runtime = runtime
            Task { await runtime.stop() }
        }
        return runtime
    }

    // MARK: - Raw HTTP

    private func sendJSON(
        port: UInt16,
        path: String,
        payload: [String: Any],
        spkiHex: String? = nil
    ) -> Data? {
        let body = try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
        var request = "POST \(path) HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(port)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        request += String(decoding: body, as: UTF8.self)
        return sendRequest(port: port, spkiHex: spkiHex, request: request)
    }

    private func headerValue(_ name: String, in response: Data?) -> String? {
        guard let text = response.flatMap({ String(data: $0, encoding: .utf8) }),
            let head = text.components(separatedBy: "\r\n\r\n").first
        else { return nil }
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    == name.lowercased()
            else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    @discardableResult
    private func mcpTool(
        port: UInt16,
        id: Int,
        name: String,
        arguments: [String: Any],
        spkiHex: String? = nil
    ) throws -> [String: Any] {
        let response = sendJSON(
            port: port, path: "/mcp",
            payload: [
                "jsonrpc": "2.0", "id": id, "method": "tools/call",
                "params": ["name": name, "arguments": arguments],
            ],
            spkiHex: spkiHex)
        let status = try XCTUnwrap(statusLine(of: response), "no response")
        XCTAssertTrue(
            status.contains(" 200 "), "tools/call \(name): \(status)")
        let json = try XCTUnwrap(jsonBody(of: response))
        let result = try XCTUnwrap(json["result"] as? [String: Any], "\(json)")
        XCTAssertEqual(
            result["isError"] as? Bool, false, "tool \(name): \(result)")
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(text.utf8))
                as? [String: Any],
            text)
    }

    private func rawText(_ dbURL: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK)
        guard let handle else { return "" }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(handle, sql, -1, &stmt, nil), SQLITE_OK)
        guard let stmt else { return "" }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }

    // MARK: - (1)(3)(4)(5)(7) model-free host, real HTTP MCP

    /// Starts the ES/IS host with NO model configured and serves the full
    /// settlement surface over real HTTP: initialize/tools-list, a successful
    /// begin → settle → readback (tool + direct SQLite), a begin → fail that
    /// leaves only a failure audit, and an inference request that is refused
    /// by the host itself.
    func testModelFreeHostServesMCPSettlementOverRealHTTP() async throws {
        let home = try requireIsolatedHome()
        useLoopbackNode()
        setTransportEnvironment(nil)

        let port = randomPort()
        let runtime = try await startHost(port: port)
        XCTAssertTrue(runtime.isRunning, "host did not start")
        XCTAssertFalse(
            runtime.isGenerating,
            "the information-space host has no model and must never report generation")

        // /health answers on the listener this runtime owns.
        let health = sendRequest(
            port: port, spkiHex: nil,
            request: "GET /health HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(port)\r\n"
                + "Connection: close\r\n\r\n")
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: health)).contains(" 200 "),
            "health: \(String(describing: health.flatMap { String(data: $0, encoding: .utf8) }))")
        XCTAssertEqual(
            headerValue("X-SimiGo-Protection", in: health),
            "unprotected-by-LOCALB",
            "the default loopback listener is the existing local tool surface")

        // MCP transport: initialize + tools/list, over real HTTP.
        let initialize = sendJSON(
            port: port, path: "/mcp",
            payload: ["jsonrpc": "2.0", "id": 1, "method": "initialize"])
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: initialize)).contains(" 200 "))
        let initializeJSON = try XCTUnwrap(jsonBody(of: initialize))
        let serverInfo = try XCTUnwrap(
            (initializeJSON["result"] as? [String: Any])?["serverInfo"]
                as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "simigo")

        let toolsList = sendJSON(
            port: port, path: "/mcp",
            payload: ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let toolsJSON = try XCTUnwrap(jsonBody(of: toolsList))
        let toolNames = Set(
            ((toolsJSON["result"] as? [String: Any])?["tools"]
                as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String })
        for required in [
            "simigo_es_begin", "simigo_es_settle", "simigo_es_fail",
            "simigo_is_settlement",
        ] {
            XCTAssertTrue(
                toolNames.contains(required),
                "missing \(required): \(toolNames)")
        }

        // (4) begin → settle → readback.
        let begun = try mcpTool(
            port: port, id: 3, name: "simigo_es_begin",
            arguments: ["model": modelIdentity, "tokenizer": tokenizerIdentity])
        let stateID = try XCTUnwrap(begun["state_id"] as? String)
        XCTAssertEqual(begun["settled"] as? Bool, false)
        XCTAssertEqual(begun["resumed"] as? Bool, false)

        let output = "隔离宿主已通过真实 HTTP 完成一次宿主侧结算。"
        let settled = try mcpTool(
            port: port, id: 4, name: "simigo_es_settle",
            arguments: [
                "state_id": stateID,
                "model": modelIdentity,
                "tokenizer": tokenizerIdentity,
                "output": output,
                "session_id": "is-host-e2e-session",
                "query": "隔离宿主真实 HTTP 结算",
            ])
        let settlementID = try XCTUnwrap(
            settled["settlement_id"] as? String)
        XCTAssertFalse(settlementID.isEmpty, "\(settled)")
        XCTAssertEqual(settled["validity"] as? String, "valid")
        let payloadDigest = try XCTUnwrap(
            settled["payload_sha256"] as? String)
        XCTAssertEqual(payloadDigest.count, 64)

        let receipt = try mcpTool(
            port: port, id: 5, name: "simigo_is_settlement",
            arguments: ["settlement_id": settlementID])
        XCTAssertEqual(receipt["settlement_id"] as? String, settlementID)
        // The stored payload is the result-contract envelope, not the bare
        // string: the settled content lives under its `content` field.
        let payloadText = try XCTUnwrap(receipt["payload"] as? String)
        let payloadEnvelope = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(payloadText.utf8))
                as? [String: Any],
            payloadText)
        XCTAssertEqual(payloadEnvelope["content"] as? String, output)
        XCTAssertEqual(receipt["validity"] as? String, "valid")
        let bindings = try XCTUnwrap(
            receipt["bindings"] as? [String: Any])
        XCTAssertEqual(
            bindings["producer.model_identity"] as? String,
            SimiGoSettlementIdentityBinding.digest(modelIdentity))
        XCTAssertEqual(
            bindings["producer.tokenizer_identity"] as? String,
            SimiGoSettlementIdentityBinding.digest(tokenizerIdentity))

        // Independent persistence readback (not through the tool layer).
        let dbURL = home.appendingPathComponent("simigo.sqlite3")
        XCTAssertEqual(
            try rawText(
                dbURL,
                "SELECT COUNT(*) FROM settlements WHERE settlement_id='\(settlementID)';"),
            "1")
        XCTAssertEqual(
            try rawText(
                dbURL,
                "SELECT COUNT(*) FROM is_objects WHERE object_id='\(payloadDigest)';"),
            "1")

        // (5) begin → fail: a failure audit, never a settlement.
        let failedState = try mcpTool(
            port: port, id: 6, name: "simigo_es_begin",
            arguments: ["model": modelIdentity, "tokenizer": tokenizerIdentity])
        let failedStateID = try XCTUnwrap(
            failedState["state_id"] as? String)
        let failed = try mcpTool(
            port: port, id: 7, name: "simigo_es_fail",
            arguments: [
                "state_id": failedStateID,
                "detail": "agent upstream returned 529",
                "evidence": ["status": "529"],
            ])
        XCTAssertEqual(failed["audit_persisted"] as? Bool, true)
        XCTAssertEqual(failed["settlement_id"] as? String, "")
        let failureObject = try XCTUnwrap(failed["object_id"] as? String)
        XCTAssertEqual(
            try rawText(
                dbURL,
                "SELECT COUNT(*) FROM is_objects WHERE object_id='\(failureObject)';"),
            "1")
        XCTAssertEqual(
            try rawText(
                dbURL,
                "SELECT COUNT(*) FROM settlements WHERE state_id='\(failedStateID)';"),
            "0",
            "a failure never fabricates a settlement")

        // (7) No model generation path: the inference route refuses inside
        // the host, and nothing new is settled.
        //
        // Two row classes live in `settlements`: a RESULT settlement
        // (`validation_status='VALID'`, produced by a model) and a DERIVED
        // retrieval row (`IS_RETRIEVAL`, no state, the IS-produced fact a
        // demand resolves to). A refused inference must add no RESULT
        // settlement; the only row it may add is the derived retrieval row
        // for the prompt's own IS demand.
        let resultSettlementsBefore = try rawText(
            dbURL,
            "SELECT COUNT(*) FROM settlements WHERE validation_status='VALID';")
        let retrievalRowsBefore = try XCTUnwrap(
            Int(try rawText(
                dbURL,
                "SELECT COUNT(*) FROM settlements WHERE validation_status='IS_RETRIEVAL';")))
        let chatResponse = sendJSON(
            port: port, path: "/v1/chat/completions",
            payload: [
                "model": modelIdentity,
                "messages": [["role": "user", "content": "hello"]],
            ])
        let chatText = String(
            decoding: chatResponse ?? Data(), as: UTF8.self)
        XCTAssertFalse(
            chatText.contains("\"choices\""),
            "the model-free host must not fabricate a completion: \(chatText)")
        XCTAssertTrue(
            chatText.contains("不提供模型推理"),
            "expected the host's explicit refusal, got: \(chatText)")
        XCTAssertEqual(
            try rawText(
                dbURL,
                "SELECT COUNT(*) FROM settlements WHERE validation_status='VALID';"),
            resultSettlementsBefore,
            "a refused inference request must not settle a result")
        XCTAssertEqual(
            try rawText(
                dbURL,
                "SELECT COUNT(*) FROM settlements WHERE validation_status='IS_RETRIEVAL';"),
            String(retrievalRowsBefore + 1),
            "the refused request resolves its own IS demand once (derived row)")

        // (1) No model surfaces from /v1/models either: the host reports only
        // its own identity.
        let models = sendRequest(
            port: port, spkiHex: nil,
            request: "GET /v1/models HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(port)\r\n"
                + "Connection: close\r\n\r\n")
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: models)).contains(" 200 "))
        XCTAssertTrue(
            String(decoding: models ?? Data(), as: UTF8.self)
                .contains("simigo-information-space"))

        await runtime.stop()
        XCTAssertFalse(runtime.isRunning)
    }

    // MARK: - (6) auth policy on the IS host

    /// The host never opens a weaker channel than its listener already has:
    /// a missing transport identity fails startup, an unactivated host keeps
    /// `/mcp` at 503, and an activated host keeps `/mcp` on the existing
    /// `.protected(.srsWrite)` policy — proof required, and the paired
    /// non-SRS client cannot obtain that challenge. The same listener still
    /// serves its normal read route through a valid V2 proof.
    func testSecureHostKeepsMCPProofPolicyAndFailsClosedBeforeActivation()
        async throws
    {
        _ = try requireIsolatedHome()
        useLoopbackNode()
        setTransportEnvironment("secure")

        // No transport identity: startup fails closed instead of falling back
        // to an open plaintext listener.
        let bareDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "is-host-bare-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bareDirectory)
        }
        let bareKeychain = LOCALBKeychainSignerStore(
            service: "com.simigo.tests.is-host-bare.\(UUID().uuidString)",
            account: "signing-key-v1")
        let bareTransport = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.is-host-bare.\(UUID().uuidString)",
            account: "tls")
        addTeardownBlock { bareTransport.deleteAll() }

        let bareRuntime = InformationSpaceRuntime()
        do {
            try await bareRuntime.startWithLOCALB(
                port: Int(randomPort()),
                localbHostDirectory: bareDirectory,
                keychainStore: bareKeychain,
                transportIdentityStore: bareTransport)
            XCTFail("secure startup without a transport identity must fail closed")
            await bareRuntime.stop()
        } catch {
            XCTAssertFalse(bareRuntime.isRunning)
        }

        // TLS identity present but host NOT activated: transport-only secure.
        // `/mcp` fails closed 503; health still answers over pinned TLS.
        let identity = try bareTransport.loadOrCreate()
        let unactivatedPort = randomPort()
        let unactivated = try await startHost(
            port: unactivatedPort,
            hostDirectory: bareDirectory,
            keychain: bareKeychain,
            transport: bareTransport)
        XCTAssertTrue(unactivated.isRunning)

        let health = sendRequest(
            port: unactivatedPort, spkiHex: identity.spkiSHA256Hex,
            request: "GET /health HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(unactivatedPort)\r\n"
                + "Connection: close\r\n\r\n")
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: health)).contains(" 200 "))
        XCTAssertEqual(
            headerValue("X-SimiGo-Protection", in: health), "localb-tls")

        let mcpNoProof = sendRequest(
            port: unactivatedPort, spkiHex: identity.spkiSHA256Hex,
            request: "POST /mcp HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(unactivatedPort)\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: 2\r\n"
                + "Connection: close\r\n\r\n{}")
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: mcpNoProof)).contains(" 503 "),
            "before activation /mcp must fail closed: "
                + String(describing: mcpNoProof.flatMap { String(data: $0, encoding: .utf8) }))
        await unactivated.stop()

        // Activated host with one paired ACTIVE client that holds the
        // ordinary client permissions (inference + information read).
        let environment = try makeBootstrapHostEnvironment()
        let port = randomPort()
        let activated = try await startHost(
            port: port,
            hostDirectory: environment.hostDirectory,
            keychain: environment.keychain,
            transport: environment.transport)
        XCTAssertTrue(activated.isRunning)
        let host = host(for: environment, port: port)

        // `/mcp` still derives its permission from the single route table:
        // SRS write, never a read or inference substitution.
        let challengeBody = "{\"method\":\"POST\",\"requestTarget\":\"/mcp\"}"
        let mcpChallenge = sendRequest(
            port: port, spkiHex: host.spkiHex,
            request: "POST /localb/auth/challenge HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(port)\r\n"
                + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(challengeBody.utf8.count)\r\n"
                + "Connection: close\r\n\r\n" + challengeBody)
        let challengeText = String(
            decoding: mcpChallenge ?? Data(), as: UTF8.self)
        XCTAssertTrue(
            challengeText.contains("LOCALB_PERMISSION_DENIED"),
            "P-SRS-WRITE is host-exclusive; a paired read client must not be "
                + "granted it: \(challengeText)")

        // No proof on the activated host is rejected, not served.
        let mcpRejected = sendRequest(
            port: port, spkiHex: host.spkiHex,
            request: "POST /mcp HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(port)\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: 2\r\n"
                + "Connection: close\r\n\r\n{}")
        let rejectedText = String(
            decoding: mcpRejected ?? Data(), as: UTF8.self)
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: mcpRejected)).contains(" 401 "),
            "unproven /mcp: \(rejectedText)")
        XCTAssertTrue(
            rejectedText.contains("LOCALB_CLIENT_PROOF_MISSING"),
            rejectedText)

        // Positive control on the SAME listener: the paired client's
        // information-read permission still works through the full
        // challenge → proof → dispatch flow.
        let (readChallenge, readPermission) = try fetchChallenge(
            host, method: "GET", target: "/v1/models")
        XCTAssertEqual(readPermission, "P-INFO-READ")
        let readRequest = try protectedRequest(
            host, method: "GET", target: "/v1/models",
            contentType: nil, body: "",
            challenge: readChallenge,
            permission: .informationRead)
        let readResponse = sendRequest(
            port: port, spkiHex: host.spkiHex, request: readRequest)
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: readResponse)).contains(" 200 "))
        XCTAssertTrue(
            String(decoding: readResponse ?? Data(), as: UTF8.self)
                .contains("simigo-information-space"))

        await activated.stop()
        XCTAssertFalse(activated.isRunning)
    }

    /// The current MCP HTTP surface must not offer a previously settled answer
    /// after another session commits new information into the shared IS. The
    /// source retrieval remains valid: this is a current-demand freshness check,
    /// not a test of dependency invalidation.
    func testRealHTTPMCPBeginRefusesAnswerAfterSharedInformationChanges() async throws {
        let home = try requireIsolatedHome()
        useLoopbackNode()
        setTransportEnvironment(nil)

        let port = randomPort()
        let runtime = try await startHost(port: port)
        XCTAssertTrue(runtime.isRunning)
        let session = "mcp-freshness-\(UUID().uuidString)"
        let query = "where is the exit"

        let search = try mcpTool(
            port: port, id: 20, name: "simigo_is_search",
            arguments: [
                "query": query, "session_id": session, "include_chat": true,
            ])
        let demandID = try XCTUnwrap(search["demand_id"] as? String)
        let retrievalID = try XCTUnwrap(search["retrieval_settlement_id"] as? String)
        XCTAssertFalse(demandID.isEmpty)
        XCTAssertFalse(retrievalID.isEmpty)

        let begun = try mcpTool(
            port: port, id: 21, name: "simigo_es_begin",
            arguments: ["model": modelIdentity, "tokenizer": tokenizerIdentity])
        let sourceStateID = try XCTUnwrap(begun["state_id"] as? String)
        let settled = try mcpTool(
            port: port, id: 22, name: "simigo_es_settle",
            arguments: [
                "state_id": sourceStateID,
                "model": modelIdentity,
                "tokenizer": tokenizerIdentity,
                "output": "The exit is in the west wing.",
                "session_id": session,
                "query": query,
                "demand_id": demandID,
                "retrieval_settlement_id": retrievalID,
            ])
        XCTAssertFalse(
            (settled["advancement_id"] as? String ?? "").isEmpty,
            "the source answer must advance the named retrieval demand")

        let dbURL = home.appendingPathComponent("simigo.sqlite3")
        let db = try SimiGoESISDatabase(url: dbURL, createIfNeeded: false)
        let outsideSession = "mcp-new-fact-\(UUID().uuidString)"
        let userID = try db.appendChatMessage(
            sessionID: outsideSession, role: "user",
            content: "exit location update", model: nil, createdAt: Date())
        try db.commitChatTurn(
            sessionID: outsideSession, userMessageID: userID,
            assistantText: "The exit has moved to the east wing.",
            model: nil, createdAt: Date())
        XCTAssertEqual(try db.settlementValidity(retrievalID), "valid",
                       "the old retrieval remains valid; new chat is not its dependency")
        db.close()

        let again = try mcpTool(
            port: port, id: 23, name: "simigo_es_begin",
            arguments: [
                "model": modelIdentity,
                "tokenizer": tokenizerIdentity,
                "session_id": session,
                "query": query,
                "include_chat": true,
            ])
        XCTAssertTrue(
            again["reusable_answer"] is NSNull,
            "a new shared-space fact changes the current demand and blocks stale reuse: \(again)")

        // The new demand can now be answered and should be reusable on its own
        // unchanged exact repeat; the older answer remains outside this basis.
        let refreshedSearch = try mcpTool(
            port: port, id: 24, name: "simigo_is_search",
            arguments: [
                "query": query, "session_id": session, "include_chat": true,
            ])
        let refreshedDemand = try XCTUnwrap(refreshedSearch["demand_id"] as? String)
        let refreshedRetrieval = try XCTUnwrap(
            refreshedSearch["retrieval_settlement_id"] as? String)
        let refreshedState = try mcpTool(
            port: port, id: 25, name: "simigo_es_begin",
            arguments: ["model": modelIdentity, "tokenizer": tokenizerIdentity])
        let refreshedStateID = try XCTUnwrap(refreshedState["state_id"] as? String)
        let refreshedAnswer = try mcpTool(
            port: port, id: 26, name: "simigo_es_settle",
            arguments: [
                "state_id": refreshedStateID,
                "model": modelIdentity,
                "tokenizer": tokenizerIdentity,
                "output": "The exit is now in the east wing.",
                "session_id": session,
                "query": query,
                "demand_id": refreshedDemand,
                "retrieval_settlement_id": refreshedRetrieval,
            ])
        XCTAssertFalse(
            (refreshedAnswer["advancement_id"] as? String ?? "").isEmpty)
        let finalRepeat = try mcpTool(
            port: port, id: 27, name: "simigo_es_begin",
            arguments: [
                "model": modelIdentity,
                "tokenizer": tokenizerIdentity,
                "session_id": session,
                "query": query,
                "include_chat": true,
            ])
        // MCP begin never serves a historical answer — not even a fresh
        // replacement whose own demand is unchanged. The begin contract keeps
        // the newly begun ES free of an un-consumed settlement; a future MCP
        // reuse path must resolve the current demand and consume explicitly.
        // Replacement freshness is exercised on the chat/responses reuse lanes.
        XCTAssertTrue(
            finalRepeat["reusable_answer"] is NSNull,
            "begin must not serve answers; explicit settlement consumption is the only zero-model path: \(finalRepeat)")
        await runtime.stop()
    }

}
