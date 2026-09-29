# SimiGo Lab MLX Execution State Phase-6 Cost Summary — 2026-09-29

## Result

```text
PHASE6_STAGE = PASS_WITH_BOUNDARY / OBSERVATION_INDEX_COMPLETE / FULL_FACTORIAL_OPEN
```

该文档索引并解释 COST1–COST5 的五组 oversized MLX Execution State cost
observation。它是 observation index，不是 throughput benchmark、production
performance claim 或 release-policy recommendation。

## Scope

```text
model       = local Qwen3-Coder-Next-4bit / qwen3_next
segment     = size 8 / 6 segments
executor    = cacheless greedy prefix recompute
representation = token-prefix Execution State payload
boundary    = harness-level observation, current model/build/workload only
```

## Profile index

| ID | Scope | Checks | Key observation |
| --- | --- | ---: | --- |
| COST1 | paired direct-vs-state generation; lifecycle capture/fork/diverge/release/restore/replay | 5/5 | state local bookkeeping mean `0.022111ms`; lifecycle local mean `7.695876ms`,其中 release mean `7.651396ms` |
| COST2 | prefix lengths `8/64/256`,direct-vs-state,1-token generation | 3/3 | direct/state means 随 prefix length增长; paired delta `-15.811/+27.744/+388.442ms`,每 bucket n=2 |
| COST3 | release action isolation,无 generation,lengths `8/64/256`,每 length 10 samples | 6/6 | current release mean `4.061400ms`; stale no-op mean `0.000188ms`; capture/restore 在微秒级 |
| COST4 | RETAIN vs RELEASE_RESTORE,2-token generation,4 cycles | 7/7 | action mean `0.008479/4.519990ms`; paired outputs exact; generation差异 n=4,不解释为 penalty/benefit |
| COST5 | RETAIN vs RELEASE_RESTORE across `1/2/4` token budgets,每 strategy每 budget 2 cycles | 5/5 | strategy-averaged generation `10,435.064/21,721.998/50,665.760ms`; transitions `6/12/24`; paired outputs exact |

## Cross-profile interpretation

### 1. Local state operations are not the dominant cost

COST1 的 no-fork state local bookkeeping mean 约为 `22µs`。COST3 中 capture /
restore 也在微秒级。

### 2. Oversized release is a real local action

COST3 把 release 从 generation 分离后，current release mean 约 `4.06ms`；
stale release 是 no-op。COST1 lifecycle local cost约 `7.70ms`,主要来自 release。
因此不能把 oversized release与 LLAMA token-prefix dictionary release直接比较。

### 3. Prefix length trend is observational

COST2 观测 direct mean约 `9.95 / 11.94 / 17.18s`,state mean趋势类似。样本
规模小，不建立曲线或定量模型。

### 4. Release/restore does not change paired outputs

COST4/COST5 中 RETAIN 和 RELEASE_RESTORE 的 generated token IDs/text 两两配对
exact。COST4 的 generation mean差异方向不稳定且样本小，因此不声称 release
带来加速或惩罚。可归因差异是 action cost和 segment transition:
`0 vs 1`。

### 5. Token budget scaling is observable but not modeled

COST5 中 generation transition delta为 `6 / 12 / 24`,与 6 segments和 token
budget成比例。strategy-averaged generation latency随 budget增长，但小样本不建立
throughput曲线。

## Combined checks

| Check | Result |
| --- | --- |
| `ALL_SOURCE_REPORTS_PASS` | PASS |
| `ALL_SOURCE_CHECKS_PASS` | PASS |
| `ALL_EXPECTED_PROFILES_PRESENT` | PASS |
| `ALL_TOKEN_SCALE_RUNS_PASS` | PASS |
| `ALL_RECOVERY_PAIRED_OUTPUTS_EXACT` | PASS |

## Artifact

```text
simigo2-experimental/results/backend-conformance/mlx-phase6-cost-summary.json
```

Source artifacts:

```text
simigo2-experimental/results/backend-conformance/mlx-execstate-cost-profile.json
simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile.json
simigo2-experimental/results/backend-conformance/mlx-release-cost-profile.json
simigo2-experimental/results/backend-conformance/mlx-release-recovery-profile.json
simigo2-experimental/results/backend-conformance/mlx-release-recovery-token-scale-summary.json
simigo2-experimental/results/backend-conformance/mlx-release-recovery-tokens1.json
simigo2-experimental/results/backend-conformance/mlx-release-recovery-tokens2.json
simigo2-experimental/results/backend-conformance/mlx-release-recovery-tokens4.json
```

## Open questions

1. prefix length × generated tokens × segment size × release/normalize action 的
   statistical factorization。PHASE6A已完成 one-cycle pilot；每 cell每 strategy
   仍只有 n=1。
2. 更多 samples、order counterbalancing、median/IQR/p95 分布报告。
3. warm-KV 或 segment-residency policy不在当前 cacheless path内,需要单独机制。
4. cross-backend cost normalization尚无定义,不能与 LLAMA cost直接比较。

## Non-claims

```text
❌ throughput benchmark
❌ production performance readiness
❌ warm-KV retention
❌ release-policy recommendation
❌ cross-backend / cross-hardware comparison
❌ prefix-length 或 token-budget 定量曲线
```
