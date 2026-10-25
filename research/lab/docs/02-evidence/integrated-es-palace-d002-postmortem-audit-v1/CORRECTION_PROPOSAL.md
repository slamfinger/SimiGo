# D-002 Replay-Adapter Correction Proposal — NON-EXECUTABLE

> **Status:** AUDIT PROPOSAL ONLY — NO AUTHORIZATION

## 1. Proposed next object

Open a new Human-reviewable instrumentation/redesign package, not a rerun. The
proposal should require a dry adapter materialization harness that captures every
D-001 reconstruction exception before any Decision Core replay.

## 2. Minimum proposed gates

```text
G1 adapter exception capture = every try/except records type, message, family, and translated object digest;
G2 D001 schema preflight     = validate translated I1/I4/I5/I6/I8/I10 exact fields and schema IDs before decide();
G3 closure digest preflight   = prove translated closure digest using the D001 canonical algorithm without calling decide();
G4 resolved-input proof       = require a resolved ESContinuationInput before any Decision Core invocation;
G5 frozen baseline recheck    = source, snapshot, D001 core, fixtures, and expected vectors unchanged.
```

## 3. Possible adapter redesign requirements

```text
translate each D002 wrapper schema explicitly to its D001 wrapper schema;
preserve every mandatory field or emit MISSING before D001 execution;
separate representation translation from validation;
never encode unresolved state inside the subject adapter;
capture all adapter exceptions as typed evidence;
keep D001 Decision Core byte-identical.
```

## 4. Explicit non-authorizations

```text
no rerun;
no repair-run;
no implementation mutation;
no evidence overwrite;
no PALACE/canonical mutation;
no Decision Core execution;
no observer execution;
no equivalence claim.
```
