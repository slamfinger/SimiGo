# BENCH: 442fbf/main fork-no-rewind 成本形态基准（2026-09-18）

**用途**：任何涉及 fork / checkpoint / admission / prefill scheduler 的修改，
对照本基准回答一个问题——**「这次修改有没有改变已知的 fork-no-rewind 成本形态？」**
而不是重新从运行日志里人工找证据。

## 出处与采集

- 模型：peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e（qwen3.5 混合架构，
  GDN 层 `isTrimmable=false`）
- 引擎：SimiGo 1.4 Build 2（01b5ba5 构建，04:28 上线）
- `trace_segment.log`：04:28:11 引擎 ready → 当日窗口结束的**原始未删节** trace
  （483 行，含 `[LC]`/`admission`/`prefillStep`/`session=` 全部行，未做任何清洗）
- 会话 `442fbf/main`：真实 agent 工作负载（73+ 消息，含 Edit/Bash/Read 工具循环）

## 期望统计（`python3 tools/prefill_stats.py trace_segment.log --session 442fbf`）

| mode | n | tokens 总量 | mean | P95 | time(s) 总量 | mean | P95 |
|---|--:|--:|--:|--:|--:|--:|--:|
| cold | 1 | 17,663 | 17,663 | 17,663 | 35.4 | 35.4 | 35.4 |
| extend | 30 | 55,186 | 1,840 | 4,842 | 553.4 | 18.4 | 20.1 |
| rebuild | 0 | 0 | — | — | 0 | — | — |
| **fork-no-rewind** | **6** | **395,389** | **65,898** | **80,182** | **1,791.9** | **298.7** | **440.5** |

- 浪费占比（fork-no-rewind + 既有会话 cold）/ 总量 = **84.4%**
- fork 系 `divergenceToken`（= promptTokens − fork@common）合计 **3,452**

## 关键判读（勿随版本漂移）

1. **`fork@common` 是分歧位置报告，不是缓存复用**。末轮
   `fork@common=82716/82919`（99.76% 公共前缀，仅 203 tok 分歧）仍全量重渲
   83,539 tok / 487.6s（171 tok/s = 全量预填速度）。`promptTime ÷ promptTokens`
   实锤物理全渲。
2. **放大率**：3,452 tok 实际分歧 → 395,389 tok 重渲 ≈ **115×**。
3. **节奏**：每 4-8 轮一次，与 TodoWrite 键序分叉机制吻合
   （JSONValue round-trip 键序不稳定 × GDN `isTrimmable=false`，见
   FIELD_OBSERVATION §7/§11 与 `qwen35-hybrid-cache-rebuild` 记忆）。
4. **decode 退化**：decode tps 随上下文 33 → 6.7（83k KV + swap）。

## 遥测诚实性

`fork@common=X/Y` 为**本仓库 vendor telemetry**（本地 mlx-swift-lm 补丁
5ba0bc1 + SimiGo 3b127ba，+36 行），非上游原生能力。引用本基准数据到
上游 issue 时必须标注此出处，见
`docs/experiments/UPSTREAM_ISSUE_DRAFT_qwen35_tool_restart_rule.md`。

## 复验

```bash
python3 tools/prefill_stats.py docs/experiments/BENCH_442FBF_FORK_REWIND_20260918/trace_segment.log --session 442fbf
```

输出应与上表一致（窗口时间戳随采集文件固定）。语义变化（而非数值抖动）
即构成回归信号：例如 fork-no-rewind 的 n 上升、divergenceToken 占比下降、
或 extend 均值劣化。
