# IPAC Instantiate Completeness — Conceptual Design v0.2 (Gap I-1c)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `REVISED DRAFT v0.2 · INCORPORATES THE HUMAN REVIEW VERDICT ON V0.1 · FREEZE NOT YET · IMPLEMENTATION / EXPERIMENT / PALACE BLOCKED · PENDING HUMAN REVIEW`
Revision lineage: v0.1 (`b717a77`) → Human Review verdict (2026-10-05: direction ACCEPT; design REVISE; one structural fix — split the verdict into orthogonal axes; two tightenings — D_RS-conditioned sufficiency, τ2★ semantic split; two downgrades — M-1 no R2-contract enlargement, PD-7 policy-not-theorem; three findings confirmed and kept) → v0.2 (this document).

---

## 0. What changed from v0.1 — and what did not

**Human review of v0.1 (registered):** the three central findings are **confirmed and kept** — (i) logical completeness ≠ efficiency completeness; (ii) carrier state = *optional efficiency state* (KV no longer secretly occupies the center of the State ontology); (iii) substrate = *operation, not memory* — "the first explicit separation of 'an Execution State needs a running mechanism' from 'an Execution State needs additional persistent state'".

**Changed — the one structural fix (the review's core):**

1. **The Outcome A/B/C three-way frame is replaced by three orthogonal axes** (§1): **Axis A — State-component completeness** (R2 + τ2: is an irreducible additional *state component* required?); **Axis B — Instantiation (operational) completeness** (R2 + τ2 + ε2 + substrate realization → sufficient to produce S2?); **Axis C — Efficiency completeness** (S2: does the continuation avoid T1 recomputation?). Anti-smuggling mapping rules bind the axes (§1.1). The v0.1 outcomes are re-explained under the axes (§8) — in particular, **under Axis A, a sufficiency-style answer may actually hold**, which v0.1's merged framing denied.

2. **The R2-sufficiency claim is D_RS-conditioned** (§2, §8): the provable statement is *"under the registered rendered-surface doctrine (D_RS), R2 supplies sufficient information for logical continuity; completeness outside D_RS remains open"* — not "R2 is complete". This makes the completeness trigger genuinely live instead of an afterthought.

3. **τ2★ = ⟨task τ2, execution envelope ε2⟩** (§1.3, §3.1): one external input channel carrying two **semantically distinct objects**. The envelope is not part of the task; whether a change of ε2 alone constitutes "the same T2" is deliberately not settled here — the split keeps it answerable later.

4. **M-1 / IC-2 downgraded** (§2, §4): R2's lineage context **MAY** carry formation/backend/weights identity *where already present in formation provenance*; **I-1c does not enlarge the frozen R2 persistence contract** (v0.3 is not to be revised to add a weights field).

5. **PD-7 marked as policy, not theorem** (§4.3): "different model = different continuation" is a **chosen lineage-strict continuation policy** — PA-2/P7 do not entail it. Registered future alternative: *cross-model continuation under content/behavioral equivalence* (not researched here; directly relevant to future cross-backend / model-portability work).

**Unchanged (review-confirmed):** the systematic classification method (M-table, now updated); the Instantiate Contract shape (IC-1..IC-7, with the IC-2 note); the two-stage continuality criterion (structural at instantiate-time / behavioral post-execution via C-CAP); the substrate interface and the recompute-baseline argument; the no-oracle discipline; the storage-agnostic, no-PALACE, no-implementation, no-experiment boundaries.

---

## 1. The three-axis structure (the central fix)

v0.1's Outcome A/B/C used one three-way frame to answer two ontologically different questions and one efficiency question. The verdict is now split into three orthogonal axes; **no axis may borrow another's answer**.

```text
Axis A — State-component completeness
    R2 + τ2  →  is any irreducible additional STATE component required?
    Answer shape: an inventory verdict ("none identified" / "component X required"),
    bounded by D_RS.

Axis B — Instantiation (operational) completeness
    R2 + τ2 + ε2 + substrate realization  →  sufficient to produce S2?
    Answer shape: the operational closure — what must be DONE, not what must
    be remembered.

Axis C — Efficiency completeness
    S2  →  does the continuation avoid T1 recomputation?
    Answer shape: carrier-relative instrumentation (C-CAP(c)).
```

Anti-smuggling mapping rules:

```text
a declaration (ε2)                      is never a state component;
an operation (substrate realization)    is never a state component;
an optional efficiency artifact (carrier state) is never required by Axis A;
Axis C is never satisfied by Axis A's answer.
```

**D_RS (the rendered-surface doctrine)** — registered as this design's central assumption: *"continuation = continue the rendered context; what is not in the surface is not required for logical continuity."* Bounded by the ES line's instrument history (PA-2, P5, T3). Every Axis-A statement below is conditional on D_RS.

---

## 2. Input boundary

### 2.1 R2 provides / does not provide

```text
✓ rendered continuation surface (bytes) — the position carrier (PA-2)
✓ used information items, re-materialized at pinned versions
✓ lineage context (A-chain; formation records; MAY include formation/
  backend/weights identity where already present in formation provenance¹;
  E1's execution-segment identifiers for trace provenance)
✓ formation baseline

✗ the task to continue (τ2 — external)
✗ the execution envelope (ε2 — external, distinct from the task)
✗ a running substrate
✗ carrier-side state (PD-3)
✗ current external-world state
✗ any forward-looking choice
```

¹ **No R2-contract enlargement** (Human review, binding): v0.3 froze the lineage context as it was; weights/backend identity appears in I-1c only *where formation provenance already carries it*. I-1c does not require v0.3's R2 to gain a new weights field.

### 2.2 τ2★ = ⟨task τ2, execution envelope ε2⟩

One external input channel, two semantically distinct objects:

```text
τ2 = what task should be executed          (the future's content)
ε2 = under what declared execution         (the future's conditions:
     conditions                              policy, limits, tool availability)
```

Both are declarative and future-facing; neither runs anything; neither is a state component. **The split is kept precisely so that "if ε2 changes, is it still the same T2?" remains an answerable, separate question** — not pre-merged into one object.

---

## 3. Missing-state classification (M-table, updated)

Each candidate: In R2? In τ2/ε2? Logically required (Axis A)? Required for no-recompute (Axis C)?

```text
#     Candidate component            R2?      τ2/ε2?  Axis A (logical)?  Axis C?     Classification
M-1   weights identity (model)       prov.¹   re-dec. YES (lineage-strict²)  YES     spec recoverable from R2 provenance
                                                                                 where present; realization = Axis-B
                                                                                 operation (X-B). **No new R2 field.**
M-2   engine / runtime substrate     no       no      no — an OPERATION, not a       Axis-B element (X-B) behind the
                                                     state component                substrate interface
M-3   decode position / cursor       derivable —      no — derived given M-1/M-2     —       DERIVED (PD-6); not independent state
M-4   KV / carrier-side state        no       no      no — recompute baseline        YES     OPTIONAL efficiency component; the only
                                                                                 candidate additional STATE component —
                                                                                 and it is optional, Axis-C-scoped
M-5   execution policy / mode        no       ε2      no — a DECLARATION, not a      —       ε2 (PD-5)
                                                     state component
M-6   tool availability / limits     no       ε2      no — declaration               —       ε2
M-7   external world state           no       declar. precondition-style only —               OUTSIDE the instantiate boundary:
                                                     T2 re-queries or ε2 declares           instantiate completes the execution
                                                                                             object, never the world
M-8   scratch / internal trajectory  no       no      NO under D_RS⁴ — the Axis-A    efficiency-only  NOT REQUIRED — doctrine-bounded;
      state (not in the surface)                      TRIGGER                                                 doctrine failure ⇒ Axis A flips
M-9   lineage / identity binding     YES      —       YES                            —       R2-supplied, instantiate-REALIZED (IC-4)
```

² **Lineage-strict per PD-7 — a chosen policy, not a theorem** (see §4.3).

⁴ M-8 is the registered **Axis-A trigger**: the one candidate that, if ever shown logically required, would flip Axis A from none-found to "component required" — and, being carrier-relative, would simultaneously make a carrier-independent complete instantiate impossible (the v0.1 "Outcome C" content, now correctly placed).

---

## 4. The semantics of instantiate

### 4.1 Signature

```text
instantiate(R2, τ2★, substrate) → S2        where τ2★ = ⟨task τ2, envelope ε2⟩
```

The v0.1 question "does X exist?" is answered **per axis**: Axis A found no additional state component; Axis B's irreducible element is the substrate realization (an operation); Axis C's element is optional carrier state. There is no single X — that was v0.1's conflation.

### 4.2 The Instantiate Contract (IC-1..IC-7, retained with the IC-2 note)

```text
IC-1  information completeness   S2's continuation surface byte-identical to R2.surface;
                                 used items present at pinned versions (inherits V-2/V-4)
IC-2  binding                    S2 executes on a substrate bound to the weights identity
                                 per the binding spec — the spec inherited from R2's
                                 provenance where present, or re-declared as the SAME
                                 weights in τ2★. **Policy note (PD-7, §4.3).** No new R2
                                 persistence requirement is created.
IC-3  envelope                   S2 runs under ε2 exactly as declared — nothing inferred
IC-4  lineage                    S2 inherits the A-chain; identity lineage-inherited-pending
                                 (finalized at T2's own persist step)
IC-5  position                   derived: tokenize(surface) under the bound tokenizer (PD-6)
IC-6  no-oracle                  no semantic judgment on R2, τ2★, or substrate fitness
                                 beyond mechanical binding checks
IC-7  efficiency (optional)      substrate MAY supply restored carrier-side state with
                                 consumed-prefix metrics (feeds C-CAP(c)); absence
                                 forfeits only the no-recompute realization, never
                                 logical continuality
```

### 4.3 PD-7 — a policy, not a theorem (downgrade, binding)

"Different model ⇒ different continuation" is **the chosen lineage-strict continuation-identity policy**. It is not entailed by PA-2 or P7 (P7 in fact shows the same continuation realized across engines — same weights, different substrate). Registered future alternative, not researched here: **cross-model continuation under content/behavioral equivalence**. PD-7 must be cited as a policy decision wherever used — relevant directly to future cross-backend / model-portability work.

---

## 5. The continuable criterion for S2 — two stages (retained)

**Structural continuality** (instantiate-time, mechanical): SC-1 surface integrity / SC-2 substrate bound per IC-2 / SC-3 envelope active / SC-4 lineage attached / SC-5 task declared (τ2 external) / SC-6 position derivable. S2 is *structurally continuable for the specified T2* iff SC-1..SC-6 hold.

**Behavioral continuity** (post-execution, C-CAP's jurisdiction): the trace-provenance check (E2 references E1.seg[0..k]; no equivalent new segment) plus carrier-form consumed-prefix metrics.

The design claims the former and pre-registers the latter's instrument; structural continuity does not guarantee behavioral continuity beyond what C-CAP measures (the semantic-equivalence escape remains the registered boundary).

---

## 6. Connection to C-CAP (unchanged)

`CR —resolve→ R2 —instantiate(R2, τ2★, substrate)→ S2 —execute T2→ trace`. The no-recompute criterion lands at the State layer by **segment-provenance inheritance**: E1's segment identifiers travel in R2's lineage context, IC-4 binds them into S2's execution context, T2's trace references them — C-CAP(c)'s check object. Two instrumentations (document-form trace provenance; carrier-form consumed-prefix metrics), one criterion.

## 7. Substrate interface (unchanged)

```text
bind(weights-identity, ε2)          → a running substrate
materialize(R2.surface)             → position/state ready to continue
restore(carrier-state)    OPTIONAL  → consumed-prefix metrics (C-CAP(c))
```

The substrate must not: judge semantics; alter the surface; supply task content; define completeness. Logical completeness is carrier-independent because the recompute baseline always exists; efficiency completeness is necessarily carrier-relative.

---

## 8. Verdict by axes (replacing the v0.1 Outcome A/B/C)

**Axis A — State-component completeness: NONE IDENTIFIED (under D_RS).** The weights-identity *specification* is recoverable from R2 provenance where present (no new R2 field — §2.1¹); M-3 is derived; M-5/M-6 are declarations (ε2 — not state); M-7 is outside the boundary; M-9 is R2-supplied. The only candidate additional state component — M-8, non-surface scratch state — is held out by D_RS. **Under D_RS, R2 + τ2 (with ε2 declared) contains no missing irreducible state component; completeness outside D_RS remains open**, and M-8 is the registered trigger that would flip this verdict.

**Axis B — Instantiation completeness: a finite operational closure.** R2 + τ2 + ε2 + substrate realization is sufficient to produce S2 via IC-1..IC-7. The substrate realization is irreducibly operational — **this axis can never be satisfied by data alone.**

**Axis C — Efficiency completeness: carrier-relative.** Achieved via IC-7's optional restore + consumed-prefix metrics and the trace-provenance check; never part of Axis A's answer.

**Re-explanation of the v0.1 outcomes under the axes:**

- v0.1 **"Outcome B"** → Axis B holds, and Axis A holds as *none-found*: *"Instantiation requires a finite set of external declarations (ε2) and an operational substrate; only carrier state is a candidate additional state component — and it is optional, efficiency-scoped."*
- v0.1 **"Outcome A"** → partially resurrected **at Axis A**: state-component-wise, sufficiency may hold (none-found under D_RS). What v0.1's A denied — the substrate operation — belongs to Axis B, not Axis A; that denial was the conflation.
- v0.1 **"Outcome C"** → re-registered as **Axis A's live trigger** (an M-8-class discovery): handled through G-2 discipline if ever fired.

## 9. Open items for Human Review

1. **The three-axis structure** — accept as the verdict's permanent shape (replacing the Outcome frame).
2. **PD-5** (ε2 inside the τ2★ channel, semantically split) — confirm.
3. **PD-6** (derived position) — confirm; note the cross-engine tokenizer-determinism dependency.
4. **PD-7** (lineage-strict policy, not theorem) — confirm the marking and the registered cross-model alternative.
5. **IC-1..IC-7 + SC-1..SC-6** — accept as the pre-registered contract/criterion shape.
6. **M-8 as the Axis-A trigger** — accept, or commission the D_RS stress test as a separate line.

## 10. Non-claims

No carrier selected (PALACE unnamed); no backend chosen; nothing implemented or run; **no claim that R2 is complete for logical continuity outside D_RS**; no claim that structural continuity guarantees behavioral continuity beyond C-CAP's measurements; no minimality claim for the component inventory; no new R2 persistence requirement created; PD-7 cited as policy wherever used; IPAC boundings carried; nothing frozen — pending Human Review.
