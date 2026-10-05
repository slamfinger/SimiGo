// swift-tools-version:5.9

import PackageDescription

// SimiGo-shaped pre-research (3.1(c) + 3.2(i)).
//
// A separate SwiftPM package consuming InformationCore via a real PATH
// dependency — proving a genuine external module/protocol dependency,
// not a copied pseudo-integration. This mirrors the shape a future
// SimiGoRuntime integration would take, without touching the SimiGo
// main repo.
let package = Package(
    name: "SimiGoShapedPreResearch",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "SimiGoShapedExecutor",
            dependencies: [
                .product(name: "InformationCore", package: "SimiGo-Lab")
            ],
            path: "Sources/SimiGoShapedExecutor"
        )
    ]
)
