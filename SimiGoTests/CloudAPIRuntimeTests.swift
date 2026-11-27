import Foundation
import XCTest

@testable import SimiGo

final class CloudAPIRuntimeTests: XCTestCase {
    func testProfileAppendsChatCompletionsToConfiguredPrefix() throws {
        let profile = CloudAPIProfile(
            name: "OpenAI-compatible",
            baseURL: "https://api.example.com/provider/v1/",
            model: "reasoning-model")

        XCTAssertEqual(
            try profile.chatCompletionsURL().absoluteString,
            "https://api.example.com/provider/v1/chat/completions")
        XCTAssertNoThrow(try profile.validate())
    }

    func testProfileRejectsInsecureRemoteHTTPButAllowsLoopbackDevelopmentEndpoint() throws {
        let remote = CloudAPIProfile(
            baseURL: "http://api.example.com/v1",
            model: "test-model")
        XCTAssertThrowsError(try remote.chatCompletionsURL()) { error in
            XCTAssertEqual(error as? CloudAPIProfileError, .insecureBaseURL)
        }

        let local = CloudAPIProfile(
            baseURL: "http://127.0.0.1:8080/v1",
            model: "test-model")
        XCTAssertEqual(
            try local.chatCompletionsURL().absoluteString,
            "http://127.0.0.1:8080/v1/chat/completions")
    }

    func testRequestUsesConfiguredProviderModelAndBearerCredential() throws {
        let profile = CloudAPIProfile(
            name: "Test provider",
            baseURL: "https://api.example.com/v1",
            model: "provider-model")
        var config = ModelConfig()
        config.temperature = 0.25
        config.topP = 0.8
        config.maxTokens = 321
        config.toolChoice = ToolChoiceSelection(mode: .required)

        let messages = [
            JSONValue.any(["role": "system", "content": "stable instruction"]),
            JSONValue.any(["role": "user", "content": "current request"]),
        ]
        let tools = [
            JSONValue.any([
                "type": "function",
                "function": [
                    "name": "lookup",
                    "description": "Look up a record",
                    "parameters": ["type": "object", "properties": [String: Any]()],
                ],
            ]),
        ]

        let request = try OpenAICompatibleClient.makeRequest(
            profile: profile,
            apiKey: "sk-test-cloud-key",
            messages: messages,
            tools: tools,
            config: config)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer sk-test-cloud-key")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            "text/event-stream")

        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "provider-model")
        XCTAssertEqual(body["stream"] as? Bool, true)
        // ModelConfig carries Float; compare through Double so the assertion
        // tests the configured value itself instead of Float's decimal rounding.
        XCTAssertEqual(body["temperature"] as? Double, Double(config.temperature))
        XCTAssertEqual(body["top_p"] as? Double, Double(config.topP))
        XCTAssertEqual(body["max_tokens"] as? Int, 321)
        XCTAssertEqual(body["tool_choice"] as? String, "required")
        XCTAssertNotNil(body["messages"] as? [[String: Any]])
        XCTAssertNotNil(body["tools"] as? [[String: Any]])

        // Local-engine-only sampler and KV settings must never leak upstream.
        XCTAssertNil(body["top_k"])
        XCTAssertNil(body["min_p"])
        XCTAssertNil(body["repeat_penalty"])
        XCTAssertNil(body["kv_cache"])
    }

    func testProfileRequiresModelName() {
        let profile = CloudAPIProfile(model: "  ")
        XCTAssertThrowsError(try profile.validate()) { error in
            XCTAssertEqual(error as? CloudAPIProfileError, .missingRequiredField)
        }
    }
}
