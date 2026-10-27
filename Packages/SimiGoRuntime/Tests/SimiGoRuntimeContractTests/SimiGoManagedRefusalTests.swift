import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// C-10d proof: every internal refusal cause maps into a closed external
/// discipline, and the failure audit is an append-only immutable record.
final class SimiGoManagedRefusalTests: XCTestCase {
    private typealias Refusal = SimiGoManagedRefusal
    private typealias Audit = SimiGoFailureAudit

    private let entries: [Refusal.Entry] = [.managedContinuation, .settlementConsumption]

    private func refusal(_ cause: Refusal.Cause, phase: Refusal.Phase = .p2,
                         origin: Refusal.Origin = .snapshot) -> Refusal.Refusal {
        Refusal.Refusal(cause: cause, origin: origin, phase: phase)
    }

    // MARK: - Closed external mapping

    func testEveryCauseMapsIntoTheClosedAllowlist() {
        for entry in entries {
            for cause in Refusal.Cause.allCases {
                let external = Refusal.external(refusal(cause), entry: entry)
                XCTAssertTrue([400, 422, 503].contains(external.status),
                              "\(cause) produced unexpected status \(external.status)")
                if let code = external.reasonCode {
                    XCTAssertTrue(Refusal.isPubliclyExposed(code),
                                  "\(cause) leaked non-allowlisted code \(code)")
                }
                if external.status == 400 {
                    XCTAssertEqual(external.errorKind, Refusal.invalidRequestEntryKind)
                } else {
                    XCTAssertEqual(external.errorKind, entry.rawValue)
                }
            }
        }
    }

    func testOnlyFourPublicReasonCodesExist() {
        XCTAssertEqual(Refusal.publiclyExposedReasonCodes, [
            "recompute_policy_invalid",
            "recompute_policy_conflict",
            "snapshot_unrepresentable",
            "idempotency_conflict"
        ])
        let coded = Refusal.Cause.allCases
            .map { Refusal.external(refusal($0), entry: .managedContinuation).reasonCode }
            .compactMap { $0 }
        XCTAssertEqual(Set(coded), Refusal.publiclyExposedReasonCodes)
    }

    func testRecomputePolicyCausesAreRequestFormatErrors() {
        let invalid = Refusal.external(
            refusal(.recomputePolicyInvalid, phase: .pre, origin: .request),
            entry: .managedContinuation)
        XCTAssertEqual(invalid.status, 400)
        XCTAssertEqual(invalid.errorKind, "INVALID_REQUEST_ENTRY")
        XCTAssertEqual(invalid.reasonCode, "recompute_policy_invalid")

        let conflict = Refusal.external(
            refusal(.recomputePolicyConflict, phase: .pre, origin: .request),
            entry: .settlementConsumption)
        XCTAssertEqual(conflict.status, 400)
        XCTAssertEqual(conflict.errorKind, "INVALID_REQUEST_ENTRY")
        XCTAssertEqual(conflict.reasonCode, "recompute_policy_conflict")
    }

    func testInternalSnapshotCausesNeverBecomePublicCodes() {
        let internalCauses: [Refusal.Cause] = [
            .invalidAnchor, .noSettlement, .unknownSettlement, .legacyMigrated,
            .digestMismatch, .invalidatedCauseUnknown, .dependencyMissing,
            .dependencyInvalid, .identityNonconformance, .refusalCauseUnconfirmed,
            .snapshotRootUnavailable, .snapshotUnstable, .snapshotSourceMissing,
            .snapshotSourceUnreadable, .snapshotInconsistent,
            .snapshotUsedUndeclared, .snapshotUsedMismatch
        ]
        for entry in entries {
            for cause in internalCauses {
                let external = Refusal.external(refusal(cause), entry: entry)
                XCTAssertNil(external.reasonCode, "\(cause) must not expose a reason code")
                XCTAssertEqual(external.status, 422)
                XCTAssertEqual(external.errorKind, entry.rawValue)
            }
        }
    }

    /// Ruling O1: a post-model `used` violation is a snapshot-contract violation,
    /// not a request-format error and not a generic "model execution failed".
    func testPostModelUsedViolationIsNotFormattedAsRequestError() {
        for cause in [Refusal.Cause.snapshotUsedUndeclared, .snapshotUsedMismatch] {
            for entry in entries {
                let external = Refusal.external(
                    refusal(cause, phase: .p2, origin: .snapshot), entry: entry)
                XCTAssertNotEqual(external.status, 400)
                XCTAssertNotEqual(external.errorKind, Refusal.invalidRequestEntryKind)
                XCTAssertEqual(external.status, 422)
            }
        }
    }

    func testAuthorityUnavailableStaysA503() {
        let external = Refusal.external(
            refusal(.authorityUnavailable, phase: .p1, origin: .admission),
            entry: .managedContinuation)
        XCTAssertEqual(external.status, 503)
        XCTAssertNil(external.reasonCode)
    }

    func testSanitizedReasonCodeDropsUnknownCodes() {
        XCTAssertEqual(Refusal.sanitizedReasonCode("snapshot_unrepresentable"),
                       "snapshot_unrepresentable")
        XCTAssertNil(Refusal.sanitizedReasonCode("snapshot_used_undeclared"))
        XCTAssertNil(Refusal.sanitizedReasonCode("internal_error"))
        XCTAssertNil(Refusal.sanitizedReasonCode(nil))
    }

    // MARK: - Audit record encoding

    private func event(executionID: String = "exec-1", attempt: Int = 1,
                       detail: String = "first attempt") -> Audit.Event {
        Audit.Event(
            executionID: executionID, attempt: attempt, phase: .p2,
            cause: .snapshotUsedMismatch, origin: .snapshot,
            evidence: ["declared_snapshot": "a", "used_item": "b"],
            modelCalls: 1, settlementsWritten: 0,
            recordedAt: Date(timeIntervalSince1970: 1_790_000_000), detail: detail)
    }

