# SimiGo Integrated ES–PALACE non-D002 validation result — 2026-10-10

> **Status:** VALIDATION_FAIL — ONE-RUN STOP RULE ENFORCED.
> No repair, rerun, or follow-on execution is authorized by this record.

## Run binding

```text
manifest instance id = 40CC5A97-8B0B-55C3-9D5A-4F26335C6FFA;
manifest canonical content SHA256 =
  039d73f1f5348b3e763b4b9bf8bffc46404df0ff11a84eff5494c2193098d99f;
runner SHA256 =
  f27b1f055b6864445fb00d63fb9078744319964234a090648a28a4d1b5c1d8fb;
authorized runs = 1;
executed runs = 1;
terminal state = VALIDATION_FAIL.
```

## Typed outcomes

```text
P-LAWFUL     = PASS / CONTINUE / SETTLED_CONTINUATION;
P-SETTLED    = PASS / REUSE / SETTLED_CONTINUATION;
P-BLOCKED    = PASS / BLOCK / BLOCKED_LAWFUL_CONTINUATION;
N-MISSING    = FAIL / BLOCK / BLOCKED_DEFECT / MISSING_INFORMATION_BLOCK;
N-STALE      = FAIL / BLOCK / BLOCKED_DEFECT / STALE_INFORMATION_BLOCK;
N-AMBIGUOUS  = FAIL / BLOCK / BLOCKED_DEFECT / AMBIGUOUS_INFORMATION_BLOCK;
N-ILLEGAL    = FAIL / BLOCK / BLOCKED_DEFECT / ILLEGAL_CONTINUATION_BLOCK.
```

The four negative cases produced the correct `BLOCK / BLOCKED_DEFECT` family,
but their precedence reason strings did not equal the registered exact-match
labels in Run Manifest v1.0. There was no fallback guess, partial continuation,
silent recompute, stale success, Carrier semantic decision, network access, or
model participation.

## Boundaries

```text
production deployment = NOT AUTHORIZED / NOT PERFORMED;
canonical PALACE mutation = false;
canonical Information Space mutation = false;
D-002 rerun / repair = false;
automatic rerun / repair = forbidden;
Integrated SimiGo full production proof = NOT ESTABLISHED;
next authorized engineering object = requires a separate Human decision.
```
