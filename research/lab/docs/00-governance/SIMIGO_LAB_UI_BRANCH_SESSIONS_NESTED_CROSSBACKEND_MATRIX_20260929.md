# SimiGo Lab UI Branch Sessions Nested Cross-Backend Matrix — 2026-09-29

## Result

```text
UI6 = PASS_WITH_BOUNDARY / NESTED_SAME_SHAPE_SEMANTIC_MATRIX
UI nested cross-backend closure = OPEN / MODEL_IDENTITY_BLOCKED
```

登记：

```text
UI_NESTED_CROSSBACKEND_SEMANTIC_MATRIX_PASS
NESTED_CROSSBACKEND_MODEL_IDENTITY_CLOSURE_BLOCKED
```

## Same-shape workload

新增 `UIBranchSessions.runNestedCrossBackendMatrix` 与 CLI
`ui-nested-branch-matrix`。single driver 先后运行 LLAMA nested harness 与
oversized MLX nested harness。

两者使用同一文本 workload、token budget、cycle count 和 session graph：

```text
seedText       = def is_palindrome(s):
branchAInput   = Now write tests for it.
nestedInput    = Explain the first test.
branchBInput   = Add a one-line TODO.
max tokens     = 2
cycles         = 2

root
├── branch A
│    └── nested A1
└── branch B
```

Operation sequence 均为 11 steps：

```text
fork@0
continue@1
continue@1
continue@1
release@1
switch@0
switch@1
release@1
switch@0
switch@1
release@1
```

## Matrix checks

八项 common semantic checks 在两个 backend 均为 PASS：

| Check | LLAMA | MLX |
| --- | --- | --- |
| `NESTED_LINEAGE_ISOLATED` | PASS | PASS |
| `FORK_POINT_ISOLATED` | PASS | PASS |
| `BRANCH_PREFIXES_DIVERGED` | PASS | PASS |
| `REPEATED_RELEASE_RESTORE_REPLAYS` | PASS | PASS |
| `REPEATED_ADVANCE_RETAINED` | PASS | PASS |
| `RELEASE_NESTED_AND_DIRECT_BRANCH` | PASS | PASS |
| `PARENT_BRANCH_SURVIVES_RELEASE` | PASS | PASS |
| `ROOT_SURVIVES_RELEASE` | PASS | PASS |

Matrix result：

```text
sameSemanticChecks     = true
sameOperationSequence  = true
sameWorkloadShape      = true
bothBackendsPass       = true
crossBackendClosure    = false
closureBlocker         = DIFFERENT_MODEL_ARTIFACTS_AND_TOKENIZERS
```

MLX 另有 backend-specific check：

```text
OVERSIZED_PROFILE_UNDER_30GIB = PASS
peak footprint = 6,079 MiB
max swap       = 0 MiB
segment transitions = 64
```

LLAMA 使用 Cyber-Tiel GGUF canonical mitigated profile；MLX 使用本地
Qwen3-Coder-Next-4bit oversized snapshot。

## Verification

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-nested-crossbackend-matrix.json
```

## Boundary

这是 harness-level nested semantic matrix，不是 same-model identity closure、UI
product、persistent session、arbitrary-depth graph 或 performance equivalence。
LLAMA 与 MLX checkpoint、quantization、tokenizer 和 physical representation 均
不同；不能把 semantic checks 一致解释为 cross-format checkpoint equivalence。
报告中的 latency、memory 和 segment transition 只是 pilot observation。

## Non-claims

```text
❌ same-checkpoint cross-backend closure 已完成
❌ arbitrary-depth nested graph 已验证
❌ persistent / multi-process session 已验证
❌ UI product 已完成
❌ performance equivalence 已建立
```

## Next

1. 若要推进 closure，需要同一 checkpoint 的可比较 backend representation 或
   显式 cross-format equivalence 定义。
2. 可选扩展更深的 branch graph / repeated switch pattern。
3. UI surface 继续保持 CLI control plane。
