# PALACE / Information Space Foundation — Route Opening Charter

Date: 2026-10-05
Active route: `PALACE / INFORMATION SPACE FOUNDATION`
Decision record: `PALACE_INFORMATION_SPACE_FOUNDATION_ROUTE_DECISION_20261005.md`
Accepted Gate baseline: `ab97244`
Charter repository state: `f4e2ba6`, clean and synced
Status: `PHASE 1 ACCEPTED / CLOSED BY HUMAN REVIEW`
Scope: `STUDY ONLY · NO IMPLEMENTATION · NO CARRIER SELECTION · NO BACKEND INTEGRATION · NO CONTRACT CHANGE · NO EXPERIMENT`

## 1. Purpose

This charter opens, but does not execute, the PALACE / Information Space
Foundation route. It asks whether an Information Space foundation can supply
what the frozen ES↔IS contracts require for continued operation, without
becoming a hidden Execution State, semantic oracle, database product, MCP
server, or application integration.

Central question:

> Can Information Space become the evolvable information foundation on which
> Execution State depends for continued operation?

This charter does not answer that question. It defines the boundary, the minimal
carrier/interface obligations, and the first decodable question by which a
future phase could test it.

## 2. Historical reconciliation

Old PALACE material is treated as historical evidence and cautionary context.
It is not silently inherited as support for this route.

| Historical line | What it was | Current-route treatment |
|---|---|---|
| P6 Architecture Synthesis Palace interface | A future-interface sketch: Palace as past-oriented evidence/relation workspace; ES as future-oriented relation closure; connection by identity/reference, not content copying or shared schema. | Historical caution. Its identity/reference separation is useful, but it is not adopted as a contract. |
| Palace V2 “Real-World Information Workspace” direction | A prior route beginning from mature open-source memory systems and a real personal-work corpus. | Historical material. No backend, corpus, or candidate system is selected now. |
| Palace V2 G0 backend survey | Survey/observations involving MemPalace, Mem0, Graphiti, and related systems. | Historical evidence only. It does not carry forward as a current carrier selection or compatibility verdict. |
| Palace V2 G1–G3 real-corpus work | Observations about ingestion, validity, cross-document work, recovery cost, and Palace/SimiGo boundaries. | Useful cautionary material, but bounded to those fixtures/tools and not generalized here. |
| MemPalace V0 / MCP real-work experiments | Product-shaped explorations of a concrete tool and integration path. | Explicitly excluded from the current meaning of PALACE. No MCP path is authorized. |
| Later “PALACE CLOSED” state | The old Palace line was closed after R3 and no next route auto-opened. | The old line remains historically closed. This is a newly named Foundation route, not a silent V2 resumption. |
| ES↔IS Conceptual Specification v0.1 | Explicitly deferred Palace until the Information concept stood. | That condition has now been met; this charter is the deferred boundary study, not a contract change. |

Reconciliation rule: old Palace conclusions may be cited only as history or
caution. They may not be cited as proof that this Foundation route can succeed.

## 3. Semantic boundary

In this route:

```text
PALACE / Information Space Foundation
≠ MCP server
≠ knowledge base product
≠ database schema
≠ storage product
≠ application integration
≠ Execution State
≠ semantic search layer
≠ hidden model memory
```

Working distinction:

```text
Information Space
  = the semantic environment formed by persistent, addressable, evolving
    information items, identities, references, lineage, provenance, and
    mutation history

Execution State
  = the runtime object needed to continue a specified execution

PALACE / Foundation candidate
  = a possible carrier/organizer for the Information Space, not the
    Information Space concept itself and not an Execution State carrier
```

The current phase selects no concrete carrier. It only asks what minimal
capabilities such a foundation must expose.

## 4. Frozen-source obligations

The Frozen Contracts are not modified. The following obligations are read from
them as requirements that an Information Space foundation would need to satisfy.

### 4.1 From I-1 Persistence / Resolve

