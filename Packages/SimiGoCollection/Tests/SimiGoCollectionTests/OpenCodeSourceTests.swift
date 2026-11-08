import Foundation
import SQLite3
import XCTest

@testable import SimiGoCollection

/// Paired tests for the opencode SQLite store.
///
/// The store is a database rather than a document, so recognition is a schema
/// question and the tests build a real (temporary) file instead of pretending
/// bytes are a transcript.
final class OpenCodeSourceTests: XCTestCase {

    private func store(
        _ rows: [(id: String, session: String, seq: Int, type: String, data: String)]
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-\(UUID().uuidString).db")
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw OpenCodeSource.ReadError.unreadable("cannot create test store")
        }
        defer { sqlite3_close(handle) }
        let schema = """
        CREATE TABLE session_message(
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL,
            seq INTEGER NOT NULL, time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL, data TEXT NOT NULL);
        """
        guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
            throw OpenCodeSource.ReadError.unreadable("cannot create test schema")
        }
        for row in rows {
            let escaped = row.data.replacingOccurrences(of: "'", with: "''")
            let sql = """
            INSERT INTO session_message VALUES(
                '\(row.id)','\(row.session)','\(row.type)',\(row.seq),0,0,'\(escaped)');
            """
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                throw OpenCodeSource.ReadError.unreadable("cannot insert \(row.id)")
            }
        }
        return url
    }

    func testUserAndAssistantPairIntoOneTurn() throws {
        let url = try store([
            (id: "m1", session: "s1", seq: 1, type: "user", data: #"{"text":"synthetic q"}"#),
            (
                id: "m2", session: "s1", seq: 2, type: "assistant",
                data: #"{"content":[{"type":"text","text":"synthetic a"}],"finish":"stop"}"#
            ),
        ])
        XCTAssertTrue(OpenCodeSource.recognizes(at: url))
        let imported = try OpenCodeSource.collect(at: url)

        XCTAssertEqual(imported.turns.count, 1)
        let turn = try XCTUnwrap(imported.turns.first)
        XCTAssertEqual(turn.promptText, "synthetic q")
        XCTAssertEqual(turn.answerText, "synthetic a")
        XCTAssertEqual(turn.sessionKey, "opencode:s1")
        XCTAssertEqual(turn.disposition, .retrievable)
    }

    /// A tool-calls step carries no text and is a step inside the round, not an
    /// answer: pairing must skip it and bind the prompt to the stopped reply.
    func testToolStepWithoutTextIsSkipped() throws {
        let url = try store([
            (id: "m1", session: "s1", seq: 1, type: "user", data: #"{"text":"q"}"#),
            (
                id: "m2", session: "s1", seq: 2, type: "assistant",
                data: #"{"content":[{"type":"tool","text":"ignored"}],"finish":"tool-calls"}"#
            ),
            (
                id: "m3", session: "s1", seq: 3, type: "assistant",
                data: #"{"content":[{"type":"text","text":"a"}],"finish":"stop"}"#
            ),
        ])
        let imported = try OpenCodeSource.collect(at: url)

        XCTAssertEqual(imported.turns.count, 1)
        XCTAssertEqual(try XCTUnwrap(imported.turns.first).answerText, "a")
    }

    func testErrorFinishIsRecordedIncomplete() throws {
        let url = try store([
            (id: "m1", session: "s1", seq: 1, type: "user", data: #"{"text":"q"}"#),
            (
                id: "m2", session: "s1", seq: 2, type: "assistant",
                data: #"{"content":[{"type":"text","text":"partial"}],"finish":"error"}"#
            ),
        ])
        let imported = try OpenCodeSource.collect(at: url)

        let turn = try XCTUnwrap(imported.turns.first)
        XCTAssertEqual(turn.disposition, .recordedIncompleteAnswer)
    }

    func testAPlainFileIsNotClaimed() throws {
        let url = try SnapshotFixture.file(
            Data(#"{"not":"a store"}"#.utf8), named: "opencode.db", in: "opencode-foreign")
        XCTAssertFalse(OpenCodeSource.recognizes(at: url))
    }
}
