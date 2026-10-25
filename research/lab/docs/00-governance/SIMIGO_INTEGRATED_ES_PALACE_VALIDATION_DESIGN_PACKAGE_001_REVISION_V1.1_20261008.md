# SimiGo Integrated ES–PALACE Validation Design Package 001 — Targeted Revision v1.1

> **Status:** REVISED FOR HUMAN REVIEW
> **Date:** 2026-10-08
> **Package ID:** `INTEGRATED-ES-PALACE-VALIDATION-DESIGN-PACKAGE-001`
> **Revision ID:** `INTEGRATED-ES-PALACE-VALIDATION-DESIGN-PACKAGE-001-V1.1`
> **Governing Request:** SimiGo Integrated ES–PALACE Validation Design Request v1.0
> **Revision base:** `a2c910150cfde6ba178008bba35e81c5d7deece5`
> **Parent package:** `SIMIGO_INTEGRATED_ES_PALACE_VALIDATION_DESIGN_PACKAGE_001_20261008.md`

## 0. Revision ruling

Package 001 was reviewed as `REVISE PACKAGE`. Its responsibility boundary and
minimal loop were accepted as direction, but they were insufficient to
adjudicate an integrated semantic closure.

This targeted revision remains inside the same governing Request. It does not
open a new Design Request and does not expand research scope. It converts the
direction into seven adjudicable contracts:

```text
P1  Primitive Inventory
P2  PALACE → ES Typed Mapping
P3  Continuation Identity Contract
P4  Side-Channel Denial Matrix
P5  Negative Decision Precedence
P6  Carrier Lifecycle Contract
P7  Integrated-vs-Predecessor Boundary
```

This revision is the active Human-review object. The parent Package 001 is not
rewritten; it is preserved as immutable governance history.

## 1. Preserved boundaries

```text
Execution State
  = continuation semantics / obligations / orchestration

PALACE Information Space
  = information representation / provenance / context

Carrier
  = persistence / integrity

Model
  = inference / semantic interpretation only
```

The minimal loop remains:

```text
ES reconstruction
  → PALACE / Information Space context recovery
  → NEXT_ACTION / continuation determination
  → ES continuation
  → bounded carrier persistence
  → next lawful continuation
```

No implementation, fixture creation, experiment execution, IS mutation, E9,
EXP-004, PALACE equivalence ruling, or integrated SimiGo proof is authorized.

## P1 — Primitive Inventory

The later Run Manifest must bind the following primitive families before any
experiment entry:

```text
I1  lawful Information Closure identity;
I2  closure membership references;
I3  CarrierRecord / CC-5 mapping records;
I4  provenance and revision records;
I5  NEXT_ACTION continuation records;
I6  approved opaque reconstruction locator;
I7  approved carrier snapshot/read binding;
I8  approved continuation-input schema;
I9  approved continuation-output schema;
I10 approved evidence destination set.
```

Reconstruction may consume only objects reachable through this inventory and
an approved opaque locator. It must not discover its task through fixture
roles, semantic search, embedding/ranking, filesystem exploration, process
environment, unregistered global state, or model context.

Every mandatory object must be addressable, digest-bound, provenance-bound,
and revision-bound. An object that cannot be resolved through the inventory is
missing for adjudication purposes, even if a similarly named object exists
elsewhere.

## P2 — PALACE → ES Typed Mapping

The integrated object must expose three distinct typed views:

```text
RecoveredInformationContext
  = all lawfully recovered IS objects and provenance;

ContinuationAuthorityView
  = the continuation-authoritative subset;

ESContinuationInput
  = the exact typed input consumed by Execution State.
```

The required mapping is:

```text
Lawful Information Closure
  → RecoveredInformationContext
  → ContinuationAuthorityView
  → ESContinuationInput
  → NEXT_ACTION / REUSE / BLOCK
```

Mapping rules:

