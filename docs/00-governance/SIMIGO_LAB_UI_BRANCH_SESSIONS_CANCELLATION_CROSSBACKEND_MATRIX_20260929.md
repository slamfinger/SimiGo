# SimiGo Lab UI Branch Sessions Cancellation Cross-Backend Matrix — 2026-09-29

## Result

```text
UI9 = PASS_WITH_BOUNDARY / SESSION_CANCELLATION_OUTCOME_SHAPE_MATRIX
UI cancellation cross-backend closure = OPEN / MECHANISM_AND_MODEL_IDENTITY_BLOCKED
```

登记：

```text
UI_SESSION_CANCELLATION_CROSSBACKEND_MATRIX_PASS
CANCELLATION_MECHANISM_DIFFERENCE_REGISTERED
CROSSBACKEND_CANCELLATION_MODEL_IDENTITY_CLOSURE_BLOCKED
```

## Same outcome shape, different mechanisms

新增 `UIBranchSessions.runCancellationCrossBackendMatrix` 与 CLI
`ui-cancellation-matrix`。single driver 先后运行 LLAMA 与 oversized MLX UI
session cancellation harness。

两者使用相同文本 workload、session graph、recovery token budget 和 cycles：

```text
seedText       = def is_palindrome(s):
rootInput      = Explain it briefly.
controlInput   = Now write tests for it.
recoveryInput  = Continue from the root.
longPrompt     = Count from 1 to 500. Return only numbers separated by spaces.
recovery tokens = 2
cycles         = 2

root
├── long branch       -> cancelled
├── control branch    -> sibling identity control
└── recovery branch   -> post-cancel fork
```

机制差异保留，不做伪装：

| Backend | Mechanism |
| --- | --- |
| LLAMA | explicit stream DELETE |
| oversized MLX | cooperative token-boundary cancel |

## Matrix checks

十项 standardized common checks 全部 PASS：

| Check | Result |
| --- | --- |
| `CANCELLATION_ACCEPTED` | PASS |
| `EXECUTION_STOPPED` | PASS |
| `CANCELLED_LONG_PHYSICAL_RELEASED` | PASS |
| `CANCELLED_LONG_LOGICALLY_DISCARDED` | PASS |
| `ROOT_RECOVERY_IDENTICAL` | PASS |
| `CONTROL_RECOVERY_IDENTICAL` | PASS |
| `ROOT_AND_CONTROL_PREFIXES_DIVERGED` | PASS |
| `RECOVERY_LINEAGE_ISOLATED` | PASS |
| `ROOT_AND_CONTROL_SURVIVE_RELEASE` | PASS |
| `CYCLES_COMPLETE` | PASS |

Matrix result：

```text
sameOutcomeShape       = true
sameRecoverySemantics  = true
sameWorkloadShape      = true
bothBackendsPass       = true
crossBackendClosure    = false
closureBlocker         = DIFFERENT_MODEL_ARTIFACTS_TOKENIZERS_AND_CANCEL_MECHANISMS
```

MLX backend-specific check：

```text
OVERSIZED_PROFILE_UNDER_30GIB = PASS
peak footprint = 6,102 MiB
segment transitions = 134
```

同时将 LLAMA cancellation harness 升级为 10-check form：新增 cancelled long
logical discard 与 root/control survive release。

## Verification

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-llama-cancellation.json
simigo2-experimental/results/backend-conformance/ui-branch-session-cancellation-crossbackend-matrix.json
```

## Boundary

这是 harness-level cancellation outcome-shape matrix。LLAMA explicit DELETE 和
MLX cooperative token-boundary cancel 是不同机制；两者 checkpoint、tokenizer、
quantization 和 physical representation 也不同。不能把 outcome shape 一致解释为
same-model closure、production cancellation readiness 或 performance equivalence。
报告中的 latency、memory 和 segment transition 只是 pilot observation。

## Non-claims

```text
❌ same-checkpoint cancellation closure 已完成
❌ arbitrary-depth cancellation graph 已验证
❌ persistent / multi-process session 已验证
❌ UI product 已完成
❌ performance equivalence 已建立
```

## Next

1. 若要推进 cancellation closure，需要同一 checkpoint / cancellation primitive
   的可比较 backend contract。
2. 可选扩展 depth-2 或 repeated cancellation/recovery pattern。
3. UI surface 继续保持 CLI control plane。
