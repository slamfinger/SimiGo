# ES↔IS Line — Session Log (2026-10-05, continued)

> Session log for the ES↔IS line beyond the conceptual stage. For the
> conceptual lineage (spec v0.1 → Scenario → Stage Synthesis → I-1 → I-1c →
> I-1d), see the Addenda in
> `docs/02-evidence/ci-c-own-structure-20261005/architecture_review/RESEARCH_LOG.md`
> and the frozen documents in this directory. Authoritative project snapshot:
> `docs/RESEARCH_STATE.md` (2026-10-05 section).

---

## Governance adoption (this day, preceding the line)

- **SimiGo Research Constitution v1.0** adopted (`docs/00-governance/SIMIGO_LAB_RESEARCH_CONSTITUTION_20261005.md`, `e97f5e7`): North Star = the ES↔IS persistent-computing closure loop (unalterable Frame); five closure edges define Core; four Gates; satellite three-state (SUPPORTING/EXPLORATORY/PAUSED); repatriation proof required; five-line session header; hard threshold **Deep but disconnected ≠ Core**.
- **RESEARCH_GOVERNANCE_CONSTITUTION v0.2** adopted as the inductive/epistemological layer (`docs/00-governance/RESEARCH_GOVERNANCE_CONSTITUTION_V0.2.md`, `827ac7b`), parallel to v1.0, not merged. Frame/Model/Claim/Evidence four-layer vocabulary (applies forward); repatriation identity rule ("A was Satellite then; evidence later brought it into Core"); governance anti-recursion (§5A).
- **Admissibility line classified PAUSED / SATELLITE** (closed loop at ES-3; repatriation condition registered: proving F-relation persistence necessity would change the I→S edge).

## The ES↔IS line at a glance (conceptual stage, all frozen)

```text
I-1   Persistence / Resolve               FROZEN — main 2b2e2ef
I-1c  Instantiate Completeness            FROZEN — main 6c3cf6a
I-1d  Runtime Realization / Verification  FROZEN — branch 1832676
```

Key frozen structures: three-level object relation CR → resolve → **R2 (Continuation Basis)** → instantiate(+τ2★) → **S2 (Execution State)** (R2 is NOT an Execution State); IC-1..7 contract; three-state binding (BOUND/UNBOUND/MISMATCH); structural finding **"missing information is not necessarily a State component — it may be a binding-decidability input"**; seam **State necessity ≠ binding-decidability necessity**; M-table frozen at nine; VV surface VV-1..VV-7 with tiers VERIFIED/COVENANTED/FAILED; four orthogonal layers (Runtime Object / Verification State / Disposition / Lifecycle); post-freeze finding paths (Implementation finding / Evidence finding / Future alternative). Conceptual chain **Information → Resolve → Instantiate → Continue: CLOSED.**

## Implementation Gate (CLOSED by Human ruling 2026-10-05)

Human ruling basis: `G4_DELIVERY.md` v2 closure audit at `d1043b8` — mapping 13/13, IF-G4-01..04 independently locked, post-fix G-1/G-2/G-3 regression PASS, C-CAP 10/10 SUPPORTED, frozen-contract drift 0.

| Scope | Status | Commit | Conformance |
|---|---|---|---|
| G-1 CR/IR formats + resolve | **ACCEPTED / CLOSED** | `1af023d` + IF-G1-01 fix `3b8b0ba` | 19/19 |
| G-2 instantiate pipeline + VV-1..7 | **ACCEPTED / CLOSED** | `95bde40` → `17d2ff5` → `e3cde56` | 17/17 |
| G-3 the E-run | **ACCEPTED / CLOSED** | `bcbaafd` → `aa0eb12` → **`397fbca`** | 10/10 evidence items |
| G-4 per-carrier mapping + audit | **ACCEPTED / CLOSED** | `runtime_g1/G4_DELIVERY.md` v2 + fix `d1043b8` | mapping 13/13; post-fix G-1 19/19, G-2 17/17, G-3 10/10 |

