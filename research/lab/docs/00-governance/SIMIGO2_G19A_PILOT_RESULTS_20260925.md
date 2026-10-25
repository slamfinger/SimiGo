# G1.9-A Instrumentation Pilot — Design Audit & Results — 2026-09-25

Status: G19A_PILOT_PASS / TRACE_COLLECTION_PENDING
Protocol: G1.9-A.PILOT.V1 (fixed prompt set × 3 repetitions, per model)
Boundary: ISOLATED_INSTRUMENTATION / LAYER_ENTERED_ONLY / OBSERVER_PASSIVE / NOT_DEMAND / NOT_PREDICTION / EXPERT_DEMAND_NOT_INSTRUMENTED
Authorization: docs/00-governance/SIMIGO2_G19A_ISOLATED_INSTRUMENTATION_AUTHORIZATION_20260925.md

## Design audit decisions registered before the run

1. **Granularity = Layer / Group.** Router / Expert / Token×Expert are not
   instrumented (Minimum Sufficient Resolution). Observation scope =
   decoder MLP down-projections only; core entry is not directly observed
   (`CORE_NOT_DIRECTLY_OBSERVED`).
2. **Observer is passive.** The instrumentation changes no parameters,
   inputs, structure, execution order, cache, or residency; it emits a
   lightweight event and performs no extra tensor computation, and makes no
   decision from observations.
3. **Observed vs Derived separation.** Events assert only
   `kind = layerEntered` (layer identity + execution ordinal). step IDs and
   group joins are derived bookkeeping at report time from the declared
   inventory partition. No demand quantity exists anywhere in the data
   model — `executed ≠ demand` is enforced structurally: the JSON contains
   no demand/priority/probability field (unit-tested).
4. **Naming.** The trace type is `MeasuredExecutionTrace` (observation);
   demand remains a later interpretation with no data structure here.
5. **Shared-expert exclusion.** Module-path discovery showed
   `Qwen35MoEModel` also exposes `mlp.shared_expert.down_proj` per layer;
   its path suffix places it outside both capture patterns, so every event
   maps to exactly one declared optional group.

## Module-path discovery (why it was needed)

G1.9-B validated capture paths on Qwen3-Coder only. Discovery
(`simigo2ctl module-paths`) registered the actual per-model-class naming:

| Model class | Prefix | down_proj variants |
|---|---|---|
| `Qwen3MoEModel` (Qwen3-Coder) | `model.layers.N` | `mlp.switch_mlp.down_proj` |
| `Qwen35MoEModel` (Nail, Cyber-Tiel) | `language_model.model.layers.N` | `mlp.switch_mlp.down_proj` (+ `mlp.shared_expert.down_proj`, excluded) |
| `Gemma4Model` (Gemma4) | `language_model.model.layers.N` | `mlp.down_proj` |
| `MuseGlimmerTextLLMModel` (Muse-Glimmer) | `model.layers.N` | `mlp.down_proj` |

The observation filter accepts both suffixes under any prefix.

## Pilot v0 defects found and fixed (audit trail)

1. Identity compared baseline **prompt** token IDs against instrumented
   **generated** token IDs — categories, not comparable. Fixed: baseline
   generated tokens are recorded from the steady baseline generation.
2. The instrumented logits forward emitted events into the box without a
   clear, contaminating rep 0 with one extra pass (24+1). Fixed: box cleared
   after the identity forward.
3. `allObservationPaths` required the `model.layers.` prefix, silently
   instrumenting zero modules on three of five model classes. Fixed via the
   discovery above (the first run's `instrumentedModuleCount = 0` artifacts
   were discarded; all five models were re-run).

## Results (5 models × 3 prompts × 3 repetitions)

### G1.9-A.1 Baseline Identity — PASS (15/15 cases)

Every case: generated token sequences identical baseline vs instrumented;
full-prompt logits SHA-256 bitwise identical; `max_abs_diff = 0.0`,
`relative_diff = 0.0`.

### G1.9-A.2 Trace Stability — PASS (15/15 cases)

All three repetitions of the same input produce identical event streams
(module + layer sequences); pass counts equal across repetitions
(e.g. Qwen3-Coder P1 = [2,2,2], P2 = [24,24,24]; Muse P1–P3 = [24,24,24]).
Per the design audit: **stability ≠ predictability** — this only establishes
that the instrumentation observes execution stably.

### G1.9-A.3 Instrumentation Overhead — recorded, ACCEPTABLE, no threshold

| Model | mean ratio (rep-mean / timed baseline) | min–max | peak mem Δ |
|---|---:|---:|---:|
| Qwen3-Coder-30B | 2.433 | 1.959–2.691 | 3.0 MB |
| Nail-Qwen3.6-35B | 1.430 | 1.069–2.126 | 0.0 MB |
| Cyber-Tiel-35B | 2.203 | 0.983–3.893 | 0.0 MB |
| Gemma4-12B | 0.908 | 0.834–1.036 | 8.5 MB |
| Muse-Glimmer-30B | 3.248 | 0.719–7.950 | 1.5 MB |

Single timed baseline vs mean of three instrumented reps, on generations
of a few hundred milliseconds to a few seconds — highly noise-exposed.
The direction is inconsistent across models (Gemma4 < 1; Cyber-Tiel and
Muse minima < 1), which is not the signature of a systematic instrumentation
cost; event-only capture is designed for ≈0 cost. Qwen3-Coder's consistent
>1.9 ratio is flagged for a dedicated timing comparison during the
collection phase if it persists (possible kernel-path difference in the
traced quantized-switch replacement). Peak memory overhead is negligible.
No universal threshold is declared, per the design audit.

### G1.9-A.4 Cross-model Viability — PASS (5/5)

```text
Qwen3-Coder-30B (switch, 48 layers)   48 modules instrumented, PASS
Nail-Qwen3.6-35B (switch, 40 layers)  40 modules instrumented, PASS
Cyber-Tiel-35B (switch, 40 layers)    40 modules instrumented, PASS
Gemma4-12B (dense, 48 layers)         48 modules instrumented, PASS
Muse-Glimmer-30B (dense, 52 layers)   52 modules instrumented, PASS
```

The two `language_model.model.layers.*` naming variants and the dense path
are covered. Muse-Glimmer's semantic-quality UNRESOLVED status is irrelevant
here: instrumentation validity compares baseline vs instrumented outputs of
the same model, which are identical.

## Verdict

```text
G1.9-A.1 = PASS
G1.9-A.2 = PASS
G1.9-A.3 = ACCEPTABLE (descriptive; no systematic cost established)
G1.9-A.4 = PASS (primary 3/3 + compatibility extension 2/2)
```

Per the fixed phase rule, the pilot qualifies the instrumentation for the
next phase — **Measured Execution Trace Collection** — after which the
declared `WorkloadTrace → state` line and the measured
`Input → ExecutionTrace` line are placed side by side and locality
quantities (recurrence, transition overlap, next ⊆ previous, working-set
breadth, temporal locality) are recomputed on measured data, re-examining
G4 source legitimacy.

This is not yet a locality result and does not reopen the Predictor
question. Predictor / probability / speculative loading / Expert or
Token×Expert demand / production MLX modifications / async I/O remain
unauthorized.

## Artifacts

```text
simigo2-experimental/results/g19a-pilot/{qwen3-coder-30b,nail-qwen36-35b,
  cyber-tiel-35b,gemma4-12b-coder,muse-glimmer-30b}.json
```
