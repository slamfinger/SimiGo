import XCTest
import Foundation

/// R0 Self-Test: proves the audit instrumentation itself is reliable.
/// No model inference — pure event recording and artifact verification.

final class ReplicationAuditSelfTest: XCTestCase {

  func testR0SelfTest() throws {
    // Step 1: Create context
    let context = AuditRunContext.create()
    XCTAssertFalse(context.runUUID.isEmpty, "runUUID must not be empty")
    XCTAssertFalse(context.gitCommit.isEmpty, "gitCommit must not be empty")

    // Step 2: Create artifact store
    let baseDir = URL(fileURLWithPath: FileManager.default.temporaryDirectory.path)
      .appendingPathComponent("r0-self-test", isDirectory: true)
    try? FileManager.default.removeItem(at: baseDir)
    let store = try AuditArtifactStore(context: context, baseDirectory: baseDir)

    // Step 3: Record events
    store.record("experiment_start", payload: ["test": "R0-self-test"])
    store.record("model_load_start")
    Thread.sleep(forTimeInterval: 0.1) // simulate work
    store.record("model_load_complete", payload: ["duration_ms": "100"])
    store.record("restore_start")
    Thread.sleep(forTimeInterval: 0.05)
    store.record("restore_complete", payload: ["position": "21"])
    store.record("generate_start")
    Thread.sleep(forTimeInterval: 0.05)
    store.record("generate_complete", payload: ["tokens": "24"])
    store.record("experiment_end", payload: ["verdict": "PASS"])

    // Step 4: Write summary
    try store.writeSummary([
      "test": "R0-self-test",
      "events_recorded": "8",
      "verdict": "PASS",
    ])

    // Step 5: Write hashes
    try store.writeHashes([
      "model": "N/A (self-test)",
      "checkpoint": "N/A (self-test)",
    ])

    // Step 6: Close
    store.finish()

    // Step 7: Verify
    let checks = try store.verify()

    print("=== R0 Audit Self-Test ===")
    print("runUUID: \(context.runUUID)")
    print("commit: \(context.gitCommit)")
    print("artifact path: \(store.directory.path)")
    print("")
    print("Checks:")

    let requiredChecks = [
      "unique_run", "metadata_exists", "events_exists",
      "events_readable", "events_same_uuid",
      "monotonic_ordering", "no_duplicate_events", "schema_valid",
    ]

    var allPassed = true
    for check in requiredChecks {
      let result = checks[check] ?? false
      let symbol = result ? "✓" : "✗"
      print("  [\(symbol)] \(check)")
      XCTAssertTrue(result, "R0 check failed: \(check)")
      if !result { allPassed = false }
    }

    // Step 8: Reload events and verify content
    let events = try store.readEvents()
    XCTAssertEqual(events.count, 8, "Expected 8 events, got \(events.count)")
    XCTAssertEqual(events.first?.event, "experiment_start")
    XCTAssertEqual(events.last?.event, "experiment_end")

    // Verify monotonic ordering
    let monos = events.map { $0.monotonicNs }
    for i in 1..<monos.count {
      XCTAssertLessThanOrEqual(monos[i - 1], monos[i], "Monotonic violation at event \(i)")
    }

    // Verify no duplicate event+timestamp pairs
    let keys = events.map { "\($0.event):\($0.monotonicNs)" }
    XCTAssertEqual(Set(keys).count, keys.count, "Duplicate events detected")

    print("")
    if allPassed {
      print("R0 Audit Self-Test: ALL CHECKS PASSED")
    } else {
      print("R0 Audit Self-Test: SOME CHECKS FAILED")
    }

    // Cleanup
    try? FileManager.default.removeItem(at: baseDir)
  }

  /// Verify directory collision detection
  func testR0DirectoryCollision() throws {
    let context = AuditRunContext.create()
    let baseDir = URL(fileURLWithPath: FileManager.default.temporaryDirectory.path)
      .appendingPathComponent("r0-collision-test", isDirectory: true)
    try? FileManager.default.removeItem(at: baseDir)

    // First creation should succeed
    let store1 = try AuditArtifactStore(context: context, baseDirectory: baseDir)
    store1.finish()

    // Second creation with same UUID should fail
    XCTAssertThrowsError(try AuditArtifactStore(context: context, baseDirectory: baseDir)) { error in
      guard case AuditArtifactStore.AuditStoreError.directoryExists = error else {
        XCTFail("Expected directoryExists error, got \(error)")
        return
      }
    }

    // Cleanup
    try? FileManager.default.removeItem(at: baseDir)
  }
}
