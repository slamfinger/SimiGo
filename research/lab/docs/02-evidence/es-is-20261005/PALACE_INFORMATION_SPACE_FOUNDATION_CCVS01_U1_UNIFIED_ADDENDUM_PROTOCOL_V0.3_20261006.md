# CCVS-01 Unified Addendum Protocol — UA v0.3

> **Status:** PROPOSED / AWAITING TARGETED CONFORMANCE REVIEW, THEN HUMAN FREEZE GATE
> **Date:** 2026-10-06
> **Revision lineage:** v0.1 (PROPOSED) → ruling B = REVISE (tightened:
> Unified Carrier Contract over existing semantics) → **v0.2** → Conformance
> Review (REVISE, R-1..R-11, zero BLOCK) → ruling **B = REVISE + CC-MA
> mandate** (`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_REVIEW_RULING_AND_CCMA_MANDATE_20261006.md`)
> → **v0.3 (this document)**.
> **Authorization basis:** Unified direction ruling; U-1 revision ruling;
> review ruling and CC-MA mandate.
> **Relationship to CCVS-01-PB v1.2:** ADDITIVE ONLY (unchanged).
> **U-2 remains NOT AUTHORIZED.**

## 0. What changed from v0.2 (revision summary)

```text
FIXED R-1   §5 deletion wording: deleting a raw session event is
            authoritative CARRIER-CONTENT loss (record, formation basis,
            mapping content reference); already-formed Informations
            persist (A1). Protects the frozen immutability semantics.
FIXED R-2   §8: "Session Information Record streams" → "SESSION-family
            CarrierRecord streams" (last v0.1 terminology residue).
FIXED R-3   CC-1: field renamed to carrier_provenance with an explicit
            two-layer distinction (ruling B.2): Information.Provenance
            (frozen A3) vs carrier-operation / carrier-production
            provenance. Never one field, never one semantic.
FIXED R-4   CC-2: relationship to CCS-C8 stated (capabilities underlie
            the C8 interface obligations; C8 remains the interface
            authority).
FIXED R-5   CC-1/CC-8: carrier-identity minting marked as a U-2
            composition-manifest obligation, mechanism-side (A-1
            disposition; the rule itself is NOT decided here).
FIXED R-6   CC-5: mapping cardinality stated N:M by default, flagged
            for Human confirmation at freeze (A-2 disposition).
FIXED R-7   CC-4: "inherited A1 semantic" → "A1 adapter atomic-MOVE
            semantic (Phase C kickoff manifest)" (ruling-vs-adapter
            ambiguity removed).
FIXED R-8   CC-8 #1 reworded per ruling B.3: identity formation input
            (mechanism-side; digest MAY participate) is now explicitly
            distinguished from the identity stability rule (an existing
            identity never drifts due to path/name/carrier/revision
            changes).
FIXED R-9   CC-3: FILE-family record kinds registered as an open
            SimiGo-side decision input (A-3 disposition; carrier stays
            opaque meanwhile).
FIXED R-10  CC-8: Representation Identity made an explicit identity
            relation (row #7), per IS-IDLOC-SEAM-01; Historical Pin
            noted as PB v1.2-governed via UA-P3.
FIXED R-11  §2: pinning sentence added — "File Information / Session
            Information" are workload-family labels (ruling vocabulary),
            never model-level class names.

NEW  CC-MA  Multi-Agent Carrier Consistency (§3A): MA-1..MA-10
            incorporating the Human's C1-C10 catalog verbatim; the
            concurrency design objects; one unified concurrency model
            across both families; Agent positioned as actor only;
            binding design scenario MA-DS-1 "Multi-Agent Research Day";
            additive correctness bounds I19-I25; CC-MA mechanisms are
            mandatory U-2 composition-manifest check items. Honest
            capability status of the current preconstruction recorded.

DISPOSITIONS A-1 deferred to U-2 manifest (explicitly NOT decided here);
             A-2 N:M default adopted and flagged for Human confirmation;
             A-3 registered as open SimiGo-side decision input.
UNCHANGED    everything else, including the four-layer structure, layer ①
             citations, raw/derived boundary content, verification
             re-labelling, compositions, parity reference, seam objects,
             phase gates, negative space.
```

## 1. Conflict and precedence rules

