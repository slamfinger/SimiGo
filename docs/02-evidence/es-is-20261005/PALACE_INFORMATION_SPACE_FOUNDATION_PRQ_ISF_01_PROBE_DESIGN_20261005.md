# PRQ-ISF-01 — Minimal Decodable Probe Design

Date: 2026-10-05  
Active route: `PALACE / INFORMATION SPACE FOUNDATION`  
Phase: `2 — MINIMAL DECODABLE PROBE DESIGN`  
Design status: `DELIVERED / AWAITING HUMAN REVIEW`  
Execution status: `NOT AUTHORIZED`  
Baseline: `ab97244`  
Prior accepted charter: `e4c74bd`  
Scope: `DESIGN ONLY · NO IMPLEMENTATION · NO CARRIER SELECTION · NO BACKEND INTEGRATION · NO CONTRACT CHANGE · NO EXPERIMENT EXECUTION`

## 1. Design question

The design answers only:

> What is the smallest mechanically decodable probe that can test whether
> obligations `IS-MCI-01..08` are sufficient to support `PRQ-ISF-01`, without
> introducing a semantic oracle?

It does not select or describe a concrete PALACE architecture. It does not choose
files, databases, graphs, MCP, RPC, or any carrier technology. It does not
modify the ES↔IS Frozen Contracts.

## 2. Separation of roles

```text
Registered Fixture
        ↓
Abstract IS Port   (IS-MCI-01..08 operations only)
        ↓
Mechanical Decoder
        ↓
Canonical Continuation Graph
        ↓
Frozen I-1 resolve semantics
        ↓
R2 or exact frozen I-1 failure state
        ↓
Scenario Judge
        ↓
SUCCESS / FAILURE / INDETERMINATE
```

### 2.1 Registered fixture

The fixture is a symbolic registration of information items, references,
provenance, pins, and mutation events. It contains no model, backend, or carrier
implementation.

### 2.2 Abstract IS Port

The carrier under test is observable only through the abstract operations already
named by `IS-MCI-01..08`:

```text
put_blob / get_blob
put_node / get_node
put_edge / get_edges
put_provenance / get_provenance
pin / resolve_pin
put_mutation_event / get_mutation_events
```

These are behavioral obligations, not API designs. No storage technology is
implied.

### 2.3 Mechanical decoder

The decoder may only use the abstract IS Port. It may check presence, equality,
digests, record fields, edge types, pins, event fields, and graph reachability.
It must not infer missing content, complete an absent edge, explain semantic
meaning, summarize, repair, rank, or call any semantic-search facility.

### 2.4 Frozen resolver authority

After a successful decode, the canonical continuation graph is evaluated by the
already frozen I-1 `resolve(CR_ref)` semantics. The probe introduces no new
resolver semantics, no new failure signature, and no new verdict tier.

### 2.5 Judge

The judge compares observed behavior with the preregistered expected behavior for
each scenario. It never uses semantic judgment to rescue a failed decode.

## 3. Minimal fixture

The fixture uses two CR-like nodes and enough content items to exercise result,
used, surface, and continues edges.

### 3.1 Content blobs

```text
B-ROOT-RESULT      bytes for the root result
B-ROOT-SURFACE     bytes for the root continuation surface
B-CHILD-RESULT     bytes for the child result
B-CHILD-USED       bytes for the child's pinned used item
B-CHILD-SURFACE    bytes for the child continuation surface
B-CHILD-USED-V2    a distinct later version used only for the evolution case
```

Concrete byte values are intentionally unspecified. They may be any deterministic
symbolic bytes chosen in a later implementation commission.

### 3.2 Canonical records

```text
N-CR-ROOT
  result   → B-ROOT-RESULT
  used     = ∅
  surface  → B-ROOT-SURFACE
  continues = ROOT

N-CR-CHILD
  result   → B-CHILD-RESULT
  used     → B-CHILD-USED
  surface  → B-CHILD-SURFACE
  continues → N-CR-ROOT
```

The canonical CR identity is recomputed using the frozen I-1 rule. The probe does
not define a new identity rule.

### 3.3 Typed edges

The fixture must preserve the edge-type distinctions:

```text
result
used
surface
continues
```

Flattening these into one undirected or untyped link is a decoder failure.

### 3.4 Separated provenance

Each node carries separately stored provenance, for example symbolic actor,
segment, and weights-identity fields. Provenance is not part of the canonical CR
identity hash.

### 3.5 Pins

```text
pin/continuation/current   → N-CR-CHILD
pin/item/current           → B-CHILD-USED
pin/item/audit-v1          → B-CHILD-USED
```

### 3.6 Evolution event

After the baseline registration, the fixture registers:

