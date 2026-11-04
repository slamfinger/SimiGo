# SimiGo-Lab Knowledge

本目录记录从工程与研究过程中沉淀出的知识，而不是过程日志。

## 知识阶梯

Observation
→ Finding
→ Principle
→ Invariant

## 目录

- `observations/`：直接观察到的事实
- `findings/`：由证据支持的发现
- `principles/`：可跨具体实现复用的原则
- `invariants/`：经过充分验证、成为核心架构约束的稳定不变量
- `open-problems/`：明确知道尚未解决的问题

知识升级必须有证据依据，不能因为文档写得确定就提高知识等级。


## 首轮知识迁移（2026-09-22）

首轮迁移不移动历史原文，而是从已经完成的 v4.5 → v5.0 收敛材料中提炼可复用知识，并保留原始证据路径。

### Findings

- [Physical KV ownership](findings/FINDING_OFFICIAL_SESSION_OWNS_PHYSICAL_KV.md) —— 官方 ChatSession 成为 Physical KV 账本与前缀调和的权威来源。
- [Protocol boundary normalization](findings/FINDING_PROTOCOL_BOUNDARY_NORMALIZATION.md) —— Tool Call 表示差异必须在协议边界规范化。
- [Simplification reduces runtime authority](findings/FINDING_SIMPLIFICATION_REDUCES_RUNTIME_AUTHORITY.md) —— 上游语义足够时，删除平行运行时权威本身就是架构收敛。

### Principle

- [Official semantics first](principles/PRINCIPLE_OFFICIAL_SEMANTICS_FIRST.md) —— 先确认上游语义来源，再决定是否需要本地抽象。

### Invariants

- [Logical/physical state separation](invariants/INVARIANT_LOGICAL_PHYSICAL_STATE_SEPARATION.md)
- [Core architecture requires evidence](invariants/INVARIANT_CORE_ARCHITECTURE_REQUIRES_EVIDENCE.md)

### 迁移原则

历史文档继续作为一手证据保留；本目录只承载经过提炼的知识。这样可以形成：

`Lesson / Experiment / Audit → Evidence → Finding → Principle / Invariant`

而不是把历史记录简单复制到新目录。
