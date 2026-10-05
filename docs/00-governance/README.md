# 00 — Governance

本目录保存 SimiGo-Lab 的档案治理、研究路线控制面、状态词汇、依赖关系、注册表与边界约束。

权威当前状态仍为 ../RESEARCH_STATE.md；本目录的 Register / Map 文件负责导航和治理，不复制完整状态。

当前快速研究导航入口：../RESEARCH_CONTEXT_INDEX.md。该索引只提供定位、状态、边界和合法下一跳，不是权威状态或记忆库。

## Governance control plane
- RESEARCH_PROGRAM_REGISTER_20260922.md：研究路线与当前/未来分支总表；
- RESEARCH_DEPENDENCY_MAP_20260922.md：问题、研究线与 Gate 的依赖关系；
- EXPERIMENT_REGISTER_20260922.md：实验/设计生命周期与历史资产入口；
- ARCHITECTURE_CONSEQUENCE_MAP_20260922.md：证据约束的架构后果与未验证架构假设；
- NEGATIVE_AND_OPEN_QUESTIONS_REGISTER_20260922.md：关闭、否决、未决和 dormant 方向。

## 核心规则
- 不以档案移动改变研究状态；
- 不把预测、观察、解释和结论混为一谈；
- 历史资产保持 provenance；
- 新研究线必须独立定义、独立编号、独立通过门禁；
- Register / Map 是控制面，不是新的证据或结论；
- CLOSED / SEALED / FROZEN 不因出现在 Register 中而重新开放。

## Multi-agent continuity
不同本地 Agent 与 ChatGPT 共享同一 Git 仓库时，应把仓库视为 durable research memory。

Agent 必须能仅凭仓库恢复：我们在哪里、已经知道什么、还不知道什么、哪些路已经关闭、下一步允许做什么、哪些事情禁止做。

具体恢复与交接规则见 ../08-research-memory/AGENT_MEMORY_PROTOCOL_20260922.md。