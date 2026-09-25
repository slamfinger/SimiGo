# SimiGo 2.0 Runtime Residency Engineering — Contract Verification Design v1.0

Status: CONTRACT_VERIFICATION_DESIGN_v1.0_REGISTERED / IMPLEMENTATION_NOT_STARTED
Date: 2026-09-25
Gate: CONTRACT VERIFICATION DESIGN — design only, no production code
Contract under verification: `SIMIGO2_RUNTIME_RESIDENCY_ENGINEERING_
REQUIREMENTS_v1.0.md` (efeb49c) — requirements R1.1–R4.3 (35 RFC-2119
items), acceptance points 1–14.

## 0. Verification question

> How do tests, fault injection, state-machine verification, and
> real-runtime reconciliation prove that the 35 requirements of the frozen
> contract are actually satisfied by the implementation?

Non-goals carried over unchanged: no prediction, no probability, no
Router/Expert, no production MLX modification, no async I/O, no computation
skipping, no frozen-vocabulary objects.

## 1. The central invariant (the contract's spine)

The research line's byte-reconciliation result (375 validated rows,
C_model + ε) is promoted into the **log-replay equivalence** invariant:

```text
INV-1 (log-replay equivalence):
  For any operation sequence — plans, admissions, executed/failed/cancelled
  transfers, pressure evictions — the controller's resident bookkeeping
  MUST equal the replay of its own transfer log:
      residentBookkeeping == replay(transferLog)
  after every completed step, including DIRTY states.

INV-2 (frontier oracle):
  For any admitted request sequence over a fixed inventory,
  cumulativeLoggedReloadBytes == n·optionalTotal − retainedLeadingIntegral
  computed from the bookkeeping (E0 frontier identity, demoted to a test
  oracle).

INV-3 (byte reconciliation):
  idleActiveBytes − (residentBytes + C_model) MUST lie within ε on every
  transition against a real runtime (registered constants; ε ≤ 5 MiB).
```

Every verification item below ultimately evidences one of these three
invariants or a directly testable requirement clause.

## 2. Verification architecture — four layers

### L1 — Planner purity and contract unit tests (pure Swift, no MLX)

- **V-P1 (R1.1)** determinism/purity: identical inputs → identical plans;
  no observable side effects; planner type carries no model/materializer
  dependency.
- **V-P3 (R1.3)** overflow report-only property: for arbitrary budget
  values, `fitsBudget == (residentBytes ≤ budgetBytes)`; on overflow the
  plan is still returned with the mandatory set resident — the planner
  never resolves overflow.
- **V-P5 (R1.5)** type-level isolation: planner input/output types contain
  no executor/model handles.
- Symbolic fixture inventory (1 core + 3 equal optional groups, 400 bytes —
  the registered test geometry) for exhaustive small-space properties.

### L2 — Controller state-machine verification (mock materializer)

The controller is specified as a state machine and verified by exhaustive
enumeration over a bounded symbolic space:

```text
states   : CLEAN | DIRTY
events   : admit(request), plan, admitPlan, loadGroup→ok|fail,
           evictGroup→ok|fail, cancel, pressure(target),
           reconcile→ok|mismatch, recover
invariants: INV-1 after every step; INV-2 over any completed sequence;
            DIRTY entered only on evict-failure / reconcile-mismatch;
            DIRTY exits only via recovery; no plan admission while DIRTY.
```

- **V-S1** exhaustive enumeration: all operation sequences up to length 8
  over the symbolic space (3 groups, fault injections at any group
  boundary) satisfy INV-1 and the transition rules. Feasible space: small
  alphabet, bounded depth.
- **V-S2** admission discipline (R2.2): no transfer-log entry may exist
  between plan generation and the controller's admit/reject decision; the
  decision is all-or-nothing per plan.

### L3 — Fault injection (mock materializer implementing the executor port)

Fault catalog — each fault injectable at any group boundary:

```text
F1  load fails after k of m groups   → R3.8 atomicity, R3.12, INV-1
F2  evict fails                      → R3.13 UNKNOWN/DIRTY, V-R2
F3  cancel during load               → R3.15–R3.16 (log recomputation)
F4  cancel during evict              → R3.17 (complete or DIRTY)
F5  reconcile deviation > ε injected → R3.6 DIRTY
F6  host budget shrink mid-request   → R3.11 fail-fast on next required
                                       overflow; in-flight unaffected
F7  pressure event                   → R3.21–R3.24 (logged, no in-flight
                                       required victims, no speculative
                                       reload afterwards)
F8  concurrent admission             → R3.18–R3.20 (serialized mutations,
                                       admission order, joint residency)
```

