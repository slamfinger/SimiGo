# CCVS-01 UA v0.2 — Unified Carrier Contract Conformance Review

> **Status:** REVIEW COMPLETE / **FINAL: REVISE** (no BLOCK, no CONTRADICTION)
> **Date:** 2026-10-06
> **Task:** UA v0.2 Unified Carrier Contract Conformance Review (Human-commissioned)
> **Object under review:**
> `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.2_20261006.md`
> (committed @ `fe4e5ec`, byte-identical to the delivered text)
> **Discipline:** Information Space semantics exist and are NOT redesigned.
> No Frozen Contract, PB v1.2, RESEARCH_STATE.md, U-0, or UA v0.2 text was
> modified by this review. No U-2 implementation. No backend selection. No
> new workload/fixture/gate definitions. Findings are registered as precise
> problem statements + revision suggestions only; no replacement semantic
> contract is self-authored here.

---

## 1. Reviewed scope

```text
R-1  UA v0.2 full text (510 lines, all UA-CC CC-1..CC-9 and UA-F sections)
R-2  U-1 Revision Ruling (both Human messages; message 2 operative)
R-3  U-0 Session Evidence Consolidation
R-4  Frozen semantic sources, verified against current code:
       trackD-memory/Sources/InformationCore/Information.swift
       (Information = identity + verbatim content + Provenance +
       optional ContentDate pair; A1-A5 implemented; A5 negative space;
       NO kind/title/summary/status fields)
       trackD-memory/Sources/InformationCore/InformationStore.swift
       (store + fetch only)
       trackD-memory/Sources/RelationCore/Relation.swift
       (identity/subject=InformationID/predicate/object=InformationID/
       provenance)
       trackD-memory/Sources/RelationCore/RelationStore.swift
       (store + fetch only)
R-5  PB v1.2 rules inherited by UA v0.2 (UA-P1/P3/P5; tiers PB-F1;
     fixtures PB-F2; rebuild equivalence; historical pin; crash
     vocabulary)
R-6  Registered boundaries: IS-IDLOC-SEAM-01, Core Sufficiency Audit,
     Carrier charter, CCS-C8, MEMPALACE_ISMCI_ADAPTER_FEASIBILITY_AUDIT
```

