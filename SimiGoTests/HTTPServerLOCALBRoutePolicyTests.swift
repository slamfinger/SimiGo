import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

final class HTTPServerLOCALBRoutePolicyTests: XCTestCase {
    func testSimigoDatabaseDiagnosticsDistinguishMissingAndUnreadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-db-status-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingURL = directory.appendingPathComponent("missing.sqlite3")
        let missing = HTTPServer.simigoDatabaseStatus(at: missingURL)
        XCTAssertFalse(missing.exists)
        XCTAssertFalse(missing.available)
        XCTAssertNil(missing.error)

        let incompleteURL = directory.appendingPathComponent("incomplete.sqlite3")
        let incomplete = try ESISDatabase(url: incompleteURL, createIfNeeded: true)
        incomplete.close()
        let unreadable = HTTPServer.simigoDatabaseStatus(at: incompleteURL)
        XCTAssertTrue(unreadable.exists)
        XCTAssertFalse(unreadable.available)
        XCTAssertNotNil(unreadable.error)
        XCTAssertThrowsError(try HTTPServer.simigoRegisteredRoots(at: incompleteURL))
    }

    func testSimigoDatabaseDiagnosticsReturnsRegisteredRoots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-db-roots-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("simigo.sqlite3")

        let database = try ESISDatabase(url: databaseURL, createIfNeeded: true)
        try database.runMigrations()
        try database.upsertRoot(
            rootID: "work-test", category: "work",
            displayName: "/tmp/work-test", locatorType: "path", status: "registered")
        database.close()

        let status = HTTPServer.simigoDatabaseStatus(at: databaseURL)
        XCTAssertTrue(status.exists)
        XCTAssertTrue(status.available)
        XCTAssertNotNil(status.schemaVersion)
        XCTAssertEqual(status.roots, ["work-test"])
        XCTAssertNil(status.error)
        XCTAssertEqual(
            try HTTPServer.simigoRegisteredRoots(at: databaseURL).map(\.rootID),
            ["work-test"])
    }

    func testInformationReadRoutesRequireInformationReadPermission() {
        let routes = [
            ("GET", "/v1/simigo/env"),
            ("GET", "/v1/simigo/roots"),
            ("GET", "/v1/simigo/is/status"),
            ("GET", "/v1/models"),
            ("GET", "/models"),
            ("GET", "/v1/simigo/is/settlement"),
            ("GET", "/v1/simigo/is/dependency"),
            ("GET", "/v1/simigo/is/file"),
            ("GET", "/v1/simigo/is/object"),
        ]
        for (method, path) in routes {
            XCTAssertEqual(
                HTTPServer.localbRoutePolicy(forMethod: method, routePath: path),
                .protected(permission: .informationRead),
                "\(method) \(path) must require P-INFO-READ")
        }
    }

    func testSearchMutationAndRootMutationRequireSRSWritePermission() {
        let routes = [
            ("GET", "/v1/simigo/search"),
            ("POST", "/v1/simigo/search"),
            ("PUT", "/v1/simigo/roots"),
            ("POST", "/v1/simigo/roots"),
            ("POST", "/v1/simigo/is/reconcile"),
            ("POST", "/mcp"),
            ("GET", "/mcp"),
        ]
        for (method, path) in routes {
            XCTAssertEqual(
                HTTPServer.localbRoutePolicy(forMethod: method, routePath: path),
                .protected(permission: .srsWrite),
                "\(method) \(path) must require P-SRS-WRITE")
        }
    }

    func testOnlyHealthPreflightAndChallengeRemainOpen() {
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(forMethod: "OPTIONS", routePath: "/v1/simigo/roots"),
            .open)
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(forMethod: "GET", routePath: "/health"),
            .open)
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(forMethod: "HEAD", routePath: "/health"),
            .open)
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(forMethod: "POST", routePath: "/localb/auth/challenge"),
            .open)
        for (method, path) in [
            ("GET", "/v1/simigo/env"),
            ("GET", "/v1/simigo/roots"),
            ("GET", "/v1/simigo/is/status"),
            ("GET", "/v1/simigo/search"),
            ("POST", "/v1/simigo/search"),
            ("PUT", "/v1/simigo/roots"),
            ("POST", "/v1/simigo/roots"),
        ] {
            XCTAssertNotEqual(
                HTTPServer.localbRoutePolicy(forMethod: method, routePath: path),
                .open,
                "\(method) \(path) must not be open")
        }
    }

    func testPlaintextLoopbackCompatibilityKeepsExplicitPermissionsOnly() {
        let allowed = HTTPServer.localbPlaintextLoopbackPermissions
        XCTAssertTrue(allowed.contains(.inference))
        XCTAssertTrue(allowed.contains(.informationRead))
        XCTAssertTrue(allowed.contains(.srsWrite))
        XCTAssertFalse(allowed.contains(.branchControl))
    }

    func testUnknownRouteRemainsDenied() {
        XCTAssertEqual(
            HTTPServer.localbRoutePolicy(forMethod: "GET", routePath: "/v1/simigo/not-a-route"),
            .denied(reason: "LOCALB_ROUTE_UNKNOWN"))
    }
}
