# Minimal PIR Probe — v0.2 Design

> **Status:** DESIGN V0.2 DELIVERED FOR HUMAN REVIEW — FIXTURE / IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-06
> **Supersedes:** Minimal PIR Probe Design v0.1, retained as audit input
> **Review basis:** Human CONDITIONAL PASS ruling on v0.1 at `c029b89`
> **Revision purpose:** four methodological revisions only; no research-question or architecture change

## 1. Effect of v0.2

This revision inherits Minimal PIR Probe Design v0.1 unless explicitly amended
here.

```text
MR-1  W_age is renamed W_obs_age and restricted to observable observation-age
      semantics.

MR-2  Physical boundedness is split into Scope membership and no-global-
      expansion properties.

MR-3  E-L/E-S scaling attribution is pre-registered by phase.

MR-4  MOVE / RENAME discovery requires a pre-registered non-semantic
      correspondence protocol.
```

All unamended v0.1 rules remain: paired `E-L/E-S`, oracle isolation, phase-
separated ICAC, `W_latency`, typed physical verdicts, Fresh Closure, evidence
requirements, and implementation/fixture/experiment prohibition.

## 2. MR-1 — `W_obs_age`, not physical-change age

v0.1's `W_age` is renamed:

```text
W_obs_age
```

The measured quantity is:

```text
W_obs_age threshold:
T_current_reconciliation - T_previous_lawful_physical_observation
  <= W_obs_age
```

Semantic meaning:

```text
observable information-physical observation staleness
```

It must not be described as:

```text
physical-world change age
```

Reason: if the last observation occurred at `10:00`, the current check occurs at
`10:05`, and an unknown physical change occurred at `10:01`, the system can only
observe five minutes of observation staleness. It cannot infer a four-minute
change age without an independent lawful change timestamp.

For planted fixtures, the control side may separately record:

```text
T_control_planted_change
```

That value belongs to evaluation only and must not enter the measured path.

The future Run Manifest must rename:

```text
W_age                → W_obs_age
observable_age       → observable_observation_age
EV-P09 W_age         → EV-P09 W_obs_age
FT-P09 W_age breach  → FT-P09 W_obs_age breach
```

`W_latency` is unchanged:

```text
T_query_receipt → T_fresh_closure_available <= W_latency
```

## 3. MR-2 — non-circular physical boundedness

`P` is not an upper bound mathematically derived from `R`. It is the number of
physical candidates actually materialized by the declared Physical Scope before
reconciliation.

The future Run Manifest must record:

```text
P_declared       candidates exposed by the declared Physical Scope;
P_materialized   candidates actually available to reconciliation;
physical_check_targets
                 identities/locators/checks actually performed;
physical_observations
                 policy-scoped observations completed;
physical_changes typed PC-* differences observed;
unrelated_physical_touches
                 checks/reads/updates outside declared Physical Scope.
```

Replace v0.1 `PC-9` with:

```text
PC-9A  Scope membership:
       every physical_check_target is proven to belong to the declared
       Physical Scope by root, filter, registered locator, or another
       pre-registered membership rule.

PC-9B  No-global-expansion:
       unrelated_physical_touches = 0 outside explicitly recorded index
       internals.

PC-9C  Count disclosure:
       P_materialized, physical_check_targets, physical_observations, and
       physical_changes are reported separately.
```

`P_materialized` may equal `R` in the intended paired shape, but equality is an
observed result, not a definitional proof.

## 4. MR-3 — pre-registered scaling attribution

E-L/E-S must report separate phase vectors:

```text
Scope Resolution / Index
Candidate Retrieval
Physical Scope Assembly
Physical Reconciliation
IS Update
Fresh Closure Reconstruction
```

Pre-registered attribution rule:

```text
N-dependent growth may be attributed only to:
  Scope Resolution / Index
  Candidate Retrieval
  declared structural registry overhead

N-dependent growth may NOT be attributed to:
  Physical Reconciliation

Physical Reconciliation cost is scope-bounded when:
  physical_check_targets ⊆ declared Physical Scope;
  unrelated_physical_touches = 0;
  physical_check count is bounded by P_materialized plus an explicitly
  pre-registered candidate-resolution allowance.
```

