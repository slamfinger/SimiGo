import Foundation
import XCTest

@testable import SimiGoCollection

/// Qoder's keys and stored bytes are already persisted in live IS rows, so the
/// extraction of the neutral core is only acceptable if they do not move. These
/// expectations were measured on the pre-refactor tree at 8d87e325 and are
/// pinned here rather than recomputed, because a recomputed expectation would
/// agree with whatever the refactor happened to produce.
final class CollectionQoderCompatibilityTests: XCTestCase {
    private func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SourceDigest.sha256Hex(try encoder.encode(value))
    }

    private func goldenTranscriptEvents() throws -> [CollectionEvent] {
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.assistantLine(uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world"),
            Fixture.assistantLine(uuid: "a-orphan", messageID: "m-orphan", text: "stray"),
            Fixture.systemCompactLine(uuid: "c-1"),
            Fixture.userLine(uuid: "u-2", text: "second"),
            Fixture.assistantLine(
                uuid: "a-2", parent: "u-2", messageID: "m-2", text: "partial", stop: nil),
            Fixture.userLine(uuid: "u-3", parent: "a-2", text: "third"),
            Fixture.queuedLine(uuid: "q-1", sourceUUID: "u-3", prompt: "queued work"),
            Fixture.assistantLine(
                uuid: "a-3", parent: "q-1", messageID: "m-3", text: "queued answer"),
            Fixture.userLine(uuid: "u-4", parent: "a-3", text: "tail"),
        ]
        return Fixture.feed(TurnAccumulator(context: Fixture.context()), lines)
    }

    func testQoderCandidateKeysAndPayloadsMatchThePreRefactorGoldens() throws {
        let expected: [(kind: CandidateKind, key: String, payload: String)] = [
            (
                .turn,
                "SIM.qoder.collect.v1:d0b08d8345600cc4d016a5a20f8c8b7260e0f49b82eeb670490ba5a620e9216a",
                "e2c7918db304247ad08db682693a50af82324621c73c1caf061f636eb3173552"
            ),
            (
                .closedWithoutAnswer,
                "SIM.qoder.candidate.v1:925d1b83732bce51364fb98b7a96845d53f2d6ef6910e8d6d94ef8d0a9fa1923",
                "925d1b83732bce51364fb98b7a96845d53f2d6ef6910e8d6d94ef8d0a9fa1923"
            ),
            (
                .turn,
                "SIM.qoder.collect.v1:429074294d561c8a5cf709470cee224718330b7c26ce19e6e5278cae2ecae68f",
                "d1e0d61fc72df75aa480fa8d8dbc08eba70c7faf36154807b527b3e2066cd2c0"
            ),
        ]
        let events = try goldenTranscriptEvents()
        XCTAssertEqual(events.count, expected.count)
        for (event, want) in zip(events, expected) {
            XCTAssertEqual(event.candidateKind, want.kind)
            XCTAssertEqual(try CandidateKey.make(for: event), want.key)
            XCTAssertEqual(try event.candidateKey(), want.key)
            XCTAssertEqual(try digest(event), want.payload)
        }
    }

    func testQoderIdentityOperationKeysMatchThePreRefactorGoldens() throws {
        let expected: [(revision: Int, key: String, payload: String)] = [
            (
                1,
                "SIM.qoder.collect.v1:e74f05ba7e714fe6df06783703efbd6e57975e446f668ab20200a7a89c5afa38",
                "24804a863663635f45331986ffe8e484b8b29a06c0a69f531c480612038b5efb"
            ),
            (
                2,
                "SIM.qoder.collect.v1:56c9fafc36d2ab604f0e9ec77ba6a7d5f9e043c6d66895471bb67069bc664b38",
                "68db889b15e550c2841e3855eb3cf1586f28f502bd6a7be54820efc3bd97a8df"
            ),
            (
                7,
                "SIM.qoder.collect.v1:c3ee072608be7a7556bd60d4b9cb686853eaa98fcd151aecd75f28be5dae9040",
                "888ac1718f8fc2a4acb4a2c84517c392d7a7937e3acf4b502c9bb69a8c308476"
            ),
        ]
        let identities = [
            SourceIdentity(
                sourceSessionID: "session", sourceTurnID: "turn", sourceMessageID: "message"),
            SourceIdentity(
                sourceSessionID: "session", sourceTurnID: "turn", sourceMessageID: "message",
                sourceRevision: 2),
            SourceIdentity(
                sourceSessionID: "s-2", sourceTurnID: "t-2", sourceMessageID: "m-2",
                sourceRevision: 7),
        ]
        XCTAssertEqual(identities.count, expected.count)
        for (identity, want) in zip(identities, expected) {
            XCTAssertEqual(identity.sourceRevision, want.revision)
            XCTAssertEqual(identity.operationKey, want.key)
            XCTAssertEqual(try digest(identity), want.payload)
        }
    }

    func testQoderCursorStateEncodingMatchesThePreRefactorGolden() throws {
        let cursor = FileCursor(
            path: "/tmp/golden/transcript.jsonl", projectID: "project-golden",
            sessionID: "session-golden", isSubagent: false, inode: 4242, offset: 128,
            segmentLines: 3, fingerprint: SourceDigest.sha256Hex("golden"),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let state = CursorState(
            initializedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cursors: [cursor.path: cursor], policy: "read_existing")
        XCTAssertEqual(
            try digest(state),
            "4f58fe5bf97d52c085250eacd6fe1ada71819a22d10f1c97a236c69c811fc58a")
    }

    /// The neutral identity must reproduce Qoder's bytes exactly, and the
    /// namespace must genuinely depend on `sourceType`. The second half is the
    /// positive control: if the prefix were hard-coded, or `sourceType` left out
    /// of the hashed payload, these assertions would fail.
    func testNeutralIdentityKeepsQoderBytesAndNamespacesOtherSources() throws {
        let qoder = SourceIdentity(
            sourceSessionID: "session", sourceTurnID: "turn", sourceMessageID: "message",
            sourceRevision: 3)
        let neutral = CollectionSourceIdentity(
            sourceType: "qoder", sourceSessionID: "session", sourceTurnID: "turn",
            sourceMessageID: "message", sourceRevision: 3,
            adapterVersion: SourceIdentity.adapterVersion)
        XCTAssertEqual(neutral.operationKey, qoder.operationKey)
        XCTAssertTrue(neutral.operationKey.hasPrefix("SIM.qoder.collect.v1:"))

        let other = CollectionSourceIdentity(
            sourceType: "aistudio", sourceSessionID: "session", sourceTurnID: "turn",
            sourceMessageID: "message", sourceRevision: 3,
            adapterVersion: SourceIdentity.adapterVersion)
        XCTAssertTrue(other.operationKey.hasPrefix("SIM.aistudio.collect.v1:"))
        XCTAssertNotEqual(other.operationKey, neutral.operationKey)
        let suffix = { (key: String) in String(key.split(separator: ":").last ?? "") }
        XCTAssertNotEqual(
            suffix(other.operationKey), suffix(neutral.operationKey),
            "sourceType must enter the hashed payload, not only the prefix")
    }
}