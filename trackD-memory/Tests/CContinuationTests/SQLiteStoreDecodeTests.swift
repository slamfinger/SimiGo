import Foundation
import InformationCore
import SQLite3
import Testing

@Test
func sqliteStoreFailsClosedOnCorruptedRequiredProvenance() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let path = root.appendingPathComponent("information.sqlite").path
    let store = try SQLiteStore(path: path)
    let information = Information(
        identity: store.makeInformationID(
            content: "persisted fact",
            provenance: Provenance(producedAt: Date(), producedBy: "test")
        ),
        content: "persisted fact",
        provenance: Provenance(producedAt: Date(), producedBy: "test")
    )
    try store.store(information)

    var database: OpaquePointer?
    guard sqlite3_open(path, &database) == SQLITE_OK else {
        Issue.record("could not open test database")
        return
    }
    defer { sqlite3_close_v2(database) }
    guard sqlite3_exec(database, "UPDATE information SET produced_at = 'not-a-date'", nil, nil, nil) == SQLITE_OK else {
        Issue.record("could not corrupt test database")
        return
    }

    #expect(throws: StorageError.invalidData("invalid produced_at")) {
        _ = try store.fetch(by: information.identity)
    }
}
