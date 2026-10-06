# ES Continuation Sufficiency Probe — v0.2 Design

> **Status:** DESIGN V0.2 DELIVERED FOR FINAL HUMAN DESIGN REVIEW — EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-06
> **Human ruling reflected here:** Probe v0.1 ACCEPT IN PRINCIPLE; v0.2 REQUIRED; experiment remains NOT AUTHORIZED.
> **Version input:** `PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_DESIGN_V0.1_20261006.md` at `59d71f2`
> **Revision purpose:** representation / decidability clarification only
> **Frozen boundary:** no U-A code, U-A Manifest, UA v1.0, PB v1.2, InformationCore, RelationCore, or Frozen Contract change

## 1. Version relationship

v0.2 does not redesign the probe. It adds the missing representation and
decidability layer to v0.1.

Unchanged from v0.1:

```text
research question           Information Closure for Continuation
necessary verdict surface    C1 Reconstruction + C2 Continuation Determination
C3 Action Execution          observation only; never a PASS condition
positive control             complete lawful closure → CONTINUE_CERTAIN
negative principle           insufficient closure → BLOCK_INSUFFICIENT
interruption boundary        after durable E0 acknowledgement; I-2 does not
                             retest MA-4
carrier substrate            accepted U-A surface only, if later authorized
```

v0.2 supersedes v0.1 only where this document explicitly defines representation,
precondition, failure attribution, and negative-control registration.

## 2. Why v0.2 is required

v0.1 correctly avoided testing LLM/Agent autonomy, but it did not fully define
how `E0` closure slots must exist in the already accepted Information Space
surface.

Without that definition, a failure could be misread:

```text
missing continuation relation
  → C1/C2 FAIL
  → "Information Space is insufficient"
```

But three different explanations are possible:

```text
L-C  Carrier capability absence:
     the accepted surface lacks a lawful primitive needed to store, resolve,
     map, relate, version, or provenance the pre-registered representation.

L-R  Probe representation failure:
     the existing primitives are sufficient, but the probe encoded, parsed,
     formed, named, or addressed the closure incorrectly.

L-S  Continuation sufficiency failure:
     the existing primitives and the pre-registered representation are valid,
     but the instantiated closure is still ambiguous, incomplete,
     unprovenanced, or revision-conflicted.
```

Only `L-S` proves continuation insufficiency. `L-C` is a current-surface
capability finding. `L-R` is a probe defect.

## 3. Probe Representation Contract

The probe must first declare, for every `E0` slot, which existing primitive
represents it. These are probe-local slot labels, not new semantic classes.

| E0 slot | Lawful existing representation | Required primitives | Prohibited shortcut |
|---|---|---|---|
| objective | a formed `Information` with existing provenance; its carrier content may be stored as a `RAW` or `JUDGMENT` `CarrierRecord` and mapped by CC-5 | Information semantics; CC-3; CC-5 | no new `Objective` entity or store |
| input references | references to existing `InformationID`s; if represented as relations, existing Information-to-Information Relation semantics | Information identity; RelationCore endpoint rules | no URL guessing, ranking, or unresolved text reference |
| decisions / work records | `JUDGMENT` `CarrierRecord` content, mapped to formed `Information` by CC-5 when it must participate in relations | CC-3; CC-5; Information provenance | no new `Decision` semantic entity |
| artifact references | existing `Carrier` / Representation identity for bytes, plus formed `Information` identity when the artifact must be a relation endpoint | CC-1; CC-8 Representation Identity; CC-5 when mapped | no locator-only reference where provenance/revision must be judged |
| boundary state | a formed `Information` whose carrier record may use existing `RESULT`, `EXCLUSION`, `UNCERTAINTY`, or `JUDGMENT` vocabulary, mapped by CC-5 | CC-3; CC-5; Information semantics | no implicit “current process state” object |
| continuation pointer | existing `NEXT_ACTION` `CarrierRecord` vocabulary, mapped to formed `Information`; relation to the boundary uses existing Information-to-Information Relation semantics when needed | CC-3 `NEXT_ACTION`; CC-5; CC-6/CC-8 relation rules | no new `ContinuationPointer` engine or relation system |
| provenance | existing Information provenance for formed Information; distinct carrier provenance for carrier operations | existing provenance boundary; CC-1 | no merging Information and carrier provenance |
| revision | Representation Identity and current/historical visibility rules | CC-8; carrier representation rules | no locator/version guess |

