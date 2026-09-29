# SimiGo Lab RQ Evidence Matrix — 2026-09-29

## Scope

这是当前 Execution State 研究证据索引，不是新的实验结果。每一行只在其
listed backend、model、workload、topology 和 harness boundary 内成立。

当前总状态：

```text
RQ1 = PASS_WITH_BOUNDARY / CLOSED-FOR-CURRENT-CONTRACT
RQ2 = PARTIAL / BLOCKED_BY_QWEN4EXP_MODEL_ARTIFACT
RQ3 = OPEN / EXECUTION_STATE_CANCEL_ISOLATION_PASS
      / SWIFT_EXECSTATE_HOTPATH_INTEGRATION_PASS
      / SWIFT_EXECSTATE_FORK_RESTORE_INTEGRATION_PASS
      / SWIFT_EXECSTATE_CANCELLATION_INTEGRATION_PASS
      / O6_MLX_OVERSIZED_CANCELLATION_AB_PASS
      / HIGHER_CONCURRENCY_CANCEL_ACCEPTANCE_COMPLETION_PASS
      / GREEDY_IDENTITY_BOUNDARY_OBSERVED
      / NO_CANCEL_BATCH_IDENTITY_INSTABILITY_OBSERVED
      / CANCELLATION_CAUSALITY_NOT_SUPPORTED
      / BATCH_CARDINALITY_THRESHOLD_LOCALIZED
      / GREEDY_IDENTITY_UNSTABLE_AT_CONTROL_COUNT_3_PLUS
      / DISTINCT_PROMPT_CARDINALITY_INSTABILITY_OBSERVED
      / DUPLICATE_PROMPT_CONFOUND_EXCLUDED
      / ACTIVE_SLOT_CONCURRENCY_CAUSAL_BOUNDARY
      / QUEUED_N4_STABLE
      / CONTINUOUS_BATCHING_FLAG_NOT_SUFFICIENT
O6  = PASS / QWEN3_NEXT_OVERSIZED_W0_W9_HARNESS_LEVEL
      / CANCELLATION_AB_PASS
```

最新全仓 Swift baseline：

```text
swift test = 157 PASS / 0 FAIL
```

该 baseline 对应新增 Swift LLAMA executor 后的当前 run；此前 Backend
Conformance baseline 也是 `157 PASS / 0 FAIL`。

## RQ1 — Backend Conformance

| Evidence | Scope | Result | Report / artifact |
| --- | --- | --- | --- |
| Same Execution State lifecycle on three representations | `MLXExecutionStateBackend`, `OversizedSegmentedStateBackend`, `LLAMAServerExecutionStateBackend`; current contract | PASS; `FBC-001` stale-release defect fixed | `docs/00-governance/SIMIGO_LAB_BACKEND_CONFORMANCE_OPENING_20260929.md` |
| Non-MLX live prefix smoke | llama-server, one GGUF model, ping/diverge/replay | semantic replay identical; branch diverged | `simigo2-experimental/results/backend-conformance/llama-server-live-smoke.json` |

判定边界：

```text
PASS_WITH_BOUNDARY / CLOSED-FOR-CURRENT-CONTRACT
```

不 claim universal Execution State、所有 backend、performance 或生产 readiness。

## RQ2 — Cross-architecture

| Evidence | Model / architecture | Scope | Result | Artifact |
| --- | --- | --- | --- | --- |
| O6 workload matrix V3 | Qwen3-Coder-Next / `qwen3_next` | oversized segmented, W0-W9 | PASS | `simigo2-experimental/results/o6-workload-matrix/qwen3-coder-next-4bit-v3.json` |
| E5 real-runtime scenario | Qwen3-Coder-30B / `Qwen3MoEModel` | real runtime, representation-consuming | PASS | `simigo2-experimental/results/e5-execution-state/qwen3-coder-30b.json` |
| E5 real-runtime scenario | Nail-Qwen3.6 / `Qwen35MoEModel` | real runtime, representation-consuming | PASS | `simigo2-experimental/results/e5-execution-state/nail-qwen36-35b.json` |
| E5 real-runtime scenario | Gemma-4 coder / `Gemma4Model` | real runtime, representation-consuming | PASS | `simigo2-experimental/results/e5-execution-state/gemma4-12b-coder.json` |
| Read-only candidate audit | five Qwen4Exp-family candidates | remote metadata / manifest / README only | all REJECT | `docs/00-governance/SIMIGO_LAB_RQ2_QWEN4EXP_READONLY_AUDIT_20260929.md` |

