# CCVS-01 Unified Addendum Protocol — UA v0.1

> **Status: SUPERSEDED — 2026-10-06**
> **Superseded by:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.2_20261006.md`
> **Superseded by ruling:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_REVISION_RULING_20261006.md`
> (B = REVISE, tightened by the Human's second message: not a new semantic
> model — the Unified Carrier Contract over the EXISTING SimiGo Information
> Space semantics).
> **Known defects in this version, corrected in v0.2:** universal `kind`
> field on Information (violates layer-① immutability); "a Session is an
> Information" (violates formation-through-existing-semantics); Session/
> SessionEvent defined as separate first-class logical objects (now
> Carrier/CarrierRecord instance families).
> Content below retained as revision history; do not use for review.

> **Status:** PROPOSED / AWAITING HUMAN REVIEW
> **Date:** 2026-10-06
> **Authorization basis:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_DIRECTION_RULING_20261006.md`
> **Design basis:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_REBASELINE_PROPOSAL_20261006.md` (archived verbatim)
> **Evidence basis:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U0_SESSION_EVIDENCE_CONSOLIDATION_20261006.md`
> **Relationship to CCVS-01-PB v1.2:** ADDITIVE ONLY. PB v1.2 stays frozen and
> governs the File side exactly as frozen. This addendum governs the Session
> side and the Unified (cross-domain) side. Nothing here may be read as
> modifying PB v1.2 numbers, bounds, fixtures, or rules.

## 0. Conflict and precedence rules

```text
UA-P1  PB v1.2 File-side rules, bounds, and delivered results stand
       unchanged. File-only metrics may be inherited from Baseline A
       runs without re-execution.
UA-P2  This addendum adds: Session workload families (S), Unified
       workload families (X), Unified candidate compositions (U-*),
       Session/Unified correctness bounds, and Session/Unified
       performance bounds.
UA-P3  Where a Unified run exercises File-side operations, the frozen
       PB v1.2 rules for those operations apply as-is (fixtures, seeds,
       admission, statistics, crash model).
UA-P4  New bound and check identifiers in this addendum use fresh
       numbering (UA-*, PB-U*, G9+, I14+, F10+) and never reuse or
       redefine a PB v1.2 identifier.
UA-P5  Mid-run change discipline is inherited: a suspected protocol
       defect stops the affected judgment and requires a new Human
       ruling before the affected results are classified.
```

## 1. UA-F1 — Research object

```text
Research object of the extended CCVS-01 scope:

    Unified Local Information Space carrier (UIS-01 shape)

    File Information  and  Session Information
    = equal first-class carrier workloads.

    Unified (same for both):  Identity / Relation / Provenance /
                              History / Availability / Search /
                              Recovery

    File side physical:  Representation -> content-addressed or
                         located POSIX/entity object -> Locator
    Session side physical: immutable ordered event sequence ->
                         raw payload

    Search is a DERIVED layer and can never be an authoritative
    Information source.
```

First-class is a workload/semantic statement, not a physical-storage
statement: File and Session share identity/relation/provenance/history
semantics; their physical byte layouts may differ (File = entity objects,
Session = ordered raw events). Neither side is forced into the other's
layout.

## 2. UA-F2 — Logical data structures (logical schema only; no DDL)

DDL and physical layout are U-2 implementation decisions made under
PB-F6-style composition manifests. This section freezes logical objects,
fields, and invariants only.

```text
L1  Information (universal)
      InformationID, kind, provenance, availability
      kind ∈ {file, session, event, result, derived, ...} = SimiGo
      semantic vocabulary; carrier stores it opaquely, never interprets
      it (CCS-C8).

L2  Representation
      RepresentationID, InformationID, revision, representation_kind,
      content_reference, digest, size, created_at
      Invariants carried over: Information Identity ≠ Representation
      Identity ≠ Physical Locator (IS-IDLOC-SEAM-01 discipline).

