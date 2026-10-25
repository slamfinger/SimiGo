# SimiGo Lab UI Branch Sessions Long-Running Cross-Backend Matrix — 2026-09-29

## Result

```text
UI12 = PASS_WITH_BOUNDARY / LONG_RUNNING_OUTCOME_SHAPE_MATRIX
CROSSBACKEND_CLOSURE = OPEN / MODEL_AND_EXECUTION_DIFFERENCES
```

登记：

```text
UI12_LONG_RUNNING_CROSSBACKEND_OUTCOME_SHAPE_MATRIX_PASS
SIX_TURN_SAME_PROMPT_SEQUENCE_CONTROLLED
CROSSBACKEND_MODEL_AND_EXECUTION_DIFFERENCES_PRESERVED
```

这是 LLAMA与 oversized MLX long-running branch的 outcome-shape matrix；不是
same-checkpoint closure、performance benchmark或 production readiness。

## Controlled workload

```text
seedText       = def is_palindrome(s):
rootInput      = Explain it briefly.
siblingInput   = Now write tests for it.
turnInputs     = six fixed implementation prompts
turns          = 6
tokensPerTurn  = 4
graph          = root -> long branch; root -> sibling baseline
```

LLAMA backend：

```text
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL GGUF
canonical mitigated server profile
predictionTokens = 4
```

MLX backend：

```text
Qwen3-Coder-Next-4bit oversized snapshot
segment size 8 / 6 segments
cacheless greedy recompute
maxTokens = 4
```

两者使用相同 prompt sequence和 workload shape；模型 artifact、tokenizer、execution
engine和 KV/cache strategy不同。

## Common outcome checks

七项 common outcome checks全部 PASS：

| Check | LLAMA | MLX |
| --- | --- | --- |
| `LONG_SEQUENCE_COMPLETE` | PASS | PASS |
| `LONG_BRANCH_FINAL_PREFIX_EXACT` | PASS | PASS |
| `LONG_BRANCH_RESTORES_FORKPOINT` | PASS | PASS |
| `LONG_BRANCH_RESTORES_FINAL_POSITION` | PASS | PASS |
| `SIBLING_BASELINE_RETAINED` | PASS | PASS |
| `RELEASE_LONG_AND_SIBLING` | PASS | PASS |
| `ROOT_SURVIVES_RELEASE` | PASS | PASS |

Matrix result：

```text
sameWorkloadShape       = true
sameOutcomeShape        = true
bothBackendsPass        = true
crossBackendClosure     = false
closureBlocker          = DIFFERENT_MODEL_ARTIFACTS_TOKENIZERS_AND_EXECUTION_ENGINES
```

MLX backend-specific check：

```text
OVERSIZED_PROFILE_UNDER_30GIB = PASS
peak footprint = 8,019 MiB
max swap        = 0 MiB
segment transitions = 170
```

## Artifacts

```text
ui-branch-session-llama-long-running.json
ui-branch-session-mlx-long-running-t4.json
ui-branch-session-long-running-crossbackend-matrix.json
```

所有文件位于：

```text
simigo2-experimental/results/backend-conformance/
```

## Boundary

这是 outcome-shape matrix，不是 same-checkpoint closure。LLAMA和 MLX的 model
artifact、tokenizer、quantization、execution engine和 state representation不同。
不建立 performance equivalence、production readiness或 causal explanation。

## Non-claims

```text
❌ same-checkpoint cross-backend closure
❌ performance equivalence
❌ production cancellation / long-running readiness
❌ product UI
❌ persistent / multi-process session
```

## Next

1. 若要推进 closure，需要 same checkpoint或明确定义的 cross-format equivalence。
2. 可继续 long-running + memory-pressure matrix。
3. 不将当前结果作为 segment size或 backend选择依据。
