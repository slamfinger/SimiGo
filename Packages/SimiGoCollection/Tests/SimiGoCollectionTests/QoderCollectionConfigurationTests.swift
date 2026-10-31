import Foundation
import XCTest
@testable import SimiGoCollection

final class QoderCollectionConfigurationTests: XCTestCase {
    func testStandardUsesDefaultsOnlyWhenOverridesAreUnset() {
        let home = URL(fileURLWithPath: "/tmp/qoder-config-test-home", isDirectory: true)
        let configuration = QoderCollectionConfiguration.standard(
            env: [:], homeDirectory: home)

        XCTAssertNil(configuration.configurationError)
        XCTAssertEqual(
            configuration.scanRoot.path,
            "/tmp/qoder-config-test-home/.qoder-cn/projects")
        XCTAssertEqual(
            configuration.stateDirectory.path,
            "/tmp/qoder-config-test-home/.simigo/collectors/qoder")
    }

    func testStandardRejectsExplicitlyEmptyOverrides() {
        let home = URL(fileURLWithPath: "/tmp/qoder-config-test-home", isDirectory: true)
        let configuration = QoderCollectionConfiguration.standard(
            env: ["QODER_PROJECTS_DIR": "", "SIMIGO_HOME": ""],
            homeDirectory: home)

        XCTAssertTrue(configuration.configurationError?.contains("QODER_PROJECTS_DIR") == true)
        XCTAssertTrue(configuration.configurationError?.contains("SIMIGO_HOME") == true)
    }

    func testStandardRejectsRelativeQoderRoot() {
        let home = URL(fileURLWithPath: "/tmp/qoder-config-test-home", isDirectory: true)
        let configuration = QoderCollectionConfiguration.standard(
            env: ["QODER_PROJECTS_DIR": "../projects"], homeDirectory: home)

        XCTAssertTrue(configuration.configurationError?.contains("absolute path") == true)
    }

    func testStandardRejectsExistingFileAsQoderRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qoder-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: file)
        let configuration = QoderCollectionConfiguration.standard(
            env: ["QODER_PROJECTS_DIR": file.path], homeDirectory: root)

        XCTAssertTrue(configuration.configurationError?.contains("non-directory") == true)
    }

    func testStandardAllowsMissingAbsoluteQoderRoot() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qoder-missing-\(UUID().uuidString)", isDirectory: true)
        let missing = root.appendingPathComponent("projects", isDirectory: true)
        let configuration = QoderCollectionConfiguration.standard(
            env: ["QODER_PROJECTS_DIR": missing.path], homeDirectory: root)

        XCTAssertNil(configuration.configurationError)
        XCTAssertEqual(configuration.scanRoot, missing.standardizedFileURL)
    }

    func testStandardRejectsRelativeSimigoHome() {
        let home = URL(fileURLWithPath: "/tmp/qoder-config-test-home", isDirectory: true)
        let configuration = QoderCollectionConfiguration.standard(
            env: ["SIMIGO_HOME": "relative-state"], homeDirectory: home)

        XCTAssertTrue(configuration.configurationError?.contains("SIMIGO_HOME") == true)
    }

    func testRunnerDoesNotCreateStateForInvalidConfiguration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qoder-invalid-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = QoderCollectionConfiguration.standard(
            env: ["QODER_PROJECTS_DIR": ""], homeDirectory: root)
        let runner = QoderCollectionRunner(configuration: configuration)
        runner.start()
        defer { runner.stop() }

        XCTAssertFalse(runner.isRunning)
        XCTAssertTrue(runner.unavailableReason?.contains("QODER_PROJECTS_DIR") == true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: configuration.stateDirectory.path),
            "invalid configuration must fail before creating collector state")
    }
}
