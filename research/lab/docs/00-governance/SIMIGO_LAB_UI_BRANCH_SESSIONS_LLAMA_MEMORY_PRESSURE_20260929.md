# SimiGo Lab UI Branch Sessions LLAMA Memory Pressure — 2026-09-29

## Result

```text
UI14 = PASS / CONTROLLED_MULTI_BRANCH_MEMORY_PRESSURE_ACTION
PRESSURE_SEMANTIC = SESSION_RELEASE_RESTORE_LOAD / NOT_OS_MEMORY_PRESSURE
```

登记：

```text
UI14_LLAMA_MULTI_BRANCH_RELEASE_RESTORE_PRESSURE_PASS
REPEATED_RECOVERY_OUTPUTS_EXACT
ROOT_AND_CONTROL_SURVIVE_RELEASE
```

这是 UI 控制面 harness 的 controlled pressure-action pilot。它保持多条活跃
branch representation 并重复 release/restore/replay；不注入、不断言、也不声称
触发了 operating-system memory pressure或 llama-server slot memory pressure。

## Session shape

```yaml
root
├── control branch: advanced and retained
├── pressure branch 0: advanced, released/restored twice
└── pressure branch 1: advanced, released/restored twice
```

使用配置：

```text
backend            = LLAMA GGUF Cyber-Tiel Coder 35B A3B MTP UD Q4_K_XL
server profile     = canonical mitigated ubatch8 / parallel4 / cache disabled
prediction tokens  = 1
cycles             = 2
pressure actions   = 4 capture/release actions
seed               = 42
```

## Validation

```text
summary checks = 8/8 PASS
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

两条 pressure branch 的 final prefix token counts分别为 15 和 17；每个 branch
的 2 次 fork-point replay和 final-position binding都 exact。

## Latency observation

非 benchmark。三个 initial continue的 client time分别约为：

```text
control       = 207.566ms
pressure b0   = 178.614ms
pressure b1   = 197.391ms
```

四个 explicit release action的 local client time均低于 0.021ms；该值只描述当前
Swift prefix-registry operation，不是 server KV release、memory reclaim或
production cost。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-llama-memory-pressure.json
```

实现入口：

```text
UIBranchSessions.runMemoryPressureLLAMA
CLI: llama-branch-session-memory-pressure
```

## Boundary

结果限定 current Cyber-Tiel snapshot、canonical mitigated launch profile、
1-token generation、2 active pressure branches、2 cycles、seed 42和本机 harness。
LLAMA Execution State representation是 Swift-owned prompt-token prefix；llama-server
继续拥有 computation和 native runtime cache。这不是 product UI、persistent
session、OS pressure validation、production cancellation readiness、performance
benchmark、same-checkpoint cross-backend closure或 MLX validation。

## Non-claims

```text
❌ OS memory pressure 已被触发或验证
❌ server slot memory pressure 已被触发或验证
❌ release action 释放了 llama-server native cache
❌ product UI
❌ persistent / multi-process session
❌ production memory-pressure policy
❌ performance benchmark
❌ cross-backend memory-pressure closure
```

## Next

1. LLAMA/MLX controlled pressure outcome-shape matrix。
2. 若要研究真实 server 或 OS pressure，需要 pressure-injection protocol和
   independent resource observation。
