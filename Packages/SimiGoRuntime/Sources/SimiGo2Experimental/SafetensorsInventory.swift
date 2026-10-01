import Foundation

public enum SafetensorsInventoryReader {
    public static func readModelGroups(modelDirectory: URL) throws -> LayerInventory {
      let configURL = modelDirectory.appendingPathComponent("config.json")
      let config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
      let modelType = config?["model_type"] as? String

      if modelType == "gemma4_unified" {
        let textConfig = config?["text_config"] as? [String: Any]
        let layerCount = (textConfig?["num_hidden_layers"] as? NSNumber)?.intValue ?? 0
        return try readIndex(modelDirectory: modelDirectory) {
          LayerGroupCatalog.denseMLPGroups(from: $0, layerCount: layerCount)
        }
      }
      if modelType == "muse_glimmer_text" || modelType == "muse_glimmer" {
        let layerCount = (config?["num_hidden_layers"] as? NSNumber)?.intValue ?? 0
        return try readIndex(modelDirectory: modelDirectory) {
          LayerGroupCatalog.denseMLPGroups(from: $0, layerCount: layerCount)
        }
      }
      return try readQwen3CoderGroups(modelDirectory: modelDirectory)
    }

    public static func readQwen3CoderGroups(modelDirectory: URL) throws -> LayerInventory {
      return try readIndex(modelDirectory: modelDirectory) {
        LayerGroupCatalog.qwen3CoderGroups(from: $0)
      }
    }

    private static func readIndex(
      modelDirectory: URL,
      catalog: ([TensorEntry]) throws -> LayerInventory
    ) throws -> LayerInventory {
      let indexURL = modelDirectory.appendingPathComponent("model.safetensors.index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw LayerResidencyError.missingModelIndexOfFile(indexURL.path)
        }

        let indexData = try Data(contentsOf: indexURL)
        let object = try JSONSerialization.jsonObject(with: indexData, options: [.fragmentsAllowed])
        guard let index = object as? [String: Any],
              let weightMap = index["weight_map"] as? [String: String] else {
            throw LayerResidencyError.invalidSafetensorsHeader(indexURL.path)
        }

        var tensors: [TensorEntry] = []
        tensors.reserveCapacity(weightMap.count)

        for (name, fileName) in weightMap {
            let entry = try readTensorEntry(name: name, fileURL: modelDirectory.appendingPathComponent(fileName))
            tensors.append(entry)
        }

        return try catalog(tensors.sorted { $0.id < $1.id })
    }

    private static func readTensorEntry(name: String, fileURL: URL) throws -> TensorEntry {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        let lengthData = try fileHandle.read(upToCount: 8) ?? Data()
        guard lengthData.count == 8 else {
            throw LayerResidencyError.invalidSafetensorsHeader(fileURL.path)
        }

        let length = lengthData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 0, as: UInt64.self).littleEndian
        }

        let headerData = try fileHandle.read(upToCount: Int(length)) ?? Data()
        guard headerData.count == Int(length) else {
            throw LayerResidencyError.invalidSafetensorsHeader(fileURL.path)
        }

        let headerObject = try JSONSerialization.jsonObject(with: headerData, options: [.fragmentsAllowed])
        guard let header = headerObject as? [String: Any],
              let entryObject = header[name] as? [String: Any],
              let dtype = entryObject["dtype"] as? String,
              let shapeObject = entryObject["shape"] as? [Any],
              let offsetsObject = entryObject["data_offsets"] as? [Any],
              offsetsObject.count == 2,
              let start = numberOfInt(offsetsObject[0]),
              let end = numberOfInt(offsetsObject[1]) else {
            throw LayerResidencyError.invalidTensorEntry(name)
        }

        let shape = shapeObject.compactMap(numberOfInt)

        let absoluteOffset = Int64(8 + length) + Int64(start)

        return TensorEntry(
            id: name,
            file: fileURL.lastPathComponent,
            fileURL: fileURL,
            absoluteDataOffset: absoluteOffset,
            dtype: dtype,
            shape: shape,
            byteCount: Int64(end - start)
        )
    }

    private static func numberOfInt(_ value: Any) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}

public enum LayerGroupCatalog {
    public static func denseMLPGroups(
        from tensors: [TensorEntry],
        layerCount: Int
    ) -> LayerInventory {
        let core = tensors.filter { !$0.isDenseMLP }
        let mlpTensors = tensors.filter { $0.isDenseMLP }
        let groupSize = Int(ceil(Double(layerCount) / 3))

        func selectedTensors(_ lower: Int, _ upper: Int) -> [TensorEntry] {
            mlpTensors.filter { tensor in
                guard let layer = tensor.decoderLayer else { return false }
                return layer >= lower && layer <= upper
            }
        }

        func makeDenseGroup(_ lower: Int, _ upper: Int) -> LayerGroup {
            makeGroup(
                id: "DENSE_MLP_L\(String(format: "%02d", lower))_\(String(format: "%02d", upper))",
                title: "Dense MLP layers \(lower)-\(upper)",
                range: "\(lower)-\(upper)",
                tensors: selectedTensors(lower, upper)
            )
        }

        let upper = layerCount - 1
        let groups = [
            makeGroup(
                id: "CORE_NON_SWITCH",
                title: "Non-MLP tensors",
                range: "all",
                tensors: core,
                alwaysResident: true
            ),
            makeDenseGroup(0, min(groupSize - 1, upper)),
            makeDenseGroup(groupSize, min(2 * groupSize - 1, upper)),
            makeDenseGroup(2 * groupSize, upper),
        ]

        return LayerInventory(
            groups: groups,
            tensors: tensors,
            totalByteCount: tensors.reduce(0) { $0 + $1.byteCount }
        )
    }

    public static func qwen3CoderGroups(from tensors: [TensorEntry]) -> LayerInventory {
        let core = tensors.filter { !$0.isSwitchMLP }
        let switchTensors = tensors.filter { $0.isSwitchMLP }

        let groups = [
            makeGroup(
                id: "CORE_NON_SWITCH",
                title: "Non-switch tensors",
                range: "all",
                tensors: core,
                alwaysResident: true
            ),
            makeGroup(
                id: "SWITCH_MLP_L00_15",
                title: "Fused MoE layers 0-15",
                range: "0-15",
                tensors: switchTensors.filter { tensor in
                    (tensor.decoderLayer ?? -1) <= 15
                }
            ),
            makeGroup(
                id: "SWITCH_MLP_L16_31",
                title: "Fused MoE layers 16-31",
                range: "16-31",
                tensors: switchTensors.filter { tensor in
                    let layer = tensor.decoderLayer ?? -1
                    return layer >= 16 && layer <= 31
                }
            ),
            makeGroup(
                id: "SWITCH_MLP_L32_47",
                title: "Fused MoE layers 32-47",
                range: "32-47",
                tensors: switchTensors.filter { tensor in
                    (tensor.decoderLayer ?? -1) >= 32
                }
            )
        ]

        return LayerInventory(
            groups: groups,
            tensors: tensors,
            totalByteCount: tensors.reduce(0) { $0 + $1.byteCount }
        )
    }

    private static func makeGroup(
        id: String,
        title: String,
        range: String,
        tensors: [TensorEntry],
        alwaysResident: Bool = false
    ) -> LayerGroup {
        LayerGroup(
            id: id,
            title: title,
            layerRangeDescription: range,
            tensorCount: tensors.count,
            byteCount: tensors.reduce(0) { $0 + $1.byteCount },
            alwaysResident: alwaysResident
        )
    }
}
