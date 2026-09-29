# SimiGo Lab RQ3 LLAMA Threadpool Ablation — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

Metal `parallel4` 下将 llama-server generation threadpool 从默认 4 threads 改为：

```text
--threads 1 --threads-batch 1
```

两个 seeds 登记为：

```text
METAL_THREADPOOL_ONE_ELIMINATES_ACTIVE3_MISMATCH
ACTIVE4_METAL_STILL_UNSTABLE
METAL_THREADPOOL_COUNT_ISOLATED
```

这说明 llama-server CPU threadpool 并发是一个真实变量：`threads=1` 可消除
active3 mismatch，但不能消除 active4 mismatch。

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
--threads 1 --threads-batch 1
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

Seed42 与 seed43 各完整运行一次。

## Results

### seed42

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **8/8** | **8/8** |
| 4 | **6/8** | **1/8** |

Mismatches by prompt：`1/0/0/2`。

### seed43

| Cardinality | All-match | Across-cycle stable |
| ---: | ---: | ---: |
| 1 | **8/8** | **8/8** |
| 2 | **8/8** | **8/8** |
| 3 | **8/8** | **8/8** |
| 4 | **6/8** | **1/8** |

Mismatches by prompt：`1/0/0/2`。

## Cross-config interpretation

| Config | active3 | active4 |
| --- | --- | --- |
| Metal `threads=4` baseline | unstable (`4/8`) | unstable (`4/8`) |
| Metal `threads=1` | **stable (`8/8` both seeds)** | unstable (`6/8`, across `1/8`) |
| CPU-only `threads=4` | stable | stable |

因此：

```text
active3 mismatch depends on llama-server CPU threadpool concurrency.
active4 mismatch persists even with one CPU threadpool thread.
```

这把边界进一步拆分为两个现象：

1. active3 mismatch 与 CPU threadpool 并发相关；
2. active4 mismatch 在 single-thread CPU coordination 下仍存在，说明还有
   Metal active4 execution path / graph shape 相关变量。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-threads1.json
  rq3-llama-distinct-prompt-cardinality-metal-threads1-seed43.json
```

## Non-claims

```text
❌ threads=1 是通用生产 mitigation
❌ CPU threadpool 是 active4 mismatch 根因
❌ Metal kernel / graph / batch reduction 机制已定位
❌ 其他模型或 backend 结论已建立
❌ performance claim 已建立；threads=1 只作为当前 harness 运行记录
```

## RQ3 boundary

RQ3 增加：

```text
METAL_THREADPOOL_ONE_ELIMINATES_ACTIVE3_MISMATCH
ACTIVE4_METAL_STILL_UNSTABLE
METAL_THREADPOOL_COUNT_ISOLATED
```

RQ3 仍保持 OPEN。
