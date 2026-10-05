# Execution Admissibility — Evaluation Signature (Conceptual Boundary Review) v0.1

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `CONCEPTUAL BOUNDARY REVIEW · NO EXPERIMENT · NO INSTRUMENT CHANGE · NO U_c WORK · VERDICT: ES-3 (PROPOSED — concurs with Human lean) · PENDING HUMAN REVIEW`
Directive: Human ruling 2026-10-05 — **Step 3 (Evaluation-Signature) opened CONCEPTUAL ONLY**, following the U3 stop. Do not continue U_c work; do not modify the probe instrument; do not run experiments. Deliverable: this boundary review, answering four questions, landing exactly one case.
Predecessors: `MODEL_B_UNIFORMITY_PROBE_DESIGN.md` (Case U3, CONFIRMED EFFECTIVE) + `EXECUTION_ADMISSIBILITY_CONCEPTUAL_SPECIFICATION_V0.3.md` (SEALED) + `EXECUTION_ADMISSIBILITY_MODEL_AB_IDENTIFIABILITY.md` (SEALED, Case 2) + `RESEARCH_LOG.md` Addenda 1–5.
Evidence added: none. Experiment authorization: none. No sealed document is modified by this review.

---

## 0. The question and the case frame

U3 established, at instrument level:

```text
current instrument → requires a verdict per transition
                   → fail-closed convergence of missing/unreadable/conflicting
                   → no independent evaluator-side "non-completion" channel
                   → U_c not legally constructible/observable for X/F
```

This exposed the deeper question (Human, registered at the stop and re-posed here as the Step 3 entry):

> **Is `unevaluable` the third state of `Admissibility(T | context)` itself, or is it an upstream runtime phenomenon — the failure of the evaluator — that does not belong to Admissibility's object language at all?**

Pre-registered case frame (binding):

```text
ES-1  Evaluation failure stays OUTSIDE Admissibility
      → v0.3's unevaluable is repositioned/reduced
ES-2  Evaluation failure IS part of Admissibility semantics
      → three states retained; an evaluator-side observable signature must be defined
ES-3  Current evidence insufficient to decide
      → pause; no experiment designed
```

This review answers four questions in the Human's order: **(1) layering; (2) the v0.3 codomain examination; (3) the Model A re-examination (reopener check); (4) the case verdict.**

Governing discipline carried forward: sealed documents are not modified; interpretations may be examined but commitments stand until Human-authorized revision; nothing here proves Model B, refutes it, or touches Model A's excludability status.

---

## 1. Layering — are these the same layer?

The two pictures under examination:

```text
Picture I (functioning chain):           Picture II (process failure):

  Evaluator can run                        Evaluator cannot run /
      ↓                                    cannot produce determination
  condition evaluation
      ↓
  Admissibility result
      ↓
  transition execution
```

**They are not the same layer.** Picture II is not a stage *within* Picture I's chain — it is a **status of the chain's first link** (whether the evaluation process runs at all). The question the fork poses is precisely: *where does this status get booked?* — inside the "Admissibility result" node (as a third value), or on the process edge (as evaluation status, with the result node simply empty)?

v0.3's own resources already contain both bookings, and this is worth stating precisely: v0.3 is **over-complete, not inconsistent**. It introduced (a) the three-valued codomain `Admissibility ∈ {true, false, unevaluable}` (inherited from v0.2 §4/§6) and (b) the Level-0 / Level-1 process vocabulary (mechanism operability vs per-condition determinations, `U_c` as a determination-failure class). The **same facts** — 846's K3-DELETED → C4 absent; the never-observed non-completion — are entered twice: once as a property value, once as a process fact. The fork asks which entry is primitive and which is shadow. v0.3 needed both to complete the function; it did not have to choose, because its job was stateability. Step 3's job is exactly this choice.

Layering facts available (all established, none reinterpreted):

- 846's evaluator-death manifests as **absence of output** (C4 absent) — the failure is visible in the *result channel's emptiness*, before any verdict semantics applies.
- The agent line's instrument forces verdicts; every chain runs to completion (COMPLETED / DEGRADED / BLOCKED). Picture II has never been manifested in the agent line at all.
- The Level-0 / Level-1 vocabulary remains **Q3/Q4-neutral** exactly as sealed: whether E and 846 are conjuncts or evaluation preconditions is untouched by how "cannot run" is booked.

---

## 2. The v0.3 codomain examination

### 2.1 The fork, formally

Two readings of the sealed three-state structure:

```text
M3 (current v0.3 codomain — "value" reading):
    Admissibility(T | context) ∈ { true, false, unevaluable }
    unevaluable is a VALUE of the property.

M2 (two-function alternative — "gap" reading):
    Admissibility(T | context) ∈ { true, false }
    EvaluationStatus(T | context) ∈ { available, unavailable }
    When EvaluationStatus = unavailable, Admissibility has NO value —
    a truth-value gap, not a third value.
```

