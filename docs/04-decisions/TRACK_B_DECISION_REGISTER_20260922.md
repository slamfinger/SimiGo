# Track B Decision Register — 2026-09-22

**Status**: ARCHIVE DECISION REGISTER  
**Scope**: Track B — Execution State Lifecycle  
**Repository**: `slamfinger/SimiGo-Lab`  
**Branch**: `refactor/research-archive-20260922`

## 1. Purpose

This register exposes the decisions already made during Track B in the new
archive decision layer.

It is a **provenance bridge**, not a new decision round. It does not reopen
Track B, alter the frozen closure, authorize implementation, or advance the
current research gate.

Decision authority remains with the original experiment records and,
ultimately, `TRACK_B_CLOSURE_RESULTS_20260921.md`.

**Research-gate effect: NONE.**

---

## 2. Decision register

### TB-DEC-001 — Continue Track B after F1 fork probe

**Decision**: Continue Track B; no stop-loss condition was triggered.

**Basis**:
- F1 page-split prototype fork cost was O(1) in the tested prototype.
- Physical growth tracked the private suffix rather than full depth.
- Array-level correctness passed.
- GDN reference fork showed bidirectional isolation in the tested functional
  update path.

**Scope**: F1 probe environment and implementation.

**Exclusions**:
- Not a production API decision.
- Not a universal claim about fork implementations.

**Provenance**:
`EXECUTION_FORK_F1_PROBE_RESULTS_20260920.md`

---

### TB-DEC-002 — Accept true-model fork correctness gate

**Decision**: The true-model fork correctness gate passed; continue to
restore-depth and lifecycle validation.

**Basis**:
- 16/16 greedy-token agreement against the same-chunking from-scratch control.
- Mixed attention page-split and GDN reference-fork state remained isolated.
- Parent attention offsets remained frozen during child execution.

**Scope**: Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e, stated 40-layer hybrid layout,
tested execution setup.

**Exclusions**:
- The control-group result does not establish equivalence against every
  possible prefill/chunking schedule.
- Not a production correctness guarantee.

**Provenance**:
`EXECUTION_FORK_F2_GATE_RESULTS_20260920.md`

---

### TB-DEC-003 — Accept Restore Depth and multi-branch prototype behavior

**Decision**: The tested page-level restore and multi-branch segment-table
prototype satisfied the recorded acceptance criteria; continue toward
constrained engineering validation.

**Basis**:
- Page-level restore was element-exact over the tested 16K/24K/32K chain.
- COW→COW composition remained O(number of segments) in the prototype.
- Four-way branching remained correct and showed private growth proportional
  to suffix size.
- Model-level decode tax at approximately 4.2K depth was 1.01× in the tested
  workload, while the record explicitly avoided universal zero-tax claims.

**Scope**: Recorded F3 tests.

**Exclusions**:
- Restore flatness is bounded to the measured range.
- No universal decode-tax conclusion.

**Provenance**:
`EXECUTION_FORK_F3_RESTORE_RESULTS_20260920.md`

---

### TB-DEC-004 — Treat long-depth multi-segment representation tax as an active research item

**Decision**: Reactivate the performance investigation after F4-E showed stable
>1.10× tax at several long-depth multi-segment configurations.

**Basis**:
- F4-E used warm-up, alternating execution, locked depth, and repeated
  measurements.
- 32K@S4 and 64K@S4 exceeded the 1.10× threshold in the reported means.
- Token correctness remained 72/72.
- The evidence supported a performance issue in the tested representation,
  not a correctness failure.

**Scope**: F4-E tested matrix and methodology.

**Exclusions**:
- The measured tax is not a universal rate.
- The first-order bandwidth model is an attribution model, not
  microarchitectural proof.

**Provenance**:
`EXECUTION_FORK_F4_STRESS_RESULTS_20260920.md`
and `EXECUTION_FORK_F4EF_RESULTS_20260920.md`

---

### TB-DEC-005 — Adopt reattach as a tested representation-transition mechanism

**Decision**: Treat Shared/Segmented → Continuous reattach as a valid tested
representation transition.

**Basis**:
- F5-1 passed element equality and 48/48 continuation checks.
- Steady-state post-merge performance was 1.006× of the fresh reference in
  the stated configuration.
