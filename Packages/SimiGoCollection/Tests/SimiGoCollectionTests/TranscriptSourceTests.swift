import Foundation
import XCTest

@testable import SimiGoCollection

final class TranscriptSourceTests: XCTestCase {
    /// What the accepted information sink does with a disposition, transcribed
    /// from `SimiGo/App/ExternalTurnSink.swift` (`write(_:)`). The package
    /// cannot import the App, so this is the reference oracle for equivalence;
    /// if that switch changes, this table has to change with it.
    private struct SinkConsequence: Equatable {
        let verified: Bool
        let internalOperation: Bool
    }

    private func sinkConsequence(_ disposition: TurnDisposition) -> SinkConsequence {
        switch disposition {
        case .eligible,
            .requiresReview(.fileOrderAfterCompaction),
            .requiresReview(.fileOrderNoChain),
            .deferredAutoTurn(.queuedCommand):
            return SinkConsequence(verified: true, internalOperation: false)
        case .requiresReview(.interrupted), .deferredAutoTurn:
            return SinkConsequence(verified: false, internalOperation: false)
        case .internalRecord:
            return SinkConsequence(verified: false, internalOperation: true)
        }
    }

    private func makeTurn(
        disposition: TurnDisposition,
        relation: AttributionRelation = .parentChain
    ) -> CollectedTurnRecord {
        CollectedTurnRecord(
            candidateID: "qoder:s-1:u-1:m-1",
            identity: SourceIdentity(
                sourceSessionID: "s-1", sourceTurnID: "u-1", sourceMessageID: "m-1"),
            projectID: "p-1", sessionID: "s-1", isSubagent: false,
            anchor: AnchorSummary(
                id: "u-1", kind: .humanPrompt, segmentLine: 1,
                timestamp: "2026-01-01T00:00:00.000Z", originKind: nil, isSidechain: false),
            promptRaw: "question", promptText: "question",
            promptRawDigest: SourceDigest.sha256Hex("question"),
            promptDigest: SourceDigest.sha256Hex("question"),
            answerText: "answer", answerDigest: SourceDigest.sha256Hex("answer"),
            messageID: "m-1", answerModel: "model-1",
            timestamp: "2026-01-01T00:00:01.000Z",
            relation: relation, disposition: disposition, interrupted: false,
            apiErrorAttempts: 0, supersededEndTurns: [], firstSegmentLine: 1,
            lastSegmentLine: 2, finalizedBy: .nextAnchor)
    }

    func testQoderSourceDeclaresThePersistedNamespaceAndSessionShape() throws {
        XCTAssertEqual(TranscriptSourceAdapter.sourceType, "qoder")
        XCTAssertEqual(
            TranscriptSourceAdapter.adapterVersion, SourceIdentity.adapterVersion)
        XCTAssertEqual(TranscriptSourceAdapter.sourceKind, .appendOnlyLog)
        XCTAssertEqual(
            TranscriptSourceAdapter.sessionKey(projectID: "p-1", sessionID: "s-1"),
            "qoder:p-1/s-1")

        let neutral = TranscriptSourceAdapter.identity(
            sessionID: "s-1", turnID: "u-1", messageID: "m-1")
        let qoder = SourceIdentity(
            sourceSessionID: "s-1", sourceTurnID: "u-1", sourceMessageID: "m-1")
        XCTAssertEqual(neutral.operationKey, qoder.operationKey)
        XCTAssertEqual(neutral.sourceRevision, 1)
        XCTAssertEqual(
            TranscriptSourceAdapter.identity(
                sessionID: "s-1", turnID: "u-1", messageID: "m-1", revision: 4
            ).sourceRevision, 4)
    }

