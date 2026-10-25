# SimiGo Lab UI Branch Sessions MLX Cancellation — 2026-09-29

## Result

```text
UI8 = PASS / MLX_SESSION_COOPERATIVE_CANCELLATION_WITH_BOUNDARY
```

登记：

```text
UI_SESSION_COOPERATIVE_CANCEL_RECOVERY_MLX_PASS
UI_CANCELLED_MLX_BRANCH_RELEASE_DISCARD_PASS
```

这是 oversized MLX harness pilot；不是 cross-backend cancellation closure 或生产
readiness claim。

## Session graph

新增 `UIBranchSessions.runCancellationOversizedMLX` 与 CLI
`mlx-branch-session-cancel`。每轮建立：

```text
root
├── long branch       -> cooperative token-boundary cancel
├── control branch    -> sibling identity control
└── recovery branch   -> forked after restore
```

Lifecycle：

```text
create / bind root
fork long + control
run root and control references
cooperatively cancel long branch after 1 token
advance / bind cancelled physical prefix
release cancelled representation
restore root to fork point
fork recovery branch
verify root recovery identity
restore / replay control branch
discard cancelled long branch
```

## Validation

使用本地 oversized MLX snapshot：

```text
mlx-community/Qwen3-Coder-Next-4bit
snapshot 7b9321eabb85ce79625cac3f61ea691e4ea984b5
segment size8 / 6 segments
cacheless greedy / maxTokens4 / cycles2
```

九项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `COOPERATIVE_CANCEL_ONE_TOKEN` | PASS |
| `CANCELLED_LONG_PHYSICAL_RELEASED` | PASS |
| `CANCELLED_LONG_LOGICALLY_DISCARDED` | PASS |
| `ROOT_RECOVERY_IDENTICAL` | PASS |
| `CONTROL_RECOVERY_IDENTICAL` | PASS |
| `ROOT_AND_CONTROL_PREFIXES_DIVERGED` | PASS |
| `RECOVERY_LINEAGE_ISOLATED` | PASS |
| `ROOT_AND_CONTROL_SURVIVE_RELEASE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

两次 cooperative cancellation 均在第 1 个完整 greedy token 后发生：

```text
cancelledTokenCounts = [1, 1]
peak footprint       = 7,946 MiB
max swap             = 0 MiB
segment transitions  = 254
```

`ROOT_RECOVERY_IDENTICAL` 与 `CONTROL_RECOVERY_IDENTICAL` 均按每个 cycle 的
pre-cancel reference 逐 cycle 比较 generated token IDs 和 text，不是只做跨 cycle
repeat check。

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-cancellation.json
```

## Boundary

结果限定 current oversized Qwen3-Next MLX snapshot、segment size 8、cacheless
greedy workload、single short prompt set、token-boundary cooperative
cancellation、depth-1 session graph 和 harness-level prefix representation。
latency、memory 和 segment transition 只是 pilot observation，不建立 production、
performance 或 UI product claim。

## Non-claims

```text
❌ cross-backend cancellation matrix 已完成
❌ arbitrary-depth cancellation graph 已验证
❌ production cancellation 已验证
❌ persistent / multi-process session 已验证
❌ performance 结论已建立
```

## Next

1. 将 LLAMA explicit cancel 与 MLX cooperative cancel 放入 same-shape UI
   cancellation matrix。
2. 再考虑 depth-2 或 repeated cancellation/recovery graph。
3. UI surface 继续保持 CLI control plane。
