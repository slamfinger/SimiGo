# Session Log — 2026-10-06

## Current state

```text
Route                                = PALACE / Information Space Foundation
Implementation Gate                  = CLOSED
Frozen Contracts                     = UNCHANGED
InformationCore / RelationCore       = UNCHANGED
Path A default entry                 = ACTIVE
Phase 2 recovery                     = ACCEPTED / BOUNDED PASS / CLOSED
IS-IDLOC-SEAM-01                     = REGISTERED / OPEN / NOT FROZEN / v0.1
PICS-01                              = ACCEPTED / BOUNDED PASS / CLOSED
CCVS-01                              = PB v1.2 FROZEN / PHASE C EXECUTING (File side VALID)
CCVS-01 File side                    = Baseline A PB-B1..B14 ALL MET + P8 G2 PASS
CCVS-01 Unified direction            = ACCEPTED BY HUMAN RULING (File + Session first-class)
CCVS-01 Candidate B1                 = SUSPENDED (registered reason; superseded by Unified scope)
CCVS-01 U-0                          = DELIVERED (session evidence consolidation)
CCVS-01 U-1                          = REVISED BY RULING (B = REVISE, tightened: Unified Carrier Contract over existing semantics)
CCVS-01 U-1 v0.2                     = PROPOSED / AWAITING HUMAN REVIEW
CCVS-01 U-2 implementation           = NOT AUTHORIZED
CCVS-01 Unified benchmark            = NOT AUTHORIZED
Lab physical reorganization          = FROZEN
Backend selection                    = NOT AUTHORIZED (Phase E gate)
OSS integration                      = NOT AUTHORIZED
Migration                            = NOT AUTHORIZED
Higher-Layer ES↔IS semantics         = NOT OPENED
```

## Progress

1. Path A made the current Information Place the default repository entry.
2. Phase 2 restricted default-entry recovery was accepted as a bounded pass.
   It did not prove fully isolated-agent reproducibility or actual continuation.
3. `IS-IDLOC-SEAM-01` separated `Information Identity`, `Representation
   Identity`, `Physical Locator`, and `Historical Pin`.
4. Existing-system review and Core mechanism audit concluded that mature
   substrate mechanisms can provide much of identity/revision/locator/history,
   while semantic identity, applicability, membership, availability meaning,
   lineage, and ES access remain SimiGo/higher-layer work.
5. `PICS-01` reduced database selection to:
   `responsibility → system class → integration seam → workload → protocol`.
6. Human accepted PICS-01 D1-D8 and CCS-C8 as `ACCEPTED / BOUNDED PASS / CLOSED`.
7. The registered PICS-01 gap is that performance was not a formal acceptance
   dimension. It is now mandatory in the successor study.
8. `CCVS-01` was opened only for design, candidate inventory, and validation
   protocol authoring.
9. CCVS-01 mandates a minimum-component baseline and forbids assuming that a
   multi-component architecture is superior.
10. CCVS-01 Phase A D1-D8 was delivered. The comparison unit is a runnable
    architecture composition, not an isolated product capability.
11. Four topologies were defined: Baseline A minimum components, Candidate B
    relational registry + entity store, Candidate C content-addressed
    representation + registry, and Candidate D server registry + object store +
    search.
12. Workload scale tiers are SMALL, MEDIUM, LARGE, and STRESS. Workload families
    cover small-object, large-file, session, relation-heavy, search/rebuild,
    mixed research, and fault/recovery behavior.
13. Integration seams are formal measured objects: write hops, query hops,
    serialization count, durable acknowledgement point, transaction boundary,
    recovery boundary, disk/memory amplification, and adapter thickness.
14. The benchmark protocol and safety limits are authored but not executed.
    Phase B protocol freeze and Phase C controlled validation both require
    separate Human action.
15. Human authorized carrier-neutral interface preconstruction. A new
    `CarrierInterface` target now defines C1-C7 protocols, C8 carrier-interface
    facts, opaque IDs/DTOs, dependency-injected `InformationSpaceRuntime`,
    memory fake stores, conformance suite, integrity/orphan observation,
    benchmark harness, and P50/P95/P99 metrics collector.
