import Foundation

/// Named concepts retained for the llama.cpp reference audit.
/// They are documentation-level mappings, not runtime claims.
public enum LlamaCppReferenceConcept: String, Sendable, CaseIterable {
    case gpuLayerCount = "n_gpu_layers"
    case layerSplit = "split_mode=layer"
    case memoryMap = "mmap"
    case lazyTensorRead = "lazy_mode"
    case tensorBufferOverride = "tensor_buft_override"
    case cpuMoEOffload = "CPU MoE / FFN offload"
}

public struct RuntimeReferenceMapping: Identifiable, Hashable, Sendable {
    public let id: String
    public let llamaCppConcept: LlamaCppReferenceConcept
    public let simiGo2Candidate: String
    public let status: String

    public static let all: [RuntimeReferenceMapping] = [
        RuntimeReferenceMapping(
            id: "gpu-layer-count",
            llamaCppConcept: .gpuLayerCount,
            simiGo2Candidate: "LayerPolicy resident group count",
            status: "REFERENCE_ONLY"
        ),
        RuntimeReferenceMapping(
            id: "layer-split",
            llamaCppConcept: .layerSplit,
            simiGo2Candidate: "SWITCH_MLP decoder-range groups",
            status: "REFERENCE_ONLY"
        ),
        RuntimeReferenceMapping(
            id: "mmap",
            llamaCppConcept: .memoryMap,
            simiGo2Candidate: "future RuntimeAdapter lazy tensor source",
            status: "NOT_IMPLEMENTED"
        ),
        RuntimeReferenceMapping(
            id: "lazy-tensor-read",
            llamaCppConcept: .lazyTensorRead,
            simiGo2Candidate: "future per-group materialization",
            status: "NOT_IMPLEMENTED"
        ),
        RuntimeReferenceMapping(
            id: "tensor-buffer-override",
            llamaCppConcept: .tensorBufferOverride,
            simiGo2Candidate: "future PlacementPolicy",
            status: "NOT_IMPLEMENTED"
        )
    ]
}
