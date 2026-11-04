import Foundation

// FORK-3 structural implementation (SIMIGO17_FORK3_STRUCTURAL_CONTRACT,
// step 8 first cut): the Gate A/B contracts become real runtime types.
// Zero-MLX. The registry API takes NO artifact/store parameters — a
// fork is O(binding metadata) by construction (zero-checkpoint-copy is
// structural, not tested-in).
// 身份纪律（IDENT-1 F1/F6）：execution identity 与 runtime address 在此
// 均为不透明字符串； RepresentationRef 内不含任何执行身份（R-I3）。

/// Gate A — content/physical identity of one Representation
/// (immutable; deterministic; no Execution identity inside, R-I3).
public enum RepresentationKind: String, Sendable {
    case prefixSnapshot
    case checkpoint
    case residentKV
    case sharedCOW
}

public struct RepresentationRef: Equatable, Sendable {
    public let kind: RepresentationKind
    public let modelIdentity: String
    public let kvLayoutIdentity: String
    public let renderIdentity: String
    /// Chain hash over the address space's content stream.
    public let contentHash: UInt64
    /// The covered logical token-prefix boundary (NOT a session position).
    public let boundLength: Int
    public let backendIdentity: String

    public init(
        kind: RepresentationKind,
        modelIdentity: String,
        kvLayoutIdentity: String,
        renderIdentity: String,
        contentHash: UInt64,
        boundLength: Int,
        backendIdentity: String = "mlx"
    ) {
        precondition(boundLength > 0, "a Ref always covers a non-empty prefix")
        self.kind = kind
        self.modelIdentity = modelIdentity
        self.kvLayoutIdentity = kvLayoutIdentity
        self.renderIdentity = renderIdentity
        self.contentHash = contentHash
        self.boundLength = boundLength
        self.backendIdentity = backendIdentity
    }

    /// Canonical key (R-I1 deterministic derivation): every identity
    /// field, joined with a delimiter that cannot appear inside the
    /// components' normalized forms.
    public var key: String {
        [kind.rawValue, modelIdentity, kvLayoutIdentity, renderIdentity,
         backendIdentity, String(contentHash), String(boundLength)]
            .joined(separator: "\u{1f}")
    }
}

public enum BindingState: String, Sendable {
    case active
    case superseded
    case detached
}

/// Gate B — the Execution↔Representation relation row (append-only;
/// Binding is a RELATION, never a RepresentationRef attribute — B-I1).
public struct ExecutionRepresentationBinding: Equatable, Sendable {
    public let executionID: String
    public let runtimeAddress: String
    public let ref: RepresentationRef
    /// == ref.boundLength by construction (Gate A R-I5).
    public let boundPositionAtBind: Int
    /// Per-Execution monotonic (B-R3); a relation version, nothing else.
    public let generation: Int
    public let state: BindingState
    public let boundAt: Date
}

public enum BindingRegistryError: Error, Equatable {
    case noActiveBinding(executionID: String)
}

