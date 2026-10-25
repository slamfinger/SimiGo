# CCVS-01 A1 Bring-Up Defects — Registered Phase C Evidence

Date: 2026-10-06  
Status: `REGISTERED EVIDENCE / FIXED + CONFORMANCE VERIFIED`  
Study: `CCVS-01`, Phase C, candidate A1 (Baseline A / CarrierSQLite)

## D1 — Stmt double-finalize (lifecycle correctness defect)

```text
Symptom  : SIGSEGV (signal 11) during adapter bring-up tests.
Root cause: prepared-statement wrapper called sqlite3_finalize twice
           (explicit finalize + deinit path) on the same handle.
Class    : resource-lifecycle correctness defect.
Fix      : finalize made idempotent (flag-checked deinit).
Verified : full CarrierSQLite test suite PASS after fix.
Lesson   : carrier adapters own C-level resource lifecycles; lifecycle
           defects can corrupt measurement before any invariant check runs.
```

## D2 — latestRevision produced_at tie (deterministic ordering defect)

```text
Symptom  : conformance check "revision preserves historical representation"
           failed although every API call returned plausible data.
Root cause: latestRevision ordered by produced_at; the conformance suite
           intentionally uses one constant timestamp, so ORDER BY produced_at
           is unstable and the "latest" revision was non-deterministic.
Class    : semantic ordering defect — changes which revision is authoritative.
Fix      : ordering authority = deterministic insertion order (rowid).
Verified : conformance 10/10 PASS after fix.
Governance note (Human direction): semantic ordering authority = deterministic
insertion order. A future candidate using a different revision-ordering
mechanism must be compared under the same correctness contract (I10 history
and latest-revision determinism), not by benchmark numbers alone.
```

## Value for Phase C

D2 demonstrates the conformance suite captures implementation errors that
change Information semantics, not just API presence. This raises confidence
that candidate comparisons rest on a shared correctness contract.
