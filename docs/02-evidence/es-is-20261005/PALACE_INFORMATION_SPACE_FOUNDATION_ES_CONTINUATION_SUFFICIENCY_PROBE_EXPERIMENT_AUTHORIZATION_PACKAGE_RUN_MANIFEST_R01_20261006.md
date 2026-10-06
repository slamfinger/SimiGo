# ES Continuation Sufficiency Probe — Experiment Authorization Package / Run Manifest R01

> **Status:** PACKAGE / RUN MANIFEST R01 REV1 SUBMITTED FOR SECOND HUMAN REVIEW — S1 NOT APPROVED; EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-06
> **Frozen design baseline:** `39c1031`
> **Accepted design:** Probe v0.2 + Probe Representation Contract
> **Candidate run label:** `ES-CSP-RUN-01`
> **Execution authorization:** NOT REQUESTED BY SUBMISSION ALONE
> **Implementation status:** none; no fixture directory, database, fixture artifact, or run result is created by this document

> **First review ruling:** REVISE BEFORE S1; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_R01_REVIEW_RULING_20261006.md`.
> **Reviewed R01 basis:** `f42762f`
> **Revision scope:** execution packaging / experimental control only; no Probe v0.2 redesign.

## 1. Purpose and authorization boundary

This is R01 Rev1. It resolves the Human's first-review findings while
preserving the accepted Probe v0.2 boundary.

```text
R1  N-B remains two independent NEXT_ACTION records: P1a → B1 and
    P1b → B2. target_slot remains scalar; no multi-target pointer
    structure is introduced.
R2  Fresh reconstruction is blinded to fixture role. It receives an
    opaque fixture instance ID, not P-POS / N-A / N-B.
R3  Fresh reconstruction receives a pre-registered opaque stable
    session locator as the deterministic entry point. It does not scan
    for the session or discover it semantically.
```

This package converts the frozen Probe v0.2 design into a reviewable run
manifest. It does not authorize implementation or execution.

```text
Package review       = lawful next action
Fixture preparation  = separate later action; still not experiment authorization
Experiment execution = requires explicit Human authorization after the
                       completed fixture manifest is reviewed
```

No result, pass/fail claim, opaque runtime identity, locator, revision, or
checksum is asserted here. Values that can exist only after authorized fixture
materialization are marked `MINTED/RECORDED AT FIXTURE PREPARATION`.

## 2. Immutable review inputs

```text
Probe v0.1        docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_DESIGN_V0.1_20261006.md
Probe v0.2        docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_DESIGN_V0.2_20261006.md
v0.2 ruling       docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_V0_2_ACCEPTANCE_RULING_20261006.md
code baseline     39c1031
target package    trackD-memory accepted U-A surface only
```

Any change under `trackD-memory/` after `39c1031` invalidates this package
revision. Documentation-only commits after that baseline do not change the
accepted carrier surface.

## 3. Candidate authorization stages

```text
S0  Human reviews this package.
S1  If approved, prepare fixtures and the completed fixture manifest.
S2  Human reviews the completed fixture manifest and checksums.
S3  Only explicit Human run authorization starts ES-CSP-RUN-01.
S4  Human reviews evidence and failure-layer attribution.
```

Approval to enter `S1` does not authorize `S3`. A run command remains illegal
until the Human explicitly authorizes execution.

## 4. Run identity and hard stop rules

```text
run label              ES-CSP-RUN-01
design version         Probe v0.2 / FROZEN
source baseline        39c1031
carrier surface        SQLiteCarrierBundle / SQLiteUnifiedCarrierOperations
carrier data root      one isolated directory outside the repository;
                       exact path recorded at fixture preparation
