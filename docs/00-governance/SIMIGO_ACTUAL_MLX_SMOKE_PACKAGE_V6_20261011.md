# Actual MLX smoke execution package V6

> **Status:** ACTUAL MLX SMOKE PASS / AUTHORIZED RUN CONSUMED / CLOSED
> **Actual MLX smoke:** PASS / AUTHORIZED RUN CONSUMED / CLOSED
> **Date:** 2026-10-11

## Basis and bounded repair

V5 remains:

```text
MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED.
```

Its evidence proved that the W1 unified backend reached real MLX execution:
position 1, active lifecycle, a 6481-token bound representation, all nine
required settlements `SETTLED`, and carrier runtime application
`APPLIED_SWIFT`. It failed only because the success gate compared
`execution_state.status` with `SETTLED`, although carrier rules allow
execution-state status `ADVANCED`.

V6 does not rerun V5 and does not modify its evidence. It adds an explicit,
layer-separated success gate:

```text
execution_state_status = ADVANCED;
runtime_application_status = APPLIED_SWIFT;
all nine required settlement states = SETTLED;
pending_obligation_count = 0;
carrier_objects_verified = true;
final_position = 1;
final_lifecycle = active;
bound_representation_token_count >= 1;
carrier_database_present = true.
```

The Child records every check independently in `success_gate_checks`; a failure
also names the failed checks instead of emitting only a generic message.

Human review returned `NO-GO` for V6 Candidate Revision 1 without creating a
marker or executing MLX. Revision 2 fixes the three blocking defects:

```text
Runner terminal validation = uses execution_state.status == ADVANCED and the
  complete shared success gate;
pending obligations = read only from execution_state.pending_obligations;
  missing field or wrong type fails closed;
carrier_database_present = independent Child success-gate check and Runner
  terminal check.
```

Human review accepted those Revision 2 directions but retained NO-GO because
terminal evidence consistency remained incomplete. Revision 3 makes evidence
selection fail-closed and preserves the same shared-gate semantics:

```text
PASS + FAIL evidence = rejected as conflicting terminal evidence;
PASS success_gate_checks = required, exact-set, all true, and equal to the
  Runner's independently recomputed shared-gate checks;
carrier.sqlite as a directory = rejected by Runner terminal validation and
  covered by a non-generative regression;
production-path selection = exercised without launching Child or loading MLX;
Revision 1 historical record = explicitly superseded.
```

Code review returned `NO-GO` for Revision 3 because a FAIL-named file could
contain a valid PASS record. Revision 4 binds the selected source kind to the
record declaration:

```text
PASS file / PASS record = accepted only when the full shared Gate passes;
FAIL file / FAIL record = parsed and rejected as an authorized-run failure;
PASS file / FAIL record = rejected as source/content conflict;
FAIL file / PASS record = rejected as source/content conflict;
PASS + FAIL files or no terminal record = rejected as before.
```

The production acceptance function and its non-generative regression cover
these four source/content combinations without starting Child or loading MLX.

## Independent code review

Revision 4 received an independent source-level code review at commit
`c37478d4fd2e88aa664181d8733e28f2003ede0c`:

```text
code review = ACCEPT;
terminal source/content binding = PASS;
production acceptance path = PASS;
PASS/FAIL/conflict/missing handling = PASS;
success_gate_checks exact consistency = PASS;
carrier database file validation = PASS;
one-run authorization boundary = PASS;
Actual MLX smoke = NOT AUTHORIZED / NOT EXECUTED.
```

The reviewer recorded a non-blocking test-quality improvement: regression could
also write source variants to their respective filesystem names and exercise
selector end-to-end. This does not invalidate the accepted fix. The reviewer did
not rerun Swift tests or independently recompute every local artifact digest;
the ACCEPT is limited to source review of the pushed commit and does not
authorize execution.

## Authorized execution result

