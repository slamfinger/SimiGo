import Foundation
import MLX

/// O3-C″ component 1: tensor-level Safetensors reader.
///
/// Route D's minimal I/O primitive: index each shard's header once
/// (tensor → file → absolute data offset → dtype/shape), then read ONLY the
/// requested tensor payload via seek+read. Replaces shard-granular
/// `loadArraysAndMetadata` where materialization must not read whole shards.
public struct PerTensorLocation: Sendable {
    public let name: String
    public let file: String
    public let absoluteDataOffset: Int64
    public let dtype: String
    public let shape: [Int]
    public let byteCount: Int64
}

public final class PerTensorSafetensorsReader: @unchecked Sendable {
    public enum ReaderError: Error, Equatable, Sendable {
        case invalidSafetensorsHeader(String)
        case unknownTensor(String)
        case unsupportedDType(String)
        case shortRead(String, expected: Int, actual: Int)
    }

    public let locations: [String: PerTensorLocation]
    private let modelDirectory: URL

    public init(modelDirectory: URL, weightMap: [String: String]) throws {
        self.modelDirectory = modelDirectory
        var locations: [String: PerTensorLocation] = [:]

        for file in Set(weightMap.values) {
            let url = modelDirectory.appendingPathComponent(file)
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }

            let lengthData = try fileHandle.read(upToCount: 8) ?? Data()
            guard lengthData.count == 8 else {
                throw ReaderError.invalidSafetensorsHeader(url.path)
            }
            let length = lengthData.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 0, as: UInt64.self).littleEndian
            }
            let headerData = try fileHandle.read(upToCount: Int(length)) ?? Data()
            guard headerData.count == Int(length),
                let headerObject = try JSONSerialization.jsonObject(
                    with: headerData, options: [.fragmentsAllowed]
                ) as? [String: Any]
            else {
                throw ReaderError.invalidSafetensorsHeader(url.path)
            }

            for (name, value) in headerObject {
                guard name != "__metadata__",
                    let entry = value as? [String: Any],
                    let dtype = entry["dtype"] as? String,
                    let shapeObject = entry["shape"] as? [Any],
                    let offsets = entry["data_offsets"] as? [Any],
                    offsets.count == 2,
                    let start = Self.int(of: offsets[0]),
                    let end = Self.int(of: offsets[1])
                else { continue }

                locations[name] = PerTensorLocation(
                    name: name,
                    file: file,
                    absoluteDataOffset: Int64(8 + length) + Int64(start),
                    dtype: dtype,
                    shape: shapeObject.compactMap(Self.int),
                    byteCount: Int64(end - start)
                )
            }
        }
        self.locations = locations
    }

    /// Read exactly one tensor payload and construct the MLXArray.
    public func loadTensor(named name: String) throws -> MLXArray {
        guard let location = locations[name] else {
            throw ReaderError.unknownTensor(name)
        }
        let url = modelDirectory.appendingPathComponent(location.file)
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        try fileHandle.seek(toOffset: UInt64(location.absoluteDataOffset))
        let data = try fileHandle.read(upToCount: Int(location.byteCount)) ?? Data()
        guard data.count == Int(location.byteCount) else {
            throw ReaderError.shortRead(
                name, expected: Int(location.byteCount), actual: data.count
            )
        }

        return try Self.makeArray(data: data, dtype: location.dtype, shape: location.shape, name: name)
    }

    // MARK: - dtype construction

    static func makeArray(
        data: Data, dtype: String, shape: [Int], name: String
    ) throws -> MLXArray {
        func leValues<T: FixedWidthInteger>(_ type: T.Type) -> [T] {
            let stride = MemoryLayout<T>.stride
            let count = data.count / stride
            return data.withUnsafeBytes { raw in
                (0..<count).map { offset in
                    T(littleEndian: raw.loadUnaligned(
                        fromByteOffset: offset * stride, as: T.self))
                }
            }
        }

        switch dtype {
        case "F32":
            let values: [Float] = leValues(UInt32.self).map { Float(bitPattern: $0) }
            return MLXArray(values, shape)
        case "F64":
            let values: [Double] = leValues(UInt64.self).map { Double(bitPattern: $0) }
            return MLXArray(values, shape)
        case "F16":
            let values: [Float16] = leValues(UInt16.self).map { Float16(bitPattern: $0) }
            return MLXArray(values, shape)
        case "BF16":
            return MLXArray(leValues(UInt16.self), shape).asType(.bfloat16)
        case "U32":
            return MLXArray(leValues(UInt32.self), shape)
        case "I32":
            return MLXArray(leValues(Int32.self), shape)
        case "I64":
            return MLXArray(leValues(Int64.self), shape)
        case "U8":
            return MLXArray(Array(data), shape)
        case "I8":
            let values: [Int8] = data.map { Int8(bitPattern: $0) }
            return MLXArray(values, shape)
        default:
            throw ReaderError.unsupportedDType("\(name): \(dtype)")
        }
    }

    static func int(of value: Any) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}
