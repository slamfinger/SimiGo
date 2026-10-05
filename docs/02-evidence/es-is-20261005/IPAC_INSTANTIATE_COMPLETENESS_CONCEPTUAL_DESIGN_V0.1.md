# IPAC Instantiate Completeness — Conceptual Design v0.1 (Gap I-1c)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `CONCEPTUAL DESIGN · GAP I-1c COMMISSIONED (HUMAN RULING) · NO IMPLEMENTATION · NO EXPERIMENT · NO PALACE / NO BACKEND SELECTION · PENDING HUMAN REVIEW`
Directive: Human ruling 2026-10-05 — I-1c (Instantiate Completeness) opened as the next Core design space, conceptual only. The design answers exactly six things: input boundary; missing-state classification; the semantics of `instantiate`; the continuable criterion for S2; the connection to C-CAP; the boundary of carrier entry.
Predecessor: `IPAC_PERSISTENCE_RESOLVE_CONCEPTUAL_DESIGN_V0.3.md` (**FROZEN**, main `2b2e2ef`; branch mirror `76825ad`). All frozen boundaries are inherited and load-bearing here.

Session header (Constitution Article 6):

```text
Core target:               I-1c — Instantiate Completeness (R2 + τ2 → genuinely continuable S2)
Affected closure edge:     I→S (the instantiate step completes it) + S→S (continuation mechanics)
Real system object:        the Instantiate Contract — a CANDIDATE interface; no runtime artifact
                           may be built before Human Review
Expected capability delta: a mechanical answer to "what does R2 + τ2 still lack for S2 to be a
                           genuinely continuable Execution State" — i.e., the I→S edge's missing half
Stop condition:            if the completeness analysis cannot be stated without naming a specific
                           carrier, or without a semantic oracle, stop and downgrade (Gate 2)
```

---

## 0. Scope and the governing discipline

**The research discipline of this round (Human, binding):** do not start from "how is MLX KV restored?"; start from *"given that the Information Space already supplies R2, what logically non-omissible states does an Execution State still lack?"* The analysis order below is therefore: components first, carrier last — §6 is the only section where a carrier appears, and it appears only as an interface.

**Central distinction this design is built on** (and which the verdict turns on):

```text
logical completeness     — what makes S2 a GENUINE continuation of the prior computation
                           (continuable even if every prior token is re-derived)
efficiency completeness  — what makes S2 continue WITHOUT recomputation
                           (C-CAP(c); necessarily carrier-relative)
```

These are different completeness claims with different components. Conflating them is the carrier-first trap in its subtlest form.

**Inherited frozen boundaries** (from v0.3, all load-bearing here): R1 ≠ CR; A-chain lineage-bearing only; V-1 includes CR self-identity; RESOLVED-WITH-VIOLATIONS ≠ success; no-recompute independent of "consume R2" (semantic-equivalence escape = registered detection boundary); τ2 externally supplied — resolve does not infer future tasks; three-edge vocabulary frozen; **R2 is not an Execution State**; no PALACE / no implementation / no experiment. IPAC boundings carried (OPEN / NONBINDING / minimality UNPROVEN / semantics NOT FROZEN).

---

## 1. Input boundary — what R2 and τ2 each provide

### 1.1 R2 (the Continuation Basis — resolve's frozen product) provides:

```text
✓ the rendered continuation surface (bytes) — the position carrier (PA-2)
✓ the used information items, re-materialized at pinned versions
✓ the lineage context (A-chain: S1's identity, formation records,
  E1's provenance — including the backend/weights identity E1 ran on,
  and E1's execution-segment identifiers for trace provenance)
✓ the formation baseline
```

### 1.2 R2 does NOT provide:

```text
✗ the task to continue (τ2 — externally supplied; frozen boundary)
✗ the execution policy / mode for the future execution
✗ a running substrate (weights realization, engine, tokenizer machinery)
✗ carrier-side state (KV etc.) — by PD-3, deliberately
✗ the current state of any external system T1's tools touched
✗ any forward-looking choice at all — R2 is entirely past-facing
```

### 1.3 τ2 provides / does not provide:

