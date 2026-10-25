# SimiGo Lab Cyber-Tiel Cross-Backend Token Matrix V2 — 2026-09-29

## Result

```text
MATRIX_V2 = PASS_WITH_BOUNDARY / PROTOCOL_COMPLETE
IDENTITY = 9/12 PROMPTS EXACT
MISMATCH = 3/12 PROMPTS
RESOURCE = SEQUENTIAL_PHASES / STEADY_SWAP_DELTA_WITHIN_LIMIT
```

登记：

```text
CYBER_TIEL_NAMED_SOURCE_TOKEN_MATRIX_V2_PROTOCOL_PASS
NAMED_SOURCE_GREEDY_IDENTITY_BOUNDARY_OBSERVED
LOAD_STEADY_SWAP_GATE_SPLIT_REGISTERED
```

这不是 all-prompt semantic equivalence，也不是 same-checkpoint closure。结果把
named-source MLX/GGUF greedy identity从 3-prompt pilot扩展到 12-family matrix，
并定位三类分叉。

## Protocol V2

```text
MLX      = Cyber-Tiel Coder 35B A3B MLX oQ4e
GGUF     = Cyber-Tiel Coder 35B A3B MTP UD-Q4_K_XL
phases   = Phase1 MLX only -> immutable record -> exit; Phase2 LLAMA only
prompts  = 12
families = 12
budget   = 24 greedy tokens per prompt
seed     = 42
```

Family set：

```text
baseline / counting / list / code-transform / exact-json / cjk /
ambiguous-continuation / long-prefix-code / constraint / repeat /
docstring / risk
```

## Resource gates

初次 strict gate FAIL artifact保留：模型加载时全局 swap瞬时上升
`1,116,272,066 bytes`，超过当时统一 `512 MiB` 上限；此时只有 MLX Phase1，没有
llama-server。该失败说明统一 gate会把 model-load transient和 steady-state
混在一起。

V2 将 gate拆为：

```text
load transient limit   = 1,610,612,736 bytes
steady-state limit     =   536,870,912 bytes
```

正式 Phase1：

```text
load swap delta    = 0 bytes
steady swap delta  = 198,317,179 bytes
peak MLX bytes     = 21,103,830,324
peak footprint     = 21,310,553,640 bytes
status             = PASS_WITH_BOUNDARY
```

正式 Phase2：

```text
max swap delta     = 0 bytes
status             = PASS_WITH_BOUNDARY
```

## Identity matrix

| ID | Family | Prompt tokens | MLX / LLAMA tokens | Identity |
| --- | --- | ---: | ---: | --- |
| P1 | baseline | 197 | 2 / 2 | PASS |
| P2 | counting | 197 | 24 / 24 | PASS |
| P3 | list | 195 | 11 / 11 | PASS |
| P4 | code-transform | 212 | 13 / 13 | PASS |
| P5 | exact-json | 204 | 6 / 6 | PASS |
| P6 | cjk | 197 | 24 / 24 | **MISMATCH** |
| P7 | ambiguous-continuation | 206 | 3 / 3 | PASS |
| P8 | long-prefix-code | 240 | 2 / 2 | PASS |
| P9 | constraint | 195 | 2 / 2 | PASS |
| P10 | repeat | 197 | 4 / 4 | PASS |
| P11 | docstring | 207 | 24 / 14 | **MISMATCH** |
| P12 | risk | 203 | 24 / 24 | **MISMATCH** |

```text
identical = 9/12 = 0.75
mismatch  = 3/12 = 0.25
```

## Mismatch anatomy

### P6 / cjk

```text
common prefix = 8 tokens
MLX  next token = 99978
LLAMA next token = 101729
```

两个 output都中文且主题相同，但第 9 个 token后选择不同表述。

### P11 / docstring

```text
common prefix = 0 tokens
MLX  first token = 71093
LLAMA first token = 12237
MLX  generated = 24 tokens
LLAMA generated = 14 tokens
```

MLX额外渲染 code fence；LLAMA直接输出 docstring。首 token就分叉。

### P12 / risk

```text
common prefix = 8 tokens
MLX  next token = 506
LLAMA next token = 678
```

两个 output都指出 force unwrapping 的 runtime crash risk，但插入词和后续表述不同。

## Interpretation

1. 短、强约束、代码/结构化任务在 named-source variants上保持 exact greedy
   identity。
2. 自由生成、CJK表述、code-fence formatting和较长解释更容易暴露 quantization
   或 execution-engine numeric differences。
3. output length不同不一定表示语义失败；P11的 LLAMA output在 EOS终止，MLX继续
   渲染 fence。token-level identity仍然为 mismatch。
4. 该矩阵不支持将 named-source result升级为 checkpoint equivalence。

## Validation

```text
Swift tests = 157 PASS / 0 FAIL
```

## Artifacts

```text
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-mlx-record-matrix-v2-initial-strict-gate-fail.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-mlx-record-matrix-v2.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-token-compare-matrix-v2.json
```

Record SHA-256：

```text
a6f8a3e9a2573a5a22675695b3816f27114863df72e67e8fe2e7be21cb6de44f
```

## Boundary

结果限定 named-source Cyber-Tiel variants、12 prompts、12 families、24-token
greedy budget、checkpoint chat-template prefixes、canonical LLAMA profile和本机。
不同 quantization和 execution engine保持为 confound。没有 MTP机制分解，也没有
tokenizer file byte identity proof。

## Next

1. 将 9/12 boundary作为 prompt-family sampling frame，扩展到 longer free-form
   generation和 repeated samples。
2. 对 P6/P11/P12 做 logits/top-token margin comparison，区分 numeric drift与
   formatting/EOS policy。
3. 用 GGUF metadata extractor和 MLX manifest建立 tokenizer/checkpoint lineage
   audit后再讨论 cross-backend closure。