**IF ledger (all registered, fixed, and CLOSED by review):**
IF-G1-01 (result attribution V-1 vs V-2) · IF-G2-01 (MISMATCH disposition) ·
IF-G2-02 (substrate.bind never invoked) · IF-G2-03 (MISMATCH early return) ·
IF-G2-04 (VV-restore invented an 8th check) · IF-G2-05 (post-creation FAILED
→ CREATE-BLOCK) · IF-G2-06 (COVENANTED never exercised) · IF-G2-07 (anomaly
check-id derived from signature prefix) · IF-G2-08 (class-name boundary +
private state instead of readback capability) · IF-G3-01 (S2 not actually
consumed by E2) · IF-G3-02 (no-recompute evidence overstated + C-CAP record
incomplete) · IF-G3-03 (S2 was a guard, not a data source) · IF-G3-04 (two
instantiate lifecycles) · **IF-G4-01 (IR missing `timestamp`/`actor`;
CLOSED)** · **IF-G4-02 (TaskRecord digest is SHA-256 over canonical
supplied `tau_star`; CLOSED)** · **IF-G4-03 (precondition blocks record
uniform `VV-1..7 = NOT ENTERED`; CLOSED)** · **IF-G4-04 (used identities are written directly into IR;
CLOSED)**.

## G-3 E-run v3 — ACCEPTED / CLOSED

```text
E1 executes T1 → CR(E1) (F1..F3 use-time pinned; provenance: E1.seg[0..3] + weights id)
resolve(CR_ref) → RESOLVED, zero violations → R2
instantiate(R2, τ2★, substrate)   [THE single instantiate — IF-G3-04]
     → IR (COMPLETED / PROCEED-WITH-ANNOTATION; BOUND; VV-1..VV-7 all VERIFIED)
     → S2 (continuation_object(): surface bytes + handle + bound weights + position)
T2 consumes S2   ← IF-G3-03: result digest = sha256(S2 surface + position + weights)
                    (direct un-bypassable data dependency; binding checks enforced)
E2 → CR(E2) (lineage parent = CR(E1))
```

**Verdict: C-CAP SUPPORTED (document-form, limited mechanical support on (c)) — 10/10 evidence items, ALL persisted in `G3_ERUN_RECORD.json` (10 ccap entries). Human accepted this at `397fbca` on 2026-10-05.**
Evidence semantics per IF-G3-02: (c) is finite document-form mechanical support (predecessor references complete / identifier-disjoint new work / resolve output consumed); a semantically-equivalent re-derivation under a new id is the registered detection boundary. Carrier-form metrics not exercised (document-form; annotation recorded). Substrate = conformance testbed (MC-1..MC-6), not a production claim. Regression: G-1 19/19, G-2 17/17.

## G-4 per-carrier mapping + audit — ACCEPTED / CLOSED

The delivery is `runtime_g1/G4_DELIVERY.md`. It maps the document-form
`ConformanceSubstrate` to MC-1..MC-6 and covers all 13 rows of frozen
I-1d §1.2. The audit re-ran G-1/G-2/G-3 locally with no failure and fixed the
non-blocking evidence-metadata typo `"G-3 E-run v1"` → `"G-3 E-run v3"`.

All four G-4 findings are CLOSED by Human review after implementation and independent regression locks:

1. **IF-G4-01 CLOSED** — completed IR carries and validates `timestamp`/`actor`.
2. **IF-G4-02 CLOSED** — task digest is SHA-256 over canonical supplied
   `tau_star`; the old `task_ref` proxy was removed and the digest is
   independently recomputed in G-2.
3. **IF-G4-03 CLOSED** — precondition blocks record exactly `VV-1..VV-7 =
   NOT ENTERED`; no `NOT-APPLICABLE` variant remains.
4. **IF-G4-04 CLOSED** — `used_item_identities` is stored directly in IR and
   compared against the CR used set.

## Post-Gate Route Decision — PALACE / Information Space Foundation ACTIVE

The prior Report/Paper Evidence Package route was rolled back at `ffc59a4`.
Human then selected **PALACE / Information Space Foundation** as the唯一 Active
Route. The ruling and Phase 1 charter boundary are in
`PALACE_INFORMATION_SPACE_FOUNDATION_ROUTE_DECISION_20261005.md`.

```text
Active route        = PALACE / Information Space Foundation
Research question   = Can Information Space become the evolvable information
                      foundation on which Execution State depends?
Phase 1             = Route Opening — Boundary Reconciliation &
                      Minimal Carrier Charter
No implementation   = true
No backend integration = true
No contract change  = true
No experiment       = true
```

