# RESEARCH_GOVERNANCE_CONSTITUTION_V0.2

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `REVISED DRAFT v0.2 · INCORPORATES THE HUMAN REVIEW VERDICT ON V0.1 · NOT APPLIED TO ANY EXISTING LINE · ADOPTION AND RELATIONSHIP-TO-V1.0 RULING PENDING`
Relationship to adopted governance: v1.0 (`SIMIGO_LAB_RESEARCH_CONSTITUTION_20261005.md`, `e97f5e7`) is **untouched**; the HR-1 resolution lives here as the Frame/Model distinction, which *interprets* v1.0 Article 1 rather than amending it.
Revision lineage (G-2 applied to this constitution itself): v0.1 (`92a94e4`) → Human Review verdict (2026-10-05: three must-fix, three recommended, remainder endorsed) → v0.2 (this document).

---

## 0. What changed from v0.1 — and what deliberately did not

**Changed (Human review directives):**

1. **HR-1 resolved by layering** (not three-choice): G-1 rewritten as the **Frame / Model distinction** with the four-layer vocabulary Frame / Model / Claim / Evidence. The unalterable is the research frame; what evidence revises is the model beneath it. v1.0 is neither amended nor overruled.
2. **R-1 split into two axes**: **Track** (CORE / SATELLITE — research status) × **Satellite state** (SUPPORTING / EXPLORATORY / PAUSED — condition within the satellite track). Ends the "is Core a line state?" ambiguity.
3. **Repatriation identity rule** (R-3 + G-2): *repatriation changes research status, never retroactively changes the evidentiary identity of the work.*
4. **E-B softened**: the three currencies are a **minimal value-accounting framework, not an exhaustive ontology**; *reusable research structure* recognized as a product class. **V-6 differentiated**: closure / invalidation / pause carry different distillation obligations; the pause obligation is deliberately weaker.
5. **R-7 rewritten**: protection is **evidence-milestone-based** (entry → protected exploration → first evidence milestone → first synthesis review) — no time, session, or commit quotas.
6. **New anti-recursion article (§5A)**: *governance is an instrument of research, not by default a research object.*

**Deliberately unchanged**: the 17-episode evidence base; E-A and E-C..E-F; V-1..V-5; R-4, R-5, R-6; G-3, G-4; the two Guarantees (terminology only aligned to Frame/Model); "Deep but disconnected ≠ Core".

**Registered, not implemented** (Human review direction): future evolution into a **generic Research Governance Framework** (evidence / exploratory / synthesis / model-revision / lineage) plus a **SimiGo Project Research Charter** (North Star, Core map, current models and lines, project gates) — SimiGo as the framework's first validated instance, not the owner of a private rulebook. Not built in v0.2, per the six-item restraint.

**Temporal scope of the new vocabulary**: Frame/Model/Claim/Evidence applies **from v0.2 forward**. Earlier goal evolutions (E15) predate it and are *not* retroactively reclassified — applying the new vocabulary backward would violate the identity rule this revision installs.

---

## 1. The evidence base: what the lineage has actually taught

