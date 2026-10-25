# SimiGo-Lab 档案总索引

> 本索引是档案入口，不替代 docs/RESEARCH_STATE.md 的权威状态职责。

## 1. 先读什么

| 需求 | 入口 |
|---|---|
| 恢复当前研究状态 | RESEARCH_STATE.md |
| 快速恢复研究路线 | 00-governance/RESEARCH_PROGRAM_REGISTER_20260922.md |
| 理解问题依赖与 Gate 顺序 | 00-governance/RESEARCH_DEPENDENCY_MAP_20260922.md |
| 查实验/设计全局状态 | 00-governance/EXPERIMENT_REGISTER_20260922.md |
| 查架构哪些是证据约束、哪些仍是假设 | 00-governance/ARCHITECTURE_CONSEQUENCE_MAP_20260922.md |
| 查已经关闭/否决/未决的问题 | 00-governance/NEGATIVE_AND_OPEN_QUESTIONS_REGISTER_20260922.md |
| 了解 Agent 行为约束 | AGENT_CONTEXT.md |
| 查看长期思想与候选假设 | RESEARCH_MEMORY.md |
| 理解思想与实验的连续性纽带 | 00-governance/IDEA_TO_EXPERIMENT_CONTINUITY_MODEL_20260922.md |
| 恢复跨 Agent 记忆协议 | 08-research-memory/AGENT_MEMORY_PROTOCOL_20260922.md |
| 了解现有资产如何映射到新档案体系 | 07-history/LEGACY_ASSET_MAPPING_20260922.md |
| 恢复 Architecture 2.0 思想总览 | 07-history/ARCHITECTURE_2.0_SESSION_KNOWLEDGE_20260922.md |
| 恢复 Architecture 2.0 概念起源 | 07-history/ARCHITECTURE_2.0_ORIGIN_RECONSTRUCTION_20260922.md |
| 快速恢复 Execution State“为什么做、每个实验验证什么、思想如何变化” | 07-history/EXECUTION_STATE_RESEARCH_STORY_20260922.md |
| 查看未来 Execution State 机制候选 | 05-architecture/EXECUTION_STATE_FUTURE_MECHANISMS.md |
| 查看 Architecture 2.0 最重要的长期思想资产 | 05-architecture/ARCHITECTURE_2.0_LONG_HORIZON_VISION_20260922.md |
| 检查 Architecture 2.0 思想血缘完整性 | 07-history/ARCHITECTURE_2.0_INTELLECTUAL_LINEAGE_AUDIT_20260922.md |
| 复盘 Architecture 2.0 下一研究方向的候选成熟度与合法动作 | 07-history/ARCHITECTURE_2.0_RESEARCH_DIRECTION_REVIEW_20260922.md |
| 概念剖析：Execution State / Boundary / Operational Unit / Residency Unit / Sharding Unit / Management Unit | 07-history/ARCHITECTURE_2.0_CONCEPTUAL_DISSECTION_20260922.md |
| 重新梳理 Architecture 2.0 研究课题、结题/终止与继续方向 | 07-history/ARCHITECTURE_2.0_RESEARCH_PROGRAM_RECLASSIFICATION_20260922.md |
| 了解方向性架构文档 | architecture/ |

## 2. 档案分层

00-governance → 01-questions → 02-evidence → 03-findings → 04-decisions → 05-architecture → 06-closure → 07-history → 08-research-memory

旧 track-*、exp-* 与 runtime2-skeleton/ 继续作为实验/规划工作区保留；控制面不要求移动它们。

## 3. 控制面与内容面

治理层控制面登记：Program → Dependency → Question → Experiment → Finding → Decision → Architecture → Closure。

思想层与验证层通过 `Idea / Structure → Question → Testable Claim → Design → Experiment → Evidence → Finding → Decision → Architecture → revised Idea` 连接。实验是高层思想下的局部检验，不等于思想本身；证据只在其定义范围内更新思想。具体规则见 `00-governance/IDEA_TO_EXPERIMENT_CONTINUITY_MODEL_20260922.md`。

具体原文、数据、脚本和历史资产仍保留在各自原路径。控制面不复制全文，也不改变 provenance。

## 4. 多 Agent 记忆模型

Authoritative State ↔ Research Memory ↔ Research Questions / Evidence / Decisions ↔ Agent Dialogue

