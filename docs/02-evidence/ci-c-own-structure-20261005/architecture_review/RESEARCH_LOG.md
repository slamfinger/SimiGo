# Research Log — Execution Admissibility

Date: 2026-10-05
Terminal commit: `5f8bf23` (handoff snapshot; post-review state in Addendum at end of file)
Branch: `codex/execution-state-research-20260929`
Worktree: clean

---

## Complete research chain

| # | Phase | Commit | Status | Key finding |
|---|---|---|---|---|
| 1 | Phase A: Authorization | `ea537cc` | CLOSED | `A_epistemic / A_execution` behaviorally separable and ordered; ORDERED_SEPARATION_SUPPORTED (STRENGTHENED) |
| 2 | Phase B: Information | `1f4fcd7` | FROZEN | F-ABSENT → BLOCKED (replicated, semantically specific); F-STALE → quality; F-IRRELEVANT → non-condition; F-CONFLICTING → unresolved |
| 3 | Eligibility Conceptual Spec v0.1 | `66a600c` | FROZEN | `Eligible(T | C)` transition-relative, condition-evaluated |
| 4 | Joint Eligibility Probe | `747c310` | COMPLETE | X- and F-absent independently produce BLOCKED; shared eligibility constraint = CANDIDATE EVIDENCE |
| 5 | Evidence Synthesis | `6962dd9` | FROZEN | Behavioral convergence established; mechanism unresolved |
| 6 | Evidence-Constrained Refinement | `a19e3ba` | FROZEN | Condition roles empirically grounded; quality ≠ eligibility boundary |
| 7 | 846 × Eligibility Mapping | `cb07a67` | FROZEN | SAME STRUCTURAL ABSTRACTION LEVEL; 846 = State-side determinant candidate |
| 8 | Admissibility Spec v0.1 | `5ef2ffb` | FROZEN | Admissibility as broader construct; three phenomena distinguished |
| 9 | **Admissibility Spec v0.2** | `5f8bf23` | **FROZEN** | **Admissibility = conjunction of necessary conditions; three-state {true, false, unevaluable}** |

---

## Core conceptual framework

```text
              Execution Admissibility
              (candidate general research object)
                        │
          ┌─────────────┴─────────────┐
          │                           │
    Condition-side              State-side /
    Authorization              Function (846)
    Information                internal structure
          │                           │
          └──────── ? ────────────────┘
                   │
                   ▼
          Eligible(T | C)
       (operationalized subset)
                   │
               Transition
```

---

## Key definitions

| Term | Definition |
|---|---|
| `Eligible(T | C)` | Transition-relative, condition-evaluated; observable subset of Admissibility |
| `Admissibility(T | context)` | Broader property; ∈ {true, false, unevaluable} |
| Admissibility condition | Factor whose absence/denial produces BLOCKED (semantically specific, replicated, not generic validation) |
| Quality condition | Factor whose manipulation produces DEGRADED but not BLOCKED |
| Non-condition | Factor with no effect on transition |
| `unevaluable` | Evaluation mechanism structurally absent (846 K3-DELETED); distinct from `false` |

---

## Established behavioral findings

| Finding | Models | Source |
|---|---|---|
| X- → BLOCKED | C, N | Joint Probe J3 |
| F-absent → BLOCKED | C, N | Phase B + Joint Probe J2 |
| F-absent blocking is semantically specific | C, N | Generic-Validation Probe P3 |
| F-STALE → DEGRADED (not BLOCKED) | C, N | Phase B main |
| F-IRRELEVANT → no blocking | C, N | Phase B + probe |
| X- + F-absent → BLOCKED, no extra interaction | C, N | Joint Probe J4 |
| Both X and F are necessary but not sufficient | C, N | Joint Probe pattern |
| E- blocks adoption (upstream of transition) | C, N | Phase A |
| K3-DELETED → C4 absent (unevaluable) | C, N | CI-C |

---

## Open questions

| # | Question | Status |
|---|---|---|
| 1 | Shared eligibility function vs parallel independent gates? | Open; candidate evidence for shared constraint |
| 2 | Does Admissibility have conjunction structure (Model B) or is it a result label (Model A)? | Open; Model B more productive |
| 3 | Is E (epistemic) a separate conjunct or a precondition for evaluating X and F? | Open |
| 4 | Is 846 State-side integrity a conjunct or a precondition for evaluation? | Open; candidate unevaluable source |
| 5 | Layered eligibility (epistemic/execution stages)? | Open; Phase A candidate structure |
| 6 | C emitted=true + BLOCKED anomaly? | Unresolved; recorded, not interpreted |
| 7 | F-CONFLICTING model-dependent divergence? | Unresolved |
| 8 | Are there additional unknown Admissibility conditions? | Unknown |