```text
B-CHILD-USED-V2
mutation event:
  target      = pin/item/current
  prior_ref   = B-CHILD-USED
  new_ref     = B-CHILD-USED-V2
  event_kind  = VERSION-SUCCESSION
```

`N-CR-CHILD` continues to pin `B-CHILD-USED`. The evolution changes the current
information pointer, not the historical continuation graph.

## 4. Decoder contract

The decoder produces a `CanonicalContinuationGraph` only if all checks pass.

### 4.1 Required checks

| Check | Mechanical rule | Forbidden rescue |
|---|---|---|
| Blob immutability | retrieved bytes hash to the registered digest | no alternate version substitution |
| Canonical record stability | retrieved record recomputes to its node identity | no field normalization or semantic repair |
| Typed-edge completeness | required result / used / surface / continues edges exist with exact types | no inference from names or text |
| Provenance separation | provenance changes do not alter CR identity | no provenance-derived completion |
| Pin stability | historical pins still resolve to their registered targets | no current-pointer replacement |
| Mutation explicitness | evolution is represented by an explicit event with prior and new refs | no inferred succession |
| Lineage traversal | `continues` references traverse to a root without missing node or cycle | no implicit ancestor reconstruction |
| Deterministic failure | absent, malformed, or mismatched data yields explicit MISSING / mismatch / frozen failure | no summarization or silent repair |

### 4.2 Decoder outputs

```text
CanonicalContinuationGraph:
  blobs        map<digest, bytes>
  nodes        map<node_id, canonical_record>
  edges        map<node_id, list<edge_type, to_id>>
  provenance   map<node_id, provenance>
  pins         map<label, target>
  events       list<mutation_event>

ProbeDecodeReport:
  graph             CanonicalContinuationGraph / none
  checks            list<check_id, PASS | FAIL, observed, expected>
  used_operations   set<IS-MCI operation>
  semantic_oracle_used = false
  decode_state      OK | FAIL
  failure_reasons   list<registered_code>
```

If `decode_state = FAIL`, the probe does not call resolver semantics and does not
attempt repair.

## 5. Frozen resolve handoff

For `decode_state = OK`, the decoder passes only the canonical graph and the
registered `CR_ref` to the frozen I-1 resolver semantics:

```text
resolve(CR_ref)
```

Allowed outcomes are exactly:

```text
RESOLVED                       with R2
RESOLVED-WITH-VIOLATIONS       with R2 plus registered V-1..V-5 violations
UNRESOLVABLE                   with registered frozen failure state
```

The probe does not create a fourth outcome and does not reinterpret
`COVENANTED`, `VERIFIED`, or `FAILED`.

## 6. Scenario matrix

Each scenario has one preregistered expected result. A scenario passes when actual
behavior equals that expectation without semantic rescue.

| ID | Scenario | Operation focus | Expected behavior | PRQ signal |
|---|---|---|---|---|
| SC-00 | Baseline integrity | IS-MCI-01..07 | decode OK; `resolve(N-CR-CHILD)` = clean `RESOLVED`; R2 contains child surface, used bytes, and lineage to root | supports PRQ |
| SC-01 | Required blob mutation | IS-MCI-01 / 08 | retrieved bytes fail digest equality; frozen resolver reports content mismatch / `I-MISMATCH` family | supports failure discipline |
| SC-02 | Required blob missing | IS-MCI-01 / 07 / 08 | `get_blob` = MISSING; decoder does not substitute; frozen resolver reports missing used referent / `I-NF` family | supports failure discipline |
| SC-03 | Canonical record mutation | IS-MCI-02 / 08 | canonical record changes while node ID remains; recomputed identity mismatches; frozen resolver reports `CR-ID-MISMATCH` | supports failure discipline |
| SC-04 | Canonical record missing | IS-MCI-02 / 07 / 08 | `get_node` = MISSING; decoder does not reconstruct the record; frozen resolver reports the registered missing-reference family | supports failure discipline |
| SC-05 | Required edge dropped | IS-MCI-03 / 07 / 08 | required `used`, `surface`, or `continues` edge is absent; decoder reports incomplete graph; no content reconstruction | supports failure discipline |
| SC-06 | Edge types flattened | IS-MCI-03 | links exist but `used` / `surface` / `continues` cannot be distinguished; decoder fails before resolve | carrier fails obligation |
| SC-07 | Provenance separation | IS-MCI-04 | either a registered provenance revision is exposed without changing CR identity, or immutable provenance-v2 is stored as a separate auditable record; clean resolve outcome is unchanged | supports separation |
| SC-08 | Historical pin retrieval | IS-MCI-05 / 06 | after `B-CHILD-USED-V2` succession, old `B-CHILD-USED` remains retrievable; CR still uses old version; event exposes prior/new refs | supports evolution |
| SC-09 | Historical pin lost | IS-MCI-05 / 08 | old pinned digest becomes unavailable after succession; probe fails historical-retention obligation | route failure signal |
| SC-10 | Lineage cycle | IS-MCI-07 / 08 | if a `continues` cycle is registrable, traversal/frozen resolver reports the `A-CYCLE` family; if the carrier explicitly rejects the cycle at registration with a deterministic failure, that also satisfies the obligation | supports failure discipline |
| SC-11 | Optional information absent | IS-MCI-08 | non-pinned interpretive information is absent; required graph still resolves; decoder must not infer the optional material | supports no-oracle rule |
| SC-12 | Required gap with tempting summary | IS-MCI-08 | a required used blob is absent while a symbolic summary is present; decoder and resolver must still fail; summary is not accepted as content | supports no-oracle rule |

