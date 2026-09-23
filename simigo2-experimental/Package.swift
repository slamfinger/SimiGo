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
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.6")),
        .package(path: "../../mlx-swift-lm")
    ],
    targets: [
        .target(
            name: "SimiGo2Experimental",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ]
        ),
        .executableTarget(
            name: "simigo2ctl",
            dependencies: [
                "SimiGo2Experimental",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ]
        ),
        .testTarget(
            name: "SimiGo2ExperimentalTests",
            dependencies: ["SimiGo2Experimental"]
        )
    ]
)
