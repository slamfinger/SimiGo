import Foundation
import XCTest

@testable import SimiGoCollection

/// Paired tests for the ChatGPT desktop export.
///
/// The document shape is synthetic; what matters is that the *absence* of
/// `children` is what makes this carrier recognisable, and that the kept branch
/// is the path the export left selected.
final class ChatGPTSourceTests: XCTestCase {

    private func node(
        _ id: String, parent: String?, role: String, type: String, text: String,
        at stamp: Double
    ) -> [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "message": [
                "author": ["role": role],
                "content": ["content_type": type, "parts": [text]],
                "create_time": stamp,
            ],
        ]
        if let parent { value["parent"] = parent }
        return value
    }

    private func document(
        current: String, mapping: [String: Any], conversationID: String = "conv-a"
    ) -> [[String: Any]] {
        [[
            "conversation_id": conversationID,
            "current_node": current,
            "mapping": mapping,
        ]]
    }

    func testKeptBranchYieldsOneTurnWithDeclaredBinding() throws {
        let mapping = [
            "n1": node("n1", parent: nil, role: "user", type: "text", text: "synthetic question", at: 1790000000),
            "n2": node("n2", parent: "n1", role: "assistant", type: "text", text: "synthetic answer", at: 1790000001),
        ]
        let url = try SnapshotFixture.file(
            document(current: "n2", mapping: mapping), named: "conversations-000.json",
            in: "chatgpt-kept")

        XCTAssertTrue(ChatGPTSource.recognizes(
            SnapshotFixture.encode(document(current: "n2", mapping: mapping))))
        let snapshot = try ChatGPTSource.readSnapshot(at: url)

        XCTAssertEqual(snapshot.turns.count, 1)
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.promptText, "synthetic question")
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertEqual(turn.sessionKey, "chatgpt:conv-a")
        XCTAssertEqual(turn.attribution, .declared)
        XCTAssertEqual(turn.disposition, .retrievable)
    }

    /// A thoughts node on the same branch is deliberation, not the answer.
    func testThoughtsTravelIntoReasoningOnly() throws {
        let mapping = [
            "n1": node("n1", parent: nil, role: "user", type: "text", text: "q", at: 1790000000),
            "n2": node("n2", parent: "n1", role: "assistant", type: "thoughts", text: "pondering", at: 1790000001),
            "n3": node("n3", parent: "n2", role: "assistant", type: "text", text: "a", at: 1790000002),
        ]
        let url = try SnapshotFixture.file(
            document(current: "n3", mapping: mapping), named: "conversations-001.json",
            in: "chatgpt-thoughts")
        let snapshot = try ChatGPTSource.readSnapshot(at: url)

        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.answerText, "a")
        XCTAssertEqual(turn.reasoningText, "pondering")
    }

    /// DeepSeek's export states `children` on every node. Claiming it here would
    /// make one carrier's documents import as the other's.
    func testMappingWithChildrenIsNotClaimed() {
        let mapping = [
            "n1": ["id": "n1", "parent": NSNull(), "children": ["n2"], "message": [:]],
            "n2": ["id": "n2", "parent": "n1", "children": [], "message": [:]],
        ]
        XCTAssertFalse(ChatGPTSource.recognizes(
            SnapshotFixture.encode(document(current: "n2", mapping: mapping))))
    }

    func testMissingCurrentNodeIsReportedNotGuessed() throws {
        let mapping = [
            "n1": node("n1", parent: nil, role: "user", type: "text", text: "q", at: 1790000000)
        ]
        var doc = document(current: "n2", mapping: mapping)
        doc[0]["current_node"] = "n2"
        let url = try SnapshotFixture.file(doc, named: "conversations-002.json", in: "chatgpt-missing")
        let snapshot = try ChatGPTSource.readSnapshot(at: url)

        XCTAssertTrue(snapshot.turns.isEmpty)
        let problems = SnapshotFixture.matching(snapshot, .unsupportedShape)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].detail.contains("current_node"))
    }
}
