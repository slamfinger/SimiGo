# SimiGo Lab RQ3 LLAMA Hot-path A/B — 2026-09-29

## Question

> **Execution State 是否可以在不破坏普通 inference hot path 的情况下提供
> fork/restore 能力？**

本轮只回答其中最窄的第一层：在 **no-fork ordinary generation** 中，
capture/bind/release bookkeeping 是否引入可观测 regression。

## Experiment

Harness:

```text
simigo2-experimental/scripts/rq3_llama_hotpath_ab.py
```

设计：

```text
OFF  direct /completion
ON   identical /completion
       + capture current prefix representation
       + bind prompt tokens + returned generated tokens
       + release prior representation
```

控制：

```text
server payload  byte-identical in OFF and ON
fork count      0
temperature     0
seed            42
generated       8 tokens
samples         30 paired samples
alternation     even=ON,OFF; odd=OFF,ON
warmup          one unrecorded request
```

Backend:

```text
llama-server 0.3.0-dev build 10775 commit 67a17c17c
model        Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
```

Raw artifact:

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-hotpath-ab.json
```

## Results

### Semantics

```text
content + generated-token identity  30/30 = 100%
```

### Client wall clock

| Metric | OFF | Execution State ON |
| --- | ---: | ---: |
| mean | 300.951 ms | 300.827 ms |
| median | 300.622 ms | 300.648 ms |
| p95 | 304.257 ms | 303.462 ms |

Paired `ON - OFF`:

```text
mean    -0.124 ms
median   +0.116 ms
p95      +6.392 ms
range   -10.705 .. +7.281 ms
```

The mean absolute paired difference is **2.809 ms**; this is the practical
client-side noise band for this run.

### Local Execution State bookkeeping

```text
mean    0.008525 ms
median  0.006333 ms
p95     0.010993 ms
max     0.062125 ms
```

Ratios:

```text
state bookkeeping / mean request          0.00283%
state bookkeeping / mean absolute paired
  client difference                       0.3035%
```

### Server predicted interval

```text
OFF mean  237.132 ms
ON mean   236.905 ms
paired ON-OFF mean  -0.228 ms
paired absolute mean 2.549 ms
```

## Finding

> **PRELIMINARY NON-REGRESSION / PASS_WITH_BOUNDARY**

在本次 llama-server、单一模型、单一 prompt、8-token generation、无 fork
负载下，Execution State 的 capture/bind/release bookkeeping 平均只有
**8.5 µs/request**，比本 run 的平均配对测量噪声 2.81 ms 低约 **329×**；
client mean difference 为 **-0.413%**，语义输出 **30/30** 一致。

因此，本 run 支持：

> **普通 inference hot path 未被 Execution State bookkeeping 明显污染。**

## Non-claims

这不是通用性能结论，也不声称以下内容：

```text
❌ 跨 backend 普适
❌ 跨模型 / 跨 prompt / 跨 token 长度普适
❌ fork/restore 本身零成本
❌ capture cost / restore cost / release cost 分项已经收敛
❌ 长上下文或 memory pressure 下仍为微秒级
❌ integrated Swift LLAMA executor 已完成
```

本轮 ON 侧使用的是 Python mirror 的本地状态操作；server 请求与
Swift RQ1 contract 的 representation 语义一致，但尚不是集成 Swift executor。

## RQ3 status

```text
RQ3 = OPEN / PRELIMINARY_NON_REGRESSION
```

2026-09-29 后续 fork/restore round 见
`SIMIGO_LAB_RQ3_LLAMA_FORK_RESTORE_COST_20260929.md`：语义 30/30 PASS，
本地 fork/release/restore 约 3.82 µs，但 reference→replay 出现未归因的
+6.688 ms client difference，因此 RQ3 继续保持 OPEN。

关闭前还需要：

1. fork / branch divergence / restore workload 的分项成本。
2. long-context 与 memory-pressure 曲线。
3. cancellation workload。
4. MLX oversized baseline 的等价 A/B。
5. integrated Swift LLAMA executor，消除外部 harness 解释负担。
