# Actual MLX smoke execution package V4

> **Status:** EXECUTION PACKAGE DELIVERED / CANDIDATE — HUMAN AUTHORIZATION REQUIRED
> **Actual MLX smoke:** NOT AUTHORIZED / NOT EXECUTED
> **Date:** 2026-10-10

## Response to V3 NO-GO

V4 fixes the only named execution-path blocker. The Runner now reads:

```text
evidence.root
```

and explicitly rejects a stale top-level `evidence_root` field. A new independent
precheck validates the real V4 Manifest field and resolves the registered path
against the Lab root:

```text
testActualMLXSmokeManifestEvidenceFieldPrecheck = PASS.
```

No authorization marker was created or consumed. No actual smoke run occurred.
Runtime Validation V2 and frozen contracts were not touched.

## V4 binding

```text
manifest path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V4.json;
manifest SHA256 =
  52a9a10a9f52b2853dd2b5f0053573b6c1830f9a84e9a07485a5af88b2d862b2;
sidecar path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V4.sha256;
sidecar format =
  52a9a10a9f52b2853dd2b5f0053573b6c1830f9a84e9a07485a5af88b2d862b2
  ACTUAL_MLX_SMOKE_MANIFEST_V4.json.
```

```text
Runner SHA256 =
  4212f9cc0af3b6492ebe8a097f130801c220d7d2c70f5b8b425503f2d620decc;
Child source SHA256 =
  7ee279ddb9781f6f48428e5d84a9756dca69e4b5f350dca76620f87716c0be83;
Child binary SHA256 =
  e21efd3ee9a7c60257c1f3c8435ae6bc21a82fba67c966d64ea74cf1b6572d28;
Package.swift SHA256 =
  a27c5e5c740a1e14a5cfc79aa0d2d8699ca0907a63c905e6a4be8792a62b9ac1.
```

Authorization path:

```text
marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V4_AUTHORIZED;
required marker content =
  52a9a10a9f52b2853dd2b5f0053573b6c1830f9a84e9a07485a5af88b2d862b2;
consumption path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V4_AUTHORIZATION_CONSUMED;
evidence root =
  integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v4.
```

Current state:

```text
V4 marker = ABSENT;
V4 consumed marker = ABSENT;
V4 evidence root = ABSENT.
```

## Prechecks

```text
ActualMLXSmokeValidation =
  PASS / 7 tests / 1 skipped / 0 failures;
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
