# SimiGo-Lab Research Estate Summary

Status: GLOBAL HISTORY AND ORIENTATION / DERIVED / NOT AUTHORITATIVE  
Date: 2026-10-06  
Current authority: `docs/RESEARCH_STATE.md`  
Census: `docs/RESEARCH_ESTATE_CENSUS_20261006.md`

This file explains how the estate reached the present. It does not replace
State, Frozen Contracts, governance registers, rulings, or evidence. Each line
below is a compressed entry point; read the cited source before relying on any
result.

## 1. Research origin

SimiGo-Lab began as the SimiGo 2.0 runtime research lab. Its stable core
question became whether **Execution State** is the missing boundary between
model execution semantics and physical resource management. The repository
README defines the current framing and the fundamental separation:

```text
SimiGo Runtime manages execution continuity and resource lifecycle.
Backend manages physical model execution and computation semantics.
```

Primary entry: `README.md`.  
The current research frontier later moved from execution alone to the
**Execution State ↔ Information Space** coupling.

## 2. Architecture 2.0 and pre-research period

This historical phase explored broader direction, architecture concepts,
optimization/representation language, and candidate decompositions before the
present narrower core was fixed. It remains valuable for provenance and dead-end
avoidance, but it is not the current authority.

```text
Why             = explore the research space and candidate architecture
Changed         = narrower ES↔IS core and explicit governance adopted
Still valid     = provenance, rejected directions, drift-control lessons
Not valid       = treating old proposals as current decisions
Where           = docs/07-history, docs/pre-research, governance registers
Status          = historical / superseded by later governance
```

## 3. Execution State / runtime identity line

The lab established a bounded execution-state concept and an engineering chain:
contract design, fake/runtime verification, real MLX adapter work, execution
continuity, representation migration, and end-to-end scenarios. The public
lifecycle is `create / fork / continue / save / restore / discard / release`.

```text
Established     = a bounded Execution State contract and runtime evidence
Not established = no universal backend theorem or performance superiority
Disposition     = historical closure/freeze; do not automatically reopen
Primary entries = README.md,
                  docs/RESEARCH_STATE.md,
                  docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_CONTRACT_V1_AMENDED_20261002.md,
                  trackB-execution-state/
```

The separately named runtime verification `L4-A/B/C` chain is **not** an
Information Place recovery layer. It belongs to runtime residency/verification
history.

## 4. Residency / Track E line

Residency research studied baseline mechanisms, policy frequency, structure
signals, oversized-model behavior, and nodes-out externalization. It produced
closed/sealed evidence but did not become the present core route.

```text
Established     = bounded residency/materialization evidence
Not established = no general residency policy claim outside sealed fixtures
Disposition     = CLOSED / SEALED / ARCHIVED
Primary entries = trackE-residency/,
                  docs/00-governance/EXPERIMENT_REGISTER_20260922.md,
                  docs/RESEARCH_STATE.md
```

## 5. Track B / execution-state research closure

Track B studied execution-state fork, continuation, persistence, and
representation transition. Its authoritative closure says do not reopen it
automatically.

```text
Why started     = test whether fork/continuation state is real and portable
What changed    = later work separated execution semantics from physical backend
Established     = bounded closure/frozen evidence
Not established = no claim outside the registered fixtures
Disposition     = CLOSED / FROZEN
Primary entries = trackB-execution-state/TRACK_B_CLOSURE_RESULTS_20260921.md,
                  docs/00-governance/EXPERIMENT_REGISTER_20260922.md
```

## 6. Governance and constitution turn

The lab adopted an operative research constitution plus an inductive
epistemological governance layer. The core target is the ES↔IS persistent
computing closure loop; satellites have three states; promotion requires an
explicit repatriation proof.

```text
Established     = explicit core/satellite governance and drift controls
Not established = no automatic promotion from interestingness
Status          = operative governance
Primary entries = docs/00-governance/SIMIGO_LAB_RESEARCH_CONSTITUTION_20261005.md,
                  docs/00-governance/RESEARCH_GOVERNANCE_CONSTITUTION_V0.1.md,
                  docs/00-governance/RESEARCH_GOVERNANCE_CONSTITUTION_V0.2.md,
                  C01-research-constitution-v1.md
```

## 7. ES ↔ IS conceptual chain

After governance, research converged on the coupling of Execution State and
Information Space. The conceptual chain became:

```text
Information → Resolve → Instantiate → Continue
```

I-1 persistence/resolve, I-1c instantiate completeness, and I-1d runtime
realization were frozen. Their implementation gates G-1..G-4 closed with
bounded conformance/runtime evidence.

```text
Established     = concept chain, frozen contracts, and bounded implementation
Not established = not a complete Information Space or universal carrier theory
Status          = frozen/closed obligations feeding current ES↔IS route
Primary entries = C04, C05, C06,
                  docs/RESEARCH_STATE.md,
                  docs/02-evidence/es-is-20261005/runtime_g1/
```