```text
✓ the task specification for T2 (what the future execution is to do)
✗ (by default) the execution envelope — policy, limits, tool availability
  (forward-looking, declarative, but distinct from task content — see PD-5)
✗ a substrate
```

**The boundary in one line: R2 is entirely past-facing; τ2 is declarative about the future; neither runs anything.** Everything that runs is instantiate's business (§3), and everything forward-looking and declarative must arrive from outside (§2, M-5).

---

## 2. Missing-state classification (systematic — no presupposed answer)

Each candidate component is asked four questions: In R2? In τ2? Logically required for continuable? Required for no-recompute?

```text
#     Candidate component            R2?      τ2?     Logical?   No-recompute?   Classification
M-1   weights identity (model)       prov.¹   overr.  YES        YES             spec recoverable (R2 provenance, default);
                                                                                 realization = instantiate op (X-2)
M-2   engine / runtime substrate     no       no      YES        —               realization OPERATION behind the
                                                                                 substrate interface (X-2) — not a state
                                                                                 component
M-3   decode position / cursor       derivable —      YES        —               DERIVED given M-1/M-2:
                                                                                 position = tokenize(surface) under the
                                                                                 bound tokenizer (PD-6) — not independent
                                                                                 state
M-4   KV / carrier-side state        no       no      NO²        YES             OPTIONAL efficiency component (X-3),
                                                                                 behind the interface — strictly
                                                                                 C-CAP(c)-scoped
M-5   execution policy / mode        no³      boundary YES       —               EXTERNAL declarative input → the
                                                                                 τ2★ envelope (PD-5)
M-6   tool availability / limits     no       envelope YES        —               τ2★ envelope
M-7   external world state           no       declar.  precondition-style        OUTSIDE the instantiate boundary:
                                                 only     (T2 re-queries   instantiate completes the execution
                                                          or τ2 declares)  object, never the world
M-8   scratch / internal trajectory  no       no      NO⁴        efficiency-only NOT REQUIRED — doctrine-bounded;
      state (not in the surface)                                                 outcome-C trigger if the doctrine fails
M-9   lineage / identity binding     YES      —       YES        —               R2-supplied, instantiate-REALIZED (IC-4)
```

¹ E1's provenance records the backend/weights it ran on — a *specification* is recoverable; the *realization* is not.
² The recompute baseline: any continuation is logically achievable by re-deriving from the surface. The lineage ground: PA-2 (the rendered text carries position/continuation), P5 attempt-1 (KV = representation fragment, not an independent carrier), T3 (no durable third carrier form).
³ E1's own policy is past provenance in R2; T2's policy is a forward-looking choice.
⁴ **The rendered-surface doctrine** — "continuation = continue the rendered context; what is not in the surface is not required" — is the load-bearing assumption of this entire classification. It is bounded by the ES line's instrument history (PA-2, P5, T3) and is *registered as the central assumption of this design*, not asserted as a law. If a logically-required non-surface state component is ever discovered, outcome C goes live (§7).

---

## 3. The semantics of instantiate

### 3.1 The signature

```text
instantiate(R2, τ2★, substrate) → S2

τ2★      = τ2 ⊕ execution envelope   (the external declaration channel: task
                                      specification ⊕ policy/limits/tool-availability —
                                      one channel, two distinguished sections; PD-5)
substrate = the realization side — an engine/runtime bound to the weights
            identity, entered ONLY through the interface (§6)
X?       — the Human's question "does an X exist, and what does it contain?" —
           is answered by the classification: X = { execution envelope (declarative,
           folded into τ2★ per PD-5), substrate realization (operational, X-2),
           carrier-side state (optional efficiency, X-3) }.
```

### 3.2 The Instantiate Contract

