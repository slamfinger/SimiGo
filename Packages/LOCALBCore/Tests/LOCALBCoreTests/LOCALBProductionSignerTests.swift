import Crypto
import Foundation
import Security
import XCTest

@testable import LOCALBCore

final class LOCALBProductionSignerTests: XCTestCase {
    private func makeBinding(_ name: String) -> SRSBindingValue {
        SRSBindingValue(identity: name, version: "1.0.0",
                        contentDigestHex64: String(repeating: "a", count: 64))
    }

    private func makeRecord() -> PersistentSRSRecord {
        var record = PersistentSRSRecord()
        record.logicalKeyIdentity = "localb-relation-001"
        record.logicalKeyVersion = "1.0.0"
        record.settledBinding = makeBinding("settled")
        record.settlementID = "settle-localb-001"
        record.settlementStatus = .declaredSettled
        record.sourceRelationIdentity = "source-relation"
        record.resultIdentity = "result-relation"
        record.requiresCanonicalIdentityRule = true
        record.canonicalIdentityRule = makeBinding("canonical-rule")
        record.settledProvenanceBindings = [makeBinding("sp-1")]
        record.sourceBinding = makeBinding("source")
        record.sourceInvalidationStatus = .none
        record.sourceStatus = .current
        record.dependencyBoundary = makeBinding("dependency-boundary")
        record.dependencies = [
            SRSDependency(binding: makeBinding("dependency-1"), role: "input",
                          necessity: "hard", resolution: .resolved, status: .current)
        ]
        record.resultBinding = makeBinding("result")
        record.resultResolution = .resolvedWithoutRecompute
        record.resultStatus = .current
        record.provenanceBindings = [makeBinding("prov-1")]
        record.provenanceLifecycle = .declaredSettled
        record.lifecycleBindings = [makeBinding("life-1")]
        record.lifecycleStatus = .declaredSettled
        record.freshnessRequirements = [
            SRSFreshnessRequirement(
                identity: "freshness-1",
                evidence: makeBinding("freshness-evidence"),
                expectedEvidenceDigestHex64: String(repeating: "b", count: 64),
                status: .current,
                validUntilUTC: "2026-12-31T23:59:59Z",
                observedAtUTC: "2026-10-11T00:00:00Z"
            )
        ]
        record.policies = [makeBinding("policy-1")]
        record.producerAuthorizationReference = "LOCALB-AUDIT-REF-001"
        return record
    }

    private func makeEntry(for key: Curve25519.Signing.PrivateKey,
                           lineageID: String,
                           generation: UInt32 = 1,
                           status: LOCALBKeyStatus = .active) throws -> LOCALBRegistryKeyEntry {
        let publicKey = Array(key.publicKey.rawRepresentation)
        return LOCALBRegistryKeyEntry(
            keyID: try LOCALBSigningInputV1.keyID(publicKeyRaw: publicKey),
            publicKeyRaw: publicKey,
            generation: generation,
            status: status,
            lineageID: lineageID
        )
    }

    func testSigningInputBindsGenerationAndLineage() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = Array(key.publicKey.rawRepresentation)
        let lineageA = UUID().uuidString.lowercased()
        let lineageB = UUID().uuidString.lowercased()
        let base = LOCALBSigningFields(
            logicalKeyIdentity: "rel-1",
            logicalKeyVersion: "1.0.0",
            payloadDigestHex: String(repeating: "0", count: 64),
            signerPublicKeyRaw: publicKey,
            producerAuthorizationReference: "audit-ref",
            decisionCoreSourceCommit: SRSEncodingConstants.decisionCoreSourceCommit,
            decisionCoreSourceSHA256Hex: SRSEncodingConstants.decisionCoreSourceSHA256,
            issuerGeneration: 1,
            issuerLineageID: lineageA,
            canonicalPayload: Array("canonical-payload".utf8)
        )
        let signature = try LOCALBSigningInputV1.sign(base, with: key)
        XCTAssertTrue(LOCALBSigningInputV1.verify(signature, fields: base))

        let changedGeneration = LOCALBSigningFields(
            logicalKeyIdentity: base.logicalKeyIdentity,
            logicalKeyVersion: base.logicalKeyVersion,
            payloadDigestHex: base.payloadDigestHex,
            signerPublicKeyRaw: base.signerPublicKeyRaw,
            producerAuthorizationReference: base.producerAuthorizationReference,
            decisionCoreSourceCommit: base.decisionCoreSourceCommit,
            decisionCoreSourceSHA256Hex: base.decisionCoreSourceSHA256Hex,
            issuerGeneration: 2,
            issuerLineageID: base.issuerLineageID,
            canonicalPayload: base.canonicalPayload
        )
        XCTAssertFalse(LOCALBSigningInputV1.verify(signature, fields: changedGeneration))

