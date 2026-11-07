import Foundation
import XCTest

@testable import SimiGoCollection

/// Paired tests for the flat `messages[]` carrier.
///
/// Every guard is tested with the document that trips it and the document that
/// must still import: the premise is never supplied by the assertion itself.
final class FlatMessageExportSourceTests: XCTestCase {
    private func read(
        _ rows: [[String: Any]], caseName: String,
        sessionID: String? = "flat-session-1", messageCount: Int? = nil
    ) throws -> SnapshotImport {
        let url = try SnapshotFixture.file(
            SnapshotFixture.flatDocument(rows, sessionID: sessionID, messageCount: messageCount),
            named: "flat-\(caseName).json", in: caseName)
        return try FlatMessageExportSource.readSnapshot(at: url)
    }

    /// A round the carrier states as finished.
    func testStoppedRoundIsRetrievableAndCarriesTheStatedIdentity() throws {
        let snapshot = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "stopped")

        XCTAssertEqual(snapshot.turns.count, 1)
        XCTAssertEqual(snapshot.diagnostics, [], "a stated session id and count leave nothing to report")
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.disposition, .retrievable)
        XCTAssertEqual(turn.attribution, .fileOrderOnly)
        XCTAssertEqual(turn.provider, "flat-export")
        XCTAssertEqual(turn.sessionKey, "flat-export:flat-session-1")
        XCTAssertEqual(turn.promptText, "synthetic question")
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertNil(turn.reasoningText)
        // Measured: no row in any of the three exports states a model.
        XCTAssertNil(turn.answerModel, "an unobserved model must not be invented")

        let identity = turn.identity
        XCTAssertEqual(identity.sourceType, "flat-export")
        XCTAssertEqual(identity.sourceSessionID, "flat-session-1")
        XCTAssertEqual(identity.sourceTurnID, "1")
        XCTAssertEqual(identity.sourceMessageID, "2")
        XCTAssertEqual(identity.sourceRevision, 1)
        XCTAssertEqual(
            identity.adapterVersion, "flat-message-export/v1")
        XCTAssertTrue(
            identity.operationKey.hasPrefix("SIM.flat-export.collect.v1:"),
            "the namespace must follow the source, not Qoder's")
        XCTAssertFalse(identity.operationKey.hasPrefix("SIM.qoder."))

        // The carrier stamps epoch seconds; the bridge must keep that instant.
        let instant = try XCTUnwrap(SnapshotFixture.instant(turn.timestamp))
        XCTAssertEqual(instant, 1_760_000_000, accuracy: 1)
        XCTAssertEqual(snapshot.contentDigest.count, 64)
    }

    /// The same document, one field shorter: an absent marker is not a
    /// finished answer, so this must degrade instead of importing.
    func testAbsentFinishReasonIsRecordedNeverRetrieved() throws {
        let snapshot = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer"),
        ], caseName: "no-finish")

        XCTAssertEqual(snapshot.turns.count, 1)
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.disposition, .recordedIncompleteAnswer)
        let incomplete = SnapshotFixture.matching(snapshot, .incompleteTurn)
        XCTAssertEqual(incomplete.count, 1)
        XCTAssertTrue(incomplete[0].locator.contains("message-2"))
    }

    /// Two non-`stop` values that mean different things must not collapse into
    /// one reported reason, even though both grade the same way.
    func testTruncatedAndUnrecognisedFinishReasonsDegradeDistinctly() throws {
        let truncated = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "half an answer", finish: "length"),
        ], caseName: "length")
        let unknown = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "filtered", finish: "content_filter"),
        ], caseName: "unknown-finish")

        for snapshot in [truncated, unknown] {
            XCTAssertEqual(snapshot.turns.count, 1)
            XCTAssertEqual(snapshot.turns[0].disposition, .recordedIncompleteAnswer)
        }
        XCTAssertEqual(SnapshotFixture.matching(truncated, .incompleteTurn).count, 1)
        XCTAssertEqual(SnapshotFixture.matching(truncated, .unsupportedShape).count, 0)
        XCTAssertEqual(SnapshotFixture.matching(unknown, .unsupportedShape).count, 1)
        XCTAssertEqual(SnapshotFixture.matching(unknown, .incompleteTurn).count, 0)
    }

    /// A `tool_calls` round neither answers nor closes the prompt: the answer
    /// that follows it still belongs to the original question.
    func testToolRoundStaysOutOfTheAnswerAndKeepsThePromptOpen() throws {
        let snapshot = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "let me look that up", finish: "tool_calls"),
            SnapshotFixture.flatRow(id: 3, role: "tool", text: "tool output"),
            SnapshotFixture.flatRow(id: 4, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "tool-loop")

        XCTAssertEqual(snapshot.turns.count, 1)
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertFalse(turn.answerText.contains("look that up"))
        XCTAssertEqual(turn.promptText, "synthetic question")
        XCTAssertEqual(turn.identity.sourceTurnID, "1", "the loop must not re-home the answer")
        XCTAssertEqual(turn.identity.sourceMessageID, "4")
        XCTAssertEqual(SnapshotFixture.matching(snapshot, .toolTraffic).count, 1)
        XCTAssertEqual(SnapshotFixture.matching(snapshot, .unboundAnswer), [])
    }

    /// A `model_switch` row is displayed as a user row but records a change of
    /// model. Paired with the identical row that is not a marker.
    func testModelSwitchRowOpensNoPrompt() throws {
        let marker = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: " switched to gpt-synthetic", modelSwitch: true),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "marker")
        let question = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: " switched to gpt-synthetic"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "not-marker")

        XCTAssertEqual(marker.turns.count, 0, "a model switch is not something a human asked")
        XCTAssertEqual(SnapshotFixture.matching(marker, .unsupportedShape).count, 1)
        XCTAssertEqual(SnapshotFixture.matching(marker, .unboundAnswer).count, 1)
        XCTAssertEqual(question.turns.count, 1, "the same text without the marker is a prompt")
        XCTAssertEqual(SnapshotFixture.matching(question, .unboundAnswer).count, 0)
    }

    /// A user row that states no text leaves nothing to bind.
    func testUserRowStatingNoTextOpensNoPrompt() throws {
        let snapshot = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "   "),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "blank-user")

        XCTAssertEqual(snapshot.turns.count, 0)
        XCTAssertEqual(SnapshotFixture.matching(snapshot, .unsupportedShape).count, 1)
        XCTAssertEqual(SnapshotFixture.matching(snapshot, .unboundAnswer).count, 1)
    }

    /// Two prompts in a row: the first is reported unanswered, the second still
    /// turns. A silent overwrite would lose the report.
    func testPromptWithoutTerminalAnswerIsReportedAndTheNextStillTurns() throws {
        let snapshot = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "first question"),
            SnapshotFixture.flatRow(id: 2, role: "user", text: "second question"),
            SnapshotFixture.flatRow(id: 3, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "two-prompts")

        XCTAssertEqual(snapshot.turns.count, 1)
        XCTAssertEqual(snapshot.turns[0].promptText, "second question")
        let unanswered = SnapshotFixture.matching(snapshot, .incompleteTurn)
        XCTAssertEqual(unanswered.count, 1)
        XCTAssertTrue(unanswered[0].locator.contains("message-1"))

        // An open prompt at the end of the file is the same fact.
        let trailing = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "first question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "answer", finish: "stop"),
            SnapshotFixture.flatRow(id: 3, role: "user", text: "never answered"),
        ], caseName: "trailing-prompt")
        XCTAssertEqual(trailing.turns.count, 1)
        XCTAssertEqual(SnapshotFixture.matching(trailing, .incompleteTurn).count, 1)
        XCTAssertTrue(
            SnapshotFixture.matching(trailing, .incompleteTurn)[0].locator.contains("message-3"))
    }

    /// Rows before any prompt are one report, not dozens.
    func testRowsBeforeAnyPromptCollapseIntoOneUnboundReport() throws {
        let snapshot = try read([
            SnapshotFixture.flatRow(id: 1, role: "assistant", text: "orphan one", finish: "stop"),
            SnapshotFixture.flatRow(id: 2, role: "tool", text: "orphan output"),
            SnapshotFixture.flatRow(id: 3, role: "assistant", text: "orphan two", finish: "stop"),
            SnapshotFixture.flatRow(id: 4, role: "user", text: "first real question"),
            SnapshotFixture.flatRow(id: 5, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "leading-orphans")

        XCTAssertEqual(snapshot.turns.count, 1)
        let unbound = SnapshotFixture.matching(snapshot, .unboundAnswer)
        XCTAssertEqual(unbound.count, 1, "the run is reported once")
        XCTAssertTrue(unbound[0].detail.contains("3"))
        XCTAssertTrue(unbound[0].locator.contains("rows 0-2"))
    }

    /// Identity precedence: the document first, then a row, then the file name —
    /// and the file-name fallback is always reported because it breaks on rename.
    func testSessionIdentityFallsBackToRowsThenFileNameAndSaysSo() throws {
        let fromRow = try read(
            [
                SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question")
                    .merging(["session_id": "row-session-9"], uniquingKeysWith: { _, new in new }),
                SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
            ],
            caseName: "row-session", sessionID: nil)
        XCTAssertEqual(fromRow.turns.count, 1)
        XCTAssertEqual(fromRow.turns[0].sessionKey, "flat-export:row-session-9")
        let rowShapes = SnapshotFixture.matching(fromRow, .unsupportedShape)
        XCTAssertEqual(rowShapes.count, 1)
        XCTAssertTrue(
            rowShapes[0].detail.contains("row session row-session-9"),
            "the diagnostic names the row that supplied the identity")
        XCTAssertFalse(
            rowShapes[0].detail.contains("file name"),
            "the identity did not come from the file name, so the report must not say it did")

        let fromName = try read(
            [
                SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
                SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
            ],
            caseName: "name-session", sessionID: nil)
        XCTAssertEqual(fromName.turns[0].identity.sourceSessionID, "flat-name-session")
        XCTAssertEqual(fromName.turns[0].sessionKey, "flat-export:flat-name-session")
        XCTAssertTrue(
            SnapshotFixture.matching(fromName, .unsupportedShape)[0].detail.contains("file name"))
    }

    /// A stated count that disagrees with the list is a contradiction the
    /// collector must not smooth over.
    func testMessageCountDisagreementIsReported() throws {
        let snapshot = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "wrong-count", messageCount: 99)

        XCTAssertEqual(snapshot.turns.count, 1, "reading continues from the actual list")
        let shapes = SnapshotFixture.matching(snapshot, .unsupportedShape)
        XCTAssertEqual(shapes.count, 1)
        XCTAssertTrue(shapes[0].locator.contains("message_count"))
        XCTAssertTrue(shapes[0].detail.contains("99"))
    }

    /// Thought text travels into `reasoningText` and nowhere else — under
    /// either of the two field names the carrier uses for it.
    func testReasoningNeverEntersTheAnswerUnderEitherFieldName() throws {
        let named = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(
                id: 2, role: "assistant", text: "synthetic answer", finish: "stop",
                reasoning: "private deliberation"),
        ], caseName: "reasoning")
        let contentOnly = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop")
                .merging(
                    ["reasoning_content": "private deliberation"],
                    uniquingKeysWith: { _, new in new })
                .merging(["reasoning": ""], uniquingKeysWith: { _, new in new }),
        ], caseName: "reasoning-content")

        for snapshot in [named, contentOnly] {
            XCTAssertEqual(snapshot.turns.count, 1)
            let turn = try XCTUnwrap(snapshot.turns.first)
            XCTAssertEqual(turn.reasoningText, "private deliberation")
            XCTAssertFalse(turn.answerText.contains("deliberation"))
            XCTAssertFalse(turn.promptText.contains("deliberation"))
        }
        // A row without either field must not read as an empty thought.
        let without = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "no-reasoning")
        XCTAssertNil(without.turns[0].reasoningText)
    }

    /// A role this adapter has never seen is refused per row, not guessed.
    func testUnknownRoleIsRefusedWithoutLosingTheRestOfFile() throws {
        let snapshot = try read([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(id: 2, role: "synthetic-role", text: "unexpected"),
            SnapshotFixture.flatRow(id: 3, role: "assistant", text: "synthetic answer", finish: "stop"),
        ], caseName: "unknown-role")

        XCTAssertEqual(snapshot.turns.count, 1)
        let shapes = SnapshotFixture.matching(snapshot, .unsupportedShape)
        XCTAssertEqual(shapes.count, 1)
        XCTAssertTrue(shapes[0].detail.contains("synthetic-role"))
    }

    /// Mis-routing is an error, never an empty import: "nothing to collect" and
    /// "not my carrier" are different facts.
    func testForeignAndUnreadableDocumentsFailClosed() throws {
        let deepseek = SnapshotFixture.encode([
            SnapshotFixture.dsConversation(
                id: "conv-1",
                nodes: [SnapshotFixture.dsNode(id: "1", parent: nil)])
        ])
        XCTAssertFalse(FlatMessageExportSource.recognizes(deepseek))

        let foreignURL = try SnapshotFixture.file(deepseek, named: "foreign.json", in: "foreign")
        XCTAssertThrowsError(try FlatMessageExportSource.readSnapshot(at: foreignURL)) { error in
            guard case .foreignDocument(let path, let detail)? = error as? SnapshotReadError else {
                return XCTFail("expected foreignDocument, got \(error)")
            }
            XCTAssertEqual(path, "foreign.json", "only the file name may travel into the error")
            XCTAssertFalse(detail.isEmpty)
        }

        // An export whose list is empty is not this carrier either.
        XCTAssertFalse(
            FlatMessageExportSource.recognizes(
                SnapshotFixture.encode(SnapshotFixture.flatDocument([]))))

        let corrupt = try SnapshotFixture.file(
            Data("{\"messages\": [".utf8), named: "corrupt.json", in: "corrupt")
        XCTAssertThrowsError(try FlatMessageExportSource.readSnapshot(at: corrupt)) { error in
            guard case .foreignDocument? = error as? SnapshotReadError else {
                return XCTFail("expected foreignDocument, got \(error)")
            }
        }
        // `interpret` sees the parse failure itself, which is a different fact.
        XCTAssertThrowsError(
            try FlatMessageExportSource.interpret(
                Data("{\"messages\": [".utf8), path: "corrupt.json", contentDigest: "digest")
        ) { error in
            guard case .unreadable? = error as? SnapshotReadError else {
                return XCTFail("expected unreadable, got \(error)")
            }
        }

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-snapshot-absent", isDirectory: true)
            .appendingPathComponent("absent.json")
        XCTAssertThrowsError(try FlatMessageExportSource.readSnapshot(at: missing)) { error in
            guard case .unreadable? = error as? SnapshotReadError else {
                return XCTFail("expected unreadable, got \(error)")
            }
        }
    }
}

