import Crypto
import XCTest

@testable import SimiGo2Experimental

final class PersistentSRSRepresentationTests: XCTestCase {
    // MARK: - Helpers

    private func makeBinding(_ name: String) -> SRSBindingValue {
        SRSBindingValue(
            identity: name,
            version: "1.0.0",
            contentDigestHex64: String(repeating: "a", count: 64)
        )
    }

    private func makeRecord(identity: String = "rel-a", version: String = "1.0.0") -> PersistentSRSRecord {
        var r = PersistentSRSRecord()
        r.logicalKeyIdentity = identity
        r.logicalKeyVersion = version
        r.settledBinding = makeBinding("settled")
        r.settlementID = "settle-001"
        r.settlementStatus = .declaredSettled
        r.sourceRelationIdentity = "src-rel"
        r.resultIdentity = "result-rel"
        r.requiresCanonicalIdentityRule = true
        r.canonicalIdentityRule = makeBinding("cir")
        r.settledProvenanceBindings = [makeBinding("sp2"), makeBinding("sp1")]
        r.sourceBinding = makeBinding("src")
        r.sourceSemanticBinding = nil
        r.sourceApplicabilityCoverage = nil
        r.sourceInvalidationRecord = nil
        r.sourceInvalidationStatus = .none
        r.sourceIdentityRule = nil
        r.sourceStatus = .current
        r.dependencyBoundary = makeBinding("depb")
        r.dependencies = [
            SRSDependency(binding: makeBinding("d1"), role: "role-1", necessity: "hard",
                          resolution: .resolved, status: .current),
            SRSDependency(binding: nil, role: "role-2", necessity: "soft",
                          resolution: .unresolved, status: .superseded),
        ]
        r.resultBinding = makeBinding("res")
        r.resultResolution = .resolvedWithoutRecompute
        r.interpretabilityEvidence = nil
        r.resultStatus = .current
        r.provenanceBindings = [makeBinding("p2"), makeBinding("p1"), makeBinding("p2")]
        r.provenanceLifecycle = .declaredSettled
        r.provenanceBoundary = nil
        r.lifecycleBindings = [makeBinding("l1")]
        r.lifecycleStatus = .declaredSettled
        r.lifecycleBoundary = makeBinding("lb")
        r.freshnessBoundary = nil
        r.freshnessRequirements = [
            SRSFreshnessRequirement(
                identity: "fresh-1", evidence: makeBinding("fe"),
                expectedEvidenceDigestHex64: String(repeating: "b", count: 64),
                status: .current, validUntilUTC: "2026-12-31T23:59:59Z",
                observedAtUTC: "2026-10-11T00:00:00Z"
            ),
        ]
        r.resolutionRule = nil
        r.policies = [makeBinding("pol")]
        r.policyBoundary = nil
        r.producerAuthorizationReference = "producer-ref-001"
        return r
    }

    private func makeTempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("psrs-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func buildFrame(record: PersistentSRSRecord, key: Curve25519.Signing.PrivateKey, payloadOverride: [UInt8]? = nil) -> [UInt8] {
        let payload = payloadOverride ?? SRSCanonical.payloadBytes(record)
        let payloadDigest = SRSCanonical.payloadDigest(payload)
        let signature = SRSSignature.sign(payload: payload, with: key)
        let envelope = SRSEnvelope(
            logicalKeyIdentity: record.logicalKeyIdentity,
            logicalKeyVersion: record.logicalKeyVersion,
            payloadDigestHex: SRSCanonical.payloadDigestHex(payloadDigest),
            signerPublicKeyRaw: SRSSignature.signerPublicKeyRaw,
            signatureRaw: signature,
            producerAuthorizationReference: record.producerAuthorizationReference,
            decisionCoreSourceCommit: SRSEncodingConstants.decisionCoreSourceCommit,
            decisionCoreSourceSHA256Hex: SRSEncodingConstants.decisionCoreSourceSHA256
        )
        let envelopeBytes = SRSEnvelope.encode(envelope)
        let envelopeDigest = SRSEnvelope.envelopeDigest(canonicalEnvelopeBytes: envelopeBytes)
        return SRSFrame.encode(SRSFrame(
            payloadBytes: payload,
            envelopeBytes: envelopeBytes,
            payloadDigestRaw: payloadDigest,
            envelopeDigestRaw: envelopeDigest
        ))
    }

