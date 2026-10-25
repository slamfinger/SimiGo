# SimiGo Lab RQ3 LLAMA Fork/Restore Cost — 2026-09-29

## Question

RQ3 的下一层不是 no-fork bookkeeping，而是：

```text
capture → fork/derive → branch divergence → release divergent state
        → restore fork point → replay reference continuation
```

其中本地 Execution State 操作和 backend inference 成本必须分开记录。

## Experiment

Harness:

```text
simigo2-experimental/scripts/rq3_llama_fork_restore_cost.py
```

Raw evidence:

```text
simigo2-experimental/results/backend-conformance/
  rq3-llama-fork-restore-cost.json
```

固定条件：

```text
backend       llama-server 0.3.0-dev build 10775 commit 67a17c17c
model         Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
representation token-ID prefix
samples       30
generation    8 tokens
temperature   0
seed          42
server prompt token-ID array
```

每个 sample 的序列：

```text
bind parent checkpoint
  → capture checkpoint
  → reference generation
  → derive child at checkpoint
  → divergent child generation
  → bind advanced child
  → capture divergent representation
  → release divergent representation
  → restore child fork point
  → replay reference generation
```

## Semantic checks

| Check | Result |
| --- | ---: |
| restored replay content + tokens == reference | **30/30** |
| branch actually diverged | **30/30** |
| parent prefix non-interference | **30/30** |
| child restored exactly to fork point | **30/30** |

## Local Execution State costs

| Operation | Mean | Median | p95 |
| --- | ---: | ---: | ---: |
| capture | 2.605 µs | 1.208 µs | 1.715 µs |
| derive / fork | 1.281 µs | 1.209 µs | 1.638 µs |
| release | 1.350 µs | 1.230 µs | 2.494 µs |
| restore | 0.997 µs | 1.042 µs | 2.259 µs |

`derive + release + restore` 合计：

```text
mean  3.821 µs
p95   6.267 µs
max   8.000 µs
```

该本地合计只占 reference/replay 平均绝对 client difference 的：

```text
0.0563%
```

## Inference observations

| Phase | Client mean | Server predicted mean |
| --- | ---: | ---: |
| reference | 300.536 ms | 236.162 ms |
| divergence | 302.940 ms | 236.781 ms |
| replay after restore | 307.223 ms | 236.001 ms |

`replay - reference`：

```text
client mean                  +6.688 ms
client absolute mean          6.788 ms
server predicted mean delta   -0.161 ms
server prompt mean delta      -0.765 ms
```

两阶段的 `cachedN=2`、`promptN=4` 保持一致。

将 client wall time 减去 server `promptMs + predictedMs` 后，未归因部分为：

```text
reference          0.925 ms
divergence         3.380 ms
replay             8.538 ms
replay-reference   +7.614 ms
```

## Finding

> **FORK_RESTORE_LOCAL_COST_CHARACTERIZED / SEMANTICS_PASS / RQ3 STILL OPEN**

本 run 证明：

1. token-prefix representation 能在 LLAMA-server 上通过
   fork/diverge/release/restore/replay 语义检查。
2. 本地 Execution State fork/release/restore bookkeeping 在微秒级，
   不是本 run 观测到的毫秒级差异来源。

但 reference→replay 的 **+6.688 ms client difference** 尚未归因；server
reported predicted/prompt 时间无法解释。它可能来自 backend cache traversal、
slot LCP 选择、HTTP/transport、client ordering 或测量顺序效应。因此不能把
本轮解释为 fork/restore 零成本，也不能据此关闭 RQ3。

## Non-claims

```text
❌ 跨 backend / 模型 / prompt / 上下文长度普适
❌ fork/restore 总成本为微秒级；只有本地 bookkeeping 为微秒级
❌ backend cache 行为已经被解释
❌ long-context、memory pressure、cancellation 已验证
❌ integrated Swift LLAMA executor 已完成
```

## Next minimal action

1. ~~复现并隔离 +6.7 ms 差异~~ 已完成第一轮 control；见下节。
2. 继续用 llama-server logs / metrics 定位 context-transition 的内部步骤。
3. 之后再扩展 long-context 与 memory-pressure。

## Follow-up control — backend context transition

新增：

