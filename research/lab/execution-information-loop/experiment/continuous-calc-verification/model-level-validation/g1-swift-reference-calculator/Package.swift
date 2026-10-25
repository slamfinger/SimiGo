// swift-tools-version: 5.9
import PackageDescription

// Test-only oracle for SIMIGO-REFERENCE-CALCULATOR-V1 (G1.1).
//
// Deliberately standalone: it must not depend on simigo2-experimental, and adding
// it must not change any existing package manifest. See SWIFT_CALCULATOR_BRIDGE_SPIKE.md
// (G1.0) for why no existing Swift target can serve as the frozen calculator.
let package = Package(
    name: "SwiftReferenceCalculator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SwiftReferenceCalculator",
            path: "Sources/SwiftReferenceCalculator"
        )
    ]
)