    /// Produce a payload with the first two top-level JSON members swapped:
    /// schema-valid, parseable, but not RFC 8785 canonical (R21 negative).
    private func reorderTopLevelMembers(_ payload: [UInt8]) -> [UInt8] {
        var depth = 0
        var inString = false
        var commas: [Int] = []
        // Scan from the opening brace so depth 1 denotes top-level members.
        var i = 0
        while i < payload.count {
            let b = payload[i]
            if inString {
                if b == 0x5C { i += 1 } else if b == 0x22 { inString = false }
            } else {
                switch b {
                case 0x22: inString = true
                case 0x7B, 0x5B: depth += 1
                case 0x7D, 0x5D: depth -= 1
                case 0x2C: if depth == 1 { commas.append(i) }
                default: break
                }
            }
            i += 1
        }
        guard commas.count >= 2 else { return payload }
        let m1 = Array(payload[1..<commas[0]])
        let m2 = Array(payload[commas[0] + 1..<commas[1]])
        let rest = Array(payload[commas[1]...])
        return Array(payload[0...0]) + m2 + [0x2C] + m1 + rest
    }

    private func attemptVectorInput() -> SRSAttemptEvidenceInput {
        SRSAttemptEvidenceInput(
            attemptID: "ATTEMPT-0001",
            matrixScenario: "V-PERSIST-20",
            batchIdentity: "EXECUTION_BATCH_01",
            humanAuthorizationRecord: "HAR-PERSIST-TEST-001",
            fixtureDigest: String(repeating: "0", count: 128),
            completedAtUTC: "2026-10-11T00:00:00Z",
            operationOutcome: "VALID_CREATE_PASS",
            scenarioVerdict: "PASS",
            runtimeBindingsJSON: .object([
                ("environment_identity", .string("TEST-ENV")),
                ("implementation_artifact_sha256", .string(String(repeating: "0", count: 64))),
                ("runtime_artifact_identity", .string("TEST-RUNTIME")),
            ]),
            observerAuthorizationReference: nil,
            startStopEvidenceJSON: .object([
                ("started_at_utc", .string("2026-10-11T00:00:00Z")),
                ("stopped_at_utc", .string("2026-10-11T00:00:01Z")),
            ]),
            outputTypedFailureEvidenceJSON: nil
        )
    }

    // MARK: - Canonical encoding and round trip

    func testValidI0EncodingAndCanonicalRoundTrip() throws {
        let record = makeRecord()
        let i1 = SRSCanonical.payloadBytes(record)
        XCTAssertFalse(i1.isEmpty)
        let parsed = try SRSStrictJSONParser.parse(i1).get()
        let decoded = try PersistentSRSRecord.decode(parsed)
        // Decoded unordered collections are in canonical sorted order; I0
        // semantic equality is canonical-byte equality, not Swift field order.
        XCTAssertEqual(SRSCanonical.payloadBytes(decoded), i1)
    }

    func testJCSReorderedCollectionsProduceSameBytes() {
        var a = makeRecord()
        var b = a
        b.provenanceBindings = [makeBinding("p1"), makeBinding("p2"), makeBinding("p2")]
        XCTAssertEqual(SRSCanonical.payloadBytes(a), SRSCanonical.payloadBytes(b))
    }

    func testNilVersusExplicitEmptyAreDistinct() throws {
        var a = makeRecord()
        a.provenanceBindings = nil
        var b = a
        b.provenanceBindings = []
        XCTAssertNotEqual(SRSCanonical.payloadBytes(a), SRSCanonical.payloadBytes(b))
        let decodedA = try PersistentSRSRecord.decode(try SRSStrictJSONParser.parse(SRSCanonical.payloadBytes(a)).get())
        let decodedB = try PersistentSRSRecord.decode(try SRSStrictJSONParser.parse(SRSCanonical.payloadBytes(b)).get())
        XCTAssertNil(decodedA.provenanceBindings)
        XCTAssertEqual(decodedB.provenanceBindings, [])
    }

    // MARK: - R5: closed nested schema (R17 vs R19 stage distinction)