```text
IC-1  information completeness   S2's continuation surface is byte-identical to
                                 R2.surface; the used items are present at their
                                 pinned versions. (Inherits resolve's V-2/V-4.)
IC-2  binding                    S2 executes on a substrate bound to the weights
                                 identity per the binding spec (default: inherited
                                 from R2's provenance; τ2★ may re-declare the SAME
                                 weights — a different model would be a different
                                 continuation, not a lineage-strict one).
IC-3  envelope                   S2 runs under the declared execution envelope
                                 (policy / limits / tool availability) — exactly as
                                 declared, nothing inferred.
IC-4  lineage                    S2 inherits the A-chain; its identity is
                                 lineage-inherited-pending — finalized only when
                                 T2's own CR is written (S2 is not yet hashable
                                 at instantiate time; it becomes so at its persist step).
IC-5  position                   the decode position is DERIVED: tokenize(surface)
                                 under the bound tokenizer — not stored (PD-6).
IC-6  no-oracle                  instantiate performs no semantic judgment on R2,
                                 τ2★, or the substrate's fitness beyond the mechanical
                                 binding checks.
IC-7  efficiency (optional)      the substrate MAY supply restored carrier-side state;
                                 if supplied, its consumed-prefix metrics feed C-CAP(c)'s
                                 carrier-form instrumentation. Absence of carrier state
                                 does not violate completeness — it only forfeits the
                                 no-recompute realization.
```

### 3.3 Design decisions registered (with alternatives)

```text
PD-5  envelope home:    τ2★ = τ2 ⊕ envelope — one external declaration channel,
                        two distinguished sections (chosen)  vs  a separate envelope
                        input (registered alternative). Ground: everything forward-facing
                        and declarative should arrive through one boundary.
PD-6  position:         derived-given-binding (chosen; PA-2-grounded — the surface IS
                        the position carrier)  vs  an explicitly stored token position
                        (registered alternative; relevant only if cross-engine tokenizer
                        determinism fails — P7's cross-backend success suggests it holds
                        in practice, bounded).
PD-7  binding default:  weights identity inherited from R2 provenance, τ2★ may re-declare
                        same-weights (chosen)  vs  free re-binding (rejected for lineage
                        strictness: a different model is a different continuation).
```

---

## 4. The continuable criterion for S2 — mechanical, two-stage

"Continuable" is judged in two stages that must never be conflated:

### 4.1 Structural continuality (judged at instantiate time — mechanical)

```text
SC-1  surface integrity      S2's continuation surface byte-identical to R2.surface
SC-2  substrate bound        weights identity matches the binding spec (IC-2)
SC-3  envelope active        the declared envelope is in force (IC-3)
SC-4  lineage attached       the A-chain continues through S2's execution context
                             (E1's segment identifiers bound in — see §5)
SC-5  task declared          τ2 present (the T2 specification is an external input —
                             frozen boundary; instantiate does not infer it)
SC-6  position derivable     the decode position is derivable under the bound
                             tokenizer (IC-5)
```

**S2 is structurally continuable for the specified T2 iff SC-1..SC-6 hold.** Every item is hash/comparison/mechanism-checkable — no oracle.

### 4.2 Behavioral continuity (judged post-execution — C-CAP's jurisdiction)

Whether S2's subsequent behavior *actually carries forward* the prior computation is decided by C-CAP(c) after T2 runs: the trace-provenance check (E2's trace references E1.seg[0..k]; no equivalent new segment) plus, in carrier form, the consumed-prefix metrics. **Structural continuality is instantiate's warranty; behavioral continuity is the executed run's evidence.** The design claims the former and pre-registers the latter's instrument — it does not claim that structural continuity guarantees behavioral continuity beyond what C-CAP measures (the semantic-equivalence escape remains the registered boundary).

---

## 5. Connection to C-CAP — the no-recompute criterion at State layer

The frozen chain `resolve → R2` now connects to `instantiate → S2 → T2` without gaps:

```text
CR —resolve→ R2 —instantiate(R2, τ2★, substrate)→ S2 —execute T2→ trace
```

**The State-layer landing of no-recompute**: R2's lineage context carries **E1's execution-segment identifiers** (they were part of the lineage context by v0.3's definition); IC-4 binds them into S2's execution context; T2's trace can therefore *reference* the inherited segments — which is exactly the object C-CAP(c)'s trace check requires (`E2 references E1.seg[0..k]; no equivalent new segment`). No new mechanism is invented: the segment provenance travels the chain by inheritance.

Two instrumentations, one criterion (unchanged from the frozen C-CAP):

- **document-form**: T2's consumed input contains the resolve output (R2's surface + items), and the trace references the inherited segments without equivalent re-execution.
- **carrier-form**: the substrate's consumed-prefix metrics (cacheHitTokens > 0 — the P7 metric reused) evidence the same criterion through IC-7's optional path.

