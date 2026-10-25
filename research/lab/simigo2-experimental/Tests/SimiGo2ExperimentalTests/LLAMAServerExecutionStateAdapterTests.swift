import Foundation
import SimiGoRuntimeContract
import XCTest

@testable import SimiGo2Experimental

/// BACKEND-1 adapter engineering — targeted evidence battery (T1–T8 of the
/// adapter engineering audit, registration 2026-09-30).
///
/// The transport is a real URLSession driven through a URLProtocol stub so
/// failure, cancellation, and malformed-response paths are deterministic.
/// The live-server path is prior evidence (RQ1 live smoke) and is not
/// re-run here. Semantic expectations are the SAME set the cross-backend
/// conformance matrix uses — no second expectation set exists (T8).
final class LLAMAServerExecutionStateAdapterTests: XCTestCase {
  private enum StubError: Error { case releaseFailed }

  private struct ForeignPayload: ExecutionRepresentationPayload {}

  // MARK: - Deterministic transport stub

  final class StubLLAMAURLProtocol: URLProtocol {
    struct Route {
      var status: Int = 200
      var body: Data = Data()
      /// When set, startLoading blocks on this semaphore before responding
      /// (deterministic mid-flight cancellation window).
      var gate: DispatchSemaphore?

      init(status: Int = 200, body: Data = Data(), gate: DispatchSemaphore? = nil) {
        self.status = status
        self.body = body
        self.gate = gate
      }
    }

    private static let tableLock = NSLock()
    private static var routes: [String: Route] = [:]
    private static var gatedRequestCount = 0

    static func setRoutes(_ newRoutes: [String: Route]) {
      tableLock.lock()
      defer { tableLock.unlock() }
      routes = newRoutes
      gatedRequestCount = 0
    }

    static var gatedRequests: Int {
      tableLock.lock()
      defer { tableLock.unlock() }
      return gatedRequestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      let path = request.url?.path ?? ""
      let route = Self.route(for: path)
      if let gate = route?.gate {
        Self.noteGated()
        _ = gate.wait(timeout: .now() + 10)
      }
      let status = route?.status ?? 404
      let data = route?.body ?? Data()
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func route(for path: String) -> Route? {
      tableLock.lock()
      defer { tableLock.unlock() }
      return routes[path]
    }

    private static func noteGated() {
      tableLock.lock()
      defer { tableLock.unlock() }
      gatedRequestCount += 1
    }
  }

  // Fixed stub token identities: every tokenize returns [100, 101], every
  // healthy completion generates [200, 201].
  private static let userTokens: [Int] = [100, 101]
  private static let generatedTokens: [Int] = [200, 201]
  private static let advancedAfterOneTurn = [100, 101] + [100, 101] + [200, 201]

  // MARK: - Fixtures

  private func makeAdapter(routes: [String: StubLLAMAURLProtocol.Route])
    -> LLAMAServerExecutionStateAdapter
  {
    StubLLAMAURLProtocol.setRoutes(routes)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubLLAMAURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return LLAMAServerExecutionStateAdapter(
      config: LLAMAServerAdapterConfig(
        baseURL: URL(string: "http://stub.local")!, session: session))
  }

  private func healthyRoutes() -> [String: StubLLAMAURLProtocol.Route] {
    [
      "/props": .init(
        body: Data("{\"model_path\":\"stub/gguf/model\"}".utf8)),
      "/tokenize": .init(
        body: Data("{\"tokens\":[100,101]}".utf8)),
      "/completion": .init(
        body: Data("{\"content\":\"ok\",\"tokens\":[200,201]}".utf8)),
    ]
  }

  private func makeOpenAdapter(
    routes: [String: StubLLAMAURLProtocol.Route]? = nil
  ) async throws -> LLAMAServerExecutionStateAdapter {
    let adapter = makeAdapter(routes: routes ?? healthyRoutes())
    _ = try await adapter.open()
    return adapter
  }

  private func waitForGatedRequest(timeout: TimeInterval = 2) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if StubLLAMAURLProtocol.gatedRequests > 0 { return true }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return false
  }

  /// boundPrefix is a concrete-type method (not on the E3 protocol); the
  /// adapter's backend is statically the LLAMA backend type.
  private func boundPrefix(
    of handle: ExecutionStateHandle, on adapter: LLAMAServerExecutionStateAdapter
  ) throws -> [Int] {
    let backend = try XCTUnwrap(
      adapter.executionStateBackend as? LLAMAServerExecutionStateBackend)
    return try backend.boundPrefix(for: handle).prefix
  }

  // MARK: - Open gating (real transport handshake)

