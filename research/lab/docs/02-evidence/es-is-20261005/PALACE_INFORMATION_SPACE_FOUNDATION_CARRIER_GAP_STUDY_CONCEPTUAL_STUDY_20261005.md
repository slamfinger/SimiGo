# Carrier Gap Study — A4 Conceptual Study

Date: 2026-10-05
Active route: `PALACE / INFORMATION SPACE FOUNDATION`
Study: `A4 — CARRIER GAP STUDY / CONCEPTUAL STUDY`
Status: `FINDINGS / REVISE REQUIRED BY HUMAN REVIEW`
Replacement study: `A4 Reduction / Ownership Study` — `PALACE_INFORMATION_SPACE_FOUNDATION_A4_REDUCTION_OWNERSHIP_STUDY_20261005.md`
Accepted scope charter: `2f0959b`
Gate baseline: `ab97244`
Frozen Contracts: `UNCHANGED`
Scope guard: `CONCEPTUAL / DOCUMENTARY ONLY · NO IMPLEMENTATION · NO ADAPTER · NO CARRIER INTEGRATION · NO MEMPALACE MUTATION · NO PROBE EXECUTION · NO EXPERIMENT · NO CONTRACT CHANGE`

## 1. Study question

This study answers the accepted A4 questions `CGQ-1..CGQ-5`:

> Which requirements are Frozen ES↔IS semantics, PRQ-bounded requirements,
> general Information Space semantics, or probe-local expression? What minimal
> carrier-layer semantics follow for the registered PRQ class?

This is a conceptual derivation. It does not prove that an implementation exists,
does not select a carrier, and does not claim universal minimality.

## 2. Bounded interpretation

The word “minimal” is used only in this sense:

> For the registered PRQ-ISF-01 mutation class, no listed primitive can be removed
> while preserving the Frozen ES↔IS semantics and the preregistered historical
> succession test.

It does **not** mean:

1. the primitive set is mathematically minimal;
2. the set is sufficient for every possible Information Space;
3. the set is sufficient for every carrier;
4. a concrete implementation can be derived without new findings;
5. PALACE, MCP, a database, graph store, or file format is selected.

## 3. Method

1. Trace every relevant obligation to one of:
   - `SRC-FROZEN`;
   - `SRC-PRQ`;
   - `SRC-IS-SEMANTIC`;
   - `SRC-PROBE-LOCAL`.
2. Remove probe-local serialization, API names, fixture bytes, and implementation
   forms from carrier semantics.
3. Group the remaining requirements into minimal candidate primitives.
4. Test each primitive against removal: if removal breaks Frozen semantics or the
   registered PRQ class, it is necessary for that bounded class.
5. Express each primitive at four levels: semantic, structural, mechanical, and
   implementation-incidental.
6. Derive failure boundaries and carrier archetypes without selecting a product.

## 4. CGQ-1 — obligation derivation

### 4.1 Final source table

