// swift-tools-version:5.9
import PackageDescription

// P0 capability probe. This package is additive: it consumes
// `simigo2-experimental` as a path dependency and modifies nothing inside it.
// The backend requirements below repeat the path package's own requirements
// verbatim so SwiftPM resolves one graph, pinned by the copied Package.resolved.
let package = Package(
    name: "G2P0Probe",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../../../../../../simigo2-experimental"),
        .package(
            url: "https://github.com/slamfinger/mlx-swift",
            revision: "ef5f1b6bb24e27922189316362f3057c64261704"),
        .package(
            url: "https://github.com/slamfinger/mlx-swift-lm.git",
            branch: "release/v2.0-beta-ml"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.3"),
    ],
    targets: [
        .executableTarget(
            name: "G2P0Probe",
            dependencies: [
                .product(name: "SimiGo2Experimental", package: "simigo2-experimental"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        )
    ]
)
