# Finding：长上下文中的 rebuild 成本可成为主要运行时成本项

**日期**：2026-09-22

## Finding

在 2026-09-13 的真实 90K 长上下文 Agent 任务中，官方 cache reuse 失败导致的全量 prefill 是主要 wall-time 成本项之一：28 个完成轮次中 13 轮出现 cacheEff=0.00，重复 prefill 约占该任务 wall time 的六成。

该 Finding 支持“先解决缓存语义稳定性，再讨论局部 decode 优化”的工程优先级，但不构成跨模型、跨硬件的性能排名。

## Evidence

- docs/experiments/FIELD_OBSERVATION_20260913_LONG_CONTEXT_TASK.md
- 完整任务 trace 与官方 cache telemetry

## Boundary

样本来自特定模型、硬件、版本和单个长任务；不得把“wall time 六成”外推成普遍比例。

## Follow-up

继续区分 cache miss 的协议分叉原因；观察不同模型架构的可回卷能力；不在 SimiGo 内建立第二套 Physical KV 真值。
