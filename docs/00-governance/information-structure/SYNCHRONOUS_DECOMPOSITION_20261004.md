# Information Structure Synchronous Decomposition

Date: 2026-10-04  
Status: `STATIC SYNCHRONOUS DECOMPOSITION COMPLETE / ANALYTIC LEAVES REACHED / EXPERIMENTAL IRREDUCIBILITY OPEN`

## 1. Operation

This is a breadth-first pass over all 32 rows in the Information Structure
Coverage Matrix. No row was allowed to enter a deeper child layer until it had
the same eight mandatory facets and the same discriminator set.

```text
Layer 0: 32 inventory rows;
Layer 1: 32 × 8 mandatory facets;
Layer 2: currently distinguishable semantic atoms per facet;
Layer 3: deletion / substitution / derivation / merge discriminators per atom.
```

## 2. Static stop

The pass stopped at **static analytic leaves**: distinguishable semantic atoms
whose next split would require a new observation, intervention, or registered
distinction not currently present in the repository.

This is not an irreducibility claim. According to the registered reduction
discipline, an atom may become candidate-irreducible only after competing
recovery paths are tested or explicitly registered as required.

## 3. Counts

```text
objects                              = 32
mandatory facets per object          = 8
facet cells                          = 256
static semantic atoms                = 846
static leaves                         = 846
experimental irreducibility claims    = 0
```

## 4. Mandatory facets

- **carrier_form** — Carrier / representation form: In what symbolic, encoded, stored, or delivered form does this object exist?
- **identity_scope** — Identity / scope: What makes this the same object, fact, observation, or scope rather than another?
- **semantic_content** — Semantic content atoms: Which independently distinguishable semantic components currently compose the object?
- **relation_dependency** — Relation / dependency: How does this object derive from, compose with, constrain, or depend on other structures?
- **access_delivery** — Access / delivery: How can this object be located, retrieved, withheld, or delivered to a fresh Execution?
- **interpretation_adoption** — Interpretation / adoption: What must be reconstructed or adopted for the object to enter reasoning?
- **effect_continuation** — Effect / continuation: What observable decision, behavior, or continuation relation can this object affect?
- **provenance_validity** — Provenance / validity: What producer, source, time, integrity, or staleness boundary governs this object?

## 5. Per-object completion

| Object | Layer | Name | Facets | Atoms | Coverage |
|---|---|---|---:|---:|---|
| `A00` | AXIS | Residue | 8 | 28 | OBSERVED/FIXED |
| `A01` | AXIS | Representation | 8 | 27 | PARTIAL |
| `A02` | AXIS | Persistence unit | 8 | 27 | REGISTERED_ONLY |
| `A03` | AXIS | Identity | 8 | 28 | REGISTERED_ONLY |
| `A04` | AXIS | Locator / selection | 8 | 28 | REGISTERED_ONLY |
| `A05` | AXIS | Retrieval | 8 | 27 | REGISTERED_ONLY |
| `A06` | AXIS | Semantic reconstruction | 8 | 27 | REGISTERED_ONLY |
| `A07` | AXIS | Task projection | 8 | 26 | PARTIAL |
| `A08` | AXIS | Adoption | 8 | 26 | PARTIAL |
| `A09` | AXIS | Behavioral effect | 8 | 26 | PARTIAL |
| `A10` | AXIS | Continuation | 8 | 27 | CONTROLLED |
| `U1` | UNIT | Exact raw residue | 8 | 32 | OBSERVED/FIXED |
| `U2` | UNIT | Decoded semantic register | 8 | 31 | STATIC_ONLY |
| `U3` | UNIT | Service baseline facts | 8 | 27 | PARTIAL |
| `U4` | UNIT | Pair compatibility facts | 8 | 26 | PARTIAL |
| `U5` | UNIT | Provenance / execution binding | 8 | 28 | EXCLUDED_UNTESTED |
| `M1.a` | M1 | Service-id set | 8 | 25 | OBSERVED/FIXED |
| `M1.b` | M1 | Baseline predicates | 8 | 26 | CONTROLLED |
| `M1.c` | M1 | Baseline issue statements | 8 | 27 | EXCLUDED_UNTESTED |
| `M1.d` | M1 | Source-file binding | 8 | 26 | EXCLUDED_UNTESTED |
| `M1.e` | M1 | Audit scope | 8 | 25 | OBSERVED/FIXED |
| `M2.a` | M2 | Pair-id set | 8 | 25 | OBSERVED/FIXED |
| `M2.b` | M2 | Pair compatibility decisions | 8 | 26 | PARTIAL |
| `M2.c` | M2 | Pair issue causes | 8 | 26 | EXCLUDED_UNTESTED |
| `M2.d` | M2 | Source / audit binding | 8 | 26 | EXCLUDED_UNTESTED |
| `M3.a` | M3 | Execution A run identity | 8 | 25 | EXCLUDED_UNTESTED |
| `M3.b` | M3 | Producer / backend binding | 8 | 25 | EXCLUDED_UNTESTED |
| `M3.c` | M3 | Task-carrier binding | 8 | 24 | EXCLUDED_UNTESTED |
| `M3.d` | M3 | Source-set binding | 8 | 24 | EXCLUDED_UNTESTED |
| `M3.e` | M3 | Result binding | 8 | 24 | EXCLUDED_UNTESTED |
| `M3.f` | M3 | Tool evidence | 8 | 26 | EXCLUDED_UNTESTED |
| `M3.g` | M3 | Temporal / Runtime evidence | 8 | 25 | EXCLUDED_UNTESTED |

## 6. Irreducibility boundary

Every atom is marked `OPEN_EXPERIMENT_REQUIRED`. The four discriminators are:

```text
1. counterfactual deletion;
2. representation substitution;
3. derivation from remaining structures;
4. merge/reclassification as another row or use-time relation.
```

Only after these competing recoveries are excluded, within the tested task,
backend, representation, and recovery scope, may an atom be called
provisionally irreducible.

## 6.1 Horizontal overlap pass

After decomposition, exact `facet + label` pairs were compared across objects.

```text
unique exact facet/label pairs       = 788;
total atom instances                 = 846;
repeated exact facet/label groups    = 13;
instances in repeated groups         = 58;
automatic merges                     = 0.
```

Most repetitions are the eleven axis-level carrier/boundary/identity templates.
The remainder are content labels such as producer identity, service-id
membership, source hashes, and tool evidence. Surface repetition is only a merge
candidate: the same label in a different object or scope is not proof of semantic
duplication. No atom was collapsed in this pass.

## 7. Execution boundary

```text
runtime probes        = NOT EXECUTED;
Observer              = NOT RUN;
InformationCore store = NOT RUN;
schema/API change     = NOT MADE;
new claims            = STATIC ONLY.
```
