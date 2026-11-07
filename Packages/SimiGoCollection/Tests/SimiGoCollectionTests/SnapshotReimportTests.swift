import Foundation
import XCTest

@testable import SimiGoCollection

/// Paired tests for whole-file snapshot re-import adjudication.
///
/// Every fixture is produced by a real adapter, so the turns under comparison
/// carry the identities the carrier would actually state. The negative controls
/// are the cases where a naive "same file, same content" rule would silently
/// duplicate, collide, or forget: a restated answer that must become a new
/// revision, a rename that must not re-deliver stated identities, and a turn
/// the document dropped that must not be forgotten.
final class SnapshotReimportTests: XCTestCase {
    // MARK: - Fixtures

    private func flatSnapshot(
        _ rows: [[String: Any]], named name: String = "flat-export.json",
        sessionID: String? = "flat-session-1",
        mutate: (inout [String: Any]) -> Void = { _ in }
    ) throws -> SnapshotImport {
        var document = SnapshotFixture.flatDocument(rows, sessionID: sessionID)
        mutate(&document)
        let data = SnapshotFixture.encode(document)
        return try FlatMessageExportSource.interpret(
            data, path: name, contentDigest: CollectionDigest.sha256Hex(data))
    }

    /// Two complete rounds over the flat carrier. `includeSecond` drops the
    /// second round entirely, which is how a rewrite that lost content looks.
    private func flatRows(
        secondAnswer: String = "second answer", includeSecond: Bool = true
    ) -> [[String: Any]] {
        var rows = [
            SnapshotFixture.flatRow(id: 1, role: "user", text: "first question"),
            SnapshotFixture.flatRow(id: 2, role: "assistant", text: "first answer", finish: "stop"),
        ]
        if includeSecond {
            rows += [
                SnapshotFixture.flatRow(id: 3, role: "user", text: "second question"),
                SnapshotFixture.flatRow(id: 4, role: "assistant", text: secondAnswer, finish: "stop"),
            ]
        }
        return rows
    }

    private func deepSeekSnapshot(
        named name: String = "conversations.json", answer: String = "synthetic answer"
    ) throws -> SnapshotImport {
        let document = SnapshotFixture.dsConversation(id: "conv-1", nodes: [
            SnapshotFixture.dsNode(id: "0", parent: nil, children: ["1"], fragments: nil),
            SnapshotFixture.dsNode(
                id: "1", parent: "0", children: ["2"],
                fragments: [SnapshotFixture.dsFragment(type: "REQUEST", content: "synthetic question")]),
            SnapshotFixture.dsNode(
                id: "2", parent: "1",
                fragments: [SnapshotFixture.dsFragment(type: "RESPONSE", content: answer)]),
        ])
        let data = SnapshotFixture.encode([document])
        return try DeepSeekSource.interpret(
            data, path: name, contentDigest: CollectionDigest.sha256Hex(data))
    }

    private func decide(
        _ snapshot: SnapshotImport, ledger: SnapshotReimportLedger?,
        source: String = FlatMessageExportSource.sourceType,
        version: String = FlatMessageExportSource.adapterVersion,
        document: String = "flat-export.json"
    ) throws -> SnapshotReimportDecision {
        try SnapshotReimport.decide(
            sourceType: source, adapterVersion: version, documentKey: document,
            snapshot: snapshot, ledger: ledger)
    }

    // MARK: - Byte identity

