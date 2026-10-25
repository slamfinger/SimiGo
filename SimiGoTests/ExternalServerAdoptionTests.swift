import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

/// requirement②: proves the external-server selection is FUNCTIONAL at the app
/// layer — `EnvManager.applyExternalAdoption` wires the resolved OpenAI-compatible
/// endpoint into the live `Service` (reusing the existing `.cloud` remote runtime),
/// and stays fail-closed (Service untouched) for non-adoptable engines.
///
/// The three `Service` fields involved persist to `AppConfig` via `didSet`, so we
/// snapshot and restore them to keep the run hermetic (never leak into the user's
/// real app configuration).
@MainActor
final class ExternalServerAdoptionTests: XCTestCase {

    private var snapshot: (selection: String?, baseURL: String?, model: String?)

    override func setUp() {
        super.setUp()
        snapshot = (
            AppConfig.get(.backendSelection),
            AppConfig.get(.cloudBaseURL),
            AppConfig.get(.cloudModel)
        )
    }

    override func tearDown() {
        AppConfig.set(snapshot.selection, for: .backendSelection)
        AppConfig.set(snapshot.baseURL, for: .cloudBaseURL)
        AppConfig.set(snapshot.model, for: .cloudModel)
        super.tearDown()
    }

    func testAdoptingOllamaWiresServiceToResolvedEndpoint() throws {
        let envMgr = EnvManager.shared
        let service = Service()

        // The engine must resolve a concrete bundled endpoint, else there is
        // nothing to wire (this precondition is also covered by the package tests).
        guard let ep = envMgr.adoptedEndpoint(for: "ollama") else {
            return XCTFail("ollama must resolve a bundled OpenAI-compatible endpoint")
        }

        let applied = envMgr.applyExternalAdoption(of: "ollama", to: service)
        XCTAssertEqual(applied?.baseURL, ep.baseURL, "adopted == resolved (single source of truth)")
        XCTAssertEqual(service.backendSelection, .cloud, "adopting an external server switches to the remote runtime")
        XCTAssertEqual(service.cloudBaseURL, ep.baseURL, "the resolved endpoint is written into the runtime")
        XCTAssertEqual(service.cloudModel, ep.defaultModel, "the server's default model is applied")
    }

    func testAdoptingEndpointlessOrNonExternalLeavesServiceUntouched() {
        let envMgr = EnvManager.shared
        let service = Service()
        let selectionBefore = service.backendSelection
        let urlBefore = service.cloudBaseURL

        // source-build (llama.cpp), native runtime (mlx-native), and an external
        // server with no declared endpoint (slang) must ALL fail-closed and return nil.
        for id in ["llama.cpp", "mlx-native", "slang"] {
            XCTAssertNil(envMgr.applyExternalAdoption(of: id, to: service),
                         "\(id) must not be adopted over an endpoint")
        }
        XCTAssertEqual(service.backendSelection, selectionBefore, "fail-closed leaves the backend selection unchanged")
        XCTAssertEqual(service.cloudBaseURL, urlBefore, "fail-closed leaves the base URL unchanged")
    }

    func testUnknownEngineIDIsFailClosed() {
        let envMgr = EnvManager.shared
        let service = Service()
        XCTAssertNil(envMgr.applyExternalAdoption(of: "does-not-exist", to: service))
    }
}
