// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "SimiGo2Experimental",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SimiGo2Experimental", targets: ["SimiGo2Experimental"]),
        .library(name: "SimiGoRuntimeContract", targets: ["SimiGoRuntimeContract"]),
        .executable(name: "simigo2ctl", targets: ["simigo2ctl"]),
        .executable(name: "SimiGo2App", targets: ["SimiGo2App"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.6")),
        // Public beta runtime fork (segment-execution APIs, Muse-Glimmer text
        // factory). Branch dep; the exact commit is pinned in
        // Package.resolved. Local live-edit alternative: temporarily switch
        // to .package(path: "../../mlx-swift-lm") with a sibling clone of
        // https://github.com/slamfinger/mlx-swift-lm on the same branch.
        .package(
            url: "https://github.com/slamfinger/mlx-swift-lm.git",
            branch: "release/v2.0-beta-ml"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.3"),
        .package(url: "https://github.com/apple/swift-collections.git", "1.1.4" ..< "1.2.0")
    ],
    targets: [
        .target(
            name: "SimiGoRuntimeContract"
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
    .executableTarget(
            name: "simigo2ctl",
            dependencies: [
                "SimiGo2Experimental",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "MLXNN", package: "mlx-swift")
            ]
        ),
        .executableTarget(
            name: "SimiGo2App",
            dependencies: ["SimiGo2Experimental"]
        ),
        .testTarget(
            name: "SimiGoRuntimeContractTests",
            dependencies: ["SimiGoRuntimeContract"]
        ),
        .testTarget(
            name: "SimiGo2ExperimentalTests",
            dependencies: ["SimiGo2Experimental", "SimiGoRuntimeContract"]
        )
    ]
)
