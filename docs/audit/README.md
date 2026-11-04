# Historical audit and review records

本目录保存按日期形成的审计、回归复核与设计登记。**它是历史证据档案，不是当前缺陷清单、当前实现说明或实施授权。** 每份记录只对其标明的 commit、分支、机器和测试范围成立。

## Beta / release validation（2026-09-29）

- [BETA4 production findings](BETA4_PROD_FINDINGS_20260929.md) — v2.0.0-beta.4 首份生产日志发现。
- [BETA audit 3 re-audit](BETA_AUDIT_3_REAUDIT_20260929.md) — 当时 Beta 生命周期审计复核。
- [BETA release smoke](BETA_RELEASE_SMOKE_1_20260929.md) — 当时 suspend/resume 冒烟记录。
- [BETA storage audit](BETA_STORAGE_1_20260929.md) — checkpoint / prefix-pool retention 范围。
- [Performance convergence](PERF_CONVERGENCE_20260929.md) — beta.4 性能收敛证据链。
- [Hedge-skip experiment design](B_HEDGE_SKIP_EXPERIMENT_DESIGN_20260929.md) — design-only；设计登记不代表实验获批或执行。

## Request / session / streaming lifecycle（2026-09-11）

- [ChatSession and request lifecycle](CHATSESSION_AND_REQUEST_LIFECYCLE_AUDIT_2026-09-11.md)
- [ChatSession reuse-prefix audit](CHATSESSION_REUSE_PREFIX_AUDIT_2026-09-11.md)
- [Lifecycle and SSE audit](LIFECYCLE_AND_SSE_AUDIT_2026-09-11.md)
- [Request-task publication audit](REQUEST_TASK_PUBLICATION_AUDIT_2026-09-11.md)
- [Streaming and lifecycle findings](STREAMING_AND_LIFECYCLE_FINDINGS_2026-09-11.md)
- [Streaming lifecycle regression](STREAMING_LIFECYCLE_REGRESSION_2026-09-11.md)
- [StreamTokenFilter audit](STREAM_TOKEN_FILTER_AUDIT_2026-09-11.md)

这些记录来自同一历史审计周期及相关分支，不应简单计为七份相互独立的当前验证。

## Conditional Restore / runtime / upstream review（2026-09-09 至 2026-09-19）

- [Conditional Restore external audit — first round](CONDITIONAL_RESTORE_EXTERNAL_AUDIT_2026-09-18.md)
- [Conditional Restore external audit — follow-up](CONDITIONAL_RESTORE_EXTERNAL_AUDIT_2026-09-19.md) — 后续复审，不是独立重复样本。
- [CancellationToken placement audit](CANCELLATION_TOKEN_PLACEMENT_AUDIT_2026-09-09.md)
- [NativeMLX pressure-policy audit](NATIVE_MLX_PRESSURE_POLICY_AUDIT_2026-09-09.md)
- [Official MLX capability matrix](OFFICIAL_MLX_CAPABILITY_MATRIX_2026-09-11.md) — 仅对正文锁定的依赖版本与源码基线成立。
- [ExecutionID test-quality review](EXECID_TEST_QUALITY_REVIEW_2026-09-19.md)
- [Lifecycle external review](LIFECYCLE_EXTERNAL_REVIEW_2026-09-19.md)
- [Post-freeze code audit](POST_FREEZE_CODE_AUDIT_2026-09-19.md)
- [Post-audit deletion record](POST_AUDIT_DELETION_RECORD_2026-09-11.md) — 历史简化 / 删除记录，不是当前删除清单。

## 使用规则

- 先读根目录 [README](../../README.md)、[当前 Open Problems](../knowledge/open-problems/README.md) 与现行源码，再决定旧审计是否仍相关。
- 后续复审或新发现应登记在当前问题索引；不要覆盖旧审计的历史结论，也不要仅因旧报告提出 P1/P0 就自动恢复为当前优先级。
- 多轮审计若共享基线、样本或证据链，必须按依赖关系理解，不得累计成独立证据。
