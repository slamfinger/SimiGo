# CCVS-01 Unified Addendum Protocol — UA v0.2

> **Status: SUPERSEDED — 2026-10-06**
> **Superseded by:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.3_20261006.md`
> **Superseded by ruling:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_REVIEW_RULING_AND_CCMA_MANDATE_20261006.md`
> (B = REVISE on the conformance review outcome: v0.2 direction and
> semantic anchoring ACCEPTED, freeze NOT granted; v0.3 = R-1..R-11 fixes +
> A-1..A-3 dispositions + new CC-MA Multi-Agent Carrier Consistency surface).
> **Review lineage:** UA v0.2 was reviewed in
> `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_V0_2_CONFORMANCE_REVIEW_20261006.md`
> (REVISE, R-1..R-11, zero BLOCK). All eleven findings are closed in v0.3.
> Content below retained as revision history; do not use for review.

> **Status:** PROPOSED / AWAITING HUMAN REVIEW
> **Date:** 2026-10-06
> **Revision lineage:** v0.1 (PROPOSED) → Human ruling **B = REVISE**
> (`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_REVISION_RULING_20261006.md`,
> tightened by the Human's second message in the same round) → **v0.2 (this
> document)**. U-0 is retained unchanged. U-2 remains NOT AUTHORIZED.
> **Authorization basis:** Unified direction ruling +
> U-1 revision ruling
> **Design basis:** archived rebaseline proposal
> **Evidence basis:** U-0 Session Evidence Consolidation
> **Relationship to CCVS-01-PB v1.2:** ADDITIVE ONLY (unchanged from v0.1).

## 0. What changed from v0.1 (revision summary)

The revision ruling tightened the round's target: **not** a new Information
Space logical model, and **not** more session workload/fixture/gate
definitions — but the **Unified Carrier Contract**, built on top of the
already-defined SimiGo Information Space semantics, such that File Carrier
and Session Carrier connect to the same Information Space with zero semantic
forking.

```text
ADDED      §3 Unified Carrier Contract (UA-CC): four-layer structure,
           carrier object, common capability surface, CarrierRecord,
           ordering stability, Information↔Record mapping, relation
           placement, derived access placement, and the six identity
           relations with lifecycle/mutability boundaries.

CORRECTED  v0.1 L1: the proposed universal `kind` field on Information
           is DROPPED. Layer ① (Information Space semantics) does not
           change because Session joined; carrier origin lives on the
           Carrier/Record side (UA-CC-1/CC-5), not as a new Information
           field.
CORRECTED  v0.1 L7: "a Session is an Information" is REMOVED. Session
           content becomes Information only through the existing
           formation semantics (identity at formation, mechanism-side
           minting) — never automatically, and never by Session
           developing its own semantics.
RESCOOPED  v0.1 L4/L5: Session / SessionEvent as separately-defined
           first-class logical objects become the SESSION instance
           family of Carrier / CarrierRecord (UA-CC-1/CC-3).

UNCHANGED  I14–I18, G9–G12, F10–F14, S1–S8, X1–X8, WL6-U, PB-U1..U11,
           statistical protocol, real-corpus diagnostic tier, candidate
           compositions, parity reference, seam objects, phase gates —
           all retained and RE-LABELLED as verification instruments of
           the Unified Carrier Contract (§6–§7). No new workload,
           fixture, or gate definitions were added.
```

## 1. Conflict and precedence rules

```text
UA-P1  PB v1.2 File-side rules, bounds, and delivered results stand
       unchanged. File-only metrics may be inherited from Baseline A
       runs without re-execution.
UA-P2  This addendum adds the Unified Carrier Contract and its
       verification layer. It adds no new semantic layer over
       Information/Relation.
UA-P3  Where a Unified run exercises File-side operations, frozen PB
       v1.2 rules apply as-is.
UA-P4  New identifiers use fresh numbering (UA-CC-*, PB-U*, G9+, I14+,
       F10+) and never redefine a PB v1.2 identifier.
UA-P5  Mid-run change discipline inherited (suspected defect stops the
       affected judgment; new Human ruling required).
UA-P6  NEW. Layer ① semantics are cited from their frozen artifacts,
       never re-specified here. If this addendum's text appears to
       redefine Information or Relation semantics, the frozen artifacts
       win and the addendum text is defective.
```