L3  Locator
      InformationID, RepresentationID, physical_locator, locator_state,
      observed_at
      MOVE = locator transition; Information identity unchanged
      (A1 semantic, inherited).

L4  Session (first-class object, not File metadata)
      SessionID, root_information (optional), started_at, ended_at,
      source, status

L5  SessionEvent
      SessionID, sequence, EventID, payload_reference, occurred_at,
      producer, provenance
      HARD INVARIANT (SessionID, sequence): stable across restart,
      summary materialization, reindex, and derived-index rebuild.
      Append-only per session; sequence never renumbered.

L6  Session Information Record (carrier-neutral work-record payload)
      record kinds: RAW, DISCOVERY, JUDGMENT, EXCLUSION, UNCERTAINTY,
      OPEN_QUESTION, NEXT_ACTION, EVIDENCE_LINK, RESULT
      (kind list evidence-mapped in U-0 §4; extending it requires a
      separate decision). record_kind is stored opaquely by the carrier.

L7  File ↔ Session typed relations
      Typed, directed, endpoints = InformationID on both sides (a
      Session is an Information). Example predicates (illustrative,
      NOT a frozen taxonomy): discussed-in, cited-by, produced-from,
      decision-source, revised-after, used, questioned, continues.
      Carrier guarantees: typed edge + stable endpoint identity +
      history. Carrier does not validate predicate semantics.

L8  RepresentationLocator (structured provenance for File hits)
      source = file:/...  plus structured locator, e.g.
        xlsx://workbook/sheet=<name>/range=<range>
        pdf://doc/page=<n>   pptx://deck/slide=<n>
        docx://doc/section=<id>
      Form is illustrative; the obligation is: a search hit can resolve
      to a source coordinate (sheet/range/page/slide/section), not only
      to a whole flattened document.

L9  IndexSource (derived-index rebuild authority)
      source_information, source_representation, extraction_version,
      extraction_reference
      Every derived-index entry must be traceable to an authoritative
      source (original File representation or RAW session event) so the
      index is deterministically rebuildable. This retires the P8 F7
      gap (searchable text living only in the derived index).
```

## 3. UA-F3 — Raw / Derived boundary

```text
File side:
  original file representation        = authoritative
  extracted text / FTS / embedding /
  summary                             = derived

Session side:
  raw session event                   = authoritative
  event normalization / summary /
  embedding / KG                      = derived

Consequences (mandatory):
  delete derived  -> MUST be rebuildable from authority
  delete raw session event     -> Information loss (forbidden as a
                                  routine operation; visible, typed)
  delete original file representation -> Representation loss (typed,
                                  availability semantics per PB v1.2)
```

## 4. UA-F4 — Correctness bounds (additive numbering)

Correctness gates G1–G8, invariants I1–I13, and crash points F1–F9 remain
frozen with their PB v1.2 meanings and continue to apply to every
File-side operation inside Unified runs. The addendum adds:

```text
I14  Session ordering stability
     (SessionID, sequence) is immutable across restart, summary
     materialization, reindex, and derived-index rebuild; append #k
     remains #k.

I15  Raw/derived separation enforced
     Deleting any derived artifact and rebuilding yields an equivalent
     view (extends PB v1.2 rebuild-equivalence to session + unified
     domains).

I16  IndexSource determinism
     Rebuild from authority via IndexSource yields a declared-equivalent
     derived index (identity coverage AND searchable-text coverage),
     verified by rebuild-compare, not assumed.

I17  Cross-domain relation integrity
     Typed File↔Session edges resolve to live InformationIDs; endpoint
     deletion follows registered availability semantics — no silent
     cascade, no dangling typed edge presented as resolvable.

I18  Historical judgment reviewability
     An EXCLUSION/JUDGMENT record is retrievable together with its
     reason, basis, evidence links (EVIDENCE_LINK), and the subsequent
     Information changes needed to answer "why re-examine?" — the
     RQ-G3-1 capability, mechanized as a carrier obligation to store and
     resolve, not to judge.

