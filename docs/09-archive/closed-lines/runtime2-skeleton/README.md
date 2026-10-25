# Runtime2 — Multi-device Execution Layer 占位

**定位（报告 §5.3）**：Planner / Scheduler / Reduction /
DistributedBackend 是**多设备执行层**的未来概念——单机世界里它们没有
可赢的机制。`[future]` 标注，**不实现、不立项**；硬件与场景未到位前
本目录只维护笔记。

**现期概念的去向**：ExecutionState / Page / Fork / Restore /
MemoryBudget 由 `trackB-execution-state/` 与 `trackD-memory/` 的原型
直接承载，**不在本目录预建接口**（防"为了架构而架构"）。

**唯一成立的世界**：跨设备时"拆分 = 获得额外计算资源"；底座 =
`mlx.distributed`（MPI/Ring/JACCL 等），SimiGo 的位置是编排，
不重做通信层。

**状态**：笔记态。
