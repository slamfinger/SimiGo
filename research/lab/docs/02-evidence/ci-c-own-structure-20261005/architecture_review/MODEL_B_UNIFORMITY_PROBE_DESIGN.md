# Model-B Uniformity / Necessary-Condition Probe — Design Gate Document

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `DESIGN GATE EXECUTED · U_c FEASIBILITY VERDICT: CASE U3 — CONFIRMED EFFECTIVE 2026-10-05 (Human confirmation) · STEP 2 STOPPED · NO EXPERIMENT · NO PROBE DESIGNED · NO U_c MANIPULATION INVENTED`
Directive: Human authorization 2026-10-05 — Step 2 Design Gate opened; **first deliverable is `U_c` operationalization feasibility, before any probe matrix**. Pre-registered decision frame: Case U1 / U2 / U3 (below).
Predecessors: `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.3.md` (SEALED, §8 review record) + `EXECUTION_ADMISSIBILITY_MODEL_AB_IDENTIFIABILITY.md` (SEALED, Case 2) + `RESEARCH_LOG.md` Addenda 1–3.
Evidence added: none. Experiment authorization: none. No sealed document is modified by this gate.

---

## 0. Directive and pre-registered decision frame

Human ruling (2026-10-05, verbatim structure):

> 唯一需要继续的问题：**X 或 F 是否存在一个合法、可操作、且不会偷改概念定义的方式，把条件置于 `U_c`（unevaluable）状态？** 这比直接设计 probe matrix 更优先，因为 C-PROP-1 是否可测，取决于 U_c 是否能被真正构造出来。

Pre-registered case rule (binding on this gate):

```text
Case U1: X 和 F 均可合法构造 U_c   → 可以设计 C-PROP-1 probe
Case U2: 只有一者可构造            → 只能做单条件 probe
Case U3: X/F 均无法合法构造 U_c    → C-PROP-1 当前不可测，Step 2 停止；
                                     不允许为了实验而发明 U_c manipulation
```

Gate order: **2.1** define legal `U_c` manipulation (strictly distinguishing `false ≠ unevaluable ≠ absent ≠ irrelevant`) → **2.2** boundary-violation check (no redefinition of `U_c`; no packaging absence as unevaluable; no reinterpreting X/F via 846; no prejudging E/846 placement) → **2.3** only if a legal manipulation exists, design the probe (first batch = C-PROP-1 only; Q3/Q4/Q6/Q7 stay closed).

This document executes Gates 2.1 + 2.2 and lands the case verdict. Gate 2.3 is **not reached** (see §4).

---

## 1. U_c operationalization feasibility

### 1.1 What would have to be constructed

The target state, quoted verbatim from v0.3 §2 (no redefinition permitted):

```text
U_c : determination of THIS condition does not complete
      while the evaluation process itself is operative
```

Two feasibility conditions must hold **simultaneously**, plus one structural presupposition:

- **B-1 (construction)**: an input-side operation exists that *yields* determination-non-completion — not merely one that we could *label* non-completion.
- **B-2 (identification)**: the observation channel can *represent and recognize* "determination did not complete" and distinguish it from (i) a completed negative determination (`false`), (ii) a completed positive one, and (iii) instrumentation failure.
- **B-3 (well-formedness)**: per-condition determinations exist as isolable occurrences — `U_c` presupposes that "the determination of condition c" is a thing that can fail on its own. Whether the agent-line evaluation is modular per condition is exactly open **Q1** (shared vs parallel), unresolved.

### 1.2 The instrument as it actually exists