maximum task lineages  ONE
maximum positive path  ONE
mandatory negatives    N-A and N-B
maximum C3 status      OBSERVATION ONLY
success surface        C1 + C2 only
```

Immediate stop conditions:

```text
carrier source baseline `trackD-memory/` differs from 39c1031;
frozen Probe v0.2 text changes;
a `target_slot` value becomes an array, set, ranked list, or other
multi-target pointer structure;
the reconstruction process receives fixture role, deficiency description, or
expected C1/C2;
the reconstruction process discovers the session by scanning, semantic search,
ranking, embedding, or fixture-generator content;
a new semantic entity, CarrierRecord kind, RelationCore rule, relation engine,
Super Store, embedding path, MCP path, remote API, or backend is introduced;
a negative fixture is derived by mutating a materialized positive fixture at
runtime;
C3 is used to decide PASS;
evidence cannot support L-C / L-R / L-S attribution.
```

## 5. Frozen Representation Contract instantiation

This run uses only existing U-A carrier primitives.

| E0 slot | CarrierRecord kind | Existing handling |
|---|---|---|
| objective | `RAW` | session event + CC-5 mapping |
| input reference | `EVIDENCE_LINK` | session event + CC-5 mapping |
| decisions / work records | `JUDGMENT` | session event + CC-5 mapping |
| artifact reference | `RESULT` | session event + CC-5 mapping |
| boundary state | `RESULT` | session event + CC-5 mapping |
| continuation pointer | `NEXT_ACTION` | session event + CC-5 mapping |
| provenance | operation/session provenance fields | existing U-A ledger/mapping fields |
| revision | carrier revision / mapping version fields | existing U-A revision fields |

No `CarrierRelation` is used by this candidate. Therefore the run must not
present carrier-level `relations` as RelationCore relations.

No new entity is created for Task, Objective, Artifact, BoundaryState, or
ContinuationPointer. These words are probe-local slot labels only.

## 6. Continuation pointer representation

The positive continuation pointer is one `NEXT_ACTION` session event whose
canonical payload names exactly one boundary slot.

Lawful path:

```text
NEXT_ACTION CarrierRecord
  → CC-5 mapping recorded by recordMapping
  → carrier-scoped Information identity
  → exact boundary slot named in the payload
```

No `ContinuationPointer` entity, relation engine, semantic index, ranking,
embedding, MCP call, or remote API is used.

If the accepted surface cannot store `NEXT_ACTION`, record its CC-5 mapping,
return stable event/mapping identities, or preserve provenance/revision, the
result is:

```text
G-C FAIL → L-C EXISTING SURFACE CAPABILITY INSUFFICIENCY
```

The run must stop at the Capability Gate. It must not add a bridge or relation
mechanism to make C1/C2 runnable.

## 7. G-R Representation Gate

`G-R` is a document/manifest comparison performed before reconstruction.

PASS requires every materialized slot to match §5 exactly:

```text
G-R-1  only allowed CarrierRecord kinds are present;
G-R-2  every slot has a CC-5 mapping attempt;
G-R-3  no Task/Objective/Artifact/Boundary/ContinuationPointer entity exists;
G-R-4  no new CarrierRecord kind is introduced;
G-R-5  no CarrierRelation or RelationCore extension is introduced;
G-R-6  continuation payload names exactly one boundary in the positive case;
G-R-7  provenance and revision fields are carried by existing U-A structures.
G-R-8  N-B contains exactly two scalar-pointer NEXT_ACTION records,
       P1a → B1 and P1b → B2; no multi-target pointer structure exists.
```

Any mismatch is:

```text
G-R FAIL → INDETERMINATE — PROBE REPRESENTATION OR HARNESS DEFECT
```

## 8. G-C Capability Gate

`G-C` is a mechanical precondition audit before C1/C2.

At fixture preparation, record the results of:

```text
G-C-1  carrier-source baseline audit:
       39c1031 is an ancestor of the checked-out commit;
       `git diff --exit-code 39c1031 HEAD -- trackD-memory` is clean; and
       the working `trackD-memory/` tree is clean;
G-C-2  SQLiteCarrierFactory creates the accepted composition;
G-C-3  appendSessionEvent accepts the existing U-0 kinds used in §5,
       including NEXT_ACTION;
G-C-4  recordMapping records information / carrier / record / representation
       provenance;
G-C-5  mappings and operationLedger return durable records;
G-C-6  events can be enumerated by stable session addressing without search;
G-C-7  carrier and operation provenance are observable;
G-C-8  revision/current-versus-historical information is observable;
G-C-9  integrityReport completes without unexplained authority issues.
```

The source audit must use the exact source tree, not a rebuilt or edited copy.
The runtime checks may run only after `S1` fixture-preparation approval.

Failures are classified:

```text
G-C source/baseline failure     INVALID — PACKAGE/HARNESS DEFECT
G-C missing lawful primitive    FAIL — L-C EXISTING SURFACE CAPABILITY
                                         INSUFFICIENCY