| Obligation | Underlying dimension | Strongest source | Other sources | Reason |
|---|---|---|---|---|
| O-1 Exact content retention | CGT-1, CGT-2 | `SRC-FROZEN` | `SRC-PRQ`, `SRC-IS-SEMANTIC` | I-1 requires used items to re-materialize at pinned identities; PRQ requires old pins to survive succession. |
| O-2 Exact reference resolution | CGT-2 | `SRC-FROZEN` | `SRC-PRQ`, `SRC-IS-SEMANTIC` | `CR_ref`, used-item pins, and parent references must denote exact registered versions. |
| O-3 Canonical record integrity | CGT-2, CGT-3 | `SRC-FROZEN` | `SRC-PRQ` | Frozen I-1 derives CR identity from identity-bearing fields; mutation must be detectable. |
| O-4 Typed relation preservation | CGT-3 | `SRC-FROZEN` | `SRC-PRQ`, `SRC-IS-SEMANTIC` | `result`, `used`, `surface`, and `continues` are not interchangeable relation kinds. |
| O-5 Provenance separation | CGT-5 | `SRC-FROZEN` | `SRC-IS-SEMANTIC` | Provenance is retained for audit but excluded from CR identity. |
| O-6 Historical pin stability | CGT-1, CGT-4 | `SRC-PRQ` | `SRC-IS-SEMANTIC` | PRQ explicitly changes a current information pointer while requiring the old historical pin to remain valid. |
| O-7 Explicit succession | CGT-4 | `SRC-PRQ` | `SRC-IS-SEMANTIC` | PRQ requires an auditable transition from prior information to successor information. |
| O-8 Lineage closure and acyclicity | CGT-6 | `SRC-FROZEN` | `SRC-PRQ` | I-1 V-3 requires unbroken, hash-consistent, acyclic ancestry. |
| O-9 Mechanical failure visibility | CGT-7 | `SRC-FROZEN` | `SRC-PRQ` | Frozen resolve must expose missing, mismatch, and cycle families rather than repairing them semantically. |
| O-10 SHA-256 as the only identity form | CGT-2 | `SRC-PROBE-LOCAL` | — | SHA-256 is a valid mechanical form in the accepted probe, not a Frozen semantic requirement. |
| O-11 Canonical JSON / record serialization | CGT-2, CGT-3 | `SRC-PROBE-LOCAL` | — | Needed for deterministic decoding, not a carrier semantics requirement. |
| O-12 `put_blob / get_node / ...` operation names | CGT-2, CGT-3 | `SRC-PROBE-LOCAL` | — | Accepted only as probe observation vocabulary. |
| O-13 Exact `SC-00..SC-12` fixture bytes | CGT-1 | `SRC-PROBE-LOCAL` | — | Fixture values are implementation choices for the registered probe. |
| O-14 Decoy summary | CGT-7 | `SRC-PROBE-LOCAL` | — | It tests forbidden semantic rescue; it is not a carrier obligation. |

### 4.2 Summary

```text
Frozen-required core:
  O-1, O-2, O-3, O-4, O-5, O-8, O-9

PRQ-bounded additions:
  O-6, O-7

Probe-local, not carrier semantics:
  O-10, O-11, O-12, O-13, O-14
```

The Information Space semantic layer supports O-1, O-2, O-4, O-5, O-6, and O-7
as plausible general obligations, but the A4 study does not universalize them
beyond the registered boundary.

## 5. CGQ-2 — minimal candidate primitive set

### 5.1 Reduced primitive set

The eight provisional primitives from the scope charter reduce to seven bounded
carrier-layer primitives.

| ID | Primitive | Covers | Necessary for registered PRQ class because |
|---|---|---|---|
| MCL-1 | Immutable Content Datum | O-1 | Without it, pinned used information can silently mutate or disappear. |
| MCL-2 | Exact Identity / Pin Resolution | O-2, O-6 | Without it, references and historical pins cannot denote exact versions. |
| MCL-3 | Typed Relation Record | O-4 | Without it, `result`, `used`, `surface`, and `continues` can be flattened. |
| MCL-4 | Separated Provenance Record | O-5 | Without it, audit context can contaminate identity or be lost. |
| MCL-5 | Succession Relation | O-6, O-7 | Without it, information change is silent and historical/ current versions are conflated. |
| MCL-6 | Lineage Closure | O-8 | Without it, ancestry can be missing, substituted, cyclic, or non-traversable. |
| MCL-7 | Mechanical Failure Surface | O-9 | Without it, missing/mismatch/cycle may be semantically repaired or hidden. |

### 5.2 Non-primitive structural expression

Canonical records remain necessary, but they are a composite expression rather
than an additional semantic primitive:

```text
Canonical Record
  = identity-bearing fields
  + typed relations
  + separated provenance
  + optional succession relations
```

