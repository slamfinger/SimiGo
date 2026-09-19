# V1.7 方向登记：Runtime 能力的真实使用价值验证（2026-09-19）

**性质**：外审战略路线登记（对应"V1.6 Final → V1.7 Usage"建议）
**核心问题转变**：V1.6 回答"能不能把一次执行说清楚"；V1.7 回答
**"这些 Runtime 能力到底有没有可量化的实际价值"**

## 三个实验方向（不必全做，按证据决定 V1.8）

### V1.7-0（最优先）：Runtime Benchmark Harness

建立系统性性能证据表：

| 场景 | Tokens | Cold | Warm | Restore | Rebuild | Peak RAM | KV | Swap |
|---|---|---|---|---|---|---|---|---|
| 短会话 | 10K | | | | | | | |
| 中会话 | 40K | | | | | | | |
| 长会话 | 80K | | | | | | | |
| 超长会话 | 120K | | | | | | | |

复用既有 harness（execution_bench.py / prefill_stats.py）扩展成
systematic runner；先 harness 后实验。

**状态（2026-09-19）**：Harness v0 已交付并 10K 冒烟
（`tools/runtime_matrix.py` + `docs/experiments/V17_RUNTIME_MATRIX/`）。
冒烟暴露校准项：客户端回显形状分歧（cdd0272 类）致 WARM/RESTORE 路径
失真——矩阵测量前置校准见 V17_RUNTIME_MATRIX/README.md。

**研究问题收敛（2026-09-19 修订，方向与顺序不变）**：V1.7-0 回答的不是
"把 cold prefill 优化掉"（预设答案），而是两个实验问题——
① restore 校准修好后的真实独立成本（rootfix 最终回归 restore=24.6s
实测 mode=cold/reuse=false，是第四个 cold，restore 格子至今无真值）；
② 40K–120K 档吞吐何处偏离线性（10K 四条 cold 路 ~710–775 tok/s 线性，
25s ≈ 随 token 伸缩的 prefill 计算；swap 3.5G / footprint 22G 是
拐点候选区）。

**V1.7-0 追加验收项：分相计时**——tokenization / prefill /
KV restore·materialization / MLX compile-setup / generation 五相落表。
prefill≈promptTimeS、generation≈wall−promptTime 已可推导，新探针仅
前三相。校准未关闭前不填 restore 格：失真路径上的分相计时只是把 cold
精确测四遍。

### V1.7-A：Runtime Efficiency

Reuse/Restore 收益曲线：delta = 1k/4k/8k/16k/32k 真实成本 →
**先实验再形成 policy**（restoreDeltaLimitTokens 8192 是否最优由数据
决定，不凭感觉改）。

### V1.7-B：Concurrency Probe（第一阶段不改串行）

1/2/4/8 请求矩阵：首次编译 / prefill / KV / memory / zero-output /
deadlock / cancellation / checkpoint / session isolation。
回答"谁持有什么锁、MLX 哪个阶段真正不能并发"。
若结论是"并发收益小风险高"，**serialized 保持即是实验依据的工程结论**。

### V1.7-C：Local Office Prototype

SimiGo 双翼定位：Runtime + Office。从文件任务起步
（多 Excel 分类/提取/汇总：读文件 → 本地模型理解 → 执行脚本 → 生成 →
模型检查 → 输出）——Runtime 第一次承载真实办公生产任务。

## 明确阻挡（外审红线）

❌ KV Tree（无上游原语支撑）❌ Agent Framework（Planner/Tool/Memory
全家桶）❌ ExecutionLineage 继续加字段（parentExecution/children/
causalGraph——无真实需求不创造语义）❌ 为"高级感"打开并发

## 顺序

```text
V1.6 FINAL（已封版）→ V1.7-0 Harness → V1.7-1 长上下文实验
→ V1.7-2 Concurrency Probe → V1.7-3 Local Office Prototype
→ 实验结果决定 V1.8
```