---

## Hard boundaries

```text
No 846 atom mapping / reinterpretation
No Observer
No InformationCore write
No minimal Information Core claim
No A / B / D retry
No experiment without Human Review
No formalizing "admissibility information" as concept yet
No Eligible(T | S, C) extension without S definition + manipulation + interaction evidence
```

---

## Next session: how to continue

1. Read this file + `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.2.md`
2. The most productive next direction depends on Human Review:
   - Model A vs B discriminating experiment (requires new conceptual groundwork)
   - Multiple Necessary Conditions Probe (extend beyond X and F)
   - Or pause and begin a new research thread
3. Do NOT re-run existing experiments or re-open frozen phases.
4. All claims and their evidence levels are documented in the referenced commits.

---

## Addendum — 2026-10-05: Human direction after log review (Identifiability Analysis v0.1)

Human reviewed this log and Spec v0.2 and directed: settle **Model A/B identifiability before any discriminating experiment** (no code, no experiments).

Delivered: `EXECUTION_ADMISSIBILITY_MODEL_AB_IDENTIFIABILITY.md` (v0.1, committed with this addendum).

Verdict (PROPOSED — pending Human Review seal): **Case 2.** Model A (result label, as stated in v0.2) entails no outcome constraints, so A/B strict identifiability fails **by construction**, not by an evidence gap; A and B are observationally equivalent over the current observable space. Key registrations:

- **ND-1**: any newly established condition (D-absent → BLOCKED) is A/B-neutral evidence — it counts toward Q8 only, never as conjunction-structure evidence, and never as evidence for Model A.
- Model B retained as **productive hypothesis / explanatory model**; its empirical content relocates to its own falsifiable commitments: no-rescue necessity, mixed-state propagation semantics, uniform three-state behavior across conditions (Q8 re-scoped as B-testing, not A/B discrimination).
- Spec gap registered: v0.2 does not define mixed-state propagation (e.g., X `false` + F `unevaluable` → output class undefined). This is the precondition gap for any future mixed-configuration test.

Human priority order registered: Q2 (settled by this note, pending seal) > Q8 (re-scoped) > Q3/Q4. Q6 stays unresolved; Q7 stays uninterpreted; Q5 stays closed.

Next-step candidates (Human Review required; nothing auto-opens): ① Spec v0.3 — complete B's mixed-state propagation semantics (conceptual only); ② re-scoped Multiple Necessary Conditions Probe (design-gated, B-uniformity framing under ND-1); ③ evaluation-signature observable question (new, open — would re-pose identifiability on a wider observable space).

This addendum supersedes the "Next session" section above.

---

## Addendum 2 — 2026-10-05: Human ruling on next steps; Spec v0.3 delivered (Step 1)

Human accepted the Case 2 framing and registered, in order:

**Binding discipline**: no experiment may ever be recorded as "supports Model B". Experiments test **specific commitments** of B; a commitment failure means "current B formulation refuted / needs revision" — never "Model A proven". "D- → BLOCKED" licenses only "D is a candidate necessary condition", never "therefore Admissibility is conjunction".

**Three-step order**:

- **Step 1 (immediate)** — Spec v0.3: complete mixed-state propagation semantics. Concept closure only. → **DELIVERED**: `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.3.md` (committed with this addendum; PENDING HUMAN REVIEW).
- **Step 2 (after Step 1; separate design gate + Human Review)** — Multiple Necessary Conditions Probe, renamed **Model-B Uniformity / Necessary-Condition Probe**: tests whether new conditions exhibit the same necessary-condition structure as X and F. Never an A/B discriminator (ND-1 in force).
- **Step 3 (kept at distance)** — Evaluation-Signature question: whether a new observable dimension (evaluation-side signature separable from transition-side result) can shrink Model A's hypothesis space and re-pose identifiability. NOT started.

v0.3 summary: two-level evaluation vocabulary (Level 0 = mechanism operability, 846-grounded; Level 1 = per-condition determination {true, false, U_c}, U_c = registered posit with source taxonomy deliberately open) + total order-independent propagation rule; **spec decision D-1 = false-dominant over per-condition unevaluable** (alternative D-1′ U-dominant registered; decision marked falsifiable, not derived); new commitments C-PROP-1..4; back-compatibility with all established findings verified (no cell changed); Q3/Q4/Q6/Q7/Q5 untouched; identifiability verdict (Case 2) and ND-1 unaffected; no experiment authorized.

