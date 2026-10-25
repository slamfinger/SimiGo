# V2-P04 — External-Review Adjudication (LM-Wrong, count 1)

> **Adjudication ID:** `V2-P04-NOT-VALID-LM-WRONG(1)`
> **Date:** 2026-10-18 (Asia/Shanghai)
> **Nature:** READ-ONLY review ruling that separates (a) the *technical* correctness of one
> statement in `SR_P3_G1G2_BOUNDARY_FORMALIZATION_20261018.md` from (b) the *evidence-independence*
> and (c) the *applicability-scope* of the external reviewer's oppositions. Adds a self-validation
> guard: an outside party may flag one reasoning gap without that automatically rescinding every
> other opinion or the retained design. No code, reruns, Frozen-Contract change, commit, or push.
> **Anchor:** `SR_P3_G1G2_BOUNDARY_FORMALIZATION_20261018.md` (the L1/L2 addendum); coexists with
> `SR_P3_CARRIER_SELECTIVE_RECOMPUTE_20261018.md`.

---

## 1. The retained design — untouched by this ruling

The L1 (logical isolation / different `state_scope`) vs L2 (actual old-KV-cache-unreachable) split
in the addendum **is preserved**. Nothing here overrules L1/L2, G1 ⇒ G2 guarded dependency, or the
`PASS-部分 / NOT_OBSERVED` level on H_Executor. This ruling only (i) corrects one technical
statement and (ii) says which of the reviewer's oppositions are valid and on what basis.

---

## 2. The two corrections — both about the addendum, none about the architecture

### C1 — "KV cache" must not be stated as in-place weight mutation (technical, the addendum's error)

The addendum's L2 justification (lines 43–48) reads:

> …the "KV cache" is not a hand-managed object — it is the model weights mutated in place at every
> forward pass.

