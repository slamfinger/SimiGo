// swift-tools-version:5.9

import PackageDescription

/// MLX-free package for the Qoder transcript collection bridge.
///
/// Kept out of SimiGoRuntime so `swift test` on the collector never compiles
/// the MLX research targets; that toolchain path has its own compiler issues
/// unrelated to this code.
let package = Package(
    name: "SimiGoCollection",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SimiGoCollection", targets: ["SimiGoCollection"])
    ],
    targets: [
        .target(name: "SimiGoCollection"),
        .testTarget(
            name: "SimiGoCollectionTests",
            dependencies: ["SimiGoCollection"]
        ),
    ]
)
