# CCVS-01 U-0 — Session Evidence Consolidation

> **Status:** DELIVERED / UNAUTHORIZED FOR IMPLEMENTATION
> **Date:** 2026-10-06
> **Authorized by:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_DIRECTION_RULING_20261006.md` (C-6)
> **Purpose:** consolidate the existing Session-side empirical evidence into
> the inheritance basis for the CCVS-01 Unified Addendum (U-1). This is
> evidence inheritance and design-obligation registration, not a new
> experiment, not a schema freeze, and not carrier implementation.
> **Upstream:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_REBASELINE_PROPOSAL_20261006.md` (§2)

---

## 0. What U-0 does and does not do

```text
DOES   trace which Session-side facts are already established, with what
       bounding, and map each to a design obligation for U-1.
DOES   register inherited failure modes as obligations (not as history
       to be re-observed).
DOES   map evidence onto the Session Information Record kinds proposed
       by the rebaseline proposal.

DOES NOT run any experiment or re-run any PALACE V2 probe.
DOES NOT freeze a schema, DDL, or API.
DOES NOT modify MemPalace, InformationCore, RelationCore, or any
       Frozen Contract.
DOES NOT authorize U-2 implementation.
```

All facts below are inherited observations from the PALACE V2 chain
(2026-10-02) and the CCVS-01 File-side chain (2026-10-06). Each carries its
original bounding; none is upgraded by this document.

## 1. Source inventory

| # | Source | What it establishes (session side) |
|---|---|---|
| S1 | `docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMPALACE_OBSERVATION_20261002.md` + `..._RUNTIME_OBSERVATION_20261002.md` | Capability inventory and collision ledger of a real memory carrier (static + runtime) |
| S2 | `docs/00-governance/SIMIGO_LAB_PALACE_REAL_CARRIER_MEMPALACE_V0_INIT_20261002.md` | Real files + real work sessions coexisting in one loaded space (9,311 drawers) |
| S3 | `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_MAIN_PROBE_20261002.md` (+ result gate) | Discovery changes subsequent exploration path; work record ≠ transcript |
| S4 | `docs/00-governance/SIMIGO_LAB_PALACE_V2_G2_EXECUTION_20261002.md` (+ result gate) | Findings reuse enables continuation with zero new reads (T-1..T-3) |
| S5 | `docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_RESULT_20261002.md` (+ result gate) | R1..R5 five-element work-recovery matrix; recovery ≠ Schema |
| S6 | `docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_1_RESULT_GATE_20261002.md` | excluded ≠ safe historical state; reason/basis needed for later re-audit |
| S7 | `docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_2_RESULT_20261002.md` | continue ≠ re-audit: two distinct capabilities (dual-axis separation) |
| S8 | `docs/00-governance/SIMIGO_LAB_PALACE_REALWORK_T1_RESULTS_REVISION_20261002.md`, `..._T2_RESULTS_20261002.md`, `..._T3_RESULTS_20261002.md` | Activation semantics: read path activated by task structure; three-generation memory ecology loop |
| S9 | `docs/00-governance/SIMIGO_LAB_PALACE_Y_RULING_20261002.md` + `..._BOUNDARY_FROZEN_Y_REVIEW_20261002.md` | BR-2 supported (shared Information ≠ agent knowledge); BR-5 (private pointer carries activation) |
| S10 | `docs/02-evidence/es-is-20261005/MEMPALACE_ISMCI_ADAPTER_FEASIBILITY_AUDIT_20261005.md` | MemPalace AS-IS does not meet strict carrier obligations; session value acknowledged separately |
| S11 | P8 record (`..._CCVS01_P8_CRASH_RECOVERY_RECORD_20261006.md`) | F7: searchable text lived only in the derived index (A1 File-side finding) |
| S12 | PB v1.2 freeze (`..._CCVS01_PHASEB_PROTOCOL_FREEZE_20261006.md`) | Frozen tiers already contain Sessions / Session events columns; session append already a measured File-side metric (WL3) |

## 2. Established facts (inherited, with bounding)

```text
F-U0-1  COEXISTENCE (S2)
        Real files and real work sessions have entered the same loaded
        information space simultaneously.
        Bounding: observed on the MemPalace implementation; a coexistence
        demonstration, not a carrier-contract proof.

F-U0-2  WORK-FRONTIER RETRIEVAL VALUE (S3/S4/S5)
        The highest retrieval value in real sessions came from work-frontier
        records: what was discovered, compared, excluded, contradicted, and
        why the next step was chosen. G3 registered these as the five
        recovery elements (current position / findings / exclusions / open
        questions / next step) and explicitly as non-Schema working
        requirements.
        Bounding: PALACE V2 observation level; element list ≠ required
        schema.

F-U0-3  SESSION = PROCESS STATE (S3)
        A discovery in mid-session changed the subsequent exploration path
        (G1 main probe). Session Information is information-work process
        state, not a conversation transcript.

F-U0-4  ZERO-NEW-READ CONTINUATION (S4)
        T-1/T-2 findings were directly reused by T-3; continuation did not
        require re-reading the underlying files (H-G1-02 SUPPORTED, strong
        exploratory). This is the session-side empirical shape of
        no-recompute.

F-U0-5  EXCLUDED ≠ SAFE HISTORICAL STATE (S6)
        A past exclusion can be invalidated by later world change (0308
        twin case). Re-audit requires the original reason, basis, and the
        Information the basis came from, plus visibility of what later
        changed.

F-U0-6  CONTINUE ≠ RE-AUDIT (S7)
        Resuming work and re-examining past judgments are two distinct
        capabilities (dual-axis separation). A carrier must support both
        retrieval paths independently.

F-U0-7  ACTIVATION IS NOT STORAGE (S8/S9)
        Shared Information existing in the space does not mean the agent
        knows it exists (BR-2 supported, no explicit counterexample;
        BR-5: a pointer outside the shared channel carries activation).
        The read path was activated by task structure (T2), and the
        T1→T2→T3 chain shows a working deposit→pointer→consume cycle.
        Carrier obligation: stable addressability and pointer support.
        Activation judgment is Execution-layer, not carrier work.

F-U0-8  RAW ≠ SUMMARY ≠ INDEX ≠ SEMANTIC STATE (S5 + G3 constitution)
        Raw source trace stays authoritative/reconstructable; summaries
        and indexes are derived. This was already the G3 working
        constitution and is the raw/derived basis for U-1 §3.
```

