import Foundation
import MLX
import XCTest
@testable import SimiGo2Experimental

final class PerTensorSafetensorsReaderTests: XCTestCase {
    func testIndexesAndReadsIndividualTensorPayloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-o3-reader-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let header = """
        {"float.weight":{"dtype":"F32","shape":[2],"data_offsets":[0,8]},"packed.weight":{"dtype":"U32","shape":[2],"data_offsets":[8,16]},"__metadata__":{"format":"pt"}}
        """
        let headerData = Data(header.utf8)
        var file = Data()
        var length = UInt64(headerData.count).littleEndian
        withUnsafeBytes(of: &length) { file.append(contentsOf: $0) }
        file.append(headerData)

        var floatValues: [Float32] = [1.0, 2.0]
        floatValues.withUnsafeBytes { file.append(contentsOf: $0) }

        var packedValues: [UInt32] = [0x11223344, 0x55667788]
        packedValues.withUnsafeBytes { file.append(contentsOf: $0) }

        let shard = directory.appendingPathComponent("model-00001.safetensors")
        try file.write(to: shard)

        let reader = try PerTensorSafetensorsReader(
            modelDirectory: directory,
            files: ["model-00001.safetensors"]
        )

        XCTAssertEqual(reader.locations.count, 2)
        XCTAssertEqual(reader.locations["float.weight"]?.dtype, "F32")
        XCTAssertEqual(reader.locations["float.weight"]?.shape, [2])
        XCTAssertEqual(reader.locations["packed.weight"]?.dtype, "U32")
        XCTAssertEqual(reader.locations["packed.weight"]?.absoluteDataOffset,
                       Int64(8 + headerData.count + 0))
        XCTAssertEqual(reader.locations["packed.weight"]?.byteCount, 8)

        let floatArray = try reader.loadTensor(named: "float.weight")
        let packedArray = try reader.loadTensor(named: "packed.weight")
        eval(floatArray, packedArray)

        XCTAssertEqual(floatArray.shape, [2])
        XCTAssertEqual(floatArray.dtype, .float32)
        XCTAssertEqual(floatArray.asArray(Float32.self), [1.0, 2.0])

        XCTAssertEqual(packedArray.shape, [2])
        XCTAssertEqual(packedArray.dtype, .uint32)
        XCTAssertEqual(
            packedArray.asArray(UInt32.self),
            [0x11223344, 0x55667788]
        )
    }

    func testMissingTensorIsExplicit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-o3-reader-missing-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let headerData = Data("{"x":{"dtype":"U32","shape":[1],"data_offsets":[0,4]}}".utf8)
        var file = Data()
        var length = UInt64(headerData.count).littleEndian
        withUnsafeBytes(of: &length) { file.append(contentsOf: $0) }
        file.append(headerData)
        var value = UInt32(7)
        withUnsafeBytes(of: &value) { file.append(contentsOf: $0) }

        try file.write(to: directory.appendingPathComponent("shard.safetensors"))
        let reader = try PerTensorSafetensorsReader(
            modelDirectory: directory,
            files: ["shard.safetensors"]
        )

        XCTAssertThrowsError(try reader.loadTensor(named: "missing"))
    }
}
