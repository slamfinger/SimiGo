import Foundation

public struct LayerDemandExperimentManifest: Codable, Hashable, Sendable {
    public let experimentID: String
    public let protocolVersion: String
    public let datasetVersion: String
    public let modelID: String
    public let checkpointHash: String
    public let runtime: RuntimeMetadata
    public let groups: [ExperimentGroup]
    public let createdAt: String

    public init(
        experimentID: String,
        protocolVersion: String = "0.1",
        datasetVersion: String,
        modelID: String,
        checkpointHash: String,
        runtime: RuntimeMetadata,
        groups: [ExperimentGroup],
        createdAt: String
    ) {
        self.experimentID = experimentID
        self.protocolVersion = protocolVersion
        self.datasetVersion = datasetVersion
        self.modelID = modelID
        self.checkpointHash = checkpointHash
        self.runtime = runtime
        self.groups = groups
        self.createdAt = createdAt
    }
}

public struct RuntimeMetadata: Codable, Hashable, Sendable {
    public let hardware: String
    public let os: String
    public let swiftVersion: String
    public let mlxVersion: String

    public init(hardware: String, os: String, swiftVersion: String, mlxVersion: String) {
        self.hardware = hardware
        self.os = os
        self.swiftVersion = swiftVersion
        self.mlxVersion = mlxVersion
    }
}

public struct ExperimentGroup: Codable, Hashable, Sendable {
    public let id: String
    public let layerStart: Int?
    public let layerEnd: Int?
    public let byteCount: Int64
    public let alwaysResident: Bool

    public init(id: String, layerStart: Int?, layerEnd: Int?, byteCount: Int64, alwaysResident: Bool) {
        self.id = id
        self.layerStart = layerStart
        self.layerEnd = layerEnd
        self.byteCount = byteCount
        self.alwaysResident = alwaysResident
    }
}

public struct LayerDemandSample: Codable, Hashable, Sendable {
    public let experimentID: String
    public let sampleID: String
    public let category: String
    public let taskForm: String
    public let lengthBucket: String
    public let promptHash: String
    public let promptText: String

    public init(
        experimentID: String,
        sampleID: String,
        category: String,
        taskForm: String,
        lengthBucket: String,
        promptHash: String,
        promptText: String
    ) {
        self.experimentID = experimentID
        self.sampleID = sampleID
        self.category = category
        self.taskForm = taskForm
        self.lengthBucket = lengthBucket
        self.promptHash = promptHash
        self.promptText = promptText
    }
}

public enum DemandEvidenceKind: String, Codable, Hashable, Sendable {
    case representation = "D_REP"
    case ablation = "D_ABL"
    case execution = "D_EXEC"
}

public struct LayerDemandObservation: Codable, Hashable, Sendable {
    public let experimentID: String
    public let sampleID: String
    public let groupID: String
    public let evidenceKind: DemandEvidenceKind
    public let baselineMetric: Double?
    public let interventionMetric: Double?
    public let demandMetric: Double?
    public let runtimeMilliseconds: Double?
    public let restored: Bool
    public let timestamp: String

    public init(
        experimentID: String,
        sampleID: String,
        groupID: String,
        evidenceKind: DemandEvidenceKind,
        baselineMetric: Double?,
        interventionMetric: Double?,
        demandMetric: Double?,
        runtimeMilliseconds: Double?,
        restored: Bool,
        timestamp: String
    ) {
        self.experimentID = experimentID
        self.sampleID = sampleID
        self.groupID = groupID
        self.evidenceKind = evidenceKind
        self.baselineMetric = baselineMetric
        self.interventionMetric = interventionMetric
        self.demandMetric = demandMetric
        self.runtimeMilliseconds = runtimeMilliseconds
        self.restored = restored
        self.timestamp = timestamp
    }
}

public struct LayerDemandRunRecord: Codable, Hashable, Sendable {
    public let manifest: LayerDemandExperimentManifest
    public let samples: [LayerDemandSample]
    public let observations: [LayerDemandObservation]

    public init(
        manifest: LayerDemandExperimentManifest,
        samples: [LayerDemandSample],
        observations: [LayerDemandObservation]
    ) {
        self.manifest = manifest
        self.samples = samples
        self.observations = observations
    }
}

public enum LayerDemandJSONL {
    public static func encode<T: Encodable>(_ values: [T]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try values.map { value in
            let data = try encoder.encode(value)
            return data
        }.reduce(into: Data()) { result, line in
            result.append(line)
            result.append(0x0A)
        }
    }
}
