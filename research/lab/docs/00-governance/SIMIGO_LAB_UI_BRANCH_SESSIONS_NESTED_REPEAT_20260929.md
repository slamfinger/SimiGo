# SimiGo Lab UI Branch Sessions Nested + Repeat — 2026-09-29

## Result

```text
UI4 = PASS / LLAMA_NESTED_AND_REPEAT_WITH_BOUNDARY
```

登记：

```text
UI_NESTED_BRANCH_GRAPH_LLAMA_PASS
UI_REPEATED_RELEASE_RESTORE_SWITCH_PASS
```

这不是 nested cross-backend closure，也不是 UI product closure。

## Session graph

新增 `UIBranchSessions.runNestedLLAMA` 和 CLI command
`llama-branch-session-nested`。图结构为：

```text
root
├── branch A
│    └── nested A1
└── branch B
```

A1 从 branch A 的 fork point 派生。A、A1、B 分别使用不同 continuation input，
因此 physical prefix 分叉。root 保持 fork-point binding。

## Repeated lifecycle

对 nested A1 执行 `2` 轮：

```text
release @1
restore  @0
replay seed + branch-A input
switch   @1
verify advanced binding retained
```

两轮 replay 与 branch A 原始 continuation 完全一致；每次 switch 回 `@1`
后，A1 advanced prefix 都保留。最后释放 nested A1 与 direct branch B，验证
parent branch A 与 root 仍存活。

## Validation

LLAMA canonical mitigated profile：

```text
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL
ctx2048 / parallel4 / slot512
ubatch8 / threads4 / threads-batch4
seed42 / prediction tokens2 / cycles2
```

八项 checks 全部 PASS：

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

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-llama-nested-repeat.json
```

## Boundary

结果限定 current LLAMA model、canonical mitigated profile、single seed、short
2-token workload、depth-2 nested graph 和 harness-level prefix representation。
报告中的 local operation latency 只是 pilot observation，不建立 production、
performance 或 UI product claim。

## Non-claims

```text
❌ nested MLX / cross-backend closure 已完成
❌ arbitrary-depth branch graph 已验证
❌ persistent / multi-process session 已验证
❌ UI product 已完成
❌ performance 结论已建立
```

## Next

1. 将 nested + repeated lifecycle 扩展到 MLX oversized backend。
2. 如两边 PASS，再把 nested graph 纳入 same-shape cross-backend matrix。
3. 继续保持 CLI control plane，暂不构建 UI surface。