Git 仓库是跨 Agent 的持久化事实与记忆载体；对话只是输入来源。具体规则见 08-research-memory/AGENT_MEMORY_PROTOCOL_20260922.md。

Architecture 2.0 历史采用三层保存：
- SESSION_KNOWLEDGE：较完整的概念、转折和边界重建；
- ORIGIN_RECONSTRUCTION：从长上下文问题到 Execution State 的最早可恢复思想链；
- RESEARCH_MEMORY：只保留会影响未来研究判断的 durable insights。

## 5. 当前阶段约束

当前阶段与下一步动作以 RESEARCH_STATE.md 为准。档案重构不得：
- 修改或重新解释 FROZEN / SEALED 资产；
- 把历史结果自动升级为当前研究问题的证据；
- 以目录调整代替研究门禁；
- 在未完成规定步骤前提前进入实现、采数或测量。

## 6. 归档区 `09-archive/`（2026-10-20 起）

`09-archive/` 只存已移出默认视野的**历史记录**，内容冻结、原文件名不变。
归档不等于失效：证据状态不变，仍按文件名检索。判定依据与逐文件映射见
`00-governance/state-layer-audit-20261020/`（计划 + CSV + 校验脚本）。

| 线 | 归档文件 | 路径 |
|---|---|---|
| E-I 连续计算 | 59 | `09-archive/execution-information-loop/2026-10/` |
| PALACE / Integrated ES | 29 | `09-archive/palace/2026-09/`、`2026-10/` |
| 通用治理 / 其他 | 55 | `09-archive/general/2026-09/`、`2026-10/`、`undated/` |
| Small-scale runtime / GUI | 2 | `09-archive/runtime-gui/2026-09/`、`2026-10/` |
| 状态层历史正文 | 2 | `09-archive/state-layer/`（`SESSION_CONTINUITY_20261008_FULL.md`、`NEXT_SESSION_ENTRY_20261002_FULL.md`） |
| **合计** | **147** | — |

`Execution State / Track B` 与 `Track D / Information Space` 两线各有 1 份，闭包复核发现被留存文档按名引用，已移回原位，归档区对应目录已清空。

`Persistent SRS / Signer` 线的 **152 份冻结批次**（`PERSISTENT_SRS` 65、`SRS_VAL_01` 34、`SRS_REAL_CLOSURE_01` 51、`PALACE_INFORMATION_SPACE` 2）暂不归档：Signer v0.7 待人类裁定，且该批次内部互引 38 处，必须整批原子迁移，不能逐份移动。仍留在 `00-governance/`。归档区不改变任何研究门位。

## 2026-10-26 文档治理归档映射

按 owner 指令治理（移动归档，内容零删改）：

| 归档位置 | 原位置 | 内容 |
| --- | --- | --- |
| `09-archive/state-layer/RESEARCH_STATE_ARCHIVED_LAYERS_20261026.md` | `RESEARCH_STATE.md`（原 242 行起） | 2026-10-15 及更早全部 continuity 层（27539 行原样）；主文件仅留头部导航 + 10-25/10-20 两层 |
| `09-archive/docs-root-legacy/` | `docs/LOSS*` `PDEP2*` `SOURCE_RUNTIME*` `STEP4A*` `STEP5*` `RESEARCH_RECOVERY_*`（14 个文件） | LOSS 成本线 / PDEP2 路线 / Source-Runtime 估计量研究线的历史文档 |
| `09-archive/closed-lines/<name>/`（12 个） | 顶层 `boundary-study` `database-carrier-replication` `exp06-roofline` `integrated-es-palace` `palace-v0` `pre-research` `runtime2-skeleton` `trackA-kernel` `trackB-execution-state` `trackD-memory` `trackE-residency` `warm-memory-proto` | 已收口/暂停研究线的全部代码与证据 |
| `05-architecture/ARCHITECTURE_2.0_PRERESEARCH_20260920.md` | `docs/architecture/` | 并入统一架构目录（原目录撤销） |

顶层活跃保留：`docs/`、`execution-information-loop/`、`g3/`、`simigo2-experimental/`、`tools/`、`vendor/`。
重复空壳目录 `simigo2Experimental/`（未跟踪、无文件）已移除；根级 `default.profraw` 垃圾已删。
