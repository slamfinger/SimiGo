# G-3 Delivery Note v3 — the E-run (first end-to-end auditable I-1 runtime evidence)

Date: 2026-10-05
Gate state: Implementation Gate OPEN — G-1 ACCEPTED/CLOSED, G-2 ACCEPTED/CLOSED; **G-3 re-delivered (v3, incorporating IF-G3-03/04)**; G-4 queued next.
Frozen judgment basis: C-CAP exactly as frozen — success = (a)+(b)+(c) together; "it stored something" is not success.

---

## 1. What changed from v2 (`aa0eb12`) — Human review findings, both FIXED

**IF-G3-04 (MUST FIX — two instantiate lifecycles):** v2 instantiated once in
`main()` (producing the IR under judgment) and again inside `run_e2()`
(producing the S2 that was consumed) — the judged IR and the consumed S2 came
from **different lifecycles**. **Fix:** the E-run now performs **exactly ONE
instantiate**, inside `run_e2()`; the same IR and the same S2 flow through T2
into CR(E2) and into the judgment. (Single call site, verified by grep.)

**IF-G3-03 (MUST FIX — S2 was a guard, not a data source):** v2 used S2 for
identity/consistency checks while the result was built from `r2` — removing
the S2 read would not have changed the result. **Fix:** T2's result digest is
now computed **over the S2 contents** —

```python
s2_material = s2["surface_bytes"] + str(s2["position_units"]).encode() \
            + s2["bound_weights_id"].encode()
result_digest = sha256_hex(s2_material)
```

— a direct, un-bypassable data dependency: change any S2 field and the result
changes. The result text embeds the digest and the S2 surface/position/weights
identities; the trace carries `result_digest` under `executed_on_s2`.

**IF-G3-02 remains CLOSED** (verified by the Human): the full C-CAP judgment
record persists in `G3_ERUN_RECORD.json` (10 entries), and (c) is worded as
*limited mechanical support* with the semantic-escape boundary stated in the
evidence item itself.

## 2. The run (v3) — one lifecycle throughout

```text
E1 executes T1 → CR(E1)
resolve(CR_ref) → RESOLVED, zero violations → R2
instantiate(R2, τ2★, substrate)   [THE single instantiate]
     → IR (COMPLETED / PROCEED-WITH-ANNOTATION; BOUND; VV-1..VV-7 all VERIFIED)
     → S2 (continuation object: surface bytes + handle + bound weights + position)
T2 consumes S2     ← data flow: result digest = sha256(S2 surface + position
                     + weights); binding checks enforced before use
E2 → CR(E2) (lineage parent = CR(E1))
```

## 3. C-CAP results (v3)

| Frozen criterion | Result | Evidence |
|---|---|---|
| (a) clean RESOLVED | **PASS** | RESOLVED, zero violations |
| (b) instantiate + continue **on S2** | **PASS** | same-lifecycle IR + S2; S2 mechanically verified as consumed (surface/handle/weights); **result digest derived from S2 contents** |
| (b)-s2 executed object ≡ R2-derived S2 | **PASS** | surface/handle/weights match the resolved R2 |
| (c) no-recompute (limited document-form support) | **PASS** | predecessor references complete + identifier-disjoint new work + resolve output consumed (boundary stated in the item) |
| chain | **PASS** | CR(E1) → IR(S2) → CR(E2) linked |

**Verdict: C-CAP SUPPORTED (document-form, limited mechanical support on (c))
— 10/10 evidence items PASS, all persisted in `G3_ERUN_RECORD.json` (10 ccap
entries, all pass).**

## 4. Regression

`i1_g1_conformance.py` 19/19 PASS; `i1_g2_conformance.py` 17/17 PASS (delivery
run results; per the registered provenance note).

## 5. Next per the fixed gate order

**G-4 — per-carrier mapping table + audit**, then Implementation Gate closes
with the G-1..G-4 evidence bundle for Human acceptance.
