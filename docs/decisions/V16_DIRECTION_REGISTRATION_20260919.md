# V1.6 方向登记：Execution Runtime 定型版（2026-09-19）

> **历史路线登记（2026-11-05）**：本文记录 V1.6 阶段的 Execution Runtime 方向，不是当前产品定位或待执行路线。其“当前实现”“远期阶段”等措辞以 2026-09-19 为时间参照；后续路线以根 README、当前源码和当前问题索引为准。

**性质**：外审战略路线登记（非立即实施；对应审计"V1.5 后路线四阶段"）

## 核心定位转变

> SimiGo = macOS 上面向本地 LLM 的 **Execution Runtime**。
> 不是聊天 UI，不是 Agent Framework，不是 KV 优化器。

## 路线四阶段

1. **V1.5 冻结 = Runtime 基线**：不再加优化点；现有链路（Conditional
   Restore/delta 门/阶梯/checkpoint）作为后续一切实验的参照系
2. **V1.6 = 架构定型版（少做）**：Execution 抽象、Lifecycle 抽象、
   checkpoint/restore/fork API 边界、Execution lineage（ExecutionID/
   ParentID）、telemetry 正式化；Conditional Restore 再优化/调步长/
   KV Tree/COW/Agent Framework/大规模重构全部 ❌
3. **上游推动**：RFC 已提交（mlx-swift-lm#629），等待能力落地
4. **远期**：F1/Fork 实验（🧪）→ Execution Graph → Agent 作为上层消费者

## 关键原则

- **先定义能力，不定义实现**：Execution Fork abstraction 的当前实现 =
  磁盘 checkpoint fork，未来 = upstream native fork——SimiGo 不自造
  SharedKVNode/COWKV
- **KV 退位**：KV 从主角降为 Execution 的底层状态一部分
- **Session ≠ Execution**：一个 Session 多个 execution 是 V1.6 的概念
  基础（SessionID ≠ ExecutionID ≠ kvFingerprint）

## 与现有文档关系

- 外审代码体检清单执行记录：`docs/audit/POST_FREEZE_CODE_AUDIT_2026-09-19.md`
- V1.5 终局决策：`docs/decisions/V15_ENDGAME_DECISION_20260919.md`
- roadmap §13 现有排序继续有效（P2 Batch/continuous batching 冻结不变）
