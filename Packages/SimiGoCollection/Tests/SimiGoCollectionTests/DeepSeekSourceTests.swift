import Foundation
import XCTest

@testable import SimiGoCollection

/// Paired tests for the DeepSeek node-mapping carrier.
///
/// This is the only snapshot carrier in this batch that states the
/// prompt/answer relation, so the tests below check both directions of that
/// statement: what the carrier says is imported, and what it contradicts itself
/// about is refused.
final class DeepSeekSourceTests: XCTestCase {
    private func read(_ conversations: [Any], caseName: String) throws -> SnapshotImport {
        let url = try SnapshotFixture.file(
            conversations, named: "conversations-\(caseName).json", in: caseName)
        return try DeepSeekSource.readSnapshot(at: url)
    }

    private func promptNode(children: [String], parent: String?, id: String = "1") -> [String: Any] {
        SnapshotFixture.dsNode(
            id: id, parent: parent, children: children,
            fragments: [SnapshotFixture.dsFragment(type: "REQUEST", content: "synthetic question")])
    }

    private func answerNode(
        id: String, parent: String?, fragments: [[String: Any]],
        at: String = "2026-11-07T08:00:05.000000+00:00"
    ) -> [String: Any] {
        SnapshotFixture.dsNode(id: id, parent: parent, fragments: fragments, insertedAt: at)
    }

    private func response(_ text: String) -> [[String: Any]] {
        [SnapshotFixture.dsFragment(type: "RESPONSE", content: text)]
    }