16. No backend-specific adapter, schema, storage layout, OSS integration, or
    migration was added. The benchmark harness was not run as candidate
    validation; only Swift build/test verification was run.
17. The preconstruction was expanded to v0.2. `InformationSpaceRuntime` now has
    carrier-neutral copy, split, merge, availability restore, search rebuild,
    and integrity-report operations. The harness covers the complete registered
    workload vocabulary, per-phase resource deltas, optional crash-recovery
    probes, relation traversal, session summary, delete/restore, pin, and index
    rebuild.
18. Conformance expanded to 10 checks: locator identity, historical revision,
    delete availability, restore observation, pin stability, copy lineage,
    split/merge lineage, session order, search rebuild, and C8 boundary.
19. Human reviewed Phase A D1-D8 and the interface preconstruction and issued
    the instruction `进行phase b`. Per charter §10 option A this authorized
    Phase B protocol freeze. Phase B remains documentation only; no benchmark
    was executed.
20. Phase B protocol freeze delivered as CCVS-01-PB v1.0 against baseline
    `0a23fb0`. Frozen: scale tiers without adjustment; deterministic synthetic
    fixture rules (master seed 20261006, UTF-8 text-bounded content, declared
    size bands, relation degree, session order, generator hash recording);
    binding workload WL6 on MEDIUM cold runs; correctness bounds G1-G8 with
    I1-I13 and F1-F9; performance bound set PB-B1..PB-B14 (P95 latency,
    amplification, rebuild, restart, integrity ceilings); repetition counts;
    Phase A §7 resource limits frozen verbatim; run/crash/candidate result
    classes; composition-manifest requirement with a recommended roster;
    frozen anti-complexity rule with concrete thresholds.
21. Any post-freeze protocol change requires an explicit Human ruling. Phase C
    controlled validation requires a separate later authorization. Phase D
    ranks qualified architectures only; Phase E remains the selection gate.
22. Human reviewed the v1.0 freeze and ruled `B / narrow protocol revision`:
    not a Phase A return, not PARK, no new candidate, no backend selection,
    no benchmark execution, no Frozen Contract change, no ES<->IS opening, no
    carrier-neutral implementation change. The ruling was registered as
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEB_REVISION_RULING_20261006.md`
    with mandatory items R1-R7.
23. The protocol freeze was revised to CCVS-01-PB v1.1 implementing R1-R7:
    PB-B1..B14 reclassified as frozen evaluation bounds (not hard elimination
    gates) with a Baseline-A feasibility/protocol-validity check (ACTIVE vs
    UNCALIBRATED, PROTOCOL-VALIDITY-FLAGGED); anti-complexity rule now requires
    end-to-end architecture-level gains, mandatory no-failure conditions, and a
    frozen 2x non-regression line over amplification/RSS/startup/recovery/
    rebuild unless justified in writing; WL6 fixed as primary binding workload
    with WL1..WL7 as mandatory diagnostic/capability evidence; a statistical
    protocol layer froze run definition, per-operation observation minimums,
    serial cold-run policy, median-of-runs aggregation, P99 >= 100-sample
    validity, invalid-run budget, and quiescence checks; amplification
    numerator/denominator and four variants were frozen with steady-state as
    primary; crash semantics were fixed to process-crash/SIGKILL with an
    explicit claim boundary versus power-loss durability; candidate verdicts
    became a layered rule with no weighted total score. v1.1 returns to
    AWAITING HUMAN REVIEW; Phase C remains NOT AUTHORIZED.
24. Human reviewed v1.1 and ruled `B / narrow revision, R4 statistical
    definitions only`: all v1.1 protocol constants accepted (2x
    non-regression, 500/100, 10/20/100, 2x invalid budget, <20% quiescence);
    one statistical ambiguity closed. Registered as
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEB_REVISION2_RULING_20261006.md`.
25. Protocol revised to CCVS-01-PB v1.2: percentiles computed independently
    per valid run; observation minimums per-run, not pooled; candidate-level
    metrics = median of valid run-level percentiles; pooled values demoted to
    clearly-labelled supplemental diagnostics outside the primary chain;
    INVALID restricted to predefined protocol/environment violations with an
    explicit prohibition on invalidating runs for poor performance; quiescence
    defined as three consecutive 5 s windows, an admission condition only.
    v1.2 returns to AWAITING HUMAN REVIEW. Human's stated expected ruling is
    v1.2 = ACCEPT / FROZEN with Phase C NOT AUTHORIZED, backend NOT SELECTED,
    benchmark NOT EXECUTED, ES<->IS opening CLOSED.