G-C test/driver defect          INDETERMINATE — HARNESS DEFECT
```

If `G-R` or `G-C` fails, C1/C2 must not be evaluated as continuation failure.

## 9. Positive fixture `P-POS`

`P-POS` is one task lineage in one SESSION carrier.

Pre-registered logical slots:

```text
O1   objective             RAW
I1   input reference       EVIDENCE_LINK
D1   decision/work record  JUDGMENT
A1   artifact reference    RESULT
B1   boundary state        RESULT
P1   continuation pointer  NEXT_ACTION → B1
```

Canonical payload schema:

```json
{
  "schema": "es-csp/e0-slot-v1",
  "slot": "<O1|I1|D1|A1|B1|B2|P1|P1a|P1b>",
  "content": "<exact UTF-8 fixture text>",
  "target_slot": "<single scalar boundary slot; required only for P1 / P1a / P1b>"
}
```

`target_slot` is always a scalar. Arrays, sets, ranked alternatives, and any
other multi-target pointer structure are forbidden.

Rules:

```text
one exact content string is fixed per slot at fixture preparation;
P1.target_slot = "B1";
no alternative boundary slot exists in P-POS;
every event receives a CC-5 mapping;
actual opaque runtime identities, revisions, locators, and checksums are
MINTED/RECORDED AT FIXTURE PREPARATION.
```

Expected answers are fixed before reconstruction:

```text
C1 expected  all six slots reconstructed with provenance and valid revision
C2 expected  exactly B1; decision = CONTINUE_CERTAIN
C3 status   OBSERVATION ONLY; excluded from PASS
```

## 10. Negative fixture `N-A`

`N-A` is an independently defined fixture: reference deficiency.

```text
slots         O1, I1, D1, A1, B1, P1
deficiency    the I1 reference does not resolve in the lawful surface
definition    fixed at fixture preparation in the N-A manifest
forbidden     semantic search, similarity substitution, guessing, ranking
expected      typed unresolved-reference finding
decision      BLOCK_INSUFFICIENT
if violated   FAIL — UNSAFE CONTINUATION
```

`N-A` must have its own fixture manifest and checksums. It must not be produced
by deleting or editing a materialized `P-POS` at runtime.

## 11. Negative fixture `N-B`

`N-B` is an independently defined fixture: continuation boundary ambiguity.

```text
slots         O1, I1, D1, A1, B1, B2, P1a, P1b
deficiency    the lawful pointer set contains two independent NEXT_ACTION
              records: P1a → B1 and P1b → B2
cardinality   exactly 2
forbidden     confidence, recency, ranking, similarity, or model preference
expected      typed ambiguous-continuation finding
decision      BLOCK_INSUFFICIENT
if violated   FAIL — UNSAFE CONTINUATION
```

Ambiguity is represented only by the observed cardinality of two independent
`NEXT_ACTION` records. It is not represented by a multi-valued `target_slot`,
new pointer object, new relation type, or carrier-side interpretation. C2
fails continuation certainty because the lawful pointer set does not identify
exactly one boundary.

`N-B` must have its own fixture manifest and checksums. It must not be produced
by adding a record to a materialized `P-POS` at runtime.

## 12. Fixture manifest to be completed at S1

If the Human approves fixture preparation, create one manifest per fixture:

```text
P-POS fixture manifest
N-A fixture manifest
N-B fixture manifest
```

Each manifest must record:

```text
schema version                 es-csp/fixture-manifest-v1
package baseline               39c1031
design baseline                Probe v0.2 / FROZEN
run label                      ES-CSP-RUN-01
fixture instance ID            ASSIGNED AT FIXTURE PREPARATION
fixture role                   P-POS | N-A | N-B
role mapping location          CONTROL-SIDE ONLY / WITHHELD FROM RECONSTRUCTION
reconstruction entry point     OPAQUE STABLE SESSION LOCATOR / RECORDED AT
                               FIXTURE PREPARATION
canonicalization               UTF-8; exact payload bytes; SHA-256 checksums
carrier label                  pre-registered logical label only
actual carrier identity        MINTED/RECORDED AT FIXTURE PREPARATION
actual session identity        MINTED/RECORDED AT FIXTURE PREPARATION
event identities               MINTED/RECORDED AT FIXTURE PREPARATION
Information identities         MINTED/RECORDED AT FIXTURE PREPARATION
mapping identities             MINTED/RECORDED AT FIXTURE PREPARATION
revision identifiers           MINTED/RECORDED AT FIXTURE PREPARATION
locators                       MINTED/RECORDED AT FIXTURE PREPARATION
payload checksums              RECORDED AT FIXTURE PREPARATION
G-R result                     PASS/FAIL with exact mismatches
G-C result                     PASS/FAIL with exact primitive/precondition
independence declaration       proves this fixture was not derived from
                               another materialized fixture
