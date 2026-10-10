# Actual MLX smoke execution package V5

> **Status:** EXECUTION PACKAGE DELIVERED / CANDIDATE — HUMAN AUTHORIZATION REQUIRED
> **Actual MLX smoke:** NOT AUTHORIZED / NOT EXECUTED
> **Date:** 2026-10-11

## Basis

V5 is built on `main` after W1 merged:

```text
merge base = 3cea5facaeca0817d10f093b3f83300525ab38bf;
W1 Backend Identity Repair = MERGED;
supersedes manifest V4 SHA256 =
  52a9a10a9f52b2853dd2b5f0053573b6c1830f9a84e9a07485a5af88b2d862b2;
V4 actual smoke remains =
  MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED.
```

The W1 merge is not treated as model-run authorization. V5 is only a candidate
package and must receive a separate execution decision.

## Candidate binding

```text
manifest path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V5.json;
manifest SHA256 =
  47761f3d0dd05e4980971441b1a7b51a542e2a7f61b8ca6c6aeb4c723e6bbcfd;
sidecar path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V5.sha256;
Runner SHA256 =
  cf3cd09e52d25964f861968c146c9f0768910f5f65504064c3f35cd2f27f9840;
Child source SHA256 =
  987c98897c1623000c763f3af4df69c861428d65c365e7ccd6c1a44cf0e9dd1d;
Child binary SHA256 =
  153620c06f0943010864334fd41a24c6ae2693804b4043462d644a81694b4b72;
Package.swift SHA256 =
  a27c5e5c740a1e14a5cfc79aa0d2d8699ca0907a63c905e6a4be8792a62b9ac1;
advancement ID = actual-mlx-smoke-v5.
```

All nine source bindings, Child source, Child binary, and `Package.swift` were
recalculated from the W1-merged working tree. The V4 QA issue is closed: the
sidecar-format precheck now reads the real V5 Manifest and V5 sidecar.

## Authorization gate

```text
marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V5_AUTHORIZED;
required marker content =
  47761f3d0dd05e4980971441b1a7b51a542e2a7f61b8ca6c6aeb4c723e6bbcfd;
consumption path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V5_AUTHORIZATION_CONSUMED;
consumption mode = atomic rename before child launch;
authorized runs if approved = 1.
```

Current state:

```text
V5 marker = ABSENT;
V5 consumed marker = ABSENT;
V5 evidence root =
  integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v5 = ABSENT;
V4 consumed marker and failure evidence = PRESERVED.
```

## Prechecks

```text
swift build --product ActualMLXSmokeChild = PASS;
ActualMLXSmokeValidation =
  PASS / 7 tests / 1 skipped / 0 failures;
ProductionRuntimeFailureBoundaryTests =
  PASS / 8 tests / 0 failures.
```

The skipped test is `testActualMLXSmokeSingleRun`, as required without a marker.

## Hard boundaries

```text
V4 result = MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED;
V4 retry / repair-run = FORBIDDEN;
Runtime Validation V2 rerun = FORBIDDEN / CLOSED;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
