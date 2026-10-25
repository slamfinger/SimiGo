import Foundation
import Testing
import CarrierInterface
@testable import CarrierSQLite

@Suite
struct CarrierSQLiteTests {
    private func freshFactory() -> SQLiteCarrierFactory {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccvs01-a1-test-\(UUID().uuidString)", isDirectory: true)
        return SQLiteCarrierFactory(rootURL: root)
    }

    @Test
    func sqliteCarrierPassesFullConformance() async throws {
        let report = try await CarrierConformanceSuite(factory: SQLiteTemporaryRuntimeFactory()).run()
        #expect(report.results.count == 10)
        for result in report.results where !result.passed {
            Issue.record("conformance failed: \(result.name): \(result.detail)")
        }
        #expect(report.passed)
    }

    @Test
    func durableStateSurvivesReopen() async throws {
        let factory = freshFactory()
        let bundle = try factory.make()
        let info = CarrierInformationID(rawValue: "reopen-info")
        _ = try await bundle.runtime.create(
            CarrierCreateRequest(
                informationID: info,
                revisionID: CarrierRevisionID(rawValue: "reopen-rev"),
                representationID: CarrierRepresentationID(rawValue: "reopen-rep"),
                payload: CarrierPayload(bytes: Data("reopen payload".utf8)),
                locatorID: CarrierLocatorID(rawValue: "reopen-loc"),
                locator: CarrierLocator(scheme: "file", value: "reopen/1"),
                provenance: CarrierProvenance(producedAt: Date(), producedBy: "test"),
                searchableText: "reopen payload body"
            )
        )
        // Reopen the same data root with a new composition.
        let reopened = try factory.make()
        let resolved = try await reopened.runtime.resolve(CarrierResolveRequest(informationID: info))
        #expect(String(data: resolved.content.payload.bytes, encoding: .utf8) == "reopen payload")
        let searchHits = try await reopened.runtime.composition.search.search("reopen", limit: 10)
        #expect(searchHits.contains { $0.informationID == info })
    }

    @Test
    func moveIsAtomicAcrossCrashBoundary() async throws {
        let bundle = try freshFactory().make()
        let info = CarrierInformationID(rawValue: "atomic-move-info")
        _ = try await bundle.runtime.create(
            CarrierCreateRequest(
                informationID: info,
                revisionID: CarrierRevisionID(rawValue: "atomic-rev"),
                representationID: CarrierRepresentationID(rawValue: "atomic-rep"),
                payload: CarrierPayload(bytes: Data("atomic".utf8)),
                locatorID: CarrierLocatorID(rawValue: "atomic-loc-1"),
                locator: CarrierLocator(scheme: "file", value: "before/1"),
                provenance: CarrierProvenance(producedAt: Date(), producedBy: "test")
            )
        )
        // Retire without assign would leave an open transaction; the runtime
        // always pairs them, and any stray handoff commits by itself.
        try await bundle.core.retireLocator("atomic-loc-1", retiredAt: Date())
        try await bundle.core.run("SELECT 1", bind: { _ in })
        let history = try await bundle.runtime.composition.locators.history(for: info)
        #expect(history.count == 1)
        #expect(history.first?.retiredAt != nil)
    }

    @Test
    func integrityDetectsOrphanEntityFile() async throws {
        let factory = freshFactory()
        let bundle = try factory.make()
        let orphanDir = factory.rootURL
            .appendingPathComponent("entities/ab", isDirectory: true)
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        let orphanDigest = String(repeating: "ab", count: 32)
        try Data("orphan".utf8).write(to: orphanDir.appendingPathComponent(orphanDigest))
        let report = try await bundle.runtime.integrityReport()
        #expect(!report.isClean)
        #expect(report.issues.contains { $0.detail.contains(orphanDigest) })
    }
}