RQ2 保持：

```text
PARTIAL / BLOCKED_BY_QWEN4EXP_MODEL_ARTIFACT
```

这些证据不等于 full Qwen4Exp closure。pruned / subnet / expert-pruned
substrate 也不能替代完整 Qwen4Exp artifact。

## RQ3 — Hot path, transition, pressure, cancellation

| Evidence | Scope | Result | Report / artifact |
| --- | --- | --- | --- |
| Hot-path A/B | llama-server, one model, ordinary generation, 30 paired samples | OFF/ON semantic `30/30`; paired client delta `-0.124ms`; local bookkeeping mean `8.525µs/request` | `results/backend-conformance/rq3-llama-hotpath-ab.json`; `SIMIGO_LAB_RQ3_LLAMA_HOTPATH_AB_20260929.md` |
| Fork/restore semantics | llama-server prefix representation, 30 samples | identity/divergence/parent non-interference/restore `30/30`; local ops `3.306µs` | `results/backend-conformance/rq3-llama-fork-restore-cost-cacheRam0.json`; `SIMIGO_LAB_RQ3_LLAMA_FORK_RESTORE_COST_20260929.md` |
| Slot state cache root cause | llama-server `--cache-ram 0`, short prompts | backend transition delta reduced; root cause localized to slot state cache | same fork/restore report and artifact |
| Long-D transition pilot | `ctx512`, one slot, D `36/144/288/432`, 12 cycles each | paired deltas `-0.986/+1.685/-0.071/-0.662ms`; no monotonic growth | `SIMIGO_LAB_RQ3_LLAMA_LONG_CONTEXT_PILOT_20260929.md` |
| Backend KV pressure | `ctx512` auto `4-slot/unified KV`, 432-token D | retries/purge observed; request recovered; paired transition `+0.268ms` | `SIMIGO_LAB_RQ3_LLAMA_MEMORY_PRESSURE_PILOT_20260929.md` |
| Explicit backend cancellation | resumable stream, one slot, 20 cycles | DELETE `20/20`; recovery identical `20/20` | `results/backend-conformance/rq3-llama-cancellation.json`; `SIMIGO_LAB_RQ3_LLAMA_CANCELLATION_20260929.md` |
| Concurrent backend cancellation | `parallel2/ctx1024`, long cancel + short control, 20 cycles | DELETE `20/20`; control identical `20/20`; unaffected control `20/20` | `results/backend-conformance/rq3-llama-concurrent-cancellation.json`; `SIMIGO_LAB_RQ3_LLAMA_CONCURRENT_CANCELLATION_20260929.md` |
| Execution State cancellation A/B | local prefix mirror around explicit cancel, 20 paired cycles | OFF/ON cancel and recovery `20/20 + 20/20`; paired recovery delta `+0.088ms` | `results/backend-conformance/rq3-llama-execution-state-cancellation-ab.json`; `SIMIGO_LAB_RQ3_LLAMA_EXECSTATE_CANCEL_AB_20260929.md` |
| Swift Execution State hot-path A/B | Swift HTTP executor consumes `LLAMAServerPrefixPayload`; ordinary generation, 30 paired samples | OFF/ON semantic `30/30 + 30/30`; paired client delta `-0.007ms`; capture mean `6.171µs` | `results/backend-conformance/rq3-llama-swift-execstate-hotpath-ab.json`; `SIMIGO_LAB_RQ3_LLAMA_SWIFT_EXECSTATE_HOTPATH_20260929.md` |
| Swift Execution State fork/restore | Swift coordinator/backend/HTTP executor; 30 live samples | replay/divergence/parent/restore checks `30/30`; replay−reference `+1.926ms` | `results/backend-conformance/rq3-llama-swift-execstate-fork-restore.json`; `SIMIGO_LAB_RQ3_LLAMA_SWIFT_EXECSTATE_FORK_RESTORE_20260929.md` |
| Swift Execution State cancellation | Swift coordinator/backend around explicit one-stream DELETE; 20 paired cycles | OFF/ON accepted and recovery `20/20 + 20/20`; paired recovery delta `-0.382ms` | `results/backend-conformance/rq3-llama-swift-execstate-cancellation.json`; `SIMIGO_LAB_RQ3_LLAMA_SWIFT_EXECSTATE_CANCELLATION_20260929.md` |
| MLX oversized cancellation A/B | real segmented Qwen3-Coder-Next core; direct versus Execution State cancel/release/restore/replay; 3 cycles | all semantic/resource gates `3/3`; peak `8,132MiB`; swap `0MiB` | `results/o6-workload-matrix/qwen3-coder-next-4bit-cancellation-ab.json`; `SIMIGO2_O6_CANCELLATION_AB_20260929.md` |
| Higher-concurrency cancellation curve | llama-server `parallel4/ctx2048`; L1-L3 long streams fill all slots; 6 cycles vs same-load completion baseline | DELETE `12/12`; control batches complete `6/6`; strict greedy identity `5/6`, baseline stability `5/6` | `results/backend-conformance/rq3-llama-concurrency-curve.json`; `SIMIGO_LAB_RQ3_LLAMA_CONCURRENCY_CURVE_20260929.md` |
| No-cancel batch identity probe | same `parallel4` load, 1 long + 3 controls, no DELETE, 16 cycles | batches complete `16/16`; within-cycle identity only `8/16`; two output groups `32/16`; instability exists without cancellation | `results/backend-conformance/rq3-llama-batch-identity-no-cancel.json`; `SIMIGO_LAB_RQ3_LLAMA_BATCH_IDENTITY_PROBE_20260929.md` |
| Batch-cardinality probe | no long, no cancel; 1/2/3/4 identical greedy controls, 8 batches each | N1-N2 stable; N3 across-cycle drift `1/8`; N4 within-cycle mismatch `3/8` and across-cycle `7/8` | `results/backend-conformance/rq3-llama-batch-cardinality-no-cancel.json`; `SIMIGO_LAB_RQ3_LLAMA_BATCH_CARDINALITY_PROBE_20260929.md` |
| Distinct-prompt cardinality probe | no long, no cancel; 1/2/3/4 distinct equal-length prompts, 8 batches each; per-prompt single-load refs | N1-N2 stable; N3/N4 match own reference in only `4/8` cycles; duplicate-prompt confound excluded | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-no-cancel.json`; `SIMIGO_LAB_RQ3_LLAMA_DISTINCT_PROMPT_CARDINALITY_PROBE_20260929.md` |
| Active-concurrency isolation | same distinct-prompt probe across `parallel4/contbatch`, `parallel4/no-contbatch`, and `parallel1/queued` | N3/N4 unstable in both 4-slot configs; `parallel1` N1-N4 all `8/8` stable | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-no-cancel.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-no-contbatch.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-parallel1.json`; `SIMIGO_LAB_RQ3_LLAMA_ACTIVE_CONCURRENCY_ISOLATION_20260929.md` |
| Active-concurrency threshold | same distinct-prompt probe on `parallel2/slot512`; N3/N4 queue with max active 2 | N1-N4 all-match and across-cycle `8/8`; instability threshold is active batch count 3+ | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-parallel2-active2.json`; `SIMIGO_LAB_RQ3_LLAMA_ACTIVE_CONCURRENCY_THRESHOLD_20260929.md` |
| Backend execution isolation | same distinct-prompt active3/4 probe on CPU-only vs Metal, 8 cycles/cardinality | CPU-only N1-N4 `8/8`; Metal N3/N4 `4/8`; boundary isolated to current Metal execution path | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-cpu.json`; `SIMIGO_LAB_RQ3_LLAMA_BACKEND_ISOLATION_20260929.md` |
| Metal flag ablation | distinct-prompt N1-N4 with FA off and CPU-Moe hybrid, 8 cycles each | FA off leaves N3/N4 unstable; CPU-Moe hybrid becomes unstable at N2 | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-flashoff.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-cpumoe.json`; `SIMIGO_LAB_RQ3_LLAMA_METAL_FLAG_ABLATION_20260929.md` |
| Runtime flag ablation II | distinct-prompt N1-N4 with `--no-repack`; `--no-op-offload` seed42/seed43 | no-repack N3/N4 unstable; no-op-offload N3 unstable both seeds and N4 unstable on repeat | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-norepack.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-noopoffload.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-noopoffload-seed43.json`; `SIMIGO_LAB_RQ3_LLAMA_RUNTIME_FLAG_ABLATION_20260929.md` |
| Threadpool ablation | Metal `parallel4`, `--threads 1 --threads-batch 1`, seed42/43, N1-N4 | active3 becomes `8/8` both seeds; active4 remains all-match `6/8` and across `1/8` | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads1.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads1-seed43.json`; `SIMIGO_LAB_RQ3_LLAMA_THREADPOOL_ABLATION_20260929.md` |
| Ubatch isolation | Metal `parallel4/threads1/ubatch2`, seed42/43, N1-N4 | N1-N4 all-match and across-cycle `8/8` in both seeds; active4 mitigation observed | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads1-ubatch2.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads1-ubatch2-seed43.json`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH_ISOLATION_20260929.md` |
| Ubatch4 stability | Metal `parallel4/threads4/ubatch4`, seed42/43, N1-N4 | N1-N4 all-match and across-cycle `8/8` in both seeds | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch4.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch4-seed43.json`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH8_STABLE_20260929.md` |
| Ubatch2 × threads4 isolation | Metal `parallel4/threads4/ubatch2`, seed42/43, N1-N4 | N1-N4 all-match and across-cycle `8/8` in both seeds; mitigation independent of single-thread setting | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch2.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch2-seed43.json`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH2_THREAD4_ISOLATION_20260929.md` |
| Ubatch8 stability | Metal `parallel4/threads4/ubatch8`, seed42/43, N1-N4 | N1-N4 all-match and across-cycle `8/8` in both seeds; safe observed ubatch bound is at least 8 | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch8.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch8-seed43.json`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH8_STABLE_20260929.md` |
| NGL layer-split sweep | Metal `parallel4/ubatch512`, NGL20/30/35/37/38, active4 | NGL20/30/35/37 stable; NGL38 intermittent mismatch across three runs | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-ngl*.json`; `SIMIGO_LAB_RQ3_LLAMA_NGL_SWEEP_20260929.md` |
| Ubatch512 reproducibility | full-Metal default `ubatch512`, seed42/43, N1-N4 | N3 unstable in both seeds (`4/8`, `6/8`); N4 unstable in both seeds (`4/8`, `3/8`) | `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-no-cancel.json`; `results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-ubatch512-seed43.json`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH512_REPRODUCIBILITY_20260929.md` |
| Ubatch2 cancellation curve | original L1-L3 cancellation curve rerun with `ubatch2`, 3 cycles | strict PASS: DELETE `6/6`, baseline stable `3/3`, cancellation identity `3/3`; latency 4.2–13.6s | `results/backend-conformance/rq3-llama-concurrency-curve-ubatch2-cycles3.json`; `SIMIGO_LAB_RQ3_LLAMA_CONCURRENCY_CURVE_UBATCH2_20260929.md` |
| Ubatch8 cancellation curve | original L1-L3 cancellation curve rerun with `ubatch8`, 3 cycles | strict PASS: DELETE `6/6`, baseline stable `3/3`, cancellation identity `3/3`; latency 2.5–7.2s | `results/backend-conformance/rq3-llama-concurrency-curve-ubatch8.json`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH8_OPERATIONAL_20260929.md` |
| Ubatch8 canonical regression | Swift hot-path, fork/restore, and cancellation harnesses under `ubatch8` | hot-path `30/30 + 30/30`; fork/restore checks `30/30`; cancellation `20/20 + 20/20` | `results/backend-conformance/rq3-llama-swift-execstate-hotpath-ab-ubatch8.json`; `results/backend-conformance/rq3-llama-swift-execstate-fork-restore-ubatch8.json`; `results/backend-conformance/rq3-llama-swift-execstate-cancellation-ubatch8.json`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH8_OPERATIONAL_20260929.md` |
| Ubatch8 launch profile upgrade | canonical wrapper default changed from `ubatch2` to `ubatch8`; wrapper validated | operational profile upgraded for lower observed latency while preserving strict identity PASS | `simigo2-experimental/scripts/rq3_llama_server_mitigated.sh`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH8_OPERATIONAL_20260929.md` |
| Mitigated launch profile | canonical wrapper fixes `parallel4/ubatch2/threads4` and cache-disabled flags; smoke tested | operational profile registered; curve free timeout default hardened to `15s` | `simigo2-experimental/scripts/rq3_llama_server_mitigated.sh`; `SIMIGO_LAB_RQ3_LLAMA_MITIGATION_PROFILE_20260929.md` |
| Ubatch2 canonical regression | Swift hot-path, fork/restore, and cancellation harnesses under canonical `ubatch2` profile | all semantic checks PASS: `30/30`, `30/30`, `20/20 + 20/20`; Swift tests `157/0` | `results/backend-conformance/rq3-llama-swift-execstate-hotpath-ab-ubatch2.json`; `results/backend-conformance/rq3-llama-swift-execstate-fork-restore-ubatch2.json`; `results/backend-conformance/rq3-llama-swift-execstate-cancellation-ubatch2.json`; `SIMIGO_LAB_RQ3_LLAMA_UBATCH2_CANONICAL_REGRESSION_20260929.md` |

