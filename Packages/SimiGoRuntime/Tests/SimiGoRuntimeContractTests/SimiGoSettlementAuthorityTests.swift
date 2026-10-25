import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// The settlement authority is the product's pre-settlement funnel. These tests
/// prove it is native-only and fail-closed: every rejection throws BEFORE any
/// `SettledResult` (and therefore before any write/sign) is produced.
final class SimiGoSettlementAuthorityTests: XCTestCase {

    private let routeContract = #"""
    {
      "schema_version":"simigo.result-contract/v1",
      "fields":{
        "origin_code":{"pattern":"^ORIGIN=([A-Z]+)$","capture_group":1,"type":"string"},
        "destination_code":{"pattern":"^DEST=([A-Z]+)$","capture_group":1,"type":"string"},
        "route_key":{"pattern":"^ROUTE=([A-Z]+>[A-Z]+)$","capture_group":1,"type":"string"},
        "priority":{"pattern":"^PRIORITY=([0-9]+)$","capture_group":1,"type":"integer","minimum":0,"maximum":9}
      },
      "constraints":[
        {"kind":"equals_binding","field":"origin_code","binding":"origin_code"},
        {"kind":"equals_binding","field":"destination_code","binding":"destination_code"},
        {"kind":"equals_binding","field":"priority","binding":"priority"},
        {"kind":"concat","field":"route_key","parts":["origin_code","destination_code"],"separator":">"}
      ]
    }
    """#

    func testAuthorizeProducesCanonicalValidatedSettlement() throws {
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5",
            contractJSON: Data(routeContract.utf8),
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(5)]
        )
        XCTAssertEqual(settled.trace.validationStatus, "VALID")
        XCTAssertEqual(settled.payloadDigest.count, 64)
        XCTAssertFalse(settled.payloadDigest.contains(where: { !"0123456789abcdef".contains($0) }))
        let decoded = try JSONDecoder().decode([String: NativeContractValue].self, from: settled.validatedPayload)
        XCTAssertEqual(decoded["route_key"], .string("NORTH>EAST"))
        XCTAssertNil(decoded["unused_raw_completion"], "raw model text must never enter the settled payload")
    }

    func testBindingMismatchRefusesBeforeSettlement() {
        XCTAssertThrowsError(try SimiGoSettlementAuthority.authorize(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5",
            contractJSON: Data(routeContract.utf8),
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(7)]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "PRODUCER_RESULT_BINDING_MISMATCH")
            XCTAssertEqual((error as? NativeResultContractError)?.stage, "PRODUCER_RESULT_CONTRACT")
        }
    }

    func testMissingBindingRefusesBeforeSettlement() {
        XCTAssertThrowsError(try SimiGoSettlementAuthority.authorize(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5",
            contractJSON: Data(routeContract.utf8),
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST")]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_BINDING_MISSING")
        }
    }

    /// Product-side counterfactual (analog of the Lab N2): `equals_binding_segment`
    /// is implemented by the Python gate but NOT by the native engine, so the
    /// native authority must refuse it fail-closed and produce no settlement.
    func testUnknownConstraintRefusesBeforeSettlement() {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"route_key":{"pattern":"^ROUTE=(.+)$","type":"string"}},"constraints":[{"kind":"equals_binding_segment","field":"route_key","binding":"d","separator":"-"}]}"#
        XCTAssertThrowsError(try SimiGoSettlementAuthority.authorize(
            generatedText: "ROUTE=NORTH>EAST",
            contractJSON: Data(json.utf8),
            verifiedBindings: ["d": .string("NORTH>EAST-suffix")]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_UNKNOWN_CONSTRAINT")
            XCTAssertEqual((error as? NativeResultContractError)?.stage, "PRODUCER_RESULT_CONTRACT")
        }
    }

    /// Production digest direction: field carries the RAW value, the verified IS
    /// binding carries the committed canonical SHA-256. Mismatch must refuse.
    func testDigestBindingAuthorizeAndRefuse() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let good = try SimiGoSettlementAuthority.authorize(
            generatedText: "SECRET=NORTH>EAST",
            contractJSON: Data(json.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")]
        )
        XCTAssertEqual(good.trace.validationStatus, "VALID")
        XCTAssertThrowsError(try SimiGoSettlementAuthority.authorize(
            generatedText: "SECRET=NORTH>EAST",
            contractJSON: Data(json.utf8),
            verifiedBindings: ["secret_commitment": .string(String(repeating: "0", count: 64))]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "PRODUCER_RESULT_DERIVATION_MISMATCH")
        }
    }
}
