# SimiGo-Lab Research Program — Execution State Reuse
Date: 2026-09-30
Status: REGISTERED / EXPERIMENTAL PROGRAM

## 1. Purpose
This program consolidates the independent research questions that emerged from the recent SimiGo and PALACE investigations. The method is deliberately bottom-up:

> engineering fact → anomaly → minimal experiment → boundary → abstraction → contract → re-validation

No new PALACE schema or universal State object is introduced by this program.

## 2. Primary question
> When a Physical Representation disappears, is cold prefill an inherent property of Execution State, or merely the consequence of the current implementation not reading and reusing an already-existing State?

This is now the highest-priority open question.

## 3. Experimental tracks

### ES-R1 — Representation-loss / Execution-State reuse
Question: Can an existing Execution State be recovered and made executable again after its current Physical Representation is deliberately removed, without consuming the complete conversation history and without full cold prefill?

Order:
1. read-only code trace;
2. establish exactly what durable/runtime information survives;
3. minimal implementation or harness only if the existing seam is insufficient;
4. representation-loss experiment;
5. continuation equivalence check;
6. only then consider performance.

Success criterion: a new runtime binding can continue from the same semantic position using durable State information rather than reconstructing from the complete history.

This does NOT yet imply PALACE.

### ES-R2 — Backend takeover
Question: Can a backend other than the current MLX path take over an existing Execution State after the MLX Physical Representation is unavailable?

This is the concrete pressure test for Backend Independence.

Success criterion: Identity, lineage, position and continuation semantics remain Runtime-owned while representation materialization is backend-owned.

### ES-R3 — Semantic absence detectability
Existing PALACE-1 evidence registered RF-1: semantic absence is not self-evidently detectable by the current continuation path.

Next question: Can the runtime distinguish durable semantic state that is sufficient for continuation from plausible but semantically unsupported context without relying on a full history replay?

This is an internal research question. No public reproducibility recipe is to be published.

### ES-R4 — Personal State authority boundary
Question: When information about another subject appears in a user's computation, does the existing system distinguish context access from durable state ownership/authority?

Start with code/evidence audit, not schema design. Use synthetic subjects and non-sensitive fixtures only.

### ES-R5 — Knowledge base vs knowledge-use topology
Question: Does turning documents into a maintained/searchable Wiki actually create additional long-term value, or does the value arise only when the system records how documents are used, related, transformed and revisited over time?

Start with an observational audit of existing logs and artifacts. Do not design a PALACE topology schema before an engineering anomaly requires one.

## 4. Priority and gates
P0: ES-R1.
P1: ES-R2, after ES-R1 reaches a factual boundary.
P2: ES-R3.
P3: ES-R4.
P4: ES-R5.

Each track must end in one of:
- CONFIRMED
- REFUTED
- BOUNDED / PARTIALLY CONFIRMED
- INCONCLUSIVE

No hypothesis is promoted to architecture merely because an experiment is interesting.

## 5. Current frozen boundaries
PALACE-1 E0–E3 evidence and framing remain frozen. The registered nucleus candidate remains workload-scoped and is not a universal schema.

Do not rewrite prior evidence to fit the new program.

## 6. Immediate next action
Run ES-R1 first. The first agent task is read-only: determine whether any already-existing durable/runtime State can reconstruct a continuation without full history after the Physical Representation is removed.

Only after that factual trace is complete should implementation be attempted.
