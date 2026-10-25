# PALACE — MINIMAL-PIR-EXP-001 Human Evidence Audit Record 031

> **Status:** CLOSED — FOUR-POINT HUMAN EVIDENCE AUDIT PASS; EXPERIMENT REMAINS
> INVALID / NON-ADJUDICATIVE
> **Date:** 2026-10-08
> **Experiment:** MINIMAL-PIR-EXP-001
> **Authorization/execution commit:** `36dc1de8d51d31f62f72db5f7b150a26c39a3667`
> **Runner commit:** `86cbfa119467f2836cabb1a324ebfdff17aef7a6`
> **Invalid completion record:** `60cb35b...`
> **Audit base:** `056f9a724d909b8b188c8449ff76a06e1476555d`

## 1. Audit ruling

The one-shot execution is confirmed **INVALID / NON-ADJUDICATIVE**. The audit
confirms a single, narrowly bounded execution-recorder defect:

```text
stop_code =
  MINIMAL_PIR_OBSERVATION_JSONL_BYTES_TO_TEXT_PERSISTENCE_DEFECT;
root_cause_class =
  HARNESS_EXPERIMENT_EVIDENCE_BYTES_TO_TEXT_PERSISTENCE_DEFECT.
```

The defect is strictly in the EV-P08 persistence call path. It is not a PIR
semantic defect, fixture defect, oracle leakage, IS mutation, CarrierSQLite
regression, or EQ/REJ criteria defect.

## 2. Check 1 — recorder contract

At the exact execution commit, EV-P08 evidence was generated as bytes:

```python
observations_path.write_text(
    b"".join(
        json.dumps(...).encode("utf-8") + b"\n"
        for x in observations
    )
)
```

`Path.write_text()` requires `str`; `Path.write_bytes()` accepts `bytes`. The
caller already held canonical JSONL bytes, so the lawful persistence form was
`write_bytes(...)`. Instead, the caller passed bytes to `write_text(...)`,
producing:

```text
TypeError: data must be str, not bytes
```

The boundary is explicit from the standard path APIs and the local byte
construction. This is therefore a caller-side bytes/text persistence contract
violation, not ambiguity in PIR semantics.

## 3. Check 2 — physical reconciliation crossed the EV-P08 boundary

The source proves that bounded physical reconciliation occurred in memory before
persistence was attempted:

```text
for every accepted Information Scope object:
    reconcile_accepted_object(...)
    observations.append(...)

then:
    phase S4 completed;
    observations_path.write_text(...)
```

Because the crash occurred at `write_text`, all 20 accepted-object
reconciliations had been appended in memory. However, their payloads were never
persisted. The audit therefore distinguishes:

```text
physical reconciliation occurred in memory = ACCEPTED AS AN EXECUTION FACT;
physical reconciliation evidence closure   = NOT ESTABLISHED;
individual verdict payload recoverability  = NOT ESTABLISHED.
```

No post-stop capture may be promoted to formal EV-P08 evidence.

## 4. Check 3 — semantic / fixture / oracle boundary

```text
E-L policy is_update_authorized = false;
measured-path forbidden keys = NONE;
accepted Information Scope = 20 / 20;
registered N = 10,000;
side-channel denial record = all denial fields false;
fixture tree unchanged since execution commit;
implementation/CarrierSQLite baseline unchanged.
```

No IS mutation, fixture mutation, oracle leakage, whole-space scan, semantic
inference, model similarity, backend selection, or E9/Database-Carrier work was
found.

## 5. Check 4 — no stale-success lifecycle defect

The only process-result artifact is explicitly marked:

```text
artifact_state = FAILURE_POST_STOP_CAPTURE;
post_stop_capture = true;
campaign_returncode = 1;
repair_performed = false;
rerun_performed = false.
```

No premature success artifact persisted. The following are absent:

```text
EXPERIMENT_RESULT.json;
EV-P08_physical_reconciliation_observations.jsonl;
EV-P11_fresh_closure.json;
EV-P12_evaluation_join.json;
EV-P13_false_positives_false_negatives.json;
EV-P14_paired_e_l_e_s_comparison.json;
EV-P16_raw_object_touch_audit.jsonl;
EV-P17_move_rename_correlation_evidence.json;
EV-P18_observations_versus_changes_counts.json.
```

Thus E7's premature-success pattern did not recur.

## 6. Artifact bindings

```text
E-L policy SHA256 =
  d2ab029c7e56e092283cb4df6deec026b26d32251420c9687d918e29e7e0c1bd;
E-L side-channel denial SHA256 =
  389ae228652d9426867bdfbf4685297c90b26e5ab1cd445249fabeb4c4f961bf;
post-stop process result SHA256 =
  ce5f834c502be6f7abad93ffbe1d6d55d2066462937ddc16d2f1c03dd94710fd;
post-stop stderr SHA256 =
  8ce3afcd4cb8a43b8294eb85fc08228c483db4344bff36fcf3d40dd2de7a9765.
```

## 7. Claim disposition

```text
MINIMAL-PIR-EXP-001                = INVALID / NON-ADJUDICATIVE;
bounded physical reconciliation    = OCCURRED IN MEMORY / NOT EVIDENCE-CLOSED;
physical reconciliation evidence   = NOT ESTABLISHED;
PIR effectiveness                  = NOT ESTABLISHED;
PIR performance theorem            = NOT ESTABLISHED;
PALACE equivalence                 = NOT ESTABLISHED;
integrated SimiGo proof            = NOT ESTABLISHED;
E8 bounded CarrierSQLite equivalence = ESTABLISHED / UNCHANGED.
```

## 8. Next lawful object

The next lawful object is an explicit Human strategic decision:

```text
DENY further PIR work; or
authorize a new independently budgeted Request scoped to
experiment-recorder bytes/text persistence correction, targeted regression,
fresh experiment-entry validation and a potential future execution.
```

This audit does not repair the recorder, design EXP-002, create fixtures,
authorize execution, or broaden PIR claims.

## 9. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this audit
closure.
```
