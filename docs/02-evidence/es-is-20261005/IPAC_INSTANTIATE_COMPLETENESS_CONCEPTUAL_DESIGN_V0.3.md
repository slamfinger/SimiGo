# IPAC Instantiate Completeness — Conceptual Design v0.3 (Gap I-1c)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `FROZEN CONCEPTUAL DESIGN v0.3 · FREEZE RULING 2026-10-05 · IMPLEMENTATION / EXPERIMENT / PALACE REMAIN BLOCKED PENDING SUBSEQUENT GATES`
Revision lineage: v0.1 (`b717a77`) → review (direction ACCEPT, design REVISE) → v0.2 (`9abd764`, three-axis structure + D_RS conditioning + τ2★ split + M-1 downgrade + PD-7 marking) → review (three-axis structure **ACCEPT**; D_RS handling **correct** — M-8 now has real falsification force; **two pre-freeze fixes** — IC-2 binding decidability, Axis B evidence-level downgrade; notation unified) → v0.3 (this document) → **pre-freeze consistency patch** (2026-10-05: M-1's Axis-A entry corrected — a weights identity is NOT a State component and is required only to DECIDE lineage-strict binding; State necessity ≠ binding-decidability necessity. No other changes.) — freeze-ready → **FREEZE RULING (2026-10-05): APPROVED / FROZEN AS I-1c CONCEPTUAL DESIGN BASELINE.**

---

## 0. What changed from v0.2 — and what did not

**Human review of v0.2 (registered):** the three-axis structure is **ACCEPT** — the v0.1 ontological confusion (state / input / operation merged) is resolved; **D_RS is now genuinely falsification-bearing** (D_RS holds ⇒ Axis A none-found; D_RS fails ⇒ M-8 may become required ⇒ Axis A flips) — no longer a decorative assumption. **The M-table is frozen at nine entries**: "the next round should not continue expanding the M-table" — remaining questions belong to *binding decidability* and *evidence-level boundaries*, not to discovering more state candidates.

**Changed — the two pre-freeze fixes:**

1. **IC-2 rebuilt as a three-state binding decision** (§4.2): the question *"same weights as whom?"* now has a mechanical answer in every case. When E1's formation provenance does not carry a weights identity (a **legal** case — R2 MAY but need not carry it, and the frozen R2 contract is not enlarged), the system **cannot** mechanically verify "τ2★ uses the same weights as E1" and is forbidden from semantically assuming it. Binding is therefore decided in three states — **BOUND / UNBOUND / MISMATCH** — with distinct claim strengths (§4.2, §5, §6).

   The structural finding this surfaces, named and kept:

   > **Missing information is not necessarily a "State component"; it may be a "binding decidability input".**

   The absence of a weights-id in R2 does not flip Axis A (it was never an R2-required field); it degrades the *claim* available at instantiate time (lineage-strict vs. undecidable). A new anti-smuggling rule encodes this (§1.1).

2. **Axis B downgraded to the evidence level** (§8): "sufficient to produce S2" is withdrawn. The correct statement: a **finite operational closure has been identified and prescribed** as the candidate instantiate contract (IC-1..IC-7) — a conceptual-model prescription. Whether it *suffices* to produce a genuinely continuable S2 is exactly what subsequent implementation/experiment would test. The Conceptual Contract is no longer written as an Empirical sufficiency claim.

**Notation unified:** Axis A's input is now written **R2 + τ2★** throughout (τ2★ = ⟨task τ2, envelope ε2⟩, frozen notation), with the standing note: *ε2 participates in instantiation-boundary judgments and never thereby becomes a state component.*

**Unchanged (review-confirmed):** the three-axis structure itself; D_RS as genuinely falsification-bearing (M-8 = the Axis-A trigger); the M-table at nine entries (frozen — no expansion next round); the Instantiate Contract shape; the two-stage continuality criterion; the substrate interface and recompute-baseline argument; the no-oracle discipline; PD-1..PD-7 with their binding notes; all storage-agnostic, no-PALACE, no-implementation, no-experiment boundaries.

---

## 1. The three-axis structure (retained; notation unified; one new rule)

```text
Axis A — State-component completeness
    R2 + τ2★  →  is any irreducible additional STATE component required?
    (ε2 participates in instantiation-boundary judgments via τ2★ and never
    thereby becomes a state component.)
    Answer shape: an inventory verdict, bounded by D_RS.

Axis B — Instantiation (operational) completeness
    R2 + τ2★ + substrate realization  →  the candidate operational closure
    for producing S2 (prescribed; sufficiency deferred to evidence — §8).
    Answer shape: what must be DONE, not what must be remembered —
    plus, from this revision, the input-decidability conditions of those
    operations (binding state, §4.2).

Axis C — Efficiency completeness
    S2  →  does the continuation avoid T1 recomputation?
    Answer shape: carrier-relative instrumentation (C-CAP(c)).
```

Anti-smuggling mapping rules (the fourth is new):

```text
a declaration (ε2)                              is never a state component;
an operation (substrate realization)            is never a state component;
an optional efficiency artifact (carrier state) is never required by Axis A;
a missing DECIDABILITY INPUT (e.g., an uncarried weights-id) is a
binding-decidability condition on Axis B — never a missing state component.
```

This seam — **State necessity ≠ binding-decidability necessity** — is a standing classification boundary: every future "why must this information be persisted?" judgment passes through it (state-necessity ⇒ Axis A / persistence; decidability-necessity ⇒ binding only).

**D_RS** — the rendered-surface doctrine, registered as the central assumption: *"continuation = continue the rendered context; what is not in the surface is not required for logical continuity."* Bounded by the ES line's instrument history (PA-2, P5, T3); genuinely falsification-bearing via M-8.

---

## 2. Input boundary (retained; the legal UNBOUND case made explicit)

R2 provides: rendered surface (bytes); used items at pinned versions; lineage context (A-chain; formation records; **MAY** include formation/backend/weights identity *where already present in formation provenance* — **no R2-contract enlargement**; E1's execution-segment identifiers); formation baseline.

R2 does not provide: the task (τ2); the envelope (ε2); a running substrate; carrier-side state; current external-world state; any forward-looking choice.

τ2★ = ⟨task τ2, envelope ε2⟩ — one channel, two semantic objects.

**The legal UNBOUND case, spelled out:** E1 ran on weights W1; E1's formation provenance did not record W1; R2 therefore carries no weights identity; τ2★ declares weights W1. The system cannot mechanically verify that τ2★'s W1 is E1's W1 — and must not semantically assume it. This is not a defect of R2 (the frozen contract stands) and not a missing State component (Axis A unaffected); it is a **binding-decidability condition**, handled by IC-2's three states (§4.2).

---

## 3. Missing-state classification (M-table frozen at nine; M-1 reclassified)

```text
#     Candidate component            R2?      τ2★?    Axis A (logical)?  Axis C?     Classification
M-1   weights identity (model)       MAY¹     re-dec. NO as a State component;   YES     **BINDING-DECIDABILITY INPUT** — not a
                                                      required only to DECIDE the        state component: where present, the spec
                                                      lineage-strict binding claim       is recoverable and IC-2 can reach BOUND/
                                                      (PD-7)                             MISMATCH; where absent, IC-2 = UNBOUND
                                                                                         (recorded, never inferred).
                                                                                         Realization = Axis-B operation (X-B).
                                                                                         **No new R2 field.**
M-2   engine / runtime substrate     no       no      no — an OPERATION, not a       Axis-B element (X-B) behind the
                                                     state component                substrate interface
M-3   decode position / cursor       derivable —      no — derived given M-1/M-2     —       DERIVED (PD-6); not independent state
M-4   KV / carrier-side state        no       no      no — recompute baseline        YES     OPTIONAL efficiency component; the only
                                                                                 candidate additional STATE component —
                                                                                 optional, Axis-C-scoped
M-5   execution policy / mode        no       ε2      no — a DECLARATION             —       ε2
M-6   tool availability / limits     no       ε2      no — declaration               —       ε2
M-7   external world state           no       declar. precondition-style only —               OUTSIDE the instantiate boundary
                                                 T2 re-queries or ε2 declares
M-8   scratch / internal trajectory  no       no      NO under D_RS — the Axis-A     efficiency-only  NOT REQUIRED — doctrine-bounded;
      state (not in the surface)                      TRIGGER (falsification-bearing)                 doctrine failure ⇒ Axis A flips
M-9   lineage / identity binding     YES      —       YES                            —       R2-supplied, instantiate-REALIZED (IC-4)
```

¹ MAY — where already present in formation provenance; I-1c does not enlarge the frozen R2 persistence contract.
² Lineage-strict per PD-7 — a chosen policy, not a theorem (§4.3).

---

## 4. The semantics of instantiate

### 4.1 Signature

```text
instantiate(R2, τ2★, substrate) → S2        τ2★ = ⟨task τ2, envelope ε2⟩
```

There is no single "X?" — the question is answered per axis (v0.2's fix, retained): Axis A found no additional state component; Axis B's irreducible element is the substrate realization **plus its input-decidability conditions**; Axis C's element is optional carrier state.

### 4.2 IC-2 rebuilt — the three-state binding decision (pre-freeze fix #1)

```text
IC-2  binding — three states, mechanically decided:

BOUND      predecessor weights identity is mechanically available
           (carried in R2's lineage provenance) AND matches the
           τ2★-declared weights identity.
           → IC-2 satisfied. S2 may claim LINEAGE-STRICT continuation.

UNBOUND    predecessor weights identity is not mechanically available
           (legal: R2 may but need not carry it; the frozen R2 contract
           is not enlarged).
           → instantiate proceeds WITHOUT a lineage-strict claim.
             No semantic inference is permitted ("probably the same
             model" is forbidden). S2 is produced as a continuation
             whose lineage-strict status is UNDECIDABLE at instantiate
             time. The undecidability is recorded, not resolved.

MISMATCH   both identities are available and differ.
           → NOT the same lineage-strict continuation (per PD-7's
           lineage-strict policy). The continuation proceeds, if at
           all, as a declared CROSS-MODEL continuation (the registered
           alternative) — never as a lineage-strict one.
```

**The binding state is recorded as part of the instantiate record** and qualifies the meaning of everything downstream (§5, §6): BOUND → lineage-strict S2; UNBOUND → continuable S2 with undecided lineage-strict status; MISMATCH → cross-model continuation per policy.

### 4.3 PD-7 — a policy, not a theorem (retained, binding)

"Different model ⇒ different continuation" is the chosen **lineage-strict continuation-identity policy** — not entailed by PA-2/P7 (P7 shows the same continuation realized across engines: same weights, different substrate). Registered future alternative, not researched here: **cross-model continuation under content/behavioral equivalence**. The MISMATCH state above is this policy's mechanical enforcement point.

---

## 5. The continuable criterion for S2 (SC-2 annotated with binding state)

**Structural continuality** (instantiate-time, mechanical):

```text
SC-1  surface integrity      byte-identical to R2.surface
SC-2  substrate bound        per IC-2 — WITH THE BINDING STATE RECORDED:
                             BOUND / UNBOUND / MISMATCH
SC-3  envelope active        ε2 in force as declared
SC-4  lineage attached       A-chain continues through S2's execution context
                             (E1.seg identifiers bound in)
SC-5  task declared          τ2 present (external input)
SC-6  position derivable     tokenize(surface) under the bound tokenizer
```

S2 is *structurally continuable for the specified T2* iff SC-1..SC-6 hold — **with the caveat that under UNBIND, the continuation is continuable but its lineage-strict status is undecided** (recorded, never semantically inferred). Under MISMATCH, the continuation is by policy a cross-model one.

**Behavioral continuity** (post-execution, C-CAP's jurisdiction): unchanged — trace provenance plus carrier-form metrics. **The binding state qualifies the interpretation of C-CAP results, not their mechanics**: the trace check runs identically under BOUND/UNBOUND/MISMATCH; what differs is what the passing run is *evidence of* (lineage-strict continuation vs. an undeclared-model continuation vs. a declared cross-model continuation).

---

## 6. Connection to C-CAP (unchanged mechanics; interpretation now binding-state-qualified)

`CR —resolve→ R2 —instantiate(R2, τ2★, substrate)→ S2 —execute T2→ trace`. Segment-provenance inheritance unchanged: E1.seg identifiers travel in R2's lineage context, IC-4 binds them into S2's context, T2's trace references them. The no-recompute criterion's two instrumentations (document-form trace provenance; carrier-form consumed-prefix metrics) are unchanged.

---

## 7. Substrate interface (unchanged)

```text
bind(weights-identity | UNBOUND, ε2)   → a running substrate
materialize(R2.surface)                → position/state ready to continue
restore(carrier-state)       OPTIONAL  → consumed-prefix metrics (C-CAP(c))
```

The substrate must not: judge semantics; alter the surface; supply task content; define completeness; or resolve the UNBOUND case by inference.

---

## 8. Verdict by axes (Axis B downgraded to the evidence level)

**Axis A — State-component completeness: NONE IDENTIFIED (under D_RS; input-decidability caveat registered).** With ε2 correctly classed as a declaration and M-1 correctly classed as a binding-decidability input (not a state component), **no irreducible additional state component is identified**. M-8 remains the falsification-bearing trigger; completeness outside D_RS remains open. The UNBOUND case does **not** touch Axis A — it is a binding-decidability condition on Axis B.

**Axis B — Instantiation completeness: a finite OPERATIONAL CLOSURE has been identified and prescribed — as a candidate instantiate contract (IC-1..IC-7), NOT as an empirical sufficiency claim.** In the current conceptual model, `R2 + τ2★ + substrate realization` is *prescribed* as instantiate's input/operation closure; whether it *suffices* to produce a genuinely continuable S2 is exactly what subsequent implementation/experiment would test. The contract also now carries its own input-decidability condition (IC-2's binding state) — a prescribed closure with a prescribed undecidable-input handling.

**Axis C — Efficiency completeness: carrier-relative.** IC-7's optional restore + consumed-prefix metrics and the trace-provenance check; never part of Axis A's answer.

*(v0.1's Outcome A/B/C remain re-explained as in v0.2 §8; no change to that mapping beyond Axis B's evidence-level downgrade.)*

---

## 9. Open items for Human Review

1. **IC-2's three-state binding decision** — accept as the pre-freeze shape (including UNBOUND's "proceed without lineage-strict claim" disposition).
2. **The binding-decidability distinction** — accept as a named structural finding and the fourth anti-smuggling rule.
3. **Axis B's evidence-level downgrade** — accept ("candidate operational closure prescribed"; real sufficiency deferred to implementation/experiment).
4. PD-5 (ε2 channel), PD-6 (derived position), PD-7 (lineage-strict policy + registered cross-model alternative) — confirm.
5. **The M-table at nine entries, frozen** — confirm no expansion next round.
6. **Freeze decision** — **FROZEN by ruling 2026-10-05.** This freeze applies to the conceptual design only; Implementation / Experiment / PALACE remain BLOCKED pending subsequent I-1c gates.

## 10. Non-claims

No carrier selected (PALACE unnamed); no backend chosen; nothing implemented or run; no claim that the prescribed operational closure is empirically sufficient (Axis B is a prescription, not a result); no claim that R2 is complete for logical continuity outside D_RS; no claim that UNBOUND continuations are lineage-strict (they are recorded as undecidable); no minimality claim for the M-inventory (frozen at nine by discipline, not by proof); no retroactive re-grading; IPAC boundings carried; nothing frozen — pending Human Review.
