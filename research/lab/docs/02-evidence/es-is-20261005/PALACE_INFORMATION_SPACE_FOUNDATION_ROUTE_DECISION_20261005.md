# PALACE / Information Space Foundation — Route Decision

Date: 2026-10-05
Status: `HUMAN RULING COMPLETE · PALACE / INFORMATION SPACE FOUNDATION = UNIQUE ACTIVE ROUTE`
Accepted Implementation Gate baseline: `ab97244`
Rollback of the prior Report/Paper route: `ffc59a4`
Frozen Contracts: `UNCHANGED`
Current phase guard: `NO FURTHER IMPLEMENTATION · NO CARRIER SELECTION · NO BACKEND INTEGRATION · NO CONTRACT CHANGE · NO EXPERIMENT BEYOND COMPLETED REGISTERED PROBE SCENARIOS`
Phase 1 status: `ACCEPTED / CLOSED` (Human review; delivery `e4c74bd`)
Phase 2 design: `PRQ-ISF-01 — MINIMAL DECODABLE PROBE DESIGN ACCEPTED / CLOSED`
Probe implementation / execution: `AUTHORIZED / COMPLETE / ACCEPTED / CLOSED`
Execution delivery: `547df19`
Execution verdict: `PRQ-ISF-01 = INDETERMINATE / NO-INDEPENDENT-CARRIER-UNDER-TEST`
Next entry: `EXPLICIT CARRIER-PATH DECISION (NO AUTO-START)`

## 1. Ruling

Human selected **PALACE / Information Space Foundation** as the唯一 Active Route.

This is not authorization to build an MCP server, knowledge base, database product,
or PALACE application. The route asks one research question:

> Can Information Space become the evolvable information foundation on which
> Execution State depends for continued operation?

If supported, a later Backend Integration route may become meaningful as:

```text
Information Space
       ↓
Execution State
       ↓
Real Backend
       ↓
new Execution State / Information
       ↺
```

That later route is not opened by this ruling.

## 2. Route state

```text
PALACE / Information Space Foundation   ACTIVE — Phase 1 opening only
Report / Paper Evidence Package         ROLLED BACK / SUPERSEDED
Backend integration                     PENDING / BLOCKED
External E-run beyond G-3               PENDING / BLOCKED
Pause ES↔IS                             PENDING
Frozen Contract modification            BLOCKED without separate revision gate
```

The prior Report/Paper route records at `4bdbd11`, `579b508`, and `6434627`
remain recoverable in git history but are not active authority. They were rolled
back at `ffc59a4`.

## 3. Historical reconciliation requirement

This ruling does not silently reopen every historical PALACE artifact or claim.
Phase 1 must explicitly reconcile prior PALACE state:

- what was CLOSED, PAUSED, or only a historical candidate;
- what belongs to database/product semantics and is excluded here;
- what can be carried forward as background, not as assumed support;
- what must be rephrased as a new Information Space foundation question.

PALACE, in this route, means the candidate foundation for a persistent and
evolvable Information Space—not an MCP server, knowledge base, database schema,
storage product, or application integration.

## 4. Phase 1 — Route Opening only

Next entry:

```text
PALACE / Information Space Foundation —
Boundary Reconciliation & Minimal Carrier Charter
```

Phase 1 may only:

1. reconcile prior PALACE history and current-route semantics;
2. map ES↔IS frozen objects to candidate Information Space obligations:
   - `CR / used / surface / continues`;
   - `R2` as Continuation Basis;
   - `instantiate → IR + S2`;
   - used-item identities, lineage, and continuation provenance;
3. define minimal carrier/interface obligations without selecting storage,
   schema, backend, or product;
4. pre-register the first decodable research question with success / failure /
   unable-to-judge criteria;
5. register non-claims and forbidden shortcuts.

## 5. Non-claims for Phase 1

No output of Phase 1 may claim that:

- PALACE has been selected as a storage implementation;
- Information Space has been proven necessary for Execution State;
- the ES↔IS loop has been externally reproduced;
- a backend can now be integrated;
- an MCP, database, graph store, or knowledge base satisfies the route;
- Frozen Contracts imply or authorize a PALACE schema;
- current G-3 results generalize beyond the registered document-form boundary.