## 2. The four-layer structure (frozen principle)

```text
┌─────────────────────────────────────────────────────────────────┐
│ ① Information Space Semantic Layer — SimiGo EXISTING, unchanged │
│    Information / Relation / provenance / temporal semantics     │
│    (§4 cites the frozen artifacts)                              │
├─────────────────────────────────────────────────────────────────┤
│ ② Unified Carrier Layer — THE CURRENT CORE WORK                 │
│    Carrier contract (§3)                                        │
│      ├─ File Carrier   (instance family FILE)                   │
│      └─ Session Carrier (instance family SESSION)               │
├─────────────────────────────────────────────────────────────────┤
│ ③ Carrier Representation / Record Layer                         │
│    FILE:    path / bytes / representation / segment ...         │
│    SESSION: event / sequence / summary / turn ...               │
│    Physical difference allowed; ONE Carrier Contract governs    │
│    both (§3)                                                    │
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

What "Unified File + Session" solves is therefore not schema merging: it is
one Carrier abstraction that presents different classes of real information
sources to the Information Space in the same way.

## 3. UA-CC — Unified Carrier Contract

Logical contract only. DDL, physical layout, and APIs are U-2 decisions
under PB-F6-style composition manifests.

### CC-1 Carrier object

```text
Carrier
  carrier identity        opaque, stable, carrier-side; independent of
                          Information Identity
  carrier_kind            FILE | SESSION (extensible only by explicit
                          SimiGo-side decision; never by carrier
                          interpretation)
  locator / locator_state where the carrier's content physically lives
  representation          content reference + version / fingerprint
  capability surface      CC-2
  records                 CC-3 (ordered / locatable units)
  provenance              where the carrier itself came from

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
                        decision, not a carrier one
  sequence/local_locator  stable addressing inside the carrier
  content_ref           where the record content lives
  metadata

FILE instance family records (illustrative): whole file / section /
paragraph / extracted representation.
SESSION instance family records (illustrative): event N / summary event.

CarrierRecord is a LOCATABILITY unit ("where, inside this carrier, this
content appears"). It is never an Information substitute.
```

### CC-4 Carrier-internal ordering stability

```text
Each instance family defines its stable internal addressing:
  SESSION: (SessionID, sequence) — append-only, never renumbered;
           survives restart, summary materialization, reindex, and
           derived-index rebuild.
  FILE:    representation/segment addressing stable under the
           representation's revision identity; locator transitions
           (MOVE) never change identity (inherited A1 semantic).

In both families: internal addressing is stable across restart,
reindex, summary materialization, and derived rebuild. This generalizes
the v0.1 (SessionID, sequence) invariant and the U-0
RepresentationLocator obligation into one contract clause.
```

### CC-5 Information ↔ CarrierRecord mapping

```text
- The mapping is EXPLICIT and provenance-bearing (which record, in
  which carrier, at which version, carried which content that became
  which Information).
- Many-to-one is allowed: several records may carry or carry over one
  Information.
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
    wake-up-contamination obligation).
```

### CC-8 The six identity relations (ruling §3, re-anchored)

| # | Identity relation | Definition locus | Lifecycle / mutability boundary |
|---|---|---|---|
| 1 | Information Identity | EXISTING frozen semantics (§4) — opaque `InformationID`, formed at formation, minted mechanism-side | immutable; never re-derived from path, name, carrier, or digest |
| 2 | Carrier Identity | THIS contract (CC-1) — opaque, carrier-side, stable | carrier identity stable for the carrier's life; locator/state mutable; content evolves via representations with versions/fingerprints |
| 3 | CarrierRecord Identity | THIS contract (CC-3/CC-4) — carrier-internal, stable addressing | append-only within a session carrier; stable under representation revision for a file carrier; a record is never mutated into a different record |
| 4 | Information ↔ CarrierRecord mapping | THIS contract (CC-5) — explicit, provenance-bearing | append/annotate only; corrections = new entries; never rewritten |
| 5 | Information ↔ Information Relation | EXISTING frozen RelationCore semantics (§4) — endpoints are InformationIDs, immutable, first-write-wins | immutable; no carrier-side relation semantics |
| 6 | DerivedIndex ↔ source | THIS contract (CC-7) — IndexSource with version/fingerprint | freely deletable/rebuildable; never authoritative |

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

## 4. Layer ① — existing semantics (cited, not redefined)

For precision, the frozen surfaces this contract builds ON (verified
against current source; cited here, not re-specified):

```text
InformationCore  (trackD-memory/Sources/InformationCore/)
  Information: opaque InformationID; immutable content; Provenance
  (producedAt/producedBy required; optional source/position fields);
  optional ContentDate pair (unknown stays unknown, never inferred)
  — rulings A1–A5; acceptance `6feac8c`.
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

