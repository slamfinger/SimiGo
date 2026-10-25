# SimiGo 本地 Agent 执行任务

请直接按《SimiGo 原生集成与自主引导部署方案》实施，不要只输出建议。完整方案见：`SimiGo_Native_Integration_Bootstrap_Plan.md`。

1. 先检查当前本地仓库 branch/HEAD/status/diff，并保护现有本地 K/native contract bridge、H/I/J/K 证据与 G2 冻结批次。公开 GitHub `main` 早于本地 Agent 进度时，绝不能用它覆盖当前工作树。
2. 把原生声明式结果契约集成到真实生产结算路径；精确核对 `digest_equals_binding` 与 Python bridge 的 canonical JSON/digest 语义；把 N2 改为真正未知约束并验证 fail-closed；跑 Swift Debug、相关 Release/build、当前扩展 parity suite（K2 基线 36 cases，记录实际 cases/hash）与 H/I/J 回归；对无关的既有 Release 编译阻断如实报告 BLOCKED，不误报通过。
3. 建立统一路径解析服务和 SQLite ES/IS 权威存储。SQLite 存储执行状态、结算语义结果、bindings/dependencies、外部文件元数据及 Agent 会话索引；不存储外部 work 文件或模型权重的第二份完整物理副本。
4. **优先原生 MLX G1–G3**：G1 验证真实结算结果脱离旧进程/ES 后可从 SQLite IS 恢复并继续；G2 验证外部 work 文件与 Agent session 两类来源共存、局部更新、依赖闭包失效/复用与故障恢复；G3 验证新 ES 不读取/借用/间接复用旧 ES 的 KV，且建立自己的新 KV。对每门运行真实 MLX、多进程、访问审计与负向对照；物理统一内存归还另行测量。注意：本文 G1–G3 是产品目标验收门，不等同于 Lab 中任何同名狭义实验。
5. `work` 必须是 `.simigo` 之外的外部目录，采用选择/注册/只读索引，不复制/移动/改写原文件；模型默认探测外部 Hugging Face cache（`~/.cache/huggingface`），不建立 `.simigo/models`，不复制模型权重。
6. 原生 MLX 的 G1–G3 完成前，先打磨 SQLite ES/IS 的双源索引、schema/迁移、事务一致性、局部动态更新和依赖闭包验证；LM Studio、Ollama、SGLang 等外部后端只能作为后续独立 conformance 阶段。持续为新模型建立原生 MLX 适配及验收流程。
7. 把外部二进制部署改造成可扩展的锁定版本 recipe registry。llama.cpp 是首个实现配方；其他 macOS 引擎可以后续加入；没有 adapter/conformance 的引擎只能标记 `built_not_adapted`。禁止未锁定的 `git pull`、`curl | bash` 和从 manifest 执行任意 shell。
8. 接入幂等、可恢复的 bootstrap：环境探测 → `.simigo` 目录 → 初始化/检查 DB → 迁移旧 StateGraph JSON → 选择并索引外部 work → Agent session 索引 → HF 模型探测 → 选择性下载/构建引擎 → smoke tests → 机器可读就绪报告。无模型时 ES/IS 仍应能初始化。
9. 每阶段实际修改代码并执行测试；输出真实日志与证据。不要触碰冻结和历史证据、不清理无关 worktree 差异、不 commit/push。

完成判据：本地 Native gate 成为生产权威；原生 MLX 的 G1–G3 分别通过真实模型与独立证据验收；SQLite 双源索引、局部动态更新、依赖失效和事务/恢复测试通过；重复初始化幂等；work 与模型都没有被复制；无 `.simigo/work` 或 `.simigo/models`；所有持久引用可移植且不依赖机器绝对路径；下载/构建与 adapter 状态明确分离；Debug/Release、回归、审计和新部署演练结果均有可复核报告。
