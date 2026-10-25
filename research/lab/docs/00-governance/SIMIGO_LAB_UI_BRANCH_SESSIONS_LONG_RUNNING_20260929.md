# SimiGo Lab UI Branch Sessions Long Running — 2026-09-29

## Result

```text
UI10 = PASS / LLAMA_LONG_RUNNING_BRANCH_WITH_BOUNDARY
```

登记：

```text
SIX_TURN_LONG_RUNNING_BRANCH_PASS
FORKPOINT_AND_FINAL_POSITION_RESTORE_PASS
SIBLING_BASELINE_RETAINED_ACROSS_LONG_BRANCH
```

这是 LLAMA harness-level long-running session pilot，不是 product UI、persistent
session、production performance claim或 cross-backend validation。

## Session graph

```text
root
├── long branch: 6 sequential turns
└── sibling baseline: retained across long branch
```

## Method

新增 `UIBranchSessions.runLongRunningLLAMA` 和 CLI
`llama-branch-session-long`。每个 turn使用不同 prompt；每次 generation后推进
logical position并 bind updated token-prefix representation。完成 6 turns后：

1. restore long branch到 fork point。
2. 验证 fork-point binding。
3. restore long branch到 final position。
4. 验证 advanced binding exact。
5. release long branch与 sibling。
6. 验证 root survives。

使用 canonical mitigated LLAMA profile、seed42、每 turn 4 tokens。

## Checks

七项 checks全部 PASS：

| Check | Result |
| --- | --- |
| `LONG_SEQUENCE_COMPLETE` | PASS |
| `LONG_BRANCH_FINAL_PREFIX_EXACT` | PASS |
| `LONG_BRANCH_RESTORES_FORKPOINT` | PASS |
| `LONG_BRANCH_RESTORES_FINAL_POSITION` | PASS |
| `SIBLING_BASELINE_RETAINED` | PASS |
| `RELEASE_LONG_AND_SIBLING` | PASS |
| `ROOT_SURVIVES_RELEASE` | PASS |

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-llama-long-running.json
```

同一提交全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Boundary

这是 LLAMA harness-level long-running branch pilot，不是 product UI、persistent
session、multi-process session、performance benchmark或 production readiness。
结果限定 current model、canonical mitigated profile、fixed prompt sequence、seed42
和 4-token turns。

## Non-claims

```text
❌ product UI
❌ persistent / multi-process session
❌ MLX long-running cross-backend validation
❌ performance benchmark
❌ production readiness
```

## Next

1. 将 long-running sequence扩展到 MLX oversized backend。
2. 增加 turns和 prompt length sweep。
3. 若继续 UI evidence，可评估 persistent or multi-process boundary。