Therefore the accepted `P3 Canonical Record Surface` is not discarded. It is
explained as a composite of `MCL-2`, `MCL-3`, and `MCL-4`.

Similarly, `P5 Historical Pin` is not a separate semantic primitive; it is a
bounded use of `MCL-2 Exact Identity / Pin Resolution`.

### 5.3 Minimal semantic layer

For the registered PRQ class, the minimal candidate semantic layer is:

```text
MCL-1  Immutable Content Datum
MCL-2  Exact Identity / Pin Resolution
MCL-3  Typed Relation Record
MCL-4  Separated Provenance Record
MCL-5  Succession Relation
MCL-6  Lineage Closure
MCL-7  Mechanical Failure Surface
```

This is a candidate minimal layer, not a mathematical minimality proof.

## 6. CGQ-3 — expression matrix

| Primitive | Semantic obligation | Structural obligation | Mechanical obligation | Implementation-incidental forms |
|---|---|---|---|---|
| MCL-1 Immutable Content Datum | A registered information value remains available in its exact historical form. | Content is identified and addressed independently of current pointers. | retrieval returns exact bytes or explicit MISSING; hash mismatch is observable. | SHA-256, blob store, file, object store. |
| MCL-2 Exact Identity / Pin Resolution | A reference denotes one exact version, not “something similar.” | pin/reference table maps label or identity to exact version. | resolve returns exact target or deterministic MISSING. | pin table, index, database key, symbolic label. |
| MCL-3 Typed Relation Record | Relation kind changes continuation meaning. | preserve `result`, `used`, `surface`, `continues` as distinct relations. | missing, duplicated, or flattened relations are observable. | edge table, JSON fields, graph record. |
| MCL-4 Separated Provenance Record | Audit context is not identity-bearing content. | provenance is stored outside canonical identity fields. | provenance change does not alter CR identity and remains auditable. | metadata columns, provenance records, actor fields. |
| MCL-5 Succession Relation | New information may succeed old information without erasing old information. | explicit prior/version/successor relation. | old and successor remain distinguishable and retrievable. | event log, version chain, successor pointer. |
| MCL-6 Lineage Closure | Continuation ancestry remains explicit and acyclic. | parent/continuation graph plus canonical record references. | missing ancestor, cycle, or identity substitution is visible. | visited-set traversal, graph index, recursive query. |
| MCL-7 Mechanical Failure Surface | Absence, mismatch, and corruption are facts, not problems to be interpreted away. | explicit failure records or result states. | deterministic frozen failure families. | error codes, JSON report fields, resolver states. |

No row authorizes semantic search, LLM summary, implicit completion, or
carrier-specific privileged access.

## 7. CGQ-4 — failure boundaries

### 7.1 Failure taxonomy

| Failure family | Trigger | Correct outcome | Forbidden rescue |
|---|---|---|---|
| F-1 content absence | pinned content digest is unavailable | explicit MISSING / frozen I-NF family | substitute current version, summary, or inferred content |
| F-2 content mutation | retrieved bytes differ from pinned identity | explicit mismatch / frozen I-MISMATCH family | normalize, repair, or accept similar bytes |
| F-3 record identity failure | canonical fields no longer reproduce record identity | explicit canonical identity failure | rewrite fields to match the expected identity |
| F-4 relation failure | required relation is missing, duplicated, or flattened | explicit typed-relation failure | infer relation from prose, naming, or similarity |
| F-5 provenance failure | provenance is missing or not separated | explicit audit failure | merge provenance into identity or invent provenance |
| F-6 succession failure | prior or successor version is missing; succession is implicit | explicit succession/history failure | treat current pointer as proof of history |
| F-7 lineage failure | ancestor missing, cycle exists, or ancestry is inconsistent | explicit lineage failure / frozen A-NF / A-CYCLE family | reconstruct ancestors semantically |
| F-8 probe/harness indeterminacy | defect, ambiguity, or implementation leak prevents attribution | INDETERMINATE | classify as carrier FAILURE without evidence |