    func testNestedUnknownMemberFailsAtR17() throws {
        let record = makeRecord()
        var json = record.canonicalJSONValue()
        guard case .object(var members) = json,
              let idx = members.firstIndex(where: { $0.0 == "provenance" }),
              case .object(var provMembers) = members[idx].1 else {
            return XCTFail("structure")
        }
        provMembers.append(("totally_unknown", .string("x")))
        members[idx].1 = .object(provMembers)
        json = .object(members)
        do {
            _ = try PersistentSRSRecord.decode(json)
            XCTFail("expected unknown nested member rejection")
        } catch let e as SRSDecodeError {
            guard case .fail(.unknownSchemaOrField) = e else {
                return XCTFail("expected R17 UNKNOWN_SCHEMA_OR_FIELD")
            }
        }
    }

    func testEnumViolationFailsAtR19() throws {
        let record = makeRecord()
        var json = record.canonicalJSONValue()
        guard case .object(var members) = json,
              let idx = members.firstIndex(where: { $0.0 == "provenance" }),
              case .object(var provMembers) = members[idx].1,
              let lifeIdx = provMembers.firstIndex(where: { $0.0 == "lifecycle" }) else {
            return XCTFail("structure")
        }
        provMembers[lifeIdx].1 = .string("bogus_lifecycle")
        members[idx].1 = .object(provMembers)
        json = .object(members)
        do {
            _ = try PersistentSRSRecord.decode(json)
            XCTFail("expected enum violation rejection")
        } catch let e as SRSDecodeError {
            guard case .fail(.schemaValidationFailed) = e else {
                return XCTFail("expected R19 SCHEMA_VALIDATION_FAILED")
            }
        }
    }

    func testPayloadCoreBindingConstFailsAtR19() throws {
        let record = makeRecord()
        var json = record.canonicalJSONValue()
        guard case .object(var members) = json,
              let idx = members.firstIndex(where: { $0.0 == "decision_core_binding" }),
              case .object(var coreMembers) = members[idx].1,
              let commitIdx = coreMembers.firstIndex(where: { $0.0 == "source_commit" }) else {
            return XCTFail("structure")
        }
        coreMembers[commitIdx].1 = .string("deadbeef")
        members[idx].1 = .object(coreMembers)
        json = .object(members)
        do {
            _ = try PersistentSRSRecord.decode(json)
            XCTFail("expected const violation rejection at R19")
        } catch let e as SRSDecodeError {
            guard case .fail(.schemaValidationFailed) = e else {
                return XCTFail("expected R19 SCHEMA_VALIDATION_FAILED")
            }
        }
    }

    // MARK: - Strict UTC parser

    func testStrictUTCAcceptanceAndRejection() {
        XCTAssertTrue(SRSStrictUTC.isValid("2026-10-11T00:00:00Z"))
        XCTAssertTrue(SRSStrictUTC.isValid("2024-02-29T23:59:59.123456789Z"))
        XCTAssertTrue(SRSStrictUTC.isValid("0001-01-01T00:00:00Z"))
        XCTAssertFalse(SRSStrictUTC.isValid("2026-02-30T00:00:00Z"))
        XCTAssertFalse(SRSStrictUTC.isValid("2023-02-29T00:00:00Z"))
        XCTAssertFalse(SRSStrictUTC.isValid("2026-10-11T24:00:00Z"))
        XCTAssertFalse(SRSStrictUTC.isValid("2026-10-11T00:00:60Z"))
        XCTAssertFalse(SRSStrictUTC.isValid("2026-10-11T00:00:00+00:00"))
        XCTAssertFalse(SRSStrictUTC.isValid("2026-10-11 00:00:00Z"))
        XCTAssertFalse(SRSStrictUTC.isValid("2026-10-11T00:00:00.Z"))
    }

    // MARK: - UTF-8 byte-exact logical-key comparison