    func testFirstImportDeliversEveryTurnAndASecondReadDeliversNothing() throws {
        let snapshot = try flatSnapshot(flatRows())
        let first = try decide(snapshot, ledger: nil)

        XCTAssertEqual(first.rebaselineReason, .firstImport)
        XCTAssertFalse(first.documentUnchanged)
        XCTAssertEqual(first.turns.map(\.identity.sourceTurnID), ["1", "3"])
        XCTAssertEqual(first.turns.map(\.identity.sourceRevision), [1, 1])
        XCTAssertEqual(first.unchangedTurnCount, 0)
        XCTAssertTrue(first.vanishedTurns.isEmpty)
        XCTAssertEqual(
            first.turns.map(\.identity.operationKey),
            snapshot.turns.map(\.identity.operationKey),
            "a first import is the adapter's own identities, not a re-interpretation")

        let second = try decide(snapshot, ledger: first.ledger)
        XCTAssertTrue(second.documentUnchanged, "identical bytes are the same document")
        XCTAssertTrue(second.turns.isEmpty)
        XCTAssertEqual(second.unchangedTurnCount, 2)
        XCTAssertEqual(second.ledger, first.ledger, "nothing changed, so nothing to commit")
    }

    func testMetadataOnlyRewriteMovesTheDigestWithoutDelivering() throws {
        let rows = flatRows()
        let initial = try decide(try flatSnapshot(rows), ledger: nil)
        let rewritten = try flatSnapshot(rows) {
            $0["title"] = "synthetic export, re-saved"
        }
        XCTAssertNotEqual(rewritten.contentDigest, initial.ledger.documents["flat-export.json"]?.contentDigest)

        let decision = try decide(rewritten, ledger: initial.ledger)
        XCTAssertFalse(decision.documentUnchanged, "the bytes differ even though the turns do not")
        XCTAssertTrue(decision.turns.isEmpty)
        XCTAssertEqual(decision.unchangedTurnCount, 2)
        XCTAssertEqual(
            decision.ledger.documents["flat-export.json"]?.contentDigest,
            rewritten.contentDigest,
            "the new digest must be committed or the rewrite would be re-read forever")

        let again = try decide(rewritten, ledger: decision.ledger)
        XCTAssertTrue(again.documentUnchanged)
        XCTAssertTrue(again.turns.isEmpty)
    }

    // MARK: - Revisions

    func testAppendedDocumentDeliversOnlyTheNewTurn() throws {
        let initial = try decide(try flatSnapshot(flatRows(includeSecond: false)), ledger: nil)
        XCTAssertEqual(initial.turns.count, 1)

        let grown = try flatSnapshot(flatRows())
        let decision = try decide(grown, ledger: initial.ledger)
        XCTAssertFalse(decision.documentUnchanged)
        XCTAssertEqual(decision.turns.map(\.identity.sourceTurnID), ["3"])
        XCTAssertEqual(decision.turns.map(\.identity.sourceRevision), [1])
        XCTAssertEqual(decision.unchangedTurnCount, 1)
        XCTAssertEqual(
            decision.turns.first?.identity.operationKey,
            grown.turns.last?.identity.operationKey)
    }

    func testChangedTurnBecomesTheNextRevisionAndAReplayIsIdentical() throws {
        let original = try flatSnapshot(flatRows())
        let initial = try decide(original, ledger: nil)

        let changed = try flatSnapshot(flatRows(secondAnswer: "second answer, restated"))
        let revised = try decide(changed, ledger: initial.ledger)
        let turn = try XCTUnwrap(revised.turns.first)
        XCTAssertEqual(revised.turns.count, 1)
        XCTAssertEqual(turn.identity.sourceTurnID, "3")
        XCTAssertEqual(turn.identity.sourceRevision, 2)
        XCTAssertEqual(turn.answerText, "second answer, restated")
        XCTAssertEqual(revised.unchangedTurnCount, 1)
        XCTAssertEqual(
            turn.identity.operationKey,
            FlatMessageExportSource.identity(
                sessionID: "flat-session-1", turnID: "3", messageID: "4", revision: 2
            ).operationKey,
            "the delivered turn names the revision, not the adapter's revision 1")
        XCTAssertNotEqual(
            turn.identity.operationKey,
            changed.turns.last?.identity.operationKey)

        let replay = try decide(changed, ledger: initial.ledger)
        XCTAssertEqual(
            replay, revised,
            "a crash between deciding and committing regenerates the same revision")

        let reverted = try decide(original, ledger: revised.ledger)
        XCTAssertEqual(
            reverted.turns.map(\.identity.sourceRevision), [3],
            "returning to older content is still a new revision, never revision 1 again")
        XCTAssertEqual(reverted.turns.first?.answerText, "second answer")
    }