```text
1. CarrierRecord content enters only through CC-5 and must retain its
   Information identity, mapping identity, revision and provenance.

2. NEXT_ACTION is the only registered continuation-pointer authority.

3. Provenance verifies whether an object is lawful and current; it does not
   choose the next action.

4. Context-only information remains context-only unless an explicit registered
   rule promotes it into the ContinuationAuthorityView.

5. Model output, suggestion, ranking or hidden context is never
   continuation-authoritative.

6. ESContinuationInput must be reconstructable as a digest-bound typed record.
```

The following separations are mandatory:

```text
context-only ≠ continuation-authoritative;
provenance ≠ decision authority;
model suggestion ≠ continuation authority;
carrier record ≠ semantic interpretation.
```

## P3 — Continuation Identity Contract

A continuation identity must be derived from a canonical, digest-bound tuple
containing at least:

```text
Information Closure identity;
closure revision;
recovered-context digest;
registered NEXT_ACTION identity;
registered continuation target/boundary digest;
continuation class;
governing authorization boundary;
ES continuation-output digest.
```

The required continuation classes are:

```text
SETTLED_CONTINUATION;
BLOCKED_LAWFUL_CONTINUATION;
BLOCKED_DEFECT;
NON_CONTINUABLE.
```

### P3.1 REUSE predicate

An existing settled continuation may be reused only when:

```text
1. its registered continuation identity is present;
2. its mandatory provenance, revision and integrity bindings validate;
3. the recovered-context digest matches;
4. the NEXT_ACTION identity and target digest match;
5. the governing boundary remains lawful;
6. no rule requires fresh semantic computation.
```

When all six conditions hold:

```text
SETTLED_CONTINUATION → REUSE without recompute.
```

REUSE must be observable as a persisted typed decision. A silent fresh
computation of an already-settled continuation is forbidden.

### P3.2 BLOCKED-LAWFUL predicate

A lawful but blocked continuation must remain explicitly blocked when:

```text
1. the Information Closure is structurally lawful;
2. provenance and revision validate;
3. the continuation boundary is registered;
4. a registered blocking condition applies.
```

The result is:

```text
BLOCKED_LAWFUL_CONTINUATION
```

It must not be silently recomputed, upgraded, downgraded, guessed, or replaced
by another continuation.

### P3.3 Identity persistence

Every terminal semantic state must be persisted as a digest-bound identity
record before success closure. A continuation result that is not persistable
under this contract is invalid.

## P4 — Side-Channel Denial Matrix

| Channel | Denial rule | Required evidence |
| --- | --- | --- |
| Fixture role | Reconstruction receives only an opaque instance/locator, never role labels. | Invocation binding contains no expected role or verdict. |
| Semantic search / embedding / ranking | Forbidden for target discovery or continuation choice. | Deterministic inventory traversal only. |
| Model hidden context | Model is absent from the authority path. | No model-derived field in `ESContinuationInput`. |
| Physical filesystem | No direct physical reconciliation or freshness inference. | No physical-probe artifact; PIR remains deferred. |
| Process environment | Only approved invocation fields are consumed. | Environment inputs outside the allowlist are denied. |
| Unregistered IS object | Not addressable. | Missing/unregistered object resolves as missing. |
| Carrier semantics | Carrier retrieves and verifies; it does not interpret or decide. | No Carrier-produced semantic verdict. |
| Global mutable state | No reconstruction dependency on mutable global state. | Same locator/context digest reproduces the same input. |

Any denied-channel influence on `ESContinuationInput`, continuation identity,
REUSE/BLOCK choice, or success closure is a design violation.

## P5 — Negative Decision Precedence

Negative conditions must be evaluated deterministically in this order:

```text
1. ILLEGAL_CONTINUATION_BLOCK
2. MISSING_INFORMATION_BLOCK
3. STALE_INFORMATION_BLOCK
4. AMBIGUOUS_INFORMATION_BLOCK
```

The precedence meaning is narrow:

