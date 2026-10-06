// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ESCSPPrep",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "/Users/mr.simi/Documents/SimiGo-Lab/trackD-memory")
    ],
    targets: [
        .executableTarget(
            name: "ESCSPPrep",
            dependencies: [
                .product(name: "CarrierInterface", package: "trackD-memory"),
                .product(name: "CarrierSQLite", package: "trackD-memory")
            ],
            path: "Sources/ESCSPPrep"
        )
    ]
)
