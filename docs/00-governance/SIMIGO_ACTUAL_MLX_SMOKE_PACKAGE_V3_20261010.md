# Actual MLX smoke execution package V3

> **Status:** EXECUTION PACKAGE DELIVERED / CANDIDATE — HUMAN AUTHORIZATION REQUIRED
> **Actual MLX smoke:** NOT AUTHORIZED / NOT EXECUTED
> **Date:** 2026-10-10

## Response to V2 NO-GO

V3 addresses the four controls without reopening Runtime Validation V2,
changing frozen contracts, creating a marker, or consuming the actual-run
opportunity.

```text
A. sidecar uses standard sha256 + filename format;
   Runner parses the digest field and checks the filename;
   real-sidecar precheck = PASS.

B. the exact Child binary is locally rebuilt under controlled mode and bound
   by SHA256 before any authorization can be consumed.

C. Child terminal records use open(O_CREAT | O_EXCL | O_WRONLY);
   a second write necessarily fails; fault-injected precheck = PASS.

D. the Runner launches Child with posix_spawnattr POSIX_SPAWN_SETPGROUP;
   timeout sends SIGKILL to negative Child PID / process group;
   a fault-injected /bin/sleep descendant is used to prove process-tree
   termination; precheck = PASS.
```

## V3 binding

```text
manifest path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V3.json;
manifest SHA256 =
  1debcc5c552fb5cb5fffc730943e8941abd0b6074b12976b4cd9f768a184c7aa;
sidecar path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V3.sha256;
sidecar format =
  1debcc5c552fb5cb5fffc730943e8941abd0b6074b12976b4cd9f768a184c7aa
  ACTUAL_MLX_SMOKE_MANIFEST_V3.json.
```

```text
Runner SHA256 =
  09d7af533b9faf75594d6bfe312a4530b3fd12b44e81c7f72ed3250b828e3c24;
Child source SHA256 =
  7ee279ddb9781f6f48428e5d84a9756dca69e4b5f350dca76620f87716c0be83;
Child binary SHA256 =
  e21efd3ee9a7c60257c1f3c8435ae6bc21a82fba67c966d64ea74cf1b6572d28;
Package.swift SHA256 =
  a27c5e5c740a1e14a5cfc79aa0d2d8699ca0907a63c905e6a4be8792a62b9ac1.
```

Runner verifies the Child binary digest, source digest, and `Package.swift`
digest before consuming the marker. The nine source-key set remains exact.

## Authorization gate

```text
marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V3_AUTHORIZED;
required marker content =
  1debcc5c552fb5cb5fffc730943e8941abd0b6074b12976b4cd9f768a184c7aa;
consumption path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V3_AUTHORIZATION_CONSUMED;
consumption mode = atomic rename before child launch.
```

Current state:

```text
V3 marker = ABSENT;
V3 consumed marker = ABSENT;
evidence root = ABSENT.
```

Evidence remains:

```text
evidence root =
  integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v3;
terminal record mode =
  O_CREAT | O_EXCL | O_WRONLY / no overwrite;
terminal states =
  MLX_SMOKE_PASS or MLX_SMOKE_FAIL.
```

## Prechecks

```text
ActualMLXSmokeValidation =
  PASS / 6 tests / 1 skipped / 0 failures;
ProductionRuntimeFailureBoundaryTests =
  PASS / 7 tests / 0 failures.
```

The skipped test is `testActualMLXSmokeSingleRun`, as required without a marker.

## Hard boundaries

```text
Runtime Validation V2 = PASS / CLOSED; rerun FORBIDDEN;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
