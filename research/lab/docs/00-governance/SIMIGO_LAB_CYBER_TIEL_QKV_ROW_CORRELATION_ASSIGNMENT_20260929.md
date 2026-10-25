# SimiGo Lab Cyber-Tiel QKV Row Correlation Assignment — 2026-09-29

## Result

```text
QKV_ROW_CORRELATION_ASSIGNMENT = PASS_WITH_BOUNDARY / LAYOUT_MAPPING_NOT_ESTABLISHED
SEGMENTS = Q2048 / K2048 / V4096
ROW_COUNT = 2048 PER SEGMENT
BEST_MATCHED_PEARSON_MAX = 0.1159309
ROWS_AT_LEAST_050 = 0 / 6144
ROWS_AT_LEAST_070 = 0 / 6144
ROWS_AT_LEAST_090 = 0 / 6144
```

登记：

```text
CYBER_TIEL_QKV_FULL_ROW_CORRELATION_ASSIGNMENT_PASS
BEST_ROW_CORRELATION_BELOW_012
NO_QKV_ROW_AT_LEAST_050
LAYOUT_MAPPING_NOT_ESTABLISHED
```

## Upgrade over norm-only audit

前一轮 Hungarian assignment只使用 row L2 norms。本轮对每个 Q/K/V segment内的
完整 row vectors做 center + L2 normalization，再计算 GGUF row ↔ MLX row 的
Pearson correlation matrix，并用 Hungarian assignment最大化 total matched
Pearson。

这能回答更强的问题：即使允许任意 row permutation，GGUF和 MLX的 Q/K/V row
vectors是否存在一一对应？

## Protocol

```text
GGUF Q8_0 dequant = blk.1.attn_qkv.weight [2048,8192]
MLX dequant       = linear_attn.in_proj_qkv → transpose [2048,8192]
segments          = Q [0:2048], K [2048:4096], V [4096:8192]
row metric        = centered row Pearson
assignment        = Hungarian maximize total Pearson
```

## Checks

| Check | Result |
| --- | --- |
| `ALL_HUNGARIAN_ASSIGNMENTS_COMPLETE` | PASS |
| `ALL_QKV_FEATURES_COVERED` | PASS |
| `QKV_SEGMENT_COUNT` | PASS |

## Results

| Segment | Rows | Features | Matched Pearson mean | Median | Max | ≥0.50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Q2048 | 2048 | 2048 | 0.0712224 | 0.0719736 | 0.1159309 | 0 |
| K2048 | 2048 | 2048 | 0.0714073 | 0.0721167 | 0.1098251 | 0 |
| V4096 | 2048 | 4096 | 0.0512549 | 0.0511149 | 0.0785623 | 0 |

Identity Pearson means也接近零：

```text
Q = 0.0005117
K = 0.0004184
V = -0.0000780
```

## Interpretation

1. 即使允许任意 row permutation，最佳 matched Pearson最大也只有 `0.1159309`。
2. `6144`个 Q/K/V rows中没有任何 row达到 `0.50`。
3. 因此 QKV layout unresolved不是 norm-only metric太弱；full row vectors本身
  不存在一一对应。
4. 该结果强化了 boundary：named-source profile不能升级为 same-checkpoint
   closure，也不能解释为 quantization-equivalent payload。

可能解释包括不同 source checkpoint、GGUF conversion的 projection grouping/order、
quantization transformation，或这些因素的组合。当前证据不足以归因。

## Artifact

```text
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-qkv-row-correlation-assignment.json
```

实现：

```text
simigo2-experimental/scripts/cyber_tiel_qkv_row_correlation_assignment.py
```

## Boundary

结果限定 layer1 `attn_qkv`、GGUF Q8_0、MLX 4-bit/group64 dequant、 hypothesized
Q2048/K2048/V4096 segmentation、full row Pearson Hungarian assignment和本机
artifacts。不建立 same-checkpoint closure、quantizer equivalence、full QKV layout
或 MTP mechanism。

## Non-claims

```text
❌ full QKV layout已解析
❌ quantizer drift已归因
❌ same checkpoint bytes
❌ Q/K/V row permutation已完全还原
❌ 上游 source artifact已验证
```

## Next

1. 用共同上游 HF source tensors推导 canonical conversion mapping。
2. 若无上游 tensors，则将 QKV mapping列为 permanently blocked，而非继续用
   quantized artifact强行对齐。
3. Named-source profile V1继续限定为 fixed-trajectory output behavior gate。