26. Human issued the final ruling `A — ACCEPT / FROZEN` for CCVS-01-PB v1.2
    and, in the same ruling's operative final line, authorized Phase C
    Controlled Validation. Registered as
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEB_FREEZE_AND_PHASEC_AUTHORIZATION_RULING_20261006.md`.
    Governance consequence: Phase B is an executable protocol; mid-run rule
    changes are forbidden — a suspected protocol defect stops the affected
    judgment and requires a new Human ruling. Standing restrictions remain:
    final backend selection (Phase E), migration, Lab reorganization, ES<->IS
    opening, Frozen Contract changes.
27. Phase C started under the frozen protocol: first target is Baseline A
    (embedded registry + embedded search + POSIX entity store) with a
    PB-F6 composition manifest, then adapter implementation, conformance,
    and controlled runs under the frozen admission/statistical rules.
28. Phase C kickoff delivered with the A1 composition manifest (seam map =
    zero cross-process seams; durable acknowledgement = fsync + digest check
    for entities and WAL/synchronous=FULL COMMIT for registry; MOVE =
    new-locator + retire in one transaction; pin/availability/identity rules
    per I1/I3/I4/I6/I7/I8; FTS5 derived-only with registry authority rebuild;
    SIGKILL crash model with WAL recovery and explicit repair records;
    SQLite backup API + entity copy smoke boundary; adapter target
    `CarrierSQLite` depending only on CarrierInterface). Next step is A1
    adapter implementation, then conformance, then Baseline A runs first
    (PV1) with per-bound ACTIVE/UNCALIBRATED classification.
29. Human authorized A1 implementation. `CarrierSQLite` delivered as a new
    trackD-memory target: `SQLiteCore` actor (single connection, WAL,
    synchronous=FULL, frozen A1 schema, paired retire/assign IMMEDIATE
    transaction so a runtime MOVE is one atomic locator transition), 
    `POSIXEntityStore` (temp write + fsync + rename + directory fsync +
    digest re-read verification; content addressed by SHA-256 shards),
    SQLite registry/locators/relations/pins/sessions/availability stores,
    FTS5 derived-only search with registry as rebuild authority, integrity
    reporter covering locator/availability cross-checks and orphan entity
    files, and `SQLiteCarrierFactory` / `SQLiteTemporaryRuntimeFactory`
    composition roots. During bring-up one real defect was found and fixed:
    a double `sqlite3_finalize` in the statement wrapper caused SIGSEGV;
    finalize is now idempotent. `latestRevision` orders by insertion rowid
    after the conformance suite exposed produced_at tie instability. Result:
    conformance 10/10 PASS on the real SQLite composition; reopen-persistence,
    atomic-move, and orphan-detection tests PASS; full package test suite PASS
    with no regression. No new semantic behavior, no schema beyond the
    manifest, no caching, no ES<->IS coupling. Next: admission gates, then
    Baseline A runs first (PV1).

30. Human supplied the Unified File + Session Information Carrier rebaseline
    proposal and ruled `按这个设计方向执行。` in response to its registered
    decision point. The proposal was archived verbatim as
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_REBASELINE_PROPOSAL_20261006.md`
    and the ruling registered as
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_DIRECTION_RULING_20261006.md`.
    Governance consequences: CCVS-01 scope extended with the Unified
    File + Session object (File and Session = equal first-class carrier
    workloads); PB v1.2 unchanged and still governing the File side; all
    File-side evidence inherited without re-proof (Baseline A conformance
    10/10, PV1 SMALL+MEDIUM VALID, PB-B1..B14 MET with D-A/D-B/D-C
    classification, P8 G2 PASS with F7 carried as a design obligation);
    candidate B1 SUSPENDED before any manifest/run with a registered
    reason per the PB-F6 roster rule; first Unified candidate = U-A
    Unified Minimal (evolution of A1); MemPalace capability parity =
    behavioral acceptance reference, not schema; U-0 + U-1 documentation
    work AUTHORIZED; U-2 implementation, Unified benchmarks, MemPalace
    integration (U-B), backend selection, migration, Lab reorganization,
    ES<->IS opening all NOT AUTHORIZED.

31. U-0 delivered:
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U0_SESSION_EVIDENCE_CONSOLIDATION_20261006.md`.
    Twelve sources inventoried (G0 static+runtime, Real Carrier v0, G1,
    G2, G3, RQ-G3-1, RQ-G3-2, T1/T2/T3, Y ruling + BR freeze, ISMCI
    audit, P8, PB v1.2). Eight established facts registered with
    bounding (coexistence; work-frontier retrieval value; session =
    process state; zero-new-read continuation; excluded ≠ safe
    historical state; continue ≠ re-audit; activation is not storage;
    raw ≠ summary ≠ index ≠ semantic state). Five inherited failure
    modes mapped to design obligations: XLSX flattening ->
    RepresentationLocator; numeric retrieval noise -> mandatory
    exact/structured search layer; session/source ordering inversion ->
    (SessionID, sequence) invariant; derived-index contamination + P8
    F7 -> IndexSource deterministic rebuild; wake-up/context pollution
    -> upper-layer negative space. Session Information Record kinds
    mapped to their supporting evidence. No experiment, no schema
    freeze, no code.

