# SimiGo 2.0 Experimental — Workload Context & Residency Research Plan v0.1

Status: EXPERIMENTAL / PLANNED
A2.0 status: FROZEN / UNAFFECTED

## 1. Decision

The Layer Demand route is broadened. The research target is not limited to isolated knowledge categories.

Realistic SimiGo workloads are expected to contain substantial document/computer-operation work, long context, multi-turn interaction, and repeated tool calls. Therefore the experiment must distinguish:

- input-dependent demand;
- execution-context-dependent demand;
- temporal locality across consecutive execution steps.

The current question becomes:

> Given workload/input and execution context, is there a stable and repeatable group-demand signal that can be observed early enough to improve parameter residency?

## 2. Resident Core is an engineering hypothesis

The existing CORE_NON_SWITCH group remains a harness grouping only. It is not yet evidence that those parameters constitute the scientifically optimal permanent Core Resident Set.

Future residency analysis should distinguish:

- CORE RESIDENT: high recurrence across workloads and high cost of repeated reload;
- WORKING SET: groups with strong short-term locality for the current task/context;
- COLD GROUPS: groups with low recent demand and candidates for release.

No specific layer/group is declared Core in advance.

## 3. Workload classes

Add three realistic workload classes beside the existing knowledge pilot:

1. DOCUMENT — read, extract, summarize, compare, rewrite, generate.
2. COMPUTER_OPERATION — files, spreadsheets, editors, terminals, repositories, controlled transformations.
3. AGENTIC_MULTI_TURN — repeated model/tool/model transitions with accumulating context.

These are experimental workload labels, not claims about model-internal semantics.

## 4. Temporal locality

For agentic traces record demand over execution steps:

```text
D_i(t)
```

Test whether recent steps contain information about near-future demand:

```text
D_i(t) -> D_i(t+1)
```

Initial target is descriptive locality, not prediction.

Measure:

- adjacent-step reuse;
- reuse across tool-call/tool-result transitions;
- repeated document operations;
- release/reload frequency;
- time from release to next reuse;
- reload bytes and reload time.

## 5. Experimental tracks

### Track A — Input-dependent demand

Keep the existing CODE/MATH/GEOGRAPHY/ASTRONOMY/LITERATURE/ENGINEERING/GENERAL pilot. Do not discard it; it establishes the controlled input baseline.

### Track B — Workload/context demand

Use controlled replayable DOCUMENT and COMPUTER_OPERATION traces first, then AGENTIC_MULTI_TURN traces.

Track B must preserve trace_id, step_id, turn_index, phase, tool type/name, context token count, operation type, previous step, and execution order.

## 6. Revised research sequence

```text
G0 theory boundary
  ↓
G1 harness validity
  ↓
G2 baseline repeatability
  ↓
G3 representation observability / separate instrumentation probe
  ↓
G4 intervention validity
  ↓
+-----------------------------+
| Track A: input demand       |
| Track B: workload/context   |
+-----------------------------+
  ↓
stable demand / temporal locality?
  ↓
pre-execution predictability
  ↓
predictive residency intervention
  ↓
runtime trade-off
  ↓
architecture decision only if evidence warrants it
```

## 7. Core research principle

Do not start by designing a 'layered loading architecture'. First establish whether useful demand locality exists.

The intended evidence chain is:

```text
phenomenon
→ stable measurement
→ temporal locality / predictability
→ useful residency intervention
→ reproducible runtime effect
→ only then architecture abstraction
```

A negative result at any stage is a valid research result.

## 8. Immediate next work

1. Keep the existing G1 schema and representation audit unchanged.
2. Finish the separate local representation instrumentation feasibility work.
3. Finish/validate the one-group ablation and restoration harness.
4. Run the existing controlled input pilot only after baseline validity.
5. In parallel, design a small deterministic DOCUMENT / COMPUTER_OPERATION trace corpus.
6. Add AGENTIC_MULTI_TURN only after deterministic single-operation traces are reproducible.
7. Do not implement predictive loading yet.

## 9. Boundary

This plan does not modify frozen A2.0 theory, does not introduce a new formal architecture, and does not assume future-state probabilities.

The existing residency benchmark remains the downstream engineering testbed.