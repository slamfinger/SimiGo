import Foundation

public struct GroupMaterializationReport: Codable, Hashable, Sendable {
    public let groupID: String
    public let tensorCount: Int
    public let byteCount: Int64
    public let elapsedMilliseconds: Double
    public let throughputMiBsPerSecond: Double
}

public struct StateMaterializationReport: Codable, Hashable, Sendable {
    public let executionState: ExecutionStateLabel
    public let loadedGroupIDs: Set<String>
    public let evictedGroupIDs: Set<String>
    public let residentGroupIDs: Set<String>
    public let reports: [GroupMaterializationReport]
    public let loadedBytes: Int64
    public let elapsedMilliseconds: Double
    public let throughputMiBsPerSecond: Double
}

public struct MaterializationExperimentReport: Codable, Hashable, Sendable {
    public let modelDirectory: String
    public let states: [ExecutionStateLabel]
    public let reports: [StateMaterializationReport]
    public let loadedBytes: Int64
    public let elapsedMilliseconds: Double
    public let averageThroughputMiBsPerSecond: Double
}

/// Pure-Swift, selective Safetensors materializer.
/// It reads only tensors selected by the execution-state policy; it does not decode
/// tensors, modify MLX internals, or execute model inference.
public struct SafetensorsGroupMaterializer: Sendable {
    public let modelDirectory: URL
    public let inventory: LayerInventory

    public init(modelDirectory: URL, inventory: LayerInventory) {
        self.modelDirectory = modelDirectory
        self.inventory = inventory
    }

    public func materialize(groups groupIDs: Set<String>) throws -> [GroupMaterializationReport] {
        let tensorsByGroup = Dictionary(
            uniqueKeysWithValues: inventory.groups.map { ($0.id, $0) }
        )

        var reports: [GroupMaterializationReport] = []
        for groupID in groupIDs.sorted() {
            guard let group = tensorsByGroup[groupID] else {
                throw LayerResidencyError.unknownLayerGroup(groupID)
            }

            let selectedTensors = inventory.tensors
                .filter { tensor in groupContains(tensor: tensor, group: group.id) }
                .sorted { $0.absoluteDataOffset < $1.absoluteDataOffset }

            let clock = ContinuousClock()
            let elapsed = try clock.measure {
                var tensorsByFile: [URL: [TensorEntry]] = [:]
                for tensor in selectedTensors {
                    tensorsByFile[tensor.fileURL, default: []].append(tensor)
                }

                for (fileURL, tensors) in tensorsByFile {
                    let handle = try FileHandle(forReadingFrom: fileURL)
                    defer { try? handle.close() }

                    for tensor in tensors.sorted(by: { $0.absoluteDataOffset < $1.absoluteDataOffset }) {
                        try handle.seek(toOffset: UInt64(tensor.absoluteDataOffset))
                        let data = try handle.read(upToCount: Int(tensor.byteCount))
                        guard let data, data.count == Int(tensor.byteCount) else {
                            throw LayerResidencyError.shortTensorRead(
                                tensor.id,
                                expected: Int(tensor.byteCount),
                                actual: data?.count ?? 0
                            )
                        }
                        // FileHandle.read has materialized tensor bytes from storage.
                        // Touch only small samples; a full checksum would turn this into
                        // a CPU benchmark instead of a residency/read experiment.
                        _ = data.prefix(64).first
                        _ = data.suffix(64).last
                    }
                }
            }

            let elapsedMilliseconds = durationMilliseconds(elapsed)
            let throughput = throughputMiBs(
                bytes: group.byteCount,
                milliseconds: elapsedMilliseconds
            )

            reports.append(
                GroupMaterializationReport(
                    groupID: groupID,
                    tensorCount: group.tensorCount,
                    byteCount: group.byteCount,
                    elapsedMilliseconds: elapsedMilliseconds,
                    throughputMiBsPerSecond: throughput
                )
            )
        }

        return reports
    }

    public func materializeStateTransition(
        currentState: ExecutionStateLabel,
        newlyLoadedGroupIDs: Set<String>
    ) throws -> StateMaterializationReport {
        let reports = try materialize(groups: newlyLoadedGroupIDs)
        let loadedBytes = reports.reduce(Int64(0)) { $0 + $1.byteCount }
        let throughput = throughputMiBs(
            bytes: loadedBytes,
            milliseconds: reports.reduce(0) { $0 + $1.elapsedMilliseconds }
        )

        return StateMaterializationReport(
            executionState: currentState,
            loadedGroupIDs: newlyLoadedGroupIDs,
            evictedGroupIDs: [],
            residentGroupIDs: [],
            reports: reports,
            loadedBytes: loadedBytes,
            elapsedMilliseconds: reports.reduce(0) { $0 + $1.elapsedMilliseconds },
            throughputMiBsPerSecond: throughput
        )
    }

    private func groupContains(tensor: TensorEntry, group: String) -> Bool {
        switch group {
        case "CORE_NON_SWITCH": return !tensor.isSwitchMLP
        case "SWITCH_MLP_L00_15": return tensor.isSwitchMLP && (tensor.decoderLayer ?? -1) <= 15
        case "SWITCH_MLP_L16_31":
            let layer = tensor.decoderLayer ?? -1
            return tensor.isSwitchMLP && layer >= 16 && layer <= 31
        case "SWITCH_MLP_L32_47": return tensor.isSwitchMLP && (tensor.decoderLayer ?? -1) >= 32
        default: return false
        }
    }

    private func durationMilliseconds(_ duration: ContinuousClock.Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }

    private func throughputMiBs(bytes: Int64, milliseconds: Double) -> Double {
        guard milliseconds > 0 else { return 0 }
        return (Double(bytes) / (1024 * 1024)) / (milliseconds / 1000)
    }
}
