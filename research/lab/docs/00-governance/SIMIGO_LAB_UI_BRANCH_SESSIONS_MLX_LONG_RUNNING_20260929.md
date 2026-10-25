# SimiGo Lab UI Branch Sessions MLX Long Running — 2026-09-29

## Result

```text
UI11 = PASS / MLX_LONG_RUNNING_BRANCH_WITH_BOUNDARY
```

登记：

```text
SIX_TURN_MLX_LONG_RUNNING_BRANCH_PASS
FORKPOINT_AND_FINAL_POSITION_RESTORE_PASS
SIBLING_ADVANCED_RETAINED_ACROSS_LONG_BRANCH
```

这是 oversized MLX harness-level long-running branch pilot，不是 product UI、
persistent session、performance benchmark或 cross-backend validation。

## Session graph

```text
root
├── long branch: 6 sequential turns
└── sibling baseline: advanced and retained
```

## Method

新增 `UIBranchSessions.runLongRunningOversizedMLX` 和 CLI
`mlx-branch-session-long`。使用本地 oversized Qwen3-Coder-Next-4bit、segment
size 8 / 6 segments、six sequential turns、每 turn 1 token、cacheless greedy
recompute。

流程：

1. root bind fork-point representation。
2. fork sibling和 long branch。
3. sibling执行一次并保留 advanced binding。
4. long branch顺序执行六个 different prompts。
5. 每turn推进 logical position并 bind updated token-prefix payload。
6. restore long branch到 fork point并验证 checkpoint binding。
7. restore回 final position并验证 advanced binding exact。
8. release long branch与 sibling；验证 root/sibling survive。

## Checks

八项 checks全部 PASS：

| Check | Result |
| --- | --- |
| `LONG_SEQUENCE_COMPLETE` | PASS |
| `LONG_BRANCH_FINAL_PREFIX_EXACT` | PASS |
| `LONG_BRANCH_RESTORES_FORKPOINT` | PASS |
| `LONG_BRANCH_RESTORES_FINAL_POSITION` | PASS |
| `SIBLING_ADVANCED_RETAINED` | PASS |
| `RELEASE_LONG_AND_SIBLING` | PASS |
| `ROOT_SURVIVES_RELEASE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

## Resource observation

```text
peak footprint = 8,022 MiB
max swap       = 0 MiB
segment transitions = 44
```

同一提交全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-long-running.json
```

## Boundary

结果限定 current oversized MLX snapshot、segment size 8、fixed six-prompt sequence、
1-token turns和 harness-level prefix representation。这不是 product UI、persistent
session、multi-process session、LLAMA cross-backend validation、performance
benchmark或 production readiness。

## Non-claims

```text
❌ product UI
❌ persistent / multi-process session
❌ LLAMA long-running cross-backend validation
❌ performance benchmark
❌ production readiness
```

## Next

1. 将 MLX long-running与 LLAMA long-running做 outcome-shape matrix。
2. 增加 turns和 prompt length variation。
3. 若继续 UI evidence，可研究 persistent/multi-process boundary。
