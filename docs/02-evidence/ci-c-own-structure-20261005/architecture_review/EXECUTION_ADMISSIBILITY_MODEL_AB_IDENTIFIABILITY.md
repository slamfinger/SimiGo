# Execution Admissibility — Model A/B Identifiability Analysis v0.1

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `IDENTIFIABILITY ANALYSIS · CONCEPTUAL/ANALYTIC · NO_NEW_CLAIM · NO_EXPERIMENT · SEALED 2026-10-05 (Human Review — Case 2 verdict accepted; sealed at identifiability level)`
Predecessor: `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.2.md` (`5f8bf23`) — whose §8 deferred discriminating-experiment design until review
Directive: Human review of `RESEARCH_LOG.md` + Spec v0.2 (2026-10-05) directed that Model A/B identifiability be settled **before** any discriminating experiment is designed. No code, no experiments, no new data.
Evidence added: none. Claim status change: none. Experiment authorization: none.

---

## 0. Purpose

Spec v0.2 closed with: *"Human Review → decide whether to design Model A vs B discriminating experiment."*

This note answers the prior question that decision depends on: **does a discriminating experiment exist?**

Per Human direction, it answers exactly three questions:

- **Q-I.** What observation or intervention *necessarily* yields result R under Model A?
- **Q-II.** Does the same observation or intervention *necessarily* yield a different result under Model B?
- **Q-III.** If no such intervention exists, are A and B observationally equivalent?

and lands an explicit verdict in exactly one of:

- **Case 1** — A/B identifiable → design formal discriminating experiment → Human Review → execute.
- **Case 2** — A/B not identifiable → no pseudo-experiment → Model B retained as productive hypothesis → seek higher-order structural evidence.

Method note: identifiability is a property of a (model pair, observable space) pair, decidable analytically once both are precisely stated. This note is that decision made on paper — which is why it precedes any experiment.

## 1. Model statements (exactly as fixed by v0.2 — no semantic change)

**Model A — Result label** (v0.2 §1):

```text
Admissibility(T) = true | false
```

A **property assignment** to a transition. Conditions are inputs to *whatever process* computes the property; the property itself is **atomic — it does not have parts**. Its load-bearing commitments: atomicity, two-valuedness, computation by an unspecified mechanism.

**Model B — Necessary condition structure** (v0.2 §1, with §2/§6 refinements):

```text
Admissible(T) ⟺ C₁ ∧ C₂ ∧ … ∧ Cₙ        (C₁ = X_eligible, C₂ = F_available, …)
Admissibility(T | context) ∈ { true, false, unevaluable }
```

Its load-bearing commitments: (B1) evaluation prior to and independent of the transition manifesting; (B2) conjunctive composition; (B3) each conjunct necessary — single failure ⇒ not admissible regardless of anything else; (B4) three-state evaluation, with `unevaluable` grounded in 846 K3-DELETED and distinct from `false`.

Note the asymmetry already visible at the statement level: v0.2 §4 ties the three-state extension to Model B ("*If* Admissibility has a necessary-condition structure, then `unevaluable` is a third state"). Model A as stated is two-valued and must absorb the K3-DELETED outcome as outside its domain (no assignment made), not as a value.

**Shared observable space O** — everything this line has observed or can observe under current authorization:

```text
O = { input manipulations (X, F variants; authorization states; 846 structural deletions),
      transition outcome class (COMPLETED / DEGRADED / BLOCKED / C4-absent),
      emitted signals and adoption behavior }
```

All nine established findings in `RESEARCH_LOG.md` live inside O.

**Spec gap registered (prerequisite, not criticism):** v0.2 defines whole-construct three-state output and per-condition evaluation, but does **not** define **mixed-state propagation** — what Admissibility outputs when conditions are in *different* states (e.g., X `false` + F `unevaluable`). Until this is fixed, Model B necessitates outcomes only for single-failure and all-satisfied configurations — precisely the configurations where its necessitations are already confirmed and shared with A. **The currently specified part of B has, as yet, no discriminative surface by construction.**

## 2. Why the existing evidence cannot decide — v0.2 §8 examined

v0.2 §8 sketches two future experiment shapes. Both fail the two-sided necessitation test (Q-I + Q-II):

