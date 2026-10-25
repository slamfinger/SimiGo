# RESEARCH_GOVERNANCE_CONSTITUTION_V0.1

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `INDUCTIVE DRAFT · DERIVED FROM THE SIMIGO-LAB RESEARCH LINEAGE · NOT AUTO-APPLIED TO ANY EXISTING LINE · PENDING HUMAN REVIEW`
Relationship to adopted governance: `SIMIGO_LAB_RESEARCH_CONSTITUTION_20261005.md` (v1.0, prescriptive, adopted `e97f5e7`) states the operative rules. This document is the **inductive layer**: it re-derives governance from what the lineage has actually done — its deviations, corrections, freezes, satellites, and goal evolutions — and proposes the epistemological grounding v1.0 currently lacks. Where the two disagree, the disagreement is surfaced as an explicit Human Review item (§7), not resolved here. Nothing in this document is applied to any existing line.

Session header (per adopted Constitution Article 6):

```text
Core target:               the research governance system itself (meta-governance)
Affected closure edge:     none directly — governance enables all five edges
Real system object:        governance documents, line-state classifications, drift signatures
Expected capability delta: drift becomes mechanically detectable; goal revision becomes legal and cheap
Stop condition:            Human Review verdict on this draft
```

---

## 1. The evidence base: what the lineage has actually taught

Every article below is induced from episodes like these. This table is the constitution's empirical ground; the articles are its compression.

| # | Episode | What happened | Governance lesson |
|---|---|---|---|
| E1 | ES-line Research Line Reset (`7622dd6`, human review `e3b1cd9`) | Concept-grade audit found evidence-grade drift (concepts all-A, evidence B/C); OFF-MAINLINE 6 items downgraded and barred from definition-evidence; the real fork identified as single-point deepening after a hidden assumption | Depth drift is **detectable** (grade inflation, unbounded deepening); downgrade preserves work while stopping narrative pollution |
| E2 | T3 Closure Review (`5b55599`) | L3 UNVERIFIABLE-AS-IS with six blockers; the distilled answer: "缺的是 Representation 能力非实验"; closure yielded a better-posed question (可分解·可引用·可重组) | A closed line's yield is a **better-posed question**, not a verdict of failure |
| E3 | Repeated human declines to continue deep lines ("不写 C 不续 B′"); R3-2 H-1 lesson | Necessary repeated negation ≠ over-proceduralization | Governance volume is not value; negation can be the work |
| E4 | P5 attempt-1 FAIL → re-judged INCONCLUSIVE (`78ed0d4`) | Baseline defect (probe-only history) caught by trace; the pre-registered claim was never tested; yet the run produced an engine-boundary fact (KV = representation fragment, not an independent carrier) | **Construct validity**: an outcome tests only the claim actually instantiated; a failed test can still reframe the model |
| E5 | P5-2 reframing (数据搬运 → 关系保持) | Human-driven goal adjustment from a negative result, continuous with the registered "what minimal relation set enables continuation?" | Core-model revision from below is a normal operation |
| E6 | PA-2 (`P5-4`) | Same count, different content → output follows rendered prompt text, not KV semantics ⇒ Position ≠ Semantic Anchor | A branch finding became load-bearing for the core model — **reflux happens, and must be legal** |
| E7 | R-C1 attempts #1–#3 invalid, #4 valid | CLI parser, premature final check, nil store force-unwrap → fail-closed `DisabledRelationStore`; each fix re-audited before any claim | Instrument defects never produce scientific claims; engineering fail-closed is governance-grade |
| E8 | Replication/Audit phase entry; R0 instrument self-check | "实验结果正确 ≠ 过程真实执行了目标路径" — P8/P9 paused until authenticity was established | Evidence governance includes the **provenance of the execution process itself** |
| E9 | Safety event: 19 research commits pushed to the public product repo; force-push rollback | Research/product venue separation was violated and repaired | Research artifacts and product artifacts live under different regimes; the boundary needs a rule, not vigilance |
| E10 | R3 family (`R3-1..R3-4`, IS-X ×2, closing `e27a7ba`) | Spec-only authorization; I≡TRUE preserved rather than complicated; INCONCLUSIVE contagion permanently preserved even after root-cause; attempt-2 scope-locked; claim-narrowing revisions (rev.2); bounded synthesis; UB-1..7 registered as open boundaries; "无反例永远带探针域" | **Claim narrowing is maintenance, not retreat**; null results are evidence; freezes are bounded; honesty clauses are pre-registered |
| E11 | Route S1..S4 rejected (上游倒置); Route A/B deferred (confounder = Information equivalence) | A route selection was refused because it inverted upstream dependencies; a discriminating probe was deferred because a confounder was identified | Sequencing and confounder checks belong to governance, before runs |
| E12 | Admissibility Case 2 (`f8840fd`) + ND-1 | Identifiability settled **on paper** before any experiment; an entire would-be experiment class (A/B discrimination) shown impossible by construction; the D-trap registered | The decidability pre-check prevents depth from compounding on undecidable questions — the cheapest experiment is the one shown impossible |
| E13 | U3 (`64bbc2e`) | Instrument cannot produce the state; no manipulation invented; "做不到" registered as a valid result | Instrument impossibility is a result; the system must not be forced to fake constructibility |
| E14 | ES-3 (`56500ad`) | M2/M3 shown signature-equivalent — the fork is attribution-level; held open rather than forced | Competing models are protected; observation decides only when signatures diverge |
| E15 | Core Goal evolution: ES as "state" → P6 "relation closure" (MLX-bounded, OP-6 open) → Boundary Synthesis embedding → R0 question adoption → 2026-09-27 product redirect (beta pulled) → ES↔IS loop adopted | The Core Goal changed legitimately several times, each with registered lineage | Goal revision is **normal and must be legalized**, with lineage; freezes are bounded, never global |
| E16 | Palace Boundary Study F-8 ("会存不会取"); T-series ("信任不随信息保存传递") | A side-study of a real system exposed that storage ≠ retrieval, and that trust does not transfer with saved information | System-level lessons often arrive from side studies — divergence has epistemic value |
| E17 | Core Reference Scenario test (`e97f5e7`) | The scenario mapping set aside the locality axis — a concept the line itself had introduced — within one session, by rule rather than by human vigilance | Drift can be caught by **mechanism**; this is the proof of concept for everything below |