Phase 1 success means only that the route opening charter is precise enough for
Human review. It does not establish PALACE viability.

## 6. Phase 1 review and next gate

Human review on 2026-10-05 ruled:

```text
Phase 1 Route Opening Charter = ACCEPTED / CLOSED
Delivery                      = e4c74bd
Route baseline                = f4e2ba6
Gate baseline                 = ab97244
Frozen Contracts              = UNCHANGED
Next phase                    = PRQ-ISF-01 — Minimal Decodable Probe Design
```

Human review subsequently accepted the Phase 2 probe design:

```text
Phase 2 Minimal Decodable Probe Design = ACCEPTED / CLOSED
Delivery                               = 7b9d167
Phase 1 ruling                         = 618ea84
Gate baseline                          = ab97244
Frozen Contracts                       = UNCHANGED
Next entry                             = Authorization decision for probe
                                         implementation / execution
```

Boundary note: the Abstract IS Port (`put_blob / get_blob / put_node / ...`) is
probe observation vocabulary only. It is not a future PALACE API, storage
protocol, carrier architecture, or implementation interface.

Implementation and execution were subsequently authorized. The executed carrier
was `ProbeReferencePort`, a non-candidate in-memory probe control. It exercised
the decoder, frozen I-1 resolver handoff, and judge without selecting PALACE,
MCP, a database, a graph store, a file format, or any external carrier. All 13
preregistered scenario expectations matched. Therefore the harness is qualified,
but `PRQ-ISF-01` is `INDETERMINATE / NO-INDEPENDENT-CARRIER-UNDER-TEST`; it does
not support a claim that PALACE or any concrete Information Space carrier can
satisfy the route.

Human review on 2026-10-05 accepted the execution with that boundary:

```text
PRQ-ISF-01 Execution = ACCEPTED / CLOSED
Delivery             = 547df19
Probe Design         = 7b9d167
Gate baseline        = ab97244
Frozen Contracts     = UNCHANGED
Route verdict        = INDETERMINATE / NO-INDEPENDENT-CARRIER-UNDER-TEST
Next entry           = explicit carrier-path decision
```

The accepted distinction is:

```text
1. Probe design is correct.
2. Probe / decoder / resolver handoff is mechanically executable.
3. An independent Information Space carrier satisfies IS-MCI-01..08.
```

The completed work reached (2), not (3). No carrier path is selected. Candidate
actions remain pending explicit Human ruling:

```text
select an independent candidate carrier for a meaningful PRQ test
revise the Foundation route
pause the Foundation route
name another explicitly authorized action
```

## 7. Carrier-path decision

Human ruling on 2026-10-05 selected Carrier Path **A**.

```text
Carrier Path                = A / select independent candidate carrier
Independent candidate       = MemPalace local file-backed core
Role                        = first independent carrier under test
Selection status            = CANDIDATE SELECTED / FEASIBILITY NOT ESTABLISHED
Next entry                  = MemPalace IS-MCI Adapter Feasibility Audit
```

This does not validate MemPalace. It selects MemPalace as the first independent
candidate whose native capabilities must be audited against `IS-MCI-01..08`.
The audit must classify each obligation as `DIRECT`, `ADAPTER`, or `GAP`.
Semantic search, LLM summaries, semantic inference, fuzzy retrieval, or automatic
completion must not be allowed to stand in for identity, canonical content,
lineage, historical pinning, or mechanical failure discipline.

This ruling authorizes only the read-only feasibility audit. Adapter
implementation, MemPalace modification, carrier integration, probe execution
against MemPalace, experiments, backend integration, and Frozen Contract changes
remain unauthorized.

## 8. MemPalace outcome and Option A4

Human review accepted the MemPalace feasibility audit:

```text
MemPalace IS-MCI Adapter Feasibility Audit = ACCEPTED / CLOSED
Delivery                                   = 1540cae
Candidate                                  = MemPalace local file-backed core
Classification                             = DIRECT 1 / ADAPTER 2 / GAP 5
Verdict                                    = MEMPALACE AS-IS NO-GO
Thin adapter                               = NOT FEASIBLE
Frozen Contracts                           = UNCHANGED
```