The Unified Carrier Contract (§3) adds layer ② and below. It does not
modify any of the above.

## 5. Raw / Derived boundary (re-anchored from v0.1 UA-F3)

```text
File side:    original file representation = authoritative;
              extracted text / FTS / embedding / summary = derived
Session side: raw session event = authoritative;
              normalization / summary / embedding / KG = derived

  delete derived  -> MUST be rebuildable from authority (CC-7)
  delete raw session event              -> Information loss (typed,
                                           visible, forbidden as routine)
  delete original file representation   -> Representation loss (typed,
                                           availability semantics per PB v1.2)
```

## 6. Correctness and crash bounds — verification of the contract

Content unchanged from v0.1; role re-labelled: these are mechanical
checks **of the Unified Carrier Contract and layer ① semantics**, not the
definition of the database structure.

```text
I14  ordering stability (SESSION family of CC-4)
I15  raw/derived separation enforced (CC-7 rebuild equivalence across
     session + unified domains)
I16  IndexSource determinism (CC-7)
I17  cross-domain relation integrity (CC-6 + CC-5: typed edges resolve
     through the mapping; no silent cascade)
I18  historical judgment reviewability (CC-5 + CC-6: EXCLUSION/
     JUDGMENT retrievable with reason, basis, evidence links, and
     subsequent Information changes)

G9   SESSION-family capability conformance (CC-2/CC-4)
G10  cross-family conformance (CC-2/CC-5/CC-6)
G11  historical judgment review end-to-end (CC-5/I18)
G12  unified restart/continue (CC-4 across both families)

F10  crash during session append burst -> committed ordered prefix,
     no gaps, no reordering
F11  crash during cross-domain relation write -> all-or-nothing per edge
F12  crash during unified derived-index rebuild -> rebuild-from-authority
     (CC-7) or DETACHED
F13  crash during session summary materialization -> summary is
     derived: discardable/rebuildable; raw events intact
F14  crash at checkpoint/resume boundary -> resume consistent with
     durable prefix

Verdict vocabulary inherited: PASS / REPAIR / DETACHED; FAIL forbidden.
```

## 7. Workload families — verification of the contract

