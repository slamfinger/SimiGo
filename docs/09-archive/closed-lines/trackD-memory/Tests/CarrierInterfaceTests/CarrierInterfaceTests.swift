import Foundation
import Testing
@testable import CarrierInterface

@Suite
struct CarrierInterfaceTests {
    @Test
    func memoryCarrierPassesCoreConformance() async throws {
        let report = try await CarrierConformanceSuite(factory: MemoryCarrierRuntimeFactory()).run()

        #expect(report.passed)
        #expect(report.results.count == 10)
        #expect(!report.results.contains { !$0.passed })
    }

    @Test
    func locatorMoveChangesLocatorWithoutChangingInformationIdentity() async throws {
        let bundle = MemoryCarrierFactory().make()
        let info = CarrierInformationID(rawValue: "move-info")
        let provenance = CarrierProvenance(producedAt: Date(timeIntervalSinceReferenceDate: 0), producedBy: "test")

        _ = try await bundle.runtime.create(
            CarrierCreateRequest(
                informationID: info,
                revisionID: CarrierRevisionID(rawValue: "move-rev"),
                representationID: CarrierRepresentationID(rawValue: "move-rep"),
                payload: CarrierPayload(bytes: Data("payload".utf8)),
                locatorID: CarrierLocatorID(rawValue: "move-loc-1"),
                locator: CarrierLocator(scheme: "memory", value: "before"),
                provenance: provenance
            )
        )
        _ = try await bundle.runtime.move(
            CarrierMoveRequest(
                informationID: info,
                newLocatorID: CarrierLocatorID(rawValue: "move-loc-2"),
                newLocator: CarrierLocator(scheme: "memory", value: "after"),
                movedAt: Date(timeIntervalSinceReferenceDate: 1)
            )
        )
        let resolved = try await bundle.runtime.resolve(CarrierResolveRequest(informationID: info))

        #expect(resolved.content.representation.informationID == info)
        #expect(resolved.locator?.locator.value == "after")
    }

    @Test
    func metricsCollectorProducesPercentiles() async {
        let collector = CarrierMetricsCollector()
        for value in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0] {
            await collector.record(name: "operation", seconds: value)
        }
        let summary = await collector.summary("operation")

        #expect(summary?.count == 10)
        #expect(summary?.p50Seconds == 5.0)
        #expect(summary?.p95Seconds == 10.0)
        #expect(summary?.p99Seconds == 10.0)
        #expect(summary?.maxSeconds == 10.0)
    }

    @Test
    func integrityReporterDetectsOrphanRepresentationAndRecovery() async throws {
        let bundle = MemoryCarrierFactory().make()
        let info = CarrierInformationID(rawValue: "orphan-info")
        let representation = CarrierRepresentation(
            representationID: CarrierRepresentationID(rawValue: "orphan-rep"),
            informationID: info,
            revisionID: CarrierRevisionID(rawValue: "orphan-rev"),
            digest: "digest",
            byteCount: 2,
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )

        try await bundle.representations.put(
            CarrierRepresentationContent(
                representation: representation,
                payload: CarrierPayload(bytes: Data("orphan".utf8))
            )
        )
        let orphanReport = try await bundle.integrity.integrityReport()

        #expect(!orphanReport.isClean)
        #expect(orphanReport.issues.contains { $0.kind == .orphanRepresentation })

        try await bundle.locators.assign(
            CarrierLocatorRecord(
                locatorID: CarrierLocatorID(rawValue: "orphan-loc"),
                informationID: info,
                revisionID: representation.revisionID,
                representationID: representation.representationID,
                locator: CarrierLocator(scheme: "memory", value: "orphan"),
                createdAt: Date(timeIntervalSinceReferenceDate: 1)
            )
        )
        try await bundle.availability.record(
            CarrierAvailabilityRecord(
                informationID: info,
                revisionID: representation.revisionID,
                representationID: representation.representationID,
                state: .available,
                observedAt: Date(timeIntervalSinceReferenceDate: 2)
            )
        )

        let repairedReport = try await bundle.integrity.integrityReport()
        #expect(repairedReport.isClean)
    }
}
