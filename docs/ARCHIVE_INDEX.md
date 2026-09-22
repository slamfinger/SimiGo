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