```text
UA-P1  PB v1.2 File-side rules, bounds, and delivered results stand
       unchanged. File-only metrics may be inherited from Baseline A
       runs without re-execution.
UA-P2  This addendum adds the Unified Carrier Contract (including
       CC-MA) and its verification layer. It adds no new semantic layer
       over Information/Relation.
UA-P3  Where a Unified run exercises File-side operations, frozen PB
       v1.2 rules apply as-is.
UA-P4  New identifiers use fresh numbering (UA-CC-*, UA-MA-*, PB-U*,
       G9+, I14+, F10+) and never redefine a PB v1.2 identifier.
UA-P5  Mid-run change discipline inherited.
UA-P6  Layer ① semantics are cited from their frozen artifacts, never
       re-specified here. If this addendum's text appears to redefine
       Information or Relation semantics, the frozen artifacts win and
       the addendum text is defective.
UA-P7  NEW. Multi-agent concurrency obligations (CC-MA) are database-
       run-correctness mechanisms at layers ②③④. They never define
       semantic objects. Agents are operating actors, never Information
       Space semantic objects. Layer ① writes already need no
       concurrency protocol beyond the frozen store contracts
       (idempotent, first-write-wins, immutable values); CC-MA governs
       carrier-layer objects: locator state, representation versioning,
       record sequence allocation, operation commits, index builds.
```

## 2. The four-layer structure (frozen principle)

```text
┌─────────────────────────────────────────────────────────────────┐
│ ① Information Space Semantic Layer — SimiGo EXISTING, unchanged │
│    Information / Relation / provenance / temporal semantics     │
│    (§4 cites the frozen artifacts)                              │
├─────────────────────────────────────────────────────────────────┤
│ ② Unified Carrier Layer — THE CURRENT CORE WORK                 │
│    Carrier contract (§3) + Multi-Agent Consistency (§3A)        │
│      ├─ File Carrier   (instance family FILE)                   │
│      └─ Session Carrier (instance family SESSION)               │
├─────────────────────────────────────────────────────────────────┤
│ ③ Carrier Representation / Record Layer                         │
│    FILE:    path / bytes / representation / segment ...         │
│    SESSION: event / sequence / summary / turn ...               │
│    Physical difference allowed; ONE Carrier Contract governs    │
│    both (§3); ONE concurrency model governs both (§3A)          │
├─────────────────────────────────────────────────────────────────┤
│ ④ Derived Access Layer                                          │
│    exact lookup / index / ranking / semantic retrieval          │
│    ALL derived; never defines Information (§3 CC-7)             │
└─────────────────────────────────────────────────────────────────┘
```

**Frozen principle (ruling-designated, most load-bearing):**

```text
File and Session are two instance families of Carrier,
NOT two semantic branches of Information Space.

Their differences stop at the Carrier layer and must not
leak upward into ①.

"Information does not care whether it came from a file or
a conversation."
```

**Pinning sentence (R-11):** the terms "File Information" and "Session
Information" — used in the direction ruling and the archived proposal —
are workload-family labels only. At the model level there is exactly one
`Information` semantic object; there are no File-Information and
Session-Information classes.

What "Unified File + Session" solves is not schema merging: it is one
Carrier abstraction that presents different classes of real information
sources to the Information Space in the same way — including under
concurrent multi-agent operation (§3A).

## 3. UA-CC — Unified Carrier Contract

Logical contract only. DDL, physical layout, and APIs are U-2 decisions
under PB-F6-style composition manifests.

### CC-1 Carrier object

```text
Carrier
  carrier identity        opaque, stable, carrier-side; independent of
                          Information Identity. HOW a carrier identity
                          is minted (and, for the FILE family, what
                          makes it the same carrier across modify and
                          rename) is a U-2 COMPOSITION-MANIFEST
                          OBLIGATION, mechanism-side — mirroring the
                          A2′ pattern for InformationID. Not decided in
                          this contract. (A-1 disposition)
  carrier_kind            FILE | SESSION (extensible only by explicit
                          SimiGo-side decision; never by carrier
                          interpretation)
  locator / locator_state where the carrier's content physically lives
  representation          content reference + version / fingerprint
  capability surface      CC-2
  records                 CC-3 (ordered / locatable units)
  carrier_provenance      carrier-operation / carrier-production
                          provenance: who performed the carrier
                          operation, when, from which prior version.
                          DISTINCT FROM the frozen Information
                          .Provenance (A3), which remains the ONLY
                          provenance of formed Informations. Same
                          concern, different layers, never one field,
                          never one semantic. (R-3 / ruling B.2)

Instance families (examples of internal difference, not extra semantics):
  File Carrier    kind = FILE;    locator = filesystem path +
                  fingerprint; records = file representation units
  Session Carrier kind = SESSION; locator = session identity;
                  records = ordered session events
```

### CC-2 Common capability surface

Both instance families expose the same verbs to upper layers; internal
physical layout may differ freely:

```text
discover          find carriers / carrier records
locate            resolve carrier identity / record addressing
read              obtain representation bytes / record content
exact-retrieve    deterministic lookup by identity, coordinate,
                  number, sequence — never replaceable by ranking
enumerate         walk records in carrier-stable order
summarize         materialize derived summaries (④ outputs only)
reconstruct       rebuild derived views from authoritative content
```