**Shape 1** — find D with D-absent → BLOCKED, and D-present + X- + F-absent → still BLOCKED. v0.2 itself labels this only "**consistent with Model B**". It is equally consistent with Model A (a third input to the atomic evaluator whose absence produces BLOCKED). Registered as:

> **ND-1 (non-discriminator).** Establishing a further condition D (semantic role specific to T; absence → BLOCKED; semantically specific; replicated; not generic validation) carries **zero weight** for conjunction structure. Under B it is a new conjunct; under A it is a new input. It counts toward Q8 only — never as evidence that Admissibility *has* conjunctive structure, and never as evidence for Model A either. A "third necessary condition" finding must never be recorded as a Model A/B discrimination result.

**Shape 2** — D-present + X- → a different outcome than X- alone (interaction). v0.2 labels this "more complex than a simple conjunction" — i.e., it is evidence **against B-as-stated**, not evidence for A: Model A, which commits to nothing about the evaluator's input structure, absorbs interactions as easily as their absence. Shape 2 discriminates B from a *third*, unstated structured model; it never discriminates B from A.

The same accounting applies to every finding already in hand (X- → BLOCKED; F-absent → BLOCKED; J4 no extra interaction; F-STALE → DEGRADED not BLOCKED; K3-DELETED → unevaluable): each is B-consistent and A-compatible. None necessitates anything under A.

## 3. The three questions

### Q-I — What does Model A necessitate?

**Nothing over O.** Model A's mechanism is specified only as "*whatever process* computes this property". An unconstrained mechanism is compatible with every input→outcome mapping: whatever the system does, the atomic-label description applies to it. Model A therefore entails **zero constraints on outcomes** — there is no R that any intervention necessitates under A.

### Q-II — Does any intervention split A and B?

**No — and none can exist.** Discrimination requires *both* models to necessitate (R under A, a different R′ under B for the same intervention). Q-I shows A necessitates nothing, so Q-II's premise is unsatisfiable — **by construction, not by an evidence gap**. No additional probe of the existing kind (more conditions, more removals, more combinations inside O) can change this: such probes vary inputs, and Model A is defined precisely so that no input→outcome pattern touches it.

### Q-III — Are A and B observationally equivalent?

**Yes — relative to O and to Model A as stated, and the equivalence is structural.**

The epistemic form deserves precise statement: since A entails no outcome constraints, no observation can count *for or against* A; differential confirmation of B **over A** is unavailable in principle. What remains asymmetric is only the other direction: B *can* fail (B entails single-failure ⇒ BLOCKED; a counterinstance would falsify it). All empirical work available to this line is therefore **B-testing; none of it is A-exclusion.**

Two scope qualifiers, registered honestly:

1. **Relativity to O.** The verdict holds over the observable space this line currently has. If evaluation leaves traces in some *new* observable class — a dissociation between an evaluation-side signal and the transition outcome — the identifiability question would have to be re-posed on a wider O. (Q6 — C `emitted: true` + `transition_status: BLOCKED` — is the one existing observation that would belong to such a class; it remains **unresolved and untouched** here, registered only by relevance class, not interpreted.) Nothing in this note predicts that such traces exist or are accessible.
2. **Relativity to Model A as stated.** A *strengthened* A — one whose evaluator commits to some input→outcome structure — would be testable. But every strengthening is a new model choice, and each gives A exactly the kind of internal structure (a structured evaluator over conditions) that is B's ontology. The A/B dichotomy as posed does not survive being made empirical: it dissolves into "which *structured* model" — of which B is, so far, the only one stated.

## 4. Where Model B's empirical content actually lives

Since B cannot be confirmed against A, its scientific value must come from its **own falsifiable commitments**. Three are load-bearing:

