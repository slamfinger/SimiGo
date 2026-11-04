# BENCH: Roll-forward Phase A 测量结果（2026-09-18）

**实验**：`RollForwardExperimentTests.testRollForwardPhaseA`（`SIMIGO_ROLLFWD_EXP=1` 门控）
**模型**：Nail-Qwen3.6-35B-A3B-MLX（真机生产同款）
**运行**：545 秒；rollforward 40 轮（上下文 1.7k→~58k）+ control 15 轮
**原始数据**：`results.json`（逐轮全量记录）

## 结果

### Arm R：roll-forward（每成功轮 save → 下轮 load 覆盖 → fragment）

| 档位 | fragment mean | save mean/max | load mean/max | TTFT mean | swap |
|---|--:|--:|--:|--:|--:|
| 10 轮 | 1,679 | 0.05 / 0.09s | 0.00 / 0.00s | 4.07s | 3.4GB |
| 20 轮 | 1,694 | 0.09 / 0.15s | 0.00 / 0.01s | 5.50s | 4.0GB |
| 30 轮 | 1,698 | 0.11 / 0.20s | 0.01 / 0.01s | 8.52s | 4.1GB |
| 40 轮 | 1,701 | 0.15 / 0.40s | 0.01 / 0.02s | 11.07s | 4.2GB |

- **fragment 全程恒定：1,701 ± 9 tok（max 1,710）**——准确表述：**40 轮实际
  prompt/eval 工作量保持 1,701 ± 9 tokens（上下文 1.7k→58k），未观察到
  full-context prefill 模态**。注意证据层次：message rendering 与 model
  prefill/eval 是两层，本 fixture 尚不能单独证明上游模板渲染阶段不存在
  完整 messages reconstruction（`cachedPromptTokens=0` 是 usage telemetry
  语义，不等价于内部不存在 token ledger）
- **saveCache 实测 0.15s 均值 / 0.40s 最差**（原估算 1–3s，乐观 10 倍偏差）
- **loadSessionCache 实测 0.01s**（近即时）
- 每轮 roll-forward 开销 ≈ **0.16s**；对比历史分歧税 300–490s
  （442fbf fixture 单事件成本），**数量级差异约 10³**——此为单点观测对比，
  非统一 workload 下的长期收益倍率
- TTFT 随上下文 4→11s 增长（fragment 恒定而 KV 增长的注意力/带宽代价），
  数量级上仍远低于分歧税
- saveFailures=0，loadFailures=0

### Arm C：control 活会话（无 roll-forward）

15 轮 promptMean=1,517 / max=1,693——全程 extend 无分叉。符合机制预判：
合成历史由模板确定性渲染，无法复现真实流量「模型自产 token 序 vs 重渲染
键序」的不稳定。**分歧税 before 曲线以 BENCH_442FBF_FORK_REWIND_20260918
fixture（真实流量）为准**，本臂仅作同条件健康基线。

## 探针校准备注

轮 2 记录了一次 immunity violation（promptTokens=1675 vs contextBefore=1698
× 50%）——**探针校准伪影，非真实违反**：早期轮 delta 与既有上下文同量级，
50% 启发式在 round 2 数学上必然误报。真实判据（promptTokens ≈ 全上下文）
全程未触发。后续轮次阈值应改为 round ≥ 3 或相对前轮 delta。

## 对 Phase B 的结论

经济性假设成立且裕量极大：roll-forward 每轮开销 0.16s（58k 上下文），
即使每轮都滚前，40 轮总开销 6.5s < 一次分歧税。生产切片（途径 1 §5 Phase B）
的阻塞条件已解除；残余开放项 = 长程免疫性在真实客户端回显流（非合成回显）
上的复认，建议随 Phase B 灰度一并观察。
