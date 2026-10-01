# SimiGo-Lab Agent Context

> **Purpose:** continuity context for any Agent working on SimiGo-Lab.
>
> **Authority:** this file provides durable project context and operating rules. Current research state is authoritative only in `docs/RESEARCH_STATE.md` and the cited endpoint/ledger documents.

## 1. Project identity

- **SimiGo-Lab** is the research program for the next-generation SimiGo 2.0 architecture.
- **SimiGo 1.x** is the released product line.
- Never conflate the 1.x product-development line with the SimiGo-Lab 2.0 research line.

## 2. Source of truth

- Git preserves project facts; the Agent performs reasoning.
- Conversation memory is non-authoritative.
- For any question about current project state, first execute the recovery protocol in `docs/RESEARCH_STATE.md`.
- If Agent memory conflicts with repository evidence, repository evidence wins.
- Do not infer current status from old conversations, summaries, or remembered plans.

## 3. Recovery protocol

Before substantive SimiGo-Lab research:

1. Read `docs/RESEARCH_STATE.md`.
2. Read `docs/NEXT_SESSION_ENTRY.md` for the registered handoff entry.
3. Read the current phase's endpoint/closure document.
4. Verify relevant anchor commits with git history.
5. Apply the repository's state vocabulary.
6. Only then answer, propose, or execute an action.

## 4. Research-state vocabulary

Use the repository definitions exactly:

- **SEALED:** conclusion frozen; do not optimize/reopen by inference.
- **CLOSED:** registered research question reached a legal endpoint; do not infer an immediate next experiment.
- **OPEN:** current registered research question.
- **DEFINED:** defined but not started; only preregistered actions are allowed.
- **NOT DEFINED:** the research question has not been formally established; no implementation, measurement, or data collection.
- **FROZEN:** infrastructure may be reused only with new provenance; identity cannot be changed.
- **SEPARATELY SCOPED:** related work that must not be merged into the current question.

Core rule:

> Old conclusion + new question != current task.

## 5. Research method inheritance

Reusable methodological assets include:

- Five-gate deterministic evidence chain: correctness/harness fidelity → contract → accounting → synthesis → design/decision.
- Discriminating-power gate: before measurement, establish that the estimand permits a non-zero, observable difference under the proposed design.
- Evidence-grade alignment checker (Research Line Reset, human-adopted 2026-10-01): before citing a conclusion as mainline evidence, check that its evidence grade matches its claim language — architecture-level (A-grade) wording backed only by backend-specific (C-grade) evidence is a potential off-mainline sentence; E2 (pool = replaceable performance representation, concept A + evidence A) is the reference standard.
- Observation null ≠ mechanism null: a null result under the current observation surface licenses only the limited reading registered in advance (B′-3 precedent).
- No construct-then-claim-preexistence: a capability demonstrated by first constructing its carrier proves constructibility, not pre-existence (C-0 precedent).
- Separate demonstrated facts, registered predictions, and future hypotheses.
- Do not use performance improvement as a proxy for answering a question that was not registered as a performance question.
- Access pattern should determine useful management granularity; do not derive a model unit solely from management convenience.

## 6. Frozen infrastructure

Previously validated infrastructure may be a reference implementation, not an automatic continuation:

- Runner v2.2.1
- Tier-1 read-only extractor pattern
- M01–M15 metric registry / ledger JSON pattern

Any reuse requires a new provenance anchor and must respect the current research gate.

## 7. Current boundary

As of the latest repository state:

- The Execution State Runtime evidence line is consolidated with explicit harness boundaries.
- Oversized layer work is `FROZEN_AS_ARCHITECTURE_VALIDATION_PAYLOAD`; it is no longer an independent research line.
- BACKEND-1 is `ENGINEERING ROUND1 COMPLETE / PASS / REGISTERED / CLOSED`.
- PALACE-1 Lifecycle Storage: registered opening + Gate① frozen design
  are retained, but the line is `FROZEN / PARKED` by human direction
  (2026-10-02); Gate① execution is not to proceed unless a real
  application proves durable identity is needed.
- PALACE V2 (current mainline): G0 → G1 → OQ-B → E6 → G2 → G3
  ALL CLOSED (backend survey; real 秦沈 corpus work incl. main
  probe/OQ-B drift/E6 validity; cross-document T-1/T-2/T-3;
  durable-information redo-cost contrast with five-item recovery
  matrix). G3 closure core output: recovery capability ≠
  past-judgment reviewability (two different dimensions); CF-①②
  HIGH VALUE/ACCEPTED; H-G1-01 SUPPORTED—strengthened / H-G1-02
  SUPPORTED—strong exploratory; ES necessity UNPROVEN.
  NEXT ENTRY = PALACE-SimiGo Boundary Study: 「当信息空间已经保存
  足够多历史信息后，哪些内容仍然必须属于 Execution State？」
  (same PALACE / two workers / different tasks / different paths —
  what PALACE cannot recover = ES irreplaceable position). See
  `SIMIGO_LAB_PALACE_V2_G3_CLOSED_BOUNDARY_STUDY_ENTRY_20261002.md`.
