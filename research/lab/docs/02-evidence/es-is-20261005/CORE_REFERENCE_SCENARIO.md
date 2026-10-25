# ES↔IS Core Reference Scenario v0.1

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `CORE REFERENCE SCENARIO · GOVERNED BY SIMIGO RESEARCH CONSTITUTION v1.0 · NO EXPERIMENT · NO PALACE · PENDING HUMAN REVIEW`
Directive: Human ruling 2026-10-05 (Constitution Article 8.1) — the five open questions of spec v0.1 are **set aside** until this scenario exists; every v0.1 concept must answer *"which problem in this scenario do I solve?"*; concepts without a position are set aside.

---

## 0. Session header (Constitution Article 6 — mandatory)

```text
Core target:               Execution State ↔ Information Space coupling
Affected closure edge:     all five (this scenario is the map; each concept must claim an edge)
Real system object:        to be identified per concept via the mapping below — forcing this
                           identification is the scenario's entire purpose
Expected capability delta: Task T2 resolves R1 and continues incrementally without recomputing
                           Task T1's work
Stop condition:            any concept with no scenario position → set aside; if no edge can be
                           given a runtime-artifact mapping, the line downgrades per Gate 2
```

## 1. The scenario (Human-directed, formalized)

```text
Task T1
  ↓
Execution State S1
  ↓ resolve / retrieve               [edge: I → S]
读取 F1 F2 F3 F4
  ↓
Trajectory T1                        [edge: S → S]
  ↓ execute
Result R1
  ↓ persist / index / relate         [edge: S → I]
Information Space 新增 R1 + provenance + relations
  ↓
Task T2
  ↓ resolve R1                       [edge: I → S]
Execution State S2
  ↓ 增量计算                          [edge: S → S]
continue — without recomputing T1
```

The scenario is deliberately minimal and **PALACE-free**: it is an abstract capability loop, not an architecture. Its function is governance — **a concept earns Core attention only by naming the problem inside this loop that it solves.**

## 2. Concept mapping (every v0.1 concept answers: which problem here do I solve?)

| v0.1 concept | Scenario problem it solves | Edge | Position |
|---|---|---|---|
| 2×2 (locality × role) | classifying every information item: F1..F4 at read time, R1 at persist time, IS entries at resolve time — context or constitutive relatum? | I→S, S→I | **HAS** |
| fourth cell (carried-but-unreferenced) | information read into T1's context but unreferenced by S1's relations; the role-axis hypothesis predicts mutating it must not break T2's continuation | I→S, S↔I | **HAS** |
| R-id (identifies) | what makes the S2 reconstructed at "resolve R1" the *continuation of S1* rather than a similar state — the provenance + relations written at persist time are R-id's material | I→S | **HAS** |
| R-an (anchors) | where in the IS/computation S2 sits, fixed via the index | I→S | **HAS** (provisional definition; dedicated definition gate still required before any matrix-level use) |
| R-res (resumes) | S2 continues T2 using R1 without recomputing T1 — **the capability-delta moment of the whole loop** | I→S, S→S | **HAS** (central) |
| R-adm (admissibility-evaluated) | S2's transition requires decision-relevant information present, or it blocks (the F phenomenon at task level) | I→S | **HAS** (transition-level bounding carries) |
| interpretive / necessary partition | which of the written relations must be persisted for T2's resolve to succeed, vs which are decorative — **this is the Gate-1 pass example, instantiated** | S→I, I→S | **HAS** (the scenario's central question) |
| five-outcome taxonomy (O-1..O-5) | what happens to S2 when IS entries it depends on mutate between T1 and T2 (R1 revised; F3 updated) | S↔I, I→I | **HAS** |
| mutation-locality variable | R1 is branch-local to the T1→T2 path; F3 may be shared across tasks — structurally different mutation cases | I→I, S↔I | **HAS** |
| mechanizability requirement | resolve(R1) must mechanically verify lineage (provenance chain) — the O-1..O-4 criteria are what make resolve checkable | I→S | **HAS** |

## 3. The honest set-aside (the governance working as intended)

**The locality axis has no scenario position.** No operation in the loop distinguishes information *inside* vs *outside* the State boundary — resolve reads from IS, persist writes to IS; every load-bearing item in the loop is external by default. Under the rule "concepts without a position are set aside":

> **The locality axis is set aside** — registered, not deepened.

Note what just happened, because it is the constitution's first live demonstration: the locality axis was introduced by this line's own v0.1, and the scenario test set it aside within one session. Its set-aside is *consistent with* the role-axis working hypothesis — but this reinforcement is **governance-level, not evidential**, and must not be cited as support for the hypothesis.

## 4. Gate status of the v0.1 open questions (set aside, not deepened)

| v0.1 open question | Status under the scenario |
|---|---|
| fourth cell / role-axis test | becomes testable **within** the scenario — a v0.2 candidate only after Human adopts the scenario |
| anchor definition gate | unchanged — still required before R-an appears in any matrix-level treatment |
| O-1..O-4 mechanization | the scenario needs it (resolve verification) — design is a Human-gated next step |
| mutation-locality | scenario instance registered (R1 branch-local vs F3 shared); unresolved |
| PALACE timing | unchanged — deferred; the scenario is PALACE-free by design |

## 5. What this document is and is not

**Is**: the reference map for admitting and judging ES↔IS work under Constitution Articles 0–6; the forced-runtime-object question for every concept; the demonstration artifact for the five-line session header.

**Is not**: an experiment design; an architecture (no PALACE); a claim that any mapping is implemented; a sealed document — the scenario itself may be amended by Human ruling, with amendments registered in git.
