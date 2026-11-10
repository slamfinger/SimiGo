import Darwin
import Foundation
import XCTest
@testable import SimiGoCollection

final class TranscriptTailerTests: XCTestCase {
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
        _ tailer: TranscriptTailer,
        sink: (([CollectionEvent]) throws -> Void)? = nil
    ) -> (events: [CollectionEvent], report: PollReport) {
        var events: [CollectionEvent] = []
        let report = tailer.poll { batch in
            events.append(contentsOf: batch)
            try sink?(batch)
        }
        return (events, report)
    }

    private func pastState() -> CursorState {
        CursorState(initializedAt: Date(timeIntervalSinceNow: -3600))
    }

    /// TemporaryDirectory is reached through `/var`, but FileManager enumerates
    /// `/private/var`, so cursor keys are the scanner's canonical paths.
    private func cursor(_ tailer: TranscriptTailer) -> FileCursor? {
        tailer.cursorState.cursors.values.first
    }

    func testCursorStoreDoesNotFollowSymlinkAndAtomicSavePreservesTarget() throws {
        let stateDirectory = root.appendingPathComponent("cursor-state", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true)
        let external = root.appendingPathComponent("external-cursor.json")
        let original = try JSONEncoder().encode(pastState())
        try original.write(to: external)
        let cursor = stateDirectory.appendingPathComponent("cursor.json")
        try FileManager.default.createSymbolicLink(at: cursor, withDestinationURL: external)
        let store = FileCursorStore(directoryURL: stateDirectory)

        XCTAssertThrowsError(
            try store.load(),
            "legacy cursor loading must not follow a symlink to an external file")
        XCTAssertEqual(try Data(contentsOf: external), original)

        // A normal atomic save replaces the directory entry, not its target.
        // The subsequent no-follow chmod must apply to the newly written file.
        let replacement = pastState()
        try store.save(replacement)
        XCTAssertThrowsError(
            try FileManager.default.destinationOfSymbolicLink(atPath: cursor.path),
            "save must leave a regular cursor file rather than a symlink")
        XCTAssertEqual(try Data(contentsOf: external), original)
        XCTAssertNotNil(try store.load())
    }

    func testCursorStoreRejectsHardlinkAndAtomicSaveLeavesExternalTargetUntouched() throws {
        let stateDirectory = root.appendingPathComponent("hardlinked-cursor-state", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true)
        let external = root.appendingPathComponent("external-hardlinked-cursor.json")
        let linkedPath = "/tmp/qoder-hardlink-source.jsonl"
        let linkedCursor = FileCursor(
            path: linkedPath, projectID: "p", sessionID: "s", isSubagent: false,
            inode: 1, offset: 10, segmentLines: 1,
            fingerprint: "abc", updatedAt: Date(timeIntervalSince1970: 1))
        let originalState = CursorState(
            initializedAt: Date(timeIntervalSince1970: 1),
            cursors: [linkedPath: linkedCursor])
        let original = try JSONEncoder().encode(originalState)
        try original.write(to: external)

        let cursorURL = stateDirectory.appendingPathComponent("cursor.json")
        try FileManager.default.linkItem(at: external, to: cursorURL)
        let store = FileCursorStore(directoryURL: stateDirectory)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(
                String(describing: error).contains("link count one"),
                "cursor loading must reject hardlinked state: \(error)")
        }
        XCTAssertEqual(try Data(contentsOf: external), original)

        let replacement = CursorState(initializedAt: Date(timeIntervalSince1970: 2))
        try store.save(replacement)
        XCTAssertEqual(try store.load(), replacement)
        XCTAssertEqual(
            try Data(contentsOf: external), original,
            "atomic replacement and chmod must not modify the hardlink target")
    }

    func testFirstPollBaselinesExistingFileAtEnd() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let size = Int64(try Data(contentsOf: file).count)

        let tailer = TranscriptTailer(scanRoot: root, now: Date())
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

    func testPostReadFingerprintFailureDiscardsCandidatesAndReplaysFromCursor() throws {
        let file = mainFile()
        try Fixture.writeLines(
            Fixture.turnLines(prompt: "first prompt", answer: "first answer"),
            to: file)

        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(), baselinePolicy: .readExisting)
        var fingerprintCalls = 0
        tailer.trailingFingerprintOverride = { path, offset, _ in
            fingerprintCalls += 1
            // The only call in a first-seen read is the post-parse
            // verification; fail it after the accumulator has ingested lines.
            if fingerprintCalls == 1 { return nil }
            guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return nil
            }
            let end = min(Int(offset), bytes.count)
            let start = max(0, end - 256)
            return SourceDigest.sha256Hex(bytes.subdata(in: start..<end))
        }

        let failed = poll(tailer)
        XCTAssertEqual(fingerprintCalls, 1)
        XCTAssertTrue(failed.report.errors.contains {
            $0.contains("cannot fingerprint") && $0.contains("after read")
        })
        XCTAssertEqual(failed.events.count, 1, "only the baseline event is deliverable")
        XCTAssertEqual(Fixture.baselines(failed.events).first?.reason, .existingFileFromStart)
        XCTAssertTrue(Fixture.turns(failed.events).isEmpty)
        XCTAssertEqual(cursor(tailer)?.offset, 0, "failed verification must not advance the durable cursor")

        tailer.trailingFingerprintOverride = nil
        let replayed = poll(tailer)
        XCTAssertEqual(Fixture.turns(replayed.events).count, 1)
        XCTAssertEqual(Fixture.turns(replayed.events).first?.promptText, "first prompt")
        XCTAssertEqual(Fixture.turns(replayed.events).first?.answerText, "first answer")
        XCTAssertEqual(cursor(tailer)?.offset, Int64(try Data(contentsOf: file).count))
    }

    /// 采集桥语义：`readExisting` 把启用前就存在的会话从头读进来，而不是
    /// 在 EOF 立一个空基线。默认策略的对照在上面那条测试里。
    func testReadExistingPolicyBackfillsExistingFileFromStart() throws {
        let file = mainFile()
        try Fixture.writeLines(
            Fixture.turnLines(prompt: "first prompt", answer: "first answer"),
            to: file)

        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(), baselinePolicy: .readExisting)
        let result = poll(tailer)

        XCTAssertEqual(result.report.scannedFiles, 1)
        XCTAssertEqual(result.report.backfilledFiles, 1)
        XCTAssertEqual(result.report.baselinedFiles, 0)
        let baseline = try XCTUnwrap(Fixture.baselines(result.events).first)
        XCTAssertEqual(baseline.reason, .existingFileFromStart)
        XCTAssertEqual(baseline.offset, 0)
        let turns = Fixture.turns(result.events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.promptText, "first prompt")
        XCTAssertEqual(turns.first?.answerText, "first answer")
        XCTAssertGreaterThan(result.report.readBytes, 0)

        // 第二轮不再回填：游标已存在，只走增量。
        let second = poll(tailer)
        XCTAssertTrue(second.events.isEmpty)
        XCTAssertEqual(second.report.backfilledFiles, 0)
    }

    /// 采集桥是**后来**打开的：先前的 `skip_existing` 已在 EOF 立了游标，
    /// 换成 `read_existing` 必须把那段既有会话读出来，而不是继承旧位置。
    func testSwitchingPolicyRetiresCursorsMadeAtEndOfFile() throws {
        let file = mainFile()
        try Fixture.writeLines(
            Fixture.turnLines(prompt: "before enable", answer: "old answer"), to: file)

        let skipped = TranscriptTailer(scanRoot: root, now: Date())
        let first = poll(skipped)
        XCTAssertTrue(Fixture.turns(first.events).isEmpty)

        let reader = TranscriptTailer(
            scanRoot: root, state: skipped.cursorState, baselinePolicy: .readExisting)
        let result = poll(reader)

        let turns = Fixture.turns(result.events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.promptText, "before enable")
        XCTAssertEqual(result.report.backfilledFiles, 1)
        XCTAssertEqual(result.report.baselinedFiles, 0)
        XCTAssertEqual(reader.cursorState.policy, BaselinePolicy.readExisting.rawValue)

        // 策略稳定后不再重复回填。
        let second = poll(reader)
        XCTAssertTrue(second.events.isEmpty)
    }

    func testAppendedTurnIsCollectedAfterBaseline() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let tailer = TranscriptTailer(scanRoot: root, now: Date())
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
        let tailer = TranscriptTailer(scanRoot: root, now: Date())
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
        let first = TranscriptTailer(scanRoot: root, now: Date())
        poll(first)

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-2", answerUUID: "a-2", messageID: "m-2",
                nextAnchor: "u-3", parent: "a-1"),
            to: file,
            append: true)

        let resumed = TranscriptTailer(
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
        let first = TranscriptTailer(scanRoot: root, state: pastState())
        let opened = poll(first)
        XCTAssertTrue(Fixture.turns(opened.events).isEmpty)
        let stored = try XCTUnwrap(cursor(first))
        XCTAssertEqual(stored.resumeOffset, 0)
        XCTAssertEqual(stored.resumeSegmentLines, 0)
        XCTAssertEqual(stored.offset, Int64(try Data(contentsOf: file).count))

        // The process restarts here: only the persisted cursor survives.
        let resumed = TranscriptTailer(scanRoot: root, state: first.cursorState)
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
        let first = TranscriptTailer(scanRoot: root, state: pastState())
        XCTAssertTrue(Fixture.turns(poll(first).events).isEmpty)

        let resumed = TranscriptTailer(scanRoot: root, state: first.cursorState)
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
        let continuous = TranscriptTailer(
            scanRoot: continuousRoot, state: pastState())
        let reference = try XCTUnwrap(Fixture.turns(poll(continuous).events).first)

        let restartedRoot = try makeRoot()
        defer { try? FileManager.default.removeItem(at: restartedRoot) }
        let restartedFile = projectFile(in: restartedRoot)
        try Fixture.writeLines(Array(lines.prefix(2)), to: restartedFile)
        let first = TranscriptTailer(
            scanRoot: restartedRoot, state: pastState())
        XCTAssertTrue(Fixture.turns(poll(first).events).isEmpty)

        let resumed = TranscriptTailer(
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
        let first = TranscriptTailer(scanRoot: root, state: pastState())
        XCTAssertEqual(Fixture.turns(poll(first).events).count, 1)

        let stored = try XCTUnwrap(cursor(first))
        let closedLines = Fixture.turnLines().prefix(2)
        let anchorStart = closedLines.reduce(Int64(0)) { $0 + Int64($1.utf8.count + 1) }
        XCTAssertEqual(stored.resumeOffset, anchorStart)
        XCTAssertEqual(stored.resumeSegmentLines, 2)
        XCTAssertLessThan(stored.resumeOffset, stored.offset)

        let resumed = TranscriptTailer(scanRoot: root, state: first.cursorState)
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
        let first = TranscriptTailer(scanRoot: root, state: pastState())
        XCTAssertEqual(Fixture.orphans(poll(first).events).count, 1)

        let stored = try XCTUnwrap(cursor(first))
        XCTAssertEqual(stored.resumeOffset, stored.offset)
        XCTAssertEqual(stored.resumeSegmentLines, stored.segmentLines)

        let resumed = TranscriptTailer(scanRoot: root, state: first.cursorState)
        let idle = poll(resumed)
        XCTAssertTrue(idle.events.isEmpty)
        XCTAssertEqual(idle.report.replayedBytes, 0)
        XCTAssertEqual(idle.report.readBytes, 0)
    }

    func testSinkFailureAfterRestartReplaysFromAnchor() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "hello")], to: file)
        let first = TranscriptTailer(scanRoot: root, state: pastState())
        poll(first)

        let resumed = TranscriptTailer(scanRoot: root, state: first.cursorState)
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
        let store = FileCursorStore(directoryURL: directory)
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

        let tailer = TranscriptTailer(scanRoot: root, state: state)
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
        let first = TranscriptTailer(scanRoot: root, now: Date())
        poll(first)

        try Data().write(to: file)
        try Fixture.append(
            Fixture.userLine(uuid: "u-1", text: "after truncate") + "\n",
            to: file)
        let newSize = Int64(try Data(contentsOf: file).count)

        let resumed = TranscriptTailer(
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
        let first = TranscriptTailer(scanRoot: root, now: Date())
        poll(first)

        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "bbbb")], to: file)
        XCTAssertEqual(Int64(try Data(contentsOf: file).count), originalSize)

        let resumed = TranscriptTailer(
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
        let first = TranscriptTailer(scanRoot: root, now: Date())
        poll(first)
        try Fixture.writeLines(Fixture.turnLines(), to: file, append: true)

        var state = first.cursorState
        let key = try XCTUnwrap(state.cursors.keys.first)
        let existing = try XCTUnwrap(state.cursors[key])
        state.cursors[key] = FileCursor(
            path: existing.path, projectID: existing.projectID,
            sessionID: existing.sessionID, isSubagent: existing.isSubagent,
            inode: existing.inode &+ 1, offset: 0, segmentLines: 0,
            fingerprint: SourceDigest.sha256Hex(Data()), updatedAt: existing.updatedAt)

        let resumed = TranscriptTailer(scanRoot: root, state: state)
        let result = poll(resumed)
        XCTAssertEqual(
            Fixture.baselines(result.events).first?.reason, .identityReset)
        XCTAssertTrue(Fixture.turns(result.events).isEmpty)
        XCTAssertEqual(
            cursor(resumed)?.offset,
            Int64(try Data(contentsOf: file).count))
    }

    func testSymlinkedSubagentsDirectoryIsNotTraversed() throws {
        let sessionDirectory = project.appendingPathComponent(
            Fixture.sessionID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionDirectory, withIntermediateDirectories: true)

        let external = FileManager.default.temporaryDirectory.appendingPathComponent(
            "qoder-external-subagents-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createDirectory(
            at: external, withIntermediateDirectories: true)
        try Fixture.writeLines(
            Fixture.turnLines(), to: external.appendingPathComponent("outside.jsonl"))

        let link = sessionDirectory.appendingPathComponent(
            "subagents", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: external)

        var scanner = TranscriptScanner(root: root)
        let result = scanner.scan()
        guard case .complete(let files) = result else {
            return XCTFail("symlinked subagents directory should be ignored, got \(result)")
        }
        XCTAssertTrue(
            files.isEmpty,
            "transcripts outside the configured scan root must not be returned")
    }

    func testSubagentTurnsAreCollectedAsInternalRecords() throws {
        let file = try subagentFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)

        let tailer = TranscriptTailer(scanRoot: root, state: pastState())
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
        let tailer = TranscriptTailer(scanRoot: root, state: pastState())

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
        let tailer = TranscriptTailer(scanRoot: root, state: pastState())
        let result = poll(tailer)
        XCTAssertEqual(result.report.parseFailures, 1)
        XCTAssertEqual(Fixture.failures(result.events).first?.segmentLine, 1)

        try Fixture.writeLines(Fixture.turnLines(), to: file, append: true)
        let next = poll(tailer)
        XCTAssertEqual(Fixture.turns(next.events).count, 1)
    }

    func testCursorStoreRoundTripPermissionsAndCorruptFile() throws {
        let directory = root.appendingPathComponent("state", isDirectory: true)
        let store = FileCursorStore(directoryURL: directory)
        XCTAssertNil(try store.load())

        let state = CursorState(
            initializedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cursors: [
                "/tmp/a.jsonl": FileCursor(
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
            guard case CollectionStateFailure.corruptLegacyCursor = error else {
                return XCTFail("expected corruptLegacyCursor, got \(error)")
            }
        }
    }

    func testCursorStoreBoundsStateBytesAndTrackedCursorCount() throws {
        let directory = root.appendingPathComponent("bounded-cursor-state", isDirectory: true)
        let store = FileCursorStore(directoryURL: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let oversized = Data(
            repeating: 0x78, count: FileCursorStore.maximumCursorStateBytes + 1)
        try oversized.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(
                String(describing: error).contains("maximum cursor-state byte limit"),
                "oversized durable state must fail before JSON decoding: \(error)")
        }
        try FileManager.default.removeItem(at: store.fileURL)

        var cursors: [String: FileCursor] = [:]
        for index in 0...FileCursorStore.maximumCursorCount {
            let path = "/tmp/qoder-cursor-\(index).jsonl"
            cursors[path] = FileCursor(
                path: path, projectID: "p", sessionID: "s", isSubagent: false,
                inode: 1, offset: 0, segmentLines: 0,
                fingerprint: "empty", updatedAt: Date(timeIntervalSince1970: 0))
        }
        XCTAssertThrowsError(try store.save(CursorState(
            initializedAt: Date(timeIntervalSince1970: 0), cursors: cursors))) { error in
                XCTAssertTrue(
                    String(describing: error).contains("maximum tracked cursor count"),
                    "state writes must reject excess cursor entries before encoding: \(error)")
            }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))

        let oversizedPath = String(repeating: "x", count: 4_500_000)
        let pathCursor = FileCursor(
            path: oversizedPath, projectID: "p", sessionID: "s", isSubagent: false,
            inode: 1, offset: 0, segmentLines: 0,
            fingerprint: "empty", updatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertThrowsError(try store.save(CursorState(
            initializedAt: Date(timeIntervalSince1970: 0),
            cursors: [oversizedPath: pathCursor]))) { error in
                XCTAssertTrue(
                    String(describing: error).contains("maximum cursor-state byte limit"),
                    "encoded state must stay within its durable byte cap: \(error)")
            }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testInvalidResumeOffsetFailsClosedWithoutAdvancingOrOrphaning() throws {
        let file = mainFile()
        try Fixture.writeLines(
            [Fixture.userLine(uuid: "u-1", text: "hello")], to: file)
        let first = TranscriptTailer(scanRoot: root, state: pastState())
        XCTAssertTrue(Fixture.turns(poll(first).events).isEmpty)

        var state = first.cursorState
        let key = try XCTUnwrap(state.cursors.keys.first)
        let healthy = try XCTUnwrap(state.cursors[key])
        XCTAssertEqual(healthy.resumeOffset, 0)
        state.cursors[key] = FileCursor(
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

        let resumed = TranscriptTailer(scanRoot: root, state: state)
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
        let first = TranscriptTailer(scanRoot: root, state: pastState())
        poll(first)

        var state = first.cursorState
        let key = try XCTUnwrap(state.cursors.keys.first)
        let healthy = try XCTUnwrap(state.cursors[key])
        // The line count claims an open turn although the byte offset says
        // there is none, so neither field can be trusted as the anchor.
        state.cursors[key] = FileCursor(
            path: healthy.path, projectID: healthy.projectID,
            sessionID: healthy.sessionID, isSubagent: healthy.isSubagent,
            inode: healthy.inode, offset: healthy.offset,
            segmentLines: healthy.segmentLines,
            resumeOffset: healthy.offset, resumeSegmentLines: 0,
            fingerprint: healthy.fingerprint, updatedAt: healthy.updatedAt)

        let resumed = TranscriptTailer(scanRoot: root, state: state)
        let blocked = poll(resumed)
        XCTAssertTrue(blocked.events.isEmpty)
        XCTAssertEqual(blocked.report.readBytes, 0)
        XCTAssertTrue(
            blocked.report.errors.contains { $0.contains("corrupt resume point") })
        XCTAssertEqual(resumed.cursorState, state)
    }

    func testNoFollowReaderRejectsSymlinkHardlinkAndIntermediateDirectories() throws {
        let fileManager = FileManager.default
        let nestedDirectory = project.appendingPathComponent("nested", isDirectory: true)
        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        let regularFile = nestedDirectory.appendingPathComponent("session.jsonl")
        try Data("{\"type\":\"message\"}\n".utf8).write(to: regularFile)

        let outside = fileManager.temporaryDirectory
            .appendingPathComponent("qoder-nofollow-outside-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("session.jsonl")
        try Data("{\"type\":\"outside\"}\n".utf8).write(to: outsideFile)
        defer { try? fileManager.removeItem(at: outside) }

        let canonicalRoot = TranscriptPathAccess.canonicalPath(root.path)
        let rootFD = try TranscriptPathAccess.openDirectoryPathNoFollow(canonicalRoot)
        defer { Darwin.close(rootFD) }
        let relative = "\(Fixture.projectID)/nested/session.jsonl"
        let opened = try TranscriptPathAccess.openFile(
            rootDirectoryFD: rootFD, relativePath: relative)
        Darwin.close(opened.descriptor)

        try fileManager.removeItem(at: regularFile)
        try fileManager.linkItem(at: outsideFile, to: regularFile)
        XCTAssertThrowsError(
            try TranscriptPathAccess.openFile(
                rootDirectoryFD: rootFD, relativePath: relative),
            "a hard-linked external file must not be read as a transcript")

        try fileManager.removeItem(at: regularFile)
        try Data("{\"type\":\"message\"}\n".utf8).write(to: regularFile)
        try fileManager.removeItem(at: regularFile)
        try fileManager.createSymbolicLink(at: regularFile, withDestinationURL: outsideFile)
        XCTAssertThrowsError(
            try TranscriptPathAccess.openFile(
                rootDirectoryFD: rootFD, relativePath: relative),
            "a symlink leaf must never be read")

        try fileManager.removeItem(at: regularFile)
        try Data("{\"type\":\"message\"}\n".utf8).write(to: regularFile)
        try fileManager.moveItem(
            at: nestedDirectory,
            to: project.appendingPathComponent("nested-original", isDirectory: true))
        try fileManager.createSymbolicLink(at: nestedDirectory, withDestinationURL: outside)
        XCTAssertThrowsError(
            try TranscriptPathAccess.openFile(
                rootDirectoryFD: rootFD, relativePath: relative),
            "a symlinked parent directory must never be traversed")
    }

    func testScannerDistinguishesAbsentFromComplete() throws {
        var scanner = TranscriptScanner(root: root)
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

    func testScannerNeverFollowsSymlinkedSubagentsDirectory() throws {
        let fileManager = FileManager.default
        let sessionDirectory = project.appendingPathComponent(
            Fixture.sessionID, isDirectory: true)
        try fileManager.createDirectory(
            at: sessionDirectory, withIntermediateDirectories: true)

        let outside = fileManager.temporaryDirectory.appendingPathComponent(
            "qoder-outside-subagents-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: outside) }

        let externalTranscript = outside.appendingPathComponent(
            "external-agent.jsonl")
        try Data(#"{"type":"message"}"#.appending("\n").utf8).write(to: externalTranscript)

        let subagents = sessionDirectory.appendingPathComponent(
            "subagents", isDirectory: true)
        try fileManager.createSymbolicLink(
            at: subagents, withDestinationURL: outside)

        var scanner = TranscriptScanner(root: root)
        let result = scanner.scan()
        XCTAssertTrue(result.isComplete, "a rejected symlink is a skipped entry, not a scan failure")
        XCTAssertTrue(
            result.files.isEmpty,
            "scanner must not import transcript files through a symlinked subagents directory")
    }

    func testScannerClassifiesMissingRootAndUnreadableRootByListingError() throws {
        let missing = root.appendingPathComponent("not-created", isDirectory: true)
        var missingScanner = TranscriptScanner(root: missing)
        XCTAssertEqual(missingScanner.scan(), .absent)

        try XCTSkipIf(getuid() == 0, "root ignores directory permissions")
        let protected = root.appendingPathComponent("protected", isDirectory: true)
        try FileManager.default.createDirectory(
            at: protected, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: protected.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: protected.path)
        }

        var scanner = TranscriptScanner(root: protected)
        let result = scanner.scan()
        guard case .partial(let files, let errors) = result else {
            return XCTFail("an unreadable root must be partial, not absent")
        }
        XCTAssertTrue(files.isEmpty)
        XCTAssertFalse(errors.isEmpty, "an unreadable root must report its listing/open error")
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

        var scanner = TranscriptScanner(root: root)
        let result = scanner.scan()
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testCompleteScanRetiresCursorsForDeletedFiles() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let tailer = TranscriptTailer(scanRoot: root, state: pastState())
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
        let tailer = TranscriptTailer(scanRoot: root, state: pastState())
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
        let tailer = TranscriptTailer(scanRoot: root, state: pastState())
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

    // MARK: - Poll budgets are poll-wide, not per file

    private func fill(_ file: URL, atLeast bytes: Int, tag: String) throws {
        var text = ""
        var index = 0
        while text.utf8.count < bytes {
            text += Fixture.turnLines(
                anchor: "u-\(tag)-\(index)", answerUUID: "a-\(tag)-\(index)",
                messageID: "m-\(tag)-\(index)", nextAnchor: "n-\(tag)-\(index)"
            ).joined(separator: "\n") + "\n"
            index += 1
        }
        try Data(text.utf8).write(to: file)
    }

    /// `maxBytesPerPoll` is the budget for the whole poll. Four files with
    /// fresh bytes must not add up to four full windows.
    func testPollByteBudgetIsGlobalAcrossFiles() throws {
        let root = try makeRoot()
        var files: [URL] = []
        for index in 0..<4 {
            let file = projectFile(in: root, session: "budget-\(index)")
            try fill(file, atLeast: 16 * 1024, tag: "b\(index)")
            files.append(file)
        }
        let budget = 4 * 1024
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxBytesPerPoll: budget)

        let first = poll(tailer)
        XCTAssertTrue(first.report.budgetExhausted, "one window cannot cover four files")
        XCTAssertLessThanOrEqual(
            first.report.readBytes, Int64(budget),
            "a single poll read more than its own budget")

        // Fair rotation: repeated polls finish the tree instead of re-reading
        // the same head, and no poll exceeds the budget.
        var polls = 1
        while true {
            polls += 1
            XCTAssertLessThan(polls, 200, "budgeted polls stopped making progress")
            let next = poll(tailer)
            XCTAssertLessThanOrEqual(next.report.readBytes, Int64(budget))
            if !next.report.budgetExhausted { break }
        }
        for file in files {
            let size = Int64(try Data(contentsOf: file).count)
            let cursor = tailer.cursorState.cursors.first {
                $0.key.hasSuffix("/" + file.lastPathComponent)
            }?.value
            XCTAssertEqual(cursor?.offset, size, "file was never drained: \(file.lastPathComponent)")
        }
    }

    /// A line larger than the poll budget is scanned across polls: the scan
    /// spends the same budget as the read, so one poll can no longer pull
    /// `maxLineBytes` (32 MiB by default) out of a single file.
    func testOversizedLineScanSharesThePollBudget() throws {
        let root = try makeRoot()
        let file = projectFile(in: root, session: "huge")
        let line = String(repeating: "x", count: 256 * 1024)
        try Data((line + "\n").utf8).write(to: file)
        let budget = 8 * 1024
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxBytesPerPoll: budget,
            maxLineBytes: 1 << 20)
        let size = Int64(try Data(contentsOf: file).count)

        var polls = 0
        var sawParseFailure = false
        while tailer.cursorState.cursors.values.first?.offset != size {
            polls += 1
            XCTAssertLessThan(polls, 200, "the oversized line never completed")
            let result = poll(tailer)
            sawParseFailure = sawParseFailure || result.report.parseFailures > 0
            XCTAssertLessThanOrEqual(
                result.report.readBytes, Int64(budget),
                "poll \(polls) read past the poll budget")
        }
        XCTAssertGreaterThan(polls, 1, "a line longer than the budget must span polls")
        XCTAssertTrue(sawParseFailure, "an oversized line is a parse failure, not content")
    }

    /// The scan reads whole chunks, so a newline near the front of a chunk still
    /// cost a whole chunk of disk. Charging only the reached position hands the
    /// rest of the poll a budget larger than the disk work that is left.
    func testOversizedLineChargesTheChunkItActuallyRead() throws {
        let root = try makeRoot()
        let file = projectFile(in: root, session: "late-newline")
        let budget = 1 << 20
        var bytes = Data(repeating: 0x78, count: budget)  // "x": no newline
        bytes.append(0x0A)
        bytes.append(Data(repeating: 0x79, count: 900 * 1024))
        try bytes.write(to: file)

        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxBytesPerPoll: budget,
            maxLineBytes: 8 << 20)

        XCTAssertTrue(poll(tailer).report.budgetExhausted, "the window spent the poll")

        let resumed = poll(tailer)
        XCTAssertEqual(
            resumed.report.parseFailures, 1, "the newline ends the dropped line")
        XCTAssertGreaterThan(
            resumed.report.readBytes, Int64(512 * 1024),
            "the chunk is read whole before its newline is found; readBytes must say so")
    }

    /// A scan position belongs to the file identity that produced it. Replacing
    /// the file at the same path must drop it: otherwise the next append resumes
    /// inside a prefix that no longer exists and the new content is never read.
    func testReplacingAFileDropsThePendingOversizedScan() throws {
        let root = try makeRoot()
        let file = projectFile(in: root, session: "replaced")
        try Data(repeating: 0x78, count: 20_000).write(to: file)

        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxBytesPerPoll: 4_096,
            maxLineBytes: 64 * 1024)
        _ = poll(tailer)  // parks a pending scan against the old inode

        // A different file at the same path: an identity reset, not a truncation.
        try FileManager.default.removeItem(at: file)
        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-old", answerUUID: "a-old", messageID: "m-old",
                nextAnchor: "n-old"),
            to: file)
        _ = poll(tailer)

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-new", answerUUID: "a-new", messageID: "m-new",
                nextAnchor: "n-new"),
            to: file, append: true)
        let appended = poll(tailer)

        XCTAssertEqual(
            appended.report.parseFailures, 0,
            "the new file is ordinary content, not a continuation of the old line")
        XCTAssertFalse(
            appended.events.isEmpty,
            "the appended turn must be read instead of being skipped by a stale scan offset")
    }

    /// A scan that stops at its file budget is partial. A partial walk cannot
    /// prove deletion, so cursors it did not see must survive.
    func testScanBudgetIsPartialAndNeverRetiresUnseenCursors() throws {
        let root = try makeRoot()
        for index in 0..<4 {
            let file = projectFile(in: root, session: "scan-\(index)")
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"),
                to: file)
        }
        let first = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting)
        _ = poll(first)
        XCTAssertEqual(first.cursorState.cursors.count, 4)

        let capped = TranscriptTailer(
            scanRoot: root, state: first.cursorState,
            now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxScannedFiles: 1)
        let result = poll(capped)
        XCTAssertFalse(result.report.scanComplete, "a capped walk is not a complete walk")
        XCTAssertEqual(
            capped.cursorState.cursors.count, 4,
            "cursors the capped walk did not see were retired as deleted")
        XCTAssertTrue(
            result.report.errors.contains { $0.contains("scan file budget") },
            "the budget stop must be reported: \(result.report.errors)")
    }

    /// The runner stages a poll's events in memory before committing them, so
    /// the event count of one poll is bounded too.
    func testEventBudgetStopsThePollBeforeStagingUnboundedEvents() throws {
        let root = try makeRoot()
        for index in 0..<4 {
            let file = projectFile(in: root, session: "events-\(index)")
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"),
                to: file)
        }
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxEventsPerPoll: 2)
        let result = poll(tailer)
        XCTAssertTrue(result.report.budgetExhausted)
        let paths = Set(Fixture.baselines(result.events).map(\.path))
        XCTAssertEqual(paths.count, 1, "the poll staged events from more than one file")
    }

    /// The event budget binds inside one file's read as well: a single file
    /// whose parse yields more events than the poll budget stops mid-file
    /// instead of staging the whole flood, and later polls finish the file
    /// without losing or duplicating events.
    func testEventBudgetStopsMidFileBeforeStagingASingleFileFlood() throws {
        var lines: [String] = []
        for index in 0..<6 {
            lines.append(
                contentsOf: Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"))
        }
        try Fixture.writeLines(lines, to: mainFile())

        let reference = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting)
        let whole = poll(reference)
        XCTAssertTrue(whole.events.count > 3, "the fixture must exceed the capped budget")

        let capped = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxEventsPerPoll: 3)
        var collected: [CollectionEvent] = []
        var sawBudgetStop = false
        for _ in 0..<20 {
            let result = poll(capped)
            XCTAssertLessThanOrEqual(
                result.events.count, 3,
                "a poll staged \(result.events.count) events beyond the budget")
            if result.report.budgetExhausted { sawBudgetStop = true }
            collected.append(contentsOf: result.events)
            if result.events.isEmpty { break }
        }
        XCTAssertTrue(sawBudgetStop, "the capped poll must report its budget stop")
        XCTAssertEqual(
            collected.count, whole.events.count,
            "capped polls must deliver the same events as the uncapped read")
        XCTAssertEqual(Fixture.turns(collected).count, Fixture.turns(whole.events).count)
        XCTAssertEqual(
            Fixture.baselines(collected).count, Fixture.baselines(whole.events).count)
        XCTAssertEqual(Fixture.failures(collected).count, Fixture.failures(whole.events).count)
    }

    /// Subagent files spend the same file budget as main files: the walk
    /// stops at the cap instead of letting the subagents branch slip past it.
    func testSubagentFilesShareTheScanFileBudget() throws {
        let projectDir = root.appendingPathComponent(Fixture.projectID, isDirectory: true)
        for index in 0..<2 {
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"),
                to: projectDir.appendingPathComponent("main-\(index).jsonl"))
        }
        let subagents = projectDir
            .appendingPathComponent("session-sub", isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: subagents, withIntermediateDirectories: true)
        for index in 0..<2 {
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "s-\(index)", answerUUID: "sa-\(index)",
                    messageID: "sm-\(index)", nextAnchor: "sn-\(index)"),
                to: subagents.appendingPathComponent("agent-\(index).jsonl"))
        }

        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxScannedFiles: 3)
        let result = poll(tailer)
        XCTAssertFalse(result.report.scanComplete, "a capped walk is not a complete walk")
        XCTAssertEqual(result.report.scannedFiles, 3)
        XCTAssertTrue(
            result.report.errors.contains { $0.contains("scan file budget") },
            "the budget stop must be reported: \(result.report.errors)")
        XCTAssertTrue(
            tailer.cursorState.cursors.keys.contains { $0.contains("/subagents/") },
            "whatever fit under the cap must include a subagent file")
    }

    /// Every surfaced subagents entry is charged to the entry budget, like
    /// the session layer above it.
    func testSubagentEntriesShareTheScanEntryBudget() throws {
        let projectDir = root.appendingPathComponent(Fixture.projectID, isDirectory: true)
        try Fixture.writeLines(
            Fixture.turnLines(), to: projectDir.appendingPathComponent("main.jsonl"))
        let subagents = projectDir
            .appendingPathComponent("session-sub", isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: subagents, withIntermediateDirectories: true)
        try Fixture.writeLines(
            Fixture.turnLines(), to: subagents.appendingPathComponent("agent.jsonl"))

        // Root(1) + one child(2) + one child(3): the fourth charge happens
        // inside the subagents branch, whichever order readdir surfaces the
        // two children in.
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxVisitedEntries: 3)
        let result = poll(tailer)
        XCTAssertFalse(result.report.scanComplete)
        XCTAssertEqual(result.report.scannedFiles, 1)
        XCTAssertTrue(
            result.report.errors.contains { $0.contains("scan entry budget") },
            "the budget stop must be reported: \(result.report.errors)")
    }

    /// The entry budget stops the walk inside a directory: entries past the
    /// cap are never surfaced, and the scan is partial.
    func testDirectoryListingStopsAtTheEntryBudgetMidDirectory() throws {
        let projectDir = root.appendingPathComponent(Fixture.projectID, isDirectory: true)
        for index in 0..<8 {
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"),
                to: projectDir.appendingPathComponent("main-\(index).jsonl"))
        }

        // Root(1) + the first two children(2,3): the fourth charge trips the
        // budget before the rest of the directory is surfaced.
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxVisitedEntries: 3)
        let result = poll(tailer)
        XCTAssertFalse(result.report.scanComplete)
        XCTAssertEqual(result.report.scannedFiles, 2)
        XCTAssertTrue(
            result.report.errors.contains { $0.contains("scan entry budget") },
            "the budget stop must be reported: \(result.report.errors)")
    }

    /// A budget-stopped scan leaves a resume watermark: each later poll
    /// skips — without spending budget on — the entries earlier polls
    /// already processed, so the files behind the budget wall take their
    /// turn and the walk eventually covers the whole tree honestly. readdir
    /// order is the filesystem's, so the assertions are order-agnostic.
    func testPartialScanLeavesAResumePointThatAdvancesAcrossPolls() throws {
        for index in 0..<8 {
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"),
                to: project.appendingPathComponent("main-\(index).jsonl"))
        }

        // root(1) + three children(2..4) per poll: the fifth charge trips.
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxVisitedEntries: 4)
        var surfaced: Set<String> = []
        var complete = false
        var polls = 0
        for _ in 0..<8 {
            let result = poll(tailer)
            polls += 1
            let names = Set(
                Fixture.baselines(result.events).map {
                    ($0.path as NSString).lastPathComponent
                })
            XCTAssertFalse(names.isEmpty, "a poll must surface fresh files")
            XCTAssertEqual(
                names.intersection(surfaced), [],
                "a file was surfaced twice: \(names)")
            surfaced.formUnion(names)
            if result.report.scanComplete {
                complete = true
                break
            }
        }
        XCTAssertTrue(complete, "the walk must eventually cover the whole tree")
        XCTAssertEqual(surfaced.count, 8, "every file must have been surfaced")
        XCTAssertEqual(tailer.cursorState.cursors.count, 8)
        XCTAssertLessThanOrEqual(
            polls, 5,
            "the resume point must advance by more than one file per poll")
    }

    /// A watermark naming an entry that no longer exists must not skip the
    /// whole listing forever: the poll reports the listing as not fully
    /// walked (never complete, so no cursor is retired) and the next walk
    /// starts the listing over. Deleting every file from the first walk
    /// guarantees the watermark name is gone regardless of readdir order.
    func testResumeWatermarkSelfHealsWhenItsEntryVanishes() throws {
        var files: [URL] = []
        for index in 0..<4 {
            let file = project.appendingPathComponent("main-\(index).jsonl")
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"),
                to: file)
            files.append(file)
        }

        // root(1) + one child(2): the third charge trips with the first
        // surfaced file as the watermark, whichever one readdir offers.
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxVisitedEntries: 2)
        let first = poll(tailer)
        XCTAssertEqual(first.report.scannedFiles, 1)
        XCTAssertFalse(first.report.scanComplete)

        for file in files {
            try FileManager.default.removeItem(at: file)
        }
        let second = poll(tailer)
        XCTAssertFalse(
            second.report.scanComplete,
            "a walk that never found its watermark is not a complete walk")
        XCTAssertTrue(
            second.report.errors.contains { $0.contains("scan resume entry not found") },
            "the unresolved watermark must be reported: \(second.report.errors)")
        XCTAssertTrue(
            Fixture.baselines(second.events).isEmpty,
            "the unresolved walk surfaced nothing")
    }

    /// A file created while a resume watermark is in force is read no later
    /// than the poll after the first complete scan — the documented delay
    /// bound, whatever readdir position the new entry lands in.
    func testNewFileCreatedUnderAWatermarkIsReadNoLaterThanFirstCompletePlusOne() throws {
        for index in 0..<6 {
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"),
                to: project.appendingPathComponent("main-\(index).jsonl"))
        }

        // root(1) + one child(2) per poll: the third charge trips, and the
        // walk advances one file per poll.
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxVisitedEntries: 2)
        let first = poll(tailer)
        XCTAssertFalse(first.report.scanComplete)

        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "g-1", answerUUID: "ga-1", messageID: "gm-1",
                nextAnchor: "gn-1"),
            to: project.appendingPathComponent("late.jsonl"))

        var completePoll = 0
        var latePoll = 0
        for pollIndex in 1...20 {
            let result = poll(tailer)
            if latePoll == 0,
                Fixture.baselines(result.events).contains(
                    where: { $0.path.hasSuffix("late.jsonl") })
            {
                latePoll = pollIndex
            }
            if result.report.scanComplete {
                completePoll = pollIndex
                break
            }
        }
        XCTAssertGreaterThan(completePoll, 0, "the walk must reach a complete scan")
        XCTAssertGreaterThan(latePoll, 0, "the new file must eventually be read")
        XCTAssertLessThanOrEqual(
            latePoll, completePoll + 1,
            "the watermark delay is bounded by the first complete scan")
    }

    /// The file budget must stop *before* the entry it refuses. A watermark
    /// left on the refused entry makes every later walk skip it, and the walk
    /// then reaches "complete" without ever listing it.
    func testFileBudgetNeverLeavesTheWatermarkOnTheRefusedEntry() throws {
        for index in 0..<4 {
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-\(index)", answerUUID: "a-\(index)",
                    messageID: "m-\(index)", nextAnchor: "n-\(index)"),
                to: project.appendingPathComponent("main-\(index).jsonl"))
        }

        // Two files per poll: the third entry is charged, then refused.
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxScannedFiles: 2)

        var surfaced: Set<String> = []
        var complete = false
        for _ in 0..<5 {
            let result = poll(tailer)
            surfaced.formUnion(
                Fixture.baselines(result.events).map {
                    ($0.path as NSString).lastPathComponent
                })
            if result.report.scanComplete {
                complete = true
                break
            }
        }
        XCTAssertTrue(complete, "the walk must reach a complete scan")
        XCTAssertEqual(
            surfaced.count, 4,
            "a refused entry must be offered again, not skipped: \(surfaced.sorted())")
        XCTAssertEqual(tailer.cursorState.cursors.count, 4)
    }

    /// A budget that stops inside a session's subagents must leave the
    /// session-level watermark on that session, not past it: skipping the
    /// directory would never open its subagents again, and a later complete
    /// walk would silently retire the files it never listed.
    func testBudgetStoppedInsideSubagentsResumesThatDirectory() throws {
        try Fixture.writeLines(
            Fixture.turnLines(
                anchor: "u-main", answerUUID: "a-main",
                messageID: "m-main", nextAnchor: "n-main"),
            to: projectFile(in: root, session: "s-1"))
        let agents = project
            .appendingPathComponent("s-1", isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: agents, withIntermediateDirectories: true)
        for index in 0..<4 {
            try Fixture.writeLines(
                Fixture.turnLines(
                    anchor: "u-a\(index)", answerUUID: "a-a\(index)",
                    messageID: "m-a\(index)", nextAnchor: "n-a\(index)"),
                to: agents.appendingPathComponent("agent-\(index).jsonl"))
        }

        // Three files per poll. The session layer holds two entries and the
        // subagents layer four, so the budget always stops inside subagents,
        // whatever order readdir yields.
        let tailer = TranscriptTailer(
            scanRoot: root, now: Date(timeIntervalSinceNow: -3600),
            baselinePolicy: .readExisting, maxScannedFiles: 3)

        var surfaced: Set<String> = []
        var complete = false
        for _ in 0..<6 {
            let result = poll(tailer)
            surfaced.formUnion(
                Fixture.baselines(result.events).map {
                    ($0.path as NSString).lastPathComponent
                })
            if result.report.scanComplete {
                complete = true
                break
            }
        }
        XCTAssertTrue(complete, "the walk must reach a complete scan")
        XCTAssertEqual(
            surfaced.count, 5,
            "every subagent behind the budget must be reached: \(surfaced.sorted())")
        XCTAssertEqual(tailer.cursorState.cursors.count, 5)
    }
}
