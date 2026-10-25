import Foundation

/// SimiGo 2.0 Runtime Backend/Materializer Contract — gate B1.
///
/// The bridge expressing WHAT the SimiGo Runtime needs from a compute
/// Backend. Pure Swift by construction: this target has no MLX dependency
/// in the package graph, and MUST NOT import MLX or any model-architecture
/// type. The contract never expresses HOW a model computes — tokenization,
/// generation, attention, and architecture interpretation stay on the
/// Backend side (Backend Boundary gate v1.0, §4).
///
///     SimiGo Runtime → Runtime Contract → Backend implementation → Compute
///
/// `MLX is the first Backend, not SimiGo's identity.`

/// Backend memory accounting snapshot used for the runtime reconciliation
/// invariant (INV-3: observedIdleBytes − (residentBytes + C_model) ∈ ε).
/// Field semantics mirror what a compute backend can report about its own
/// memory; the interpretation stays on the Runtime side.
public struct BackendMemoryObservation: Equatable, Hashable, Sendable {
    public let activeBytes: Int64
    public let cacheBytes: Int64
    public let peakBytes: Int64

    public init(activeBytes: Int64, cacheBytes: Int64, peakBytes: Int64) {
        self.activeBytes = activeBytes
        self.cacheBytes = cacheBytes
        self.peakBytes = peakBytes
    }
}

/// Materialization half of the contract: per-group, all-or-nothing
/// residency operations. The residency Controller depends on exactly this
/// surface and nothing else of the Backend.
///
/// Implementations wrap the validated load/release behavior of one concrete
/// compute backend. A group transfer is atomic at the contract level: the
/// method either returns (the group changed residency state) or throws
/// (residency state is unchanged for that group). The operations are async:
/// backend materialization is inherently serialized I/O plus compute-state
/// mutation (e.g. MLX `container.perform`), and the contract MUST NOT force
/// implementations to block threads.
public protocol ResidencyMaterializer: Sendable {
    /// Bring `groupID` into resident (materialized) state.
    func materialize(groupID: String) async throws

    /// Take `groupID` out of resident state. A thrown error means the group
    /// MUST be treated as still resident (contract R3.13).
    func release(groupID: String) async throws
}

/// Full backend surface: materialization plus the memory-accounting and
/// cache-hygiene operations the Runtime needs for the audit/reconciliation
/// boundary (INV-3) and for post-transition hygiene. The Controller itself
/// depends only on `ResidencyMaterializer`; the host and verification
/// layers use this extended surface.
public protocol RuntimeResidencyBackend: ResidencyMaterializer {
    /// Current backend memory accounting. MUST reflect the backend's own
    /// reported state without changing it (observation is passive).
    func memoryObservation() throws -> BackendMemoryObservation

    /// Release backend-reusable scratch/caches so that a memory observation
    /// reflects parameter residency rather than transient buffers. Called
    /// by the Runtime at transition boundaries, mirroring the validated
    /// research-harness hygiene.
    func purgeTransientCaches() throws
}