1. **No-rescue necessity (B3).** Precise form: a *rescue intervention* = a manipulation of inputs **other than** the failed condition's own restoration, which changes the outcome from BLOCKED to not-BLOCKED while the condition remains unsatisfied. B entails: **no rescue intervention exists for any established condition** (a false conjunct forces ¬Admissible regardless of all else). A rescue-success on X or F would force reclassification of that condition or revision of B — a genuine cost, since X and F's condition status is frozen, so this is a real B-risk, not a tautology. No-rescue *success* is B-consistent evidence (and A-neutral, per §2). Untested to date: the probe matrix varied only X and F; no compensation cell exists.
2. **Three-state semantics completion (B4).** The mixed-state propagation gap (§1) must be fixed at the spec level before any mixed-configuration test is even stateable. Once fixed, B necessitates a specific output class per configuration — including differential behavior of `false` vs `unevaluable` under repair-of-evaluator vs repair-of-condition manipulations. Failures there are B-failures. This is **conceptual work (a v0.3 candidate), not an experiment.**
3. **Uniformity across conditions.** B claims its conditions live in one evaluation framework with uniform three-state semantics. Q8 work (hunting additional conditions) tests this uniformity: a factor that behaves heterogeneously (sometimes blocks, sometimes degrades; sometimes evaluable, sometimes not) stresses B. Under this re-scoping, **Q8 becomes B-testing, not A/B discrimination** — which is why the Human priority order survives this verdict intact.

The practical consequence: the research question changes from *"A or B?"* (unanswerable as posed) to *"what does B predict that could fail?"*

## 5. Verdict

**Case 2.**

Model A and Model B, as stated in v0.2, are **observationally equivalent over O — structurally, by construction**. A Model A/B discriminating experiment, as posed, does not exist and must not be run. Model B is retained as a **productive hypothesis**: an explanatory model whose *interpretation* (conjunction structure) is not currently a falsifiable empirical claim, but whose *specific commitments* (§4.1–4.3) are.

This is not a negative result about Admissibility; it is a negative result about a planned experiment class. Per the Human decision frame, it prevents pseudo-experiments and redirects effort to where B's content actually is.

## 6. Consequences and next-step candidates (nothing auto-opens)

Consequences, effective upon Human seal of this note:

- No discriminating experiment; no "third condition" probe may be recorded as conjunction-structure evidence (ND-1 stands).
- Model B stays as the working interpretation, in the epistemic slot **productive hypothesis / explanatory model**.

Candidates for Human Review — listed only, no selection made here:

| # | Candidate | Type | Note |
|---|---|---|---|
| 1 | **Spec v0.3**: complete B's mixed-state propagation semantics | Conceptual only, no experiment | Precondition for making §4.2 stateable; smallest concrete next step |
| 2 | **Re-scoped Multiple Necessary Conditions Probe** | Experiment, design-gated | Explicitly framed as B-uniformity testing under ND-1; never as conjunction confirmation |
| 3 | **Evaluation-signature question**: does evaluation leave observable traces distinct from outcomes? | New open question | Would re-pose identifiability on a wider O; highest risk/reward; a null answer would itself strengthen the explanatory-model reading |

## 7. Open-question priority (registered from Human direction)

Q2 (settled here, pending seal) > Q8 (re-scoped per §4.3) > Q3/Q4 (conjunct vs evaluation-precondition for E and 846).

Unchanged: Q6 stays unresolved; Q7 (F-CONFLICTING) stays uninterpreted; Q5 (layered eligibility) stays closed. No frozen phase reopened.

## 8. Boundaries, reopeners, non-claims

**Boundaries reaffirmed** — all hard boundaries from `RESEARCH_LOG.md` remain in force (no 846 atom mapping/reinterpretation; no Observer; no InformationCore write; no minimal Information Core claim; no A/B/D retry; no experiment without Human Review; no formalizing "admissibility information"; no `Eligible(T | S, C)` extension). Nothing here reinterprets any frozen phase; §1 restates v0.2 wording only.

**What would reopen this analysis** — the verdict is exact relative to (a) the model statements of §1 and (b) the observable space O. It reopens if either changes: Model A is given a precise predictive statement (any strengthening — requires a v0.2 of this note), or a new observable class carrying possible evaluation-side traces is authorized (requires Human Review). Neither event is triggered by this note.

**Non-claims** — this note does not: prove Model B; prove Model A; interpret Q6 or Q7; reopen any frozen phase; authorize any experiment, code, or data collection; select among §6 candidates; generalize beyond models C and N or beyond the tested transition; or touch PALACE, IPAC, or the sealed ES research line.
