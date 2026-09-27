# SimiGo 2.0 Runtime Residency Engineering — Requirements & Contract v1.0

Status: RUNTIME_RESIDENCY_ENGINEERING_REQUIREMENTS_v1.0_REGISTERED / IMPLEMENTATION_NOT_STARTED
Date: 2026-09-25
Gate: REQUIREMENTS DEFINITION — NO CODE
Predecessor: SimiGo 2.0 Experimental research line (CLOSED/FROZEN,
`SIMIGO2_EXPERIMENTAL_FINAL_RESEARCH_AUDIT_v1.0.md`, 7d54622)
Key terms: the key words MUST, MUST NOT, SHOULD, MAY are to be interpreted
as RFC-2119 requirement levels.

## 0. Scope and non-goals

This contract defines what the runtime residency controller MUST guarantee.
It is an engineering contract: every requirement is grounded in a measured
or validated fact from the frozen research line, and none introduces a new
theoretical object.

**Explicit non-goals (permanent unless separately authorized):**

```text
- prediction of any kind (the controller never predicts);
- probability / demand-probability quantities;
- Router / Expert / Token×Expert observation or modeling;
- production MLX modifications (materialization stays within the public
  API and the isolation patterns already validated);
- async I/O / I-O–compute overlap;
- computation skipping (measured: execution set = FULL);
- SSD / disk-tier residency or multi-tier placement;
- multi-model residency coordination;
- any Optimal*/Demand/Probability vocabulary or object.
```

## 1. Frozen planner contract

The existing `ExecutionResidencyPlanner` contract is frozen:

```text
inputs : required execution set + current resident set + memory budget
          ( + optional externally supplied ordering hints, see 1.1 )
output : load / keep / evict / overflow (+ resident bytes, fitsBudget)
```

```text
R1.1  The planner MUST remain pure: no I/O, no MLX access, no state.
R1.2  The planner MUST NOT obtain "what will execute in the future" by any
      means. Its required-set input is an explicit declaration by the caller
      for the request being served.
R1.3  The planner MUST report overflow (overflowGroupIDs, fitsBudget=false)
      without deciding what to do about it. Overflow resolution belongs to
      the controller (see D4).
R1.4  Ordering hints: the runtime controller MUST pass no hints by default.
      If hints are ever supplied, they MUST carry a registered provenance
      label and remain descriptive ordering signals; any hint channel that
      encodes probability or future-state information violates this
      contract.
R1.5  Planner ≠ Executor ≠ Materializer ≠ Model Execution. The planner MUST
      NOT touch tensors, memory, or the model object.
```

## 2. Architecture roles and state ownership

```text
HOST           owns the memory envelope decision (the budget, D1).
CONTROLLER     owns resident-set state, plan admission, failure, cancel,
               concurrency, pressure response (D2, D4–D7).
PLANNER        pure function (frozen, section 1).
MATERIALIZER   executes load/release against the model; the only component
               allowed to touch tensors; reports executed transfers.
MODEL/RUNTIME  executes the request once the required set is resident.
```

```text
R2.1  The resident set MUST have exactly one owner: the CONTROLLER. All
      mutations of residency state MUST serialize through it.
R2.2  The planner MUST be called only by the CONTROLLER, only with state it
      owns, and its output MUST be either fully admitted or fully rejected
      by the controller before any transfer starts.
R2.3  The MATERIALIZER MUST report every executed transfer (groupIDs,
      bytes, milliseconds) in the transfer-log format already validated by
      the research line (Gate 5 / observability audit).
```

## 3. The seven boundary domains

### D1 — Budget

```text
R3.1  The budget MUST be supplied by the HOST as an explicit input; the
      controller and planner MUST NOT invent one. Admitted forms: fixed
      bytes, fraction of model recommended bytes, or a host-computed
      dynamic envelope (both first forms exist in ResidencyBudgetPolicy).
R3.2  The active budget value MUST be recorded with every plan and every
      transfer log entry.
R3.3  The envelope from which the residency budget is derived MUST account
      for non-residency consumers: KV cache, activations, MLX scratch, and
      a runtime overhead reserve (see C6).
```

