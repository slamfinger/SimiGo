# Track B Evidence-to-Findings Map — 2026-09-22

**Status**: ARCHIVE INDEX / PROVENANCE MAP  
**Scope**: Track B — Execution State Lifecycle  
**Repository**: `slamfinger/SimiGo-Lab`  
**Branch**: `refactor/research-archive-20260922`

## 1. Purpose

This file maps the already-closed Track B evidence package to the findings and
claims that are actually supported by that package.

It is an **archive-level evidence-to-findings map**, not a new experiment,
not a reopening of Track B, and not a replacement for the frozen closure
record.

No existing Track B asset is moved, renamed, rewritten, or reinterpreted by
this map.

**Research-gate effect: NONE.**  
This map does not register STEP ④, does not define a new estimand, does not
authorize new measurement, and does not change `RESEARCH_STATE.md`.

---

## 2. Provenance rule

The primary semantic anchor is:

- `trackB-execution-state/TRACK_B_CLOSURE_RESULTS_20260921.md`

The preceding F1–F5 records are evidence sources. Where a statement is a
closure-level claim, the closure record remains the controlling source for
its final scope and limitations.

The distinction used here is:

- **Evidence fact** — directly recorded observation, measurement, test result,
  or process fact.
- **Finding** — a bounded statement synthesized from already-registered
  evidence and retained within the frozen Track B scope.
- **Exclusion** — an explicit statement of what the evidence does **not**
  establish.

---

## 3. Findings map

| ID | Bounded finding | Primary evidence | Claim scope | Explicit exclusion |
|---|---|---|---|---|
| TB-FND-001 | The tested execution-state fork representation preserved continuation correctness across the tested fork/COW lifecycle. | F1, F2, F3, F4, F5-1, F5-2, F5-3, Closure v4 | Tested model/configurations and execution positions recorded by Track B. | Not a claim of correctness for all models, runtimes, concurrency modes, or production conditions. |
| TB-FND-002 | Attention KV state can be represented as shared historical segments plus a private append-only suffix without requiring a full-depth copy at fork time in the tested prototype. | F1 E3, F2, F3, F4-A/B/C | Prototype segment-table representation; fork cost and physical-growth observations are test-scoped. | Not an official MLX paged-KV capability or a production API commitment. |
| TB-FND-003 | Hybrid execution state requires different fork semantics for the tested attention KV and GDN components: attention uses disjoint append regions/page-split representation, while GDN state is safely reference-forked because its tested updates are functional. | F1 E2/E4, F2, F3, F4 | Tested Qwen3.5 MoE hybrid layout and prototype implementation. | Not a universal statement about every hybrid architecture or cache implementation. |
| TB-FND-004 | The tested representation-transition path from segmented/shared state to a continuous representation restored near-fresh steady-state decode performance after paying a one-time materialization cost. | F5-1, F5-2 | 18K–64K tested matrix; 128K Tier B cells were N/A under the memory-safety rule. | Does not establish universal performance superiority or a production performance guarantee. |
| TB-FND-005 | In the tested matrix, the performance tax of the multi-segment representation was more strongly associated with context depth than with segment count, and its magnitude varied materially across runs. | F4-E, F5-2 | Tested depths/segment configurations and repeated runs on the specified machine/model. | No static universal threshold is established; no microarchitectural proof is claimed. |
| TB-FND-006 | The tested online adaptive representation policy could select between COW and reattach using observed tax and remaining-work estimates, with low aggregate decision regret in the tested live configuration. | F5-3 Step 1, F5-3 Step 2/3 | Simulator plus 12 live trials at 64K@S4 on the specified machine/model. | Estimator robustness is explicitly not closed; the policy is exploratory, not a tuned production policy. |
| TB-FND-007 | The final lifecycle closure established that discard preserves the parent's pre-fork execution state and continuation by discarding child results rather than adopting child continuation state. | Closure v4; audit history v1→v4 | Tested execution position and final audited lifecycle harness. | Does not establish performance superiority, estimator robustness, or residency behavior. |
| TB-FND-008 | Track B established a bounded execution-state lifecycle model in which representation migration can preserve execution identity and continuation across the tested lifecycle. | Closure v4; F5-1/F5-2/F5-3 | Frozen Track B architecture proposition under the tested boundaries. | It does not establish physical residency transition across locations; Residency is outside Track B closure. |

---

## 4. Evidence facts that should not be promoted to independent findings

The following are retained as evidence facts and should not be silently
recast as general findings:

1. F1 `copy()` is lazy/O(1) at call time in the tested implementation, with
   later materialization observed during evaluation.
2. F1 page-split prototype measured 0.020 ms fork cost in its single-layer
   test and showed physical growth proportional to the private suffix.
3. F2 measured 16/16 greedy-token agreement for the true-model fork gate.
4. F3 measured Restore Depth behavior of the page-level path over the tested
   16K/24K/32K chain and recorded flatness 1.22 for that measurement range.
5. F3 measured 1.01× model-level decode tax at approximately 4.2K depth in
   one workload; later F4-E showed >1.10× tax at several long-depth
   multi-segment configurations. These are workload observations, not a
   universal zero-tax or universal-tax claim.
6. F4-A recorded the tested 32K/64K/128K × chain/branch pressure matrix with
   no structural failure within its stated bounds.
7. F5-2 recorded N/A for the 128K Tier-B cells because the estimated peak
   footprint exceeded the defined machine safety line; this is a deliberate
   boundary decision, not a missing result to be back-filled.
8. F5-3 live testing recorded 36/36 token gates and the observed regret values
   for the stated 12-trial, 64K@S4 configuration.
9. The closure experiment's performance gate passed its pre-registered form,
   but the closure record explicitly warns that execution order and thermal
   throttling confounded its absolute performance numbers. The F5-3
   interleaved comparisons are the appropriate performance evidence for that
   question.

---

## 5. Closure anchor

The final Track B closure record states:

> Track B — Execution State Lifecycle  
> Status: CLOSED / FROZEN

The frozen semantic scope includes:

- Fork / COW
- Continuation
- Multi-branch lifecycle
- Reattach
- Migration
- Migration tax
- Adaptive decision
- Discard semantics
- Parent continuation preservation

The closure record also explicitly excludes:

- performance superiority as a general claim;
- estimator robustness;
- general residency behavior.

Therefore, this map **does not reopen any of those questions**.

---

## 6. Provenance chain

```
F1 probe
  → F2 true-model gate
  → F3 restore / multi-branch
  → F4 constrained engineering validation
  → F5 representation transition
  → F5-3 adaptive policy
  → Closure v4
  → TRACK B = CLOSED / FROZEN
```

The audit history remains authoritative for corrections that occurred during
the lifecycle, including the v1→v4 discard-semantics correction. Earlier
failed or superseded variants remain historical evidence and are not erased
by the final finding map.

---

## 7. Archive and research-gate status

- **Archive action**: mapping only.
- **Existing evidence**: preserved in original Track B paths.
- **Existing closure status**: unchanged.
- **`RESEARCH_STATE.md`**: unchanged.
- **Definition / Opening STEP ④ estimand**: NOT STARTED.
- **New measurement authorization**: none.
- **Track B reopening**: none.
- **Next research question**: Residency remains a separate future research
  line and is not implied by this map.