32. U-1 delivered as UA v0.1 PROPOSED / AWAITING HUMAN REVIEW:
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.1_20261006.md`.
    Contents: conflict/precedence rules (additive only; PB v1.2
    identifiers never redefined); UIS-01 research object; nine logical
    structures frozen as logical schema only (Universal Information
    with opaque kind, Representation, Locator, first-class Session,
    SessionEvent with the hard (SessionID, sequence) invariant, Session
    Information Record kinds, typed File<->Session relations,
    RepresentationLocator structured provenance, IndexSource);
    raw/derived boundary; additive correctness bounds I14-I18, hard
    gates G9-G12, crash points F10-F14 (same verdict vocabulary);
    workload families S1-S8 (new), F family inherited, X1-X8 (new),
    with WL6-U "Unified Research Day" (16 frozen steps) as the primary
    binding workload; mandatory real-corpus diagnostic realism tier
    (archive-organizer as File producer; G1-G3/MemPalace records as
    session source; never entering synthetic fixtures); performance
    bounds PB-U1..PB-U11 starting UNCALIBRATED with the D-A Q1
    amplification discipline; statistical protocol inherited verbatim
    from v1.2 §3.5; candidate compositions U-A/U-B/U-C/U-D with U-A
    first and U-D excluded AS-IS; MemPalace capability parity
    reference; extended seam-cost objects; phase sequence U-2..U-6 with
    explicit gates; negative space; next-gate options A/B/C.

33. Standing restrictions unchanged: no U-2 implementation, no Unified
    benchmark execution, no MemPalace integration, no backend selection
    (Phase E gate), no migration, no Lab physical reorganization, no
    ES<->IS opening, no Frozen Contract change, no PB v1.2 change, no
    mid-run protocol change.

34. Human ruled on the U-1 v0.1 delivery in two messages, the second being
    a self-issued TIGHTENING of the first (both archived verbatim in
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_REVISION_RULING_20261006.md`).
    Verdict: B = REVISE. Direction confirmed (Unified File + Session
    continues; U-0 retained; MemPalace stays closed; PB v1.2 untouched).
    Message 1 designated a ruling block proposing a "Canonical Information
    Space Logical Model" (five layers incl. redefined
    InformationCore/RelationCore/Store). Message 2 tightened it: NOT a
    redesign of Information Space semantics — the work is the **Unified
    Carrier Contract** built ON TOP of the existing, already-defined
    SimiGo Information Space semantics, in four layers: ① semantic layer
    (existing, unchanged) / ② Unified Carrier layer (the current core
    work) / ③ Carrier Representation/Record layer (physical difference
    allowed, one contract) / ④ Derived Access layer (all derived, never
    defines Information). Frozen principle designated by the Human: File
    and Session are two instance families of Carrier, not two semantic
    branches of Information Space; "Session is not a second class of
    Information". Registered consequences R-1..R-5, including the
    required v0.1 corrections (drop Information.kind; remove "a Session
    is an Information"; Session/SessionEvent become Carrier/
    CarrierRecord instances) and the honesty note that the Human
    reviewed the report, not the remote commits (verification commit:
    27bc805).

