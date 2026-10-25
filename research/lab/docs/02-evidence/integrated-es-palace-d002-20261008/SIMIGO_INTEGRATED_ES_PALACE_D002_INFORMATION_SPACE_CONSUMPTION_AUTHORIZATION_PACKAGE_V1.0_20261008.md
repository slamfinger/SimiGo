# SimiGo Integrated ES–PALACE D-002 Information-Space Consumption Authorization Package v1.0

> **Status:** DELIVERED FOR HUMAN REVIEW — PACKAGE ONLY
> **Date:** 2026-10-08
> **Package ID:** `INTEGRATED-ES-PALACE-D002-IS-CONSUMPTION-AUTH-PACKAGE-V1.0`
> **Predecessor:** D-001 CLOSED / BOUNDED PASS
> **Canonical base:** `2ca30042440e8ef387d032fa206c7ee84a7bf896`
> **Implementation:** NOT AUTHORIZED
> **Fixture creation or mutation:** NOT AUTHORIZED
> **Experiment execution:** NOT AUTHORIZED
> **Canonical IS mutation:** NOT AUTHORIZED
> **Cloud LLM / model in causal chain:** NOT AUTHORIZED
> **E9 / EXP-004:** NOT AUTHORIZED

## 1. Research question

D-002 asks exactly one question:

```text
Can a real PALACE Information Space primitive be converted, under closed and
auditable conditions without hidden semantic input, into the D-001 typed ES
reconstruction input and then produce the same frozen decision vector?
```

The target hop is:

```text
real PALACE / Information Space primitive
  → typed ES reconstruction input
```

D-001 remains closed downstream of this hop:

```text
typed ES reconstruction input
  → Execution State decision
  → Carrier persistence
  → independent observation.
```

## 2. Preserved D-001 result and non-composition

```text
D-001 semantic decision harness    = CLOSED / BOUNDED PASS;
Attempt-001                        = FAIL / RETAINED / comparator defect;
Attempt-002                        = PASS;
PALACE equivalence                 = NOT ESTABLISHED;
Integrated SimiGo proof            = NOT ESTABLISHED;
general Execution State theorem    = NOT ESTABLISHED;
production SimiGo validity         = NOT ESTABLISHED;
LLM autonomy                       = NOT ESTABLISHED;
E8 + R01 + D-001 composition proof = NOT ESTABLISHED.
```

D-002 must not treat D-001 as authority to broaden scope. It must produce a new
evidence chain for the real Information-Space consumption hop.

## 3. Real source-carrier observation

This Package binds the following read-only observation of the real local PALACE
carrier:

```text
path                     = palace-v0/palace/chroma.sqlite3;
size bytes               = 1486848;
SHA-256                  =
  3f790600bfa0ebb0eb7bd4e9f28ac1b6353bd6802d5eeb8f964e7edb8861bf0a;
collection id            = 8cb3160e-e082-4b23-b78c-1dc8711910ec;
collection name          = mempalace_drawers;
distinct embedding ids   = 120;
embedding metadata rows  = 1230;
typed diary_entry ids    = 38.
```

These counts are observational bindings only. They do not authorize reading,
exporting, publishing, or consuming drawer text outside the future authorized
and isolated D-002 stage.

## 4. Source-integrity and privacy boundary

If separately accepted, D-002 implementation must first create a byte-stable
read-only source snapshot. The original PALACE carrier must remain untouched.

```text
original source             = read-only / no write connection;
snapshot                    = copied once into the D-002 evidence parent;
snapshot SHA-256            = must equal 3f790600…;
post-snapshot source digest = must remain unchanged;
snapshot integrity          = verified before any mapping;
privacy                     = no content publication outside evidence closure;
network                     = forbidden;
cloud/model inference       = forbidden.
```

Any source drift, WAL change, missing table, digest mismatch, symlink, or
write-open attempt is `INVALID`.

## 5. Permitted source surface

The future adapter may consume only deterministic structural metadata from the
snapshot:

```text
collections;
collection_metadata;
segments;
segment_metadata;
embedding_metadata;
embedding_metadata_array.
```

The adapter must not consume or traverse:

```text
embeddings;
embedding vectors;
embedding_fulltext_search*;
embeddings_queue*;
semantic search;
similarity ranking;
model-generated ranking;
filesystem exploration outside the snapshot;
process environment;
unregistered global state;
model context.
```

Any denied-channel influence on `RecoveredInformationContext`,
`ESContinuationInput`, identity, decision, or claim is forbidden.

## 6. Required D-002 primitive inventory

The implementation manifest must bind real-source equivalents of the D-001
primitive families:

| ID | Real-source binding |
| --- | --- |
| R-I1 | lawful PALACE record identity / drawer or record UUID |
| R-I2 | closure membership references and stable metadata digests |
| R-I3 | CarrierRecord / CC-5-compatible mapping record |
| R-I4 | provenance, revision, filed-at / last-modified integrity record |
| R-I5 | registered NEXT_ACTION pointer derived only from allowed metadata |
| R-I6 | approved opaque locator, with no expected verdict or role hint |
| R-I7 | read-only carrier snapshot and expected digest binding |
| R-I8 | approved `ES-CONTINUATION-INPUT-D001-V1` schema |
| R-I9 | approved `ES-CONTINUATION-OUTPUT-D001-V1` schema |
| R-I10 | approved D-002 evidence destination set |

An object not resolvable through this inventory is missing. Semantic similarity
or nearby-content inference may not recover it.

## 7. Required typed mapping contract

The mapping must expose the D-001 views without semantic widening:

```text
real PALACE primitive metadata
  → RecoveredInformationContext
  → ContinuationAuthorityView
  → ESContinuationInput
  → NEXT_ACTION / REUSE / BLOCK
```

