import XCTest
@testable import SimiGo2Experimental

final class DriftFenceDiagnostics: XCTestCase {
    func testHFSnapshotFingerprintStabilityAndOverhead() throws {
        let dir = URL(fileURLWithPath:
            "/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d",
            isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw XCTSkip("local HF snapshot not present")
        }
        // Are the entries symlinks (HF convention)?
        let entries = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey])
        let symlinkCount = entries.filter {
            (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        }.count
        print("DIAG entries=\(entries.count) symlinks=\(symlinkCount)")

        let a = MLXPrefixCrossSessionCache.modelDirectoryRevision(modelDirectory: dir)
        let b = MLXPrefixCrossSessionCache.modelDirectoryRevision(modelDirectory: dir)
        XCTAssertEqual(a, b)
        XCTAssertNotNil(a)
        print("DIAG fingerprint=\(a?.prefix(16) ?? "nil")… stable=\(a == b)")

        // Per-lookup overhead: 200 collections.
        let clock = ContinuousClock()
        let start = clock.now
        var acc = 0
        for _ in 0..<200 {
            acc &+= MLXPrefixCrossSessionCache.modelDirectoryRevision(modelDirectory: dir)?.count ?? 0
        }
        let total = clock.now - start
        let seconds = Double(total.components.seconds)
            + Double(total.components.attoseconds) / 1e18
        print(String(format: "DIAG 200 collections = %.1f ms total, %.3f ms each (acc=%d)", seconds * 1000, seconds * 1000 / 200, acc))
    }
}
