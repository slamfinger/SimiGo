# SimiGo Lab Cyber-Tiel Quantized Layout Pilot — 2026-09-29

## Result

```text
QUANTIZED_DRIFT_PILOT = PASS_WITH_BOUNDARY / LAYOUT_OR_SOURCE_UNRESOLVED
TENSORS = 3
ALL_FINITE = TRUE
ELEMENTWISE_COSINE_NEAR_ZERO = TRUE
QUANTIZER_DRIFT_ATTRIBUTABLE = FALSE
```

登记：

```text
CYBER_TIEL_Q8_VS_MLX_QUANTIZED_PILOT_PASS
TENSOR_ELEMENT_MAPPING_UNRESOLVED
QUANTIZER_DRIFT_NOT_ATTRIBUTABLE
```

## Scope

选取 layer1的三个 Q8_0 tensors：

```text
blk.1.attn_qkv.weight ↔ linear_attn.in_proj_qkv
blk.1.attn_gate.weight ↔ linear_attn.in_proj_z
blk.1.ssm_out.weight   ↔ linear_attn.out_proj
```

GGUF Q8_0完整 dequant；MLX affine tensors通过 `mx.dequantize`完整 dequant。
比较使用 GGUF transpose后的 shape。

## Observations

| Tensor | Count | MAE | Max abs diff | Cosine | Pearson |
| --- | ---: | ---: | ---: | ---: | ---: |
| `attn_qkv` | 16,777,216 | 0.0177567 | 0.2934704 | 0.000224 | 0.000224 |
| `attn_gate` | 8,388,608 | 0.0177558 | 0.3343945 | 0.000156 | 0.000156 |
| `ssm_out` | 8,388,608 | 0.0169305 | 0.6274338 | 0.000093 | 0.000092 |

两个值分布的 sorted magnitude有一定相似性，但 positional row/column norm
correlation接近零：

```text
transpose row-norm Pearson       ≈ -0.011 / -0.008 / -0.000
transpose column-norm Pearson    ≈  0.024 /  0.025 / -0.009
sorted row-norm Pearson          ≈  0.875 /  0.982 /  0.660
sorted column-norm Pearson       ≈  0.796 /  0.967 /  0.720
```

这说明当前 mapping不能建立 elementwise correspondence。可能是 GGUF fused
group order、MLX projection grouping、transpose/packing约定不同，也可能是
artifact source本身不同。不能将其解释为 quantizer drift。

## Artifacts

```text
simigo2-experimental/scripts/cyber_tiel_quantized_drift_pilot.py
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-quantized-drift-pilot-layer1.json
```

## Boundary

结果限定 layer1、three tensors、GGUF Q8_0 full dequant、MLX affine full dequant、
canonical LLAMA/MLX artifacts和本机。不建立 quantizer drift、same checkpoint、
dequantization equivalence或 full tensor mapping。

## Non-claims

```text
❌ quantizer drift已证明
❌ tensor element mapping已证明
❌ same checkpoint bytes
❌ dequantization equivalence
❌ MTP机制已解释
```

## Next

1. 用共同上游 HF/Ornith/Huihui source tensors推导 canonical conversion mapping。
2. 对 Q/K/V grouping、transpose、packing和 row permutation做 assignment audit。
3. 只有 mapping resolved后才能重开 large-matrix dequantized drift attribution。
