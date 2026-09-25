import Foundation
import MLX

public struct SafetensorsTensorLocation: Sendable, Hashable {
    public let name: String
    public let fileURL: URL
    public let absoluteDataOffset: Int64
    public let byteCount: Int64
    public let dtype: String
    public let shape: [Int]

    public init(
        name: String,
        fileURL: URL,
        absoluteDataOffset: Int64,
        byteCount: Int64,
        dtype: String,
        shape: [Int]
    ) {
        self.name = name
        self.fileURL = fileURL
        self.absoluteDataOffset = absoluteDataOffset
        self.byteCount = byteCount
        self.dtype = dtype
        self.shape = shape
    }
}

public enum PerTensorSafetensorsReaderError: Error, Equatable, Sendable {
    case invalidHeaderLength(URL)
    case invalidHeader(URL)
    case tensorNotFound(String, URL)
    case invalidTensorEntry(String)
    case invalidOffsets(String)
    case integerOverflow(String)
    case unsupportedDType(String)
    case shortRead(String, expected: Int, actual: Int)
}

/// Tensor-level Safetensors reader for Route D.
///
/// The existing MLX shard loader returns every tensor in a shard. This reader
/// keeps only the Safetensors header index resident, seeks directly to one
/// tensor's data_offsets, and constructs exactly that MLXArray. It therefore
/// provides the missing I/O primitive for layer-streaming execution.
public final class PerTensorSafetensorsReader: @unchecked Sendable {
    private let handles: [URL: FileHandle]
    public let locations: [String: SafetensorsTensorLocation]

    public init(modelDirectory: URL, files: Set<String>) throws {
        var handles: [URL: FileHandle] = [:]
        var locations: [String: SafetensorsTensorLocation] = [:]

        for file in files.sorted() {
            let url = modelDirectory.appendingPathComponent(file)
            let handle = try FileHandle(forReadingFrom: url)

            do {
                let prefix = try Self.readExact(handle, count: 8, name: url.path)
                let headerLength = prefix.withUnsafeBytes {
                    $0.loadUnaligned(as: UInt64.self).littleEndian
                }

                guard headerLength <= UInt64(Int.max - 8) else {
                    throw PerTensorSafetensorsReaderError.invalidHeaderLength(url)
                }

                let headerData = try Self.readExact(
                    handle,
                    count: Int(headerLength),
                    name: url.path
                )

                guard let object = try JSONSerialization.jsonObject(with: headerData)
                    as? [String: Any]
                else {
                    throw PerTensorSafetensorsReaderError.invalidHeader(url)
                }

                for (name, raw) in object where name != "__metadata__" {
                    guard
                        let entry = raw as? [String: Any],
                        let dtype = entry["dtype"] as? String,
                        let shapeRaw = entry["shape"] as? [Any],
                        let offsetsRaw = entry["data_offsets"] as? [Any],
                        offsetsRaw.count == 2
                    else {
                        throw PerTensorSafetensorsReaderError.invalidTensorEntry(name)
                    }

                    let shape = try shapeRaw.map {
                        try Self.intValue($0, tensor: name)
                    }
                    let start = try Self.int64Value(offsetsRaw[0], tensor: name)
                    let end = try Self.int64Value(offsetsRaw[1], tensor: name)

                    guard start >= 0, end >= start else {
                        throw PerTensorSafetensorsReaderError.invalidOffsets(name)
                    }

                    let absoluteOffset = Int64(8) + Int64(headerLength) + start

                    locations[name] = SafetensorsTensorLocation(
                        name: name,
                        fileURL: url,
                        absoluteDataOffset: absoluteOffset,
                        byteCount: end - start,
                        dtype: dtype,
                        shape: shape
                    )
                }

                handles[url] = handle
            } catch {
                try? handle.close()
                throw error
            }
        }

        self.handles = handles
        self.locations = locations
    }

    public convenience init(modelDirectory: URL, weightMap: [String: String]) throws {
        try self.init(modelDirectory: modelDirectory, files: Set(weightMap.values))
    }

    deinit {
        handles.values.forEach { try? $0.close() }
    }

    public func location(for tensorName: String) throws -> SafetensorsTensorLocation {
        guard let location = locations[tensorName] else {
            throw PerTensorSafetensorsReaderError.tensorNotFound(
                tensorName,
                URL(fileURLWithPath: "")
            )
        }
        return location
    }

    public func readData(_ location: SafetensorsTensorLocation) throws -> Data {
        guard let handle = handles[location.fileURL] else {
            throw PerTensorSafetensorsReaderError.tensorNotFound(
                location.name,
                location.fileURL
            )
        }

        try handle.seek(toOffset: UInt64(location.absoluteDataOffset))

        let count = Int(location.byteCount)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else {
            throw PerTensorSafetensorsReaderError.shortRead(
                location.name,
                expected: count,
                actual: data.count
            )
        }
        return data
    }

    public func loadTensor(
        named tensorName: String,
        stream: StreamOrDevice = .cpu
    ) throws -> MLXArray {
        let location = try location(for: tensorName)
        let data = try readData(location)

        guard let dtype = Self.dtype(location.dtype) else {
            throw PerTensorSafetensorsReaderError.unsupportedDType(location.dtype)
        }

        _ = stream
        return MLXArray(data, location.shape, dtype: dtype)
    }

    private static func readExact(
        _ handle: FileHandle,
        count: Int,
        name: String
    ) throws -> Data {
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else {
            throw PerTensorSafetensorsReaderError.shortRead(
                name,
                expected: count,
                actual: data.count
            )
        }
        return data
    }

    private static func intValue(_ value: Any, tensor: String) throws -> Int {
        guard let number = value as? NSNumber else {
            throw PerTensorSafetensorsReaderError.integerOverflow(tensor)
        }
        let value = number.int64Value
        guard value >= 0, value <= Int64(Int.max) else {
            throw PerTensorSafetensorsReaderError.integerOverflow(tensor)
        }
        return Int(value)
    }

    private static func int64Value(_ value: Any, tensor: String) throws -> Int64 {
        guard let number = value as? NSNumber else {
            throw PerTensorSafetensorsReaderError.integerOverflow(tensor)
        }
        return number.int64Value
    }

    private static func dtype(_ name: String) -> DType? {
        switch name {
        case "BOOL": return .bool
        case "U8": return .uint8
        case "U16": return .uint16
        case "U32": return .uint32
        case "U64": return .uint64
        case "I8": return .int8
        case "I16": return .int16
        case "I32": return .int32
        case "I64": return .int64
        case "F16": return .float16
        case "BF16": return .bfloat16
        case "F32": return .float32
        case "F64": return .float64
        default: return nil
        }
    }
}
