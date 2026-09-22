# 08 — Research Memory

保存长期思想、候选假设、未决线索和可复用的研究启发，并为不同本地 Agent 提供可恢复的持久记忆层。

本目录中的内容默认不是当前状态、正式研究问题或结论。现有 docs/RESEARCH_MEMORY.md 继续作为主要思想登记文件；任何条目进入正式研究线，都必须经过独立定义和门禁流程。

## Multi-agent memory

跨 Agent 的记忆不是聊天记录复制，而是结构化、带 provenance 的研究记忆：

State → Memory → Dialogue

- 当前状态：docs/RESEARCH_STATE.md；
- 长期思想：docs/RESEARCH_MEMORY.md；
- 记忆协议与 Agent 交接：AGENT_MEMORY_PROTOCOL_20260922.md；
- 路线、依赖、实验和架构控制面：docs/00-governance/。

目标是让一个没有原始会话上下文的新 Agent，仅凭仓库恢复研究位置、历史知识、开放问题、关闭路线和下一步合法动作。