RQ3 当前状态：

```text
OPEN / LOCAL_STATE_NON_REGRESSION /
      FORK_RESTORE_SEMANTICS_PASS /
      SLOT_STATE_CACHE_ROOT_CAUSE_CONFIRMED /
      LONG_D_TRANSITION_PILOT_WITHIN_NOISE /
      BACKEND_KV_PRESSURE_RECOVERS /
      EXPLICIT_BACKEND_CANCEL_AND_RECOVER /
      CONCURRENT_BACKEND_CANCEL_WITH_UNAFFECTED_CONTROL /
      EXECUTION_STATE_CANCEL_ISOLATION_PASS /
      SWIFT_EXECSTATE_HOTPATH_INTEGRATION_PASS /
      SWIFT_EXECSTATE_FORK_RESTORE_INTEGRATION_PASS /
      SWIFT_EXECSTATE_CANCELLATION_INTEGRATION_PASS /
      O6_MLX_OVERSIZED_CANCELLATION_AB_PASS /
      HIGHER_CONCURRENCY_CANCEL_ACCEPTANCE_COMPLETION_PASS /
      GREEDY_IDENTITY_BOUNDARY_OBSERVED /
      NO_CANCEL_BATCH_IDENTITY_INSTABILITY_OBSERVED /
      CANCELLATION_CAUSALITY_NOT_SUPPORTED /
      BATCH_CARDINALITY_THRESHOLD_LOCALIZED /
      GREEDY_IDENTITY_UNSTABLE_AT_CONTROL_COUNT_3_PLUS /
      DISTINCT_PROMPT_CARDINALITY_INSTABILITY_OBSERVED /
      DUPLICATE_PROMPT_CONFOUND_EXCLUDED /
      ACTIVE_SLOT_CONCURRENCY_CAUSAL_BOUNDARY /
      QUEUED_N4_STABLE /
      CONTINUOUS_BATCHING_FLAG_NOT_SUFFICIENT
```