    // MARK: - Vanished turns

    func testVanishedTurnIsReportedRememberedAndNeverRedelivered() throws {
        let rows = flatRows()
        let initial = try decide(try flatSnapshot(rows), ledger: nil)

        let shrunk = try decide(
            try flatSnapshot(Array(rows.prefix(2))), ledger: initial.ledger)
        XCTAssertTrue(shrunk.turns.isEmpty)
        XCTAssertEqual(shrunk.unchangedTurnCount, 1)
        XCTAssertEqual(shrunk.vanishedTurns.map(\.turnID), ["3"])
        XCTAssertEqual(shrunk.vanishedTurns.first?.revision, 1)
        XCTAssertEqual(
            shrunk.ledger.sessions["flat-session-1"]?.count, 2,
            "the removed turn stays in the ledger; information space cannot delete it")

        let restored = try decide(try flatSnapshot(rows), ledger: shrunk.ledger)
        XCTAssertTrue(restored.turns.isEmpty, "the record prevents a redelivery")
        XCTAssertEqual(restored.unchangedTurnCount, 2)
        XCTAssertTrue(restored.vanishedTurns.isEmpty)

        let changed = try flatSnapshot(flatRows(secondAnswer: "second answer, restated"))
        let reasserted = try decide(changed, ledger: shrunk.ledger)
        XCTAssertEqual(
            reasserted.turns.map(\.identity.sourceRevision), [2],
            "a vanished turn that returns changed must not reuse its delivered revision 1")
    }

    /// One state directory holds many documents. A rewrite of one of them says
    /// nothing about the others, so their turns must not be reported as this
    /// document's deletions.
    func testVanishIsScopedToTheDocumentThatStatedIt() throws {
        func document(_ name: String, session: String, appended: Bool) throws -> SnapshotImport {
            var rows = [
                SnapshotFixture.flatRow(id: 1, role: "user", text: "\(name) question"),
                SnapshotFixture.flatRow(id: 2, role: "assistant", text: "\(name) answer", finish: "stop"),
            ]
            if appended {
                rows += [
                    SnapshotFixture.flatRow(id: 3, role: "user", text: "\(name) follow-up"),
                    SnapshotFixture.flatRow(id: 4, role: "assistant", text: "\(name) follow-up answer", finish: "stop"),
                ]
            }
            return try flatSnapshot(rows, named: "\(name).json", sessionID: session)
        }

        let firstA = try decide(try document("alpha", session: "session-alpha", appended: false),
                                ledger: nil, document: "alpha.json")
        let firstB = try decide(try document("beta", session: "session-beta", appended: false),
                                ledger: firstA.ledger, document: "beta.json")
        XCTAssertEqual(firstB.turns.count, 1)

        let rereadA = try decide(
            try document("alpha", session: "session-alpha", appended: true),
            ledger: firstB.ledger, document: "alpha.json")
        XCTAssertEqual(rereadA.turns.map(\.identity.sourceTurnID), ["3"])
        XCTAssertTrue(
            rereadA.vanishedTurns.isEmpty,
            "beta's turn belongs to another document and is not this document's deletion")
        XCTAssertEqual(rereadA.unchangedTurnCount, 1)
    }

    // MARK: - Document identity

