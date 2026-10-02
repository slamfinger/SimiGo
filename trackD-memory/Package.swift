// swift-tools-version:5.9

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
        .target(name: "InformationCore", path: "Sources/InformationCore"),
        .target(name: "RelationCore", dependencies: ["InformationCore"], path: "Sources/RelationCore"),
        .target(name: "ExecutionCore", dependencies: ["InformationCore", "RelationCore"], path: "Sources/ExecutionCore"),
        .executableTarget(name: "CContinuationStudy", dependencies: ["InformationCore", "RelationCore"], path: "Sources/CContinuationStudy"),
        .testTarget(name: "ExecutionCoreTests", dependencies: ["ExecutionCore"], path: "Tests/ExecutionCoreTests")
    ]
)