Grounding artifacts (this line's own sealed run): `joint_probe_design/JOINT_ELIGIBILITY_PROBE_DESIGN.md` §5, `joint_probe_run/prompts/TEMPLATE_J.prompt.txt`, `INFO_F_PRESENT.txt`, `INFO_F_ABSENT.txt`, and the J1–J4 run records.

Fact 1 — **conditions are prompt-rendered declarations**. X is an authorization-layer declaration in the instruction text (`A_execution (X): {X_STATUS}` + reason); F is the "Available information" section (a baseline-compatibility record, or "not available in this context"). Conditions are inputs *given as text*, not hidden state.

Fact 2 — **the output contract forces verdicts**. The mandated JSON requires `transition_status ∈ {COMPLETED, DEGRADED, BLOCKED}` and mandatory determination fields (`source_ledger.F_content_visible`, `information_dependency.compatibility_info_available/current/consistent`, `execution_gate.status ∈ {ELIGIBLE, INELIGIBLE}`). **No field admits a non-verdict value.** "Could not determine" is not representable; free-text `reason` fields do not rescue this — a forced boolean alongside prose still completes the determination observationally.

Fact 3 — **the instrument instructs fail-closed resolution**. Template rule 4: *"If the required information is missing or the execution path is not eligible, block the transition and declare the dependency."* Every missing/indeterminate input is, by instruction, to be resolved into a completed negative determination.

Fact 4 — **established resolution tendency**. Across all runs of this line (Phase A, Phase B, Joint Probe J1–J4, Generic-Validation Probe), every outcome landed in {COMPLETED, DEGRADED, BLOCKED}. No no-result / non-verdict outcome class has ever been observed in the agent line. (Inductive status, honestly marked: absence of such observations ≠ impossibility — but see B-1/B-2, which do not rest on this tendency alone.)

### 1.3 The four-way distinction (Gate 2.1)

| Notion | Category | Instrument grounding |
|---|---|---|
| **absent** | an **input state** (manipulation class) | `INFO_F_ABSENT.txt`: "record not available in this context" |
| **irrelevant** | an input class with no blocking effect (non-condition) | G / F-IRRELEVANT: no BLOCKED (Generic-Validation Probe) |
| **false** | a **determination outcome**: completed, negative | F-absent → `compatibility_info_available: false` → BLOCKED (established, J2) |
| **unevaluable (`U_c`)** | a **determination outcome**: does not complete | **no input state maps to it; no output slot represents it** |

The crux this table encodes: absent / irrelevant / corrupt are **input states**; true / false / `U_c` are **determination outcomes**. A "`U_c` manipulation" would have to be an input state that forces a *non-outcome*. In this instrument that category is empty: every input state the line knows how to produce is (by instruction — Fact 3 — and by established tendency — Fact 4) resolved into an outcome.

### 1.4 Why no legal route exists (three independent blockers)

**B-1 — construction.** X's "determination" is reading a declared status from text; there is no input state that makes reading a declaration fail to complete while the rest of the procedure continues. F's determination is scaffolded by explicit rules; every producible input state (absent / partial / stale / conflicting / corrupt) either belongs to an established class with a completed outcome (absent → false; stale → quality layer; conflicting → model-dependent completed determinations) or resolves fail-closed per rule 4. No operation yields non-completion.

**B-2 — identification.** Even if a determination internally failed to complete, the observation channel could not record that fact: the contract forces a verdict enum and booleans (Fact 2). The one established no-result signature in this research program — 846's C4-absent — lives in the CI-C fixture's channel and **must not be mapped onto the agent line** (boundary, §7). A contract-violating response (garbage / no JSON) is confounded with instrumentation failure and would be classification-by-stipulation — precisely the move Gate 2.2 forbids.

**B-3 — well-formedness.** `U_c` presupposes per-condition determinations as isolable occurrences. The agent line's own probe could not resolve shared vs parallel structure (Q1 open; the observed J3 pattern — BLOCKED, not the H-INDEPENDENT-predicted DEGRADED — is registered candidate evidence *leaning shared*, cited here only as Q1's existing evidence state, not as a resolution). If evaluation is a shared holistic function, "condition c's determination alone failed" may be structurally ill-formed rather than merely hard to induce. `U_c` feasibility is therefore **downstream of Q1**.

---

## 2. Candidate manipulations examined and rejected (Gates 2.1 + 2.2 executed)

