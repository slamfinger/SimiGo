import Foundation
import XCTest
@testable import SimiGoCollection

final class QoderCollectionIdentityTests: XCTestCase {

    func testDigestUsesSHA256() {
        XCTAssertEqual(
            QoderDigest.sha256Hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(QoderDigest.sha256Hex("abc"), QoderDigest.sha256Hex(Data("abc".utf8)))
    }

    func testOperationKeyIsDeterministicAndIdentityOnly() {
        let base = QoderSourceIdentity(
            sourceSessionID: "session", sourceTurnID: "turn", sourceMessageID: "message")
        let same = QoderSourceIdentity(
            sourceSessionID: "session", sourceTurnID: "turn", sourceMessageID: "message")
        XCTAssertEqual(base.operationKey, same.operationKey)
        XCTAssertTrue(base.operationKey.hasPrefix("SIM.qoder.collect.v1:"))

        let newRevision = QoderSourceIdentity(
            sourceSessionID: "session", sourceTurnID: "turn", sourceMessageID: "message",
            sourceRevision: 2)
        XCTAssertNotEqual(base.operationKey, newRevision.operationKey)

        let otherMessage = QoderSourceIdentity(
            sourceSessionID: "session", sourceTurnID: "turn", sourceMessageID: "message-2")
        XCTAssertNotEqual(base.operationKey, otherMessage.operationKey)

        let otherAdapter = QoderSourceIdentity(
            sourceSessionID: "session", sourceTurnID: "turn", sourceMessageID: "message",
            adapterVersion: "qoder-transcript-final/v2")
        XCTAssertNotEqual(base.operationKey, otherAdapter.operationKey)
    }

    func testCollectedTurnIdentityMatchesAnchorAndMessage() {
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let turn = Fixture.turns(Fixture.feed(accumulator, Fixture.turnLines())).first
        guard let turn else { return XCTFail("expected a turn") }
        let expected = QoderSourceIdentity(
            sourceSessionID: "session-1", sourceTurnID: "u-1", sourceMessageID: "m-1")
        XCTAssertEqual(turn.identity, expected)
        XCTAssertEqual(turn.identity.operationKey, expected.operationKey)
        XCTAssertEqual(turn.answerDigest, QoderDigest.sha256Hex("world"))
        XCTAssertEqual(QoderSourceIdentity.adapterVersion, "qoder-transcript-final/v1")
    }

    func testStandardConfigurationUsesOverrides() {
        let configuration = QoderCollectionConfiguration.standard(
            env: [
                "QODER_PROJECTS_DIR": "/tmp/qoder-projects",
                "SIMIGO_HOME": "/tmp/simigo-home",
            ],
            homeDirectory: URL(fileURLWithPath: "/tmp/ignored-home", isDirectory: true))
        XCTAssertEqual(configuration.scanRoot.path, "/tmp/qoder-projects")
        XCTAssertEqual(
            configuration.stateDirectory.path,
            "/tmp/simigo-home/collectors/qoder")
    }
}

final class QoderCollectionRunnerTests: XCTestCase {

    private struct SinkFailure: Error {}

    private final class SinkBox {
        var failing: Bool
        var deliveries: [QoderCandidateDelivery] = []

        var events: [QoderCollectionEvent] { deliveries.map(\.event) }
        var keys: [String] { deliveries.map(\.key) }

        init(failing: Bool) {
            self.failing = failing
        }

        func receive(_ batch: [QoderCandidateDelivery]) throws {
            if failing { throw SinkFailure() }
            deliveries.append(contentsOf: batch)
        }
    }