### D2 — Resident state (single source of truth)

```text
R3.4  The controller's bookkeeping MUST be the operational source of truth
      for the resident set. There MUST NOT be a second writer.
R3.5  Grounded in the observability audit (375 validated rows): bookkeeping
      MUST be reconciled against the independent MLX aggregate byte
      observation on every transition, using
          predictedIdleBytes = residentBytes + C_model
      where C_model is the registered per-model-class constant (0 for
      Qwen3-Coder/Gemma4/Muse; −851.1/−851.5 MiB for Nail/Cyber-Tiel) and
      ε is a per-model tolerance (≤ 5 MiB observed).
R3.6  If reconciliation fails beyond ε, the controller MUST mark the
      resident state DIRTY and refuse further plans until a recovery pass
      (re-snapshot or full re-materialize) restores consistency. Per-group
      runtime truth beyond executed transfers MUST NOT be claimed (the
      observability audit showed non-perturbing per-group probes are
      unavailable).
```

### D3 — Load / evict executor

```text
R3.7  The planner output MUST be executed only by the MATERIALIZER.
R3.8  Load = materialize missing groups into the model; evict = replace a
      group's parameters with placeholders (the validated release
      mechanism). The MATERIALIZER MUST implement load/evict as
      all-or-nothing per group.
R3.9  Every transfer MUST be appended to the transfer log before control
      returns, in the validated format. The log is the audit trail.
R3.10 Retention (evict) application timing MAY be eager (immediately after
      a request) or lazy (deferred until memory is needed). The choice MUST
      be recorded per transition; total economics are unchanged by timing
      (E0 frontier), only the idle profile moves.
```

### D4 — Failure and overflow

```text
R3.11 Required-set overflow: grounded in the measured fact that execution
      needs ALL decoder-layer groups (G1.9-C), a required set that does not
      fit the budget means the request CANNOT be served at that budget.
      The controller MUST fail the request fast with an explicit overflow
      report; silently exceeding the budget is FORBIDDEN. A budget
      violation path MAY exist only as a separately authorized, explicitly
      logged host decision.
R3.12 Load failure: the request MUST fail (after host-defined retries);
      groups already materialized in the failed attempt remain resident and
      the bookkeeping MUST reflect them (transfers are committed
      per-group).
R3.13 Evict failure: the affected group's residency MUST be treated as
      UNKNOWN; the controller MUST mark state DIRTY (R3.6 semantics) and
      MUST NOT plan against an assumed-released group.
R3.14 Overflow of optional (hinted) groups is a normal, non-error planner
      outcome: they are simply not retained. Only required-set overflow is
      an error (R3.11).
```

### D5 — Cancellation

```text
R3.15 Cancellation MUST leave the invariant "bookkeeping = executed
      transfers" intact: a group is either fully materialized (counted) or
      not counted. In-flight per-group transfers run to the group boundary;
      remaining groups of the plan are dropped.
R3.16 After cancellation the controller MUST recompute the resident set
      from the transfer log (it is the audit trail) and continue serving
      the next request; no rollback of already-executed materialization is
      required, because resident groups are always safe to keep.
R3.17 Eviction in progress at cancellation time MUST complete or be marked
      DIRTY (evictions are not safely interruptible at the parameter-update
      level); they are never resumed half-applied.
```

### D6 — Concurrency

```text
R3.18 All residency state mutations MUST serialize through the single
      controller (actor/serial queue). There is no lock-free residency
      path.
R3.19 Concurrent requests MUST be planned against the serialized state in
      admission order. Sharing one plan across requests is FORBIDDEN unless
      an explicit request-sharing contract is defined.
R3.20 Model execution concurrency (whether generations serialize on one
      model instance or use per-request instances) is a HOST concern; the
      contract only requires that the controller see a serialized
      mutation stream and that required sets of concurrently admitted
      requests be jointly resident for their whole execution window.
```

