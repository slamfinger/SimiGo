# SimiGo Lab Oversized Research Boundary Freeze — 2026-09-29

## Decision

```text
OVERSIZED_INDEPENDENT_RESEARCH_LINE = FROZEN
OVERSIZED_ROLE = ARCHITECTURE_VALIDATION_PAYLOAD
```

oversized layer research不再作为独立主研究线扩张，也不删除既有资产。后续只在
Execution State / Storage / Backend architecture实验中作为规模边界载荷复用。

## Research routing

```text
主问题：
Execution State / Storage / Backend architecture
                │
                ├── 普通模型：证明默认路径
                │
                └── oversized：证明规模边界
                              │
                              ├── retention
                              ├── artifact lifecycle
                              ├── restore
                              ├── resource budget
                              ├── backend capability
                              └── failure / recovery
```

每个实验优先回答主架构问题；oversized只作为同一实验里的旁证或压力边界，
不再为了 oversized 本身新增 layer、tensor或 loading strategy语义。

## Allowed secondary validations

| 主线机制 | oversized secondary role |
| --- | --- |
| PALACE artifact lifecycle | oversized artifact capture / restore / release |
| Representation Store / retention GC | oversized store eviction和 byte-budget压力 |
| RepresentationRef | 普通模型证明语义，oversized证明大 artifact边界 |
| Backend Adapter | 普通路径证明 seam，oversized证明 capability boundary |
| crash recovery | 普通路径验证正确性，oversized观察恢复成本 |
| LAN / remote | 普通 execution验证 API，oversized验证 locator / streaming |
| resource scheduling | oversized作为压力载荷 |

## Frozen non-goals

```text
❌ 继续优化 oversized layer loading 作为独立目标
❌ 新建 layer / tensor / loading strategy研究分支
❌ 为产生 oversized结果而给 Execution State增加特殊语义
❌ 把 oversized scale sweep升级成 performance benchmark主线
❌ 用 oversized旁证替代普通模型默认路径证明
```

## Final scale observation

冻结前完成最后一个 process-clean MLX scale observation：prefix
`8/64/256`、每 bucket `10` pairs、1-token generation、segment size 8。

```text
status               = PASS
semantic pairs       = 30/30 PASS
checks               = 3/3 PASS
peak footprint       = 7,364 MiB
max swap             = 0 MiB
segment transitions  = 397
wall clock           = 898.09s
```

run前后均确认无 `llama-server` / `simigo2ctl`，无 `18080` listener。residual
host swap从 before `4,262.44 MiB` 到 after `3,750.44 MiB`，不归因本 run；
`vm.memory_pressure` before `0`、after `249` 仅原样记录。

paired `state−direct` mean / median / stdev ms：

| Prefix tokens | Delta mean | Delta median | Delta stdev | State local mean ms |
| ---: | ---: | ---: | ---: | ---: |
| 8   | `+18.171537`   | `-4.314375`   | `171.364680` | `0.010671` |
| 64  | `-337.701508`  | `-44.328895`  | `897.093750` | `0.014084` |
| 256 | `-537.781654`  | `-565.164395` | `690.257408` | `0.012108` |

该 n=10 run semantic继续 PASS，但 latency delta方向与 n=5 process-clean run
相反，方差也更大。这支持冻结判断：继续追加 oversized scale samples不会稳定
产出架构结论，只会诱使 harness继续膨胀。结果不得解释为 Execution State加速、
overhead、performance curve或 production readiness。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n10-process-clean-final.json
simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n10-process-clean-final-host-context.json
```

结果 SHA-256：

```text
f6bff44050ebfb0ee8a8fb63332c1ee690c663c24dd62a7962299d480c4f701d
```

## Next main lines

1. PALACE-1：继续 audit-first，研究 durable state、artifact locator、
   consistency、retention / GC和 crash recovery；oversized作为规模验证载荷。
2. BACKEND-1：继续 audit-first，分离 Execution semantics与 MLX implementation
   detail，寻找最小 backend seam；oversized作为 capability / resource边界载荷。
3. 不再排入 standalone oversized experiment。
