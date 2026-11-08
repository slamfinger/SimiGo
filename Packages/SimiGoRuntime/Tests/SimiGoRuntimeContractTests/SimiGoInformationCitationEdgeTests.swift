import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// P-05: a retrieval that cites a settled summary must depend on it.
///
/// The file path is covered by `settlement_bindings.source_file_id`; a cited
/// settlement has no bytes to bind, so before this edge existed the citation was
/// invisible to the invalidation closure — invalidating the cited result left the
/// citing retrieval, and everything downstream of it, 'valid'.
final class SimiGoInformationCitationEdgeTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-cite-\(UUID().uuidString)-\(name).sqlite3")
    }
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private static let contract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#

    private func settle(_ db: SimiGoESISDatabase, stateID: String, value: String) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "RESULT=\(value)", contractJSON: Data(Self.contract.utf8),
            verifiedBindings: ["next_input": .string(value)])
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    func testCitedSettlementBecomesADependencyAndInvalidationPropagates() throws {
        let url = tempURL("citation")
        defer { cleanup(url) }
        let db = try SimiGoESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()

        let cited = try settle(db, stateID: "S-CITED", value: "epsilon")
        _ = try db.recordSettlementSummary(
            settlementID: cited, sessionID: nil, query: "where epsilon lives")

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(.init(
            stateID: "S-ASKER", query: "epsilon",
            rootIDs: [], includeChat: false))

        let citedHit = try XCTUnwrap(
            resolution.hits.first { $0.kind == "settlement" },
            "the settled summary must be citable by its own query term")
        let declared = citedHit.sourceSettlementID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = (declared?.isEmpty == false)
            ? declared!
            : String(citedHit.itemID.dropFirst("settlement:".count))
        XCTAssertEqual(effective, cited)

        let closure = try db.upstreamDependencyClosure(
            ofSettlement: resolution.retrievalSettlementID)
        XCTAssertTrue(closure.contains(cited),
                      "the retrieval must record that it cites the settled result")

        // Repeating the same pair is a no-op, so in-degree stays the number of
        // distinct dependencies rather than the number of attempts.
        try db.addDependency(fromSettlement: resolution.retrievalSettlementID,
                             toSettlement: cited, kind: "citation")
        let again = try db.upstreamDependencyClosure(
            ofSettlement: resolution.retrievalSettlementID)
        XCTAssertEqual(again.filter { $0 == cited }.count, 1)

        // Withdrawing the cited result withdraws the answer that cited it.
        let invalidated = try db.invalidateSettlement(cited)
        XCTAssertTrue(invalidated.contains(cited))
        XCTAssertTrue(invalidated.contains(resolution.retrievalSettlementID),
                      "the citing retrieval is downstream of the cited settlement")
        XCTAssertEqual(try db.settlementValidity(resolution.retrievalSettlementID), "invalid")
        XCTAssertEqual(try db.settlementValidity(cited), "invalid")
    }
}
