# SimiGo Lab RQ3 LLAMA Ubatch Isolation — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

在 Metal `parallel4 / threads1` 下将 physical batch 从默认：

```text
--ubatch-size 512
```

改为：

```text
--ubatch-size 2
```

两个 seeds 登记为：

```text
METAL_THREADS1_UBATCH2_STABLE_N1_N4
ACTIVE4_METAL_UBATCH2_MITIGATION_OBSERVED
UBATCH_SHAPE_ISOLATED
```

这把 active4 mismatch 的剩余变量进一步定位到 physical ubatch shape。`ubatch=2`
是当前 harness 中第一个让 Metal active4 在两个 seeds 下均稳定的配置。

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
--ubatch-size 2
--threads 1 --threads-batch 1
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

两 seeds 合计 N1–N4 共 80 requests，全部 match 自身 reference。

## Cross-config comparison

在 Metal `parallel4 / threads1` 下：

| Config | N1 | N2 | N3 | N4 |
| --- | ---: | ---: | ---: | ---: |
| `ubatch512` | `8/8` | `8/8` | `8/8` | all-match `6/8`, across `1/8` |
| `ubatch2` | **`8/8`** | **`8/8`** | **`8/8`** | **`8/8`** |

因此 active4 mismatch 与 physical ubatch shape 相关；`ubatch2` 是当前观察到的
effective mitigation。这与 CPU-only stable 的结果一致：问题不是 Execution State
contract，而是 Metal 特定 execution shape。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-threads1-ubatch2.json
  rq3-llama-distinct-prompt-cardinality-metal-threads1-ubatch2-seed43.json
```

## Boundary

覆盖 current llama-server build、GGUF model、4 个 6-token distinct prompts、
8 generated tokens、`parallel4/slot512`、`threads1`、`ubatch2` 和 8 cycles/
cardinality。没有测量吞吐或性能，不能说 `ubatch2` 更快或适合生产。没有定位具体
Metal kernel / graph reduction；也没有证明其他模型、backend、context 长度或
ubatch 值具有相同行为。

## Non-claims

```text
❌ ubatch2 是通用生产配置
❌ Metal kernel / graph reduction 根因已定位
❌ 其他 ubatch 值、模型或 backend 必然稳定
❌ performance / throughput 结论已建立
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
METAL_THREADS1_UBATCH2_STABLE_N1_N4
ACTIVE4_METAL_UBATCH2_MITIGATION_OBSERVED
UBATCH_SHAPE_ISOLATED
```

RQ3 仍保持 OPEN。