Relationship to CCS-C8 (R-4): these capabilities UNDERLIE the C8
interface obligations (resolve / consume / produce / pin / continue);
CCS-C8 remains the authority on the SimiGo↔carrier interface. The two
vocabularies describe different levels and are both maintained.

### CC-3 CarrierRecord

```text
CarrierRecord
  record identity       carrier-internal, stable (CC-4)
  carrier_id            owning carrier
  record_kind           carrier-neutral work-record vocabulary from U-0
                        (RAW, DISCOVERY, JUDGMENT, EXCLUSION,
                        UNCERTAINTY, OPEN_QUESTION, NEXT_ACTION,
                        EVIDENCE_LINK, RESULT) — stored opaquely by the
                        carrier; extending the list is a SimiGo-side
                        decision, not a carrier one.
                        FILE-family record kinds are a REGISTERED OPEN
                        DECISION INPUT (the U-0 nine kinds are session-
                        work-flavored); until decided, FILE records use
                        opaque kinds chosen at implementation, with zero
                        semantic risk because the carrier never
                        interprets them. (R-9 / A-3 disposition)
  sequence/local_locator  stable addressing inside the carrier
  content_ref           where the record content lives
  metadata

FILE instance family records (illustrative): whole file / section /
paragraph / extracted representation.
SESSION instance family records (illustrative): event N / summary event.

CarrierRecord is a LOCATABILITY unit ("where, inside this carrier, this
content appears"). It is never an Information substitute. Deleting,
invalidating, or rebuilding a CarrierRecord never automatically equals
deleting an existing Information (ruling B.1; see §5).
```

### CC-4 Carrier-internal ordering stability

```text
Each instance family defines its stable internal addressing:
  SESSION: (SessionID, sequence) — append-only, never renumbered;
           survives restart, summary materialization, reindex, and
           derived-index rebuild.
  FILE:    representation/segment addressing stable under the
           representation's revision identity; locator transitions
           (MOVE) never change identity — the A1 adapter atomic-MOVE
           semantic (Phase C kickoff manifest). (R-7)

In both families: internal addressing is stable across restart,
reindex, summary materialization, and derived rebuild.
```

### CC-5 Information ↔ CarrierRecord mapping

```text
- The mapping is EXPLICIT and provenance-bearing (which record, in
  which carrier, at which version, carried which content that became
  which Information).
- Mapping cardinality is N:M BY DEFAULT: several records may carry one
  Information, and one record may relate to several formable contents.
  Any restriction is an explicit per-decision. This default is a
  carrier-layer rule, flagged for Human confirmation at freeze.
  (R-6 / A-2 disposition)
- EXISTENCE OF A RECORD NEVER CREATES INFORMATION. A CarrierRecord
  becomes Information only through the existing SimiGo formation
  semantics — identity formed at formation, minted mechanism-side,
  immutable value semantics (§4). Session events, turns, tool calls,
  summaries, and file sections/segments are Carrier-internal locatable
  content until SimiGo forms them into Information.
- WHEN session (or file) content becomes Information, and how it
  relates to existing Information, is decided by the EXISTING layer ①
  semantics — never by Session (or File) developing its own semantics.
- Corrections to a mapping are new mapping entries with provenance;
  history is never rewritten.
```

### CC-6 Relations are Information-to-Information only

```text
Relation semantics = existing RelationCore (§4): a Relation's endpoints
are InformationIDs; predicates are minimal opaque values; no relation
semantics is buried inside Carrier record metadata — otherwise File and
Session unification would re-fork the semantic layer, which this
addendum exists to prevent.

Cross-domain retrieval (X family) therefore operates at two levels:
  carrier-level: locate/enumerate across instance families — no
                 semantic judgment required (CC-2);
  information-level: resolve through the CC-5 mapping into Information,
                 where Relations apply.
```

### CC-7 Derived access layer

```text
exact lookup / index / ranking / semantic retrieval are DERIVED
structures:
  - every derived artifact traceable to an authoritative source via
    IndexSource (source information/representation, extraction version,
    extraction reference; source version/fingerprint recorded);
  - rebuild from authority is deterministic and verified by
    rebuild-compare (identity coverage AND searchable-content
    coverage — retiring the P8 F7 gap);
  - a derived artifact is freely deletable and rebuildable;
  - a derived artifact is NEVER a fact source or identity source, and
    Carrier reads must not present derived noise as facts (U-0
    wake-up-contamination obligation);
  - under concurrent multi-agent operation, index isolation follows
    MA-9 (§3A).
```

### CC-8 Identity relations

