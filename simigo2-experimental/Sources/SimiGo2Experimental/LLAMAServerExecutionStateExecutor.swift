import Foundation
import SimiGoRuntimeContract

/// Minimal Swift transport that consumes an existing LLAMA prefix
/// representation. llama-server remains the inference and native-cache
/// authority; this type owns no model and no second KV runtime.
public struct LLAMAServerExecutionStateExecutor: Sendable {
  public struct Completion: Codable, Equatable, Sendable {
    public let content: String
    public let tokens: [Int]?
  }

  private struct CompletionRequest: Encodable {
    let prompt: [Int]
    let nPredict: Int
    let temperature: Double
    let seed: Int
    let cachePrompt: Bool
    let returnTokens: Bool

    enum CodingKeys: String, CodingKey {
      case prompt
      case nPredict = "n_predict"
      case temperature
      case seed
      case cachePrompt = "cache_prompt"
      case returnTokens = "return_tokens"
    }
  }

  public let baseURL: URL
  private let session: URLSession

  public init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }

  public func complete(tokenPrefix: [Int], predictionTokens: Int, seed: Int) async throws
    -> Completion
  {
    let request = CompletionRequest(
      prompt: tokenPrefix,
      nPredict: predictionTokens,
      temperature: 0,
      seed: seed,
      cachePrompt: false,
      returnTokens: true
    )
    return try await post(path: "/completion", body: request)
  }

  public func complete(
    _ representation: ExecutionRepresentation, predictionTokens: Int, seed: Int
  ) async throws -> Completion {
    guard let payload = representation.payload as? LLAMAServerPrefixPayload else {
      throw ExecutionStateBackendError.foreignRepresentationPayload(
        representation.executionID)
    }
    return try await complete(
      tokenPrefix: payload.tokenPrefix, predictionTokens: predictionTokens, seed: seed)
  }

  private func post<Body: Encodable, Result: Decodable>(path: String, body: Body) async throws
    -> Result
  {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      throw LLAMAServerExecutorError.badStatus(status)
    }
    return try JSONDecoder().decode(Result.self, from: data)
  }
}

public enum LLAMAServerExecutorError: Error, Equatable, Sendable {
  case badStatus(Int)
  case missingSample(index: Int, mode: String)
}
