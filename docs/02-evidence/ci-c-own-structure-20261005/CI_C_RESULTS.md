# CI-C Own-Structure First Discrimination

Date: 2026-10-05  
Status: `FIRST_DISCRIMINATION_COMPLETE · MINIMUM_NOT_DECLARED · NO_846_MAPPING`

## Criterion

The executable continuation core `C4` is preserved only when:

```text
deployment_order == ["alpha", "beta"]
blocked_service_ids == ["gamma"]
```

The wording of `release_decision` is not part of this core criterion.  
`C4` is absent when the output explicitly returns:

```text
deployment_order = []
error = deployment_admissibility_relation_unavailable
```

## Arm results

| Arm | A qwen3_moe | C gemma4_unified | Reading |
|---|---|---|---|
| `FULL` | degraded | preserved | A has no valid positive baseline here. |
| `K1_ONLY` | degraded | degraded | `K2` is necessary in both runnable models. |
| `K2_ONLY` | degraded | preserved | `K1` necessity is model-dependent. |
| `GAMMA_REDUCED` | degraded | preserved | C supports reducing `K1` to the gamma blocker; A is inconclusive. |
| `K3_DELETED` | absent | absent | Strongest aligned result: relational admissibility operator is load-bearing. |
| `K3_PRECOMPUTED_F` | preserved | preserved | Explicit `K3` is substitutable by a precomputed higher-level result. |
| `ID_BINDING_BROKEN` | degraded | preserved | Id-binding necessity is model-dependent. |

## Interpretation

The result is **not** simply “C1 + C2 + C3 are all necessary.”

The cleaner reading is:

1. **K2 is necessary in both runnable models.**  
   Removing the pair/coexistence component degrades C4 in A and C.

2. **K1 is not yet a cross-model necessary component.**  
   C preserves C4 in `K2_ONLY`; A does not.

3. **K3 is functionally load-bearing, but not representationally unique.**  
   When the relational admissibility operator is deleted, both models lose C4.  
   But when a precomputed higher-level result is supplied, both preserve C4 without applying K3.

4. **A cannot currently serve as a positive control for CI-C.**  
   A fails even `FULL`; therefore A-specific component readings are inconclusive.

5. **No cross-model minimum is established.**  
   The C-model frame suggests `K2 + relational admissibility function`, but this is not stable across A.

## Direct answer to the three outcomes

- If `C3` is destroyed and `C4` disappears, relation structure is load-bearing.  
  This happened in both runnable models for `K3_DELETED`.

- If `C3` is replaced by precomputed `C4` and function survives, explicit relation form is not unique.  
  This happened in both runnable models for `K3_PRECOMPUTED_F`.

- Therefore the current candidate is not “C3 as optional notation,” but also not “this exact C3 serialization is minimal.”  
  The candidate is: **an executable admissibility relation/function is load-bearing; its explicit form can be replaced by an equivalent higher-level function.**

## Boundary

No 846 atom was mapped, merged, deleted, or rewritten.  
No Observer was run.  
No InformationCore write occurred.  
No full cross-model stability claim was made.  
No minimal Information Core was declared.