    func testUTF8ByteExactLogicalKeyComparison() {
        let precomposed = "\u{e9}"
        let decomposed = "e\u{301}"
        XCTAssertNotEqual(
            persistentSRSUTF8Bytes(precomposed),
            persistentSRSUTF8Bytes(decomposed)
        )
        // The shared production classifier must treat them as distinct keys:
        // same proposed payload at a content path held by the other form is a
        // content-identity mismatch, never an equivalent record.
        let existing = SRSClassificationDescriptor(
            identityUtf8: persistentSRSUTF8Bytes(precomposed), versionUtf8: [UInt8(ascii: "1")],
            payloadDigestBytes: Array(repeating: 0x11, count: 32), canonicalPayloadI1Bytes: [0x7B, 0x7D])
        let proposed = SRSClassificationDescriptor(
            identityUtf8: persistentSRSUTF8Bytes(decomposed), versionUtf8: [UInt8(ascii: "1")],
            payloadDigestBytes: Array(repeating: 0x11, count: 32), canonicalPayloadI1Bytes: [0x7B, 0x7D])
        let classification = SRSWriteClassifier.classify(existingDescriptor: existing, proposedDescriptor: proposed)
        XCTAssertEqual(classification, .recordContentIdentityMismatch)
    }

    // MARK: - Shared classifier collision branches (PR-A41)

    func testContentAddressedCollisionClassification() {
        func descriptor(_ id: String, digest: [UInt8], i1: [UInt8]) -> SRSClassificationDescriptor {
            SRSClassificationDescriptor(
                identityUtf8: persistentSRSUTF8Bytes(id), versionUtf8: persistentSRSUTF8Bytes("1"),
                payloadDigestBytes: digest, canonicalPayloadI1Bytes: i1)
        }
        let key = descriptor("k", digest: Array(repeating: 0x22, count: 32), i1: [0x7B, 0x7D])
        let otherKey = descriptor("other", digest: Array(repeating: 0x22, count: 32), i1: [0x7B, 0x7D])
        let payloadA: [UInt8] = [0x7B, 0x7D]
        // No existing record at the proposed content path: NEW_RECORD.
        XCTAssertEqual(
            SRSWriteClassifier.classify(existingDescriptor: nil, proposedDescriptor: key),
            .newRecord
        )
        // Different logical key at the proposed content path: identity mismatch.
        XCTAssertEqual(
            SRSWriteClassifier.classify(existingDescriptor: otherKey, proposedDescriptor: key),
            .recordContentIdentityMismatch
        )
        // Same key, same I1 bytes: existing equivalent record.
        XCTAssertEqual(
            SRSWriteClassifier.classify(existingDescriptor: key, proposedDescriptor: key),
            .existingEquivalentRecord
        )
        // Same ordered key, same payload digest, different I1 bytes (synthetic
        // SHA-256 collision descriptor from the test-only constructor):
        // PERSISTENT_LOGICAL_KEY_CONFLICT, final and non-retriable.
        XCTAssertEqual(
            SRSWriteClassifier.classify(
                existingDescriptor: descriptor("k", digest: key.payloadDigestBytes, i1: [0x20, 0x7D]),
                proposedDescriptor: key),
            .persistentLogicalKeyConflict
        )
    }

    // MARK: - Reader failure statuses (exact registry, no aliases)

    func testReaderFailureStatuses() throws {
        let root = makeTempRoot()
        let recordsDir = root.appendingPathComponent("records", isDirectory: true)
        try FileManager.default.createDirectory(at: recordsDir, withIntermediateDirectories: true)
        let key = Curve25519.Signing.PrivateKey()
        let record = makeRecord()
        let frame = buildFrame(record: record, key: key)
        let path = recordsDir.appendingPathComponent("candidate.psrs")

        func expectStatus(_ data: [UInt8], _ status: PersistentSRSStatus, file: StaticString = #filePath, line: UInt = #line) {
            let result = SRSReader.read(data: data, path: path, authorizedRoot: root, performUniquenessScan: true)
            guard case .failure(let s) = result else {
                return XCTFail("expected failure \(status.rawValue)", file: file, line: line)
            }
            XCTAssertEqual(s, status, file: file, line: line)
        }

        // R1: truncated below the 108-byte minimum.
        expectStatus(Array(frame.prefix(64)), .truncatedRecord)
        // R6: declared total exceeds the actual (short-frame) length.
        expectStatus(Array(frame.prefix(frame.count - 1)), .physicalLengthMismatch)
        // R8: trailing data after MAGIC_END.
        expectStatus(frame + [0x00], .trailingDataAfterRecord)
        // R21: schema-valid but noncanonical top-level member order reaches the
        // canonical byte equality check and fails exactly there.
        let canonicalPayload = SRSCanonical.payloadBytes(record)
        let nonCanonicalPayload = reorderTopLevelMembers(canonicalPayload)
        XCTAssertNotEqual(nonCanonicalPayload, canonicalPayload)
        let nonCanonicalFrame = buildFrame(record: record, key: key, payloadOverride: nonCanonicalPayload)
        expectStatus(nonCanonicalFrame, .nonCanonicalPayloadBytes)
        // R25: exact byte-valid frame signed by a non-production key must fail
        // signature verification against the unique production anchor.
        expectStatus(frame, .signatureVerificationFailed)
    }