| # | Identity relation | Definition locus | Lifecycle / mutability boundary |
|---|---|---|---|
| 1 | Information Identity | EXISTING frozen semantics (§4) — opaque `InformationID`, formed at formation, minted mechanism-side | immutable. Formation input vs stability rule (R-8 / ruling B.3): formation inputs are mechanism-side (the registered first-implementation input = content + source + chunkIndex; a digest MAY participate in formation); the STABILITY RULE is that an EXISTING identity never changes due to path, name, carrier, or subsequent content/representation changes |
| 2 | Carrier Identity | THIS contract (CC-1) — opaque, carrier-side, stable | carrier identity stable for the carrier's life; locator/state mutable; content evolves via representations with versions/fingerprints; minting = U-2 manifest obligation (A-1) |
| 3 | CarrierRecord Identity | THIS contract (CC-3/CC-4) — carrier-internal, stable addressing | append-only within a session carrier; stable under representation revision for a file carrier; a record is never mutated into a different record |
| 4 | Information ↔ CarrierRecord mapping | THIS contract (CC-5) — explicit, provenance-bearing | append/annotate only; corrections = new entries; never rewritten |
| 5 | Information ↔ Information Relation | EXISTING frozen RelationCore semantics (§4) — endpoints are InformationIDs, immutable, first-write-wins | immutable; no carrier-side relation semantics |
| 6 | DerivedIndex ↔ source | THIS contract (CC-7) — IndexSource with version/fingerprint | freely deletable/rebuildable; never authoritative |
| 7 | Representation Identity | EXISTING registration IS-IDLOC-SEAM-01, made explicit here (R-10) — content-derived, carrier-side | each representation version is immutable once recorded; new revision ≠ new Information Identity ≠ new Carrier Identity; Historical Pin behavior remains PB v1.2-governed (UA-P3): a pin resolves to the exact prior representation |

The mandated ≠ chain holds at clause level: Information Identity ≠
Carrier Identity ≠ Representation Identity ≠ Physical Locator ≠
Record/Event Identity ≠ Derived Index Entry.

### CC-9 Hard constraints (ruling §5, binding)

```text
  - No parallel core Stores: no FileStore / SessionStore split of the
    core semantic layer. One Carrier contract, two instance families;
    per-family physical tables are implementation detail beneath the
    contract (U-2 manifests), never core semantic stores.
  - Session schema must not invade InformationCore: no session fields
    on Information or Relation.
  - CarrierRecord must not replace Information (CC-5).
  - DerivedIndex must not become a fact source or identity source
    (CC-7).
  - No MemPalace backend reopening because of this revision.
  - No PB v1.2 modification.
  - No U-2 implementation until this protocol passes Human Review.
```

## 3A. CC-MA — Multi-Agent Carrier Consistency

> **Positioning (ruling):** CC-MA is a DATABASE-DESIGN CONSTRAINT at
> layers ②③④ — a correctness obligation for the Unified Carrier under
> concurrent multi-agent operation. It is NOT a new Information Space
> semantic layer, NOT a new semantic object set, and NOT a separate
> concurrency database. Multi-agent parallel work (multiple Agents
> simultaneously reading, producing, modifying, and organizing the same
> Information Space) is a HIGH-FREQUENCY FUTURE SCENARIO and therefore a
> first-class constraint from the database design phase onward — not a
> later deployment concern.
>
> **Relationship to layer ① (ruling):** Phase 2 proved Information and
> Relation are independent semantic objects and the two Stores are
> parallel boundaries; concurrency control is built ON this existing
> boundary. Layer ① writes need no concurrency protocol beyond S1-S6 /
> R1-R6 (idempotent, first-write-wins, immutable values — there is no
> Information "update" to lose). CC-MA governs carrier-layer objects:
> locator state, representation versioning, record sequence allocation,
> operation commits, index builds. Database mechanisms may address
> identity/revision/transaction/operation/conflict/provenance/recovery —
> but never redefine Information, Relation, or Session.
>
> **Agent positioning (ruling):** an Agent is an OPERATING ACTOR, never
> a semantic object.
>
> ```text
> Agent ──operates on──> Carrier
> Agent ──produces─────> Representation / Event / Relation
> NOT     Agent ──is-a──> Information
> ```
>
> actor_id / actor_type / operation_id / timestamp fields belong to
> provenance / audit / concurrency control only. FORBIDDEN:
> AgentInformation, AgentRelation, Agent-specific Information semantics,
> AgentStore, File/Session semantic branches.

### MA-1..MA-10 — guaranteed capabilities (C1–C10 catalog, verbatim obligations)