35. UA v0.2 delivered:
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.2_20261006.md`.
    Scope exactly per ruling: NEW Unified Carrier Contract UA-CC
    (CC-1 Carrier object with FILE/SESSION instance families; CC-2
    common capability surface discover/locate/read/exact-retrieve/
    enumerate/summarize/reconstruct; CC-3 CarrierRecord with opaque
    work-record kinds; CC-4 carrier-internal ordering stability
    generalizing (SessionID, sequence) and RepresentationLocator;
    CC-5 Information↔CarrierRecord mapping — record existence never
    creates Information, formation only through existing semantics;
    CC-6 relations Information-to-Information only, existing
    RelationCore semantics, no relation semantics in carrier metadata;
    CC-7 derived access layer with IndexSource; CC-8 the six identity
    relations with lifecycle/mutability boundaries — #1 and #5 cited
    from frozen artifacts, not re-specified; CC-9 hard constraints
    from the ruling). Layer ① cited with verified frozen surfaces
    (InformationCore A1-A5/B1-B3/S1-S6/A2′; RelationCore
    D1(a)/D2(a)/D3(a)/R1-R6). All v0.1 verification content retained
    and re-labelled as contract verification (I14-I18, G9-G12, F10-F14,
    S/X families, WL6-U, PB-U1..U11); zero new workload/fixture/gate
    definitions. v0.1 file marked SUPERSEDED with the three corrected
    defects recorded. UA v0.2 returns to AWAITING HUMAN REVIEW; U-2
    remains NOT AUTHORIZED.

36. Human commissioned the UA v0.2 Unified Carrier Contract Conformance
    Review (review-only; no implementation, no PB v1.2 change, no
    RESEARCH_STATE.md change). Delivered as
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_V0_2_CONFORMANCE_REVIEW_20261006.md`.
    Method: every UA-CC/UA-F clause tested against UA-P6 (frozen
    artifacts win), the tightening test (Session as second class of
    Information), and the identity-boundary chain, with anchors verified
    against current code (Information.swift: identity + verbatim
    content + Provenance + optional ContentDate; NO kind/title/summary/
    status). **Final status: REVISE** — eleven precision/boundary
    findings R-1..R-11 (deletion-wording "Information loss" imprecise
    under CC-5; §8 residual term "Session Information Record";
    Carrier-provenance vs frozen A3 Provenance name collision; CC-2 vs
    CCS-C8 relationship unstated; carrier-identity minting unmarked as
    U-2 manifest obligation; mapping cardinality N:M; "inherited A1
    semantic" ambiguous ruling-vs-adapter; CC-8 #1 "digest" wording
    vs registered minting input content+source+chunkIndex; FILE-family
    record_kind gap; Representation Identity implicit vs
    IS-IDLOC-SEAM-01; workload-term pinning). **Zero BLOCK, zero
    CONTRADICTION** — no clause redefines Information/Relation
    semantics; CC-6/CC-7/CC-9 and UA-F1/F4..F13 pass clean. Symmetry:
    only one live residue (§8 line 407); no core-store split language.
    Real-workload mapping registered six cases from the actual Agent
    A/Agent B parallel round (authoring, external modification +
    re-read-before-write, estate reorganization with content-addressed
    stability, rename/move = contract-composed but not yet observed
    [honest boundary], derived-index staleness corrected against
    authority, dual-producer provenance) — all explainable by UA-CC
    composition without a second semantic model, and registered as
    diagnostic only, not promoted to semantics. Three unresolved
    ambiguities (carrier-identity minting, mapping cardinality,
    FILE-family kinds) registered as decision inputs. U-2 remains NOT
    AUTHORIZED until Human accepts the contract; suggested next step =
    UA v0.3 implementing R-1..R-11 after Human ruling on this review.

