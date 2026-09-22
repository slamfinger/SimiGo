# SimiGo Evolution

记录 SimiGo 从工程实践走向稳定架构的演进历史。

这里保留历史，不重写历史。

重点回答：

> 为什么系统从当时的状态走到了现在的状态？

建议以稳定基线为锚点记录：

- V4.5 Stable Foundation
- 后续 Runtime 演进
- V5.0 Core Architecture Baseline
- 后续版本及其架构变化

历史记录应链接到对应 Decision、Experiment、Lesson 和 Release，而不是只罗列版本号。


## 已建立的演进锚点

### V4.5 Stable Foundation

- [V4.5 Stable Foundation Decision](../decisions/V4_5_STABLE_FOUNDATION_BASELINE.md)
- [Evolution Track](../experiments/EVOLUTION_TRACK.md)

V4.5 保留为历史稳定基础。其 99 条历史铁律不直接继续扩张；仍然成立的长期原则由 v5.0 Core Architecture Baseline 重新收敛。

### V5.0 Core Architecture Baseline

- [Core Architecture Baseline](../../README_base.md)
- [Post-audit deletion record](../audit/POST_AUDIT_DELETION_RECORD_2026-09-11.md)
- [Simplification migration lessons](../lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md)

v5.0 的关键变化不是增加更多 Runtime 层，而是把已经由官方 MLX/MLXLMCommon 提供的语义重新归还给上游，并收缩 SimiGo 自身的权威边界。

### 2026-09-22：Research / Knowledge Layer 建立

PR #5 已合并到 main，建立 Research → Knowledge → Decision → Architecture 的上层结构。首轮知识迁移随后完成：从已有 Lesson / Audit / Architecture 中提炼 Findings、Principle 与 Invariants，同时不移动或删除历史原文。

- [Knowledge Layer](../knowledge/README.md)
- [Research Layer](../research/README.md)
- [Decision Layer](../decisions/README.md)
