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
CCVS-01                              = PB v1.2 FROZEN / PHASE C FILE SIDE EXECUTED AND VALID / UNIFIED U-2 AUTHORIZED / U-A EXECUTING
CCVS-01 File side                    = Baseline A PB-B1..B14 ALL MET + P8 G2 PASS (delivered evidence, inherited)
CCVS-01 Unified direction            = ACCEPTED BY HUMAN RULING (File + Session first-class)
CCVS-01 Candidate B1                 = SUSPENDED (registered reason; superseded by Unified scope)
CCVS-01 U-0                          = DELIVERED (session evidence consolidation)
CCVS-01 U-1                          = UA v1.0 FROZEN (Gate B ACCEPT / FREEZE; R-1..R-11 + A-1..A-3 + CC-MA + five freeze conditions incorporated)
CCVS-01 UA v1.0 freeze ruling        = ACCEPT / FREEZE — docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_V1_0_FREEZE_RULING_20261006.md
CCVS-01 Unified U-2                  = EXECUTED AND ACCEPTED (Human ruling 2026-10-06: U-A Correctness Acceptance — Ownership/Visibility/Effect boundaries closed; A/B/C all ACCEPT; 32/32 tests; MA-DS-1 run 11 VALID) / Gate C = STARTED / OPEN → READY FOR CLOSURE REVIEW (closure package submitted; closure = separate Human action)
CCVS-01 U-A manifest                 = v1.1 (self-audited) — docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_UNIFIED_MINIMAL_COMPOSITION_MANIFEST_20261006.md
CCVS-01 U-A manifest self-audit      = COMPLETE / NO SEMANTIC UPGRADE FOUND / 3 BOUNDING AMENDMENTS (A1-A3) / SA-4 CLEAN — docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_MANIFEST_SELF_AUDIT_20261006.md
CCVS-01 U-A mechanism evidence       = docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_MECHANISM_IMPLEMENTATION_EVIDENCE_20261006.md
CCVS-01 U-A MA-DS-1 evidence         = docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_MADS1_EVIDENCE_20261006.md
CCVS-01 U-A MA-DS-1 artifacts        = trackD-memory/mads1-report.json + trackD-memory/mads1-final-state.json (runner: Sources/CarrierMADS1)
CCVS-01 U-A implementation findings  = UA-IF-1/2/3/3b/3c/4 + round-4 ruling applied: MA-7 zero-effect boundary extends to the POSIX entity layer — replay/CAS/identity admission ALL precede any durable external effect inside one write transaction; deterministic rejections leave ZERO external side effects (crash-only MA-4 orphan window preserved, UA-C2 gate inside the open transaction after entity durability); session replay returns the RECORDED terminal outcome (.applied, no .replayed demotion); A (legacy ownership) ACCEPTED by Human; manifest §4.2 divergence flagged for acceptance review (Manifest unmodified per directive)
CCVS-01 U-A verification report      = docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_VERIFICATION_REPORT_20261006.md (six focus areas + rounds 3-5; round 5 = acceptance ruling with layered MA-4 table + run-10 retraction + B proof boundary)
CCVS-01 Gate C closure package       = docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_GATE_C_CLOSURE_PACKAGE_20261006.md (acceptance evidence + research results R1-R5 + layered MA-4 record + acceptance conditions AC-1..4 + run ledger + closure-meaning boundaries; closure = separate Human action)
CCVS-01 U-A mechanisms               = carriers + ua_operations ledger + ua_mapping + client_ref idempotency + ua_index_builds; CAS revise / compound entity-then-transaction / carrier-side session allocation / snapshot read-version / index build tracking; crash gates UA-C1/C2/C3 registered for MA-DS-1
Branch governance                    = FINAL CLEANUP VERIFIED; main is sole canonical remote branch; historical refs deleted; history retained in main
CCVS-01 Unified benchmark            = NOT AUTHORIZED
Lab physical reorganization          = FROZEN
Backend selection                    = NOT AUTHORIZED (Phase E gate)
OSS integration                      = NOT AUTHORIZED
Migration                            = NOT AUTHORIZED
Higher-Layer ES↔IS semantics         = NOT OPENED
```

## Branch state after immediate consolidation

```text
main @ 7f7e049                                 = SOLE CANONICAL Research State
codex/research-recovery-layer-v0.1 @ 0078379  = merged source branch; no longer operative
integration/path-a-information-place @ 27bc805 = archived historical subset
codex/execution-state-research-20260929       = historical / not merged
research/es-reuse-program-20260930            = historical / not merged
```

The Human subsequently ordered immediate consolidation because the remaining
branch count was judged excessive. This supersedes the earlier merge timing
instruction only. UA v0.3 remains in HUMAN REVIEW / FREEZE GATE; U-2 remains
NOT AUTHORIZED.

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

37. Human ruled on the v0.2 conformance review in three messages (all
    archived verbatim in
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_REVIEW_RULING_AND_CCMA_MANDATE_20261006.md`):
    **B = REVISE** — direction and the review's semantic-anchoring
    conclusion ACCEPTED (no conflicts; no Canonical Logical Model; no
    return to Information/Relation/Store basics); v0.2 NOT frozen;
    UA v0.3 mandated with R-1..R-11 fixes, A-1..A-3 dispositions, and a
    NEW mandatory contract surface **CC-MA — Multi-Agent Carrier
    Consistency** (multi-agent parallel work = high-frequency future
    scenario = first-class database-design constraint NOW, not later).
    Message 1 supplied the C1–C10 capability catalog verbatim, the
    concurrency design objects (Object Version / Operation Identity /
    Write Intent / Idempotency Key / Snapshot-Read Version / Index
    Build Version / ...), the Multi-Agent Research Day binding design
    scenario, unified-concurrency-model-across-families, and
    Agent-as-actor-only positioning (no AgentInformation/AgentRelation/
    AgentStore). Message 2 supplied the honest capability-gap table of
    the current preconstruction (architecture compatible, capability
    not yet fully covered; InformationSpaceRuntime deliberately does
    not unify cross-component transaction semantics) and its
    verification boundary (CarrierSQLite local implementation not
    assessed). Message 3 = formal instruction with B.1-B.3 special
    preserves (record deletion ≠ Information deletion;
    Information.Provenance vs carrier-operation provenance; identity
    formation input vs identity stability rule) and D-prohibitions
    (incl. not promoting the real parallel scenario to a completed
    concurrency validation).

38. UA v0.3 delivered:
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.3_20261006.md`.
    R-1..R-11 all closed (R-1/B.1 authoritative-carrier-content-loss
    wording; R-2 residue removed; R-3/B.2 carrier_provenance two-layer
    distinction; R-4 CCS-C8 relationship; R-5/A-1 carrier-identity
    minting deferred to U-2 manifest; R-6/A-2 N:M default flagged for
    Human confirmation; R-7 A1-adapter citation; R-8/B.3
    formation-input vs stability-rule; R-9/A-3 FILE-kind open decision
    input; R-10 Representation Identity as explicit CC-8 row #7;
    R-11 workload-label pinning). **CC-MA added (§3A)**: MA-1..MA-10 =
    C1-C10 verbatim; concurrency design objects (never semantic
    objects); ONE unified concurrency model across both families (no
    FileConcurrencyStore/SessionConcurrencyStore split); Agent =
    actor only; **MA-DS-1 "Multi-Agent Research Day"** binding design
    scenario (explicitly NOT a completed validation) with additive
    correctness bounds **I19-I25** (no lost update / no identity
    duplication / no dangling provenance / no invalid cross-version
    relation / no session reorder / no duplicate retry / no
    derived-index corruption); honest capability-status table of the
    current preconstruction recorded as design basis; UA-P7 added
    (concurrency = carrier-layer correctness mechanisms; layer ① needs
    no concurrency protocol beyond S1-S6/R1-R6). CC-MA mechanisms are
    mandatory U-2 composition-manifest check items. v0.2 marked
    SUPERSEDED with full review lineage.

39. Targeted Conformance Review delivered (per ruling E, five points
    only):
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_V0_3_TARGETED_CONFORMANCE_REVIEW_20261006.md`.
    Every verification evidence-based (grep/inspection of v0.3 text).
    **FINAL: NO BLOCK** — (1) R-1..R-11 closed; (2) A-1..A-3 explicit
    dispositions without self-deciding; (3) CC-MA compatible with
    frozen semantics (UA-P6/P7 clean; no MA clause implies Information
    mutation; MA-5 forbidden equivalences reinforce frozen identity);
    (4) family isomorphism retained under one concurrency model;
    (5) identity boundaries now fully explicit (≠ chain stated in
    full; Representation Identity and dual provenance no longer
    implicit). Per ruling E the protocol returns to the **HUMAN REVIEW
    / FREEZE GATE**. U-2 remains NOT AUTHORIZED.

40. Human Freeze Review on UA v0.3 registered (verbatim in
    `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_V0_3_FREEZE_REVIEW_20261006.md`):
    design mainline ACCEPTED, no re-architecture, no v0.4, no U-2
    entry; freeze gate OPEN with FIVE CONDITIONS — (1) UA-P7 reworded
    to split "no new semantic concurrency contract" from
    compound-operation atomicity (MA-4 governs the compound case);
    (2) I20 narrowed to "No unintended duplicate Carrier identity or
    conflicting duplicate registration for one logical Carrier
    instance"; (3) unified concurrency frozen as ONE CONTRACT /
    guarantees, NOT one physical algorithm (CAS / atomic sequence
    allocation / SQLite transactions / build-version+swap all
    admissible; Universal Lock Manager forbidden); (4) P8 F7 feedback
    elevated to a U-A must-pass rebuild completeness gate (authority
    must hold searchable source content sufficient for the index's
    promised coverage; otherwise only INCOMPLETE rebuild capability may
    be declared) — A1's F7 stays a valid File-side baseline result but
    is NOT the U-A implementation template; (5) state hygiene (this
    commit). Standing recording requirement FR-7: future crash-boundary
    PASSes carry "PASS (expected detached/orphan state, explicitly
    detected)" or ExpectedPostCrashState = DETACHED_OR_ORPHAN_DETECTED;
    the existing P8 record is not retroactively modified. State
    correction sharpened everywhere: Phase C FILE SIDE = EXECUTED AND
    VALID; Unified U-2 = NOT STARTED.
    HYGIENE NOTE: Progress items 1..39 are append-only historical
    narrative (item 14 reflects its own date, later superseded by
    items 26-29); the three canonical sections (Current state / Key
    documents / Next legal transition) are the ONLY current-truth
    surfaces and have been made unique and conflict-free.

