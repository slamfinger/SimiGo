import Foundation
import MLX
import SimiGoRuntimeContract

/// Oversized segment materializer — the ResidencyMaterializer port for the
/// oversized engine (2026-09-26). Maps controller groupIDs ("layers-L-R")
/// onto the engine's per-unit materialize/release; the controller therefore
/// owns segment residency exactly as it does for fitting models (transfer
/// log + INV-1 log-replay equivalence over segments).
public final class OversizedSegmentMaterializer: RuntimeResidencyBackend, @unchecked Sendable {
    private let load: @Sendable (String) throws -> Void
    private let unload: @Sendable (String) throws -> Void
    private let observe: @Sendable () -> BackendMemoryObservation
    private let purge: @Sendable () -> Void

    init(
        load: @escaping @Sendable (String) throws -> Void,
        unload: @escaping @Sendable (String) throws -> Void,
        observe: @escaping @Sendable () -> BackendMemoryObservation,
        purge: @escaping @Sendable () -> Void
    ) {
        self.load = load
        self.unload = unload
        self.observe = observe
        self.purge = purge
    }

    public func materialize(groupID: String) async throws {
        try load(groupID)
    }

    public func release(groupID: String) async throws {
        try unload(groupID)
    }

    public func memoryObservation() throws -> BackendMemoryObservation {
        observe()
    }

    public func purgeTransientCaches() throws {
        purge()
    }
}
