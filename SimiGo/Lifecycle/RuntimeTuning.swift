import Foundation

/// Minimal runtime limits that delegate memory governance to MLX.
nonisolated enum RuntimeTuning {
    static let gibibyte = 1024 * 1024 * 1024

    /// MLX overall allocation limit.
    static let mlxMemoryLimitBytes = 22 * gibibyte

    /// MLX recyclable buffer cache limit.
    static let mlxCacheLimitBytes = 4 * gibibyte

    /// Responses store is protocol state, not inference memory.
    static let responsesStoreMaxCount = 64
    static let responsesStoreTTLSeconds: TimeInterval = 1800

    /// 生成全局串行化（P0-3 强化，2026-09-11）。
    ///
    /// qwen3_5_moe 等动态编译架构（GatedDeltaNet/SparseMoeBlock/decode 段
    /// 全部包在 compile() 里）在并发生成时，多个 task 同时首次编译各自的
    /// kernel/段，会在 mlx-swift 的 evalLock / CompiledFunction.lock /
    /// mlx compile mutex 锁链上互堵，表现为全部生成线程零输出永久挂起
    /// （2026-09-11 22:18 三线程 sample 实锤；单请求串行正常）。
    ///
    /// 开启后所有生成跨 session 串行（gate key 常量化），本地单用户场景
    /// GPU 本身串行、吞吐损失可忽略。上游修复嵌套编译锁问题后可关闭。
    static let serializeGeneration = true

    /// P1 会话 LRU：托管 ChatSession 数上限（超出驱逐最久未用，官方 clear() 释放 KV）。
    static let sessionLimit = 8

    /// P1 per-generation KV token 上限（官方 maxKVSize 透传）；nil = 仅受 ctx 约束。
    static var maxKVSize: Int? = nil

    /// P1 卸载后 memory settle 等待上限。
    static var memorySettleTimeoutSeconds: TimeInterval = 10

    /// 进程物理足迹（phys_footprint）——MLX 分配与统一内存压力的直接观测量。
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    /// 系统 swap 已用量（vm.swapusage 的 used 字段）。
    static func swapUsedBytes() -> UInt64 {
        var size = 0
        sysctlbyname("vm.swapusage", nil, &size, nil, 0)
        guard size > 0 else { return 0 }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("vm.swapusage", &buffer, &size, nil, 0)
        guard let text = String(cString: buffer, encoding: .utf8),
              let usedRange = text.range(of: "used = ") else { return 0 }
        let remainder = text[usedRange.upperBound...]
        let number = remainder.prefix(while: { $0.isNumber || $0 == "." })
        guard let value = Double(number) else { return 0 }
        let unit = remainder.drop { !$0.isLetter }.first
        let bytes = unit == "G" ? value * 1024 * 1024 * 1024 : value * 1024 * 1024
        return UInt64(bytes)
    }

    /// Unified Memory 快照行（MLX 计数器由调用方注入，保持本文件无 MLX 依赖）。
    static func memorySnapshotLine(
        activeBytes: Int, cacheBytes: Int, peakBytes: Int
    ) -> String {
        func mb(_ bytes: Int) -> String { String(format: "%.0fMB", Double(bytes) / 1048576.0) }
        let mlx = "active=\(mb(activeBytes)) cache=\(mb(cacheBytes)) peak=\(mb(peakBytes))"
        let footprint = "footprint=\(mb(Int(footprintBytes())))"
        let swap = "swapUsed=\(mb(Int(swapUsedBytes())))"
        return mlx + " " + footprint + " " + swap
    }
}
