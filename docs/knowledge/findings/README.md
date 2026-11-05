# Findings

本目录保存 2026-09 阶段从具体实验和生产观察提炼的历史 Findings。它们是有范围的证据解释，不自动描述当前 main 的实现，也不自动成为当前架构约束。

每条 Finding 应说明：

- Evidence
- Interpretation
- Alternative explanations
- Boundary conditions
- Consequence

## 当前性边界

- 每条记录的证据日期、模型、机器、版本与 commit 是结论适用范围的一部分。
- 上游依赖、运行时架构或产品实现变化后，旧 Finding 不能不经复核直接外推。
- 本目录中的结论可作为当前研究的历史输入，但不得覆盖根 README 所述的 ES / IS / Backend 权威边界。
- Finding 可以进入 Decision，但不自动成为 Invariant；需要新证据时应新增当前基线复核，不改写旧证据。
