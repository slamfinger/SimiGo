# SimiGo Lab UI Branch Sessions Pilot — 2026-09-29

## Result

```text
UI1 = PASS / LLAMA_PILOT_WITH_BOUNDARY
```

登记：

```text
UI_CONTROL_PLANE_OPERATIONAL
UI_BRANCH_SESSIONS_LLAMA_PILOT_PASS
```

这不是 UI product closure，也不是 cross-backend session closure。

## Minimal control plane

新增 `UIBranchSessions` 与 CLI command：

```bash
simigo2-experimental/.build/debug/simigo2ctl llama-branch-session /tmp \
  --host 127.0.0.1 --port 18080 --tokens 8 --seed 42
```

Harness 语义路径：

```text
create / bind
  -> fork branch A + branch B
  -> capture root fork point
  -> continue root / A / B
  -> switch root to fork point
  -> switch A and root to advanced positions
  -> release branches
  -> verify root survives
```

Implementation 只复用现有 `ExecutionContinuityCoordinator`、
`LLAMAServerExecutionStateBackend` 和 HTTP executor；不新增 inference runtime，
不触碰 native KV authority。

## Validation

当前 canonical mitigated LLAMA server：

```text
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL
ctx2048 / parallel4 / slot512
ubatch8 / threads4 / threads-batch4
seed42 / prediction tokens8
```

七项 semantic checks 全部 PASS：

| Check | Result |
| --- | --- |
| `BRANCHES_DIVERGED` | PASS |
| `BRANCH_LINEAGE_ISOLATED` | PASS |
| `SWITCH_ROOT_TO_FORK_REPLAYS` | PASS |
| `SWITCH_BRANCH_RETAINS_DIVERGENCE` | PASS |
| `SWITCH_ROOT_RETAINS_ADVANCE` | PASS |
| `RELEASE_BRANCHES` | PASS |
| `ROOT_SURVIVES_RELEASE` | PASS |

Root replay 与原始 root continuation 输出一致；branch A / B 内容互相不同；
branch release 后 physical binding 消失，root binding 仍存在。

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-llama-pilot.json
```

## Boundary

结果限定 current model、current Metal LLAMA build、canonical mitigated profile、
single seed、short-token workload 和 harness-level prefix representation。
报告中的 local operation latency 只是 pilot observation，不建立 UI、session 或
performance production claim。

## Non-claims

```text
❌ 用户可见产品 UI 已完成
❌ persistent / multi-process session 已验证
❌ nested branch graph 已验证
❌ MLX / LLAMA / future backend session closure 已完成
❌ Execution State abstraction universal 成立
```

## Next

1. 增加至少一个 second backend UI session pilot，优先 MLX。
2. 验证 nested branch 与重复 switch / restore / release。
3. 之后才考虑极简 UI surface；当前阶段先保持 CLI control plane。
