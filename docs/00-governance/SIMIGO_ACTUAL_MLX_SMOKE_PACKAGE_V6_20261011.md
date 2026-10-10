# Actual MLX smoke execution package V6

> **Status:** EXECUTION PACKAGE DELIVERED / CANDIDATE — HUMAN AUTHORIZATION REQUIRED
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

## Candidate binding

```text
manifest path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V6.json;
manifest SHA256 =
  3036df7e8b3c0ddd1548bc45fb7c1b198dbd25939e0c09804c222365eedec55e;
sidecar path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V6.sha256;
Runner SHA256 =
  4b27bcada44128fc501e7dac7f2547689e64a3381a4cd442877f1809e010ff0e;
Success Gate source SHA256 =
  eec8f82683203bca69649aece68563483dcc1116372437b6cd4e802045eb6bbb;
Child source SHA256 =
  918c3faf1a0000d9e15996d16c83d4ce42d47d4a81bebb29e60f9f3d5e1d94ff;
Child binary SHA256 =
  4d514780be383e6d459b61ffa6d237501e904940610e945fdd85867184dc2c8f;
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
  3036df7e8b3c0ddd1548bc45fb7c1b198dbd25939e0c09804c222365eedec55e;
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
  PASS / 8 tests / 1 skipped / 0 failures;
ProductionRuntimeFailureBoundaryTests =
  PASS / 8 tests / 0 failures.
```

The skipped test is `testActualMLXSmokeSingleRun`, as required without a marker.

## Hard boundaries

```text
V5 result = MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED;
V5 retry / gate adjustment by rerun = FORBIDDEN;
Runtime Validation V2 rerun = FORBIDDEN / CLOSED;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
