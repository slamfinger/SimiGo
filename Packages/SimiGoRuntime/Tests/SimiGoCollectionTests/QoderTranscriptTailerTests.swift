import Foundation
import XCTest
@testable import SimiGoCollection

final class QoderTranscriptTailerTests: XCTestCase {
    private struct SinkFailure: Error {}

    private var root: URL!
    private var project: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "qoder-tailer-\(UUID().uuidString)", isDirectory: true)
        project = root.appendingPathComponent(Fixture.projectID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: project, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func mainFile(_ session: String = Fixture.sessionID) -> URL {
        project.appendingPathComponent("\(session).jsonl")
    }

    private func subagentFile(
        session: String = Fixture.sessionID, agent: String = "agent-1"
    ) throws -> URL {
        let directory = project
            .appendingPathComponent(session, isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(agent).jsonl")
    }

    @discardableResult
    private func poll(
        _ tailer: QoderTranscriptTailer,
        sink: (([QoderCollectionEvent]) throws -> Void)? = nil
    ) -> (events: [QoderCollectionEvent], report: QoderPollReport) {
        var events: [QoderCollectionEvent] = []
        let report = tailer.poll { batch in
            events.append(contentsOf: batch)
            try sink?(batch)
        }
        return (events, report)
    }

    private func pastState() -> QoderCursorState {
        QoderCursorState(initializedAt: Date(timeIntervalSinceNow: -3600))
    }

    /// TemporaryDirectory is reached through `/var`, but FileManager enumerates
    /// `/private/var`, so cursor keys are the scanner's canonical paths.
    private func cursor(_ tailer: QoderTranscriptTailer) -> QoderFileCursor? {
        tailer.cursorState.cursors.values.first
    }

    func testFirstPollBaselinesExistingFileAtEnd() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let size = Int64(try Data(contentsOf: file).count)

        let tailer = QoderTranscriptTailer(scanRoot: root, now: Date())
        let result = poll(tailer)

        XCTAssertEqual(result.report.scannedFiles, 1)
        XCTAssertEqual(result.report.baselinedFiles, 1)
        XCTAssertTrue(Fixture.turns(result.events).isEmpty)
        let baseline = try XCTUnwrap(Fixture.baselines(result.events).first)
        XCTAssertEqual(baseline.reason, .existingFileAtEnd)
        XCTAssertEqual(baseline.offset, size)
        XCTAssertEqual(baseline.sessionID, Fixture.sessionID)
        XCTAssertFalse(baseline.isSubagent)
        XCTAssertEqual(
            cursor(tailer)?.offset, size)
    }

    func testAppendedTurnIsCollectedAfterBaseline() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let tailer = QoderTranscriptTailer(scanRoot: root, now: Date())
        poll(tailer)

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-2", answerUUID: "a-2", messageID: "m-2",
                prompt: "second prompt", answer: "second answer", nextAnchor: "u-3",
                parent: "a-1"),
            to: file,
            append: true)

        let result = poll(tailer)
        XCTAssertTrue(Fixture.baselines(result.events).isEmpty)
        let turns = Fixture.turns(result.events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.anchor.id, "u-2")
        XCTAssertEqual(turns.first?.promptText, "second prompt")
        XCTAssertEqual(turns.first?.answerText, "second answer")
        XCTAssertGreaterThan(result.report.readBytes, 0)
    }

    func testPartialLineWaitsForNewline() throws {
        let file = mainFile()
        try Fixture.writeLines([], to: file)
        let tailer = QoderTranscriptTailer(scanRoot: root, now: Date())
        poll(tailer)

        try Fixture.append(
            Fixture.userLine(uuid: "u-1", text: "hello"), to: file)
        let partial = poll(tailer)
        XCTAssertTrue(partial.events.isEmpty)
        XCTAssertEqual(cursor(tailer)?.offset, 0)
        XCTAssertFalse(partial.report.stateChanged)

        try Fixture.append(
            "\n"
                + Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world")
                + "\n"
                + Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next")
                + "\n",
            to: file)
        let complete = poll(tailer)
        XCTAssertEqual(Fixture.turns(complete.events).count, 1)
        XCTAssertEqual(Fixture.turns(complete.events).first?.answerText, "world")
    }

    func testResumeFromSavedCursorDoesNotReplay() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let first = QoderTranscriptTailer(scanRoot: root, now: Date())
        poll(first)

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-2", answerUUID: "a-2", messageID: "m-2",
                nextAnchor: "u-3", parent: "a-1"),
            to: file,
            append: true)

        let resumed = QoderTranscriptTailer(
            scanRoot: root, state: first.cursorState)
        let result = poll(resumed)
        XCTAssertTrue(Fixture.baselines(result.events).isEmpty)
        XCTAssertEqual(Fixture.turns(result.events).count, 1)
        XCTAssertEqual(Fixture.turns(result.events).first?.anchor.id, "u-2")
    }

    func testFileCreatedAfterInitializationReadsFromStart() throws {
        let state = pastState()
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)

        let tailer = QoderTranscriptTailer(scanRoot: root, state: state)
        let result = poll(tailer)
        XCTAssertEqual(result.report.newFilesFromStart, 1)
        XCTAssertEqual(
            Fixture.baselines(result.events).first?.reason, .newFileFromStart)
        XCTAssertEqual(Fixture.turns(result.events).count, 1)
        XCTAssertEqual(Fixture.turns(result.events).first?.disposition, .eligible)
    }

    func testTruncationResetsToNewEOF() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let first = QoderTranscriptTailer(scanRoot: root, now: Date())
        poll(first)

        try Data().write(to: file)
        try Fixture.append(
            Fixture.userLine(uuid: "u-1", text: "after truncate") + "\n",
            to: file)
        let newSize = Int64(try Data(contentsOf: file).count)

        let resumed = QoderTranscriptTailer(
            scanRoot: root, state: first.cursorState)
        let result = poll(resumed)
        XCTAssertEqual(result.report.resetFiles, 1)
        XCTAssertEqual(
            Fixture.baselines(result.events).first?.reason, .truncatedReset)
        XCTAssertEqual(
            cursor(resumed)?.offset, newSize)
        XCTAssertTrue(Fixture.turns(result.events).isEmpty)

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-9", answerUUID: "a-9", messageID: "m-9",
                nextAnchor: "u-10"),
            to: file,
            append: true)
        let next = poll(resumed)
        XCTAssertEqual(Fixture.turns(next.events).count, 1)
        XCTAssertEqual(Fixture.turns(next.events).first?.answerText, "world")
    }

    func testFingerprintMismatchResetsEvenWhenSizeMatches() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "aaaa")], to: file)
        let originalSize = Int64(try Data(contentsOf: file).count)
        let first = QoderTranscriptTailer(scanRoot: root, now: Date())
        poll(first)

        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "bbbb")], to: file)
        XCTAssertEqual(Int64(try Data(contentsOf: file).count), originalSize)

        let resumed = QoderTranscriptTailer(
            scanRoot: root, state: first.cursorState)
        let result = poll(resumed)
        XCTAssertEqual(result.report.resetFiles, 1)
        XCTAssertEqual(
            Fixture.baselines(result.events).first?.reason, .fingerprintReset)
        XCTAssertEqual(
            cursor(resumed)?.offset, originalSize)
        XCTAssertTrue(Fixture.turns(result.events).isEmpty)
    }

    func testInodeChangeResets() throws {
        let file = mainFile()
        try Fixture.writeLines([], to: file)
        let first = QoderTranscriptTailer(scanRoot: root, now: Date())
        poll(first)
        try Fixture.writeLines(Fixture.turnLines(), to: file, append: true)

        var state = first.cursorState
        let key = try XCTUnwrap(state.cursors.keys.first)
        let existing = try XCTUnwrap(state.cursors[key])
        state.cursors[key] = QoderFileCursor(
            path: existing.path, projectID: existing.projectID,
            sessionID: existing.sessionID, isSubagent: existing.isSubagent,
            inode: existing.inode &+ 1, offset: 0, segmentLines: 0,
            fingerprint: QoderDigest.sha256Hex(Data()), updatedAt: existing.updatedAt)

        let resumed = QoderTranscriptTailer(scanRoot: root, state: state)
        let result = poll(resumed)
        XCTAssertEqual(
            Fixture.baselines(result.events).first?.reason, .identityReset)
        XCTAssertTrue(Fixture.turns(result.events).isEmpty)
        XCTAssertEqual(
            cursor(resumed)?.offset,
            Int64(try Data(contentsOf: file).count))
    }

    func testSubagentTurnsAreCollectedAsInternalRecords() throws {
        let file = try subagentFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)

        let tailer = QoderTranscriptTailer(scanRoot: root, state: pastState())
        let result = poll(tailer)
        XCTAssertEqual(result.report.scannedFiles, 1)
        let turns = Fixture.turns(result.events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns.first?.isSubagent ?? false)
        XCTAssertEqual(turns.first?.disposition, .internalRecord)
        XCTAssertEqual(turns.first?.sessionID, Fixture.sessionID)
    }

    func testSinkFailureLeavesCursorUnadvancedAndReplays() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let tailer = QoderTranscriptTailer(scanRoot: root, state: pastState())

        let failed = poll(tailer) { _ in throw SinkFailure() }
        XCTAssertFalse(failed.report.errors.isEmpty)
        XCTAssertTrue(tailer.cursorState.cursors.isEmpty)
        XCTAssertEqual(failed.report.deliveredEvents, 0)

        let replayed = poll(tailer)
        XCTAssertEqual(Fixture.turns(replayed.events).count, 1)
        XCTAssertNotNil(cursor(tailer))
        XCTAssertEqual(
            cursor(tailer)?.offset,
            Int64(try Data(contentsOf: file).count))
    }

    func testMalformedLineIsRecordedAndDoesNotStall() throws {
        let file = mainFile()
        try Fixture.writeLines(["{not json"], to: file)
        let tailer = QoderTranscriptTailer(scanRoot: root, state: pastState())
        let result = poll(tailer)
        XCTAssertEqual(result.report.parseFailures, 1)
        XCTAssertEqual(Fixture.failures(result.events).first?.segmentLine, 1)

        try Fixture.writeLines(Fixture.turnLines(), to: file, append: true)
        let next = poll(tailer)
        XCTAssertEqual(Fixture.turns(next.events).count, 1)
    }

    func testCursorStoreRoundTripPermissionsAndCorruptFile() throws {
        let directory = root.appendingPathComponent("state", isDirectory: true)
        let store = QoderFileCursorStore(directoryURL: directory)
        XCTAssertNil(store.load())

        let state = QoderCursorState(
            initializedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cursors: [
                "/tmp/a.jsonl": QoderFileCursor(
                    path: "/tmp/a.jsonl", projectID: "p", sessionID: "s",
                    isSubagent: false, inode: 42, offset: 10, segmentLines: 1,
                    fingerprint: "abc", updatedAt: Date(timeIntervalSince1970: 1_700_000_001))
            ])
        try store.save(state)
        XCTAssertEqual(store.load(), state)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.fileURL.path)
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try Data("not a cursor".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())
    }
}
