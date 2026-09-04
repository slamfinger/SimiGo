import Foundation

// MARK: - Detector (Model Detection)

public struct Detector: Sendable {

    /// 检测模型格式并返回 ModelInfo
    nonisolated
    public static func detect(path: String) -> ModelInfo {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false

        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
            fatalError("❌ 模型路径不存在: \(path)")
        }

        // 1. 单个 GGUF 文件
        if !isDirectory.boolValue {
            return detectSingleGGUFFile(path: path, fm: fm)
        }

        // 2. MLX 目录检测
        if let mlxInfo = detectMLX(in: path, fm: fm) {
            return mlxInfo
        }

        // 3. GGUF 目录检测
        if let ggufInfo = detectGGUF(in: path, fm: fm) {
            return ggufInfo
        }

        fatalError("❌ 无法识别的模型架构，目录不包含合法的 MLX 或 GGUF 结构: \(path)")
    }

    // MARK: - GGUF Single File Detection

    nonisolated
    private static func detectSingleGGUFFile(path: String, fm: FileManager) -> ModelInfo {
        let fileURL = URL(fileURLWithPath: path)
        let parentDir = fileURL.deletingLastPathComponent().path
        let draftPath = findDraftModel(in: parentDir, excluding: fileURL.lastPathComponent, fm: fm)
        let mmprojPath = findMMProj(in: parentDir, fm: fm)

        return ModelInfo(
            path: path,
            kind: .gguf,
            mmprojPath: mmprojPath,
            draftModelPath: draftPath
        )
    }

    // MARK: - GGUF Directory Detection

    nonisolated
    private static func detectGGUF(in path: String, fm: FileManager) -> ModelInfo? {
        guard let files = try? fm.contentsOfDirectory(atPath: path) else {
            return nil
        }

        let ggufFiles = files
            .filter { $0.lowercased().hasSuffix(".gguf") }
            .sorted()

        guard !ggufFiles.isEmpty else {
            return nil
        }

        let baseURL = URL(fileURLWithPath: path)
        var mainModelPath: String?
        var draftModelPath: String?
        var mmprojPath: String?

        var normalGGUFPaths: [String] = []

        for file in ggufFiles {
            let fullPath = baseURL.appendingPathComponent(file).path
            let lowerFile = file.lowercased()

            if lowerFile.contains("mmproj") {
                if mmprojPath == nil { mmprojPath = fullPath }
                continue
            }

            if isDFlashModel(file) {
                if draftModelPath == nil {
                    draftModelPath = fullPath
                }
                continue
            }

            if isMTPModel(file) {
                if draftModelPath == nil {
                    draftModelPath = fullPath
                }
                continue
            }

            normalGGUFPaths.append(fullPath)
        }

        if let firstNormal = normalGGUFPaths.first {
            mainModelPath = firstNormal
        }

        guard let modelPath = mainModelPath else {
            if let draft = draftModelPath {
                print("⚠️ GGUF 目录中未检测到普通主模型，检测到的文件为 Draft: \(draft)")
            }
            return nil
        }

        return ModelInfo(
            path: modelPath,
            kind: .gguf,
            mmprojPath: mmprojPath,
            draftModelPath: draftModelPath
        )
    }

    // MARK: - Draft & MMProj Helpers

    nonisolated
    private static func findDraftModel(
        in directory: String,
        excluding mainFileName: String,
        fm: FileManager
    ) -> String? {
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        let ggufFiles = files
            .filter { $0.lowercased().hasSuffix(".gguf") && $0 != mainFileName }
            .sorted()

        if let dflash = ggufFiles.first(where: { isDFlashModel($0) }) {
            return URL(fileURLWithPath: directory).appendingPathComponent(dflash).path
        }

        if let mtp = ggufFiles.first(where: { isMTPModel($0) }) {
            return URL(fileURLWithPath: directory).appendingPathComponent(mtp).path
        }

        return nil
    }

    nonisolated
    private static func findMMProj(in directory: String, fm: FileManager) -> String? {
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        if let mmproj = files.first(where: { $0.lowercased().hasSuffix(".gguf") && $0.lowercased().contains("mmproj") }) {
            return URL(fileURLWithPath: directory).appendingPathComponent(mmproj).path
        }
        return nil
    }

    // MARK: - Model Identification Helpers

    nonisolated
    public static func resolvedModelFileURL(from path: String) -> URL? {
        let fm = FileManager.default
        let inputURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false

        if fm.fileExists(atPath: path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue, inputURL.pathExtension.lowercased() == "gguf" {
                return inputURL
            }
        }

        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return nil }

        let candidates = files
            .filter { $0.lowercased().hasSuffix(".gguf") }
            .filter {
                let lower = $0.lowercased()
                return !lower.contains("mmproj") && !lower.contains("dflash") && !lower.contains("mtp")
            }
            .sorted()

        if let first = candidates.first {
            return URL(fileURLWithPath: path).appendingPathComponent(first)
        }

        let anyGguf = files.filter { $0.lowercased().hasSuffix(".gguf") }.sorted()
        if let first = anyGguf.first {
            return URL(fileURLWithPath: path).appendingPathComponent(first)
        }
        return nil
    }

    nonisolated
    public static func resolvedModelName(from path: String) -> String {
        if let modelURL = resolvedModelFileURL(from: path) {
            let name = modelURL.deletingPathExtension().lastPathComponent
            if !name.isEmpty { return name }
        }
        let fallback = URL(fileURLWithPath: path).lastPathComponent
        return fallback.isEmpty ? "SimiGo-Model" : fallback
    }

    nonisolated
    public static func resolvedRepositoryName(from path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardized.pathComponents

        for component in components {
            let prefix = "models--"
            guard component.hasPrefix(prefix) else { continue }
            let repo = String(component.dropFirst(prefix.count))
            let parts = repo.components(separatedBy: "--")
            guard parts.count >= 2 else { return repo }
            let owner = parts[0]
            let repository = parts.dropFirst().joined(separator: "-")
            return "\(owner)/\(repository)"
        }
        return nil
    }

    // MARK: - Draft Classifier

    nonisolated
    public static func isDFlashModel(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        return lower.hasPrefix("dflash-") || lower.hasPrefix("dflash_") || lower.contains("dflash")
    }

    nonisolated
    public static func isMTPModel(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        if isDFlashModel(fileName) { return false }
        return lower.hasPrefix("mtp-")
            || lower.hasPrefix("mtp_")
            || lower.contains("-mtp-")
            || lower.contains("_mtp")
            || lower.contains("mtp")
    }

    // MARK: - MLX Detection

    nonisolated
    private static func detectMLX(in path: String, fm: FileManager) -> ModelInfo? {
        let baseURL = URL(fileURLWithPath: path)
        let configPath = baseURL.appendingPathComponent("config.json").path
        guard fm.fileExists(atPath: configPath) else { return nil }

        let files = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let hasWeights = files.contains { file in
            let lower = file.lowercased()
            return lower.hasSuffix(".safetensors") || lower.hasSuffix(".bin") || lower.hasSuffix(".weights")
        }

        if hasWeights {
            return ModelInfo(
                path: path,
                kind: .mlx
            )
        }
        return nil
    }

    // MARK: - Utilities & Description

    nonisolated
    public static func listModelFiles(in path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.sorted() ?? []
    }

    nonisolated
    public static func containsGGUF(in path: String) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).contains { $0.lowercased().hasSuffix(".gguf") }
    }

    nonisolated
    public static func describeModel(at path: String) -> String {
        let info = detect(path: path)
        var description = "模型类型: \(info.backendName)"

        if info.isVisualModel {
            description += " (视觉模型)"
        }

        if let mmproj = info.mmprojPath {
            description += "\n视觉组件: " + URL(fileURLWithPath: mmproj).lastPathComponent
        }

        if let draft = info.draftModelPath {
            let draftName = URL(fileURLWithPath: draft).lastPathComponent
            if isDFlashModel(draftName) {
                description += "\nDFlash 草稿模型: \(draftName)"
            } else if isMTPModel(draftName) {
                description += "\nMTP 草稿模型: \(draftName)"
            } else {
                description += "\n草稿模型: \(draftName)"
            }
        }

        if let size = getModelSize(at: path) {
            description += "\n模型大小: \(size)"
        }

        return description
    }

    nonisolated
    public static func getModelSize(at path: String) -> String? {
        let fm = FileManager.default
        var isDirectory = ObjCBool(false)

        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }

        if !isDirectory.boolValue {
            if let attrs = try? fm.attributesOfItem(atPath: path), let fileSize = attrs[.size] as? Int64 {
                return formatBytes(fileSize)
            }
            return nil
        }

        var totalSize: Int64 = 0
        let url = URL(fileURLWithPath: path)
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        return formatBytes(totalSize)
    }

    nonisolated
    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

public typealias ModelDetector = Detector