If a slot need only be readable text, `CarrierRecord` representation may be
sufficient. If it must be a relation endpoint or participate in C2, it must be
a formed `Information` under existing formation semantics.

## 4. Continuation pointer representation

The lawful positive representation is restricted to existing primitives:

```text
P-1  NEXT_ACTION CarrierRecord
     The U-A/UA work-record vocabulary already contains NEXT_ACTION.

P-2  CC-5 mapping
     The NEXT_ACTION content that becomes continuation-relevant Information
     must have an explicit, provenance-bearing mapping.

P-3  relation form, only if needed
     When the pointer must relate a next-action Information to a boundary
     Information, use existing RelationCore semantics: both endpoints are
     InformationIDs and the predicate is a minimal opaque probe-fixture
     value.
```

The pointer is valid only if reconstruction can decide exactly one registered
continuation boundary without semantic interpretation by the carrier.

The probe must not:

```text
create a ContinuationPointer primitive;
create a Task / Objective / Boundary semantic entity;
extend CarrierRecord kinds;
add a relation engine;
let the carrier interpret NEXT_ACTION;
use a derived index as the pointer authority;
infer the pointer from embeddings or ranking.
```

### 4.1 Pointer precondition classification

Before any C1/C2 verdict, the design review/run precondition check must ask:

```text
Can NEXT_ACTION be stored as a CarrierRecord?
Can its continuation-relevant content be mapped by CC-5?
Can required Information endpoints be resolved?
Can existing RelationCore represent the required relation without extension?
Can provenance and revision be observed?
```

If any answer is NO, the required finding is:

```text
PRECONDITION FAILURE:
existing Information Space surface lacks lawful representation
for continuation relation
```

This is `L-C`: current Information Space capability insufficiency.

The probe must not build a new relation mechanism to make the experiment pass.
That result is valuable precisely because it distinguishes:

```text
durable / indexed / recoverable Information
  ≠
continuation-sufficient Information
```

## 5. Existing primitives that must not be invented

v0.2 explicitly prohibits semantic growth during the probe:

```text
no TaskStore / ObjectiveStore / ArtifactStore / BoundaryStore /
     ContinuationPointerStore
no Task, Objective, Artifact, BoundaryState, or ContinuationPointer
     semantic entity
no Agent semantic entity / AgentStore
no new CarrierRecord kind
no new RelationCore semantics
no carrier-side interpretation of work-record vocabulary
no implicit SessionEvent → Information promotion
no new Super Store
no schema-first capability growth
```

A probe-local predicate value or fixture label is data, not a new semantic
primitive. If the existing RelationCore requires predicate registration and
the probe predicate is not lawfully representable, the result is a
precondition failure, not permission to extend RelationCore.

## 6. Failure attribution

### 6.1 Current surface capability insufficiency — `L-C`

Classify as `L-C` when:

```text
the pre-registered representation uses only existing UA/U-A primitives,
but the accepted surface cannot lawfully store, form, map, resolve, relate,
version, or provenance it.
```

Example findings:

```text
NEXT_ACTION unavailable in the accepted implementation
CC-5 mapping unavailable for pointer content
existing RelationCore cannot represent the required endpoint relation
provenance or representation revision cannot be observed
```

Verdict:

```text
FAIL — EXISTING SURFACE CAPABILITY INSUFFICIENCY
```

This does not by itself prove that every possible Information Space design is
insufficient. It proves that the current accepted surface lacks a lawful
representation required by the pre-registered closure.

### 6.2 Probe representation failure — `L-R`

Classify as `L-R` when:

```text
the required existing primitive exists,
but the fixture encodes the wrong kind,
omits required CC-5 mapping,
uses an unresolved locator instead of an Information endpoint,
mislabels provenance,
ignores revision visibility,
uses a malformed pointer,
or the reconstruction parser has a defect.
```

Verdict:

```text
INDETERMINATE — PROBE REPRESENTATION OR HARNESS DEFECT
```

This must not be reported as Information Space insufficiency.

### 6.3 Continuation sufficiency failure — `L-S`

Classify as `L-S` only when:

```text
1.  the accepted carrier precondition is valid;
2.  the E0 encoding was pre-registered and uses only existing primitives;
3.  provenance and revision are observable;
4.  the interruption boundary was observed;
5.  reconstruction uses only lawful resolution; and
6.  C1 or C2 still fails because required closure is absent, ambiguous,
    unprovenanced, revision-conflicted, or boundary-deficient.
```

