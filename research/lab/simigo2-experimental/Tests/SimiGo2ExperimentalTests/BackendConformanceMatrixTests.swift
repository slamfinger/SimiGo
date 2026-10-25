import SimiGoRuntimeContract
import XCTest

@testable import SimiGo2Experimental

/// RQ1 — Backend Conformance.
///
/// This is a contract harness, not a second runtime. It runs the same
/// capture/fork/diverge/restore/release/discard lifecycle through any prefix
/// representation strategy and asserts the Backend never redefines logical
/// identity, lineage, position, or continuation.
final class BackendConformanceMatrixTests: XCTestCase {
  private struct ForeignPayload: ExecutionRepresentationPayload {}

  private struct PrefixAdapter {
    let backend: any ExecutionStateBackend
    let makePayload: ([Int]) -> any ExecutionRepresentationPayload
    let prefix: (any ExecutionRepresentationPayload) throws -> [Int]
    let bind: (ExecutionID, ExecutionPosition, [Int]) async throws -> Void
    let boundPrefix: (ExecutionStateHandle) throws -> [Int]

    static func mlxPrefix() -> PrefixAdapter {
      let backend = MLXExecutionStateBackend()
      return PrefixAdapter(
        backend: backend,
        makePayload: { MLXPrefixPayload(tokenPrefix: $0) },
        prefix: { payload in
          guard let payload = payload as? MLXPrefixPayload else {
            throw ExecutionStateBackendError.foreignRepresentationPayload(
              ExecutionID("adapter")
            )
          }
          return payload.tokenPrefix
        },
        bind: { backend.bind(executionID: $0, position: $1, tokenPrefix: $2) },
        boundPrefix: { try backend.boundPrefix(for: $0).prefix }
      )
    }

    static func oversizedPrefix() -> PrefixAdapter {
      let backend = OversizedSegmentedStateBackend(releaseAll: {})
      return PrefixAdapter(
        backend: backend,
        makePayload: { OversizedPrefixPayload(tokenPrefix: $0) },
        prefix: { payload in
          guard let payload = payload as? OversizedPrefixPayload else {
            throw ExecutionStateBackendError.foreignRepresentationPayload(
              ExecutionID("adapter")
            )
          }
          return payload.tokenPrefix
        },
        bind: { backend.bind(executionID: $0, position: $1, prefix: $2) },
        boundPrefix: { try backend.boundPrefix(for: $0).prefix }
      )
    }
    static func llamaServerPrefix() -> PrefixAdapter {
      let backend = LLAMAServerExecutionStateBackend()
      return PrefixAdapter(
        backend: backend,
        makePayload: { LLAMAServerPrefixPayload(tokenPrefix: $0) },
        prefix: { payload in
          guard let payload = payload as? LLAMAServerPrefixPayload else {
            throw ExecutionStateBackendError.foreignRepresentationPayload(
              ExecutionID("adapter")
            )
          }
          return payload.tokenPrefix
        },
        bind: { backend.bind(executionID: $0, position: $1, tokenPrefix: $2) },
        boundPrefix: { try backend.boundPrefix(for: $0).prefix }
      )
    }
  }

  func testLLAMAServerPrefixConformance() async throws {
    try await runConformance(adapter: .llamaServerPrefix())
  }

  func testMLXPrefixRecomputeConformance() async throws {
    try await runConformance(adapter: .mlxPrefix())
  }

  func testOversizedSegmentedConformance() async throws {
    try await runConformance(adapter: .oversizedPrefix())
  }

