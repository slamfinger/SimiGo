# SimiGo 2.0 Experimental — ds4 Runtime Design Adaptation Audit Conclusion

Date: 2026-09-24
Status: AUDITED / ENGINEERING ROUTE CONFIRMED
A2.0 status: FROZEN / UNAFFECTED

## 1. Audit conclusion

The current ds4-inspired adaptation is directionally correct and should be retained as the engineering mainline.

The reusable contribution from ds4 is not “expert loading” or “SSD streaming” itself. The material abstraction is the separation of:

    parameter universe
        ↓
    required execution set
        ↓
    resident set
        ↓
    materialization
        ↓
    execution

This separation is sufficiently concrete to guide implementation while remaining below the threshold of a new universal architecture claim.

## 2. Current architectural status

The following is accepted as the current engineering decomposition:

    Workload / Context
            ↓
    Actual / observed execution
            ↓
    Required Execution Set
            ↓
    ExecutionResidencyPlanner
        ┌───┴──────────────┐
        │                  │
    Core / mandatory   Working-set cache
        │                  │
        └────────┬─────────┘
                 ↓
          Load / Keep / Evict
                 ↓
          Materialization
                 ↓
               MLX
                 ↓
             Execution
                 ↓
            Observation

This is an engineering candidate, not a final SimiGo 2.0 architecture declaration.

## 3. Audit findings

### 3.1 Planner layer

ExecutionResidencyPlanner is correctly isolated as a pure planning layer.

It may consume:
- mandatory/core groups;
- required execution groups;
- budget;
- externally supplied demand priority.

It must not, at this stage:
- infer model-internal demand;
- predict future demand;
- perform I/O;
- modify MLX;
- claim that its heuristic is optimal.

### 3.2 Required set versus resident set

This distinction is the key structural improvement over the earlier state-driven residency model.

A group being resident does not prove that it is required for the current execution step.

A group being required does not prove that it is currently resident.

Therefore:

    required ≠ resident

This distinction must be preserved when integrating the planner into the runtime.

### 3.3 Legacy/new-system relationship

The existing LayerResidencyEngine and the new ExecutionResidencyPlanner are currently parallel abstractions.

The next engineering task is not to delete the legacy baseline, but to demonstrate that the planner can express the existing deterministic behavior on the same workload/model.

Target:

    legacy deterministic behavior
             ≡
    planner-produced behavior

for the same declared execution requirements and budget.

Only after this equivalence is demonstrated should the planner become the runtime decision path.

### 3.4 Runtime semantic boundary

The current complete-generation experiment still requires all decoder-layer groups for actual Transformer computation.

Therefore planner integration must not be interpreted as layer skipping.

At the current stage the safe interpretation is:

    planner controls residency
    not computation

The required execution set must be defined consistently with this fact.

### 3.5 Overflow

If mandatory/core plus required groups exceed the configured budget, the planner currently reports overflow.

This is intentionally not resolved into a universal policy.

Possible later policies include:
- fail-fast;
- explicit budget breach;
- staged materialization/streaming.

No choice is registered until real workload evidence shows which behavior is necessary.

### 3.6 Working set

The immediate research object should remain the bounded working set.

There is no current evidence requiring a jump to:
- Router;
- Expert;
- Token × Expert;
- predictive probability models.

The ds4 reference demonstrates that execution-centric residency can be useful without making deeper model-internal structure the first research target.

### 3.7 Core residency

CORE_NON_SWITCH remains an implementation grouping.

It is not yet a scientifically established universal “Core Resident Set”.

This distinction must remain explicit in future documents and measurements.

## 4. Research-depth governance decision

This adaptation is classified as a horizontal engineering refinement.

It does not justify vertical research-depth escalation.

The existing Minimum Sufficient Resolution Principle remains active:

    phenomenon
        ↓
    measurement
        ↓
    repeatability
        ↓
    current resolution sufficient?
        ├─ yes → record / stop
        └─ no  → increase one resolution

Research depth follows evidence, not curiosity.

In particular, ds4's existence alone is not evidence that SimiGo must research Router/Expert/Token×Expert behavior.

## 5. Immediate execution plan

### Phase 0 — Pure semantics

Run:

    swift test

Required result:
- planner tests pass;
- existing tests remain passing.

### Phase 1 — Legacy equivalence

For identical model groups, execution requirements, and budget:

1. generate the legacy deterministic residency result;
2. generate the planner result;
3. compare resident/load/keep/evict sets;
4. record any divergence;
5. do not optimize the planner merely to remove unexplained divergence.

This phase establishes semantic compatibility before runtime substitution.

### Phase 2 — Simulator integration

Integrate the planner into the existing simulator without changing model computation semantics.

Measure at minimum:
- resident bytes;
- load bytes;
- evicted bytes;
- transition count;
- overflow;
- cache hit/miss where definable.

The simulator remains the controlled environment for policy comparison.

### Phase 3 — Real MLX runtime

Only after Phase 1/2 pass:

- run the real MLX residency benchmark;
- compare legacy and planner paths;
- record reload bytes;
- reload time;
- idle resident memory;
- generation time;
- output identity.

No general performance-improvement claim is allowed from a single workload.

### Phase 4 — Real workload traces

Use the actual SimiGo-oriented workload classes:

- document;
- computer operation;
- agentic multi-turn;
- long-context/tool-call traces.

Measure whether stable temporal locality exists in the observed required execution sets.

### Phase 5 — Conditional escalation

Only if measurements show a stable, actionable locality pattern:

    execution history
        ↓
    demand / locality
        ↓
    residency decision

Then predictor/preload research may be considered.

Only if materialization cost is shown to dominate:

    materialization
        ↕
    computation

may asynchronous I/O-compute overlap be investigated, taking ds4 as an engineering reference.

Only if group-level resolution is demonstrably insufficient may the next observation resolution be introduced.

## 6. Explicit non-goals

The following are not authorized by this audit:

- new A2.0 definitions;
- R-INTERNAL expansion;
- restoration of historical δ optimization;
- universal SimiGo architecture declaration;
- Expert-level demand model;
- predictive probability model;
- speculative loading claims;
- async SSD implementation before measurement;
- MLX internal modification;
- ds4 feature-parity claims.

## 7. Current success criterion

The immediate success criterion is narrow:

> Demonstrate that Required Execution Set → Bounded Residency Planner → Load/Keep/Evict can express the existing baseline behavior and operate safely in the real MLX experimental runtime without changing computation semantics.

If this succeeds, SimiGo 2.0 Experimental has moved from a state-driven residency experiment toward an execution-driven residency engineering framework.

If it fails, the failure is itself a useful boundary result; the abstraction should be revised from evidence rather than expanded speculatively.

## 8. Final audit statement

Current route:

    A2.0
      ↓
    frozen theory / adversarial terminal result
      ↓
    Experimental engineering
      ↓
    execution-centric residency
      ↓
    required set / resident set separation
      ↓
    bounded working-set planner
      ↓
    empirical validation

No theory resurrection is required.

No architecture claim is required.

The next decisive evidence must come from execution and measurement.
