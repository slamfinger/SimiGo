// swift-tools-version:5.9

import PackageDescription

/// Standalone LOCALB (Local Trust Domain B) signing and verification core.
///
/// Vendored from the research repository SimiGo-Lab, PR #10 branch
/// `codex/localb-signing-core-20261016` @ commit 5282b7c6.
///
/// Scope discipline (matches SimiGoRuntime's): this package contains ONLY the
/// LOCALB implementation files, their tests, and a minimal extracted I0 support
/// closure. The frozen Domain-A implementation (PersistentSRSRepresentation
/// writer/reader, SRSVALDecisionCore, the Domain-A trust anchor) is NOT part of
/// this package. The only dependency is swift-crypto, deliberately declared
/// here instead of arriving transitively through MLX-bearing packages.
let package = Package(
    name: "LOCALBCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LOCALBCore", targets: ["LOCALBCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "LOCALBCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "LOCALBCoreTests",
            dependencies: ["LOCALBCore"]
        )
    ]
)
