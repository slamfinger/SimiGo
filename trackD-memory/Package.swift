// swift-tools-version:5.9
//
// Standalone mini-manifest for InformationCore (Backend Independence
// Gate 5(c) transition form): lets external consumers depend on
// InformationCore alone — zero MLX/LLM graph — while the full root
// SimiGoLab manifest remains the research monorepo entry point.
// Full (b2) standalone-package extraction stays a separately gated
// decision.

import PackageDescription

let package = Package(
    name: "InformationCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "InformationCore", targets: ["InformationCore"]),
        .executable(name: "CContinuationStudy", targets: ["CContinuationStudy"])
    ],
    targets: [
        .target(
            name: "InformationCore",
            path: "Sources/InformationCore"
        ),
        .target(
            name: "RelationCore",
            dependencies: ["InformationCore"],
            path: "Sources/RelationCore"
        ),
        .target(
            name: "ExecutionCore",
            dependencies: ["InformationCore", "RelationCore"],
            path: "Sources/ExecutionCore"
        ),
        .executableTarget(
            name: "CContinuationStudy",
            dependencies: ["InformationCore", "RelationCore"],
            path: "Sources/CContinuationStudy"
        ),
        .testTarget(
            name: "ExecutionCoreTests",
            dependencies: ["ExecutionCore"],
            path: "Tests/ExecutionCoreTests"
        )
    ]
)