```text
simigo2-experimental/scripts/rq3_llama_context_controls.py
```

control 中没有任何 Execution State object。每个 cycle 交替运行两个纯
backend sequence：

```text
same     C,C,C
diverge  C,D,C
```

server 启动：

```text
--no-cache-prompt --no-cache-idle-slots
request cache_prompt=false
cycles 20，交替 order
```

### Result A — long D（10 tokens）

| Sequence | third-minus-first client mean |
| --- | ---: |
| `C,C,C` | +0.262 ms |
| `C,D,C` | +5.546 ms |
| difference | **+5.284 ms** |

`n_predict=1`。两序列的 third token 均为 **20/20** 与 first 一致。

### Result B — same-length D（6 tokens）

`D = "Return exactly one word: alpha"`，与 C 同为 6 tokens。

| Sequence | third-minus-first client mean |
| --- | ---: |
| `C,C,C` | -0.633 ms |
| `C,D,C` | -0.417 ms |
| difference | **+0.216 ms** |

### Attribution

原始 fork/restore round 中的 `+6.688 ms` 不能归给本地 Execution State：

1. 纯 backend control 没有 Execution State object，仍出现同方向差异。
2. server 级 prompt cache 与 idle-slot cache 禁用后，差异仍存在。
3. `n_predict=1` 时差异仍存在，排除 8-token generation。
4. 将 D 缩到与 C 同长后，差异从约 `+5.3 ms` 降到 `+0.2 ms`。

## Follow-up control — slot similarity and server task trace

再次禁用 slot 选择相关性：

```text
--slot-prompt-similarity 0.0
--no-cache-prompt --no-cache-idle-slots
long D，n_predict=1，20 cycles
```

结果：

```text
C,C,C third-minus-first      -3.663 ms
C,D,C third-minus-first      +4.761 ms
diverge-minus-same           +8.423 ms
semantic identity            20/20 + 20/20
```

因此 slot prompt similarity / LCP selection 也不是主因。

解析 server log 的 `release → next launch` 延迟：

| Transition | n | Mean | Median |
| --- | ---: | ---: | ---: |
| `10 → 6` | 20 | **7.741 ms** | 5.295 ms |
| `6 → 10` | 20 | 2.294 ms | 1.804 ms |
| `6 → 6` | 80 | 1.915 ms | 0.564 ms |

`sequenceMatch=true`。该 trace 直接命中 client 观测：`C,D,C` 的第三个 C
前面是 `10 → 6` transition；`C,C,C` 只有 `6 → 6` transition。

## Follow-up sweep — token length is not a sufficient cause

继续做 6/7/8/9/10-token divergent prompt sweep：

```text
simigo2-experimental/scripts/rq3_llama_transition_length_sweep.py
12 cycles per length
n_predict=1
same backend cache/similarity flags
```

`C,D,C` 减 `C,C,C` 的 client difference：

| D length | Mean difference |
| ---: | ---: |
| 6 | +9.822 ms |
| 7 | +5.485 ms |
| 8 | +7.885 ms |
| 9 | +4.988 ms |
| 10 | +6.389 ms |

线性相关为 `-0.593`，因此不能把原因简化为 token 长度单调增长。
server trace 更稳定的信号是：只要从较长 prompt 返回 6-token C，就会看到
`N → 6` transition delay：

| Transition | n | Mean |
| --- | ---: | ---: |
| `7 → 6` | 6 | 8.404 ms |
| `8 → 6` | 6 | 12.309 ms |
| `9 → 6` | 6 | 6.951 ms |
| `10 → 6` | 6 | 7.124 ms |

同长度 `6 → 6` 的 same-sequence baseline 在各段为 `1.415–2.035 ms`。
注意：6-token D 在 sweep 中也能触发较高差异，所以 content、run order、
slot 历史或 prompt-cache 内部布局都可能参与；不能写成纯长度公式。

## Root-cause control — HTTP transport and slot state cache

### Keep-alive control

改用单条 HTTP keep-alive connection 重跑 long-D control：

```text
transport                  HTTP keep-alive
server cache flags         --no-cache-prompt --no-cache-idle-slots
slot similarity            0.0
sequence                   C,C,C vs C,D,C
n_predict                  1
cycles                     20
```

