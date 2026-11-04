import Foundation

public struct TensorEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let file: String
    public let fileURL: URL
    public let absoluteDataOffset: Int64
    public let dtype: String
    public let shape: [Int]
    public let byteCount: Int64

    public var absoluteByteRange: Range<Int64> {
        absoluteDataOffset..<(absoluteDataOffset + byteCount)
    }

    public var components: [String] {
        id.split(separator: ".").map(String.init)
    }

    public var decoderLayer: Int? {
        guard let index = components.firstIndex(of: "layers"),
              index + 1 < components.count,
              let layer = Int(components[index + 1]) else {
            return nil
        }
        return layer
    }

    public var isSwitchMLP: Bool {
        components.contains("switch_mlp")
    }

    public var isDenseMLP: Bool {
        components.contains("mlp") && !isSwitchMLP
    }

    public init(
        id: String,
        file: String,
        fileURL: URL = URL(fileURLWithPath: "/dev/null"),
        absoluteDataOffset: Int64 = 0,
        dtype: String,
        shape: [Int],
        byteCount: Int64
    ) {
        self.id = id
        self.file = file
        self.fileURL = fileURL
        self.absoluteDataOffset = absoluteDataOffset
        self.dtype = dtype
        self.shape = shape
        self.byteCount = byteCount
    }
}

public struct LayerGroup: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let layerRangeDescription: String
    public let tensorCount: Int
    public let byteCount: Int64
    public let alwaysResident: Bool

    public init(
        id: String,
        title: String,
        layerRangeDescription: String,
        tensorCount: Int,
        byteCount: Int64,
        alwaysResident: Bool = false
    ) {
        self.id = id
        self.title = title
        self.layerRangeDescription = layerRangeDescription
        self.tensorCount = tensorCount
        self.byteCount = byteCount
        self.alwaysResident = alwaysResident
    }

    public var mebibytes: Double {
        Double(byteCount) / (1024 * 1024)
    }
}

public struct LayerInventory: Sendable {
    public let groups: [LayerGroup]
    public let tensors: [TensorEntry]
    public let totalByteCount: Int64

    public func group(withID id: String) -> LayerGroup? {
        groups.first { $0.id == id }
    }
}
