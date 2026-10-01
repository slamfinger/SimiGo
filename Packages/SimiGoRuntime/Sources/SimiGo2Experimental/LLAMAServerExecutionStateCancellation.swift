import Foundation
import SimiGoRuntimeContract

/// RQ3 — Swift contract integration around an explicit llama-server stream
/// cancellation. The long child request is cancelled; the unaffected root
/// representation is restored and replayed. llama-server owns inference and
/// native cache; this is a research harness, not production cancellation.
public enum LLAMAServerExecutionStateCancellation {
  public static let protocolVersion = "RQ3.LLAMA.SWIFT.EXECSTATE.CANCELLATION.V1"
  public static let boundary =
    "SWIFT_CONTRACT_STATE_AROUND_EXPLICIT_BACKEND_CANCEL / HARNESS_LEVEL / "
    + "NO_NATIVE_KV_AUTHORITY_CHANGE / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"

  public struct Check: Encodable {
    public let name: String
    public let pass: Bool
    public let detail: String
  }

  public struct Sample: Encodable {
    public let index: Int
    public let mode: String
    public let conversationId: String
    public let deleteStatus: Int
    public let cancelAccepted: Bool
    public let deleteToFreeMs: Double
    public let recoveryClientMs: Double
    public let stateOperationMs: Double
    public let recoveryContent: String
    public let recoveryTokens: [Int]
    public let semanticIdentical: Bool
  }

  public struct TimingSummary: Encodable {
    public let n: Int
    public let meanMs: Double
    public let medianMs: Double
  }

