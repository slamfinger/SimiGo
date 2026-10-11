# Actual MLX smoke execution package V6 result

> **Status:** MLX_SMOKE_PASS / AUTHORIZED RUN CONSUMED / CLOSED
> **Run count:** 1 / 1
> **Date:** 2026-10-11

## Authorized binding

```text
execution package = Actual MLX Smoke V6 Revision 4;
execution commit = c37478d4fd2e88aa664181d8733e28f2003ede0c;
manifest =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_MANIFEST_V6.json;
manifest SHA256 =
  d89b505ff3fa562651c1852e173b1ee57206fbffd94ae752ebde86aab31416bb;
marker content = the manifest SHA256 above;
consumed marker path =
  integrated-es-palace/mlx-smoke-v1/ACTUAL_MLX_SMOKE_V6_AUTHORIZATION_CONSUMED;
consumed marker content SHA256 =
  d89b505ff3fa562651c1852e173b1ee57206fbffd94ae752ebde86aab31416bb;
consumed marker file SHA256 =
  0094bb9f3afeeee467b4f569a781f45e86748c53d38084471914ea2482ad3bb4.
```

The marker was consumed by atomic rename before child launch. The Manifest is
preserved unchanged after execution; it still contains the pre-execution fields
`smoke_authorized = false` and `smoke_executed = false`. This result document
is the post-execution authority.

## Observed terminal state

```text
terminal_state = MLX_SMOKE_PASS;
run_count = 1 / 1;
started_at_utc = 2026-10-11T00:36:25Z;
completed_at_utc = 2026-10-11T00:37:57Z;
duration_seconds = 91.85853791236877;
final_position = 1;
final_lifecycle = active;
bound_representation_token_count = 6475;
result_digest = c8d491f40fd794a0cc48b54246505549a862f0414784203189d2d950d83637ce;
computed_item_ids = REAL-COLLECTION, REAL-SEGMENT, REAL-1 through REAL-7;
reused_item_ids = none;
report_state = ADVANCED;
execution_state.status = ADVANCED;
runtime_application_status = APPLIED_SWIFT;
pending_obligations = empty;
all nine carrier settlements = SETTLED;
carrier_object_count = 21;
carrier_all_objects_verify = true;
child stdout = empty;
child stderr = empty.
```

All ten registered success-gate checks were `true`:

```text
report_advanced = true;
execution_state_advanced = true;
runtime_application_applied = true;
required_settlements_settled = true;
final_position_one = true;
final_lifecycle_active = true;
representation_bound = true;
no_pending_obligations = true;
carrier_objects_verified = true;
carrier_database_present = true.
```

## Evidence preservation

```text
MLX_SMOKE_PASS.json SHA256 =
  0411cffb47105efbce444adc995e4ecf8ea5248d75f27f647e0ed64654750266;
carrier.sqlite SHA256 =
  b154e0d2970e2669bdd28a02a0654949271c03f3e421a23bd5c629e6e36cb12e;
child.pgid SHA256 =
  52c971e48c78e35cd8cbb4590f90f6b62c193cbfd3efa9c6f099c006b4809cf4;
child.stdout.log SHA256 =
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;
child.stderr.log SHA256 =
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.
```

The Parent test reported the authorized one-shot as
`PASS / 1 test / 0 failures` in 95.857 seconds. The additional four seconds is
Parent setup and teardown outside the Child-recorded execution duration.

## Stop state

```text
run_count = 1 / 1;
automatic retry / gate adjustment / repair / model replacement =
  NOT PERFORMED AND NOT AUTHORIZED;
V6 authorization = consumed and closed;
production deployment / traffic = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED;
Runtime Validation V2 rerun = FORBIDDEN / CLOSED;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN.
```