This is the classical distinction between a **three-valued logic** (undefined as a truth value) and a **partial function** (no value; "undefined" describes the absence). M2 is exactly the shape the Human sketched; ES-1 ≈ M2, ES-2 ≈ M3.

### 2.2 What the established material actually says

**Textual**: v0.2 §4's definition of `unevaluable` is *process-descriptive* — "the admissibility determination **cannot be completed**". The content of the third state was always a fact about the evaluation process, not about the transition. M3 books that process fact as a property value; M2 books it where it descriptively already lives.

**Observational**: the only established manifestation of non-completion is 846's C4-absent — *output absence*. M3 must add an attribution step (absence → the property took the value `unevaluable`); M2 records it directly (evaluation unavailable; no value exists). Both accommodate every established observation identically:

| Observation | M3 (value reading) | M2 (gap reading) |
|---|---|---|
| 846 K3-DELETED → C4 absent | Admissibility = unevaluable; manifests as no output | Admissibility valueless; EvaluationStatus = unavailable; manifests as no output |
| Agent-line BLOCKED | Admissibility = false | Admissibility = false (evaluation available, completed) |
| Agent-line COMPLETED / DEGRADED | true | true |
| Sealed mixed rule (D-1) | registered spec decision | near-derivable (§2.3) |
| Hypothetical future "no-verdict" evaluation-side signature | value `unevaluable` emitted | status `unavailable` emitted — **same observable** |

**Signature-equivalence (the load-bearing finding).** Within everything currently stateable — and plausibly under *any* evaluator-side-signature instrument — M2 and M3 predict the **same channel behavior**. For them to diverge observationally, some *consumer* would have to behave differently on "the admissibility slot holds the value U" vs "the admissibility slot is empty (status: unavailable)" — but any such consumer behavior reintroduces the same value-vs-gap choice at the consumer's own encoding, one level up. The fork is therefore an **attribution-level (predication) fork, not a signature-level fork**: observation can at most reveal *that* evaluation failed; it cannot decide *what the failure is predicated of*. (Registered as a conceptual analysis-claim, not an established result.)

### 2.3 Derivational economy — a virtue-tilt, honestly marked

Under M3, the sealed propagation decision D-1 (false-dominant) was a **registered spec decision**: strong-Kleene and weak-Kleene-style aggregations were both internally coherent, and v0.2 §5's "false (or unevaluable)" necessitated an explicit choice.

Under M2, the same rule is **near-derivable**: if one condition's determination is false, the conjunction's value is settled by the ordinary meaning of conjunction (no partial logic needs to be chosen), and v0.2 §4's boundary does the rest (a completed negative determination is completed — withholding the verdict because *another* determination failed would be a reporting policy, not a semantics). M3 carries a **logic-choice degree of freedom** (strong vs weak partial conjunction → D-1 vs D-1′); M2's rule follows from plain classical composition plus a verdict-withholding policy. Net: M2 stipulates less.

This is a genuine conceptual virtue favoring M2 — and it is **not evidence**. Virtue arguments have no decided status in this line's taxonomy; they justify holding a tilt, not landing a choice. Registered as tilt; not converted into a verdict.

Two further coherence notes, both non-decisive:

- v0.2 §4 tied the three-state extension to Model B ("*If* Admissibility has a necessary-condition structure, then `unevaluable` is a third state"). Under M2 that tie **dissolves**: conjunctive structure implies nothing about three-valuedness — the codomain choice was an independent modeling decision all along.
- The M2 side is **not yet fully specified**: EvaluationStatus cardinality (binary {available, unavailable} vs. a three-way {unavailable / ran-but-incomplete / complete}), the per-condition split between determination availability and determined value, and the whole-construct rule when the mechanism runs but a condition's determination fails. Choosing ES-1 today would mean adopting a structure with open representational decisions. (v0.3's sealed propagation rule covers the *observable* behavior in all these cells; what is open under M2 is the status vocabulary, not the behavior.)

### 2.4 Effect on the sealed commitment inventory (interpretation only)

The fork **reinterprets without modifying** any sealed commitment:

- C-PROP-1: testable content unchanged (X=false + F-not-determined → BLOCKED); under M2 it shifts from "stipulated" toward "derivable" — same prediction, same U3 blocker, same testability status.
- C-PROP-2: under M2 becomes near-definitional (no process → no determinations); its generalization claim stands.
- C-PROP-3, C-PROP-4: unchanged; C-PROP-4's "reporting purity" becomes natural under M2.
- D-1 itself: sealed, stands under both readings; the fork changes its *epistemic* standing (stipulated vs derivable), not its content.

No sealed document is edited. If ES-1 were ever chosen, that would be a codomain revision (a future v0.4) requiring explicit Human authorization — **not proposed here**.

---

## 3. Model A re-examination — reopener check