State after this commit: Step 1 delivered pending Human Review; Step 2 / Step 3 NOT started; nothing auto-opens.

---

## Addendum 3 — 2026-10-05: Human Review seal (Case 2 + Spec v0.3)

Human review verdict: **SEALED — no revisions required**, both the identifiability analysis v0.1 (Case 2, sealed at identifiability level) and Spec v0.3. Full review record captured in `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.3.md` §8. Three **binding** review annotations:

1. **Level 0→1 layering confirmed** — the structural core of v0.3; Level-0 generality stays a commitment (C-PROP-2), not an established fact.
2. **D-1 language discipline** — D-1 (false-dominant) and D-1′ (U-dominant) are both internally consistent under current evidence; D-1 is a specification choice and falsifiable commitment of B, never "proven three-valued logic". Observation `X=false, F=U_c → BLOCKED` licenses only "C-PROP-1/D-1 supported by the observation" — never "Model B proven". An `unevaluable` outcome licenses only "D-1 refuted / B formulation needs revision" — never evidence for Model A.
3. **`U_c` operationalization stays in Step 2** — no spec may assume a manipulation realizing `U_c` exists; otherwise v0.3 slides from conceptual semantics into an unproven experimental state.

Formal research state at seal:

```text
Step 1  Spec v0.3              COMPLETE / SEALED
Case 2  A/B non-identifiable   SEALED AT IDENTIFIABILITY LEVEL
Model B                        explanatory model → concrete falsifiable commitments
Step 2  Uniformity Probe       DESIGN GATE — NOT AUTHORIZED
Step 3  Evaluation-Signature   DEFERRED
```

Next-gate condition: Step 2's design gate requires explicit Human authorization; if opened, the design's FIRST question — before any experiment matrix — is **whether X or F can legitimately be manipulated to `U_c`** (this determines whether C-PROP-1 is an actually testable commitment).

Line reframe registered at seal: conjunction is an explanatory hypothesis; the research object is whether it can sustainably honor a definite set of structural commitments.

---

## Addendum 4 — 2026-10-05: Step 2 Design Gate executed — U_c feasibility verdict CASE U3 (PROPOSED)

Human authorized the Step 2 Design Gate with the first question fixed: **can X or F be legitimately manipulated to `U_c`?** — before any probe matrix. Pre-registered case rule: U1 (both constructible → C-PROP-1 probe) / U2 (one → single-condition probe) / U3 (neither → C-PROP-1 untestable, **Step 2 stops, no U_c manipulation invented**).

Delivered: `MODEL_B_UNIFORMITY_PROBE_DESIGN.md` (committed with this addendum). Gates 2.1 + 2.2 executed; Gate 2.3 not reached.

**Verdict: Case U3 — neither X nor F admits a legal, operationalizable, non-smuggled `U_c` manipulation.** Three independent blockers, grounded in the actual instrument (prompt-rendered conditions, `TEMPLATE_J` + mandated JSON output contract):

- **B-1 construction**: no input-side operation forces determination-non-completion; the instrument instructs fail-closed resolution (template rule 4) and every producible input state (absent/partial/stale/conflicting/corrupt) resolves to a completed determination (established classes: absent→false, stale→quality, conflicting→model-dependent completed).
- **B-2 identification**: the output contract forces verdicts (`transition_status` enum + mandatory booleans) — **no representable non-verdict**; the 846 C4-absent signature belongs to the CI-C fixture's channel and is not mappable onto the agent line; contract violations are confounded with instrumentation failure. The instrument-fix route (adding a COULD_NOT_DETERMINE slot) was analyzed and rejected: new instrument, B-1 untouched, and the slot invites strategic use — the identification problem recurs one level up.
- **B-3 well-formedness**: `U_c` presupposes per-condition determinations as isolable occurrences = condition-level modularity, which is open Q1 (J3's BLOCKED-not-DEGRADED pattern is registered as Q1's existing candidate evidence leaning shared — cited as evidence state, not resolved). U_c feasibility is downstream of Q1.

Four-way distinction enforced (Gate 2.1): absent/irrelevant/corrupt = input states; true/false/U_c = determination outcomes; a "U_c manipulation" would be an input state forcing a non-outcome — a category that is empty in this instrument. Stipulation routes (declaring "UNDETERMINED" as input text; relabeling corruption as U_c) explicitly identified as the smuggling forms and rejected.

