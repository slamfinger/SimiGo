// swift-tools-version:5.9

import PackageDescription

/// Standalone runtime package consumed by the public SimiGo app.
///
/// This package intentionally contains only the Runtime Contract and the
/// Runtime/Backend implementation required to build the public app. Research
/// evidence, experiment executables, and research-only tests remain separate.
let package = Package(
    name: "SimiGoRuntime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SimiGo2Experimental", targets: ["SimiGo2Experimental"]),
        .library(name: "SimiGoRuntimeContract", targets: ["SimiGoRuntimeContract"]),
    ],
    dependencies: [
        .package(url: "https://github.com/slamfinger/mlx-swift", revision: "7cfb117f4dbda72f5b8c97a9e1393b729657030c"),
        .package(
            url: "https://github.com/slamfinger/mlx-swift-lm.git",
            revision: "86e0c63ce15793531b366ecd86f0691d68fcd7be"
        ),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.3"),
    ],
    targets: [
        .target(
            name: "SimiGoRuntimeContract",
            linkerSettings: [
                // ES/IS authoritative persistence uses the system SQLite3 (MLX-free).
                .linkedLibrary("sqlite3")
            ]
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
            ]
        ),
        .testTarget(
            name: "SimiGoRuntimeContractTests",
            dependencies: ["SimiGoRuntimeContract"]
        ),
        .testTarget(
            name: "SimiGo2ExperimentalTests",
            dependencies: ["SimiGo2Experimental"]
        ),
    ]
)
