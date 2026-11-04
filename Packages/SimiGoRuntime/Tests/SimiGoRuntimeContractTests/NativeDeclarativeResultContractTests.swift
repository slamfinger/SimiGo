import Foundation
import XCTest
@testable import SimiGoRuntimeContract

final class DeclarativeNativeResultContractTests: XCTestCase {
    private func contract(_ text: String) throws -> NativeResultContract {
        try NativeResultContract.decodeStrict(from: Data(text.utf8))
    }

    private let routeContract = #"""
    {
      "schema_version":"simigo.result-contract/v1",
      "fields":{
        "origin_code":{"pattern":"^ORIGIN=([A-Z]+)$","capture_group":1,"type":"string","required":true,"match_policy":"exactly_one"},
        "destination_code":{"pattern":"^DEST=([A-Z]+)$","capture_group":1,"type":"string","required":true,"match_policy":"exactly_one"},
        "route_key":{"pattern":"^ROUTE=([A-Z]+>[A-Z]+)$","capture_group":1,"type":"string","required":true,"match_policy":"exactly_one"},
        "priority":{"pattern":"^PRIORITY=([0-9]+)$","capture_group":1,"type":"integer","minimum":0,"maximum":9,"required":true,"match_policy":"exactly_one"}
      },
      "constraints":[
        {"kind":"equals_binding","field":"origin_code","binding":"origin_code"},
        {"kind":"equals_binding","field":"destination_code","binding":"destination_code"},
        {"kind":"equals_binding","field":"priority","binding":"priority"},
        {"kind":"concat","field":"route_key","parts":["origin_code","destination_code"],"separator":">"}
      ]
    }
    """#

    func testValidDeclaredFieldsBindingsAndDerivedRoute() throws {
        let c = try contract(routeContract)
        let trace = try NativeDeclarativeResultContractValidator.validate(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5",
            contract: c,
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(5)]
        )
        XCTAssertEqual(trace.validationStatus, "VALID")
        XCTAssertEqual(trace.values["route_key"], .string("NORTH>EAST"))
        XCTAssertEqual(trace.values["priority"], .integer(5))
        XCTAssertEqual(trace.constraintChecks.count, 4)
        XCTAssertTrue(trace.constraintChecks.allSatisfy(\.passed))
    }

    func testValidationIsIndependentOfRuntimeTaskID() throws {
        let c = try contract(routeContract)
        let text = "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5"
        let bindings: [String: NativeContractValue] = ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(5)]
        // Runtime IDs are intentionally not inputs to the validator.
        let ids = ["J-\(UUID().uuidString)-U1", "J-\(UUID().uuidString)-U1"]
        XCTAssertNotEqual(ids[0], ids[1])
        let a = try NativeDeclarativeResultContractValidator.validate(generatedText: text, contract: c, verifiedBindings: bindings)
        let b = try NativeDeclarativeResultContractValidator.validate(generatedText: text, contract: c, verifiedBindings: bindings)
        XCTAssertEqual(a.values, b.values)
        XCTAssertEqual(a.constraintChecks, b.constraintChecks)
    }

    func testMissingRequiredFieldFailsClosed() throws {
        let c = try contract(routeContract)
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST",
            contract: c,
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(5)]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "PRODUCER_RESULT_FIELD_MISSING")
            XCTAssertEqual((error as? NativeResultContractError)?.field, "priority")
        }
    }

    func testBindingMismatchFailsClosed() throws {
        let c = try contract(routeContract)
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5",
            contract: c,
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(7)]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "PRODUCER_RESULT_BINDING_MISMATCH")
            XCTAssertEqual((error as? NativeResultContractError)?.field, "priority")
        }
    }

    func testDerivedFieldMismatchFailsClosed() throws {
        let c = try contract(routeContract)
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>WEST\nPRIORITY=5",
            contract: c,
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(5)]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "PRODUCER_RESULT_DERIVATION_MISMATCH")
            XCTAssertEqual((error as? NativeResultContractError)?.field, "route_key")
        }
    }

    func testUnknownSchemaVersionFailsClosed() throws {
        let json = routeContract.replacingOccurrences(of: "simigo.result-contract/v1", with: "simigo.result-contract/v99")
        XCTAssertThrowsError(try NativeResultContract.decodeStrict(from: Data(json.utf8))) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_UNKNOWN_SCHEMA_VERSION")
        }
    }

    func testUnknownKeysFailClosed() throws {
        let json = routeContract.replacingOccurrences(of: #""schema_version":"simigo.result-contract/v1""#, with: #""schema_version":"simigo.result-contract/v1","fallback_by_item_id":true"#)
        XCTAssertThrowsError(try NativeResultContract.decodeStrict(from: Data(json.utf8))) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_UNKNOWN_KEY")
        }
    }

    func testAmbiguousRequiredFieldFailsExactlyOnePolicy() throws {
        let c = try contract(routeContract)
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5\nPRIORITY=6",
            contract: c,
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(5)]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_AMBIGUOUS_FIELD")
            XCTAssertEqual((error as? NativeResultContractError)?.field, "priority")
        }
    }

    func testFirstPolicyKeepsFirstMatch() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"route":{"pattern":"^ROUTE=(.+)$","capture_group":1,"type":"string","match_policy":"first"}}}"#
        let c = try contract(json)
        let trace = try NativeDeclarativeResultContractValidator.validate(generatedText: "ROUTE=A>B\nROUTE=C>D", contract: c, verifiedBindings: [:])
        XCTAssertEqual(trace.values["route"], .string("A>B"))
    }

    func testNamedCaptureGroupWorks() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"code":{"pattern":"^CODE=(?<value>[A-Z]{2})$","capture_group":"value","type":"string"}}}"#
        let c = try contract(json)
        let trace = try NativeDeclarativeResultContractValidator.validate(generatedText: "CODE=NE", contract: c, verifiedBindings: [:])
        XCTAssertEqual(trace.values["code"], .string("NE"))
    }

    func testEnumAndBooleanTypes() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"mode":{"pattern":"^MODE=(.+)$","type":"enum","values":["safe","fast"]},"enabled":{"pattern":"^ENABLED=(.+)$","type":"boolean"}}}"#
        let c = try contract(json)
        let trace = try NativeDeclarativeResultContractValidator.validate(generatedText: "MODE=safe\nENABLED=yes", contract: c, verifiedBindings: [:])
        XCTAssertEqual(trace.values["mode"], .string("safe"))
        XCTAssertEqual(trace.values["enabled"], .boolean(true))
    }

    func testOptionalFieldCanBeAbsent() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"code":{"pattern":"^CODE=(.+)$","type":"string"},"note":{"pattern":"^NOTE=(.+)$","type":"string","required":false}}}"#
        let c = try contract(json)
        let trace = try NativeDeclarativeResultContractValidator.validate(generatedText: "CODE=OK", contract: c, verifiedBindings: [:])
        XCTAssertEqual(trace.values["note"], .null)
        XCTAssertEqual(trace.fieldExtraction["note"]?.parsed, false)
    }


    func testMissingBindingFailsClosedWithProducerStage() throws {
        let c = try contract(routeContract)
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5",
            contract: c,
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST")]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_BINDING_MISSING")
            XCTAssertEqual((error as? NativeResultContractError)?.stage, "PRODUCER_RESULT_CONTRACT")
        }
    }

    func testEqualsFieldAndLiteralConstraints() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"code":{"pattern":"^CODE=(.+)$","type":"string"},"copy":{"pattern":"^COPY=(.+)$","type":"string"},"status":{"pattern":"^STATUS=(.+)$","type":"string"}},"constraints":[{"kind":"equals_field","field":"copy","other_field":"code"},{"kind":"equals_literal","field":"status","value":"READY"}]}"#
        let c = try contract(json)
        let trace = try NativeDeclarativeResultContractValidator.validate(generatedText: "CODE=A7\nCOPY=A7\nSTATUS=READY", contract: c, verifiedBindings: [:])
        XCTAssertEqual(trace.constraintChecks.count, 2)
        XCTAssertTrue(trace.constraintChecks.allSatisfy(\.passed))
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(generatedText: "CODE=A7\nCOPY=B8\nSTATUS=READY", contract: c, verifiedBindings: [:])) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "PRODUCER_RESULT_FIELD_MISMATCH")
        }
    }

    func testValidatedPayloadContainsOnlyNativeContractValues() throws {
        let data = Data(routeContract.utf8)
        let payload = try NativeProducerResultContractGate.validatedResultPayload(
            generatedText: "ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5",
            contractJSON: data,
            verifiedBindings: ["origin_code": .string("NORTH"), "destination_code": .string("EAST"), "priority": .integer(5)]
        )
        let decoded = try JSONDecoder().decode([String: NativeContractValue].self, from: payload)
        XCTAssertEqual(decoded["route_key"], .string("NORTH>EAST"))
        XCTAssertNil(decoded["unused_raw_completion"])
    }

    func testIntegerRangeFailsClosed() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"priority":{"pattern":"^PRIORITY=([0-9]+)$","type":"integer","minimum":0,"maximum":9}}}"#
        let c = try contract(json)
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(generatedText: "PRIORITY=12", contract: c, verifiedBindings: [:])) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_RANGE_VIOLATION")
        }
    }
    func testDigestEqualsBindingMatchesCanonicalStringDigest() throws {
        // Production/Python direction: the result field carries the RAW value and
        // the verified IS binding carries the committed canonical digest of it.
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let c = try contract(json)
        let trace = try NativeDeclarativeResultContractValidator.validate(
            generatedText: "SECRET=NORTH>EAST",
            contract: c,
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")]
        )
        XCTAssertEqual(trace.validationStatus, "VALID")
        XCTAssertTrue(trace.constraintChecks[0].passed)
        XCTAssertEqual(trace.constraintChecks[0].kind, "digest_equals_binding")
    }

    func testDigestCanonicalJSONMatchesPythonForNestedNonASCII() throws {
        // The digest input bytes for a nested, non-ASCII, unordered-key value must
        // match Python's json.dumps(ensure_ascii=False, sort_keys=True, compact).
        let nested: NativeContractValue = .object([
            "b": .string("é"),
            "a": .integer(1)
        ])
        let canonical = try nested.canonicalJSONData()
        XCTAssertEqual(String(data: canonical, encoding: .utf8), #"{"a":1,"b":"é"}"#)
        // And the SHA-256 over those bytes equals the vector Python's hashlib emits
        // for the same value (digest_equals_binding uses this convention).
        XCTAssertEqual(
            NativeSHA256.hexDigest(canonical),
            "09ad9fd2fb648cb2f62141215828ea00a62c299db05d20aa9ade2f527a301cc6")
    }

    func testDigestEqualsBindingMismatchFailsClosed() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        let c = try contract(json)
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(
            generatedText: "SECRET=NORTH>EAST",
            contract: c,
            verifiedBindings: ["secret_commitment": .string("0000000000000000000000000000000000000000000000000000000000000000")]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "PRODUCER_RESULT_DERIVATION_MISMATCH")
            XCTAssertEqual((error as? NativeResultContractError)?.stage, "PRODUCER_RESULT_CONTRACT")
        }
    }

    func testDigestEqualsBindingRequiresVerifiedBinding() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"payload_digest":{"pattern":"^DIGEST=([0-9a-f]{64})$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"payload_digest","binding":"payload"}]}"#
        let c = try contract(json)
        XCTAssertThrowsError(try NativeDeclarativeResultContractValidator.validate(
            generatedText: "DIGEST=2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8",
            contract: c,
            verifiedBindings: [:]
        )) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_BINDING_MISSING")
        }
    }

    func testUnknownConstraintStillFailsClosed() throws {
        let json = #"{"schema_version":"simigo.result-contract/v1","fields":{"code":{"pattern":"^CODE=(.+)$","type":"string"}},"constraints":[{"kind":"execute_shell","field":"code"}]}"#
        XCTAssertThrowsError(try contract(json)) { error in
            XCTAssertEqual((error as? NativeResultContractError)?.code, "CONTRACT_UNKNOWN_CONSTRAINT")
        }
    }

}
