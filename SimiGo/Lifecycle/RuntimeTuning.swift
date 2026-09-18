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

    /// P2 Admission（2026-09-18）：暖会话 KV token 总预算——全部存活会话
    /// processedTokenCount 之和的上限，swap 压力下按 LRU 逐出（官方 clear()）。
    /// 背景：并行多会话负载下 5+ 个 18-65k 暖会话把内存顶进 swap 爬速区
    /// （40-110 tok/s），39613 tok 重建跑不赢客户端 ~10.5 min 超时，形成
    /// 「重建×超时」无进展循环（09-17 深夜 2h22m 实证，lessons 同名文档深夜段）。
    /// 初值按当晚边界定：3 会话 ≈88k tok 可完成（尾段已退化）。校准常数，
    /// 随 [MLX] admission 观测行调整。
    static let warmTokenBudget = 100_000

    /// swap 压力触发阈值：全机信号（其他进程占用也计入），作触发偏保守正确。
    /// 逐出循环的出口用进程内可立即复测的暖 token 总和，不用 swap（回落滞后）。
    /// swap 读不到（nil=未知）不触发内存维度：未知不冒充压力。
    static let swapPressureThresholdBytes: UInt64 = 2 * UInt64(gibibyte)

    /// Phase B roll-forward（2026-09-18，探索文档 §5/§6）：账本尾部 assistant
    /// 含多键 tool_calls 时，下轮前同 key 恢复 checkpoint 进入
    /// fragment-continuation（raw-cache 无账本 → 无比较 → 无分歧税）。
    /// Phase A 实测开销 0.16s/轮 vs 分歧税 300-490s（≈2000×）。
    /// 灰度开关：置 false 即回退纯活会话行为。
    /// 状态（2026-09-18 外审定级）：Phase B implemented / production hypothesis
    /// under validation——真实客户端回放验收（fork-no-rewind 恒 0、恢复后
    /// 指纹连续复用、无 detached session）通过前不得视为生产已验证。
    static var rollforwardEnabled = true

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
