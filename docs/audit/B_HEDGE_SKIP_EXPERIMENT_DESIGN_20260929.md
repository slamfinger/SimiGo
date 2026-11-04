# EXP-B DESIGN — hedge-skip 生产规模对照实验（2026-09-29，design-only）

> 状态：**设计冻结待批准**。本文档批准前不写任何生产代码。
> 上游依赖：实验 A = PASS（BETA4_PROD_FINDINGS_20260929 §3）。
> 目标一句话：验证在 warm-session + 高 cache continuity 条件下跳过
> conditional restore，能否消除生产规模（~27k checkpoint）的 restore
> 固定成本（~346ms），同时保持与 A 完全一致的 Execution State 语义。

## 1. 机制定义（最小 diff）

**开关形态（待批准项 ①）**：全程 env-gated，零产品语义——

```text
SIMIGO_EXP_HEDGE_SKIP=1                                  # 缺省关闭 = A 行为
SIMIGO_EXP_HEDGE_SKIP_THRESHOLD=0.95                     # 实验阈值，非产品语义
```

**判定条件**（restore 尝试之前）：

```text
warmSession（reusedSession == true）
&& lastCompletionMode == "extend"
&& lastCompletionCacheEff >= threshold
    → skip conditional restore（trace: action=hedgeSkip）→ direct extend
```

- 状态载体：ManagedSession 增加运行时字段
  `lastCompletionMode: String?` / `lastCompletionCacheEff: Double?`，
  轮末从 info 块写入。**不持久化**——重启后为 nil → 对冲保持开启
  （保守回退：未知状态不跳过 restore）。
- 触碰面清单（就这些，其余全不动）：ManagedSession 两字段、轮末写两行、
  restore 块前一个条件 + 一行 hedgeSkip trace、RuntimeTuning 两个实验
  env 读取。reconciliation / gate 结构 / cacheLoad / retention / token
  export / checkpoint 格式零改动。

## 2. 负载规范（生产规模校准）

- 模型/硬件/客户端形态与 A 完全一致：Nail-Qwen3.6-35B-A3B-MLX、32GB、
  Codex 同款回显（assistant content:null、arguments 字符串化）、
  session header ≤6 字符。
- **规模校准修正**：A 的 90KB 中文垫底经 BPE 压缩实测仅 8.3k token。
  B 的目标 promptTokens ≥ 25k（目标 27k±10%，与生产 22:20 日志同量级）
  → 垫底体积按实测比例外推至 ~280KB，且**先做一次校准预跑**确认
  promptTokens 落窗后再进入正式采集。
- 轮数：每态 10 工具轮 + 1 总结轮。
- checkpoint 规模预期：27k 上下文 → GB 级 safetensors，restore 成本
  应复现生产 ~346ms 量级；若实测 <50ms，则 B 的前提（346ms）需要重估
  （诚实出口，见 §6）。

## 3. 运行矩阵（三态对照，两个独立 session）

| 态 | 配置 | session | 预期行为 |
|---|---|---|---|
| B0（A 基线） | 无 env 开关 | `expb0` | restore → rollforward → extend（每轮 346ms） |
| B1（hedge-skip） | `SIMIGO_EXP_HEDGE_SKIP=1` | `expb1` | 首轮后 restore 全跳过 → direct extend |

- 两个独立 session：避免 B0 的 checkpoint 与 B1 的判定交叉污染；
  各自冷启动第一轮 + 10 工具轮，按 round index 配对比较。
- 顺序：B0 先、B1 后；同一 binary（含开关，env 区分），单次构建。

## 4. 测量增强（待批准项 ②）

现有 trace 的 cacheLoad 只有完成时刻，成本内部不可分。B 的实验 commit
申请新增**一个实验性 trace 字段**：`cacheLoadMs`（performLoad 起止
单调钟差），用于把 restore 成本从 preflight 中精确拆出。实验后该字段
去留另行议定。除此之外日志语义零变更。

## 5. 指标与硬门槛

| 指标 | B0（A 基线） | B1（hedge-skip） |
|---|---|---|
| cacheLoadMs | ~346ms 量级（实测分布 ×10） | 应消失（无 cacheLoad 行） |
| action=rollforward | 10/10 | 0（全部 hedgeSkip） |
| cacheEff | ~1.0 | **必须保持 ~1.0** |
| cacheHitTokens | 全额 | **必须全额** |
| TTFT / wall | baseline | baseline − restore 成本附近 |
| tool lifecycle | 正常 | **必须正常** |
| bindingGen | 连续 | **必须连续** |
| transcript | 正常 | **必须正常** |
| anomalies / REJECTED / unknown_tc | 0 | **必须 0（硬门槛）** |
| checkpoint 一致性 | cacheSave 全成功 | **必须全成功** |

后五项为 **B 的硬门槛**：任一破坏 → B FAIL → 关闭 env 开关即回到 A
行为（零代码回滚成本），findings 回写 FAIL 结论。

## 6. 统计与判定

- 主指标：配对 round 的 TTFT/wall 差值（B1−B0），预期 ≈ −restore cost。
- restore cost 实测分布：B0 的 10 个 cacheLoadMs 样本（中位数 + 极差）。
- **B PASS**：全部硬门槛保持 + TTFT/wall 差值 ≈ −restore cost。
- **诚实出口**：若 B0 实测 restore cost 远低于预期（<50ms），则"346ms
  前提"不成立，B 的价值重估、结论如实回写。
- PASS 后的**设计演化方向**（非本实验产出）：conditional restore 从
  "默认 hedge"改为"有条件 hedge"——正常 warm continuation 直接 extend，
  divergence/cold/uncertain 状态才 restore。阈值的产品化形态留待该
  阶段的设计讨论。

## 7. 回滚与边界

- env-gated：不开开关 = A 行为 = 可发布语义；实验 commit 不触碰
  reconciliation / gate 结构 / retention / token export / checkpoint 格式。
- 不动 beta.4 工件、tag、provenance 锚。
- 结论（PASS/FAIL）回写 BETA4_PROD_FINDINGS_20260929.md §3。
- push 纪律不变：A/B/Findings 全部 commit 在 B 结论出来后一并决策。

## 8. 待批准项汇总

1. env 开关形态（`SIMIGO_EXP_HEDGE_SKIP[_THRESHOLD]`）；
2. 实验性 trace 字段 `cacheLoadMs`；
3. 双独立 session（expb0/expb1）矩阵。
