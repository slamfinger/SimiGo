# STEP ④ Preparation Boundary Audit — 2026-09-22

**Repository:** `slamfinger/SimiGo-Lab`  
**Branch:** `refactor/research-archive-20260922`

## 1. Purpose

Perform a read-only methodological audit immediately before the next permitted
research action: STEP ④ estimand definition.

This audit checks whether the repository currently distinguishes:

- registered STEP ③ status from source-document draft labels;
- Q2.1 object/question definition from a completed RQ definition;
- estimand from existence/insufficiency criteria;
- research proposal from repository authorization;
- historical candidate material from current state.

No estimand is defined by this audit.

## 2. Authority

Current state was read from:

`docs/RESEARCH_STATE.md`

It states:

- Phase: Definition / Opening;
- STEP ③: PASS and registered;
- STEP ④ estimand: NOT STARTED;
- RQ ID: not assigned;
- implementation, harness construction, data collection and performance
  measurement: forbidden;
- STEP ④ external review must precede STEP ⑤+.

Therefore this audit does not treat any lower-layer draft snapshot as authority
over the state file.

## 3. Boundary audit

### B-01 — STEP ③ registration vs source header

The independence-argument source still labels itself:

`STEP ③ DRAFT / EXTERNAL REVIEW PASS — 待登记`

while `RESEARCH_STATE.md` records STEP ③ as externally reviewed **and
registered**.

**Disposition:** historical source-header drift identified.

This does not change the source document's substantive argument. The current
registered state is controlled by `RESEARCH_STATE.md`.

### B-02 — STEP ①/② source snapshots

The STEP ① and STEP ② source documents contain their own gate snapshots and
draft/review labels. These are versioned source-artifact metadata and must not
override the current state authority.

**Disposition:** retain as provenance; do not rewrite historical source
artifacts merely to make their embedded snapshots look like a live state file.

### B-03 — Q2.1 is not an RQ ID

Confirmed.

Q2.1 selected C1 as the minimal object and supplied a candidate formal question,
but the repository explicitly keeps RQ-F-01 as NOT DEFINED and RQ ID unassigned.

No promotion is warranted at this audit stage.

### B-04 — STEP ④ has no hidden definition

Confirmed.

The current materials mention estimand only as a future step. No audited
document supplies a registered estimand, an existence criterion, an
insufficiency criterion, or a measurement authorization.

This is the correct state for the current gate.

### B-05 — No implementation-first leakage

Confirmed for the audited materials.

The current gate explicitly forbids runtime implementation, harness
construction, data collection and performance measurement. The STEP ①–③
documents also explicitly defer Path/Harness/Experiment.

### B-06 — No result leakage from memory/prediction

Confirmed.

Registered predictions remain identified as predictions, and research-memory
items remain candidate/hypothesis material. Neither provides an estimand or
measurement result.

## 4. STEP ④ entry contract

Before STEP ④ is started, the following must remain unresolved rather than
silently assumed:

1. the exact estimand;
2. its target quantity and unit of analysis;
3. the population / object domain to which the estimand refers;
4. the observation boundary required to identify it;
5. what is intentionally outside the estimand;
6. how the estimand remains compatible with the bidirectional C1 question.

The audit does **not** choose these items.

## 5. Forbidden shortcuts

STEP ④ must not be replaced by:

- selecting a Model Unit family in advance;
- choosing a runtime API because it is convenient;
- defining “existence” by whatever a harness happens to expose;
- using performance improvement as the estimand unless that is independently
  justified by the research question;
- converting the registered nodes-out prediction into an outcome variable;
- importing Track B thresholds as current runtime criteria;
- assigning RQ-F-01 before the full definition chain is complete.

## 6. Review conclusion

**Boundary status: READY FOR STEP ④ DEFINITION, BUT STEP ④ HAS NOT STARTED.**

The repository has enough separation between current state, historical source
artifacts, findings, decisions, and memory to begin the next *definition*
action without entering measurement or implementation.

This record itself:

- does not define an estimand;
- does not assign an RQ ID;
- does not alter `RESEARCH_STATE.md`;
- does not authorize STEP ⑤;
- does not authorize implementation or measurement.
