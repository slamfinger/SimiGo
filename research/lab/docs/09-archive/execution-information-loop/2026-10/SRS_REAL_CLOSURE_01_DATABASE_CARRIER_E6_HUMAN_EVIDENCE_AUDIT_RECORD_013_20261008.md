# SRS-REAL-CLOSURE-01 — Database-Carrier E6 Human Evidence Audit Record 013

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_E6_HUMAN_EVIDENCE_AUDIT_RECORD_013_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** CLOSED — HUMAN-DIRECTED READ-ONLY EVIDENCE AUDIT; E6 CONFIRMED
> INVALID / NON-ADJUDICATIVE
> **Date:** 2026-10-08
> **Campaign:** exec-dbcarrier-006-66f3c1e
> **Audit base:** `5a93b84783277fa4b6970ce173e20b43ca644698`
> **Governing Request v1.8:** `f7429fea79ebbcfa82f7d52088271d822730ba80`
> **R5 correction:** `e98734a15d4deb04c6fc9758c3683dd33493fd5d`
> **R5 completion:** `c9b572c26169e80e9aa2ec40f0fe2bea6aa2f9ee`
> **E6 authorization/execution:** `66f3c1e3998a7bd42eb74aeee6ace5cc4ef8f291`
> **E6 invalid completion record:** `d86196833e0bc2b2d9cbac0561e9efb0c52e693b`

## 1. Audit ruling

E6 is confirmed **INVALID / NON-ADJUDICATIVE**. The prior broad attribution in
Record 012 — residual preflight provenance path normalization — is refined by
this audit without modifying Record 012.

The exact root cause is:

```text
HARNESS_ADAPTER_BUILD_RECORD_TUPLE_UNPACK_BINDING_DEFECT.
```

`build_adapter()` returns a `(Path, dict)` tuple. The campaign caller assigned
the whole tuple to `adapter_build_record` without unpacking it. Therefore the
proposed preflight graph contained a `PosixPath` at:

```text
preflight.adapter_build[0]
```

The R4 recursive canonical-JSON boundary correctly rejected that object before
writing `preflight_verification.json`. This was not a serializer defect, not a
missed normalization field, and not late re-introduction after canonicalization.

## 2. R5 audit — PASS, no regression

R5's caller-side correction was present and effective:

```python
persist_exact_json(output_path, proc.stdout)
result = json.loads(output_path.read_bytes())
```

`persist_exact_json()` retained its persistence-binding contract. The harness
passed E5's former stop point and executed both adapter stages.

```text
ES2 input SHA256  = 0c3c547af76ef386dfce65bc2d31cf2348eea2873b300cd23041eeae1c4df5e1;
ES2 output SHA256 = 370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7;
raw ES2 decision  = REUSE / REUSE_PATH;
ESN input SHA256  = 315816a7d10c776641fa011210cc301ff483899a5e1bf54ac7e8a7b42287049c;
ESN output SHA256 = c35ea6826e14cd79c5fa61c09dba0660d3af73ac0fc686baa2467a923b502bf4;
raw ESN decision  = BLOCK / BLOCKED_NON_RECOMPUTE_PATH;
ES2/ESN exact persistence = PASS;
ES2/ESN caller parse = PASS.
```

These adapter decisions remain raw and non-authoritative.

## 3. R4 boundary audit — PASS

The fresh v1.8 evidence-path preflight was:

```text
31/31 PASS.
```

At the end of O0–O5, canonical serialization of `PREFLIGHT_VERIFICATION`
encountered the prohibited `PosixPath` and failed closed before file creation.
Thus:

```text
preflight_verification.json = ABSENT;
evidence_serialization_self_check.json = ABSENT;
campaign_process_result.json = ABSENT AT HARNESS STOP;
campaign_stderr.txt = ABSENT AT HARNESS STOP;
SHA256SUMS = ABSENT.
```

R4's invariant worked as specified: it prevented a path-bearing object from
entering the evidence chain. The defect was upstream object construction, not
the R4 boundary.

## 4. Raw sequence facts

The audit accepts only the following as raw facts:

```text
O0 = 0 objects / 0 index / 0 dependencies;
O1 = 1 object  / 0 index / 1 dependency;
O2 = 2 objects / 1 index / 1 dependency;
O3 = 3 objects / 2 index / 1 dependency;
O4 = 4 objects / 2 index / 2 dependencies;
O5 = 4 objects / 2 index / 2 dependencies;
O0/O5 SQLite integrity = OK.
```

The sequence completed, but a complete campaign evidence package did not.

## 5. Adjudication discipline

Mechanical artifacts were not authorized to adjudicate anything:

```text
mechanical observer = ALL PASS / NON-AUTHORITATIVE;
EQ-1..EQ-8 = mechanically true / NOT ESTABLISHED;
REJ-1..REJ-14 = mechanically false / NOT ESTABLISHED;
mechanical outcome = VALID / NON-AUTHORITATIVE;
CarrierSQLite equivalence = NOT ESTABLISHED;
broader SimiGo/ES claim = NOT ESTABLISHED.
```

`EQ all true / REJ all false` has no adjudicative effect without complete
provenance, serialization self-check, process closure and SHA256SUMS.

## 6. Budget disposition

```text
E6 campaign budget       = CONSUMED;
E6 IS-mutation budget    = CONSUMED;
E6 observer budget       = CONSUMED BY INVALID ATTEMPT;
repair                   = NOT AUTHORIZED;
rerun                    = NOT AUTHORIZED;
old evidence reuse       = FORBIDDEN;
automatic renewal        = FORBIDDEN;
E6 -> VALID              = FORBIDDEN.
```

## 7. Key bindings

```text
O0 database SHA256       = 6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
O5 database SHA256       = ba323adc7f52f947d401b21c6ac65fcaf1bea81d057436477e32b54f3c3a1dec;
ES2 output SHA256        = 370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7;
ESN output SHA256        = c35ea6826e14cd79c5fa61c09dba0660d3af73ac0fc686baa2467a923b502bf4;
observer verdict SHA256  = 412b8710879efa871a7051d302ed7fb484ddeafa85c26d7c8ca25ac56495bb8f;
EQ/REJ matrix SHA256     = 5c4f11b45f4879b200b95eaaa79a4078b29f1f18d04767f655b592905899b27e;
path execution record SHA256 = 5e2ecedf7d46d2a1a362f1af90f0d97f7d0681f30e36e4359191cf998350ac39;
path map SHA256          = d6ca9ddf77e99eef6fbc2a80e9dd27a174d28e78f9b8fdb744bfdd63ae15deda.
```

## 8. Next lawful object

The next lawful object is an explicit Human decision:

```text
DENY further work; or
authorize a new independently budgeted Request.
```

If a future Request is authorized, its scope is a Human governance choice. This
audit does not draft, authorize, or design E7. It does not authorize repair,
rerun, old-evidence reuse, normalization-refactor work, equivalence
establishment, or budget renewal.

## 9. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this audit
closure.
```
