import XCTest
@testable import SimiGo2Experimental

/// FORK-3 step-8 structural battery (zero-MLX; NO artifact store in
/// scope at all — the registry API cannot touch artifacts, so
/// zero-checkpoint-copy is structural, not asserted-in-hindsight).
///
/// F3_PARENT_CHILD_BINDING wiring: real Parent Binding → Child Binding
/// pointing at the SAME RepresentationRef, with independent identities,
/// positions, and deltas.
private let fork3Ref = RepresentationRef(
    kind: .prefixSnapshot, modelIdentity: "qwen3-8b",
    kvLayoutIdentity: "fp-mlc4", renderIdentity: "think:0",
    contentHash: 0xdead_beef_cafe_1234, boundLength: 6200, backendIdentity: "mlx")

final class Fork3StructuralBattery: XCTestCase {
    /// Test 1 — ForkSharesSameRepresentationRef (+ F-I5 first N=2).
    func testForkSharesSameRepresentationRef() throws {
        let registry = ExecutionBindingRegistry()
        let parent = registry.bind(
            executionID: "exec-P", runtimeAddress: "agent/default/sess-P/main",
            ref: fork3Ref)
        let child = try registry.forkChildBinding(
            parentExecutionID: "exec-P", childExecutionID: "exec-C",
            childRuntimeAddress: "agent/default/sess-C/main")

        XCTAssertEqual(child.ref, parent.ref, "F-I1: same RepresentationRef")
        XCTAssertEqual(child.boundPositionAtBind, 6200, "F-I3: child starts at T")
        XCTAssertEqual(
            registry.activeBindings(ref: fork3Ref).count, 2,
            "F-I5: the first realized N=2 instance")
        XCTAssertEqual(parent.state, .active)
        XCTAssertEqual(child.state, .active)
    }

    /// Test 2 — ForkCreatesIndependentExecutionIdentity (+ F-I6).
    func testForkCreatesIndependentExecutionIdentity() throws {
        let registry = ExecutionBindingRegistry()
        _ = registry.bind(
            executionID: "exec-P", runtimeAddress: "agent/default/sess-P/main",
            ref: fork3Ref)
        let child = try registry.forkChildBinding(
            parentExecutionID: "exec-P", childExecutionID: "exec-C",
            childRuntimeAddress: "agent/default/sess-C/main")

        XCTAssertNotEqual(child.executionID, "exec-P", "F-I6: new canonical identity")
        XCTAssertNotEqual(
            child.runtimeAddress, "agent/default/sess-P/main", "B-R1: new runtime address")
        // Sharing exists ONLY at the Ref layer: the Ref itself carries no
        // execution identity (R-I3 is type-level — RepresentationRef has
        // no such field).
    }

    /// Test 3 — ForkDoesNotCopyCheckpoint. The registry has NO artifact /
    /// store / copy parameter anywhere in its API: a fork is O(binding
    /// metadata) by construction. Behavioral pin: forking at a huge
    /// boundary behaves identically to forking at a small one — no
    /// size-dependent work exists to observe.
    func testForkDoesNotCopyCheckpoint() throws {
        let registry = ExecutionBindingRegistry()
        let smallRef = RepresentationRef(
            kind: .prefixSnapshot, modelIdentity: "m", kvLayoutIdentity: "fp",
            renderIdentity: "r", contentHash: 111, boundLength: 512,
            backendIdentity: "mlx")
        let hugeRef = RepresentationRef(
            kind: .prefixSnapshot, modelIdentity: "m", kvLayoutIdentity: "fp",
            renderIdentity: "r", contentHash: 222, boundLength: 200_000,
            backendIdentity: "mlx")

        _ = registry.bind(executionID: "p1", runtimeAddress: "k1", ref: smallRef)
        let startSmall = Date()
        _ = try registry.forkChildBinding(
            parentExecutionID: "p1", childExecutionID: "c1",
            childRuntimeAddress: "agent/a/c1/main")
        let smallMillis = Date().timeIntervalSince(startSmall) * 1000

        _ = registry.bind(executionID: "p2", runtimeAddress: "k2", ref: hugeRef)
        let startHuge = Date()
        _ = try registry.forkChildBinding(
            parentExecutionID: "p2", childExecutionID: "c2",
            childRuntimeAddress: "agent/a/c2/main")
        let hugeMillis = Date().timeIntervalSince(startHuge) * 1000

        // Both forks are pure registry writes: no size-proportional work.
        XCTAssertLessThan(smallMillis, 50)
        XCTAssertLessThan(hugeMillis, 50)
        XCTAssertEqual(registry.activeBindings(ref: hugeRef).count, 2)
    }

