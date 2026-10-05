import Foundation

public enum CarrierScaleTier: String, Hashable, Sendable, CaseIterable {
    case small
    case medium
    case large
    case stress
}

public struct CarrierBenchmarkPlan: Hashable, Sendable {
    public let tier: CarrierScaleTier
    public let objectCount: Int
    public let revisionCount: Int
    public let sessionEventCount: Int
    public let relationCount: Int
    public let searchQueryCount: Int
    public let payloadBytes: Int

    public init(
        tier: CarrierScaleTier,
        objectCount: Int,
        revisionCount: Int,
        sessionEventCount: Int,
        relationCount: Int,
        searchQueryCount: Int,
        payloadBytes: Int
    ) {
        self.tier = tier
        self.objectCount = objectCount
        self.revisionCount = revisionCount
        self.sessionEventCount = sessionEventCount
        self.relationCount = relationCount
        self.searchQueryCount = searchQueryCount
        self.payloadBytes = payloadBytes
    }

    public static func recommended(for tier: CarrierScaleTier) -> CarrierBenchmarkPlan {
        switch tier {
        case .small:
            CarrierBenchmarkPlan(
                tier: tier,
                objectCount: 100,
                revisionCount: 20,
                sessionEventCount: 100,
                relationCount: 100,
                searchQueryCount: 20,
                payloadBytes: 1_024
            )
        case .medium:
            CarrierBenchmarkPlan(
                tier: tier,
                objectCount: 1_000,
                revisionCount: 100,
                sessionEventCount: 1_000,
                relationCount: 1_000,
                searchQueryCount: 100,
                payloadBytes: 4_096
            )
        case .large:
            CarrierBenchmarkPlan(
                tier: tier,
                objectCount: 10_000,
                revisionCount: 1_000,
                sessionEventCount: 10_000,
                relationCount: 10_000,
                searchQueryCount: 1_000,
                payloadBytes: 16_384
            )
        case .stress:
            CarrierBenchmarkPlan(
                tier: tier,
                objectCount: 100_000,
                revisionCount: 10_000,
                sessionEventCount: 100_000,
                relationCount: 100_000,
                searchQueryCount: 10_000,
                payloadBytes: 65_536
            )
        }
    }
}

public struct CarrierBenchmarkReport: Hashable, Sendable {
    public let plan: CarrierBenchmarkPlan
    public let metrics: [CarrierMetricSummary]
    public let startedAt: Date
    public let completedAt: Date

    public init(
        plan: CarrierBenchmarkPlan,
        metrics: [CarrierMetricSummary],
        startedAt: Date,
        completedAt: Date
    ) {
        self.plan = plan
        self.metrics = metrics
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Harness preparation only. Calling `run` in production research requires
/// separate authorization; this type exists so every future candidate can be
/// driven through the same operation sequence.
public struct CarrierBenchmarkHarness {
    private let clock: ContinuousClock

    public init(clock: ContinuousClock = ContinuousClock()) {
        self.clock = clock
    }

    public func run(
        _ plan: CarrierBenchmarkPlan,
        on runtime: InformationSpaceRuntime,
        collector: CarrierMetricsCollector
    ) async throws -> CarrierBenchmarkReport {
        let startedAt = Date()
        let baseDate = startedAt

        for index in 0..<plan.objectCount {
            let info = CarrierInformationID(rawValue: "bench-info-\(index)")
            let payload = CarrierPayload(
                bytes: Data("\(index):\(plan.payloadBytes)".utf8),
                mediaType: "text/plain"
            )
            _ = try await measured("create", collector) {
                try await runtime.create(
                    CarrierCreateRequest(
                        informationID: info,
                        revisionID: CarrierRevisionID(rawValue: "bench-rev-\(index)"),
                        representationID: CarrierRepresentationID(rawValue: "bench-rep-\(index)"),
                        label: "Benchmark \(index)",
                        payload: payload,
                        locatorID: CarrierLocatorID(rawValue: "bench-loc-\(index)"),
                        locator: CarrierLocator(scheme: "memory", value: "bench/\(index)"),
                        provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness"),
                        searchableText: "benchmark object \(index)"
                    )
                )
            }

            if index.isMultiple(of: 2) {
                _ = try await measured("move", collector) {
                    try await runtime.move(
                        CarrierMoveRequest(
                            informationID: info,
                            newLocatorID: CarrierLocatorID(rawValue: "bench-loc-moved-\(index)"),
                            newLocator: CarrierLocator(scheme: "memory", value: "bench/moved/\(index)"),
                            movedAt: baseDate
                        )
                    )
                }
            }
        }

        for index in 0..<plan.revisionCount {
            let info = CarrierInformationID(rawValue: "bench-info-\(index % max(1, plan.objectCount))")
            _ = try await measured("revise", collector) {
                try await runtime.revise(
                    CarrierReviseRequest(
                        informationID: info,
                        revisionID: CarrierRevisionID(rawValue: "bench-revision-\(index)"),
                        representationID: CarrierRepresentationID(rawValue: "bench-revision-rep-\(index)"),
                        payload: CarrierPayload(bytes: Data("revision \(index)".utf8)),
                        locatorID: CarrierLocatorID(rawValue: "bench-revision-loc-\(index)"),
                        locator: CarrierLocator(scheme: "memory", value: "bench/revision/\(index)"),
                        provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness"),
                        predecessorRevisionID: CarrierRevisionID(rawValue: "bench-rev-\(index % max(1, plan.objectCount))")
                    )
                )
            }
        }

        for index in 0..<plan.sessionEventCount {
            _ = try await measured("session-append", collector) {
                try await runtime.appendSessionEvent(
                    CarrierSessionAppendRequest(
                        eventID: CarrierSessionEventID(rawValue: "bench-event-\(index)"),
                        sessionID: CarrierSessionID(rawValue: "bench-session"),
                        sequence: index,
                        kind: "benchmark",
                        payload: Data("event \(index)".utf8),
                        occurredAt: baseDate,
                        provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness")
                    )
                )
            }
        }

        for index in 0..<plan.relationCount {
            _ = try await measured("relation-append", collector) {
                try await runtime.relate(
                    relationID: CarrierRelationID(rawValue: "bench-relation-\(index)"),
                    subject: CarrierInformationID(rawValue: "bench-info-\(index % max(1, plan.objectCount))"),
                    predicate: "references",
                    object: CarrierInformationID(rawValue: "bench-info-\((index + 1) % max(1, plan.objectCount))"),
                    provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness")
                )
            }
        }

        for index in 0..<plan.searchQueryCount {
            _ = try await measured("search", collector) {
                try await runtime.search("benchmark \(index % max(1, plan.objectCount))")
            }
        }

        return CarrierBenchmarkReport(
            plan: plan,
            metrics: await collector.summaries(),
            startedAt: startedAt,
            completedAt: Date()
        )
    }

    private func measured<T>(
        _ name: String,
        _ collector: CarrierMetricsCollector,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let start = DispatchTime.now()
        let value = try await operation()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        await collector.record(name: name, seconds: elapsed)
        return value
    }
}
