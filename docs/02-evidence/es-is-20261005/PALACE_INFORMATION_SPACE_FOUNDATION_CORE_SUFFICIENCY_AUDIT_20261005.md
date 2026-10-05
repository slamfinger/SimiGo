# InformationCore / RelationCore Sufficiency Audit

Date: 2026-10-05  
Active route: `PALACE / INFORMATION SPACE FOUNDATION`  
Study: `A4 — CORE SUFFICIENCY AUDIT`  
Status: `DELIVERED / AWAITING HUMAN REVIEW`  
Prior study: `A4 Reduction / Ownership Study` at `6ce88b9`, Human ruling `FINDINGS / REFRAME REQUIRED`  
Gate baseline: `ab97244`  
Frozen Contracts: `UNCHANGED`  
Scope: `READ-ONLY SEMANTIC / CONTRACT / IMPLEMENTATION AUDIT · NO IMPLEMENTATION · NO ADAPTER · NO CARRIER INTEGRATION · NO MEMPALACE MUTATION · NO PROBE EXECUTION · NO EXPERIMENT · NO CONTRACT CHANGE`

## 1. Reframing

Human review correctly withdrew the prior interpretation:

```text
CS-1..CS-6
        ↓
missing carrier primitives
        ↓
find another carrier
```

The corrected chain is:

```text
Frozen ES↔IS semantics
        ↓
PRQ-ISF-01 obligations
        ↓
Information / Relation semantic core
        ↓
InformationStore / RelationStore boundary
        ↓
SQLite / InMemory / MemPalace / other replaceable persistence
```

Therefore the prior MemPalace result is narrowed, not discarded:

```text
MemPalace native schema does not directly expose the PRQ semantic surface.
Therefore no thin, semantics-preserving adapter makes MemPalace the direct
PRQ implementation.

This does NOT mean MemPalace cannot later serve as a persistence backend,
migration target, or third backend behind the existing Core/Store boundary.
```

The prior A4 Reduction / Ownership Study remains useful as a candidate semantic
decomposition, but its `CS-1..CS-6` are no longer treated as six physical carrier
primitives.

## 2. Audited implementation boundary

```text
InformationCore
  Information            immutable semantic value
  InformationID          opaque semantic identity
  Provenance             separated origin/audit facts
  InformationStore       store / fetch by exact identity

RelationCore
  Relation               immutable directed relation
  RelationID             opaque semantic identity
  RelationPredicate      open semantic slot; no vocabulary/ontology
  RelationStore          store / fetch by exact relation identity

Physical controls
  SQLiteStore            InformationStore physical persistence
  InMemoryStore          second InformationStore backend / control
  SQLiteRelationStore    RelationStore physical persistence
  UpperLayer             imports InformationCore and binds only the Store boundary
```

Important existing facts:

- `Information` is immutable and already formed before storage.
- `InformationID` is opaque; identity recipes are mechanism-side.
- `Information.content` is verbatim by definition.
- `InformationStore.store` is idempotent by identity: first-write-wins.
- `InformationStore.fetch` distinguishes absence (`nil`) from storage failure (`throw`).
- `Relation` is immutable and directed between two `InformationID` endpoints.
- `RelationPredicate` is an open semantic slot with no ontology in Core.
- `RelationStore` mirrors first-write-wins, absence-as-nil, failure-as-throw.
- `UpperLayer` depends only on `InformationCore` and `any InformationStore`; it has
  zero SQLite/WAL/transaction/filing symbols.

## 3. Audit method

For each PRQ obligation `O-1..O-9`, classify:

```text
SATISFIED BY CORE       Information semantic object/store already expresses it.
SATISFIED BY RELATION   Relation semantics express it using existing fields.
HIGHER-LAYER ONLY       Expressible by existing Core/Relation, but traversal,
                        convention, validation, or judgment belongs above Store.
ACTUAL SEMANTIC GAP     Existing semantic objects cannot express the obligation
                        without changing Core/Relation semantics.
```

No implementation was written and no backend was selected.

## 4. Sufficiency matrix

