# Phase B Evidence Boundary

Date: 2026-10-05
Status: `EVIDENCE_BOUNDARY_FROZEN · AWAITING_HUMAN_REVIEW`
Terminal commit: `d2c821a`

---

## 1. Frozen claim map

| Information condition | Observed behavior (C/N) | Claim status | Semantic role |
|---|---|---|---|
| F-PRESENT | executable (C: COMPLETED; N: DEGRADED label, correct decision) | baseline | sufficient |
| **F-ABSENT** | **BLOCKED + dependency_declared (both C, N)** | **STRONG / REPLICATED** | **execution prerequisite** |
| F-STALE | executable, output incorrect (both C, N deploy gamma) | **H2-LIKE / REPLICATED** | quality condition |
| F-CONFLICTING | C: COMPLETED; N: BLOCKED + dep=true | **UNRESOLVED / DIVERGENT** | model-dependent |
| F-IRRELEVANT | executable, irrelevant info ignored (both) | **CONTROL PASSED** | non-condition |

---

## 2. H3 status

```text
H3 (Information = constitutive condition of Execution State)
    ↓
GENERAL H3: NOT ESTABLISHED
    ↓
F-ABSENT SPECIFIC: CANDIDATE EVIDENCE / REPLICATED
    ↓
F-STALE SPECIFIC: NOT SUPPORTED (H2-like)
    ↓
F-CONFLICTING SPECIFIC: UNRESOLVED (C/N divergent)
```

Maximum claimable from this run:

> For the tested transition, absence of decision-relevant Information F reproducibly changes execution eligibility from executable to blocked in both C and N, with explicit dependency declaration.

NOT claimable:
- Information is constitutive of Execution State in general
- All Information validity dimensions share the same relationship to execution
- Mechanistic proof of Information-state dependency

---

## 3. Primary rival explanation (must be addressed before upgrading H3)

### Rival: generic missing-field validation

The strongest rival explanation for `F-ABSENT → BLOCKED` is:

> The model applies a generic "required field is missing" rule. Any absent field that the prompt names as necessary would trigger the same block. This is input validation, not Information serving as a constitutive condition of the Execution State.

**Current mitigation**: `F-IRRELEVANT` control passed. The model does not block when irrelevant information is present alongside the required F.

**Remaining gap**: `F-IRRELEVANT` tests "irrelevant info does not cause blocking" but does not test "a *different* required-but-absent field causes the same blocking." If the model blocks whenever any named-required field is absent, regardless of its semantic content, then the block is generic validation, not Information-conditioned execution.

To fully address this rival, a future probe would need to show that:
1. blocking is specific to the semantic content of F (not merely to the fact that a named field is empty);
2. a structurally identical transition with a *different* type of required information does not block in the same way;
3. or that the model can articulate *why* this specific absence (not just any absence) prevents the transition.

---

## 4. Emerging structure (not yet theorized)

The results suggest that Information conditions may not form a single binary (present/absent → executable/not) but rather a **condition space with distinct semantic roles**:

```text
                Information
                     │
       ┌─────────────┼─────────────┐
       │             │             │
   execution     quality       irrelevant
   condition     condition      condition
       │             │             │
    ABSENT         STALE          IRRELEVANT
       │
    BLOCKED
```

**This structure is not established.** It is a preliminary pattern from one experiment. It should not be treated as a claim.

If future experiments confirm that different Information validity dimensions reliably map to different transition outcomes (prerequisite → blocked; quality → degraded; irrelevant → no effect), this would suggest that:

> Execution State is not a standalone runtime artifact but a **relation between a state and a set of Information conditions with distinct semantic roles**.

This would be a significant theoretical step beyond both H1 and the simple H3 framing.

---

## 5. Phase A / Phase B relationship

Phase A established: `A_epistemic / A_execution` are behaviorally separable and ordered.

Phase B now suggests: Information conditions themselves occupy different relationships to Execution State (prerequisite vs quality vs irrelevant).

If both hold, the research object shifts from:

> "How does SimiGo execute?"

to:

> "What conditions constitute an executable state, and how do those conditions determine the nature of state transitions?"

This is the deeper theoretical entry point. But it remains speculative until the generic-validation rival is addressed.

---

## 6. Next steps (proposed, not authorized)

1. **Do not expand Information types** (no F-PARTIAL, F-AMBIGUOUS, F-LOW-CONFIDENCE, etc.).
2. **Address the generic-validation rival**: design a probe that distinguishes "named-field-missing → block" from "this specific Information absence → block."
3. Only after the rival is addressed: consider whether the condition-space structure is worth formalizing.

---

## 7. Frozen commit chain

| Commit | Content |
|---|---|
| `973da1d` | Phase B experiment design frozen |
| `d2c821a` | Phase B 10-cell run + results + this evidence boundary |