    func testAuditRoundTripsByteIdentically() throws {
        let original = event()
        let data = try Audit.encoded(original)
        let decoded = try Audit.decode(data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(try Audit.encoded(decoded), data)
        XCTAssertEqual(decoded.modelCalls, 1)
        XCTAssertEqual(decoded.settlementsWritten, 0)
    }

    func testAuditDecodeRejectsUnknownSchemaAndMissingFields() throws {
        let data = try Audit.encoded(event())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        object["schema_version"] = "c-failure-audit-v2"
        XCTAssertThrowsError(try Audit.decode(
            JSONSerialization.data(withJSONObject: object)))

        object["schema_version"] = Audit.schemaVersion
        object.removeValue(forKey: "model_calls")
        XCTAssertThrowsError(try Audit.decode(
            JSONSerialization.data(withJSONObject: object)))
    }

    func testAuditIdentityCannotCollideWithExistingPrefixes() {
        XCTAssertEqual(Audit.identity(executionID: "abc"), "c-failure-audit:abc")
        for existing in ["file:", "chat:", "demand:", "settlement:", "settlement-summary:"] {
            XCTAssertFalse(Audit.indexPrefix.hasPrefix(existing))
        }
    }

    // MARK: - Append-only storage

    private func makeDatabase(_ name: String) throws -> (SimiGoESISDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-audit-\(UUID().uuidString)-\(name).sqlite3")
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        return (db, url)
    }

    func testAuditWritePersistsOneImmutableRecord() throws {
        let (db, _) = try makeDatabase("persist")
        let original = event()

        let result = db.recordFailureAudit(original)
        XCTAssertTrue(result.auditPersisted)
        XCTAssertEqual(result.failureClass, nil)
        let objectID = try XCTUnwrap(result.objectID)
        XCTAssertEqual(objectID.count, 64)
        XCTAssertTrue(db.verifyObject(objectID))

        XCTAssertEqual(db.failureAudit(executionID: "exec-1"), original)
        XCTAssertEqual(try db.failureAuditHistory(executionID: "exec-1").count, 1)
    }

    func testSecondAuditForSameExecutionNeverOverwritesHistory() throws {
        let (db, _) = try makeDatabase("duplicate")
        let first = event(attempt: 1, detail: "first attempt")
        XCTAssertTrue(db.recordFailureAudit(first).auditPersisted)

        let second = event(attempt: 2, detail: "second attempt")
        let result = db.recordFailureAudit(second)
        XCTAssertFalse(result.auditPersisted)
        XCTAssertNil(result.objectID)
        XCTAssertEqual(result.failureClass, "duplicate_execution_id")

        let history = try db.failureAuditHistory(executionID: "exec-1")
        XCTAssertEqual(history.count, 1, "the ledger must not gain a second entry")
        XCTAssertEqual(db.failureAudit(executionID: "exec-1"), first,
                       "the first terminal record is still the one on file")
        XCTAssertFalse(db.verifyObject(SimiGoSnapshotContract.sha256Hex(try Audit.encoded(second))),
                       "a rejected duplicate must not leave an orphan object")
    }

    func testAuditsForDistinctExecutionsAreIndependent() throws {
        let (db, _) = try makeDatabase("distinct")
        XCTAssertTrue(db.recordFailureAudit(event(executionID: "exec-a")).auditPersisted)
        XCTAssertTrue(db.recordFailureAudit(event(executionID: "exec-b")).auditPersisted)

        XCTAssertEqual(try db.failureAuditHistory(executionID: "exec-a").count, 1)
        XCTAssertEqual(try db.failureAuditHistory(executionID: "exec-b").count, 1)
        XCTAssertEqual(db.failureAudit(executionID: "exec-a")?.executionID, "exec-a")
        XCTAssertEqual(db.failureAudit(executionID: "exec-b")?.executionID, "exec-b")
        XCTAssertNil(db.failureAudit(executionID: "exec-missing"))
    }

    func testEachAuditAddsExactlyOneImmutableObject() throws {
        let (db, _) = try makeDatabase("objects")
        let before = try db.count("is_objects")

        let first = db.recordFailureAudit(event(executionID: "exec-a"))
        XCTAssertTrue(first.auditPersisted)
        XCTAssertEqual(try db.count("is_objects"), before + 1)

        let duplicate = db.recordFailureAudit(event(executionID: "exec-a"))
        XCTAssertFalse(duplicate.auditPersisted)
        XCTAssertEqual(try db.count("is_objects"), before + 1,
                       "a duplicate attempt must not write another object")

        let second = db.recordFailureAudit(event(executionID: "exec-b"))
        XCTAssertTrue(second.auditPersisted)
        XCTAssertNotEqual(second.objectID, first.objectID)
        XCTAssertEqual(try db.count("is_objects"), before + 2)

        // The audit ledger never touches settlement identity prefixes.
        XCTAssertNil(try db.resolveIndexIdentity("settlement:c-failure-audit:exec-a"))
        XCTAssertNil(try db.resolveIndexIdentity("settlement-summary:exec-a"))
    }

    /// A storage failure must be reported, never thrown, and must not change the
    /// caller's terminal result. A closed handle is the cheapest way to force it
    /// without touching any real database.
    func testStorageFailureIsReportedNotThrown() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-audit-\(UUID().uuidString)-closed.sqlite3")
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        db.close()
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let result = db.recordFailureAudit(event(executionID: "exec-closed"))
        XCTAssertFalse(result.auditPersisted)
        XCTAssertNil(result.objectID)
        XCTAssertEqual(result.failureClass, "storage_failure")
    }
}