| PRQ obligation | Existing expression | Store / backend expression | Validation location | Classification |
|---|---|---|---|---|
| O-1 Exact content retention | `Information.content` is verbatim and immutable. | `InformationStore` first-write-wins; SQLite stores content and does not overwrite; InMemory confirms the same contract. | `fetch(by:)` returns exact stored value; absence is `nil`; storage failure throws. | **SATISFIED BY CORE** for UTF-8/text-bounded PRQ. **ACTUAL SEMANTIC GAP** only if arbitrary non-Unicode byte fidelity is required. |
| O-2 Exact reference resolution | `InformationID` is an opaque semantic identity; `RelationID` is opaque. | `fetch(by identity:)`; first-write-wins. | Exact-ID fetch is already the Store contract. | **SATISFIED BY CORE** |
| O-3 Canonical record integrity | `Information` is immutable; identity is a fact of the Information; `Relation` is immutable and identity-bearing. | Stores never overwrite an existing identity. | A future CR mapper must compute/check canonical identity above Store. | **SATISFIED BY CORE + HIGHER-LAYER ONLY** |
| O-4 Typed relation preservation | `Relation` has subject, predicate, object; predicate is an open semantic slot. | `RelationStore` preserves the full relation. | Higher layer must fix/register PRQ predicate conventions and validate required relation kinds. | **SATISFIED BY RELATION** |
| O-5 Provenance separation | `Provenance` is a separate value on `Information` and `Relation`. | Stores persist provenance without merging it into identity/content. | Higher layer may audit provenance. | **SATISFIED BY CORE** |
| O-6 Historical pin stability | Immutable Information plus a Relation such as `historicalPin` can bind a label/reference to exact Information identity. | `RelationStore` preserves the relation first-write-wins. | Pin resolution and audit are higher-layer; Store need not understand “pin”. | **SATISFIED BY RELATION + HIGHER-LAYER ONLY** |
| O-7 Explicit succession | Immutable directed Relation can record `prior → successor` with provenance. | `RelationStore` preserves the succession relation. | Higher layer defines valid succession and prevents confusing current with historical. | **SATISFIED BY RELATION + HIGHER-LAYER ONLY** |
| O-8 Lineage closure / acyclicity | Relations can encode lineage edges between Information identities. | RelationStore preserves individual edges. | Graph traversal, closure, and cycle checking belong above Store. | **SATISFIED BY RELATION + HIGHER-LAYER ONLY** |
| O-9 Mechanical failure visibility | Store distinguishes absence from failure; first-write-wins prevents silent update. | Backends preserve existing facts and expose storage errors. | Frozen failure-family mapping belongs to resolver/verification. | **HIGHER-LAYER ONLY** |

## 5. Findings

### 5.1 Existing Core already covers most PRQ semantics

`O-1..O-5` have a strong existing basis.

```text
O-1  immutable verbatim Information content
O-2  opaque exact identity and exact-ID fetch
O-3  immutable semantic object identity
O-4  directed typed relation slot
O-5  separated provenance
```

These are not new carrier primitives to invent.

### 5.2 Succession, pin, lineage, and failure visibility are higher-layer

They can be expressed with existing immutable Information/Relation semantics, but
they are not Store responsibilities:

```text
O-6  historical pin        Relation expression + higher-layer resolution/audit
O-7  succession            Relation expression + higher-layer succession semantics
O-8  lineage/cycle         Relation graph + higher-layer traversal/validation
O-9  failure mapping       Store nil/throw separation + higher-layer Frozen mapping
```

Thus the missing piece is not necessarily a new Store primitive. The missing piece
is a small upper-layer continuation-graph semantics.

### 5.3 One conditional semantic gap

`Information.content` is `String`, verbatim by definition, and persisted as text.

Therefore:

```text
For a UTF-8/text-bounded PRQ:  no semantic gap.
For arbitrary non-Unicode byte fidelity: actual semantic gap.
```

The route must explicitly choose one:

```text
bound PRQ-ISF-01 to textual/UTF-8 content, or
open a separate Information byte-content semantic finding.
```

No silent widening of `Information.content` is authorized by this audit.

### 5.4 Backend-control asymmetry is implementation debt, not semantic debt

`InformationStore` has two controls:

```text
SQLiteStore
InMemoryStore
```

`RelationStore` currently has SQLite but no parallel in-memory control in the
audited surface. This asymmetry does not show a Core semantic gap, but it should be
registered as future implementation debt if backend independence is needed for
Relations.

## 6. Sufficiency result

```text
FOR THE TEXT/UTF-8-BOUNDED PRQ DOMAIN:

InformationCore + RelationCore + Store boundaries are sufficient to express
the PRQ-ISF-01 continuation graph semantics.

No new Store primitive is currently required.

Required upper-layer work:
  CR/canonical mapping
  predicate conventions
  historical pin resolution
  succession semantics
  lineage traversal/cycle validation
  frozen failure-family mapping

One conditional semantic gap:
  arbitrary non-text byte fidelity in Information.content
```

This result does not claim that every backend implements the semantics, only that
the existing semantic/Store boundary is sufficient to express them.

## 7. MemPalace reclassification

The earlier MemPalace NO-GO remains true in its original narrow form:

```text
MemPalace native drawers do not directly expose the PRQ semantic surface.
No thin, semantics-preserving native adapter makes MemPalace the direct PRQ
implementation.
```

But it must be reframed:

```text
NO-GO as direct PRQ semantic carrier
≠
eliminated as a future persistence backend or migration target
```

MemPalace may return later as:

```text
a migration source;
a persistence backend behind InformationStore / RelationStore;
a third backend-control case after SQLite and InMemory.
```

Any such path must preserve the Core/Store boundary and must not require the upper
layer to know MemPalace internals.

## 8. Non-claims

This audit does not claim that:

1. Information Space is fully implemented;
2. Core/Relation semantics are universally sufficient;
3. SQLite or InMemory satisfies every future production requirement;
4. MemPalace is approved or rejected as a backend;
5. higher-layer graph traversal is authorized for implementation;
6. predicate vocabulary is defined;
7. byte-content semantics should be widened;
8. Frozen Contracts are changed.

## 9. Next gate

Human review of this sufficiency audit.

```text
ACCEPT TEXT-DOMAIN BOUNDARY
  → authorize a higher-layer continuation-graph semantics/design study,
    still without implementation.

REQUIRE BYTE FIDELITY
  → open a separate Information byte-content semantic finding first.

FINDINGS
  → revise this audit.
```
