import Foundation
import XCTest

@testable import SimiGoCollection

/// Paired tests for the AI Studio `chunkedPrompt` carrier.
///
/// Every document here is synthetic. The identity statement about the file name
/// is present in all of them, so counts of `.unsupportedShape` are asserted with
/// that baseline in mind.
final class AIStudioSourceTests: XCTestCase {
    private func read(
        _ chunks: [[String: Any]], caseName: String,
        pending: [[String: Any]] = [], model: String = "synthetic-gemini"
    ) throws -> SnapshotImport {
        let url = try SnapshotFixture.file(
            SnapshotFixture.aiDocument(chunks, pendingInputs: pending, model: model),
            named: "prompt-\(caseName).json", in: caseName)
        return try AIStudioSource.readSnapshot(at: url)
    }

    private func expectDiagnostic(
        _ snapshot: SnapshotImport, _ kind: CollectionDiagnostic.Kind, containing: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let found = SnapshotFixture.matching(snapshot, kind).filter {
            $0.detail.contains(containing)
        }
        XCTAssertEqual(found.count, 1, "one \(kind) about \(containing)", file: file, line: line)
    }

    /// The document names no conversation, so the identity comes from the file
    /// name and says so — while the round itself is still imported.
    func testStoppedRunIsRetrievableWithTheFileNameIdentity() throws {
        let snapshot = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "stopped")