- One-time materialization cost was measured and recorded separately.

**Scope**: 64K@4-segment F5-1 test plus the F5-2 matrix.

**Exclusions**:
- Does not imply that reattach is always beneficial.
- Break-even values are workload/configuration measurements, not universal
  thresholds.

**Provenance**:
`EXECUTION_FORK_F5_1_REATTACH_RESULTS_20260920.md`
and `EXECUTION_FORK_F5_2_MATRIX_RESULTS_20260920.md`

---

### TB-DEC-006 — Do not use a static depth/segment lookup table as the transition policy

**Decision**: Use online tax estimation rather than a fixed static threshold
table for the tested adaptive-policy direction.

**Basis**:
- F5-2 showed material cross-run variation in pre-merge tax.
- Segment-count effects were weaker and non-monotonic within the tested data.
- Therefore a static table would encode unstable observations as fixed rules.

**Scope**: Track B policy prototype.

**Exclusions**:
- This is not a production policy specification.
- Estimator robustness was not closed.

**Provenance**:
`EXECUTION_FORK_F5_2_MATRIX_RESULTS_20260920.md`

---

### TB-DEC-007 — Select the tested adaptive-policy parameters

**Decision**: For the Track B live validation, use the tested online policy
shape and set `observe_k=8`.

**Basis**:
- Step 1 simulator exposed systematic over-migration from a fixed continuation
  budget and corrected it with a rolling remaining-work estimate.
- Step 2/3 live post-hoc comparison showed k=8 had lower relative tax-estimation
  error than k=2 or k=4 in the tested data.
- Live policy validation recorded +0.9% aggregate regret against the stated
  two-strategy empirical oracle.

**Scope**: F5-3 simulator and 12 live trials at 64K@S4.

**Exclusions**:
- Not a tuned production policy.
- Estimator robustness across thermal states, models, machines, and workloads
  remains open.

**Provenance**:
`EXECUTION_FORK_F5_3_STEP1_POLICY_SIM_RESULTS_20260921.md`
and `EXECUTION_FORK_F5_3_STEP23_LIVE_RESULTS_20260921.md`

---

### TB-DEC-008 — Freeze Track B at closure

**Decision**: Track B is CLOSED / FROZEN.

**Basis**:
- Closure v4 passed the five audited lifecycle gates.
- The final discard semantics were corrected so that child results are
  discarded while the parent continues from its own pre-fork next-input.
- The closure audit explicitly fixed earlier v1→v3 semantic/misalignment
  errors before freeze.

**Frozen scope**:
- Fork / COW
- Continuation
- Multi-branch lifecycle
- Reattach
- Migration
- Migration tax
- Adaptive decision
- Discard semantics
- Parent continuation preservation

**Explicit exclusions**:
- Performance superiority
- Estimator robustness
- General residency behavior

**Provenance**:
`TRACK_B_CLOSURE_RESULTS_20260921.md`

---

## 3. Decision → Finding linkage

| Decision | Related findings |
|---|---|
| TB-DEC-001 | TB-FND-002, TB-FND-003 |
| TB-DEC-002 | TB-FND-001, TB-FND-003 |
| TB-DEC-003 | TB-FND-001, TB-FND-002 |
| TB-DEC-004 | TB-FND-005 |
| TB-DEC-005 | TB-FND-004 |
| TB-DEC-006 | TB-FND-005, TB-FND-006 |
| TB-DEC-007 | TB-FND-006 |
| TB-DEC-008 | TB-FND-001, TB-FND-007, TB-FND-008 |

Finding definitions are maintained in:
`docs/03-findings/TRACK_B_EVIDENCE_TO_FINDINGS_MAP_20260922.md`

---

## 4. Decision boundary

The register deliberately stops at the frozen Track B boundary.

It does **not** decide:

- whether or how Residency should be implemented;
- whether a Track C design is correct;
- any future estimand;
- any future sampling or measurement plan;
- any production API or release commitment.

Those questions require their own research objects, evidence, and decisions.

---

## 5. Provenance chain

```
Evidence
  ↓
Bounded Finding
  ↓
Track B Decision
  ↓
Closure v4
  ↓
CLOSED / FROZEN
```

Historical superseded decisions remain represented by the original Track B
records. This register does not erase the audit trail.