### D7 — Memory pressure

```text
R3.21 The runtime MUST allow proactive residency shrinkage on external
      memory pressure; this is the eviction machinery's purpose, not an
      emergency hack.
R3.22 Pressure response MUST be an explicit controller policy: a target
      byte level, a victim order over non-required groups (registered
      order, e.g. largest-first or least-recently-retained — descriptive,
      not predictive), and MUST NOT evict any group required by an
      in-flight request.
R3.23 Every pressure-triggered eviction MUST be a logged transfer like any
      other, so the economics remain exactly accountable.
R3.24 After pressure subsides, the controller MUST NOT speculatively
      re-materialize anything (no preload without a request requiring it).
```

## 4. Run conditions

### C5 — Long context

```text
R4.1  Context growth consumes envelope memory (KV cache + activations) and
      therefore SHRINKS the residency budget available to the controller
      (R3.3). The consequence chain
          context growth → budget pressure → residency shrink →
          eviction → later reload
      is a budget mechanic. It MUST NOT be interpreted or implemented as
      demand prediction.
R4.2  Because the research harness had no KV cache, KV accounting is a NEW
      implementation requirement: the controller MUST obtain KV/activation
      estimates from the runtime before serving, and the byte
      reconciliation (R3.5) MUST include them in the predicted envelope.
```

### C6 — Planner never sees the future

```text
R4.3  Repeated for emphasis as a standalone invariant: at no point, under
      pressure, concurrency, or long context, does the planner receive
      information about a future request or future execution content.
      Future-directed behavior is only ever the host's explicit required
      set for an admitted request.
```

## 5. Acceptance mapping (the 14 contract points)

```text
 1 inputs                 → R1 frozen contract, R3.1
 2 state                  → R3.4 (bookkeeping), R3.5 (reconciliation)
 3 state owner            → R2.1 controller, single writer
 4 plan generator         → R1 pure planner, frozen
 5 plan executor          → R2.3/R3.7 materializer only
 6 load success/failure   → R3.8 per-group atomicity, R3.12, R3.9 log
 7 evict success/failure  → R3.8, R3.13 UNKNOWN/DIRTY semantics
 8 overflow               → R3.11 fail-fast on required; R3.14 non-error
                            for optionals; planner never decides (R1.3)
 9 cancellation           → R3.15–R3.17 (transfer-log recomputation)
10 concurrent requests    → R3.18–R3.20 (single writer, admission order)
11 memory pressure        → R3.21–R3.24 (proactive shrink, logged)
12 long context           → R4.1–R4.2 (budget mechanic, not prediction)
13 controller/planner     → R1.5, R2.2 (pure planner, controller-owned
   boundary                  admission, materializer separation)
14 explicit non-goals     → section 0 (permanent unless authorized)
```

## 6. Implementation decision points (engineering choices, no research gate)

These MAY be decided during implementation with recorded defaults; they do
not require reopening any research gate:

- eager vs lazy eviction timing (R3.10) — default: eager, matching the
  measured harness;
- pressure victim order (R3.22) — default: largest-byte-first among
  non-required groups;
- retry counts and backoff for transient load failures (R3.12);
- reconciliation frequency (R3.5) — default: every transition plus on
  pressure events;
- envelope reserve sizing (R3.3/C5) — default: measured C_model + 5%
  headroom until KV data exists.

## 7. Verification path (after implementation)

The contract is verifiable without new research: unit-level planner purity
and admission/serialization tests; transfer-log replay against the
bookkeeping; byte-reconciliation integration tests using the registered
C_model constants and ε; overflow/cancel/pressure scenario tests. The
research line's artifacts (transfer-log format, C_model constants, ε) are
the fixtures.

## 8. Status

```text
Research line            CLOSED / FROZEN (unchanged)
Engineering route        OPEN — requirements v1.0 registered
Implementation           NOT STARTED
Current gate             REQUIREMENTS DEFINITION → COMPLETE (this document)
Next gate                contract verification design → implementation
```
