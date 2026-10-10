# Actual MLX smoke execution package

> **Status:** NO-GO / SUPERSEDED BY V3 EXECUTION PACKAGE
> **Actual MLX smoke:** NOT AUTHORIZED / NOT EXECUTED
> **Date:** 2026-10-10

## Scope

This package was reviewed as NO-GO and is retained only as history. It is
superseded by `ACTUAL_MLX_SMOKE_MANIFEST_V2.json`; do not create its marker or
execute its entry. The successor fixes the stale source-binding question,
enforces all nine source-binding checks, consumes authorization exactly once,
uses write-once evidence, and covers model load with a parent-process hard
timeout.

The preceding targeted corrections are committed at `87aad209f6e1a234506d698dedebd7840a532286`:

```text
Runtime Validation V2 status restored =
  RUNTIME_VALIDATION_PASS / AUTHORIZED RUN CONSUMED / CLOSED;
representation-binding failure assertions made machine-checkable;
ProductionRuntimeFailureBoundaryTests =
  PASS / 7 tests / 0 failures.
```

## Candidate manifest

```text
manifest path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V1.json;
manifest SHA256 =
  26e6e7d8f7a1f2f6e86cfd6a384eea9670653139ae87cb4f1635f25389713ac7;
sidecar =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V1.sha256.
```

Authorization gate:

```text
marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_AUTHORIZED;
required marker content = the manifest SHA256 above;
without an exact marker / manifest / sidecar match =
  runner fails closed before the smoke run.
```

## Bound execution

```text
entry class = ActualMLXSmokeValidation;
entry test = testActualMLXSmokeSingleRun;
entry SHA256 =
  1109b88b6adfbc32007406d976eacd196089789d8a7e7811e8e5ee3b3f760237;
authorized runs if approved = 1;
model calls = 1;
information demand items = 7;
max-token upper bound = 32;
sampling = greedy;
wall-clock timeout = 1200 seconds.
```

The bound model is the locally cached MLX snapshot
`mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit`
at revision `6b82053fa694ac4f1a0069f27ab71f1ab0cd7fff`. The manifest binds
the config, tokenizer, tokenizer configuration, and both safetensors shards
by SHA256.

## Isolation and success gate

```text
PALACE snapshot = read-only;
sealed snapshot SHA256 =
  8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444;
validity policy =
  integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json;
carrier database = fresh temporary path created only during the approved run;
evidence root =
  integrated-es-palace/mlx-smoke-v1/mlx-smoke-evidence-v1;
evidence root currently absent = true;
evidence mode = write-once.
```

The only authorized passing terminal shape is:

```text
carrier report state = ADVANCED;
execution state = SETTLED;
final position = 1;
final lifecycle = active;
bound representation token count >= 1;
one carrier database and one typed evidence record persisted.
```

The serialization precheck is:

```text
ActualMLXSmokeValidation =
  PASS / 2 tests / 1 skipped / 0 failures.
```

The skipped test is the actual smoke entry, as required while authorization is
absent.

## Terminal rule

After the approved run writes `MLX_SMOKE_PASS` or `MLX_SMOKE_FAIL`, execution
stops. No automatic repair, rerun, timeout retry, model swap, or case expansion
is authorized. Either terminal state requires a separate human decision.

## Hard boundaries

```text
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
Runtime Validation V2 rerun = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
