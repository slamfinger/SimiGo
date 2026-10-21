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
        .executable(name: "ActualMLXSmokeChild", targets: ["ActualMLXSmokeChild"]),
        .executable(name: "EngineBaselineCrashChild", targets: ["EngineBaselineCrashChild"]),
        .executable(name: "MaterializationQuarantineCrashChild", targets: ["MaterializationQuarantineCrashChild"]),
        .executable(name: "ExecutionStateChaosChild", targets: ["ExecutionStateChaosChild"]),
        .executable(name: "SimiGo2App", targets: ["SimiGo2App"])
    ],
    dependencies: [
        // G3 native storage-identity accessor (MLXArray.mlxStorageIdentity) lives in
        // the Cmlx C++ interop boundary, published on slamfinger/mlx-swift branch
        // feature/g3-storage-identity at this exact revision. That commit carries the
        // mlx-c submodule gitlink pinned to 3fe6fa8 (the mlx_array_get_storage_identity
        // C accessor) on slamfinger/mlx-c, so a clean checkout resolves the whole
        // native chain reproducibly.
        .package(url: "https://github.com/slamfinger/mlx-swift", revision: "7ae48feb0b15fd5df5e542759f0a165759a3cd2a"),
        // The native KV-cache write-boundary observer (KVCacheWriteObserver) and its
        // binding capability live inside MLXLMCommon.KVCacheSimple.update, published on
        // slamfinger/mlx-swift-lm branch feature/g3-kv-write-observer at this exact
        // revision. That branch already aligns its transitive mlx-swift pin to the
        // same 7ae48fe above, so the graph resolves to one consistent mlx-swift
        // revision instead of clashing on two exact revisions of the same package.
        .package(url: "https://github.com/slamfinger/mlx-swift-lm.git", revision: "420fc503ae44e38a7f487d64cf7b602dc75cf258"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.3"),
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
            name: "ActualMLXSmokeChild",
            dependencies: [
                "SimiGo2Experimental",
                "SimiGoRuntimeContract",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .executableTarget(
            name: "SimiGo2App",
            dependencies: ["SimiGo2Experimental"]
        ),
        .executableTarget(
            name: "EngineBaselineCrashChild",
            dependencies: ["SimiGo2Experimental"]
        ),
        .executableTarget(
            name: "MaterializationQuarantineCrashChild",
            dependencies: ["SimiGo2Experimental"]
        ),
        .executableTarget(
            name: "ExecutionStateChaosChild",
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
