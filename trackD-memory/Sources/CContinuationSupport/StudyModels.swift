import Foundation
import InformationCore
import RelationCore

public enum Arm: String, Codable, Sendable, CaseIterable {
    case a = "C-A"
    case b = "C-B"
    case c = "C-C"

    public var informationEnabled: Bool { self != .a }
    public var relationEnabled: Bool { self == .c }
}

public struct ExecutionState: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var taskID: String
    public var lifecyclePhase: String
    public var attemptCount: Int
    public var carrierPointers: [String: String]
    public var runID: String
    public var executorIdentity: String

    public init(
        taskID: String,
        lifecyclePhase: String,
        attemptCount: Int = 0,
        carrierPointers: [String: String] = [:],
        runID: String,
        executorIdentity: String
    ) {
        self.schemaVersion = "c-impl-execution-state-v2"
        self.taskID = taskID
        self.lifecyclePhase = lifecyclePhase
        self.attemptCount = attemptCount
        self.carrierPointers = carrierPointers
        self.runID = runID
        self.executorIdentity = executorIdentity
    }

    public func validate(for arm: Arm) throws {
        let keys = Set(carrierPointers.keys)
        switch arm {
        case .a:
            guard keys.isEmpty else { throw StudyError.invalidState("C-A carrier pointers must be empty") }
        case .b:
            guard keys == ["task", "s0", "s1", "progress"] else {
                throw StudyError.invalidState("C-B carrier pointer set is invalid")
            }
        case .c:
            guard keys == ["task", "s0", "s1", "progress", "relation"] else {
                throw StudyError.invalidState("C-C carrier pointer set is invalid")
            }
        }
    }
}

public struct EntitySnapshot: Codable, Equatable, Sendable {
    public var entity: String
    public var alpha: Int
    public var mode: String

    public init(entity: String, alpha: Int, mode: String) {
        self.entity = entity
        self.alpha = alpha
        self.mode = mode
    }

    public var display: String { "alpha=\(alpha);mode=\(mode)" }

    public static func directionalChange(before: EntitySnapshot, after: EntitySnapshot) -> String? {
        guard before != after else { return nil }
        return "changed=true;before=\(before.display);after=\(after.display)"
    }
}

public struct ContinuationRule: Codable, Equatable, Sendable {
    public var alphaMinimum: Int
    public var requiredMode: String
    public var action: String

    public init(alphaMinimum: Int, requiredMode: String, action: String) {
        self.alphaMinimum = alphaMinimum
        self.requiredMode = requiredMode
        self.action = action
    }

    public func action(for snapshot: EntitySnapshot) -> String {
        snapshot.alpha >= alphaMinimum && snapshot.mode == requiredMode ? action : "WAIT_FOR_CHANGE"
    }
}

public struct TaskCharter: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var taskID: String
    public var objective: String
    public var continuationRule: ContinuationRule

    public init(
        schemaVersion: String,
        taskID: String,
        objective: String,
        continuationRule: ContinuationRule
    ) {
        self.schemaVersion = schemaVersion
        self.taskID = taskID
        self.objective = objective
        self.continuationRule = continuationRule
    }
}

public struct ContinuationReport: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var taskID: String
    public var beforeState: String?
    public var afterState: String?
    public var directionalChange: String?
    public var nextAction: String?
    public var blocker: String
    public var sourceLegality: Bool

    public init(
        schemaVersion: String,
        taskID: String,
        beforeState: String?,
        afterState: String?,
        directionalChange: String?,
        nextAction: String?,
        blocker: String,
        sourceLegality: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.taskID = taskID
        self.beforeState = beforeState
        self.afterState = afterState
        self.directionalChange = directionalChange
        self.nextAction = nextAction
        self.blocker = blocker
        self.sourceLegality = sourceLegality
    }
}

public struct CarrierRead: Codable, Equatable, Sendable {
    public var sequence: Int
    public var carrier: String
    public var identity: String
    public var method: String
    public var found: Bool

    public init(sequence: Int, carrier: String, identity: String, method: String, found: Bool) {
        self.sequence = sequence
        self.carrier = carrier
        self.identity = identity
        self.method = method
        self.found = found
    }
}

public struct AuditObservation: Codable, Equatable, Sendable {
    public var check: String
    public var method: String
    public var observed: String
    public var passed: Bool

    public init(check: String, method: String, observed: String, passed: Bool) {
        self.check = check
        self.method = method
        self.observed = observed
        self.passed = passed
    }
}

public struct InvocationEvidence: Codable, Equatable, Sendable {
    public var command: String
    public var arm: Arm
    public var root: String
    public var processID: Int32
    public var parentProcessID: Int32
    public var arguments: [String]
    public var workingDirectory: String
    public var environmentNames: [String]
    public var declaredEnvironmentValues: [String: String]
    public var timestamp: Date

    public init(
        command: String,
        arm: Arm,
        root: String,
        processID: Int32,
        parentProcessID: Int32,
        arguments: [String],
        workingDirectory: String,
        environmentNames: [String],
        declaredEnvironmentValues: [String: String],
        timestamp: Date
    ) {
        self.command = command
        self.arm = arm
        self.root = root
        self.processID = processID
        self.parentProcessID = parentProcessID
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environmentNames = environmentNames
        self.declaredEnvironmentValues = declaredEnvironmentValues
        self.timestamp = timestamp
    }
}