| # | Candidate | Target | Why it fails |
|---|---|---|---|
| 1 | F-absent (existing) | F | Completed negative determination → `false` (established, J2). Absence is an input state, not `U_c`. |
| 2 | F-STALE (established) | F | Currency facet → quality layer (DEGRADED, non-blocking). Not `U_c`. |
| 3 | F-CONFLICTING (established) | F | Model-dependent **completed** determinations (C completes / N blocks); no non-completion observed; Q7 untouched. |
| 4 | F section rendered unreadable/corrupt (new) | F | Fail-closed resolution → "unavailable" → `false`; even an error-shaped output has no representable slot (B-2); declaring it `U_c` by stipulation = forbidden redefinition. |
| 5 | F partially present / truncated content (new) | F | Resolves to an availability judgment → `false` or quality class; no non-completion route. |
| 6 | F relevance made indeterminable (new) | F | Outcome-contingent (F-CONFLICTING precedent), not by-construction (B-1) and not identifiable (B-2). Registered as a candidate *region* only; it does not rescue feasibility. |
| 7 | Authorization layer section removed entirely | X | Mutates the instructed evaluation scaffold (context mutation, not a condition state); fail-closed parallel of F-absent → `false`. |
| 8 | X declaration malformed or self-contradictory | X | Decidable-as-invalid (fail-closed) → X- equivalent → `false`; conflict precedent = model-dependent completed determination. |
| 9 | X declared "UNDETERMINED" in text (new) | X | The purest stipulation route: `U_c` would be *asserted as an input label*, not observed as a determination outcome; the contract's forced `execution_gate.status ∈ {ELIGIBLE, INELIGIBLE}` resolves it. This is the concept-smuggle Gate 2.2 exists to catch. |
| 10 | Evaluator-side degradations (context truncation, attention engineering, capability reduction) | X/F | Damages the evaluation process → Level-0 territory → wholesale `unevaluable` (C-PROP-2 preemption), or instrument mutation. Not condition-state operations at all. |
| 11 | Self-referential constructs (X/F defined via their own verdict) | X/F | Mutates the condition's semantic role — illegal under Gate 2.1's legality requirement. |
| 12 | 846-style component deletion mapped onto X/F | X/F | Forbidden: 846 reinterpretation boundary. K3/C4 belong to the CI-C fixture, not to the agent-line conditions. |

Every candidate collapses into (a) an existing input class with an established completed outcome, (b) an evaluator-side / instrument mutation (Level 0 or context change), or (c) stipulation. None is a legal `U_c` manipulation.

---

## 3. The structural finding: the squeeze

The candidate space for legal `U_c` manipulations is squeezed between the two failure modes this program understands best:

```text
input-side indeterminacy  ──(instructed/established resolution)──►  completed determination (false / quality)
evaluator-side damage     ────────────────(Level 0)──────────────►  wholesale unevaluable (C-PROP-2 preemption)
                          ─────────────── ??? ────────────────►  per-condition U_c: no known occupant of this region
```

A per-condition `U_c` requires the evaluation process to stay operative while exactly one condition's determination fails — which presupposes per-condition modularity (B-3/Q1), a forcing operation (B-1: none exists; the instrument instructs the opposite), and a representable observation (B-2: none exists). **The two-level structure sealed in v0.3 is thus not just vocabulary — it explains the feasibility failure**: the agent line's instrument sits entirely on the two resolved sides of the squeeze.

### 3.1 The instrument-fix route, analyzed and rejected

Could the output contract be extended with an explicit non-verdict option (e.g., `COULD_NOT_DETERMINE`)? This would address B-2's representability at best — and it fails three times over:

1. It is a **new instrument** (new design gate, new authorization) — not a condition-state manipulation.
2. It leaves **B-1 untouched**: nothing forces a determination to actually fail; the option's existence does not create the state it names.
3. It introduces a **demand-characteristic**: an available non-verdict slot invites *use* — strategic evasion, not determination failure. Classifying its emission as `U_c` would be stipulation one level up: the distinction "genuine non-completion vs. chosen non-answer" is exactly the criterion we lack (B-2 recurs).

