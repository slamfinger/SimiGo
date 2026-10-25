# SimiGo Lab Cyber-Tiel QKV Segment Layout Diagnostic — 2026-09-29

## Result

```text
QKV_SEGMENT_DIAGNOSTIC = PASS_WITH_BOUNDARY / LAYOUT_UNRESOLVED
BEST_SEGMENT_ORDER = K2048 → Q2048 → V4096
BEST_SUMMED_BLOCK_NORM_PEARSON = 0.6063845
NATURAL_QKV_ORDER_SUMMED_PEARSON = 0.6049992
BEST_ROW_ASSIGNMENT_MAX_PEARSON = 0.1159309
ROW_ASSIGNMENTS_AT_LEAST_050 = 0 / 6
```

登记：

```text
CYBER_TIEL_QKV_SEGMENT_DIAGNOSTIC_PASS
BEST_SEGMENT_ORDER_SUGGESTIVE_BUT_ROW_MAPPING_ABSENT
LAYOUT_UNRESOLVED
```

## Scope

只诊断 layer1 `attn_qkv` fused tensor：

```text
GGUF Q8_0  = blk.1.attn_qkv.weight [2048,8192]
MLX 4-bit  = linear_attn.in_proj_qkv, dequant [8192,2048]
comparison = GGUF ↔ MLX transpose
```

假设 segment划分：

```text
Q = 2048
K = 2048
V = 4096
```

这是 layout diagnostic；不比较 weight bytes equivalence，不声称 quantizer drift。

## Block norm correlations

| GGUF segment | MLX segment | Pearson |
| --- | --- | ---: |
| Q2048 | Q2048 | -0.0107489 |
| Q2048 | K2048 | 0.0014684 |
| Q2048 | V4096 | 0.0058131 |
| K2048 | Q2048 | 0.0076930 |
| K2048 | K2048 | -0.0016967 |
| K2048 | V4096 | 0.0102894 |
| V4096 | Q2048 | -0.0081472 |
| V4096 | K2048 | -0.0119375 |
| V4096 | V4096 | -0.0177119 |

## Segment permutations

| Rank | MLX order | Summed block-norm Pearson |
| ---: | --- | ---: |
| 1 | K2048 → Q2048 → V4096 | 0.6063845 |
| 2 | Q2048 → K2048 → V4096 | 0.6049992 |
| 3 | Q2048 → V4096 → K2048 | -0.2324637 |
| 4 | V4096 → Q2048 → K2048 | -0.2336506 |
| 5 | K2048 → V4096 → Q2048 | -0.3740516 |
| 6 | V4096 → K2048 → Q2048 | -0.3766238 |

最佳 `(K,Q,V)`与自然 `(Q,K,V)`的差仅：

```text
0.6063845 - 0.6049992 = 0.0013853
```

不足以决定 segment order。

## Row assignment

对同长度 segment pairs计算每个 GGUF row到 MLX rows的最佳 Pearson：

| GGUF segment | MLX segment | Rows | Best Pearson mean | Best Pearson max | ≥0.50 |
| --- | --- | ---: | ---: | ---: | ---: |
| Q2048 | Q2048 | 2048 | 0.0736434 | 0.1159309 | 0 |
| Q2048 | K2048 | 2048 | 0.0736063 | 0.1098654 | 0 |
| K2048 | Q2048 | 2048 | 0.0739031 | 0.1087307 | 0 |
| K2048 | K2048 | 2048 | 0.0740197 | 0.1098251 | 0 |
| V4096 | V4096 | 2048* | 0.0531644 | 0.0785623 | 0 |

`*`表示 V4096 GGUF segment采样为 2048 rows以做同shape correlation。所有 row assignment
best correlations都低于 `0.12`，因此没有可用 row mapping。

## Interpretation

1. `(K,Q,V)`的 block-norm ordering略高于自然 `(Q,K,V)`，但差距太小，不能确定
   fused order。
2. row-level best correlation普遍低于 `0.12`，说明 transpose mapping未能建立。
3. 该 diagnostic不支持把 GGUF/MLX elementwise difference归因为 quantizer drift。
4. large quantized tensor attribution继续 BLOCKED。

## Artifact

```text
simigo2-experimental/scripts/cyber_tiel_qkv_segment_diagnostic.py
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-qkv-segment-diagnostic.json
```

## Boundary

结果限定 layer1 `attn_qkv`、假设的 2048/2048/4096 segment划分、GGUF Q8_0、
MLX 4-bit group64 dequant和本机 artifacts。不建立 same-checkpoint closure、
quantizer equivalence、full QKV layout或 MTP mechanism。

## Non-claims

```text
❌ segment order已确定
❌ Q/K/V row mapping已确定
❌ quantizer drift已证明
❌ same checkpoint
❌ MTP root cause已定位
```
