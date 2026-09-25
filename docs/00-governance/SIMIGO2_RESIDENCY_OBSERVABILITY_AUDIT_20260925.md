# Residency Observability Audit — 2026-09-25

Status: RESIDENCY_OBSERVABILITY_AUDITED / BYTE_LEVEL_VALIDATED / GROUP_LEVEL_POLICY_ONLY
Boundary: POLICY_RESIDENCE_IS_BOOKKEEPING / BYTE_OBSERVATION_IS_INDEPENDENT / NOT_DEMAND / NOT_PREDICTION

The G1.9-C post-audit froze the research tree at "Residency Observability
Audit". This audit answers the four registered questions with code evidence
and a new byte-level validation over existing artifacts. It decides which
branch the tree takes next.

## Q1 — What is the actual resident set in the current experiments?

Per transition, the Gate 5 harness maintains a Swift-side bookkeeping
variable (`var resident` in `MLXGroupResidencyBenchmark.stateDrivenPass`;
release-to-empty in `naiveOnDemandPass`; never-released in `allResident`).
No per-transition group-residency list is written to the artifacts — only
the executed transfer lists (`reloadedGroupIDs`, `releasedGroupIDs`) and
MLX memory snapshots (`ready/generated/idleActiveBytes`) are recorded.

```text
group-level resident set = POLICY BOOKKEEPING (derived)
```

## Q2 — What is the planner desired/retained set?

The planner's `ResidencyPlan` outputs (load / keep / evict / overflow) are
decision records computed before each transfer. They are the policy line,
distinct from Q1's bookkeeping only in that they are the plan; the executed
bookkeeping follows them.

## Q3 — What materialization/load/eviction actually happened?

The transfer records are real observations: each load/release was executed
against the live model (`container.perform` parameter updates) and timed
with byte counts; every benchmark run passed output-identity, so the
executed transfers did not change compute semantics.

```text
transfer log = OBSERVED (executed + timed)
```

## Q4 — Which data is recorded vs merely policy-derived?

```text
OBSERVED   : executed transfer log (groups, bytes, milliseconds);
             MLX aggregate active/cache/peak memory snapshots
DERIVED    : per-transition group resident set (bookkeeping from
             transfers + planner decisions)
ABSENT     : independent per-group runtime residency observation
             (a probe asking "are group G's parameters materialized now?")
```

## New evidence — byte-level validation (computed in this audit)

If the bookkeeping is correct, the measured idle active bytes after each
transition must equal the summed inventory bytes of the predicted resident
set. `scripts/audit_residency_observability.py` recomputes this from the 20
real trace artifacts (5 models × 4 workloads; 75 transitions each across
three policies) and the per-model inventories:

```text
Qwen3-Coder-30B   max |dev| 0.038 MiB   max rel 4.6e-5
Gemma4-12B        max |dev| 2.319 MiB   max rel 3.6e-4
Muse-Glimmer-30B  max |dev| 4.939 MiB   max rel 6.6e-4
Nail-Qwen3.6-35B  constant deviation −851.1 MiB across all 75 transitions,
                  all three policies (exactly constant to 0.1 MiB)
Cyber-Tiel-35B    constant deviation −851.5 MiB, same signature
```

The Nail/Cyber-Tiel constant offset is reconciled: both checkpoints are
multimodal-family packages whose safetensors index includes a
`vision_tower` (333 tensors, 851.8 MiB) that the text-path model class does
not instantiate. Index-span arithmetic reproduces the offset within
< 0.8 MiB residual. The deviation is therefore an inventory-vs-loaded-model
reconciliation item, not a residency-tracking error.

```text
VERDICT: after the model-class constant offset, the policy bookkeeping and
the independent MLX byte observation agree exactly (≤ 0.1 MiB over 225
transitions on the offset models; ≤ 5 MiB elsewhere).
```

## Audit verdict (branch decision)

Split, per the registered decision rule:

1. **Byte-level ObservedResidency exists and is sufficient**: aggregate
   memory snapshots are independent observations, and they validate the
   policy bookkeeping exactly. Byte-level retention curves may be treated as
   observed quantities.
2. **Group-level residency is PolicyResidency only.** There is no
   independent per-group runtime observation, and a non-perturbing one
   appears unavailable at the current public API — any probe that touches a
   group to test its residency would materialize it, changing the observed
   state (consistent with the G1.9-A API audit's REJECTED conclusion for
   direct public-API capture; a runtime-side mechanism would be a production
   MLX modification, which is unauthorized).

Naming discipline for any following analysis:

```text
allowed   : "PolicyResidency retention structure (byte-validated)"
forbidden : "natural/true residency demand", "observed residency locality"
```

`R_t ∩ R_{t+1}` structure over group sets may be studied, but it is the
retention structure of the policy, not a naturally observed locality. The
observed quantities for any such analysis remain the transfer log and the
byte snapshots.

## Next-gate options (user decision, not entered)

a. Residency locality analysis under the labels above (PolicyResidency,
   byte-validated; observed transfer/byte quantities alongside);
b. a minimal per-group residency observation mechanism — requires either
   perturbing probes (changes what is observed) or runtime support
   (production MLX modification) — both new authorization decisions;
c. STOP here: the execution/residency separation plus byte-validated
   policy bookkeeping is already a complete engineering-accountability
   result.

No new runtime capability, predictor, async I/O, or production MLX
modification follows from this audit. A2.0 remains FROZEN/TERMINAL.

## Artifacts

```text
simigo2-experimental/scripts/audit_residency_observability.py
simigo2-experimental/results/residency-audit/{slug}-inventory.json (5)
simigo2-experimental/results/residency-audit/byte-validation.json
```