41. Human Branch Consolidation Ruling registered; later superseded in part by an immediate-merge instruction. 
    `docs/00-governance/SIMIGO_LAB_BRANCH_CONSOLIDATION_RULING_20261006.md`;
    verified ancestry: integration @ 27bc805 is a STRICT ANCESTOR of the
    codex line — 0 commits unique to integration). Consequences BR-1..BR-6:
    no immediate merge into main; codex/research-recovery-layer-v0.1 stays
    the current working branch until UA v0.3 freeze; AFTER the Human
    ACCEPT/FREEZE ruling the whole codex branch merges into main with
    --no-ff as a SEPARATE governance action (merge = "this research round
    is official Lab state"), never mixed with experiment progression
    (freeze -> U-2 authorization -> implementation -> experiments -> new
    evidence -> separate stage merge); integration = ARCHIVED historical
    backup from now on (no further commits, not deleted); target end-state
    = main as sole canonical Research State with old ES and es-reuse
    branches as frozen history; future agent entry = main -> Research
    State -> next legal step, no guessing between 27bc805 and the codex
    tip.

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

CCVS-01 review ruling + CC-MA mandate (three messages)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_REVIEW_RULING_AND_CCMA_MANDATE_20261006.md

CCVS-01 U-1 addendum protocol v0.3 (CURRENT)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.3_20261006.md

CCVS-01 U-1 v0.3 targeted conformance review (NO BLOCK)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_V0_3_TARGETED_CONFORMANCE_REVIEW_20261006.md

CCVS-01 UA v0.3 freeze review (FIVE CONDITIONS REGISTERED)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_V0_3_FREEZE_REVIEW_20261006.md

CCVS-01 UA v1.0 freeze ruling (Gate B ACCEPT / FREEZE)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_V1_0_FREEZE_RULING_20261006.md

CCVS-01 U-A Unified Minimal Composition Manifest (CURRENT — U-2 execution basis)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_UNIFIED_MINIMAL_COMPOSITION_MANIFEST_20261006.md

CCVS-01 U-1 v0.2 conformance review (REVISE, R-1..R-11)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_V0_2_CONFORMANCE_REVIEW_20261006.md

CCVS-01 U-1 revision ruling (two messages, second operative)
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_REVISION_RULING_20261006.md

CCVS-01 U-1 addendum protocol v0.2 (SUPERSEDED by v0.3, history)
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
CCVS-01-PB v1.2 remains FROZEN.
UA v1.0 remains FROZEN (Gate B ACCEPT / FREEZE, five conditions
incorporated; protocol + ruling documents registered).

GATE SEPARATION (do not conflate):
  Gate A (CLOSED):    CCVS-01 Phase C FILE SIDE — A1 CarrierSQLite
                      implemented, conformance 10/10, Baseline A SMALL
                      5/5 + MEDIUM 5/5 VALID, PB-B1..B14 MET, P8 F1-F9
                      executed (G2 PASS), D-A/D-B/D-C calibration.
                      Delivered evidence, inherited; nothing here is
                      re-opened.
  Gate B (CLOSED):    UA v0.3 ruled ACCEPT / FREEZE as UA v1.0; five
                      freeze conditions incorporated into the frozen
                      text; R-1..R-11 CLOSED; A-1..A-3 disposed;
                      CC-MA compatible; File/Session isomorphic.
  Gate C (STARTED):   Unified U-2 AUTHORIZED by Human 2026-10-06.
                      U-A Unified Minimal Composition Manifest
                      DELIVERED (requirement → mechanism → observable
                      evidence → pass/fail criterion → MA-DS-1
                      exercise chains for MA-3/MA-4/MA-6/MA-7/MA-9/
                      MA-10 + MA-1/2/5/8; identity minting A-1;
                      mapping/locator/provenance closed loop; rebuild
                      completeness hard gate; MA-DS-1 13-step round-
                      one operationalization; layered verdicts, no
                      total score; UA-DF-n defect protocol).
                      Authorized U-A sequence: manifest (done) →
                      mechanism implementation on the A1 base →
                      conformance (A1 10/10 must not regress) →
                      admission → MA-DS-1 execution → evidence chain
                      packaged for Human audit.
                      NOT done and NOT claimable: Gate C closure —
                      a separate Human action after the evidence
                      chain audit. No experiment results exist yet;
                      none are predicted or pre-announced.

Round-one exclusions (standing): no horizontal carrier-topology
comparison; no backend selection; no carrier migration; no MemPalace
integration; no UA v1.0 / PB v1.2 / Frozen Contract modification; no
PB-U* calibration or larger benchmark (U-3 scope).

Standing restrictions: no final backend selection (Phase E gate), no
migration, no Lab reorganization, no ES<->IS opening, no Frozen Contract
change, no PB v1.2 change, no mid-run protocol change, no Agent
semantic entity / AgentStore / two-family concurrency split, no
separate concurrency database layer, no Universal Lock Manager.
```

Any suspected protocol defect during Phase C stops the affected judgment and
requires a new Human ruling before the affected results are classified.


## Branch consolidation update — 2026-10-06

The Human's latest instruction was to consolidate the Lab repository branch
history into `main`.

Result:
- `main` now points to `6ad810466695ed0703c5291c1039736185465248`.
- `codex/research-recovery-layer-v0.1` is reachable from `main` via
  topology-only consolidation; its stale post-merge documentation is not
  reintroduced into the current tree.
- `research/es-reuse-program-20260930` is also reachable from `main` via
  topology-only consolidation; its historical ES-reuse documents are not
  imported into the current PALACE tree.
- `integration/path-a-information-place` and
  `codex/execution-state-research-20260929` were already fully behind
  `main` and contain no current-only content.

This is repository-history consolidation, not semantic adoption of the old
research lines.

Research gate status is unchanged:
UA v1.0 = FROZEN by Gate B ACCEPT / FREEZE; U-2 = NOT AUTHORIZED; Unified benchmark = NOT AUTHORIZED.

## U-2 authorization and U-A manifest delivery — 2026-10-06

The Human formally authorized U-2 (status changed from
`NOT STARTED / NOT AUTHORIZED` to `AUTHORIZED / READY TO EXECUTE`),
immediately after confirming the Gate B baseline at `232680a`. The
authorization is bounded:

```text
IN SCOPE (U-A round one):
  FILE + SESSION + mapping + provenance + CC-MA
    → SQLite + POSIX minimal substrate
    → MA-DS-1 "Multi-Agent Research Day"

EXCLUDED (round one):
  horizontal carrier-topology comparison; backend selection; carrier
  migration; MemPalace; UA v1.0 modification; PB v1.2 modification;
  Frozen Contract modification; larger-scale benchmark.
```

Execution principle fixed by the Human: **manifest first, then
mechanisms, then experiment** — every requirement mapped as
`Requirement → Mechanism → Observable Evidence → Pass/Fail Criterion →
MA-DS-1 Exercise` so the post-experiment audit targets the evidence
chain, not unevaluable code.

Delivered this round:

```text
U-A Unified Minimal Composition Manifest v1.0
  PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_UNIFIED_MINIMAL_COMPOSITION_MANIFEST_20261006.md
```

Manifest content summary:

1. Composition definition: one SQLite carrier database + POSIX entity
   store; FILE and SESSION instance families beneath ONE Carrier
   contract and ONE concurrency guarantee set; derived access L1 exact
   + L2 FTS mandatory, L3 semantic absent with registered reason.
2. Identity model: three separate namespaces with separate minting —
   Information Identity (frozen A2′ semantics, untouched), logical
   Carrier Identity (registry-minted opaque CarrierID, never derived
   from path/name/digest), Representation Identity (content digest +
   revision); the CC-8 ≠ chain enforced at clause level; I20 narrowed
   duplicate-registration rule as a registry constraint.
3. Mapping / locator / provenance closed loop: walkable chain
   Information → CC-5 mapping → carrier → representation → bytes and
   back, provenance-bearing at every hop; compound-operation order
   fixed as formation-before-registration with one operation_id
   spanning both sides (UA-P7 mechanism decision).
4. Six mandated chains (MA-3/4/6/7/9/10) plus short-form chains for
   MA-1/2/5/8: each requirement mapped to a concrete SQLite/POSIX
   mechanism (CAS via expected_revision; single-transaction compound
   operations with entity-fsync-then-commit durable acknowledgement;
   carrier-side sequence allocation with client_event_ref idempotency;
   unique operation ledger replay; IndexSource + build_version with
   rebuild-compare over identity AND searchable-content coverage;
   single-read-version snapshot views), each with observable evidence
   and a decidable pass/fail criterion and a named MA-DS-1 step.
5. MA-DS-1 operationalized as a deterministic 13-step two-actor
   scenario with clock-skew, three crash points, and retry episodes;
   step-to-bound mapping pre-registered (I19-I25 coverage: 4.1→I19,
   identity model→I20, 4.2/4.7→I21, 4.6→I22, 4.3→I23, 4.4→I24,
   4.5→I25).
6. Verdict structure: layered per-mechanism / per-bound / conformance
   (A1 10/10 must not regress) / rebuild-completeness (PASS or
   INCOMPLETE) / scenario verdicts; NO weighted total; crash verdicts
   PASS / REPAIR / DETACHED; UA-DF-n typed defect protocol — real UA
   v1.0 gaps are recorded as defects, never explained into a PASS.

Not done in this round, deliberately: no mechanism code, no
conformance run, no MA-DS-1 execution, no result claims of any kind.
Gate C is STARTED, not passed. The next authorized steps are U-A
mechanism implementation on the A1 base, then conformance, admission,
and MA-DS-1 execution, after which the evidence chain is packaged for
the Human audit.

## U-A manifest self-audit — 2026-10-06

The Human ruled the U-A manifest `REVIEWABLE / NO BLOCK` and set a
manifest self-audit as the next checkpoint before mechanism
implementation — the audit question: did the manifest wrongly
"implement-ize" the frozen protocol or silently add new semantics?

Four Human risk points audited clause-by-clause against UA v1.0:

```text
SA-1  MA-4 entity-fsync-then-commit order
      = WORDING RISK CONFIRMED → AMENDMENT A1: the order is a U-A
      composition mechanism for the durable acknowledgement point on
      SQLite + POSIX; UA v1.0 requires the explicit atomic boundary,
      not this physical order.
SA-2  expected_revision / client_event_ref / operation_id /
      build_version / read_version
      = PARTIAL COVERAGE → AMENDMENT A2: §4 SCOPE BOUNDING paragraph —
      the five handles are layer ②③④ implementation/evidence fields
      only; never Information/Relation fields (Information carries NO
      revision field — frozen), never Frozen Contract vocabulary,
      never obligations on other candidates.
SA-3  Representation Identity = SHA-256 + revision
      = WORDING RISK CONFIRMED → AMENDMENT A3: identity rows split
      into REGISTERED PROPERTY (content-derived / carrier-side /
      immutable per version — IS-IDLOC-SEAM-01 / CC-8 #7) vs U-A
      RECIPE (SHA-256 + per-carrier revision; UUIDv4 CarrierID also
      marked a recipe under the CC-1/A-1 obligation).
SA-4  MA-DS-1 as conformance/failure exercise, not benchmark
      = CLEAN, no amendment: manifest §5 already declares it not a
      performance benchmark and not completed validation; no timing/
      percentile/throughput vocabulary in §5/§6; PB-U* calibration
      excluded to U-3.
```

Additional sweep: agent-as-actor only; no new semantic objects; layer ①
untouched; CC-9 honored; FILE record kinds opaque pending A-3; PB v1.2
cited not modified; negative space restated — all PASS.

Result: **NO SEMANTIC UPGRADE FOUND; three bounding amendments applied;
manifest → v1.1.** Zero guarantee changes, zero frozen-text changes,
zero changes to evidence, criteria, or MA-DS-1 step mapping. The audit
does NOT declare "APPROVED FOR IMPLEMENTATION" (a Human action) and
makes no Gate C progress claim. Per the Human's flow, the next step
after this checkpoint is A1 mechanism implementation.

## U-A mechanism implementation + conformance + admission — 2026-10-06

The Human ruled the manifest self-audit APPROVED and authorized **A1
mechanism implementation** with the standing order: do not skip
conformance to reach MA-DS-1, and stop-and-report (never re-write
criteria) if implementation and manifest semantics ever conflict.

Delivered (commit on main, pushed):

```text
Sources/CarrierSQLite/SQLiteCore.swift                  ua_* schema +
  withTransaction / withReadSnapshot / statement / changes primitives
Sources/CarrierSQLite/SQLiteUnifiedCarrierOperations.swift  NEW — the
  §4 mechanisms: identity minting (I20-guarded), CAS revise (MA-3),
  compound entity-then-transaction revise (MA-4), carrier-side session
  allocation with client_ref + operation_id idempotency (MA-6/MA-7),
  CC-5 mapping, consistent snapshot (MA-10), index build tracking +
  staleness + rebuild (MA-9), authority fingerprint + dangling-
  provenance evidence queries; crash gates UA-C1/C2/C3 registered
Sources/CarrierSQLite/POSIXEntityStore.swift            module-internal
  exposure of durableWrite (no protocol change)
Sources/CarrierSQLite/SQLiteCarrierFactory.swift        bundle.operations
Tests/CarrierSQLiteTests/UAOperationTests.swift         NEW — 11 tests
```

Results:

```text
UAOperationTests 11/11 PASS (3 consecutive runs)
A1 conformance regression  10/10 PASS (frozen A1 surface unchanged)
Full package suite         stable green across repeated runs
```

Registered finding (reverse anti-pattern check): the first MA-2 test
draft retried a conflicted CAS revise REUSING the operation id and got
the recorded CONFLICT replayed. Manifest §4.1 says "rebase = new
operation with new expected_revision after re-read" — CONFLICT is
terminal; MA-7 replay covers unknown-outcome re-drive only. Mechanism
confirmed correct against the manifest; the TEST was fixed (fresh
operation_id per rebase attempt). No manifest semantics changed.

Honest boundaries: crash gates wired but multi-process SIGKILL
exercises belong to MA-DS-1 (P8 crash-runner pattern); in-process
concurrency serializes on the single connection (composition
property); no performance measurements (PB-U* stays UNCALIBRATED).

Next within the authorization: MA-DS-1 execution (13 pre-registered
steps), then evidence chain packaged for the Human audit. Gate C
closure remains a separate Human action.

## MA-DS-1 execution — 2026-10-06

The Human accepted the mechanism implementation (UAOperationTests 11/11,
A1 10/10 regression) and authorized MA-DS-1 with three disciplines: no
new mechanisms; the 13-step workload unchanged as pre-registered; outcome
classification strictly per manifest semantics (DETACHED ≠ automatic
failure; REPAIR ≠ mechanism failure), never a PASS-only script.

Executed via a new P8-pattern runner (`Sources/CarrierMADS1`): 17 phases,
of which three are real process-SIGKILL episodes at the wired gates
UA-C1 (after session-append commit), UA-C2 (between entity fsync and the
registry transaction), UA-C3 (inside the rebuild transaction). Dual
actors, clock-skew injection via a creation/clock-decoupling permutation,
operation ledger, authority fingerprints, provenance-completeness
queries, rebuild-compare, and a final state reconstruction are all
captured per step.

Results (two consecutive campaign runs, identical classifications):

```text
S1-S7   PASS (identity minting, closed-loop mapping, concurrent reads,
        cross-family MOVE+revise, stale-write CONFLICT typed with no
        overwrite, rebase with from-version provenance, gapless concurrent
        session ordering under reversed clock skew)
S8      PASS  — UA-C1: commit durable, same-operation_id retry = REPLAYED,
        zero state delta (MA-7/I24)
S9      PASS (expected orphan state, explicitly detected; recovery via
        prescribed idempotent retry) — UA-C2: entity durable, registry
        all-or-nothing, orphan typed and resolved by the retry (MA-4/I21)
S10     REPAIR (prescribed recovery: rebuild re-run from authority) —
        UA-C3: atomic rollback left the old index intact and stale-
        detectable; authority byte-identical; coverage restored (MA-9/I25)
S11-S13 PASS (single-version snapshots, summary materialization with raw
        events intact, full-day identity audit + historical judgment
        reviewable against F1@rev-1 via the CC-5 mapping)
Overall: VALID — no bound violation; all classifications within manifest
semantics. Gate C NOT closed; evidence chain submitted for the Human's
independent audit.
```

Registered implementation findings (manifest-driven corrections, zero
protocol change; both documented in the MA-DS-1 evidence document §3):

```text
UA-IF-1  index-build watermark granularity: ua_index_builds keyed per
         (information_id, carrier_id) — the CC-5 mapping is N:M and
         manifest §4.5 prescribes a per-carrier revision watermark.
UA-IF-2  staleness = built-but-outdated (inner join over existing build
         rows); missing coverage belongs to the rebuild-compare gate, not
         the staleness join.
```

Honest boundaries registered: in-process concurrency rides the
actor-owned single connection (composition property); crash model is
process SIGKILL only; A1-reporter locator/availability invariants do not
bind UA-path representations (composition bookkeeping boundary, residual,
not silently reconciled); no performance measurements.

Artifacts: `trackD-memory/mads1-report.json`,
`trackD-memory/mads1-final-state.json`,
evidence document
`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_MADS1_EVIDENCE_20261006.md`.

## Human code-level audit + correction round — 2026-10-06

The Human performed a code-level independent audit of `d98d5c1` (not a
review of the evidence summary) and ruled:

```text
MA-DS-1 workload        = VALID (13/13, 0 UA-DF, 0 bound violation observed)
U-A implementation      = BLOCKED — two gaps:
  1. BLOCKER (MA-9/I25): UA-IF-1 fixed the build-watermark granularity
     but search_fts stayed information-scoped (no carrier_id column;
     uaIndexDocument deleted by information_id) — indexing Information I
     for Carrier B erased I's searchable representation for Carrier A.
     The N:M / per-carrier rebuild semantics the manifest already writes
     were not fully implemented.
  2. HIGH: INSERT OR IGNORE in the compound revise silently swallowed a
     Representation Identity conflict — same R with a different digest
     would leave operation=APPLIED, revision advanced, stored bytes old
     (violates CC-8 #7 immutability semantics).
Also adopted: precise MA-4 statement (SQLite registry-side compound
transaction atomic; allowed typed detectable orphan window between
entity durable write and registry transaction, with prescribed recovery
path — not "MA-4 proven universally"); UA-C3 REPAIR accepted; the
MA-3/MA-7 operation state machine (APPLIED/CONFLICT terminal; same-id
retry = REPLAYED; rebase = new operation_id) retained as research
evidence.
Explicit discipline: neither finding may be re-labelled "boundary
residual"; no Manifest modification; correction path = manifest →
implementation mismatch → code correction → targeted conformance →
targeted MA-DS-1 regression.
```

Corrections delivered (this round):

```text
UA-IF-3  search_fts v2 with carrier_id (stale-schema drop/recreate is
         legitimate: FTS is derived, CC-7); per-(information, carrier)
         index writes; scoped search API (searchScoped -> UASearchHit;
         neutral CarrierSearchResult unchanged); runtime-path FTS writes
         use NULL carrier_id.
UA-IF-4  duplicate representation registration classified explicitly:
         identical immutable properties -> idempotent REPLAYED (no bump,
         no duplicate row); different properties -> typed
         conflictingDuplicateRepresentation + ledger CONFLICT evidence
         row; carrier state unchanged; INSERT OR IGNORE removed.
Correction-process note: the runtime FTS re-binding was initially
         mis-aligned (3 binds / 4 parameters) and crashed NULL text reads
         under the full parallel suite — caught by the suite before any
         commit, fixed, registered.
```

Targeted verification:

```text
UAOperationTests            13/13 PASS (11 original + 2 new targeted
                            regressions: ma9CarrierScopedSearchableRepresen
                            tations, representationIdentityConflictIsTyped)
CarrierSQLite target        17/17 PASS incl. A1 conformance 10/10 (no
                            regression), full parallel suite green
Targeted MA-DS-1 regression 13/13 within manifest semantics, overall
                            VALID (classifications unchanged)
```

Status: U-A implementation RESUBMITTED for the Human's code-level audit.
Gate C remains STARTED / OPEN — closure is a separate Human action.

## Code-level verification round (audit round 2) — 2026-10-06

The Human ruled: Gate C stays OPEN; U-A implementation RESUBMITTED;
UA-IF-3/UA-IF-4 = FIXED/VERIFY. Directive: no new mechanisms — code-level
verification only, with six focus areas (carrier_id full chain, FTS v2
migration CC-7, replay boundary, conflict atomicity, legacy NULL
boundary, concurrency).

Verification performed (report:
PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_VERIFICATION_REPORT_20261006.md;
instruments: UAVerificationTests 10 tests + full FTS touchpoint trace):

```text
Focus 1  full-chain trace found TWO second-layer defects exactly of the
         predicted class:
   F-1  campaign coverageOf was information-scoped (unscoped search) →
         fixed to (information|carrier) aggregation;
   F-2/UA-IF-3b  legacy runtime upsert/delete deleted by information_id
         alone (would erase U-A carrier-scoped rows) → confined to their
         own NULL-carrier rows.
Focus 2  migration verified CC-7-legal: authority fingerprint
         byte-identical; old derived state discarded with no ghosts; the
         EMPTY index does NOT pass rebuild-compare (no free clean PASS);
         rebuild restores promised coverage. Legacy searchable-text loss
         on whole-index loss = registered P8 F7 property (INCOMPLETE
         rebuild capability for the legacy path under the U-A gate).
Focus 3  replay boundary verified: six-field strictness (same R + same
         digest + different media_type = typed conflict, NOT digest-only
         replay); effects bounded to the attempt's own append-only ledger
         row — object provenance singular, entity bytes/carrier revision/
         mappings/representation row unchanged.
Focus 4  conflict atomicity verified: evidence row committed in its own
         transaction (outside the rolled-back work); state machine
         continues after conflict; dangling provenance 0.
Focus 5  legacy NULL boundary verified: scoped queries never match NULL;
         unscoped reads surface legacy rows as EMPTY carrier scope
         (explicit marker); staleness/rebuild never attribute NULL to a
         carrier; NULL-safe read fix applied (crash caught pre-commit).
Focus 6  concurrency battery (5 scenarios): rebuild vs scoped indexing
         (legal linearizations only), two carriers same information
         (coexistence), conflict racing normal revision (one bump, both
         ledger outcomes, provenance complete), replay racing new
         operation (no duplicates), search during rebuild (only complete
         committed states). Composition note: actor-owned single
         connection; the battery verifies legal linearization, not
         multi-connection parallelism.
```

Test status: 27/27 target tests (4 + 13 + 10); A1 conformance 10/10
no-regression; targeted MA-DS-1 re-run 13/13 VALID (classifications
unchanged). Artifacts refreshed (mads1-report.json).

Gate C remains STARTED / OPEN. The verified package is resubmitted for
the Human's code-level review; no acceptance claimed.

## Correction round 3 (Human second code-level re-audit) — 2026-10-06

Human re-audit verdict: legacy clear/rebuild isolation BLOCKED (upsert/
delete were fixed but the destructive legacy rebuild/clear still wiped
U-A rows); Focus 6 oracle insufficient (identical "legal" sets + weak
staleness allowance); replay external side-effect required a probe
(test first, no solution). Tasks A–D executed:

```text
A  UA-IF-3c ownership fix: legacy clear()/rebuild() now delete ONLY
   carrier_id IS NULL rows; uaRebuildIndex mirror-symmetric (only
   carrier_id IS NOT NULL). Zero unscoped `DELETE FROM search_fts`
   remain. Regression: UA rows survive legacy upsert/delete/clear/
   rebuild; legacy portion exactly rebuilt; mirror verified. PASS.
B  Focus 6 oracles strengthened: strict atomic-visibility (BEFORE/
   AFTER distinguishable sets; ∅/partial/mixed all fail) — one
   test-construction bug found by the strengthened oracle (the rebuild
   task's placeholder empty set counted as an observation) fixed;
   racing writes made linearization-distinguishable (v1/v2 revision);
   weak staleness allowance replaced by strict close-out.
C  Replay side-effect probe (characterization only): registry delta
   zero in all three probes (replay/stale/identity-conflict), BUT the
   EXTERNAL entity side effect is non-zero — P2/P3/P4 entities are
   durably written before the replay/revision/identity checks and
   remain as unreferenced orphans. ADDITIONAL FINDING: replay
   convention inconsistency (compound revise returns the recorded
   .applied outcome; session append returns an explicit .replayed
   marker). Both registered for a Human ruling — no solution designed,
   per directive.
D  Re-run: UAVerificationTests 12/12; UAOperationTests 13/13;
   CarrierSQLiteTests 4/4 (A1 conformance 10/10 no-regression);
   targeted MA-DS-1 campaign 13/13 VALID (run 9). Results reported
   with legacy clear/rebuild, replay side-effect, and oracle strength
   as separate sections (verification report §9.1–§9.3).
```

Gate C remains STARTED / OPEN. U-A implementation NOT ACCEPTED — the
three items above are submitted for the Human's next review, with the
replay-semantics ruling (canonical convention + entity-write ordering)
explicitly reserved for the Human.

## Correction round 4 (Human ruling on replay semantics + entity-layer MA-7) — 2026-10-06

Human round-3 review: A = ACCEPT (legacy ownership boundary closed); B
oracle PASS but interleave observation coverage insufficient; C = BLOCKER
and DECIDABLE — frozen MA-7 already fixes the canonical semantics: retry
returns the RECORDED terminal outcome and performs NO new effects, and
"no new effects" includes the POSIX entity layer. The P2/P3/P4 orphans
were deterministic rejection side effects, not crash orphans — not
legalizable by MA-4.

Corrections delivered (no Manifest change, no mechanism expansion):

```text
C-core   compound revise restructured: admission (operation replay → CAS
         revision → representation identity) ALL inside the write
         transaction BEFORE any durable external effect; deterministic
         rejections leave zero external side effects; rejection evidence
         rows commit with the admission transaction; entity durable write
         happens only after ALL checks pass; UA-C2 gate now sits inside
         the open transaction = the MA-4 crash-only orphan window.
C3       session append same-operation retry returns the recorded
         terminal outcome (.applied); no .replayed terminal outcome.
B        deterministic interleave instrumentation: a second connection
         holds the exact rebuild transaction open; readers forced inside
         the critical section observe exactly BEFORE (WAL snapshot);
         COMMIT → AFTER. Single-connection self-observation is
         impossible without a mechanism seam (out of scope).
Runner   MA-DS-1 step 8 expectation aligned to the recorded-outcome
         convention; MA-7 evidence = zero-effect checks (event count,
         fingerprint).
```

Verification:

```text
focusC1  H1 (fingerprint INCLUDING entity files) == H2 after OP1(P2)
         replay; P2 entity does not exist; one OP1 ledger row.
focusC2  stale rejection → P3 entity absent; state unchanged; one
         terminal CONFLICT row.
focusC3  identity conflict → P4 entity absent; fingerprint delta =
         evidence row only.
focusB   readers inside the forced rebuild critical section see exactly
         BEFORE; after COMMIT, AFTER.
Tests    32/32 target tests green (4 + 13 + 12 + legacy); A1 conformance
         10/10 no-regression; MA-DS-1 run 11 = 13/13 VALID under the
         round-4 semantics.
```

Registered divergence (flagged, Manifest unmodified per directive): the
U-A manifest §4.2 mechanism sentence describes the pre-correction
entity-write ordering; folding it into a manifest v1.2 is the Human's
call at acceptance review. Gate C remains STARTED / OPEN; acceptance
consideration is the Human's next action.

## U-A Correctness Acceptance + Gate C closure package — 2026-10-06

The Human's final review of `b9d2ac1` ruled mechanism correctness and
frozen-document consistency SEPARATELY:

```text
A  legacy ownership         ACCEPT
B  atomic visibility        ACCEPT (proof boundary registered: controlled
                            interleave, not scheduler-complete; no
                            artificial test seams in production)
C  MA-7 zero-effect replay  ACCEPT (entity layer included; C1's
                            entity-inclusive fingerprint H1==H2 is the
                            real MA-7 evidence)
C3 session replay           ACCEPT (recorded-outcome convention; no UA
                            v1.0 or Manifest change needed)
U-A implementation          ACCEPTED — "U-A Correctness Acceptance":
                            Ownership → Visibility → Effect boundaries
                            closed
Manifest v1.1               UNCHANGED (explicit ruling): divergence is
                            an acceptance condition entering future v1.2
                            documentation reconciliation (not forced for
                            Gate C)
Run 10 UA-DF                RETRACTED as protocol defect → registered as
                            verification harness stale expectation /
                            runner defect (run 10 INVALID/runner-error;
                            run 11 VALID)
Gate C                      STARTED / OPEN → ready for closure review;
                            closure remains a separate Human action
```

Layered MA-4 wording registered (prevents future "did v1.2 change MA-4?"
ambiguity): MA-4 guarantee unchanged; orphan classification unchanged/
crash-only; deterministic rejection semantics strengthened; physical
write ordering changed; Manifest §4.2 mechanism wording temporarily
stale.

Delivered: **Gate C Closure Package**
(`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_GATE_C_CLOSURE_PACKAGE_20261006.md`)
— unified acceptance evidence, research results R1-R5, layered MA-4
record, acceptance conditions AC-1..AC-4, full campaign run ledger, and
the closure-meaning boundaries (closure opens nothing: U-3..U-6, Phase
D/E, migration, selection all remain separately gated).

Next: the Human's Gate C closure ruling — CLOSED, or held with
registered reasons. No further U-A repair work is authorized or needed;
the line moves from "implementation candidate" to "acceptable
implementation" per the Human's own wording.

## Gate C closure ruling — 2026-10-06

The Human independently reviewed the Gate C Closure Package at `c91a20c`
and ruled:

```text
Gate A   CLOSED
Gate B   CLOSED / ACCEPT / FREEZE
Gate C   CLOSED / ACCEPT

UA v1.0        FROZEN
Manifest v1.1  FROZEN / UNCHANGED
U-A            ACCEPTED
MA-DS-1        run 11 VALID
```

Ruling basis / implementation basis:

```text
ruling basis        c91a20c — closure package + advisory recommendation
implementation      b9d2ac1
formal record       docs/00-governance/
                    PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_GATE_C_CLOSURE_RULING_20261006.md
```

The Human did not merely adopt the package's `CLOSURE RECOMMENDED`
status: §8 remains advisory, while this section and the ruling document
register the separate final Human ruling.

Boundary findings:

```text
A Ownership    PASS — legacy / U-A destructive operations preserve
               carrier ownership; no unscoped DELETE FROM search_fts.
B Visibility   PASS — controlled interleave shows complete BEFORE or
               AFTER committed snapshots, never an intermediate state.
C Effect       PASS — replay, stale, and identity conflict have zero
               new POSIX entity effect; MA-7 covers the complete
               external-effect surface.
```

The accepted effect chain is:

```text
replay / stale / identity conflict → zero external effect

entity durable
  → process crash / unknown outcome
  → MA-4 orphan
```

Run handling and documentation state remain:

```text
Run 10      INVALID / runner-error / RETRACTED (stale step-8
            expectation; audit trail retained)
Run 11      VALID / 13/13 — closure object
Manifest    v1.1 FROZEN / unchanged; §4.2 temporarily stale and
            registered as implementation/documentation divergence for
            future v1.2 documentation reconciliation
```

Closure scope: Gate C CLOSED closes only the CCVS-01 correctness
question. It does not open U-3 PB-U* calibration/performance, U-4
realism diagnostics, U-5 U-B, U-6 U-C, Phase D ranking, Phase E backend
selection, carrier migration, MemPalace integration, or any Frozen
Contract / UA v1.0 modification. The next legal action is a separate
stage-transition review to select the post-CCVS-01 research question.

## Post-CCVS-01 stage transition and Probe v0.2 acceptance — 2026-10-06

The Human accepted the post-CCVS-01 stage transition and then independently
reviewed Probe v0.1, Probe v0.2, and the U-A Manifest v1.1 boundary.

Current research status:

```text
Stage Transition                       ACCEPTED
Probe v0.1                             ACCEPT IN PRINCIPLE
Probe v0.2                             ACCEPTED
Probe Representation Contract          ACCEPTED
Experiment                             NOT AUTHORIZED
Execution Authorization                NOT YET REQUESTED
```

Design basis:

```text
accepted design       Probe v0.2 at 9b9da6c
v0.1 input            PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_DESIGN_V0.1_20261006.md
v0.2 design           PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_DESIGN_V0.2_20261006.md
formal ruling         docs/00-governance/
                      PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_V0_2_ACCEPTANCE_RULING_20261006.md
```

The Human confirmed that v0.2 separates:

```text
L-C  carrier capability absence
L-R  probe representation / harness failure
L-S  continuation sufficiency failure
```

`L-C` is a current accepted-surface capability finding. It must not be
reported as research-level continuation insufficiency; only `L-S` may carry
that meaning.

The accepted gate order is:

```text
G-R Representation Gate
G-C Capability Gate
  → C1 Reconstruction
  → C2 Continuation Determination
```

If `G-R` or `G-C` fails, C1/C2 must not be evaluated as continuation failure.
The continuation-pointer path is restricted to `NEXT_ACTION` + CC-5 mapping +
Information + existing Information-to-Information Relation semantics when
needed. No `ContinuationPointer` primitive, store, engine, new CarrierRecord
kind, new RelationCore semantics, or Agent semantic entity is authorized.

N-A and N-B are mandatory pre-registered negative controls:

```text
N-A  required reference unresolved / ambiguous → BLOCK_INSUFFICIENT
N-B  continuation boundary ambiguous → BLOCK_INSUFFICIENT
```

`C1 + C2` remains the only necessary success surface. `C3 Action Execution`
is observation only and never contributes to PASS.

Design governance result:

```text
Probe v0.2         ACCEPTED / DESIGN FROZEN
Probe v0.3         NOT WARRANTED
Further revision   NOT REQUIRED
Experiment         NOT AUTHORIZED
```

The next review object is a separate Experiment Authorization Package / Run
Manifest. It must show before execution that: positive E0 uses only existing
UA/U-A primitives; G-R/G-C are mechanically decidable before C1/C2; N-A/N-B
are pre-registered fixture variants; and I-1/I-2 do not secretly retest
CCVS-01. Preparing or submitting that package does not authorize execution.

## Experiment Authorization Package / Run Manifest R01 submitted — 2026-10-06

At frozen governance baseline `39c1031`, the local agent submitted a
documentation-only authorization package for Human review:

```text
package       Experiment Authorization Package / Run Manifest R01
run label     ES-CSP-RUN-01
status        SUBMITTED FOR HUMAN REVIEW — NOT AUTHORIZED
document      docs/02-evidence/es-is-20261005/
              PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_EXPERIMENT_AUTHORIZATION_PACKAGE_RUN_MANIFEST_R01_20261006.md
```

The package does not create a fixture directory, database, fixture artifact, or
run result. It does not request execution by submission alone.

Pre-registered review structure:

```text
S0  Human reviews this package.
S1  If separately approved, prepare independent P-POS / N-A / N-B fixture
    manifests and checksums.
S2  Human reviews the completed fixture manifests.
S3  Only explicit Human run authorization starts ES-CSP-RUN-01.
S4  Human reviews evidence and L-C/L-R/L-S attribution.
```

Representation choices:

```text
objective             RAW + CC-5 mapping
input reference       EVIDENCE_LINK + CC-5 mapping
decision/work record  JUDGMENT + CC-5 mapping
artifact reference    RESULT + CC-5 mapping
boundary state        RESULT + CC-5 mapping
continuation pointer  NEXT_ACTION + CC-5 mapping
```

No `CarrierRelation` is used. No Task/Objective/Artifact/BoundaryState/
ContinuationPointer semantic entity, new CarrierRecord kind, new RelationCore
rule, relation engine, Super Store, embedding, MCP, remote API, or backend is
introduced.

The package fixes:

```text
positive slots      O1, I1, D1, A1, B1, P1
positive pointer    P1 → B1; expected C2 = CONTINUE_CERTAIN
N-A                 independently defined unresolved-reference deficiency
N-B                 independently defined ambiguous-boundary deficiency
negative result     BLOCK_INSUFFICIENT
success surface     C1 + C2 only
C3                  OBSERVATION ONLY
```

Opaque runtime identities, revisions, locators, and checksums are deliberately
marked `MINTED/RECORDED AT FIXTURE PREPARATION`; none is invented in this
package.

Current state:

```text
Experiment                 NOT AUTHORIZED
Execution Authorization    NOT REQUESTED
Fixture preparation        NOT STARTED
Database creation          NOT STARTED
Probe run                  NOT STARTED
```

## R01 first review = REVISE BEFORE S1; R01 Rev1 submitted — 2026-10-06

The Human independently reviewed submitted R01 at `f42762f` and ruled that its
governance boundary, experiment structure, and evidence design were qualified,
but execution packaging required revision before S1.

Formal record:

```text
R01 review    REVISE BEFORE S1
review basis  f42762f
formal ruling docs/00-governance/
              PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_R01_REVIEW_RULING_20261006.md
S1           NOT APPROVED
Experiment   NOT AUTHORIZED
```

The Human confirmed as correct: frozen baseline `39c1031`; no Probe v0.2
change; `S1 ≠ S3`; no database/fixture/result; no hidden semantic entity;
`NEXT_ACTION → CC-5 → Information`; `G-R/G-C` before `C1/C2`; independent
N-A/N-B; I-1/I-2 outside CCVS-01/MA-4; mandatory `EV-R5`; C3 observation only;
and no embedding/MCP/remote-API/Super-Store bypass.

Three required revisions were:

```text
R1  N-B must remain two independent NEXT_ACTION records:
    P1a → B1 and P1b → B2. target_slot remains scalar; no multi-target
    pointer structure is allowed.
R2  Fresh reconstruction must be blinded to fixture role. It receives an
    opaque fixture instance ID; control-side metadata retains
    instance → role and expected result.
R3  Fresh reconstruction must receive a pre-registered opaque stable
    session locator as its deterministic entry point. It must not scan for
    the session or discover it through semantic search / ranking.
```

R01 Rev1 now records those fixes. It remains documentation-only:

```text
R01 Rev1       SUBMITTED FOR SECOND HUMAN REVIEW
S1            NOT APPROVED
Experiment    NOT AUTHORIZED
Fixture prep  NOT STARTED
Probe run     NOT STARTED
```

## R01 Rev1 accepted; S1 fixture preparation complete — 2026-10-06

The Human's second independent review accepted R01 Rev1 at `bce3dc4` and
approved S1 only:

```text
R01 Rev1       ACCEPTED
S0 review     PASS
S1            APPROVED / COMPLETE
S2            REQUIRED
S3            NOT AUTHORIZED
Experiment    NOT AUTHORIZED
```

Formal record:

```text
second-review ruling docs/00-governance/
  PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_R01_REV1_SECOND_REVIEW_RULING_20261006.md
S1 completion record docs/02-evidence/es-is-20261005/ES_CSP_R01_FIXTURE_PREPARATION/S1_COMPLETION_RECORD_20261006.md
```

Three independent fixtures were materialized outside the repository using the
accepted U-A SQLite surface:

```text
P-POS  E3645CE9-F8E3-4DF5-8644-33CD96143F9C  G-R PASS / G-C PASS
N-A    DCC93C19-02B9-4E6C-BDD8-DF3371DF9871  G-R PASS / G-C PASS
N-B    2F204D32-02A4-416E-BEE2-965CD5A626CE  G-R PASS / G-C PASS
```

Each has actual U-A session records, CC-5 mappings, provenance, revision
fields, stable opaque session locator, and SHA-256 payload/manifest evidence.
No `CarrierRelation` or hidden semantic growth was introduced. No C1, C2, C3,
I-1, I-2, Probe Run, or execution result was produced.

Two earlier preparation attempts were aborted by preparer validation and
quarantined as failed attempts:

```text
missing-pointer-records
pointer-target-harness-defect
```

Neither failed attempt was reconstructed, evaluated, or used as an accepted
fixture.

Current state:

```text
S2 fixture manifest review  REQUIRED
S3 execution               NOT AUTHORIZED
Experiment                 NOT AUTHORIZED
Probe run                  NOT STARTED
```

## S2 PASS, explicit S3 authorization, and ES-CSP-RUN-01 executed — 2026-10-06

The Human independently reviewed S1 evidence at `d193556` and ruled:

```text
S2 fixture manifest review    PASS
P-POS fixture                VALID
N-A fixture                  VALID
N-B fixture                  VALID
G-R                          PASS
G-C                          PASS
fixture independence         PASS
reconstruction blinding      PASS
deterministic entry point    PASS
```

The Human preserved an evidence boundary: S2 was manifest/evidence-level
review, not a second physical copy audit of the external fixture roots.

The Human then gave an explicit S3 authorization for `ES-CSP-RUN-01` only.
The local agent registered the authorization and executed the run.

Execution method:

```text
blinded reconstruction inputs  baseline + run label + opaque instance ID +
                               isolated root + opaque stable session locator
randomized fixture order       recorded in s3-run-order.txt
C1                            mechanical reconstruction checks
C2                            NEXT_ACTION records only
C3                            NOT_PERFORMED / OBSERVATION_ONLY
I-1                           clean process stop, then fresh reconstruction
I-2                           durable-acknowledgement witness process loss,
                              then fresh reconstruction
```

Unblinded control comparison produced:

```text
P-POS  I-1/I-2  C1 PASS  C2 CONTINUE_CERTAIN / B1
N-A    I-1/I-2  C1 FAIL  C2 BLOCK_INSUFFICIENT
N-B    I-1/I-2  C1 PASS  C2 BLOCK_INSUFFICIENT
all expected matches  TRUE
research verdict      PASS — CONTINUATION SUFFICIENT
EV-R5                 NOT_APPLICABLE_NO_RESEARCH_FAILURE
```

The N-A failure reason was exactly `input reference
CSP-MISSING-SLOT-00000000 does not resolve`. The N-B reason was exactly
`AMBIGUOUS_POINTER_SET` with pointer targets `B1` and `B2`.

The three registry databases were unchanged by reconstruction; SHA-256 values
matched the S1 completion record. C3 was not performed and did not contribute
to PASS. No fixture, Probe v0.2, U-A code, Manifest, UA, PB, or Frozen Contract
was modified.

Primary evidence:

```text
docs/02-evidence/es-is-20261005/ES_CSP_R01_EXECUTION/S3_COMPLETION_RECORD_20261006.md
docs/02-evidence/es-is-20261005/ES_CSP_R01_EXECUTION/s3-control-comparison.json
```

The bounded run verdict does not open the next research phase.

## R01 final closure and PIR gap registration — 2026-10-06

The Human independently reviewed the S2→S3 authorization chain, S3 completion
record, control comparison, reconstruction source, I-1 outputs, and the
`d193556..ee59150` change scope.

Final ruling:

```text
R01                        CLOSED / ACCEPTED
research verdict           PASS — CONTINUATION SUFFICIENT
claim scope                BOUNDED / registered closure only
rerun                      NOT WARRANTED
Probe v0.3                 NOT WARRANTED
C3 makeup run              NOT AUTHORIZED
```

Accepted checks:

```text
Governance                 PASS
Blinding                   PASS
Deterministic entry point  PASS
P-POS / N-A / N-B          PASS
I-1 / I-2                  PASS
C3                         OBSERVATION ONLY
```

Registered non-blocking finding:

```text
ES-CSP-MF-01
  C2 uniqueness uses the set of distinct pointer targets. Multiple pointer
  records pointing to the same boundary could therefore appear unique.
  R01 did not trigger this form because N-B used P1a→B1 and P1b→B2.
  R01 remains valid, but must not be generalized to all continuation-pointer
  anomalies.
```

The accepted claim is limited to a registered, lawful, structurally complete,
provenance-bearing Information Closure. It does not cover arbitrary real-world
Agent continuation, physical-world changes after registration, production
readiness, or semantic-retrieval quality.

Next research gap:

```text
PIR    Physical–Information Reconciliation
status REGISTERED / NEXT RESEARCH GAP
```

PIR asks whether, after physical files change and before treating stale
Information as current, SimiGo can use a constrained query-time Reconciliation
Sub-Agent to verify relevant physical objects and bring Information Space to a
prescribed freshness requirement.

PIR implementation, experiment, and SimiGo code change remain NOT AUTHORIZED.

## PIR Design v0.1 delivered — 2026-10-06

Following R01 closure, the local agent delivered PIR Design v0.1 for Human
design review:

```text
status      DESIGN V0.1 DELIVERED FOR HUMAN REVIEW
document    docs/02-evidence/es-is-20261005/
            PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.1_20261006.md
implementation   NOT AUTHORIZED
experiment       NOT AUTHORIZED
code change      NOT AUTHORIZED
```

The design addresses the four required first-version subjects:

```text
PIR-D1  physical change classes: create, modify, delete, move/rename
PIR-D2  query-time freshness policy and typed verdicts, not continuous sync
PIR-D3  responsibility split among Main Agent/ES, constrained Reconciliation
        Sub-Agent, passive Information Space, and Physical World
PIR-D4  typed outputs and hard boundaries; no business judgment, no user-file
        mutation, no semantic guess over physical fact, no Execution State
        expansion
```

The first bounded physical domain is local filesystem regular files under one
registered observation root. No backend, MCP, remote API, filesystem watcher,
continuous synchronization, or implementation path is authorized.

Current state:

```text
R01                CLOSED / ACCEPTED
PIR gap            REGISTERED
PIR Design v0.1    SUBMITTED FOR HUMAN REVIEW
PIR implementation NOT AUTHORIZED
PIR experiment     NOT AUTHORIZED
```

## ES–IS Settled Relation Coupling audit package delivered — 2026-10-06

Human commission `ca3d606` ordered a corpus audit before any implementation.
The local agent fast-forwarded to `ca3d606`, inspected constitutional, IPAC,
boundary-synthesis, Relation, U-A, R01, PIR, and source-level material, and
delivered:

```text
docs/02-evidence/es-is-20261005/
  SIMIGO_ES_IS_SETTLED_RELATION_COUPLING_ARCHITECTURE_AUDIT_PACKAGE_20261006.md
```

Core audit conclusion:

```text
Settled Relation State is a new canonical composite over existing parts.
It is not a renaming of Relation, IPAC, checkpoint, or cache.
Information Topology is the accumulated ES-produced structure of Information
nodes and Relation/Settled Relation State edges with dependency, revision,
freshness, and provenance validity conditions.
```

The corpus already contains prerequisites:

```text
Constitution ES↔IS closure loop;
Core Reference Scenario T1→R1→T2 without recomputing T1;
IPAC Q3 adoption conditions;
Boundary Synthesis adopt/recompute gate;
RelationCore D1–D3 and R1–R6;
U-A CC-5/CC-8/MA-7/MA-8 provenance/revision/mapping;
R01 continuation closure PASS;
PIR freshness design acceptance.
```

The central missing claim is:

```text
An independent ES₂ can validate and consume a Settled Relation State produced
by ES₁, avoid recomputation of the settled relation, compute only Δ, and
correctly reject stale/invalid dependencies.
```

This is NOT ESTABLISHED.

The package defines:

```text
SRS minimum fields:
  result + source relation + dependency revisions + provenance + freshness +
  relation semantics + settlement status.

Information Topology:
  Information nodes + Relation/SRS edges + validity conditions, accumulated by
  Execution State.

Falsifiable hypotheses:
  H1 lawful reuse after validation;
  H2 stale/invalid dependency forces recompute or block;
  H3 bare result without SRS bundle cannot authorize lawful reuse.

Minimum experiment outline:
  ARM-A valid reuse;
  ARM-B stale dependency;
  ARM-C missing provenance;
  ARM-D bare-result control;
  ARM-E independent Execution State control.
```

The package explicitly forbids reinterpreting R01 or PIR as SRS reuse evidence.

Current state:

```text
Audit package              SUBMITTED FOR HUMAN REVIEW
PIR Design v0.2            ACCEPTED / freshness prerequisite design
Minimal PIR Probe v0.2     PAUSED pending central architecture ruling
PIR implementation         NOT AUTHORIZED
PIR experiment             NOT AUTHORIZED
SRS implementation         NOT AUTHORIZED
SRS experiment             NOT AUTHORIZED
SimiGo code change         NOT AUTHORIZED
```

## Issue #2 decomposition/control artifact delivered — 2026-10-06

Human opened GitHub Issue #2 to require decomposition of the ES–IS architecture
research position without creating a new task tree, implementation, fixture, or
experiment.

Delivered control artifact:

```text
docs/00-governance/
  SIMIGO_ES_IS_ARCHITECTURE_RESEARCH_DECOMPOSITION_CONTROL_20261006.md
```

The artifact preserves historical lineage:

```text
Phase 2 Relation → IPAC adoption question → Boundary Synthesis →
Research Constitution / Core Reference Scenario → R01 → PIR v0.2 →
Settled Relation Audit Package → Issue #2 decomposition.
```

It classifies:

```text
ESTABLISHED:
  ES↔IS constitutional loop;
  Core Scenario;
  immutable Information;
  immutable Relation edge;
  bounded Relation persistence;
  U-A durable carrier/revision/provenance machinery;
  R01 bounded continuation from prepared closure;
  PIR v0.2 as accepted prerequisite design.

PREREQUISITE EVIDENCE:
  IPAC, R01, PIR, U-A, RelationCore support future SRS work but do not prove
  SRS reuse.

ARCHITECTURE-CLARIFIED BUT UNPROVEN:
  Settled Relation State;
  Information Topology;
  ES₁→IS→ES₂ reuse loop;
  lawful reuse predicate;
  invalidation behavior;
  bare-result insufficiency.

OPEN GAPS:
  G1 SRS semantic boundary;
  G2 SRS reuse validation predicate;
  G3 ES→IS settlement contract;
  G4 IS→ES reuse contract;
  G5 durable SRS carrier-binding boundary;
  G6 minimal reuse experiment design;
  G7 experiment execution.
```

Only one smallest next closure task was selected:

```text
SRS-SEM-01 Minimal Settled Relation State Semantic Boundary
Status = SELECTED, NOT STARTED
```

It is prior to validation, settlement, reuse, carrier binding, and experiment
because those tasks cannot define lawful inputs/outputs until SRS semantics are
frozen.

Completion requires a dedicated design-only artifact,
`SIMIGO_ES_IS_SRS_SEMANTIC_BOUNDARY_DESIGN_V0.1.md`, plus Human ACCEPTED. It
must not define Swift/SQLite structures, select a backend, modify cores, or run
anything.

Next dependency after acceptance:

```text
SRS-VAL-01 Settled Relation State Reuse Validation Predicate
```

Current state:

```text
Issue #2 output             DELIVERED FOR HUMAN REVIEW
Selected task               SRS-SEM-01 / SELECTED, NOT STARTED
Minimal PIR Probe v0.2      PAUSED pending central architecture ruling
PIR implementation          NOT AUTHORIZED
PIR experiment              NOT AUTHORIZED
SRS implementation          NOT AUTHORIZED
SRS experiment              NOT AUTHORIZED
SimiGo code change          NOT AUTHORIZED
```

## Query-Priority Reconciliation direction and PIR Design v0.2 — 2026-10-06

The Human accepted a PIR design principle:

```text
Query-Priority Reconciliation
  SimiGo does not require whole-Information-Space continuous synchronization.
  On request, it first resolves Query Scope and prioritizes verification/update
  of physical objects in that scope that affect the current Information Closure.
  Unrelated or lower-priority Information may defer reconciliation.
```

Required path:

```text
Query → Scope → Candidate Index → Relevant Objects → Physical Check → Fresh
Closure
```

The forbidden anti-pattern is full scan / full reindex / full update before
answering.

The Human also established a two-level logical model:

```text
HOT / QUERY PATH
  Index, Summary, Identity/Revision, scope-relevant Relations, Physical
  Reconciliation, Query-Scoped Closure.

COLD / BACKGROUND
  stale, historical, unrelated, pending, or low-priority Information.
```

This is not a new backend, store, schema, or consistency protocol.

New metric direction:

```text
ICAC = Information Closure Acquisition Cost
      Scope Resolution Cost
    + Candidate Retrieval Cost
    + Physical Reconciliation Cost
    + IS Update Cost
    + Closure Reconstruction Cost
```

The key PIR question is whether cost depends primarily on Query Scope rather
than total Information Space size.

PIR Design v0.2 was delivered to record this principle. It also pre-registers a
future experiment shape:

```text
10,000 Information objects;
20 objects in Query Scope;
5 relevant physical changes;
fixed freshness window;
query-priority reconciliation only.
```

That shape is NOT COMMISSIONED. No fixture, dataset, implementation, harness,
database, or run is authorized.

Current state:

```text
PIR Design v0.1    SUPERSEDED / RETAINED
PIR Design v0.2    SUBMITTED FOR HUMAN REVIEW
PIR implementation NOT AUTHORIZED
PIR experiment     NOT AUTHORIZED
```

## PIR v0.2 conditional pass and clarification addendum — 2026-10-06

The Human independently reviewed PIR Query-Priority direction and Design v0.2
at `ce10827`.

Ruling:

```text
PIR Query-Priority Direction              PASS / ACCEPTED
Architecture Principle                    PASS
Passive Information Space                 PASS
Query-Priority Reconciliation             PASS
HOT/COLD logical model                    PASS
ICAC direction                            PASS
No-new-backend boundary                   PASS
Governance separation                     PASS
R01 compatibility                         PASS

PIR Design v0.2                           CONDITIONAL PASS
```

Five required clarifications were registered and answered in a clarification
addendum:

```text
F1  Query Scope = Information Scope + Physical Scope.
    Physical Scope is required to discover create / move / rename /
    unregistered relevant objects.

F2  Scope Resolution and Physical Reconciliation must be measured separately.
    An evaluation oracle may know planted relevant objects, but must not feed
    them into the lawfully measured reconciliation path.

F3  ICAC is a cost vector / decomposition, not a scalar formed by adding
    heterogeneous units. Weighted ICAC is forbidden until separately
    pre-registered.

F4  Freshness Window splits into:
    W_age     physical observation age bound
    W_latency query-to-fresh-closure latency budget

F5  HOT/COLD is request-relative. HOT = required by effective Query Scope.
    COLD = not required. Historical Information is not inherently COLD.
```

The clarification addendum also defines bounded Physical Scope rules: declared
roots/filters/exclusions only; no global filesystem scan, watching, or
unrestricted recursive search.

Current state:

```text
PIR Design v0.2                 CONDITIONAL PASS
Clarification Addendum          DELIVERED FOR HUMAN REVIEW
Minimal PIR Probe Design        NOT COMMISSIONED
PIR implementation              NOT AUTHORIZED
PIR experiment                  NOT AUTHORIZED
SimiGo code change              NOT AUTHORIZED
```

## PIR v0.2 accepted; Minimal PIR Probe Design v0.1 commissioned — 2026-10-06

The Human independently reviewed `c50978a` and accepted:

```text
Query-Priority Reconciliation       PASS
PIR Design v0.2                     PASS / ACCEPTED
Clarification Addendum              PASS / ACCEPTED
F1 Query Scope                      RESOLVED
F2 Scope/Reconciliation separation  RESOLVED
F3 ICAC cost vector                 RESOLVED
F4 W_age / W_latency                RESOLVED
F5 HOT/COLD request-relative        RESOLVED
```

No architecture redesign, R01 reopening, implementation, or experiment was
authorized. The Human noted a non-blocking probe-design requirement: `W_age`
must later be operationalized as an observable controlled timestamp difference,
not as unknowable absolute physical-world age.

Formal commission:

```text
PIR v0.2 + Addendum      ACCEPTED
commissioned artifact    Minimal PIR Probe Design v0.1
implementation           NOT AUTHORIZED
experiment               NOT AUTHORIZED
fixture creation         NOT AUTHORIZED
```

Commission ruling:

```text
docs/00-governance/
  PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.2_ACCEPTANCE_AND_MINIMAL_PROBE_COMMISSION_20261006.md
```

Delivered probe design:

```text
docs/02-evidence/es-is-20261005/
  PALACE_INFORMATION_SPACE_FOUNDATION_MINIMAL_PIR_PROBE_DESIGN_V0.1_20261006.md
```

The probe design is documentation-only. It defines paired controls:

```text
E-L  N=10,000, R=20, M=5
E-S  N=20,     R=20, M=5
```

It also defines oracle isolation, planted-change rules, separate Scope Resolution
and Physical Reconciliation measurement, observable `W_age`, explicit
`W_latency`, ICAC cost vectors, Fresh Closure criteria, false-positive/false-
negative evaluation, side-channel prohibitions, failure taxonomy, and
INDETERMINATE conditions.

Current state:

```text
Minimal PIR Probe Design v0.1    SUBMITTED FOR HUMAN REVIEW
PIR implementation               NOT AUTHORIZED
PIR experiment                   NOT AUTHORIZED
Fixture creation                 NOT AUTHORIZED
SimiGo code change               NOT AUTHORIZED
```

## Minimal PIR Probe v0.1 conditional pass; v0.2 delivered — 2026-10-06

The Human independently reviewed Minimal PIR Probe Design v0.1 at `c029b89`.

Ruling:

```text
Minimal PIR Probe Design v0.1     CONDITIONAL PASS
Research question                 PASS
Paired E-L / E-S                  PASS
Scope / reconciliation split      PASS
Oracle isolation                  PASS
ICAC vector                       PASS
Change pattern                    PASS
CREATE deferral                   PASS
Negative controls                 PASS
Move / rename protocol            NEEDS REVISION
Scaling attribution               NEEDS REVISION
Physical-check boundedness        NEEDS REVISION
W_age semantics                   NEEDS REVISION
```

Formal ruling:

```text
docs/00-governance/
  PALACE_INFORMATION_SPACE_FOUNDATION_MINIMAL_PIR_PROBE_DESIGN_V0.1_REVIEW_RULING_20261006.md
```

The Human confirmed that CREATE should remain deferred and `C-NOCHANGE` should
remain. Future Run Manifest must distinguish physical observations from
physical changes.

Four required revisions were:

```text
MR-1  W_age → W_obs_age:
      current reconciliation time - previous lawful physical observation time.
      This is observable observation staleness, not physical-world change age.

MR-2  Physical boundedness must be non-circular:
      physical_check_targets ⊆ declared Physical Scope;
      unrelated_physical_touches = 0;
      P is actually materialized by declared Physical Scope, not merely derived
      from R.

MR-3  E-L/E-S scaling attribution must be pre-registered by phase:
      N-dependent growth may belong to Scope Resolution / Index / declared
      structural overhead, never to whole-N Physical Reconciliation.

MR-4  MOVE / RENAME discovery must be locked by a declared candidate pool,
      allowed file class, deterministic identity-correlation rule, bounded
      directory scope, maximum candidate count, ambiguity policy, and evidence
      requirements. No semantic fallback.
```

Minimal PIR Probe Design v0.2 was delivered with these revisions and updated
PASS/Evidence rules:

```text
PC-9A  declared Physical Scope membership
PC-9B  unrelated_physical_touches = 0
PC-9C  separate P_materialized / targets / observations / changes
PC-13A phase-separated scaling attribution
PC-13B Physical Reconciliation bounded by P_materialized + allowance
PC-13C no whole-N scan growth
FT-P14 N-dependent Physical Reconciliation expansion
EV-P16 MOVE/RENAME protocol
EV-P17 P / check-target provenance
EV-P18 observations versus changes
```

Current state:

```text
Minimal PIR Probe Design v0.1    CONDITIONAL PASS / SUPERSEDED BY V0.2
Minimal PIR Probe Design v0.2    SUBMITTED FOR HUMAN REVIEW
PIR Fixture                      NOT AUTHORIZED
PIR Implementation               NOT AUTHORIZED
PIR Experiment                   NOT AUTHORIZED
```

## SRS-SEM-01 v0.1 REVISE; v0.2 semantic correction delivered — 2026-10-07

The Human independently reviewed SRS-SEM-01 Design v0.1 at `a80577f`.

Ruling:

```text
SRS-SEM-01 Design v0.1     REVISE
Overall direction          PASS
Scope discipline           PASS
SRS vs cache               PASS
SRS vs Relation            PASS
Immutable SRS              PASS
Append-only lifecycle      PASS
Carrier neutrality         PASS
SRS-VAL-01                 NOT AUTHORIZED
```

Required corrections:

```text
R1  Remove lawful-settlement circularity.
R2  Restrict revision_binding to exact immutable revision identity.
R3  Conservative lifecycle derivation; unresolved conflict blocks reuse.
C4  result / Information identity is not SRS identity.
C5  Provenance is minimum semantic proof obligation, not a new taxonomy.
C6  SRS stores freshness requirements, not freshness verdicts.
```

SRS-SEM-01 Design v0.2 was delivered:

```text
docs/02-evidence/es-is-20261005/
  SIMIGO_ES_IS_SRS_SEMANTIC_BOUNDARY_DESIGN_V0.2_20261007.md
```

Key corrections:

```text
Birth status        DECLARED_SETTLED
Settlement meaning  records an ES settlement declaration under governing
                    settlement semantics; does not define operational lawfulness
Revision binding    EXACT_REVISION only; no semantic-equivalence upgrade
Lifecycle conflict  UNRESOLVED_LIFECYCLE_CONFLICT and CONTESTED are not
                    determinate reusable statuses
Result boundary     result identity ≠ SRS identity
Provenance          minimum semantic proof obligations only
Freshness           requirements/conditions only, not verdicts
```

Current state:

```text
SRS-SEM-01 v0.1     REVISE / SUPERSEDED BY V0.2
SRS-SEM-01 v0.2     SUBMITTED FOR HUMAN REVIEW
SRS-VAL-01          NOT AUTHORIZED
SRS implementation  NOT AUTHORIZED
SRS fixture         NOT AUTHORIZED
SRS experiment      NOT AUTHORIZED
```

## SRS-SEM-01 v0.5 ACCEPT / FROZEN; SRS-VAL-01 design commissioned and delivered — 2026-10-07

The Human independently reviewed SRS-SEM-01 Design v0.5 at `c7192f0` by
attacking its stability axiom:

```text
immutable SRS
  → every external semantic dependency that can change interpretation/reuse
  → immutable identity / exact immutable version / immutable content address
```

Final ruling:

```text
SRS-SEM-01 Design v0.5     ACCEPT / FROZEN

v0.1 findings              PASS
v0.2 findings              PASS
v0.3 findings              PASS
v0.4 findings              PASS

Source identity stability  PASS
Result target stability    PASS
Resolution-rule stability  PASS
Policy/version stability   PASS
Canonical identity-rule stability PASS
Provenance evidence stability PASS
Lifecycle evidence stability PASS
Exact revision / freshness separation PASS
SRS / validation separation PASS
Carrier neutrality         PASS
Scope discipline           PASS
```

Frozen coverage:

```text
source relation identity;
canonical identity-generation rule;
result target;
resolution rule;
policy / semantic rule;
provenance evidence;
lifecycle evidence.
```

The Human confirmed the separation:

```text
SRS-SEM-01 = immutable settled semantic state.
SRS-VAL-01 = REUSE / BLOCK / RECOMPUTE predicate.
```

SRS-VAL-01 Design v0.1 was commissioned and delivered:

```text
docs/02-evidence/es-is-20261005/
  SIMIGO_ES_IS_SRS_VAL_01_REUSE_VALIDATION_PREDICATE_DESIGN_V0.1_20261007.md
```

It defines validation input groups G-V1..G-V7, exact-binding checks,
lifecycle/provenance/freshness checks, REUSE/BLOCK/RECOMPUTE semantics,
non-recomputation evidence boundary, independence requirements, negative and
positive validation scenarios, evidence output, and failure taxonomy.

Current state:

```text
SRS-SEM-01 v0.5     ACCEPT / FROZEN
SRS-VAL-01 v0.1     SUBMITTED FOR HUMAN REVIEW
SRS-VAL implementation NOT AUTHORIZED
SRS-VAL fixture       NOT AUTHORIZED
SRS-VAL experiment    NOT AUTHORIZED
IS mutation           NOT AUTHORIZED
```

## SRS-VAL-01 v0.2 REVISE; v0.3 decision precedence delivered — 2026-10-07

The Human independently reviewed SRS-VAL-01 Design v0.2 at `7b4989b`.

Ruling:

```text
SRS-SEM-01 inheritance                 PASS
I-14 recompute authorization           PASS
I-15 exact reuse request               PASS
I-16 observation consistency           PASS
Freshness clearing                     PASS
SRS never authorizes recompute         PASS
Failure alone never means recompute    PASS
Independence boundary                  PASS
Non-recomputation boundary             PASS
Typed failure taxonomy                 PASS

Source invalidation precedence         REVISE
Decision mutual exclusivity            REVISE
Context Index current document pointer REVISE

SRS-VAL-01 Design v0.2                 REVISE
```

Required v0.3 corrections:

```text
R1  source-relation invalidation records are evaluated under the same
    failure-classification rules. An invalidation is HARD_BLOCK unless exact
    I-14 authorization explicitly covers that invalidation class.
    I-14 authorization never overrides INVALIDATED / CONTESTED /
    UNRESOLVED_LIFECYCLE_CONFLICT lifecycle blockers.

R2  formal decision precedence:
    DP-0 observation inconsistency → BLOCK;
    DP-1 any structural/provenance/resolution/policy/source/lifecycle
         HARD_BLOCK → BLOCK;
    DP-2 applicability NOT_APPLICABLE / INDETERMINATE → BLOCK;
    DP-3 all remaining failures explicitly covered by I-14 → RECOMPUTE;
    DP-4 no failure remains → REUSE.
    Exactly one primary decision is returned. REUSE, BLOCK, and RECOMPUTE are
    mutually exclusive.

R3  Context Index current design pointer corrected to v0.3; v0.1 remains only
    superseded lineage.
```

SRS-VAL-01 Design v0.3 was delivered:

```text
docs/02-evidence/es-is-20261005/
  SIMIGO_ES_IS_SRS_VAL_01_REUSE_VALIDATION_PREDICATE_DESIGN_V0.3_20261007.md
```

Current state:

```text
SRS-VAL-01 v0.2     REVISE / SUPERSEDED BY V0.3
SRS-VAL-01 v0.3     SUBMITTED FOR HUMAN REVIEW
SRS-VAL implementation NOT AUTHORIZED
SRS-VAL fixture       NOT AUTHORIZED
SRS-VAL experiment    NOT AUTHORIZED
IS mutation           NOT AUTHORIZED
```

## SRS-VAL-01 v0.1 REVISE; v0.2 decision-boundary correction delivered — 2026-10-07

The Human independently reviewed SRS-VAL-01 Design v0.1 at `f733457`.

Ruling:

```text
SRS-SEM-01 inheritance              PASS
Exact-binding validation            PASS
G-V1..G-V7 structure                PASS
REUSE semantics                     PASS / boundary completion needed
BLOCK semantics                     PARTIAL
RECOMPUTE semantics                 REVISE
Applicability input                 REVISE
Freshness recheck wording           SHOULD-FIX
Validation observation consistency  REVISE
Independence boundary               PASS
Non-recomputation boundary          PASS
Failure taxonomy                    PASS / additions needed

SRS-VAL-01 Design v0.1              REVISE
```

Required v0.2 corrections:

```text
B1  RECOMPUTE authorization source conflict:
    SRS never authorizes RECOMPUTE. Add explicit governing
    recompute/reuse authorization binding I-14. RECOMPUTE is possible only when
    that separately bound governing semantic contract/policy explicitly
    authorizes the current invalidation class.

B2  Current reuse request input:
    Add non-natural-language current_reuse_request binding I-15, or conservatively
    BLOCK whenever applicability cannot be exactly determined.

B3  BLOCK versus RECOMPUTE must become a complete decision relation:
    every validation failure is classified; RECOMPUTE occurs only when a
    separately bound governing rule explicitly authorizes that invalidation
    class. RECOMPUTE does not mean “validation failed, so compute again.”

B4  Validation observation consistency:
    all inputs for one decision belong to one lawful validation observation
    boundary. If cross-input consistency cannot be established, return BLOCK
    with a typed consistency reason.

C1  Freshness V7.6 positive clearing semantics:
    present + uncleared → BLOCK; explicitly cleared by lawful evidence →
    continue evaluation.
```

SRS-VAL-01 Design v0.2 was delivered:

```text
docs/02-evidence/es-is-20261005/
  SIMIGO_ES_IS_SRS_VAL_01_REUSE_VALIDATION_PREDICATE_DESIGN_V0.2_20261007.md
```

Key additions:

```text
I-14  governing recompute/reuse authorization binding
I-15  exact current reuse request binding
I-16  validation observation boundary binding

FT-V26 VALIDATION_INPUT_STATE_INCONSISTENT
FT-V27 GOVERNING_RECOMPUTE_AUTHORIZATION_MISSING_OR_INVALID
FT-V28 APPLICABILITY_INDETERMINATE
FT-V29 CURRENT_REUSE_REQUEST_BINDING_MISSING_OR_INVALID
FT-V30 UNAUTHORIZED_RECOMPUTE_REQUEST
FT-V31 GOVERNING_AUTHORIZATION_OUTSIDE_REQUEST_SCOPE
FT-V32 GOVERNING_AUTHORIZATION_EXPIRED
FT-V33 GOVERNING_AUTHORIZATION_CONTRADICTS_LIFECYCLE
```

Current state:

```text
SRS-VAL-01 v0.1     REVISE / SUPERSEDED BY V0.2
SRS-VAL-01 v0.2     SUBMITTED FOR HUMAN REVIEW
SRS-VAL implementation NOT AUTHORIZED
SRS-VAL fixture       NOT AUTHORIZED
SRS-VAL experiment    NOT AUTHORIZED
IS mutation           NOT AUTHORIZED
```

## SRS-SEM-01 v0.4 REVISE; v0.5 identity/evidence stability delivered — 2026-10-07

The Human independently reviewed SRS-SEM-01 Design v0.4 at `79fc37a`.

Ruling:

```text
v0.3 source identity scope independence       PASS
v0.3 result target immutability               PASS
v0.3 resolution-rule exact version            PASS
v0.3 recomputation prohibition relocation     PASS
v0.3 policy/semantic version stability        PASS
v0.3 Context Index consistency                PASS

Canonical identity-rule exact version binding REVISE
Provenance evidence immutable binding         REVISE
Lifecycle evidence immutable binding          REVISE

SRS-SEM-01 Design v0.4                        REVISE
SRS-VAL-01                                    NOT AUTHORIZED
```

SRS-SEM-01 Design v0.5 was delivered with these corrections:

```text
R1  CANONICAL_DERIVED_RELATION_ID binds its canonical identity-generation rule
    by EXACT_RULE_VERSION.

R2  Changing canonical identity-generation semantics requires a new rule
    identity/version.

R3  Existing SRS source identity is never reinterpreted under a later canonical
    rule.

R4  Provenance or lifecycle evidence references that can affect SRS
    interpretation or reuse must bind to immutable evidence identity, exact
    immutable evidence revision, or immutable content address.

R5  Mutable or unversioned evidence references are insufficient for determinate
    reusable SRS.

R6  Missing or unstable required evidence produces
    PROVENANCE_EVIDENCE_UNSTABLE_OR_MISSING or
    LIFECYCLE_EVIDENCE_UNSTABLE_OR_MISSING and blocks lawful reuse.
```

Current state:

```text
SRS-SEM-01 v0.4     REVISE / SUPERSEDED BY V0.5
SRS-SEM-01 v0.5     SUBMITTED FOR HUMAN REVIEW
SRS-VAL-01          NOT AUTHORIZED
SRS implementation  NOT AUTHORIZED
SRS fixture         NOT AUTHORIZED
SRS experiment      NOT AUTHORIZED
```

## SRS-SEM-01 v0.3 REVISE; v0.4 external-reference stability delivered — 2026-10-07

The Human independently reviewed SRS-SEM-01 Design v0.3 at `d2b6a93`.

Ruling:

```text
v0.2 required semantic gaps              CLOSED
Concrete relation-instance identity      PARTIAL PASS
Result resolvability                     PARTIAL PASS
FRESHNESS_RECHECK_REQUIRED blocking      PASS
Lifecycle evidence minimum               PASS
Exact revision vs freshness               PASS

Source identity scope dependence         REVISE
Result target immutability               REVISE
Resolution-rule stability                REVISE
Recomputation prohibition as SRS field   SHOULD-FIX
Policy / semantic-version binding        SHOULD-CLARIFY
Context Index canonical consistency      REVISE

SRS-SEM-01 Design v0.3                   REVISE
SRS-VAL-01                               NOT AUTHORIZED
```

SRS-SEM-01 Design v0.4 was delivered with these corrections:

```text
R1  source-relation identity is context-independent and immutable.
    Declared Scope validates uniqueness but is not identity authority.

R2  RESULT_REFERENCE / DESCRIPTOR must bind to exact immutable result-state
    identity or exact immutable result revision.

R3  resolution_rule_id becomes resolution_rule_binding to exact immutable rule
    identity/version.

S1  recomputation_prohibition is removed as an SRS field. The no-recompute rule
    belongs to SRS-VAL-01 / reuse validation.

S2  semantic rules and policies affecting reuse bind to exact immutable
    policy/semantic versions.

G1  Context Index current-state navigation is corrected.
```

Key stability invariants:

```text
INV-SRS-SEM-21 context-independent immutable source-relation identity
INV-SRS-SEM-22 declared scope is validation context, not identity authority
INV-SRS-SEM-23 exact immutable result-state identity/revision binding
INV-SRS-SEM-24 mutable/latest result targets cannot support lawful reuse
INV-SRS-SEM-25 exact immutable resolution-rule identity/version binding
INV-SRS-SEM-26 resolution semantic changes require new rule identity/version
INV-SRS-SEM-27 exact immutable policy/semantic version binding
INV-SRS-SEM-28 recomputation prohibition is reuse-validation invariant
```

Current state:

```text
SRS-SEM-01 v0.3     REVISE / SUPERSEDED BY V0.4
SRS-SEM-01 v0.4     SUBMITTED FOR HUMAN REVIEW
SRS-VAL-01          NOT AUTHORIZED
SRS implementation  NOT AUTHORIZED
SRS fixture         NOT AUTHORIZED
SRS experiment      NOT AUTHORIZED
```

## SRS-SEM-01 v0.2 REVISE; v0.3 delivered — 2026-10-07

The Human independently reviewed SRS-SEM-01 Design v0.2 at `253a23f`.

Ruling:

```text
v0.1 six findings closed                  PASS
Scope discipline                          PASS
Carrier neutrality                        PASS
DECLARED_SETTLED boundary                 PASS
EXACT_REVISION boundary                   PASS
Result identity separation                PASS
Provenance boundary                       PASS
Freshness/verdict separation              PASS

Concrete source-relation identity         REVISE
Result resolvability                      REVISE
FRESHNESS_RECHECK_REQUIRED lifecycle      REVISE
Lifecycle evidence minimum                SHOULD-FIX
revision-current wording                  CLARIFY
Research Context Index consistency        GOVERNANCE FIX

SRS-SEM-01 Design v0.2                    REVISE
SRS-VAL-01                                NOT AUTHORIZED
```

SRS-SEM-01 Design v0.3 was delivered with these corrections:

```text
M1  source_relation must uniquely identify the concrete relation instance:
    PERSISTED_RELATION_ID or UNAMBIGUOUS_SOURCE_DESCRIPTION.

M2  reusable result must be RESULT_VALUE directly consumable, or
    RESULT_REFERENCE / RESULT_STATE_DESCRIPTOR lawfully resolvable without
    recomputation. Non-resolvable descriptor alone is insufficient.

M3  FRESHNESS_RECHECK_REQUIRED is blocking/non-reusable until separately defined
    freshness evidence clears it.

S1  lifecycle records require kind, target settlement, authority/event, reason,
    evidence, ordering/time, successor when SUPERSEDED, and affected dependency/
    freshness requirement. Incomplete evidence yields
    INDETERMINATE_LIFECYCLE_EVIDENCE and blocks reuse.

C1  exact revision equality is separate from freshness; revision-current is
    forbidden as a freshness class.

G1  Context Index stale v0.1/v0.2 current-state navigation is corrected to v0.3.
```

Current state:

```text
SRS-SEM-01 v0.2     REVISE / SUPERSEDED BY V0.3
SRS-SEM-01 v0.3     SUBMITTED FOR HUMAN REVIEW
SRS-VAL-01          NOT AUTHORIZED
SRS implementation  NOT AUTHORIZED
SRS fixture         NOT AUTHORIZED
SRS experiment      NOT AUTHORIZED
```

## SRS-VAL-01 v0.3 REVISE; v0.4 RECOMPUTE envelope delivered — 2026-10-07

The Human independently reviewed SRS-VAL-01 Design v0.3 at `d2b6a93`.

Ruling:

```text
v0.2 required corrections                     CLOSED
Source-relation invalidation precedence        PASS
DP-0..DP-4 decision precedence                PASS
REUSE / BLOCK / RECOMPUTE mutual exclusivity  PASS
Context Index current pointer to v0.3         PASS
Prior superseded lineage retained             PASS

RECOMPUTE target semantic scope               REVISE
Result target identity/derivation scope       REVISE
Canonical identity-generation scope           REVISE
Unclassified failure → RECOMPUTE guard        REVISE

SRS-VAL-01 Design v0.3                        REVISE
```

Required v0.4 corrections:

```text
R1  I-14 must contain an exact immutable RECOMPUTE semantic envelope:
      covered recomputation target semantic class;
      covered result-target identity/derivation boundary;
      covered canonical relation-identity generation rule binding.

R2  The canonical relation-identity generation rule must bind by
    EXACT_RULE_VERSION with immutable rule identity, exact immutable version,
    and integrity binding when required.

R3  RECOMPUTE authorization does not implicitly permit changing the canonical
    identity-generation rule.

R4  RECOMPUTE is eligible only when the recomputed result remains inside the
    exact result semantic / target-generation envelope authorized by I-14.

R5  Every remaining validation failure MUST first be classified as
    RECOMPUTE_ELIGIBLE by a registered predicate rule.

R6  I-14 coverage alone MUST NOT upgrade an otherwise unclassified failure into
    RECOMPUTE_ELIGIBLE.
```

SRS-VAL-01 Design v0.4 was delivered:

```text
docs/02-evidence/es-is-20261005/
  PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.4_20261007.md
```

Current state:

```text
SRS-VAL-01 v0.3     REVISE / SUPERSEDED BY V0.4
SRS-VAL-01 v0.4     SUBMITTED FOR HUMAN REVIEW
SRS-VAL implementation NOT AUTHORIZED
SRS-VAL fixture       NOT AUTHORIZED
SRS-VAL experiment    NOT AUTHORIZED
IS mutation           NOT AUTHORIZED
```
