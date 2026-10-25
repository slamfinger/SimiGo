import XCTest
@testable import SimiGo2Experimental

/// Audit diagnostic (AUDIT-TOKENIZER-REVISION-IDENTITY-20261015, rev 3):
/// ASSERTING, env-gated, candidate-selecting. Documents the proven defect —
/// EngineModelIdentity sees nothing through HF snapshot symlinks — without
/// scanning models in regular test runs. The discrimination assertion is
/// deliberately inverted: proposal V1 (resolve symlinks in the identity)
/// must FLIP it.
final class TokenizerIdentityAuditDiagnostics: XCTestCase {
    /// SHA-256 of empty input — the constant both digest components
    /// collapse to when every candidate is skipped behind a symlink.
    private static let emptyInputSHA256 =
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    func testHFSnapshotIdentityCollapse() throws {
        // Gate: ONLY an unset variable skips. A SET variable that is
        // malformed (not exactly two paths) or points at a nonexistent
        // directory FAILS the test — a misconfigured audit run must
        // report, not silently skip.
        guard let raw = ProcessInfo.processInfo.environment[
            "SIMIGO_TOKENIZER_IDENTITY_AUDIT_DIRS"]
        else {
            throw XCTSkip(
                "set SIMIGO_TOKENIZER_IDENTITY_AUDIT_DIRS=<snapshotA>:<snapshotB>")
        }
        let paths = raw.split(separator: ":").map(String.init)
        guard paths.count == 2 else {
            XCTFail(
                "SIMIGO_TOKENIZER_IDENTITY_AUDIT_DIRS must contain exactly two colon-separated snapshot paths (got \(paths.count))")
            return
        }
        for path in paths where !FileManager.default.fileExists(atPath: path) {
            XCTFail("SIMIGO_TOKENIZER_IDENTITY_AUDIT_DIRS entry does not exist: \(path)")
            return
        }
        let a = URL(fileURLWithPath: paths[0], isDirectory: true)
        let b = URL(fileURLWithPath: paths[1], isDirectory: true)

        // Candidate-selected probe on BOTH snapshots: a weights entry is
        // REQUIRED — without one the root-cause assertion below would
        // silently not run while the empty-digest assertions could still
        // pass. The probe must also prove it is looking at the expected
        // HF-link scenario: the entry is a symlink whose resolved target
        // IS a regular file.
        for snapshot in [a, b] {
            let weightsEntry = try XCTUnwrap(
                FileManager.default.contentsOfDirectory(
                    at: snapshot, includingPropertiesForKeys: [])
                    .first { $0.lastPathComponent.hasSuffix(".safetensors") },
                "audit requires a .safetensors candidate in \(snapshot.path)")
            let entryValues = try weightsEntry.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            // The root cause, asserted: enumerator URLs report the LINK.
            XCTAssertEqual(entryValues.isRegularFile, false)
            XCTAssertEqual(entryValues.isSymbolicLink, true)
            let resolvedValues = try weightsEntry.resolvingSymlinksInPath()
                .resourceValues(forKeys: [.isRegularFileKey])
            XCTAssertEqual(resolvedValues.isRegularFile, true)
        }

        let identityA = EngineModelIdentity.compute(modelDirectory: a)
        let identityB = EngineModelIdentity.compute(modelDirectory: b)

        // The CURRENT defect, asserted (V1 must flip these):
        XCTAssertEqual(identityA.weights, Self.emptyInputSHA256)
        XCTAssertEqual(identityA.tokenizer, Self.emptyInputSHA256)
        XCTAssertEqual(identityB.weights, Self.emptyInputSHA256)
        XCTAssertEqual(identityB.tokenizer, Self.emptyInputSHA256)
        XCTAssertEqual(identityA.weights, identityB.weights)
        XCTAssertEqual(identityA.tokenizer, identityB.tokenizer)

        // Trivially stable while constant; V1 must re-check stability with
        // real content flowing in.
        let recomputed = EngineModelIdentity.compute(modelDirectory: a)
        XCTAssertEqual(recomputed.weights, identityA.weights)
        XCTAssertEqual(recomputed.tokenizer, identityA.tokenizer)
    }
}