Content unchanged from v0.1 (and unchanged by this revision, per the
ruling's instruction to stop adding workload/fixture/gate definitions):

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

Binding workload: WL6-U "Unified Research Day" (16 frozen steps,
unchanged from v0.1) = PRIMARY for the Unified addendum; WL6 remains
the File-side binding workload; binding-role discipline inherited
(WL6-U PASS never implies large-file, relation-heavy, or fault-recovery
PASS).

Tiers: PB-F1 numbers inherited verbatim (SMALL 10 sessions/1,000
events; MEDIUM 100/10,000; ...). Session record-kind distribution and
cross-domain linkage counts are fixture-generator parameters under the
frozen master-seed discipline (version bump recorded).
```

## 8. Real-corpus diagnostic realism tier (unchanged from v0.1)

Primary binding = deterministic synthetic fixtures (PB-F2 discipline).
Mandatory diagnostic (non-binding) tier: archive-organizer as File
Information producer over the registered real corpus; G1/G2/G3 +
MemPalace real-carrier records replayed as Session Information Record
streams. Real corpus never enters synthetic fixtures; realism runs
reported separately; a realism failure is reportable evidence, not a
bound violation.

## 9. Performance bounds (unchanged from v0.1)

PB-U1..PB-U11 as listed in v0.1, starting UNCALIBRATED, calibrated by
the first valid U-A runs; D-A discipline (Q1 steady-state allocated-block
footprint primary; Q3 writeback traffic diagnostic only); PB v1.2
identities for File-side metrics preserved.

## 10. Statistical protocol (unchanged from v0.1)

Inherited verbatim from PB v1.2 §3.5: per-run independent percentiles;
per-run observation minimums; median-of-valid-run percentiles; pooled
values as labelled diagnostics only; INVALID restricted to predefined
protocol/environment violations; quiescence = three consecutive 5 s
windows (admission only); serial cold-run policy. A Unified run is one
execution of the full step list under the same admission rules.

## 11. Candidate compositions (unchanged from v0.1, re-expressed)

```text
U-A  Unified Minimal (FIRST): evolution of Baseline A / A1 into the
     FIRST IMPLEMENTATION of the Unified Carrier Contract — SQLite
     registry + POSIX entity store + SESSION carrier family (records,
     ordering, work-record kinds) + FILE carrier family (with
     RepresentationLocator provenance) + CC-5 mapping + derived access
     (L1 exact + L2 FTS mandatory; L3 semantic pluggable seam, not
     required for qualification).
U-B  InformationCore + MemPalace-derived retrieval: MemPalace demoted
     to derived retrieval only; after U-A session results; seam = formal
     measured object.
U-C  Unified DB + dedicated search/vector engines: only under the
     frozen anti-complexity rule (end-to-end >= 30% P95 or >= 50%
     durable throughput; M1–M3; 2x non-regression line).
U-D  MemPalace-centric: EXCLUDED AS-IS (ISMCI audit + Core Sufficiency
     Audit boundary).

Verdict composition: ruling R7 layered verdicts; no weighted total.
```

## 12. MemPalace capability parity reference (unchanged from v0.1)

Behavioral acceptance reference for the SESSION family of U-A — parity
of capability, not schema; no MemPalace object replication; MCP /
wake-up / agent UI excluded from carrier correctness. The twelve-parity
list and the L3 pluggable note carry over verbatim from v0.1 §10.

## 13. Integration seam cost (unchanged from v0.1)

PB v1.2 seam objects plus: event-store↔registry consistency point;
cross-domain search fan-out; cross-domain relation traversal hops;
derived-index rebuild span across both domains; checkpoint/resume hop
count. U-B seam discipline: whole-path measurement only.

## 14. Phase sequence and gates

```text
now   UA v0.2 -> HUMAN REVIEW (this document)
U-2   Unified implementation (manifest first; adapter evolution of A1;
      conformance; admission)        [needs its own Human authorization]
U-3   Session/Unified controlled runs + PB-U* calibration
U-4   Realism-tier diagnostic runs
U-5   U-B only if U-A session evidence justifies the seam
U-6   U-C only under the frozen anti-complexity rule
later Phase D ranking / Phase E selection: unchanged, still gated
```

## 15. Negative space (v0.1 §13 + ruling hard constraints)

```text
This addendum does not:
  - modify PB v1.2, any Frozen Contract, InformationCore, or
    RelationCore (UA-P6: frozen artifacts win any apparent conflict);
  - define a new semantic layer over Information/Relation — the
    revision's whole point is that ① already exists;
  - freeze DDL, physical layout, or APIs;
  - extend record kinds beyond the U-0 evidence map;
  - give the carrier any interpretation role over kinds or predicates;
  - create FileStore/SessionStore core stores (CC-9);
  - let session content self-promote to Information (CC-5);
  - require a vector index in U-A's mandatory surface;
  - authorize MemPalace integration (U-B), backend selection,
    migration, Lab reorganization, ES↔IS opening, or InformationCore
    mutation;
  - copy MemPalace's object model or silently ingest its collision
    debts.
```

## 16. Next gate

Human review of UA v0.2:

```text
option A  ACCEPT / FREEZE as UA v1.0, then decide U-2 authorization
          separately;
option B  REVISE (enumerated items only) -> UA v0.3;
option C  PARK (registered reason).
```

No implementation begins before option A is ruled and U-2 is
specifically authorized.