```text
1. If present evidence proves that the attempted continuation violates the
   registered boundary, authority or identity, rule ILLEGAL first.

2. If legality cannot be determined because a mandatory object, mapping,
   revision, digest or pointer is absent/unresolvable, rule MISSING first.

3. If the mandatory evidence is present but invalidated, expired, superseded
   or outside the registered freshness/revision window, rule STALE.

4. If current mandatory evidence is valid but yields zero valid continuation
   pointers, multiple conflicting pointers, or multiple conflicting mandatory
   mappings, rule AMBIGUOUS.
```

For every negative decision the Run Manifest must persist:

```text
trigger;
mandatory-object inventory result;
evidence references and digests;
precedence reason;
typed decision;
all secondary observed defects without changing precedence;
closure artifact digest.
```

All negative paths are fail-closed:

```text
no fallback guess;
no partial continuation;
no semantic repair;
no silent recompute;
no stale-success persistence.
```

## P6 — Carrier Lifecycle Contract

The Carrier remains restricted to:

```text
persistence;
retrieval;
integrity verification;
digest / identity binding;
success/failure lifecycle evidence.
```

The Carrier is forbidden from:

```text
semantic interpretation;
NEXT_ACTION generation;
REUSE/BLOCK authority;
PALACE inference;
physical-state authority;
repairing invalid semantic input.
```

Lifecycle invariants:

```text
1. A FINAL_SUCCESS artifact may exist only after all mandatory semantic,
   identity, provenance, negative-case and Carrier closure validations pass.

2. A persistence failure invalidates the run and must not leave a success
   artifact.

3. A post-write self-check failure invalidates the run and must be represented
   as failure evidence.

4. Process-result evidence must reflect the final validated lifecycle state,
   not an earlier optimistic status.

5. Success and failure artifacts must be separately typed and must not be
   merged into one ambiguous aggregate.

6. Immutable evidence objects are write-once; later correction requires a new
   governance object and cannot rewrite prior evidence.
```

The pre-existing E8 Carrier boundary may constrain the later implementation,
but it does not itself prove this integrated lifecycle.

## P7 — Integrated-vs-Predecessor Boundary

The predecessor evidence is admissible only with these limits:

```text
E8 = bounded CarrierSQLite carrier equivalence for its exact adjudicated
     configuration.

R01 = bounded continuation sufficiency for its exact registered Information
      Closure and reconstruction configuration.

D  = a NEW integrated semantic-closure object.
```

Therefore:

```text
E8 + R01 ≠ integrated SimiGo proof;
E8 + R01 ≠ PALACE equivalence;
E8 + R01 ≠ general Execution State theorem;
E8 + R01 ≠ production SimiGo validity;
E8 + R01 ≠ LLM autonomy.
```

Partition D may use E8 and R01 only as predecessor evidence boundaries. The
integrated claim must be established by a fresh evidence chain for the
registered D configuration.

If D later succeeds, the only permissible claim is:

```text
For the pre-registered bounded configuration, PALACE Information Space supplied
complete, traceable, side-channel-free continuation context and Execution State
produced the next lawful continuation without hidden authority transfer.
```

The claim must not be broadened to arbitrary IS states, arbitrary ES states,
physical reconciliation, PALACE equivalence, production SimiGo, LLM autonomy,
or a general SimiGo architecture proof.

## Acceptance effect

Acceptance of this v1.1 revision would only establish that the design contracts
are sufficiently precise for a separate Run Manifest / Implementation-Fixture
Preparation Request.

It does not authorize:

```text
implementation;
fixture creation;
experiment execution;
IS mutation;
E9;
EXP-004;
PALACE equivalence ruling;
general ES theorem;
integrated SimiGo proof;
automatic campaign authorization.
```

The next lawful step after acceptance is a separately reviewed implementation,
fixture or Run Manifest Request. Experiment execution remains a separate
explicit Human decision.