Consequences: C-PROP-1 = stateable (sealed, unchanged) / currently untestable in the agent-line instrument; **Step 2 stopped per the pre-registered rule, pending Human confirmation of the U3 verdict**; uniformity-without-C-PROP-1 (ND-1-bound new-condition hunt) remains registered, NOT pursued — independent Human decision required if ever desired. Verdict scope = instrument-relative (no claim about U_c realizability in principle or other setups).

Reopeners registered (none pursued, each requiring new Human authorization): R-1 = an instrument that can represent determination-non-completion + a criterion separating genuine non-completion from evasion/instrumentation failure (adjacent to deferred Step 3 — noted, not opened); R-2 = incidental repeated no-verdict observation under fixed input; R-3 = Q1 resolution toward condition-level modularity.

Q3/Q4/Q6/Q7/Q5 untouched; no frozen phase reopened; no sealed document modified.

---

## Addendum 5 — 2026-10-05: Human confirmation — U3 EFFECTIVE, Step 2 STOPPED (session terminal registration)

Human confirmed: **the U3 verdict and the Step 2 stop take effect.** This addendum is pure registration (zero research content) — it upgrades the PROPOSED status of `MODEL_B_UNIFORMITY_PROBE_DESIGN.md` to CONFIRMED EFFECTIVE and fixes the terminal state of this session per Human direction.

### Fixed formal state (Human, binding)

```text
Case U3
X/F: no legal U_c operationalization
C-PROP-1: stateable / currently untestable
Step 2: STOPPED
No U_c manipulation invented
No experiment run
```

### Boundaries endorsed at confirmation (binding annotations)

1. **Instrument-relative, not ontology.** Never write "`U_c` does not exist in principle." Only: *in the current prompt-rendering / fail-closed / output-contract instrument, X/F have no legal `U_c` construction or observation path.*
2. **The U-slot is not a cheap fix.** Adding `COULD_NOT_DETERMINE` solves representation only; it does not answer which input state genuinely represents "evaluation did not complete" — that unresolved problem would merely move from the outcome layer to the input/determination layer. It is a new-instrument direction, not a modification of the current experiment.
3. **C-PROP-1 is not "refuted".** Its exact status: a clearly defined B-side commitment, currently untestable in this instrument — never `C-PROP-1 false`, and never `C-PROP-1 false → Model A` (Case 2 discipline).

### Research fork registered (Human; none auto-opens)

```text
Step 2  U_c feasibility → U3 → CLOSED / STOPPED
              ↓
        Research choice
        A. keep current instrument, turn to B commitments that do not depend on U_c
        B. open evaluation-signature / new-instrument research
        C. pause Admissibility, switch research line
```

A and B (and C) all require explicit Human re-authorization.

### Deeper question registered at the stop (Human; connects to deferred Step 3; NOT opened)

U3 exposed that `unevaluable` is a state v0.3 introduced for theoretical completeness, while the agent-line instrument's task contract fundamentally requires a verdict. The next worthy question may therefore not be "how to manufacture U_c?" but:

> **Should evaluation failure enter Admissibility's object language, or does it belong to runtime failure outside Admissibility?**

This connects to the deferred Step 3 (evaluation-signature). It is registered as a candidate future question only; nothing is opened by this addendum.

### Session terminal state (per Human direction)

```text
64bbc2e — Step 2 Design Gate COMPLETE → U3 → STOPPED
awaiting Human re-authorization for the next research direction
```

The "cannot-do" itself is a valid research result; no sealed conclusion was sacrificed. A/B/C and the deeper question all remain behind explicit Human authorization.

---

## Addendum 6 — 2026-10-05: Step 3 opened (conceptual) — Evaluation-Signature boundary review delivered, verdict ES-3 (PROPOSED)

Human directive: Step 3 (Evaluation-Signature) formally opened **conceptual only** — no U_c work, no instrument modification, no experiments. Note: this resolves part of the Addendum-5 fork by Human choice — the line continues (options A/C not taken; B taken in its conceptual form as Step 3).

Delivered: `EXECUTION_ADMISSIBILITY_EVALUATION_SIGNATURE.md` v0.1 (committed with this addendum). Four answers in the Human's order:

1. **Layering**: "evaluator cannot run" is not a stage within the functioning chain — it is a status of the chain's first link. The fork asks where this status is booked. v0.3 shown to be **over-complete, not inconsistent**: the same facts are double-entered (three-valued codomain + Level-0/1 process vocabulary); the fork picks which entry is primitive.
2. **Codomain examination**: the fork formalized as **M3** (value reading: `Admissibility ∈ {true, false, unevaluable}` — current v0.3) vs **M2** (gap reading: `Admissibility ∈ {true, false}` + `EvaluationStatus ∈ {available, unavailable}`) — three-valued logic vs partial function / truth-value gap. Key findings: v0.2 §4's `unevaluable` definition is process-descriptive (the content was always a process fact); the only established manifestation is output *absence* (846 C4-absent), which M2 records directly while M3 must attribute; **signature-equivalence** — all established observations, and on analysis any evaluator-side-signature instrument, are accommodated identically by both readings (the fork is attribution-level: a consumer that distinguished value-vs-empty would reintroduce the same choice one level up); derivational economy tilts toward M2 (D-1 near-derivable under M2 via classical conjunction + the §4 boundary; M3 carries a partial-logic choice degree of freedom → D-1 vs D-1′) — **virtue registered as tilt, not converted to evidence**; the M2 side is not yet fully specified (status cardinality, per-condition bookkeeping). v0.2 §4's tie of three-state to Model B dissolves under M2.
3. **Model A re-examination (reopener check)**: the reopener registered in the identifiability note was **checked and answered, not fired into reversal** — Model A stays zero-constrained under any observable expansion (its "whatever process" clause is orthogonal to observables); **Case 2 stands unmodified**. What the expansion changes is the structured landscape: the live comparison becomes M3 vs M2 (both structured; NOT an A/B discrimination). M2 is exactly the "strengthened-A" shape the identifiability note anticipated — Case 2's collapse observation confirmed from the constructive side.
4. **Verdict: ES-3** — evidence insufficient to decide; the insufficiency is structural (signature-equivalence + unspecified M2 + virtues-are-not-evidence + v0.3's codomain was inherited for completeness under a question not yet asked). Concurs with the Human's stated lean. Pause: no experiment, no instrument change, no spec revision.

Decision material registered (none pursued): D-SIG-1 evaluation-consumption divergence (the one class that could break signature-equivalence — the observation this Step is named for); D-SIG-2 Q1 resolution toward modularity; D-SIG-3 M2 specification completion.

Boundary accounting: Case 2 stands; v0.3 stands (fork at interpretation layer only; ES-1-if-ever-chosen ⇒ future v0.4, not proposed); U3/Step-2 STOP untouched; ND-1 in force; Q3/Q4/Q6/Q7/Q5 untouched; all hard boundaries in force. If ES-1 chosen someday it is a codomain revision requiring explicit Human authorization.

---

## Addendum 7 — 2026-10-05: Human seal — ES-3 confirmed; line closed loop (terminal registration)

Human sealed the ES-3 verdict — **no revisions**. Three registered grounds:

1. **M2/M3 correctly placed at the predication layer** — `unevaluable`'s content was always process-factual; no evidence forces elevating the process fact into a third property value.
2. **Signature-equivalence = the round's most important finding** — enhanced evaluator-side instrumentation will not by itself resolve the fork; *"we can observe evaluation failure"* must never be written as *"therefore unevaluable is Admissibility's third value"* (a predication choice, not an observation).
3. **Case 2 reinforced, not overturned** — the live comparison is now M3 vs M2, both structured explanatory models; the discipline asks when a distinguishing structural commitment appears, not which label is prettier. Currently none.

Preserved verbatim as a standing research formulation (Human):

> **M3 与 M2 当前在 observation/signature level 上等价，差异位于 predication / ontological accounting，而非已观察到的行为差异。**

This is a genuine **non-identifiability boundary**, not a failed experiment.

Fixed terminal state (binding):

```text
Case 2                 SEALED
Spec v0.3              SEALED
U3 / Step 2            STOPPED
Step 3                 COMPLETE / ES-3
M2 vs M3               observationally unresolved
Model A reopener       NOT TRIGGERED
New experiment         NOT AUTHORIZED
```

Standing prohibitions: no further `U_c` work; no M2/M3 continuation; no consumer-trick design aimed at breaking the signature-equivalence.

**Line closed loop**: identifiability analysis → Case 2 (sealed) → Spec v0.3 (sealed) → Step 2 U_c feasibility → U3 (Step 2 STOPPED) → Step 3 Evaluation-Signature → ES-3 (sealed). All open items — D-SIG-1..3, Q1/Q3/Q4/Q6/Q7/Q5, any future v0.4 codomain revision — remain behind explicit Human authorization. Nothing auto-opens.
