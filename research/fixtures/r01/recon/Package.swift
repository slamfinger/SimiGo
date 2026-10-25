// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ESCSPRecon",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "/Users/mr.simi/Documents/SimiGo-Lab/trackD-memory")
    ],
    targets: [
        .executableTarget(
            name: "ESCSPRecon",
            dependencies: [
                .product(name: "CarrierInterface", package: "trackD-memory"),
                .product(name: "CarrierSQLite", package: "trackD-memory")
            ],
            path: "Sources/ESCSPRecon"
        )
    ]
)
