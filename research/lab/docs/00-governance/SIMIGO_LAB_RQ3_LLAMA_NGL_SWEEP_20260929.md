# SimiGo Lab RQ3 LLAMA NGL Sweep — 2026-09-29

## Decision

Protocol：

```text
RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1
```

完成 Metal layer-split sweep 后登记：

```text
NGL20_30_35_37_STABLE_ACTIVE4
NGL38_INTERMITTENT_ACTIVE4_MISMATCH
NGL_BOUNDARY_LOCALIZED_TO_HIGH_LAYER_SPLIT
DETERMINISTIC_NGL_THRESHOLD_NOT_ESTABLISHED
```

这把 Metal backend isolation 进一步收窄：将部分层留在 CPU 时，`ngl<=37`
的 active4 runs 均 stable；`ngl38` 三次 run 中两次 stable、一次 active4
mismatch。因此 mismatch 与 high-layer Metal split 相关，但不是稳定 deterministic
threshold。

## Experiment

沿用 distinct equal-length prompt cardinality probe：

```text
prompt0 ping
prompt1 alpha
prompt2 beta
prompt3 gamma
```

每 prompt 6 tokens；每个 configuration 先串行生成 3 次 single-load reference，
三次均 stable。cardinality 1–4，各 8 cycles；active4 mismatch 通过与当前
configuration reference 比较判定。没有 long request、cancellation 或 Execution
State object。

Server：

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
ctx2048 / parallel4 / slot512 / ubatch512
--n-gpu-layers N
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

## NGL sweep

| `--n-gpu-layers` | Seed / run | N4 all-match | N4 across-cycle |
| ---: | --- | ---: | ---: |
| 20 | 42 | **8/8** | **8/8** |
| 30 | 42 | **8/8** | **8/8** |
| 35 | 42 | **8/8** | **8/8** |
| 37 | 42 | **8/8** | **8/8** |
| 38 | 42 initial | **3/8** | **5/8** |
| 38 | 42 repeat | **7/8** | **7/8** |
| 38 | 43 | **8/8** | **8/8** |
| 40 full Metal baseline | 42 | **4/8** | **4/8** |

Interpretation：

```text
ngl20/30/35/37  => active4 stable
ngl38           => intermittent active4 mismatch
full40          => active4 mismatch observed
```

NGL38 三次 run 的 mismatch cycle 数分别为 `3/8`、`1/8`、`0/8`。这说明 layer
split 确实进入敏感区间，但 mismatch 是概率性/调度相关的，不能简化为
“`ngl>=38` 必然失败”。

## Artifacts

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-distinct-prompt-cardinality-metal-ngl20.json
  rq3-llama-distinct-prompt-cardinality-metal-ngl30.json
  rq3-llama-distinct-prompt-cardinality-metal-ngl35.json
  rq3-llama-distinct-prompt-cardinality-metal-ngl37.json
  rq3-llama-distinct-prompt-cardinality-metal-ngl38.json
  rq3-llama-distinct-prompt-cardinality-metal-ngl38-seed42-repeat.json
  rq3-llama-distinct-prompt-cardinality-metal-ngl38-seed43.json
```

## Boundary

覆盖 current llama-server build、GGUF model、4 个 6-token distinct prompts、
8 generated tokens、`parallel4/slot512/ubatch512` 和 8 cycles/cardinality。
NGL sweep 只改变层放置，不改变 ubatch、threadpool、FA、repack 或 op-offload。
未定位具体 Metal kernel / graph reduction；未测试所有 NGL 21–39 值。

## Non-claims

```text
❌ 精确 NGL threshold 已证明
❌ 特定 Metal kernel / graph reduction 已定位
❌ ngl38 必然 unstable 或 ngl37 必然 stable 的普适结论
❌ performance / throughput 结论已建立
❌ production readiness 已完成
```

## RQ3 boundary

RQ3 增加：

```text
NGL20_30_35_37_STABLE_ACTIVE4
NGL38_INTERMITTENT_ACTIVE4_MISMATCH
NGL_BOUNDARY_LOCALIZED_TO_HIGH_LAYER_SPLIT
DETERMINISTIC_NGL_THRESHOLD_NOT_ESTABLISHED
```

RQ3 仍保持 OPEN。
