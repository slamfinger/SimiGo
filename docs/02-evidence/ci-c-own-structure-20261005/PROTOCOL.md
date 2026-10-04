# CI-C Own-Structure Minimal Discrimination

Date: 2026-10-05  
Status: `CI_C_ONLY · NO_846_MAPPING · NO_INFORMATIONCORE_WRITE · NO_OBSERVER`

## Question

Does the executable continuation function C4 require:

1. C1, an individual information component?
2. C2, a second relational component?
3. C3, the join/relation operator that binds components into C4?

This is not an 846 reduction. Atom identity, merge, deletion, and mapping are out of scope.

## Labels

Use `K1/K2/K3/F` to avoid confusion with model A/B/C/D:

```text
K1 = individual compatibility component
K2 = pair coexistence component
K3 = relational join/admissibility operator
F  = executable continuation function (C4)
```

## Arms

| Arm | K1 | K2 | K3 | Question |
|---|---:|---:|---:|---|
| `FULL` | gamma-specific | present | present | baseline executable function |
| `K1_ONLY` | gamma-specific | absent | present | is K2 necessary? |
| `K2_ONLY` | absent | present | present | is K1 necessary? |
| `GAMMA_REDUCED` | reduced to blocker | present | present | is full K1 necessary, or only discriminating predicate? |
| `K3_DELETED` | present | present as archival text | deleted | is the relational join necessary? |
| `K3_PRECOMPUTED_F` | archival | archival | replaced by precomputed F | can a higher-level substitute preserve F? |
| `ID_BINDING_BROKEN` | service-bound | pair facts use unbound ids | present | is the actual id-binding part of K3? |

## Models

Run only the two semantically usable models:

```text
A qwen3_moe
C gemma4_unified
```

Do not run or retry B. Do not run or retry D.

## Boundary

No Observer. No InformationCore store. No 846 mapping. No atom merge/delete.  
A PASS here is frame-bounded to TC-A-like release continuation.

## Post-first-round replication control

After the first A/C discrimination, model N `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX`
was added as a post-hoc replication control. N is not a replacement for unavailable B and is
not a retry of degenerate D. N was already proven in Reduction Round 1 and is used only to test
whether the aligned pair survives in another effective model:

```text
K3_DELETED        -> C4 absent
K3_PRECOMPUTED_F  -> C4 preserved
```

All seven arms are run for context, but the replication claim is limited to the aligned pair.
