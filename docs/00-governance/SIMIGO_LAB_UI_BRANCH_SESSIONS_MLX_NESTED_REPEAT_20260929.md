# SimiGo Lab UI Branch Sessions MLX Nested + Repeat — 2026-09-29

## Result

```text
UI5 = PASS / MLX_NESTED_AND_REPEAT_WITH_BOUNDARY
```

登记：

```text
UI_NESTED_BRANCH_GRAPH_MLX_PASS
UI_REPEATED_RELEASE_RESTORE_SWITCH_MLX_PASS
```

这不是 nested cross-backend closure，也不是 UI product closure。

## Session graph

新增 `UIBranchSessions.runNestedOversizedMLX` 和 CLI command
`mlx-branch-session-nested`。图结构与 LLAMA nested pilot 保持一致：

```text
root
├── branch A
│    └── nested A1
└── branch B
```

A1 从 branch A 的 fork point 派生。A、A1、B 分别使用不同 continuation input，
physical prefix 分叉。root 保持 fork-point binding。

## Repeated oversized lifecycle

对 nested A1 执行 `2` 轮：

```text
release current @1
  -> release all oversized switch-MLP segments
restore @0
  -> coordinator rebinds surviving fork-point prefix
replay seed + branch-A input
switch @1
  -> verify advanced prefix retained
```

两轮 replay 都与 branch A 原始 continuation 一致；每次 switch 回 `@1` 后，A1
advanced prefix 都保留。最后释放 nested A1 与 direct branch B，parent branch A
与 root 仍存活。

## Validation

使用本地 MLX oversized snapshot：

```text
mlx-community/Qwen3-Coder-Next-4bit
snapshot 7b9321eabb85ce79625cac3f61ea691e4ea984b5
segment size8 / 6 segments
cacheless greedy / 2-token continuations / cycles2
```

九项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `NESTED_LINEAGE_ISOLATED` | PASS |
| `FORK_POINT_ISOLATED` | PASS |
| `BRANCH_PREFIXES_DIVERGED` | PASS |
| `REPEATED_RELEASE_RESTORE_REPLAYS` | PASS |
| `REPEATED_ADVANCE_RETAINED` | PASS |
| `RELEASE_NESTED_AND_DIRECT_BRANCH` | PASS |
| `PARENT_BRANCH_SURVIVES_RELEASE` | PASS |
| `ROOT_SURVIVES_RELEASE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

观测：

```text
peak footprint     = 7,970 MiB
max swap           = 0 MiB
segment transitions = 64
```

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-nested-repeat.json
```

## Boundary

结果限定 current oversized Qwen3-Next MLX snapshot、segment size 8、cacheless
greedy workload、single short prompt set、2-token continuations、depth-2 nested
graph 和 harness-level prefix representation。报告中的 latency、memory 和
segment transition 计数只是 pilot observation，不建立 production、performance 或
UI product claim。

## Non-claims

```text
❌ nested cross-backend matrix 已完成
❌ arbitrary-depth branch graph 已验证
❌ persistent / multi-process session 已验证
❌ UI product 已完成
❌ performance 结论已建立
```

## Next

1. 把 LLAMA 与 MLX 的 nested + repeated lifecycle 放入 same-shape cross-backend
   matrix。
2. 之后再考虑更深的 branch graph 和更重复的 switch/restore/load pattern。
3. 继续保持 CLI control plane，暂不构建 UI surface。