Hard eligibility gates (extending G1–G8):

G9  Session conformance
    append ordering + durability, raw retention, (SessionID, sequence)
    stability, timeline reconstruction correctness.
G10 Unified cross-domain conformance
    X-family correctness: file→session and session→file resolution,
    cross-session file history, revision→judgment-history linkage.
G11 Historical judgment review
    the I18 scenario executable end-to-end on stored data.
G12 Unified restart/continue
    checkpoint materialization + resume with all of I14–I17 intact.

Crash points (extending F1–F9; same verdict vocabulary PASS / REPAIR /
DETACHED; FAIL forbidden):

F10 kill during session append burst    -> committed ordered prefix,
                                           no gaps, no reordering
F11 kill during cross-domain relation write -> all-or-nothing per edge
F12 kill during unified derived-index rebuild -> rebuild-from-authority
                                           path (I16) or DETACHED
F13 kill during session summary materialization -> summary is derived:
                                           discardable/rebuildable, raw
                                           events intact
F14 kill at checkpoint/resume boundary  -> resume state consistent with
                                           durable prefix
```

## 5. UA-F5 — Workload families and binding workload

```text
S family (session-only; new):
  S1 high-frequency session append
  S2 ordered timeline read
  S3 session exact/structured search
  S4 session lexical search
  S5 session semantic search (pluggable L3; skipped = recorded N/A
     where the candidate has no L3 component)
  S6 historical session retrieval
  S7 session index rebuild
  S8 session crash/recovery

F family: PB v1.2 WL1..WL7 unchanged. File-only metrics inherit from
  Baseline A / PV1 results; no File-only re-run is required.

X family (unified cross-domain; new):
  X1 File → Session retrieval
  X2 Session → File retrieval
  X3 Cross-session → file history
  X4 File revision → session judgment history
  X5 File + Session mixed research day
  X6 interruption → restart → continue
  X7 derived index rebuild across both domains
  X8 historical judgment re-audit

Binding workload for the Unified addendum:

  WL6-U "Unified Research Day" (X5, extended definition) = PRIMARY
  binding workload. Frozen step list:

    1  import new files
    2  open a session
    3  discuss file content
    4  discover a problem
    5  form a judgment
    6  exclude one file
    7  continue with another file
    8  modify the original file (new revision)
    9  session references the new revision
    10 form a conclusion
    11 interrupt (crash point F14-class)
    12 restart
    13 continue
    14 query: why was this judgment made?      (X8/I18)
    15 query: which files did this judgment use?
    16 query: has later evidence overturned it?

  WL6 (File-side mixed research day) remains the File-side binding
  workload, unchanged. S1..S8 and X1..X8 are mandatory
  diagnostic/capability families, each reported independently (R3
  binding-role discipline inherited: a WL6-U PASS never implies
  large-file, relation-heavy, or fault-recovery PASS).

Tiers: PB-F1 tier numbers are inherited verbatim (SMALL 10 sessions /
1,000 events; MEDIUM 100 sessions / 10,000 events; ...). Session event
record-kind distribution and cross-domain linkage counts are new
fixture-generator parameters, generated deterministically under the
frozen master-seed derivation discipline (generator version bump
recorded per PB-F2). SMALL + MEDIUM mandatory; LARGE/STRESS per PB-F1
obligations.
```

## 6. UA-F6 — Real-corpus diagnostic realism tier

```text
Primary binding workloads remain deterministic synthetic fixtures
(PB-F2 discipline, comparability preserved). The addendum adds a
mandatory DIAGNOSTIC (non-binding) realism tier:

  File realism source:
    registered real corpus replay with archive-organizer as the File
    Information producer (scan / change detection / classification /
    move / rename / remap / journal), recorded with content hashes.

  Session realism source:
    G1/G2/G3 + MemPalace real-carrier session records replayed as
    Session Information Record streams (real discoveries, judgments,
    exclusions, pending work, file references).

