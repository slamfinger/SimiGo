# SimiGo Lab RQ3 LLAMA Ubatch2 × Threads4 Isolation — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

在 seed42/seed43 补齐对照后登记：

```text
UBATCH2_INDEPENDENT_OF_THREADPOOL
THREADS4_UBATCH2_STABLE_N1_N4
UBATCH2_IS_PRIMARY_MITIGATION
```

先前 stable 配置是 `threads1 / ubatch2`，因此还不能判断修复来自 `ubatch2` 还是
必须叠加 `threads1`。本轮保持默认 `--threads 4 --threads-batch 4`，仅添加
`--ubatch-size 2`；两个 seeds 中 N1–N4 全部 stable。因此 primary mitigation 是
`ubatch2`，不依赖 single-thread CPU coordination。

## Experiment

Server：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / slot512
--ubatch-size 2
--threads 4 --threads-batch 4
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

Distinct equal-length prompts：

```text
prompt0 ping
prompt1 alpha
prompt2 beta
prompt3 gamma
```

每 prompt 6 tokens；先串行生成 3 次 single-load reference，三次均 stable。
cardinality 1–4，各 8 cycles；响应按 prompt index 与自身 reference 比较。
没有 long request、cancellation 或 Execution State object。

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

## Factor matrix

Metal `parallel4` 下：

| threads | ubatch | N3 all-match / across | N4 all-match / across |
| ---: | ---: | ---: | ---: |
| 4 | 512 | `4/8` / `4/8` | `4/8` / `4/8` |
| 1 | 512 | `8/8` / `8/8` | `6/8` / `1/8` |
| 1 | 2 | `8/8` / `8/8` | `8/8` / `8/8` |
| 4 | 2 | **`8/8` / `8/8`** | **`8/8` / `8/8`** |

因此：

```text
ubatch512 是 mismatch 触发面；
ubatch2 独立于 threadpool count 修复 N3/N4；
threads1 只在 ubatch512 下部分缓解 active3。
```

## Artifacts

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch2.json
  rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch2-seed43.json
```

## Boundary

覆盖 current llama-server build、GGUF model、4 个 6-token distinct prompts、
8 generated tokens、`parallel4/slot512`、`threads4/ubatch2` 和 8 cycles/
cardinality。未测量吞吐或性能，不能推荐 `ubatch2` 作为生产配置。没有定位具体
Metal kernel / graph reduction；也没有证明其他模型、backend、context 长度或
ubatch 值具有相同行为。

## Non-claims

```text
❌ ubatch2 是通用生产配置
❌ 性能代价已建立
❌ Metal kernel / graph reduction 根因已定位
❌ 其他模型、backend 或 ubatch 值必然稳定
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
UBATCH2_INDEPENDENT_OF_THREADPOOL
THREADS4_UBATCH2_STABLE_N1_N4
UBATCH2_IS_PRIMARY_MITIGATION
```

RQ3 仍保持 OPEN。