MemPalace is eliminated **as-is** from the current independent-carrier test. The
negative result is preserved as a valid candidate elimination, not as a failed
experiment.

Human then selected **Option A4**: commission a new non-implementation research
question into the minimal missing carrier layer.

```text
A4 study        = Carrier Gap Study
Core question   = What minimal carrier layer is required to satisfy the
                  MemPalace GAP areas without semantic inference, hidden
                  completion, candidate mutation, or Frozen Contract change?
Status          = COMMISSIONED / SCOPE CHARTER PENDING
Next entry      = Human review of InformationCore / RelationCore Sufficiency Audit
```

Human review accepted the scope charter and commissioned the A4 conceptual study:

```text
A4 Scope & Research Question Charter = ACCEPTED / CLOSED
Delivery                             = 2f0959b
Gate baseline                        = ab97244
Frozen Contracts                     = UNCHANGED
A4 Conceptual Study                  = COMMISSIONED / NOT STARTED
Study questions                      = CGQ-1..CGQ-5
```

The commissioned study is conceptual / documentary only. Adapter implementation,
carrier implementation, MemPalace mutation, integration, probe execution,
experiments, backend integration, and Frozen Contract changes remain unauthorized.

## 9. A4 scope charter

The Carrier Gap Study scope and research question charter is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_CARRIER_GAP_STUDY_SCOPE_CHARTER_20261005.md`.

It defines:

```text
GAP dimensions                 CGT-1..CGT-7
Obligation sources             SRC-FROZEN / SRC-PRQ /
                               SRC-IS-SEMANTIC / SRC-PROBE-LOCAL
Candidate primitives           P1..P8
Study questions                CGQ-1..CGQ-5
Completion criteria            nine-point A4 delivery standard
```

It explicitly separates minimal semantic obligations from probe-local expression
and carrier implementation details. Human review is the next gate; no
implementation, adapter, carrier integration, MemPalace mutation, probe execution,
experiment, or contract change follows automatically.

## 10. A4 conceptual study

The A4 conceptual study is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_CARRIER_GAP_STUDY_CONCEPTUAL_STUDY_20261005.md`.

It answers `CGQ-1..CGQ-5` and reduces the candidate primitives to seven bounded
carrier-layer semantics:

```text
MCL-1  Immutable Content Datum
MCL-2  Exact Identity / Pin Resolution
MCL-3  Typed Relation Record
MCL-4  Separated Provenance Record
MCL-5  Succession Relation
MCL-6  Lineage Closure
MCL-7  Mechanical Failure Surface
```

It also defines eight failure families and four carrier archetypes. The result is
bounded to the registered PRQ-ISF-01 mutation class; it does not claim universal
minimality, select a carrier, authorize implementation, or modify Frozen
Contracts.

## 11. A4 reduction / ownership study

Human review returned `FINDINGS / REVISE REQUIRED` on the prior A4 conceptual
study. The required reduction study is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_A4_REDUCTION_OWNERSHIP_STUDY_20261005.md`.

It separates:

```text
Carrier-state semantics        CS-1..CS-6
Derived observation            deterministic resolution, pin verification,
                               canonical identity, relation integrity,
                               lineage closure, frozen failure mapping,
                               indeterminacy classification
Non-carrier                    mechanical failure surface as a carrier primitive
```

The study does not select an archetype, authorize implementation, select a
carrier, or modify Frozen Contracts.

## 12. Human reframe and Core Sufficiency Audit

Human review reframed the A4 result. The prior reduction remains a candidate
semantic decomposition, not six physical carrier primitives. The corrected chain
is:

```text
Frozen ES↔IS semantics
        ↓
PRQ-ISF-01 obligations
        ↓
Information / Relation semantic core
        ↓
Store boundary
        ↓
SQLite / InMemory / MemPalace / other backends
```

The Core Sufficiency Audit is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_CORE_SUFFICIENCY_AUDIT_20261005.md`.

Its result is:

```text
For UTF-8/text-bounded PRQ:
  InformationCore + RelationCore + Store boundaries are sufficient to express
  PRQ-ISF-01 continuation graph semantics.

No new Store primitive is currently required.

Higher-layer work:
  CR/canonical mapping, predicate conventions, historical pin resolution,
  succession semantics, lineage traversal/cycle validation, and frozen
  failure-family mapping.

Conditional semantic gap:
  arbitrary non-Unicode byte fidelity in Information.content.
```

