# Actual MLX smoke V5 result

> **Status:** MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED
> **Run count:** 1 / 1
> **Date:** 2026-10-11

## Authorized binding

```text
execution commit =
  933c4442db22aa623d24b15bf5f66fa64308099d;
manifest =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V5.json;
manifest SHA256 =
  1b7f5e4662b4bb16806ab3d53ad33f9283411e5204fc3e5aebe90a6c023a9765;
marker content = the manifest SHA256 above;
consumed marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V5_AUTHORIZATION_CONSUMED;
consumed marker content SHA256 =
  dfa57d74e5593c96ec13b170868c87ffcc1371cfc67f56b42c1a96345cd3134c.
```

## Observed terminal state

The authorized entry consumed the marker and attempted exactly one real MLX
smoke. The child loaded the model, consumed the bound representation through
the unified backend, advanced the Execution State, and persisted a carrier
database. The run then failed the registered success gate because the carrier
audit reported execution-state status `ADVANCED`, while the V5 gate required
`SETTLED`.

```text
terminal_state = MLX_SMOKE_FAIL;
failure = success gate did not pass;
started_at_utc = 2026-10-10T16:34:33Z;
completed_at_utc = 2026-10-10T16:38:28Z;
duration_seconds = 235.05580997467041;
report.state = ADVANCED;
final_position = 1;
final_lifecycle = active;
bound_representation_token_count = 6481;
computed_item_ids =
  REAL-COLLECTION, REAL-SEGMENT, REAL-1 through REAL-7;
reused_item_ids = none;
runtime_application_status = APPLIED_SWIFT;
all nine carrier settlements = SETTLED;
child stderr = empty;
child stdout = empty.
```

The exact gate discrepancy was:

```text
observed execution_state.status = ADVANCED;
required execution_state.status = SETTLED.
```

This is preserved as the registered FAIL reason. It is not reopened, relabeled,
or treated as a PASS because the other execution observations were healthy.

## Evidence preservation

```text
MLX_SMOKE_FAIL.json SHA256 =
  fa7349e7029ca6431ee067a240692235de585b055cb7b959b0f0a71ebe259f38;
carrier.sqlite SHA256 =
  a9006857dfeeefbaaefb9072388e7aff1d623064fca03818e768fdf843c4ad68;
child.pgid SHA256 =
  0f8855f4d41ba0f7f0085a69c998b5e70dd042d42ebeee65621ac43e9566b5f6;
child.stdout.log SHA256 =
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;
child.stderr.log SHA256 =
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.
```

## Stop state

```text
run_count = 1 / 1;
automatic retry / gate adjustment / repair / model replacement =
  NOT PERFORMED AND NOT AUTHORIZED;
V5 authorization = consumed and closed;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED;
Runtime Validation V2 rerun = FORBIDDEN / CLOSED;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN.
```
