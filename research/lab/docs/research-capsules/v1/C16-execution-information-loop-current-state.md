# C16 — Execution–Information Closed Loop Current State

## Research State Capsule

```text
Research Object          = Execution State ↔ Information Space closed loop
Status                   = WORKING BASELINE / COMPUTE→SETTLE PASS / RELEASE→FORK PENDING
Last verified            = 2026-10-16 @ 7d8d8811
Capsule lineage          = C01 core route → 2026-10-09 closed-loop implementation → bounded validations
```

## Research Question

For a reliable, semantically sufficient, dependency-complete settlement, can a fork continue from Information Space after the old model stage/cache is inaccessible and compute only the invalidated delta?

## What is established

```text
SQLite/carrier-backed persistence, settlement reuse, dependency invalidation,
restart recovery, fail-closed behavior, and audited state transitions were
implemented and exercised by isolated selftests and E2E records.

Pilot v5 human acceptance is bounded to SQLite busy/concurrency behavior.
It does not authorize production deployment or a real-model claim.

Actual MLX Smoke V6 consumed a real 12B MLX model representation, advanced
Execution State, settled all nine required carrier items, and applied the Swift
runtime result. It authorized one model call and at most 32 generated tokens;
no item was reused. Runtime Validation V2 separately passed the reuse/blocking
predicate matrix.

The architecture separation is a working baseline, not an accepted real-model
continuity theorem.
```

## Evidence

```text
execution-information-loop/README.md
execution-information-loop/loop.py
execution-information-loop/carrier_loop.py
execution-information-loop/real_palace_loop.py
docs/00-governance/SIMIGO_EXECUTION_INFORMATION_LOOP_VERTICAL_SLICE_AUTHORIZATION_AND_EXECUTION_20261009.md
docs/00-governance/SIMIGO_EXECUTION_INFORMATION_CLOSED_LOOP_FINAL_ACCEPTANCE_PACKAGE_20261009.md
docs/00-governance/SIMIGO_CONTROLLED_PRODUCTION_PILOT_V5_SQLITE_BUSY_ACCEPT_20261010.md
docs/00-governance/SIMIGO_RUNTIME_VALIDATION_V2_RESULT_20261010.md
docs/00-governance/SIMIGO_ACTUAL_MLX_SMOKE_V6_RESULT_20261011.md
docs/00-governance/SIMIGO_INTEGRATED_ES_PALACE_D002_CLOSURE_AND_POSTMORTEM_AUDIT_OPENING_20261009.md
docs/02-evidence/execution-information-loop-vertical-slice-20261009/
```

## Remaining proof obligation

Release is lawful only when the settlement is:

```text
semantically sufficient       = persisted content supports the later task;
dependency-complete           = sources, versions, dependencies, and validity recover;
atomic / recoverable          = crash cannot promote a partial settlement;
execution-rebuildable         = a new stage can reconstruct input from IS alone.
```

Run a controlled real-model experiment on a task with an explicit boundary
between already-completed work and new work. Use three arms:

```text
A full-recompute baseline     = no settlement reads; execute the complete task.
B persisted continuation      = old process/cache inaccessible; restore valid
                                settlements from IS; execute only the delta.
C invalidation control        = change one settled source/dependency and prove
                                only dependent work recomputes.
```

Each arm must record:

```text
correctness                   = pre-registered task predicate;
reuse                         = settlement IDs read and actually applied;
minimal recompute             = model calls, computed units, and skipped units;
cache isolation               = old process exit or inaccessible cache namespace;
cost                          = input/output tokens and wall time, including
                                tokens that re-feed settled results.
```

Reading a settlement is information-reuse evidence; only skipped historical
model work plus correct delta output is computation-benefit evidence. Physical
RSS decrease is supplementary, never the sole release proof.

## Bounding

KV Cache is allowed during an execution stage and before reliable settlement. The V6 prefix-recompute executor runs real MLX forwards but passes `cache: nil`; therefore V6 is not a KV-cache lifecycle test and must not be relabeled as one. This capsule does not claim that cache is unnecessary, that SQLite is a universal backend, or that isolated fixtures prove production behavior. Local Closure, SRS-REAL-CLOSURE-01, PIR, carrier-equivalence, and D-002 failure evidence remains historical and closed unless reopened by Human ruling.

## What it does NOT prove

```text
Real-model continuation after observable cache/model-stage release.
Information-Space-only fork continuation with incremental model computation.
Cost superiority of re-feeding settlements plus delta over full recomputation.
Production readiness or general backend selection.
```

## Failure taxonomy

```text
settlement semantics; dependency completeness; input reconstruction;
backend/model-stage lifecycle; experiment measurement design.
```
