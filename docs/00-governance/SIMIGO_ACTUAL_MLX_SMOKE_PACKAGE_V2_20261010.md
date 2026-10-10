# Actual MLX smoke execution package V2

> **Status:** EXECUTION PACKAGE DELIVERED / CANDIDATE — HUMAN AUTHORIZATION REQUIRED
> **Actual MLX smoke:** NOT AUTHORIZED / NOT EXECUTED
> **Date:** 2026-10-10

## Response to V1 NO-GO

This V2 package addresses the four named controls without reopening Runtime
Validation V2, changing frozen contracts, or consuming the smoke opportunity.

```text
1. source bindings regenerated and dynamically checked;
2. Manifest and Runner source-binding key sets must be exactly equal;
   all 9 keys are checked;
3. evidence root precheck + exclusive directory creation +
   atomic marker consumption + O_CREAT/O_EXCL terminal records;
4. model load and production run execute in a separate child process;
   the parent enforces a 1200 second deadline and SIGKILL on overrun.
```

## Source-binding reconciliation

The current post-assertion failure-boundary source is authoritative:

```text
ProductionRuntimeFailureBoundaryTests.swift SHA256 =
  da2f50a14645446bab1b0a8b5a29edf3c19c73fa8cdbe40ab3b0d859c2eba30a.
```

`a7a93b94f51dd23de95ab3dbc368ca1ad65a2fb6b4d188ff87488c65a9c50f0d` was the
superseded pre-assertion revision. Rebinding it would remove the two required
representation-recovery assertions, so it is retained only as history.

## V2 candidate binding

```text
manifest path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V2.json;
manifest SHA256 =
  f7b4818e84bd757b7a573ef0edad0302b9903423050e07b97824c06dab5fabff;
sidecar =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V2.sha256;
runner SHA256 =
  428f3f592738a102a20e6163029b4edef97a16c075d183a40c011cf9ba5969d3;
child source SHA256 =
  416ab49220436aa6d8b59ca41fde78be24c21d9d928cdeb8d48f6ff1d848c8ea;
Package.swift SHA256 =
  a27c5e5c740a1e14a5cfc79aa0d2d8699ca0907a63c905e6a4be8792a62b9ac1.
```

The nine source keys are:

```text
smoke_runner;
production_integration;
mlx_executor;
execution_state_backend;
continuity_coordinator;
failure_boundary_tests;
runtime_bridge;
carrier_loop;
real_palace_loop.
```

The Runner rejects any missing or extra binding key and checks each path and
SHA256 before creating the evidence root, consuming the marker, launching the
child, creating a carrier database, or entering model execution.

## One-run and write-once controls

```text
marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V2_AUTHORIZED;
required marker content =
  f7b4818e84bd757b7a573ef0edad0302b9903423050e07b97824c06dab5fabff;
consumption path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V2_AUTHORIZATION_CONSUMED;
consumption mode = atomic rename before child launch;
evidence root =
  integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v2;
evidence root precheck = must not exist;
terminal record mode = O_CREAT / O_EXCL / no overwrite.
```

The marker cannot satisfy a second run after it is atomically renamed. If the
child is killed on timeout or exits without terminal evidence, the parent writes
the exclusive `MLX_SMOKE_FAIL.json` record and stops.

## Hard timeout

The production integration and model loading run in `ActualMLXSmokeChild`, a
separate process launched by the Runner. The parent starts the deadline before
launch and kills the child with `SIGKILL` at 1200 seconds. Thus the limit
covers model load, Information Space execution, logical advance, representation
binding, and carrier confirmation.

The precheck uses a live `/bin/sleep` child to prove the timeout helper reaches
`SIGKILL`; it also proves a second `O_CREAT/O_EXCL` write cannot replace the
first record.

## Prechecks

```text
ActualMLXSmokeValidation =
  PASS / 3 tests / 1 skipped / 0 failures;
ProductionRuntimeFailureBoundaryTests =
  PASS / 7 tests / 0 failures.
```

The skipped test is `testActualMLXSmokeSingleRun`; no V2 marker exists.

## Hard boundaries

```text
Runtime Validation V2 = PASS / CLOSED; rerun FORBIDDEN;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
