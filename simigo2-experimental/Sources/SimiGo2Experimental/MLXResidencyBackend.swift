import Foundation
import MLX
import MLXLMCommon
import SimiGoRuntimeContract

/// L4-A: the first concrete Backend — wraps the already-validated MLX group
/// materialization/release behavior behind the Runtime Contract
/// (`RuntimeResidencyBackend`). The Controller never sees MLX: it holds this
/// type only through the `ResidencyMaterializer` surface.
///
/// Memory observation maps the backend's own reported accounting
/// (`Memory.snapshot()`) into the contract value type; interpretation
/// (C_model, ε) stays on the Runtime side. `purgeTransientCaches` mirrors
/// the validated `Memory.clearCache()` transition hygiene.
public final class MLXResidencyBackend: RuntimeResidencyBackend, @unchecked Sendable {
    public let inventory: LayerInventory
    private let container: ModelContainer

    public init(container: ModelContainer, inventory: LayerInventory) {
        self.container = container
        self.inventory = inventory
    }

    public func materialize(groupID: String) async throws {
        _ = try await MLXGroupResidencyBenchmark.loadGroups(
            container: container,
            inventory: inventory,
            groupIDs: [groupID]
        )
    }

    public func release(groupID: String) async throws {
        _ = try await MLXGroupResidencyBenchmark.releaseGroups(
            container: container,
            inventory: inventory,
            groupIDs: [groupID]
        )
    }

    public func memoryObservation() throws -> BackendMemoryObservation {
        let snapshot = Memory.snapshot()
        return BackendMemoryObservation(
            activeBytes: Int64(snapshot.activeMemory),
            cacheBytes: Int64(snapshot.cacheMemory),
            peakBytes: Int64(snapshot.peakMemory)
        )
    }

    public func purgeTransientCaches() {
        Memory.clearCache()
    }
}
