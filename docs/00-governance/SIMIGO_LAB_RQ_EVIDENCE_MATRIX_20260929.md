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
```

所有耗时只是当前 harness run 记录；语义 PASS 只覆盖对应 protocol 的
workload 和 topology。
