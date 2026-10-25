# SimiGo Lab Cyber-Tiel F32 Control Drift Audit — 2026-09-29

## Result

```text
F32_CONTROL_AUDIT = PASS_WITH_OBSERVED_DRIFT
TENSORS = 260
EXACT TENSORS = 30 / 260
ZERO_DRIFT = FALSE
MAX_ABS_DIFF = 101.82308959960938
MEAN_TENSOR_MEAN_ABS_DIFF = 0.644830577143153
```

登记：

```text
CYBER_TIEL_F32_CONTROL_TENSOR_AUDIT_PASS
NAMED_SOURCE_CHECKPOINT_NUMERICAL_DRIFT_OBSERVED
SAME_CHECKPOINT_IDENTITY_EFFECTIVELY_REJECTED_FOR_CONTROL_TENSORS
```

## Scope

只比较两侧都未经过大矩阵 quantization 的 control/normalization tensors：

```text
GGUF F32
MLX BF16
```

覆盖 40层中的 shared control tensors：

```text
all layers:
attn_norm.weight
post_attention_norm.weight
ffn_gate_inp.weight

linear-attention layers (30):
ssm_a ↔ A_log
ssm_conv1d.weight ↔ conv1d.weight
ssm_dt.bias ↔ dt_bias
ssm_norm.weight ↔ norm.weight

full-attention layers (10):
attn_q_norm.weight ↔ q_norm.weight
attn_k_norm.weight ↔ k_norm.weight
```

计数：

```text
all-layer tensors  = 40 × 3 = 120
linear-only tensors = 30 × 4 = 120
full-only tensors   = 10 × 2 = 20
total              = 260
```

GGUF `ffn_gate_inp.weight`转置后与 MLX `mlp.gate.weight`比较。GGUF
`ssm_conv1d.weight`按 conv layout auto-orientation比较。其余一维/同shape tensors
直接比较。

## Aggregate

```text
exact tensors              = 30 / 260
zero-drift tensors         = 0 / 260
max absolute difference    = 101.82308959960938
mean of meanAbsDiff        = 0.644830577143153
```

## Per-family drift

| Family | n | Zero tensors | Max abs diff | Median max abs diff |
| --- | ---: | ---: | ---: | ---: |
| attn_norm.weight | 40 | 0 | 0.0078125 | 0.00390625 |
| post_attention_norm.weight | 40 | 0 | 0.0078125 | 0.00390625 |
| ffn_gate_inp.weight | 40 | 0 | 0.51953125 | 0.351501 |
| ssm_a ↔ A_log | 30 | 0 | 101.82309 | 13.526779 |
| ssm_conv1d.weight | 30 | 0 | 2.544586 | 0.932098 |
| ssm_dt.bias | 30 | 0 | 18.40625 | 7.074219 |
| ssm_norm.weight | 30 | 30 | 0 | 0 |
| attn_q_norm.weight | 10 | 0 | 0.0078125 | 0.0078125 |
| attn_k_norm.weight | 10 | 0 | 0.0078125 | 0.0078125 |

`sml_norm.weight`是唯一 exact family。`ssm_a`、`ssm_dt.bias`显示大 drift。
这些差异不能归因于大矩阵 quantization，因为所选 tensors在 GGUF侧为 F32。

## Interpretation

1. GGUF/MLX artifacts共享 tokenizer substrate和 text tensor topology。
2. 但 control tensors存在 finite numerical drift；因此不能将两者视为
   same checkpoint或 dequantization-equivalent payload。
3. 大 drift集中在线性-attention control path，特别是 `ssm_a` 和 `ssm_dt.bias`。
4. 小 normalization drift与 BF16 rounding量级接近；但 `ssm_*` 大 drift需要进一步
   source/abliteration/quantization lineage分析。

## Implementation correction

初版 GGUF reader把 tensor offset当作 absolute file offset，导致随机噪声。已修正为：
先解析完整 GGUF tensor-info list，再按 32-byte alignment计算 tensor data section
起点，最后使用 relative offset。

## Validation

```text
protocol checks = 3/3 PASS
Python syntax    = PASS
all records finite = true
no failures       = true
```

## Artifacts

```text
simigo2-experimental/scripts/cyber_tiel_f32_control_tensor_audit.py
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-f32-control-audit.json
```

## Boundary

结果限定 named-source CyberTiel GGUF/MLX pair、当前 local snapshots、260个
F32-control tensors和本机 audit。不比较 large quantized matrices、vision tensors
或 nextn tensors。不建立 quantization equivalence，也不定位 drift的上游来源
（abliteration、conversion、quantizer或 metadata transformation）。

## Non-claims

```text
❌ same checkpoint
❌ dequantization-equivalent payload
❌ large quantized matrix equality
❌ drift root cause已定位
❌ profile V1失效
```

Named-source profile V1本来不假设 same checkpoint；本结果是该边界的直接数值证据。

## Next

1. 比较 large quantized matrices dequantized后的 sampled drift。
2. 若可能，获取共同上游 Huihui/Ornith source tensors，分离 abliteration与
   quantization drift。
3. 将 named-source profile的 boundary从隐含假设升级为显式 numerical-drift
   evidence link。