  func testOpenReportsModelIdentityAndGatesUse() async throws {
    let adapter = makeAdapter(routes: healthyRoutes())
    do {
      _ = try await adapter.continueTurn(id: ExecutionID("m"), userText: "x")
      XCTFail("use before open must fail")
    } catch {
      XCTAssertEqual(error as? LLAMAServerAdapterError, .adapterNotOpen)
    }
    let identity = try await adapter.open()
    XCTAssertEqual(identity, "stub/gguf/model")
    XCTAssertTrue(adapter.isOpen)
  }

  func testOpenServerFailureLeavesNoSemanticState() async throws {
    var routes = healthyRoutes()
    routes["/props"] = .init(status: 500)
    let adapter = makeAdapter(routes: routes)
    do {
      _ = try await adapter.open()
      XCTFail("open against a failing server must throw")
    } catch {
      XCTAssertEqual(error as? LLAMAServerAdapterError, .serverUnavailable(status: 500))
    }
    XCTAssertFalse(adapter.isOpen)
    XCTAssertNil(adapter.modelIdentity)
  }

  // MARK: - T1 Capture

  func testCapturePositionGuardsAtAdapterLevel() async throws {
    let adapter = try await makeOpenAdapter()
    let created = try await adapter.createExecution(
      id: ExecutionID("main"), text: "hello")
    let current = try await adapter.executionStateBackend.captureRepresentation(
      for: try XCTUnwrap(adapter.handle(for: created.id)))
    XCTAssertEqual(
      try XCTUnwrap(current.payload as? LLAMAServerPrefixPayload).tokenPrefix,
      Self.userTokens)

    // A stale logical position cannot capture the newer binding (the
    // continuation advanced the bound position to 1).
    let advanced = try await adapter.continueTurn(id: created.id, userText: "next")
    do {
      _ = try await adapter.executionStateBackend.captureRepresentation(for: created)
      XCTFail("stale position capture must fail")
    } catch {
      XCTAssertEqual(
        error as? ExecutionStateBackendError,
        .representationPositionMismatch(
          executionID: created.id,
          bound: ExecutionPosition(1),
          logical: ExecutionPosition(0)))
    }

    // An unknown execution has no bound representation.
    let unknown = ExecutionStateHandle(
      id: ExecutionID("ghost"),
      lineage: ExecutionLineage(root: ExecutionID("ghost")),
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: "x", continuationID: "x"),
      lifecycle: .active)
    do {
      _ = try await adapter.executionStateBackend.captureRepresentation(for: unknown)
      XCTFail("unbound capture must fail")
    } catch {
      XCTAssertEqual(
        error as? ExecutionStateBackendError, .noBoundRepresentation(unknown.id))
    }
    _ = advanced
  }

  // MARK: - T2 Derive (including direct-entry guards, M-2)

  func testDeriveForeignAndMispositionedFailClosedWithoutLogicalChild() async throws {
    let adapter = try await makeOpenAdapter()
    let parent = try await adapter.createExecution(
      id: ExecutionID("parent"), text: "hello")

    // Direct backend entry (M-2): the foreign-payload guard must hold on
    // the direct path, not only behind the coordinator.
    let foreign = ExecutionRepresentation(
      executionID: parent.id,
      position: parent.position,
      payload: ForeignPayload())
    let childProbe = ExecutionStateHandle(
      id: ExecutionID("child"),
      lineage: ExecutionLineage(root: parent.lineage.root, parent: parent.id),
      position: parent.position,
      continuation: parent.continuation,
      lifecycle: .active)
    do {
      _ = try await adapter.executionStateBackend.deriveRepresentation(
        from: foreign, for: childProbe)
      XCTFail("foreign derive must fail")
    } catch {
      XCTAssertEqual(
        error as? ExecutionStateBackendError,
        .foreignRepresentationPayload(childProbe.id))
    }

    // The position invariant must also hold on the direct path.
    let parentRep = try await adapter.executionStateBackend.captureRepresentation(
      for: parent)
    let mispositioned = ExecutionStateHandle(
      id: ExecutionID("child2"),
      lineage: ExecutionLineage(root: parent.lineage.root, parent: parent.id),
      position: ExecutionPosition(7),
      continuation: parent.continuation,
      lifecycle: .active)
    do {
      _ = try await adapter.executionStateBackend.deriveRepresentation(
        from: parentRep, for: mispositioned)
      XCTFail("mispositioned derive must fail")
    } catch {
      XCTAssertEqual(
        error as? ExecutionStateBackendError,
        .representationPositionMismatch(
          executionID: mispositioned.id,
          bound: parent.position,
          logical: ExecutionPosition(7)))
    }

    // Neither failed derive committed a logical child.
    XCTAssertNil(adapter.handle(for: ExecutionID("child")))
    XCTAssertNil(adapter.handle(for: ExecutionID("child2")))
  }

  // MARK: - T3 Restore

  func testRestoreToCapturedPositionContinuesFromRestoredPrefix() async throws {
    let adapter = try await makeOpenAdapter()
    let created = try await adapter.createExecution(
      id: ExecutionID("main"), text: "hello")
    _ = try await adapter.continueTurn(id: created.id, userText: "turn-one")

    let restored = try await adapter.restoreExecution(
      id: created.id, to: ExecutionPosition(0))
    XCTAssertEqual(restored.lifecycle, .restored)
    XCTAssertEqual(restored.position, ExecutionPosition(0))
    // The restored continuation is the one the Runtime recorded for that
    // position — the adapter does not invent semantic state.
    XCTAssertEqual(restored.continuation.nextInput, "hello")
    XCTAssertEqual(
      try self.boundPrefix(of: restored, on: adapter),
      Self.userTokens)

    // The next real turn continues from the restored prefix (end-to-end
    // semantic continuity across the restore).
    let advanced = try await adapter.continueTurn(id: created.id, userText: "after")
    XCTAssertEqual(advanced.position, ExecutionPosition(1))
    XCTAssertEqual(
      try self.boundPrefix(of: advanced, on: adapter),
      Self.advancedAfterOneTurn)
  }

  func testRestoreMissingRepresentationFailsClosedAndStateUnchanged() async throws {
    let adapter = try await makeOpenAdapter()
    let created = try await adapter.createExecution(
      id: ExecutionID("main"), text: "hello")
    _ = try await adapter.continueTurn(id: created.id, userText: "turn-one")

    do {
      _ = try await adapter.restoreExecution(id: created.id, to: ExecutionPosition(5))
      XCTFail("restore without a captured representation must fail")
    } catch {
      XCTAssertEqual(
        error as? ExecutionContinuityCoordinator.CoordinatorError,
        .noRepresentationAtPosition(
          executionID: created.id, position: ExecutionPosition(5)))
    }
    let unchanged = try XCTUnwrap(adapter.handle(for: created.id))
    XCTAssertEqual(unchanged.position, ExecutionPosition(1))
    // The failed restore never reached a semantic commit: the execution is
    // exactly as the last committed turn left it.
    XCTAssertEqual(unchanged.lifecycle, .active)
  }

  // MARK: - T4 Release

  func testStaleReleaseIsNoOpAndKeepsLiveBinding() async throws {
    let adapter = try await makeOpenAdapter()
    let created = try await adapter.createExecution(
      id: ExecutionID("main"), text: "hello")
    let staleSnapshot = try await adapter.executionStateBackend
      .captureRepresentation(for: created)
    _ = try await adapter.continueTurn(id: created.id, userText: "turn-one")

    // Releasing the stale position-0 snapshot must not invalidate the
    // live position-1 binding (FBC-001 invariant).
    try await adapter.executionStateBackend.releaseRepresentation(staleSnapshot)
    let live = try XCTUnwrap(adapter.handle(for: created.id))
    XCTAssertEqual(
      try self.boundPrefix(of: live, on: adapter),
      Self.advancedAfterOneTurn)
  }

  func testDiscardReleaseFailureIsRetryableWithLLAMAStrategy() async throws {
    // Contract-level failure atomicity with the LLAMA representation
    // strategy in the loop: a failing physical release must leave the
    // logical state resumable, and the retry must commit.
    let gate = ReleaseGate()
    let wrapper = FailingReleaseBackend(real: LLAMAServerExecutionStateBackend(), gate: gate)
    let runtime = ExecutionContinuityCoordinator(backend: wrapper)
    let handle = try await runtime.create(
      id: ExecutionID("main"),
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: "hello", continuationID: "turn-0"))
    try await runtime.bindRepresentation(
      executionID: handle.id,
      position: ExecutionPosition(0),
      payload: LLAMAServerPrefixPayload(tokenPrefix: [100, 101]))

    gate.failRelease = true
    do {
      try await runtime.discard(handle)
      XCTFail("discard must propagate a failed release")
    } catch {
      XCTAssertEqual(error as? StubError, .releaseFailed)
    }
    let unchanged = try XCTUnwrap(runtime.handle(handle.id))
    // The failed discard left the pre-discard state (attached, never
    // continued) fully resumable.
    XCTAssertEqual(unchanged.lifecycle, .attached)

    gate.failRelease = false
    try await runtime.discard(unchanged)
    XCTAssertEqual(
      try XCTUnwrap(runtime.handle(handle.id)).lifecycle, .discarded)
  }

  // MARK: - T5/T8 Lifecycle and semantic continuity

  func testFullLifecycleThroughAdapterPreservesRuntimeSemantics() async throws {
    let adapter = try await makeOpenAdapter()
    let created = try await adapter.createExecution(
      id: ExecutionID("main"), text: "hello")
    XCTAssertEqual(created.lifecycle, .attached)
    XCTAssertEqual(created.position, ExecutionPosition(0))

    let advanced = try await adapter.continueTurn(id: created.id, userText: "turn-one")
    XCTAssertEqual(advanced.position, ExecutionPosition(1))
    XCTAssertEqual(advanced.continuation.nextInput, "turn-one")
    XCTAssertEqual(advanced.lineage.root, ExecutionID("main"))
    XCTAssertNil(advanced.lineage.parent)

    let child = try await adapter.forkExecution(
      parentID: created.id, childID: ExecutionID("branch"))
    XCTAssertEqual(child.position, advanced.position)
    XCTAssertEqual(child.lineage.parent, ExecutionID("main"))
    XCTAssertEqual(child.lineage.root, advanced.lineage.root)
    XCTAssertEqual(child.lifecycle, .active)

    // Branch divergence must not move the parent.
    let childAdvanced = try await adapter.continueTurn(
      id: ExecutionID("branch"), userText: "child-turn")
    XCTAssertEqual(childAdvanced.position, ExecutionPosition(2))
    let parentAfterBranch = try XCTUnwrap(adapter.handle(for: created.id))
    XCTAssertEqual(parentAfterBranch.position, ExecutionPosition(1))

    let restored = try await adapter.restoreExecution(
      id: ExecutionID("branch"), to: ExecutionPosition(1))
    XCTAssertEqual(restored.lifecycle, .restored)
    XCTAssertEqual(restored.position, ExecutionPosition(1))

    let reattached = try await adapter.reattachExecution(id: ExecutionID("branch"))
    XCTAssertEqual(reattached.lifecycle, .active)
    XCTAssertEqual(reattached.position, ExecutionPosition(1))

    try await adapter.discardExecution(id: ExecutionID("branch"))
    XCTAssertEqual(
      try XCTUnwrap(adapter.handle(for: ExecutionID("branch"))).lifecycle,
      .discarded)

    // Discard is branch-local: the parent stays active and restorable.
    let parentRestored = try await adapter.restoreExecution(
      id: created.id, to: ExecutionPosition(0))
    XCTAssertEqual(parentRestored.lifecycle, .restored)
    XCTAssertEqual(parentRestored.id, created.id)
    XCTAssertEqual(parentRestored.lineage, created.lineage)
  }

  // MARK: - T6 Failure atomicity

  func testCreateTokenizeFailureCreatesNothing() async throws {
    var routes = healthyRoutes()
    routes["/tokenize"] = .init(status: 500)
    let adapter = try await makeOpenAdapter(routes: routes)
    do {
      _ = try await adapter.createExecution(id: ExecutionID("main"), text: "hello")
      XCTFail("tokenize failure must fail closed")
    } catch {
      XCTAssertEqual(error as? LLAMAServerExecutorError, .badStatus(500))
    }
    // Fail closed: no logical execution was committed by the failed create.
    XCTAssertNil(adapter.handle(for: ExecutionID("main")))
  }

  func testContinueTurnServerFailureLeavesStateUnchangedAndRetryable() async throws {
    var routes = healthyRoutes()
    routes["/completion"] = .init(status: 500)
    let adapter = try await makeOpenAdapter(routes: routes)
    let created = try await adapter.createExecution(
      id: ExecutionID("main"), text: "hello")

    do {
      _ = try await adapter.continueTurn(id: created.id, userText: "next")
      XCTFail("server failure must propagate")
    } catch {
      XCTAssertEqual(error as? LLAMAServerExecutorError, .badStatus(500))
    }
    let unchanged = try XCTUnwrap(adapter.handle(for: created.id))
    XCTAssertEqual(unchanged.position, ExecutionPosition(0))
    // The failed turn never committed: the execution is exactly as the
    // create left it (attached, position 0).
    XCTAssertEqual(unchanged.lifecycle, .attached)
    XCTAssertEqual(
      try self.boundPrefix(of: unchanged, on: adapter),
      Self.userTokens)

    // The failed turn consumed nothing: the retry advances exactly once.
    StubLLAMAURLProtocol.setRoutes(healthyRoutes())
    let retried = try await adapter.continueTurn(id: created.id, userText: "next")
    XCTAssertEqual(retried.position, ExecutionPosition(1))
    XCTAssertEqual(
      try self.boundPrefix(of: retried, on: adapter),
      Self.advancedAfterOneTurn)
  }

  func testContinueTurnMissingTokensFailsClosed() async throws {
    var routes = healthyRoutes()
    routes["/completion"] = .init(body: Data("{\"content\":\"ok\"}".utf8))
    let adapter = try await makeOpenAdapter(routes: routes)
    let created = try await adapter.createExecution(
      id: ExecutionID("main"), text: "hello")

    do {
      _ = try await adapter.continueTurn(id: created.id, userText: "next")
      XCTFail("missing completion tokens must fail closed")
    } catch {
      XCTAssertEqual(error as? LLAMAServerAdapterError, .missingCompletionTokens)
    }
    let unchanged = try XCTUnwrap(adapter.handle(for: created.id))
    XCTAssertEqual(unchanged.position, ExecutionPosition(0))
  }

  // MARK: - T7 Cancellation

  func testContinueTurnCancellationBeforeCommitLeavesStateUnchangedAndRetryable()
    async throws
  {
    let gate = DispatchSemaphore(value: 0)
    var routes = healthyRoutes()
    routes["/completion"] = .init(
      body: Data("{\"content\":\"ok\",\"tokens\":[200,201]}".utf8), gate: gate)
    let adapter = try await makeOpenAdapter(routes: routes)
    let created = try await adapter.createExecution(
      id: ExecutionID("main"), text: "hello")

    let task = Task {
      try await adapter.continueTurn(id: ExecutionID("main"), userText: "next")
    }
    // Best effort: exercise the mid-completion cancellation window when the
    // scheduling allows it. Atomicity holds on every interleaving.
    _ = await waitForGatedRequest()
    task.cancel()
    gate.signal()

    do {
      _ = try await task.value
      XCTFail("a cancelled turn must not commit")
    } catch {
      // CancellationError or URLError.cancelled — the type is transport's
      // business; the contract invariant is "no logical commit".
    }
    let unchanged = try XCTUnwrap(adapter.handle(for: created.id))
    XCTAssertEqual(unchanged.position, ExecutionPosition(0))
    // The cancelled turn never committed: the execution is exactly as the
    // create left it.
    XCTAssertEqual(unchanged.lifecycle, .attached)
    XCTAssertEqual(
      try self.boundPrefix(of: unchanged, on: adapter),
      Self.userTokens)

    // The cancelled turn consumed nothing: the retry advances exactly once.
    StubLLAMAURLProtocol.setRoutes(healthyRoutes())
    let retried = try await adapter.continueTurn(id: created.id, userText: "next")
    XCTAssertEqual(retried.position, ExecutionPosition(1))
  }

  // MARK: - T8 Cross-backend conformance is shared, not duplicated

  func testAdapterBackendIsTheConformanceMatrixBackendType() {
    // The adapter runs the SAME E3 backend type already covered by
    // BackendConformanceMatrixTests (3/3) — the conformance evidence is
    // shared, and the adapter adds no separate semantic expectation set.
    let adapter = LLAMAServerExecutionStateAdapter(
      config: LLAMAServerAdapterConfig(baseURL: URL(string: "http://stub.local")!))
    XCTAssertTrue(
      type(of: adapter.executionStateBackend) == LLAMAServerExecutionStateBackend.self)
  }

  // MARK: - Failure-injection helper (T4/T6 retryable discard)

  private final class ReleaseGate: @unchecked Sendable {
    let lock = NSLock()
    var failRelease = false
  }

  private struct FailingReleaseBackend: ExecutionStateBackend {
    let real: LLAMAServerExecutionStateBackend
    let gate: ReleaseGate

    func captureRepresentation(for state: ExecutionStateHandle) async throws
      -> ExecutionRepresentation
    {
      try await real.captureRepresentation(for: state)
    }

    func deriveRepresentation(
      from parent: ExecutionRepresentation, for child: ExecutionStateHandle
    ) async throws -> ExecutionRepresentation {
      try await real.deriveRepresentation(from: parent, for: child)
    }

    func restoreRepresentation(_ representation: ExecutionRepresentation) async throws {
      try await real.restoreRepresentation(representation)
    }

    func releaseRepresentation(_ representation: ExecutionRepresentation) async throws {
      if gate.failRelease {
        throw StubError.releaseFailed
      }
      try await real.releaseRepresentation(representation)
    }
  }
}
