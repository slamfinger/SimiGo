# 工程经验

本目录记录 2026-09 阶段真实发生的故障、回归、失败尝试及其处理结果。Lesson 是有范围的工程经验，不自动成为当前缺陷、架构规则或实施授权。

## 历史记录

- [Audit simplification migration lessons](AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md)：v5.0 简化迁移与官方语义所有权。
- [Cancel during prefill: poisoned session](cancel-mid-prefill-poisoned-session-2026-09-17.md)：特定 session lifecycle 故障与修复。
- [KV fork checkpoint experiment](kv-fork-checkpoint-experiment-2026-09-17.md)：v1.4 磁盘 checkpoint / fork 实验记录。
- [Application crash and server hang](incident-app-crash-and-server-hang-2026-09-19.md)：tools:null 输入进入 Foundation / ObjC 边界的历史故障。
- [Native MLX long-run trace](native_mlx-longrun-trace-2026-09-14.md)：指定 MLX / 模型 / 机器的长运行观察。
- [Reconnect counter render loop](reconnect-counter-render-loop-2026-09-18.md)：历史 UI reconnect loop 故障。

## 阅读边界

- 每篇记录说明现象、复现与证据、根因（若已确认）、处理方式、影响范围和未解决限制。
- 推测性根因应明确标注；是否升级为实验或决策，由后续证据决定。
- 不因单次故障直接增加核心不变量；也不把旧 lesson 的“已修复”扩大为当前版本 / 所有 backend 均无此问题。
- 当前仍开放的问题统一见 [Open Problems](../knowledge/open-problems/README.md)。
