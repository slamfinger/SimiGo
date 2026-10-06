# Evidence Inheritance → Current Information Space Design Matrix

Status: DERIVED RECOVERY / DESIGN-INHERITANCE AID / NOT AUTHORITATIVE  
Date: 2026-10-06  
Authority: each cited source document plus `docs/RESEARCH_STATE.md`  
Boundary: no experiment, implementation, backend selection, schema freeze,
Frozen Contract change, U-2 implementation, or rewrite of historical evidence.

## 1. Purpose

This matrix answers a different question from a navigation census:

> Which completed results are qualified to constrain current Information Space
> design, which remain bounded evidence, and which must not be adopted?

It is intentionally separate from the estate census. A file can be easy to find
while its design authority remains unclear.

## 2. Qualification classes

```text
A = established architecture constraint
B = established design judgment / prior evidence
C = current Unified Carrier design obligation
D = bounded evidence only
E = higher-layer ES↔IS constraint, not carrier/storage primitive
F = not established / explicitly forbidden
```

The class does not change any source's historical status. It records only how a
current derived design discussion may use that source.

## 3. Source anchors

```text
Information/Relation Phase 0-2:
  docs/RESEARCH_STATE.md (Phase 0-2 records),
  commit b29d4198,
  docs/00-governance/SIMIGO_LAB_PHASE1_ACCEPTANCE_20261002.md,
  docs/00-governance/SIMIGO_LAB_PHASE1_INTEGRATION_BOUNDARY_GATE_RESULT_20261002.md,
  docs/00-governance/SIMIGO_LAB_PHASE1_BACKEND_INDEPENDENCE_GATE_RESULT_20261002.md,
  docs/00-governance/SIMIGO_LAB_PHASE1_PERSISTENCE_SEMANTICS_GATE_RESULT_20261002.md,
  docs/00-governance/SIMIGO_LAB_PHASE2_RELATION_BOUNDARY_GATE_RESULT_20261002.md,
  docs/00-governance/SIMIGO_LAB_PHASE2_RELATION_PERSISTENCE_SEMANTICS_GATE_RESULT_20261002.md

Folder Information:
  docs/research-capsules/v1/C12-folder-information-initialization.md,
  docs/00-governance/SIMIGO_LAB_FOLDER_INFORMATION_INITIALIZATION_RESULT_20261004.md,
  docs/02-evidence/folder-information-initialization-20261004/

R3 / Local Closure / continuation:
  docs/00-governance/SIMIGO_LAB_R3_CLOSING_DECLARATION_20261003.md,
  docs/research-capsules/v1/C15-local-closure-information-reduction.md,
  docs/00-governance/SIMIGO_LAB_INFORMATION_ROUND1_RESULT_20261005.md,
  docs/research-capsules/v1/C13-t4-t42-rc1-continuation-evidence.md

Boundary / private-shared:
  boundary-study/exp1-x1/{RECORD,RESULTS}.md,
  docs/00-governance/SIMIGO_LAB_PALACE_BOUNDARY_FROZEN_Y_REVIEW_20261002.md,
  docs/00-governance/SIMIGO_LAB_PALACE_REALWORK_T1_RESULTS_REVISION_20261002.md,
  docs/00-governance/SIMIGO_LAB_PALACE_REALWORK_T2_RESULTS_20261002.md,
  docs/00-governance/SIMIGO_LAB_PALACE_REALWORK_T3_RESULTS_20261002.md,
  docs/00-governance/SIMIGO_LAB_PALACE_Y_RULING_20261002.md

Real Carrier / U-0 / U-1:
  docs/00-governance/SIMIGO_LAB_PALACE_REAL_CARRIER_MEMPALACE_V0_INIT_20261002.md,
  docs/RESEARCH_STATE.md C-6 wiring-layer record,
  docs/02-evidence/es-is-20261005/MEMPALACE_ISMCI_ADAPTER_FEASIBILITY_AUDIT_20261005.md,
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U0_SESSION_EVIDENCE_CONSOLIDATION_20261006.md,
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.2_20261006.md,
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_V0_2_CONFORMANCE_REVIEW_20261006.md,
  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_REVIEW_RULING_AND_CCMA_MANDATE_20261006.md
```