## O6 — Qwen3-Coder-Next oversized baseline

Protocol：

```text
G1.9-O6.EXECSTATE.V3
```

Workloads：

```text
W0  linear generation
W1  capture
W2  fork
W3  branch divergence
W4  restore
W5  branch release
W6  repeated fork/restore
W7  long-running branch restore
W8  memory pressure release/recovery
W9  cooperative cancellation/recovery
```

Result：

```text
checks               12/12 PASS
model                Qwen3-Coder-Next-4bit / qwen3_next
segment size         8
peak footprint       8,032 MiB <= 30,720 MiB
max swap             0 MiB
segment transitions  322
```

Artifact：

```text
simigo2-experimental/results/o6-workload-matrix/
  qwen3-coder-next-4bit-v3.json
```

该结果是 harness-level workload evidence，不是性能、生产 cancellation、
上游 runtime 或跨模型普适 claim。

## MLX oversized Phase-6 cost observation

Status：

```text
PASS_WITH_BOUNDARY / OBSERVATION_INDEX_COMPLETE / FULL_FACTORIAL_OPEN
```

| Profile | Scope | Checks | Key observation | Artifact |
| --- | --- | ---: | --- | --- |
| COST1 paired cost | direct-vs-state ordinary generation; lifecycle capture/fork/diverge/release/restore/replay | 5/5 | state local mean `0.022111ms`; lifecycle local mean `7.695876ms`, release mean `7.651396ms` | `results/backend-conformance/mlx-execstate-cost-profile.json` |
| COST2 token-length scale | prefix `8/64/256`; direct-vs-state; 1-token generation | 3/3 | latency increases across observed lengths; paired delta `-15.811/+27.744/+388.442ms`, n=2 per bucket | `results/backend-conformance/mlx-execstate-scale-profile.json` |
| COST3 release isolation | current release vs stale no-op vs restore; no generation; 30 samples | 6/6 | current release mean `4.061400ms`; stale no-op mean `0.000188ms` | `results/backend-conformance/mlx-release-cost-profile.json` |
| COST4 retain vs release/restore | 64-token prefix, 2-token generation, 4 cycles | 7/7 | action mean `0.008479/4.519990ms`; paired outputs exact | `results/backend-conformance/mlx-release-recovery-profile.json` |
| COST5 token-budget scale | budgets `1/2/4`; two cycles per strategy per budget | 5/5 | strategy-averaged generation `10,435.064/21,721.998/50,665.760ms`; transitions `6/12/24`; paired outputs exact | `results/backend-conformance/mlx-release-recovery-token-scale-summary.json` |

