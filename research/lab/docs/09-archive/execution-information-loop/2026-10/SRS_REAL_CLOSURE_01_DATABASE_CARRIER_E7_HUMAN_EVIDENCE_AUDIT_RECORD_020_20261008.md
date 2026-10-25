# SRS-REAL-CLOSURE-01 — Database-Carrier E7 Human Evidence Audit Record 020

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_E7_HUMAN_EVIDENCE_AUDIT_RECORD_020_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** CLOSED — HUMAN-DIRECTED READ-ONLY EVIDENCE AUDIT; E7 CONFIRMED
> INVALID / NON-ADJUDICATIVE
> **Date:** 2026-10-08
> **Campaign:** exec-dbcarrier-007-c315442
> **Audit base:** `83b3feae469173c86acdbb40453bd0b7f987f208`
> **E7 authorization/execution:** `c31544210fcfef4a3a48dad16c5ec1a5ea024db6`
> **E7 invalid completion record:** `01670a86c9ed4921f17b63800f38bcbf26cf74a7`
> **Governing Request v2.0:** `d961440ddb0d230c4e69ee7b8abc8ceb026318b7`
> **R6 correction:** `3f8b33a7e97a3d4017e55ad4ca3080b90c95b934`
> **R6 completion:** `7a919fe79936362d63ce6c8230337ccef0023e1e`
> **E7 path-map addendum:** `b8146e93822221aa20b90a40d62265a2a483c8b2`

## 1. Audit ruling

E7 is confirmed **INVALID / NON-ADJUDICATIVE**. The audit finds two independent
harness evidence-layer defects:

```text
PRIMARY_STOP_DEFECT =
  HARNESS_TRANSACTION_LOG_JSONL_PRETTY_SERIALIZATION_PRODUCER_DEFECT;
SECONDARY_DEFECT =
  CAMPAIGN_PROCESS_RESULT_PREMATURE_SUCCESS_PERSISTENCE_DEFECT.
```

The secondary defect was exposed by the same failed run path, but it is not the
same defect as the JSONL producer mismatch. CarrierSQLite semantics, database
schema/transactions, ES2/ESN semantics, decision boundary, tau, fixture, runner
semantic sequence, and EQ/REJ criteria remain non-defective in this stop.

## 2. Check 1 — R5/R6 regression status

No regression was found.

### R5 adapter-output persistence

The exact call form was:

```python
persist_exact_json(output_path, proc.stdout)
result = json.loads(output_path.read_bytes())
```

`persist_exact_json()` still returns a persistence binding and is not misused as
the parsed adapter result. ES2 and ESN outputs were persisted byte-exactly and
parsed separately.

```text
ES2 input SHA256  = 0c3c547af76ef386dfce65bc2d31cf2348eea2873b300cd23041eeae1c4df5e1;
ES2 output SHA256 = 370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7;
raw ES2 decision  = REUSE / REUSE_PATH;
ESN input SHA256  = 315816a7d10c776641fa011210cc301ff483899a5e1bf54ac7e8a7b42287049c;
ESN output SHA256 = c35ea6826e14cd79c5fa61c09dba0660d3af73ac0fc686baa2467a923b502bf4;
raw ESN decision  = BLOCK / BLOCKED_NON_RECOMPUTE_PATH.
```

### R6 adapter-build tuple unpack

The audited E7 source contains:

```python
_, adapter_build_record = build_adapter(evidence_paths)
```

`preflight_verification.json` parsed successfully and its `adapter_build` value
is a record object, not `tuple[Path, dict]`. The harness therefore passed E6's
former stop point and completed O0–O5.

```text
R5 = NO REGRESSION;
R6 = NO REGRESSION;
fresh path preflight = 31/31 PASS;
O0–O5 = COMPLETE;
O0/O5 SQLite integrity = OK.
```

## 3. Check 2 — transaction log defect boundary

The JSONL contract is unambiguous. The manifest destination is
`TRANSACTION_LOG` / `transaction_log.jsonl`, and the serialization self-check
consumer reads the file with `.splitlines()` and parses each line as one JSON
object:

```python
json.loads(line) for line in transaction_log.read_text(...).splitlines()
```

The producer instead called the generic canonical-JSON helper with `indent=2`.
That helper is correct for standalone JSON evidence artifacts, but produces
multi-line pretty JSON. Consequently:

```text
transaction log SHA256 = 881fa05ff6700917a9b306d29d0fdbcd2cbc5caab7026580725bf394b50ec0b5;
raw line count = 88;
per-line JSON parse = FAIL;
stream parse as concatenated JSON objects = PASS;
valid JSON objects in stream = 8;
events = four BEGIN/COMMIT pairs.
```

The consumer did not falsely reject valid JSONL. It correctly rejected an
aggregate pretty-JSON stream presented under a `.jsonl` contract. The primary
defect is therefore producer-side and narrowly bounded to the transaction-log
serialization contract. No broader serializer replacement is authorized by this
audit.

