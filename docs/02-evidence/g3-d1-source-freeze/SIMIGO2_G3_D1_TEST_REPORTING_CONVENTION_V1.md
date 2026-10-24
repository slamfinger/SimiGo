# SimiGo G3/D1 Test Evidence Reporting Convention

**Version:** 1.0  
**Status:** Normative reporting rule  
**Intended repository location:** `docs/02-evidence/g3-d1-source-freeze/SIMIGO2_G3_D1_TEST_REPORTING_CONVENTION_V1.md`

## 1. Purpose

This specification prevents distinct test invocations and distinct evidence classes from being merged into a single, ambiguous PASS claim. It governs reporting for the G3/D1 Phase 1 worker, supervisor, identity-binding, and gated-entry work.

## 2. Supervisor test runs must be reported separately

The following are **different runs** and must never be combined into one row, one count, or one undifferentiated PASS statement:

| Run class | Invocation condition | Reported result | What it establishes |
|---|---|---|---|
| Default supervisor test run | `G3D1SupervisorTests` without enabling subprocess integration | **12 tests, 2 skipped** (per the recorded run) | The default test configuration passed its executed tests; the two skipped tests were not exercised in that run. |
| Subprocess-enabled supervisor test run | `G3D1_RUN_SUBPROCESS_TESTS=1` with `G3D1_WORKER_BINARY` set to the intended built worker | **12/12 passed** (per the recorded run) | The subprocess-enabled integration cases ran against the specified worker binary and passed in that invocation. |

The second result does not retroactively turn the two skips in the default run into executed tests. Conversely, the default run's skip count must not be copied onto the subprocess-enabled 12/12 run unless that invocation's own output reports skips.

Each run must have its own evidence record, including:

- exact command and relevant environment variables;
- test target/suite and build-product identity;
- total, passed, failed, and skipped counts as emitted by that run;
- exit code;
- whether real subprocess integration was enabled;
- for subprocess integration, confirmation that distinct worker PIDs were observed and that the intended worker binary was used.

If these details are unavailable, mark them **not recorded**; do not infer them from another run.

## 3. Keep test layers distinct

Do not merge or substitute these evidence classes:

1. **Contract/unit tests** — test the contract behavior and state transitions.
2. **Model-free production-path tests** — exercise real routing/session/gate code with a model-free or weightless test configuration.
3. **Subprocess integration tests** — exercise actual worker processes and their supervisor lifecycle.
4. **Identity-binding verification** — verifies the launched executable identity against the bound record and frozen inputs.
5. **Real-model experiments** — load and execute the intended model and test the actual ES/IS continuation claim.

A PASS at one layer is not evidence that a later layer has run. In particular, successful subprocess or identity tests do not establish that a model was loaded or that a real-model G3 experiment passed.

## 4. Meaning of `bound`

For this project, `bound` means that the worker execution identity is bound according to the identity protocol and the verification record. It does **not** mean any of the following:

- the live provider is trusted or registered;
- the provider-trust gate was passed;
- model generation occurred;
- settlement or binding consumption occurred;
- the real-model ES → IS → new ES continuation experiment succeeded.

When a worker correctly fails closed at `provider_trust` with `generationCallCount == 0`, report this as an expected gated refusal for that run, not as a successful model execution and not automatically as a worker identity failure. Keep the identity result and the gated-execution result in separate fields.

## 5. Required reporting format

Report each invocation independently. A recommended compact record is:

```text
run_id:
run_class: default-supervisor | subprocess-enabled-supervisor | contract | model-free-production | identity-verification | real-model
command:
environment:
worker_binary_sha256: <hash | not-applicable | not-recorded>
subprocess_integration: true | false
worker_pids: <distinct PID list | not-applicable | not-recorded>
tests_total:
passed:
failed:
skipped:
exit_code:
identity_status: bound | control-only | unclosed | not-applicable
provider_trust_result: passed | refused | not-reached | not-applicable
model_loaded: true | false | not-established
model_generation_calls:
settlement_or_binding_consumption:
claim_scope:
limitations:
```

Values must come from that invocation's actual output or its preserved evidence. Do not fill missing fields from a different invocation.

## 6. Frozen-tree and same-round discipline

When test results are used to support a frozen-source claim:

- record the source and runner digests used for that run;
- ensure the test run corresponds to the code/build product identified by those digests;
- keep the manifest, sidecar, artifact stamp, and execution-identity record consistent with the final round;
- if an in-scope file changes, re-run the required build/stamp/identity/verify chain before claiming same-round consistency;
- report a missing worker as `unclosed`, and report a stand-in run as `control-only`; neither may be promoted to `bound` on the basis of a successful stand-in launch.

## 7. Current known example (not a substitute for fresh evidence)

The currently recorded figures must be presented as separate invocations:

- Default `G3D1SupervisorTests`: **12 tests, 2 skipped**.
- Subprocess-enabled `G3D1SupervisorTests`: **12/12 passed**, with the real subprocess integration explicitly enabled.
- Full-suite bundle results recorded elsewhere: RuntimeContract **130**, Experimental **383 with 5 skipped**, Swift Testing **75 tests / 11 suites**. These totals belong to the full-suite run and must not be added to or substituted for the supervisor-specific figures.

These numbers are historical records. Any new report must prefer the actual counts emitted by the new invocation and must not silently inherit these values.
