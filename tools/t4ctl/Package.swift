// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "t4ctl",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../trackD-memory")],
    targets: [
        .executableTarget(
            name: "t4ctl",
            dependencies: [.product(name: "InformationCore", package: "trackD-memory")],
            path: "Sources/t4ctl"
        ),
        .testTarget(
            name: "t4ctlTests",
            dependencies: ["t4ctl", .product(name: "InformationCore", package: "trackD-memory")],
            path: "Tests/t4ctlTests"
        )
    ]
)
