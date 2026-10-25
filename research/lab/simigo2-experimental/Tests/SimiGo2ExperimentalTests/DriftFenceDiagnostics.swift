import XCTest
@testable import SimiGo2Experimental

final class DriftFenceDiagnostics: XCTestCase {
    func testHFSnapshotFingerprintStabilityAndOverhead() throws {
        guard let snapshotPath = ProcessInfo.processInfo.environment["SIMIGO_HF_DRIFT_DIAG_MODEL_DIR"],
            !snapshotPath.isEmpty
        else {
            throw XCTSkip("set SIMIGO_HF_DRIFT_DIAG_MODEL_DIR to a local HF snapshot directory")
        }
        let dir = URL(fileURLWithPath: snapshotPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw XCTSkip("HF snapshot path from SIMIGO_HF_DRIFT_DIAG_MODEL_DIR is absent")
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