## Key documents

```text
PICS-01 study
  PALACE_INFORMATION_SPACE_FOUNDATION_PICS01_CARRIER_COMPONENT_STUDY_20261006.md

PICS-01 closure
  PALACE_INFORMATION_SPACE_FOUNDATION_PICS01_CLOSURE_RULING_20261006.md

CCVS-01 charter
  PALACE_INFORMATION_SPACE_FOUNDATION_CARRIER_CANDIDATE_PERFORMANCE_VALIDATION_CHARTER_20261006.md

CCVS-01 Phase A
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEA_DESIGN_20261006.md

CCVS-01 interface preconstruction
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_INTERFACE_PRECONSTRUCTION_20261006.md

CCVS-01 Phase B protocol freeze
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEB_PROTOCOL_FREEZE_20261006.md

CCVS-01 Phase B revision ruling
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEB_REVISION_RULING_20261006.md

CCVS-01 Phase B revision ruling 2
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEB_REVISION2_RULING_20261006.md

CCVS-01 Phase B freeze + Phase C authorization ruling
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEB_FREEZE_AND_PHASEC_AUTHORIZATION_RULING_20261006.md

CCVS-01 Phase C kickoff + A1 manifest
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEC_KICKOFF_AND_A1_MANIFEST_20261006.md

CCVS-01 U-0 consolidation
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U0_SESSION_EVIDENCE_CONSOLIDATION_20261006.md

CCVS-01 U-1 v0.2 conformance review
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_V0_2_CONFORMANCE_REVIEW_20261006.md

CCVS-01 U-1 revision ruling (two messages, second operative)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_REVISION_RULING_20261006.md

CCVS-01 U-1 addendum protocol v0.2 (CURRENT)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.2_20261006.md

CCVS-01 U-1 addendum protocol v0.1 (SUPERSEDED, history)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.1_20261006.md

CCVS-01 Unified rebaseline proposal (archived verbatim)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_REBASELINE_PROPOSAL_20261006.md

CCVS-01 Unified direction ruling
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_DIRECTION_RULING_20261006.md

CCVS-01 A1 adapter code
  trackD-memory/Sources/CarrierSQLite/ (CarrierSQLite target)
```

## Next legal transition

```text
CCVS-01-PB v1.2 remains FROZEN. The Unified direction ruling extended the
CCVS-01 scope: File Information and Session Information are equal
first-class carrier workloads, with the archived rebaseline proposal as
design basis. The U-1 revision ruling (B = REVISE, tightened) fixed the
revision target: the Unified Carrier Contract over the EXISTING SimiGo
Information Space semantics — File and Session are Carrier instance
families, not semantic branches.

Current step: Human review of UA v0.2 (Unified Carrier Contract) ->
ruling (option A ACCEPT/FREEZE, option B REVISE, or option C PARK).
U-2 implementation and Unified benchmark execution remain NOT AUTHORIZED
until separately ruled.

Standing restrictions: no final backend selection (Phase E gate), no
migration, no Lab reorganization, no ES<->IS opening, no Frozen Contract
change, no PB v1.2 change, no mid-run protocol change.
```

Any suspected protocol defect during Phase C stops the affected judgment and
requires a new Human ruling before the affected results are classified.