Required authority separations remain:

```text
context-only ≠ continuation-authoritative;
provenance ≠ decision authority;
 CarrierRecord ≠ semantic interpretation;
 model suggestion ≠ continuation authority;
 embedding/vector ≠ lawful content.
```

If no registered rule maps a real metadata field into the authority view, the
result is `MISSING_INFORMATION_BLOCK`, not a guess.

## 8. Decision-core reuse boundary

The D-002 future implementation may reuse D-001 `schemas.py`, `inventory.py`,
`reconstruction.py`, `continuation.py`, and `carrier.py` only as frozen
read-only dependencies. It must not modify:

```text
Decision Core semantics;
P1–P7;
frozen seven-case expected vectors;
D-001 fixtures or evidence;
D-001 runner or observer semantics;
Run Manifest Contract v1.0.
```

The D-002 adapter may add only new source-consumption and mapping code. Decision
semantics must remain byte-for-byte inherited or be proven identical by digest
and replay.

## 9. Proposed implementation scope if separately accepted

The only proposed implementation root is:

```text
integrated-es-palace/d002/implementation/
```

The proposed allowed artifacts are:

```text
IMPLEMENTATION_MANIFEST.json
README.md
source_snapshot.py
primitive_inventory.py
typed_mapping.py
decision_replay.py
observer.py
selfcheck.py
```

No file outside this root and its separately bound evidence parent may be
created or modified.

## 10. Required fixture / real-source matrix

The future D-002 manifest must pre-register exactly seven real-source or
snapshot-derived cases, mapped to the frozen D-001 vector:

```text
P-LAWFUL     = CONTINUE / SETTLED_CONTINUATION / LAWFUL_CURRENT_CONTINUATION;
P-SETTLED    = REUSE   / SETTLED_CONTINUATION / REUSE_PREDICATE_COMPLETE;
P-BLOCKED    = BLOCK   / BLOCKED_LAWFUL_CONTINUATION / REGISTERED_BLOCKING_CONDITION;
N-MISSING    = BLOCK   / BLOCKED_DEFECT / MANDATORY_OBJECT_UNRESOLVABLE;
N-STALE      = BLOCK   / BLOCKED_DEFECT / MANDATORY_EVIDENCE_SUPERSEDED;
N-AMBIGUOUS  = BLOCK   / BLOCKED_DEFECT / CONFLICTING_VALID_POINTERS;
N-ILLEGAL    = BLOCK   / BLOCKED_DEFECT / REGISTERED_BOUNDARY_VIOLATION_PROVEN.
```

For each case, the manifest must bind:

```text
real source record id or explicit absence trigger;
allowed metadata fields and digests;
typed mapping result;
D-001 schema input digest;
frozen three-component expected vector;
decision-core digest;
observer binding;
closure artifact;
no fallback guess.
```

If seven lawful real-source cases cannot be found, D-002 must fail closed and
report the deficiency. It may not synthesize PALACE records into the canonical
carrier to make the experiment pass.

## 11. Required classification ladder

A failed D-002 run must attribute failure to exactly one first-fault class:

```text
PALACE_REPRESENTATION_DEFECT;
TYPED_MAPPING_DEFECT;
EXECUTION_STATE_DEFECT;
CARRIER_DEFECT;
OBSERVER_DEFECT;
EVIDENCE_INFRASTRUCTURE_DEFECT;
SOURCE_DRIFT_OR_INVALID.
```

Secondary defects may be recorded but must not change first-fault precedence.

## 12. Evidence and write-once closure

The proposed evidence parent is:

```text
docs/02-evidence/integrated-es-palace-d002-consumption-v1/
```

The proposed evidence objects are:

```text
RUN_MANIFEST_INSTANCE.json
SOURCE_SNAPSHOT_BINDING.json
PRIMITIVE_INVENTORY.json
TYPED_MAPPING_RECORD.json
DECISION_REPLAY_RECORD.json
OBSERVER_RECORD.json
RECONCILIATION_RECORD.json
CLAIM_RECORD.json
EVIDENCE_SHA256SUMS
```

All objects are write-once. `EVIDENCE_SHA256SUMS` is final and must cover the
other eight objects exactly once.

## 13. Validation boundary

If later accepted and executed, the only lawful terminal states are:

```text
D002_CONSUMPTION_PASS;
D002_CONSUMPTION_FAIL;
D002_CONSUMPTION_INVALID.
```

`PASS` means only:

```text
For the pre-registered real-source D-002 configuration, allowed PALACE metadata
was converted into typed D-001 ES reconstruction inputs, reused the unchanged
Decision Core, produced the frozen three-component decision vector, and was
independently reconciled without forbidden-channel influence or canonical IS
mutation.
```

It does not mean PALACE equivalence or integrated SimiGo proof.

## 14. Explicit prohibitions

This Package does not authorize:

```text
implementation artifact creation;
fixture creation or mutation;
snapshot creation;
real-source consumption;
experiment execution;
canonical IS mutation;
PALACE record creation, deletion, rewrite, or import;
cloud LLM execution;
model participation in the causal chain;
semantic search, embeddings, ranking, or similarity traversal;
PIR reopening;
E9;
EXP-004;
CarrierSQLite semantic change;
D-001 evidence mutation;
D-001 rerun;
PALACE equivalence claim;
integrated SimiGo proof;
general Execution State theorem;
production SimiGo validity;
LLM autonomy;
automatic Run Manifest approval;
automatic experiment transition.
```

## 15. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   permit only a separately recorded D-002 implementation / snapshot /
         fixture preparation stage;
REVISE   require a new reviewed package revision;
REJECT   close this D-002 pathway.
```

ACCEPT does not authorize execution, create a Run Manifest instance, or broaden
the bounded claim.