    private var root: URL!
    private var project: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "qoder-runner-\(UUID().uuidString)", isDirectory: true)
        project = root.appendingPathComponent(Fixture.projectID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: project, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func mainFile() -> URL {
        project.appendingPathComponent("\(Fixture.sessionID).jsonl")
    }

    private func configuration() -> QoderCollectionConfiguration {
        QoderCollectionConfiguration(
            scanRoot: root,
            stateDirectory: root.appendingPathComponent("state", isDirectory: true),
            pollInterval: 30)
    }

    /// Cursors are keyed by the scanner's canonical path; the temporary
    /// directory is reached through `/var` while enumeration yields
    /// `/private/var`, so look the single cursor up by value, not by `file.path`.
    private func storedCursor(_ configuration: QoderCollectionConfiguration) throws
        -> QoderFileCursor?
    {
        try QoderCandidateInbox(directoryURL: configuration.stateDirectory)
            .loadCursorState()?.cursors.values.first
    }

    private func pendingCount(_ configuration: QoderCollectionConfiguration) throws -> Int {
        try QoderCandidateInbox(directoryURL: configuration.stateDirectory).pendingCount()
    }

    func testRunnerPersistsCursorAndResumesInNewInstance() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let configuration = configuration()
        var events: [QoderCollectionEvent] = []
        let first = QoderCollectionRunner(configuration: configuration) {
            events.append(contentsOf: $0.map(\.event))
        }
        let report = first.pollOnce()
        XCTAssertEqual(report.baselinedFiles, 1)
        XCTAssertTrue(Fixture.turns(events).isEmpty)
        let stored = try XCTUnwrap(storedCursor(configuration))
        XCTAssertEqual(stored.offset, Int64(try Data(contentsOf: file).count))

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-2", answerUUID: "a-2", messageID: "m-2",
                prompt: "second", answer: "answer two", nextAnchor: "u-3",
                parent: "a-1"),
            to: file,
            append: true)
        events.removeAll()
        let second = first.pollOnce()
        XCTAssertEqual(Fixture.turns(events).count, 1)
        XCTAssertEqual(Fixture.turns(events).first?.answerText, "answer two")
        XCTAssertEqual(
            second.readBytes, Int64(try Data(contentsOf: file).count) - stored.offset)

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-4", answerUUID: "a-4", messageID: "m-4",
                prompt: "third", answer: "answer three", nextAnchor: "u-5",
                parent: "a-2"),
            to: file,
            append: true)
        events.removeAll()
        first.stop()
        let resumed = QoderCollectionRunner(configuration: configuration) {
            events.append(contentsOf: $0.map(\.event))
        }
        let third = resumed.pollOnce()
        XCTAssertEqual(third.baselinedFiles, 0)
        XCTAssertEqual(Fixture.turns(events).count, 1)
        XCTAssertEqual(Fixture.turns(events).first?.answerText, "answer three")
        XCTAssertEqual(
            try storedCursor(configuration)?.offset, Int64(try Data(contentsOf: file).count))
    }

    func testRunnerRecoversPendingTurnAcrossRestart() throws {
        var events: [QoderCollectionEvent] = []
        let first = QoderCollectionRunner(configuration: configuration()) {
            events.append(contentsOf: $0.map(\.event))
        }
        first.pollOnce()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: configuration().stateDirectory.appendingPathComponent(
                    QoderCandidateInbox.databaseFileName).path))

        let file = mainFile()
        try Fixture.writeLines([Fixture.userLine(uuid: "u-1", text: "hello")], to: file)
        first.pollOnce()
        XCTAssertTrue(Fixture.turns(events).isEmpty)

        let anchorCursor = try XCTUnwrap(storedCursor(configuration()))
        XCTAssertEqual(anchorCursor.resumeOffset, 0)
        XCTAssertEqual(anchorCursor.resumeSegmentLines, 0)

        try Fixture.writeLines(
            [
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world"),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ], to: file, append: true)
        events.removeAll()
        first.stop()
        let resumed = QoderCollectionRunner(configuration: configuration()) {
            events.append(contentsOf: $0.map(\.event))
        }
        resumed.pollOnce()
        let turns = Fixture.turns(events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.anchor.id, "u-1")
        XCTAssertEqual(turns.first?.answerText, "world")
        XCTAssertEqual(turns.first?.relation, .parentChain)
        XCTAssertTrue(Fixture.orphans(events).isEmpty)
    }

    func testRunnerKeepsCandidatesWhenDeliveryFailsAndRetriesWithoutRereading() throws {
        let configuration = configuration()
        let box = SinkBox(failing: true)
        let runner = QoderCollectionRunner(configuration: configuration) {
            try box.receive($0)
        }
        runner.pollOnce()

        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let collected = runner.pollOnce()
        XCTAssertFalse(collected.errors.isEmpty)
        XCTAssertEqual(Fixture.turns(box.events).count, 0)
        XCTAssertEqual(try pendingCount(configuration), 2)

        // The cursor advanced even though delivery failed, so the transcript
        // is not read again; the backlog survives for the next drain.
        let stored = try XCTUnwrap(storedCursor(configuration))
        XCTAssertEqual(stored.offset, Int64(try Data(contentsOf: file).count))

        box.failing = false
        let drained = runner.pollOnce()
        XCTAssertEqual(drained.readBytes, 0)
        XCTAssertEqual(drained.deliveredCandidates, 2)
        XCTAssertTrue(drained.errors.isEmpty)
        XCTAssertEqual(Fixture.turns(box.events).count, 1)
        XCTAssertEqual(Fixture.turns(box.events).first?.answerText, "world")
        XCTAssertEqual(try pendingCount(configuration), 0)
    }

    func testRunnerFailsClosedOnCorruptStateAndRecoversOnlyByQuarantine() throws {
        let configuration = configuration()
        try FileManager.default.createDirectory(
            at: configuration.stateDirectory, withIntermediateDirectories: true)
        let database = configuration.stateDirectory.appendingPathComponent(
            QoderCandidateInbox.databaseFileName)
        try Data("this is not sqlite".utf8).write(to: database)

        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)

        var events: [QoderCollectionEvent] = []
        var errors: [String] = []
        let runner = QoderCollectionRunner(
            configuration: configuration,
            sink: { events.append(contentsOf: $0.map(\.event)) },
            onError: { errors.append($0) })
        runner.start()
        XCTAssertFalse(runner.isRunning)
        XCTAssertNotNil(runner.unavailableReason)
        XCTAssertFalse(errors.isEmpty)

        let blocked = runner.pollOnce()
        XCTAssertFalse(blocked.errors.isEmpty)
        XCTAssertEqual(blocked.baselinedFiles, 0)
        XCTAssertTrue(events.isEmpty)
        // Failure close means the damaged state is still there, untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.path))

        let quarantined = try XCTUnwrap(runner.quarantineState())
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: quarantined.appendingPathComponent(
                QoderCandidateInbox.databaseFileName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
        XCTAssertNil(runner.unavailableReason)

        // Recovery is explicit and therefore allowed to baseline the existing
        // transcript at EOF.
        let recovered = runner.pollOnce()
        XCTAssertTrue(recovered.errors.isEmpty)
        XCTAssertEqual(recovered.baselinedFiles, 1)
        XCTAssertEqual(Fixture.baselines(events).first?.reason, .existingFileAtEnd)
        XCTAssertTrue(Fixture.turns(events).isEmpty)
    }

    func testRunnerMigratesSliceTwoCursorIntoTheInbox() throws {
        let configuration = configuration()
        let file = mainFile()
        try Fixture.writeLines([Fixture.userLine(uuid: "u-1", text: "hello")], to: file)

        let scanned = try XCTUnwrap(
            QoderTranscriptScanner(root: root).scan().files.first)
        let size = Int64(try Data(contentsOf: file).count)
        let inode = try XCTUnwrap(
            (FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber]
                as? NSNumber)?.uint64Value)
        let legacy = QoderCursorState(
            initializedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cursors: [
                scanned.path: QoderFileCursor(
                    path: scanned.path, projectID: scanned.projectID,
                    sessionID: scanned.sessionID, isSubagent: false,
                    inode: inode, offset: size, segmentLines: 1,
                    resumeOffset: 0, resumeSegmentLines: 0,
                    fingerprint: QoderDigest.sha256Hex(try Data(contentsOf: file)),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_001))
            ])
        try FileManager.default.createDirectory(
            at: configuration.stateDirectory, withIntermediateDirectories: true)
        try QoderFileCursorStore(directoryURL: configuration.stateDirectory)
            .save(legacy)

        try Fixture.writeLines(
            [
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world"),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ], to: file, append: true)

        var events: [QoderCollectionEvent] = []
        let runner = QoderCollectionRunner(configuration: configuration) {
            events.append(contentsOf: $0.map(\.event))
        }
        let report = runner.pollOnce()
        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(report.baselinedFiles, 0)

        let turns = Fixture.turns(events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.answerText, "world")
        XCTAssertEqual(turns.first?.relation, .parentChain)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: configuration.stateDirectory.appendingPathComponent(
                    QoderCandidateInbox.legacyCursorFileName).path))
        XCTAssertEqual(try storedCursor(configuration)?.offset, Int64(try Data(contentsOf: file).count))
    }

    func testRunnerDoesNotRescanAfterRestartWithDurableBacklog() throws {
        let configuration = configuration()
        let box = SinkBox(failing: true)
        let first = QoderCollectionRunner(configuration: configuration) {
            try box.receive($0)
        }
        first.pollOnce()
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        first.pollOnce()
        XCTAssertEqual(try pendingCount(configuration), 2)

        box.failing = false
        first.stop()
        let resumed = QoderCollectionRunner(configuration: configuration) {
            try box.receive($0)
        }
        let drained = resumed.pollOnce()
        // The open turn (u-2) is replayed to rebuild state, but the already
        // committed turn candidate is not regenerated or delivered twice.
        XCTAssertGreaterThan(drained.replayedBytes, 0)
        XCTAssertEqual(drained.persistedCandidates, 0)
        XCTAssertEqual(drained.duplicateCandidates, 0)
        XCTAssertEqual(Fixture.turns(box.events).count, 1)
        XCTAssertEqual(try pendingCount(configuration), 0)
    }

    func testCrashWindowAfterSinkAcceptanceBeforeMarkDeliveredRedeliversSameStableKey() throws {
        let configuration = configuration()
        let accumulator = QoderTurnAccumulator(context: Fixture.context())
        let turn = try XCTUnwrap(
            Fixture.turns(Fixture.feed(accumulator, Fixture.turnLines())).first)

        let inbox = QoderCandidateInbox(directoryURL: configuration.stateDirectory)
        let state = QoderCursorState(initializedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try inbox.commit(events: [.turn(turn)], cursorState: state)
        let pending = try inbox.pendingCandidates()
        XCTAssertEqual(pending.map(\.key), [turn.identity.operationKey])

        // Model the crash window: the first sink accepted this delivery, but
        // markDelivered was not committed. The restarted Runner must hand over
        // the exact same key (at-least-once, not exactly-once).
        let acceptedBeforeCrash = pending.map(\.key)
        let box = SinkBox(failing: false)
        let runner = QoderCollectionRunner(configuration: configuration) {
            try box.receive($0)
        }
        let report = runner.pollOnce()
        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(box.keys, acceptedBeforeCrash)
        XCTAssertEqual(box.deliveries.map(\.kind), [.turn])
        XCTAssertEqual(box.deliveries.first?.event, .turn(turn))
        XCTAssertEqual(box.deliveries.first?.sequence, pending.first?.sequence)
        XCTAssertEqual(try pendingCount(configuration), 0)
    }

    func testCollectionOnlyRunnerRetainsCandidatesWithoutPretendingTheyWereDelivered() throws {
        let configuration = configuration()
        let runner = QoderCollectionRunner(configuration: configuration)
        _ = runner.pollOnce()

        try Fixture.writeLines(Fixture.turnLines(), to: mainFile())
        let report = runner.pollOnce()
        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(report.persistedCandidates, 2)
        let status = runner.statusSnapshot
        XCTAssertEqual(status.pendingCount, 2)
        XCTAssertNil(status.lastDeliveryAt)
        XCTAssertNil(status.unavailableReason)
    }

    func testNormallyStoppedRunnerDoesNotRedeliverMarkedCandidates() throws {
        let configuration = configuration()
        let box = SinkBox(failing: false)
        let first = QoderCollectionRunner(configuration: configuration) {
            try box.receive($0)
        }
        _ = first.pollOnce()
        try Fixture.writeLines(Fixture.turnLines(), to: mainFile())
        let delivered = first.pollOnce()
        XCTAssertEqual(delivered.deliveredCandidates, 2)
        let acceptedKeys = box.keys
        XCTAssertEqual(acceptedKeys.count, 2)
        XCTAssertEqual(first.statusSnapshot.pendingCount, 0)
        XCTAssertNotNil(first.statusSnapshot.lastDeliveryAt)
        first.stop()

        let inbox = QoderCandidateInbox(directoryURL: configuration.stateDirectory)
        let cursor = try XCTUnwrap(inbox.loadCursorState())
        let replay = try inbox.commit(events: box.events, cursorState: cursor)
        XCTAssertEqual(replay.insertedCandidates, 0)
        XCTAssertEqual(replay.duplicateCandidates, 2)
        XCTAssertEqual(try inbox.pendingCount(), 0)

        let resumed = QoderCollectionRunner(configuration: configuration) {
            try box.receive($0)
        }
        let restarted = resumed.pollOnce()
        XCTAssertTrue(restarted.errors.isEmpty)
        XCTAssertEqual(restarted.deliveredCandidates, 0)
        XCTAssertEqual(box.keys, acceptedKeys)
        XCTAssertEqual(try inbox.pendingCount(), 0)
    }

    func testInboxRejectsSameIdentityWithDifferentContent() throws {
        let configuration = configuration()
        let inbox = QoderCandidateInbox(directoryURL: configuration.stateDirectory)
        let original = try XCTUnwrap(
            Fixture.turns(
                Fixture.feed(
                    QoderTurnAccumulator(context: Fixture.context()),
                    Fixture.turnLines())
            ).first)
        let rewritten = try XCTUnwrap(
            Fixture.turns(
                Fixture.feed(
                    QoderTurnAccumulator(context: Fixture.context()),
                    Fixture.turnLines(answer: "different answer"))
            ).first)
        XCTAssertEqual(original.identity, rewritten.identity)
        XCTAssertNotEqual(original.answerDigest, rewritten.answerDigest)

        let state = QoderCursorState(initializedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try inbox.commit(events: [.turn(original)], cursorState: state)

        let moved = QoderCursorState(
            initializedAt: state.initializedAt,
            cursors: [
                "/tmp/moved.jsonl": QoderFileCursor(
                    path: "/tmp/moved.jsonl", projectID: "p", sessionID: "s",
                    isSubagent: false, inode: 1, offset: 100, segmentLines: 4,
                    fingerprint: "f",
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            ])
        XCTAssertThrowsError(
            try inbox.commit(events: [.turn(rewritten)], cursorState: moved)
        ) { error in
            guard case QoderCollectionStateError.conflictingCandidate = error else {
                return XCTFail("expected conflictingCandidate, got \(error)")
            }
        }
        // The rejected batch rolls back as a whole: nothing new is stored and
        // the cursor does not move past content that was never recorded.
        XCTAssertEqual(try inbox.pendingCount(), 1)
        XCTAssertEqual(try inbox.loadCursorState(), state)

        // Same identity with the same content is the replay the design absorbs.
        let retried = try inbox.commit(events: [.turn(original)], cursorState: state)
        XCTAssertEqual(retried.insertedCandidates, 0)
        XCTAssertEqual(retried.duplicateCandidates, 1)
    }

    func testInboxMigratesASliceThreeVersionOneDatabase() throws {
        let configuration = configuration()
        try FileManager.default.createDirectory(
            at: configuration.stateDirectory, withIntermediateDirectories: true)
        let databaseURL = configuration.stateDirectory.appendingPathComponent(
            QoderCandidateInbox.databaseFileName)

        let turn = try XCTUnwrap(
            Fixture.turns(
                Fixture.feed(
                    QoderTurnAccumulator(context: Fixture.context()),
                    Fixture.turnLines())
            ).first)
        let state = QoderCursorState(initializedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let eventPayload = try encoder.encode(QoderCollectionEvent.turn(turn))
        let cursorPayload = try encoder.encode(state)

        do {
            let connection = try QoderSQLiteConnection.open(path: databaseURL.path)
            defer { connection.close() }
            try connection.execute(
                """
                CREATE TABLE cursor_state (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    payload BLOB NOT NULL
                );
                CREATE TABLE candidates (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    key TEXT NOT NULL UNIQUE,
                    kind TEXT NOT NULL,
                    recorded_at REAL NOT NULL,
                    delivered_at REAL,
                    payload BLOB NOT NULL
                );
                CREATE INDEX candidates_pending_seq
                    ON candidates(seq) WHERE delivered_at IS NULL;
                """)
            let insertCursor = try connection.prepare(
                "INSERT INTO cursor_state(id, payload) VALUES (1, ?)")
            try insertCursor.bind(blob: cursorPayload, at: 1)
            _ = try insertCursor.step()
            let insertCandidate = try connection.prepare(
                "INSERT INTO candidates(key, kind, recorded_at, payload) VALUES (?, ?, ?, ?)")
            try insertCandidate.bind(text: turn.identity.operationKey, at: 1)
            try insertCandidate.bind(text: QoderCandidateKind.turn.rawValue, at: 2)
            insertCandidate.bind(double: 1_700_000_001, at: 3)
            try insertCandidate.bind(blob: eventPayload, at: 4)
            _ = try insertCandidate.step()
            try connection.execute("PRAGMA user_version = 1")
        }

        let inbox = QoderCandidateInbox(directoryURL: configuration.stateDirectory)
        XCTAssertEqual(try inbox.loadCursorState(), state)
        XCTAssertEqual(
            try inbox.pendingCandidates().map(\.key), [turn.identity.operationKey])
        // The backfilled digest keeps a legitimate replay a duplicate rather
        // than a false conflict.
        let retried = try inbox.commit(events: [.turn(turn)], cursorState: state)
        XCTAssertEqual(retried.insertedCandidates, 0)
        XCTAssertEqual(retried.duplicateCandidates, 1)

        let upgraded = try QoderSQLiteConnection.open(path: databaseURL.path)
        defer { upgraded.close() }
        XCTAssertEqual(try upgraded.scalarInt64("PRAGMA user_version"), 2)
    }

    func testPendingCandidatesRejectsPayloadTamperingBeforeSinkDelivery() throws {
        let configuration = configuration()
        let inbox = QoderCandidateInbox(directoryURL: configuration.stateDirectory)
        let turn = try XCTUnwrap(
            Fixture.turns(
                Fixture.feed(
                    QoderTurnAccumulator(context: Fixture.context()),
                    Fixture.turnLines())
            ).first)
        let state = QoderCursorState(
            initializedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try inbox.commit(events: [.turn(turn)], cursorState: state)

        let databaseURL = configuration.stateDirectory.appendingPathComponent(
            QoderCandidateInbox.databaseFileName)
        do {
            let connection = try QoderSQLiteConnection.open(path: databaseURL.path)
            defer { connection.close() }
            let select = try connection.prepare(
                "SELECT seq, payload FROM candidates WHERE key = ?")
            try select.bind(text: turn.identity.operationKey, at: 1)
            XCTAssertTrue(try select.step())
            let sequence = select.int64(at: 0)
            var payload = try XCTUnwrap(select.blob(at: 1))
            let range = try XCTUnwrap(payload.range(of: Data("hello".utf8)))
            payload.replaceSubrange(range, with: Data("hullo".utf8))

            let update = try connection.prepare(
                "UPDATE candidates SET payload = ? WHERE seq = ?")
            try update.bind(blob: payload, at: 1)
            update.bind(int64: sequence, at: 2)
            _ = try update.step()
        }

        XCTAssertThrowsError(try inbox.pendingCandidates()) { error in
            guard case QoderCollectionStateError.corruptState = error else {
                return XCTFail("expected corruptState, got \(error)")
            }
        }

        var sinkCalls = 0
        let runner = QoderCollectionRunner(configuration: configuration) { _ in
            sinkCalls += 1
        }
        let report = runner.pollOnce()
        XCTAssertEqual(sinkCalls, 0)
        XCTAssertTrue(report.errors.contains { $0.contains("payload digest mismatch") })
        XCTAssertTrue(runner.unavailableReason?.contains("payload digest mismatch") == true)
        XCTAssertEqual(runner.statusSnapshot.pendingCount, 1)
        XCTAssertEqual(try inbox.pendingCount(), 1)
    }

    func testInboxAbsorbsReplayedCandidatesWithoutRedeliveringThem() throws {
        let configuration = configuration()
        let box = SinkBox(failing: false)
        let runner = QoderCollectionRunner(configuration: configuration) {
            try box.receive($0)
        }
        runner.pollOnce()
        try Fixture.writeLines(Fixture.turnLines(), to: mainFile())
        runner.pollOnce()
        XCTAssertEqual(box.events.count, 2)
        XCTAssertEqual(try pendingCount(configuration), 0)

        // A crash between reading and committing leaves the cursor behind, so
        // the next poll regenerates the same events. They must be absorbed by
        // their keys rather than recorded and delivered a second time.
        let inbox = QoderCandidateInbox(directoryURL: configuration.stateDirectory)
        let state = try XCTUnwrap(inbox.loadCursorState())
        let replayed = try inbox.commit(events: box.events, cursorState: state)
        XCTAssertEqual(replayed.insertedCandidates, 0)
        XCTAssertEqual(replayed.duplicateCandidates, 2)
        XCTAssertTrue(try inbox.pendingCandidates().isEmpty)
        XCTAssertEqual(try pendingCount(configuration), 0)

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-2", answerUUID: "a-2", messageID: "m-2",
                prompt: "second", answer: "second answer", nextAnchor: "u-3",
                parent: "a-1"),
            to: mainFile(),
            append: true)
        let next = runner.pollOnce()
        XCTAssertEqual(next.deliveredCandidates, 1)
        XCTAssertEqual(Fixture.turns(box.events).count, 2)
        XCTAssertEqual(Fixture.turns(box.events).last?.answerText, "second answer")
    }

    func testInboxFailsClosedOnCorruptLegacyCursorWithoutCreatingADatabase() throws {
        let configuration = configuration()
        try FileManager.default.createDirectory(
            at: configuration.stateDirectory, withIntermediateDirectories: true)
        let legacy = configuration.stateDirectory.appendingPathComponent(
            QoderCandidateInbox.legacyCursorFileName)
        try Data("{\"initializedAt\": 0, \"cursors\": {".utf8).write(to: legacy)
        let database = configuration.stateDirectory.appendingPathComponent(
            QoderCandidateInbox.databaseFileName)

        let inbox = QoderCandidateInbox(directoryURL: configuration.stateDirectory)
        XCTAssertThrowsError(try inbox.loadCursorState()) { error in
            guard case QoderCollectionStateError.corruptLegacyCursor = error else {
                return XCTFail("expected corruptLegacyCursor, got \(error)")
            }
        }
        // Damage must not be replaced by a fresh database that would baseline
        // the transcript at EOF.
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))

        try Fixture.writeLines(Fixture.turnLines(), to: mainFile())
        var events: [QoderCollectionEvent] = []
        let runner = QoderCollectionRunner(
            configuration: configuration,
            sink: { events.append(contentsOf: $0.map(\.event)) },
            onError: { _ in })
        let report = runner.pollOnce()
        XCTAssertFalse(report.errors.isEmpty)
        XCTAssertNotNil(runner.unavailableReason)
        XCTAssertEqual(report.baselinedFiles, 0)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testCollectionLeaseIsExclusiveUntilItsHolderIsReleased() throws {
        let configuration = configuration()
        do {
            let lease = try QoderCollectionLease.acquire(
                directoryURL: configuration.stateDirectory)
            XCTAssertEqual(lease.fileURL.lastPathComponent, "collector.lock")
            XCTAssertThrowsError(
                try QoderCollectionLease.acquire(
                    directoryURL: configuration.stateDirectory)
            ) { error in
                guard case QoderCollectionStateError.stateAlreadyOwned = error else {
                    return XCTFail("expected stateAlreadyOwned, got \(error)")
                }
            }
        }
        // Deallocating the holder closes the descriptor, which releases the
        // lock; the file itself stays so the next runner can reuse it.
        let reacquired = try QoderCollectionLease.acquire(
            directoryURL: configuration.stateDirectory)
        _ = reacquired
    }

    func testSecondRunnerCannotTakeOverAnOwnedStateDatabase() throws {
        let configuration = configuration()
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)

        var first: QoderCollectionRunner? = QoderCollectionRunner(
            configuration: configuration) { _ in }
        let initial = try XCTUnwrap(first).pollOnce()
        XCTAssertTrue(initial.errors.isEmpty)
        let owned = try XCTUnwrap(storedCursor(configuration))

        // A new turn lands while the first runner owns the state.
        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-2", answerUUID: "a-2", messageID: "m-2",
                prompt: "second", answer: "answer two", nextAnchor: "u-3",
                parent: "a-1"),
            to: file, append: true)

        let loserBox = SinkBox(failing: false)
        let second = QoderCollectionRunner(configuration: configuration) {
            try loserBox.receive($0)
        }
        let blocked = second.pollOnce()
        XCTAssertTrue(loserBox.deliveries.isEmpty)
        XCTAssertTrue(blocked.errors.contains { $0.contains("already owned") })
        XCTAssertNotNil(second.unavailableReason)
        // The loser must not touch the shared state, and it certainly may not
        // displace it through quarantine.
        XCTAssertEqual(try storedCursor(configuration), owned)
        XCTAssertNil(second.quarantineState())
        XCTAssertEqual(try storedCursor(configuration), owned)

        // Releasing the owner (as process exit would) lets a new runner resume
        // from the stored position instead of re-baselining.
        first = nil
        let winnerBox = SinkBox(failing: false)
        let third = QoderCollectionRunner(configuration: configuration) {
            try winnerBox.receive($0)
        }
        let resumed = third.pollOnce()
        XCTAssertTrue(resumed.errors.isEmpty)
        XCTAssertEqual(resumed.baselinedFiles, 0)
        XCTAssertTrue(Fixture.baselines(winnerBox.events).isEmpty)
        XCTAssertEqual(Fixture.turns(winnerBox.events).count, 1)
        XCTAssertEqual(Fixture.turns(winnerBox.events).first?.answerText, "answer two")
    }

    func testRunnerStartStopToggles() {
        let runner = QoderCollectionRunner(configuration: configuration()) { _ in }
        XCTAssertFalse(runner.isRunning)
        runner.start()
        XCTAssertTrue(runner.isRunning)
        runner.stop()
        XCTAssertFalse(runner.isRunning)
    }
}