Verdict:

```text
FAIL — CONTINUATION INSUFFICIENCY
```

This is the intended research failure and must not be repaired by expanding
Information Space during the probe.

## 7. Pre-registered negative controls

Negative variants must be defined before any run. They must be separate
pre-registered fixture variants, not runtime edits to the positive case.

### N-A — reference ambiguity / unresolved reference

```text
registered deficiency:
  one required input reference is unresolved in the lawful Information
  Space surface

forbidden compensation:
  semantic search, guessing, best-effort ranking, or substituting a similar
  record

required decision:
  BLOCK_INSUFFICIENT

if violated:
  FAIL — unsafe continuation from insufficient closure
```

### N-B — continuation boundary deficiency

```text
registered deficiency:
  the continuation pointer resolves to two distinct registered boundary
  candidates, so exactly-one continuation cannot be decided

forbidden compensation:
  choosing either boundary by preference, confidence, recency, or ranking

required decision:
  BLOCK_INSUFFICIENT

if violated:
  FAIL — unsafe continuation from ambiguous boundary
```

Both N-A and N-B are mandatory. Their data transformations, affected IDs, and
expected typed outcomes must appear in the eventual run manifest before
execution authorization.

## 8. Adjusted verdict set

The research verdict remains PASS / FAIL / INDETERMINATE, with these required
qualifications:

```text
PASS — CONTINUATION SUFFICIENT
  positive C1 + C2 PASS;
  N-A emits BLOCK_INSUFFICIENT;
  N-B emits BLOCK_INSUFFICIENT;
  C3 is not required.

FAIL — CONTINUATION INSUFFICIENCY
  valid existing primitives and valid pre-registered representation,
  but positive C1 or C2 fails.

FAIL — EXISTING SURFACE CAPABILITY INSUFFICIENCY
  lawful pre-registered representation cannot exist on the accepted surface.

FAIL — UNSAFE CONTINUATION
  N-A or N-B produces CONTINUE_CERTAIN despite registered deficiency.

INDETERMINATE — PROBE REPRESENTATION OR HARNESS DEFECT
  L-R conditions occur.

INDETERMINATE — CARRIER PRECONDITION OR PROTOCOL DEFECT
  the accepted U-A precondition, interruption boundary, evidence capture,
  or protocol fails for reasons outside the closure being tested.
```

A single unqualified `FAIL` is not an acceptable final research verdict.

## 9. Evidence additions

In addition to v0.1 evidence requirements, each eventual run must record:

```text
EV-R1  Probe Representation Contract table used by the run
EV-R2  proof that every slot used only existing UA/U-A primitives
EV-R3  continuation-pointer representation form: record, mapping, relation
EV-R4  precondition result for NEXT_ACTION / CC-5 / relation / provenance /
       revision
EV-R5  failure-layer attribution: L-C, L-R, or L-S
EV-R6  N-A and N-B pre-registration manifests and fixture checksums
EV-R7  proof that negative variants were not derived by runtime mutation of
       the positive case
```

Without `EV-R5`, a C1/C2 failure is not interpretable.

## 10. C1 / C2 predicate additions

v0.1's C1/C2 logic remains. v0.2 adds two gates before it:

```text
G-R  Representation Gate
     every E0 slot has a lawful mapping under the Probe Representation
     Contract.

G-C  Capability Gate
     the accepted surface can store, form, map, resolve, relate, version,
     and provenance that representation without extension.
```

Then:

```text
positive:
  G-R PASS and G-C PASS are preconditions.
  C1 and C2 are then evaluated.

negative:
  the registered deficiency must be observed as typed insufficiency.
  G-R/G-C may still PASS because the deficiency is in the instantiated
  closure, not in the ability to represent the probe.
```

If `G-R` or `G-C` fails, do not evaluate C1/C2 as continuation failure.

## 11. What v0.2 still does not authorize

This document still does not authorize:

```text
experiment execution
implementation work
database creation
U-A code change
U-A Manifest change
UA v1.0 change
PB v1.2 change
InformationCore or RelationCore mutation
MemPalace integration
MCP integration
embedding or semantic ranking
remote API use
backend selection
performance testing
new formal Gate creation
```

The next action is Human final design review of v0.2. Only after ACCEPT may a
separate execution-authorization decision be considered.
