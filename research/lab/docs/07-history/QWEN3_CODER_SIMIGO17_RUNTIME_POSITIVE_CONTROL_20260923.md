# Qwen3-Coder SimiGo 1.7 Runtime Positive Control

**Date**: 2026-09-23  
**Status**: RUNTIME_POSITIVE_CONTROL_REGISTERED  
**Nature**: runtime-observation correction; not a Concrete Instance or route selection

## 1. Correction

The researcher reports that the local checkpoint

```text
mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit
```

loads and runs in SimiGo 1.7. This corrects any broader claim suggested by the
isolated `mlx-swift-lm` probe. The isolated probe failure must not be read as a
general Qwen3-Coder execution failure.

## 2. Runtime authority

SimiGo 1.7 uses the production vendor pin:

```text
mlx-swift-lm = dc3ca619717192425254d4da18af0c29b978fcf7
mlx-swift    = 0.31.6
```

The prior isolated xcodebuild probe used a different local working-tree state:

```text
mlx-swift-lm = 59e9abd0b876f324f5dcdac876dc91080946c56c
```

That probe was not a SimiGo 1.7 runtime reproduction. Its result is scoped to
the probe harness and local working-tree state; it is not evidence that
Qwen3-Coder cannot run in SimiGo 1.7.

## 3. Existing SimiGo evidence

The SimiGo compatibility matrix already records Qwen3-Coder as a successful
standard `qwen3_moe` control:

| Surface | Result |
| --- | --- |
| OpenAI-compatible path | PASS |
| Responses, single request | PASS |
| Responses, two concurrent first turns | PASS; both completed |
| Tool calling | PASS; 24 tools and continuous tool calls |
| KV / session cache | PASS; reuse=true |
| draftN=2 under concurrency | PASS |

Recorded concurrent TTFTs were `24.9s` and `31.1s`; the first measured rate of
`1.0 tok/s` was attributed to GPU contention. Session-cache examples show cold
TTFT `33.2s`, then `0.69s`, `0.85s`, and `4.1s` on later rounds with cache
efficiency `0.99`, `0.99`, and `0.93`.

## 4. Corrected four-layer view

For the SimiGo 1.7 production runtime:

| Layer | Qwen3-Coder observation |
| --- | --- |
| Declaration | PASS: standard `qwen3_moe`. |
| Instantiation | PASS: loads in SimiGo 1.7. |
| Execution | PASS: Responses/tool-call/cache runs are recorded. |
| Semantic consistency | OPEN: runtime success does not yet prove formal/execution semantic equivalence. |

Thus Qwen3-Coder is better used as a positive runtime control, while Gemma 4
remains a negative/boundary candidate for the same computational-semantics
comparison.

## 5. Boundaries

This correction does not declare `(P1,θ1)`, does not instantiate an instance
family, does not select `COMPUTATIONAL_SEMANTICS`, and does not reopen
R-INTERNAL or R_ASSEMBLY. It does not authorize new implementation, harness,
data collection, profiling, measurement, or experiment work.