Each fault test asserts: the transfer log, the bookkeeping, the returned
error surface, and the state (CLEAN/DIRTY) — all four must cohere.

### L4 — Real-runtime reconciliation integration (MLX, on-device)

- **V-R1 (R3.5/INV-3)**: controller + real materializer on a real model;
  after every transition, `Memory.snapshot()` idle bytes vs bookkeeping +
  C_model within ε.
- **V-C3 (R2.3/R3.9)**: transfer-log format compatibility with the
  research-line format (groupIDs, bytes, milliseconds; entry appended
  before control returns — ordering asserted via the mock, format via the
  real run).
- **V-ID**: controller-served generation output identity vs a baseline
  generation (Gate-5-style check) — correctness through the full
  controller path.
- **Required fixtures**: Qwen3-Coder-30B (primary, C_model = 0) and
  Nail-Qwen3.6 (exercises the C_model = −851.1 MiB offset). Other three
  registered models optional.

## 3. Research-line fixtures reused (research → verification handoff)

```text
C_model constants : 0 (Qwen3-Coder, Gemma4, Muse);
                    −851.1 / −851.5 MiB (Nail, Cyber-Tiel)
ε                 : ≤ 5 MiB observed bound
transfer-log      : {groupIDs, bytes, milliseconds} per executed transfer
inventories       : switch geometry (48/40 layers) + dense geometry
state sequences   : T1–T4 workload traces as drivers
oracle            : E0 frontier identity (INV-2)
boundaries        : naive (zero retention) and all-resident (full
                    retention) as reload-accounting anchors
```

## 4. Requirement traceability matrix (R1.1–R4.3 → verification items)

```text
R1.1 planner purity/determinism   V-P1
R1.2 no future information        V-P2 (input-type surface test + review
                                       gate: required set is the only
                                       future-bearing input, supplied per
                                       admitted request)
R1.3 overflow report-only         V-P3
R1.4 hints default-off/provenance V-P4 (controller passes none; type
                                       carries provenance field)
R1.5 planner never touches model  V-P5
R2.1 single owner/writer          V-C1 (architecture + V-S1 serialization)
R2.2 admission before transfers   V-S2
R2.3 transfer-log format          V-C3
R3.1 budget host-supplied         V-B1 (no internal default budget)
R3.2 budget recorded per plan/log V-B2
R3.3 envelope accounting          V-B3 (reserve + KV estimate input,
                                       flagged: needs runtime data)
R3.4 bookkeeping single source    INV-1
R3.5 C_model + ε reconciliation   V-R1 (+ L1 unit test with fixtures)
R3.6 DIRTY/refuse/recovery        V-R2 (F2/F5)
R3.7 materializer-only execution  V-S2/V-P5
R3.8 per-group atomicity          V-F1
R3.9 log-before-return            V-C3
R3.10 eviction timing recorded    V-B2
R3.11 required overflow fail-fast V-O1 (zero transfers before failure)
R3.12 load failure semantics      V-F1
R3.13 evict failure → UNKNOWN     V-F2
R3.14 optional overflow non-error V-O2
R3.15–R3.17 cancellation          V-X1–V-X3 (F3/F4)
R3.18–R3.20 concurrency           V-N1–V-N3 (F8)
R3.21–R3.24 memory pressure       V-M1–V-M4 (F7)
R4.1 long context budget mechanic V-L1 (budget shrink → plan/reload
                                       consequence; no prediction channel)
R4.2 KV accounting input          V-L2 (requires runtime KV estimate)
R4.3 planner never sees future    V-P2
Coverage: 35/35 requirements mapped; acceptance points 1–14 covered via
the contract's own mapping table.
```

## 5. Implementation ordering (for the next gate)

Tests-first ordering is mandatory: L1 and the L2 state-machine harness land
with (before) the controller implementation; L3 fault injection extends the
mock; L4 integrates the real materializer. A requirement is "done" only
when its verification items pass — the matrix is the definition of done.

New production surface must stay within the contract: materializer uses
only the public MLX API patterns already validated; no new observation
mechanisms; no Router/Expert; no prediction channels (V-P2 is repeated at
code review).

## 6. Status

```text
Contract            FROZEN (efeb49c, v1.0)
Verification design REGISTERED (this document)
Implementation      NOT STARTED — next gate, tests-first per section 5
Research line       CLOSED / FROZEN (unchanged)
```
