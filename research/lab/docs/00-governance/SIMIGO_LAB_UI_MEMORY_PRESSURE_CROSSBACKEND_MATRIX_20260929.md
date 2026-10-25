# SimiGo Lab UI Memory Pressure Cross-Backend Matrix — 2026-09-29

## Result

```text
UI15 = PASS_WITH_BOUNDARY / CONTROLLED_MEMORY_PRESSURE_OUTCOME_SHAPE_MATRIX
CROSSBACKEND_CLOSURE = OPEN / MODEL_EXECUTION_AND_MECHANISM_DIFFERENCES
```

登记：

```text
UI15_CONTROLLED_MEMORY_PRESSURE_OUTCOME_SHAPE_MATRIX_PASS
EIGHT_COMMON_CHECKS_PASS_ON_LLAMA_AND_MLX
PHYSICAL_PRESSURE_MECHANISM_DIFFERENCES_PRESERVED
```

这是 LLAMA与 oversized MLX controlled memory-pressure action的 outcome-shape
matrix；不是 same-checkpoint closure、performance benchmark、production policy或
OS pressure validation。

## Controlled workload

```text
seedText          = def is_palindrome(s):
controlInput      = Now write tests for it.
pressureInputs    = List one edge case for the function.
                    Add a focused unit test for that edge case.
tokens/turn       = 1
cycles            = 2
active pressure   = 2
release actions   = 4 per backend
seed              = 42
```

LLAMA使用 canonical mitigated ubatch8 profile；MLX使用 oversized
Qwen3-Coder-Next-4bit、segment size 8、cacheless greedy recompute。

## Common outcome checks

| Check | Result |
| --- | --- |
| `PRESSURE_WORKLOAD_COMPLETE` | PASS |
| `PRESSURE_RELEASE_ACTIONS_COMPLETE` | PASS |
| `PRESSURE_LINEAGE_ISOLATED` | PASS |
| `ACTIVE_BRANCH_PREFIXES_DIVERGED` | PASS |
| `REPEATED_RECOVERY_OUTPUTS_EXACT` | PASS |
| `RECOVERY_FINAL_BINDINGS_EXACT` | PASS |
| `RELEASE_PRESSURE_BRANCHES` | PASS |
| `ROOT_AND_CONTROL_SURVIVE` | PASS |

Matrix result：

```text
sameWorkloadShape  = true
sameOutcomeShape   = true
bothBackendsPass   = true
crossBackendClosure = false
```

## Backend-specific observations

```text
LLAMA = PASS / 8 checks
  mechanism = Swift prefix-registry release/restore

MLX   = PASS / 10 checks
  mechanism = Swift prefix registry release + oversized segment release
  peak footprint = 6,628 MiB
  max swap       = 0 MiB
  transitions    = 48
```

机制差异保留：LLAMA的 controlled action不释放 llama-server native cache；MLX
额外释放 oversized segment representation。这不伪装为同一 physical mechanism。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-memory-pressure-crossbackend-matrix.json
```

实现入口：

```text
UIBranchSessions.runMemoryPressureCrossBackendMatrix
CLI: ui-memory-pressure-matrix
```

## Boundary

结果限定 current model artifacts、tokenizers、canonical LLAMA profile、MLX
segment size 8、1-token generation、2 cycles和本机 harness。所有结果都是
harness-level controlled session pressure observation；不是 product UI、
persistent session、OS memory-pressure injection、production cancellation
readiness、performance benchmark或 same-checkpoint closure。

## Non-claims

```text
❌ OS memory pressure 已被触发或验证
❌ same-checkpoint cross-backend closure
❌ LLAMA native cache与 MLX segment机制等价
❌ production memory-pressure readiness
❌ performance benchmark
```

## Next

1. OS/server pressure-injection protocol需要单独立项。
2. 可选增加 branch count、context length、cycles或同一 checkpoint/family
   对照；不得把当前 outcome-shape matrix升级为 closure claim。
