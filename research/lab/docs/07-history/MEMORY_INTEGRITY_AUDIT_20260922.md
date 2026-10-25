# Research Memory Integrity Audit (2026-09-22)

## 1. Objective

Audit whether the new archive/control-plane structure preserves the knowledge needed for a different local Agent to resume SimiGo-Lab without the original conversation, while keeping memory separate from authoritative research state.

This is a **targeted integrity audit**, not an exhaustive repository text scan.

## 2. Audit sources

Reviewed as the primary continuity set:

- `docs/RESEARCH_STATE.md`
- `docs/AGENT_CONTEXT.md`
- `docs/RESEARCH_MEMORY.md`
- `docs/00-governance/RESEARCH_PROGRAM_REGISTER_20260922.md`
- `docs/00-governance/RESEARCH_DEPENDENCY_MAP_20260922.md`
- `docs/00-governance/EXPERIMENT_REGISTER_20260922.md`
- `docs/00-governance/ARCHITECTURE_CONSEQUENCE_MAP_20260922.md`
- `docs/00-governance/NEGATIVE_AND_OPEN_QUESTIONS_REGISTER_20260922.md`
- `docs/08-research-memory/AGENT_MEMORY_PROTOCOL_20260922.md`
- Track B findings/decisions/architecture/closure
- Track E H-P1 results and Track E closure record
- the historical asset/provenance audits

## 3. Findings

### 3.1 Current state is recoverable

**PASS.**

The repository separates current state from memory. `RESEARCH_STATE.md` identifies the current Definition/Opening phase, STEP ④ PASS, and the next legal action as STEP ⑤ existence-criterion definition.

### 3.2 Closed knowledge is recoverable

**PASS.**

Track B and Track E closure knowledge is represented through findings, decisions, architecture constraints, endpoint/closure records, and the Negative/Open Register.

### 3.3 Durable intellectual knowledge was previously underrepresented

**GAP FOUND → ADDRESSED.**

The original memory layer primarily preserved candidate architectural ideas. It did not sufficiently preserve the high-value knowledge a new Agent would otherwise have to rediscover from old experiment documents.

RM-011–RM-017 were therefore added to `RESEARCH_MEMORY.md` to capture:

- bounded execution-state lifecycle knowledge;
- representation-transition knowledge;
- non-authoritative adaptive-policy knowledge;
- P3 mechanism decomposition;
- H-P1 three-layer structural-signal separation;
- the Hot Null v2 methodological lesson;
- closed/dead-end routes.

Each item includes provenance, scope, and forbidden inference.

### 3.4 Historical status ambiguity

**GAP FOUND → ADDRESSED.**

The H-P1 opening snapshot contains historical wording equivalent to “PASS / Design Question Lock Pending”, while the later H-P1 result is CLOSED / SEALED.

The opening file must remain unchanged for provenance. A new bridge, `HISTORICAL_STATUS_BRIDGES_20260922.md`, now explicitly routes future Agents from the historical opening snapshot to the later result and Track E closure.

### 3.5 Memory/state separation

**PASS.**

The Agent Memory Protocol establishes:

```
State → constrains Memory
Memory → proposes future questions
Dialogue → creates candidate memory
```

Memory is not permitted to silently mutate state.

### 3.6 Negative knowledge / anti-loop protection

**PASS.**

The Negative/Open Register and Experiment Register provide explicit protection against repeatedly proposing already closed or blocked routes.

### 3.7 Provenance preservation

**PASS.**

Historical assets remain in place. The audit does not promote old results to current evidence and does not modify frozen/sealed artifacts.

## 4. Multi-Agent recovery test

A future Agent working without the original conversation should be able to answer:

| Recovery question | Repository source |
|---|---|
| Where are we? | `RESEARCH_STATE.md` |
| What is the program structure? | Program Register + Dependency Map |
| What has been demonstrated? | Findings + Decisions + Evidence |
| What is closed/frozen/sealed? | Endpoint/Closure + Negative/Open Register |
| What should be remembered? | `RESEARCH_MEMORY.md` |
| What remains unknown? | Negative/Open Register + current gate |
| What can be proposed? | Memory candidates, subject to a new definition/RQ gate |
| What may not be done? | State + closure + negative register + experiment register |

**Result: PASS for the current archive scope.**

## 5. Remaining limitations

This audit does **not** establish:

- that every historically valuable sentence in every conversation has been captured;
- that every possible cross-reference is machine-valid;
- that every old document contains an explicit superseded-by marker;
- that the memory layer can replace reading evidence when a detailed factual claim is required.

The durable rule remains:

> Memory restores intellectual continuity; evidence restores factual detail; authoritative state restores legal research position.

## 6. Current state impact

**No research state transition.**

This audit and its memory additions do not:

- open STEP ⑤;
- define an existence criterion;
- create RQ-F-01;
- reopen Track B or Track E;
- authorize runtime implementation;
- authorize data collection.

The next legal research action remains the STEP ⑤ existence-criterion definition under the current gate.
