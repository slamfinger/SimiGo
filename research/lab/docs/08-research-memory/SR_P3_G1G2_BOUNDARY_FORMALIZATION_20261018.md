# P3 G1/G2 Boundary Formalization + Logic-Isolation Verdict — Review-Addendum

> **Review ID:** `REVIEW-SR-P3-G1G2-20261018`
> **Date:** 2026-10-18 (Asia/Shanghai)
> **Nature:** READ-ONLY addendum appending the G1↔G2 boundary formalization and tightening
> `H_Executor`'s logic-isolation verdict. Establishes the "test-side state ≠ argument-side
> state" distinction between `NOT_VERIFIED` (test-lifecycle) and `PASS-部分`/`NOT_ESTABLISHED`
> (argument-lifecycle). Does NOT change code, rerun experiments, modify Frozen Contracts,
> commit, or push. Coexists with `REVIEW-SR-P3-20261018`; supersedes earlier informal boundary notes.

---

## 1. Prior state (why formalization was needed)

`REVIEW-SR-P3-20261018` established proxy-layer support but left G1↔G2 formalized only informally,
and it bundled the logic-isolation verdict inside `NOT_VERIFIED` without separating:

- **Logical isolation** (different Execution State IDs ⇒ different `state_scope`) — present in
  executor's v1 design; **NEVER instrumented** by Swift-call tracing.
- **Actual physical isolation** (old KV cache genuinely unreachable after new Execution State) —
  the G2-relevant claim.

The addendum separates these as **two distinct claims** with a hard dependency (G1 ⇒ G2 is
guarded, not granted).

---

## 2. The two claims — formally separated

### Claim L1 — logical isolation (v1 executor design, G1-lifecycle)

> Statement: "In the current version, different Execution State IDs mean
> different `state_scope`."

Verdict: **PRESENT (design only)**. v1 executor is a dict keyed by Execution State ID, so the
*declaration* holds. **NEVER instrumented** — no Swift-call trace proves a new Execution State
actually rebinds to fresh KV cache. This is the G1 gap: isolation declared but unobserved.

### Claim L2 — actual physical isolation (G2-relevant)

> Statement: "When creating a new Execution State, the old KV cache is unreachable."

Verdict: **NOT_OBSERVED**. In real LLM inference, the "KV cache" is not a hand-managed object —
it is the model weights mutated in place at every forward pass. LLMs have **no KV-cache
invalidation mechanism**; eviction only happens under OOM (context-window fragmentation) or via
external sweepers. So "recompute" ≠ a separate model run — it is **the same weights continuing to
accumulate activations**. L1 ⇒ L2 is a *guarded dependency*: L2 requires *model-level non-cumulative*
proof, an independent claim.

### G1 ⇒ G2 guarded dependency (formalized)

```
G1 PASS  ─┬─> G2 PASS   : NOT automatic (guarded)
           │
           └─ L1 holds but L2 not observed : G1 true, G2 unknown
```

This matches observation Set 3's structural distinction: G1 concern = executor observable;
G2-relevant concern = execution-event observability of a real model.

---

## 3. Why the proxy cannot close L2 (structural, not per-argument)

Per `NOT_VERIFIED`, the proxy's cached-reuse signals are **structural probes**:
`swift_forward_units_this_run()` counts forwarded units per Execution State, and `no_cache_penalty`
flags whether a state triggered cache-miss behavior — in the *proxy layer*, not real model weights.
The proxy is a **deterministic stub**, never the executable executor, so its "cache hit/miss" is
an internal accounting label with **no correlation to real model-work**. Therefore the proxy can
support L1-pattern claims but is structurally incapable of closing L2. The `NOT_VERIFIED` verdict
already encodes this structural gap and now gets a formal boundary line.

---

## 4. P3 Arm-1 evidence — where it lands under the new formalization

Arm-1 (no recompute on unchanged sources) **still supports** the selective-recompute *pattern*,
but under L1/L2 formalization its weight changes:

- `p3-arm1.jsonl` rows 6–9 (no new forwards after marker) prove L1-pattern behavior: after
  `invalidate` + `rerequest`, no new `swift-forward` rows appear ⇒ no *re-entry* into the forward
  path for unchanged units. This is **proxy-layer**, not model-work proof.
- It does **NOT** prove L2: it says nothing about whether weights continued accumulating for the
  unchanged source (that is unknowable at proxy level).

So Arm-1 = **proxy-layer supported for L1-pattern; silent on L2.** Do not read it as cache isolation
proof.

---

## 5. H_Executor verdict — tightened + boundary line (unchanged level)

**Verdict unchanged: `NOT_VERIFIED`.** The addendum tightens *by separating* what the verdict now
covers, not by re-deriving it:

| Item | Status | Boundary line (added) |
|---|---|---|
| Proxy `not_computed_item_ids` (Arm-1/2/3) | **Proxy-layer: SUPPORTED** | proxy ≠ real model; not executor proof; does not close L2 |
| `no_cache_penalty` (Arm-1/2) | **Supports L1-pattern only** | proxy internal accounting; not cache isolation proof; does not close L2 |
| `swift_forward_units_this_run` (Arm-1/2/3) | **Supports L1-pattern only** | no-proxy recompute ⟹ but never real executor; does not close L2 |
| Cache isolation proof (Arm-1/3) | **NOT_OBSERVED** | real-cache-miss never measured at model level; closure requires real Swift Calculator |
| **New: L1 ⇒ G2 guarded dependency** | **State note: recorded** | L1 (proxy) proves L1-pattern only; G2-relevant claim is *independent of executor*, requires model-level evidence |

The guard against **self-validation failure** (Carriers reporting cached reuse as proof of
isolation): proxy cache-hit accounting and `no_cache_penalty` both sit in the Carrier/proxy layer;
a real execution-event trace **outside the proxy** is the only witness. The verdict now states this
boundary explicitly so a future `PASS` cannot be inferred from a single proxy source.

---

## 6. Persistent caveats (carried forward unchanged)

- **proxy-layer PASS on deterministic `swift_forward` stub**: proves executor-integration +
  settlement-reuse + selective-recompute *pattern*; **NOT** real model continuous computation.
- **cache-hit/miss ≠ cache isolation proof**: proxy accounting label, not real model-work.
- **L1 ⇒ L2 guarded dependency is recorded**, not established: L1 (proxy) proves L1-pattern only;
  the model-level continuous-computation claim is *independent of executor*, requires independent
  model-level evidence.
- **Real Swift `Calculator` integration through Python carrier**: still unverified — boundary
  statement stands.

---

## 7. State note

Artifacts under `execution-information-loop/experiment/` and this addendum file are **untracked**
(`git status ??`) as of 2026-10-18. Per instruction: Frozen Contracts untouched, no commit, no
push — evidence kept in working tree for downstream Swift-bridge round.
