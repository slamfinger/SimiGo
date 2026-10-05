# A4 Reduction / Ownership Study

Date: 2026-10-05
Active route: `PALACE / INFORMATION SPACE FOUNDATION`
Study: `A4 — CARRIER GAP STUDY / REDUCTION & OWNERSHIP`
Status: `FINDINGS / REFRAME REQUIRED BY HUMAN REVIEW`
Reframe audit: `PALACE_INFORMATION_SPACE_FOUNDATION_CORE_SUFFICIENCY_AUDIT_20261005.md`
Prior A4 conceptual study: `eae0b02`, ruled `FINDINGS / REVISE REQUIRED`
Gate baseline: `ab97244`
Frozen Contracts: `UNCHANGED`
Scope guard: `CONCEPTUAL / DOCUMENTARY ONLY · NO IMPLEMENTATION · NO ADAPTER · NO CARRIER INTEGRATION · NO MEMPALACE MUTATION · NO PROBE EXECUTION · NO EXPERIMENT · NO CONTRACT CHANGE`

## 1. Purpose

This study answers the Human review findings on the prior A4 conceptual study.

It separates:

1. carrier-state semantic obligations;
2. resolver / adapter / validation obligations;
3. probe / harness obligations;
4. Frozen Contract requirements.

It then performs dependency and removal analysis over the prior `MCL-1..7`
candidate closure. The result replaces that flat list with a provisional
carrier-state reduction.

This study does **not** claim a final minimal carrier, select an archetype,
authorize implementation, or revise MemPalace.

Human review subsequently reframed the result: `CS-1..CS-6` are candidate
semantic decomposition artifacts, not six physical carrier primitives. The next
study is `InformationCore / RelationCore Sufficiency Audit`, separating semantic
Core, Store boundary, backend, and validation layer.

## 2. Ownership vocabulary

| Owner | Meaning |
|---|---|
| `CARRIER-STATE` | A semantic fact or relation that must persist in the carrier for future continuation to remain expressible. |
| `RESOLVER/ADAPTER` | A mechanical operation that reads, validates, traverses, or reports carrier-state facts. |
| `PROBE/HARNESS` | The registered observation apparatus used by PRQ-ISF-01. |
| `FROZEN-CONTRACT` | A requirement whose meaning and failure family come from Frozen ES↔IS contracts. |
| `UNRESOLVED` | Ownership cannot yet be assigned without additional Human ruling or evidence. |

Important rule:

```text
A carrier must preserve semantic facts.
It does not follow that the carrier must implement every validator
that observes those facts.
```

## 3. Obligation ownership matrix

### 3.1 Registered obligations `O-1..O-9`

| ID | Obligation | Primary semantic owner | Secondary owners | Reduction reading |
|---|---|---|---|---|
| O-1 | Exact content retention | `CARRIER-STATE` | `FROZEN-CONTRACT`, `PROBE/HARNESS` | Immutable historical content must persist; probe only verifies retrieval/mismatch. |
| O-2 | Exact reference resolution | split | `CARRIER-STATE`, `RESOLVER/ADAPTER`, `PROBE/HARNESS` | Carrier stores stable exact identity/addressability; resolver performs deterministic resolution. |
| O-3 | Canonical record integrity | `CARRIER-STATE` | `FROZEN-CONTRACT`, `RESOLVER/ADAPTER` | Carrier preserves identity-bearing fields; Frozen Contract defines identity; resolver detects mismatch. |
| O-4 | Typed relation preservation | `CARRIER-STATE` | `FROZEN-CONTRACT`, `RESOLVER/ADAPTER` | Carrier must preserve `result / used / surface / continues` as distinct relations. |
| O-5 | Provenance separation | `CARRIER-STATE` | `FROZEN-CONTRACT` | Provenance is stored outside identity-bearing content. |
| O-6 | Historical pin stability | `CARRIER-STATE` | `RESOLVER/ADAPTER`, `PROBE/HARNESS` | Carrier preserves the old pin target; resolver/probe verify it. |
| O-7 | Explicit succession | `CARRIER-STATE` | `PROBE/HARNESS` | Carrier stores an explicit prior/successor relation; probe checks it. |
| O-8 | Lineage closure and acyclicity | split | `CARRIER-STATE`, `RESOLVER/ADAPTER`, `FROZEN-CONTRACT`, `PROBE/HARNESS` | Carrier stores explicit lineage relations; resolver/probe detect closure/cycle. |
| O-9 | Mechanical failure visibility | `FROZEN-CONTRACT + RESOLVER/ADAPTER` | `PROBE/HARNESS` | Frozen Contract defines failure families; resolver reports them. This is not a carrier-state primitive. |