| Frozen semantic | Required Information Space obligation | Minimal interface obligation |
|---|---|---|
| Information items are use-time pinned by content identity | Preserve immutable bytes and return stable content identities | `put_blob(bytes) → digest`; `get_blob(digest) → bytes / MISSING` |
| CR has identity-bearing fields: result, used, surface, continues | Preserve canonical CR records without silent mutation | `put_node(node_id, canonical_record)`; `get_node(node_id)` |
| `used`, `surface`, and `continues` are distinct semantic edges | Preserve typed references, not flattened text | `put_edge(from, edge_type, to)`; `get_edges(node_id, edge_type?)` |
| Provenance is outside the CR identity hash | Store provenance separately from identity-bearing payload | `put_provenance(node_id, provenance)`; `get_provenance(node_id)` |
| Resolve must detect missing or changed pinned referents | Make missing/mismatching content deterministically observable | Missing result for absent digest; caller compares retrieved bytes with pinned digest |
| Lineage must remain traversable and acyclic | Expose complete parent/continues references; do not hide or rewrite them | `get_edges(node_id, "continues")` and deterministic node retrieval |
| Information may evolve without destroying historical pins | Preserve old identities while allowing new/current identities and mutation records | append-only mutation/event records; historical digests remain retrievable |

### 4.2 From I-1c Instantiate Completeness

| Frozen semantic | Required Information Space obligation | Explicit non-obligation |
|---|---|---|
| R2 = surface + re-materialized used items + lineage context | Retrieve all referenced pieces in a form from which R2 can be assembled | Do not materialize model state or execute the task |
| τ2 is externally supplied | Do not infer, recommend, or complete the future task from stored information | No task suggestion / semantic planning |
| Binding needs predecessor and declared weights identities | Preserve predecessor provenance as retrievable metadata | Do not decide BOUND / UNBOUND / MISMATCH |
| Missing information may be a binding-decidability input | Preserve absence explicitly; do not invent a missing referent | No hidden completion |
| Envelope, tokenizer, and substrate belong to execution | Do not store or interpret them as Information Space obligations | No model/runtime configuration ownership |
| Completeness outside the declared dependency relation remains open | Do not claim semantic completeness | No universal Information Space sufficiency claim |

### 4.3 From I-1d Runtime Realization / Verification

| Frozen semantic | Required Information Space obligation | Boundary |
|---|---|---|
| Used-item identities are directly recorded in IR | Expose exact identities for downstream records | No inferred identity normalization |
| Verification and disposition records must remain auditable | Preserve evidence records and their provenance | No evaluation of whether evidence is “good” |
| COVENANTED is not VERIFIED | Preserve claim strength as data | Do not upgrade uncertainty into verification |
| No semantic judgment enters the Verification Surface | Interface operations remain mechanical | No semantic search/ranking requirement is implied |
| Failure signatures must not be silently reclassified | Preserve original evidence and event order | Append-only audit history preferred |

## 5. Minimal Carrier / Interface Obligation

The candidate foundation must be capable of exposing the following abstract
operations. This is an interface-ownership list, not an API design and not an
implementation specification.

### IS-MCI-01 Immutable content

```text
put_blob(bytes)       → content_digest
get_blob(digest)      → bytes / MISSING
```

Obligation: byte persistence, stable digest identity, deterministic missing
result.

### IS-MCI-02 Canonical records

```text
put_node(node_id, canonical_record)
get_node(node_id)     → canonical_record / MISSING
```

Obligation: records such as CR-like nodes can be addressed and retrieved without
silent mutation.

### IS-MCI-03 Typed references

```text
put_edge(from_id, edge_type, to_id)
get_edges(node_id, edge_type?)
```

Obligation: preserve at least `used`, `surface`, and `continues` distinctions.
No particular storage model is required.

### IS-MCI-04 Separated provenance

```text
put_provenance(node_id, provenance)
get_provenance(node_id)
```

Obligation: provenance can be stored without becoming part of identity.

### IS-MCI-05 Pinning and historical retrieval

```text
pin(node_id / digest, label)
resolve_pin(label)    → node_id / digest
```

Obligation: current pointers may evolve, but old pinned identities remain
retrievable.

### IS-MCI-06 Evolution events

```text
put_mutation_event(target, prior_ref, new_ref, event_kind)
get_mutation_events(target)
```

Obligation: changes to current Information are explicit and auditable. Historical
versions are not silently overwritten.

### IS-MCI-07 Traversable lineage

Obligation: all `continues` and `used` references are retrievable with enough
fidelity for the caller to traverse lineage and detect missing referents.

### IS-MCI-08 Mechanical failure discipline

Obligation: absent, malformed, or hash-mismatched referents are explicit errors
or MISSING results. The carrier must not infer, repair, summarize, or silently
substitute.

## 6. Explicit non-obligations

The minimal carrier does **not** need to provide, in this phase:

1. vector search, embeddings, semantic ranking, or natural-language retrieval;
2. a graph database, relational database, document store, object store, or file format;
3. an MCP server, daemon, RPC service, or product UI;
4. concurrent multi-agent transaction semantics;
5. authentication, authorization, sharing, or encryption;
6. a Palace schema;
7. model weights, KV cache, tokenizer state, substrate, or backend binding;
8. task selection, continuation planning, or semantic completeness;
9. a claim that Information is necessary for all Execution States;
10. a proof that PALACE can implement the Information Space.

These may become later research questions, but they are not obligations created
by this charter.

## 7. First decodable research question

### PRQ-ISF-01

> Can a candidate Information Space carrier satisfying IS-MCI-01..08 preserve a
> registered ES↔IS continuation graph under bounded information evolution, so
> that pinned identities remain retrievable, lineage remains explicit, mutations
> remain auditable, and `resolve(CR_ref)` either produces a clean R2 or an exact
> frozen I-1 failure state—without semantic inference, hidden completion, or
> Frozen Contract modification?

This question is not authorized for execution by this charter. It is preregistered
as the first question the route must make decodable.

## 8. Judgment criteria for PRQ-ISF-01

### Success

A bounded test would be `SUCCESS` only if all of the following hold:

1. every registered content blob, canonical record, typed edge, provenance
   record, and pin is retrievable without silent mutation;
2. recomputation of CR identity matches the stored CR reference;
3. all `used`, `surface`, and `continues` references remain explicit and
   complete;
4. lineage traversal finds no missing required referent and no cycle;
5. after a registered Information mutation:
   - old pinned identities remain unchanged and retrievable;
   - new identities are distinct;
   - mutation events expose the prior/new relationship;
6. `resolve(CR_ref)` returns either clean `RESOLVED` with R2 or an exact frozen
   I-1 failure state;
7. no semantic inference, hidden completion, natural-language repair, or
   Frozen Contract modification is needed.

### Failure

A route-level `FAILURE` signal would be registered if any of the following is
the only available outcome:

1. the minimal obligations cannot be satisfied without turning the carrier into
   an Execution State carrier, semantic oracle, MCP product, or hidden memory;
2. pinned content or lineage is silently changed, lost, normalized, or
   substituted;
3. provenance cannot be kept outside identity;
4. assembling R2 requires semantic inference or task invention;
5. missing or mutated referents cannot be observed mechanically;
6. the carrier requires modifying a Frozen Contract to preserve ES↔IS semantics.

### Indeterminate

`INDETERMINATE` is required when:

1. failures are confounded by harness defects rather than carrier obligations;
2. only an unregistered mutation class was exercised;
3. behavior depends on undocumented carrier-specific semantics;
4. coverage is insufficient to distinguish carrier failure from test failure;
5. results pass mechanically but claim strength cannot be recorded without
   violating the COVENANTED / VERIFIED / FAILED discipline.

## 9. Route-opening non-claims

This charter does not claim that:

1. PALACE can implement the Information Space;
2. Information Space is necessary for every Execution State;
3. the ES↔IS loop has been externally reproduced;
4. a concrete storage system, database, graph store, MCP server, or product should be selected;
5. old Palace V2 results support this route;
6. R2 is a complete Execution State;
7. R2 plus τ2★ plus substrate is empirically sufficient outside the registered I-1c boundary;
8. current G-3 document-form evidence generalizes to production systems;
9. implementation is authorized;
10. Frozen Contracts authorize a Palace schema or carrier.

## 10. Completion criteria for Phase 1

Phase 1 is complete when a Human reviewer can determine from this charter:

1. what old Palace material is excluded;
2. what “PALACE / Information Space Foundation” means now;
3. which frozen ES↔IS semantics create obligations for the candidate foundation;
4. which abstract capabilities are minimal obligations;
5. which capabilities are explicitly not required;
6. what the first decodable question is;
7. what success, failure, and indeterminate mean;
8. why no implementation is yet authorized.

## 11. Human review and next gate

Human review on 2026-10-05:

```text
Phase 1 = ACCEPTED / CLOSED
Delivery = e4c74bd
Route baseline = f4e2ba6
Gate baseline = ab97244
Frozen Contracts = UNCHANGED
Next phase = PRQ-ISF-01 — Minimal Decodable Probe Design
```

The next phase is design-only. No implementation, carrier selection, backend
integration, experiment execution, or Frozen Contract change follows
automatically.