Review method: every UA-CC item was tested with the UA-P6 rule ("if this
addendum's text appears to redefine Information or Relation semantics, the
frozen artifacts win"), the ruling's tightening test ("does any sentence
treat Session as a second class of Information?"), and the identity-boundary
chain test (Information ≠ Carrier ≠ Representation ≠ Locator ≠ Record ≠
IndexEntry).

## 2. Source anchors

| Anchor | Used for |
|---|---|
| A1–A5 rulings + `Information.swift` | CC-8 #1; §4 citations; layer-① immutability |
| A2′ (identity at formation, mechanism-side minting) | CC-5; CC-8 #1 |
| A3 Provenance (producedAt/producedBy required; source/sourceTime/position/extractionMode optional) | CC-1 provenance check (finding R-3) |
| B1–B3 + S1–S6 (store idempotent first-write-wins; fetch Optional) | CC-5 formation rule; no-overwrite property |
| D1(a)/D2(a)/D3(a)/D7(a) + R1–R6 + `Relation.swift` | CC-6; CC-8 #5 |
| CCS-C8 (carrier resolves/consumes/produces/pins/continues as interface obligation) | CC-1/CC-2 carrier-only classification |
| IS-IDLOC-SEAM-01 (Information Identity ≠ Representation Identity ≠ Physical Locator ≠ Historical Pin) | CC-4; CC-8 (finding R-10) |
| PB v1.2 §3.2 (I1–I13; historical pin resolves to exact prior representation; index rebuild derives equivalent view from authority) | CC-7; UA-F4 re-labelling |
| PB v1.2 §5.1 / P8 record (F verdicts; F7 searchable-text finding) | CC-7; UA-F4 |
| U-0 F-U0-1..8, O-U0-1..5 | evidence column of the matrix |
| First-implementation registered decisions (minting input = content + source + chunkIndex) | finding R-8 |
| Revision ruling (message 1 §1–§6; message 2 four layers + frozen principle) | whole contract |

## 3. Conformance matrix (compact)

Legend: CO = carrier-only obligation (new carrier-layer concept, explicitly
not Information semantics); EX = anchored in existing frozen semantics;
MIX = anchored rule whose mechanics are carrier-side.

| Item | Existing semantic anchor | U-0 evidence | CO? | File mapping | Session mapping | Conflict/Ambiguity | Disposition |
|---|---|---|---|---|---|---|---|
| CC-1 Carrier object | CCS-C8; IS-IDLOC-SEAM-01 | F-U0-1; O-U0-5 | CO | path+fingerprint locator; per-file/directory carrier | SessionID locator | R-3 (provenance name); R-5 (identity minting unmarked) | REVISE (precision) |
| CC-2 Capability surface | CCS-C8 (relationship unstated) | O-U0-2; F-U0-7 | CO | discover/locate/read/exact/enumerate/summarize/reconstruct all exhibit | same verbs, event-grained | R-4 (C8 relationship) | REVISE (one sentence) |
| CC-3 CarrierRecord | ruling §2 (record layer first) | U-0 §4 kind map | CO | whole/section/paragraph/extracted | event N / summary event | R-9 (FILE kinds gap) | REVISE (mark decision input) |
| CC-4 Ordering stability | IS-IDLOC-SEAM-01; PB v1.2 I-series | O-U0-3 | CO | segment addressing per revision; MOVE = locator transition | (SessionID, sequence) append-only | R-7 ("A1" ambiguous) | REVISE (citation precision) |
| CC-5 Info↔Record mapping | A2′; B1-B3; ruling msg 2 | F-U0-7; F-U0-8 | MIX (mapping=CO; formation rule=EX) | section→Information when formed | event→Information when formed | R-6 (cardinality) | REVISE (minor) |
| CC-6 Relations Info↔Info | D1(a)/D3(a)/R1–R6 | F-U0-5; F-U0-6 | EX | relations between mapped Informations | same; no carrier-level relations | none | PASS |
| CC-7 Derived access | PB v1.2 rebuild equivalence; P8 F7 | O-U0-4; O-U0-1; O-U0-2 | CO | FTS/extraction from file bytes; IndexSource=representation | summary/embedding from raw events; IndexSource=event | none | PASS |
| CC-8 Identity relations | A2/A2′; D1(a)/D2(a); seam-01 | O-U0-3; O-U0-4 | #1/#5=EX; #2/#3/#4/#6=CO | — | — | R-8 (#1 wording "digest"); R-10 (Representation Identity implicit) | REVISE (precision) |
| CC-9 Hard constraints | ruling §5 verbatim | — | governance | binds both families | binds both families | none | PASS |
| UA-F1 four layers | ruling msg 2 verbatim | — | structure | — | — | none | PASS |
| UA-F3 raw/derived | PB v1.2; G3 constitution | F-U0-8 | CO | original representation authoritative | raw event authoritative | R-1 ("Information loss" mislabel) | REVISE (wording) |
| UA-F4 bounds re-label | PB v1.2 G/I/F | P8 | verification | — | — | none (I17 wording already fixed in v0.2) | PASS |
| UA-F5 workloads re-label | PB v1.2 WL/tiers | S12 | verification | — | — | none | PASS |
| UA-F6 realism tier | PB-F2 (no real data in fixtures) | S8 | diagnostic-only | archive-organizer producer | G1-G3 record replay | none | PASS |
| UA-F7..F8 perf/stats | PB v1.2 §3.5; D-A ruling | — | verification | — | — | none | PASS |
| UA-F9..F11 compositions/parity/seam | ISMCI audit; charter | S10 | CO | U-A = contract implementation | SESSION family in U-A | none | PASS |
| UA-F13 negative space | ruling §5 | O-U0-5 | governance | — | — | none | PASS |

## 4. Full CC-1..CC-9 disposition

### CC-1 — Carrier object

```text
Traceability   every field is carrier-layer; none presented as
               Information semantics. carrier_kind extension gated to
               SimiGo-side decision (respects CCS-C8). "independent of
               Information Identity" stated explicitly. UA-P6 test: PASS.
Carrier-only?  YES.
File behavior  locator = filesystem path + fingerprint; records =
               representation units. Ambiguity: what makes a File
               Carrier the SAME carrier across modify and rename is not
               stated (see R-5).
Session behavior locator = session identity (SessionID); unambiguous.
Findings       R-3, R-5.
Disposition    REVISE (precision items only; structure sound).
```

### CC-2 — Common capability surface

```text
Traceability   all seven verbs are carrier capabilities; none
               interpreted as semantic operations. exact-retrieve
               "never replaceable by ranking" = O-U0-2 obligation.
Carrier-only?  YES.
File/Session   both families exhibit all seven verbs; summarize
               correctly marked as derived-output-only (④).
Findings       R-4 (relationship to CCS-C8's five interface obligations
               — resolve/consume/produce/pin/continue — is unstated;
               without it, two competing verb vocabularies coexist).
Disposition    REVISE (one clarifying sentence).
```

### CC-3 — CarrierRecord

```text
Traceability   "LOCATABILITY unit, never an Information substitute" =
               ruling §2 verbatim. record_kind stored opaquely =
               CCS-C8. Nine-kind vocabulary evidence-mapped in U-0 §4.
Carrier-only?  YES.
File behavior  record kinds for FILE-family records (whole/section/
               paragraph/extracted) are not covered by the session-
               work-flavored U-0 vocabulary (see R-9).
Session behavior event N / summary event map cleanly; kinds covered.
Findings       R-9.
Disposition    REVISE (mark as SimiGo-side decision input).
```

### CC-4 — Ordering stability

```text
Traceability   generalizes O-U0-3 ((SessionID, sequence)) and the
               RepresentationLocator obligation into one clause; MOVE =
               locator transition, identity unchanged = IS-IDLOC-SEAM-01
               + PB v1.2 I-series + A1-adapter atomic-MOVE conformance.
Carrier-only?  YES.
File behavior  segment addressing stable per revision identity; old
               revisions stay addressable (historical pin, PB v1.2).
Session behavior append-only, never renumbered; survives restart/
               summary/reindex/rebuild.
Findings       R-7 ("inherited A1 semantic" — A1 denotes both a frozen
               ruling (immutable value) and the A1 adapter
               (CarrierSQLite); the intended referent here is the
               adapter).
Disposition    REVISE (citation precision).
```

### CC-5 — Information ↔ CarrierRecord mapping

```text
Traceability   "record existence never creates Information; formation
               only through existing semantics" = ruling message 2 +
               A2′. The mapping OBJECT is new (carrier-layer); the
               formation RULE it points to is existing frozen
               semantics. This is the clause that structurally blocks
               "Session develops its own semantics".
Carrier-only?  MIX — mapping mechanics CO; formation rule EX.
File behavior  section → Information when SimiGo forms it; many records
               may carry one Information.
Session behavior event → Information when formed; same rule.
Findings       R-6 ("many-to-one allowed" states records→Information;
               M:N unaddressed — one record containing several
               formable findings is a real shape).
Disposition    REVISE (minor).
```

### CC-6 — Relations are Information-to-Information only

```text
Traceability   D1(a) endpoints are InformationIDs; D3(a) immutable;
               no predicate taxonomy; R1–R6 store contract. "No
               relation semantics buried in carrier metadata" is the
               anti-reforking clause the ruling demanded.
Carrier-only?  NO — this is existing semantics, correctly cited (EX).
File/Session   cross-domain retrieval works at carrier level (CC-2,
               no semantics) and information level (through CC-5
               mapping, where Relations apply). X4 ("file revision →
               judgment history") composes Relation + mapping +
               historical pin — verified composable, no new semantics.
Findings       none.
Disposition    PASS.
```

### CC-7 — Derived access layer

```text
Traceability   PB v1.2 rebuild equivalence extended; P8 F7 retired by
               IndexSource (identity coverage AND searchable-content
               coverage, rebuild-compare verified). "Never a fact or
               identity source" + "derived noise not presented as
               facts" = O-U0-4 + O-U0-5 obligations.
Carrier-only?  YES.
File behavior  FTS/extraction derived from file bytes; IndexSource =
               representation + extraction version.
Session behavior summary/embedding/KG derived from raw events;
               IndexSource = event.
Findings       none.
Disposition    PASS.
```

### CC-8 — The six identity relations

```text
Traceability   #1 and #5 cite frozen artifacts (verified against code,
               §2/R-4 of this review); #2/#3/#4/#6 are carrier-layer
               definitions — exactly the ruling's split.
Carrier-only?  as table: #1/#5 EX; #2/#3/#4/#6 CO. Correct.
Boundary test  the mandated ≠ chain holds at clause level: Information
               Identity (formation-only) ≠ Carrier Identity (CC-1) ≠
               Record Identity (CC-3/CC-4) ≠ Derived Index Entry (CC-7);
               Representation Identity is present but IMPLICIT (inside
               #2's wording) although IS-IDLOC-SEAM-01 treats it as a
               distinct concept (see R-10). Historical Pin behavior
               remains PB v1.2-governed via UA-P3 (noted, no defect).
File/Session   the chain is family-independent by construction.
Findings       R-8, R-10.
Disposition    REVISE (two precision items).
```

### CC-9 — Hard constraints

```text
Traceability   ruling §5 carried verbatim with the message-2 tightening
               applied. No new constraint invented, none dropped.
Findings       none.
Disposition    PASS.
```

## 5. Semantic conflicts

```text
None found at the frozen-artifact level.

The UA-P6 test was applied to every UA-CC and UA-F clause: no sentence
redefines, extends, or specializes Information or Relation semantics.
The closest case is R-8 — a WORDING defect in CC-8 #1 that could be
MISREAD as contradicting the deterministic minting-input decision
("never re-derived from ... digest" vs minting input = content + source
+ chunkIndex). It is a wording defect in the review object, not an
assertion of new semantics, therefore classified REVISE, not
CONTRADICTION/BLOCK.
```

## 6. Carrier-only obligations (explicit register)

```text
CO-1  Carrier identity, carrier_kind, locator/locator_state,
      representation versioning (CC-1) — new carrier-layer concepts;
      explicitly independent of Information Identity.
CO-2  The seven-verb capability surface (CC-2).
CO-3  CarrierRecord model + opaque record_kind vocabulary (CC-3).
CO-4  Ordering stability mechanics for both families (CC-4).
CO-5  The mapping object and its append-only correction rule (CC-5
      mechanics; the formation rule it defers to is existing).
CO-6  Derived access layer + IndexSource + rebuild-compare (CC-7).
CO-7  Identity relations #2/#3/#4/#6 and their lifecycle boundaries
      (CC-8).
CO-8  CC-9 governance constraints (inherited from the ruling).

Everything else in UA-CC either cites existing frozen semantics
(CC-6; CC-8 #1/#5; §4) or inherits PB v1.2 via UA-P1/P3/P5.
```

## 7. File/Session symmetry findings

```text
S-1  RESIDUE (REVISE, R-2): §8 line 407 still says "Session Information
     Record streams" — a v0.1 term. Under the tightened model this must
     read "SESSION-family CarrierRecord streams". This is the only live
     residue; grep across v0.2 finds no other instance.
S-2  CLEAN: "a Session is an Information" appears only inside the §0
     revision summary as a recorded correction (lines 36, 42), not as a
     live assertion.
S-3  CLEAN: no kind/title/summary/status fields were adopted into
     layer ① (grep: zero hits). The rebaseline proposal's "Information:
     id/kind/title/summary/status/timestamps" sketch was correctly NOT
     carried into the contract; summary belongs to layer ④, title/
     status are SimiGo-side and undecided.
S-4  TERMINOLOGY NOTE (pin at revision): the ruling vocabulary "File
     Information / Session Information" (workload-family labels, used
     in the direction ruling itself) coexists with the model-level
     single `Information`. Both are legitimate; the contract should pin
     with one sentence that these are workload-family labels, never
     model-level class names.
S-5  CLEAN: no FileStore/SessionStore core-store language anywhere;
     §11 U-A is expressed as one contract implementation with two
     instance families.
```

## 8. Real-workload mapping (File Carrier diagnostic)

The designated real scenario is the one that actually ran during the
previous round: Agent A (research work producing/modifying repository
files) in parallel with Agent B (Lab organization: estate census,
coverage index, recovery navigation). All cases below are verifiable in
git history. Per the Human's instruction, these are registered as File
Carrier diagnostic observations ONLY — none is promoted into new
Information Space semantics.

```text
D-1  Authoring (Agent A, commit 27bc805: 6 files, +2465 lines)
     UA-CC expression: File Carrier records = the new files/sections;
     each commit = new representation (versioned, fingerprinted);
     whether any doc becomes an Information is a SimiGo formation
     decision (CC-5: record existence never creates Information).
     VERDICT: explainable, no second semantics.

D-2  External modification + concurrent observation (Agent B committed
     Agent A's working files as ca4ddb5 while Agent A kept editing;
     Agent A's subsequent index edit hit "file modified since read" and
     was re-read then re-applied as fe4e5ec)
     UA-CC expression: fingerprint change = new representation observed;
     representations immutable (old preserved in history) so nothing is
     blind-overwritten; re-read-before-write enforced at tool level.
     GAP: observation/compare/re-decide on external modification is
     composable from CC-1+CC-8 #2 but is not an explicit contract
     clause — registered as R-8′ (see §10: suggested explicit
     conformance obligation candidate at revision time).

D-3  Estate reorganization without identity loss (branch switch
     integration/path-a-information-place → codex/research-recovery-
     layer-v0.1; identical content shared as the same content-addressed
     blob across branches)
     UA-CC expression: locator/estate context changed; representation
     identity (content-addressed) stable across the move; Information
     identities unaffected. VERDICT: explainable (CC-4 + CC-8 #2).

D-4  Rename/move: NOT exercised in this round (no renames occurred).
     Mapping by contract composition (CC-4 locator transition, identity
     preserved) with archive-organizer as the designated producer
     (move/rename/remap/journal); real move events belong to the U-4
     realism tier. HONEST BOUNDARY: currently contract-composed, not
     yet workload-observed.

D-5  Derived-index staleness and correction (the L0 index carried
     "Canonical Logical Model gate REQUIRED BEFORE U-2", superseded by
     the operative ruling; detected by comparison against authority and
     corrected in fe4e5ec; the estate census/coverage-index files are
     themselves derived artifacts rebuilt from the corpus)
     UA-CC expression: index ≠ authority (CC-7); drift detectable by
     comparison to authority; refresh = rebuild-from-authority. This is
     the negative case for "derived never becomes fact source".

D-6  Producer attribution across two actors (content authored by
     Agent A; the committing representation produced by Agent B)
     UA-CC expression: carrier-side provenance records the
     representation producer (commit); Information-level Provenance
     (frozen A3) records content authorship. The case REINFORCES R-3:
     the two provenance layers must stay explicitly distinct.
```

## 9. Unresolved ambiguities (decision input for Human ruling / revision)

```text
A-1  (= R-5) Carrier identity minting: what computation/registration
     establishes a Carrier's identity, and for the FILE family, what
     makes it the same carrier across modify and rename. Suggested
     disposition: mark carrier-identity minting as a U-2
     composition-manifest obligation (mechanism-side, mirroring A2′);
     the contract keeps "opaque, stable, carrier-side".
A-2  (= R-6) Mapping cardinality: records→Information N:1 stated;
     M:N unaddressed. Suggested: state N:M by default; restrictions
     are per-decision.
A-3  (= R-9) FILE-family record_kind vocabulary: the U-0 nine kinds are
     session-work-flavored. Suggested: register FILE-kind extension as
     a SimiGo-side decision input for the UA revision (carrier stays
     opaque either way; zero semantic risk).
```

## 10. Findings register (precise problems + revision suggestions)

```text
R-1  §5 (UA-F3): "delete raw session event -> Information loss" is
     imprecise under CC-5. A formed Information persists (A1) when its
     source record is deleted; what is lost is the authoritative
     carrier content, the formation basis, and the CC-5 mapping's
     content reference. Suggested wording: "authoritative carrier-
     content loss: destroys the record, its formation basis, and the
     mapping's content reference; already-formed Informations persist;
     typed, visible, forbidden as routine."

R-2  §8 line 407: residual v0.1 term "Session Information Record
     streams". Suggested: "SESSION-family CarrierRecord streams".

R-3  CC-1: the field name "provenance" (where the carrier itself came
     from) collides with the frozen Information.Provenance type (A3).
     Suggested: one explicit sentence distinguishing Carrier provenance
     (carrier-side origin/recording facts) from Information Provenance
     (frozen A3); or rename the carrier-side field. D-6 shows why the
     distinction matters in practice.

R-4  CC-2: relationship to CCS-C8 (resolve/consume/produce/pin/
     continue) unstated; two verb vocabularies coexist. Suggested: one
     sentence — CC-2 capabilities underlie the C8 interface obligations;
     C8 remains the SimiGo↔carrier interface authority.

R-5  CC-1/CC-8 #2: carrier-identity formation/minting rule unspecified;
     FILE-family same-carrier-across-modify/rename question unmarked.
     Suggested: mark as U-2 composition-manifest obligation (see A-1).

R-6  CC-5: cardinality half-specified (see A-2).

R-7  CC-4: "inherited A1 semantic" — A1 denotes both the frozen ruling
     (immutable value) and the A1 adapter (CarrierSQLite); the intended
     referent is the adapter's atomic-MOVE semantic. Suggested: cite
     "A1 adapter (Phase C kickoff manifest)" explicitly.

R-8  CC-8 #1: "never re-derived from path, name, carrier, or digest" —
     the word "digest" misleads: the registered first-implementation
     minting input is content + source + chunkIndex, so content digests
     DO participate in identity formation mechanism-side. The intended
     statement is about immutability of an EXISTING identity, not about
     formation inputs. Suggested: "assigned at formation (A2′); an
     existing identity never changes due to path, name, carrier, or
     subsequent content versions."

R-9  CC-3: FILE-family record_kind gap (see A-3).

R-10 CC-8: Representation Identity is implicit (inside #2's wording)
     although IS-IDLOC-SEAM-01 treats it as a distinct concept and the
     review's mandated ≠ chain includes it. Suggested: make it explicit
     (content-derived, carrier-side) in the identity table; note that
     Historical Pin behavior remains PB v1.2-governed via UA-P3.

R-11 §2: add the S-4 pinning sentence (workload-family labels vs
     model-level single Information).
```

## 11. Final status

```text
FINAL: REVISE

  - PASS-level (no findings): CC-6, CC-7, CC-9, UA-F1, UA-F4..F13.
  - REVISE-level: CC-1, CC-2, CC-3, CC-4, CC-5, CC-8 (R-1..R-11 above;
    all precision/boundary-marking items; none alters the contract's
    structure or introduces new Information semantics).
  - BLOCK-level: none. No conflict with any frozen artifact.

The contract's structure — four layers, six identity relations with
#1/#5 cited from frozen artifacts, the CC-5 anti-self-promotion clause,
and the CC-9 hard constraints — is sound and fully traceable. The eleven
findings are wording and boundary-marking defects that should be fixed
in a UA v0.3 before Human acceptance review, per the enumerated revision
suggestions above. No replacement semantic contract is proposed here.

U-2 remains NOT AUTHORIZED until the Human accepts the contract.
```