Rules:
  - Real corpus NEVER enters synthetic fixtures (PB-F2 stands: no real
    user data in fixtures).
  - Realism-tier runs are reported separately; they never replace
    synthetic binding results and never enter bound classification.
  - A realism-tier capability failure (e.g., a retrieval shape that the
    synthetic workload could not expose) is reportable evidence and may
    drive Phase D discussion, but is not a bound violation.
```

## 7. UA-F7 — Performance bounds (additive; UNCALIBRATED until U-A runs)

Classification mechanism inherited from PB v1.2 R1: new bounds start
UNCALIBRATED, are calibrated by the first valid U-A Baseline runs, and
then become ACTIVE/MET or PROTOCOL-VALIDITY-FLAGGED. Amplification
metric follows the D-A ruling: Q1 steady-state allocated-block footprint
= primary; Q3 device-writeback traffic = diagnostic only.

```text
| ID     | Bound (MEDIUM, cold, valid runs, median-of-runs)          |
|--------|-----------------------------------------------------------|
| PB-U1  | session append P95                                        |
| PB-U2  | ordered timeline reconstruction P95                       |
| PB-U3  | session exact/structured search P95                       |
| PB-U4  | session lexical search P95                                |
| PB-U5  | cross-domain traversal P95 (file→session, session→file)   |
| PB-U6  | historical judgment lookup P95 (X8)                       |
| PB-U7  | unified derived-index rebuild (both domains) wall-clock   |
| PB-U8  | checkpoint materialization + resume latency (X6)          |
| PB-U9  | unified steady-state amplification (Q1 primary)           |
| PB-U10 | unified steady-state RSS                                  |
| PB-U11 | unified restart/open after clean shutdown                 |

Session metrics already measured File-side (WL3 session append P95,
WL4/WL5/WL7) keep their PB v1.2 identities and values; PB-U1 covers the
first-class Session Information Record workload, which is a different,
heavier append shape.
```

## 8. UA-F8 — Statistical protocol

Inherited verbatim from PB v1.2 §3.5: per-run independent percentiles;
per-run observation minimums; median-of-valid-run percentiles as
candidate metrics; pooled values as clearly-labelled supplemental
diagnostics only; INVALID restricted to predefined protocol/environment
violations (never poor performance); quiescence = three consecutive 5 s
windows, admission condition only; serial cold-run policy. A Unified run
is one execution of the full step list (WL6-U or family script) under
the same admission rules.

## 9. UA-F9 — Candidate compositions

```text
U-A  Unified Minimal (FIRST candidate; evolution of Baseline A / A1):
       SQLite registry (+ Information/Representation/Locator/Relation/
       Pin/Availability/Session/SessionEvent tables)
       + POSIX entity store (files; large session payloads if any)
       + first-class Session Information Record store
       + RepresentationLocator structured provenance
       + IndexSource-backed derived search:
           L1 exact/structured  = mandatory
           L2 lexical (FTS5)    = mandatory
           L3 semantic          = pluggable seam, NOT required for
                                  U-A qualification
       Rationale: fewest components, one authority, lowest seam —
       consistent with the standing anti-complexity principle.

U-B  InformationCore + MemPalace-derived retrieval:
       MemPalace demoted to derived retrieval only (semantic/session/
       KG-derived); never authoritative. Enters only after U-A session
       results exist. Its integration seam is a formal measured object.

U-C  Unified DB + dedicated search/vector engines:
       only if U-A/U-B real-workload evidence shows the search/scale
       gain exceeds the composition cost under the frozen
       anti-complexity rule (inherited verbatim: end-to-end >= 30% P95
       or >= 50% durable throughput on the binding workload; M1–M3 side
       conditions; 2x non-regression line).

