# P0 勘察：现有实现能否承载真实模型级连续计算实验

执行日期：2026-10-16（Asia/Shanghai）
目标：确认现有 SimiGo 实现能否承载"旧模型执行缓存不可用 → Information Space 恢复结算 + 选择性失效重算"的真实模型端到端实验。

## 1. 仓库与代码现状
- CWD: `/Users/mr.simi/Documents/SimiGo-Lab`（main 分支）
- 四个关键文件全部存在：
  - `database-carrier-replication/implementation/db_is.py` —— Database-backed Information Space carrier（append-only，约束 3 表）
  - `execution-information-loop/carrier_loop.py` —— CarrierInformationLoop（需求、源、结算、执行状态恢复接口）
  - `execution-information-loop/real_palace_loop.py` —— RealPalaceSource（只读结构化数据适配器）
  - `execution-information-loop/production_runtime_bridge.py` —— 生产运行时集成桥（CLI 工具）
- Swift 侧模型执行链路：
  - `MLXPrefixRecomputeExecutor.swift` —— 真实 MLX 执行器，通过 `continueExecution` 消耗 token prefix 进行多轮生成（真实模型调用入口）
  - `MLXExecutionStateBackend.swift` —— 持有 token prefix 绑定（E3/L4 策略，纯数据）
  - `MLXSmallScaleChatHost.swift` —— 小规模 chat host，单 hook owner、单模型生命周期
- Swift build（含测试）：已验证可编译通过，约 35s。

## 2. 本地模型路径
- HF cache model directory: `/Users/mr.simi/.cache/huggingface/hub/` 下已缓存的本地离线模型目录。
- （以当前实际存在的目录为准，避免误报。）

## 3. 真实模型入口判定
- `MLXPrefixRecomputeExecutor.continueExecution` 是唯一的真实模型执行入口，它：
  - 消费一个 `ExecutionStateHandle` 的 token prefix（bound representation）；
  - 附加 next input tokens → MLX forward + greedy decode；
  - 返回 `ExecutionContinuationResult`（含 `nextInputTokenCount`、`generatedTokenIDs` 等可观测指标）。
- ⚠️ mlx-lm (python) 侧的 `qwen3_5_moe` model type 暂不被支持，因此实验复用 **Swift 侧真实执行器** 而非 python mlx_lm。这保证了"确实使用了模型"的证据（A）。

## 4. 边界确认
- 不改主仓库稳定路径；实验目录隔离在 `execution-information-loop/experiment/continuous-calc-verification`。
- 复用现有 carrier、loop、executor，不新建持久化/依赖管理/执行状态系统。
- 只用 1 个本地大模型目录（用户硬件约束），不双加载。

## 5. 结论 / 缺口
- 现有实现**能承载**本实验：carrier + loop 提供信息空间结算能力，Swift executor 提供真实模型执行。
- 缺口：需要写一个**隔离的最小多阶段测试脚本/用例**，串联"结算恢复 → 旧缓存隔离 → 恢复续算 → 选择性失效重算"，并记录可观测指标。下一阶段 P1-P3 实施。
