# G-2 Delivery Note — Instantiate Pipeline + Verification Surface (Gate scope G-2)

Date: 2026-10-05
Gate state: Implementation Gate OPEN — G-1 ACCEPTED/CLOSED; **G-2 delivered**; G-3 (E-run) queued next per the fixed order.
Frozen sources realized: I-1c (`IPAC_INSTANTIATE_COMPLETENESS_CONCEPTUAL_DESIGN_V0.3.md`, main `6c3cf6a`) + I-1d (`IPAC_INSTANTIATE_RUNTIME_REALIZATION_VERIFICATION_CONCEPTUAL_DESIGN_V0.3.md`, branch `1832676`). Zero contract modifications.

---

## 1. Delivered artifacts

```text
runtime_g1/i1_instantiate.py       the pipeline (steps 0-5) + Verification
                                   Surface VV-1..VV-7 with tiers + BindingRecord
                                   three-state decision + dispositions/lifecycle
runtime_g1/i1_g2_conformance.py    14 implementation self-checks proving the
                                   frozen semantics hold TOGETHER inside one
                                   instantiate lifecycle (no drift)
```

## 2. Mapping (frozen clause → implementation)

| Frozen clause | Realization | Conformance |
|---|---|---|
| pipeline steps 0-5 | precondition → bind → restore(opt) → materialize [CREATION POINT] → attach → record | checks 01/02/07 |
| step 0 precondition | R2 must be clean RESOLVED (degraded ≠ clean — D-2 note enforced) + τ2 present; else IR closed BLOCK/PRECONDITION-BLOCK | check 02 |
| IC-2 binding three-state | BOUND / UNBOUND / MISMATCH from (lineage provenance, τ2★ declaration) — mechanical, no inference | checks 01c/03/04/05 |
| VV applicability | surface entered only after precondition passes; PRECONDITION-BLOCK ⇒ VV-1..7 NOT ENTERED (applicability fact, not a tier) | checks 02/02b |
| verdict tiers | VERIFIED / COVENANTED / FAILED only; per-check tier profile in the IR | checks 01b/08/10 |
| IC-4/SC-4 lineage attach | E1.seg + A-chain segment identifiers bound into S2's context | checks 01/07 |
| IC-5/PD-6 position | derived (tokenize(surface) under bound tokenizer), recorded | check 07 |
| VV-7 manifest | engine/weights/tokenizer identity recorded | check 08 |
| dispositions exhaustive | BLOCK{PRECONDITION-BLOCK, CREATE-BLOCK, POLICY-BLOCK} / PROCEED-WITH-ANNOTATION / DECLARED-ALTERNATIVE — exactly one primary per outcome | checks 02/04/05/06 |
| MISMATCH decided by envelope (frozen final patch) | allowed → DECLARED-ALTERNATIVE; lineage-strict required → BLOCK/POLICY-BLOCK at step 1 (before materialize) | checks 04/05 |
| POST-CREATION-ANOMALY | lifecycle fields present in every IR (orthogonal; not exercised to completion at G-2 — recovery tested at G-3) | field presence |
| document-form scoping | restore not taken; carrier-absent annotation recorded | checks 01/09 |

## 3. Implementation Findings

**IF-G2-01 — registered and FIXED during self-checks:**

```text
Type:  Implementation defect (a frozen-rule miss, not a contract conflict)
Issue: MISMATCH + cross-model-allowed was disposed as PROCEED-WITH-ANNOTATION
       (with a MISMATCH annotation); the frozen I-1d final patch requires
       the primary disposition to be DECLARED-ALTERNATIVE — the envelope
       decides, no side-branch.
Fix:   the MISMATCH/allowed branch now returns class DECLARED-ALTERNATIVE
       directly (with the MISMATCH annotation carried); conformance case 04
       asserts the class.
```

**IF-G2-02 — registered and FIXED:** the pipeline never called
`substrate.bind(...)` (the BindingRecord was decided but the substrate was
never configured; surfaced as VV-4's readback crashing). Fixed: step 1 now
performs the actual substrate bind with the declared weights identity.

**No Frozen Contract conflict.** Two additional test-side corrections
(annotation-set expectation; the `entered()` helper now tests verdict tiers,
not entry existence) were conformance defects, not implementation ones.

## 4. Conformance results

`python3 i1_g2_conformance.py` → **14/14 PASS**; `i1_g1_conformance.py` →
19/19 PASS (no regression). Coverage: both BLOCK subtypes + POLICY-BLOCK,
all three binding states, DECLARED-ALTERNATIVE, tier-profile recording,
VV applicability boundary, IR lifecycle field completion, single-primary-
disposition on every exercised path.

## 5. Next per the fixed gate order

**G-3 — the E-run**: one end-to-end pass (E1 → CR(E1) → resolve → R2 →
instantiate → IR(S2) → T2 → CR(E2)) with C-CAP (a)(b)(c) measured, using
G-1 + G-2 as the runtime. Then G-4 (per-carrier mapping + audit).
