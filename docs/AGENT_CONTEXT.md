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
2. Read the current phase's endpoint/closure document.
3. Verify relevant anchor commits with git history.
4. Apply the repository's state vocabulary.
5. Only then answer, propose, or execute an action.

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

- Track E / nodes-out is CLOSED.
- H-P1 is CLOSED / SEALED.
- P3-C is CLOSED / SEALED.
- Track F / RQ-F-01 is NOT DEFINED.
- P4 / RQ-P4-01 is NOT STARTED.
- The current gate is a new research-question definition gate, not runtime implementation.

Therefore an Agent must not jump directly to runtime harness construction, implementation, or data collection.

## 8. Agent behavior

When asked to "resume SimiGo-Lab" or equivalent:

- recover state from Git first;
- distinguish facts from reasoning;
- cite the repository evidence used for state claims when possible;
- preserve frozen/sealed boundaries;
- do not revive closed experiments because they appear interesting;
- do not convert a registered prediction into a result;
- do not invent a next step when the current gate says NOT DEFINED or NOT STARTED.

## 9. Personal-memory boundary

Long-term Agent memory may contain historical context about the developer and earlier SimiGo development. That context may help explain intent or preferences, but it is never authoritative for SimiGo-Lab's current research state.

When repository state and Agent memory disagree:

> **Git wins.**
