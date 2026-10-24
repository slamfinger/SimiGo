# G2 Core-API Replay — recorded result

Script: `batch/replay_g2_as_core_api.py`
Machine record: `G2_CORE_API_REPLAY_RESULT.json` (produced by the run below)
Evidence source: `evidence/20261020T082124Z` (frozen, unmodified)

## Command

```
cd g2/batch
python3 replay_g2_as_core_api.py --fixtures fixture-1 fixture-2 fixture-3 \
    --out ../G2_CORE_API_REPLAY_RESULT.json
```

## Result

| field | value |
| --- | --- |
| `result` | `PASS` (3/3 fixtures) |
| `core_api_restore` | `PASS` |
| `core_api_reuse` | `PASS` |
| `new_model_starts` | `0` |
| `is_new_execution_evidence` | `false` |
| `runtime_application_semantics` | `REBINDS_RECORDED_EVENT` |
| `legacy_settlements_classification` | `OPAQUE` — 1 per fixture, 3 total |
| `evidence_checks` | 31 per fixture, all `true` |
| `replay_checks` | 12 per fixture, all `true` |
| `reuse_scope_note` | reuse applies to the rebuilt conforming settlement, not to the G2 objects |

## What was proved

1. **Evidence identity first.** For every fixture, the A / B1 / B2
   `identity_check.json` files match each other and the three frozen engine
   digests in `manifest/G2_MANIFEST.json` (`weights`, `tokenizer`, `combined`).
   `B1/r1.json` is self-consistent (`digest(json.loads(r1_canonical)) ==
   r1_sha256`), `B1/host_record.json` repeats the same canonical R1, and
   `B1/carrier_phase1.json`'s `result_digest` recomputes to the same value.
   The recorded U2 answer is re-checked with the frozen `check_u2` rule and
   matches the recorded `checker.json` on every field.
   If any of these failed, the script would report `INCONCLUSIVE` and write no
   ES record at all. It did not.
2. **The core API expresses the same continuation.** In a temporary replay
   carrier (never `evidence/`), the first record is
   `SIMIGO-G2-REPLAY-BINDING-V1` with `scope: SYNTHETIC_REPLAY`,
   the evidence path/sha256 list, `model_starts: 0` and
   `runtime_application_semantics: REBINDS_RECORDED_EVENT`.
   `define_demand` → `put_source` (declared window + sealed policy) →
   `execute_demand` → `confirm_runtime_application` produces the chain

   ```
   u1-settled -> u1-settled:runtime-applied -> u2-restored
              -> u2-advanced -> u2-advanced:runtime-applied
   ```

   and `restore_continuation` succeeds at `u2-restored` and again at the end.
3. **Reuse is decided by the predicate, not by the script.** The calculator for
   the first demand returns the recorded `R1` verbatim; its `result_digest`
   equals the recorded `r1_sha256`. The calculator for the second demand raises
   `AssertionError("U1 was re-executed")`, so a missed reuse would fail the run
   instead of being relabelled. It was not called: the second demand reports
   `action == "REUSE"`, `computed_item_ids == []`, and the same
   `settlement_object_id` as the first.
4. **Historical settlements are opaque.** Auditing the three canonical G2
   carriers read-only yields `{"OPAQUE": 1}` each. G2 settlements are readable
   and non-reusable by construction, exactly as `SETTLEMENT_CONTRACT_CHANGELOG.md`
   records.

## Provenance of `APPLIED_SWIFT`

`confirm_runtime_application(state_id)` does not accept evidence. It accepts a
state id, requires the state to be `PENDING_SWIFT` and the latest one, and
then records `APPLIED_SWIFT`. The API is therefore a **gate on state shape, not
a verifier of execution**. Everything that distinguishes "a host applied this"
from "a script wrote this" lives in the evidence chain the replay verifies
*before* it creates any carrier. Each link is machine-checked against the frozen
bytes, and the values are copied into the report as `evidence_provenance`.

| link | frozen source | check name | value (fixture-1; same checks per fixture) |
| --- | --- | --- | --- |
| event identity | `B1/host_record.json` | `b1_host_record_event_identity_complete`, `..._event_span_ordered` | `pid 51607`, `parent_pid 51216`, `process_group 51607`, `mode phase1`, `2026-10-20T08:21:43Z → 08:21:56Z` |
| terminal state | `B1/host_record.json`, `terminal.json` | `..._terminal_state`, `terminal_claims_pass` | `exit_code 0`, `u1_generated`/`u1_parsed` both true, arm claim `G2-B: PASS`, `halted: false` |
| executable hash | `manifest/G2_MANIFEST.json` | `frozen_executable_hash_present`, `terminal_binds_frozen_manifest` | host build product `9eee4bc3…99a75217`; four frozen tools (`runner`, `gate`, `checker`, `fixtures_generator`); `terminal.manifest_sha256` equals the on-disk manifest hash |
| entry identity | `B1/host_record.json`, manifest `model_binding` | `..._entry_identity_agrees`, `..._identity_agrees` | model dir `artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6`, revision prefix `6e302ea6`, engine triple `bb0b2711…` / `9bada7c8…` / `d1f01c0c…` |
| result binding | `B1/host_record.json`, `B1/r1.json` | `..._binds_r1`, `b1_host_record_agrees_with_r1` | `u1.r1_sha256` equals `B1/r1.json`'s `r1_sha256`, and `u1.r1_canonical` is byte-equal to it |

What this chain proves: the `R1` rebound into the ES chain is the `R1` of a
host process that started, terminated with exit code 0, ran a binary whose hash
the manifest froze, loaded the model directory the manifest bound, and reported
its own parse checks. What it does **not** prove: that the replay applied
anything. The `APPLIED_SWIFT` record is a statement about the carrier's own
state machine, which is why `runtime_application_semantics` is
`REBINDS_RECORDED_EVENT` rather than `NEW_APPLICATION`.

## Scope of the reuse claim

The reuse proved here is the reuse of a settlement **this script wrote under the
current contract** (`EINFO-SETTLEMENT-CONTRACT-V1`), in a carrier created for
the replay. It says: given recorded bytes, the core API can settle them once and
then reuse that settlement in a later demand without recomputing.

It does **not** say the historical G2 settlement objects became reusable. Those
stay `OPAQUE` — the audit in the same run reports `{"OPAQUE": 3}` — and W1
requires exactly that: a settlement without the contract identity is not
reusable and is not silently upgraded. Rebuilding a conforming settlement from
recorded bytes and reusing the rebuild is a weaker, different claim than
reusing the original object, and the two are reported separately
(`legacy_settlements_classification` versus `core_api_reuse`).

## What was not proved, and is not claimed

- No G2-A/B/C evidence is produced; the 98 frozen evidence files are untouched.
- No model was started, no host was launched, no new Swift application is
  claimed. `APPLIED_SWIFT` inside the replay carrier means "recorded host event
  rebound to the core ES chain".
- The historical G2 settlement objects are not made reusable; only the rebuilt
  conforming settlement is reused.
- This does not show that G2's PASS is reproducible, nor that the core API would
  have chosen the same continuation without the recorded answer.