PALACE is not an MCP server, knowledge base, database schema, storage product,
or application integration in this route. Historical PALACE artifacts must be
reconciled before any is treated as background support.

## PALACE / Information Space Foundation — Phase 1 Charter ACCEPTED / CLOSED

The Route Opening Charter is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_ROUTE_OPENING_CHARTER_20261005.md`.

It reconciles old Palace history, fixes the semantic boundary against
MCP/knowledge-base/database/storage/product misreadings, maps frozen ES↔IS
semantics to Information Space obligations, defines minimal carrier/interface
obligations `IS-MCI-01..08`, and preregisters `PRQ-ISF-01` with
success/failure/indeterminate criteria.

Human review ruled Phase 1 `ACCEPTED / CLOSED`. No blocking finding was raised.

```text
Phase 1 delivery   = e4c74bd
Route baseline     = f4e2ba6
Gate baseline      = ab97244
Frozen Contracts   = UNCHANGED
Next phase         = PRQ-ISF-01 — Minimal Decodable Probe Design
Phase status       = COMMISSIONED / DESIGN ONLY / NOT STARTED

No implementation       = true
No carrier selection    = true
No backend integration  = true
No contract change      = true
No experiment execution = true
```

## PRQ-ISF-01 — Minimal Decodable Probe Design ACCEPTED / CLOSED

The Phase 2 design is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_PRQ_ISF_01_PROBE_DESIGN_20261005.md`.

It defines a symbolic registered fixture, an abstract IS Port limited to
`IS-MCI-01..08`, a mechanical decoder with no semantic rescue, handoff to frozen
I-1 `resolve(CR_ref)` semantics, and scenarios `SC-00..SC-12`. It also
preregisters route-level `SUCCESS / FAILURE / INDETERMINATE` judgments.

Human review ruled the design `ACCEPTED / CLOSED`, with one non-blocking boundary
note: the Abstract IS Port is probe observation vocabulary only—not a future
PALACE API, storage protocol, carrier architecture, or implementation interface.

```text
Phase 2 delivery = 7b9d167
Phase 1 ruling   = 618ea84
Gate baseline    = ab97244
Frozen Contracts = UNCHANGED
Next entry       = Authorization decision for probe implementation / execution

Implementation       = NOT AUTHORIZED
Carrier selection    = NOT AUTHORIZED
Backend integration  = NOT AUTHORIZED
Experiment execution = NOT AUTHORIZED
Contract change      = NOT AUTHORIZED
```

## PRQ-ISF-01 — Probe Implementation / Execution ACCEPTED / CLOSED

Human authorized probe implementation / execution. The implementation used
`ProbeReferencePort`, a non-candidate in-memory probe control, to exercise the
accepted design without selecting a PALACE or external Information Space
carrier.

```text
Scenarios executed        = SC-00..SC-12
Scenario expectations     = 13/13 MATCH
Semantic oracle used      = false
Harness qualification     = PASS
Execution delivery        = 547df19
Execution review          = ACCEPTED / CLOSED
Route PRQ-ISF-01          = INDETERMINATE / NO-INDEPENDENT-CARRIER-UNDER-TEST
Carrier selection         = NONE
Backend integration       = NONE
Contract change           = NONE
```

Human review accepted the three-layer boundary:

```text
1. Probe design is correct.
2. Probe / decoder / resolver handoff is mechanically executable.
3. An independent Information Space carrier satisfies IS-MCI-01..08.
```

The work reached (2), not (3). Therefore `13/13 MATCH` is not carrier validation.

## Carrier-Path Decision — MemPalace selected as first independent candidate

Human ruled Carrier Path **A** and selected **MemPalace local file-backed core**
as the first independent candidate carrier. The decision record is
`PALACE_INFORMATION_SPACE_FOUNDATION_CARRIER_PATH_DECISION_20261005.md`.