    /// Test 4 — ChildForwardDoesNotMutateParent (+ F-I2/F-I4, B-I3).
    /// Child's own advance/export = a child REBIND to a new Ref; the
    /// parent's row is untouched; the child's old row is superseded —
    /// and note (F-I4 honored): position advance alone creates NO new
    /// Ref; the rebind here models the child's own EXPORT.
    func testChildAdvanceDoesNotMutateParent() throws {
        let registry = ExecutionBindingRegistry()
        _ = registry.bind(
            executionID: "exec-P", runtimeAddress: "agent/default/sess-P/main",
            ref: fork3Ref)
        _ = try registry.forkChildBinding(
            parentExecutionID: "exec-P", childExecutionID: "exec-C",
            childRuntimeAddress: "agent/default/sess-C/main")

        let parentBefore = registry.currentBinding(executionID: "exec-P")
        let rowsBefore = registry.allRows()

        // Child continues +ΔC and exports its advanced representation:
        // Ref C @ T+ΔC (T=6200, ΔC=300).
        let refC = RepresentationRef(
            kind: .prefixSnapshot, modelIdentity: fork3Ref.modelIdentity,
            kvLayoutIdentity: fork3Ref.kvLayoutIdentity,
            renderIdentity: fork3Ref.renderIdentity,
            contentHash: 0xfeed_face, boundLength: 6500,
            backendIdentity: fork3Ref.backendIdentity)
        _ = registry.bind(
            executionID: "exec-C", runtimeAddress: "agent/default/sess-C/main",
            ref: refC)

        // Parent: bit-identical binding, still active on Ref X.
        let parentAfter = registry.currentBinding(executionID: "exec-P")
        XCTAssertEqual(parentAfter, parentBefore, "F-I2: parent non-interference")
        XCTAssertEqual(parentAfter?.ref, fork3Ref)
        // Child: rebound to its own Ref (old child row superseded).
        XCTAssertEqual(
            registry.currentBinding(executionID: "exec-C")?.ref, refC)
        XCTAssertEqual(
            registry.currentBinding(executionID: "exec-C")?.generation, 2,
            "B-R3: per-Execution monotonic generation")
        // Append-only: a transition never rewrites its predecessor. Rebinding
        // therefore appends both the superseded row and its replacement.
        XCTAssertEqual(registry.allRows().count, rowsBefore.count + 2)
        XCTAssertEqual(
            registry.allRows().filter { $0.state == .superseded }.count, 1)
    }

