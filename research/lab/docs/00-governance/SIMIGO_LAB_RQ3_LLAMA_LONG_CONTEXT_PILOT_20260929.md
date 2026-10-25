# SimiGo Lab RQ3 LLAMA Long-context Pilot — 2026-09-29

## Question

在 `--cache-ram 0` 已确认 slot state cache root cause 后，较长的 divergent
prompt 是否会在 LLAMA-server 的下一个 short C prompt 上引入随长度增长
的 transition cost？

本轮是 **backend control pilot**，没有 Execution State object。

## Experiment

Harness:

```text
simigo2-experimental/scripts/rq3_llama_context_controls.py
```

Server:

```text
llama-server 0.3.0-dev
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
--ctx-size 512 --parallel 1
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

Request:

```text
C = 6-token "Return exactly one word: ping"
D = repeated alpha/beta vocabulary
length D = 36 / 144 / 288 / 432 tokens
cycles   = 12 per length
n_predict=1, temperature=0, seed=42
request cache_prompt=false
HTTP keep-alive
sequence same    = C,C,C
sequence diverge = C,D,C
primary metric   = diverge-minus-same third-minus-first client delta
```

## Results

| D tokens | same `C3-C1` | diverge `C3-C1` | paired delta | D prompt mean | next-C-after-D prompt mean | semantics |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 36  | +0.051 ms | -0.936 ms | **-0.986 ms** | 191.289 ms | 99.676 ms | 12/12 + 12/12 |
| 144 | -0.907 ms | +0.778 ms | **+1.685 ms** | 328.745 ms | 102.061 ms | 12/12 + 12/12 |
| 288 | +0.878 ms | +0.807 ms | **-0.071 ms** | 494.198 ms | 105.671 ms | 12/12 + 12/12 |
| 432 | -0.182 ms | -0.843 ms | **-0.662 ms** | 663.658 ms | 102.048 ms | 12/12 + 12/12 |

D 的 prompt cost 本身随长度明显上升；但 D 之后回到 short C 时，没有看到
随 D 长度单调增长的 transition penalty。所有 paired delta 都在本 pilot 的
短上下文噪声带内；每长度 12 组 next-C prompt mean 保持在约
`99.7–105.7ms`。

原始 artifact：

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-long-context-pilot-1slot-L036.json
  rq3-llama-long-context-pilot-1slot-L144.json
  rq3-llama-long-context-pilot-1slot-L288.json
  rq3-llama-long-context-pilot-1slot-L432.json
```

## Topology hazard

第一次 preflight 使用默认 slot 自动展开成 4 slots。到达 432-token D 时，
server 出现 KV free-space retry 并 purge 其他 slot。这些 artifact 保留为
`rq3-llama-long-context-pilot-4slots-kvpressure-*.json`，只记录该拓扑
hazard，不用于 transition-cost attribution。

clean pilot 统一使用 `--parallel 1`，启动面为 `n_slots=1 /
n_ctx_slot=512 / kv_unified=false`。

## Finding

> **LONG_D_TRANSITION_PILOT_WITHIN_NOISE / SEMANTICS_PASS**

在当前 `cacheRam0 + one-slot + 512-token context + GGUF model` 条件下，
36–432 token 的 long-D backend transition 没有表现出单调增长的下一请求
成本。该结果进一步支持 slot state cache 是先前观察到的毫秒级差异主因；
但不能推出长上下文 transition 恒为零成本。

## Non-claims

```text
❌ 超过 512 token 的 long-context 已收口
❌ 跨模型 / 跨 backend / 跨 workload 普适
❌ memory-pressure 曲线已完成
❌ cancellation workload 已完成
❌ 这是 Execution State hot-path A/B；本 control 不含 Execution State object
❌ 可建立通用 D-length-to-cost 公式
```

## RQ3 boundary

RQ3 仍保持：

```text
OPEN / LOCAL_STATE_NON_REGRESSION /
FORK_RESTORE_SEMANTICS_PASS /
SLOT_STATE_CACHE_ROOT_CAUSE_CONFIRMED /
LONG_D_TRANSITION_PILOT_WITHIN_NOISE
```

下一最小缺口仍是真正的 memory-pressure 曲线、cancellation control、MLX
oversized 等价 A/B，以及 integrated Swift LLAMA executor。