---

## 2. Research epistemology (what this lineage says research is)

**E-A. A research line produces evidence, not narratives.** Its products are exactly three: claims with boundings, better-posed questions, and (occasionally) capabilities. Anything else it accumulates — depth, elegance, internal consistency — is fuel, not product. (E1, E2, E10)

**E-B. Every closure must pay in one of three currencies.** A line that ends must show: a system capability gained, a better-posed question distilled, or a corrected model element. T3 paid in questions; U3 in a boundary fact; P5-attempt-1 in a reframing; R3 in a bounded characterization plus seven registered open boundaries. A line unable to pay in any currency at closure has not failed — but its *lostness* has just become visible. (E2, E4, E13)

**E-C. Non-identifiability and null results are first-class outcomes.** Case 2 (structural non-identifiability), R3-3 (10/10 holds), IS-X's anti-sliding clause, ES-3's signature-equivalence — the lineage repeatedly found that *ruling things out or ruling them undecidable* was the most consequential work it did. Governance must never score these below "positive" results. (E12, E14)

**E-D. Claim narrowing is maintenance, not retreat.** The rev.2 lineage (universal quantifiers narrowed, assertion scopes restricted, "I≡TRUE preserved rather than complicated") shows a healthy line *continuously shrinks* its claims toward what the evidence holds. A claim that never narrows under pressure is the anomaly. (E10, E3)