### 3.2 Prior primitive ownership `MCL-1..7`

| Prior ID | Ownership ruling | Reduction |
|---|---|---|
| MCL-1 Immutable Content Datum | Essential carrier-state. | Becomes `CS-1 Immutable historical content`. |
| MCL-2 Exact Identity / Pin Resolution | Mixed. | Splits into `CS-2 Stable exact identity / addressability` plus derived `MO-1 deterministic reference resolution` and historical-pin verification. |
| MCL-3 Typed Relation Record | Essential carrier-state. | Becomes `CS-3 Typed relation records`. |
| MCL-4 Separated Provenance Record | Essential carrier-state. | Becomes `CS-4 Separated provenance records`. |
| MCL-5 Succession Relation | Essential carrier-state for the registered PRQ class. | Becomes `CS-5 Explicit succession relations`. |
| MCL-6 Lineage Closure | Mixed. | Splits into `CS-6 Explicit lineage relations` plus derived `MO-4 closure/cycle validation`. |
| MCL-7 Mechanical Failure Surface | Non-carrier. | Moves to `MO-2`, `MO-5`, and Frozen-Contract/resolver responsibility. It is not a carrier-state primitive. |

## 4. Reduced carrier-state set

```text
CS-1  Immutable historical content
CS-2  Stable exact identity / addressability
CS-3  Typed relation records
CS-4  Separated provenance records
CS-5  Explicit succession relations
CS-6  Explicit lineage relations
```

This is a **registered-bounded candidate carrier-state set**. It is not yet a
mathematically minimal carrier architecture.

CS-6 is retained because removing explicit lineage relations first breaks O-8;
it is not fully derived from generic typed relations. A generic typed-relation
primitive could store `continues`, but the lineage-specific obligation requires
that this relation be preserved, traversable, and non-cyclic.

## 5. Dependency graph

```text
CS-1 Immutable historical content
  ├── enables → CS-2 stable exact identity / addressability
  ├── enables → MO-2 missing / mismatch visibility
  └── first breaks → O-1

CS-2 Stable exact identity / addressability
  ├── enables → MO-1 deterministic reference resolution
  ├── enables → CS-3 / CS-5 / CS-6 endpoint binding
  ├── enables → O-2
  └── first breaks → O-2

CS-3 Typed relation records
  ├── enables → MO-3 relation integrity checks
  ├── enables → CS-5 succession as a typed relation
  ├── enables → CS-6 lineage as a typed relation
  └── first breaks → O-4

CS-4 Separated provenance records
  ├── enables → O-5
  └── first breaks → O-5

CS-5 Explicit succession relations
  ├── enables → O-7
  └── first breaks → O-7

CS-6 Explicit lineage relations
  ├── enables → MO-4 lineage / cycle checks
  ├── enables → O-8
  └── first breaks → O-8
```

Mechanical / observation obligations:

```text
MO-1 deterministic reference resolution
  depends on → CS-2
  observes → O-2

MO-2 missing / mismatch visibility
  depends on → CS-1 + CS-2
  observes → O-1 / O-3 failures

MO-3 relation integrity checks
  depends on → CS-3
  observes → O-4

MO-4 lineage / cycle checks
  depends on → CS-2 + CS-6
  observes → O-8

MO-5 frozen failure-family mapping
  depends on → FROZEN-CONTRACT + resolver/adapter
  observes → O-9

MO-6 indeterminacy classification
  depends on → PROBE/HARNESS
  prevents harness defects from being miscalled carrier failures
```

## 6. Removal analysis

