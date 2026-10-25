import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

final class CloudBackendTests: XCTestCase {
    func testDefaultCloudModelOverridesLocalAlias() throws {
        XCTAssertEqual(CloudBackendConfiguration().model, "glm-5.3-flash")

        let backend = RemoteOpenAIBackend(
            configuration: CloudBackendConfiguration(baseURLString: "https://api.example.com/v1"),
            apiKey: "secret"
        )
        let request = try backend.makeRequest(
            path: "/v1/chat/completions",
            method: "POST",
            headers: ["content-type": "application/json"],
            body: Data(#"{"model":"Localmodel","messages":[]}"#.utf8)
        )

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "glm-5.3-flash")
    }

    func testVersionedBaseURLDoesNotDuplicateV1() throws {
        let configuration = CloudBackendConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "gpt-test"
        )

        let url = try XCTUnwrap(configuration.upstreamURL(path: "/v1/chat/completions"))
        XCTAssertEqual(url.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testZAICodingBaseURLDoesNotDuplicateV4() throws {
        let configuration = CloudBackendConfiguration(
            baseURLString: "https://open.bigmodel.cn/api/coding/paas/v4",
            model: "glm-5.3-flash"
        )

        let url = try XCTUnwrap(configuration.upstreamURL(path: "/v1/chat/completions"))
        XCTAssertEqual(
            url.absoluteString,
            "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions"
        )
    }

    func testHostRootKeepsClientVersionPath() throws {
        let configuration = CloudBackendConfiguration(
            baseURLString: "https://api.example.com",
            model: "gpt-test"
        )

        let url = try XCTUnwrap(configuration.upstreamURL(path: "/v1/chat/completions"))
        XCTAssertEqual(url.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testRemoteRequestUsesConfiguredKeyAndModel() throws {
        let configuration = CloudBackendConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "gpt-test"
        )
        let backend = RemoteOpenAIBackend(configuration: configuration, apiKey: "secret")
        let body = Data(#"{"model":"simigo-local","messages":[]}"#.utf8)

        let request = try backend.makeRequest(
            path: "/v1/chat/completions",
            method: "POST",
            headers: ["content-type": "application/json", "connection": "keep-alive"],
            body: body
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertNil(request.value(forHTTPHeaderField: "Connection"))

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-test")
    }

    func testCloudConfigurationRequiresAPIKeyOutsideLoopback() {
        let configuration = CloudBackendConfiguration(
            baseURLString: "https://api.example.com/v1",
            model: "gpt-test"
        )

        XCTAssertThrowsError(try configuration.validated(apiKey: ""))
        XCTAssertNoThrow(try configuration.validated(apiKey: "secret"))
    }

    func testGLMDisablesThinkingUnlessClientChooses() throws {
        let configuration = CloudBackendConfiguration(
            baseURLString: "https://api.z.ai/api/coding/paas/v4",
            model: "glm-5.3-flash"
        )
        let backend = RemoteOpenAIBackend(configuration: configuration, apiKey: "secret")

        func json(_ body: String) throws -> [String: Any] {
            let request = try backend.makeRequest(
                path: "/v1/chat/completions",
                method: "POST",
                headers: ["content-type": "application/json"],
                body: Data(body.utf8)
            )
            return try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        }

        XCTAssertEqual(
            (try json(#"{"model":"Localmodel","messages":[]}"#))["thinking"] as? [String: String],
            ["type": "low"]
        )
        XCTAssertNil((try json(#"{"model":"Localmodel","messages":[],"enable_thinking":true,"reasoning_effort":"high","reasoning":{"effort":"high"}}"#))["enable_thinking"])
        XCTAssertNil((try json(#"{"model":"Localmodel","messages":[],"enable_thinking":true,"reasoning_effort":"high","reasoning":{"effort":"high"}}"#))["reasoning_effort"])
        XCTAssertNil((try json(#"{"model":"Localmodel","messages":[],"enable_thinking":true,"reasoning_effort":"high","reasoning":{"effort":"high"}}"#))["reasoning"])
    }

    /// The cloud credential is a 0600 file under the managed root — never the
    /// login Keychain, whose items are signature-locked to the creating build
    /// (every re-signed build hit an unsatisfiable SecurityAgent prompt,
    /// 2026-10-26). Round-trip, permissions, and clearing all happen inside the
    /// managed root the runner redirects via SIMIGO_HOME.
    func testCloudCredentialManagedFileRoundTrip() throws {
        let home = ProcessInfo.processInfo.environment["SIMIGO_HOME"] ?? ""
        try XCTSkipIf(home.isEmpty, "requires the isolated runner's SIMIGO_HOME")
        let probe = "probe-\(UUID().uuidString)"
        CloudKeychain.writeAPIKey(probe)
        XCTAssertEqual(CloudKeychain.readAPIKey(), probe,
                       "write then read must round-trip through the managed file")
        let url = SimiGoPaths.managedRoot()
            .appendingPathComponent("cloud/api-key")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600, "the credential file must be owner-only")
        CloudKeychain.writeAPIKey("")
        XCTAssertEqual(CloudKeychain.readAPIKey(), "",
                       "an empty write clears the credential")
    }
}
