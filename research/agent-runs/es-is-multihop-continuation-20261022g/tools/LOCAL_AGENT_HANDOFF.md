# 直接执行指令

读取 `AGENT_TASK.md`，在当前本地 `SimiGo-Lab` 工作树中无人看守地实施 G 轮。不要只回答方案或生成 Canvas。先在任何源码修改之前建立工作树快照和 A–F 历史产物哈希快照，再阅读当前实际 Swift/MLX/IS/ES 实现；然后完成原生代码适配、构建、测试、三阶段真实模型运行、转移依赖闭包负对照和证据校验。

唯一研究目的：证实已结算工作 U1 与中间工作 U2，在旧进程与执行上下文结束后，能够通过 PALACE Information Space 被连续两个全新 OS 进程 / Execution State 恢复，最终只计算 U3；不能重生成 U1/U2。U2/U3 应通过普通生产 `continueTask` 自行解析 IS，不允许 Python/harness 直接读 settlement/item 并注入答案。

运行根固定为 `$HOME/SimiGo-Agent-Runs/es-is-multihop-continuation-20261022g/`。保护 F 轮及 A–E 的现有证据、G2 冻结批次、`run-20261022a`、所有现有无关 dirty/untracked 文件；不改 `carrier_loop` 的既有重算语义，不新增 anti-rollback、远程信任根或新的全局 no-recompute 策略，不 stage/commit/push。

遇到真实模型/MLX 阻塞时继续完成能够落地的原生代码、单测和 runner，将无法执行条件明确标 `BLOCKED_NOT_RUN`；不可将计划、mock 测试、Canvas 或预填计数视为实验完成。所有失败尝试保留，修代码后使用新的 attempt/run ID，不能覆盖旧失败证据。