Mandatory route-level coverage is `SC-00..SC-12`. No additional scenario is needed
for minimal decodability.

## 7. Scenario judgment

For each scenario:

```text
CASE PASS
  actual behavior == preregistered expected behavior
  and semantic_oracle_used == false
  and no non-IS-MCI carrier operation is required
  and any failure uses the exact frozen I-1 failure family

CASE FAIL
  actual behavior != expected behavior
  or failure is silently repaired
  or success depends on semantic inference
  or a non-IS-MCI operation is required
```

## 8. PRQ-ISF-01 judgment

### 8.1 SUCCESS

`PRQ-ISF-01` may be judged `SUCCESS / REGISTERED-BOUNDED` only if:

1. `SC-00` passes with clean `RESOLVED`;
2. every negative scenario produces its exact registered frozen failure family;
3. evolution preserves historical pins and exposes explicit succession;
4. provenance mutation does not alter identity;
5. optional absence does not cause inference;
6. required absence is never repaired;
7. all cases pass without semantic oracle or non-IS-MCI operations.

This means the registered obligations were sufficient for the registered fixture
and mutation classes. It is bounded and does not prove universal PALACE viability.

### 8.2 FAILURE

`PRQ-ISF-01` must be judged `FAILURE` if any of the following is required to make
the probe pass:

1. semantic repair, summarization, ranking, or implicit reconstruction;
2. non-IS-MCI operations such as search, model inference, schema migration, or
   carrier-specific privileged access;
3. silent mutation, silent substitution, or loss of historical pins;
4. merging provenance into identity;
5. weakening or reclassifying a frozen I-1 failure;
6. modifying a Frozen Contract to accommodate the carrier.

### 8.3 INDETERMINATE

`PRQ-ISF-01` must be judged `INDETERMINATE` if:

1. a failure is caused by probe/harness defects rather than carrier obligations;
2. a carrier-specific behavior is needed to decide the result;
3. behavior varies across repeated deterministic reads;
4. the implementation accidentally exceeds the registered fixture or mutation
   classes;
5. coverage cannot distinguish carrier failure from decoder failure.

## 9. What is registered, modified, preserved, and failed

### Registered

```text
content blobs
canonical CR-like records
typed result / used / surface / continues edges
separated provenance
continuation pin
historical content pin
version-succession mutation event
```

### Modified

Only the registered current information pointer may evolve:

```text
B-CHILD-USED → B-CHILD-USED-V2
```

The historical CR graph remains pinned to `B-CHILD-USED`.

### Preserved

```text
CR identity
pinned historical bytes
typed edge distinctions
lineage path
separated provenance
mutation event
frozen failure semantics
```

### Must fail

The probe must fail mechanically, without semantic rescue, when:

```text
pinned bytes are missing
pinned bytes mutate under the same identity
canonical record no longer matches its identity
required edge is missing or untyped
lineage is missing or cyclic
historical pin is lost
required gap is offered only as a semantic summary
```

## 10. Non-claims

This design does not claim that:

1. PALACE, MCP, a database, graph store, file system, or any product can satisfy
   the obligations;
2. Information Space is necessary for every Execution State;
3. the probe proves universal Information Space sufficiency;
4. `SUCCESS` would generalize beyond the registered fixture and mutation
   classes;
5. R2 is a complete Execution State;
6. implementation or execution is authorized;
7. Frozen Contracts authorize a Palace schema or carrier.

## 11. Implementation gate

This design authorizes no execution. A future implementation commission would
need to separately authorize:

```text
concrete symbolic fixture values
an abstract-port adapter for one candidate carrier
a decoder implementation
a judge implementation
execution of SC-00..SC-12
persisting raw probe evidence
```

Until then, this document is the route's design authority for `PRQ-ISF-01`.