## 4. Matrix

| Evidence / conclusion | Source status | Class | Current Information Space use | Forbidden upgrade |
|---|---|---|---|---|
| I-1 / I-1c / I-1d chain | Frozen; implementation gates closed | A | Use as the accepted Information→Resolve→Instantiate→Continue baseline. | Do not redefine these concepts in carrier work. |
| InformationCore + RelationCore + Store sufficiency | Accepted/closed for UTF-8/text-bounded PRQ domain | A | Begin carrier design from the existing semantic/store split. | Do not treat sufficiency as complete Information Space or arbitrary-byte support. |
| Information and Relation are independent semantic objects; `InformationStore ∥ RelationStore` | Phase 2 closed/PASS; human-confirmed | A | Preserve parallel boundaries. Unified Carrier unifies Carrier, not Information and Relation into a super Store. | Do not introduce a GenericStore/SuperStore without a new contract gate. |
| Symmetric persistence contracts `S1-S6 ∥ R1-R6`; first-write-wins | Phase 1/2 closed/PASS | A | Preserve semantic identity, independent physical filings, and upper-layer backend independence. | Do not infer a Knowledge Graph system or cross-store abstraction. |
| Dual-backend Information persistence: SQLiteStore + InMemoryStore | Phase 1 backend-independence PASS | A/B | Treat database as implementation choice, not architecture premise. | Do not select a production backend from this evidence. |
| Folder Information Initialization with InformationCore + SQLiteStore | Bounded real run; 5 files formed/stored; TXT/Markdown/path roundtrip pass; idempotent | B | Use as prior File Carrier engineering evidence and as a measured gap source (binary/empty, list/query, directory semantics). | Do not claim SQLite is the selected Information Space backend or complete carrier. |
| T4 / T4-2 / T5 / R-C1 continuation evidence | Closed/task-domain bounded replication passes | D | Use as evidence that persistent Information can support continuation in registered task domains. | Do not generalize into a universal continuation theorem. |
| R3 differential sensitivity / interaction boundary | Formally closed, fixture-slice bounded | D | Carry as a bounded constraint: compound Information Space changes may need explicit operation-order description. | Do not claim a general non-interaction law or universal non-commutativity. |
| Local Closure / Information Reduction Round 1 | 17/17 bounded conditions executed; RAW/DECODED/SEMANTIC continuations passed; gamma-only M1.b+M2.b passed | D | Use as representation/reduction evidence: equivalent layers and composite relevance can exist in a bounded frame. | Do not select a universal Information schema or claim universal minimality. Observer/store/cross-model were not run. |
| Palace V2 G0-G3 durable information | Closed/bounded observations | D | Use as historical evidence that discovery, work records, exclusions, open questions, and next steps improved recovery. | Do not infer ES necessity, backend selection, or required schema. |
| EXP1-X1 | Human accepted/closed; explicit work frontier and judgment+basis were strongest survival forms; trust did not transfer automatically | B/E | Treat as higher-layer recovery/semantics evidence and as motivation for judgment/basis/frontier representation. | Do not turn the observed X1 forms into a frozen schema or ES proof. |
| BR-1 lifecycle-form split | Human frozen | E | Same content in different lifecycle forms may belong to private continuity and shared Information separately. | Do not force one content→one layer classification. |
| BR-2 pure continuity metadata is private | Human frozen | E | Pointers/routes/lineage/where-to-continue default to private continuity. | Do not place activation judgment in carrier storage. |
| BR-3 reusable products are Information | Human frozen | E | Formed reusable work products/facts/reports/conclusions/environment records enter shared Information without waiting for later demand. | Do not infer that every session event automatically becomes Information. |
| BR-5 shared Information does not summon itself | Human frozen; T1-T3 supported | E | Existence, activation, and read-direction are distinct problems at the Execution↔Information interface. | Do not implement wake-up/recommendation/ranking as carrier correctness. |
| T1/T2/T3 private/shared behavior | Registered behavioral evidence; deposit→pointer→consume chain observed | B/E | Treat as evidence for private continuity, activation, explicit frontier, and work-history informatization as separate concerns. | Do not promote n=3/single-lineage/single-task behavior to a universal semantic law. |
| Y probe | Human ruled: BR-2 supported/no explicit counterexample; three observations retained; sealed/closed | D | Preserve as bounded counterexample search, not proof or refutation beyond its ruling. | Do not reopen or use it to rewrite BR-2. |
| MemPalace real-carrier C-1..C-6 | Observed collision ledger; C-6 was wiring-layer and fixed at that layer | C | C-1 PDF ingestion, C-2 XLSX flattening/NaN, C-3 numeric retrieval noise, C-4 ordering/ranking inversion, C-5 wake-up pollution, and C-6 wiring separation motivate U-0 obligations. | Do not read as MemPalace universally unsuitable; do not repair or select MemPalace now. |
| MemPalace IS-MCI audit | AS-IS NO-GO for direct independent PRQ semantic carrier | D | Preserve as strict-carrier negative feasibility evidence. | Do not generalize to rejection of MemPalace for every historical/migration/backend role. |
| U-0 inheritance | Delivered; maps real-carrier failures to RepresentationLocator, exact layer, ordering, IndexSource, and upper-layer activation boundaries | C | Treat as the current bridge from observed failures to Unified Carrier obligations. | Do not add wake-up/MCP/UI interpretation to carrier correctness. |
| U-1 v0.2 Unified Carrier Contract | Conformance review REVISE with zero BLOCK; Human ruling B = REVISE; direction and semantic anchoring accepted, v0.2 not frozen | C | Use as accepted direction and semantic anchoring, but not as a frozen contract. | Do not begin U-2 or alter PB v1.2 before UA v0.3 review/freeze. |
| UA v0.3 mandate and CC-MA | Mandated: R-1..R-11, A-1..A-3 dispositions, and Multi-Agent Carrier Consistency | C | Treat multi-agent concurrency, operation identity, stale-write detection, atomicity, provenance, snapshots, and index rebuild as mandatory carrier design constraints. | Do not treat the real Agent A/Agent B scenario as completed concurrency validation or model Agent as an Information semantic entity. |
| Real multi-source convergence: files, sessions, research material, judgments, private continuity | Registered design direction | B | Treat as the real workload context for Unified Carrier design. | Do not create a new theoretical model disconnected from existing evidence. |
| General R3 interaction law | Explicitly not claimed | F | Preserve R3 only with fixture-slice bounds. | Do not use R3 as a universal non-commutativity or interaction law. |
| Universal Local Closure minimality | Explicitly not established | F | Use Round 1 only as bounded representation evidence. | Do not derive a universal Information schema. |
| ES necessity from durable Information | Explicitly unproven | F | Treat durable Information as recovery support, not ES proof. | Do not collapse Information into Execution State. |
| Universal MemPalace rejection | Not established | F | Retain the strict IS-MCI NO-GO boundary only. | Do not erase MemPalace's historical/migration/backend-candidate distinctions. |