public struct Evidence: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var invocation: InvocationEvidence
    public var declaredReadPaths: [String]
    public var carrierReads: [CarrierRead]
    public var persistenceSources: [String]
    public var sourceLegality: Bool
    public var auditObservations: [AuditObservation]

    public init(
        schemaVersion: String,
        invocation: InvocationEvidence,
        declaredReadPaths: [String],
        carrierReads: [CarrierRead],
        persistenceSources: [String],
        sourceLegality: Bool,
        auditObservations: [AuditObservation]
    ) {
        self.schemaVersion = schemaVersion
        self.invocation = invocation
        self.declaredReadPaths = declaredReadPaths
        self.carrierReads = carrierReads
        self.persistenceSources = persistenceSources
        self.sourceLegality = sourceLegality
        self.auditObservations = auditObservations
    }
}

public struct PhysicalChangeEvidence: Codable, Equatable, Sendable {
    public var sourcePath: String
    public var overwriteReference: String
    public var beforeSHA256: String
    public var afterSHA256: String
    public var declaredAt: Date
    public var observedAt: Date

    public init(
        sourcePath: String,
        overwriteReference: String,
        beforeSHA256: String,
        afterSHA256: String,
        declaredAt: Date,
        observedAt: Date
    ) {
        self.sourcePath = sourcePath
        self.overwriteReference = overwriteReference
        self.beforeSHA256 = beforeSHA256
        self.afterSHA256 = afterSHA256
        self.declaredAt = declaredAt
        self.observedAt = observedAt
    }
}

public struct ProcessMarker: Codable, Equatable, Sendable {
    public var phase: String
    public var pid: Int32
    public var timestamp: Date

    public init(phase: String, pid: Int32, timestamp: Date) {
        self.phase = phase
        self.pid = pid
        self.timestamp = timestamp
    }
}

public enum StudyError: Error, CustomStringConvertible {
    case argument(String)
    case invalidState(String)

    public var description: String {
        switch self {
        case .argument(let value): return "argument error: \(value)"
        case .invalidState(let value): return "invalid state: \(value)"
        }
    }
}

public enum StudyPaths {
    public static func checkpoint(_ root: URL) -> URL { root.appendingPathComponent("execution-state.json") }
    public static func information(_ root: URL) -> URL { root.appendingPathComponent("information.sqlite") }
    public static func relation(_ root: URL) -> URL { root.appendingPathComponent("relation.json") }
    public static func evidence(_ root: URL) -> URL { root.appendingPathComponent("invocation-evidence.jsonl") }
    public static func continuationEvidence(_ root: URL) -> URL { root.appendingPathComponent("continuation-evidence.json") }
    public static func awaitingMarker(_ root: URL) -> URL { root.appendingPathComponent("awaiting-external-overwrite.json") }
    public static func terminationMarker(_ root: URL) -> URL { root.appendingPathComponent("old-process-terminated.json") }
    public static func freshProcessMarker(_ root: URL) -> URL { root.appendingPathComponent("fresh-process-started.json") }
    public static func physicalChange(_ root: URL) -> URL { root.appendingPathComponent("physical-change-evidence.json") }
    public static func report(_ root: URL) -> URL { root.appendingPathComponent("continuation-report.json") }
}

public enum StudyJSON {
    public static var timestamp: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    public static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp.string(from: date))
        }
        return try encoder.encode(value)
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try read(type, from: Data(contentsOf: url))
    }

    public static func read<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = timestamp.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid timestamp")
            }
            return date
        }
        return try decoder.decode(type, from: data)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data(value).write(to: url, options: .atomic)
    }

    public static func appendLine<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let line = try data(value) + Data([0x0a])
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }
}

public struct StoredRelation: Codable, Equatable, Sendable {
    public var subject: String
    public var predicate: String
    public var object: String
    public var producedAt: Date
    public var producedBy: String
    public var source: String?
    public var extractionMode: String?

    public init(_ relation: Relation) {
        subject = relation.subject.rawValue
        predicate = relation.predicate.value
        object = relation.object.rawValue
        producedAt = relation.provenance.producedAt
        producedBy = relation.provenance.producedBy
        source = relation.provenance.source
        extractionMode = relation.provenance.extractionMode
    }

    public var relation: Relation {
        Relation(
            identity: RelationMinter.makeRelationID(
                subject: InformationID(rawValue: subject),
                predicate: RelationPredicate(value: predicate),
                object: InformationID(rawValue: object)
            ),
            subject: InformationID(rawValue: subject),
            predicate: RelationPredicate(value: predicate),
            object: InformationID(rawValue: object),
            provenance: Provenance(
                producedAt: producedAt,
                producedBy: producedBy,
                source: source,
                extractionMode: extractionMode
            )
        )
    }
}

public final class RelationFileStore: RelationStore {
    private let url: URL
    private var records: [String: StoredRelation]

    public init(path: URL) throws {
        self.url = path
        records = FileManager.default.fileExists(atPath: path.path)
            ? try StudyJSON.read([String: StoredRelation].self, from: path)
            : [:]
    }

    public func store(_ relation: Relation) throws {
        let key = relation.identity.rawValue
        guard records[key] == nil else { return }
        records[key] = StoredRelation(relation)
        try StudyJSON.write(records, to: url)
    }

    public func fetch(by identity: RelationID) throws -> Relation? {
        records[identity.rawValue]?.relation
    }
}
