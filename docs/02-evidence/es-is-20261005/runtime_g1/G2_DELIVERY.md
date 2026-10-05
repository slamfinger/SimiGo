# G-2 Delivery Note — Instantiate Pipeline + Verification Surface (Gate scope G-2)

Date: 2026-10-05
Gate state: Implementation Gate OPEN — G-1 ACCEPTED/CLOSED; **G-2 re-delivered** (v2, incorporating IF-G2-01..06); G-3 (E-run) queued next per the fixed order.
Frozen sources realized: I-1c (`IPAC_INSTANTIATE_COMPLETENESS_CONCEPTUAL_DESIGN_V0.3.md`, main `6c3cf6a`) + I-1d (`IPAC_INSTANTIATE_RUNTIME_REALIZATION_VERIFICATION_CONCEPTUAL_DESIGN_V0.3.md`, branch `1832676`). Zero contract modifications across both delivery rounds.

---

## 1. Delivered artifacts

```text
runtime_g1/i1_instantiate.py       the pipeline (steps 0-5) + Verification
                                   Surface VV-1..VV-7 with tiers + BindingRecord
                                   three-state decision + dispositions/lifecycle
                                   + OpaqueSubstrate (IF-G2-06 path)
runtime_g1/i1_g2_conformance.py    17 implementation self-checks proving the
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
| verdict tiers | VERIFIED / COVENANTED / FAILED only; per-check tier profile in the IR; **COVENANTED path realized on an opaque substrate (06b)** | checks 01b/06b/08/10 |
| IC-4/SC-4 lineage attach | E1.seg + A-chain segment identifiers bound into S2's context | checks 01/07 |
| IC-5/PD-6 position | derived (tokenize(surface) under bound tokenizer), recorded | check 07 |
| VV-7 manifest | engine/weights/tokenizer identity recorded | check 08 |
| dispositions exhaustive | BLOCK{PRECONDITION-BLOCK, CREATE-BLOCK, POLICY-BLOCK} / PROCEED-WITH-ANNOTATION / DECLARED-ALTERNATIVE — exactly one primary per outcome on every exercised path | checks 02/04/05/06/06c |
| MISMATCH decided by envelope (frozen final patch) | allowed → DECLARED-ALTERNATIVE recorded with the COMPLETED IR (full lifecycle continues); lineage-strict required → BLOCK/POLICY-BLOCK at step 1 (before materialize) | checks 04/05 |
| creation-point boundary (frozen) | materialize failure → CREATE-BLOCK; **any FAILED check past creation → POST-CREATION-ANOMALY (lifecycle) + PROCEED-WITH-ANNOTATION, never CREATE-BLOCK** | check 06c |
| VV numbering frozen | no VV-8; restore metrics = IR instrumentation annotation, never a check | — (absence asserted by the frozen vocabulary check 10) |
| document-form scoping | restore not taken; carrier-absent annotation recorded | checks 01/09 |
| POST-CREATION-ANOMALY | lifecycle fields in every IR; **anomaly transition exercised (06c)** with recovery default recorded; recovery attempt transition lands at G-3 | field presence + check 06c |

## 3. Implementation Findings

Round 1 (v1, `95bde40`): IF-G2-01, IF-G2-02 — registered and FIXED.
Round 2 (Human review of v1): four Findings registered, **all FIXED** in this delivery:

```text
IF-G2-03 (MUST FIX)  MISMATCH+allowed terminated the lifecycle early
                     (primary disposition misused as lifecycle termination).
                     Fix: the pipeline continues steps 2-5; DECLARED-
                     ALTERNATIVE is recorded with the COMPLETED IR.
                     Conformance: case 04 asserts a COMPLETED stage +
                     manifest + DECLARED-ALTERNATIVE.

IF-G2-04 (MUST FIX)  "VV-restore" invented an eighth Verification check —
                     the VV numbering is frozen at VV-1..VV-7. Fix: restore
                     metrics are lifecycle instrumentation (IR annotation),
                     never a check. Case 10 (frozen vocabulary) guards it.

IF-G2-05 (MUST FIX)  FAILED checks after the creation point returned
                     CREATE-BLOCK. Fix: post-creation FAILED →
                     POST-CREATION-ANOMALY (lifecycle state) + primary
                     disposition PROCEED-WITH-ANNOTATION (anomaly annotation;
                     conservative re-instantiation recovery recorded).
                     Conformance: case 06c (unfaithful substrate) proves it.

IF-G2-06 (MUST FIX before acceptance)  COVENANTED was never exercised — the
                     readback substrate made every path VERIFIED. Fix:
                     OpaqueSubstrate (no readback interface); its VV-2/VV-4
                     land COVENANTED with the explicit covenant recorded and
                     ENVELOPE-DRIFT not claimable. Conformance: case 06b.
```

**Coverage downgrade per Human review (registered):** v1's case 06 claimed "every outcome" while exercising one path — corrected to "every **exercised** outcome (BOUND/MISMATCH/UNBOUND)". POST-CREATION-ANOMALY coverage in v1 was field-presence only — now the anomaly transition itself is exercised (06c); the **recovery-attempt transition** remains G-3 scope and is stated as such.

Round 3 (Human review of v2): two Findings registered, **both FIXED** in this delivery:

```text
IF-G2-07 (MUST FIX)  post_creation_anomaly() derived the check id from the
                     signature prefix ("SURFACE-INFIDELITY" -> check
                     "SURFACE"), drifting the VV-2/VV-4 ownership. Fix: the
                     helper takes the VV check id EXPLICITLY; the anomaly
                     record and lifecycle carry check="VV-2"/"VV-4".
                     Conformance: case 06c asserts the ownership field.

IF-G2-08 (MUST FIX)  VV-4's VERIFIED/COVENANTED decision relied on
                     isinstance(OpaqueSubstrate) + private-state reads
                     (_envelope) — a class-name boundary, not a capability
                     boundary. Fix: substrates declare readback observability
                     via an explicit capability interface
                     (surface_readback_available() / envelope_readback());
                     the pipeline follows the declared capability. Opaque
                     behavior without the OpaqueSubstrate class is proven by
                     case 06d (CapabilityRevokedSubstrate: same readback-
                     capable class, capability declared absent -> VV-2/VV-4
                     COVENANTED).
```

**No Frozen Contract conflict in either round.** Remaining self-check corrections were conformance defects (annotation expectation; `entered()` semantics = verdict tiers, not entry existence), not implementation or contract issues.

## 4. Conformance results

**Provenance note (registered per Human review of v2):** the counts below are
the delivery's own run results; the Human acceptance verified the source and
test structure (GitHub CI/status did not re-execute them).

`python3 i1_g2_conformance.py` → **17/17 PASS**; `i1_g1_conformance.py` →
19/19 PASS (no regression). Coverage: all three BLOCK subtypes (incl. the
policy-gated POLICY-BLOCK at step 1), all three binding states, both
non-BLOCK classes, the COVENANTED tier on TWO substrate paths (OpaqueSubstrate
and the capability-revoked same-class substrate — proving the decision follows
the declared capability, not the class), the anomaly lifecycle transition with
explicit VV ownership, tier-profile recording, the VV applicability boundary,
and single-primary-disposition on every exercised path.

## 5. Next per the fixed gate order

**G-3 — the E-run**: one end-to-end pass (E1 → CR(E1) → resolve → R2 →
instantiate → IR(S2) → T2 → CR(E2)) with C-CAP (a)(b)(c) measured, using
G-1 + G-2 as the runtime. Then G-4 (per-carrier mapping + audit).
