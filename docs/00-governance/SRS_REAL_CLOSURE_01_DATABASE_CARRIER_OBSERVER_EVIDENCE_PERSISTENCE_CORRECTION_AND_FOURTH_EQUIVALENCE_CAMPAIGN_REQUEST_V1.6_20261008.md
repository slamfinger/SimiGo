# SRS-REAL-CLOSURE-01 — Database-Carrier Observer/Evidence-Persistence Correction & Fourth Equivalence Campaign Request v1.6

> **Status:** HUMAN-AUTHORIZED — PART R3 CORRECTION + CONDITIONAL PART E4
> **Date:** 2026-10-08
> **Predecessor canonical stop:** `4102b7cd8d237e2ac0c955301c2b4747dfc1469f`
> **Predecessor audit stop:** `b19bab444993eabbb146230c3c1fdf39eb987f41`

## 1. Exact Human ruling

The Human ruling for this Request is:

```text
Authorize observer/evidence persistence correction -> brand-new,
independently budgeted equivalence campaign.

The correction surface is strictly limited to:
- observer schema/key canonicalization;
- persistence/evidence binding;
- preflight/self-check.

Do not use this as an opportunity to change the semantic layer or existing
criteria.
```

This authorization is registered canonically by the commit introducing this
Request. It creates fresh Part R3 and Part E4 budgets; it does not renew or
reuse EXEC-DB-001, EXEC-DB-002, or EXEC-DB-003.

## 2. Inherited authoritative facts

```text
accepted design package          = 21acba4e07f312fcb818968f33fd9e0c185fccf0;
corrected implementation         = 7392fcb79fb7e8465b73f9e1837c4634e56c0409;
accepted fresh DB SHA256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
EXEC-006 document reference      = 69b2227dbd9ec7bfc8ad744d65efe46e3a9ab33a;
EXEC-006 evidence reference      = cb365a44c48d4b7b90b4cc2155fcae00d3e01572;

EXEC-DB-003 outcome              = INVALID / NON-ADJUDICATIVE;
E3 evidence commit               = 1ac081b0304a72205685a11bd610d65e8a6c8109;
E3 audit commit                  = b19bab444993eabbb146230c3c1fdf39eb987f41;
root-cause class =
  HARNESS_POST_SEQUENCE_EVIDENCE_KEY_BINDING_DEFECT.
```

Raw O0–O5 remain accepted facts only. Raw ES2 `REUSE` and ESN `BLOCK` remain
non-authoritative observations. They neither establish nor weaken EQ/REJ,
CarrierSQLite equivalence, or any broader SimiGo/ES claim.

## 3. Part R3 — authorized correction only

One work cycle may modify only campaign evidence instrumentation in the
following bounded classes:

```text
observer schema/key canonicalization;
observer verdict persistence and byte-level evidence binding;
evidence-path preflight and persistence self-check.
```

The R3 correction must:

```text
use one canonical observer key for C3;
fail closed on absent, mismatched, noncanonical, or unpersisted observer keys;
write the observer verdict exactly once to its authorized path;
reread the persisted bytes and require exact byte and parsed-object equality;
bind the verdict SHA256, canonical key name, path identity and persistence
  self-check result in a separate authorized evidence artifact;
keep all 30 authorized campaign destinations under exact path-map control;
require complete preflight PASS before O0 and fail closed otherwise.
```

R3 must not execute O1–O5, invoke T-IMPL-01, mutate logical IS rows, change
carrier/schema semantics, ES2/ESN decision behavior, decision boundary, τ,
fixture, runner, observer semantics, T-IMPL-01, EQ-1..EQ-8, or REJ-1..REJ-14.

R3 completion requires static and tool-checkable self-checks only. It does not
consume the fourth campaign budget.

## 4. Part E4 — conditional fourth frozen campaign

Only after Part R3 is canonical, its path map is complete, all preflight
destinations PASS, and the R3 persistence self-check PASS may exactly one new
frozen campaign execute under this Request.

The E4 campaign must bind:

```text
Request v1.6 canonical commit;
R3 corrected commit;
fresh, absent campaign output root;
accepted design/implementation/database baselines;
EXEC-006 references;
EQ-1..EQ-8 and REJ-1..REJ-14 unchanged;
one fresh campaign / IS-mutation / observer budget.
```

Even if E4 completes mechanically, its result is only
`CANDIDATE_EQUIVALENCE_PENDING_HUMAN_AUDIT`. Canonical equivalence still
requires a separate Human evidence audit.

## 5. Independent budgets

```text
observer_persistence_correction_work_cycle_budget = 1;
fourth_database_equivalence_campaign_budget       = 1;
fourth_database_IS_mutation_campaign_budget       = 1;
fourth_observer_equivalent_budget                 = 1;

EXEC-DB-001/002/003 budget reuse                  = FORBIDDEN;
old working DB/evidence reuse                     = FORBIDDEN;
document-form EXEC-006 rerun                      = FORBIDDEN;
implementation repair                             = FORBIDDEN;
schema migration                                  = FORBIDDEN;
logical import                                    = FORBIDDEN;
semantic/criteria repair                          = FORBIDDEN;
automatic equivalence                             = FORBIDDEN;
automatic renewal                                 = FORBIDDEN.
```

## 6. Required stop

Part E4 must stop after producing the complete campaign evidence package, or
earlier fail-closed at the first missing/mismatched evidence artifact. It must
not self-adjudicate equivalence authority, renew its budget, rerun after any
failure, or reuse prior campaign state.
