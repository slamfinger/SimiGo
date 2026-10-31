import Foundation
import XCTest
@testable import SimiGoCollection

final class QoderTranscriptClassifierTests: XCTestCase {

    private func entry(_ line: String) throws -> QoderTranscriptEntry {
        try QoderTranscriptLineParser.parse(Data(line.utf8))
    }

    func testHumanPromptStripsKnownInjectedPrefix() throws {
        let text = "<system-reminder>context</system-reminder>\nreal question"
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(Fixture.userLine(uuid: "u-1", text: text)))
        XCTAssertEqual(classification.kind, .humanPrompt)
        XCTAssertEqual(classification.strippedText, "\nreal question")
        XCTAssertEqual(classification.injectedPrefixes, ["system-reminder"])
    }

    func testUnknownLeadingTagIsKeptVerbatim() throws {
        let text = "<unknown-tag>payload</unknown-tag>"
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(Fixture.userLine(uuid: "u-1", text: text)))
        XCTAssertEqual(classification.kind, .humanPrompt)
        XCTAssertEqual(classification.strippedText, text)
        XCTAssertTrue(classification.injectedPrefixes.isEmpty)
    }

    func testMultipleKnownPrefixesAreStrippedInOrder() throws {
        let text =
            "<qoder_system_reminder>a</qoder_system_reminder>"
            + " <system-reminder>b</system-reminder> ask"
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(Fixture.userLine(uuid: "u-1", text: text)))
        XCTAssertEqual(classification.kind, .humanPrompt)
        XCTAssertEqual(
            classification.injectedPrefixes, ["qoder_system_reminder", "system-reminder"])
        XCTAssertEqual(classification.strippedText, " ask")
    }

    func testInjectedOnlyInputIsNotAHumanPrompt() throws {
        let text = "<system-reminder>only context</system-reminder>"
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(Fixture.userLine(uuid: "u-1", text: text)))
        XCTAssertEqual(classification.kind, .injectedContext)
    }

    func testToolResultIsNotAPrompt() throws {
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(Fixture.userLine(uuid: "u-1", text: "ok", toolResult: true)))
        XCTAssertEqual(classification.kind, .toolResult)
    }

    func testCompactSummaryIsNotAPrompt() throws {
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(
                Fixture.userLine(
                    uuid: "u-1", text: "summary", isCompactSummary: true,
                    isVisibleInTranscriptOnly: true)))
        XCTAssertEqual(classification.kind, .compactSummary)
    }

    func testInterruptMarkers() throws {
        for text in [
            "[Request interrupted by user]",
            "[Request interrupted by user for tool use]",
            "  [Request interrupted by user]  ",
        ] {
            let classification = QoderTranscriptClassifier.classifyUser(
                try entry(Fixture.userLine(uuid: "u-1", text: text)))
            XCTAssertEqual(classification.kind, .interruptMarker, text)
        }
    }

    func testInterruptMarkerInsideLongerTextIsNotAMarker() throws {
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(
                Fixture.userLine(
                    uuid: "u-1", text: "[Request interrupted by user] then keep going")))
        XCTAssertEqual(classification.kind, .humanPrompt)
    }

    func testGoalContinuationMeta() throws {
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(
                Fixture.userLine(
                    uuid: "g-1", text: "Continue working toward the active thread goal.",
                    isMeta: true)))
        XCTAssertEqual(classification.kind, .continuationPrompt)
    }

    func testTaskNotificationMeta() throws {
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(
                Fixture.userLine(
                    uuid: "n-1", text: "[SYSTEM NOTIFICATION - NOT USER INPUT] done",
                    isMeta: true, originKind: "task-notification")))
        XCTAssertEqual(classification.kind, .notificationPrompt)
    }

    func testOtherMetaIsRecordedNotAnchored() throws {
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(Fixture.userLine(uuid: "m-1", text: "internal note", isMeta: true)))
        XCTAssertEqual(classification.kind, .meta)
    }

    func testSupervisionCallback() throws {
        let classification = QoderTranscriptClassifier.classifyUser(
            try entry(
                Fixture.userLine(uuid: "s-1", text: "[监督回调] session s turn t")))
        XCTAssertEqual(classification.kind, .supervisionCallback)
    }

    func testEmptyAndImageOnlyInput() throws {
        let empty = QoderTranscriptClassifier.classifyUser(
            try entry(Fixture.userLine(uuid: "u-1", text: "")))
        XCTAssertEqual(empty.kind, .emptyUserInput)
        let image = QoderTranscriptClassifier.classifyUser(
            try entry(Fixture.userLine(uuid: "u-1", text: "", image: true)))
        XCTAssertEqual(image.kind, .imageOnly)
    }

    func testAssistantTerminalTable() {
        typealias Classifier = QoderTranscriptClassifier
        XCTAssertEqual(
            Classifier.classifyTerminal(
                stop: "end_turn", text: "answer", apiError: false, ambiguous: false),
            .answerCandidate)
        XCTAssertEqual(
            Classifier.classifyTerminal(
                stop: "end_turn", text: "   ", apiError: false, ambiguous: false),
            .emptyAnswer)
        XCTAssertEqual(
            Classifier.classifyTerminal(
                stop: "tool_use", text: "", apiError: false, ambiguous: false),
            .executionEvent)
        XCTAssertEqual(
            Classifier.classifyTerminal(
                stop: "stop_sequence", text: "x", apiError: false, ambiguous: false),
            .stopSequence)
        XCTAssertEqual(
            Classifier.classifyTerminal(
                stop: nil, text: "partial", apiError: false, ambiguous: false),
            .unknownStop)
        XCTAssertEqual(
            Classifier.classifyTerminal(
                stop: "end_turn", text: "quota", apiError: true, ambiguous: false),
            .apiError)
        XCTAssertEqual(
            Classifier.classifyTerminal(
                stop: "end_turn", text: "x", apiError: false, ambiguous: true),
            .ambiguousTerminal)
    }

    func testAssistantEntryClassificationHonorsAPIErrorFlag() throws {
        let line = Fixture.assistantLine(
            uuid: "a-1", parent: "u-1", messageID: "m-1", text: "quota",
            apiError: true)
        let parsed = try entry(line)
        XCTAssertEqual(
            QoderTranscriptClassifier.classifyAssistantTerminal(
                parsed, text: parsed.message?.text ?? "", ambiguous: false),
            .apiError)
    }
}
