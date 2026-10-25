# Execution–Information Loop Validity Gate PASS

> **Status:** ISOLATED VALIDITY / SELECTIVE RECOMPUTE PASS  
> **Date:** 2026-10-09  
> **Canonical base before change:** `2bc26d89df55d6330e072546093fda2d1e105200`

## 1. Evidence-binding correction

The prior `Real PALACE Settlement Invalidation Propagation PASS` section in
`docs/RESEARCH_STATE.md` incorrectly cited the earlier FAIL capture. The FAIL
record remains retained unchanged. The valid PASS evidence is
`REAL_PALACE_INVALIDATION_E2E_RECORD_FIXED.json`; its binding is corrected by
this record. No evidence object is overwritten.

```text
FAIL capture = REAL_PALACE_INVALIDATION_E2E_RECORD.json;
PASS capture = REAL_PALACE_INVALIDATION_E2E_RECORD_FIXED.json.
```

## 2. Added capability

Settlements are no longer treated as permanent truth merely because their state
is `SETTLED`. Each information item may carry a UTC `valid_until_utc`; the
settlement result and basis retain that condition. Execution supplies the
observation time. Reuse requires source, version, dependency-object and validity
checks to pass together.

```text
valid settlement       = REUSE;
expired settlement     = COMPUTE;
dependent downstream   = selective COMPUTE;
unaffected item        = REUSE;
malformed observation  = BLOCKED_VALIDITY_FAILURE / no calculator call;
invalid source window  = rejected before persistence;
missing information    = BLOCKED_MISSING_INFORMATION / no guess.
```

## 3. Verification

```text
execution-information-loop/selftest.py            = PASS;
execution-information-loop/carrier_selftest.py    = PASS;
execution-information-loop/real_palace_selftest.py = PASS.
```

New write-once evidence:

```text
VALIDITY_E2E_RECORD.json
  SHA256 = 748a3380ab4d59ff1efb6bfaea9a89182869886c9cf231c6dafc5c118e482ea4;

REAL_PALACE_VALIDITY_E2E_RECORD.json
  SHA256 = ea704ba2629e94eaa125931b336cb99a5419d74baa0f5634bb3cbdbe1f5d311a.
```

The real-source record uses the sealed D002 snapshot in read-only mode and
declares the validity window as an isolated test condition; it does not claim
that PALACE supplies that window.

## 4. Boundary

This is still an isolated vertical slice. It does not rerun D-002, execute
D-001, mutate PALACE or canonical Information Space, use semantic/vector/model
access, establish PALACE equivalence, or prove Integrated SimiGo. Real PALACE
structural dependency discovery and source-supplied validity conditions remain
separate work.
