# Track D — Adaptive Memory（独立推进）

**研究问题**：运行时知道"现在能安全使用多少内存"，替代静态
`mlxMemoryLimitBytes = 22GiB` / `mlxCacheLimitBytes = 4GiB`
（主仓 `RuntimeTuning.swift:8-12`）。

**公式链（报告 §5.4）**：Physical Memory → System Available →
Model/KV Requirement → Runtime Working Set → **Dynamic Budget**。

**安全边界（防自杀式自适应）**：硬性保留量（物理内存 15–25% 或固定值
取大者）+ memory pressure 事件**主动**收缩（不等 swap 发生）。

**落地验证**：256K prefill 实测"预算放宽不引入 swap 劣化"
（1024 档教训的制度化）。

**状态**：未开工。不依赖 Track A/B/C，可先行；实验室阶段做预算模拟，
生产化随 Level 门迁回主仓 RuntimeTuning。