        let changedLineage = LOCALBSigningFields(
            logicalKeyIdentity: base.logicalKeyIdentity,
            logicalKeyVersion: base.logicalKeyVersion,
            payloadDigestHex: base.payloadDigestHex,
            signerPublicKeyRaw: base.signerPublicKeyRaw,
            producerAuthorizationReference: base.producerAuthorizationReference,
            decisionCoreSourceCommit: base.decisionCoreSourceCommit,
            decisionCoreSourceSHA256Hex: base.decisionCoreSourceSHA256Hex,
            issuerGeneration: base.issuerGeneration,
            issuerLineageID: lineageB,
            canonicalPayload: base.canonicalPayload
        )
        XCTAssertFalse(LOCALBSigningInputV1.verify(signature, fields: changedLineage))
    }

    func testCredentialDigestUsesCanonicalUUIDAndRawSecretBytes() throws {
        let material = try LOCALBPairingCredentialMaterial.issue()
        XCTAssertEqual(material.credentialID.utf8.count, 36)
        XCTAssertEqual(material.digest.count, 32)
        let secret = try material.takeSecretRawOnce()
        XCTAssertEqual(secret.count, 32)
        XCTAssertTrue(material.verify(presentedSecretRaw: secret))
        XCTAssertThrowsError(try material.takeSecretRawOnce())

        let wrong = [UInt8](repeating: 0, count: 32)
        XCTAssertFalse(material.verify(presentedSecretRaw: wrong))

        XCTAssertThrowsError(try LOCALBPairingCredentialMaterial.credentialDigest(
            credentialID: material.credentialID.uppercased(),
            secretRaw: secret
        ))
    }

    func testLOCALBRecordWriterReaderRoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let lineageID = UUID().uuidString.lowercased()
        let record = makeRecord()
        let snapshot = try LOCALBRegistrySnapshot(
            currentLineageID: lineageID,
            entries: [try makeEntry(for: key, lineageID: lineageID)]
        )
        let frame = try LOCALBRecordWriter.encode(
            record: record, signingKey: key, lineageID: lineageID,
            issuerGeneration: 1, registry: snapshot
        )

        let result = LOCALBRecordReader.read(data: frame, registry: snapshot)
        let verified = try result.get()
        XCTAssertEqual(verified.logicalKeyIdentity, record.logicalKeyIdentity)
        XCTAssertEqual(verified.logicalKeyVersion, record.logicalKeyVersion)
        XCTAssertEqual(verified.issuerGeneration, 1)
        XCTAssertEqual(verified.issuerLineageID, lineageID)
        XCTAssertEqual(verified.producerAuthorizationReference, record.producerAuthorizationReference)
        XCTAssertEqual(verified.payloadBytes, SRSCanonical.payloadBytes(record))
    }

    func testReaderRejectsGenerationMismatchAndForeignLineage() throws {
        let key = Curve25519.Signing.PrivateKey()
        let lineageID = UUID().uuidString.lowercased()
        let signingSnapshot = try LOCALBRegistrySnapshot(
            currentLineageID: lineageID,
            entries: [try makeEntry(for: key, lineageID: lineageID, generation: 1)]
        )
        let frame = try LOCALBRecordWriter.encode(
            record: makeRecord(), signingKey: key, lineageID: lineageID,
            issuerGeneration: 1, registry: signingSnapshot
        )

        let wrongGenerationSnapshot = try LOCALBRegistrySnapshot(
            currentLineageID: lineageID,
            entries: [try makeEntry(for: key, lineageID: lineageID, generation: 2)]
        )
        XCTAssertEqual(LOCALBRecordReader.read(data: frame, registry: wrongGenerationSnapshot),
                       .failure(.issuerGenerationMismatch))

        let foreignCurrentLineage = UUID().uuidString.lowercased()
        let foreignLineageSnapshot = try LOCALBRegistrySnapshot(
            currentLineageID: foreignCurrentLineage,
            entries: [try makeEntry(for: key, lineageID: lineageID)]
        )
        XCTAssertEqual(LOCALBRecordReader.read(data: frame, registry: foreignLineageSnapshot),
                       .failure(.issuerLineageMismatch))
    }

    func testWriterRefusesNonActiveSigningKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let lineageID = UUID().uuidString.lowercased()
        let retiredSnapshot = try LOCALBRegistrySnapshot(
            currentLineageID: lineageID,
            entries: [try makeEntry(for: key, lineageID: lineageID, status: .retired)]
        )
        XCTAssertThrowsError(try LOCALBRecordWriter.encode(
            record: makeRecord(), signingKey: key, lineageID: lineageID,
            issuerGeneration: 1, registry: retiredSnapshot
        )) { error in
            XCTAssertEqual(error as? LOCALBStatus, .issuerKeyNotActive)
        }
    }

    func testRevokedKeyNeverVerifiesEvenWithValidSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let lineageID = UUID().uuidString.lowercased()
        let signingSnapshot = try LOCALBRegistrySnapshot(
            currentLineageID: lineageID,
            entries: [try makeEntry(for: key, lineageID: lineageID, status: .active)]
        )
        let frame = try LOCALBRecordWriter.encode(
            record: makeRecord(), signingKey: key, lineageID: lineageID,
            issuerGeneration: 1, registry: signingSnapshot
        )
        let revokedSnapshot = try LOCALBRegistrySnapshot(
            currentLineageID: lineageID,
            entries: [try makeEntry(for: key, lineageID: lineageID, status: .revoked)]
        )
        XCTAssertEqual(LOCALBRecordReader.read(data: frame, registry: revokedSnapshot),
                       .failure(.issuerKeyRevoked))
    }

    // Cross-domain rejection tests intentionally NOT ported:
    //   testFrozenAReaderStructurallyRejectsLOCALBEnvelopeWithoutSourceMutation
    //   testADomainEnvelopeIsRejectedBySchemaBeforeEnvelopeDigest
    // Both require the frozen Domain-A implementation (SRSReader, SRSSignature
    // anchor material, the A-envelope codec), which is deliberately absent from
    // this package. They remain in the Lab test suite (PR #10), where both
    // trust domains coexist. The B-side early-schema rejection property itself
    // is covered here by testSchemaIDRejectionPrecedesPayloadInterpretation-
    // AndEnvelopeDigest below, which is self-contained.

    func testSchemaIDRejectionPrecedesPayloadInterpretationAndEnvelopeDigest() throws {
        let key = Curve25519.Signing.PrivateKey()
        let lineageID = UUID().uuidString.lowercased()
        let signingSnapshot = try LOCALBRegistrySnapshot(
            currentLineageID: lineageID,
            entries: [try makeEntry(for: key, lineageID: lineageID)]
        )
        var frame = try LOCALBRecordWriter.encode(
            record: makeRecord(), signingKey: key, lineageID: lineageID,
            issuerGeneration: 1, registry: signingSnapshot
        )

        var payloadLength: UInt64 = 0
        for byte in frame[16..<24] { payloadLength = (payloadLength << 8) | UInt64(byte) }
        let envelopeStart = 64 + Int(payloadLength)
        let firstLabel = Array("envelope_schema_id".utf8)
        let schemaValueStart = envelopeStart + 4 + 2 + firstLabel.count + 8
        XCTAssertLessThan(schemaValueStart, frame.count)
        // Same byte length, so the envelope stays parseable; digest is now stale.
        frame[schemaValueStart] = UInt8(ascii: "X")

        let lineageSnapshot = try LOCALBRegistrySnapshot(currentLineageID: lineageID, entries: [])
        XCTAssertEqual(LOCALBRecordReader.read(data: frame, registry: lineageSnapshot),
                       .failure(.unknownEnvelopeSchema))
    }

    /// The signer store is scoped by the same rule as the transport identity
    /// store: under an isolated managed root its item lives in a keychain file
    /// inside that root, never in the real login Keychain.
    func testKeychainSignerStoreScopeKeepsItemOutOfDefaultSearchList() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("signer-scope-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("signer.keychain-db").path
        let service = "com.simigo.tests.signer-scope.\(UUID().uuidString)"
        let store = LOCALBKeychainSignerStore(service: service, account: "signing-key-v1",
                                             keychainPath: path)
        let created = try store.loadOrCreate()
        XCTAssertEqual(created.rawRepresentation.count, 32)
        XCTAssertEqual(try store.loadExisting().rawRepresentation, created.rawRepresentation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        var defaultRef: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "signing-key-v1",
            kSecReturnData as String: true
        ] as CFDictionary, &defaultRef), errSecItemNotFound)
    }
}
