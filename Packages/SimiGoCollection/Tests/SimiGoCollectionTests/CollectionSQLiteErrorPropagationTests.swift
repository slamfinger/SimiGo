import Darwin
import Foundation
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
}
