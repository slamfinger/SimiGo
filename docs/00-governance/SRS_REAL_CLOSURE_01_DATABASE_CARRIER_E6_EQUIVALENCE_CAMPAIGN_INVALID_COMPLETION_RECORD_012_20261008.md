# SRS-REAL-CLOSURE-01 — Database-Carrier E6 Equivalence Campaign Invalid Completion Record 012

> **Status:** RAW INVALID COMPLETION — HUMAN EVIDENCE AUDIT NOT OPEN
> **Date:** 2026-10-08
> **Campaign:** exec-dbcarrier-006-66f3c1e
> **Governing Request v1.8:** `f7429fea79ebbcfa82f7d52088271d822730ba80`
> **R5 correction commit:** `e98734a15d4deb04c6fc9758c3683dd33493fd5d`
> **R5 completion record:** `c9b572c26169e80e9aa2ec40f0fe2bea6aa2f9ee`
> **E6 authorization/execution commit:** `66f3c1e3998a7bd42eb74aeee6ace5cc4ef8f291`

## 1. Disposition

E6 is **INVALID / NON-ADJUDICATIVE**. It passed 31/31 fresh path preflight,
completed O0–O5, persisted ES2/ESN outputs, observer verdict and persistence
binding, EQ/REJ matrix, campaign outcome and DB validation, then fail-closed
while canonically serializing `PREFLIGHT_VERIFICATION`.

```text
outcome = INVALID / NON-ADJUDICATIVE;
stop_code =
  CAMPAIGN_PREFLIGHT_VERIFICATION_POSIXPATH_SERIALIZATION_DEFECT;
root_cause_class =
  HARNESS_PREFLIGHT_PROVENANCE_PATH_NORMALIZATION_RESIDUAL_DEFECT.
```

The canonical writer rejected a residual `PosixPath` before writing. This is
the same general path-normalization defect class previously exposed at E4; R5
corrected the separate E5 adapter-output return-type defect but did not exhaust
all preflight provenance path-normalization sites.

## 2. R5 effectiveness

R5 was effective for its narrow target:

```text
ES2 adapter invocation = COMPLETED;
ES2 exact output persistence = PASS;
ES2 persisted-output caller parse = PASS;
ESN adapter invocation = COMPLETED;
ESN exact output persistence = PASS;
ESN persisted-output caller parse = PASS;
persist_exact_json contract = UNCHANGED.
```

Thus E5's return-type defect did not recur. The E6 stop is independent of that
correction and of CarrierSQLite semantics.

## 3. Accepted raw campaign facts

```text
fresh path preflight = 31/31 PASS;
O0 logical state = 0 objects / 0 index / 0 dependencies;
O5 logical state = 4 objects / 2 index / 2 dependencies;
O0/O5 database integrity = OK;
O0–O5 observations = PRESENT;
raw ES2 = REUSE / REUSE_PATH;
raw ESN = BLOCK / BLOCKED_NON_RECOMPUTE_PATH;
observer mechanical checks = ALL PASS.
```

All of these are raw facts or non-authoritative harness observations only.

## 4. Complete-chain failure

At authoritative stop these required artifacts were absent:

```text
preflight_verification.json;
evidence_serialization_self_check.json;
campaign_process_result.json;
campaign_stderr.txt;
SHA256SUMS.
```

The added process/stderr files are post-stop captures only, not
harness-generated completion evidence. Mechanically present outcome, EQ/REJ,
observer and provenance artifacts remain non-authoritative because the complete
chain is not closed.

## 5. Claim disposition

```text
raw O0–O5 facts              = ACCEPTED;
raw ES2 REUSE                = NON-AUTHORITATIVE;
raw ESN BLOCK                = NON-AUTHORITATIVE;
EQ-1..EQ-8                   = NOT ESTABLISHED;
REJ-1..REJ-14                = NOT ESTABLISHED;
CarrierSQLite equivalence    = NOT ESTABLISHED;
broader SimiGo/ES claim      = NOT ESTABLISHED.
```

The O5 state cannot be used to retrofit adjudication or convert E6 to VALID.

## 6. Budget disposition

```text
E6 campaign budget           = CONSUMED;
E6 IS-mutation budget        = CONSUMED;
E6 observer budget           = CONSUMED BY INVALID ATTEMPT;
repair                       = NOT AUTHORIZED;
rerun                        = NOT AUTHORIZED;
E5/E6 old-evidence reuse     = FORBIDDEN;
automatic renewal            = FORBIDDEN.
```

## 7. Key bindings

```text
O0 database SHA256 = 6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
O5 database SHA256 = ba323adc7f52f947d401b21c6ac65fcaf1bea81d057436477e32b54f3c3a1dec;
ES2 input SHA256   = 0c3c547af76ef386dfce65bc2d31cf2348eea2873b300cd23041eeae1c4df5e1;
ES2 output SHA256  = 370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7;
ESN input SHA256   = 315816a7d10c776641fa011210cc301ff483899a5e1bf54ac7e8a7b42287049c;
ESN output SHA256  = c35ea6826e14cd79c5fa61c09dba0660d3af73ac0fc686baa2467a923b502bf4;
observer verdict SHA256 = 412b8710879efa871a7051d302ed7fb484ddeafa85c26d7c8ca25ac56495bb8f;
authoritative path map SHA256 = d6ca9ddf77e99eef6fbc2a80e9dd27a174d28e78f9b8fdb744bfdd63ae15deda;
```

## 8. Next lawful object

The next lawful object is Human evidence audit of INVALID E6. If further work
is proposed, it must begin with a new independently budgeted Human-directed
Request and must decide whether remaining harness-evidence risk justifies a
seventh campaign. Stopping without adjudication is a lawful research outcome.
This record authorizes no repair, rerun, old-evidence reuse, equivalence
establishment, or renewal.

## 9. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