```text
MA-1  Concurrent Read (= C1)
      Multiple Agents can concurrently read the same Information /
      Carrier / Representation without blocking each other from
      working.

MA-2  Concurrent Write (= C2)
      Multiple Agents can concurrently write new content or new
      versions to the same Carrier; a single global write lock must not
      serialize the whole Information Space.

MA-3  Lost-Update Prevention (= C3)
      Agent A reads version V1 and works; Agent B has meanwhile updated
      the same OBJECT (carrier version / representation revision /
      record sequence) to V2. On A's later commit the carrier:
        MUST detect the stale version;
        MUST NOT silently overwrite V2.
      Allowed outcomes ONLY: accept / merge / rebase (re-read) /
      conflict / retry. Blind overwrite is forbidden.

MA-4  Atomicity (= C4)
      Updates spanning related objects have an explicit atomic
      boundary, e.g.:
        new Representation + Carrier version + provenance
        + relation/reference
      No state may exist where the主体 has committed but
      provenance/reference is half-committed ("unexplainable state").

MA-5  Identity Stability under concurrency (= C5)
      Concurrent modification must never inadvertently change existing
      Information / Carrier identity because of: file rename, file
      move, representation revision, session append, re-index, summary
      materialization.
      SPECIFICALLY FORBIDDEN equivalences:
        path change   == new Information
        event append  == new Session identity
        index entry   == Information identity

MA-6  Session Ordering under concurrency (= C6)
      (SessionID, sequence) remains stable. When multiple Agents append
      to the same Session concurrently, the carrier must define:
        ordering authority; sequence allocation; duplicate prevention;
        retry/idempotency; failure recovery.
      Client timestamps must never be the ordering inference source.

MA-7  Idempotent Retry (= C7)
      After network failure, process crash, or unknown commit outcome,
      an Agent's retry must not produce duplicates of: Information,
      Representation, SessionEvent, Relation, provenance record.
      A stable operation/event identity (or equivalent mechanism) must
      exist.

MA-8  Provenance Under Concurrency (= C8)
      Every concurrently produced change must be able to answer:
        who / when / from which version / based on what representation
        / resulting version
      This belongs to provenance/history (carrier_provenance per CC-1)
      and must not change the existing semantic definition of
      Information.

MA-9  Derived Index Isolation (= C9)
      While authoritative data is updated concurrently:
        authoritative store -> derived index
      Index updates may lag, but must: never overwrite authoritative
      data; never become a fact source; be rebuildable from authority;
      make stale indexes DETECTABLE; never corrupt authority during
      concurrent rebuilds.

MA-10 Snapshot / Recovery (= C10)
      An Agent reading while another Agent modifies must obtain either
      a consistent snapshot or an explicit version view. A set of
      relations spanning different versions that forms a "seemingly
      legal but never-existed" mixed state must not be observable.
```

### Concurrency design objects (database-run-correctness mechanisms, NOT semantic objects)

The U-2 design must make the following concepts explicit. They are
run-correctness mechanisms of the carrier database, never Information
Space semantic objects:

```text
Object Version             Revision / Generation
Operation Identity         Write Intent
Commit / Transaction Boundary
Concurrency Conflict       Idempotency Key
Snapshot / Read Version    Index Build Version
```

Conceptually (per the ruling — one Carrier DB, no separate concurrency
layer):

```text
Information      (frozen semantics; no revision field added —
                  immutability + store idempotence already hold)
Representation   revision
Operation        operation_id, actor_id, base_revision
SessionEvent     event_id, sequence
Transaction      commit boundary
Index            source revision, build revision
```

### Unified concurrency model across both families (ruling §5)

```text
Avoid:  File -> "normal DB concurrency"
        Session -> special session lock system

Require: ONE Unified Carrier concurrency model over both
         instance families. Internal storage characteristics may
         differ, but identity / version / provenance / transaction /
         conflict / recovery / index invalidation-and-rebuild obey the
         SAME principles. No FileConcurrencyStore /
         SessionConcurrencyStore two-mechanism split.
```

### MA-DS-1 — binding design scenario: "Multi-Agent Research Day"

The real parallel scenario observed in this research round is adopted as
the FIRST binding DESIGN scenario (a design obligation for U-2 manifests
and validation design — explicitly NOT a completed concurrency
validation; ruling D):

```text
Agent A (actual research writer):
  create/update research file
  create session records
  derive judgment
  reference file revision

Agent B (Lab organizer):
  concurrently read existing lab material
  reorganize / rename / classify file
  update index / summary

Agent A:
  continue from earlier read
  encounter external revision
  attempt write

Database (carrier) must:
  detect version relation
  preserve both authoritative histories
  reject silent overwrite
  maintain identity/provenance
  rebuild derived index if required
```

MA-DS-1 must be able to verify (additive correctness bounds, I19–I25):

```text
I19  No lost update          (MA-3; stale detection + no blind overwrite)
I20  No identity duplication (MA-5; concurrency never mints a second
                             identity for the same object)
I21  No dangling provenance  (MA-4/MA-8; every committed operation has
                             complete provenance — no half-commit)
I22  No invalid cross-version relation (MA-10; no never-existed mixed
                             state)
I23  No session reorder under concurrency (MA-6)
I24  No duplicate retry effects (MA-7)
I25  No derived-index corruption under concurrent writes (MA-9)
```