Consolidated artifact：

```text
results/backend-conformance/mlx-phase6-cost-summary.json
```

Phase-6 当前状态是 observation index complete，不是 performance benchmark 或
production readiness。full factorial、更大样本、分布报告、warm-KV/segment-residency
policy 和 cross-backend cost normalization仍未完成。

### Phase-6A factorial pilot

Status：

```text
PASS_WITH_BOUNDARY / FULL_FACTORIAL_PILOT_COMPLETE / STATISTICAL_FACTORIZATION_OPEN
```

新增 8-cell pilot：prefix `8/64` × tokens `1/2` × segment size `8/16` ×
strategy `RETAIN/RELEASE_RESTORE`，每 cell每 strategy `n=1`。全部 cells PASS，
paired outputs exact；RETAIN action transition全为 `0`，RELEASE_RESTORE全为 `1`；
generation transition符合 `segment count × token count`；max swap `0 MiB`。

Observation：segment size 16 的 transition数量更少，但在全部四个可比 pair中
strategy-averaged generation latency高于 segment size 8。该结果不建立最优
segment size结论。

Artifacts：

```text
results/backend-conformance/mlx-release-recovery-factorial-p*.json
results/backend-conformance/mlx-phase6a-factorial-pilot-summary.json
```

### Phase-6B targeted segment replication

