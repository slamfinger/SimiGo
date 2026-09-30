import Foundation
import MLX
import MLXLMCommon

public struct MLXGroupGateReport: Codable, Hashable, Sendable {
  public let groupID: String
  public let fileCount: Int
  public let tensorCount: Int
  public let byteCount: Int64
    public let elapsedMilliseconds: Double
    public let throughputMiBsPerSecond: Double
    public let materializedShapes: [String]
}

public enum MLXGroupGate {
  public static func materialize(
    modelDirectory: URL,
    inventory: LayerInventory,
    groupID: String
  ) async throws -> MLXGroupGateReport {
    guard let group = inventory.group(withID: groupID) else {
      throw LayerResidencyError.unknownLayerGroup(groupID)
    }

    let groupTensorNames = Set(
      inventory.tensors
        .filter { tensor in groupContains(tensor: tensor, group: groupID) }
        .map(\.id)
    )

    let files = Set(
      inventory.tensors.compactMap { tensor -> URL? in
        guard groupTensorNames.contains(tensor.id) else { return nil }
        return modelDirectory.appendingPathComponent(tensor.file)
      }
    )

    var tensorCount = 0
    var shapes: [String] = []

    let clock = ContinuousClock()
    let elapsed = try clock.measure {
      for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        // MLX's Safetensors loader is lazy. Filter before evaluation so only
        // the selected tensor ranges are materialized.
        let (all, _) = try MLX.loadArraysAndMetadata(url: file, stream: .cpu)
        let selected = all.filter { groupTensorNames.contains($0.key) }
        let arrays = selected.values
        eval(arrays)

        tensorCount += arrays.count
        for (name, array) in selected.sorted(by: { $0.key < $1.key }) {
          shapes.append("\(name):\(array.dtype)=\(array.shape)")
        }
      }
    }

    // This probe only verifies materialization; avoid retaining a 5+ GiB group.
    Memory.clearCache()

    let milliseconds = durationMilliseconds(elapsed)
    return MLXGroupGateReport(
      groupID: groupID,
      fileCount: files.count,
      tensorCount: tensorCount,
      byteCount: group.byteCount,
      elapsedMilliseconds: milliseconds,
      throughputMiBsPerSecond: throughput(
        bytes: group.byteCount,
        milliseconds: milliseconds
      ),
      materializedShapes: shapes
    )
  }

  private static func groupContains(tensor: TensorEntry, group: String) -> Bool {
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

  private static func durationMilliseconds(_ duration: ContinuousClock.Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
  }

  private static func throughput(bytes: Int64, milliseconds: Double) -> Double {
    guard milliseconds > 0 else { return 0 }
    return (Double(bytes) / (1024 * 1024)) / (milliseconds / 1000)
  }
}
