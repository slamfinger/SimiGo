# SimiGo Lab UI Branch Sessions MLX Pilot — 2026-09-29

## Result

```text
UI2 = PASS / OVERSIZED_MLX_PILOT_WITH_BOUNDARY
```

登记：

```text
UI_BRANCH_SESSIONS_MLX_PILOT_PASS
UI_SESSION_TWO_BACKEND_EVIDENCE
```

这是第二 backend 的 harness-level pilot；不是 cross-backend universal closure。

## Setup

新增 `UIBranchSessions.runOversizedMLX` 与 CLI command：

```bash
simigo2-experimental/.build/debug/simigo2ctl mlx-branch-session \
  <LOCAL_HOME>/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots/7b9321eabb85ce79625cac3f61ea691e4ea984b5 \
  --tokens 2 --segment-size 8
```

复用既有 oversized MLX physical machinery：

```text
ExecutionContinuityCoordinator
OversizedSegmentedStateBackend
OversizedSegmentedExecutor
O6SegmentedCore
```

模型为已存在的 `mlx-community/Qwen3-Coder-Next-4bit` 本地 snapshot；
segment size `8` 产生 `6` segments。使用 cacheless greedy generation，
每次 continuation `2` tokens。本次运行没有下载模型。

## Semantic checks

八项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `BRANCHES_DIVERGED` | PASS |
| `BRANCH_LINEAGE_ISOLATED` | PASS |
| `SWITCH_ROOT_TO_FORK_REPLAYS` | PASS |
| `SWITCH_BRANCH_RETAINS_DIVERGENCE` | PASS |
| `SWITCH_ROOT_RETAINS_ADVANCE` | PASS |
| `RELEASE_BRANCHES` | PASS |
| `ROOT_SURVIVES_RELEASE` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

Root 从 fork point restore 后，使用同一 root input 重新执行，输出与原 root
continuation 完全一致。branch A / B 的 generated tokens 互不相同；switch 回
advanced position 后，root 与 branch A 的 prefix 均保留；release A/B 后它们的
physical binding 消失，root binding 仍存在。

本次观测：

```text
peak footprint = 7,858 MiB
max swap       = 0 MiB
segment transitions = 50
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
simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-oversized-pilot.json
```

## Boundary

结果限定 current oversized Qwen3-Next MLX snapshot、segment size 8、cacheless
greedy workload、single short prompt set、2-token continuations 和
harness-level prefix representation。报告中的 operation latency 与 memory gauge
只是 pilot observation，不建立 production、performance 或 UI product claim。

## Non-claims

```text
❌ UI product 已完成
❌ MLX / LLAMA exact same-workload closure 已完成
❌ nested branch graph 已验证
❌ persistent / multi-process session 已验证
❌ Execution State abstraction universal 成立
❌ 7.9GiB peak 是通用模型/配置性能结论
```

## Two-backend state

```text
LLAMA pilot : PASS
MLX pilot   : PASS
UI closure  : OPEN / NEEDS_SAME_WORKLOAD_CROSS_BACKEND_MATRIX
```

下一步应固定同一 semantic operation sequence 和 workload shape，再做 MLX vs
LLAMA 对照；之后才扩展 nested branches 与重复 switch/restore/release。
