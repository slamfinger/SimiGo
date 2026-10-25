import Foundation

public struct LayerDemandExperimentRunner: Sendable {
    public init() {}

    public func validate(manifest: LayerDemandExperimentManifest, samples: [LayerDemandSample]) throws {
        guard !manifest.experimentID.isEmpty else {
            throw LayerDemandExperimentError.invalidManifest("experimentID is empty")
        }
        guard !manifest.modelID.isEmpty else {
            throw LayerDemandExperimentError.invalidManifest("modelID is empty")
        }
        guard !manifest.checkpointHash.isEmpty else {
            throw LayerDemandExperimentError.invalidManifest("checkpointHash is empty")
        }
        guard !manifest.groups.isEmpty else {
            throw LayerDemandExperimentError.invalidManifest("no experiment groups")
        }

        var sampleIDs = Set<String>()
        for sample in samples {
            guard sample.experimentID == manifest.experimentID else {
                throw LayerDemandExperimentError.invalidSample(sample.sampleID, "experimentID mismatch")
            }
            guard sampleIDs.insert(sample.sampleID).inserted else {
                throw LayerDemandExperimentError.invalidSample(sample.sampleID, "duplicate sampleID")
            }
            guard !sample.category.isEmpty, !sample.taskForm.isEmpty else {
                throw LayerDemandExperimentError.invalidSample(sample.sampleID, "category/taskForm is empty")
            }
        }

        var groupIDs = Set<String>()
        for group in manifest.groups {
            guard groupIDs.insert(group.id).inserted else {
                throw LayerDemandExperimentError.invalidManifest("duplicate groupID: (group.id)")
            }
            guard group.byteCount >= 0 else {
                throw LayerDemandExperimentError.invalidManifest("negative byteCount: (group.id)")
            }
        }
    }

    public func validateObservation(
        _ observation: LayerDemandObservation,
        manifest: LayerDemandExperimentManifest,
        sampleIDs: Set<String>
    ) throws {
        guard observation.experimentID == manifest.experimentID else {
            throw LayerDemandExperimentError.invalidObservation(observation.sampleID, "experimentID mismatch")
        }
        guard sampleIDs.contains(observation.sampleID) else {
            throw LayerDemandExperimentError.invalidObservation(observation.sampleID, "unknown sampleID")
        }
        guard manifest.groups.contains(where: { $0.id == observation.groupID }) else {
            throw LayerDemandExperimentError.invalidObservation(observation.sampleID, "unknown groupID")
        }
        if let value = observation.demandMetric, !value.isFinite {
            throw LayerDemandExperimentError.invalidObservation(observation.sampleID, "non-finite demandMetric")
        }
        if !observation.restored {
            throw LayerDemandExperimentError.invalidObservation(observation.sampleID, "observation was not restored")
        }
    }

    public func encodeJSONL(_ record: LayerDemandRunRecord) throws -> (manifest: Data, samples: Data, observations: Data) {
        try validate(manifest: record.manifest, samples: record.samples)
        let sampleIDs = Set(record.samples.map { $0.sampleID })
        for observation in record.observations {
            try validateObservation(observation, manifest: record.manifest, sampleIDs: sampleIDs)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (
            try encoder.encode(record.manifest),
            try LayerDemandJSONL.encode(record.samples),
            try LayerDemandJSONL.encode(record.observations)
        )
    }
}

public enum LayerDemandExperimentError: Error, Equatable, Sendable {
    case invalidManifest(String)
    case invalidSample(String, String)
    case invalidObservation(String, String)
}