    func testNeutralTurnCarriesTheSinkSessionKeyRequestIDAndText() throws {
        let turn = makeTurn(disposition: .eligible)
        let neutral = turn.collectedTurn
        XCTAssertEqual(neutral.sessionKey, "qoder:\(turn.projectID)/\(turn.sessionID)")
        XCTAssertEqual(neutral.provider, "qoder")
        XCTAssertEqual(neutral.identity.operationKey, turn.identity.operationKey)
        XCTAssertEqual(neutral.promptText, turn.promptText)
        XCTAssertEqual(neutral.answerText, turn.answerText)
        XCTAssertEqual(neutral.promptDigest, turn.promptDigest)
        XCTAssertEqual(neutral.answerDigest, turn.answerDigest)
        XCTAssertEqual(neutral.answerModel, turn.answerModel)
        XCTAssertEqual(neutral.timestamp, turn.timestamp)
        // Qoder's transcript has no separate reasoning channel. Nil means "not
        // observed"; an empty string would claim it was observed and empty.
        XCTAssertNil(neutral.reasoningText)
    }

    /// Every disposition variant, paired against the sink's own consequence.
    /// The table is the negative control for a constant mapping: four distinct
    /// outcomes across ten inputs, so collapsing them would fail here.
    func testNeutralGradingMatchesTheAcceptedSinkForEveryDisposition() throws {
        let cases: [(TurnDisposition, CollectionTurnDisposition)] = [
            (.eligible, .retrievable),
            (.requiresReview(.fileOrderAfterCompaction), .retrievable),
            (.requiresReview(.fileOrderNoChain), .retrievable),
            (.requiresReview(.interrupted), .recordedIncompleteAnswer),
            (.deferredAutoTurn(.queuedCommand), .retrievable),
            (.deferredAutoTurn(.humanPrompt), .recordedAutomatedTurn),
            (.deferredAutoTurn(.continuationPrompt), .recordedAutomatedTurn),
            (.deferredAutoTurn(.notificationPrompt), .recordedAutomatedTurn),
            (.deferredAutoTurn(.supervisionCallback), .recordedAutomatedTurn),
            (.internalRecord, .auditOnly),
        ]
        var outcomes = Set<CollectionTurnDisposition>()
        for (disposition, expected) in cases {
            let neutral = makeTurn(disposition: disposition).collectedTurn
            XCTAssertEqual(
                neutral.disposition, expected, "disposition \(disposition)")
            outcomes.insert(neutral.disposition)

            let sink = sinkConsequence(disposition)
            XCTAssertEqual(
                neutral.disposition == .retrievable, sink.verified,
                "retrievable must mean exactly what the sink verifies: \(disposition)")
            XCTAssertEqual(
                neutral.disposition == .auditOnly, sink.internalOperation,
                "auditOnly must mean exactly the sink's internalOperation: \(disposition)")
        }
        XCTAssertEqual(outcomes.count, 4)
    }

    func testNeutralAttributionCoversAllThreeRelationsDistinctly() throws {
        let cases: [(AttributionRelation, CollectionAttribution)] = [
            (.parentChain, .declared),
            (.fileOrderAfterCompaction, .fileOrderAfterCompaction),
            (.fileOrderNoChain, .fileOrderOnly),
        ]
        var outcomes = Set<CollectionAttribution>()
        for (relation, expected) in cases {
            let neutral = makeTurn(disposition: .eligible, relation: relation).collectedTurn
            XCTAssertEqual(neutral.attribution, expected)
            outcomes.insert(neutral.attribution)
        }
        XCTAssertEqual(outcomes.count, 3)
    }

    /// A real accumulator-produced turn, not a hand-built one: the mapping has
    /// to hold on the shape the collector actually emits.
    func testAccumulatorTurnsMapWithoutLosingIdentityOrText() throws {
        let events = Fixture.feed(
            TurnAccumulator(context: Fixture.context()), Fixture.turnLines())
        let turns = Fixture.turns(events)
        XCTAssertFalse(turns.isEmpty)
        for turn in turns {
            let neutral = turn.collectedTurn
            XCTAssertEqual(neutral.identity.operationKey, turn.identity.operationKey)
            XCTAssertEqual(
                neutral.sessionKey, "qoder:\(turn.projectID)/\(turn.sessionID)")
            XCTAssertEqual(neutral.promptText, turn.promptText)
            XCTAssertEqual(neutral.answerText, turn.answerText)
            XCTAssertEqual(
                neutral.disposition == .retrievable,
                sinkConsequence(turn.disposition).verified)
        }
    }
}