The Human gate subsequently authorized the restricted one-run flow. The marker
was created with the exact Revision 4 Manifest SHA256, consumed by atomic
rename, and the authorized Child completed exactly once:

```text
V6 actual smoke = MLX_SMOKE_PASS;
run count = 1 / 1;
started_at_utc = 2026-10-11T00:36:25Z;
completed_at_utc = 2026-10-11T00:37:57Z;
execution_state.status = ADVANCED;
runtime_application_status = APPLIED_SWIFT;
bound_representation_token_count = 6475;
all nine settlements = SETTLED;
pending obligations = empty;
all ten success-gate checks = true;
V6 result record = docs/00-governance/SIMIGO_ACTUAL_MLX_SMOKE_V6_RESULT_20261011.md.
```

## Candidate binding

```text
manifest path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V6.json;
manifest SHA256 =
  d89b505ff3fa562651c1852e173b1ee57206fbffd94ae752ebde86aab31416bb;
sidecar path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V6.sha256;
Runner SHA256 =
  1c3fcdf06022126d2bea12ec743568ab52a9b90982bc3bfae490b0153c11cc85;
Success Gate source SHA256 =
  b32a1038ce14ff0c14af502847acd98511e5d6c0d1d12ee36b6065098bc87711;
Child source SHA256 =
  87e58b221a911bd126d41f730016a878a7d20a5d6a19f4e313f134b8e6a4d32f;
Child binary SHA256 =
  088e12ba16ab41f69167f0adc9892f38126b8453ed6c9291ce2ed09eafb13020;
Package.swift SHA256 =
  a27c5e5c740a1e14a5cfc79aa0d2d8699ca0907a63c905e6a4be8792a62b9ac1;
advancement ID = actual-mlx-smoke-v6.
```

The Manifest now binds ten source objects: the former nine plus the new
Success Gate implementation. Runner verifies the exact key set and every path
SHA256 before consuming authorization.

## Authorization gate

```text
marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V6_AUTHORIZED;
required marker content =
  d89b505ff3fa562651c1852e173b1ee57206fbffd94ae752ebde86aab31416bb;
consumption path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V6_AUTHORIZATION_CONSUMED;
consumption mode = atomic rename before child launch;
authorized runs if approved = 1.
```

Current state:

```text
V6 marker = ABSENT;
V6 consumed marker = PRESENT / CONTENT BOUND TO REVISION 4 MANIFEST SHA256;
V6 evidence root =
  integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v6 = PRESERVED;
V5 consumed marker and failure evidence = PRESERVED.
Revision 4 code review = ACCEPT;
authorized run = CONSUMED / CLOSED.
```

## Prechecks

```text
swift build --product ActualMLXSmokeChild = PASS;
ActualMLXSmokeValidation =
  PASS / 12 tests / 1 skipped / 0 failures;
ProductionRuntimeFailureBoundaryTests =
  PASS / 8 tests / 0 failures.
```

The skipped test is `testActualMLXSmokeSingleRun`, as required without a marker.
The non-generative regressions cover shared success-gate defects, terminal
record validation, exact `success_gate_checks` consistency, and terminal
evidence selection without invoking MLX. Full `testActualMLXSmokeSingleRun`
remains dynamically exercisable only if a separate Human authorization later
creates the marker.

## Hard boundaries

```text
V5 result = MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED;
V6 Revision 1 = NO-GO / SUPERSEDED;
V6 Revision 2 = NO-GO / SUPERSEDED / NOT EXECUTED;
V6 Revision 3 = NO-GO / SUPERSEDED / NOT EXECUTED;
V6 Revision 4 = CODE REVIEW ACCEPT;
V6 actual smoke = MLX_SMOKE_PASS / AUTHORIZED RUN CONSUMED / CLOSED;
V6 retry / gate adjustment by rerun = FORBIDDEN;
V5 retry / gate adjustment by rerun = FORBIDDEN;
Runtime Validation V2 rerun = FORBIDDEN / CLOSED;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