    // MARK: - Attempt evidence: frozen fixed encoding vector

    func testFixedEncodingVector() throws {
        let built = try SRSAttemptEvidence.build(attemptVectorInput()).get()
        XCTAssertEqual(
            SRSCanonical.payloadDigestHex(Array(SHA256.hash(data: Data(built.coreCanonicalData)))),
            "92ed449b764e791395354cd2708d13e66199df46297182b7508c138c6a2cbe19"
        )
        XCTAssertEqual(built.baseEvidenceDigestHex, "5311214a709efd1ba72823da71238796cb45ecbd93d7ef3ee8f6ca3ef372258f")
        XCTAssertEqual(
            SRSCanonical.payloadDigestHex(Array(SHA256.hash(data: Data(built.completionOrderKeyValue)))),
            "17a53a9c8c0fee81fbfe38ec9714e2de988af245d1e931c6ef2ea56582bcf6ce"
        )
        XCTAssertEqual(
            SRSCanonical.payloadDigestHex(Array(SHA256.hash(data: Data(built.sealedCanonicalData)))),
            "6188e6fa6bac44ef85ddac9181818516466116f499768ca2d70b7937780882e1"
        )
        XCTAssertEqual(
            SRSCanonical.payloadDigestHex(built.evidenceDigest),
            "9dc1891f6961852660524e1a23f681745ab05c08272c6391ddc0ef6873e61615"
        )
        // V1-V5 verification accepts the exact sealed evidence.
        guard case .success = SRSAttemptEvidence.verify(
            sealed: built.sealedCanonicalData, claimedEvidenceDigest: built.evidenceDigest
        ) else {
            return XCTFail("expected V1-V5 verification to succeed for the fixed vector")
        }
        // Any sealed byte mutation breaks the digest chain.
        var tampered = built.sealedCanonicalData
        tampered[tampered.count - 1] ^= 0xFF
        guard case .failure(let tamperStatus) = SRSAttemptEvidence.verify(sealed: tampered, claimedEvidenceDigest: built.evidenceDigest) else {
            return XCTFail("expected tamper failure")
        }
        // The trailing byte lies inside the completion-order-key value, so the
        // V1→V5 order must fail at exactly V3 with the typed status
        // INVALID_COMPLETION_ORDER_KEY, before the V5 digest comparison.
        XCTAssertEqual(tamperStatus, .invalidCompletionOrderKey)
    }

    func testBaseDigestIndependenceFromCompletionOrderKey() throws {
        let plain = try SRSAttemptEvidence.build(attemptVectorInput(), fractionalDigits: "").get()
        let withFraction = try SRSAttemptEvidence.build(attemptVectorInput(), fractionalDigits: "999").get()
        // The base digest is derived only from the 12 core fields.
        XCTAssertEqual(plain.baseEvidenceDigest, withFraction.baseEvidenceDigest)
        // The order key itself differs with the exact supplied digits.
        XCTAssertNotEqual(plain.completionOrderKeyValue, withFraction.completionOrderKeyValue)
        // The sealed evidence digest binds core, base, and order key together.
        XCTAssertNotEqual(plain.evidenceDigest, withFraction.evidenceDigest)
    }

    func testSealedEvidenceDigestBinding() throws {
        let baseline = try SRSAttemptEvidence.build(attemptVectorInput()).get()
        var mutatedInput = attemptVectorInput()
        mutatedInput.attemptID = "ATTEMPT-0002"
        let mutated = try SRSAttemptEvidence.build(mutatedInput).get()
        XCTAssertNotEqual(mutated.evidenceDigest, baseline.evidenceDigest)
        XCTAssertNotEqual(mutated.baseEvidenceDigest, baseline.baseEvidenceDigest)
        // Verification of the original sealed bytes against the mutated digest
        // fails closed.
        if case .success = SRSAttemptEvidence.verify(
            sealed: baseline.sealedCanonicalData, claimedEvidenceDigest: mutated.evidenceDigest
        ) {
            return XCTFail("original sealed evidence must not verify against the mutated digest")
        }
    }

