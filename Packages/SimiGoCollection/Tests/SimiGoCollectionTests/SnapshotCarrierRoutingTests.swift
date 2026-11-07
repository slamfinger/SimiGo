import Foundation
import XCTest

@testable import SimiGoCollection

/// The three snapshot carriers have to be separable by structure alone: real
/// exports arrive with no extension and with misleading sibling attachments, and
/// one directory of the measured corpus holds a flat export beside an AI Studio
/// document. Discovery therefore has nothing but `recognizes` to route on, so
/// that predicate has to behave as a partition.
///
/// This is the negative control for the per-adapter tests, each of which only
/// shows its own carrier refusing one other shape. Here every adapter meets
/// every shape, so a `recognizes` that claims everything and one that claims
/// nothing both fail.
final class SnapshotCarrierRoutingTests: XCTestCase {
    private struct Carrier {
        let sourceType: String
        let fileName: String
        let document: Data
        /// The same carrier's shape with one round more: recognisable, and
        /// different from `document` only in what the conversation says.
        let revised: Data
        let recognizes: (Data) -> Bool
        let read: (URL) throws -> SnapshotImport
        let interpret: (Data, String, String) throws -> SnapshotImport
    }

    private func carriers() -> [Carrier] {
        let flatRows = [
            SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
            SnapshotFixture.flatRow(
                id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
        ]
        let aiChunks = [
            SnapshotFixture.aiChunk(role: "user", text: "synthetic question"),
            SnapshotFixture.aiChunk(role: "model", text: "synthetic answer", finish: "STOP"),
        ]
        let dsNodes = [
            SnapshotFixture.dsNode(id: "1", parent: nil, children: ["2"]),
            SnapshotFixture.dsNode(
                id: "2", parent: "1",
                fragments: [
                    SnapshotFixture.dsFragment(type: "RESPONSE", content: "synthetic answer")
                ]),
        ]
        return [
            Carrier(
                sourceType: FlatMessageExportSource.sourceType,
                fileName: "flat-export.json",
                document: SnapshotFixture.encode(
                    SnapshotFixture.flatDocument(flatRows)),
                revised: SnapshotFixture.encode(
                    SnapshotFixture.flatDocument(
                        flatRows + [
                            SnapshotFixture.flatRow(
                                id: 3, role: "user", text: "second synthetic question")
                        ])),
                recognizes: FlatMessageExportSource.recognizes,
                read: FlatMessageExportSource.readSnapshot,
                interpret: FlatMessageExportSource.interpret),
            Carrier(
                sourceType: AIStudioSource.sourceType,
                fileName: "prompt.json",
                document: SnapshotFixture.encode(SnapshotFixture.aiDocument(aiChunks)),
                revised: SnapshotFixture.encode(
                    SnapshotFixture.aiDocument(
                        aiChunks + [
                            SnapshotFixture.aiChunk(
                                role: "user", text: "second synthetic question")
                        ])),
                recognizes: AIStudioSource.recognizes,
                read: AIStudioSource.readSnapshot,
                interpret: AIStudioSource.interpret),
            Carrier(
                sourceType: DeepSeekSource.sourceType,
                fileName: "conversations.json",
                document: SnapshotFixture.encode([
                    SnapshotFixture.dsConversation(id: "conv-1", nodes: dsNodes)
                ]),
                revised: SnapshotFixture.encode([
                    SnapshotFixture.dsConversation(id: "conv-1", nodes: dsNodes),
                    SnapshotFixture.dsConversation(id: "conv-2", nodes: dsNodes),
                ]),
                recognizes: DeepSeekSource.recognizes,
                read: DeepSeekSource.readSnapshot,
                interpret: DeepSeekSource.interpret),
        ]
    }

    /// The full 3×3 matrix: each shape is claimed, and claimed exactly once.
    func testRecognitionIsAPartitionOverTheThreeShapes() throws {
        let all = carriers()
        for (owner, carrier) in all.enumerated() {
            XCTAssertTrue(
                carrier.recognizes(carrier.document), "\(carrier.sourceType) claims its own")
            for (other, foreign) in all.enumerated() where other != owner {
                XCTAssertFalse(
                    carrier.recognizes(foreign.document),
                    "\(carrier.sourceType) must not claim \(foreign.sourceType)")
            }
        }
        // Two adapters claiming one document would import the same round twice
        // under two different identities.
        for carrier in all {
            XCTAssertEqual(
                all.filter { $0.recognizes(carrier.document) }.count, 1,
                "exactly one adapter may claim \(carrier.sourceType)")
        }
    }

    /// Mis-routing is an error, never an empty import — and only for the six
    /// wrong pairs. The three right pairs read, which is what turns the six
    /// refusals into evidence instead of a broken fixture.
    func testEveryWrongPairThrowsAndEveryRightPairReads() throws {
        let all = carriers()
        for (owner, carrier) in all.enumerated() {
            for (other, foreign) in all.enumerated() {
                let url = try SnapshotFixture.file(
                    foreign.document, named: foreign.fileName, in: "carrier-routing")
                if other == owner {
                    let imported = try carrier.read(url)
                    XCTAssertEqual(
                        imported.turns.count, 1,
                        "\(carrier.sourceType) reads its own round, so refusing the others is a judgement")
                    continue
                }
                XCTAssertThrowsError(try carrier.read(url)) { error in
                    guard case .foreignDocument(let path, let detail)? =
                        error as? SnapshotReadError
                    else {
                        return XCTFail("\(carrier.sourceType) on \(foreign.sourceType): \(error)")
                    }
                    XCTAssertEqual(
                        path, foreign.fileName, "only the file name travels into the error")
                    XCTAssertTrue(
                        detail.hasPrefix("\(carrier.sourceType) "),
                        "the error says who is refusing")
                    XCTAssertTrue(detail.contains("does not claim"))
                }
            }
        }
    }

    /// The digest is the revision evidence for a whole-file carrier, so it has to
    /// fingerprint the exact bytes: stable for the same document, different for a
    /// changed one, and handed in rather than restated by the adapter.
    func testContentDigestFingerprintsTheExactBytes() throws {
        for carrier in carriers() {
            let url = try SnapshotFixture.file(
                carrier.document, named: carrier.fileName, in: "digest-stable")
            let first = try carrier.read(url)
            let again = try carrier.read(url)
            XCTAssertEqual(
                first.contentDigest, again.contentDigest, "the same bytes are the same revision")
            XCTAssertEqual(
                first.contentDigest, CollectionDigest.sha256Hex(carrier.document),
                "\(carrier.sourceType) reports the digest of the bytes it read")
            XCTAssertEqual(first.contentDigest.count, 64)
            XCTAssertTrue(first.contentDigest.allSatisfy(\.isHexDigit))

            let revisedURL = try SnapshotFixture.file(
                carrier.revised, named: carrier.fileName, in: "digest-revised")
            let revised = try carrier.read(revisedURL)
            XCTAssertTrue(
                carrier.recognizes(carrier.revised), "the revised document is still this carrier")
            XCTAssertNotEqual(
                revised.contentDigest, first.contentDigest,
                "\(carrier.sourceType): a changed document must not read as unchanged")

            let handed = try carrier.interpret(
                carrier.document, carrier.fileName, "digest-as-handed")
            XCTAssertEqual(
                handed.contentDigest, "digest-as-handed",
                "\(carrier.sourceType) passes the digest through instead of computing its own")
        }
    }

    /// Renaming a file moves the identity of the carriers that have nothing to
    /// state it, and only of those. Stated identity is what makes DeepSeek's
    /// rounds re-importable from any directory, and the routing layer cannot
    /// supply it: the fact lives in the document or nowhere.
    private func sessionKeys(
        _ carrier: Carrier, document: Data, named name: String
    ) throws -> Set<String> {
        let url = try SnapshotFixture.file(document, named: name, in: "identity-by-name")
        return Set(try carrier.read(url).turns.map(\.sessionKey))
    }

    func testRenamingMovesOnlyTheDerivedIdentities() throws {
        let byType = Dictionary(uniqueKeysWithValues: carriers().map { ($0.sourceType, $0) })
        let flat = try XCTUnwrap(byType[FlatMessageExportSource.sourceType])
        let aiStudio = try XCTUnwrap(byType[AIStudioSource.sourceType])
        let deepseek = try XCTUnwrap(byType[DeepSeekSource.sourceType])

        // The flat carrier reads a stated session id first, so the derivation
        // under test needs a document that states none.
        let flatWithoutStatedSession = SnapshotFixture.encode(
            SnapshotFixture.flatDocument(
                [
                    SnapshotFixture.flatRow(id: 1, role: "user", text: "synthetic question"),
                    SnapshotFixture.flatRow(
                        id: 2, role: "assistant", text: "synthetic answer", finish: "stop"),
                ],
                sessionID: nil))

        for (carrier, document) in [(flat, flatWithoutStatedSession), (aiStudio, aiStudio.document)]
        {
            XCTAssertNotEqual(
                try sessionKeys(carrier, document: document, named: carrier.fileName),
                try sessionKeys(carrier, document: document, named: "renamed-\(carrier.fileName)"),
                "\(carrier.sourceType): the file name is the session, so renaming moves it")
        }
        XCTAssertEqual(
            try sessionKeys(deepseek, document: deepseek.document, named: deepseek.fileName),
            try sessionKeys(
                deepseek, document: deepseek.document, named: "renamed-\(deepseek.fileName)"),
            "\(deepseek.sourceType): the document states the session, so renaming is harmless")
    }
}
