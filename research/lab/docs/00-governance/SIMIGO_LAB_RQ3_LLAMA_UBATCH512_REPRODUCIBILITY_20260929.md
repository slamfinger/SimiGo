# SimiGo Lab RQ3 LLAMA Ubatch512 Reproducibility — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

用 seed43 复跑 full-Metal default `ubatch512` 后登记：

```text
METAL_UBATCH512_MISMATCH_REPRODUCED
ACTIVE3_UNSTABLE_BOTH_SEEDS
ACTIVE4_UNSTABLE_BOTH_SEEDS
```

因此 default `ubatch512` 的 active3/4 mismatch 不是 seed42 单次观察，而是可复现
baseline boundary。

## Experiment

继续使用 distinct equal-length prompt cardinality probe：

```text
prompt0 ping
prompt1 alpha
prompt2 beta
prompt3 gamma
```

每 prompt 6 tokens；先串行生成 3 次 single-load reference，三次均 stable。
cardinality 1–4，各 8 cycles；响应按 prompt index 与自身 reference 比较。
没有 long request、cancellation 或 Execution State object。

Server：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / slot512 / ubatch512
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

## Results

### seed42 prior baseline

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **4/8** | **4/8** |
| 4 | **4/8** | **4/8** |

### seed43 new reproducibility run

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **6/8** | **6/8** |
| 4 | **3/8** | **5/8** |

Mismatches by prompt：

```text
seed42 N3 = 4/0/0
seed43 N3 = 2/0/0
seed42 N4 = 4/0/0/4
seed43 N4 = 5/0/0/5
```

## Interpretation

| Cardinality | Seeds unstable | Conclusion |
| ---: | --- | --- |
| 1 | none | stable in observed runs |
| 2 | none | stable in observed runs |
| 3 | 42/43 | reproducible unstable |
| 4 | 42/43 | reproducible unstable |

结合 mitigation runs：

```text
ubatch512 / threads4  => N3/N4 unstable in both seeds
ubatch2   / threads4  => N1-N4 stable in both seeds
ubatch2   / threads1  => N1-N4 stable in both seeds
```

因此 default `ubatch512` mismatch reproducible，且 `ubatch2` mitigation 不是
seed-specific coincidence。

## Artifact

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-ubatch512-seed43.json
```

## Boundary

覆盖 current llama-server build、GGUF model、4 个 6-token distinct prompts、
8 generated tokens、`parallel4/slot512/ubatch512`、`threads4` 和 8 cycles/
cardinality。未定位具体 Metal kernel / graph reduction；不建立性能、上游
llama.cpp 实现缺陷或跨模型/跨 backend 结论。

## Non-claims

```text
❌ 具体 Metal kernel / graph reduction 已定位
❌ 所有 seed / prompt / context 下必然失稳
❌ ubatch2 性能代价已量化
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
METAL_UBATCH512_MISMATCH_REPRODUCED
ACTIVE3_UNSTABLE_BOTH_SEEDS
ACTIVE4_UNSTABLE_BOTH_SEEDS
```

RQ3 仍保持 OPEN。