The claim is therefore not that all SimiGo phases are `O(1)` with respect to
`N`. The claim is:

```text
N ↑ may cause index/scope-resolution cost;
N ↑ must not cause whole-Information-Space physical reconciliation growth.
```

If Physical Reconciliation latency or object checks grow with `N` while
`P_materialized` and `physical_check_targets` remain bounded, record:

```text
FT-P14 N-DEPENDENT PHYSICAL RECONCILIATION EXPANSION
```

## 5. MR-4 — MOVE / RENAME discovery protocol

The future Run Manifest must pre-register the entire MOVE / RENAME observation
protocol before fixture authorization.

Required fields:

```text
MR-4A  declared candidate pool:
       roots, directories, depth, exclusions, and allowed file classes.

MR-4B  allowed physical candidate source:
       bounded directory/listing result from the declared Physical Scope;
       no global scan, fuzzy search, semantic search, model inference, or
       filesystem watcher.

MR-4C  identity-correlation rule:
       deterministic mapping from missing old locator to allowed new locator.

MR-4D  maximum candidate count:
       number of new candidates that may be correlated to one missing old
       object.

MR-4E  tie-break / ambiguity policy:
       zero, one, and multiple candidate outcomes.

MR-4F  evidence requirements:
       old locator check, candidate locator check, and correlation evidence.
```

The minimal lawful shape is:

```text
old locator missing
  + exactly one allowed candidate in the declared Physical Scope
  + satisfying the pre-registered identity-correlation rule
  → PHYSICALLY_MOVED / PHYSICALLY_RENAMED

old locator missing
  + zero accepted candidate
  → PHYSICALLY_DELETED

old locator missing
  + multiple accepted candidates
  → CONFLICT or INDETERMINATE, as fixed by policy
```

The correlation rule may use deterministic registered identity evidence, size,
content digest, stable prefix/content policy, or another pre-registered tuple.
It must not use model similarity, filename intuition, business intent, or
post-hoc best guess.

If the correlation evidence is insufficient, output:

```text
CONFLICT
```

or:

```text
INDETERMINATE
```

as fixed by the Run Manifest. It must not choose a likely move.

## 6. Observations versus changes

The future Run Manifest must separately count:

```text
physical_observations
  policy-scoped checks performed on declared physical candidates.

physical_changes
  typed PC-MODIFY / PC-DELETE / PC-MOVE / PC-RENAME differences actually
  observed.
```

For `C-NOCHANGE`:

```text
physical_observations = R
physical_changes = 0
false_positive_changes = 0
```

`physical_observations = R` remains legal because reconciliation must check each
accepted object even when no change exists.

## 7. Updated PASS criteria

Replace v0.1 `PC-6`, `PC-9`, and `PC-13` as follows.

```text
PC-6   observable_observation_age <= W_obs_age for every accepted object.

PC-9A  every physical_check_target has declared Physical Scope membership.
PC-9B  unrelated_physical_touches = 0 outside recorded index internals.
PC-9C  P_materialized, physical_check_targets, physical_observations, and
       physical_changes are reported separately.

PC-13A Scope Resolution / Index / Candidate Retrieval growth is reported
       separately from Physical Reconciliation.
PC-13B Physical Reconciliation object targets are bounded by
       P_materialized plus the pre-registered allowance.
PC-13C No Physical Reconciliation phase performs whole-N scan growth.
```

Add failure:

```text
FT-P14 N-dependent Physical Reconciliation expansion.
```

Add evidence:

```text
EV-P16 MOVE/RENAME candidate pool and correlation protocol.
EV-P17 P_declared / P_materialized / check-target provenance.
EV-P18 physical_observations versus physical_changes counts.
```

## 8. Decision requested

This document requests Human review only.

```text
ACCEPT PROBE DESIGN V0.2   proceed to a separately reviewed Fixture / Run
                           Manifest; still no implementation or execution.
REVISE PROBE DESIGN        return with registered defects.
REJECT PROBE DESIGN        do not proceed.
```

No fixture, implementation, filesystem access, or experiment is authorized.
