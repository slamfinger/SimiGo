import Foundation
import XCTest
@testable import SimiGoCollection

final class QoderTurnAccumulatorTests: XCTestCase {

    func testParentChainTurnIsEligible() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let events = Fixture.feed(accumulator, Fixture.turnLines())
        let turns = Fixture.turns(events)
        XCTAssertEqual(turns.count, 1)
        guard let turn = turns.first else { return }
        XCTAssertEqual(turn.anchor.id, "u-1")
        XCTAssertEqual(turn.anchor.kind, .humanPrompt)
        XCTAssertEqual(turn.promptText, "hello")
        XCTAssertEqual(turn.answerText, "world")
        XCTAssertEqual(turn.messageID, "m-1")
        XCTAssertEqual(turn.relation, .parentChain)
        XCTAssertEqual(turn.disposition, .eligible)
        XCTAssertFalse(turn.interrupted)
        XCTAssertEqual(turn.apiErrorAttempts, 0)
        XCTAssertTrue(turn.supersededEndTurns.isEmpty)
        XCTAssertEqual(turn.finalizedBy, .nextAnchor)
        XCTAssertEqual(turn.candidateID, "qoder:session-1:u-1:m-1")
        XCTAssertEqual(turn.identity.sourceType, "qoder")
        XCTAssertEqual(turn.identity.sourceSessionID, "session-1")
        XCTAssertEqual(turn.identity.sourceTurnID, "u-1")
        XCTAssertEqual(turn.identity.sourceMessageID, "m-1")
        XCTAssertEqual(turn.identity.sourceRevision, 1)
        XCTAssertEqual(turn.identity.adapterVersion, "qoder-transcript-final/v1")
        XCTAssertTrue(Fixture.closures(events).isEmpty)
    }

    func testInjectedPrefixKeepsRawAndSemanticDigestsApart() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(
                uuid: "u-1",
                text: "<system-reminder>ctx</system-reminder>\nactual question"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "answer"),
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
        ]
        let turns = Fixture.turns(Fixture.feed(accumulator, lines))
        XCTAssertEqual(turns.count, 1)
        guard let turn = turns.first else { return }
        XCTAssertEqual(turn.promptText, "actual question")
        XCTAssertTrue(turn.promptRaw.contains("<system-reminder>"))
        XCTAssertEqual(turn.promptRawDigest, QoderDigest.sha256Hex(turn.promptRaw))
        XCTAssertEqual(turn.promptDigest, QoderDigest.sha256Hex("actual question"))
        XCTAssertNotEqual(turn.promptRawDigest, turn.promptDigest)
    }

    func testFileOrderWithoutChainRequiresReview() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "missing-parent", messageID: "m-1",
                text: "answer"),
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
        ]
        let turns = Fixture.turns(Fixture.feed(accumulator, lines))
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.relation, .fileOrderNoChain)
        XCTAssertEqual(turns.first?.disposition, .requiresReview(.fileOrderNoChain))
    }

    func testCompactionBoundaryIsAttributionNotFinalization() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "before"),
            Fixture.systemCompactLine(uuid: "sys-1"),
            Fixture.userLine(
                uuid: "c-1", parent: "sys-1", text: "summary", isCompactSummary: true,
                isVisibleInTranscriptOnly: true),
            Fixture.assistantLine(
                uuid: "a-2", parent: "c-1", messageID: "m-2", text: "after"),
            Fixture.userLine(uuid: "u-2", parent: "a-2", text: "next"),
        ]
        let events = Fixture.feed(accumulator, lines)
        XCTAssertEqual(Fixture.compactions(events).count, 1)
        XCTAssertTrue(Fixture.closures(events).isEmpty)
        let turns = Fixture.turns(events)
        XCTAssertEqual(turns.count, 1)
        guard let turn = turns.first else { return }
        XCTAssertEqual(turn.answerText, "after")
        XCTAssertEqual(turn.relation, .fileOrderAfterCompaction)
        XCTAssertEqual(
            turn.disposition, .requiresReview(.fileOrderAfterCompaction))
        XCTAssertEqual(turn.supersededEndTurns.map(\.messageID), ["m-1"])
        XCTAssertEqual(turn.finalizedBy, .nextAnchor)
    }

    func testLatestEndTurnWinsAndEarlierAnswersAreSuperseded() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "first"),
            Fixture.assistantLine(
                uuid: "a-2", parent: "a-1", messageID: "m-2", text: "second"),
            Fixture.userLine(uuid: "u-2", parent: "a-2", text: "next"),
        ]
        let turns = Fixture.turns(Fixture.feed(accumulator, lines))
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.answerText, "second")
        XCTAssertEqual(turns.first?.messageID, "m-2")
        XCTAssertEqual(turns.first?.supersededEndTurns.count, 1)
        XCTAssertEqual(
            turns.first?.supersededEndTurns.first?.answerDigest,
            QoderDigest.sha256Hex("first"))
    }

    func testToolLoopOnlySettlesFinalAnswer() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "use a tool"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "",
                stop: "tool_use"),
            Fixture.assistantLine(
                uuid: "a-2", parent: "a-1", messageID: "m-2", text: "done"),
            Fixture.userLine(uuid: "u-2", parent: "a-2", text: "next"),
        ]
        let events = Fixture.feed(accumulator, lines)
        let turns = Fixture.turns(events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.answerText, "done")
        XCTAssertTrue(turns.first?.supersededEndTurns.isEmpty ?? false)
        XCTAssertEqual(turns.first?.apiErrorAttempts, 0)
        XCTAssertTrue(Fixture.closures(events).isEmpty)
    }

    func testAPIErrorAttemptIsCountedButDoesNotBlockRetry() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "quota",
                apiError: true),
            Fixture.assistantLine(
                uuid: "a-2", parent: "a-1", messageID: "m-2", text: "ok"),
            Fixture.userLine(uuid: "u-2", parent: "a-2", text: "next"),
        ]
        let turns = Fixture.turns(Fixture.feed(accumulator, lines))
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.answerText, "ok")
        XCTAssertEqual(turns.first?.apiErrorAttempts, 1)
        XCTAssertEqual(turns.first?.disposition, .eligible)
    }

    func testSnapshotCoalescingUsesLatestText() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "Hel",
                stop: nil),
            Fixture.assistantLine(
                uuid: "a-2", parent: "a-1", messageID: "m-1", text: "Hello"),
            Fixture.userLine(uuid: "u-2", parent: "a-2", text: "next"),
        ]
        let events = Fixture.feed(accumulator, lines)
        let turns = Fixture.turns(events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.answerText, "Hello")
        XCTAssertTrue(turns.first?.supersededEndTurns.isEmpty ?? false)
        XCTAssertTrue(Fixture.closures(events).isEmpty)
    }

    func testConflictingTerminalsForOneMessageAreAmbiguous() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "first"),
            Fixture.assistantLine(
                uuid: "a-2", parent: "a-1", messageID: "m-1", text: "second"),
            Fixture.userLine(uuid: "u-2", parent: "a-2", text: "next"),
        ]
        let events = Fixture.feed(accumulator, lines)
        XCTAssertTrue(Fixture.turns(events).isEmpty)
        XCTAssertEqual(Fixture.closures(events).first?.reason, .ambiguousTerminal)
    }

    func testInterruptMarkerMarksTurnButDoesNotCloseIt() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let beforeNextAnchor = Fixture.feed(accumulator, [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "partial"),
            Fixture.userLine(uuid: "i-1", parent: "a-1", text: "[Request interrupted by user]"),
        ])
        XCTAssertTrue(Fixture.turns(beforeNextAnchor).isEmpty)
        XCTAssertTrue(Fixture.closures(beforeNextAnchor).isEmpty)

        let events = Fixture.feed(
            accumulator,
            [
                Fixture.assistantLine(
                    uuid: "a-2", parent: "u-1", messageID: "m-2", text: "late answer"),
                Fixture.userLine(uuid: "u-2", parent: "a-2", text: "next"),
            ], startingAt: 4)
        let turns = Fixture.turns(events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.answerText, "late answer")
        XCTAssertTrue(turns.first?.interrupted ?? false)
        XCTAssertEqual(turns.first?.disposition, .requiresReview(.interrupted))
    }

    func testGoalContinuationIsDeferredNotEligible() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.userLine(
                uuid: "g-1", text: "Continue working toward the active thread goal.",
                isMeta: true),
            Fixture.assistantLine(
                uuid: "a-1", parent: "g-1", messageID: "m-1", text: "worked"),
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
        ]
        let turns = Fixture.turns(Fixture.feed(accumulator, lines))
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.anchor.kind, .continuationPrompt)
        XCTAssertEqual(
            turns.first?.disposition, .deferredAutoTurn(.continuationPrompt))
        XCTAssertEqual(turns.first?.relation, .parentChain)
    }

    func testQueuedCommandIsAnAnchorAndDeferred() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let lines = [
            Fixture.queuedLine(uuid: "att-1", sourceUUID: "q-1", prompt: "steer"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "att-1", messageID: "m-1", text: "steered"),
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
        ]
        let turns = Fixture.turns(Fixture.feed(accumulator, lines))
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.anchor.id, "q-1")
        XCTAssertEqual(turns.first?.anchor.kind, .queuedCommand)
        XCTAssertEqual(
            turns.first?.disposition, .deferredAutoTurn(.queuedCommand))
        XCTAssertEqual(turns.first?.relation, .parentChain)
    }

    func testSubagentTurnsAreInternalRecords() {
        let accumulator = QoderTurnAccumulator(
            context: Fixture.context(isSubagent: true))
        let turns = Fixture.turns(Fixture.feed(accumulator, Fixture.turnLines()))
        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns.first?.isSubagent ?? false)
        XCTAssertEqual(turns.first?.disposition, .internalRecord)
    }

    func testLateAnswerForClosedTurnIsOrphaned() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let events = Fixture.feed(accumulator, [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "answer"),
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            Fixture.assistantLine(
                uuid: "a-2", parent: "u-1", messageID: "m-2", text: "late"),
            Fixture.userLine(uuid: "u-3", parent: "a-2", text: "next again"),
        ])
        XCTAssertEqual(Fixture.turns(events).count, 1)
        XCTAssertEqual(
            Fixture.orphans(events).first?.reason, .lateForClosedTurn)
        XCTAssertEqual(
            Fixture.orphans(events).first?.messageID, "m-2")
        XCTAssertEqual(Fixture.closures(events).first?.reason, .noAnswer)
    }

    func testAssistantWithoutOpenTurnIsOrphaned() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let events = Fixture.feed(accumulator, [
            Fixture.assistantLine(
                uuid: "a-1", parent: nil, messageID: "m-1", text: "answer")
        ])
        XCTAssertEqual(
            Fixture.orphans(events).first?.reason, .noOpenTurn)
        XCTAssertTrue(Fixture.turns(events).isEmpty)
    }

    func testClosureReasons() {
        func closure(_ lines: [String]) -> QoderClosureReason? {
            let accumulator = QoderTurnAccumulator(context: Fixture.context())
            return Fixture.closures(Fixture.feed(accumulator, lines)).first?.reason
        }
        XCTAssertEqual(
            closure([
                Fixture.userLine(uuid: "u-1", text: "hello"),
                Fixture.userLine(uuid: "u-2", parent: "u-1", text: "next"),
            ]), .noAnswer)
        XCTAssertEqual(
            closure([
                Fixture.userLine(uuid: "u-1", text: "hello"),
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: ""),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ]), .emptyAnswer)
        XCTAssertEqual(
            closure([
                Fixture.userLine(uuid: "u-1", text: "hello"),
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "x",
                    stop: "stop_sequence"),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ]), .stopSequence)
        XCTAssertEqual(
            closure([
                Fixture.userLine(uuid: "u-1", text: "hello"),
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "",
                    stop: "tool_use"),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ]), .toolOnly)
    }

    func testDuplicateAnchorIDIsIgnored() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let events = Fixture.feed(accumulator, [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "answer"),
            Fixture.userLine(uuid: "u-1", text: "hello duplicated"),
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
        ])
        XCTAssertEqual(Fixture.turns(events).count, 1)
        XCTAssertEqual(Fixture.turns(events).first?.promptText, "hello")
    }

    func testFlushCurrentTurnUsesEndOfInputBoundary() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        _ = Fixture.feed(accumulator, [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "answer"),
        ])
        var events: [QoderCollectionEvent] = []
        accumulator.flushCurrentTurn(boundary: .endOfInput, into: &events)
        XCTAssertEqual(Fixture.turns(events).first?.finalizedBy, .endOfInput)
        XCTAssertFalse(accumulator.hasOpenTurn)
    }
}