*(Unchanged from v0.1 — the constitution's empirical ground.)*

| # | Episode | What happened | Governance lesson |
|---|---|---|---|
| E1 | ES-line Research Line Reset (`7622dd6`, human review `e3b1cd9`) | Concept-grade audit found evidence-grade drift; OFF-MAINLINE 6 items downgraded and barred from definition-evidence; the real fork: single-point deepening after a hidden assumption | Depth drift is **detectable**; downgrade preserves work while stopping narrative pollution |
| E2 | T3 Closure Review (`5b55599`) | L3 UNVERIFIABLE-AS-IS; "缺的是 Representation 能力非实验"; closure yielded a better-posed question | A closed line's yield is a **better-posed question**, not a verdict of failure |
| E3 | Repeated human declines to continue deep lines; R3-2 H-1 lesson | Necessary repeated negation ≠ over-proceduralization | Governance volume is not value; negation can be the work |
| E4 | P5 attempt-1 FAIL → INCONCLUSIVE (`78ed0d4`) | Baseline defect; claim never tested; yet produced an engine-boundary fact (KV = representation fragment) | **Construct validity**; a failed test can still reframe the model |
| E5 | P5-2 reframing (数据搬运 → 关系保持) | Goal adjustment from a negative result, continuous with the registered continuation question | Core-model revision from below is normal |
| E6 | PA-2 (`P5-4`) | Position ≠ Semantic Anchor — output follows rendered prompt text | A branch finding became load-bearing — **reflux happens, and must be legal** |
| E7 | R-C1 attempts #1–#3 invalid, #4 valid | Instrument defects → fail-closed fixes, re-audited before any claim | Instrument defects never produce scientific claims |
| E8 | Replication/Audit phase; R0 self-check | "实验结果正确 ≠ 过程真实执行了目标路径" | Evidence governance includes **provenance of the execution process** |
| E9 | Safety event: 19 commits to product repo; rollback | Venue separation violated and repaired | Research and product artifacts live under separated regimes |
| E10 | R3 family (`R3-1..R3-4`, IS-X ×2, closing `e27a7ba`) | Spec-only authorization; I≡TRUE preserved; INCONCLUSIVE permanently preserved; attempt-2 scope-locked; claim-narrowing rev.2; bounded synthesis; UB-1..7; "无反例永远带探针域" | **Claim narrowing is maintenance**; null results are evidence; freezes are bounded |
| E11 | Route S1..S4 rejected (上游倒置); Route A/B deferred (confounder) | Content refused for sequencing; probe deferred for confounder | Sequencing and confounder checks come before runs |
| E12 | Admissibility Case 2 (`f8840fd`) + ND-1 | Identifiability settled on paper; an experiment class shown impossible by construction | The decidability pre-check prevents depth compounding on undecidable questions |
| E13 | U3 (`64bbc2e`) | Instrument cannot produce the state; no manipulation invented; "做不到" = valid result | Instrument impossibility is a result; the system must not be forced to fake constructibility |
| E14 | ES-3 (`56500ad`) | M2/M3 signature-equivalent — attribution-level fork held open | Competing models are protected; observation decides only when signatures diverge |
| E15 | Core Goal evolution: state → P6 relation closure (MLX-bounded) → Boundary Synthesis embedding → R0 adoption → 2026-09-27 product redirect → ES↔IS loop | The Core Goal changed legitimately, each time with registered lineage | Goal/model revision is **normal and must be legalized**, with lineage; freezes are bounded |
| E16 | Palace F-8 ("会存不会取"); "信任不随信息保存传递" | A side-study exposed storage ≠ retrieval | System-level lessons often arrive from side studies — divergence has epistemic value |
| E17 | Core Reference Scenario test (`e97f5e7`) | The scenario mapping set aside the locality axis by rule, within one session | Drift can be caught by **mechanism** |

---

## 2. Research epistemology

**E-A. A research line produces evidence, not narratives.** Its products are claims with boundings, better-posed questions, and (occasionally) capabilities. Anything else it accumulates — depth, elegance, internal consistency — is fuel, not product. (E1, E2, E10)

**E-B. Every closure must pay in a recognizable currency — and the currency list is a floor, not a ceiling.** A line's primary value outputs are classifiable into three: **claims with boundings, better-posed questions, and capabilities**. This is a *minimal value-accounting framework*, deliberately not an exhaustive ontology: the lineage also repeatedly produced **reusable research structure** — instruments, evaluators, fixtures, trace protocols, relation mappings, transferable analysis methods — which may in the end reduce to one of the three but is recognized as a product class of its own. Governance must not be narrower than the evidence it governs. T3 paid in questions; U3 in a boundary fact; P5-attempt-1 in a reframing; R3 in a bounded characterization plus registered open boundaries; the R3-2/R3-3 harnesses and evaluators paid in reusable structure. (E2, E4, E13, E10)

**E-C. Non-identifiability and null results are first-class outcomes.** Case 2, R3-3's 10/10 holds, IS-X's anti-sliding clause, ES-3's signature-equivalence — ruling things out or undecidable was repeatedly the most consequential work. Governance must never score these below "positive" results. (E12, E14)

**E-D. Claim narrowing is maintenance, not retreat.** A healthy line continuously shrinks its claims toward what the evidence holds (rev.2 lineage; I≡TRUE preserved rather than complicated). A claim that never narrows under pressure is the anomaly. (E10, E3)

**E-E. Models compete; evidence decides only what it can.** The lineage has held competing models open across sessions (Structure A/B; M2/M3; I1/I2/I3): sometimes observation decides (R3's differential sensitivity), sometimes only attribution differs and the fork must be held (ES-3). Forcing closure on an attribution-level fork is a governance error. (E14, E12)

**E-F. Instrument truth and claim truth are different registers.** An implementation defect produces INCONCLUSIVE, never refutation; a successful run proves only the claim it instantiated; the authenticity of the execution process is itself evidence. (E4, E7, E8, E10)

## 3. Evidence governance

**V-1 — Bounding-carrying citation.** Every sealed result carries its bounding, and every citation must carry it forward. Mechanically checkable at citation time — the OFF-MAINLINE regime worked because of this. Drift's first signature is a bounding silently dropped. (E1)

**V-2 — Periodic grade accounting.** The map of "established vs. assumed" is re-audited at each synthesis gate. Evidence-grade inflation is the second drift signature; it triggered the only full line reset in the lineage. (E1)

**V-3 — Construct validity.** A run tests exactly the claim it was designed and instrumented to test. Claims must be stated precisely enough that "was it tested?" is checkable; re-judgment from FAIL to INCONCLUSIVE when the claim was never instantiated is mandatory. (E4, E10)

**V-4 — Instrument/claim separation, with preservation.** Instrument defects invalidate the run, not the hypothesis; INCONCLUSIVE verdicts are permanent even after root-cause is known (undoing a pre-registered exit rule post hoc would corrupt the exit-rule institution); all data is preserved and never silently reorganized into conclusions. (E7, E10)

**V-5 — Process authenticity and venue separation.** "The result is correct" and "the target process actually executed" are separate checkpoints; execution provenance (commits, hashes, traces, audits) is part of the evidence; research and product artifacts live under separated regimes. (E8, E9)

**V-6 — Differentiated distillation obligations.** Every substantive closure or invalidation must distill what was learned; a pause must record why continuation is currently not warranted, and what would reopen it.

```text
Closure      → better question / claim / capability
Invalidation → boundary / corrected interpretation
Pause        → why not continue + reopening conditions
```

The pause obligation is deliberately weaker than the closure obligation: compelling every pause to manufacture a fresh "better question" would produce exactly the inflation governance exists to prevent. (E2, E4, E5, E13)

## 4. Route governance

**R-1 — Two axes: Track and Satellite state.** Research status and satellite condition are different dimensions, recorded separately:

```text
Track:            CORE / SATELLITE                     (research status)
Satellite state:  SUPPORTING / EXPLORATORY / PAUSED    (condition within the satellite track)
```

CORE-track lines carry no satellite state. SATELLITE-track lines carry exactly one:

```text
Admissibility   Track = SATELLITE   State = PAUSED      (closed loop complete)
F phenomenon    Track = SATELLITE   State = SUPPORTING  (directly supports Core)
```

Transitions: **promotion** = SATELLITE → CORE, only via a reflux ground (R-3); **demotion** = CORE → SATELLITE (graceful; work preserved with boundings); satellite-state changes (SUPPORTING ↔ EXPLORATORY ↔ PAUSED) are ordinary governance moves requiring no reflux proof. A special flag exists for **competing models**: two models may both hold Core-adjacent status while a fork is genuinely open (M2/M3).

**R-2 — Depth stop conditions.** A line's depth is governed neither by "how deep" nor by "whether it relates to Core", but by four questions, assessed **at synthesis gates, never by the line itself**:

```text
1. Is it still producing new evidence (not re-confirming)?
2. Is it narrowing an important uncertainty?
3. Is it producing transferable structure?
4. Or is it only refining a local distinction that cannot affect the system model?
```

If (4) alone holds → downgrade or pause. The line is the worst judge of its own recursion; the judgment is externalized. (E1)

**R-3 — Reflux channels, and the identity rule.** A satellite re-enters Core when it demonstrably does any of:

```text
a. exposes a necessary condition of the core model        (PA-2 — E6)
b. provides a key counterexample or impossibility result   (Case 2/U3 — E12, E13)
c. discovers a new realistic implementation path           (carrier findings — E4)
d. changes the current model itself                        (Boundary Synthesis — E15)
e. establishes a key State ↔ Information relation          (R-adm elevation)
```

And the identity rule, formal:

> **Repatriation changes research status, never retroactively changes the evidentiary identity of the work.**

If satellite work from years past becomes Core, the record must forever read *"A was Satellite then; evidence later brought it into Core"* — never *"A was Core's foundation all along."* The lineage already observes this (PA-2 was a branch finding before it was load-bearing); the rule makes the practice mandatory. **偏离不是失败。** (E6, E15, E16)

**R-4 — Decidability pre-check.** Before any experiment whose purpose is discrimination between models, the identifiability question is settled on paper: what observation, under each model, is *necessitated*? If neither side necessitates anything, the experiment is shown impossible — and that showing is itself the result. Among the lineage's most expensive compressed lessons; transferable to any project. (E12)

**R-5 — Sequencing and confounder discipline.** Route selections that invert upstream dependencies are rejected without content review; a proposed discrimination with an identified confounder is deferred, not run. (E11)

**R-6 — Anti-beautification.** When evidence is compatible with a simple (even trivial) form of a concept, the simple form is preserved; complexity is never added to make a result more interesting. What would *not* be surprising is pre-registered, so surprise cannot be manufactured post hoc. (E10)

**R-7 — Protected exploration window, evidence-milestone-based.** A new line enters a protected window at creation. The window ends not at a fixed time — no day, session, or commit quotas — but at the line's **first evidence milestone**: the point at which there is evidence sufficient to evaluate the line at all.

```text
line entry → protected exploration → first evidence milestone → first synthesis review
```

Before the milestone, the governance questions of R-2 and G-5 must not be applied as admission vetoes or worthiness judgments — divergence, competing models, and unproven value are the expected condition. After the milestone, ordinary governance applies. The milestone form prevents both failure modes at once: premature killing of immature directions, and indefinite shelter in "still exploring."

## 5. Goal governance (Frame / Model)

**G-1 — Frame / Model distinction (HR-1 resolution).** The vocabulary is four-layered, and every revision must state the layer at which it occurs:

```text
Frame   研究参照系 — the persistent-computing-system question (the closure loop)
        NOT arbitrarily changeable; the invariant governance steers by
Model   the current scientific model under the frame (e.g., ES ↔ IS coupled system)
        revisable by evidence, with lineage
Claim   e.g., F is necessary under fixture X — bounded, falsifiable
Evidence bounded observation — carries its own bounding forward
```

What is unalterable is the **Frame**; what evidence revises is the **Model** (and below). Thus `old model → evidence → revised model` is fully legal, while arbitrary rewrite of the frame is not. Interpretive note, binding for the relationship to v1.0: **v1.0 Article 1's "North Star unalterable" is read at Frame level** — no amendment to v1.0 is required, and v0.1's G-1 is hereby made precise rather than rejected.

**G-2 — Model revision, with lineage.** If accumulated satellite evidence shows the current **model** inaccurate, the model is formally revised:

```text
old model → evidence → reason for revision → revised model
```

registered in git. Retroactive reinterpretation is prohibited: past claims are cited at their original grades and boundings, never rewritten to flatter the present model — and by the R-3 identity rule, a line's track history is likewise never rewritten. The lineage already exercised this right legitimately (E15); making revision cheap in dignity terms removes the incentive to defend an outdated model for narrative consistency.

**G-3 — Domain separation of promotion forces.** Experimental success, conceptual elegance, and engineering maturity are three different currencies, and none alone promotes a theory: a beautiful spec does not make a model Core; a clean experiment proves only its instantiated claim (V-3); a mature runtime proves feasibility, not truth. Symmetrically, one failed experiment does not demote the model, and one instrument defeat does not refute a concept. (E4, E7, E10)

**G-4 — Bounded freezes.** Every freeze/seal is a *local* commitment carrying explicit non-universality bounding and registered reopeners (P6: MLX-based, OP-6 open; R3: fixture-slice, UB-1..7). "Sealed" always means "sealed under these conditions." A freeze that cannot state its own reopening conditions is not a freeze but an evasion. (E10, E15)

**G-5 — Periodic synthesis gate.** After every line closure — and in any case at regular intervals or when unrefluxed satellite mass accumulates — a synthesis gate answers five questions, in this order:

```text
1. 我们现在对总体系统理解比上一轮多了什么？
2. 哪些旁支真正回流到了 Core？
3. Current model 是否仍然成立 — as hypothesis?
4. 目前最大的现实缺口是什么？
5. 下一步研究哪一个缺口，而不是哪一个问題最有趣。
```

The gate produces a **gap map, never an automatic work assignment** — governance must not become a task generator that walks the agent away from exploration. The gate is also where R-2's stop conditions are assessed and V-2's grade audit runs: one instrument, three functions.

## 5A. Governance is an instrument (anti-recursion)

> **Governance is an instrument of research, not by default a research object.**

The lineage's deepest lesson — local depth losing contact with the whole — applies to governance with special force: a governance meta-model ("what is a good synthesis?", "what is a good gate?", "the decidability of governance itself") is exactly the shape of a beautiful, self-enclosed branch. Therefore governance mechanisms are built, used, and repaired; they become a research object **only when real research continuously exposes failures in the mechanisms themselves** — and even then under the same Track/state discipline as any other line.

## 6. The cycle, and the two guarantees

The constitution institutionalizes one cycle:

```text
允许探索 → 累积证据 → 形成结构 → 回归整体 → 必要时修正整体
```

Exploration is protected (R-7, R-1); evidence is governed (V-1..V-6); structure forms under claim-narrowing and model competition (E-D, E-E); return is forced by synthesis gates and closure-currency obligations (G-5, E-B); revision is legal, lineage-bound, and cheap (G-2, G-4).

### Guarantee 1 — How can SimiGo go deep locally without being permanently lost locally?

**By making lostness a detectable state instead of a forbidden one.** Every serious drift in the lineage was preceded by detectable signatures: evidence-grade inflation (E1), bounding dropped in citation, a line unable to state what it would cash out at closure, deepening on a question no experiment could decide (E12), recursion on a distinction that cannot affect the system model. The constitution does not prevent anyone from going deep anywhere — it installs four trip-wires under the depth:

1. **bounding-carrying citation** (V-1) — drift shows up as a bounding violation, mechanically checkable;
2. **grade accounting** (V-2) — drift shows up as grade inflation at audit;
3. **closure-currency obligation** (E-B/V-6) — every line must pay capability, a better question, a corrected model, or reusable structure; inability to pay makes lostness *visible at closure* even if invisible during work;
4. **synthesis gates with gap-first ordering** (G-5) — the rudder: the next step is chosen by the gap map, not by local gravity; and the decidability pre-check (R-4) prevents the deepest loss — compounding depth on an undecidable question.

None of these requires Human vigilance to notice yaw; each converts yaw into an inspectable signal. "深入局部，但不会永久迷失在局部" does not mean depth is bounded — it means **being lost is engineered to be discoverable**, and history (E17) shows the trip-wires fire.

### Guarantee 2 — How can we prevent deviation-avoidance from prematurely freezing an immature overall goal?

**By freezing the frame, bounding every seal, and making model revision legal and cheap.** Five asymmetries:

1. **The invariant is the frame, not any model.** What governance steers by is thinner than any theory of it; every model beneath the frame is registered as revisable hypothesis. Premature freezing of the frame cannot happen because the frame makes almost no claim.
2. **Every freeze is bounded** (G-4): "sealed" always carries its conditions and reopeners — a pause in tension, not a tombstone. All lineage freezes (P6, R3) had this form, and their reopeners remain live.
3. **No single event moves the model** (G-3): domain separation means neither a triumph nor a disaster in one register can unilaterally rewrite it — revision requires *accumulated* evidence.
4. **Competing models are protected** (E-E, R-1): where observation cannot yet decide, forks are held open (ES-3) rather than forced into a choice that would feel like progress.
5. **Revision writes lineage forward** (G-2, R-3): old model → evidence → reason → revised model, with retroactive reinterpretation prohibited in both directions — past claims are never re-graded, and past track status is never rewritten. Because revising is dignified and recorded, there is no incentive to defend an outdated model for narrative consistency — the actual historical cause of premature freezing.

And the deepest protection is historical: the lineage *has* already revised its models legitimately and repeatedly (E15). The Frame/Model vocabulary applies from v0.2 forward and is not retroactively reclassified; what this constitution legalizes is what the lineage already did well, so future revisions carry the same legitimacy without depending on the same luck.

## 7. Human Review disposition (v0.1 items) and what remains open

| Item | Disposition |
|---|---|
| HR-1 North Star alterability | **Resolved by layering** — G-1 Frame/Model distinction; v1.0 untouched, interpreted at Frame level |
| HR-2 state taxonomy | **Resolved by two axes** — R-1: Track × Satellite state |
| HR-3 synthesis-gate cadence (K) | **Open** — deliberately unspecified |
| HR-4 stop-condition assessor | **Open** — the proposal stands (synthesis gate, never the line itself) |
| HR-5 protected window | **Resolved** — R-7 evidence-milestone-based, no time quota |
| HR-6 relationship to v1.0 | **Partially resolved** — v1.0 untouched; the distinction lives here; formal adoption and application to existing lines require an explicit Human ruling |

## 8. Registered future direction (not implemented)

Evolution into a **generic Research Governance Framework** (evidence governance / exploratory governance / synthesis / model revision / lineage) plus a **SimiGo Project Research Charter** (North Star, Core Research Map, current models, current lines, project-specific gates). The frame to aim at:

> SimiGo does not own a private governance rulebook — **SimiGo is the first validated instance of a transferable research governance framework.**

Not built in v0.2, per the six-item restraint.

**Non-claims**: this document proves nothing about Execution State or Information Space; seals nothing; authorizes no experiment; reopens no frozen line; retroactively re-grades nothing; applies the Frame/Model vocabulary forward only; and claims no research-object status for itself (§5A).