These are correctness bounds in the PB v1.2 sense: a violation is a
protocol failure of the candidate, never a reason to relax a bound.
They are exercised through MA-DS-1 in U-2 manifest design and
validation; classification follows the PB v1.2 mechanism.

### Honest capability status of the current preconstruction (design basis, from the Human's assessment)

```text
Concurrent Read            basic support
Concurrent Write           Store/Runtime exist; no concurrency protocol
Lost-update prevention     GAP (no revision compare-and-swap / optimistic
                           concurrency)
Atomicity                  GAP (InformationSpaceRuntime deliberately does
                           not unify cross-component transaction
                           semantics — good component boundary, no
                           unified model)
Identity stability         good basis (move / revise / pin covered)
Session ordering           partial ((SessionID, sequence) direction only)
Idempotent retry           GAP (no operation identity / idempotency key)
Provenance                 partial (relation/history/provenance direction)
Derived-index isolation    good (DerivedSearchIndex + rebuild), needs
                           concurrent invalidation rules
Snapshot consistency       GAP (no snapshot/read-version contract)
Multi-agent conflict       no formal contract yet
resolution

Assessment boundary (honesty): this table reflects the Carrier-neutral
preconstruction; the CarrierSQLite adapter's local implementation was
NOT assessed for concurrency mechanisms and no claim is made either way.
Conclusion: architecture compatible, capability not yet fully covered —
which is precisely why CC-MA enters the contract NOW, before U-2.
```

### What CC-MA does not do

```text
  - does not define new Information semantics or redefine Information /
    Relation / Session;
  - does not model the Agent as a semantic entity (no AgentInformation /
    AgentRelation / AgentStore);
  - does not create a separate concurrency database layer (one Carrier
    DB, added concurrency-control fields/mechanisms only);
  - does not create two per-family concurrency mechanisms;
  - does not treat the observed real parallel scenario as a completed
    concurrency validation — it is MA-DS-1 design evidence;
  - does not modify PB v1.2 or any Frozen Contract.
```

## 4. Layer ① — existing semantics (cited, not redefined)

For precision, the frozen surfaces this contract builds ON (verified
against current source; cited here, not re-specified):

```text
InformationCore  (trackD-memory/Sources/InformationCore/)
  Information: opaque InformationID; immutable verbatim content;
  Provenance (producedAt/producedBy required; optional source/
  sourceTime/position/extractionMode); optional ContentDate pair
  (unknown stays unknown, never inferred) — rulings A1–A5; acceptance
  `6feac8c`. NO kind/title/summary/status fields (A5 negative space).
  InformationStore: store (idempotent, first-write-wins no-op) +
  fetch (Optional absence) — rulings B1–B3; contract S1–S6 FINALIZED
  (conflicting value = success no-op, existing stays authoritative).
  Identity formed AT FORMATION, minted mechanism-side; recipe outside
  the semantic API — ruling A2′.

RelationCore  (trackD-memory/Sources/RelationCore/)
  Relation: opaque RelationID; subject and object are InformationIDs;
  minimal opaque RelationPredicate; Provenance; immutable — rulings
  D1(a)/D2(a)/D3(a); RelationCore depends on InformationCore, never
  the reverse (D7(a)).
  RelationStore: store/fetch, first-write-wins — contract R1–R6
  FINALIZED.

Boundary authority:
  CCS-C8: the carrier resolves/consumes/produces/pins/continues as an
  INTERFACE obligation; semantic judgment stays with SimiGo.
  IS-IDLOC-SEAM-01: Information Identity ≠ Representation Identity ≠
  Physical Locator ≠ Historical Pin.
```

The Unified Carrier Contract (§3) and CC-MA (§3A) add layer ② and below.
They do not modify any of the above.

## 5. Raw / Derived boundary

```text
File side:    original file representation = authoritative;
              extracted text / FTS / embedding / summary = derived
Session side: raw session event = authoritative;
              normalization / summary / embedding / KG = derived

Consequences (mandatory):
  delete derived  -> MUST be rebuildable from authority (CC-7)
  delete raw session event -> AUTHORITATIVE CARRIER-CONTENT LOSS:
        the record, its formation basis, and the CC-5 mapping's
        content reference are destroyed; already-formed Informations
        PERSIST (A1 — deletion of a CarrierRecord never automatically
        equals deletion of an existing Information; ruling B.1);
        typed, visible, forbidden as a routine operation
  delete original file representation -> Representation loss (typed,
        availability semantics per PB v1.2)
```

## 6. Correctness and crash bounds — verification of the contract

Content carried from v0.1/v0.2, re-labelled as mechanical checks of the
Unified Carrier Contract and layer ① semantics:

```text
I14  ordering stability (SESSION family of CC-4)
I15  raw/derived separation enforced (CC-7 rebuild equivalence)
I16  IndexSource determinism (CC-7)
I17  cross-domain relation integrity (CC-6 + CC-5)
I18  historical judgment reviewability (CC-5 + CC-6)
I19  no lost update (MA-3)                    [new, §3A]
I20  no identity duplication (MA-5)           [new, §3A]
I21  no dangling provenance (MA-4/MA-8)       [new, §3A]
I22  no invalid cross-version relation (MA-10)[new, §3A]
I23  no session reorder under concurrency (MA-6) [new, §3A]
I24  no duplicate retry effects (MA-7)        [new, §3A]
I25  no derived-index corruption (MA-9)       [new, §3A]

G9   SESSION-family capability conformance (CC-2/CC-4)
G10  cross-family conformance (CC-2/CC-5/CC-6)
G11  historical judgment review end-to-end (CC-5/I18)
G12  unified restart/continue (CC-4 across both families)

F10  crash during session append burst    -> committed ordered prefix,
     no gaps, no reordering
F11  crash during cross-domain relation write -> all-or-nothing per edge
F12  crash during unified derived-index rebuild -> rebuild-from-authority
     (CC-7) or DETACHED
F13  crash during session summary materialization -> summary is
     derived: discardable/rebuildable; raw events intact
F14  crash at checkpoint/resume boundary  -> resume consistent with
     durable prefix

Verdict vocabulary inherited: PASS / REPAIR / DETACHED; FAIL forbidden.
I19–I25 are exercised via MA-DS-1 (§3A) in U-2 manifest design.
```

## 7. Workload families — verification of the contract

Unchanged from v0.2:

```text
S family (SESSION-carrier capability verification):
  S1 high-frequency append        S2 ordered timeline read
  S3 session exact search         S4 session lexical search
  S5 session semantic search (pluggable L3; N/A-with-reason if absent)
  S6 historical session retrieval S7 session index rebuild
  S8 session crash/recovery

F family: PB v1.2 WL1..WL7 unchanged; File-only metrics inherited from
  Baseline A / PV1 (no File-only re-run required).

X family (cross-family contract verification):
  X1 File → Session retrieval     X2 Session → File retrieval
  X3 Cross-session → file history X4 File revision → judgment history
  X5 File + Session mixed day     X6 interruption → restart → continue
  X7 derived index rebuild, both domains
  X8 historical judgment re-audit

Binding workload: WL6-U "Unified Research Day" (16 frozen steps) =
PRIMARY for the Unified addendum; WL6 remains the File-side binding
workload; binding-role discipline inherited.

Tiers: PB-F1 numbers inherited verbatim. Session record-kind
distribution and cross-domain linkage counts are fixture-generator
parameters under the frozen master-seed discipline.

MA-DS-1 (§3A) is a BINDING DESIGN SCENARIO, not a new workload family;
its exercise rides the existing families and U-2 manifest design.
```

## 8. Real-corpus diagnostic realism tier

Unchanged from v0.2 except R-2: primary binding = deterministic
synthetic fixtures (PB-F2 discipline). Mandatory diagnostic
(non-binding) tier: archive-organizer as File Information producer over
the registered real corpus; G1/G2/G3 + MemPalace real-carrier records
replayed as **SESSION-family CarrierRecord streams**. Real corpus never
enters synthetic fixtures; realism runs reported separately; a realism
failure is reportable evidence, not a bound violation.

## 9. Performance bounds (unchanged from v0.2)

PB-U1..PB-U11 starting UNCALIBRATED, calibrated by the first valid U-A
runs; D-A discipline (Q1 steady-state allocated-block footprint primary;
Q3 writeback traffic diagnostic only); PB v1.2 identities for File-side
metrics preserved.

## 10. Statistical protocol (unchanged from v0.2)

Inherited verbatim from PB v1.2 §3.5: per-run independent percentiles;
per-run observation minimums; median-of-valid-run percentiles; pooled
values as labelled diagnostics only; INVALID restricted to predefined
protocol/environment violations; quiescence = three consecutive 5 s
windows (admission only); serial cold-run policy.

## 11. Candidate compositions (re-stated with CC-MA)

```text
U-A  Unified Minimal (FIRST): evolution of Baseline A / A1 into the
     FIRST IMPLEMENTATION of the Unified Carrier Contract INCLUDING
     CC-MA — SQLite registry + POSIX entity store + SESSION carrier
     family (records, ordering, work-record kinds) + FILE carrier
     family (with RepresentationLocator provenance) + CC-5 mapping +
     derived access (L1 exact + L2 FTS mandatory; L3 semantic
     pluggable seam) + the MA-1..MA-10 concurrency mechanisms as
     MANDATORY manifest check items (especially MA-3, MA-4, MA-6,
     MA-7, MA-8, MA-9, MA-10 per the ruling).
U-B  InformationCore + MemPalace-derived retrieval: after U-A session
     results; seam = formal measured object.
U-C  Unified DB + dedicated search/vector engines: only under the
     frozen anti-complexity rule.
U-D  MemPalace-centric: EXCLUDED AS-IS.

Verdict composition: ruling R7 layered verdicts; no weighted total.
```

