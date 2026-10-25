import Foundation

public enum CarrierCrashPoint: String, Hashable, Sendable, CaseIterable {
    case afterEntityWriteBeforeRegistry
    case afterRegistryBeforeIndex
    case duringLocatorMove
    case duringRelationAppend
    case duringSessionAppend
    case duringIndexRebuild
}

public enum CarrierRecoveryOutcome: String, Hashable, Sendable {
    case complete
    case repaired
    case explicitlyDetached
    case failed
    case unsupported
}

public struct CarrierRecoveryReport: Hashable, Sendable {
    public let point: CarrierCrashPoint
    public let outcome: CarrierRecoveryOutcome
    public let integrityClean: Bool
    public let detail: String

    public init(
        point: CarrierCrashPoint,
        outcome: CarrierRecoveryOutcome,
        integrityClean: Bool,
        detail: String = ""
    ) {
        self.point = point
        self.outcome = outcome
        self.integrityClean = integrityClean
        self.detail = detail
    }

    public var isLawful: Bool {
        switch outcome {
        case .complete, .repaired, .explicitlyDetached:
            return integrityClean
        case .failed, .unsupported:
            return false
        }
    }
}

public protocol CarrierCrashRecoveryTester: Sendable {
    func recoveryReport(for point: CarrierCrashPoint) async throws -> CarrierRecoveryReport
}

public struct CarrierResourceSample: Hashable, Sendable {
    public let label: String
    public let residentBytes: UInt64?
    public let diskReadBytes: UInt64?
    public let diskWrittenBytes: UInt64?
    public let openFileDescriptors: Int?
    public let cpuSeconds: Double?
    public let collectedAt: Date

    public init(
        label: String,
        residentBytes: UInt64? = nil,
        diskReadBytes: UInt64? = nil,
        diskWrittenBytes: UInt64? = nil,
        openFileDescriptors: Int? = nil,
        cpuSeconds: Double? = nil,
        collectedAt: Date = Date()
    ) {
        self.label = label
        self.residentBytes = residentBytes
        self.diskReadBytes = diskReadBytes
        self.diskWrittenBytes = diskWrittenBytes
        self.openFileDescriptors = openFileDescriptors
        self.cpuSeconds = cpuSeconds
        self.collectedAt = collectedAt
    }
}

public protocol CarrierResourceObserver: Sendable {
    func sample(label: String) async throws -> CarrierResourceSample
}

public struct NullCarrierResourceObserver: CarrierResourceObserver {
    public init() {}

    public func sample(label: String) async throws -> CarrierResourceSample {
        CarrierResourceSample(label: label)
    }
}

public struct CarrierResourceDelta: Hashable, Sendable {
    public let label: String
    public let residentBytesDelta: Int64?
    public let diskReadBytesDelta: Int64?
    public let diskWrittenBytesDelta: Int64?
    public let cpuSecondsDelta: Double?

    public init(
        label: String,
        residentBytesDelta: Int64?,
        diskReadBytesDelta: Int64?,
        diskWrittenBytesDelta: Int64?,
        cpuSecondsDelta: Double?
    ) {
        self.label = label
        self.residentBytesDelta = residentBytesDelta
        self.diskReadBytesDelta = diskReadBytesDelta
        self.diskWrittenBytesDelta = diskWrittenBytesDelta
        self.cpuSecondsDelta = cpuSecondsDelta
    }
}