Status：

```text
PASS_WITH_BOUNDARY / TARGETED_SEGMENT_REPLICATION_COMPLETE / FULL_FACTORIZATION_OPEN
```

对 PHASE6A 中最有区分度的 2-token cells做 replication：prefix `8/64` ×
segment size `8/16`，strategy `RETAIN/RELEASE_RESTORE`。PHASE6A每 strategy 1 cycle，
PHASE6B增加 2 cycles，combined每 strategy `n=3`。十项 checks全部 PASS；所有
paired outputs exact；RETAIN transitions全为 `0`，RELEASE_RESTORE全为 `1`；
generation transitions符合 `segment count × token count`。

Combined median observation：segment size 16 在 prefix 8 两个 strategy和 prefix 64
RETAIN中慢于 segment size 8；prefix 64 RELEASE_RESTORE median
`45,780.322ms`仍慢于 segment 8 的 `29,864.848ms`。segment 16 mean
`45,990.251ms`也高于 segment 8 mean `29,994.914ms`。这 replicated PHASE6A 的
结论：更少 transition不等于更低总成本。当前结果不建立最优 segment size。

Artifacts：

```text
results/backend-conformance/mlx-release-recovery-replicate-p*.json
results/backend-conformance/mlx-phase6b-segment-size-replication-summary.json
```

