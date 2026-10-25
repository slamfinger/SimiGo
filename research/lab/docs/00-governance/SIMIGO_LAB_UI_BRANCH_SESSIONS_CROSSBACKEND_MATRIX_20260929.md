# SimiGo Lab UI Branch Sessions Cross-Backend Matrix — 2026-09-29

## Result

```text
UI3 = PASS_WITH_BOUNDARY / SAME_SHAPE_SEMANTIC_MATRIX
UI cross-backend closure = OPEN / MODEL_IDENTITY_BLOCKED
```

登记：

```text
UI_LLAMA_TEXT_WORKLOAD_ALIGNMENT
UI_CROSSBACKEND_SEMANTIC_MATRIX_PASS
CROSSBACKEND_MODEL_IDENTITY_CLOSURE_BLOCKED
```

## Workload alignment

`UIBranchSessions.run` 升级到 V2：LLAMA 不再使用硬编码 token IDs，而是通过
llama-server `/tokenize` 读取与 MLX pilot 相同的文本 workload。两者都执行：

```text
seedText       = def is_palindrome(s):
rootInput      = Explain it briefly.
branchAInput   = Now write tests for it.
branchBInput   = Add a one-line TODO.
max tokens     = 2
```

Operation sequence 均为：

```text
fork@0
continue@1
continue@1
continue@1
switch@0
switch@1
switch@1
release@1
```

这验证同一 semantic operation sequence 和 workload shape。`BRANCHES_DIVERGED`
的含义是 physical prefix divergence；不要求不同模型产生相同或不同 token text。

## Backends

LLAMA server model：

```text
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / slot512 / ubatch8 / threads4
seed42 / greedy temperature 0
```

MLX oversized model：

```text
mlx-community/Qwen3-Coder-Next-4bit
snapshot 7b9321eabb85ce79625cac3f61ea691e4ea984b5
segment size8 / 6 segments / cacheless greedy
```

两者是不同 model artifact 和 tokenizer；因此这不是 same-model closure。

## Matrix checks

七项 common semantic checks 在两个 backend 均为 PASS：

| Check | LLAMA | MLX |
| --- | --- | --- |
| `BRANCHES_DIVERGED` | PASS | PASS |
| `BRANCH_LINEAGE_ISOLATED` | PASS | PASS |
| `SWITCH_ROOT_TO_FORK_REPLAYS` | PASS | PASS |
| `SWITCH_BRANCH_RETAINS_DIVERGENCE` | PASS | PASS |
| `SWITCH_ROOT_RETAINS_ADVANCE` | PASS | PASS |
| `RELEASE_BRANCHES` | PASS | PASS |
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
peak footprint = 6,577 MiB
```

## Verification

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-crossbackend-matrix.json
```

## Boundary

这是 harness-level semantic matrix，不是 UI product、not a performance claim，
也不是 cross-model/cross-backend universal closure。LLAMA 与 MLX 的 model
checkpoint、quantization、tokenizer 和 physical representation 都不同；不能把
semantic checks 一致解释为“same model identity closure”。报告中 latency 和
memory 只是 pilot observation。

## Non-claims

```text
❌ same-checkpoint cross-backend closure 已完成
❌ 所有模型 / workload / backend 已验证
❌ UI product 已完成
❌ nested branch graph 已验证
❌ persistent / multi-process session 已验证
❌ performance equivalence 已建立
```

## Next

1. 若要真正 model-identity closure，需要同一 checkpoint 的可比较 backend
   representation 或明确定义 cross-format equivalence；不能默认 GGUF/MLX 转换等价。
2. 继续扩展 nested branch、repeated switch/restore/release。
3. UI surface 仍保持 CLI control plane；等产品语义矩阵更稳定后再考虑极简 UI。
