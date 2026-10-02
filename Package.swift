// swift-tools-version:5.9

import PackageDescription

/// Public SwiftPM entry point for the SimiGo runtime packages.
///
/// The research repository remains the source of truth; this root manifest
/// exposes only the two library products consumed by the public SimiGo app.
/// Experimental executables and research-only test targets intentionally stay
/// in `simigo2-experimental/Package.swift`.
let package = Package(
    name: "SimiGoLab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "InformationCore", targets: ["InformationCore"]),
        .library(name: "SimiGo2Experimental", targets: ["SimiGo2Experimental"]),
        .library(name: "SimiGoRuntimeContract", targets: ["SimiGoRuntimeContract"]),
    ],
    dependencies: [
        .package(url: "https://github.com/slamfinger/mlx-swift", revision: "ef5f1b6bb24e27922189316362f3057c64261704"),
        .package(url: "https://github.com/slamfinger/mlx-swift-lm.git", branch: "release/v2.0-beta-ml"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.3"),
    ],
    targets: [
        .target(
            name: "InformationCore",
            path: "trackD-memory/Sources/InformationCore"
        ),
        .target(
            name: "RelationCore",
            dependencies: ["InformationCore"],
            path: "trackD-memory/Sources/RelationCore"
        ),
        .executableTarget(
            name: "InformationIntegration",
            dependencies: ["InformationCore", "RelationCore"],
            path: "trackD-memory/Sources/InformationIntegration"
        ),
        .target(
            name: "SimiGoRuntimeContract",
            path: "simigo2-experimental/Sources/SimiGoRuntimeContract"
        ),
        .target(
            name: "SimiGo2Experimental",
            dependencies: [
                "SimiGoRuntimeContract",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "MLXNN", package: "mlx-swift")
            ],
            path: "simigo2-experimental/Sources/SimiGo2Experimental"
        ),
    ]
)