### Phase-6C token-budget replication

Status：

```text
PASS_WITH_BOUNDARY / TOKEN_BUDGET_REPLICATION_COMPLETE / SMALL_SAMPLE
```

将 prefix `64` / segment size `8` 的 token budgets提升到 combined每 strategy
`n=3`：budget `1/4`由 COST5 `n=2` + PHASE6C `n=1`组成；budget `2`由 COST5
`n=2` + PHASE6A `n=1`组成。九项 checks全部 PASS；所有 budgets的 RETAIN和
RELEASE_RESTORE generated token IDs/text exact；RETAIN action transitions全为
`0`，RELEASE_RESTORE全为 `1`；generation transitions为 `6/12/24`。

Median generation随 budget增长：

```text
RETAIN:          10,448.105 -> 22,858.117 -> 50,508.985ms
RELEASE_RESTORE: 10,436.751 -> 22,061.736 -> 52,059.338ms
```

但 mean被长尾拉高。budget 4 RELEASE_RESTORE包含 `149,541.501ms` run，range
`99,418.801ms`；prefix-8 supplementary 4-token run也观测到
`48,387.495 / 98,497.580ms`。因此不建立固定 token-cost或 release-penalty模型。

Artifacts：

```text
results/backend-conformance/mlx-release-recovery-token-replicate-p*.json
results/backend-conformance/mlx-phase6c-token-budget-replication-summary.json
```

### Phase-6D distribution expansion partial

Status：

```text
PARTIAL_PASS_WITH_BOUNDARY / DISTRIBUTION_EXPANSION_PARTIAL / GPU_TIMEOUT_BOUNDARY
```

尝试将 2-token cells提升到 combined每 strategy `n=5`（PHASE6A `1` + PHASE6B `2` +
PHASE6D `2`）。三个 cells完成：prefix `8 / segment 8`、prefix `64 / segment 8`、
prefix `64 / segment 16`。`prefix 8 / segment 16`连续两次遇到 Metal GPU command
buffer timeout，保持 combined `n=3`；按熔断不再自动重试。