```text
Carrier Path           = A / select independent candidate carrier
Candidate              = MemPalace local file-backed core
Role                   = first independent carrier under test
Selection status       = CANDIDATE SELECTED / FEASIBILITY NOT ESTABLISHED
Next entry             = MemPalace IS-MCI Adapter Feasibility Audit
Phase guard            = READ-ONLY FEASIBILITY AUDIT ONLY

No adapter implementation  = true
No carrier integration     = true
No MemPalace mutation      = true
No probe execution         = true
No contract change         = true
No experiment              = true
```

The next audit must classify `IS-MCI-01..08` as `DIRECT`, `ADAPTER`, or `GAP`.
Semantic search, summaries, inference, fuzzy retrieval, or completion must not be
accepted as substitutes for identity, canonical content, lineage, historical
pinning, or mechanical failure discipline.

## MemPalace IS-MCI Adapter Feasibility Audit DELIVERED

The read-only audit is delivered at
`MEMPALACE_ISMCI_ADAPTER_FEASIBILITY_AUDIT_20261005.md`.

It classified the selected MemPalace candidate as:

```text
DIRECT   = 1 / 8   provenance separation
ADAPTER  = 2 / 8   canonical records, evolution events
GAP      = 5 / 8   immutable content, typed references,
                   historical pinning, lineage, mechanical failure discipline
```

Verdict:

```text
MEMPALACE AS-IS = NO-GO FOR PRQ-ISF-01 CARRIER TEST
THIN ADAPTER    = NOT FEASIBLE
Reason          = closing the five GAPs would build a new carrier layer,
                  not independently test MemPalace
```

No MemPalace data was mutated. The audit used read-only MCP inspection, source
reading, and read-only SQLite checks.

## MemPalace Feasibility Audit ACCEPTED / CLOSED

Human review accepted the negative feasibility result at delivery `1540cae`.
MemPalace is eliminated **as-is** from the current independent-carrier test; the
result is preserved as a valid candidate elimination.

```text
MemPalace audit = ACCEPTED / CLOSED
Verdict         = MEMPALACE AS-IS NO-GO
Thin adapter    = NOT FEASIBLE
PRQ-ISF-01      = INDETERMINATE / NO-INDEPENDENT-CARRIER-UNDER-TEST
```

## Option A4 — Carrier Gap Study Scope & Research Question Charter DELIVERED

Human selected **A4**: authorize a new non-implementation research question into
the minimal missing carrier layer.

```text
A4 study      = Carrier Gap Study
Core question = What minimal carrier layer is required to satisfy the
                MemPalace GAP areas without semantic inference, hidden
                completion, candidate mutation, or Frozen Contract change?
Status        = SCOPE & RESEARCH QUESTION CHARTER DELIVERED / AWAITING HUMAN REVIEW
Next entry    = Human review of the A4 scope charter
```

## A4 Scope & Research Question Charter — DELIVERED

The charter is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_CARRIER_GAP_STUDY_SCOPE_CHARTER_20261005.md`.

It defines:

```text
GAP dimensions       CGT-1..CGT-7
Obligation sources   SRC-FROZEN / SRC-PRQ / SRC-IS-SEMANTIC / SRC-PROBE-LOCAL
Candidate primitives P1..P8
Study questions      CGQ-1..CGQ-5
```

Its central discipline is that a MemPalace gap does not automatically become a
carrier obligation. Each requirement must be traced to Frozen ES↔IS semantics,
the registered PRQ mutation class, general Information Space semantics, or
probe-local expression.

```text
Status = DELIVERED / AWAITING HUMAN REVIEW
No implementation       = true
No adapter              = true
No carrier integration  = true
No MemPalace mutation   = true
No probe execution      = true
No experiment           = true
No contract change      = true
```

## Next steps (none auto-open)

1. Human review the A4 scope charter.
2. On ACCEPT: execute the conceptual Carrier Gap Study according to
   `CGQ-1..CGQ-5`.
3. On FINDINGS: revise the scope charter without implementation.
4. On REJECT/PAUSE: close or pause A4 by explicit ruling.
5. No adapter implementation, carrier integration, MemPalace mutation, probe
   execution, experiment, or Frozen Contract change is authorized.
2. Pin the exact MemPalace audit specimen and read-only boundary.
3. Classify every `IS-MCI-01..08` obligation as `DIRECT`, `ADAPTER`, or `GAP`.
4. Return to Human review before any adapter implementation, integration,
   probe execution, or contract change.