        XCTAssertEqual(snapshot.turns.count, 1)
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.disposition, .retrievable)
        XCTAssertEqual(turn.attribution, .fileOrderOnly, "the carrier has no parent link")
        XCTAssertEqual(turn.provider, "aistudio")
        XCTAssertEqual(turn.sessionKey, "aistudio:prompt-stopped")
        XCTAssertEqual(turn.promptText, "synthetic question")
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertNil(turn.reasoningText)
        // `runSettings` states the model for the whole document, not per chunk.
        XCTAssertEqual(turn.answerModel, "synthetic-gemini")
        XCTAssertEqual(turn.identity.sourceType, "aistudio")
        XCTAssertEqual(turn.identity.sourceSessionID, "prompt-stopped")
        XCTAssertEqual(turn.identity.sourceTurnID, "prompt-0")
        XCTAssertEqual(turn.identity.sourceMessageID, "chunk-1")
        XCTAssertEqual(
            turn.identity.adapterVersion, "aistudio-chunked-prompt/v1")
        XCTAssertTrue(turn.identity.operationKey.hasPrefix("SIM.aistudio.collect.v1:"))
        XCTAssertFalse(turn.identity.operationKey.hasPrefix("SIM.qoder."))

        // One diagnostic, and it is the identity warning — nothing else.
        XCTAssertEqual(snapshot.diagnostics.count, 1)
        expectDiagnostic(snapshot, .unsupportedShape, containing: "no session identifier")
    }

    /// The two ways an answer fails to be finished must not read the same.
    func testAbsentAndAbnormalFinishReasonsAreBothRecordedNeverRetrieved() throws {
        let absent = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer"),
        ], caseName: "no-finish")
        let abnormal = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(
                role: "model", text: "synthetic answer", finish: "MALFORMED_RESPONSE"),
        ], caseName: "malformed")

        for snapshot in [absent, abnormal] {
            XCTAssertEqual(snapshot.turns.count, 1)
            XCTAssertEqual(snapshot.turns[0].disposition, .recordedIncompleteAnswer)
        }
        XCTAssertEqual(SnapshotFixture.matching(absent, .incompleteTurn).count, 1)
        XCTAssertTrue(
            SnapshotFixture.matching(absent, .incompleteTurn)[0].detail.contains("absent marker"))
        XCTAssertEqual(SnapshotFixture.matching(abnormal, .incompleteTurn).count, 0)
        let shapes = SnapshotFixture.matching(abnormal, .unsupportedShape)
        XCTAssertEqual(shapes.count, 2, "the identity statement plus the abnormal end")
        XCTAssertTrue(shapes.contains { $0.detail.contains("MALFORMED_RESPONSE") })
    }

    /// A thought chunk is what the model deliberated, never what it answered.
    func testThoughtChunksBecomeReasoningNeverTheAnswer() throws {
        let paired = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "private deliberation", thought: true),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "thought")

        XCTAssertEqual(paired.turns.count, 1)
        let turn = try XCTUnwrap(paired.turns.first)
        XCTAssertEqual(turn.reasoningText, "private deliberation")
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertFalse(turn.answerText.contains("deliberation"))
        XCTAssertEqual(turn.identity.sourceMessageID, "chunk-2", "the answer, not the thought")
        XCTAssertEqual(turn.disposition, .retrievable)
        XCTAssertEqual(paired.diagnostics.count, 1, "a thought is not a problem to report")

        // The same flag arrives inside `parts[]`, and must select the same chunk.
        let viaParts = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(
                role: "model", text: "private deliberation", thoughtInParts: true),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "thought-parts")
        XCTAssertEqual(viaParts.turns.count, 1)
        XCTAssertEqual(viaParts.turns[0].reasoningText, "private deliberation")
        XCTAssertEqual(viaParts.turns[0].answerText, "synthetic answer")
    }

    /// A run of only thoughts has no answer at all, so it is not a turn.
    func testThoughtOnlyRunImportsNothing() throws {
        let snapshot = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "private deliberation", thought: true),
        ], caseName: "thought-only")

        XCTAssertEqual(snapshot.turns.count, 0)
        let incomplete = SnapshotFixture.matching(snapshot, .incompleteTurn)
        XCTAssertEqual(incomplete.count, 1)
        XCTAssertTrue(incomplete[0].detail.contains("thought fragments only"))
    }

    /// A pending input is text the composer held when the export was taken: the
    /// user never sent it, so it cannot open a turn however complete it reads.
    func testPendingInputIsNeverAPrompt() throws {
        let draft = "draft the user never sent"
        let withDraft = try read(
            [
                SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
                SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
            ],
            caseName: "pending", pending: [["text": draft]])
        let asPrompt = try read([
            SnapshotFixture.aiChunk(role: "user", text: draft),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "pending-as-prompt")

        XCTAssertEqual(withDraft.turns.count, 1)
        XCTAssertEqual(withDraft.turns[0].promptText, "synthetic question")
        XCTAssertFalse(
            withDraft.turns.contains { $0.promptText.contains(draft) },
            "an unsent draft must not become a question")
        let drafts = SnapshotFixture.matching(withDraft, .unsentDraft)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertTrue(drafts[0].detail.contains("never sent"))
        XCTAssertTrue(
            drafts[0].locator.hasSuffix(".json#prompt-pending/pendingInputs-0"),
            "locator is file#session/part, with the session taken from the file name")

        // The identical text, once sent, is a prompt: the guard is the location.
        XCTAssertEqual(asPrompt.turns.count, 1)
        XCTAssertEqual(asPrompt.turns[0].promptText, draft)
        XCTAssertEqual(SnapshotFixture.matching(asPrompt, .unsentDraft).count, 0)
    }

    /// User chunks arrive in runs of one to five that form one question.
    func testConsecutiveUserChunksJoinIntoOnePrompt() throws {
        let snapshot = try read([
            SnapshotFixture.aiChunk(role: "user", text: "part one"),
            SnapshotFixture.aiChunk(role: "user", text: "part two"),
            SnapshotFixture.aiChunk(role: "user", text: "part three"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "user-run")

        XCTAssertEqual(snapshot.turns.count, 1, "the run is one question, not three")
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.promptText, "part one\npart two\npart three")
        XCTAssertEqual(turn.identity.sourceTurnID, "prompt-0", "the run is named by its first chunk")
    }

    /// Model output in front of any user chunk has no question to bind to.
    func testModelRunBeforeAnyUserChunkIsReportedUnbound() throws {
        let snapshot = try read([
            SnapshotFixture.aiChunk(role: "model", text: "cold open", finish: "STOP"),
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "cold-open")

        XCTAssertEqual(snapshot.turns.count, 1)
        XCTAssertEqual(snapshot.turns[0].promptText, "synthetic question")
        XCTAssertEqual(snapshot.turns[0].identity.sourceTurnID, "prompt-1")
        let unbound = SnapshotFixture.matching(snapshot, .unboundAnswer)
        XCTAssertEqual(unbound.count, 1)
        XCTAssertTrue(unbound[0].locator.contains("chunks 0-0"))

        // Without the leading run, the same document reports nothing unbound.
        let clean = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "cold-open-control")
        XCTAssertEqual(SnapshotFixture.matching(clean, .unboundAnswer).count, 0)
    }

    /// An error chunk beside the answer means the round did not complete as the
    /// last chunk claimed, and its own text never becomes an answer.
    func testErrorChunkIsExcludedAndDowngradesTheRound() throws {
        let failing = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(
                role: "model", text: "text that came with an error", errorMessage: "rate limited"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "error")
        let clean = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "text that came with an error", finish: "STOP"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "error-control")

        XCTAssertEqual(failing.turns.count, 1)
        let turn = try XCTUnwrap(failing.turns.first)
        XCTAssertFalse(turn.answerText.contains("came with an error"))
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertEqual(turn.disposition, .recordedIncompleteAnswer)
        expectDiagnostic(failing, .unsupportedShape, containing: "error chunk")

        // Same document, no error field: both chunks are answers and the round is
        // retrievable — so the error check is what changed the outcome.
        XCTAssertEqual(clean.turns.count, 1)
        XCTAssertEqual(clean.turns[0].disposition, .retrievable)
        XCTAssertEqual(
            clean.turns[0].answerText, "text that came with an error\n\nsynthetic answer")
    }

    /// A branch marker means the carrier keeps alternatives it does not rank.
    func testBranchMarkerDowngradesTheRound() throws {
        let branched = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question", branch: true),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "branch")
        let linear = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "branch-control")

        XCTAssertEqual(branched.turns.count, 1, "the round is still recorded")
        XCTAssertEqual(branched.turns[0].disposition, .recordedIncompleteAnswer)
        expectDiagnostic(branched, .unsupportedShape, containing: "branch marker")
        XCTAssertEqual(linear.turns[0].disposition, .retrievable)
    }

    /// A function call is traffic inside the round, not content of the answer.
    func testFunctionCallIsToolTrafficNotAnswerContent() throws {
        let snapshot = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: nil, functionCall: true),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "function-call")

        XCTAssertEqual(snapshot.turns.count, 1)
        let turn = try XCTUnwrap(snapshot.turns.first)
        XCTAssertEqual(turn.answerText, "synthetic answer")
        XCTAssertEqual(turn.disposition, .retrievable, "the round did finish")
        let traffic = SnapshotFixture.matching(snapshot, .toolTraffic)
        XCTAssertEqual(traffic.count, 1)
        XCTAssertTrue(traffic[0].locator.contains("chunk-1"))
    }

    /// A user chunk that states no text carries an attachment instead, and a run
    /// whose whole prompt is an attachment has no stated question.
    func testUserChunkWithoutTextIsReportedAndLeavesNoQuestion() throws {
        let attachment = try read([
            SnapshotFixture.aiChunk(role: "user", text: nil),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "attachment")
        let mixed = try read([
            SnapshotFixture.aiChunk(role: "user", text: nil),
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ], caseName: "attachment-mixed")

        XCTAssertEqual(attachment.turns.count, 0)
        XCTAssertEqual(SnapshotFixture.matching(attachment, .skippedAttachment).count, 1)
        XCTAssertEqual(SnapshotFixture.matching(attachment, .incompleteTurn).count, 1)

        // One textless chunk in a run does not lose the question the others state.
        XCTAssertEqual(mixed.turns.count, 1)
        XCTAssertEqual(mixed.turns[0].promptText, "synthetic question")
        XCTAssertEqual(SnapshotFixture.matching(mixed, .skippedAttachment).count, 1)
        XCTAssertEqual(SnapshotFixture.matching(mixed, .incompleteTurn).count, 0)
    }

    /// A stamp that is not a moment stays absent: the bridge must not substitute
    /// an observed time for a carrier that stated none.
    func testStampsThatAreNotMomentsStayAbsent() throws {
        let snapshot = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question", createTime: nil),
            SnapshotFixture.aiChunk(
                role: "model", text: "synthetic answer", finish: "STOP",
                createTime: "not a moment"),
        ], caseName: "bad-stamp")

        XCTAssertEqual(snapshot.turns.count, 1)
        XCTAssertNil(snapshot.turns[0].timestamp)

        let stated = try read([
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question", createTime: nil),
            SnapshotFixture.aiChunk(
                role: "model", text: "synthetic answer", finish: "STOP",
                createTime: "2026-11-07T08:05:00Z"),
        ], caseName: "good-stamp")
        XCTAssertEqual(
            SnapshotFixture.parsed(stated.turns[0].timestamp),
            SnapshotFixture.moment(year: 2026, month: 11, day: 7, hour: 8, minute: 5))
    }

    /// Rounds are sequential questions, not one growing question. The bug this
    /// pins is a prompt block that never resets: `turn 2` would then carry
    /// "first question" in front of its own text.
    func testEachRoundKeepsOnlyItsOwnPrompt() throws {
        let snapshot = try read(
            [
                SnapshotFixture.aiChunk(role: "user", text: "first question"),
                SnapshotFixture.aiChunk(role: "model", text: "first answer", finish: "STOP"),
                SnapshotFixture.aiChunk(role: "user", text: "second question"),
                SnapshotFixture.aiChunk(role: "model", text: "second answer", finish: "STOP"),
            ], caseName: "two-rounds")

        XCTAssertEqual(snapshot.turns.count, 2)
        XCTAssertEqual(snapshot.turns.map(\.promptText), ["first question", "second question"])
        XCTAssertEqual(
            snapshot.turns.map(\.identity.sourceTurnID), ["prompt-0", "prompt-2"],
            "each round is named by the chunk that opened it")
    }

    /// A branch marker belongs to the round that stated it. Carrying the earlier
    /// prompt forward would leave every later round downgraded forever.
    func testBranchMarkerOnAnEarlierPromptDoesNotDowngradeLaterRounds() throws {
        let snapshot = try read(
            [
                SnapshotFixture.aiChunk(role: "user", text: "branched question", branch: true),
                SnapshotFixture.aiChunk(role: "model", text: "branched answer", finish: "STOP"),
                SnapshotFixture.aiChunk(role: "user", text: "later question"),
                SnapshotFixture.aiChunk(role: "model", text: "later answer", finish: "STOP"),
            ], caseName: "branch-then-clear")

        XCTAssertEqual(
            snapshot.turns.map(\.disposition), [.recordedIncompleteAnswer, .retrievable])
        XCTAssertEqual(
            snapshot.diagnostics.filter { $0.detail.contains("branch marker") }.count, 1,
            "the marker is reported for the round that stated it only")
    }

    /// Recognition is structural, and a mis-routed document is an error rather
    /// than an empty import.
    func testRecognitionAndRoutingFailClosed() throws {
        let flat = SnapshotFixture.encode(SnapshotFixture.flatDocument([
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
        ]))
        XCTAssertFalse(AIStudioSource.recognizes(flat))

        let deepseek = SnapshotFixture.encode([
            SnapshotFixture.dsConversation(
                id: "conv-1",
                nodes: [SnapshotFixture.dsNode(id: "1", parent: nil)])
        ])
        XCTAssertFalse(AIStudioSource.recognizes(deepseek))

        // Without `runSettings` the document is not this carrier's shape.
        XCTAssertFalse(
            AIStudioSource.recognizes(
                SnapshotFixture.encode([
                    "chunkedPrompt": [
                        "chunks": [SnapshotFixture.aiChunk(role: "user", text: "question")]
                    ]
                ])))

        let foreignURL = try SnapshotFixture.file(flat, named: "flat.json", in: "as-foreign")
        XCTAssertThrowsError(try AIStudioSource.readSnapshot(at: foreignURL)) { error in
            guard case .foreignDocument(let path, _)? = error as? SnapshotReadError else {
                return XCTFail("expected foreignDocument, got \(error)")
            }
            XCTAssertEqual(path, "flat.json")
        }

        XCTAssertThrowsError(
            try AIStudioSource.interpret(
                SnapshotFixture.encode(["chunkedPrompt": ["chunks": "not a list"]]),
                path: "broken.json", contentDigest: "digest")
        ) { error in
            guard case .foreignDocument? = error as? SnapshotReadError else {
                return XCTFail("expected foreignDocument, got \(error)")
            }
        }
    }
}
