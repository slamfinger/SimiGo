# Information Structure Reduction Design

Date: 2026-10-04  
Status: `STATIC REDUCTION DESIGN COMPLETE / NO RUNTIME PROBE / NO IRREDUCIBILITY CLAIM`

## 1. Scope

This pass converts the synchronous decomposition into an auditable reduction design. All 846 atoms were classified; no atom was deleted, merged, or executed.

## 2. Source

`docs/00-governance/information-structure/synchronous-decomposition-20261004.json`  
SHA-256: `1c6c5ebc92889fc84d1007f652f465734a88bddb4d3307ea2ef75561809bd4b0`

## 3. Counts

```text
classified atoms                     = 846
canonical groups                     = 22
reduction families                   = 11
cross-object equivalence groups      = 15
candidate relation groups            = 10
discriminating experiment designs    = 17
runtime executions                   = 0
```

## 4. Reduction families

| Family | Atoms |
|---|---:|
| `access_selection` | 82 |
| `adoption_effect_continuation` | 80 |
| `aggregation_variant` | 16 |
| `explanation_optional` | 50 |
| `identity_addressing` | 146 |
| `provenance_binding` | 183 |
| `reconstruction_projection` | 68 |
| `reference_structure` | 29 |
| `representation_variant` | 68 |
| `semantic_core` | 78 |
| `structural_relation` | 46 |

## 5. Canonical groups

| Canonical group | Family | Atoms | Objects |
|---|---|---:|---:|
| `access_delivery` | `access_selection` | 34 | 14 |
| `adoption_relation` | `adoption_effect_continuation` | 29 | 10 |
| `baseline_decision` | `semantic_core` | 26 | 4 |
| `behavioral_effect` | `adoption_effect_continuation` | 45 | 14 |
| `continuation_relation` | `adoption_effect_continuation` | 6 | 1 |
| `execution_binding` | `provenance_binding` | 45 | 5 |
| `identity_scope` | `identity_addressing` | 146 | 32 |
| `issue_explanation` | `explanation_optional` | 50 | 6 |
| `locator_selection` | `access_selection` | 22 | 3 |
| `pair_decision` | `semantic_core` | 24 | 5 |
| `pair_identifier` | `reference_structure` | 7 | 4 |
| `persistence_aggregation` | `aggregation_variant` | 16 | 6 |
| `provenance_integrity` | `provenance_binding` | 94 | 23 |
| `representation_form` | `representation_variant` | 68 | 30 |
| `retrieval_shape` | `access_selection` | 26 | 7 |
| `runtime_evidence` | `provenance_binding` | 21 | 3 |
| `semantic_content_other` | `semantic_core` | 28 | 15 |
| `semantic_reconstruction` | `reconstruction_projection` | 50 | 15 |
| `service_identifier` | `reference_structure` | 22 | 3 |
| `structural_relation` | `structural_relation` | 46 | 20 |
| `task_projection` | `reconstruction_projection` | 18 | 3 |
| `tool_evidence` | `provenance_binding` | 23 | 4 |

## 6. Candidate relation groups

| ID | Type | Statement | Status |
|---|---|---|---|
| `DER-001` | derivation_candidate | U1 exact bytes -> U2 decoded semantic register via first/second JSON decode. | STATIC_ONLY |
| `DER-002` | derivation_candidate | U2 semantic register -> U3 + U4 via projection, preserving version/order/issues. | STATIC_ONLY |
| `DER-003` | derivation_candidate | U3 + U4 -> U2 only when register version, ordering, issue statements and aggregation convention are recoverable. | STATIC_ONLY |
| `DER-004` | derivation_candidate | M1/M2 semantic fields may be recomputable from source configs, but that changes continuation into recomputation. | SEPARATE_RECOVERY_PATH |
| `IND-001` | independence_candidate | U3 baseline facts and U4 pair facts are independent at fact level. | CANDIDATE_ONLY |
| `IND-002` | independence_candidate | U5 provenance is not semantically entailed by U1/U2 and may be independent of narrow task decision. | CANDIDATE_ONLY |
| `IND-003` | independence_candidate | Identity, locator, retrieval and semantic reconstruction may be distinct rather than one access pipeline. | CANDIDATE_ONLY |
| `IND-004` | independence_candidate | Task projection, adoption, behavioral effect and continuation are sequential candidates but may partially collapse. | CANDIDATE_ONLY |
| `CTX-001` | context_candidate | Pair blocks may denote coexistence constraints, not individual blocks; M1.b may anchor that distinction. | SUPPORTED_BY_S_B2R_BOUNDED_RESULT |
| `CTX-002` | context_candidate | M1.b function may arise from baseline-compatible slot interacting with pair decisions, not from gamma-blocked information alone. | SUPPORTED_BY_S_B1I_S_B1S_BOUNDED_RESULT |

