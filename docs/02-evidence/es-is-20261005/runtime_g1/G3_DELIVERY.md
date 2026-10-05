# G-3 Delivery Note — the E-run (first end-to-end auditable I-1 runtime evidence)

Date: 2026-10-05
Gate state: Implementation Gate OPEN — G-1 ACCEPTED/CLOSED, G-2 ACCEPTED/CLOSED; **G-3 delivered**; G-4 (per-carrier mapping + audit) queued next.
Frozen judgment basis: C-CAP exactly as frozen in I-1d/Gate Package §4 — success = (a)+(b)+(c) together; "it stored something" is not success.

---

## 1. The run

```text
E1 executes T1 (compat analysis; consumes F1..F3 pinned at use time)
   → R1 produced → CR(E1) written (frozen I-1 format, identity hash over
     identity-bearing fields; provenance carries E1.seg[0..3] + weights id)
E1.trace = { segments E1.seg[0..3]; consumed: used-item digests;
             produced: R1 digest }                                   ← C-CAP(c) material
resolve(CR_ref) → state RESOLVED, zero violations → R2 assembled
instantiate(R2, τ2★, substrate) → IR(S2): COMPLETED /
     PROCEED-WITH-ANNOTATION (single annotation: document-form carrier-absent);
     BindingRecord = BOUND; VV-1..VV-7 entered, all VERIFIED (tier profile
     recorded per check)                                            ← C-CAP(a)(b)
E2 executes T2 from the reconstructed S2
   → CR(E2) written; trace = { new segments E2.seg[0..1];
     predecessor_references: E1.seg[0..3] (ALL inherited via R2 lineage);
     consumed: R2 surface + pinned used items }                     ← C-CAP(c)
```

## 2. C-CAP results

| Frozen criterion | Result | Evidence |
|---|---|---|
| (a) clean RESOLVED | **PASS** | resolve state = RESOLVED, zero violations (V-1..V-5) |
| (b) instantiate + continue | **PASS** | IR COMPLETED / PROCEED-WITH-ANNOTATION; E2 produced its result from the reconstructed context |
| (c) no-recompute (document-form) | **PASS** | E2 trace references ALL of E1.seg[0..3]; E2's new segments are disjoint from E1's (no equivalent new segment); E2 consumed the resolve output (necessary condition, recorded as distinct) |
| chain | **PASS** | CR(E1) → IR(S2) → CR(E2): E2's lineage parent is E1's CR |

**Verdict: C-CAP SUPPORTED (document-form) — 9/9 evidence items PASS.**
Full machine-readable record: `G3_ERUN_RECORD.json` (run parameters, IR
verification/tiers, binding record, disposition, CR chain, verdict).

## 3. Registered boundaries (carried, unchanged)

- Detection boundary: a *semantically* equivalent re-derivation under a new
  segment identifier is not caught by (c)-ii — the frozen no-oracle boundary.
- Carrier-form no-recompute (consumed-prefix metrics) was NOT exercised —
  document-form run; the annotation is recorded in the IR.
- The substrate is the conformance testbed (MC-1..MC-6); this is the first
  auditable evidence, not a claim about production substrates.
- E2's T2 specification was an external input (τ2★); resolve inferred nothing.

## 4. Regression

`i1_g1_conformance.py` 19/19 PASS; `i1_g2_conformance.py` 17/17 PASS — no
regression from the E-run additions (delivery-run results; per the registered
provenance note, Human acceptance verifies structure, GitHub CI does not
re-execute).

## 5. Next per the fixed gate order

**G-4 — per-carrier mapping table + audit**: the conformance substrate's
mapping table formalized against I-1d §1.2, audited for full coverage; then
the Implementation Gate closes with the G-1..G-4 evidence bundle for Human
acceptance.
