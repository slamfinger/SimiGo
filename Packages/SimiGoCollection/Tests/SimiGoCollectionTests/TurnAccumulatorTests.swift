import Foundation
import XCTest
@testable import SimiGoCollection

final class TurnAccumulatorTests: XCTestCase {

    func testParentChainTurnIsEligible() {
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        XCTAssertEqual(turn.promptRawDigest, SourceDigest.sha256Hex(turn.promptRaw))
        XCTAssertEqual(turn.promptDigest, SourceDigest.sha256Hex("actual question"))
        XCTAssertNotEqual(turn.promptRawDigest, turn.promptDigest)
    }

    func testFileOrderWithoutChainRequiresReview() {
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
            SourceDigest.sha256Hex("first"))
    }

    func testToolLoopOnlySettlesFinalAnswer() {
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(
            context: Fixture.context(isSubagent: true))
        let turns = Fixture.turns(Fixture.feed(accumulator, Fixture.turnLines()))
        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns.first?.isSubagent ?? false)
        XCTAssertEqual(turns.first?.disposition, .internalRecord)
    }

    func testLateAnswerForClosedTurnIsOrphaned() {
        let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
        let events = Fixture.feed(accumulator, [
            Fixture.assistantLine(
                uuid: "a-1", parent: nil, messageID: "m-1", text: "answer")
        ])
        XCTAssertEqual(
            Fixture.orphans(events).first?.reason, .noOpenTurn)
        XCTAssertTrue(Fixture.turns(events).isEmpty)
    }

    func testClosureReasons() {
        func closure(_ lines: [String]) -> ClosureReason? {
            let accumulator = TurnAccumulator(context: Fixture.context())
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
        let accumulator = TurnAccumulator(context: Fixture.context())
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

    func testPendingTurnRetentionIsBoundedAndFailsClosed() {
        let limits = TurnAccumulator.RetentionLimits(
            maxRetainedNodes: 16, maxSeenAnchorIDs: 16,
            maxPendingMessages: 3, maxPendingTerminalTextBytes: 16)
        let accumulator = TurnAccumulator(
            context: Fixture.context(), retentionLimits: limits)
        var lines = [Fixture.userLine(uuid: "u-1", text: "hello")]
        for index in 0..<12 {
            lines.append(Fixture.assistantLine(
                uuid: "a-\(index)", parent: "u-1", messageID: "m-\(index)",
                text: "answer-\(index)"))
        }
        _ = Fixture.feed(accumulator, lines)

        XCTAssertLessThanOrEqual(
            accumulator.retainedPendingMessageCountForTesting,
            limits.maxPendingMessages)
        XCTAssertLessThanOrEqual(
            accumulator.retainedPendingTerminalCountForTesting,
            limits.maxPendingMessages)
        XCTAssertLessThanOrEqual(
            accumulator.retainedPendingTerminalTextBytesForTesting,
            limits.maxPendingTerminalTextBytes)
        XCTAssertTrue(accumulator.pendingHistoryTruncatedForTesting)

        let closeEvents = Fixture.feed(
            accumulator,
            [Fixture.userLine(uuid: "u-2", parent: "a-11", text: "next")],
            startingAt: Int64(lines.count + 1))
        XCTAssertTrue(Fixture.turns(closeEvents).isEmpty)
        XCTAssertEqual(
            Fixture.closures(closeEvents).first?.reason, .historyLimitExceeded)
    }

    func testEvictedAncestryNeverUpgradesAttributionToEligible() {
        let limits = TurnAccumulator.RetentionLimits(
            maxRetainedNodes: 4, maxSeenAnchorIDs: 16,
            maxPendingMessages: 8, maxPendingTerminalTextBytes: 128)
        let accumulator = TurnAccumulator(
            context: Fixture.context(), retentionLimits: limits)
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "part one", stop: nil),
            Fixture.assistantLine(
                uuid: "a-2", parent: "a-1", messageID: "m-1", text: "part two", stop: nil),
            Fixture.assistantLine(
                uuid: "a-3", parent: "a-2", messageID: "m-1", text: "part three", stop: nil),
            Fixture.assistantLine(
                uuid: "a-4", parent: "a-3", messageID: "m-1", text: "answer"),
            Fixture.userLine(uuid: "u-2", parent: "a-4", text: "next"),
        ]
        let events = Fixture.feed(accumulator, lines)
        let turns = Fixture.turns(events)
        XCTAssertLessThanOrEqual(
            accumulator.retainedNodeCountForTesting, limits.maxRetainedNodes)
        XCTAssertLessThanOrEqual(
            accumulator.retainedNodeOrderCountForTesting, limits.maxRetainedNodes * 2)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.relation, .fileOrderNoChain)
        XCTAssertEqual(turns.first?.disposition, .requiresReview(.fileOrderNoChain))
    }

    func testAnchorHistoryCapMakesLaterTurnsFailClosed() {
        let limits = TurnAccumulator.RetentionLimits(
            maxRetainedNodes: 32, maxSeenAnchorIDs: 2,
            maxPendingMessages: 8, maxPendingTerminalTextBytes: 128)
        let accumulator = TurnAccumulator(
            context: Fixture.context(), retentionLimits: limits)
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "one"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "answer one"),
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "two"),
            Fixture.assistantLine(
                uuid: "a-2", parent: "u-2", messageID: "m-2", text: "answer two"),
            Fixture.userLine(uuid: "u-3", parent: "a-2", text: "three"),
        ]
        let events = Fixture.feed(accumulator, lines)
        XCTAssertEqual(accumulator.retainedAnchorIDCountForTesting, 2)
        XCTAssertLessThanOrEqual(
            accumulator.retainedNodeCountForTesting, limits.maxRetainedNodes)
        XCTAssertLessThanOrEqual(
            accumulator.retainedNodeOrderCountForTesting, limits.maxRetainedNodes * 2)
        XCTAssertTrue(accumulator.pendingHistoryTruncatedForTesting)
        XCTAssertTrue(Fixture.turns(events).allSatisfy { $0.disposition == .eligible })
        let closeEvents = Fixture.feed(
            accumulator,
            [Fixture.userLine(uuid: "u-4", parent: "u-3", text: "four")],
            startingAt: Int64(lines.count + 1))
        XCTAssertTrue(Fixture.turns(closeEvents).isEmpty)
        XCTAssertEqual(
            Fixture.closures(closeEvents).first?.reason, .historyLimitExceeded)
    }

    func testOversizedIdentifiersAndPromptsFailClosedWithoutRetention() {
        let limits = TurnAccumulator.RetentionLimits(
            maxRetainedNodes: 8, maxSeenAnchorIDs: 4,
            maxPendingMessages: 2, maxPendingTerminalTextBytes: 64,
            maxIdentifierBytes: 32, maxPendingPromptBytes: 128)
        let accumulator = TurnAccumulator(
            context: Fixture.context(), retentionLimits: limits)
        let oversized = String(repeating: "x", count: 1_024)
        let lines = [
            Fixture.userLine(uuid: oversized, text: oversized),
            Fixture.assistantLine(
                uuid: oversized + "-assistant", parent: oversized,
                messageID: oversized, text: "answer"),
        ]
        _ = Fixture.feed(accumulator, lines)

        XCTAssertTrue(accumulator.pendingHistoryTruncatedForTesting)
        XCTAssertLessThanOrEqual(
            accumulator.retainedNodeCountForTesting, limits.maxRetainedNodes)
        XCTAssertLessThanOrEqual(
            accumulator.retainedNodeOrderCountForTesting, limits.maxRetainedNodes * 2)
        XCTAssertLessThanOrEqual(
            accumulator.retainedAnchorIDCountForTesting, limits.maxSeenAnchorIDs)
        XCTAssertTrue(
            accumulator.retainedIdentifiersForTesting.allSatisfy {
                $0.utf8.count <= limits.maxIdentifierBytes
            })
        XCTAssertLessThanOrEqual(
            accumulator.retainedPendingMessageCountForTesting, limits.maxPendingMessages)
        XCTAssertLessThanOrEqual(
            accumulator.retainedPendingTerminalTextBytesForTesting,
            limits.maxPendingTerminalTextBytes)

        let closeEvents = Fixture.feed(
            accumulator,
            [Fixture.userLine(uuid: "u-2", text: "next")],
            startingAt: Int64(lines.count + 1))
        XCTAssertTrue(Fixture.turns(closeEvents).isEmpty)
        XCTAssertEqual(
            Fixture.closures(closeEvents).first?.reason, .historyLimitExceeded)
    }

    func testRepeatedTerminalUpdatesRetainOneTextAndDetectConflict() {
        let limits = TurnAccumulator.RetentionLimits(
            maxRetainedNodes: 64, maxSeenAnchorIDs: 32,
            maxPendingMessages: 2, maxPendingTerminalTextBytes: 64)
        let accumulator = TurnAccumulator(
            context: Fixture.context(), retentionLimits: limits)
        var lines = [Fixture.userLine(uuid: "u-1", text: "hello")]
        for index in 0..<20 {
            let parent = index == 0 ? "u-1" : "a-\(index - 1)"
            lines.append(Fixture.assistantLine(
                uuid: "a-\(index)", parent: parent, messageID: "m-1",
                text: "answer-\(index)"))
        }
        _ = Fixture.feed(accumulator, lines)

        XCTAssertEqual(accumulator.retainedPendingMessageCountForTesting, 1)
        XCTAssertEqual(accumulator.retainedPendingTerminalCountForTesting, 1)
        XCTAssertLessThanOrEqual(
            accumulator.retainedPendingTerminalTextBytesForTesting,
            limits.maxPendingTerminalTextBytes)
        XCTAssertFalse(accumulator.pendingHistoryTruncatedForTesting)

        let closeEvents = Fixture.feed(
            accumulator,
            [Fixture.userLine(uuid: "u-2", parent: "a-19", text: "next")],
            startingAt: Int64(lines.count + 1))
        XCTAssertEqual(
            Fixture.closures(closeEvents).first?.reason, .ambiguousTerminal)
        XCTAssertTrue(Fixture.turns(closeEvents).isEmpty)
    }

    func testFlushCurrentTurnUsesEndOfInputBoundary() {
        let accumulator = TurnAccumulator(context: Fixture.context())
        _ = Fixture.feed(accumulator, [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(
                uuid: "a-1", parent: "u-1", messageID: "m-1", text: "answer"),
        ])
        var events: [CollectionEvent] = []
        accumulator.flushCurrentTurn(boundary: .endOfInput, into: &events)
        XCTAssertEqual(Fixture.turns(events).first?.finalizedBy, .endOfInput)
        XCTAssertFalse(accumulator.hasOpenTurn)
    }
}
