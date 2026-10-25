# SimiGo Integrated ES–PALACE targeted revision validation result

> **Status:** VALIDATION_PASS — ONE-RUN STOP RULE ENFORCED.
> This result is limited to the seven prepared cases and the pre-registered
> bounded configuration. It is not production authorization or an Integrated
> SimiGo full production proof.

## Run binding

```text
manifest instance id = 0D17FD1B-18FA-5D74-98BA-AE53029078EE;
manifest canonical content SHA256 =
  0de1909d780dabc6477f492945421c667b4990be523bce9a4ec52c4a2b640815;
manifest file SHA256 =
  097b0a57c48808b7b3828ae8dda17dd72c35d66fa79ab74da82c219c6ab39d7a;
runner SHA256 =
  50772199dc18c2f7dde7abaf0b95feb879c195f946ef334bc2952b4e73a84d52;
executed runs = 1 / authorized runs = 1;
terminal state = VALIDATION_PASS.
```

First-run evidence remained immutable:

```text
first Run Manifest SHA256 =
  b8a668ef482897b2cbe9b40e4aa6eb48868c613b76ef194338f89d7d22a59ef5;
first runner SHA256 =
  f27b1f055b6864445fb00d63fb9078744319964234a090648a28a4d1b5c1d8fb;
first validation record SHA256 =
  a6d3a4101f80eb072dbb98d691ada957460ff91bbc9a33ca6f031f9714fce55e;
first terminal state = VALIDATION_FAIL.
```

## Results

```text
P-LAWFUL     = PASS / CONTINUE / SETTLED_CONTINUATION /
               LAWFUL_CURRENT_CONTINUATION;
P-SETTLED    = PASS / REUSE / SETTLED_CONTINUATION /
               REUSE_PREDICATE_COMPLETE;
P-BLOCKED    = PASS / BLOCK / BLOCKED_LAWFUL_CONTINUATION /
               REGISTERED_BLOCKING_CONDITION;
N-MISSING    = PASS / BLOCK / BLOCKED_DEFECT /
               MANDATORY_OBJECT_UNRESOLVABLE;
N-STALE      = PASS / BLOCK / BLOCKED_DEFECT /
               MANDATORY_EVIDENCE_SUPERSEDED;
N-AMBIGUOUS  = PASS / BLOCK / BLOCKED_DEFECT /
               CONFLICTING_VALID_POINTERS;
N-ILLEGAL    = PASS / BLOCK / BLOCKED_DEFECT /
               REGISTERED_BOUNDARY_VIOLATION_PROVEN.
```

The negative reasons were derived from actual state conditions:

```text
missing mandatory inventory object;
superseded mandatory evidence;
conflicting valid pointers;
proven unauthorized boundary.
```

## Boundaries

```text
run 3 or automatic repair = FORBIDDEN;
production deployment = NOT AUTHORIZED / NOT PERFORMED;
canonical PALACE mutation = false;
canonical Information Space mutation = false;
D-002 rerun / repair = false;
Integrated SimiGo full production proof = NOT ESTABLISHED;
next authorized engineering object = requires a separate Human decision.
```