    func testRenameIsHarmlessOnlyWhenTheDocumentStatesItsSession() throws {
        let deepSeek = try deepSeekSnapshot(named: "conversations.json")
        let first = try decide(
            deepSeek, ledger: nil, source: DeepSeekSource.sourceType,
            version: DeepSeekSource.adapterVersion, document: "conversations.json")
        XCTAssertEqual(first.turns.count, 1)

        let renamed = try deepSeekSnapshot(named: "renamed.json")
        let second = try decide(
            renamed, ledger: first.ledger, source: DeepSeekSource.sourceType,
            version: DeepSeekSource.adapterVersion, document: "renamed.json")
        XCTAssertFalse(second.documentUnchanged, "the document key really is new")
        XCTAssertTrue(second.turns.isEmpty, "the stated session carries the identity")
        XCTAssertEqual(second.unchangedTurnCount, 1)

        let flatNamed = try flatSnapshot(flatRows(), named: "flat-export.json", sessionID: nil)
        let flatInitial = try decide(flatNamed, ledger: nil, document: "flat-export.json")
        let flatRenamed = try flatSnapshot(flatRows(), named: "renamed.json", sessionID: nil)
        let moved = try decide(
            flatRenamed, ledger: flatInitial.ledger, document: "renamed.json")
        XCTAssertEqual(
            moved.turns.count, 2,
            "the file name is the session here, so renaming changes every identity")
        XCTAssertEqual(moved.unchangedTurnCount, 0)
        XCTAssertTrue(
            moved.vanishedTurns.isEmpty,
            "a document key with no prior record has no vanished turns of its own")
        XCTAssertNotEqual(
            moved.turns.map(\.identity.operationKey),
            flatInitial.turns.map(\.identity.operationKey))
    }

    // MARK: - Observer identity

    func testAdapterVersionChangeRebaselinesInsteadOfRevising() throws {
        let snapshot = try flatSnapshot(flatRows())
        let initial = try decide(snapshot, ledger: nil)

        let sameVersion = try decide(snapshot, ledger: initial.ledger)
        XCTAssertTrue(sameVersion.documentUnchanged, "control: the version alone changes nothing")

        let bumped = try decide(
            snapshot, ledger: initial.ledger, version: "flat-message-export/v2")
        XCTAssertEqual(bumped.rebaselineReason, .adapterVersionChanged)
        XCTAssertFalse(bumped.documentUnchanged)
        XCTAssertEqual(bumped.turns.count, 2, "a new interpretation states every turn again")
        XCTAssertEqual(bumped.unchangedTurnCount, 0)
        XCTAssertTrue(bumped.vanishedTurns.isEmpty)
        XCTAssertEqual(bumped.ledger.adapterVersion, "flat-message-export/v2")
        XCTAssertTrue(
            bumped.ledger.sessions["flat-session-1"]?.allSatisfy { $0.revision == 1 } == true,
            "old revisions are not carried into an interpretation that never saw them")
    }

