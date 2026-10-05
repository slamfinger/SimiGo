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
