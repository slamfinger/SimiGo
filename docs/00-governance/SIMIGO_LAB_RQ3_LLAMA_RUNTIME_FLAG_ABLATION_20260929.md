# SimiGo Lab RQ3 LLAMA Runtime Flag Ablation II — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

继续 Metal flag ablation，登记：

```text
NO_REPACK_NOT_SUFFICIENT
NO_OP_OFFLOAD_NOT_SUFFICIENT
METAL_FLAG_MITIGATION_NOT_ESTABLISHED
```

`--no-repack` 不消除 N3/N4 instability。`--no-op-offload` 在 seed42 run 中
N4 observed stable，但 seed43 repeat 中 N3/N4 重新 unstable；因此不能把 N4
改善解释为修复，只能登记为 sample variability / frequency shift。

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

## A. Metal `--no-repack`

Server：

```text
parallel4 / slot512
--no-repack
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **5/8** | **5/8** |
| 4 | **6/8** | **6/8** |

Artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-norepack.json
```

Finding：

```text
NO_REPACK_NOT_SUFFICIENT
```

## B. Metal `--no-op-offload`

Server：

```text
parallel4 / slot512
--no-op-offload
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

Run 1 / seed42：

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **7/8** | **7/8** |
| 4 | **8/8** | **8/8** |

Run 2 / seed43：

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **4/8** | **4/8** |
| 4 | **6/8** | **6/8** |

Combined interpretation：

```text
NO_OP_OFFLOAD_NOT_SUFFICIENT
```

seed42 中 N4 改善只是单次 run 观察无法外推；seed43 重现 N3/N4 instability。
不能把它作为 mitigation。

Artifacts：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-noopoffload.json
  rq3-llama-distinct-prompt-cardinality-metal-noopoffload-seed43.json
```

## Accumulated flag status

| Path / flag | active3 | active4 | Conclusion |
| --- | --- | --- | --- |
| Metal full-GPU auto | unstable | unstable | baseline boundary |
| `--flash-attn off` | unstable | unstable | not sufficient |
| `--no-cont-batching` | unstable | unstable | not sufficient |
| `--cpu-moe` | unstable | unstable | hybrid worsens / N2 unstable |
| `--no-repack` | unstable | unstable | not sufficient |
| `--no-op-offload` | unstable both seeds; N4 unstable on repeat | unstable on repeat | not sufficient |
| CPU-only | stable | stable | execution-path isolation only |

## Non-claims

```text
❌ 已找到可稳定化 Metal active3/4 的 runtime flag
❌ repacking 或 op offload 是根因
❌ seed42 no-op-offload N4 stable 可外推
❌ llama.cpp 内部机制已定位
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
NO_REPACK_NOT_SUFFICIENT
NO_OP_OFFLOAD_NOT_SUFFICIENT
METAL_FLAG_MITIGATION_NOT_ESTABLISHED
```

RQ3 仍保持 OPEN。