## 7. Minimal discriminating experiment designs

These are designs only. No runtime experiment is authorized by this document.

| ID | Family | Question | Boundary |
|---|---|---|---|
| `R-D1` | `aggregation_variant` | Whole decoded register versus U3+U4 decomposition versus bare booleans. | Success does not make the register minimal. |
| `R-D2` | `representation_variant` | Exact U1 bytes versus decoded text versus semantic object under equivalent delivery. | A representation win is frame-bounded. |
| `R-D3` | `semantic_core` | Retain M1.b while deleting M2.b; compare with existing M1.b-retained/M2.b-present result. | Failure of M2 deletion need not prove M2 universally irreducible. |
| `R-D4` | `semantic_core` | Retain all M1 versus gamma-only baseline predicate versus no baseline predicate. | Existing results cover only narrow direct-inline variants. |
| `R-D5` | `explanation_optional` | Add/remove M1.c and M2.c explanations while decisions remain fixed. | Explanation change alone is not continuation gain. |
| `R-D6` | `reference_structure` | Vary service-id set and pair-id set only when task remains solvable by rule. | Do not infer general identifier minimality. |
| `R-D7` | `provenance_binding` | No M3 versus individual M3.a-g versus full provenance bundle. | Task success does not invalidate audit value. |
| `R-D8` | `provenance_binding` | Valid source hashes versus stale hashes versus absent hashes. | Stale detection is separate from immediate continuation. |
| `R-D9` | `provenance_binding` | Tool evidence present versus absent versus summary-only. | Trust shortcut is not provenance minimality. |
| `R-D10` | `identity_addressing` | No identity, non-matching sentinel identity, and correct identity with otherwise fixed payload. | Identity/locator may still be distinct. |
| `R-D11` | `access_selection` | No locator, non-A locator, correct locator, and pre-located direct payload. | Do not collapse locator into identity or retrieval. |
| `R-D12` | `access_selection` | Single-object, set, relation-preserving, projection-time and provenance-only retrieval. | Fetch is not semantic reconstruction. |
| `R-D13` | `reconstruction_projection` | After fetch, ask reconstruction before release decision; compare with direct release. | Paraphrase is not proof of reconstruction. |
| `R-D14` | `reconstruction_projection` | Keep Information fixed while changing release constraints or candidate set. | Task-specific failure does not refute stored semantic structure. |
| `R-D15` | `adoption_effect_continuation` | Add present-but-irrelevant material to test fetch versus adoption. | Mention is not adoption. |
| `R-D16` | `adoption_effect_continuation` | Counterfactual delete adopted field after establishing baseline behavior. | No universal irreducibility claim. |
| `R-D17` | `structural_relation` | For repeated normalized labels, test cross-object merge against independent-context explanation. | Surface repetition alone is not duplication. |

## 8. Merge discipline

15 cross-object exact-label groups are registered as merge candidates only. None was merged.

For each group, a future test must distinguish:

```text
duplicated content;
shared reference;
representation variant;
independent semantic structure.
```

## 9. Boundary

```text
Observer                 = NOT RUN;
InformationCore store    = NOT RUN;
Runtime probe            = NOT RUN;
schema/API change        = NOT MADE;
minimal structure claim  = NOT MADE;
irreducibility claim     = NOT MADE.
```
