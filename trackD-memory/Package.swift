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
        .library(name: "CarrierInterface", targets: ["CarrierInterface"]),
        .library(name: "CContinuationSupport", targets: ["CContinuationSupport"]),
        .library(name: "CContinuationEvaluatorCore", targets: ["CContinuationEvaluatorCore"]),
        .executable(name: "CContinuationStudy", targets: ["CContinuationStudy"]),
        .executable(name: "CContinuationEvaluator", targets: ["CContinuationEvaluator"])
    ],
    targets: [
        .target(
            name: "InformationCore",
            path: "Sources/InformationCore"
        ),
        .target(
            name: "CarrierInterface",
            path: "Sources/CarrierInterface"
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
        .target(
            name: "CContinuationSupport",
            dependencies: ["InformationCore", "RelationCore"],
            path: "Sources/CContinuationSupport"
        ),
        .target(
            name: "CContinuationEvaluatorCore",
            dependencies: ["CContinuationSupport"],
            path: "Sources/CContinuationEvaluatorCore"
        ),
        .executableTarget(
            name: "CContinuationStudy",
            dependencies: [
                "CContinuationSupport",
                "ExecutionCore",
                "InformationCore",
                "RelationCore",
            ],
            path: "Sources/CContinuationStudy"
        ),
        .executableTarget(
            name: "CContinuationStudyContinue",
            dependencies: [
                "CContinuationSupport",
                "ExecutionCore",
                "InformationCore",
                "RelationCore",
            ],
            path: "Sources/CContinuationStudyContinue"
        ),
        .executableTarget(
            name: "CContinuationEvaluator",
            dependencies: ["CContinuationEvaluatorCore"],
            path: "Sources/CContinuationEvaluator"
        ),
        .testTarget(
            name: "ExecutionCoreTests",
            dependencies: ["ExecutionCore"],
            path: "Tests/ExecutionCoreTests"
        ),
        .testTarget(
            name: "CarrierInterfaceTests",
            dependencies: ["CarrierInterface"],
            path: "Tests/CarrierInterfaceTests"
        ),
        .testTarget(
            name: "CContinuationTests",
            dependencies: [
                "CContinuationSupport",
                "CContinuationEvaluatorCore",
                "ExecutionCore",
                "InformationCore",
                "RelationCore",
            ],
            path: "Tests/CContinuationTests"
        )
    ]
)
