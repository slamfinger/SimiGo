import Foundation
import XCTest

@testable import SimiGo

/// #149 acceptance: `/v1/models` stays an OpenAI-compatible model list and
/// gains a top-level `simigo` discovery object.
///
/// The object is a declaration, not an authority: these tests pin that it is
/// built without touching ES/IS, that the model `data` shape is unchanged for
/// clients that ignore the key, and that no implementation detail (path,
/// database location, pid) reaches the wire.
final class ModelsBootstrapHTTPTests: XCTestCase {

    private final class HealthFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _healthy = true
        var healthy: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _healthy }
            set { lock.lock(); _healthy = newValue; lock.unlock() }
        }
    }

    private func makeServer(
        port: UInt16,
        health: HealthFlag
    ) -> HTTPServer {
        let server = HTTPServer(
            port: Int(port),
            modelId: "bootstrap-test-model",
            bonjourEnabled: false,
            generateHandler: { _, _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "bootstrap-test-model",
                    savedAt: Date(),
                    history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { health.healthy }
        )
        server.configureLOCALBSecurityMode(.legacyPlaintextCompat)
        return server
    }

    private func getModels(port: UInt16) async throws -> (status: Int, body: [String: Any]) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/models")!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, json)
    }

    @MainActor
    private func withServer(
        health: HealthFlag,
        run: (UInt16) async throws -> Void
    ) async throws {
        let port = try GGUFRestFixture.freePort()
        let server = makeServer(port: port, health: health)
        try server.start()
        defer { server.stop() }
        try GGUFRestFixture.waitUntilListening(port: Int(port))
        try await run(port)
    }

    // MARK: - Compatibility

    @MainActor
    func testModelListShapeIsUnchangedForClientsThatIgnoreSimigo() async throws {
        let health = HealthFlag()
        try await withServer(health: health) { port in
            let (status, body) = try await getModels(port: port)
            XCTAssertEqual(status, 200)
            XCTAssertEqual(body["object"] as? String, "list")

            let data = try XCTUnwrap(body["data"] as? [[String: Any]])
            XCTAssertEqual(data.count, 1)
            let model = try XCTUnwrap(data.first)
            XCTAssertEqual(model["id"] as? String, "bootstrap-test-model")
            XCTAssertEqual(model["object"] as? String, "model")
            XCTAssertEqual(model["owned_by"] as? String, "simigo")
            XCTAssertNotNil(model["created"] as? Int)
            XCTAssertNil(
                model["simigo"],
                "the extension belongs to the list response, not the model object")
        }
    }

    // MARK: - Discovery content

    @MainActor
    func testBootstrapDeclaresCapabilitiesScopesCarrierAndLiveStatus() async throws {
        let health = HealthFlag()
        try await withServer(health: health) { port in
            let before = Date()
            let (status, body) = try await getModels(port: port)
            XCTAssertEqual(status, 200)

            let simigo = try XCTUnwrap(body["simigo"] as? [String: Any])
            XCTAssertEqual(simigo["schema_version"] as? Int, 1)

            let capabilities = try XCTUnwrap(simigo["capabilities"] as? [String: Any])
            for key in ["es", "is", "memory_kv_cache", "external_api_intake"] {
                XCTAssertNotNil(
                    capabilities[key] as? [String: Any],
                    "capability \(key) must be declared")
            }
            let isCapability = try XCTUnwrap(capabilities["is"] as? [String: Any])
            let search = try XCTUnwrap(isCapability["search"] as? [String: Any])
            XCTAssertEqual(search["path"] as? String, "/v1/simigo/search")
            XCTAssertEqual(search["methods"] as? [String], ["GET", "POST"])
            let mcp = try XCTUnwrap(isCapability["mcp"] as? [String: Any])
            XCTAssertEqual(mcp["path"] as? String, "/mcp")

            // The cloud proxy was removed before this branch, so an external
            // API result can only enter the space through MCP settlement.
            let intake = try XCTUnwrap(capabilities["external_api_intake"] as? [String: Any])
            XCTAssertEqual(intake["channels"] as? [String], ["mcp_settle"])

            let scopes = try XCTUnwrap(simigo["request_scopes"] as? [String: Any])
            let declaration = try XCTUnwrap(scopes["declaration"] as? [String: Any])
            XCTAssertEqual(
                declaration["json_keys"] as? [String],
                [
                    "metadata.simigo_request_scope",
                    "client_metadata.simigo_request_scope",
                ])
            XCTAssertEqual(
                declaration["headers"] as? [String], ["X-SimiGo-Request-Scope"])
            XCTAssertEqual(
                declaration["internal_values"] as? [String],
                ["internal", "internal_operation", "internal-op"])
            XCTAssertEqual(declaration["default"] as? String, "ordinary")

            let surfaces = try XCTUnwrap(scopes["surfaces"] as? [[String: Any]])
            let byPath = Dictionary(
                uniqueKeysWithValues: surfaces.compactMap { surface -> (String, [String: Any])? in
                    guard let path = surface["path"] as? String else { return nil }
                    return (path, surface)
                })
            XCTAssertEqual(byPath["/v1/chat/completions"]?["managed"] as? Bool, true)
            XCTAssertEqual(
                byPath["/v1/chat/completions"]?["identifiers"] as? [String],
                ["session_id", "conversation_id"])
            XCTAssertEqual(byPath["/v1/responses"]?["managed"] as? Bool, true)
            XCTAssertEqual(byPath["/v1/completions"]?["managed"] as? Bool, false)

            let carrier = try XCTUnwrap(simigo["carrier"] as? [String: Any])
            let kv = try XCTUnwrap(carrier["kv_cache"] as? [String: Any])
            XCTAssertEqual(kv["mode"] as? String, "memory")
            XCTAssertNotNil(
                kv["disk_persistence"] as? Bool,
                "persistence is declared, not implied")
            let information = try XCTUnwrap(carrier["information_space"] as? [String: Any])
            XCTAssertEqual(information["durability"] as? String, "disk")

            let runtime = try XCTUnwrap(simigo["runtime_status"] as? [String: Any])
            XCTAssertEqual(runtime["health"] as? String, "ok")
            let observedAt = try XCTUnwrap(runtime["observed_at"] as? String)
            let parsed = try XCTUnwrap(ISO8601DateFormatter().date(from: observedAt))
            XCTAssertGreaterThanOrEqual(parsed, before.addingTimeInterval(-1))
            XCTAssertLessThanOrEqual(parsed, Date().addingTimeInterval(1))
        }
    }

    @MainActor
    func testHealthProbeChangesStatusWithoutChangingTheModelList() async throws {
        let health = HealthFlag()
        health.healthy = false
        try await withServer(health: health) { port in
            let (status, body) = try await getModels(port: port)
            XCTAssertEqual(status, 200, "discovery stays available while the engine is not")
            let simigo = try XCTUnwrap(body["simigo"] as? [String: Any])
            let runtime = try XCTUnwrap(simigo["runtime_status"] as? [String: Any])
            XCTAssertEqual(runtime["health"] as? String, "unavailable")
            XCTAssertNotNil(
                body["data"] as? [[String: Any]],
                "the model list is not gated on the health probe")
        }
    }

    // MARK: - No implementation details

    @MainActor
    func testBootstrapCarriesNoPathsDatabaseLocationOrPid() async throws {
        let health = HealthFlag()
        try await withServer(health: health) { port in
            let (_, body) = try await getModels(port: port)
            let simigo = try XCTUnwrap(body["simigo"] as? [String: Any])

            var keys: [String] = []
            var strings: [String] = []
            func walk(_ value: Any) {
                switch value {
                case let object as [String: Any]:
                    for (key, nested) in object {
                        keys.append(key.lowercased())
                        walk(nested)
                    }
                case let array as [Any]:
                    array.forEach(walk)
                case let text as String:
                    strings.append(text)
                default:
                    break
                }
            }
            walk(simigo)

            for forbidden in ["pid", "process_id", "database", "db_path", "db", "workdir"] {
                XCTAssertFalse(
                    keys.contains(forbidden),
                    "bootstrap must not expose \(forbidden)")
            }
            for text in strings {
                XCTAssertFalse(text.contains("/Users/"), "filesystem path leaked: \(text)")
                XCTAssertFalse(text.contains(".sqlite"), "database location leaked: \(text)")
                XCTAssertFalse(text.contains("tokenizer.adapter.json"), "file name leaked: \(text)")
            }
            for text in strings where text.hasPrefix("/") {
                XCTAssertTrue(
                    text == "/mcp" || text.hasPrefix("/v1/"),
                    "only API surfaces may be named as absolute paths: \(text)")
            }
        }
    }

    // MARK: - Declarative construction

    func testBootstrapDocumentIsDeterministicAndNeedsNoStore() {
        let epoch = Date(timeIntervalSince1970: 0)
        let document = HTTPServer.simigoBootstrapDocument(health: true, observedAt: epoch)
        let runtime = document["runtime_status"] as? [String: Any]
        XCTAssertEqual(runtime?["observed_at"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(runtime?["health"] as? String, "ok")

        let dark = HTTPServer.simigoBootstrapDocument(health: false, observedAt: epoch)
        XCTAssertEqual(
            (dark["runtime_status"] as? [String: Any])?["health"] as? String,
            "unavailable")
    }
}
