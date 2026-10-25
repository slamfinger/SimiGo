import Foundation
import MLX
import MLXLMCommon

public struct MLXLifecycleMemorySample: Codable, Hashable, Sendable {
  public let activeBytes: Int64
  public let cacheBytes: Int64
  public let peakBytes: Int64

  init(snapshot: Memory.Snapshot) {
    activeBytes = Int64(snapshot.activeMemory)
    cacheBytes = Int64(snapshot.cacheMemory)
    peakBytes = Int64(snapshot.peakMemory)
  }
}

public struct MLXGroupLifecycleReport: Codable, Hashable, Sendable {
  public let groupID: String
  public let tensorCount: Int
  public let byteCount: Int64
  public let initialLoadMilliseconds: Double
  public let memoryAfterInitialLoad: MLXLifecycleMemorySample
  public let memoryAfterRelease: MLXLifecycleMemorySample
  public let rematerializeMilliseconds: Double
  public let memoryAfterRematerialize: MLXLifecycleMemorySample
  public let rematerializedTensorCount: Int
  public let rematerializedByteCount: Int64
  public let semanticEqualCount: Int
  public let semanticMismatchCount: Int
  public let lifecyclePass: Bool
}

public enum MLXGroupLifecycleExperiment {
  public static func run(
    modelDirectory: URL,
    inventory: LayerInventory,
    groupID: String
  ) async throws -> MLXGroupLifecycleReport {
    guard inventory.group(withID: groupID) != nil else {
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

    Memory.memoryLimit = max(
      24 * 1024 * 1024 * 1024,
      Memory.memoryLimit
    )

    let clock = ContinuousClock()

    var initial: [String: MLXArray] = [:]
    let initialLoadElapsed = try clock.measure {
      for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let (all, _) = try MLX.loadArraysAndMetadata(url: file, stream: .cpu)
        for (name, array) in all where groupTensorNames.contains(name) {
          initial[name] = array
        }
      }
      eval(Array(initial.values))
    }

    let initialTensorCount = initial.count
    let initialByteCount = try Self.byteCount(initial)
    let baselineFingerprints = try Self.fingerprints(initial)
    let memoryAfterInitialLoad = Memory.snapshot()

    initial.removeAll()
    Memory.clearCache()
    let memoryAfterRelease = Memory.snapshot()

    var rematerialized: [String: MLXArray] = [:]
    let rematerializeElapsed = try clock.measure {
      for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let (all, _) = try MLX.loadArraysAndMetadata(url: file, stream: .cpu)
        for (name, array) in all where groupTensorNames.contains(name) {
          rematerialized[name] = array
        }
      }
      eval(Array(rematerialized.values))
    }

    let rematerializedByteCount = try Self.byteCount(rematerialized)
    let memoryAfterRematerialize = Memory.snapshot()

    let rematerializedFingerprints = try Self.fingerprints(rematerialized)
    let semanticEqualCount = baselineFingerprints.filter { name, fingerprint in
      rematerializedFingerprints[name] == fingerprint
    }.count
    let semanticMismatchCount = baselineFingerprints.count - semanticEqualCount

    let lifecyclePass =
      rematerialized.count == initialTensorCount
      && rematerializedByteCount == initialByteCount
      && semanticMismatchCount == 0

    initial.removeAll()
    rematerialized.removeAll()
    Memory.clearCache()

    return MLXGroupLifecycleReport(
      groupID: groupID,
      tensorCount: initialTensorCount,
      byteCount: initialByteCount,
      initialLoadMilliseconds: durationMilliseconds(initialLoadElapsed),
      memoryAfterInitialLoad: MLXLifecycleMemorySample(snapshot: memoryAfterInitialLoad),
      memoryAfterRelease: MLXLifecycleMemorySample(snapshot: memoryAfterRelease),
      rematerializeMilliseconds: durationMilliseconds(rematerializeElapsed),
      memoryAfterRematerialize: MLXLifecycleMemorySample(snapshot: memoryAfterRematerialize),
      rematerializedTensorCount: rematerialized.count,
      rematerializedByteCount: rematerializedByteCount,
      semanticEqualCount: semanticEqualCount,
      semanticMismatchCount: semanticMismatchCount,
      lifecyclePass: lifecyclePass
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

  private static func fingerprints(_ arrays: [String: MLXArray]) throws -> [String: String] {
    var result: [String: String] = [:]
    for name in arrays.keys.sorted() {
      let array = arrays[name]!
      eval(array)
      let sum = array.sum().item(Float.self)
      let minimum = array.min().item(Float.self)
      let maximum = array.max().item(Float.self)
      result[name] =
        "dtype=\(array.dtype);shape=\(array.shape);sum=\(sum);min=\(minimum);max=\(maximum)"
    }
    return result
  }

  private static func durationMilliseconds(_ duration: ContinuousClock.Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
  }

  private static func byteCount(_ arrays: [String: MLXArray]) throws -> Int64 {
    var total: Int64 = 0
    for (_, array) in arrays {
      let elementCount = array.shape.reduce(1) { $0 * $1 }
      total += Int64(elementCount) * Int64(array.dtype.size)
    }
    eval()
    return total
  }
}
