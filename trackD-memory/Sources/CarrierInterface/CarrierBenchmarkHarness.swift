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
    public let copyCount: Int
    public let splitCount: Int
    public let mergeCount: Int
    public let pinCount: Int
    public let deleteRestoreCount: Int
    public let sessionEventCount: Int
    public let relationCount: Int
    public let searchQueryCount: Int
    public let rebuildCount: Int
    public let payloadBytes: Int

    public init(
        tier: CarrierScaleTier,
        objectCount: Int,
        revisionCount: Int,
        copyCount: Int,
        splitCount: Int,
        mergeCount: Int,
        pinCount: Int,
        deleteRestoreCount: Int,
        sessionEventCount: Int,
        relationCount: Int,
        searchQueryCount: Int,
        rebuildCount: Int,
        payloadBytes: Int
    ) {
        self.tier = tier
        self.objectCount = objectCount
        self.revisionCount = revisionCount
        self.copyCount = copyCount
        self.splitCount = splitCount
        self.mergeCount = mergeCount
        self.pinCount = pinCount
        self.deleteRestoreCount = deleteRestoreCount
        self.sessionEventCount = sessionEventCount
        self.relationCount = relationCount
        self.searchQueryCount = searchQueryCount
        self.rebuildCount = rebuildCount
        self.payloadBytes = payloadBytes
    }

    public static func recommended(for tier: CarrierScaleTier) -> CarrierBenchmarkPlan {
        switch tier {
        case .small:
            CarrierBenchmarkPlan(tier: tier, objectCount: 100, revisionCount: 20, copyCount: 20, splitCount: 5, mergeCount: 5, pinCount: 20, deleteRestoreCount: 20, sessionEventCount: 100, relationCount: 100, searchQueryCount: 20, rebuildCount: 1, payloadBytes: 1_024)
        case .medium:
            CarrierBenchmarkPlan(tier: tier, objectCount: 1_000, revisionCount: 100, copyCount: 100, splitCount: 25, mergeCount: 25, pinCount: 100, deleteRestoreCount: 100, sessionEventCount: 1_000, relationCount: 1_000, searchQueryCount: 100, rebuildCount: 2, payloadBytes: 4_096)
        case .large:
            CarrierBenchmarkPlan(tier: tier, objectCount: 10_000, revisionCount: 1_000, copyCount: 1_000, splitCount: 100, mergeCount: 100, pinCount: 1_000, deleteRestoreCount: 1_000, sessionEventCount: 10_000, relationCount: 10_000, searchQueryCount: 1_000, rebuildCount: 3, payloadBytes: 16_384)
        case .stress:
            CarrierBenchmarkPlan(tier: tier, objectCount: 100_000, revisionCount: 10_000, copyCount: 10_000, splitCount: 500, mergeCount: 500, pinCount: 10_000, deleteRestoreCount: 10_000, sessionEventCount: 100_000, relationCount: 100_000, searchQueryCount: 10_000, rebuildCount: 5, payloadBytes: 65_536)
        }
    }
}

public struct CarrierBenchmarkReport: Hashable, Sendable {
    public let plan: CarrierBenchmarkPlan
    public let metrics: [CarrierMetricSummary]
    public let resourceDeltas: [CarrierResourceDelta]
    public let recoveryReports: [CarrierRecoveryReport]
    public let startedAt: Date
    public let completedAt: Date

