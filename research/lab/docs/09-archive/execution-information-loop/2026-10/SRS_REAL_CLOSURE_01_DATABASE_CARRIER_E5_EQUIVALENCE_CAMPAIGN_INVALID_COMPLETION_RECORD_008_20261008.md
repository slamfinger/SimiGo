# SRS-REAL-CLOSURE-01 — Database-Carrier E5 Equivalence Campaign Invalid Completion Record 008

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_E5_EQUIVALENCE_CAMPAIGN_INVALID_COMPLETION_RECORD_008_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** RAW INVALID COMPLETION — HUMAN EVIDENCE AUDIT NOT OPEN
> **Date:** 2026-10-08
> **Campaign:** `exec-dbcarrier-005-2a3b358`
> **Governing Request v1.7 commit:** `1b518c822b586dc3a6a900327267f5e3512a7e49`
> **R4 instrumentation commit:** `44514117f7657eda98b15155a916966d4e7c9b19`
> **E5 authorization/execution commit:** `2a3b3584344bcfd4f7df4dc8f2a0f1df8394a2c2`

## 1. Ruling disposition

E5 is **INVALID / NON-ADJUDICATIVE**. The campaign passed all 31 fresh
destination preflights and executed through O2 with an ES2 adapter invocation,
then fail-closed while binding the already-persisted ES2 output. The complete
evidence chain was not produced. Raw observations cannot be promoted to
equivalence.

```text
outcome = INVALID / NON-ADJUDICATIVE;
stop_code = CAMPAIGN_ES2_OUTPUT_JSON_PARSE_BINDING_DEFECT;
root_cause_class =
  HARNESS_ADAPTER_OUTPUT_PERSISTENCE_RETURN_TYPE_BINDING_DEFECT.
```

`persist_exact_json` correctly persisted and reread the ES2 bytes, then
returned a binding object. The caller incorrectly passed that binding object to
`json.loads`. This is a campaign evidence/provenance API defect, not a
CarrierSQLite semantic, DB schema, ES2/ESN semantic, decision-boundary,
fixture, runner, or EQ/REJ criteria defect.

## 2. Accepted raw campaign facts

```text
authoritative path map identity =
  DATABASE_CARRIER_EQUIVALENCE_EVIDENCE_PATH_BINDING_MANIFEST_005;
path map destination count/version = 31 / 3;
fresh destination preflight = 31/31 PASS;
O0 observation = PRESENT;
O1 observation = PRESENT;
O2 observation = PRESENT;
O3/O4/O5 observations = ABSENT;
ES2 adapter invocation = EXECUTED ONCE;
ES2 adapter output = PERSISTED / VALID JSON;
ESN adapter invocation = NOT REACHED;
database integrity at stop = OK.
```

Raw ES2 output remains non-authoritative. It must not be promoted to a
campaign result.

## 3. Stop-state database facts

```text
O0 database SHA256 = 6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
campaign database SHA256 = f3cf49600c3f07c87b98e0cfd356dd025582b8c61ac5f682a9ccaf1da6275123;
O0 logical state = 0 objects / 0 index / 0 dependencies;
campaign stop state = 2 objects / 1 index / 1 dependency;
O5 database = ABSENT;
SQLite integrity = OK.
```

## 4. Fail-closed boundary

The failing call was:

```python
json.loads(persist_exact_json(output_path, proc.stdout))
```

`persist_exact_json` returns a persistence binding, not bytes. Passing that
binding to `json.loads` raises:

```text
TypeError: the JSON object must be str, bytes or bytearray, not dict
```

The ESN stage, O3–O5, observer, EQ/REJ adjudication, outcome, provenance
closure, serialization self-check and final SHA256SUMS were not reached.

## 5. Evidence-chain disposition

All raw O0–O2 and the single ES2 observation are facts only. The following
artifacts are absent at authoritative stop:

```text
O5_DATABASE: O5_DATABASE.sqlite
OBSERVATION_O3: observations/O3.json
OBSERVATION_O4: observations/O4.json
OBSERVATION_O5: observations/O5.json
ADAPTER_ESN_OUTPUT: adapter/esn-output.json
PREFLIGHT_VERIFICATION: preflight_verification.json
RUNTIME_PROVENANCE: runtime_provenance.json
OBSERVER_VERDICT: observer_verdict.json
OBSERVER_PERSISTENCE_BINDING: observer_persistence_binding.json
EQ_REJ_MATRIX: eq_rej_matrix.json
CAMPAIGN_OUTCOME: campaign_outcome.json
CAMPAIGN_DB_VALIDATION: campaign_db_validation.json
EVIDENCE_SERIALIZATION_SELF_CHECK: evidence_serialization_self_check.json
SHA256SUMS: SHA256SUMS
```

The two added process/stderr files are post-stop captures only and are not
harness-generated completion evidence.

## 6. Claim disposition

```text
raw O0–O2 facts                = ACCEPTED;
raw ES2 REUSE                  = NON-AUTHORITATIVE;
raw ESN BLOCK                  = NOT OBSERVED;
EQ-1..EQ-8 adjudication        = NOT ESTABLISHED;
REJ-1..REJ-14 adjudication     = NOT ESTABLISHED;
CarrierSQLite equivalence      = NOT ESTABLISHED;
broader SimiGo/ES claim        = NOT ESTABLISHED.
```

## 7. Budget disposition

```text
E5 campaign budget              = CONSUMED;
E5 IS-mutation budget           = CONSUMED;
E5 observer budget              = CONSUMED BY FAIL-CLOSED ATTEMPT;
repair                          = NOT AUTHORIZED;
rerun                           = NOT AUTHORIZED;
old campaign/evidence reuse     = FORBIDDEN;
automatic renewal               = FORBIDDEN;
conversion of E5 to VALID       = FORBIDDEN.
```

## 8. Key raw artifact bindings

```text
O0 observation SHA256 = 4a032a960559d584a64465c9a8b9bd4cf7175013a46d7c4e3e5e933b1585a779
O1 observation SHA256 = defbe8d2eaed00260ea45018ca107cd7edb7584ad1f0de2ce1ee88624ee4d8f9
O2 observation SHA256 = 22f619674e93c8aab9dba24787b976eb0f000398996045fab989e0543dfa79d3
ES2 input SHA256      = 0c3c547af76ef386dfce65bc2d31cf2348eea2873b300cd23041eeae1c4df5e1
ES2 output SHA256     = 370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7
path map SHA256       = 67b742397f2e245dd002a9b8344c03cdcb6dbc83be45e6369d2d5d50ee9b7d0b
```

## 9. Next lawful object

The next lawful object is a Human evidence audit of INVALID E5. If correction
is desired, it then requires a new independently budgeted Human-directed
Request scoped to adapter-output persistence return-type binding and a
potential sixth frozen campaign. This record authorizes neither repair, rerun,
evidence reuse, equivalence establishment, nor budget renewal.

## 10. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