### 7.2 Boundary rule

A carrier may fail explicitly. A probe may record failure. Neither may repair by
semantic inference.

```text
MISSING      stays MISSING
MISMATCH     stays MISMATCH
CYCLE        stays CYCLE
CORRUPTION   stays CORRUPTION
INDETERMINATE stays INDETERMINATE
```

## 8. CGQ-5 — carrier archetypes

These are conceptual archetypes, not products and not authorized implementations.

### Archetype A — Immutable object + reference index

```text
immutable content leaves
        ↓
identity / pin resolution
        ↓
typed relation records
        ↓
lineage closure
```

Strength: direct fit to MCL-1, MCL-2, MCL-3, MCL-6.
Risk: succession and provenance may become afterthoughts unless MCL-4/MCL-5 are
first-class.

### Archetype B — Append-only version/event graph

```text
version succession events
        ↓
immutable content records
        ↓
typed lineage relations
        ↓
failure records
```

Strength: natural fit for MCL-5 and historical retention.
Risk: event richness may hide whether exact content and typed relations remain
mechanically retrievable.

### Archetype C — Typed lineage graph with content-addressed leaves

```text
typed canonical records
        ↓
content-addressed leaves
        ↓
provenance sidecars
        ↓
lineage closure validator
```

Strength: closest fit to the Frozen CR/IR vocabulary.
Risk: graph layer may introduce semantic inference if edges are derived rather
than explicitly registered.

### Archetype D — Composite carrier

Two or more carriers cooperate, with one owning immutable content and another
owning relations or events.
This is not an independent single-carrier test. It requires a separate composite
route and must not be presented as MemPalace validation.

## 9. Result

```text
A4 CONCEPTUAL STUDY RESULT
  Registered-bounded minimal candidate carrier layer =
    MCL-1 Immutable Content Datum
    MCL-2 Exact Identity / Pin Resolution
    MCL-3 Typed Relation Record
    MCL-4 Separated Provenance Record
    MCL-5 Succession Relation
    MCL-6 Lineage Closure
    MCL-7 Mechanical Failure Surface
```

The study also yields a negative design rule:

> Any carrier path that needs semantic search, summaries, implicit reconstruction,
> LLM inference, or frozen-contract modification to satisfy these primitives is not
> a valid independent-carrier implementation of PRQ-ISF-01.

## 10. Non-claims

This study does not claim that:

1. `MCL-1..7` are universally minimal;
2. they are sufficient for every Information Space or carrier;
3. a concrete implementation exists;
4. MemPalace, MCP, a database, graph store, or file format can implement them;
5. a composite carrier is approved;
6. Information Space is necessary for every Execution State;
7. Frozen Contracts authorize a carrier schema;
8. implementation or experiment is authorized.

## 11. Next gate

Human review of this conceptual study.

```text
ACCEPT        → Human may authorize a separate decodable study or carrier-path
                decision based on MCL-1..7
FINDINGS      → revise this conceptual study without implementation
REJECT/PAUSE  → close or pause the Foundation route by explicit ruling
```

No implementation, carrier selection, integration, experiment, or Frozen Contract
change follows automatically.

## 12. Human review findings and supersession

Human review ruled this study `FINDINGS / REVISE REQUIRED`. The direction was
accepted, but `MCL-1..7` mixed carrier-state semantics with resolver and probe
observation capabilities.

Required replacement study:
`A4 Reduction / Ownership Study`.

Key findings preserved:

1. Split stable carrier-state facts from deterministic resolution.
2. Split explicit lineage preservation from closure/cycle validation.
3. Split failure-as-information from failure reporting/classification.
4. Treat `MCL-1..7` as a candidate closure, not a proven minimal carrier layer.
5. Perform ownership, dependency, and removal analysis before carrier selection.
