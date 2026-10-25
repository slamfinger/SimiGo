# K-Round Evidence Report — Native Result-Contract as Pre-Settlement Authority

Round: K · Label: `es-is-native-result-contract-20261023k` · Date: 2026-10-23
Terminal state: **OBSERVED** · Independent verifier: **PASS (issue_count = 0)**

## Research question (unchanged from the objective)

Can the native Swift result-contract engine — fed **only** with Information
Space-verified bindings — act as the **pre-settlement authority** for a real
model on run-time-generated IDs, agreeing with the Python gate where both
implement a construct and refusing fail-closed (settling and signing nothing)
where only Python does — so that a settled semantic result can leave its old
execution context and be recovered incrementally through the Information Space,
rather than merely bolting on another validation framework?

## Claim tiers (fact / conclusion / assumption / authorization)

- **FACT (measured this session):** listed under "What was actually run".
- **CONCLUSION (drawn from the facts):** listed under "What the facts establish".
- **ASSUMPTION / NOT CLAIMED:** listed under "Honest limits".
- **AUTHORIZATION:** no commit, no stage, no `carrier_loop.py` or historical
  artifact change was made or is implied; HEAD stayed at `e7f63856`.

## What was actually run (FACT)

| Artifact | Result |
| --- | --- |
| `swift build --product SimiGoTaskRun` relink | binary SHA `35fe017e89e88820…`, matches the SHA recorded in `summary.json` and re-hashed by the verifier |
| Native Swift unit tests (`--filter DeclarativeNativeResultContractTests`) | `Executed 16 tests, with 0 failures` (re-run independently this session; the earlier "Executed 0" tail was a different, empty test bundle) |
| Cross-language parity harness + comparator | `issue_count = 0` over 32 cases; cases fixture SHA `b4311ee1…` re-hashed and matched |
| Regression suite (H / I / J / admission / `<unit>`) | all members exit 0, verdict PASS |
| **K0 — three-process real-model run** (Qwen3-Coder-30B-A3B-Instruct-4bit, run-time IDs `J-7ab37051-U1/U2/U3`) | every stage: native gate VALID, bindings taken from IS (each carries `settlement_object_id` + `value_sha256`), `native == python` values agree, `native == settled` declared fields agree, then settlement **and** signature created; terminal `TASK_SETTLED` |
| **N2 — counterfactual** (`--u1-constraint-kind digest_equals_binding`, real model) | native gate **refused** after a real generation (`model_continuation_calls = 1`) with structured `{code: CONTRACT_UNKNOWN_CONSTRAINT, stage: PRODUCER_RESULT_CONTRACT, field: route_key}`; **no settlement, no signature**; Python gate implements the same kind (`PRODUCER_RESULT_DERIVATION_MISMATCH`, i.e. it does not treat it as unknown) |
| Independent verifier `validate_k_evidence.py` | PASS, issue_count 0 |

## Production ordering, as required

The native gate runs inside `SimiGoTaskRun.continueTask`'s `modelValue` closure,
**before** any value file is written and **before** the `execute-with-model-result`
settlement bridge is called. A throw therefore cannot leave a settlement object
or a signature envelope. This is exactly the mandated order: Information Space
admission (signature + dependency validation) supplies verified bindings → native
contract engine validates → only on VALID does the result settle and sign. On the
real model K0 confirms the happy path; N2 confirms the fail-closed refusal path.

## Bugs fixed on the path to landing (each proven by a run)

1. **Adapter binding projection** read engine-only bytes with bindings stripped,
   so `equals_binding` always saw an empty binding set. Fix: project from
   `fullContractData`. Proven by K0 `native_verified_bindings` being non-empty
   with IS digests on the real model.
2. **`capture_group` corrupted to `Bool`** by `AnyCodable` (Foundation bridges
   `NSNumber(1)` to `true` ahead of the `Int` case), making the integer capture
   group schema-invalid at runtime. Fix: re-encode forwarded contract with
   `JSONSerialization` (faithful `NSNumber` preservation). Proven by the single-stage
   real-model smoke reaching `SETTLED` and by K0 VALID across all three stages.
3. **Structured N2 refusal was lost** because `continueTask` re-wraps a closure
   throw into `.modelExecutionFailed(reason:)`, dropping the typed rejection. Fix:
   `main.swift` handles that case and `NativeTaskResultContract.rejectionEvidence`
   reconstructs `{stage, code, field}` from the wrapped reason. Proven by N2's
   populated `native_result_contract_rejection`.
4. **Misleading `generation_before_refusal`** — a refused result persists no
   `generated_text`, so the flag read false even though the model generated. Fix:
   derive it from the runtime counter. The verifier independently checks
   `counters.model_continuation_calls ≥ 1`, so it no longer relies on the flag.

## What the facts establish (CONCLUSION)

- The native engine is now the **authoritative pre-settlement gate on the real
  production path**, selecting rules from each item's own declaration — the
  validator takes no task ID, and validation passed on run-time IDs never seen by
  any fixture.
- Native and Python agree value-for-value on the real model (K0 parity on live
  output), on top of the 32-case shared-fixture parity (`issue_count = 0`).
- Where only Python implements a construct, native **refuses fail-closed and
  settles nothing** (N2) — the safety direction required before Python can ever be
  retired. The Python gate is retained in parallel, per the instruction, until
  shared tests prove equivalence (they now do for the implemented family).

## Honest limits (NOT claimed)

- **Not committed / not staged.** All work is uncommitted in the working tree;
  `git diff --cached` is empty; HEAD stayed `e7f63856`. This report documents a
  verified landing on the local tree, not a merge.
- **`carrier_loop.py` and prior-round run dirs are byte-for-byte unchanged by
  K** (its SHA matches the pre-K pre-change snapshot; prior `es-is-*` dirs keep
  pre-K mtimes). The `carrier_loop` settlement-contract changes were H/I/J work
  already present before this round.
- **Supported constraint family is narrower in native than Python.** Native
  implements `equals_binding / concat / equals_field / equals_literal`; it
  deliberately refuses `digest_equals_binding` etc. fail-closed (that refusal is
  the point of N2), not silently ignores them. Retiring Python requires porting
  the remaining kinds or shrinking the accepted vocabulary first.
- One model snapshot, one seed family per stage; match_policy `"first"` still
  tolerates trailing contradicting lines in upstream fixtures (carried-over limit).
- The real-model N2 refusal is for an *unsupported* kind; a real-model refusal on
  a *supported* construct (e.g. a wrong derived value) was not separately run.

## Reproduce

```
cd simigo2-experimental && swift build --product SimiGoTaskRun \
  && swift test --filter DeclarativeNativeResultContractTests
cd simigo2-experimental/scripts/ordinary_task && /usr/bin/python3 run_phase_k.py \
  --model-dir <Qwen3-Coder-30B-A3B-Instruct-4bit snapshot> --max-tokens 48
/usr/bin/python3 execution-information-loop/validate_k_evidence.py \
  ~/SimiGo-Agent-Runs/es-is-native-result-contract-20261023k
```
