# SimiGo Lab UI Branch Sessions MLX Memory Pressure — 2026-09-29

## Result

```text
UI13 = PASS / CONTROLLED_MULTI_BRANCH_MEMORY_PRESSURE_ACTION
PRESSURE_SEMANTIC = SESSION_RELEASE_RESTORE_LOAD / NOT_OS_MEMORY_PRESSURE
```

登记：

```text
UI13_MLX_MULTI_BRANCH_RELEASE_RESTORE_PRESSURE_PASS
REPEATED_RECOVERY_OUTPUTS_EXACT
ROOT_AND_CONTROL_SURVIVE_RELEASE
NO_SWAP_ON_CONTROLLED_PRESSURE_ACTION
```

这是 UI 控制面 harness 的 controlled pressure-action pilot。它增加同时活跃的
branch states 并重复 release/restore/replay，不注入、不断言、也不声称触发了
operating-system memory pressure。

## Session shape

```yaml
root
├── control branch: advanced and retained
├── pressure branch 0: advanced, released/restored twice
└── pressure branch 1: advanced, released/restored twice
```

使用配置：

```text
backend       = oversized MLX Qwen3-Coder-Next-4bit
segment size  = 8 / 6 segments
tokens/turn   = 1
cycles        = 2
pressure act. = 4 capture/release actions
```

## Validation

```text
summary checks = 10/10 PASS
Swift tests    = 157 PASS / 0 FAIL
```

| Check | Result |
| --- | --- |
| `PRESSURE_WORKLOAD_COMPLETE` | PASS |
| `PRESSURE_RELEASE_ACTIONS_COMPLETE` | PASS |
| `PRESSURE_LINEAGE_ISOLATED` | PASS |
| `ACTIVE_BRANCH_PREFIXES_DIVERGED` | PASS |
| `REPEATED_RECOVERY_OUTPUTS_EXACT` | PASS |
| `RECOVERY_FINAL_BINDINGS_EXACT` | PASS |
| `RELEASE_PRESSURE_BRANCHES` | PASS |
| `ROOT_AND_CONTROL_SURVIVE` | PASS |
| `NO_SWAP_ON_PRESSURE_ACTION` | PASS |
| `OVERSIZED_PROFILE_UNDER_30GIB` | PASS |

两个 pressure branch 的最终 prefix 分别为 15 和 17 tokens；每个 branch 的
2 次 fork-point replay 与 final-position binding 都 exact。

## Resource observation

```text
peak footprint      = 6,904 MiB
max swap            = 0 MiB
segment transitions = 48
```

该资源值描述当前 cacheless greedy segmented harness，不是 production footprint、
retention policy 或 performance claim。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-memory-pressure.json
```

实现入口：

```text
UIBranchSessions.runMemoryPressureOversizedMLX
CLI: mlx-branch-session-memory-pressure
```

## Boundary

结果限定 current Qwen3-Coder-Next-4bit snapshot、segment size 8、1-token
generation、2 active pressure branches、2 cycles 和本机 harness。这是
harness-level Execution State session observation，不是 product UI、persistent
session、OS pressure validation、production cancellation readiness、performance
benchmark、same-checkpoint cross-backend closure 或 LLAMA validation。

## Non-claims

```text
❌ OS memory pressure 已被触发或验证
❌ product UI
❌ persistent / multi-process session
❌ production memory-pressure policy
❌ performance benchmark
❌ cross-backend memory-pressure closure
```

## Next

1. LLAMA memory-pressure branch pilot。
2. MLX/LLAMA controlled pressure outcome-shape matrix。
3. 若要研究真实 OS pressure，需要单独的 pressure-injection protocol 和
   independent resource observation，不得复用本 pilot 的语义命名。
