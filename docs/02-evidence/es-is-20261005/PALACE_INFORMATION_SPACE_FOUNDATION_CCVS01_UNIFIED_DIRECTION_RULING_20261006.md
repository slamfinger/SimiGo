# CCVS-01 Unified Direction Ruling

> **Status:** REGISTERED
> **Date:** 2026-10-06
> **Scope:** CCVS-01 — Carrier Candidate & Performance Validation
> **Relationship to CCVS-01-PB v1.2:** additive scope extension. PB v1.2 is
> NOT modified, re-opened, or re-frozen. This ruling registers a Human
> direction and its governance consequences only.

## 1. Human instruction (verbatim)

```text
按这个设计方向执行。
```

The instruction was issued in direct response to the archived proposal:

```text
docs/02-evidence/es-is-20261005/
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_REBASELINE_PROPOSAL_20261006.md
```

## 2. Ruling interpretation

The proposal's registered decision point was:

```text
是否接受：
CCVS-01 增加
"Unified File + Session Information Carrier"
作为正式验证范围？
```

The Human instruction answers this decision point in the affirmative. The
ruling therefore registers:

```text
Ruling = CCVS-01 Unified direction ACCEPTED.

CCVS-01 formal validation scope is extended with the
"Unified File + Session Information Carrier" object.

File Information and Session Information are equal first-class
carrier workloads in the extended scope.

Session Information is not File metadata and not a Memory
application layered above the Information Space.
```

The proposal remains the archived design basis. Design commitments inside it
(workload families, logical structures, bounds, topologies, phase sequence)
become binding only through the U-1 Unified Addendum Protocol and only after
that protocol's own Human review ruling. This ruling authorizes the path to
that protocol; it does not itself freeze protocol content.

## 3. Governance consequences

```text
C-1  CCVS-01 scope extended (Unified File + Session) as above.

C-2  CCVS-01-PB v1.2 remains FROZEN and governs the File side exactly as
     frozen. The Unified Addendum is a separate additive protocol layer.
     In any conflict, File-side results, bounds, and frozen rules stand
     unchanged. Mid-run protocol change remains forbidden.

C-3  Existing File-side evidence is INHERITED without re-proof:
       Baseline A (A1 CarrierSQLite) conformance 10/10;
       PV1 Baseline A SMALL 5/5 + MEDIUM 5/5 VALID;
       PB-B1..B14 ALL ACTIVE/MET (with the D-A/D-B/D-C calibration
       classification: Q1 steady-state allocated-block footprint =
       primary amplification metric; B10 = 1.11x; B11 = 1.006x);
       P8 crash/recovery COMPLETE / G2 PASS (SIGKILL scope), including
       the F7 finding (searchable text lives only in the derived index)
       which is carried forward as a design obligation, not discarded.

C-4  Candidate B1 (server/embedded relational registry + POSIX entity
     store) adapter work is SUSPENDED before any B1 manifest or run.
     Registered reason per the PB-F6 roster rule ("substitutions require
     a registered reason before runs"): the Human-accepted scope
     extension supersedes the File-only roster progression; the next
     candidate is U-A Unified Minimal, not B1. A1 remains delivered,
     validated File-side evidence and the direct ancestor of U-A.

C-5  First Unified candidate after addendum freeze = U-A Unified Minimal
     (evolution of Baseline A), per the proposal's decision point.
     MemPalace is NOT the first candidate. MemPalace capability parity
     is the U-A behavioral acceptance reference, not a schema reference;
     MemPalace objects (wing/room/drawer/closet) are not replicated.

C-6  AUTHORIZED by this ruling (documentation work only):
       U-0  Session Evidence Consolidation
            (inheritance of G0 / Real Carrier / G1 / G2 / G3 /
            RQ-G3-1 / RQ-G3-2 evidence into the Unified design basis;
            no new experiment, no re-run);
       U-1  Unified Addendum Protocol drafting (v0.1)
            (PROPOSED / AWAITING HUMAN REVIEW on delivery).

C-7  NOT AUTHORIZED by this ruling:
       U-2 implementation (A+ Unified carrier code);
       session/unified benchmark execution;
       MemPalace integration in any topology (U-B);
       backend selection (Phase E gate unchanged);
       migration; Lab physical reorganization;
       Higher-Layer ES<->IS opening;
       Frozen Contract change;
       CCVS-01-PB v1.2 change;
       InformationCore / RelationCore change.
```

## 4. Consistency with standing rulings

```text
- MEMPALACE AS-IS NO-GO as direct PRQ-ISF-01 independent semantic carrier
  stands; nothing here re-opens it. U-B (MemPalace-derived retrieval
  topology) remains a separately-gated future candidate, acknowledged by
  the proposal itself as post-U-A.
- The ISMCI adapter feasibility audit
  (MEMPALACE_ISMCI_ADAPTER_FEASIBILITY_AUDIT_20261005.md) and the Core
  Sufficiency Audit boundary (MemPalace native semantic surface vs
  InformationCore) remain the cited basis for C-5.
- The F7 P8 finding and the MemPalace G0 collision ledger (XLSX
  flattening, numeric retrieval noise, ordering inversion, derived-index
  contamination) enter the U-0 consolidation as design obligations.
- Session workload counts were already frozen inside PB-F1 tier tables;
  the addendum extends workload families and structures, not tier
  numbers.
```

## 5. Next gate

```text
U-0 and U-1 delivery -> Human review of U-1 v0.1 ->
ruling: REVISE or ACCEPT / FREEZE ->
then, separately, Human decision on U-2 authorization.
```

No step beyond U-1 delivery is authorized by this ruling.
