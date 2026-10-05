# Carrier Gap Study — Scope & Research Question Charter

Date: 2026-10-05  
Active route: `PALACE / INFORMATION SPACE FOUNDATION`  
Study: `A4 — CARRIER GAP STUDY`  
Phase: `SCOPE & RESEARCH QUESTION CHARTER`  
Status: `DELIVERED / AWAITING HUMAN REVIEW`  
Prior ruling: `639f0ab`  
MemPalace audit: `ACCEPTED / CLOSED` at `1540cae`  
Gate baseline: `ab97244`  
Scope guard: `CONCEPTUAL / DOCUMENTARY STUDY ONLY · NO IMPLEMENTATION · NO ADAPTER · NO CARRIER INTEGRATION · NO MEMPALACE MUTATION · NO PROBE EXECUTION · NO EXPERIMENT · NO CONTRACT CHANGE`

## 1. Purpose

This charter defines the A4 study, but does not answer it.

The commissioned question is:

> What is the minimal carrier layer required to satisfy the MemPalace GAP areas
> without semantic inference, hidden completion, candidate mutation, or Frozen
> Contract modification?

The immediate study question is stricter:

> Which MemPalace gaps are minimal Information Space semantics, which are
> current `IS-MCI` / probe expression requirements, and which are carrier
> implementation details?

This distinction is necessary because a missing capability in MemPalace does not
automatically become a carrier obligation.

## 2. Inputs

```text
Frozen I-1 Persistence / Resolve contract
Frozen I-1c Instantiate Completeness contract
Frozen I-1d Runtime Realization / Verification contract
Accepted PRQ-ISF-01 probe design
Accepted PRQ-ISF-01 execution record
Accepted MemPalace IS-MCI feasibility audit
MemPalace historical G0-G3 observations, used only as cautionary context
```

No code, carrier, adapter, MCP, database, or experiment is an input object for
design.

## 3. Non-goals

This study must not:

1. implement an adapter or carrier;
2. modify MemPalace;
3. select a database, graph store, file format, MCP server, or product;
4. redefine Frozen Contracts;
5. add capabilities to `IS-MCI` merely because MemPalace lacks them;
6. claim that a candidate primitive set is sufficient before Human review;
7. convert probe convenience into carrier semantics.

## 4. GAP taxonomy

The MemPalace audit found five exposed gaps. For A4, each is reclassified into
seven underlying semantic dimensions rather than treated as independent product
features.

| Taxonomy ID | Dimension | Core question | MemPalace-exposed gaps |
|---|---|---|---|
| CGT-1 | Content invariance | What remains exactly retrievable after registration, succession, or movement? | immutable content; historical pinning |
| CGT-2 | Identity and resolution | What makes an information item the same item at a later time? | immutable content; canonical records |
| CGT-3 | Typed relation preservation | Which distinctions are semantic and may not be flattened? | typed references |
| CGT-4 | Temporal succession | How can current information change without destroying historical references? | historical pinning; evolution events |
| CGT-5 | Provenance separation | What is identity-bearing evidence and what is non-identity context? | separated provenance |
| CGT-6 | Lineage and acyclicity | How are continuation ancestors preserved and traversed? | traversable lineage |
| CGT-7 | Mechanical failure discipline | How are absence, mismatch, cycle, and corruption exposed without repair? | mechanical failure discipline |

Canonical records are treated as a structural expression of CGT-2 and CGT-3, not
as an independent semantic primitive.

## 5. Obligation-source classification

Every candidate obligation must be classified into one of four sources. A
primitive may have more than one source, but the strongest source must be named.

| Source code | Meaning | Decision force |
|---|---|---|
| SRC-FROZEN | Required by a Frozen ES↔IS contract. | Required for that contract; cannot be removed without contract revision. |
| SRC-PRQ | Required by the registered PRQ-ISF-01 mutation/evolution class. | Required for the registered bounded test, not universally. |
| SRC-IS-SEMANTIC | Required by the Information Space concept independent of a specific probe. | Candidate general obligation, but needs explicit argument. |
| SRC-PROBE-LOCAL | Required only by decoder, harness, serialization, or current implementation. | Must not be promoted to carrier semantics without separate ruling. |

### 5.1 Provisional classification

This classification is provisional until Human review.

| Gap / requirement | Underlying dimension | Provisional source | Reason |
|---|---|---|---|
| Immutable historical bytes | CGT-1, CGT-2 | `SRC-FROZEN + SRC-PRQ` | I-1 requires used items to re-materialize at pinned identities; PRQ tests old pins after succession. |
| Content digest as identity form | CGT-2 | `SRC-PROBE-LOCAL` | Digest is a useful mechanical identity form, not the only conceivable identity semantics. |
| Canonical record serialization | CGT-2, CGT-3 | `SRC-PROBE-LOCAL` | Canonical form is needed for deterministic decoding, but JSON / record shape is not carrier semantics. |
| Typed `result / used / surface / continues` distinction | CGT-3 | `SRC-FROZEN` | These distinctions are frozen CR semantics, not storage implementation details. |
| Historical pin retrieval | CGT-1, CGT-4 | `SRC-PRQ` | Required because PRQ explicitly tests information succession without changing historical continuation. |
| Append-only storage | CGT-1, CGT-4 | `SRC-PROBE-LOCAL` | Append-only is one implementation strategy; semantic need is historical retrievability and explicit succession. |
| Explicit succession event | CGT-4 | `SRC-PRQ + SRC-IS-SEMANTIC` | PRQ requires auditable succession; Information Space evolution also needs explicit change boundaries. |
| Provenance outside identity | CGT-5 | `SRC-FROZEN` | I-1 excludes provenance from CR identity while retaining it for audit. |
| Parent / ancestor lineage | CGT-6 | `SRC-FROZEN` | I-1 V-3 requires unbroken, hash-consistent, acyclic lineage. |
| Mechanical missing / mismatch / cycle outcomes | CGT-7 | `SRC-FROZEN + SRC-PRQ` | Frozen resolve requires exact failure families; PRQ forbids semantic rescue. |
| Semantic search | none required here | not obligated | Retrieval usefulness is outside PRQ mechanical semantics. |
| Graph / relational database | none required here | `SRC-PROBE-LOCAL` | Storage form is incidental unless later route explicitly studies it. |

