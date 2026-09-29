import Foundation

/// BETA-STORAGE-1: a paired checkpoint is the durable receipt for one logical
/// execution. Retention is ownership-aware and byte-bounded: active keys are
/// never collected, malformed pairs are orphans, and oldest valid receipts are
/// collected only after the physical-byte budget is exceeded.
nonisolated enum BranchCheckpointRetention {
    struct Result: Equatable {
        var removedOrphans = 0
        var removedForBudget = 0
        var freedBytes: Int64 = 0
        var retainedBytes: Int64 = 0
        var retainedReceipts = 0
    }

    static func enforce(
        directory: URL,
        retainedKeys: Set<String>,
        byteBudget: Int,
        fileManager: FileManager = .default
    ) throws -> Result {
        guard byteBudget > 0 else {
            throw RuntError.generationFailed("branch checkpoint byte budget must be positive")
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var result = Result()
        let urls = try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])

        var cacheURLsByBase: [String: URL] = [:]
        var metadataURLsByBase: [String: URL] = [:]
        for url in urls where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
            if url.lastPathComponent.hasSuffix(".meta.json") {
                metadataURLsByBase[String(url.lastPathComponent.dropLast(".meta.json".count))] = url
            } else if url.lastPathComponent.hasSuffix(".safetensors") {
                cacheURLsByBase[String(url.lastPathComponent.dropLast(".safetensors".count))] = url
            }
        }

        func remove(_ urls: URL...) {
            for url in urls {
                let bytes = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                try? fileManager.removeItem(at: url)
                result.removedOrphans += 1
                result.freedBytes += Int64(bytes)
            }
        }

        for (base, cacheURL) in cacheURLsByBase where metadataURLsByBase[base] == nil {
            remove(cacheURL)
            cacheURLsByBase[base] = nil
        }
        for (base, metadataURL) in metadataURLsByBase where cacheURLsByBase[base] == nil {
            remove(metadataURL)
            metadataURLsByBase[base] = nil
        }

        struct Receipt {
            var key: String
            var savedAt: Date
            var cacheURL: URL
            var metadataURL: URL
            var bytes: Int64
        }

        // 预算前置门（2026-09-29 效率审查 #1，窄实施）：配对后的字节总量
        // 用 fileSizeKey 统计即可，未超预算时 eviction 循环在数学上不可能
        // 触发（唯一触发条件是 retainedBytes > byteBudget），因此整段
        // sidecar 解码——每个 .meta.json 内嵌全量 transcript，MB 级——完全
        // 跳过。代价：配对完好但解码失败的畸形 receipt 在未超预算期间暂
        // 不清理，推迟到首次超预算清扫；load 路径对坏 sidecar 本就响亮
        // 失败并回退 extend，无静默续算风险。gate 位置 / eviction 排序 /
        // schema / 遥测格式均不变。
        var pairedBytes: Int64 = 0
        var pairedCount = 0
        for (base, cacheURL) in cacheURLsByBase {
            guard let metadataURL = metadataURLsByBase[base] else { continue }
            let cacheBytes = Int64((try? cacheURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            let metadataBytes = Int64((try? metadataURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            pairedBytes += cacheBytes + metadataBytes
            pairedCount += 1
        }
        if pairedBytes <= Int64(byteBudget) {
            result.retainedBytes = pairedBytes
            result.retainedReceipts = pairedCount
            return result
        }

        var receipts: [Receipt] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for (base, metadataURL) in metadataURLsByBase {
            guard let cacheURL = cacheURLsByBase[base] else { continue }
            let receipt: SessionCacheMetadata?
            do {
                receipt = try decoder.decode(
                    SessionCacheMetadata.self, from: Data(contentsOf: metadataURL))
            } catch {
                receipt = nil
            }
            guard let receipt, !receipt.storageKey.isEmpty else {
                remove(metadataURL, cacheURL)
                cacheURLsByBase[base] = nil
                continue
            }
            let cacheBytes = Int64((try? cacheURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            let metadataBytes = Int64((try? metadataURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            receipts.append(Receipt(
                key: receipt.storageKey,
                savedAt: receipt.savedAt,
                cacheURL: cacheURL,
                metadataURL: metadataURL,
                bytes: cacheBytes + metadataBytes))
        }

        result.retainedBytes = receipts.reduce(0) { $0 + $1.bytes }
        result.retainedReceipts = receipts.count
        let candidates = receipts
            .filter { !retainedKeys.contains($0.key) }
            .sorted { $0.savedAt < $1.savedAt }
        var candidateIndex = 0

        while result.retainedBytes > Int64(byteBudget), candidateIndex < candidates.count {
            let victim = candidates[candidateIndex]
            candidateIndex += 1
            try? fileManager.removeItem(at: victim.cacheURL)
            try? fileManager.removeItem(at: victim.metadataURL)
            result.removedForBudget += 2
            result.freedBytes += victim.bytes
            result.retainedBytes -= victim.bytes
            result.retainedReceipts -= 1
        }
        return result
    }
}
