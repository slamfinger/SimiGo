// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "SimiGo2Experimental",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SimiGo2Experimental", targets: ["SimiGo2Experimental"]),
        .executable(name: "simigo2ctl", targets: ["simigo2ctl"])
    ],
    targets: [
        .target(name: "SimiGo2Experimental"),
        .executableTarget(
            name: "simigo2ctl",
            dependencies: ["SimiGo2Experimental"]
        ),
        .testTarget(
            name: "SimiGo2ExperimentalTests",
            dependencies: ["SimiGo2Experimental"]
        )
    ]
)
