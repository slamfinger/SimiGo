# SimiGo-Lab 档案总索引

> 本索引是档案入口，不替代 `docs/RESEARCH_STATE.md` 的权威状态职责。

## 1. 先读什么

| 需求 | 入口 |
|---|---|
| 恢复当前研究状态 | [`RESEARCH_STATE.md`](./RESEARCH_STATE.md) |
| 了解 Agent 行为约束 | [`AGENT_CONTEXT.md`](./AGENT_CONTEXT.md) |
| 查看长期思想与候选假设 | [`RESEARCH_MEMORY.md`](./RESEARCH_MEMORY.md) |
| 了解档案体系设计来源 | [`00-governance/ARCHIVE_ARCHITECTURE_INSPIRATIONS.md`](./00-governance/ARCHIVE_ARCHITECTURE_INSPIRATIONS.md) |
| 了解方向性架构文档 | [`architecture/`](./architecture/) |

## 2. 档案分层

```text
docs/
├── 00-governance/   规则、状态、档案设计与维护约束
├── 01-questions/    研究问题、对象边界、资格门与定义过程
├── 02-evidence/     实验观察、数据、审查记录与证据索引
├── 03-findings/     从证据中形成的限定性发现
├── 04-decisions/    研究裁定、路径选择与设计修订
├── 05-architecture/ 由研究结果约束的架构后果与不变量
├── 06-closure/      研究线关闭、封存、冻结与出口记录
├── 07-history/      历史映射、迁移记录与 provenance
└── 08-research-memory/ 长期候选思想与未决线索的整理入口
```

第一阶段只建立索引和分类入口，不要求立即搬迁已有文件。`track-*`、`exp-*` 与 `runtime2-skeleton/` 继续作为实验工作区保留。

## 3. 证据链

```text
Question → Hypothesis → Design → Evidence → Finding → Decision → Architecture → Invariant / Closure
```

所有链接应尽量指向具体文档、章节、Git commit 或其他可复核锚点；预测、计划、观察和结论不得混写。

## 4. 当前阶段约束

当前阶段与下一步动作以 [`RESEARCH_STATE.md`](./RESEARCH_STATE.md) 为准。档案重构不得：

- 修改或重新解释 FROZEN / SEALED 资产；
- 把历史结果自动升级为当前研究问题的证据；
- 以目录调整代替研究门禁；
- 在未完成规定步骤前提前进入实现、采数或测量。