    // MARK: - Append-only attempt status and current projection

    func testAppendOnlyAttemptStatusAndProjection() {
        var events: [SRSAttemptStatusEvent] = []
        events.append(SRSAttemptStatusEvent(eventID: "e1", attemptID: "A", eventType: .executed, priorEventID: nil))
        XCTAssertEqual(srsCurrentAttemptProjection(events: events, attemptID: "A"), .executedActive)
        // Append-only: later events override, earlier events are never rewritten.
        events.append(SRSAttemptStatusEvent(eventID: "e2", attemptID: "A", eventType: .excludedByAuthorizedSupersession, priorEventID: "e1"))
        XCTAssertEqual(srsCurrentAttemptProjection(events: events, attemptID: "A"), .excluded)
        XCTAssertEqual(events[0].eventType, .executed)
        XCTAssertEqual(events[1].priorEventID, "e1")
        events.append(SRSAttemptStatusEvent(eventID: "e3", attemptID: "B", eventType: .failed, priorEventID: nil))
        XCTAssertEqual(srsCurrentAttemptProjection(events: events, attemptID: "B"), .failed)
        XCTAssertNil(srsCurrentAttemptProjection(events: events, attemptID: "missing"))
        // R6: a broken prior_event_id append chain yields no valid projection.
        events.append(SRSAttemptStatusEvent(eventID: "e5", attemptID: "C", eventType: .executed, priorEventID: nil))
        events.append(SRSAttemptStatusEvent(eventID: "e6", attemptID: "C", eventType: .failed, priorEventID: "WRONG"))
        XCTAssertNil(srsCurrentAttemptProjection(events: events, attemptID: "C"))
    }

    // MARK: - Batch budget and transitions

    func testBatchBudgetAndTransitions() {
        XCTAssertTrue(srsBatchBudgetAllows(executedAttemptCount: 16))
        XCTAssertFalse(srsBatchBudgetAllows(executedAttemptCount: 17))
        XCTAssertFalse(srsBatchBudgetAllows(executedAttemptCount: -1))
        XCTAssertTrue(srsBatchTransitionAllowed(from: .active, to: .complete))
        XCTAssertTrue(srsBatchTransitionAllowed(from: .active, to: .superseded))
        XCTAssertTrue(srsBatchTransitionAllowed(from: .complete, to: .superseded))
        XCTAssertTrue(srsBatchTransitionAllowed(from: .active, to: .failedClosed))
        // FAILED_CLOSED is terminal.
        XCTAssertFalse(srsBatchTransitionAllowed(from: .failedClosed, to: .active))
        XCTAssertFalse(srsBatchTransitionAllowed(from: .failedClosed, to: .complete))
        XCTAssertFalse(srsBatchTransitionAllowed(from: .failedClosed, to: .superseded))
        XCTAssertFalse(srsBatchTransitionAllowed(from: .complete, to: .active))
        XCTAssertFalse(srsBatchTransitionAllowed(from: .complete, to: .failedClosed))
    }

    // MARK: - R1: sealed field label/type matrix (table-driven)

    func testSealedFieldTypeMatrix() throws {
        let built = try SRSAttemptEvidence.build(attemptVectorInput()).get()
        let sealed = built.sealedCanonicalData
        let magicLen = Array("SIMISRS-ASEALED-V1".utf8).count
        // Parse each field's label and type from the encoded bytes.
        var fields: [(label: String, type: UInt8)] = []
        var pos = magicLen + 4
        while pos < sealed.count {
            let labelLen = Int(sealed[pos]) << 8 | Int(sealed[pos + 1])
            pos += 2
            let label = String(bytes: sealed[pos..<pos + labelLen], encoding: .utf8)!
            pos += labelLen
            let type = sealed[pos]
            pos += 1
            var valueLen: UInt64 = 0
            for _ in 0..<8 { valueLen = valueLen << 8 | UInt64(sealed[pos]); pos += 1 }
            pos += Int(valueLen)
            fields.append((label, type))
        }
        XCTAssertEqual(fields.count, 14)
        // Every encoded type must equal the frozen label/type table entry.
        for (i, field) in fields.enumerated() {
            XCTAssertEqual(field.label, SRSAttemptEvidence.allFieldLabels[i])
            XCTAssertTrue(
                SRSAttemptEvidence.allowedFieldTypes[i].contains(field.type),
                "field \(field.label) type \(field.type) not allowed"
            )
        }
    }

