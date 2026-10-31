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

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "qoder-tailer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(Fixture.projectID, isDirectory: true),
            withIntermediateDirectories: true)
        return url
    }

    private func projectFile(in root: URL, session: String = Fixture.sessionID) -> URL {
        root.appendingPathComponent(Fixture.projectID, isDirectory: true)
            .appendingPathComponent("\(session).jsonl")
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

    func testRestartAfterAnchorRecoversPendingTurnForLateAnswer() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "hello")], to: file)
        let first = QoderTranscriptTailer(scanRoot: root, state: pastState())
        let opened = poll(first)
        XCTAssertTrue(Fixture.turns(opened.events).isEmpty)
        let stored = try XCTUnwrap(cursor(first))
        XCTAssertEqual(stored.resumeOffset, 0)
        XCTAssertEqual(stored.resumeSegmentLines, 0)
        XCTAssertEqual(stored.offset, Int64(try Data(contentsOf: file).count))

        // The process restarts here: only the persisted cursor survives.
        let resumed = QoderTranscriptTailer(scanRoot: root, state: first.cursorState)
        let recovered = poll(resumed)
        XCTAssertTrue(recovered.events.isEmpty)
        XCTAssertEqual(recovered.report.replayedBytes, stored.offset)

        try Fixture.writeLines(
            [
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world"),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ], to: file, append: true)
        let result = poll(resumed)
        let turns = Fixture.turns(result.events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.anchor.id, "u-1")
        XCTAssertEqual(turns.first?.promptText, "hello")
        XCTAssertEqual(turns.first?.answerText, "world")
        XCTAssertEqual(turns.first?.relation, .parentChain)
        XCTAssertEqual(turns.first?.disposition, .eligible)
        XCTAssertTrue(Fixture.orphans(result.events).isEmpty)
    }

    func testRestartAfterAnswerSettlesUnclosedTurnExactlyOnce() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [
                Fixture.userLine(uuid: "u-1", text: "hello"),
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world"),
            ], to: file)
        let first = QoderTranscriptTailer(scanRoot: root, state: pastState())
        XCTAssertTrue(Fixture.turns(poll(first).events).isEmpty)

        let resumed = QoderTranscriptTailer(scanRoot: root, state: first.cursorState)
        try Fixture.appendLine(
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"), to: file)
        let closed = poll(resumed)
        let turns = Fixture.turns(closed.events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.answerText, "world")
        XCTAssertEqual(turns.first?.relation, .parentChain)

        let again = poll(resumed)
        XCTAssertTrue(Fixture.turns(again.events).isEmpty)
    }

    func testRestartAfterCompactionPreservesAttribution() throws {
        let lines = [
            Fixture.userLine(uuid: "u-1", text: "hello"),
            Fixture.userLine(
                uuid: "c-1", parent: "u-1", text: "summary", isCompactSummary: true),
            Fixture.assistantLine(
                uuid: "a-1", parent: "c-1", messageID: "m-1", text: "world"),
            Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
        ]

        let continuousRoot = try makeRoot()
        defer { try? FileManager.default.removeItem(at: continuousRoot) }
        let continuousFile = projectFile(in: continuousRoot)
        try Fixture.writeLines(lines, to: continuousFile)
        let continuous = QoderTranscriptTailer(
            scanRoot: continuousRoot, state: pastState())
        let reference = try XCTUnwrap(Fixture.turns(poll(continuous).events).first)

        let restartedRoot = try makeRoot()
        defer { try? FileManager.default.removeItem(at: restartedRoot) }
        let restartedFile = projectFile(in: restartedRoot)
        try Fixture.writeLines(Array(lines.prefix(2)), to: restartedFile)
        let first = QoderTranscriptTailer(
            scanRoot: restartedRoot, state: pastState())
        XCTAssertTrue(Fixture.turns(poll(first).events).isEmpty)

        let resumed = QoderTranscriptTailer(
            scanRoot: restartedRoot, state: first.cursorState)
        try Fixture.writeLines(Array(lines.suffix(2)), to: restartedFile, append: true)
        let restarted = try XCTUnwrap(Fixture.turns(poll(resumed).events).first)

        XCTAssertEqual(reference.relation, .fileOrderAfterCompaction)
        XCTAssertEqual(restarted.relation, reference.relation)
        XCTAssertEqual(restarted.disposition, reference.disposition)
        XCTAssertEqual(restarted.disposition, .requiresReview(.fileOrderAfterCompaction))
        XCTAssertEqual(restarted.anchor.id, reference.anchor.id)
        XCTAssertEqual(restarted.promptText, reference.promptText)
        XCTAssertEqual(restarted.answerText, reference.answerText)
        XCTAssertEqual(restarted.candidateID, reference.candidateID)
        XCTAssertEqual(restarted.firstSegmentLine, reference.firstSegmentLine)
        XCTAssertEqual(restarted.lastSegmentLine, reference.lastSegmentLine)
    }

    func testRestartReplaysOnlyTheOpenTurnNotFinalizedTurns() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let first = QoderTranscriptTailer(scanRoot: root, state: pastState())
        XCTAssertEqual(Fixture.turns(poll(first).events).count, 1)

        let stored = try XCTUnwrap(cursor(first))
        let closedLines = Fixture.turnLines().prefix(2)
        let anchorStart = closedLines.reduce(Int64(0)) { $0 + Int64($1.utf8.count + 1) }
        XCTAssertEqual(stored.resumeOffset, anchorStart)
        XCTAssertEqual(stored.resumeSegmentLines, 2)
        XCTAssertLessThan(stored.resumeOffset, stored.offset)

        let resumed = QoderTranscriptTailer(scanRoot: root, state: first.cursorState)
        let replayed = poll(resumed)
        XCTAssertTrue(Fixture.turns(replayed.events).isEmpty)
        XCTAssertEqual(
            replayed.report.replayedBytes, stored.offset - stored.resumeOffset)

        try Fixture.writeLines(
            [
                Fixture.assistantLine(
                    uuid: "a-2", parent: "u-2", messageID: "m-2", text: "second"),
                Fixture.userLine(uuid: "u-3", parent: "a-2", text: "next"),
            ], to: file, append: true)
        let closed = poll(resumed)
        let turns = Fixture.turns(closed.events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.anchor.id, "u-2")
        XCTAssertEqual(turns.first?.answerText, "second")
        XCTAssertTrue(Fixture.orphans(closed.events).isEmpty)
    }

    func testRestartWithoutAnyOpenTurnDoesNotReplay() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [Fixture.assistantLine(uuid: "a-1", messageID: "m-1", text: "orphan")],
            to: file)
        let first = QoderTranscriptTailer(scanRoot: root, state: pastState())
        XCTAssertEqual(Fixture.orphans(poll(first).events).count, 1)

        let stored = try XCTUnwrap(cursor(first))
        XCTAssertEqual(stored.resumeOffset, stored.offset)
        XCTAssertEqual(stored.resumeSegmentLines, stored.segmentLines)

        let resumed = QoderTranscriptTailer(scanRoot: root, state: first.cursorState)
        let idle = poll(resumed)
        XCTAssertTrue(idle.events.isEmpty)
        XCTAssertEqual(idle.report.replayedBytes, 0)
        XCTAssertEqual(idle.report.readBytes, 0)
    }

    func testSinkFailureAfterRestartReplaysFromAnchor() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "hello")], to: file)
        let first = QoderTranscriptTailer(scanRoot: root, state: pastState())
        poll(first)

        let resumed = QoderTranscriptTailer(scanRoot: root, state: first.cursorState)
        try Fixture.writeLines(
            [
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world"),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ], to: file, append: true)

        let failed = poll(resumed) { _ in throw SinkFailure() }
        XCTAssertFalse(failed.report.errors.isEmpty)
        XCTAssertEqual(failed.report.deliveredEvents, 0)

        let replayed = poll(resumed)
        let turns = Fixture.turns(replayed.events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.answerText, "world")
        XCTAssertTrue(Fixture.orphans(replayed.events).isEmpty)
        XCTAssertGreaterThan(replayed.report.replayedBytes, 0)
    }

    func testLegacyCursorWithoutResumeFieldsDecodesToNoReplay() throws {
        let directory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let store = QoderFileCursorStore(directoryURL: directory)
        let json = """
            {"initializedAt":0,"cursors":{"/tmp/legacy.jsonl":{"fingerprint":"abc",\
            "inode":7,"isSubagent":false,"offset":120,"path":"/tmp/legacy.jsonl",\
            "projectID":"p","segmentLines":3,"sessionID":"s","updatedAt":0}}}
            """
        try Data(json.utf8).write(to: store.fileURL)
        let state = try XCTUnwrap(store.load())
        let legacy = try XCTUnwrap(state.cursors["/tmp/legacy.jsonl"])
        XCTAssertEqual(legacy.resumeOffset, 120)
        XCTAssertEqual(legacy.resumeSegmentLines, 3)
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
        XCTAssertEqual(cursor(resumed)?.resumeOffset, newSize)
        XCTAssertEqual(cursor(resumed)?.resumeSegmentLines, 0)
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
        XCTAssertNil(try store.load())

        let state = QoderCursorState(
            initializedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cursors: [
                "/tmp/a.jsonl": QoderFileCursor(
                    path: "/tmp/a.jsonl", projectID: "p", sessionID: "s",
                    isSubagent: false, inode: 42, offset: 10, segmentLines: 1,
                    fingerprint: "abc", updatedAt: Date(timeIntervalSince1970: 1_700_000_001))
            ])
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.fileURL.path)
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try Data("not a cursor".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            guard case QoderCollectionStateError.corruptLegacyCursor = error else {
                return XCTFail("expected corruptLegacyCursor, got \(error)")
            }
        }
    }

    func testInvalidResumeOffsetFailsClosedWithoutAdvancingOrOrphaning() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "hello")], to: file)
        let first = QoderTranscriptTailer(scanRoot: root, state: pastState())
        XCTAssertTrue(Fixture.turns(poll(first).events).isEmpty)

        var state = first.cursorState
        let key = try XCTUnwrap(state.cursors.keys.first)
        let healthy = try XCTUnwrap(state.cursors[key])
        XCTAssertEqual(healthy.resumeOffset, 0)
        state.cursors[key] = QoderFileCursor(
            path: healthy.path, projectID: healthy.projectID,
            sessionID: healthy.sessionID, isSubagent: healthy.isSubagent,
            inode: healthy.inode, offset: healthy.offset,
            segmentLines: healthy.segmentLines,
            resumeOffset: 1, resumeSegmentLines: 0,
            fingerprint: healthy.fingerprint, updatedAt: healthy.updatedAt)

        // The answer arrives while the cursor can no longer name its anchor.
        try Fixture.writeLines(
            [
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world"),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ], to: file, append: true)

        let resumed = QoderTranscriptTailer(scanRoot: root, state: state)
        let blocked = poll(resumed)
        XCTAssertTrue(blocked.events.isEmpty)
        XCTAssertTrue(Fixture.orphans(blocked.events).isEmpty)
        XCTAssertEqual(blocked.report.deliveredEvents, 0)
        XCTAssertEqual(blocked.report.readBytes, 0)
        XCTAssertTrue(
            blocked.report.errors.contains { $0.contains("corrupt resume point") })
        XCTAssertEqual(resumed.cursorState, state)

        // Repeating the poll keeps the path stopped instead of degrading into
        // a forward read that would emit the answer as an orphan.
        let again = poll(resumed)
        XCTAssertTrue(again.events.isEmpty)
        XCTAssertTrue(
            again.report.errors.contains { $0.contains("corrupt resume point") })
        XCTAssertEqual(resumed.cursorState, state)
    }

    func testInconsistentResumeFieldsFailClosed() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "hello")], to: file)
        let first = QoderTranscriptTailer(scanRoot: root, state: pastState())
        poll(first)

        var state = first.cursorState
        let key = try XCTUnwrap(state.cursors.keys.first)
        let healthy = try XCTUnwrap(state.cursors[key])
        // The line count claims an open turn although the byte offset says
        // there is none, so neither field can be trusted as the anchor.
        state.cursors[key] = QoderFileCursor(
            path: healthy.path, projectID: healthy.projectID,
            sessionID: healthy.sessionID, isSubagent: healthy.isSubagent,
            inode: healthy.inode, offset: healthy.offset,
            segmentLines: healthy.segmentLines,
            resumeOffset: healthy.offset, resumeSegmentLines: 0,
            fingerprint: healthy.fingerprint, updatedAt: healthy.updatedAt)

        let resumed = QoderTranscriptTailer(scanRoot: root, state: state)
        let blocked = poll(resumed)
        XCTAssertTrue(blocked.events.isEmpty)
        XCTAssertEqual(blocked.report.readBytes, 0)
        XCTAssertTrue(
            blocked.report.errors.contains { $0.contains("corrupt resume point") })
        XCTAssertEqual(resumed.cursorState, state)
    }

    func testScannerDistinguishesAbsentFromComplete() throws {
        let scanner = QoderTranscriptScanner(root: root)
        guard case .complete(let empty) = scanner.scan() else {
            return XCTFail("an empty tree is a complete walk with no files")
        }
        XCTAssertTrue(empty.isEmpty)

        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let found = scanner.scan()
        XCTAssertTrue(found.isComplete)
        XCTAssertTrue(found.errors.isEmpty)
        XCTAssertEqual(found.files.map(\.sessionID), [Fixture.sessionID])

        try FileManager.default.removeItem(at: root)
        XCTAssertEqual(scanner.scan(), .absent)
    }

    func testScannerReportsPartialWhenAProjectCannotBeListed() throws {
        try XCTSkipIf(getuid() == 0, "root ignores directory permissions")
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: project.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: project.path)
        }

        let result = QoderTranscriptScanner(root: root).scan()
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testCompleteScanRetiresCursorsForDeletedFiles() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let tailer = QoderTranscriptTailer(scanRoot: root, state: pastState())
        poll(tailer)
        XCTAssertEqual(tailer.cursorState.cursors.count, 1)

        try FileManager.default.removeItem(at: file)
        let result = poll(tailer)
        XCTAssertTrue(result.report.errors.isEmpty)
        XCTAssertTrue(tailer.cursorState.cursors.isEmpty)
        XCTAssertTrue(result.report.stateChanged)
    }

    func testPartialScanKeepsCursorsAndReportsTheFailure() throws {
        try XCTSkipIf(getuid() == 0, "root ignores directory permissions")
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let tailer = QoderTranscriptTailer(scanRoot: root, state: pastState())
        poll(tailer)
        let saved = tailer.cursorState
        XCTAssertEqual(saved.cursors.count, 1)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: project.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: project.path)
        }

        let failed = poll(tailer)
        XCTAssertTrue(failed.events.isEmpty)
        XCTAssertFalse(failed.report.errors.isEmpty)
        XCTAssertEqual(tailer.cursorState, saved)
        XCTAssertFalse(failed.report.stateChanged)
    }

    func testMissingRootKeepsCursors() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let tailer = QoderTranscriptTailer(scanRoot: root, state: pastState())
        poll(tailer)
        let saved = tailer.cursorState
        XCTAssertEqual(saved.cursors.count, 1)

        try FileManager.default.removeItem(at: root)
        let missing = poll(tailer)
        XCTAssertTrue(missing.events.isEmpty)
        XCTAssertTrue(missing.report.errors.isEmpty)
        XCTAssertEqual(tailer.cursorState, saved)
        XCTAssertFalse(missing.report.stateChanged)
    }
}