## 3. Inherited failure modes → design obligations

Each failure mode below was actually observed (G0 collision ledger, Real
Carrier v0, P8 F7). None may be silently dropped in U-1.

```text
O-U0-1  XLSX FLATTENING (G0 C-2)
        Observed: sheet retained; cell coordinates lost; formulas lost.
        Obligation: structured representation provenance
        (RepresentationLocator: file → sheet → range/cell/formula), so a
        search hit resolves to a source coordinate, not a flattened blob.

O-U0-2  NUMERIC RETRIEVAL NOISE (G0 runtime observation)
        Observed: exact figures (313,356 / 2,881.34 / 4200) can be
        drowned by semantic/vector ranking.
        Obligation: derived search must include a mandatory exact /
        structured layer (L1); semantic search (L3) must never be the
        only retrieval path for exact values.

O-U0-3  SESSION / SOURCE ORDERING INVERSION (G0 C-4, 0308 twin)
        Observed: session records and their source documents interleaved
        with wrong relative order.
        Obligation: explicit, stable session ordering — the (SessionID,
        sequence) invariant — never inferred from timestamps or file
        order.

O-U0-4  DERIVED-INDEX CONTAMINATION / F7 (G0 C-? ledger + P8 F7)
        Observed: derived index held the only copy of searchable text
        (P8 F7 = REPAIR); rebuild restored identity coverage but not the
        original searchable text.
        Obligation: IndexSource concept — every derived index entry
        traceable to an authoritative source (original file
        representation or raw session event), with deterministic rebuild
        and rebuild-equivalence checking.

O-U0-5  WAKE-UP / CONTEXT POLLUTION (G0 C-5)
        Observed: wake-up noise occupying context; ruling was a≠修
        (kept as-is, collision-ledgered).
        Obligation (negative): wake-up/agent-facing APIs are upper-layer
        interface, not carrier correctness requirements; U-1 must not
        smuggle them into the carrier surface.
```

## 4. Evidence → Session Information Record kinds

The rebaseline proposal §6 lists nine carrier-neutral record kinds. Their
empirical support, inherited from the sources above:

```text
RAW            S2/S8   raw session event stream is the authoritative base
DISCOVERY      S3/S4   G1: discoveries steer the path; G2: reused later
JUDGMENT       S5/S6   G3: judgments are first-class work output
EXCLUSION      S6      RQ-G3-1: exclusions need reason + basis + re-audit
UNCERTAINTY    S5      open questions / not-yet-closed items (R4)
OPEN_QUESTION  S5      R4 element; feeds NEXT_ACTION
NEXT_ACTION    S5      R5 element; the continuation frontier
EVIDENCE_LINK  S4/S6   basis chains: which Information a judgment used
RESULT         S4/S5   T-3-style durable work output

Boundary (unchanged from the proposal):
these kinds are SimiGo semantic vocabulary. The carrier stores, locates,
retrieves, relates, and recovers them; it does not interpret, classify,
or judge them (CCS-C8 boundary maintained). kind is an opaque stored
value from the carrier's point of view.
```

## 5. Inheritance summary for U-1

```text
U-1 must carry forward:
  - File + Session as equal first-class workloads (ruling C-1);
  - the (SessionID, sequence) ordering invariant (O-U0-3);
  - raw/derived boundary with raw session events authoritative (F-U0-8);
  - IndexSource + deterministic rebuild (O-U0-4, retiring the F7 gap);
  - RepresentationLocator structured provenance (O-U0-1);
  - mandatory exact/structured search layer (O-U0-2);
  - Historical Judgment Review as a first-class capability
    (F-U0-5 + F-U0-6);
  - pointer/addressability support without activation semantics
    (F-U0-7);
  - MemPalace capability parity as behavioral acceptance reference, not
    schema (S10 + ruling C-5);
  - no replication of MemPalace objects; MCP/wake-up/UI excluded from
    carrier correctness (O-U0-5).

U-1 must NOT:
  - freeze DDL or physical layout (that belongs to U-2 manifests under
    PB-F6-style rules);
  - modify PB v1.2 numbers, tiers, or frozen rules;
  - extend record kinds beyond the evidence above without new work;
  - couple to ES↔IS higher-layer semantics (standing closure).
```

## 6. Exit condition

U-0 is complete when this consolidation is registered and U-1 drafting
proceeds from it. Both were authorized by the direction ruling (C-6). U-1
delivery returns the state to AWAITING HUMAN REVIEW.