## 4. Check 3 — stale `returncode=0` classification

The stale process result is a **separate process-result lifecycle/ordering
defect**, not the JSONL producer defect itself.

The E7 source wrote process-result evidence before final closure:

```text
line 786: resolve CAMPAIGN_PROCESS_RESULT;
line 787: write process result with campaign_returncode = 0,
          campaign_stderr = "", and success stdout;
line 801: write_serialization_self_check(...);
line 802: write_sha_sums(...);
line 803: return 0.
```

Thus the artifact recorded success before serialization self-check, stderr
closure and SHA256SUMS existed. The later JSONL self-check raised, the process
actually exited nonzero, and no code updated or invalidated the earlier
process-result artifact. Therefore:

```text
campaign_process_result.json returncode = 0 / STALE;
actual campaign exit = NONZERO / FAIL-CLOSED;
classification =
  CAMPAIGN_PROCESS_RESULT_PREMATURE_SUCCESS_PERSISTENCE_DEFECT;
relationship to primary JSONL defect =
  exposed by same failed run; independent root defect.
```

This finding does not imply another hidden semantic failure. It shows the
process-result producer lacks a freshness/consistency invariant: success-result
evidence must not persist before all closure checks pass, and failed closure
must not leave a stale success artifact as final process evidence.

## 5. Check 4 — adjudication remains forbidden

The mechanical artifacts do not adjudicate equivalence:

```text
mechanical observer = PASS / NON-AUTHORITATIVE;
EQ-1..EQ-8 = mechanically true / NOT ESTABLISHED;
REJ-1..REJ-14 = mechanically false / NOT ESTABLISHED;
campaign outcome = mechanically VALID / NON-AUTHORITATIVE;
CarrierSQLite equivalence = NOT ESTABLISHED;
broader SimiGo/ES claim = NOT ESTABLISHED.
```

Required complete-chain artifacts absent at stop:

```text
evidence_serialization_self_check.json;
campaign_stderr.txt;
SHA256SUMS.
```

The process result is also stale. Therefore E7 cannot be converted to VALID and
O5 state cannot be used retroactively for adjudication.

## 6. Accepted raw facts

```text
fresh path preflight = 31/31 PASS;
O0 = 0 objects / 0 index / 0 dependencies;
O1 = 1 object / 0 index / 1 dependency;
O2 = 2 objects / 1 index / 1 dependency;
O3 = 3 objects / 2 index / 1 dependency;
O4 = 4 objects / 2 index / 2 dependencies;
O5 = 4 objects / 2 index / 2 dependencies;
O0/O5 SQLite integrity = OK;
R5/R6 = NO REGRESSION.
```

## 7. Key bindings

```text
O0 database SHA256       = 6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
O5 database SHA256       = ba323adc7f52f947d401b21c6ac65fcaf1bea81d057436477e32b54f3c3a1dec;
ES2 output SHA256        = 370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7;
ESN output SHA256        = c35ea6826e14cd79c5fa61c09dba0660d3af73ac0fc686baa2467a923b502bf4;
observer verdict SHA256  = 412b8710879efa871a7051d302ed7fb484ddeafa85c26d7c8ca25ac56495bb8f;
process result SHA256    = 17ba71b44ec6ef219bb61f18f636e4d614dd411a8638bc8329c9df19ce8e41f0;
EQ/REJ matrix SHA256     = 5c4f11b45f4879b200b95eaaa79a4078b29f1f18d04767f655b592905899b27e;
transaction log SHA256   = 881fa05ff6700917a9b306d29d0fdbcd2cbc5caab7026580725bf394b50ec0b5;
authoritative path map SHA256 = c719043c74a157c17a0d8e96013168c7fae29cb2f58976e89adf8b9c5cb946b8.
```

## 8. Budget disposition

```text
E7 campaign budget       = CONSUMED;
E7 IS-mutation budget    = CONSUMED;
E7 observer budget       = CONSUMED BY INVALID ATTEMPT;
repair                   = NOT AUTHORIZED;
rerun                    = NOT AUTHORIZED;
old evidence reuse       = FORBIDDEN;
automatic renewal        = FORBIDDEN;
E7 -> VALID              = FORBIDDEN;
E8                       = NOT AUTHORIZED AND NOT DRAFTED.
```

## 9. Next lawful object

The next lawful object is an explicit Human strategic decision:

```text
DENY further work; or
authorize a new independently budgeted Request.
```

If the Human authorizes further work, this audit identifies a narrow candidate
scope—transaction-log JSONL producer/consumer contract correction plus a
process-result freshness/lifecycle invariant and fresh harness validation—but
this audit neither drafts, scopes into a Request, authorizes, nor launches E8.

## 10. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this audit
closure.
```
