# N-Model Replication of the CI-C Critical Pair

Date: 2026-10-05  
Status: `CRITICAL_PAIR_REPLICATED · INVARIANT_RENAMED · NO_846_MAPPING`

## Purpose

Model N `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX` was added as a post-hoc
effective-model control. N is not a replacement for unavailable B and is not a retry
of degenerate D. N had already produced valid Round-1 outputs.

## Critical pair

| Arm | A | C | N | Result |
|---|---|---|---|---|
| `K3_DELETED` | C4 absent | C4 absent | C4 absent | **Replicated** |
| `K3_PRECOMPUTED_F` | C4 preserved | C4 preserved | C4 preserved | **Replicated** |

This is now the strongest aligned result:

```text
Delete the relational executable function:
        K1/K2 may remain, but C4 disappears.

Replace explicit K3 with a precomputed higher-level result:
        C4 survives.
```

Therefore the candidate invariant should not be called `K3 minimal structure`.
The better name is:

> **relational executable admissibility function**

or, more generally:

> **relational executable function**

## Important revision: K2 is not a surface invariant

N changes the earlier component reading.

| Arm | A | C | N | Surface reading |
|---|---|---|---|---|
| `K1_ONLY` | degraded | degraded | preserved | K1 is not a surface cross-model necessity. |
| `K2_ONLY` | degraded | preserved | preserved | K2 is not a surface cross-model necessity. |
| `ID_BINDING_BROKEN` | degraded | preserved | preserved | Id binding is not a surface cross-model necessity. |

However, the preserved C4 results in `K1_ONLY`, `K2_ONLY`, and
`ID_BINDING_BROKEN` require unauthorized inference:

- `K1_ONLY`: the model infers pair compatibility not supplied.
- `K2_ONLY`: the model infers individual incompatibility not supplied.
- `ID_BINDING_BROKEN`: the model infers the missing id mapping.

So the cleaner distinction is:

```text
Surface C4:
    order/block shape survives.

Authorized C4:
    order/block shape survives without recovering an explicitly unavailable relation.
```

Under **authorized C4**, K1 and K2 remain load-bearing.  
Under **surface C4**, they are not invariant.

## Hypothesis update

### H1 — components plus function

Partly supported, but only for the authorized route.  
K1/K2 are not pure cross-model component invariants.

### H2 — K2 already contains the relation

Not established.  
Apparent `K2_ONLY` success depends on unauthorized inference.

### H3 — relational executable structure

Best supported.  
The recurring requirement is not K1, K2, or the explicit K3 serialization.  
It is an authorized executable admissibility function that can be realized as:

```text
component data + relational operator
or
precomputed higher-level function
```

## Current candidate

> **Relational executable admissibility function is the CI-C candidate invariant.**

This is still frame-bounded to the TC-A-like continuation task.  
It is not yet a general Information Core and does not authorize 846 mapping.

## Boundary

No 846 atom was mapped, merged, deleted, or rewritten.  
No Observer was run.  
No InformationCore write occurred.  
No B retry or D retry occurred.  
No minimal Information Core was declared.