The identifiability note (SEALED) registered the reopener: *"a new observable class carrying possible evaluation-side traces is authorized → the identifiability question would have to be re-posed on a wider O."* Step 3's premise — evaluator-side signature as a potential observation dimension — is exactly that reopener's territory. Check executed, honestly:

**Does the reopener fire?** As an obligation to re-pose: yes, and here the re-posing is done. As a reversal of Case 2: **no — and it cannot.** Model A's zero-constraint lives in its "whatever process computes this property" clause, which is **orthogonal to any observable whatsoever**, including evaluation-side ones: a process that is specified only as "whatever" emits whatever it emits, and the atomic-label description applies afterwards. Expanding O with evaluation-signature channels adds constraints that M-structured models must satisfy; it adds none that A must satisfy. A remains excludable by nothing.

What the reopener *actually* changes is the **structured landscape**. Under a wider O, the live comparison is no longer "A vs B" but:

```text
M3  (B, three-valued codomain)          vs   M2  (two-valued + evaluation status)
      └─ both are structured models; choosing between them is NOT an A/B
         discrimination and inherits none of Case 2's blocking
```

Note the continuity: M2 is precisely the "strengthened-A" shape anticipated by the identifiability note's scope qualifier 2 — give A enough structure to predict and it acquires an evaluation-like component (a structured evaluator with a status channel). Case 2's collapse observation is thus confirmed from the constructive side: the fork populates the structured region Case 2 said would matter if A were ever strengthened.

**Therefore: Case 2 stands, unmodified and unweakened. The reopener is answered rather than triggered into reversal.** Per the standing discipline, the M3-vs-M2 choice is internal theory choice among explanatory models — decidable (if ever) by theoretical virtues and, should the signature-equivalence of §2.2 ever break, by evaluation-consumption observations; never by "proving" one of them against Model A.

---

## 4. VERDICT

**ES-3.** Current evidence is insufficient to decide between ES-1 and ES-2 — and the insufficiency is structural, not merely provisional:

1. **Signature-equivalence**: every established observation (and, on analysis, any evaluator-side-signature instrument) is accommodated identically by both readings; the fork is attribution-level.
2. **The M2 side is unspecified**: its status vocabulary and per-condition bookkeeping are open; adopting ES-1 now means choosing an incomplete structure.
3. **Virtues are not evidence**: the derivational-economy tilt favors M2, and v0.2 §4's three-state-to-Model-B tie dissolves under M2 — but converting a tilt into a codomain revision without either observational divergence or a completed M2 specification would repeat exactly the move this line's discipline exists to prevent.
4. v0.3's codomain was chosen (inherited from v0.2) **for theoretical completeness under a question that had not yet been asked**. That is a reason to hold the question open, not to answer it in either direction now.

This concurs with the Human's stated lean. **Pause: no experiment, no instrument change, no spec revision.** The deeper question registered at the Step-2 stop — *does evaluation failure belong to Admissibility's object language or to runtime failure outside it?* — is now formally posed, with ES-1 and ES-2 as its two answers and ES-3 as its current status.

### What would decide the fork (registered, not pursued)

- **D-SIG-1 (evaluation-consumption divergence)**: any observation in which system behavior differs depending on whether a non-verdict evaluation event is *consumed as an admissibility value* or *as an evaluation status* — the one class that could break §2.2's signature-equivalence. This is the true "evaluation-signature" observation this Step is named for.
- **D-SIG-2 (Q1 resolution)**: condition-level modularity resolved would firm up per-condition determinations as isolable occurrences — a precondition for any per-condition version of the fork.
- **D-SIG-3 (M2 completion)**: a finished M2 specification would at least make the virtue comparison exhaustive; it would still not, by itself, constitute evidence.

None of the three is opened, designed, or scheduled by this document.

---

## 5. Boundary accounting

| Standing item | Status after this review |
|---|---|
| Case 2 (identifiability, SEALED) | **Stands unmodified** — reopener checked, answered, not fired into reversal |
| v0.3 (SEALED) | **Stands** — codomain, D-1, C-PROP-1..4 unchanged; fork operates at interpretation layer only |
| U3 / Step 2 STOPPED | **Untouched** — no U_c work resumed, no instrument modified |
| ND-1 | In force — nothing here is conjunction-structure evidence |
| Q3/Q4 | Untouched — Level-0/Level-1 vocabulary remains placement-neutral |
| Q6 / Q7 / Q5 | Untouched |
| Hard boundaries (RESEARCH_LOG) | All in force |

**Non-claims**: this review does not prove, refute, or revise Model B or M3; does not adopt M2; does not reinterpret 846 or any frozen finding; does not authorize any experiment, instrument change, code, or data collection; does not claim `unevaluable` "does not exist" (instrument-relative lessons of U3 carried over: nothing here is an ontology claim); does not reopen any sealed document or frozen phase. Its sole deliverable is the four answers above and the ES-3 hold.