## 6. Candidate minimal carrier-layer primitives

The following are candidate primitives for study, not accepted design objects and
not an API.

| Primitive | Conceptual role | Underlying dimensions | Mechanically testable property |
|---|---|---|---|
| P1 Immutable Content Datum | An octet sequence whose historical value remains retrievable under a stable identity. | CGT-1, CGT-2 | retrieve exact bytes or explicit MISSING; no silent mutation |
| P2 Identity Resolution Surface | Resolve an identity or pin to its exact registered version. | CGT-2 | deterministic resolution or deterministic failure |
| P3 Canonical Record Surface | Preserve identity-bearing fields separately from non-identity provenance. | CGT-2, CGT-5 | recomputable canonical identity; provenance change does not alter identity |
| P4 Typed Reference | Preserve distinctions among semantic relation kinds. | CGT-3 | typed retrieval preserves exact relation membership |
| P5 Historical Pin | Bind a label to an exact historical version. | CGT-1, CGT-4 | old pin resolves to old version after succession |
| P6 Succession Record | Register that one version succeeded another without erasure. | CGT-4 | prior and successor remain retrievable and event order is explicit |
| P7 Lineage Closure | Preserve and traverse continuation ancestry. | CGT-3, CGT-6 | complete ancestor path; explicit cycle / missing failure |
| P8 Mechanical Validation Surface | Expose absence, mismatch, cycle, and corruption as explicit outcomes. | CGT-7 | no silent repair, completion, or reclassification |

Incidental forms that must not be promoted to obligations:

```text
JSON serialization
SHA-256 as the only possible identity form
append-only log implementation
graph database
relational database
MCP server
semantic index
file / directory layout
Python / Swift / Rust language binding
```

## 7. Study questions

### CGQ-1 — Derivation question

Which `IS-MCI` obligations derive from Frozen ES↔IS semantics, which derive from
the registered PRQ mutation class, and which are merely probe-local?

Required output: a final `SRC-*` table with reasoning for every obligation.

### CGQ-2 — Minimal-primitive question

What is the smallest candidate set of carrier-layer primitives that covers the
MemPalace GAP dimensions without semantic inference?

Required output:

```text
necessary primitive set
redundant or incidental primitive candidates
dependency relations among primitives
explicit insufficiency claims
```

The study may propose “necessary for the registered PRQ class”; it must not claim
universal minimality.

### CGQ-3 — Expression question

For each necessity, distinguish:

```text
semantic obligation
structural obligation
mechanically testable obligation
implementation strategy
```

Required output: a four-column expression matrix.

### CGQ-4 — Failure-boundary question

Which failures must remain visible to preserve ES↔IS semantics, and which may be
handled as ordinary carrier operations?

Required output: failure taxonomy with forbidden rescues.

### CGQ-5 — Carrier-archetype question

Which broad carrier archetypes could satisfy the candidate primitive set without
changing Frozen Contracts?

Required output: conceptual archetypes only, such as immutable object + reference
layer, versioned record layer, lineage graph layer, or explicit event layer. No
product or technology selection.

## 8. Completion criteria

The A4 study can be delivered only when it provides:

1. a final GAP taxonomy;
2. an obligation-source table for every `IS-MCI` item relevant to the five gaps;
3. a candidate primitive inventory;
4. dependency and redundancy analysis;
5. semantic / structural / mechanical / implementation classification;
6. failure-boundary taxonomy;
7. carrier-archetype candidates;
8. non-claims and forbidden shortcuts;
9. explicit statement that no implementation is authorized.

## 9. Judgment criteria for the charter itself

This charter succeeds if it prevents the main failure mode:

```text
MemPalace lacks X
        ↓
therefore X must be added to a carrier
        ↓
therefore a modified carrier passes
        ↓
therefore Information Space Foundation is validated
```

Instead, it forces:

```text
MemPalace lacks X
        ↓
derive whether X is frozen semantic, PRQ-bounded, general IS semantic,
or probe-local
        ↓
study the minimal primitive only where derivation supports it
        ↓
Human ruling before implementation
```

## 10. Non-claims

This charter does not claim that:

1. a minimal carrier layer exists;
2. the candidate primitive set is sufficient;
3. MemPalace can or cannot be revised into a valid carrier;
4. a composite carrier is desirable;
5. Information Space is necessary for every Execution State;
6. implementation or experiment is authorized;
7. Frozen Contracts authorize a carrier schema.

## 11. Next gate

Human review of this charter.

```text
ACCEPT        → execute the A4 conceptual study according to CGQ-1..CGQ-5
FINDINGS      → revise scope without implementation
REJECT/PAUSE  → close or pause A4 by explicit ruling
```
