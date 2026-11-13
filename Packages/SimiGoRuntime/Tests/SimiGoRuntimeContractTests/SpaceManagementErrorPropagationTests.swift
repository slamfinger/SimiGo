import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

final class SpaceManagementErrorPropagationTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-space-errors-\(name)-\(UUID().uuidString).sqlite3")
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        // Create the lazily-owned room schema, including spaces.axis and space_turns.
        _ = try db.assignTurnSpaces(dryRun: true)
        return (url, db)
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func setAxis(_ url: URL, spaceID: String, axis: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let handle else {
            throw NSError(domain: "SpaceManagementErrorPropagationTests", code: 1)
        }
        defer { sqlite3_close_v2(handle) }
        let sql = "UPDATE spaces SET axis='\(axis)' WHERE space_id='\(spaceID)';"
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        if rc != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "sqlite rc=\(rc)"
            sqlite3_free(error)
            throw NSError(
                domain: "SpaceManagementErrorPropagationTests", code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func testSpaceDeletionTargetPropagatesCandidateAxisReadFailure() throws {
        let (url, db) = try open("delete-target")
        defer { db.close(); cleanup(url) }
        let source = try db.createSpace(title: "source")
        let target = try db.createSpace(title: "same-axis target")
        try setAxis(url, spaceID: source.spaceID, axis: "project")
        try setAxis(url, spaceID: target.spaceID, axis: "project")

        db.beforeSpaceAxisLookupForTesting = { candidateID in
            if candidateID == target.spaceID {
                throw ESISDatabase.DatabaseError.sql("injected candidate-axis read failure")
            }
        }
        XCTAssertThrowsError(try db.spaceDeletionTarget(for: source.spaceID),
                             "A failed axis read must not silently choose a fallback target")
    }

    func testMergeSpacePropagatesAbsorbedTurnCountFailureAndRollsBack() throws {
        let (url, db) = try open("merge-count")
        defer { db.close(); cleanup(url) }
        let source = try db.createSpace(title: "source")
        let target = try db.createSpace(title: "target")
        db.beforeMergeSpaceAbsorbedCountForTesting = {
            throw ESISDatabase.DatabaseError.sql("injected absorbed-count failure")
        }

        XCTAssertThrowsError(try db.mergeSpace(source: source.spaceID, into: target.spaceID))
        XCTAssertNotNil(try db.space(id: source.spaceID),
                        "The failed transaction must leave the source room intact")
        XCTAssertNotNil(try db.space(id: target.spaceID))
    }
}
