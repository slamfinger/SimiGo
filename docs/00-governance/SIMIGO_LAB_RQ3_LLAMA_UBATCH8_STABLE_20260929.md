# SimiGo Lab RQ3 LLAMA Ubatch8 Stability — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

在 seed42/seed43 补测后登记：

```text
UBATCH8_STABLE_N1_N4
SAFE_UBATCH_UPPER_BOUND_AT_LEAST_8
UBATCH512_INSTABILITY_NOT_SIMPLE_THRESHOLD_AT_8
```

`ubatch2` 仍是最早确认的 mitigation，但不是唯一 stable value：`ubatch4` 与
`ubatch8` 在两个 seeds 中也全部 stable。因此不能把 safe boundary 定为 2。

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
ctx2048 / parallel4 / slot512
--ubatch-size 8
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

seed42 与 seed43 各完整运行一次。

## Results

### seed42

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **8/8** | **8/8** |
| 4 | **8/8** | **8/8** |

### seed43

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **8/8** | **8/8** |
| 4 | **8/8** | **8/8** |

## Ubatch observations

| `ubatch-size` | Seeds | N1-N4 result |
| ---: | --- | --- |
| 2 | 42/43 | stable |
| 4 | 42/43 | stable |
| 8 | 42/43 | stable |
| 512 | 42 | intermittent mismatch |

`ubatch4` artifacts：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch4.json
  rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch4-seed43.json
```

因此当前支持的 safe observed upper bound 是：

```text
ubatch <= 8
```

default `ubatch512` 的 mismatch 不是“只要超过 8 就必然失败”的简单阈值；
更像是大 physical batch shape 下概率性触发的 Metal execution boundary。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch8.json
  rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch8-seed43.json
```

## Boundary

覆盖 current llama-server build、GGUF model、4 个 6-token distinct prompts、
8 generated tokens、`parallel4/slot512`、`threads4`、`ubatch8` 和 8 cycles/
cardinality。未测量性能，没有定位具体 Metal kernel / graph reduction；也没有
测试 9–511 的所有 ubatch 值。

## Non-claims

```text
❌ ubatch8 是通用生产配置
❌ ubatch<=8 在所有模型 / backend / context 下必然稳定
❌ ubatch>8 必然不稳定
❌ performance / throughput 结论已建立
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
UBATCH8_STABLE_N1_N4
SAFE_UBATCH_UPPER_BOUND_AT_LEAST_8
UBATCH512_INSTABILITY_NOT_SIMPLE_THRESHOLD_AT_8
```

RQ3 仍保持 OPEN。
