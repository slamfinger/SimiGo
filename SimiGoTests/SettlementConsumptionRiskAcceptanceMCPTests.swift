import Foundation
import XCTest

@testable import SimiGo

final class SettlementConsumptionRiskAcceptanceMCPTests: XCTestCase {

    func testConsumeToolAdvertisesOptionalFreshnessRiskAcceptance() throws {
        let definition = try XCTUnwrap(
            HTTPServer.mcpToolDefinitions.first {
                $0["name"] as? String == "simigo_es_consume"
            })
        let schema = try XCTUnwrap(definition["inputSchema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let field = try XCTUnwrap(
            properties["accept_invalidated_dependency"] as? [String: Any])

        XCTAssertEqual(field["type"] as? String, "boolean")
        let required = schema["required"] as? [String] ?? []
        XCTAssertFalse(
            required.contains("accept_invalidated_dependency"),
            "risk acceptance is an explicit optional choice; omission must retain fail-closed default")
    }

    func testRiskAcceptanceParserRequiresAJSONBoolean() throws {
        XCTAssertNil(try HTTPServer.strictOptionalBoolean([:], "accept_invalidated_dependency"))
        XCTAssertEqual(
            try HTTPServer.strictOptionalBoolean(
                ["accept_invalidated_dependency": true],
                "accept_invalidated_dependency"),
            true)

        XCTAssertThrowsError(
            try HTTPServer.strictOptionalBoolean(
                ["accept_invalidated_dependency": NSNumber(value: 1)],
                "accept_invalidated_dependency"),
            "numeric 1 must not be accepted as a boolean")

        XCTAssertThrowsError(
            try HTTPServer.strictOptionalBoolean(
                ["accept_invalidated_dependency": "true"],
                "accept_invalidated_dependency"),
            "string booleans must be refused")
    }
}