    /// G-8: lifecycle transitions must preserve their predecessor instead of
    /// rewriting an existing relation row.
    func testDetachAndRebindAppendLifecycleTransitions() throws {
        let registry = ExecutionBindingRegistry()
        let first = registry.bind(
            executionID: "exec-A", runtimeAddress: "agent/default/sess-A/main",
            ref: fork3Ref)

        let detached = try XCTUnwrap(registry.detach(executionID: "exec-A"))
        XCTAssertEqual(detached.generation, first.generation)
        XCTAssertEqual(detached.state, .detached)
        XCTAssertNil(registry.currentBinding(executionID: "exec-A"))

        let replacementRef = RepresentationRef(
            kind: .prefixSnapshot, modelIdentity: fork3Ref.modelIdentity,
            kvLayoutIdentity: fork3Ref.kvLayoutIdentity,
            renderIdentity: fork3Ref.renderIdentity,
            contentHash: 0x6ead_beef, boundLength: 6400,
            backendIdentity: fork3Ref.backendIdentity)
        let replacement = registry.bind(
            executionID: "exec-A", runtimeAddress: "agent/default/sess-A/main",
            ref: replacementRef)

        let rows = registry.allRows()
        XCTAssertEqual(rows.count, 4, "active, detached, superseded, replacement active")
        XCTAssertEqual(rows[0], first)
        XCTAssertEqual(rows[1], detached)
        XCTAssertEqual(rows[2].state, .superseded)
        XCTAssertEqual(rows[2].generation, first.generation)
        XCTAssertEqual(rows[3], replacement)
        XCTAssertEqual(registry.currentBinding(executionID: "exec-A"), replacement)
        XCTAssertEqual(registry.activeBindings(ref: replacementRef).count, 1)
    }

    /// Test 5 — EvictionWithTwoBindings: FORK-3 + Gate D. Artifact
    /// eviction is a Representation AVAILABILITY change — Bindings stay
    /// active and each Execution resolves INDEPENDENTLY (D-R2; no fifth
    /// state).
    func testEvictionWithTwoBindingsResolvesIndependently() throws {
        let registry = ExecutionBindingRegistry()
        _ = registry.bind(
            executionID: "exec-P", runtimeAddress: "agent/default/sess-P/main",
            ref: fork3Ref)
        _ = try registry.forkChildBinding(
            parentExecutionID: "exec-P", childExecutionID: "exec-C",
            childRuntimeAddress: "agent/default/sess-C/main")
        let refX = fork3Ref

        func resolve(liveP: Bool, liveC: Bool, artifact: Bool)
            -> (ResolutionState, ResolutionState)
        {
            let pActive = registry.currentBinding(executionID: "exec-P") != nil
            let cActive = registry.currentBinding(executionID: "exec-C") != nil
            let p = ResolutionState.classify(
                hasActiveBinding: pActive, liveMaterialization: liveP,
                artifactAvailable: artifact)
            let c = ResolutionState.classify(
                hasActiveBinding: cActive, liveMaterialization: liveC,
                artifactAvailable: artifact)
            return (p, c)
        }

        // Artifact available — the review matrix's upper half.
        let r1 = resolve(liveP: true, liveC: true, artifact: true)
        XCTAssertEqual(r1.0, .attachedLive)
        XCTAssertEqual(r1.1, .attachedLive)
        let r2 = resolve(liveP: true, liveC: false, artifact: true)
        XCTAssertEqual(r2.0, .attachedLive)
        XCTAssertEqual(r2.1, .reattachable)

        // Artifact EVICTED — Bindings remain active (D-R1); each side
        // resolves independently (D-R2) per the Gate D acceptance matrix.
        let r3 = resolve(liveP: true, liveC: true, artifact: false)
        XCTAssertEqual(r3.0, .attachedLive)
        XCTAssertEqual(r3.1, .attachedLive,
                       "evicted artifact never mutates a LIVE holder")
        let r3b = resolve(liveP: true, liveC: false, artifact: false)
        XCTAssertEqual(r3b.0, .attachedLive)
        XCTAssertEqual(r3b.1, .rematerializationRequired,
                       "mixed: per-execution states diverge")
        let r4 = resolve(liveP: false, liveC: false, artifact: false)
        XCTAssertEqual(r4.0, .rematerializationRequired)
        XCTAssertEqual(r4.1, .rematerializationRequired)
        XCTAssertNotNil(registry.currentBinding(executionID: "exec-P"),
                        "D-R1: eviction never touches the binding")
        XCTAssertNotNil(registry.currentBinding(executionID: "exec-C"))
    }
}