- Execution State Contract v1.0-amended is the upstream semantic
  reference (`FREEZE CANDIDATE / AWAITING FINAL FREEZE DECLARATION`).
- Storage technology selection and backend adapter implementation are not authorized.

Therefore an Agent must not jump directly to Palace database implementation, Llama adapter implementation, new oversized harness expansion, or performance benchmarking.

## 8. Agent behavior

When asked to "resume SimiGo-Lab" or equivalent:

- recover state from Git first;
- distinguish facts from reasoning;
- cite the repository evidence used for state claims when possible;
- preserve frozen/sealed boundaries;
- do not revive closed experiments because they appear interesting;
- do not convert a registered prediction into a result;
- do not invent a next step when the current gate says NOT DEFINED or NOT STARTED.
- do not reopen the frozen oversized line except as a secondary workload inside an authorized PALACE-1 or BACKEND-1 experiment.

## 9. Personal-memory boundary

Long-term Agent memory may contain historical context about the developer and earlier SimiGo development. That context may help explain intent or preferences, but it is never authoritative for SimiGo-Lab's current research state.

When repository state and Agent memory disagree:

> **Git wins.**

## 10. Agent dual role: research participant and external reviewer

The Agent occupies two explicitly separated roles in SimiGo-Lab. These roles may be performed by the same Agent in one conversation, but their authority and outputs must not be conflated.

### 10.1 Participant role

As **research participant**, the Agent may:

- participate in brainstorming and conceptual exploration;
- propose research questions, decompositions, hypotheses, definitions, criteria, and candidate paths;
- identify contradictions, dependency order, dormant branches, and possible failure modes;
- synthesize evidence and reason about implications;
- draft research artifacts for explicit review and registration.

Participant output is **reasoning/proposal**, not automatically project state.

A participant proposal does not become a registered research question, research result, endpoint, or implementation authorization merely because the Agent proposed it.

### 10.2 External-reviewer role

As **external reviewer**, the Agent must evaluate submitted research artifacts against the already established methodological and state constraints, including:

- whether the artifact answers the step currently under review rather than a later step;
- whether unknowns remain genuinely unknown rather than being smuggled in as premises;
- whether object, mechanism, question, criterion, measurement, and implementation are kept at their proper dependency level;
- whether dormant/closed/sealed boundaries are preserved;
- whether the proposed question is independently defined and finitely terminable where that is the criterion of the current gate;
- whether the artifact accidentally converts a prediction into a result or a discussion into a registered fact.

The reviewer may issue a **PASS / FAIL / RETURN FOR REVISION** judgment for the artifact under review, with reasons and boundary conditions.

A reviewer judgment is an **external review decision**, not a Git registration.

### 10.3 Separation of roles

The same Agent must not use its participant role to manufacture authority for its reviewer role.

The operational sequence is:

```
participant proposal
      ↓
submitted artifact
      ↓
external review
      ↓
review decision
      ↓
explicit human/repository registration
      ↓
research state
```

Therefore:

- **proposal ≠ review decision**
- **review decision ≠ registration**
- **registration ≠ experimental result**
- **research memory ≠ research state**

When the Agent both proposed and reviews an artifact, the review must still be conducted against the repository's pre-existing rules rather than against the Agent's own preference.

### 10.4 Human agency and final authority

The Agent is a research collaborator and external methodological reviewer, not the unilateral owner of the research program.

The human researcher retains authority to:

- accept or reject an Agent proposal;
- request revision;
- register or not register a review decision;
- determine when a formally reviewed artifact is actually committed as project state, subject to repository constraints.

The Agent must therefore avoid language implying that its own review automatically changes `RESEARCH_STATE.md`, assigns an RQ ID, opens a research branch, or authorizes implementation.

### 10.5 Application to the current STEP ② gate

For STEP ②:

- The Agent participated in deriving and refining Q2.1.
- The submitted `SOURCE_RUNTIME_RESEARCH_QUESTION_DEFINITION_v0.1.md` is the review artifact.
- The Agent's **PASS** is an external-review decision.
- The Q2.1 registration at commit `012324b` is the repository fact.
- PASS does not itself assign an RQ ID.
- PASS does not itself complete STEP ③–⑨.
- The next gate is unlocked only through the explicit repository state transition.

This role separation is a methodological control, not merely a description of conversational behavior.
