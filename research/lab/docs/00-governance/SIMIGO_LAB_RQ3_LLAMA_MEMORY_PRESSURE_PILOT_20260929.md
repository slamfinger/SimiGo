# SimiGo Lab RQ3 LLAMA Memory-pressure Pilot — 2026-09-29

## Question

在 `ctx512` 的 unified KV topology 中，432-token D 触发 server 内部
free-space retry/purge 后，backend 语义是否仍然恢复？这是 backend
memory-pressure observation，不是 Execution State A/B。

## Experiment

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
--ctx-size 512
parallel = auto  => n_slots=4 / n_ctx_slot=512 / kv_unified=true
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
verbosity = 6
```

Control:

```text
same    = C,C,C       (C = 6 tokens)
diverge = C,D,C       (D = 432 tokens)
cycles  = 12
n_predict=1, temperature=0, seed=42
request cache_prompt=false, HTTP keep-alive
```

## Pressure evidence

verbosity-6 log 抽取为：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-memory-pressure-4slot-auto-L432.server-events.json
```

事件计数：

```text
init attention-ubatch failure      18
failed to find a memory slot       18
failed to find free space          18
try_clear_id purging slot          18
```

purge 分布：

| Slot | Purged tokens | Count |
| ---: | ---: | ---: |
| 0 | 6   | 6 |
| 1 | 6   | 6 |
| 2 | 432 | 6 |

也就是说，D 并未让请求失败；server 进入内部 KV free-space retry 并按 LRU
清空其它 slot 后完成。

## Results

| Sequence | phase | client mean | prompt mean | tokens |
| --- | ---: | ---: | ---: | ---: |
| same    | C1 | 104.422 ms | 103.445 ms | 6 |
| same    | C2 | 102.173 ms | 101.247 ms | 6 |
| same    | C3 | 102.980 ms | 101.927 ms | 6 |
| diverge | C1 | 101.893 ms | 100.654 ms | 6 |
| diverge | D  | 651.604 ms | 650.617 ms | 432 |
| diverge | C3 | 100.720 ms |  99.930 ms | 6 |

Summary:

```text
same C3-C1                  -1.442 ms
diverge C3-C1               -1.173 ms
paired diverge-minus-same   +0.268 ms
semantics                   12/12 + 12/12
```

原始 control：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-memory-pressure-4slot-auto-L432.json
```

## Finding

> **BACKEND_KV_PRESSURE_RECOVERS / SEMANTICS_PASS**

在本次单一 topology pilot 中，432-token D 显式触发 server 内部 KV
pressure/purge，但后续 6-token C 的 prompt mean 回到约 `99.9ms`，第三
token 语义保持 `12/12`。paired transition delta 为 `+0.268ms`，在本
pilot 内没有观察到恢复后的持续惩罚。

## Non-claims

```text
❌ 不是系统 RAM / swap pressure 实验
❌ 不是并发请求 memory-pressure 曲线
❌ 不是 Execution State release/recovery A/B
❌ 跨模型 / backend / context 长度普适
❌ 可宣称 pressure recovery 零成本
❌ RQ3 memory-pressure 线已收口
```

## RQ3 boundary

RQ3 保持：

```text
OPEN / LOCAL_STATE_NON_REGRESSION /
FORK_RESTORE_SEMANTICS_PASS /
SLOT_STATE_CACHE_ROOT_CAUSE_CONFIRMED /
LONG_D_TRANSITION_PILOT_WITHIN_NOISE /
BACKEND_KV_PRESSURE_RECOVERS
```

下一最小缺口仍是 Execution State 侧的 pressure/release/recovery A/B、
并发 workload、cancellation control、MLX oversized 等价 A/B，以及
integrated Swift LLAMA executor。