    /// The round trips through the document's own declared binding, with nothing
    /// left to report.
    func testDeclaredBindingIsRetrievableAndAttributesAsDeclared() throws {
        let snapshot = try read([
            SnapshotFixture.dsConversation(id: "conv-1", nodes: [
                SnapshotFixture.dsNode(id: "0", parent: nil, children: ["1"], fragments: nil),
                promptNode(children: ["2"], parent: "0"),
                answerNode(id: "2", parent: "1", fragments: response("synthetic answer")),
            ])
        ], caseName: "declared")

        XCTAssertEqual(snapshot.turns.count, 1)
        XCTAssertEqual(snapshot.diagnostics, [], "a self-consistent export is not a finding")
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.disposition, .retrievable)
        XCTAssertEqual(turn.attribution, .declared, "the carrier states the relation")
        XCTAssertEqual(turn.provider, "deepseek")
        XCTAssertEqual(turn.sessionKey, "deepseek:conv-1")
        XCTAssertEqual(turn.promptText, "synthetic question")
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertNil(turn.reasoningText)
        XCTAssertEqual(turn.answerModel, "deepseek-chat", "the answer node states its model")
        XCTAssertEqual(
            SnapshotFixture.parsed(turn.timestamp),
            SnapshotFixture.moment(year: 2026, month: 11, day: 7, hour: 8, minute: 0, second: 5),
            "microseconds with a numeric offset must keep their instant")
        XCTAssertEqual(turn.identity.sourceSessionID, "conv-1")
        XCTAssertEqual(turn.identity.sourceTurnID, "1", "the node keys, not positions")
        XCTAssertEqual(turn.identity.sourceMessageID, "2")
        XCTAssertEqual(turn.identity.adapterVersion, "deepseek-mapping/v1")
        XCTAssertTrue(turn.identity.operationKey.hasPrefix("SIM.deepseek.collect.v1:"))
        XCTAssertFalse(turn.identity.operationKey.hasPrefix("SIM.qoder."))
    }

    /// Regenerations are kept side by side and the export does not say which one
    /// the user kept, so choosing one would invent that fact.
    func testSiblingAnswersImportNoTurn() throws {
        let siblings = try read([
            SnapshotFixture.dsConversation(id: "conv-siblings", nodes: [
                promptNode(children: ["2", "3"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: response("first answer")),
                answerNode(id: "3", parent: "1", fragments: response("regenerated answer")),
            ])
        ], caseName: "siblings")
        let single = try read([
            SnapshotFixture.dsConversation(id: "conv-siblings", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: response("first answer")),
            ])
        ], caseName: "siblings-control")

        XCTAssertEqual(siblings.turns.count, 0, "no answer may be picked for the user")
        let unbound = SnapshotFixture.matching(siblings, .unboundAnswer)
        XCTAssertEqual(unbound.count, 1)
        XCTAssertTrue(unbound[0].detail.contains("2 sibling answers"))
        XCTAssertTrue(unbound[0].detail.contains("no turn is imported"))
        XCTAssertEqual(single.turns.count, 1, "one child of the same prompt is a normal round")
        XCTAssertEqual(single.turns[0].answerText, "first answer")
    }

    /// The binding has to hold in both directions: a link stated only by the
    /// prompt side is the carrier contradicting itself, not evidence.
    func testOneSidedParentLinkIsRefused() throws {
        let wrongParent = try read([
            SnapshotFixture.dsConversation(id: "conv-onesided", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: "9", fragments: response("synthetic answer")),
            ])
        ], caseName: "wrong-parent")
        let noParent = try read([
            SnapshotFixture.dsConversation(id: "conv-onesided", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: nil, fragments: response("synthetic answer")),
            ])
        ], caseName: "no-parent")

        for snapshot in [wrongParent, noParent] {
            XCTAssertEqual(snapshot.turns.count, 0)
            let shapes = SnapshotFixture.matching(snapshot, .unsupportedShape)
            XCTAssertEqual(shapes.count, 1)
            XCTAssertTrue(shapes[0].detail.contains("not declared on both sides"))
        }
        XCTAssertTrue(wrongParent.diagnostics[0].detail.contains("names 9"))
        XCTAssertTrue(noParent.diagnostics[0].detail.contains("names no parent"))
    }

    /// A child that never reached a RESPONSE is an unfinished round, not a short
    /// answer.
    func testChildWithoutResponseIsIncompleteNotShort() throws {
        let stalled = try read([
            SnapshotFixture.dsConversation(id: "conv-stalled", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(
                    id: "2", parent: "1",
                    fragments: [SnapshotFixture.dsFragment(type: "THINK", content: "thinking")]),
            ])
        ], caseName: "stalled")
        let childless = try read([
            SnapshotFixture.dsConversation(id: "conv-childless", nodes: [
                promptNode(children: [], parent: nil)
            ])
        ], caseName: "childless")

        for snapshot in [stalled, childless] {
            XCTAssertEqual(snapshot.turns.count, 0)
            let incomplete = SnapshotFixture.matching(snapshot, .incompleteTurn)
            XCTAssertEqual(incomplete.count, 1)
            XCTAssertTrue(incomplete[0].detail.contains("reached a RESPONSE fragment"))
        }
        XCTAssertTrue(
            childless.diagnostics.contains { $0.detail.contains("it has no children") })
        XCTAssertFalse(
            stalled.diagnostics.contains { $0.detail.contains("it has no children") })
    }

    /// `THINK` content is deliberation and travels only beside the answer.
    func testThinkContentNeverEntersTheAnswer() throws {
        let snapshot = try read([
            SnapshotFixture.dsConversation(id: "conv-think", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: [
                    SnapshotFixture.dsFragment(type: "THINK", content: "private deliberation"),
                    SnapshotFixture.dsFragment(type: "RESPONSE", content: "synthetic answer"),
                ]),
            ])
        ], caseName: "think")

        XCTAssertEqual(snapshot.turns.count, 1)
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.reasoningText, "private deliberation")
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertFalse(turn.answerText.contains("deliberation"))
        XCTAssertFalse(turn.promptText.contains("deliberation"))
        XCTAssertEqual(turn.disposition, .retrievable, "a thought is not an unfinished round")
        XCTAssertEqual(snapshot.diagnostics.count, 0)
    }

    /// Search and tool fragments state no content in this carrier, so excluding
    /// them drops nothing from the answer — and the round is still reported.
    func testToolFragmentsAreTrafficReportedAlongsideTheAnswer() throws {
        let snapshot = try read([
            SnapshotFixture.dsConversation(id: "conv-tools", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: [
                    SnapshotFixture.dsFragment(type: "THINK", content: "private deliberation"),
                    SnapshotFixture.dsFragment(type: "TOOL_SEARCH"),
                    SnapshotFixture.dsFragment(type: "TOOL_OPEN"),
                    SnapshotFixture.dsFragment(type: "SEARCH"),
                    SnapshotFixture.dsFragment(type: "RESPONSE", content: "synthetic answer"),
                ]),
            ])
        ], caseName: "tool-fragments")

        XCTAssertEqual(snapshot.turns.count, 1)
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertEqual(turn.reasoningText, "private deliberation")
        XCTAssertEqual(turn.disposition, .retrievable)
        let traffic = SnapshotFixture.matching(snapshot, .toolTraffic)
        XCTAssertEqual(traffic.count, 1)
        XCTAssertTrue(traffic[0].detail.contains("3 search/tool fragment(s)"))
        XCTAssertTrue(traffic[0].locator.contains("node-2"))
    }

    /// A fragment type this adapter has never seen is something it cannot
    /// classify, so the round is recorded but never retrieved.
    func testUnrecognisedFragmentTypeDowngradesTheRound() throws {
        let unknown = try read([
            SnapshotFixture.dsConversation(id: "conv-unknown", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: [
                    SnapshotFixture.dsFragment(type: "RESPONSE", content: "synthetic answer"),
                    SnapshotFixture.dsFragment(type: "SYNTHETIC_MARKER"),
                ]),
            ])
        ], caseName: "unknown-fragment")
        let known = try read([
            SnapshotFixture.dsConversation(id: "conv-unknown", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: response("synthetic answer")),
            ])
        ], caseName: "known-fragment")

        XCTAssertEqual(unknown.turns.count, 1, "the answer is still recorded")
        XCTAssertEqual(unknown.turns[0].disposition, .recordedIncompleteAnswer)
        let shapes = SnapshotFixture.matching(unknown, .unsupportedShape)
        XCTAssertEqual(shapes.count, 1)
        XCTAssertTrue(shapes[0].detail.contains("SYNTHETIC_MARKER"))
        XCTAssertEqual(known.turns[0].disposition, .retrievable)
    }

    /// A prompt that also carries an attachment: the question is stated, the
    /// attachment is not text, and both facts are reported.
    func testFileFragmentIsAttachmentNotPromptText() throws {
        let snapshot = try read([
            SnapshotFixture.dsConversation(id: "conv-file", nodes: [
                SnapshotFixture.dsNode(
                    id: "1", parent: nil, children: ["2"],
                    fragments: [
                        SnapshotFixture.dsFragment(type: "FILE"),
                        SnapshotFixture.dsFragment(type: "REQUEST", content: "synthetic question"),
                    ]),
                answerNode(id: "2", parent: "1", fragments: response("synthetic answer")),
            ])
        ], caseName: "file-prompt")

        XCTAssertEqual(snapshot.turns.count, 1)
        XCTAssertEqual(snapshot.turns[0].promptText, "synthetic question")
        let skipped = SnapshotFixture.matching(snapshot, .skippedAttachment)
        XCTAssertEqual(skipped.count, 1)
        XCTAssertTrue(skipped[0].detail.contains("FILE fragment"))
    }

    /// Node ids are unique only inside one conversation, so the conversation id
    /// must travel in the identity.
    func testNodeKeysAreScopedByTheirConversation() throws {
        func conversation(_ id: String) -> [String: Any] {
            SnapshotFixture.dsConversation(id: id, nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: response("answer in \(id)")),
            ])
        }
        let snapshot = try read([conversation("conv-a"), conversation("conv-b")],
                               caseName: "two-conversations")

        XCTAssertEqual(snapshot.turns.count, 2)
        XCTAssertEqual(Set(snapshot.turns.map { $0.identity.sourceSessionID }), ["conv-a", "conv-b"])
        XCTAssertEqual(Set(snapshot.turns.map { $0.identity.operationKey }).count, 2,
                       "identical node keys must not collide across conversations")
        XCTAssertEqual(Set(snapshot.turns.map { $0.sessionKey }), ["deepseek:conv-a", "deepseek:conv-b"])
    }

    /// Without the conversation id there is nothing to bind turns to, and the
    /// nodes are refused rather than re-named by position.
    func testConversationWithoutIdIsRefusedNotDerived() throws {
        let nodes: [[String: Any]] = [
            promptNode(children: ["2"], parent: nil),
            answerNode(id: "2", parent: "1", fragments: response("synthetic answer")),
        ]
        let nameless = try read(
            [SnapshotFixture.dsConversation(id: nil, nodes: nodes)], caseName: "no-conversation-id")
        let named = try read(
            [SnapshotFixture.dsConversation(id: "conv-named", nodes: nodes)],
            caseName: "with-conversation-id")

        XCTAssertEqual(nameless.turns.count, 0)
        let shapes = SnapshotFixture.matching(nameless, .unsupportedShape)
        XCTAssertEqual(shapes.count, 1)
        XCTAssertTrue(shapes[0].detail.contains("2 nodes"))
        XCTAssertTrue(shapes[0].detail.contains("derived identity"))
        XCTAssertTrue(shapes[0].locator.contains("conversation-0"))
        XCTAssertEqual(named.turns.count, 1, "the same mapping under an id is an ordinary round")
    }

    /// Three ways a prompt node can contradict itself.
    func testAmbiguousPromptNodesImportNothing() throws {
        let twoRequests = try read([
            SnapshotFixture.dsConversation(id: "conv-ambiguous", nodes: [
                SnapshotFixture.dsNode(
                    id: "1", parent: nil, children: ["2"],
                    fragments: [
                        SnapshotFixture.dsFragment(type: "REQUEST", content: "first question"),
                        SnapshotFixture.dsFragment(type: "REQUEST", content: "second question"),
                    ]),
                answerNode(id: "2", parent: "1", fragments: response("synthetic answer")),
            ])
        ], caseName: "two-requests")
        let emptyRequest = try read([
            SnapshotFixture.dsConversation(id: "conv-ambiguous", nodes: [
                SnapshotFixture.dsNode(
                    id: "1", parent: nil, children: ["2"],
                    fragments: [SnapshotFixture.dsFragment(type: "REQUEST", content: "   ")]),
                answerNode(id: "2", parent: "1", fragments: response("synthetic answer")),
            ])
        ], caseName: "empty-request")
        let danglingChild = try read([
            SnapshotFixture.dsConversation(id: "conv-ambiguous", nodes: [
                promptNode(children: ["7"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: response("synthetic answer")),
            ])
        ], caseName: "dangling-child")

        XCTAssertEqual(twoRequests.turns.count, 0)
        XCTAssertTrue(
            twoRequests.diagnostics.contains { $0.detail.contains("the prompt is ambiguous") })

        XCTAssertEqual(emptyRequest.turns.count, 0)
        XCTAssertTrue(
            emptyRequest.diagnostics.contains {
                $0.detail.contains("REQUEST fragment states no content")
            })

        XCTAssertEqual(danglingChild.turns.count, 0)
        let missing = SnapshotFixture.matching(danglingChild, .unsupportedShape)
        XCTAssertEqual(missing.count, 1)
        XCTAssertTrue(missing[0].detail.contains("child 7 is not in the mapping"))
        XCTAssertEqual(SnapshotFixture.matching(danglingChild, .incompleteTurn).count, 1)
    }

    /// An answer node that does not resolve, and a mapping that is not a node.
    func testUnreadableFragmentsAndNodesAreReportedPerNode() throws {
        let noText = try read([
            SnapshotFixture.dsConversation(id: "conv-noanswer", nodes: [
                promptNode(children: ["2"], parent: nil),
                answerNode(id: "2", parent: "1", fragments: [
                    SnapshotFixture.dsFragment(type: "RESPONSE", content: "")
                ]),
            ])
        ], caseName: "response-without-text")

        XCTAssertEqual(noText.turns.count, 0)
        XCTAssertTrue(
            noText.diagnostics.contains {
                $0.detail.contains("RESPONSE fragment states no content")
            })

        // A mapping entry that is not an object cannot be a node. Built by hand,
        // because no node fixture can state a non-node.
        let broken = try DeepSeekSource.interpret(
            SnapshotFixture.encode([[
                "id": "conv-broken", "title": "synthetic conversation",
                "mapping": ["1": "not a node"],
            ]]),
            path: "conversations-broken.json", contentDigest: "digest")
        XCTAssertEqual(broken.turns.count, 0)
        let shapes = SnapshotFixture.matching(broken, .unsupportedShape)
        XCTAssertEqual(shapes.count, 1)
        XCTAssertTrue(shapes[0].detail.contains("node is not an object"))
        XCTAssertTrue(shapes[0].locator.contains("node-1"), "the mapping key is the locator")
    }

    /// Recognition is structural, and this carrier is the only one of the three
    /// whose top level is a list.
    func testRecognitionAndEmptyExportFailClosed() throws {
        let flat = SnapshotFixture.encode(SnapshotFixture.flatDocument([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
        ]))
        XCTAssertFalse(DeepSeekSource.recognizes(flat))
        XCTAssertFalse(
            DeepSeekSource.recognizes(
                SnapshotFixture.encode(SnapshotFixture.aiDocument([
                    SnapshotFixture.aiChunk(role: "user", text: "synthetic question")
                ]))))
        XCTAssertFalse(DeepSeekSource.recognizes(SnapshotFixture.encode([])))

        let emptyURL = try SnapshotFixture.file(
            [Any](), named: "conversations.json", in: "ds-empty")
        XCTAssertThrowsError(try DeepSeekSource.readSnapshot(at: emptyURL)) { error in
            guard case .foreignDocument(let path, let detail)? = error as? SnapshotReadError else {
                return XCTFail("expected foreignDocument, got \(error)")
            }
            XCTAssertEqual(path, "conversations.json")
            XCTAssertTrue(detail.contains("does not claim"))
        }
        // Reaching the interpretation directly states the same fact in the
        // adapter's own words: an export with no conversations is not readable.
        XCTAssertThrowsError(
            try DeepSeekSource.interpret(
                SnapshotFixture.encode([Any]()), path: "conversations.json",
                contentDigest: "digest")
        ) { error in
            guard case .foreignDocument(_, let detail)? = error as? SnapshotReadError else {
                return XCTFail("expected foreignDocument, got \(error)")
            }
            XCTAssertTrue(detail.contains("no conversations"))
        }
    }
}