    public init(plan: CarrierBenchmarkPlan, metrics: [CarrierMetricSummary], resourceDeltas: [CarrierResourceDelta], recoveryReports: [CarrierRecoveryReport], startedAt: Date, completedAt: Date) {
        self.plan = plan
        self.metrics = metrics
        self.resourceDeltas = resourceDeltas
        self.recoveryReports = recoveryReports
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Harness preparation only. Calling `run` for candidate research requires
/// separate authorization; this type exists so every future composition is
/// driven through the same operation set.
public struct CarrierBenchmarkHarness {
    private let resourceObserver: any CarrierResourceObserver
    private let recoveryTester: (any CarrierCrashRecoveryTester)?

    public init(
        resourceObserver: any CarrierResourceObserver = NullCarrierResourceObserver(),
        recoveryTester: (any CarrierCrashRecoveryTester)? = nil
    ) {
        self.resourceObserver = resourceObserver
        self.recoveryTester = recoveryTester
    }

    public func run(
        _ plan: CarrierBenchmarkPlan,
        on runtime: InformationSpaceRuntime,
        collector: CarrierMetricsCollector
    ) async throws -> CarrierBenchmarkReport {
        let startedAt = Date()
        let baseDate = startedAt
        var resourceDeltas: [CarrierResourceDelta] = []
        let objectCount = max(1, plan.objectCount)

        resourceDeltas += try await sampledPhase("create") {
            for index in 0..<plan.objectCount {
                let info = CarrierInformationID(rawValue: "bench-info-\(index)")
                let payload = CarrierPayload(bytes: Data(repeating: UInt8(index % 251), count: plan.payloadBytes), mediaType: "application/octet-stream")
                _ = try await measured("create", collector) {
                    try await runtime.create(CarrierCreateRequest(informationID: info, revisionID: CarrierRevisionID(rawValue: "bench-rev-\(index)"), representationID: CarrierRepresentationID(rawValue: "bench-rep-\(index)"), label: "Benchmark \(index)", payload: payload, locatorID: CarrierLocatorID(rawValue: "bench-loc-\(index)"), locator: CarrierLocator(scheme: "memory", value: "bench/\(index)"), provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness")))
                }
                if index.isMultiple(of: 2) {
                    _ = try await measured("move", collector) {
                        try await runtime.move(CarrierMoveRequest(informationID: info, newLocatorID: CarrierLocatorID(rawValue: "bench-loc-moved-\(index)"), newLocator: CarrierLocator(scheme: "memory", value: "bench/moved/\(index)"), movedAt: baseDate))
                    }
                }
            }
        }

        resourceDeltas += try await sampledPhase("revise") {
            for index in 0..<plan.revisionCount {
                let sourceIndex = index % objectCount
                _ = try await measured("revise", collector) {
                    try await runtime.revise(CarrierReviseRequest(informationID: CarrierInformationID(rawValue: "bench-info-\(sourceIndex)"), revisionID: CarrierRevisionID(rawValue: "bench-revision-\(index)"), representationID: CarrierRepresentationID(rawValue: "bench-revision-rep-\(index)"), payload: CarrierPayload(bytes: Data("revision \(index)".utf8)), locatorID: CarrierLocatorID(rawValue: "bench-revision-loc-\(index)"), locator: CarrierLocator(scheme: "memory", value: "bench/revision/\(index)"), provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness"), predecessorRevisionID: CarrierRevisionID(rawValue: "bench-rev-\(sourceIndex)")))
                }
            }
        }

        resourceDeltas += try await sampledPhase("copy") {
            for index in 0..<plan.copyCount {
                _ = try await measured("copy", collector) {
                    try await runtime.copy(CarrierCopyRequest(sourceInformationID: CarrierInformationID(rawValue: "bench-info-\(index % objectCount)"), targetInformationID: CarrierInformationID(rawValue: "bench-copy-\(index)"), revisionID: CarrierRevisionID(rawValue: "bench-copy-rev-\(index)"), representationID: CarrierRepresentationID(rawValue: "bench-copy-rep-\(index)"), locatorID: CarrierLocatorID(rawValue: "bench-copy-loc-\(index)"), locator: CarrierLocator(scheme: "memory", value: "bench/copy/\(index)"), provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness")))
                }
            }
        }

        resourceDeltas += try await sampledPhase("split-merge") {
            for index in 0..<plan.splitCount {
                let target = CarrierCreateRequest(informationID: CarrierInformationID(rawValue: "bench-split-\(index)"), revisionID: CarrierRevisionID(rawValue: "bench-split-rev-\(index)"), representationID: CarrierRepresentationID(rawValue: "bench-split-rep-\(index)"), payload: CarrierPayload(bytes: Data("split \(index)".utf8)), locatorID: CarrierLocatorID(rawValue: "bench-split-loc-\(index)"), locator: CarrierLocator(scheme: "memory", value: "bench/split/\(index)"), provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness"))
                _ = try await measured("split", collector) {
                    try await runtime.split(CarrierSplitRequest(sourceInformationID: CarrierInformationID(rawValue: "bench-info-\(index % objectCount)"), targets: [target], provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness")))
                }
            }
            for index in 0..<plan.mergeCount {
                let target = CarrierCreateRequest(informationID: CarrierInformationID(rawValue: "bench-merge-\(index)"), revisionID: CarrierRevisionID(rawValue: "bench-merge-rev-\(index)"), representationID: CarrierRepresentationID(rawValue: "bench-merge-rep-\(index)"), payload: CarrierPayload(bytes: Data("merge \(index)".utf8)), locatorID: CarrierLocatorID(rawValue: "bench-merge-loc-\(index)"), locator: CarrierLocator(scheme: "memory", value: "bench/merge/\(index)"), provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness"))
                let copyCount = max(1, plan.copyCount)
                _ = try await measured("merge", collector) {
                    try await runtime.merge(CarrierMergeRequest(target: target, sourceInformationIDs: [CarrierInformationID(rawValue: "bench-info-\(index % objectCount)"), CarrierInformationID(rawValue: "bench-copy-\(index % copyCount)")], relationIDs: [CarrierRelationID(rawValue: "bench-merge-relation-\(index)-a"), CarrierRelationID(rawValue: "bench-merge-relation-\(index)-b")], provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness")))
                }
            }
        }

        resourceDeltas += try await sampledPhase("availability-pin") {
            for index in 0..<plan.deleteRestoreCount {
                let info = CarrierInformationID(rawValue: "bench-info-\(index % objectCount)")
                _ = try await measured("delete", collector) {
                    try await runtime.recordAvailability(CarrierAvailabilityRequest(informationID: info, state: .deleted, reason: "benchmark delete", observedAt: baseDate))
                }
                _ = try await measured("restore", collector) {
                    try await runtime.recordAvailability(CarrierAvailabilityRequest(informationID: info, state: .restored, reason: "benchmark restore", observedAt: baseDate))
                }
            }
            for index in 0..<plan.pinCount {
                _ = try await measured("pin", collector) {
                    try await runtime.pin(CarrierResolveRequest(informationID: CarrierInformationID(rawValue: "bench-info-\(index % objectCount)")), pinID: CarrierPinID(rawValue: "bench-pin-\(index)"), label: "benchmark", at: baseDate)
                }
            }
        }

        resourceDeltas += try await sampledPhase("session-relation") {
            for index in 0..<plan.sessionEventCount {
                _ = try await measured("session-append", collector) {
                    try await runtime.appendSessionEvent(CarrierSessionAppendRequest(eventID: CarrierSessionEventID(rawValue: "bench-event-\(index)"), sessionID: CarrierSessionID(rawValue: "bench-session"), sequence: index, kind: "benchmark", payload: Data("event \(index)".utf8), occurredAt: baseDate, provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness")))
                }
            }
            _ = try await measured("session-summary", collector) {
                try await runtime.addSessionSummary(summaryID: CarrierSummaryID(rawValue: "bench-summary"), sessionID: CarrierSessionID(rawValue: "bench-session"), throughSequence: max(0, plan.sessionEventCount - 1), payload: Data("benchmark summary".utf8), provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness"))
            }
            for index in 0..<plan.relationCount {
                _ = try await measured("relation-append", collector) {
                    try await runtime.relate(relationID: CarrierRelationID(rawValue: "bench-relation-\(index)"), subject: CarrierInformationID(rawValue: "bench-info-\(index % objectCount)"), predicate: "references", object: CarrierInformationID(rawValue: "bench-info-\((index + 1) % objectCount)"), provenance: CarrierProvenance(producedAt: baseDate, producedBy: "harness"))
                }
            }
            for index in 0..<min(plan.relationCount, 100) {
                _ = try await measured("relation-traverse", collector) {
                    try await runtime.composition.relations.relations(involving: CarrierInformationID(rawValue: "bench-info-\(index % objectCount)"))
                }
            }
        }

        resourceDeltas += try await sampledPhase("search-rebuild") {
            for index in 0..<plan.searchQueryCount {
                _ = try await measured("search", collector) {
                    try await runtime.search("benchmark \(index % objectCount)")
                }
            }
            for _ in 0..<plan.rebuildCount {
                let documents = (0..<plan.objectCount).map { index in
                    CarrierSearchDocument(informationID: CarrierInformationID(rawValue: "bench-info-\(index)"), revisionID: CarrierRevisionID(rawValue: "bench-rev-\(index)"), title: "Benchmark \(index)", text: "benchmark object \(index)")
                }
                _ = try await measured("index-rebuild", collector) {
                    try await runtime.rebuildSearch(with: documents)
                }
            }
        }

        resourceDeltas += try await sampledPhase("integrity") {
            _ = try await measured("integrity-report", collector) {
                try await runtime.integrityReport()
            }
        }

        var recoveryReports: [CarrierRecoveryReport] = []
        if let recoveryTester {
            let selectedPoints = Array(CarrierCrashPoint.allCases.prefix(plan.tier == .small ? 3 : CarrierCrashPoint.allCases.count))
            for point in selectedPoints {
                _ = try await measured("crash-recovery", collector) {
                    try await recoveryTester.recoveryReport(for: point)
                }
            }
            for point in selectedPoints {
                do {
                    recoveryReports.append(try await recoveryTester.recoveryReport(for: point))
                } catch {
                    recoveryReports.append(CarrierRecoveryReport(point: point, outcome: .failed, integrityClean: false, detail: String(describing: error)))
                }
            }
        }

        return CarrierBenchmarkReport(plan: plan, metrics: await collector.summaries(), resourceDeltas: resourceDeltas, recoveryReports: recoveryReports, startedAt: startedAt, completedAt: Date())
    }

    private func sampledPhase(_ label: String, _ operation: () async throws -> Void) async throws -> [CarrierResourceDelta] {
        let before = try await resourceObserver.sample(label: "\(label):before")
        try await operation()
        let after = try await resourceObserver.sample(label: "\(label):after")
        return [CarrierResourceDelta(label: label, before: before, after: after)]
    }

    private func measured<T>(_ name: String, _ collector: CarrierMetricsCollector, _ operation: () async throws -> T) async rethrows -> T {
        let start = DispatchTime.now()
        let value = try await operation()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        await collector.record(name: name, seconds: elapsed)
        return value
    }
}

public extension CarrierResourceDelta {
    init(label: String, before: CarrierResourceSample, after: CarrierResourceSample) {
        self.label = label
        self.residentBytesDelta = Self.delta(before.residentBytes, after.residentBytes)
        self.diskReadBytesDelta = Self.delta(before.diskReadBytes, after.diskReadBytes)
        self.diskWrittenBytesDelta = Self.delta(before.diskWrittenBytes, after.diskWrittenBytes)
        self.cpuSecondsDelta = Self.delta(before.cpuSeconds, after.cpuSeconds)
    }

    static func delta(_ before: UInt64?, _ after: UInt64?) -> Int64? {
        guard let before, let after else { return nil }
        return Int64(after) - Int64(before)
    }

    static func delta(_ before: Double?, _ after: Double?) -> Double? {
        guard let before, let after else { return nil }
        return after - before
    }
}
