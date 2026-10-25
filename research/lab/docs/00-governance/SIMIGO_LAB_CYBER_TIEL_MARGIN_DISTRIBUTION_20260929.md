# SimiGo Lab Cyber-Tiel Margin Distribution — 2026-09-29

## Result

```text
MARGIN_DISTRIBUTION = PASS_WITH_BOUNDARY / FULL_MLX_TRAJECTORY
POSITIONS = 72
MLX_SELF_CONSISTENCY = 72/72
LLAMA_TOP1_AGREEMENT = 66/72 = 91.67%
REFERENCE_IN_LLAMA_TOP16 = 72/72 = 100%
MAX_REFERENCE_RANK_IN_LLAMA = 2
```

登记：

```text
CYBER_TIEL_FULL_TRAJECTORY_MARGIN_DISTRIBUTION_PASS
MLX_BATCHED_TRAJECTORY_SELF_CONSISTENT
LLAMA_TOP1_NEAR_BOUNDARY_FLIP_OBSERVED
NO_TOP16_DISSOCIATION_OBSERVED
```

## Question

Matrix V2 只在首个 divergence teacher-force一次。本轮扩展为完整 MLX greedy
trajectory：对 P6/P11/P12 的每个 generated position，都 teacher-force
`prompt IDs + 前续 MLX reference tokens`，观测 LLAMA next-token top-16与 MLX
top-16 margin。

这不比较两条 divergent paths；它固定 MLX trajectory，测量另一 backend在每个
decision point上的 near-boundary行为。

## Protocol

```text
Phase 1 MLX only
  读取 Matrix V2 compare artifact
  选择 P6/P11/P12 三个 mismatch cases
  对完整 prompt + MLX greedy trajectory 一次 forward
  抽取每个 generated position的 top-16/logprob/margin
  写 immutable record并退出

Phase 2 LLAMA only
  逐 position构造 prompt + prior MLX reference tokens
  提交 /completion，n_probs = 16
  比较 top1 agreement、reference rank和 top1 margin
```

配置：

```text
cases       = P6 cjk / P11 docstring / P12 risk
positions   = 24 + 24 + 24 = 72
topK        = 16
seed        = 42
Phase1 gate = 768 MiB steady swap delta
Phase2 gate = 512 MiB steady swap delta
```

## Summary

| Case | Positions | MLX self-consistent | LLAMA top1 agree | Reference in LLAMA top16 | Max reference rank | Mean MLX top1 margin | Mean LLAMA top1 margin |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P6 cjk | 24 | 24 | 21 (87.5%) | 24 | 1 | 2.645833 | 2.717431 |
| P11 docstring | 24 | 24 | 23 (95.833%) | 24 | 2 | 5.713623 | 6.041444 |
| P12 risk | 24 | 24 | 22 (91.667%) | 24 | 1 | 4.046875 | 4.231230 |
| Total | 72 | 72 | 66 (91.667%) | 72 | 2 | — | — |

## Divergence positions

| Case | Position | MLX reference | LLAMA top1 | Reference rank in LLAMA | Reference deficit in LLAMA |
| --- | ---: | --- | --- | ---: | ---: |
| P6 cjk | 8 | `99978` / 访问 | `101729` / 请求 | 1 | 0.852407 |
| P6 cjk | 9 | `95952` | `96043` | 1 | 2.406191 |
| P6 cjk | 23 | `96746` | `108572` | 1 | 0.715313 |
| P11 docstring | 0 | `71093` / ``` | `12237` / `"""` | 2 | 1.833576 |
| P12 risk | 8 | `506` / ` at` | `678` / ` your` | 1 | 1.465946 |
| P12 risk | 22 | `846` | `1112` | 1 | 0.988773 |

所有 6 个 divergence的 reference deficit都不超过 2.41 logprob；P6/P12的 5 个
position的 deficit不足 2.5 logprob。P11 position 0 是 formatting-policy敏感点。

## Interpretation

1. MLX batched full-trajectory logits对 72/72 greedy choices self-consistent，
   说明 full-sequence recompute没有引入 top1 mismatch。
2. LLAMA在 91.67% positions选择同一 top1；6 个 flip都在 close-candidate区域。
3. 所有 MLX reference tokens都在 LLAMA top16，最大 rank仅为 2，因此没有
   top16 dissociation。
4. P6/P12的 mismatch是 near-boundary numeric drift；P11 position 0还叠加
   code-fence vs direct-docstring formatting policy。

## Validation

```text
Swift tests = 157 PASS / 0 FAIL
```

## Artifacts

```text
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-record.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-compare.json
```

Record SHA-256：

```text
764475cf74fa08de05abda0d9afed6f185bd07041422d00d5975fdc5d2a0f63d
```

Compare SHA-256：

```text
0f60d64fcbb0b377b4d898652a24bba62f15c11a421912fa9b6699ae9f9a2430
```

实现：

```text
CrossBackendMarginProbe.runRecord
CrossBackendMarginProbe.runCompare
CLI: cross-backend-margin-record / cross-backend-margin-compare
```

## Resource

```text
Phase1 MLX steady swap delta = 494,340,670 bytes <= 768 MiB
Phase2 LLAMA steady swap delta = 0 bytes <= 512 MiB
peak MLX bytes = 21,103,830,324
```

## Boundary

结果限定 named-source Cyber-Tiel MLX oQ4e与 MTP UD-Q4_K_XL GGUF variants、
P6/P11/P12、MLX greedy trajectory、teacher-forced prefixes、top-16 observation、
canonical LLAMA profile和本机。不比较两条 divergent paths；不建立 quantization
equivalence、tokenizer lineage proof、MTP root cause或 same-checkpoint closure。

## Next

1. 扩展到 Matrix V2 的 9 个 identity cases和更多 prompt families。
2. 对 6 个 flip points做 repeated seed / batch-shape ablation。
3. 将 near-boundary acceptance rule形式化为可复用 gate。