---

## 6. The boundary of carrier entry

The carrier enters **only at the realization layer**, through a black-box interface:

```text
Substrate interface (candidate, minimal):
  bind(weights-identity, envelope)   → a running substrate
  materialize(R2.surface)            → position/state ready to continue
                                       (decode position derived per IC-5)
  restore(carrier-state)   OPTIONAL  → consumed-prefix metrics (feeds C-CAP(c))
```

**The substrate must not**: judge semantics; alter the surface; supply task content; or define completeness. Logical completeness is carrier-independent **because the recompute baseline always exists** (M-4: carrier state is efficiency-only); efficiency completeness is necessarily carrier-relative. This is the precise sense in which the design stays "carrier-independent but still Execution-State technology".

**PALACE**: not selected, not evaluated. The interface shows where a carrier could ever qualify — the substrate layer only; the IS-side storage question is a separate later evaluation. One sentence, no commitment.

---

## 7. Verdict — the three outcomes

**Verdict: B — a finite, small additional set; no hidden state component; C not triggered.**

```text
A.  R2 + τ2 sufficient —              NOT available in the strict sense: the substrate
                                      realization (X-2) is an irreducible OPERATION, not a
                                      state component, and no execution object runs without
                                      it. In the weak sense ("no additional STATE component
                                      beyond the τ2★ envelope"), almost-A holds — and that
                                      is the precise sense registered here.

B.  a finite set of additional        ADOPTED:
    components                        X-1  the execution envelope (declarative; τ2★)
                                      X-2  substrate realization (operational; behind
                                           the interface)
                                      X-3  carrier-side state (optional; efficiency-only)
                                      plus derivable components (M-3) that are NOT
                                      additional, and R2-realized components (M-9) that
                                      are not additional inputs.

C.  no carrier-independent complete   NOT triggered — but its liveness condition is
    instantiate                       registered precisely: a component that is
                                      (logically required) ∧ (not externally declarable)
                                      ∧ (carrier-relative, i.e. defeats the recompute
                                      baseline) would flip the verdict to C. The only
                                      candidate ever identified — non-surface scratch
                                      state (M-8) — is held out by the rendered-surface
                                      doctrine, which is itself bounded (E10/E15 lineage).
                                      If that doctrine ever fails, C goes live through G-2
                                      discipline.
```

The structural result worth stating plainly: **the Information Space side (R2) is complete for logical continuity; the irreducible remainder is one declarative input (the envelope) and one operational side (the substrate).** The Execution State / Information Space boundary runs exactly between the past-facing basis and the forward-declaring envelope, with the substrate as the sanctioned third element — an operation, not a memory.

---

## 8. Open items for Human Review

1. **PD-5** (envelope inside τ2★ vs separate input) — confirm or flip.
2. **PD-6** (derived position vs stored position) — confirm; note the cross-engine tokenizer-determinism dependency.
3. **PD-7** (binding default = same-weights inheritance) — confirm the lineage-strict reading.
4. **The Instantiate Contract IC-1..IC-7** — accept as the pre-registered contract shape for any future implementation/experiment.
5. **The two-stage continuality split** (structural at instantiate-time / behavioral post-execution) — accept as the criterion's jurisdiction boundary.
6. **Outcome B as the registered verdict, with C's liveness condition** — confirm, or commission deeper analysis of M-8 (the doctrine stress test) as a separate line.

## 9. Non-claims

No carrier is selected (PALACE unnamed as a target); no backend is chosen; nothing is implemented or run; no minimality claim for the component inventory (the classification is systematic within the listed candidates — additional candidates may exist and would enter through evidence); the rendered-surface doctrine is carried at its registered bounding, not asserted as a law; structural continuality is not claimed to guarantee behavioral continuity beyond C-CAP's measurements; IPAC boundings carried; nothing frozen here — this design is pending Human Review like its predecessors.
