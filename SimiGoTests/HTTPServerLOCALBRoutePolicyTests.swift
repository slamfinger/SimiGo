import XCTest
@testable import SimiGo

final class HTTPServerLOCALBRoutePolicyTests: XCTestCase {
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
