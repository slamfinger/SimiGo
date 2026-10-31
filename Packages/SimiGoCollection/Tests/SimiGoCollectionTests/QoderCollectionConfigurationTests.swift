import XCTest
@testable import SimiGoCollection

final class QoderCollectionConfigurationTests: XCTestCase {
    func testStandardUsesIsolatedQoderProjectsOverride() {
        let home = URL(fileURLWithPath: "/tmp/qoder-config-test-home", isDirectory: true)
        let configuration = QoderCollectionConfiguration.standard(
            env: [
                "QODER_PROJECTS_DIR": "/tmp/qoder-config-test-scan",
                "SIMIGO_HOME": "/tmp/qoder-config-test-state",
            ],
            homeDirectory: home)

        XCTAssertEqual(configuration.scanRoot.path, "/tmp/qoder-config-test-scan")
        XCTAssertEqual(
            configuration.stateDirectory.path,
            "/tmp/qoder-config-test-state/collectors/qoder")
    }

    func testStandardFallsBackToQoderDefaultWhenOverrideIsEmpty() {
        let home = URL(fileURLWithPath: "/tmp/qoder-config-test-home", isDirectory: true)
        let configuration = QoderCollectionConfiguration.standard(
            env: ["QODER_PROJECTS_DIR": "", "SIMIGO_HOME": ""],
            homeDirectory: home)

        XCTAssertEqual(
            configuration.scanRoot.path,
            "/tmp/qoder-config-test-home/.qoder-cn/projects")
        XCTAssertEqual(
            configuration.stateDirectory.path,
            "/tmp/qoder-config-test-home/.simigo/collectors/qoder")
    }
}