MemPalace is not eliminated as a future backend or migration target; it is only
ruled out as a direct native PRQ semantic carrier without a semantics-preserving
adapter.

## 13. Core Sufficiency ruling candidate

The final candidate was subsequently accepted. It
incorporates the required scope correction:

```text
Text domain = currently registered PRQ-ISF-01 task domain only.
Not a global or permanent Information Space boundary.
```

The candidate ruling states:

```text
Core Sufficiency Audit = ACCEPTED / CLOSED
Current PRQ domain     = UTF-8 / text-bounded
Core/Relation/Store    = sufficient for that domain
New Store primitive    = NOT REQUIRED
Carrier semantic layer = NOT REQUIRED for current PRQ domain
Arbitrary-byte finding = CONDITIONAL ONLY
Higher-layer items     = O-3/O-6/O-7/O-8/O-9
MemPalace              = narrow AS-IS PRQ NO-GO only
Relation asymmetry     = implementation/test debt, not current blocker
Next research entry    = Higher-Layer Continuation Graph Semantics
```

No formal Human ruling has yet been recorded.

## 14. Core Sufficiency Audit accepted

On 2026-10-06, Human accepted the final ruling candidate.

```text
Core Sufficiency Audit = ACCEPTED / CLOSED
Current PRQ-ISF-01 domain = UTF-8 / text-bounded, task-domain bounded
Core + Relation + Store = sufficient for that registered domain
New Store primitive = NOT REQUIRED
Carrier semantic layer = NOT REQUIRED for current domain
Arbitrary-byte fidelity = conditional finding only; not a current gap
Higher-layer obligations = O-3/O-6/O-7/O-8/O-9
MemPalace = narrow AS-IS PRQ carrier-test NO-GO only
Relation backend asymmetry = implementation/test debt, not current blocker
Next entry = Higher-Layer Continuation Graph Semantics —
             Scope & Research Question Charter
Frozen Contracts = UNCHANGED
```

This closes only the question of whether the current PRQ task domain requires new
Core / Store / carrier semantics. It does not close Information Space generally or
authorize implementation.

## 15. Fresh-Agent recovery evaluation

Human review evaluated the first fresh-Agent recovery run as:

```text
Fresh-Agent L0→L1 Recovery Test = NOT VALIDATED / WRONG ENTRY SURFACE
Evaluation delivery             = PALACE_INFORMATION_SPACE_FOUNDATION_FRESH_AGENT_RECOVERY_EVALUATION_20261006.md
```

The intended L0/L1 surface exists on research branch `d198a31`:

```text
docs/RESEARCH_CONTEXT_INDEX.md
docs/research-capsules/v1/C01..C15
```

But a fresh Agent entering the default repository surface recovered
`origin/main @6c3cf6a`, where those files are absent. Therefore the run did not
test L0/L1 quality or recovery capability. It exposed two findings:

```text
default-repository discoverability failed;
branch-to-current-state binding failed.
```

No branch merge, carrier selection, implementation, experiment, or contract
change is authorized. Human must explicitly choose PATH A/B/C/D from the
evaluation report.

## 16. Path A controlled integration plan

Human selected PATH A. The controlled integration plan is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_PATH_A_INTEGRATION_PLAN_20261006.md`.

Machine probe result:

```text
origin/main          = 6c3cf6a
research tip         = 3f467d3
merge base           = dd61b495
divergence           = 2 / 327
merge-tree           = CLEAN
proposed merged tree = bac63b9d415e02bf9280311504c39479e8356d82
I-1 / I-1c blobs     = unchanged
I-1d                 = introduced by research branch
```

The plan requires a two-parent, no-ff integration commit and forbids squash,
force-reset, and hand-rewriting Frozen Contract conflicts. It also requires
post-merge validation of L0/L1 presence, all 15 capsules, protected semantic
blobs, default-entry discoverability, and a fresh-Agent rerun.

Merge execution, default-main update, and rerun remain unauthorized until Human
approves the plan.
