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
        try QoderFileCursorStore(directoryURL: configuration.stateDirectory)
            .load()?.cursors.values.first
    }

    func testRunnerPersistsCursorAndResumesInNewInstance() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let configuration = configuration()
        var events: [QoderCollectionEvent] = []
        let first = QoderCollectionRunner(configuration: configuration) {
            events.append(contentsOf: $0)
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
        let resumed = QoderCollectionRunner(configuration: configuration) {
            events.append(contentsOf: $0)
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
            events.append(contentsOf: $0)
        }
        first.pollOnce()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: configuration().stateDirectory.appendingPathComponent(
                    "cursor.json").path))

        let file = mainFile()
        try Fixture.writeLines([Fixture.userLine(uuid: "u-1", text: "hello")], to: file)
        first.pollOnce()
        XCTAssertTrue(Fixture.turns(events).isEmpty)

        let stored = try XCTUnwrap(
            QoderFileCursorStore(directoryURL: configuration().stateDirectory).load())
        let anchorCursor = try XCTUnwrap(stored.cursors.values.first)
        XCTAssertEqual(anchorCursor.resumeOffset, 0)
        XCTAssertEqual(anchorCursor.resumeSegmentLines, 0)

        try Fixture.writeLines(
            [
                Fixture.assistantLine(
                    uuid: "a-1", parent: "u-1", messageID: "m-1", text: "world"),
                Fixture.userLine(uuid: "u-2", parent: "a-1", text: "next"),
            ], to: file, append: true)
        events.removeAll()
        let resumed = QoderCollectionRunner(configuration: configuration()) {
            events.append(contentsOf: $0)
        }
        resumed.pollOnce()
        let turns = Fixture.turns(events)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.anchor.id, "u-1")
        XCTAssertEqual(turns.first?.answerText, "world")
        XCTAssertEqual(turns.first?.relation, .parentChain)
        XCTAssertTrue(Fixture.orphans(events).isEmpty)
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