结果：

```text
C,C,C third-minus-first    -2.261 ms
C,D,C third-minus-first    +4.518 ms
diverge-minus-same         +6.779 ms
semantic identity          20/20 + 20/20
```

因此新建 TCP connection / urllib transport 不是差异来源。

`release → next launch` 仍为：

| Transition | n | Mean |
| --- | ---: | ---: |
| `10 → 6` | 20 | **7.334 ms** |
| `6 → 10` | 20 | 2.478 ms |
| `6 → 6` | 80 | 1.565 ms |

### Verbose root cause

`--verbosity 6` 下，`D → C` 的关键 trace 为：

```text
D release                      0.02.244.956
task 18 posted to queue        0.02.245.272
updating prompt cache          0.02.245.279
prompt_save length=10          state size = 63.009 MiB
load better prompt length=6    f_keep = 1.000, f_sim = 1.000
cache state                    125.822 MiB
prompt cache update took       10.26 ms
task 18 launched               0.02.255.583
```

这把 `release → launch` delay 精确落到 llama-server slot state cache：
保存 10-token idle slot state，再查找/加载 6-token prompt。
该 build 已带 `--no-cache-prompt --no-cache-idle-slots`，但 observed cache
update 仍发生；说明这两个 flag 在本 run 中没有阻止 idle slot state cache。

### `--cache-ram 0` closure control

加入 `--cache-ram 0` 后，keep-alive long-D control 变为：

```text
C,C,C third-minus-first    +1.121 ms
C,D,C third-minus-first    +0.428 ms
diverge-minus-same         -0.693 ms
semantic identity          20/20 + 20/20
```

server transition delay：

| Transition | n | Mean |
| --- | ---: | ---: |
| `10 → 6` | 20 | 0.530 ms |
| `6 → 10` | 20 | 0.549 ms |
| `6 → 6` | 80 | 0.555 ms |

root cause confirmed：

> **llama-server slot state cache update，而非 Execution State、HTTP transport、
> slot similarity 或 model generation 本身。**

### Fork/restore rerun with `--cache-ram 0`

复跑 30-sample fork/restore benchmark：

| Check | Result |
| --- | ---: |
| restored replay identity | **30/30** |
| branch divergence | **30/30** |
| parent prefix non-interference | **30/30** |
| child restored to fork point | **30/30** |

本地 `derive + release + restore` 仍为微秒级：

```text
mean  3.306 µs
p95   7.747 µs
```

client 成本：

| Phase | Mean |
| --- | ---: |
| reference | 301.355 ms |
| divergence | 424.948 ms |
| replay after restore | 303.505 ms |

`replay - reference` 从原 default-slot-cache run 的 `+6.688 ms` 降为
`+2.150 ms`；该 run 的 mean absolute paired difference 为 `6.047 ms`，
因此已进入测量噪声。原 `+6.7ms` 系统性差异被移除。

因此当前归因是：

> **llama-server `release → next launch` transition delay，尤其是较长 prompt
> 返回较短 prompt 的 `N → 6` transition；不是本地 Execution State
> bookkeeping，也不是 slot similarity。更精确定位是 slot state cache update。
> 这是 backend configuration cost line，不是 RQ3 的 Execution State hot-path
> pollution evidence。

Artifacts:

```text
rq3-llama-context-controls-nocache.json
rq3-llama-context-controls-npredict1-longD.json
rq3-llama-context-controls-npredict1-sameLengthD.json
rq3-llama-context-controls-slotSim0-longD.json
rq3-llama-context-controls-slotSim0-taskTrace.json
rq3-llama-context-controls-slotSim0-server.log
rq3-llama-transition-length-sweep.json
rq3-llama-transition-length-sweep-server.log
rq3-llama-context-controls-keepAlive-longD.json
rq3-llama-context-controls-keepAlive-taskTrace.json
rq3-llama-context-controls-cacheRam0-longD.json
rq3-llama-context-controls-cacheRam0-taskTrace.json
rq3-llama-prompt-cache-root-cause-verbose.log
rq3-llama-fork-restore-cost-cacheRam0.json
rq3-llama-fork-restore-cost-cacheRam0-server.log
```