```

The fixture instance ID and stable session locator must be opaque and
role-nonrevealing. They must not encode `P-POS`, `N-A`, `N-B`, positive/
negative status, fixture order, or deficiency type. Assign them only after the
control-side role/expectation mapping has been sealed.

Fixture preparation is complete only when all three manifests exist and all
`MINTED/RECORDED AT FIXTURE PREPARATION` fields are filled.

The control side, not the reconstruction process, owns the mapping:

```text
fixture instance ID → fixture role
fixture instance ID → expected C1/C2 result
fixture instance ID → deficiency description
```

These mappings must be sealed in the control-side evidence ledger before
reconstruction and must not be passed to the fresh process.

## 13. Reconstruction process

A fresh reconstruction process may receive only:

```text
source baseline identifier       39c1031
run label                        ES-CSP-RUN-01
opaque fixture instance ID       ASSIGNED AT FIXTURE PREPARATION
isolated carrier data root path
opaque stable session locator    REGISTERED NON-SEMANTIC ENTRY POINT
Reconstruction Manifest schema version
```

It must not receive:

```text
fixture role                    P-POS / N-A / N-B
deficiency description
expected C1 result
expected C2 result
control-side instance mapping
fixture generator content
prior process memory
conversation history
agent notes
semantic search results
embedding data
MCP context
remote API context
private model state
content copied from the fixture generator
```

Procedure:

```text
R1  Open only the registered isolated carrier root.
R2  Resolve the pre-registered opaque stable session locator to exactly one
    registered session. Do not scan carriers, sessions, tables, or indexes to
    discover it.
R3  Read existing mappings and provenance; do not use derived search as
    authority.
R4  Build the Reconstruction Manifest from resolved slots.
R5  Evaluate C1.
R6  Evaluate C2 from NEXT_ACTION records only.
R7  Emit one typed result:
      CONTINUE_CERTAIN
      BLOCK_INSUFFICIENT
R8  Emit C3 as OBSERVATION ONLY if action execution is externally observed.
```

The reconstruction process emits only its observed result. The control side
later joins the opaque fixture instance ID to its sealed role and expected
result, then classifies the run. For N-A and N-B, the pre-registered expected
C2 result is `BLOCK_INSUFFICIENT`; this expectation is not revealed to the
reconstruction process.

If the entry locator does not resolve to exactly one registered session, the
run is:

```text
INVALID — RECONSTRUCTION ENTRY POINT DEFECT
```

The process must not fall back to semantic search, full enumeration to discover
the session, ranking, or fixture-generator content.

## 14. I-1 / I-2 interruption boundaries

```text
I-1  clean pause / process stop
     after P-POS writes and mappings are acknowledged

I-2  adverse process loss
     after durable acknowledgement of the completed E0 closure
```

I-2 does not use crash gates and does not interrupt a write transaction. It
does not retest MA-4, entity durability, registry atomicity, orphan recovery,
or any CCVS-01 correctness result.

If any I-1/I-2 procedure changes carrier state before reconstruction, the run
is `INVALID — INTERRUPTION BOUNDARY VIOLATION`.

## 15. Evidence ledger

The eventual run must retain v0.1 evidence plus v0.2 additions:

```text
EV-1    pre-registered E0 closure definition
EV-2    expected C1/C2 and expected negative results
EV-3    interruption type and durable acknowledgement boundary
EV-4    resolved identities, revisions, locators, provenance
EV-5    unresolved/ambiguous references with typed reasons
EV-6    Reconstruction Manifest
EV-7    C1 status
EV-8    C2 status and continuation decision
EV-9    carrier precondition/integrity result
EV-10   raw audit logs
EV-R1   instantiated Representation Contract table
EV-R2   proof that only existing UA/U-A primitives were used
EV-R3   NEXT_ACTION → CC-5 → Information pointer path
EV-R4   G-R/G-C results
EV-R5   L-C / L-R / L-S attribution with exact evidence
EV-R6   N-A/N-B manifests and checksums
EV-R7   fixture independence proof
```

`EV-R5` must cite one of:

```text
L-C  lawful representation exists in the contract but accepted surface lacks
     the primitive/precondition
L-R  surface primitive exists but fixture, encoding, parser, or harness is
     defective
L-S  surface and representation are valid, but closure still fails
```

If `EV-R5` is absent or ambiguous, the research verdict is
`INDETERMINATE — ATTRIBUTION EVIDENCE INSUFFICIENT`.

## 16. Decision requested

This submission requests only:

```text
Human review of this package and candidate run manifest.
```

Possible next rulings:

```text
APPROVE S1  prepare the three independent fixture manifests and checksums;
            this still does not authorize a run
REVISE      return this package with registered defects
REJECT      do not prepare fixtures or run
```

No command, fixture artifact, database, or evidence in this package authorizes
`S3` execution.

## 17. Current non-authorization record

```text
Experiment                 NOT AUTHORIZED
Execution Authorization    NOT REQUESTED
Fixture preparation        NOT STARTED
Database creation          NOT STARTED
Probe run                  NOT STARTED
```
