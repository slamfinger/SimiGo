# 交给本地 Agent 的启动指令

请在当前本地 `SimiGo-Lab` 工作树中，完整执行 `AGENT_TASK.md`。目标是原生 Swift/MLX 代码实现和真实模型证据，不是生成计划后停止。必须先完成工作树快照和 A–E 历史运行产物哈希快照，再改动源码；实施后运行构建、Swift 测试、真实双进程 U1→新 ES 的 U2 实验和负对照。所有本轮产物写到 `$HOME/SimiGo-Agent-Runs/es-is-detached-continuation-20261022f/`。保护旧实验、冻结证据和既有 dirty/untracked 文件；不改 `carrier_loop` 重算语义、不 stage/commit/push；遇到真实模型阻塞时继续完成可行代码与测试，并如实报告 `BLOCKED_NOT_RUN`。

## 建议直接执行的首条消息

“读取并执行 `LOCAL_AGENT_HANDOFF.md` 和 `AGENT_TASK.md`。不要只复述计划：先建快照，然后在原生生产代码中实现旧 U1 执行上下文结束后的 IS 结算恢复和全新 U2 Execution State 继续，运行所有可运行的构建/测试/真实模型实验，保存原始证据，最后做前后守卫。不得改动旧运行和无关本地变化。”