This sentence is **technically wrong as written** and must be corrected — but it does **not** defeat
L2 or L1. In ordinary LLM inference the model weights and the KV cache are **different state**; a
cache update is not a weight update. The addendum's intent — that there is no explicit per-state
cache invalidation in real inference and L2 therefore needs model-level proof — is still defensible,
but it must be rephrased neutrally (e.g. "the KV cache is not independently invalidated per new
Execution State" rather than "the KV cache *is* the weights").

Why this does not touch the boundary: removing a wrong sentence about state identity does not itself
prove the old KV cache was reachable or unreachable in any given run. L1/L2 separation stands on
design, not on this sentence.

### C2 — proxy-layer count is not independent proof of real model work (evidence-independence)

Confirmed: `_swift_forward_units_this_run()`, `not_computed_item_ids`, and `no_cache_penalty` are
Carrier/proxy-layer accounting. They **cannot alone** prove (a) a real model run occurred or
(b) the old KV cache became unreachable. The addendum already holds this (its own self-validation
clause, lines 104–107); the ruling just gives it a boundary line and forbids inferring `PASS`
from any single proxy source.

**Important nuance (see §4 below):** rejecting the proxy count as *independent* proof is **not**
rejecting a real Swift `Calculator` execution event as *evidence*. A genuine execution event at the
real Swift entry, correlated to task/input/output with verified observation coverage, can prove that
*that specific call happened*. It still cannot on its own prove (i) no other execution path called,
or (ii) the old KV cache was unreachable. The two are logically separable and must not be collapsed.

---

## 3. Applicability-scope correction (the reviewer's own gap)

The reviewer opposes L2 by citing: *"LLMs generally do not clear the entire KV cache between
consecutive forward passes within a single sequence."*

That proposition answers whether the cache is cleared **within one sequence**. It does **not**
decide whether a *new Execution State* may access the *previous Execution State's* cache — that is
a cross-Execution-State question. The single-sequence statement cannot, by itself, adjudicate the
cross-state isolation claim. To deny cross-state isolation on that basis alone is an inference gap;
to instead cite "cross-state isolation by design" likewise does not substitute for checking the actual
cache object, handle, ownership, and access path at runtime. Both directions need their own evidence.

---

## 4. Self-validation guard — the reviewer's self-consistency attack is *conditional*, not established

If the external review asserts *"self-consistency attack invalid"* because it itself uses a
proxy-layer count as its *own* proof, that is a valid objection — but only **if** the review did
exactly that. Merely noting "this count comes from the proxy layer" ≠ treating that count as
independent evidence of model work; those are two different inferences. Likewise, the reviewer's own
statement that *"any call count is structural proof of real model work"* must be checked against what
the reviewer actually claimed.

> Self-note from prior turn: the writer did **not** assert "any call count is structural proof of
> real model work." The asserted position was: proxy counts = diagnostic only; a real Swift entry
> execution event can prove a specific call occurred; old-cache-unreachable needs separate evidence.
> If the review summarized that position as "any call count proves model work," it is a
> **mis-attribution** (straw-man), not a self-consistency failure on the writer's part.

So `V2-P04-NOT-VALID-LM-WRONG(1)` stands for the **one** technical error (C1) and the **two**
evidence/scope corrections (C2, §3); it does **not** rescind the reviewer's other opinions nor rescue
every one of them either.

---

## 5. Verification registry — each opposition, what it checks, and its verdict

The registry below maps the external reviewer's oppositions to (a) what dimension it targets
(technical correctness / evidence-independence / applicability-scope), (b) the rule it must satisfy
to land, (c) what evidence is required to confirm or deny, and (d) the ruling on this date.

| # | Reviewer opposition (paraphrase) | Dimension checked | Rule it must satisfy | Evidence on file | Verdict 2026-10-18 |
|---|---|---|---|---|---|
| O1 | Addendum states KV-cache = weights mutated in place at every forward | **Technical** (C1) | The sentence must not equate cache-state with weight-state; restate neutrally | `SR_P3_G1G2_BOUNDARY_FORMALIZATION_20261018.md` lines 43–48 | **Correct** — rephrase needed; L1/L2 separation unaffected |
| O2 | Proxy-layer call count does not prove real model work works / that old cache is unreachable | **Evidence-independence** (C2) | A Carrier/proxy counter alone cannot witness a model run or cache isolation; needs real-entry event + correlation | `_swift_forward_units_this_run`, `not_computed_item_ids`, `no_cache_penalty` are proxy/Carrier accounting (L104–107) | **Correct** — proxy count is diagnostic only; a real Swift `Calculator` execution event can still prove that specific call occurred |
| O3 | Real Swift entry's independent execution event | **Applicability-scope** (execution-event witness) | Must cover the exact target path; coverage verified; does not by itself prove no other path or old-cache isolation | Real Swift `Calculator` integration through the carrier still unverified (`results.md`, H_Executor = NOT_VERIFIED) | **Conditionally correct** — an event can prove a specific call; coverage-scope and cross-isolation still separate questions |
| O4 | Single-sequence KV-cache behavior negates cross-Execution-State isolation | **Applicability-scope** (§3) | A within-one-sequence statement must not be read as a cross-state verdict; the two are different questions | Addendum gives no cross-state instrumented evidence; L2 = NOT_OBSERVED | **Inference gap** — single-sequence proposition does not adjudicate cross-state isolation |
| O5 | Reviewer flags proxy count as non-independent source | **Self-consistency** (§4) | Only holds if the review *used* the proxy count as its own proof; mere source-labeling ≠ using it as evidence | Reviewer's actual argument text is the deciding artifact (recorded in §4) | **Not established** — pending the reviewer's own wording; distinguishing "source-labeled" from "used-as-evidence" |

Verdict ledger (cumulative, read-only):
- O1 — Correct (technical rephrase required; architecture untouched).
- O2 — Correct (evidence-independence boundary held).
- O3 — Conditionally correct (execution event = witness for a specific call; isolation still separate).
- O4 — Inference gap (scope mismatch: within-sequence vs cross-state).
- O5 — Not established (depends on the reviewer's own stated inference, not merely that it mentions a proxy count).

**Net:** design retained; O1/O2 accepted verbatim; O3 kept conditional; O4 flagged as scope gap;
O5 not established on current record. OneLMWRONG = 1 (C1) is the sole *automatic* technical
rescission; the remaining oppositions each stand on their own dimension and must be judged
individually — no blanket rescind, no blanket rescue.

---

## 6. Persistent boundary statement (carried from G1/G2 addendum + SR_P3_CARRIER_SELECTIVE_RECOMPUTE)

- **proxy-layer PASS on a deterministic `swift_forward` stub** proves executor-integration +
  settlement-reuse + selective-recompute *pattern* — **not** real-model continuous computation.
- **cache hit/miss ≠ cache-isolation proof**: proxy accounting label, not real model-work;
- **L1 ⇒ G2 guarded dependency** is recorded, not established: L1 (proxy) proves L1-pattern only;
  the model-level continuous-computation / cross-state-isolation claims are independent of executor
  and require real Swift `Calculator` evidence;
- a **real execution event at the Swift entry** (outside the proxy) is the only witness of a specific
  call, and even then must still be checked for coverage scope and cross-isolation separately;
- **proxy-layer success does not substitute for real-model evidence; design-level isolation does not
  substitute for runtime isolation.** Reviewer rebuttals must meet the same verifiability bar as the
  research itself.

---

## 7. State note

Anchor `SR_P3_G1G2_BOUNDARY_FORMALIZATION_20261018.md` and
`SR_P3_CARRIER_SELECTIVE_RECOMPUTE_20261018.md` are **untracked** (`git status ??`) as of
2026-10-18. Per standing instruction: no code change, no rerun, Frozen Contracts untouched,
no commit, no push. This adjudication is READ-ONLY and self-contained; it does not re-derive H
Executor's verdict. For L1/L2 formalization and the G1⇒G2 guarded dependency, read the anchor.