| Removed item | First registered obligation lost | Downstream loss | Reduction verdict |
|---|---|---|---|
| CS-1 Immutable historical content | O-1 | O-2 loses an invariant target; O-3/O-6/O-7 lose stable content basis. | **Essential.** |
| CS-2 Stable exact identity / addressability | O-2 | O-3, O-6, O-7, and MO-1 cannot denote exact versions. | **Essential.** |
| CS-3 Typed relation records | O-4 | O-7 and O-8 lose typed relation form; MO-3 has no integrity object. | **Essential.** |
| CS-4 Separated provenance records | O-5 | Audit context can contaminate identity or disappear. | **Essential.** |
| CS-5 Explicit succession relations | O-7 | Historical and current versions become implicitly related at best. | **Essential for the registered PRQ class.** |
| CS-6 Explicit lineage relations | O-8 | MO-4 has no lineage object; ancestry preservation fails. | **Essential.** |
| MO-1 deterministic reference resolution | O-2 becomes externally undecidable. | Historical pin cannot be mechanically resolved. | Derived / non-carrier observation. |
| MO-2 missing / mismatch visibility | O-1/O-3 become unverifiable. | Silent mutation becomes possible. | Derived / non-carrier observation. |
| MO-3 relation integrity checks | O-4 becomes unverifiable. | Flattening or loss may be hidden. | Derived / non-carrier observation. |
| MO-4 lineage / cycle checks | O-8 closure/cycle becomes unverifiable. | Lineage corruption may be hidden. | Derived / non-carrier observation. |
| MO-5 frozen failure-family mapping | O-9 loses Frozen Contract classification. | Mechanical failures may be present but misreported. | Derived / non-carrier observation. |
| MO-6 indeterminacy classification | Harness defects may be miscalled carrier failures. | Route verdict loses epistemic discipline. | Probe/harness obligation. |

## 7. Reduction result

### 7.1 Essential carrier-state semantics

```text
CS-1  Immutable historical content
CS-2  Stable exact identity / addressability
CS-3  Typed relation records
CS-4  Separated provenance records
CS-5  Explicit succession relations
CS-6  Explicit lineage relations
```

These six are essential for the registered PRQ-ISF-01 mutation class.

### 7.2 Derived / observation obligations

```text
D-1  deterministic exact reference resolution
D-2  historical pin verification
D-3  canonical record identity verification
D-4  typed relation integrity verification
D-5  lineage closure / cycle verification
D-6  frozen failure-family reporting
D-7  indeterminacy classification
```

These are required to observe and judge the carrier, but they are not carrier-state
primitives.

### 7.3 Non-carrier reductions

```text
MCL-2 Exact Identity / Pin Resolution
  → CS-2 + D-1 + D-2

MCL-6 Lineage Closure
  → CS-6 + D-5

MCL-7 Mechanical Failure Surface
  → MO-2 + MO-5 + D-6, governed by Frozen Contract
```

Thus the prior flat `MCL-1..7` list becomes:

```text
6 essential carrier-state semantics
+ 7 derived / observation obligations
```

## 8. Consequences

### 8.1 For MemPalace

MemPalace's NO-GO becomes deeper than “it lacks a failure surface.” Under the
reduction, MemPalace as-is does not preserve the required carrier-state set:

```text
CS-1  weak / absent for immutable historical content
CS-2  weak for exact version identity independent of source path/chunk
CS-3  absent as a canonical typed relation surface
CS-4  partially present
CS-5  not native for information succession
CS-6  absent for canonical continuation lineage
```

Therefore MemPalace is not rejected because it lacks a resolver feature. It is
rejected because its native state does not preserve the necessary continuation
facts.

### 8.2 For carrier selection

No archetype or carrier is selected. The correct future question is no longer:

> Which product implements MCL-1..7?

It is:

> Which carrier-state model can preserve CS-1..CS-6, and which separate observer
> can verify them without semantic rescue?

## 9. Non-claims

This study does not claim that:

1. `CS-1..6` are universally minimal;
2. they are sufficient for every Information Space or carrier;
3. a composite carrier is approved;
4. a resolver design is approved;
5. MemPalace could never be revised;
6. implementation is authorized;
7. Frozen Contracts authorize a carrier schema.

## 10. Next gate

Human review of this reduction study.

```text
ACCEPT        → authorize a narrowly scoped follow-up: define a decodable
                observation contract for CS-1..CS-6 without selecting a carrier
FINDINGS      → revise ownership, dependency, or reduction analysis
REJECT/PAUSE  → close or pause the Foundation route by explicit ruling
```

No implementation, carrier selection, integration, experiment, or Frozen Contract
change follows automatically.
