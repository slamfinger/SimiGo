import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXNN
import Tokenizers

public enum RepresentationCaptureRoute: String, Codable, Sendable {
    case directPublicAPI
    case isolatedInstrumentation
    case unavailable
}

public struct RepresentationCaptureReport: Codable, Equatable, Sendable {
    public let modelType: String
    public let observedModulePathCount: Int
    public let candidateLayerPaths: [String]
    public let stableObservationContract: Bool
    public let recommendedRoute: RepresentationCaptureRoute
    public let boundary: String

    init(
        modelType: String,
        observedModulePathCount: Int,
        candidateLayerPaths: [String],
        stableObservationContract: Bool,
        recommendedRoute: RepresentationCaptureRoute,
        boundary: String
    ) {
        self.modelType = modelType
        self.observedModulePathCount = observedModulePathCount
        self.candidateLayerPaths = candidateLayerPaths
        self.stableObservationContract = stableObservationContract
        self.recommendedRoute = recommendedRoute
        self.boundary = boundary
    }
}

public enum RepresentationCaptureAudit {
    public static func audit(modelDirectory: URL) async throws -> RepresentationCaptureReport {
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        return await container.perform { context in
            audit(model: context.model)
        }
    }

    /// Inspects the installed MLX module tree without invoking forward.
    ///
    /// This deliberately answers only whether the public API exposes a stable,
    /// layer-indexed observation contract. A discovered module path is not a
    /// representation and must not be treated as H_i(x).
    public static func audit(model: some MLXNN.Module) -> RepresentationCaptureReport {
        let paths = model.leafModules().flattened().map(\.0)
        let candidateLayerPaths = uniqueLayerPaths(in: paths)

        // The public LanguageModel contract exposes logits and KV-cache state,
        // not a generic decoder-layer return value. Module traversal cannot add
        // that forward contract, so no path found here is directly capturable.
        let route: RepresentationCaptureRoute = candidateLayerPaths.isEmpty
            ? .unavailable
            : .isolatedInstrumentation

        return RepresentationCaptureReport(
            modelType: String(describing: type(of: model)),
            observedModulePathCount: paths.count,
            candidateLayerPaths: candidateLayerPaths,
            stableObservationContract: false,
            recommendedRoute: route,
            boundary:
                "MODULE_INVENTORY_ONLY / NOT_ACTIVATION_CAPTURE / FORWARDS_SEMANTICS_UNCHANGED"
        )
    }

    static func uniqueLayerPaths(in modulePaths: [String]) -> [String] {
        var paths = Set<String>()

        for path in modulePaths {
            let components = path.split(separator: ".")
            guard let layersIndex = components.firstIndex(of: "layers"),
                layersIndex + 1 < components.count,
                Int(components[layersIndex + 1]) != nil
            else { continue }

            paths.insert(
                components[...(layersIndex + 1)]
                    .map(String.init)
                    .joined(separator: ".")
            )
        }

        return paths.sorted {
            let lhs = $0.split(separator: ".").compactMap { Int($0) }
            let rhs = $1.split(separator: ".").compactMap { Int($0) }
            return lhs.lexicographicallyPrecedes(rhs)
        }
    }
}
