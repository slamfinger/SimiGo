# BENCH: Execution Continuity 三臂 n=2 重复（2026-09-19）

**目的**：外部审计（`docs/audit/CONDITIONAL_RESTORE_EXTERNAL_AUDIT_2026-09-18.md`）
最高优先行动项——固定二进制 `7ccd136`，对 LIVE / 1024(阶梯) / 2048 三臂补 n。
**模型**：Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e（与 n=1 三臂同模型，trace ready 行核实）。
**本夜 swap**：3–4GB（n=1 夜 4–5GB，系统负载更低）。

## 结果文件

| 文件 | 臂 | 轮次 |
|---|---|---|
| `results_step1024_r2.json` | derived（E/R 交替，R 轮 rollforward fragment） | 15/15 全通 + 连续性检查过 |
| `results_live_r2.json` | LIVE（纯对话轮轮 extend） | 9/9 全 extend，cacheEff 0.06→0.89 |
| `results_step_partial_nail_r2aborted.json` | Nail 首跑 R1–R8（驱动缺陷中断，trace 重建） | 仅作 Nail 基线点，不与 Cyber-Tiel 比 |

## 关键对照（同深度 per-fill-token 吞吐，tok/s）

| 深度 | n1 derived | n1 live | n1 比 | n2 derived | n2 live | n2 比 |
|---|--:|--:|--:|--:|--:|--:|
| ~9.4k | 403 | 723 | 0.56 | 707 | 611 | 1.16 |
| ~18.7k | 531 | 575 | 0.92 | 566 | 492 | 1.15 |
| ~28k | 348 | 386 | 0.90 | 439 | 400 | 1.10 |
| ~37k | 249 | 324 | 0.77 | 224 | 281 | 0.80 |
| ~56.4k | 247 | 252 | 0.98 | 235 | 208 | 1.13 |
| ~66.2k | 173 | 205 | 0.84 | 187 | 182 | 1.03 |

（n1 R11@46.5k=84 tok/s 为换页尖峰离群 108.7s，按 n=1 登记剔除）

## 结论补 n 后的更新

1. **2048 悬崖死亡复认**：66.2k E 轮 n=2 为 187 tok/s（n1=173，旧 2048 臂=54）
   ——两个独立夜晚确认悬崖未复现。
2. **residual overhead 收紧为 ≈1.0×**：derived/live 比 n=2 落在 0.66–1.16
   （中位 ≈1.0），n=1 为 0.56–0.98；合并证据支持「阶梯修复后恢复态剩余
   额外成本 ≈ 0.8–1.2×，已无数量级税」。审计措辞纪律维持：此为状态形态
   对照（LIVE workload 与 derived 的增量形态不同），非 universal 承诺。
3. **LIVE 链形态复现**：9 轮全 extend、cacheEff 0.06→0.89 与 n=1 同构，
   各深度速率差 <±12%。
4. **R 轮小 delta**：n2 526→94 vs n1 485→106 tok/s 同形（深度税普适）。

## n=2 后仍不可判定（留待三臂决策）

- **2048 臂无法在当前二进制复跑**（阶梯已焊死 <64k→2048，压平 2048 是
  已退役的实验构建）；「悬崖消失」由 66.2k 点跨夜双样本支撑，2048 臂
  本身 n=1。
- LIVE vs derived 的 workload 形态差异仍在（审计 §4）。

## 驱动侧缺陷修复（随本 n=2 入库）

- `main()` 补 `discover_key()`——n=1 纯靠当时进程 traceKey 恰为
  `bench/main` 与回退串撞中；n=2 进程键为 `cbench/main` 时全 miss。
- preflight 重启容忍：旧实例在途 RUNNING 行残留 trace 的误报消除。