/// Gate B registry — the first REAL holder of multi-Execution bindings
/// over one RepresentationRef (F-I5's N=2 instance lives here).
/// Canonical key: ExecutionID. No AgentExecutionKey reverse index.
public final class ExecutionBindingRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [ExecutionRepresentationBinding] = []
    /// Per-Execution last generation (B-R3: scoped, monotonic).
    private var lastGeneration: [String: Int] = [:]

    public init() {}

    public func allRows() -> [ExecutionRepresentationBinding] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }

    /// Current binding of one Execution (B-R2): at most one ACTIVE row,
    /// selected by highest generation. max-generation is the RESOLUTION
    /// rule; the ≤1 guarantee is maintained by bind/rebind below.
    public func currentBinding(executionID: String) -> ExecutionRepresentationBinding? {
        lock.lock()
        defer { lock.unlock() }
        return rows.last {
            $0.executionID == executionID && $0.state == .active
        }
    }

    /// All ACTIVE bindings over one RepresentationRef (B-I5: Ref → N).
    public func activeBindings(ref: RepresentationRef) -> [ExecutionRepresentationBinding] {
        lock.lock()
        defer { lock.unlock() }
        return rows.filter { $0.ref == ref && $0.state == .active }
    }

    /// Create (or re-bind) an Execution's binding to a Representation.
    /// R-I5 by construction: boundPositionAtBind IS ref.boundLength.
    /// A pre-existing active row is superseded (B-I3/B-I4: append-only,
    /// rewind creates a new binding, never silently reuses the stale one).
    @discardableResult
    public func bind(
        executionID: String, runtimeAddress: String, ref: RepresentationRef,
        boundAt: Date = Date()
    ) -> ExecutionRepresentationBinding {
        lock.lock()
        defer { lock.unlock() }
        supersedeActiveLocked(executionID: executionID)
        let generation = (lastGeneration[executionID] ?? 0) + 1
        lastGeneration[executionID] = generation
        let binding = ExecutionRepresentationBinding(
            executionID: executionID, runtimeAddress: runtimeAddress, ref: ref,
            boundPositionAtBind: ref.boundLength, generation: generation,
            state: .active, boundAt: boundAt)
        rows.append(binding)
        return binding
    }

    /// Explicit detach operation (Gate C: detached is an OPERATION, never
    /// a resolution outcome). The row is retained, state = detached.
    @discardableResult
    public func detach(executionID: String) -> ExecutionRepresentationBinding? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = rows.lastIndex(where: {
            $0.executionID == executionID && $0.state == .active
        }) else { return nil }
        let detached = ExecutionRepresentationBinding(
            executionID: rows[index].executionID,
            runtimeAddress: rows[index].runtimeAddress,
            ref: rows[index].ref,
            boundPositionAtBind: rows[index].boundPositionAtBind,
            generation: rows[index].generation,
            state: .detached,
            boundAt: rows[index].boundAt)
        rows[index] = detached
        return detached
    }

    private func supersedeActiveLocked(executionID: String) {
        guard let index = rows.lastIndex(where: {
            $0.executionID == executionID && $0.state == .active
        }) else { return }
        let superseded = ExecutionRepresentationBinding(
            executionID: rows[index].executionID,
            runtimeAddress: rows[index].runtimeAddress,
            ref: rows[index].ref,
            boundPositionAtBind: rows[index].boundPositionAtBind,
            generation: rows[index].generation,
            state: .superseded,
            boundAt: rows[index].boundAt)
        rows[index] = superseded
    }
}

public extension ExecutionBindingRegistry {
    /// FORK-3 structural operation: create a Child Binding pointing at
    /// the SAME RepresentationRef as the Parent's active binding.
    /// F-I1 zero re-materialization at fork (the registry touches no
    /// artifact — it cannot: it has no store); F-I2 parent untouched;
    /// F-I3 child starts at the boundary; F-I5 the first realized N=2.
    @discardableResult
    func forkChildBinding(
        parentExecutionID: String, childExecutionID: String, childRuntimeAddress: String
    ) throws -> ExecutionRepresentationBinding {
        guard childExecutionID != parentExecutionID else {
            throw BindingRegistryError.noActiveBinding(executionID: parentExecutionID)
        }
        guard let parent = currentBinding(executionID: parentExecutionID),
            parent.state == .active
        else {
            throw BindingRegistryError.noActiveBinding(executionID: parentExecutionID)
        }
        return bind(
            executionID: childExecutionID, runtimeAddress: childRuntimeAddress,
            ref: parent.ref)
    }
}

/// Gate C four-state resolution (structural-level pure classifier; the
/// production resolver composes BindingRegistry + SessionRegistry +
/// artifact availability per the same truth table).
public enum ResolutionState: String, Sendable {
    case unbound
    case attachedLive
    case reattachable
    case rematerializationRequired

    /// RR-I1 total; detached is an OPERATION (an execution with a
    /// detached row resolves as unbound — Gate C).
    public static func classify(
        hasActiveBinding: Bool, liveMaterialization: Bool, artifactAvailable: Bool
    ) -> ResolutionState {
        if !hasActiveBinding { return .unbound }
        if liveMaterialization { return .attachedLive }
        if artifactAvailable { return .reattachable }
        return .rematerializationRequired
    }
}