## 12. MemPalace capability parity reference (unchanged from v0.2)

Behavioral acceptance reference for the SESSION family of U-A — parity
of capability, not schema; no MemPalace object replication; MCP /
wake-up / agent UI excluded from carrier correctness.

## 13. Integration seam cost (unchanged from v0.2)

PB v1.2 seam objects plus: event-store↔registry consistency point;
cross-domain search fan-out; cross-domain relation traversal hops;
derived-index rebuild span across both domains; checkpoint/resume hop
count. U-B seam discipline: whole-path measurement only.

## 14. Phase sequence and gates

```text
now   UA v0.3 -> TARGETED CONFORMANCE REVIEW (five points, per ruling E)
      -> if no BLOCK: HUMAN REVIEW / FREEZE GATE
U-2   Unified implementation (manifest first; adapter evolution of A1;
      conformance; admission) — manifest MUST include the CC-MA
      mechanisms as mandatory check items   [needs its own Human
      authorization]
U-3   Session/Unified controlled runs + PB-U* calibration
U-4   Realism-tier diagnostic runs
U-5   U-B only if U-A session evidence justifies the seam
U-6   U-C only under the frozen anti-complexity rule
later Phase D ranking / Phase E selection: unchanged, still gated
```

## 15. Negative space

```text
This addendum does not:
  - modify PB v1.2, any Frozen Contract, InformationCore, or
    RelationCore (UA-P6: frozen artifacts win any apparent conflict);
  - define a new semantic layer over Information/Relation;
  - freeze DDL, physical layout, or APIs;
  - extend record kinds beyond the U-0 evidence map + the registered
    FILE-kind open decision input;
  - give the carrier any interpretation role over kinds or predicates;
  - create FileStore/SessionStore core stores (CC-9);
  - let session content self-promote to Information (CC-5);
  - require a vector index in U-A's mandatory surface;
  - model the Agent as a semantic entity: no AgentInformation, no
    AgentRelation, no AgentStore, no Agent-specific Information
    semantics, no File/Session semantic branches (CC-MA positioning);
  - create a separate concurrency database layer or two per-family
    concurrency mechanisms (one Unified Carrier concurrency model);
  - treat the observed real parallel scenario as a completed
    concurrency validation (it is MA-DS-1 design evidence);
  - authorize MemPalace integration (U-B), backend selection,
    migration, Lab reorganization, ES↔IS opening, or InformationCore
    mutation;
  - copy MemPalace's object model or silently ingest its collision
    debts.
```

## 16. Next gate

Targeted Conformance Review (already mandated; verifies exactly:
R-1..R-11 closure; A-1..A-3 dispositions; CC-MA semantic compatibility;
File/Session isomorphism; identity boundaries). If no BLOCK → Human
Review / Freeze gate:

```text
option A  ACCEPT / FREEZE as UA v1.0, then decide U-2 authorization
          separately;
option B  REVISE (enumerated items only) -> UA v0.4;
option C  PARK (registered reason).
```

No implementation begins before option A is ruled and U-2 is
specifically authorized.

## 17. Change log v0.2 → v0.3

```text
+  CC-MA (§3A): MA-1..MA-10 (C1-C10 catalog verbatim); concurrency
   design objects; unified concurrency model; Agent-as-actor
   positioning; MA-DS-1 binding design scenario; I19-I25; honest
   capability status; U-2 manifest mandatory check items.
~  CC-1: carrier_provenance rename + two-layer distinction (R-3/B.2);
   carrier-identity minting marked as U-2 manifest obligation (R-5/A-1).
~  CC-2: CCS-C8 relationship sentence (R-4).
~  CC-3: FILE-kind open decision input (R-9/A-3); record-deletion ≠
   Information-deletion sentence (B.1).
~  CC-4: A1 adapter citation precision (R-7).
~  CC-5: N:M cardinality default, flagged (R-6/A-2).
~  CC-8 #1: formation-input vs stability-rule distinction (R-8/B.3);
   row #7 Representation Identity added (R-10).
~  §2: workload-label pinning sentence (R-11).
~  §5: raw-event deletion wording corrected (R-1/B.1).
~  §8: "SESSION-family CarrierRecord streams" (R-2).
+  UA-P7: concurrency = carrier-layer correctness mechanisms; agents
   are actors.
   Everything else unchanged.
```