**E-E. Models compete; evidence decides only what it can.** The lineage has held competing models open across sessions (Structure A/B; M2/M3; I1/I2/I3) and has learned to distinguish the cases: sometimes observation can decide (R3's differential sensitivity), sometimes only attribution differs and the fork must be held (ES-3). Forcing closure on an attribution-level fork is a governance error. (E14, E12)

**E-F. Instrument truth and claim truth are different registers.** An implementation defect produces INCONCLUSIVE, never refutation; a successful run proves only the claim it actually instantiated; the authenticity of the execution process is itself evidence. The lineage learned each of these the expensive way. (E4, E7, E8, E10)

## 3. Evidence governance (articles)

**V-1 — Bounding-carrying citation.** Every sealed result carries its bounding (fixture-slice, carrier-level, task-domain, backend-bounded), and every citation must carry it forward. This is mechanically checkable at citation time — which is what made the OFF-MAINLINE regime work (E1). Drift's first signature is a bounding silently dropped.

**V-2 — Periodic grade accounting.** The map of "what is actually established vs. assumed" must be re-audited at each synthesis gate. Evidence-grade inflation is the second drift signature; it was the trigger of the only full line reset in the lineage (E1).

**V-3 — Construct validity.** A run tests exactly the claim it was designed and instrumented to test — no more. Claims must be stated precisely enough that "was it tested?" is checkable; re-judgment from FAIL to INCONCLUSIVE when the claim was never instantiated is mandatory, not optional charity. (E4, E10)

**V-4 — Instrument/claim separation, with preservation.** Instrument defects invalidate the run, not the hypothesis; INCONCLUSIVE verdicts are permanent records even after root-cause is known (undoing a pre-registered exit rule post hoc would corrupt the exit-rule institution itself); all data is preserved and never silently reorganized into conclusions. (E7, E10)

**V-5 — Process authenticity and venue separation.** "The result is correct" and "the target process actually executed" are separate checkpoints; execution provenance (commits, hashes, traces, audits) is part of the evidence; research artifacts and product artifacts live under separated regimes with separated failure modes. (E8, E9)

**V-6 — Negative-result reflexivity.** Every closure, pause, or invalidation must answer: *what question does this failure better-pose?* A negative result with no distilled question is treated as incomplete closure — not because the result is worthless, but because its value is still uncashed. (E2, E4, E5, E13)

## 4. Route governance (the local-depth problem)

**R-1 — Three line states, with legal transitions.**

```text
CORE            directly load-bearing for the current Core Goal
EXPLORATORY     (Satellite) valuable, divergence permitted, no Core obligation
PAUSED/ARCHIVED sound, but continued work does not currently narrow important uncertainty
```

Transitions: **promotion** requires a reflux ground (R-3); **demotion** is graceful and irreversible only in the sense that the work is preserved with boundings; **pausing** is a normal mature state, not failure (the Admissibility line's PAUSED/SATELLITE classification is the precedent). A special flag exists for **competing models**: two models may both hold Core-adjacent status while a fork is genuinely open (M2/M3).

**R-2 — Depth stop conditions.** A line's depth is not governed by "how deep it is" or "whether it relates to Core", but by four questions, assessed **at synthesis gates, not by the line itself**:

```text
1. Is it still producing new evidence (not re-confirming)?
2. Is it narrowing an important uncertainty?
3. Is it producing transferable structure (usable by other lines or the system)?
4. Or is it only refining a local distinction that cannot affect the system model?
```

If (4) alone holds → downgrade or pause. This is the institutional answer to the deepening trap of E1: the line itself is the worst judge of its own recursion, so the judgment is externalized.

**R-3 — Reflux channels (Satellite → Core).** A satellite re-enters Core when it demonstrably does any of:

```text
a. exposes a necessary condition of the core model        (PA-2: Position ≠ Anchor — E6)
b. provides a key counterexample or impossibility result   (Case 2/U3-class: E12, E13)
c. discovers a new realistic implementation path           (carrier findings: E4)
d. changes the Core Goal itself                            (Boundary Synthesis: E15)
e. establishes a key State ↔ Information relation          (R-adm elevation: current ES↔IS work)
```

**偏离不是失败。** The lineage's most valuable single facts (PA-2; the KV-fragment boundary; storage ≠ retrieval) all arrived from work that looked side-ways when started.

**R-4 — Decidability pre-check.** Before any experiment whose purpose is discrimination between models, the identifiability question is settled on paper: what observation, under each model, is *necessitated*? If neither side necessitates anything, the experiment is shown impossible — and that showing is itself the result. (E12 saved an entire experiment class this way.)

**R-5 — Sequencing and confounder discipline.** Route selections that invert upstream dependencies are rejected without review of their content; a proposed discrimination with an identified confounder is deferred, not run. (E11)

**R-6 — Anti-beautification.** When evidence is compatible with a simple (even trivial) form of a concept, the simple form is preserved — complexity is never added to make a result more interesting (I≡TRUE stood as registered). And what would *not* be surprising is pre-registered, so that surprise cannot be manufactured post hoc. (E10)

**R-7 — Protected exploration window.** The governance questions of R-2 and §5 are **retrospective and periodic instruments**. They must never be applied as admission vetoes to young lines: a new line gets a protected window in which divergence, competing models, and unproven value are the expected condition. Governance catches drift; it does not prevent entry.

## 5. Goal governance (the Core Goal problem)

**G-1 — The North Star is a reference frame, not a theorem.** The stable element of the Core Goal is the **closure loop** (Information Space ↕ Execution State ↕ continuation) — the frame within which research is steered. Every *model* inside that frame (P6's definition, M2/M3, I1/I2/I3, the R-adm elevation) is explicitly a hypothesis with registered revisability. Governance steers by the frame; epistemics never mistakes the frame for established fact. ⚠ This article **tensions with** adopted v1.0's "North Star unalterable" clause; see §7, HR-1.

**G-2 — Core Goal revision, with lineage.** If accumulated satellite evidence shows the current formulation inaccurate, the goal is formally revised:

```text
old goal → evidence → reason for revision → new goal
```

registered in git. Retroactive reinterpretation of history is prohibited: past claims are cited at their original grades and boundings, never rewritten to flatter the present goal. The lineage already exercised this right legitimately (E15); the constitution's role is to make it cheap in dignity terms — a goal whose revision is shameful will be defended past its accuracy.

**G-3 — Domain separation of promotion forces.** Experimental success, conceptual elegance, and engineering maturity are three different currencies and none alone promotes a theory: a beautiful spec does not make a model Core; a clean experiment proves only its instantiated claim (V-3); a mature runtime proves feasibility, not truth. Symmetrically: one failed experiment does not demote the Core Goal; one instrument defeat does not refute a concept. (E4, E7, E10)

**G-4 — Bounded freezes.** Every freeze/seal is a *local* commitment carrying explicit non-universality bounding and registered reopeners (P6: MLX-based, OP-6 open; R3: fixture-slice, UB-1..7). "Sealed" always means "sealed under these conditions." A freeze that cannot state its own reopening conditions is not a freeze but an evasion.

**G-5 — Periodic synthesis gate.** After every line closure — and in any case at regular intervals or when unrefluxed satellite mass accumulates — a synthesis gate answers five questions, in this order:

```text
1. 我们现在对总体系统理解比上一轮多了什么？   What do we understand now that we did not?
2. 哪些旁支真正回流到了 Core？               Which satellites actually refluxed?
3. Core Goal 是否仍然成立？                  Does the Core Goal still hold — as hypothesis?
4. 目前最大的现实缺口是什么？                 What is the biggest real gap?
5. 下一步研究哪一个缺口，而不是哪一个问題最有趣。 Next: which gap — not which question is most interesting.
```

The gate produces a **gap map**, not a work assignment; selection remains a Human ruling. The gate is also where R-2's stop conditions are assessed and V-2's grade audit runs — one instrument, three functions.

## 6. The cycle, and the two guarantees

The constitution institutionalizes one cycle:

```text
允许探索 → 累积证据 → 形成结构 → 回归整体 → 必要时修正整体
(permit exploration → accumulate evidence → form structure → return to the whole → revise the whole when necessary)
```

Exploration is protected (R-7, R-1); evidence is governed (V-1..V-6); structure forms under claim-narrowing and model competition (E-D, E-E); return is forced by synthesis gates and closure-currency obligations (G-5, E-B); revision is legal, lineage-bound, and cheap (G-2, G-4).

### Guarantee 1 — How can SimiGo go deep locally without being permanently lost locally?

**By making lostness a detectable state instead of a forbidden one.** The lineage shows that every serious drift was preceded by detectable signatures: evidence-grade inflation (E1), bounding dropped in citation, a line unable to state what it would cash out at closure, deepening on a question no experiment could decide (E12), recursion on a distinction that cannot affect the system model. The constitution does not prevent anyone from going deep anywhere — it installs four trip-wires under the depth:

1. **bounding-carrying citation** (V-1) — drift shows up as a bounding violation, mechanically checkable;
2. **grade accounting** (V-2) — drift shows up as grade inflation at audit;
3. **closure-currency obligation** (E-B/V-6) — every line must pay capability, a better question, or a corrected model; inability to pay makes lostness *visible at closure* even if invisible during work;
4. **synthesis gates with gap-first ordering** (G-5) — the rudder: periodically, the next step is chosen by the gap map, not by local gravity; and the decidability pre-check (R-4) prevents the deepest loss of all — compounding depth on an undecidable question.

None of these requires Human vigilance to notice yaw; each converts yaw into a inspectable signal. That is the practical meaning of "深入局部，但不会永久迷失在局部": not that depth is bounded, but that **being lost is engineered to be discoverable** — and history (E17) shows the trip-wires fire.

### Guarantee 2 — How can we prevent deviation-avoidance from prematurely freezing an immature overall goal?

**By freezing the frame, bounding every seal, and making goal revision legal and cheap.** Five asymmetries do the work:

1. **The invariant is the loop, not any model.** What governance steers by (IS↔ES↕continuation) is thinner than any theory of it; every model beneath the frame is registered as revisable hypothesis. Premature freezing of the *frame* cannot happen because the frame makes almost no claim.
2. **Every freeze is bounded** (G-4): "sealed" always carries its conditions and reopeners, so a freeze is a pause in tension, not a tombstone. The lineage's freezes (P6, R3) all had this form, and all their reopeners remain live.
3. **No single event moves the goal** (G-3): the domain separation means neither a triumph nor a disaster in one register can unilaterally rewrite the Core Goal — revision requires *accumulated* evidence.
4. **Competing models are protected** (E-E, R-1): where observation cannot yet decide, the constitution holds forks open (ES-3) rather than forcing a choice that would feel like progress.
5. **Revision writes lineage forward** (G-2): old goal → evidence → reason → new goal, with retroactive reinterpretation prohibited. Because revising is dignified and recorded, there is no incentive to defend an outdated goal for narrative consistency — the actual historical cause of premature freezing.

And the deepest protection is historical: the Core Goal *has* already been revised legitimately several times (E15 — from "state" to "relation closure" to "embedding in Information Space" to the loop). This constitution does not invent goal-fluidity; it **legalizes what the lineage already did well**, so that future revisions carry the same legitimacy without depending on the same luck.

## 7. What this document is not, and what Human Review must decide

**Not**: a project-management specification; a checklist; an experiment protocol; an auto-applied regime. It is a research-epistemology + route-governance + evidence-governance document, derived from the lineage and offered for review. Per directive, **nothing here is applied to any existing line** until Human Review returns a verdict.

**Explicit Human Review items:**

| # | Question | Note |
|---|---|---|
| HR-1 | North Star alterability: this draft treats the Core Goal as a *reference frame + revisable hypothesis* (G-1); adopted v1.0 Article 1 says "unalterable". Reconcile: amend v1.0, scope v1.0's clause to the loop-frame only, or reject G-1. | The lineage (E15) supports revisability-with-lineage; the decision is Human's. |
| HR-2 | Do the three states of R-1 replace or complement v1.0's SUPPORTING/EXPLORATORY/PAUSED? | The sets overlap; a merge table can be produced on request. |
| HR-3 | Synthesis-gate cadence: after every line closure? every K closures? calendar-based? | K left open deliberately. |
| HR-4 | Who assesses R-2's stop conditions — proposal: the synthesis gate, never the line itself. | Confirm or adjust. |
| HR-5 | Protected exploration window (R-7): duration/exit criteria for young lines. | Deliberately unspecified. |
| HR-6 | If adopted: does this supersede v1.0, amend it, or stand beside it as its epistemological preamble? | Any choice requires registering the lineage (G-2 applied to the constitution itself). |

**Non-claims**: this draft proves nothing about Execution State or Information Space; it seals nothing; it authorizes no experiment; it reopens no frozen line; and it does not retroactively re-grade any past result — every episode above is cited at the grade and bounding it already carries.
