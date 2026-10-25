# Harness preflight (NOT a scientific condition)

Model-free wiring check run before the real-model experiment:

1. `run_phase_f.define_detached_task` built a signed fixture under
   `provenance_policy="required"` into `preflight/carrier.sqlite`.
2. A separate `SimiGoTaskRun --admission-probe` process ran the same production
   `resolveTaskInput` path with `SIMIGO_SETTLEMENT_PROVENANCE=verify` and no
   signing key in its environment.
3. Result: `input_admission_status = ADMITTED`, `terminal_state = INPUT_ADMITTED`,
   and `settlement_signatures[]` carries an Ed25519 record for `TASK-SOURCE`
   with `verified: true`.

Purpose: prove fixture signing, trust-anchor loading, the verify-only consumer
policy and the evidence field names before spending real-model time. It loads no
model, settles nothing, and is not one of the six experiment conditions.

The trust root used here (key id `e-round-e9c49aac4cfcb864`) was provisional and
was deleted when the scientific run provisioned its own trust root, so this probe
record is kept only as a harness log and is no longer verifiable against the
run anchor.
