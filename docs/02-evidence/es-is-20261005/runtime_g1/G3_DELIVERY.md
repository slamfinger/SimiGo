# G-3 Delivery Note v2 — the E-run (first end-to-end auditable I-1 runtime evidence)

Date: 2026-10-05
Gate state: Implementation Gate OPEN — G-1 ACCEPTED/CLOSED, G-2 ACCEPTED/CLOSED; **G-3 re-delivered (v2, incorporating IF-G3-01/02)**; G-4 queued next.
Frozen judgment basis: C-CAP exactly as frozen — success = (a)+(b)+(c) together; "it stored something" is not success.

---

## 1. What changed from v1 (`bcbaafd`) — Human review findings, both FIXED

**IF-G3-01 (MUST FIX — the core experimental problem):** v1's E2 never
consumed the continuation object instantiate produced — it constructed CR(E2)
in parallel, so S2 was "recorded/claimed to exist", not "actually consumed by
the subsequent computation". **Fix:** the substrate now exposes the realized
continuation object (`continuation_object()`: materialized surface bytes +
handle digest + bound weights + derived position); **T2's execution adapter
consumes THAT object** — with mechanical binding checks before use (S2
surface ≡ resolved R2 surface; handle digest ≡ R2 surface digest; bound
weights ≡ declared τ2★ weights; any mismatch raises and aborts the run). E2's
result is now **derived from the S2-carried surface** (no hardcoded result
string).

**IF-G3-02 (evidence semantics tightened):** the no-recompute claim is now
worded and structured as what the document-form evidence actually supports —

```text
C-CAP(c)-i    E2's trace references ALL inherited predecessor segments
C-CAP(c)-ii   E2 reused NO predecessor segment identifier for new work
              (limited mechanical support; semantic re-derivation under a
              new id is the registered detection boundary — stated in the
              evidence item itself)
C-CAP(necessary) E2 consumed the resolve output (necessary, distinct)
```

plus a new (b)-sub-item: **C-CAP(b)-s2 — "the executed object IS the
R2-derived S2"** (surface/handle/weights mechanically matched).

**Persistence fix:** `G3_ERUN_RECORD.json` now contains the **full C-CAP
judgment record** — every `ev()` item (10 entries, pass/detail) lands in the
machine-readable record; the verdict is no longer stdout-only.

## 2. The run (v2)

```text
E1 executes T1 → CR(E1) (F1..F3 use-time pinned; provenance: E1.seg[0..3],
     weights id)
resolve(CR_ref) → RESOLVED, zero violations → R2
instantiate(R2, τ2★, substrate) → IR(S2): COMPLETED / PROCEED-WITH-ANNOTATION;
     BindingRecord = BOUND; VV-1..VV-7 entered, all VERIFIED (tier profile
     recorded)
T2 executes ON the S2 continuation object (mechanical binding checks pass;
     result derived from the S2-carried surface)
E2 → CR(E2); trace = { new segments E2.seg[0..1]; predecessor_references:
     E1.seg[0..3]; consumed: R2 surface + pinned items; executed_on_s2: … }
```

## 3. C-CAP results (v2)

| Frozen criterion | Result | Evidence |
|---|---|---|
| (a) clean RESOLVED | **PASS** | RESOLVED, zero violations |
| (b) instantiate + continue **on S2** | **PASS** | COMPLETED/PROCEED-WITH-ANNOTATION + **S2 mechanically verified as consumed** (surface/handle/weights) + result derived from the S2 surface |
| (c) no-recompute (limited document-form support) | **PASS** | predecessor references complete + identifier-disjoint new work + resolve output consumed (boundary stated in the evidence item) |
| (b)-s2 executed object ≡ R2-derived S2 | **PASS** | new sub-criterion per IF-G3-01 |
| chain | **PASS** | CR(E1) → IR(S2) → CR(E2) linked |

**Verdict: C-CAP SUPPORTED (document-form, limited mechanical support on (c))
— 10/10 evidence items PASS, all persisted in `G3_ERUN_RECORD.json`.**

## 4. Regression

`i1_g1_conformance.py` 19/19 PASS; `i1_g2_conformance.py` 17/17 PASS (delivery
run results; per the registered provenance note).

## 5. Next per the fixed gate order

**G-4 — per-carrier mapping table + audit**, then Implementation Gate closes
with the G-1..G-4 evidence bundle for Human acceptance.