    func testLedgerVersionChangeRebaselines() throws {
        let snapshot = try flatSnapshot(flatRows())
        let initial = try decide(snapshot, ledger: nil)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try initial.ledger.encoded())
                as? [String: Any])
        object["schemaVersion"] = SnapshotReimportLedger.currentSchemaVersion - 1
        let older = try SnapshotReimportLedger(
            decoding: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))

        let decision = try decide(snapshot, ledger: older)
        XCTAssertEqual(decision.rebaselineReason, .ledgerVersionChanged)
        XCTAssertEqual(decision.turns.count, 2)
        XCTAssertEqual(decision.unchangedTurnCount, 0)
        XCTAssertEqual(
            decision.ledger.schemaVersion, SnapshotReimportLedger.currentSchemaVersion)
    }

    func testLedgerRoundTripsAndDamagedLedgerFailsClosed() throws {
        let ledger = try decide(try flatSnapshot(flatRows()), ledger: nil).ledger
        let encoded = try ledger.encoded()
        XCTAssertEqual(try SnapshotReimportLedger(decoding: encoded), ledger)
        XCTAssertEqual(try ledger.encoded(), encoded, "a re-encoded ledger is byte-identical")

        XCTAssertThrowsError(try SnapshotReimportLedger(decoding: Data("not a ledger".utf8))) {
            error in
            guard case .unreadableLedger? = error as? SnapshotReimportError else {
                return XCTFail("expected unreadableLedger, got \(error)")
            }
        }
    }

    func testForeignLedgerFailsClosed() throws {
        let deepSeek = try deepSeekSnapshot()
        let deepLedger = try decide(
            deepSeek, ledger: nil, source: DeepSeekSource.sourceType,
            version: DeepSeekSource.adapterVersion, document: "conversations.json").ledger

        let flat = try flatSnapshot(flatRows())
        XCTAssertThrowsError(try decide(flat, ledger: deepLedger)) { error in
            XCTAssertEqual(
                error as? SnapshotReimportError,
                .foreignLedger(storedSourceType: "deepseek", expectedSourceType: "flat-export"))
        }

        let control = try decide(
            deepSeek, ledger: deepLedger, source: DeepSeekSource.sourceType,
            version: DeepSeekSource.adapterVersion, document: "conversations.json")
        XCTAssertTrue(control.documentUnchanged, "control: the same ledger is usable by its own source")
    }

    // MARK: - Durable consequence

    private struct InboxTurnEvent: CollectionCandidateEvent, Sendable {
        let turn: CollectedTurn

        var candidateKind: CollectionCandidateKind { .turn }
        func candidateKey() throws -> String { turn.identity.operationKey }
    }

    /// The decision's output goes through the real durable inbox: only changed
    /// turns insert rows, identical re-reads commit nothing, and the revision
    /// bump is what keeps a restated answer from colliding. The last block undoes
    /// the judgement on purpose — the same adapter output without the revision —
    /// to show the failure the judgement exists to prevent.
    func testDecisionOutputCommitsThroughTheDurableInboxWithoutCollision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "simigo-reimport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = CollectionCandidateInbox<InboxTurnEvent>(directoryURL: root)

        let original = try flatSnapshot(flatRows())
        let initial = try decide(original, ledger: nil)
        let firstCommit = try inbox.commit(
            events: initial.turns.map(InboxTurnEvent.init),
            position: try initial.ledger.encoded())
        XCTAssertEqual(firstCommit.insertedCandidates, 2)
        XCTAssertEqual(firstCommit.duplicateCandidates, 0)
        XCTAssertEqual(try inbox.pendingCount(), 2)

        let idle = try decide(original, ledger: initial.ledger)
        let idleCommit = try inbox.commit(
            events: idle.turns.map(InboxTurnEvent.init),
            position: try idle.ledger.encoded())
        XCTAssertEqual(idleCommit.insertedCandidates, 0)
        XCTAssertEqual(idleCommit.duplicateCandidates, 0)
        XCTAssertEqual(
            try SnapshotReimportLedger(decoding: try XCTUnwrap(try inbox.loadPosition())),
            initial.ledger)

        let changed = try flatSnapshot(flatRows(secondAnswer: "second answer, restated"))
        let revised = try decide(changed, ledger: initial.ledger)
        let revisionCommit = try inbox.commit(
            events: revised.turns.map(InboxTurnEvent.init),
            position: try revised.ledger.encoded())
        XCTAssertEqual(revisionCommit.insertedCandidates, 1)
        XCTAssertEqual(try inbox.pendingCount(), 3)

        let unjudged = try XCTUnwrap(
            changed.turns.first { $0.identity.sourceTurnID == "3" })
        XCTAssertThrowsError(
            try inbox.commit(
                events: [InboxTurnEvent(turn: unjudged)],
                position: try initial.ledger.encoded())
        ) { error in
            guard case .conflictingCandidate(let key, _, _)? = error as? CollectionStateError
            else {
                return XCTFail("expected conflictingCandidate, got \(error)")
            }
            XCTAssertEqual(key, unjudged.identity.operationKey)
        }
        XCTAssertEqual(
            try inbox.pendingCount(), 3,
            "the rejected commit rolled back instead of leaving a partial row")
    }
}