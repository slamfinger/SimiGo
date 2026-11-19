import Darwin
import Foundation
import SQLite3

private func collectionDenyRollbackForTesting(
    _ userData: UnsafeMutableRawPointer?,
    _ action: Int32,
    _ firstArgument: UnsafePointer<CChar>?,
    _ secondArgument: UnsafePointer<CChar>?,
    _ databaseName: UnsafePointer<CChar>?,
    _ triggerName: UnsafePointer<CChar>?
) -> Int32 {
    guard action == SQLITE_TRANSACTION,
          let firstArgument,
          String(cString: firstArgument).uppercased() == "ROLLBACK"
    else { return SQLITE_OK }
    return SQLITE_DENY
}
import XCTest
@testable import SimiGoCollection

final class CollectionSQLiteErrorPropagationTests: XCTestCase {
    private func canonicalDatabasePath(_ url: URL) throws -> String {
        var resolvedParent = [CChar](repeating: 0, count: Int(PATH_MAX))
        let success = url.deletingLastPathComponent().path.withCString { source in
            resolvedParent.withUnsafeMutableBufferPointer { target in
                Darwin.realpath(source, target.baseAddress) != nil
            }
        }
        guard success else {
            throw NSError(
                domain: "CollectionSQLiteErrorPropagationTests",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "cannot resolve SQLite fixture parent"])
        }
        return URL(fileURLWithPath: String(cString: resolvedParent))
            .appendingPathComponent(url.lastPathComponent).path
    }

    func testNumericBindErrorsPropagateBeforeWriteAndResetSurfacesStepError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-sqlite-bind-errors-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("inbox.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let connection = try CollectionSQLiteConnection.open(
            path: try canonicalDatabasePath(databaseURL))
        defer { connection.close() }
        try connection.execute("CREATE TABLE numeric_bindings(value INTEGER)")
        try connection.execute("CREATE TABLE unique_values(value INTEGER UNIQUE)")
        try connection.execute("INSERT INTO unique_values(value) VALUES(1)")

        do {
            let statement = try connection.prepare(
                "INSERT INTO numeric_bindings(value) VALUES(?)")
            XCTAssertThrowsError(try statement.bind(int64: 42, at: 2)) { error in
                guard case CollectionStateError.sqliteFailure(let code, _) = error else {
                    return XCTFail("expected SQLITE_RANGE from int64 bind, got \(error)")
                }
                XCTAssertEqual(code, 25)
            }
            XCTAssertThrowsError(try statement.bind(double: 3.14, at: 2)) { error in
                guard case CollectionStateError.sqliteFailure(let code, _) = error else {
                    return XCTFail("expected SQLITE_RANGE from double bind, got \(error)")
                }
                XCTAssertEqual(code, 25)
            }
        }
        XCTAssertEqual(try connection.scalarInt64("SELECT COUNT(*) FROM numeric_bindings"), 0)

        do {
            let statement = try connection.prepare("INSERT INTO unique_values(value) VALUES(?)")
            try statement.bind(int64: 1, at: 1)
            XCTAssertThrowsError(try statement.step()) { error in
                guard case CollectionStateError.sqliteFailure(let code, _) = error else {
                    return XCTFail("expected SQLITE_CONSTRAINT from step, got \(error)")
                }
                XCTAssertEqual(code, 19)
            }
            XCTAssertThrowsError(try statement.reset()) { error in
                guard case CollectionStateError.sqliteFailure(let code, _) = error else {
                    return XCTFail("expected SQLITE_CONSTRAINT from reset, got \(error)")
                }
                XCTAssertEqual(code, 19)
            }
        }
    }
    func testTransactionPreservesFailureWhenSQLiteAlreadyRolledBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-sqlite-auto-rollback-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("inbox.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = try CollectionSQLiteConnection.open(path: try canonicalDatabasePath(databaseURL))
        defer { connection.close() }

        try connection.execute("CREATE TABLE rows(value INTEGER)")
        try connection.execute("""
        CREATE TRIGGER automatic_rollback BEFORE INSERT ON rows
        BEGIN SELECT RAISE(ROLLBACK, 'forced automatic rollback'); END;
        """)

        XCTAssertThrowsError(try connection.withTransaction {
            try connection.execute("INSERT INTO rows(value) VALUES(1)")
        }) { error in
            guard case CollectionStateError.sqliteFailure(let code, let detail) = error else {
                return XCTFail("expected the original SQLite statement failure, got \\(error)")
            }
            XCTAssertEqual(code & 0xFF, SQLITE_CONSTRAINT)
            XCTAssertTrue(detail.contains("forced automatic rollback"), detail)
        }
        XCTAssertEqual(try connection.scalarInt64("SELECT COUNT(*) FROM rows"), 0)
        try connection.execute("DROP TRIGGER automatic_rollback")
        try connection.execute("INSERT INTO rows(value) VALUES(2)")
        XCTAssertEqual(try connection.scalarInt64("SELECT COUNT(*) FROM rows"), 1)
    }

    func testRollbackFailureIsReportedAndConnectionIsRetired() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-sqlite-rollback-failure-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("inbox.sqlite")
        let path = try canonicalDatabasePath(databaseURL)
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = try CollectionSQLiteConnection.open(path: path)
        defer { connection.close() }
        try connection.execute("CREATE TABLE rows(value INTEGER)")
        connection.beforeRollbackForTesting = { handle in
            XCTAssertEqual(
                sqlite3_set_authorizer(handle, collectionDenyRollbackForTesting, nil),
                SQLITE_OK)
        }

        XCTAssertThrowsError(try connection.withTransaction {
            try connection.execute("INSERT INTO rows(value) VALUES(1)")
            throw NSError(
                domain: "CollectionSQLiteErrorPropagationTests", code: 91,
                userInfo: [NSLocalizedDescriptionKey: "original transaction body failure"])
        }) { error in
            guard case CollectionStateError.sqliteFailure(let code, let detail) = error else {
                return XCTFail("expected rollback failure, got \\(error)")
            }
            XCTAssertEqual(code & 0xFF, SQLITE_AUTH)
            XCTAssertTrue(detail.contains("ROLLBACK failed"), detail)
            XCTAssertTrue(detail.contains("original transaction body failure"), detail)
        }

        XCTAssertThrowsError(try connection.execute("INSERT INTO rows(value) VALUES(2)")) { error in
            guard case CollectionStateError.sqliteFailure(let code, let detail) = error else {
                return XCTFail("expected a retired-connection failure, got \\(error)")
            }
            XCTAssertEqual(code & 0xFF, SQLITE_MISUSE)
            XCTAssertTrue(detail.contains("connection closed"), detail)
        }
        let verifier = try CollectionSQLiteConnection.open(path: path)
        defer { verifier.close() }
        XCTAssertEqual(try verifier.scalarInt64("SELECT COUNT(*) FROM rows"), 0,
                       "closing the uncertain connection must discard its uncommitted row")
    }
}