A later Information/Relation persistence baseline must also be inherited:

```text
Information and Relation = independent semantic objects
InformationStore ∥ RelationStore = parallel boundaries, not a Super Store
S1-S6 ∥ R1-R6 = symmetric persistence contracts; both first-write-wins
Backend evidence = SQLiteStore + InMemoryStore; database remains an
                  implementation choice, not an architecture premise
Disposition       = Phase 2 closed/PASS; semantic/persistence boundary only
Primary entries   = docs/RESEARCH_STATE.md Phase 0-2 records,
                    commit b29d4198,
                    docs/00-governance/EVIDENCE_INHERITANCE_DESIGN_MATRIX_20261006.md
```

## 8. Palace / Information Space Foundation route

The current route asks whether Information Space can become the information
foundation on which Execution State continuity depends and evolves. The old
PALACE line was reconciled as historical input; "PALACE" here is a route name,
not a product mandate or a new external database project.

Progress:

```text
Route opening       = accepted/closed
PRQ-ISF-01 design   = accepted/closed
PRQ-ISF-01 execution= accepted/closed; probe succeeded mechanically, but
                      no independent carrier was tested
A4/Core audit       = accepted/closed for UTF-8/text-bounded PRQ domain
PICS-01             = documentation study; bounded pass/closed
CCVS-01             = active carrier validation study, Phase C in progress
```

Current boundary:

```text
Current legal surface = review of U-1 Unified Addendum Protocol v0.1
Forbidden unless separately ruled = backend selection, carrier integration,
Lab migration/reorganization, Frozen Contract change, or experiment outside
the frozen CCVS protocol
Primary entries = docs/RESEARCH_CONTEXT_INDEX.md,
                  docs/RESEARCH_STATE.md,
                  docs/02-evidence/es-is-20261005/
```

## 9. PRQ-ISF-01

PRQ-ISF-01 tested a minimal decodable probe in a registered UTF-8/text-bounded
domain. It did not select an independent carrier.

```text
Established     = probe mechanism result within the registered domain
Not established = no independent-carrier result; no global Information Space
Disposition     = ACCEPTED / CLOSED / INDETERMINATE for independent carrier
Primary entries = C08-prq-isf-01-probe-design.md,
                  C09-prq-isf-01-execution.md,
                  docs/02-evidence/es-is-20261005/
```

## 10. Carrier studies

PICS-01 decomposed physical carrier responsibilities without selecting a
backend. CCVS-01 followed with a frozen candidate/performance validation
protocol and authorized Phase C.

```text
PICS-01         = ACCEPTED / BOUNDED PASS / CLOSED
CCVS-01-PB v1.2 = ACCEPTED / FROZEN
CCVS-01 Phase C = AUTHORIZED / IN PROGRESS
File prior evidence = Folder Initialization real run; bounded text-domain
                      substrate plus measured gaps; not backend selection
U-1 v0.1        = REVISED / direction confirmed / structural revision gate
U-1 v0.2        = REVIEWED / REVISE (R-1..R-11, zero BLOCK) /
                  direction and semantic anchoring accepted; not frozen
UA v0.3         = MANDATED with R-1..R-11 fixes, A-1..A-3 dispositions,
                  and CC-MA Multi-Agent Carrier Consistency
Final backend   = NOT SELECTED / Phase E gate
Primary entries = docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_PICS01_*,
                  docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_*,
                  simigo2-experimental/
```

## 11. MemPalace and information experiments

MemPalace and the folder Information/SQLite experiments are historical and
stopped as Lab-wide memory/database carriers. They are retained as evidence.

```text
MemPalace as-is direct PRQ carrier = NO-GO / historical negative feasibility
Folder Information experiment      = bounded/real-run observation; stopped
Carrier implementation permission  = NONE without a new ruling
Primary entries = C10-a4-core-sufficiency-audit.md,
                  C12-folder-information-initialization.md,
                  docs/02-evidence/es-is-20261005/,
                  docs/02-evidence/folder-information-initialization-20261004/,
                  docs/00-governance/EVIDENCE_INHERITANCE_DESIGN_MATRIX_20261006.md
```

This disposition does not declare the general information direction failed. It
means those specific carriers/experiments must not silently become the Lab-wide
database.

## 12. Local Closure / Information Reduction

Local Closure studied which information was actually needed for continuation
and ran a bounded reduction round. It found narrow, frame-bounded necessity
candidates but did not prove general minimality.

```text
Established     = bounded Round 1 observations and narrowed candidates
Not established = formal cross-model runtime and general minimality
Disposition     = partially sealed; representation/reduction evidence only;
                  later ES↔IS route has priority
Primary entries = C15-local-closure-information-reduction.md,
                  docs/02-evidence/local-execution-information-closure/,
                  docs/00-governance/SIMIGO_LAB_INFORMATION_ROUND1_RESULT_20261005.md,
                  docs/00-governance/EVIDENCE_INHERITANCE_DESIGN_MATRIX_20261006.md
```