    // MARK: - R3: invalid signing key has zero filesystem side effects

    func testInvalidSigningKeyHasZeroSideEffects() throws {
        let root = makeTempRoot()
        let record = makeRecord()
        let wrongKey = Curve25519.Signing.PrivateKey()
        let result = SRSWriter.write(record: record, signingKey: wrongKey, root: root)
        XCTAssertEqual(result, .failure(.signatureVerificationFailed))
        // Zero side effects: the root must not even exist.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("staging").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".writer.lock").path))
    }

    // MARK: - R4: refresh failure handling

    func testRefreshFailureLeavesFailClosedState() throws {
        let root = makeTempRoot()
        let recordsDir = root.appendingPathComponent("records", isDirectory: true)
        try FileManager.default.createDirectory(at: recordsDir, withIntermediateDirectories: true)
        let target = recordsDir.appendingPathComponent("final.psrs")
        // W10 failure: no final record may exist.
        SRSRefreshFailureInjector.failFileFlush = true
        let fileFlush = SRSWriter.persist(frameBytes: [0x00], root: root,
                                          recordsDir: recordsDir, targetPath: target)
        SRSRefreshFailureInjector.failFileFlush = false
        guard case .failure(let fileFlushStatus) = fileFlush else {
            return XCTFail("expected file-flush failure")
        }
        XCTAssertEqual(fileFlushStatus, .persistenceVerificationIndeterminate)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        // W12 failure: the immutable final record must remain and the state is
        // reported indeterminate — never deleted, never denied.
        SRSRefreshFailureInjector.failDirFlush = true
        let dirFlush = SRSWriter.persist(frameBytes: [0x00], root: root,
                                         recordsDir: recordsDir, targetPath: target)
        SRSRefreshFailureInjector.failDirFlush = false
        guard case .failure(let dirFlushStatus) = dirFlush else {
            return XCTFail("expected dir-flush failure")
        }
        XCTAssertEqual(dirFlushStatus, .persistenceVerificationIndeterminate)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: - R27 envelope binding boundary (exact)

    func testR27EnvelopeBindingMutationBoundary() {
        // Frozen envelope values: R27 passes (nil status).
        XCTAssertNil(SRSReader.checkDecisionCoreBinding(
            envelopeCommit: SRSEncodingConstants.decisionCoreSourceCommit,
            envelopeSHA256: SRSEncodingConstants.decisionCoreSourceSHA256))
        // Each envelope field mutated separately fails at exactly R27.
        XCTAssertEqual(
            SRSReader.checkDecisionCoreBinding(
                envelopeCommit: "deadbeef",
                envelopeSHA256: SRSEncodingConstants.decisionCoreSourceSHA256),
            .decisionCoreBindingMismatch)
        XCTAssertEqual(
            SRSReader.checkDecisionCoreBinding(
                envelopeCommit: SRSEncodingConstants.decisionCoreSourceCommit,
                envelopeSHA256: "feedface"),
            .decisionCoreBindingMismatch)
    }

    // MARK: - Two-phase closure: selection, registration, chain

    func testClosureSelectionRegistrationAndChain() throws {
        let orderKeyA = Array("aaaa".utf8)
        let orderKeyB = Array("bbbb".utf8)
        let eligible = SRSCandidateEligibility(
            evidenceV1to5Pass: true, scenarioExecutionRequired: true, verdictPass: true,
            latestProjectionExecutedActive: true, sourceBatchActiveOrComplete: true,
            frozenBindingsMatch: true, r29EvidencePresentAndPassing: true, noUnresolvedDrift: true)
        let c1 = SRSClosureCandidate(scenario: "V-PERSIST-01", attemptID: "attempt-early",
                                     completionOrderKeyBytes: orderKeyA, eligibility: eligible)
        let c2 = SRSClosureCandidate(scenario: "V-PERSIST-01", attemptID: "attempt-late",
                                     completionOrderKeyBytes: orderKeyB, eligibility: eligible)
        // Phase 1: ineligible attempts are excluded before selection.
        let ineligible = SRSCandidateEligibility(
            evidenceV1to5Pass: false, scenarioExecutionRequired: true, verdictPass: true,
            latestProjectionExecutedActive: true, sourceBatchActiveOrComplete: true,
            frozenBindingsMatch: true, r29EvidencePresentAndPassing: true, noUnresolvedDrift: true)
        XCTAssertEqual(SRSClosure.admitEligibleCandidates([c1, c2]).count, 2)
        let ineligibleCandidate = SRSClosureCandidate(
            scenario: "V-PERSIST-02", attemptID: "attempt-x", completionOrderKeyBytes: orderKeyA,
            eligibility: ineligible)
        XCTAssertEqual(
            SRSClosure.admitEligibleCandidates([c1, c2, ineligibleCandidate]).map(\.attemptID),
            ["attempt-early", "attempt-late"])
        // Phase 1 output keeps multiple eligible attempts per scenario.
        let selection = try SRSClosure.selectFinalAttempts([c1, c2]).get()
        XCTAssertEqual(selection.map(\.attemptID), ["attempt-late"])
        // Phase 2 registration: exactly one candidate per scenario.
        var set: [SRSClosureCandidate] = []
        set = try SRSClosure.registerCandidate(c2, into: set).get()
        guard case .failure(let dup) = SRSClosure.registerCandidate(c1, into: set) else {
            return XCTFail("expected duplicate candidate rejection")
        }
        XCTAssertEqual(dup, .closureDuplicateCandidate)

        // Linear chain validation.
        let commit1 = SRSClosureCommitRecord(closureVersion: 1, priorClosureHeadVersion: nil, candidates: [c2], headState: .active)
        let commit2 = SRSClosureCommitRecord(closureVersion: 2, priorClosureHeadVersion: 1, candidates: [c2], headState: .active)
        let head = try SRSClosureChain.validateChain([commit1, commit2]).get()
        XCTAssertEqual(head.closureVersion, 2)
        XCTAssertEqual(head.headState, .active)
        // Fork rejection on a skipped/gapped version.
        let forked = SRSClosureCommitRecord(closureVersion: 4, priorClosureHeadVersion: 2, candidates: [], headState: .active)
        XCTAssertEqual(SRSClosureChain.validateChain([commit1, commit2, forked]), .failure(.closureChainForkRejected))
        // Invalidation only applies to the current head.
        let invalidated = try SRSClosureChain.applyInvalidation(SRSClosureInvalidation(targetClosureVersion: 2), head: head).get()
        XCTAssertEqual(invalidated.headState, .invalidated)
        XCTAssertEqual(
            SRSClosureChain.applyInvalidation(SRSClosureInvalidation(targetClosureVersion: 1), head: head),
            .failure(.closureInvalidationTargetNotHead)
        )
    }

    // MARK: - Writer classification against an existing content path

    func testWriteRejectsUnverifiableExistingContentPath() throws {
        let root = makeTempRoot()
        let recordsDir = root.appendingPathComponent("records", isDirectory: true)
        try FileManager.default.createDirectory(at: recordsDir, withIntermediateDirectories: true)
        let record = makeRecord()
        let payload = SRSCanonical.payloadBytes(record)
        let digestHex = SRSCanonical.payloadDigestHex(SRSCanonical.payloadDigest(payload))
        // Place a byte-valid frame signed by a non-production key at the exact
        // content-addressed path. The writer must execute R1-R28 on that path
        // before classification and must not overwrite it.
        let frame = buildFrame(record: record, key: Curve25519.Signing.PrivateKey())
        let contentPath = recordsDir.appendingPathComponent("\(digestHex).psrs")
        try Data(frame).write(to: contentPath)

        let writeKey = Curve25519.Signing.PrivateKey()
        let result = SRSWriter.write(record: record, signingKey: writeKey, root: root)
        XCTAssertEqual(result, .failure(.signatureVerificationFailed))
        // The exact existing bytes remain immutable.
        XCTAssertEqual(try Data(contentsOf: contentPath), Data(frame))
    }
}
