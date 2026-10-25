import InformationCore
import XCTest

@testable import t4ctl

final class FolderInformationInitializerTests: XCTestCase {
  private var root: URL!
  private var databasePath: String!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    root = root.resolvingSymlinksInPath()
    databasePath = temporaryDatabasePath()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(atPath: databasePath)
  }

  private func temporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".sqlite").path
  }

  private func fetchStored(_ report: FolderInformationInitializer.Report) throws -> [Information] {
    let store = try SQLiteStore(path: databasePath)
    return try report.entries
      .filter { $0.extractionStatus == .stored }
      .compactMap { try store.fetch(by: InformationID(rawValue: $0.identity)) }
  }

  func testRecursiveTextFolderBecomesInformationSpace() throws {
    try Data("alpha content".utf8).write(to: root.appendingPathComponent("a.txt"))
    try Data("# beta markdown\n\nbody".utf8).write(to: root.appendingPathComponent("b.md"))
    let sub = root.appendingPathComponent("sub", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data("gamma content".utf8).write(to: sub.appendingPathComponent("c.txt"))

    let report = try FolderInformationInitializer().initialize(
      folderPath: root.path,
      databasePath: databasePath
    )
    let stored = try fetchStored(report)

    XCTAssertEqual(report.directoriesScanned, 2)
    XCTAssertEqual(report.filesScanned, 3)
    XCTAssertEqual(report.informationFormed, 5)
    XCTAssertEqual(report.informationStored, 5)
    XCTAssertEqual(report.extractionSucceeded, 5)
    XCTAssertEqual(report.extractionSkipped, 0)
    XCTAssertEqual(report.extractionFailed, 0)
    XCTAssertEqual(stored.count, 5)

    let textContents = Set(
      stored.filter { $0.provenance.extractionMode == "verbatim-text" }.map(\.content))
    XCTAssertEqual(textContents, ["alpha content", "# beta markdown\n\nbody", "gamma content"])
    XCTAssertTrue(stored.contains { $0.content.contains("FOLDER_SNAPSHOT") })
    XCTAssertTrue(stored.allSatisfy { $0.provenance.source?.hasPrefix(root.path) == true })
  }

  func testRepeatedInitializationIsIdempotentForUnchangedFolder() throws {
    try Data("stable content".utf8).write(to: root.appendingPathComponent("a.txt"))
    let first = try FolderInformationInitializer().initialize(
      folderPath: root.path,
      databasePath: databasePath
    )
    let firstStored = try fetchStored(first)

    let second = try FolderInformationInitializer().initialize(
      folderPath: root.path,
      databasePath: databasePath
    )
    let secondStored = try fetchStored(second)

    XCTAssertEqual(second.informationFormed, first.informationFormed)
    XCTAssertEqual(second.informationStored, first.informationStored)
    XCTAssertEqual(Set(secondStored), Set(firstStored))
  }

  func testEmptyFolderFormsOnlyFolderInventory() throws {
    let report = try FolderInformationInitializer().initialize(
      folderPath: root.path,
      databasePath: databasePath
    )
    let stored = try fetchStored(report)

    XCTAssertEqual(report.directoriesScanned, 1)
    XCTAssertEqual(report.filesScanned, 0)
    XCTAssertEqual(report.informationStored, 1)
    XCTAssertEqual(stored.count, 1)
    XCTAssertTrue(stored[0].content.contains("direct_entries\t0"))
  }

  func testUnsupportedAndEmptyTextAreNotFabricated() throws {
    try Data([0x00, 0x01, 0xff]).write(to: root.appendingPathComponent("binary.bin"))
    try Data().write(to: root.appendingPathComponent("empty.txt"))

    let report = try FolderInformationInitializer().initialize(
      folderPath: root.path,
      databasePath: databasePath
    )

    XCTAssertEqual(report.filesScanned, 2)
    XCTAssertEqual(report.informationStored, 1)  // folder inventory only
    XCTAssertEqual(report.extractionSkipped, 2)
    XCTAssertTrue(
      report.entries.contains {
        $0.source.hasSuffix("binary.bin") && $0.reason == "unsupported or non-text format"
      })
    XCTAssertTrue(
      report.entries.contains {
        $0.source.hasSuffix("empty.txt") && $0.reason?.contains("empty text") == true
      })
  }

  func testUnreadableFileIsReportedAsFailure() throws {
    let unreadable = root.appendingPathComponent("unreadable.txt")
    try Data("secret".utf8).write(to: unreadable)
    guard chmod(unreadable.path, 0o000) == 0 else {
      throw XCTSkip("could not construct unreadable file in this environment")
    }
    defer { chmod(unreadable.path, 0o644) }

    let report = try FolderInformationInitializer().initialize(
      folderPath: root.path,
      databasePath: databasePath
    )

    XCTAssertEqual(report.extractionFailed, 1)
    XCTAssertEqual(report.informationStored, 1)  // folder inventory only
    XCTAssertTrue(report.failures.contains { $0.contains("unreadable.txt") })
  }
}
