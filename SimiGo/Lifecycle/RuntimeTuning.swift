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

    /// 预填步长按上下文规模选档（2026-09-13 阶梯实测定档）。
    /// 实测（121k 冷预填、32GB 工作机、权重 19.3GB 驻留）：
    /// 512 = 188 tok/s；1024 = 早段 399 / 中段 221（健康）；2048 = 无并发
    /// 早段 510、并发日常任务后 <48（换页抖动，swap 6G+）；4096 = 94（淘汰）。
    /// 瓶颈是内存容量而非批次：小上下文用大步长吃满带宽，大上下文降档保内存。
    /// 官方 API 无运行中换挡（stepSize 固定、分块计划预先生成），此为按会话
    /// 规模的请求级阶梯；运行中自适应列 upstream feature request 素材。
    static func prefillStepSize(contextTokens: Int) -> Int? {
        if contextTokens < 65536 { return 2048 }
        if contextTokens < 98304 { return 1024 }
        return nil // 512：超大上下文换页保护
    }

    /// 预填吞吐保守下限（tok/s）——512 档实测 188，取 150 估算闲置会话重建时长。
    static let prefillThroughputFloor = 150.0

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

    /// vm.swapusage 的 sysctl 返回二进制 `xsw_usage`（sys/sysctl.h），
    /// 不是字符串——终端看到的文本是 sysctl(8) 工具格式化的。
    /// 旧实现按 C 字符串解析，首字节 0x00 → 空串 → 永远返回 0
    /// （2026-09-13 实测修正；镜像结构体与 sysctl(8) 同帧对拍一致）。
    private struct XswUsage {
        var total: UInt64 = 0
        var avail: UInt64 = 0
        var used: UInt64 = 0
        var pageSize: UInt32 = 0
        var encrypted: Int32 = 0
    }

    /// 系统 swap 已用量（xsu_used 字段）。读不到返回 nil：未知不冒充 0。
    static func swapUsedBytes() -> UInt64? {
        var usage = XswUsage()
        var size = MemoryLayout<XswUsage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0,
              size == MemoryLayout<XswUsage>.size else {
            return nil
        }
        return usage.used
    }

    /// Unified Memory 快照行（MLX 计数器由调用方注入，保持本文件无 MLX 依赖）。
    static func memorySnapshotLine(
        activeBytes: Int, cacheBytes: Int, peakBytes: Int
    ) -> String {
        func mb(_ bytes: Int) -> String { String(format: "%.0fMB", Double(bytes) / 1048576.0) }
        let mlx = "active=\(mb(activeBytes)) cache=\(mb(cacheBytes)) peak=\(mb(peakBytes))"
        let footprint = "footprint=\(mb(Int(footprintBytes())))"
        let swap = swapUsedBytes().map { "swapUsed=\(mb(Int($0)))" } ?? "swapUsed=n/a"
        return mlx + " " + footprint + " " + swap
    }
}
