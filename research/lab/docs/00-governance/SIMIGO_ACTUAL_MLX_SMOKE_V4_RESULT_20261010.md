# Actual MLX smoke V4 result

> **Status:** MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED
> **Run count:** 1 / 1
> **Actual model forward generation:** NOT PERFORMED
> **Date:** 2026-10-10

## Authorized binding

```text
execution commit =
  ba5e11a29916704b8ec3dc240cf59418ea340c27;
manifest =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V4.json;
manifest SHA256 =
  52a9a10a9f52b2853dd2b5f0053573b6c1830f9a84e9a07485a5af88b2d862b2;
marker content = the manifest SHA256 above;
consumed marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V4_AUTHORIZATION_CONSUMED;
consumed marker content SHA256 =
  b402045f9e8deb6e9bae35827c8758b44a848e5125f565138c9efc595ba37271.
```

## Observed terminal state

The authorized entry consumed the marker and attempted exactly one run. It
reached the `model_execution` stage. `MLXPrefixRecomputeExecutor` then failed
closed because it found no bound representation for
`PRODUCTION-REAL-PALACE`. Therefore no MLX forward pass or generated tokens
were produced.

```text
terminal_state = MLX_SMOKE_FAIL;
failure stage = model_execution;
failure =
  modelExecutionFailed(reason: "[model_execution] noBoundRepresentation(
    SimiGoRuntimeContract.ExecutionID(rawValue: \"PRODUCTION-REAL-PALACE\"))");
duration_seconds = 2.6973729133605957;
automatic retry / repair / model replacement / scope expansion = none.
```

## Evidence preservation

```text
MLX_SMOKE_FAIL.json SHA256 =
  24c5b6d4ef6476e4a532f422364a785e7a59c4b6b869ee985616f9f11bf4b5e3;
carrier.sqlite SHA256 =
  95ac7cfc2a43793b0020dec104b74b5d07e771042d52e4c26abaa91aed397aa5;
child.pgid SHA256 =
  2b4e78159e3496c34fa7f29658c6cc9098c661256e0f65c26d6c922974fac331;
child.stdout.log SHA256 =
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;
child.stderr.log SHA256 =
  ead6175219af42ba2dd3c0fadfbdd0f7c590c01c62bfcd0b1ddf4a4dee58fce3.
```

Preliminary source inspection identifies a likely cause: the smoke runner
created one backend for the model executor but allowed the integration to
instantiate a separate default backend. The integration/runtime seed binding
therefore did not reach the executor's backend. This is diagnosis only; no
repair was made and no second run was attempted.

## Hard boundaries

```text
retry or repair-run = FORBIDDEN without separate Human decision;
Runtime Validation V2 rerun = FORBIDDEN / CLOSED;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
