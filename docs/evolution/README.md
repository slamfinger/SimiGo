# SimiGo 演进史

本目录保留历史决策与架构演进脉络，不代表当前产品状态、开发计划或授权。当前实现以产品代码和对应版本证据为准。

## 关键锚点

### V4.5 Stable Foundation
- [Baseline decision](../decisions/V4_5_STABLE_FOUNDATION_BASELINE.md)
- [Evolution track](../experiments/EVOLUTION_TRACK.md)

V4.5 是历史稳定基础；其 99 条历史铁律不自动延续为当前规则。仍成立的原则由后续基线重新收敛。

### V5.0 Core Architecture Baseline
- [Archived baseline](../history/CORE_ARCHITECTURE_BASELINE_V5_20260912.md)（原 `README_base.md`，2026-10-30 归档）
- [Post-audit deletion record](../audit/POST_AUDIT_DELETION_RECORD_2026-09-11.md)
- [Simplification migration lessons](../lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md)

V5.0 的主要变化是把 MLX / MLXLMCommon 已提供的语义归还上游，并收缩 SimiGo 自身的权威边界。

### 2026-09-22：Research / Knowledge Layer
PR #5 建立 Research、Knowledge、Decision 的文档分层；首轮知识迁移提炼了既有 Lesson、Audit 和 Architecture 内容，没有移动或删除历史原文。

- [Knowledge](../knowledge/README.md)
- [Research archive](../research/README.md)
- [Decisions](../decisions/README.md)
