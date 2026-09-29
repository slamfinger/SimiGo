# SimiGo Lab RQ3 LLAMA Metal Flag Ablation — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

新增两个 Metal flag ablation 后登记：

```text
FLASH_ATTN_OFF_NOT_SUFFICIENT
CPU_MOE_HYBRID_NOT_STABLE
METAL_MOE_HYBRID_BOUNDARY_NOT_ISOLATED
```

Flash Attention 关闭不能消除 active3/4 instability；`--cpu-moe` 混合放置不是一个有效 mitigation，反而把 instability 提前到 N2。

## Common probe

沿用 distinct equal-length prompt cardinality probe：

```text
prompt0 ping
prompt1 alpha
prompt2 beta
prompt3 gamma
```

每 prompt 6 tokens；每个 configuration 先串行建立 3 次 single-load reference，
三次均 stable。cardinality 1–4，各 8 cycles；响应按 prompt index 与当前
configuration reference 比较。没有 long request、cancellation 或 Execution State
object。

## A. Metal Flash Attention OFF

Server：

```text
parallel4 / slot512
--flash-attn off
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **4/8** | **4/8** |
| 4 | **4/8** | **2/8** |

Finding：

```text
FLASH_ATTN_OFF_NOT_SUFFICIENT
```

N3/N4 仍 unstable，且 N4 across-cycle stable 低于 original auto config 的
`4/8`；不能把 original boundary 归因于 Flash Attention。

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-flashoff.json
```

## B. Metal + CPU MoE hybrid

Server：

```text
parallel4 / slot512
--cpu-moe
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

MoE expert weights移到 CPU，其余模型路径仍在 Metal。

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **2/8** | **1/8** |
| 3 | **2/8** | **6/8** |
| 4 | **0/8** | **6/8** |

Finding：

```text
CPU_MOE_HYBRID_NOT_STABLE
METAL_MOE_HYBRID_BOUNDARY_NOT_ISOLATED
```

该混合 placement 不但未修复 N3/N4，还让 N2 出现 mismatch。因此不能把它作为
mitigation；也不能据此断言 Metal MoE expert kernel 是唯一原因，因为混合设备
路径本身引入了新的 CPU/GPU boundary。

Artifacts：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-flashoff.json
  rq3-llama-distinct-prompt-cardinality-metal-cpumoe.json
```

## Interpretation

结合既有对照：

| Path | active1 | active2 | active3 | active4 |
| --- | --- | --- | --- | --- |
| Metal full-GPU auto | stable | stable | unstable | unstable |
| Metal full-GPU FA off | stable | stable | unstable | unstable |
| Metal + CPU MoE hybrid | stable | unstable | unstable | unstable |
| CPU-only | stable | stable | stable | stable |

当前可支持的结论是：instability 隔离到 Metal execution path；Flash Attention 与
CPU-Moe hybrid placement 不是 fixes。具体 Metal kernel、graph、batch reduction
或 synchronization机制仍未定位。

## Non-claims

```text
❌ Flash Attention 是原因
❌ CPU MoE hybrid 是修复
❌ MoE expert path 已被排除或定位
❌ llama.cpp 内部机制已定位
❌ 其他 hybrid placement / repack / op-offload 已收口
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
FLASH_ATTN_OFF_NOT_SUFFICIENT
CPU_MOE_HYBRID_NOT_STABLE
METAL_MOE_HYBRID_BOUNDARY_NOT_ISOLATED
```

RQ3 仍保持 OPEN。