  private func runConformance(adapter: PrefixAdapter) async throws {
    let runtime = ExecutionContinuityCoordinator(backend: adapter.backend)

    // W0/W2: parent checkpoint and physical fork.
    let parent = try await runtime.create(
      id: ExecutionID("parent"),
      position: ExecutionPosition(0),
      continuation: ExecutionContinuation(nextInput: "parent-0", continuationID: "p0")
    )
    try await runtime.bindRepresentation(
      executionID: parent.id,
      position: ExecutionPosition(0),
      payload: adapter.makePayload([1, 2, 3])
    )
    let parentCheckpoint = try await adapter.backend.captureRepresentation(for: parent)
    XCTAssertEqual(try adapter.prefix(parentCheckpoint.payload), [1, 2, 3])

    let child = try await runtime.fork(
      ExecutionForkRequest(
        parent: parent,
        childID: ExecutionID("child"),
        childPosition: ExecutionPosition(0),
        childContinuation: ExecutionContinuation(nextInput: "child-0", continuationID: "c0")
      )
    )
    XCTAssertEqual(child.lineage.root, parent.lineage.root)
    XCTAssertEqual(child.lineage.parent, parent.id)
    XCTAssertEqual(try adapter.boundPrefix(child), [1, 2, 3])

    // Divergent branches must not overwrite each other's representation.
    let childAdvanced = try await runtime.continueExecution(
      child,
      continuation: ExecutionContinuation(nextInput: "child-1", continuationID: "c1")
    )
    try await runtime.bindRepresentation(
      executionID: child.id,
      position: childAdvanced.position,
      payload: adapter.makePayload([1, 2, 3, 20])
    )
    XCTAssertEqual(try adapter.boundPrefix(childAdvanced), [1, 2, 3, 20])

    let parentAdvanced = try await runtime.continueExecution(
      parent,
      continuation: ExecutionContinuation(nextInput: "parent-1", continuationID: "p1")
    )
    try await runtime.bindRepresentation(
      executionID: parent.id,
      position: parentAdvanced.position,
      payload: adapter.makePayload([1, 2, 3, 10])
    )
    XCTAssertEqual(try adapter.boundPrefix(parentAdvanced), [1, 2, 3, 10])

    // A stale logical position cannot silently capture the newer binding.
    do {
      _ = try await adapter.backend.captureRepresentation(for: child)
      XCTFail("stale position capture must fail")
    } catch {
      XCTAssertEqual(
        error as? ExecutionStateBackendError,
        .representationPositionMismatch(
          executionID: child.id,
          bound: ExecutionPosition(1),
          logical: ExecutionPosition(0)
        )
      )
    }

    // Foreign payloads cannot enter the Backend's representation authority.
    do {
      try await runtime.bindRepresentation(
        executionID: parent.id,
        position: parentAdvanced.position,
        payload: ForeignPayload()
      )
      XCTFail("foreign payload bind must fail")
    } catch {
      XCTAssertEqual(
        error as? ExecutionStateBackendError,
        .foreignRepresentationPayload(parent.id)
      )
    }
    XCTAssertEqual(try adapter.boundPrefix(parentAdvanced), [1, 2, 3, 10])

    // Releasing a stale snapshot must not invalidate the live binding.
    let staleChildSnapshot = ExecutionRepresentation(
      executionID: child.id,
      position: ExecutionPosition(0),
      payload: adapter.makePayload([1, 2, 3])
    )
    let currentChildState = try XCTUnwrap(runtime.handle(child.id))
    let currentChild = try await adapter.backend.captureRepresentation(
      for: currentChildState
    )
    try await adapter.backend.releaseRepresentation(staleChildSnapshot)
    XCTAssertEqual(try adapter.boundPrefix(currentChildState), [1, 2, 3, 20])
    XCTAssertEqual(try adapter.prefix(currentChild.payload), [1, 2, 3, 20])

    // Release only removes the current physical binding; the captured
    // fork-point state remains restoreable.
    try await adapter.backend.releaseRepresentation(currentChild)
    do {
      _ = try await adapter.backend.captureRepresentation(for: child)
      XCTFail("released representation must not remain current")
    } catch {
      XCTAssertEqual(
        error as? ExecutionStateBackendError,
        .noBoundRepresentation(child.id)
      )
    }

    let restoredChild = try await runtime.restore(
      child,
      request: ExecutionRestoreRequest(
        targetPosition: ExecutionPosition(0),
        continuation: ExecutionContinuation(nextInput: "child-restore", continuationID: "cr")
      )
    )
    XCTAssertEqual(restoredChild.lifecycle, .restored)
    XCTAssertEqual(restoredChild.position, ExecutionPosition(0))
    XCTAssertEqual(try adapter.boundPrefix(restoredChild), [1, 2, 3])

    // Discard is child-local; the parent remains active and restoreable.
    try await runtime.discard(restoredChild)
    let parentAfterChild = try await runtime.restore(
      parent,
      request: ExecutionRestoreRequest(
        targetPosition: ExecutionPosition(1),
        continuation: ExecutionContinuation(nextInput: "parent-restore", continuationID: "pr")
      )
    )
    XCTAssertEqual(parentAfterChild.lifecycle, .restored)
    XCTAssertEqual(parentAfterChild.position, ExecutionPosition(1))
    XCTAssertEqual(try adapter.boundPrefix(parentAfterChild), [1, 2, 3, 10])
    XCTAssertEqual(parentAfterChild.id, parent.id)
    XCTAssertEqual(parentAfterChild.lineage, parent.lineage)
  }
}
