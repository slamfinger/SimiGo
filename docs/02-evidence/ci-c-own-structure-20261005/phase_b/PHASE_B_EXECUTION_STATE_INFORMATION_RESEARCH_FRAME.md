# Phase B: Execution State + Information Research Frame

Date: 2026-10-05
Status: `FRAME_PROPOSED · NOT_FROZEN · NO_EXPERIMENT_AUTHORIZED`
Predecessor: Phase A (Authorization, closed at `ea537cc`)
Relationship to Phase A: independent research question. Phase A results are not used to interpret Phase B outcomes and vice versa.

---

## 1. Research question

> Does a specific class of Information function as a **constitutive condition** for a specific Execution State transition, rather than as an external input or an attached metadata field?

In other words: is there a type of Information without which certain Execution States are not executable states at all, rather than merely states that produce degraded or stale output?

---

## 2. Competing hypotheses

| Hypothesis | Statement | If true, the implication is |
|---|---|---|
| **H1** | Information is an **external input** to Execution State. ES does not depend on Information; it executes regardless. | Execution State is self-contained. Information affects output quality but not state executability. |
| **H2** | Information is **attached state** to Execution State. ES can execute, but Information determines persistence, recoverability, or consistency over time. | Execution State + Information is a runtime + metadata pairing. Removing Information degrades durability but does not make the state unexecutable. |
| **H3** | Information is a **constitutive condition** of Execution State. Without meeting an Information condition, certain Execution State transitions do not constitute executable states at all. | Execution State is not a runtime artifact alone; it is a **state + information relation**. Removing the required Information collapses the state's executability, not just its output quality. |

**Working bias: H3 is the most theoretically interesting and most product-architecture-relevant hypothesis.** But this frame is designed to distinguish all three, not to confirm H3.

---

## 3. Operational definition of Information

For the minimal experiment, Information is operationalized as a single **information object `F`** that a given Execution State transition requires or does not require.

`F` is not PALACE, not MCP, not Memory, not RAG, not a remote API. It is a minimal, self-contained object placed in or removed from the prompt context.

Four conditions:

| Condition | Meaning |
|---|---|
| `F-present` | F is visible, current, and consistent. |
| `F-absent` | F is not present in the context at all. |
| `F-stale` | F is present but its values are outdated relative to a known correct state. |
| `F-conflicting` | F is present, current, but contradicts another visible fact that the Execution State also depends on. |

`F` remains the **same semantic object** across all four conditions. Only its presence, currency, or consistency changes.

---

## 4. Observable execution outcome

The Execution State under test is a **transition** from a defined source state to a defined target state. The model is asked to perform or authorize this transition.

Observable outcomes:

| Field | Meaning |
|---|---|
| `transition_attempted` | Did the model attempt to perform the transition? |
| `transition_completed` | Did the model produce the target state? |
| `transition_blocked` | Did the model explicitly refuse or halt the transition? |
| `transition_degraded` | Did the model complete the transition with visibly incorrect or stale output? |
| `information_dependency_declared` | Did the model explicitly name F (or its absence/staleness/conflict) as a reason for its action? |

The primary contrast is between:

```text
transition_completed + information_dependency_declared
    versus
transition_blocked + information_dependency_declared
    versus
transition_degraded + information_dependency_declared = false
```

If H1 is true: all four F conditions produce `transition_completed`. Information affects output content but not state executability.

If H2 is true: all four F conditions produce `transition_completed`, but `transition_degraded` appears in `F-stale` and `F-conflicting`. Information affects quality but not executability.

If H3 is true: at least one F condition produces `transition_blocked` (not merely degraded) with `information_dependency_declared = true`. The state is not executable without the required Information.

---

## 5. Minimal candidate design

### Option A: 2 × 2 (minimum)

| | F-present | F-absent |
|---|---|---|
| Execution State S1 → S2 | cell 1 | cell 2 |
| Control state (no transition) | cell 3 | cell 4 |

This is the minimum to distinguish H1 from H3. H2 requires at least one additional condition.

### Option B: 2 × 4 (recommended)

| | F-present | F-absent | F-stale | F-conflicting |
|---|---|---|---|---|
| Execution State S1 → S2 | cell 1 | cell 2 | cell 3 | cell 4 |

Plus one no-transition control row if needed to separate "state is unexecutable" from "model refuses all action in this context."

Total: 4–8 cells. Models: C + N only (same as Phase A). No other models.

---

## 6. Explicit non-goals

This frame explicitly excludes:

1. PALACE / MCP / Memory / RAG / remote API / Agent / InformationCore / Observer — none are introduced.
2. 846 mapping — not touched.
3. Mechanistic probes — different research layer.
4. Multi-step or long-horizon execution — a single transition is sufficient.
5. Cross-template robustness — one template, varied only on F condition.
6. Model extension beyond C + N.

---

## 7. Falsification criteria

### H3 is falsified if:

```text
All four F conditions produce transition_completed.
No condition produces transition_blocked with information_dependency_declared = true.
```

Then Information is not a constitutive condition for this Execution State transition; it is at most H1 (external input) or H2 (attached state).

### H3 is supported if:

```text
At least one F condition produces transition_blocked (not merely degraded).
information_dependency_declared = true for that condition.
The same transition completes in F-present.
```

And this pattern replicates on both C and N.

### Ambiguous zone

If `F-stale` produces `transition_degraded` but not `transition_blocked`, the result supports H2 (attached state) rather than H3 (constitutive condition). The distinction between "wrong output" and "state does not constitute an executable transition" is the critical boundary.

---

## 8. Boundary inheritance from Phase A

Phase A established behavioral ordered separation of `A_epistemic` and `A_execution`. Phase B does not build on that result directly. The two phases address different research questions:

```text
Phase A: Does authorization have two behaviorally separable layers?
Phase B: Does Information constitute a condition for Execution State executability?
```

Phase B results must not be used to reinterpret Phase A, and Phase A results must not be used to presuppose Phase B outcomes.

---

## 9. Proposed next gate

1. Human Review of this frame.
2. If approved: freeze the frame, design the minimal experiment.
3. If approved: run the experiment (C + N only).
4. Falsification review.
5. Claim status update.