所有 completed runs paired outputs exact；RETAIN action transitions全为 `0`，
RELEASE_RESTORE全为 `1`；generation transitions符合结构；completed runs swap为
`0 MiB`且低于 30GiB gate。完成后 cells的 generation/action分布出现长尾和较大
action波动，因此只记录 observation，不建立稳定 performance model。

Artifacts：

```text
results/backend-conformance/mlx-release-recovery-distribution-p8-t2-s8.json
results/backend-conformance/mlx-release-recovery-distribution-p64-t2-s8.json
results/backend-conformance/mlx-release-recovery-distribution-p64-t2-s16.json
results/backend-conformance/mlx-phase6d-distribution-partial-summary.json
```

### Phase-6E post-hoc distribution analysis

Status：

```text
PASS_WITH_BOUNDARY / POST_HOC_DISTRIBUTION_ANALYSIS_COMPLETE / NO_NEW_GPU_RUNS
```

对 PHASE6D 已有 samples做 robust analysis：mean、median、p05/p25/p75/p95、IQR和
Tukey 1.5×IQR fences。八个 analysis checks全部 PASS；所有 cell内 samples共享同一
generated output；generation transitions符合 `segment count × token count`；RETAIN
transitions全为 `0`，RELEASE_RESTORE全为 `1`。

Completed n=5 cells呈现 long tail。IQR analysis在 prefix `64 / segment16` 的
RETAIN arm标出 `92,221.424ms` outlier；其他 completed generation arms在该规则下
没有标出 outlier。action distributions也有长尾，但小样本 IQR不构成因果诊断。
`prefix8 / segment16` 仍只有 combined `n=3`，不足以比较。

Artifacts：

```text
results/backend-conformance/mlx-phase6e-distribution-analysis.json
```

## Open gaps

1. RQ2 缺少可用且 32GB-fit 的 full Qwen4Exp artifact；候选问题需要用户裁定。
2. RQ3 的 greedy identity mismatch 已找到 harness mitigations：Metal
   `ubatch2/4/8` 在两 seeds 中均 stable；`ubatch2` 在原始 cancellation curve 中
   使 baseline 与 cancellation identity 均 `3/3` stable，但 latency 放大到
   4.2–13.6s。NGL sweep 将敏感区收窄到 high-layer split，`ngl38` 呈间歇性
   mismatch；具体 Metal kernel / graph reduction 机制未定位，
   higher-concurrency semantic closure 未完成。
3. RQ1/RQ2/RQ3 还没有形成同一 model、同一 workload、同一 harness 的
   cross-backend closure。
4. MLX oversized Phase-6 cost observation index已完成，PHASE6A one-cycle pilot、
   PHASE6B targeted replication、PHASE6C token-budget replication和PHASE6E
   post-hoc distribution analysis也已通过；PHASE6D将三个 cells扩展到 n=5，但
   `p8/t2/segment16` 因 Metal GPU timeout保持 n=3。statistical factorization、
   完整 n=5 matrix、更多 replicates、warm-KV/segment-residency policy和
   cross-backend cost normalization仍未完成。

## Non-claims

不能从本矩阵推出：

```text
Execution State 普适成立
LLAMA-server hot path 在所有负载下零成本
fork/restore 总成本恒为微秒级
Qwen4Exp 已验证
W9 cancellation 已达到 production readiness
concurrent cancellation 已达到 production readiness
pruned / subnet Qwen4Exp 可以替代 full Qwen4Exp closure
performance 或 upstream runtime claim 已建立
MLX Phase-6 cost observation是 throughput benchmark
MLX Phase-6B replication已建立 production segment-size policy
MLX Phase-6C mean已建立稳定 token-cost model
MLX Phase-6D GPU timeout已定位为 Execution State语义错误
MLX Phase-6E IQR outlier已建立因果诊断
```

所有耗时只是当前 harness run 记录；语义 PASS 只覆盖对应 protocol 的
workload 和 topology。
