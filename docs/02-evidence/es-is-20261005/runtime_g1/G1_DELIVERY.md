# G-1 Delivery Note — CR/IR Formats + Resolve (Implementation Gate, scope G-1)

Date: 2026-10-05
Gate state: Implementation Gate OPEN (Human ruling) — scope G-1 delivered; G-2 next per the fixed order.
Frozen sources realized: I-1 (`IPAC_PERSISTENCE_RESOLVE_CONCEPTUAL_DESIGN_V0.3.md`, main `2b2e2ef`) + the I-1d IR field list/lifecycle (`..._V0.3.md`, branch `1832676`). Zero contract modifications.

---

## 1. Delivered artifacts

```text
runtime_g1/i1_records.py           CR format (identity hash, canonical order,
                                   formation baseline, provenance outside the
                                   identity hash), IR format (frozen §1.1 field
                                   list + lifecycle stages ESTABLISHED / CREATED /
                                   COMPLETED / CLOSED / ANOMALY + validators),
                                   ContentStore (write-once nodes + blobs)
runtime_g1/i1_resolve.py           resolve(CR_ref): V-1..V-5 with frozen failure
                                   signatures, three-state output, R2 assembly
runtime_g1/i1_g1_conformance.py    17 implementation self-checks (realization
                                   verification — not the E-run, which stays
                                   gated at G-3)
```

## 2. Mapping (frozen clause → implementation)

| Frozen clause | Realization | Conformance |
|---|---|---|
| V-1(i) CR self-identity | `recompute_cr_identity(node) == cr_ref` | check 04 → CR-ID-MISMATCH |
| V-1(ii) referability | result + used targets EXIST at pinned addresses | checks 03/12/17 → I-NF / C-REF-NOT-FOUND |
| V-2 content match | result + used items re-hashed ≡ pinned digests | checks 02/18 → I-MISMATCH |
| V-3 lineage integrity | chain walk: self-identity + visited-set | checks 05/06/07 → A-SUB / A-NF / A-CYCLE |
| V-4 surface integrity | stored surface digest equality | check 08 → P-VIOLATION |
| V-5 formation baseline | enumerated fields, hash equality only | check 09 → FORM-DRIFT |
| three-state output | RESOLVED / RESOLVED-WITH-VIOLATIONS / UNRESOLVABLE | checks 01–09 |
| IR lifecycle (I-1d) | attempt record at step 0 → completed / closed / anomaly | checks 13–16 |
| drop-test property | provenance outside the identity hash | checks 10–11 |
| segment provenance | E1.seg ids travel CR provenance → R2 lineage | check 01b |

## 3. Implementation decisions (within frozen constraints; alternatives registered)

- **D-1 canonical order**: used-set sorted lexicographically over (content_digest, ref) byte strings — the frozen "deterministic serialization from content identities", pinned here.
- **D-2 I-NF classification**: a missing used item yields RESOLVED-WITH-VIOLATIONS (traversal completes; the item is unmaterializable and signed). The alternative (UNRESOLVABLE) is registered; the frozen text ("the record cannot be traversed") was read as governing the *record*, not individual targets.
- **D-3 store layout**: content-addressed blobs + write-once JSON nodes (MC-4 minimal form). The store is not the IS — it realizes IS persistence.
- **D-4 formation fields**: enumerated as {procedure_id, input_digests}; V-5 = baseline hash recomputation + input resolvability (blob or node — formation inputs may reference CR nodes).
- **D-5 structural finding (wording tightened per Human review)**: under the frozen identity construction (parent refs hashed into CR identities) **and** immutable identity-addressed storage, a lineage cycle cannot be constructed through a conforming write path — a forced cycle requires identity verification to be bypassed or storage corruption/substitution. The A-CYCLE visited-set guard is retained as defense-in-depth and exercised via the conformance instrument (`verify_lineage_identity=False`).
- **D-6 R2 carries the result item** (digest + bytes) alongside the three frozen components: the result is the resolution target itself and is required for T2 binding. The frozen R2 definition is unchanged — this documents where the resolution target travels.

## 4. Implementation Findings

**IF-G1-01** — registered and **FIXED** in this delivery:

```text
Type:     Implementation Finding
Class:    mapping / verification-attribution
Severity: MUST FIX before G-1 final acceptance
Issue:    result content mismatch was emitted under V-1; the frozen mapping
          places I-MISMATCH under V-2.
Fix:      V-1(ii) checks result referability only (absent → C-REF-NOT-FOUND);
          V-2 owns result content-match (present, hash ≠ pinned → I-MISMATCH).
          Conformance cases 17/18 assert the attribution via the check field.
```

Other notes (code defects, not contract conflicts): store write-once vs tamper simulation; V-5 resolvability scope — both fixed during self-checks and required no frozen-object change.

**Boundary notes (Human review, binding):**

- **Validator scope**: `ir_validate_completed` is a **G-1 format validator**, not the full I-1d compliance checker — VV-1..VV-7 completeness is a **G-2 obligation**.
- **D-2 visibility for G-2/G-3**: RESOLVED-WITH-VIOLATIONS ≠ clean RESOLVED. The instantiate precondition requires a clean RESOLVED R2; a degraded resolve result must never enter instantiate as if clean. (The current code contains no such smuggle — this registration keeps it that way.)

## 5. Conformance results

`python3 i1_g1_conformance.py` → **19/19 PASS** (includes the IF-G1-01 attribution cases 17/18, which assert the *check field* — V-1 vs V-2 — not just the signature). The suite covers every frozen resolve-side failure signature and the IR lifecycle/closure formats.

## 6. Next per the fixed gate order

**G-2 — instantiate pipeline (steps 0–5) + Verification Surface VV-1..VV-7** over a carrier satisfying MC-1..MC-6, consuming a RESOLVED R2 from G-1. Then G-3 (the E-run), then G-4 (per-carrier mapping + audit).