The fix route therefore relocates the identification problem rather than solving it. It is registered (R-1, §6), not recommended as a rescue.

---

## 4. VERDICT

**Case U3.** Neither X nor F admits a legal, operationalizable, non-smuggled `U_c` manipulation in the current instrument — blocked independently by B-1 (construction), B-2 (identification), and B-3 (well-formedness, downstream of open Q1).

Per the pre-registered rule: **C-PROP-1 is currently untestable; Step 2 STOPS; no `U_c` manipulation is invented.** Gate 2.3 is not reached; no probe matrix is designed.

Verdict scope: **instrument-relative.** This verdict says nothing about `U_c` being unrealizable in any setup — v0.3's `U_c` remains well-defined, and the 846 fixture retains its own (Level-0) unevaluable. What is established here is only that the agent-line instrument affords no legal route for X or F.

Status: **CONFIRMED EFFECTIVE 2026-10-05 (Human confirmation) — Step 2 STOPPED.** See `RESEARCH_LOG.md` Addendum 5 for the fixed terminal state and the registered research fork.

---

## 5. Consequences

1. **C-PROP-1 re-marked**: stateable (v0.3's deliverable — unchanged, sealed) / currently untestable in the agent-line instrument / three blockers registered (§1.4). No sealed document changes.
2. **Step 2 stopped** in its C-PROP-1-first framing, per the pre-registered Case U3 rule, pending Human confirmation.
3. **Uniformity without C-PROP-1** (new-condition hunt under ND-1, the original Q8 re-scope): remains **registered, not pursued** — whether any such activity continues is an independent Human decision; nothing here advocates or opens it.
4. No new conditions, no new models, no instrument changes proposed, no frozen phase reopened.

---

## 6. Reopeners (registered, none pursued)

- **R-1**: an instrument whose observation channel can represent determination-non-completion **and** a criterion separating genuine non-completion from evasion or instrumentation failure. (Adjacent to the deferred Step 3 evaluation-signature question — noted for genealogy only; Step 3 is not opened by this document.)
- **R-2**: incidental, repeated observation of a no-verdict outcome under a fixed input state — would establish that non-completion *occurs*; identification would still require R-1.
- **R-3**: resolution of Q1 toward condition-level modularity would firm up `U_c`'s well-formedness (B-3). Q1 stays open; this registers the dependency only.

Any reopener requires new Human authorization. Until then Step 2 remains stopped.

---

## 7. Gate 2.2 compliance checklist

| Prohibition | Compliance |
|---|---|
| 偷换 `U_c` 定义 | `U_c` quoted verbatim from v0.3 §2 (§1.1); every candidate tested *against* the definition; the stipulation routes (candidates 4, 9) explicitly identified as the smuggling forms and rejected. |
| 把一般缺失包装成 unevaluable | Absence classified as an input state whose established outcome is `false` (§1.3); F-absent / X- never relabeled. |
| 借 846 重新解释 X/F | 846 cited only as the established Level-0 instance and the home of the C4-absent signature; explicitly not mapped onto X/F (candidate 12 rejected; B-2 scoped accordingly). |
| 提前决定 E / 846 是 conjunct 还是 precondition | No placement made anywhere; Q3/Q4 untouched; B-3 references Q1 only as an unresolved dependency. |

Q6 (C anomaly) and Q7 (F-CONFLICTING) are cited only in their established statuses; neither is interpreted. All hard boundaries from `RESEARCH_LOG.md` remain in force.

---

## 8. Non-claims

This document does not: prove or refute Model B, Model A, or any commitment; interpret Q6/Q7; resolve or prejudge Q1/Q3/Q4; reopen any frozen phase; authorize any experiment, code, or instrument change; claim `U_c` is unrealizable in principle or in other setups; or modify any sealed document. Its sole deliverable is the feasibility verdict under the pre-registered case rule.