## 13. Cross-model / continuation evidence

T4, T4-2, R-C1 #4, and T5 established task-domain-bounded continuation
replication evidence. These results do not generalize to every task.

```text
Established     = structural independent task-domain replication passes
Not established = no universal continuation theorem
Disposition     = gate chain sealed/closed
Primary entries = C13-t4-t42-rc1-continuation-evidence.md,
                  docs/00-governance/SIMIGO_LAB_T5_REPLICATION_DECLARATION_20261004.md,
                  docs/02-evidence/{t4-execution,t42-execution,t5-execution,rc1-*}
```

## 14. Palace V2 durable-information study

Palace V2/G0-G3 studied durable information and real work recovery. It produced
bounded observations and was closed; its lessons feed later ES↔IS work but are
not current state.

```text
Established     = G0-G3 bounded durable-information findings
Not established = no complete production Information Space claim
Disposition     = CLOSED / historical
Primary entries = C14-palace-g0-g3-durable-information.md,
                  docs/02-evidence/palace-realwork-t1/,
                  docs/02-evidence/palace-v2-*/,
                  docs/00-governance/EVIDENCE_INHERITANCE_DESIGN_MATRIX_20261006.md
```

## 15. Boundary Study / EXP1-X1 / Y

Boundary Study and EXP1-X1 examined trust, verification, frontier, and real
work boundaries. X1 was accepted/closed with the bounded findings that explicit
work frontiers survived strongly, judgment+basis was the load-bearing record
form, and trust did not transfer automatically with stored information.

The private/shared chain adds stronger constraints:

```text
BR-1 = lifecycle-form split; same content does not imply same layer
BR-2 = pure continuity metadata defaults private
BR-3 = formed reusable products enter shared Information
BR-5 = shared Information existence does not summon itself; read/activation
       semantics are separate
T1-T3 = behavioral deposit → pointer → consume evidence
Y    = BR-2 supported / no explicit counterexample / sealed closed
```

```text
Current recovery disposition = PAUSED / HISTORICAL / NEEDS CONNECTED RECOVERY
Forbidden action             = infer completion or reopen without ruling
Primary entries = boundary-study/,
                  boundary-study/exp1-x1/{00-MANIFEST,RECORD,RESULTS}.md,
                  boundary-study/y-exp/Y-EXECUTION-REGISTRATION.md,
                  docs/00-governance/SIMIGO_LAB_PALACE_BOUNDARY_FROZEN_Y_REVIEW_20261002.md,
                  docs/00-governance/SIMIGO_LAB_PALACE_Y_RULING_20261002.md,
                  docs/00-governance/RESEARCH_STAGE_SYNTHESIS_20261005.md,
                  docs/00-governance/EVIDENCE_INHERITANCE_DESIGN_MATRIX_20261006.md
```

## 16. Other registered lines

```text
Track A Kernel/Bandwidth = NOT STARTED / conditional, exp06 roofline gate
Track D Adaptive Memory  = NOT STARTED / independent definition required
Track C Multi-device     = FUTURE / separate definition required
Runtime2 skeleton        = NOTE-ONLY / FUTURE
Admissibility            = PAUSED / SATELLITE with registered reflux grounds
Cross-backend further    = EXPLORATORY after task-bounded evidence
846 / CI-C               = EXPLORATORY
M2/M3                    = EXPLORATORY
```

Do not open these because they appear interesting. A satellite return requires
the repatriation proof defined by governance.

## 17. Current frontier and reading order

At this snapshot the lawful recovery order is:

```text
L0      docs/RESEARCH_CONTEXT_INDEX.md
Global  docs/RESEARCH_ESTATES_SUMMARY.md
Coverage docs/RESEARCH_ESTATE_COVERAGE.md
Design inheritance docs/00-governance/EVIDENCE_INHERITANCE_DESIGN_MATRIX_20261006.md
State   docs/RESEARCH_STATE.md
L1      relevant docs/research-capsules/v1/C*.md
L2      cited ruling/contract/decision
L3      cited raw evidence
```

Current active research object:

```text
ES ↔ Information Space carrier validation.
CCVS-01 is in Phase C under frozen protocol.
UA v0.2 was reviewed and ruled B = REVISE. UA v0.3 is mandated with
R-1..R-11, explicit A dispositions, and CC-MA concurrency constraints.
U-2 remains blocked.
```

Preserved unknowns/open gaps include the 2427 orphan-candidate paths, missing
new capsules for PICS/CCVS, partial recovery for Boundary Study/Track E, and
all explicitly unknown research questions in L2/State. This summary must not
fill those gaps by inference.
