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
        // Real-model ES -> IS -> fresh-ES handoff: stage A settles a model result
        // into IS and releases the carrier, stage C recovers a fresh ES in a new
        // process and continues with only the remaining model work.
        .executable(name: "RealModelHandoff", targets: ["RealModelHandoff"]),
        // Ordinary task entry: one process runs one task item through the
        // production continuation, which resolves and admits the item's
        // declared dependency settlements from IS before any generation. It
        // contains no handoff orchestration and receives no input text.
        .executable(name: "SimiGoTaskRun", targets: ["SimiGoTaskRun"]),
        // F round: native orchestration of the detached U1->U2 process and
        // execution-state boundary. Model-free and settlement-free: it only
        // owns subprocess lifecycle and evidence assembly.
        .executable(name: "SimiGoDetachedDriver", targets: ["SimiGoDetachedDriver"]),
        .executable(name: "EngineBaselineCrashChild", targets: ["EngineBaselineCrashChild"]),
        .executable(name: "MaterializationQuarantineCrashChild", targets: ["MaterializationQuarantineCrashChild"]),
        .executable(name: "ExecutionStateChaosChild", targets: ["ExecutionStateChaosChild"]),
        .executable(name: "g3-swift-isolation-entry", targets: ["G3SwiftIsolationEntry"]),
        // G6/G7b: the real D1 worker and supervisor. Both are contract-only
        // (SimiGoRuntimeContract), so they cannot reach the ungated executor
        // surface (SimiGo2Experimental) and are model-free: the isolation gate
        // refuses under the empty trust registry before any model call or
        // binding consumption (G8a). Their identity is bound by G3_EXPECT_EXEC_SHA256.
        .executable(name: "G3D1Worker", targets: ["G3D1Worker"]),
        .executable(name: "G3D1Supervisor", targets: ["G3D1Supervisor"]),
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
            name: "RealModelHandoff",
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
            name: "SimiGoTaskRun",
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
            name: "SimiGoDetachedDriver",
            dependencies: []
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
        // Native G3 isolation-gate control point, invoked by the Python research
        // harness. MLX-free and model-free: it only exercises the gate's control
        // flow (attestation -> requireIsolation -> generation), so the boundary
        // is callable and testable without loading a model or the MLX runtime.
        .executableTarget(
            name: "G3SwiftIsolationEntry",
            dependencies: ["SimiGoRuntimeContract"]
        ),
        // G3D1WorkerCore: the shared, contract-only logic for the D1 worker and
        // supervisor (identity self-check, one-shot authorization, model-free
        // gated dual-arm control flow, auditable records). It MUST NOT depend on
        // SimiGo2Experimental — that is the G8b-A boundary the manifest checks.
        .target(
            name: "G3D1WorkerCore",
            dependencies: ["SimiGoRuntimeContract"]
        ),
        .executableTarget(
            name: "G3D1Worker",
            dependencies: ["G3D1WorkerCore", "SimiGoRuntimeContract"]
        ),
        .executableTarget(
            name: "G3D1Supervisor",
            dependencies: ["G3D1WorkerCore", "SimiGoRuntimeContract"]
        ),
        .testTarget(
            name: "G3D1SupervisorTests",
            dependencies: ["G3D1WorkerCore", "SimiGoRuntimeContract"]
        ),
        .testTarget(
            name: "SimiGoRuntimeContractTests",
            dependencies: ["SimiGoRuntimeContract"]
        ),
        .testTarget(
            name: "SimiGo2ExperimentalTests",
            dependencies: [
                "SimiGo2Experimental", "SimiGoRuntimeContract",
                .product(name: "MLX", package: "mlx-swift"),
                // The real KV cache under test (KVCacheSimple.update) lives in
                // MLXLMCommon; linking it lets the during-generation allocation
                // gateway be exercised against the genuine cache lifecycle without
                // loading a model.
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ]
        )
    ]
)
