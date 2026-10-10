# Actual MLX smoke execution package V6

> **Status:** EXECUTION PACKAGE REVISION 2 DELIVERED / CANDIDATE — HUMAN
> AUTHORIZATION REQUIRED
> **Actual MLX smoke:** NOT AUTHORIZED / NOT EXECUTED
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

## Candidate binding

```text
manifest path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V6.json;
manifest SHA256 =
  63711800a2181b7e3fa8a3e330a9916da3cffe223f76ebcd2e820fc8c5987346;
sidecar path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V6.sha256;
Runner SHA256 =
  f174f3ff0842d4b7b2527996477f67c39b0719091c6997235e4dfdedd366b943;
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
  63711800a2181b7e3fa8a3e330a9916da3cffe223f76ebcd2e820fc8c5987346;
consumption path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V6_AUTHORIZATION_CONSUMED;
consumption mode = atomic rename before child launch;
authorized runs if approved = 1.
```

Current state:

```text
V6 marker = ABSENT;
V6 consumed marker = ABSENT;
V6 evidence root =
  integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v6 = ABSENT;
V5 consumed marker and failure evidence = PRESERVED.
```

## Prechecks

```text
swift build --product ActualMLXSmokeChild = PASS;
ActualMLXSmokeValidation =
  PASS / 10 tests / 1 skipped / 0 failures;
ProductionRuntimeFailureBoundaryTests =
  PASS / 8 tests / 0 failures.
```

The skipped test is `testActualMLXSmokeSingleRun`, as required without a marker.
The two new non-generative regression tests cover the shared success-gate
defects and Runner terminal-record validation without invoking MLX.

## Hard boundaries

```text
V5 result = MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED;
V6 Revision 1 = NO-GO / SUPERSEDED;
V6 Revision 2 = CANDIDATE — HUMAN AUTHORIZATION REQUIRED;
V5 retry / gate adjustment by rerun = FORBIDDEN;
Runtime Validation V2 rerun = FORBIDDEN / CLOSED;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