## 5. Four load-bearing inheritances

1. **Information and Relation remain independent.** Carrier unification must
   not erase the verified parallel Store boundaries.
2. **Persistence is already engineered, not hypothetical.** SQLiteStore and
   InMemoryStore provide bounded dual-backend evidence; Folder Initialization
   adds a real text-domain run and explicit gaps.
3. **Existence is not activation.** X1/T1/T2/T3 and BR-5 show that storing
   work history and making the current Execution read it are different
   problems.
4. **The next workload is already real and mixed.** Files, sessions, research
   records, judgments, exclusions, open questions, and private continuity are
   converging; Unified Carrier should inherit that reality rather than restart
   from abstract schema design.
5. **Concurrency is a carrier design constraint, not a new semantic object.**
   Agents may be actors and provenance subjects, but not `AgentInformation`,
   `AgentRelation`, or an AgentStore.

## 6. Non-adoption list

```text
NO general interaction law from R3
NO universal Local Closure minimality
NO proven ES necessity from durable Information
NO universal MemPalace rejection
NO SQLite backend selection from bounded experiments
NO activation semantics inside Carrier DB
NO Session-as-second-class-Information model
NO automatic SessionEvent→Information conversion
NO Agent semantic entity / AgentStore
NO claim that the real parallel-agent day is completed validation
```

If a source and this matrix conflict, the source and current State win.