  public struct Report: Encodable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let host: String
    public let port: Int
    public let longPrompt: String
    public let rootTokenPrefix: [Int]
    public let cancelDelayMs: Int
    public let predictionTokens: Int
    public let reference: LLAMAServerExecutionStateExecutor.Completion
    public let checks: [Check]
    public let samples: [Sample]
    public let deleteToFreeMs: [String: TimingSummary]
    public let recoveryClientMs: [String: TimingSummary]
    public let pairedOnMinusOffRecoveryMs: TimingSummary
    public let stateOperationMs: TimingSummary
    public let overallPass: Bool
  }

  private struct Health: Decodable {
    let status: String
  }

  private struct Slot: Decodable {
    let id: Int
    let isProcessing: Bool

    enum CodingKeys: String, CodingKey {
      case id
      case isProcessing = "is_processing"
    }
  }

  private struct ChatMessage: Encodable {
    let role: String
    let content: String
  }

  private struct ChatRequest: Encodable {
    let stream: Bool
    let maxTokens: Int
    let temperature: Double
    let seed: Int
    let messages: [ChatMessage]

    enum CodingKeys: String, CodingKey {
      case stream
      case maxTokens = "max_tokens"
      case temperature
      case seed
      case messages
    }
  }

  final class CancellableStream: @unchecked Sendable {
    private let task: URLSessionDataTask
    private let session: URLSession

    init(session: URLSession, request: URLRequest) {
      self.session = session
      self.task = session.dataTask(with: request)
      self.task.resume()
    }

    func close() {
      task.cancel()
    }

  }

  public static func run(
    host: String = "127.0.0.1",
    port: Int = 18080,
    cycles: Int = 20,
    cancelDelayMs: Int = 100,
    predictionTokens: Int = 256,
    freeTimeoutMs: Int = 15000,
    seed: Int = 42,
    longPrompt: String = "Count from 1 to 500. Return only numbers separated by spaces.",
    rootTokenPrefix: [Int] = [5423, 6681, 799, 3299, 25, 29018]
  ) async throws -> Report {
    let baseURL = URL(string: "http://\(host):\(port)")!
    let executor = LLAMAServerExecutionStateExecutor(baseURL: baseURL)
    let session = URLSession(configuration: .ephemeral)

    let health: Health = try await get(baseURL: baseURL, path: "/health")
    guard health.status == "ok" else {
      throw LLAMAServerExecutorError.badStatus(-1)
    }
    let reference = try await executor.complete(
      tokenPrefix: rootTokenPrefix, predictionTokens: 1, seed: seed
    )

    let childTokens = try await tokenize(baseURL: baseURL, content: longPrompt)
    var samples: [Sample] = []
    for cycle in 0..<cycles {
      let offFirst = cycle % 2 == 0
      let modes: [(String, Bool)] = offFirst
        ? [("off", false), ("swift_execution_state_on", true)]
        : [("swift_execution_state_on", true), ("off", false)]
      for (mode, usesState) in modes {
        samples.append(
          try await runCycle(
            index: cycle,
            mode: mode,
            usesState: usesState,
            host: host,
            port: port,
            baseURL: baseURL,
            session: session,
            executor: executor,
            reference: reference,
            rootTokenPrefix: rootTokenPrefix,
            childTokens: childTokens,
            longPrompt: longPrompt,
            cancelDelayMs: cancelDelayMs,
            predictionTokens: predictionTokens,
            freeTimeoutMs: freeTimeoutMs,
            seed: seed
          )
        )
      }
    }
    session.finishTasksAndInvalidate()

    let off = samples.filter({ $0.mode == "off" })
    let on = samples.filter({ $0.mode == "swift_execution_state_on" })
    var paired: [Double] = []
    for cycle in 0..<cycles {
      guard
        let offSample = samples.first(where: { $0.index == cycle && $0.mode == "off" }),
        let onSample = samples.first(where: {
          $0.index == cycle && $0.mode == "swift_execution_state_on"
        })
      else { continue }
      paired.append(onSample.recoveryClientMs - offSample.recoveryClientMs)
    }

    let checks = [
      Check(
        name: "OFF_CANCEL_AND_RECOVER",
        pass: off.allSatisfy({ $0.cancelAccepted && $0.semanticIdentical }),
        detail: "\(off.filter({ $0.cancelAccepted && $0.semanticIdentical }).count)/\(off.count)"
      ),
      Check(
        name: "SWIFT_EXECSTATE_CANCEL_ISOLATION",
        pass: on.allSatisfy({ $0.cancelAccepted && $0.semanticIdentical }),
        detail: "\(on.filter({ $0.cancelAccepted && $0.semanticIdentical }).count)/\(on.count)"
      ),
    ]
    let overallPass = checks.allSatisfy({ $0.pass })
    let summary = timingSummary
    return Report(
      status: overallPass ? "PASS" : "FAIL",
      protocolVersion: protocolVersion,
      boundary: boundary,
      host: host,
      port: port,
      longPrompt: longPrompt,
      rootTokenPrefix: rootTokenPrefix,
      cancelDelayMs: cancelDelayMs,
      predictionTokens: predictionTokens,
      reference: reference,
      checks: checks,
      samples: samples,
      deleteToFreeMs: [
        "off": summary(off.map({ $0.deleteToFreeMs })),
        "swiftExecutionStateOn": summary(on.map({ $0.deleteToFreeMs })),
      ],
      recoveryClientMs: [
        "off": summary(off.map({ $0.recoveryClientMs })),
        "swiftExecutionStateOn": summary(on.map({ $0.recoveryClientMs })),
      ],
      pairedOnMinusOffRecoveryMs: summary(paired),
      stateOperationMs: summary(on.map({ $0.stateOperationMs })),
      overallPass: overallPass
    )
  }

  private static func runCycle(
    index: Int,
    mode: String,
    usesState: Bool,
    host: String,
    port: Int,
    baseURL: URL,
    session: URLSession,
    executor: LLAMAServerExecutionStateExecutor,
    reference: LLAMAServerExecutionStateExecutor.Completion,
    rootTokenPrefix: [Int],
    childTokens: [Int],
    longPrompt: String,
    cancelDelayMs: Int,
    predictionTokens: Int,
    freeTimeoutMs: Int,
    seed: Int
  ) async throws -> Sample {
    let conversationId = "swift-rq3-cancel-\(mode)-\(index)-\(Int(Date().timeIntervalSince1970 * 1_000_000_000))"
    let backend = LLAMAServerExecutionStateBackend()
    let coordinator = ExecutionContinuityCoordinator(backend: backend)
    let root = try await coordinator.create(
      id: ExecutionID("cancel-root-\(mode)-\(index)"),
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: "", continuationID: "root-0")
    )
    let child = try await coordinator.create(
      id: ExecutionID("cancel-child-\(mode)-\(index)"),
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: "", continuationID: "child-0")
    )
    try await coordinator.bindRepresentation(
      executionID: root.id,
      position: ExecutionPosition(0),
      payload: LLAMAServerPrefixPayload(tokenPrefix: rootTokenPrefix)
    )
    try await coordinator.bindRepresentation(
      executionID: child.id,
      position: ExecutionPosition(0),
      payload: LLAMAServerPrefixPayload(tokenPrefix: childTokens)
    )

    var childSnapshot: ExecutionRepresentation?
    var stateOperationMs = 0.0
    if usesState {
      let rootStarted = DispatchTime.now().uptimeNanoseconds
      _ = try await backend.captureRepresentation(for: root)
      stateOperationMs += elapsedMs(rootStarted)
      let childStarted = DispatchTime.now().uptimeNanoseconds
      childSnapshot = try await backend.captureRepresentation(for: child)
      stateOperationMs += elapsedMs(childStarted)
    }

    _ = try await waitIdleSlot(baseURL: baseURL)
    let delayStarted = DispatchTime.now().uptimeNanoseconds
    let stream = CancellableStream(
      session: session,
      request: streamRequest(baseURL: baseURL, conversationId: conversationId, prompt: longPrompt, tokens: predictionTokens, seed: seed)
    )
    let remaining = Double(cancelDelayMs) / 1000 - elapsedMs(delayStarted) / 1000
    if remaining > 0 {
      try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }

    let deleteStarted = DispatchTime.now().uptimeNanoseconds
    let deleteStatus = try await deleteStream(baseURL: baseURL, conversationId: conversationId)
    _ = try await waitIdleSlot(baseURL: baseURL, timeoutMs: freeTimeoutMs)
    stream.close()
    let deleteToFreeMs = elapsedMs(deleteStarted)
    if usesState {
      let recoveryStarted = DispatchTime.now().uptimeNanoseconds
      let releaseStarted = DispatchTime.now().uptimeNanoseconds
      try await backend.releaseRepresentation(try unwrap(childSnapshot, mode: mode))
      stateOperationMs += elapsedMs(releaseStarted)
      let restoreStarted = DispatchTime.now().uptimeNanoseconds
      _ = try await coordinator.restore(
        root,
        request: ExecutionRestoreRequest(
          targetPosition: ExecutionPosition(0),
          continuation: ExecutionContinuation(nextInput: "", continuationID: "root-r")
        )
      )
      stateOperationMs += elapsedMs(restoreStarted)
      let captureStarted = DispatchTime.now().uptimeNanoseconds
      let restored = try await backend.captureRepresentation(for: root)
      stateOperationMs += elapsedMs(captureStarted)
      let recovery = try await executor.complete(restored, predictionTokens: 1, seed: seed)
      let recoveryClientMs = elapsedMs(recoveryStarted)
      return Sample(
        index: index,
        mode: mode,
        conversationId: conversationId,
        deleteStatus: deleteStatus,
        cancelAccepted: deleteStatus == 204,
        deleteToFreeMs: deleteToFreeMs,
        recoveryClientMs: recoveryClientMs,
        stateOperationMs: stateOperationMs,
        recoveryContent: recovery.content,
        recoveryTokens: recovery.tokens ?? [],
        semanticIdentical: recovery == reference
      )
    }

    let recoveryStarted = DispatchTime.now().uptimeNanoseconds
    let recovery = try await executor.complete(
      tokenPrefix: rootTokenPrefix, predictionTokens: 1, seed: seed
    )
    let recoveryClientMs = elapsedMs(recoveryStarted)
    return Sample(
      index: index,
      mode: mode,
      conversationId: conversationId,
      deleteStatus: deleteStatus,
      cancelAccepted: deleteStatus == 204,
      deleteToFreeMs: deleteToFreeMs,
      recoveryClientMs: recoveryClientMs,
      stateOperationMs: 0,
      recoveryContent: recovery.content,
      recoveryTokens: recovery.tokens ?? [],
      semanticIdentical: recovery == reference
    )
  }

  private static func streamRequest(
    baseURL: URL, conversationId: String, prompt: String, tokens: Int, seed: Int
  ) -> URLRequest {
    var request = URLRequest(url: baseURL.appending(path: "/v1/chat/completions"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(conversationId, forHTTPHeaderField: "X-Conversation-Id")
    request.timeoutInterval = 30
    request.httpBody = try? JSONEncoder().encode(
      ChatRequest(
        stream: true,
        maxTokens: tokens,
        temperature: 0,
        seed: seed,
        messages: [ChatMessage(role: "user", content: prompt)]
      )
    )
    return request
  }

  private static func deleteStream(baseURL: URL, conversationId: String) async throws -> Int {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.path = "/v1/stream"
    components.queryItems = [URLQueryItem(name: "conv_id", value: conversationId)]
    var request = URLRequest(url: components.url!)
    request.httpMethod = "DELETE"
    let (_, response) = try await URLSession.shared.data(for: request)
    return (response as? HTTPURLResponse)?.statusCode ?? -1
  }

  private static func waitIdleSlot(baseURL: URL, timeoutMs: Int = 1000) async throws -> Slot {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
    while Date() < deadline {
      let slots: [Slot] = try await get(baseURL: baseURL, path: "/slots")
      if !slots.isEmpty, slots.allSatisfy({ !$0.isProcessing }) {
        return slots[0]
      }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    throw LLAMAServerExecutorError.badStatus(-1)
  }

  private static func tokenize(baseURL: URL, content: String) async throws -> [Int] {
    struct Request: Encodable { let content: String }
    struct Response: Decodable { let tokens: [Int] }
    let response: Response = try await post(baseURL: baseURL, path: "/tokenize", body: Request(content: content))
    return response.tokens
  }

  private static func get<Result: Decodable>(baseURL: URL, path: String) async throws -> Result {
    let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: path))
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw LLAMAServerExecutorError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return try JSONDecoder().decode(Result.self, from: data)
  }

  private static func post<Body: Encodable, Result: Decodable>(
    baseURL: URL, path: String, body: Body
  ) async throws -> Result {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw LLAMAServerExecutorError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return try JSONDecoder().decode(Result.self, from: data)
  }

  private static func unwrap<Value>(_ value: Value?, mode: String) throws -> Value {
    guard let value else { throw LLAMAServerExecutorError.missingSample(index: -1, mode: mode) }
    return value
  }

  private static func elapsedMs(_ started: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e6
  }

  private static func timingSummary(_ values: [Double]) -> TimingSummary {
    let ordered = values.sorted()
    let median = ordered.isEmpty
      ? 0
      : (ordered.count % 2 == 1
        ? ordered[ordered.count / 2]
        : (ordered[ordered.count / 2 - 1] + ordered[ordered.count / 2]) / 2)
    return TimingSummary(
      n: values.count,
      meanMs: values.reduce(0, +) / Double(values.count),
      medianMs: median
    )
  }
}