U-D  MemPalace-centric: EXCLUDED AS-IS (ISMCI audit + Core Sufficiency
       Audit boundary). Re-entry requires reconstructed authoritative
       identity/revision/lineage mechanisms — a separate decision.
```

Verdict composition inherits ruling R7: layered capability/performance/
resource/fault verdicts; no weighted total score.

## 10. UA-F10 — U-A acceptance reference (MemPalace capability parity)

Behavioral acceptance reference for the Session side of U-A — parity of
capability, NOT of schema. MemPalace objects (wing/room/drawer/closet)
are not replicated. MCP / wake-up API / agent UI are upper-layer
interfaces and are excluded from carrier correctness (O-U0-5).

```text
  ✓ raw session retention            ✓ session provenance
  ✓ incremental session ingestion    ✓ cross-session retrieval
  ✓ session lexical retrieval        ✓ File ↔ Session relations
  ✓ session semantic retrieval*      ✓ historical session recall
  ✓ work-frontier retrieval          ✓ negative-knowledge recall
  ✓ rebuild derived indexes          ✓ resume after restart

  * L3 semantic is pluggable; where U-A ships without an L3 component,
    parity for this row is assessed against the registered L3 seam
    (interface present, implementation optional) and the S5 family
    records N/A-with-reason.
```

## 11. UA-F11 — Integration seam cost (extended)

PB v1.2 seam objects (write hops, query hops, serialization count,
durable acknowledgement point, transaction boundary, recovery boundary,
disk/memory amplification, adapter thickness) remain measured objects.
Session/Unified additions:

```text
  - event-store ↔ registry consistency point
  - cross-domain search fan-out (one query across file + session
    namespaces: hops and serialization count)
  - cross-domain relation traversal hops (X1/X2/X5)
  - derived-index rebuild span across both domains (X7)
  - checkpoint/resume hop count (X6)

U-B seam discipline: never report MemPalace search speed alone. The
measured path is ingest → canonical store → derived index → query →
provenance resolution → cross-domain relation, end-to-end through the
common adapter.
```

## 12. UA-F12 — Phase sequence and gates

```text
now     U-0 done; U-1 (this document) -> HUMAN REVIEW
U-2     A+ Unified implementation (composition manifest first, then
        adapter evolution of A1, conformance, admission)   [gate: needs
        its own Human authorization after U-1 ruling]
U-3     Session/Unified controlled runs under frozen admission +
        statistical rules; PB-U* calibration              [same gate or
        explicit separate authorization — Human's choice at U-1 ruling]
U-4     Realism-tier diagnostic runs (UA-F6)
U-5     U-B only if U-A session evidence justifies the seam
U-6     U-C only under the frozen anti-complexity rule
later   Phase D ranking / Phase E selection: unchanged, still gated
```

## 13. UA-F13 — What this addendum does not do

```text
  - does not modify PB v1.2, any Frozen Contract, InformationCore, or
    RelationCore;
  - does not freeze DDL, physical layout, or APIs (U-2 manifests do
    that under PB-F6 rules);
  - does not extend the Session Information Record kinds beyond the
    U-0 evidence map without a separate decision;
  - does not give the carrier any interpretation role over record
    kinds or predicates (CCS-C8 unchanged);
  - does not require a vector index in U-A's mandatory surface;
  - does not authorize MemPalace integration (U-B), backend selection,
    migration, Lab reorganization, ES↔IS opening, or InformationCore
    mutation;
  - does not copy MemPalace's object model or ingest its collision
    debts silently — obligations enter only as explicit U-0/U-1 items.
```

## 14. UA-F14 — Next gate

Human review of this v0.1:

```text
option A  ACCEPT / FREEZE UA v1.0 (constants as proposed), then decide
          U-2 authorization separately;
option B  REVISE (narrow, enumerated items) -> UA v1.1;
option C  PARK (registered reason).
```

No implementation begins before option A is ruled and U-2 is
specifically authorized.
